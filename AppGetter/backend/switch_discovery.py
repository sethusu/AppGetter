from __future__ import annotations

import platform
import re
import subprocess
import urllib.error
import urllib.request
from pathlib import Path
from typing import Any


KNOWN_SWITCHES_BY_EXTENSION: dict[str, list[str]] = {
    ".msi": ["/quiet", "/qn", "/norestart"],
    ".msix": ["Add-AppxPackage -Path <installer>"],
    ".appx": ["Add-AppxPackage -Path <installer>"],
}

EXE_FAMILY_SIGNATURES: dict[str, dict[str, Any]] = {
    "inno setup": {
        "tokens": ["/VERYSILENT", "/SUPPRESSMSGBOXES", "/NORESTART"],
        "reason": "Detected Inno Setup bootstrap markers in the installer binary.",
    },
    "nullsoft install system": {
        "tokens": ["/S"],
        "reason": "Detected NSIS bootstrap markers in the installer binary.",
    },
    "installshield": {
        "tokens": ["/s", "/v\"/qn\""],
        "reason": "Detected InstallShield bootstrap markers in the installer binary.",
    },
    "wix toolset": {
        "tokens": ["/quiet", "/passive", "/norestart"],
        "reason": "Detected WiX bootstrap markers in the installer binary.",
    },
}

COMMON_SWITCH_REGEX = re.compile(
    r"(?:^|[\s\"'])("
    r"/VERYSILENT|/SILENT|/SUPPRESSMSGBOXES|/NORESTART|/S\b|/Q\b|/QN\b|/QB\b|/quiet\b|/passive\b|"
    r"--silent\b|--quiet\b|--help\b|/help\b|/\?\b|-h\b|-q\b|-s\b"
    r")(?=$|[\s\"'])",
    re.IGNORECASE,
)


def _dedupe_preserve_order(values: list[str]) -> list[str]:
    seen: set[str] = set()
    deduped: list[str] = []
    for value in values:
        normalized = value.strip()
        if not normalized:
            continue
        key = normalized.lower()
        if key not in seen:
            deduped.append(normalized)
            seen.add(key)
    return deduped


def _extract_ascii_strings(content: bytes, minimum_length: int = 4) -> list[str]:
    pattern = rb"[ -~]{" + str(minimum_length).encode("ascii") + rb",}"
    return [match.decode("latin-1", errors="ignore") for match in re.findall(pattern, content)]


def _extract_utf16le_strings(content: bytes, minimum_chars: int = 4) -> list[str]:
    pattern = rb"(?:(?:[ -~]\x00){" + str(minimum_chars).encode("ascii") + rb",})"
    results: list[str] = []
    for match in re.findall(pattern, content):
        try:
            results.append(match.decode("utf-16le", errors="ignore"))
        except UnicodeDecodeError:
            continue
    return results


def extract_binary_strings(installer_path: Path, max_bytes: int = 8 * 1024 * 1024) -> list[str]:
    with installer_path.open("rb") as installer_stream:
        content = installer_stream.read(max_bytes)
    strings = _extract_ascii_strings(content) + _extract_utf16le_strings(content)
    return _dedupe_preserve_order(strings)


def extract_switch_tokens(text: str) -> list[str]:
    matches = [match.group(1).strip() for match in COMMON_SWITCH_REGEX.finditer(text)]
    return _dedupe_preserve_order(matches)


def detect_known_exe_family(binary_strings: list[str]) -> dict[str, Any]:
    all_text = " ".join(binary_strings).lower()
    for signature, data in EXE_FAMILY_SIGNATURES.items():
        if signature in all_text:
            return {
                "family": signature,
                "switches": data["tokens"],
                "reason": data["reason"],
            }
    return {}


def _html_to_text(content: str) -> str:
    collapsed = re.sub(r"<[^>]+>", " ", content)
    return re.sub(r"\s+", " ", collapsed)


def research_switches_from_urls(urls: list[str]) -> dict[str, Any]:
    findings: list[dict[str, Any]] = []
    discovered_switches: list[str] = []

    for url in urls:
        if not url:
            continue
        try:
            req = urllib.request.Request(
                url,
                headers={"User-Agent": "AppGetter-Switch-Discovery/1.0"},
            )
            with urllib.request.urlopen(req, timeout=8) as response:
                body = response.read().decode("utf-8", errors="ignore")
            text = _html_to_text(body)
            switches = extract_switch_tokens(text)
            if switches:
                findings.append(
                    {
                        "url": url,
                        "switches": switches,
                        "summary": "Found potential silent switches in documentation content.",
                    }
                )
                discovered_switches.extend(switches)
        except (urllib.error.URLError, TimeoutError, ValueError):
            findings.append(
                {
                    "url": url,
                    "switches": [],
                    "summary": "Unable to fetch or parse this page.",
                }
            )

    return {
        "switches": _dedupe_preserve_order(discovered_switches),
        "findings": findings,
    }


