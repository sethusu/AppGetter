"""FastAPI backend and Win11-style UI for AppGetter."""

from __future__ import annotations

from pathlib import Path
from typing import Any
import json
import os
import subprocess

from fastapi import FastAPI, File, Form, HTTPException, UploadFile
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import FileResponse
from fastapi.staticfiles import StaticFiles
from pydantic import BaseModel, Field

from appgetter_ui_backend.installer_analysis import (
    InstallerInspector,
    download_installer,
    ensure_download_location,
)


PROJECT_ROOT = Path(__file__).resolve().parent.parent
STATIC_DIR = Path(__file__).resolve().parent / "static"
CONFIG_PATH = Path(
    os.getenv("APPGETTER_CONFIG_PATH", str(PROJECT_ROOT / ".appgetter-ui-config.json"))
)
DEFAULT_DOWNLOAD_LOCATION = os.getenv(
    "APPGETTER_DOWNLOAD_ROOT", str(PROJECT_ROOT / "downloads")
)
POWERSHELL_SCRIPT = PROJECT_ROOT / "Create-IntuneWinFromWeb.ps1"

inspector = InstallerInspector()


class AppConfig(BaseModel):
    download_location: str = Field(default=DEFAULT_DOWNLOAD_LOCATION)


class ConfigUpdate(BaseModel):
    download_location: str


class AnalyzeFromUrlRequest(BaseModel):
    download_url: str
    download_location: str | None = None
    try_runtime_tests: bool = False


class DiscoverSwitchesRequest(BaseModel):
    installer_path: str
    try_runtime_tests: bool = False


class PackageRequest(BaseModel):
    app_name: str
    website_url: str | None = None
    download_url: str | None = None
    version: str | None = None
    publisher: str | None = None
    output_path: str | None = None
    icon_path: str | None = None
    install_command: str | None = None


def load_config() -> AppConfig:
    if not CONFIG_PATH.exists():
        return AppConfig()
    try:
        payload = json.loads(CONFIG_PATH.read_text())
        return AppConfig(**payload)
    except (json.JSONDecodeError, OSError):
        return AppConfig()


def save_config(config: AppConfig) -> None:
    CONFIG_PATH.parent.mkdir(parents=True, exist_ok=True)
    CONFIG_PATH.write_text(config.model_dump_json(indent=2))


def append_powershell_param(command: list[str], flag: str, value: str | None) -> None:
    if value is not None and str(value).strip():
        command.extend([flag, value])


app = FastAPI(title="AppGetter Installer Workbench", version="2.0.0")
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)
app.mount("/static", StaticFiles(directory=STATIC_DIR), name="static")


@app.get("/")
def index() -> FileResponse:
    return FileResponse(STATIC_DIR / "index.html")


@app.get("/api/health")
def health() -> dict[str, str]:
    return {"status": "ok"}


@app.get("/api/config")
def get_config() -> dict[str, Any]:
    config = load_config()
    ensure_download_location(config.download_location)
    return config.model_dump()


@app.post("/api/config")
def update_config(update: ConfigUpdate) -> dict[str, Any]:
    config = AppConfig(download_location=update.download_location)
    ensure_download_location(config.download_location)
    save_config(config)
    return {
        "message": "Download location updated.",
        "config": config.model_dump(),
    }


@app.post("/api/analyze/url")
def analyze_from_url(payload: AnalyzeFromUrlRequest) -> dict[str, Any]:
    config = load_config()
    download_location = payload.download_location or config.download_location
    ensure_download_location(download_location)
    try:
        installer_path = download_installer(payload.download_url, download_location)
        result = inspector.discover_silent_switches(
            str(installer_path),
            try_runtime_tests=payload.try_runtime_tests,
        )
    except Exception as exc:  # noqa: BLE001
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    return {
        "download_url": payload.download_url,
        "installer_path": str(installer_path),
        **result,
    }


@app.post("/api/analyze/upload")
async def analyze_from_upload(
    file: UploadFile = File(...),
    download_location: str | None = Form(default=None),
    try_runtime_tests: bool = Form(default=False),
) -> dict[str, Any]:
    config = load_config()
    target_location = download_location or config.download_location
    target_dir = ensure_download_location(target_location)
    safe_file_name = Path(file.filename).name
    target_path = target_dir / safe_file_name
    data = await file.read()
    target_path.write_bytes(data)

    result = inspector.discover_silent_switches(
        str(target_path),
        try_runtime_tests=try_runtime_tests,
    )
    return {
        "uploaded_file_name": safe_file_name,
        "installer_path": str(target_path),
        **result,
    }


@app.post("/api/discover-switches")
def discover_switches(payload: DiscoverSwitchesRequest) -> dict[str, Any]:
    try:
        return inspector.discover_silent_switches(
            payload.installer_path,
            try_runtime_tests=payload.try_runtime_tests,
        )
    except FileNotFoundError as exc:
        raise HTTPException(status_code=404, detail=str(exc)) from exc
    except Exception as exc:  # noqa: BLE001
        raise HTTPException(status_code=400, detail=str(exc)) from exc


@app.post("/api/create-package")
def create_package(payload: PackageRequest) -> dict[str, Any]:
    if not payload.download_url and not payload.website_url:
        raise HTTPException(
            status_code=400,
            detail="Either download_url or website_url is required.",
        )
    if not POWERSHELL_SCRIPT.exists():
        raise HTTPException(
            status_code=500,
            detail=f"PowerShell script not found: {POWERSHELL_SCRIPT}",
        )

    command = ["pwsh", "-File", str(POWERSHELL_SCRIPT), "-AppName", payload.app_name]
    append_powershell_param(command, "-WebsiteUrl", payload.website_url)
    append_powershell_param(command, "-DownloadUrl", payload.download_url)
    append_powershell_param(command, "-Version", payload.version)
    append_powershell_param(command, "-Publisher", payload.publisher)
    append_powershell_param(command, "-OutputPath", payload.output_path)
    append_powershell_param(command, "-IconPath", payload.icon_path)
    append_powershell_param(command, "-InstallCommand", payload.install_command)

    try:
        completed = subprocess.run(
            command,
            cwd=PROJECT_ROOT,
            capture_output=True,
            text=True,
            check=False,
        )
    except FileNotFoundError as exc:
        raise HTTPException(
            status_code=500,
            detail="pwsh was not found on this machine.",
        ) from exc

    return {
        "command": command,
        "exit_code": completed.returncode,
        "stdout": completed.stdout,
        "stderr": completed.stderr,
        "success": completed.returncode == 0,
    }


if __name__ == "__main__":
    import uvicorn

    uvicorn.run("appgetter_ui_backend.server:app", host="0.0.0.0", port=8000)

