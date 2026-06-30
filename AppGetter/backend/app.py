from __future__ import annotations

import json
import os
import shutil
import subprocess
import uuid
from datetime import datetime, timezone
from pathlib import Path
from typing import Any
from urllib.parse import urlparse
from urllib.request import Request, urlopen

from flask import Flask, jsonify, request, send_from_directory
from werkzeug.utils import secure_filename

try:
    from backend.switch_discovery import analyze_installer
except ModuleNotFoundError:
    from switch_discovery import analyze_installer


REPO_ROOT = Path(__file__).resolve().parent.parent
DATA_DIR = REPO_ROOT / "app_data"
UPLOADS_DIR = DATA_DIR / "uploads"
FALLBACK_DOWNLOADS_DIR = DATA_DIR / "downloads"
INSTALLER_INDEX_PATH = DATA_DIR / "installers.json"
CONFIG_PATH = DATA_DIR / "config.json"
UI_DIR = REPO_ROOT / "ui"
POWERSHELL_SCRIPT = REPO_ROOT / "Create-IntuneWinFromWeb.ps1"

DEFAULT_DOWNLOAD_LOCATION = r"D:\Intoon In Progress"


def utc_timestamp() -> str:
    return datetime.now(timezone.utc).isoformat()


def ensure_directories() -> None:
    DATA_DIR.mkdir(parents=True, exist_ok=True)
    UPLOADS_DIR.mkdir(parents=True, exist_ok=True)
    FALLBACK_DOWNLOADS_DIR.mkdir(parents=True, exist_ok=True)


def load_json(path: Path, default: Any) -> Any:
    if not path.exists():
        return default
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError:
        return default


def save_json(path: Path, payload: Any) -> None:
    path.write_text(json.dumps(payload, indent=2), encoding="utf-8")


def load_config() -> dict[str, Any]:
    config = load_json(CONFIG_PATH, {"downloadLocation": DEFAULT_DOWNLOAD_LOCATION})
    if "downloadLocation" not in config:
        config["downloadLocation"] = DEFAULT_DOWNLOAD_LOCATION
    return config


def save_config(config: dict[str, Any]) -> None:
    save_json(CONFIG_PATH, config)


def load_installer_index() -> dict[str, Any]:
    return load_json(INSTALLER_INDEX_PATH, {"installers": {}})


def save_installer_index(index: dict[str, Any]) -> None:
    save_json(INSTALLER_INDEX_PATH, index)


def register_installer(record: dict[str, Any]) -> dict[str, Any]:
    index = load_installer_index()
    index["installers"][record["id"]] = record
    save_installer_index(index)
    return record


def get_installer_record(installer_id: str) -> dict[str, Any] | None:
    index = load_installer_index()
    return index.get("installers", {}).get(installer_id)


def to_public_installer_record(record: dict[str, Any]) -> dict[str, Any]:
    return {
        "id": record["id"],
        "source": record["source"],
        "originalName": record["originalName"],
        "storedName": record["storedName"],
        "sourceUrl": record.get("sourceUrl"),
        "createdAt": record["createdAt"],
    }


def resolve_download_directory(configured_path: str) -> tuple[Path, str]:
    configured = Path(configured_path)
    try:
        configured.mkdir(parents=True, exist_ok=True)
        return configured, "configured"
    except OSError:
        FALLBACK_DOWNLOADS_DIR.mkdir(parents=True, exist_ok=True)
        return FALLBACK_DOWNLOADS_DIR, "fallback"


def save_uploaded_file(file_storage: Any) -> dict[str, Any]:
    original_name = secure_filename(file_storage.filename or "")
    if not original_name:
        raise ValueError("A file name is required.")

    installer_id = uuid.uuid4().hex
    stored_name = f"{installer_id}_{original_name}"
    destination = UPLOADS_DIR / stored_name
    file_storage.save(destination)

    return register_installer(
        {
            "id": installer_id,
            "source": "upload",
            "originalName": original_name,
            "storedName": stored_name,
            "path": str(destination.resolve()),
            "createdAt": utc_timestamp(),
        }
    )


