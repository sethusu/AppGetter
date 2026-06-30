import importlib
from pathlib import Path

from fastapi.testclient import TestClient

import appgetter_ui_backend.server as server_module


def _reload_server_module(monkeypatch, tmp_path: Path):
    monkeypatch.setenv("APPGETTER_CONFIG_PATH", str(tmp_path / "config.json"))
    monkeypatch.setenv("APPGETTER_DOWNLOAD_ROOT", str(tmp_path / "downloads"))
    return importlib.reload(server_module)


def test_config_roundtrip(monkeypatch, tmp_path: Path) -> None:
    module = _reload_server_module(monkeypatch, tmp_path)
    client = TestClient(module.app)

    response = client.post(
        "/api/config",
        json={"download_location": str(tmp_path / "custom-downloads")},
    )
    assert response.status_code == 200
    assert response.json()["config"]["download_location"].endswith("custom-downloads")

    response = client.get("/api/config")
    assert response.status_code == 200
    assert response.json()["download_location"].endswith("custom-downloads")


def test_analyze_upload(monkeypatch, tmp_path: Path) -> None:
    module = _reload_server_module(monkeypatch, tmp_path)
    client = TestClient(module.app)

    files = {"file": ("installer.exe", b"MZ...Inno Setup...", "application/octet-stream")}
    response = client.post(
        "/api/analyze/upload",
        files=files,
        data={"try_runtime_tests": "false"},
    )

    assert response.status_code == 200
    body = response.json()
    assert body["analysis"]["installer_type"] == "exe"
    assert "switches" in body["discovery"]

