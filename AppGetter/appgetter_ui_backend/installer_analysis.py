"""Installer analysis and silent-switch discovery helpers."""

from __future__ import annotations

from dataclasses import dataclass, asdict
from hashlib import sha256
from pathlib import Path
from typing import Any
from urllib.parse import urlparse
from urllib.request import urlopen
import platform
import re
import subprocess
import zipfile


KNOWN_SWITCHES_BY_TYPE: dict[str, list[str]] = {
    "msi": ["/qn", "/quiet", "/norestart"],
    "msix": ["Add-AppxPackage -Path <file>"],
    "appx": ["Add-AppxPackage -Path <file>"],
    "exe": ["/S", "/silent", "/verysilent", "/quiet"],
}

ENGINE_SWITCH_RESEARCH_DB: dict[str, list[str]] = {
    "Inno Setup": ["/VERYSILENT", "/SILENT", "/SUPPRESSMSGBOXES", "/NORESTART"],
    "NSIS": ["/S"],
    "InstallShield": ["/s", "/v/qn", "/v/REBOOT=ReallySuppress"],
    "WiX Burn": ["/quiet", "/passive", "/norestart"],
    "Advanced Installer": ["/quiet", "/passive", "/norestart"],
    "Squirrel": ["--silent", "--silentInstall"],
}

ENGINE_SIGNATURES: dict[str, tuple[bytes, ...]] = {
    "Inno Setup": (b"Inno Setup", b"innosetup"),
    "NSIS": (b"Nullsoft", b"NSIS", b"Nullsoft Install System"),
    "InstallShield": (b"InstallShield", b"setup.inx"),
    "WiX Burn": (b"WixBundle", b"BurnStub"),
    "Advanced Installer": (b"Advanced Installer", b"AI_UNINSTALLER"),
    "Squirrel": (b"Squirrel", b"--squirrel-firstrun"),
}


@dataclass
class InstallerAnalysis:
    installer_path: str
    file_name: str
    file_size_bytes: int
    sha256: str
    installer_type: str
    installer_engine: str | None


@dataclass
class SilentSwitchDiscovery:
    installer_path: str
    installer_type: str
    installer_engine: str | None
    switches: list[str]
    source: str
    confidence: str
    notes: list[str]
    runtime_probe: dict[str, Any] | None = None


def ensure_download_location(path: str) -> Path:
    download_dir = Path(path).expanduser().resolve()
    download_dir.mkdir(parents=True, exist_ok=True)
    return download_dir


def _clean_filename_from_url(download_url: str) -> str:
    parsed = urlparse(download_url)
    name = Path(parsed.path).name
    if not name:
        return "downloaded_installer.bin"
    return re.sub(r"[^a-zA-Z0-9._-]", "_", name)


def download_installer(download_url: str, download_location: str) -> Path:
    target_dir = ensure_download_location(download_location)
    filename = _clean_filename_from_url(download_url)
    target_path = target_dir / filename

    with urlopen(download_url) as response:
        content = response.read()
    target_path.write_bytes(content)
    return target_path


def _sha256(path: Path) -> str:
    digest = sha256()
    with path.open("rb") as infile:
        while True:
            chunk = infile.read(1024 * 1024)
            if not chunk:
                break
            digest.update(chunk)
    return digest.hexdigest()


def detect_installer_type(installer_path: Path) -> str:
    suffix = installer_path.suffix.lower()
    if suffix in {".msi", ".msix", ".appx", ".exe"}:
        return suffix.lstrip(".")

    if suffix in {".zip", ".appxbundle", ".msixbundle"}:
        return "archive"

    try:
        with installer_path.open("rb") as infile:
            header = infile.read(16)
        if header.startswith(b"MZ"):
            return "exe"
        if header.startswith(b"\xD0\xCF\x11\xE0"):
            return "msi"
    except OSError:
        return "unknown"

    try:
        with zipfile.ZipFile(installer_path, "r") as archive:
            names = {name.lower() for name in archive.namelist()}
            if "appxmanifest.xml" in names:
                return "appx"
            if any(name.endswith(".msix") for name in names):
                return "msix"
    except zipfile.BadZipFile:
        pass

    return "unknown"


def detect_installer_engine(installer_path: Path) -> str | None:
    try:
        with installer_path.open("rb") as infile:
            blob = infile.read(5 * 1024 * 1024)
    except OSError:
        return None

    lowered_blob = blob.lower()
    for engine, signatures in ENGINE_SIGNATURES.items():
        if any(signature.lower() in lowered_blob for signature in signatures):
            return engine
    return None


def _extract_potential_switches_from_text(text: str) -> list[str]:
    candidates: set[str] = set()
    switch_pattern = re.compile(
        r"(?i)(/[a-z][a-z0-9-]*|--[a-z][a-z0-9-]*|-{1}[a-z]{1,3})"
    )
    strong_hints = {"s", "silent", "verysilent", "quiet", "qn", "qb", "passive", "norestart"}
    for token in switch_pattern.findall(text):
        normalized = token.lstrip("-/").lower()
        if normalized in strong_hints or any(
            hint in normalized for hint in ("silent", "quiet", "passive", "norestart")
        ):
            candidates.add(token)
    return sorted(candidates)