def probe_installer_help_output(installer_path: Path) -> dict[str, Any]:
    if platform.system().lower() != "windows":
        return {
            "supported": False,
            "reason": "Installer probing is only supported on Windows hosts.",
            "switches": [],
            "attempts": [],
        }

    probe_flags = ["/?", "-?", "/h", "--help", "/help"]
    attempts: list[dict[str, Any]] = []
    discovered: list[str] = []

    for flag in probe_flags:
        command = [str(installer_path), flag]
        try:
            result = subprocess.run(
                command,
                capture_output=True,
                text=True,
                timeout=12,
                check=False,
            )
            output = f"{result.stdout}\n{result.stderr}".strip()
            switches = extract_switch_tokens(output)
            discovered.extend(switches)
            attempts.append(
                {
                    "flag": flag,
                    "returnCode": result.returncode,
                    "switches": switches,
                }
            )
            if switches:
                break
        except (OSError, subprocess.TimeoutExpired) as exc:
            attempts.append(
                {
                    "flag": flag,
                    "returnCode": None,
                    "switches": [],
                    "error": str(exc),
                }
            )

    return {
        "supported": True,
        "switches": _dedupe_preserve_order(discovered),
        "attempts": attempts,
    }


def build_recommended_install_command(file_name: str, extension: str, switches: list[str]) -> str:
    if extension == ".msi":
        return f'msiexec /i "{file_name}" /quiet /norestart'
    if extension in {".msix", ".appx"}:
        return f'Add-AppxPackage -Path "{file_name}"'

    if not switches:
        return f'"{file_name}" <silent_switch_here>'

    return f'"{file_name}" {switches[0]}'


def analyze_installer(
    installer_path: Path,
    app_name: str | None = None,
    research_urls: list[str] | None = None,
    allow_runtime_probe: bool = False,
) -> dict[str, Any]:
    path = installer_path.resolve()
    if not path.exists():
        raise FileNotFoundError(f"Installer file not found: {path}")

    extension = path.suffix.lower()
    known_switches = KNOWN_SWITCHES_BY_EXTENSION.get(extension, [])
    discovered_switches: list[str] = []
    methods_used: list[str] = []
    insights: list[str] = []
    research_result: dict[str, Any] = {"switches": [], "findings": []}
    probe_result: dict[str, Any] = {
        "supported": False,
        "reason": "Runtime probing was not requested.",
        "switches": [],
        "attempts": [],
    }

    binary_strings: list[str] = []
    exe_family_result: dict[str, Any] = {}

    if extension == ".exe":
        binary_strings = extract_binary_strings(path)
        methods_used.append("binary-static-analysis")

        exe_family_result = detect_known_exe_family(binary_strings)
        if exe_family_result:
            known_switches.extend(exe_family_result["switches"])
            insights.append(exe_family_result["reason"])

        discovered_switches.extend(extract_switch_tokens(" ".join(binary_strings)))

    if research_urls:
        methods_used.append("documentation-research")
        research_result = research_switches_from_urls(research_urls)
        discovered_switches.extend(research_result["switches"])

    if allow_runtime_probe and extension == ".exe":
        methods_used.append("runtime-probe")
        probe_result = probe_installer_help_output(path)
        discovered_switches.extend(probe_result["switches"])

    known_switches = _dedupe_preserve_order(known_switches)
    discovered_switches = _dedupe_preserve_order(discovered_switches)

    all_switches = _dedupe_preserve_order(known_switches + discovered_switches)
    is_known = len(known_switches) > 0
    was_discovered = (not is_known) and len(discovered_switches) > 0

    if is_known:
        status = "known"
    elif was_discovered:
        status = "discovered"
    else:
        status = "missing"

    recommendation = build_recommended_install_command(path.name, extension, all_switches)

    return {
        "appName": app_name or "",
        "installerFileName": path.name,
        "installerPath": str(path),
        "extension": extension,
        "status": status,
        "knownSwitches": known_switches,
        "discoveredSwitches": discovered_switches,
        "recommendedSwitches": all_switches,
        "recommendedInstallCommand": recommendation,
        "methodsUsed": methods_used,
        "insights": insights,
        "research": research_result,
        "runtimeProbe": probe_result,
        "nextSteps": (
            []
            if status != "missing"
            else [
                "No silent switches could be identified automatically.",
                "Run installer in a disposable VM and capture full help output.",
                "Check vendor enterprise deployment docs for exact silent flags.",
            ]
        ),
    }