def download_installer_file(url: str, configured_location: str) -> tuple[dict[str, Any], str]:
    parsed = urlparse(url)
    file_name = os.path.basename(parsed.path) or "installer.bin"
    safe_name = secure_filename(file_name) or "installer.bin"

    download_dir, mode = resolve_download_directory(configured_location)
    installer_id = uuid.uuid4().hex
    stored_name = f"{installer_id}_{safe_name}"
    destination = download_dir / stored_name

    request_obj = Request(url, headers={"User-Agent": "AppGetter-Backend/1.0"})
    with urlopen(request_obj, timeout=30) as response, destination.open("wb") as output_stream:
        shutil.copyfileobj(response, output_stream)

    record = register_installer(
        {
            "id": installer_id,
            "source": "download",
            "originalName": safe_name,
            "storedName": stored_name,
            "sourceUrl": url,
            "path": str(destination.resolve()),
            "createdAt": utc_timestamp(),
        }
    )
    return record, mode


def pick_powershell_executable() -> str | None:
    if os.name == "nt":
        return "powershell.exe"
    if shutil.which("pwsh"):
        return "pwsh"
    if shutil.which("powershell"):
        return "powershell"
    return None


def run_packaging_script(payload: dict[str, Any], output_path: str) -> dict[str, Any]:
    executable = pick_powershell_executable()
    if not executable:
        return {
            "ok": False,
            "error": "PowerShell is not available on this host.",
            "command": [],
            "exitCode": None,
            "stdout": "",
            "stderr": "",
        }

    command = [
        executable,
        "-NoProfile",
        "-ExecutionPolicy",
        "Bypass",
        "-File",
        str(POWERSHELL_SCRIPT),
    ]

    parameter_map = {
        "WebsiteUrl": payload.get("websiteUrl"),
        "DownloadUrl": payload.get("downloadUrl"),
        "AppName": payload.get("appName"),
        "Version": payload.get("version"),
        "Publisher": payload.get("publisher"),
        "DeveloperUrl": payload.get("developerUrl"),
        "SupportUrl": payload.get("supportUrl"),
        "InstallCommand": payload.get("installCommand"),
        "IconPath": payload.get("iconPath"),
        "OutputPath": output_path,
    }

    for parameter, value in parameter_map.items():
        if value is None or str(value).strip() == "":
            continue
        command.extend([f"-{parameter}", str(value)])

    try:
        result = subprocess.run(
            command,
            capture_output=True,
            text=True,
            timeout=1800,
            check=False,
        )
        return {
            "ok": result.returncode == 0,
            "command": command,
            "exitCode": result.returncode,
            "stdout": result.stdout,
            "stderr": result.stderr,
        }
    except subprocess.TimeoutExpired as exc:
        return {
            "ok": False,
            "error": "Packaging script timed out.",
            "command": command,
            "exitCode": None,
            "stdout": exc.stdout or "",
            "stderr": exc.stderr or "",
        }