def _research_switches(installer_path: Path, installer_type: str, engine: str | None) -> list[str]:
    if engine and engine in ENGINE_SWITCH_RESEARCH_DB:
        return ENGINE_SWITCH_RESEARCH_DB[engine]

    try:
        text = installer_path.read_text(errors="ignore")
    except OSError:
        return []

    switches = _extract_potential_switches_from_text(text)
    if switches:
        return switches

    return KNOWN_SWITCHES_BY_TYPE.get(installer_type, [])


def _runtime_probe_for_switches(installer_path: Path) -> dict[str, Any]:
    if platform.system() != "Windows":
        return {
            "status": "skipped",
            "reason": "Runtime switch probing requires Windows to execute installers safely.",
        }

    if installer_path.suffix.lower() != ".exe":
        return {
            "status": "skipped",
            "reason": "Runtime probing is only performed for .exe installers.",
        }

    probe_flags = ["/?", "-?", "/help", "--help", "-help"]
    discovered: set[str] = set()
    command_results: list[dict[str, Any]] = []

    for flag in probe_flags:
        command = [str(installer_path), flag]
        try:
            completed = subprocess.run(
                command,
                capture_output=True,
                text=True,
                timeout=8,
                check=False,
            )
            output = (completed.stdout or "") + "\n" + (completed.stderr or "")
            parsed = _extract_potential_switches_from_text(output)
            discovered.update(parsed)
            command_results.append(
                {
                    "flag": flag,
                    "exit_code": completed.returncode,
                    "switches_found": parsed,
                }
            )
        except subprocess.TimeoutExpired:
            command_results.append(
                {
                    "flag": flag,
                    "exit_code": None,
                    "switches_found": [],
                    "note": "timeout",
                }
            )

    return {
        "status": "completed",
        "commands": command_results,
        "switches_found": sorted(discovered),
    }


class InstallerInspector:
    """Performs installer identification and silent-switch discovery."""

    def analyze(self, installer_path: str) -> dict[str, Any]:
        path = Path(installer_path).expanduser().resolve()
        if not path.exists():
            raise FileNotFoundError(f"Installer not found: {path}")

        installer_type = detect_installer_type(path)
        engine = detect_installer_engine(path) if installer_type == "exe" else None
        analysis = InstallerAnalysis(
            installer_path=str(path),
            file_name=path.name,
            file_size_bytes=path.stat().st_size,
            sha256=_sha256(path),
            installer_type=installer_type,
            installer_engine=engine,
        )
        return asdict(analysis)

    def discover_silent_switches(
        self,
        installer_path: str,
        *,
        try_runtime_tests: bool = False,
    ) -> dict[str, Any]:
        path = Path(installer_path).expanduser().resolve()
        analysis = self.analyze(str(path))
        installer_type = analysis["installer_type"]
        installer_engine = analysis["installer_engine"]

        known_switches = []
        if installer_engine and installer_engine in ENGINE_SWITCH_RESEARCH_DB:
            known_switches = ENGINE_SWITCH_RESEARCH_DB[installer_engine]
            source = "research-db"
            confidence = "high"
            notes = [f"Matched installer engine signature: {installer_engine}."]
        else:
            known_switches = KNOWN_SWITCHES_BY_TYPE.get(installer_type, [])
            source = "known-by-installer-type"
            confidence = "medium" if known_switches else "low"
            notes = []
            if known_switches:
                notes.append(
                    f"Using fallback known switches for installer type '{installer_type}'."
                )

        if not known_switches:
            researched = _research_switches(path, installer_type, installer_engine)
            if researched:
                known_switches = researched
                source = "researched-from-installer-content"
                confidence = "medium"
                notes.append("Recovered candidate switches from installer metadata/text.")

        runtime_probe: dict[str, Any] | None = None
        if try_runtime_tests:
            runtime_probe = _runtime_probe_for_switches(path)
            if runtime_probe.get("status") == "completed":
                runtime_switches = runtime_probe.get("switches_found") or []
                if runtime_switches:
                    known_switches = sorted(set(known_switches + runtime_switches))
                    source = "runtime-probe"
                    confidence = "high"
                    notes.append("Runtime help-output probing returned additional switches.")
            else:
                notes.append(runtime_probe.get("reason", "Runtime probe skipped."))

        if not known_switches:
            notes.append(
                "No silent switches were identified. Manual validation in a sandbox is recommended."
            )

        discovery = SilentSwitchDiscovery(
            installer_path=str(path),
            installer_type=installer_type,
            installer_engine=installer_engine,
            switches=sorted(set(known_switches)),
            source=source,
            confidence=confidence,
            notes=notes,
            runtime_probe=runtime_probe,
        )
        return {
            "analysis": analysis,
            "discovery": asdict(discovery),
        }