def create_app() -> Flask:
    ensure_directories()

    app = Flask(__name__, static_folder=str(UI_DIR), static_url_path="")

    @app.route("/")
    def index() -> Any:
        return send_from_directory(UI_DIR, "index.html")

    @app.route("/api/health")
    def health() -> Any:
        return jsonify(
            {
                "status": "ok",
                "scriptPath": str(POWERSHELL_SCRIPT),
                "powerShellAvailable": pick_powershell_executable() is not None,
            }
        )

    @app.route("/api/config/download-location", methods=["GET"])
    def get_download_location() -> Any:
        config = load_config()
        return jsonify({"downloadLocation": config["downloadLocation"]})

    @app.route("/api/config/download-location", methods=["PUT"])
    def set_download_location() -> Any:
        payload = request.get_json(silent=True) or {}
        new_location = str(payload.get("downloadLocation", "")).strip()
        if not new_location:
            return jsonify({"error": "downloadLocation is required."}), 400

        config = load_config()
        config["downloadLocation"] = new_location
        save_config(config)
        return jsonify({"downloadLocation": new_location})

    @app.route("/api/installers", methods=["GET"])
    def list_installers() -> Any:
        index = load_installer_index()
        records = [to_public_installer_record(value) for value in index.get("installers", {}).values()]
        records.sort(key=lambda item: item["createdAt"], reverse=True)
        return jsonify({"installers": records})

    @app.route("/api/installers/upload", methods=["POST"])
    def upload_installer() -> Any:
        if "file" not in request.files:
            return jsonify({"error": "File field 'file' is required."}), 400

        file_storage = request.files["file"]
        if not file_storage or not file_storage.filename:
            return jsonify({"error": "A file must be selected."}), 400

        try:
            record = save_uploaded_file(file_storage)
            return jsonify({"installer": to_public_installer_record(record)})
        except ValueError as exc:
            return jsonify({"error": str(exc)}), 400

    @app.route("/api/installers/download", methods=["POST"])
    def download_installer() -> Any:
        payload = request.get_json(silent=True) or {}
        url = str(payload.get("url", "")).strip()
        if not url:
            return jsonify({"error": "url is required."}), 400

        config = load_config()
        try:
            record, mode = download_installer_file(url, config["downloadLocation"])
        except Exception as exc:  # noqa: BLE001
            return jsonify({"error": f"Failed to download installer: {exc}"}), 400

        response_payload = {
            "installer": to_public_installer_record(record),
            "storageMode": mode,
        }
        if mode == "fallback":
            response_payload["warning"] = (
                "Configured download location could not be used on this host, "
                "so the installer was stored in the backend fallback downloads directory."
            )

        return jsonify(response_payload)

    @app.route("/api/installers/analyze", methods=["POST"])
    def analyze_existing_installer() -> Any:
        payload = request.get_json(silent=True) or {}
        installer_id = str(payload.get("installerId", "")).strip()
        if not installer_id:
            return jsonify({"error": "installerId is required."}), 400

        record = get_installer_record(installer_id)
        if not record:
            return jsonify({"error": "Installer not found."}), 404

        research_urls = payload.get("researchUrls") or []
        if not isinstance(research_urls, list):
            return jsonify({"error": "researchUrls must be an array of URLs."}), 400

        allow_runtime_probe = bool(payload.get("allowRuntimeProbe", False))
        app_name = str(payload.get("appName", "")).strip() or None

        try:
            analysis = analyze_installer(
                Path(record["path"]),
                app_name=app_name,
                research_urls=[str(url) for url in research_urls if str(url).strip()],
                allow_runtime_probe=allow_runtime_probe,
            )
        except FileNotFoundError as exc:
            return jsonify({"error": str(exc)}), 404
        except Exception as exc:  # noqa: BLE001
            return jsonify({"error": f"Failed to analyze installer: {exc}"}), 400

        return jsonify(
            {
                "installer": to_public_installer_record(record),
                "analysis": analysis,
            }
        )

    @app.route("/api/packages/create", methods=["POST"])
    def create_package() -> Any:
        payload = request.get_json(silent=True) or {}
        app_name = str(payload.get("appName", "")).strip()
        website_url = str(payload.get("websiteUrl", "")).strip()
        download_url = str(payload.get("downloadUrl", "")).strip()

        if not app_name:
            return jsonify({"error": "appName is required."}), 400
        if not website_url and not download_url:
            return jsonify({"error": "websiteUrl or downloadUrl is required."}), 400

        config = load_config()
        result = run_packaging_script(payload, config["downloadLocation"])
        status_code = 200 if result.get("ok") else 400
        return jsonify({"result": result}), status_code

    return app


if __name__ == "__main__":
    create_app().run(host="0.0.0.0", port=8765, debug=True)
