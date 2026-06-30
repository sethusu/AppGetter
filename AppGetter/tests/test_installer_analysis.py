from pathlib import Path

from appgetter_ui_backend.installer_analysis import InstallerInspector


def test_msi_uses_known_switches(tmp_path: Path) -> None:
    installer = tmp_path / "sample.msi"
    installer.write_bytes(b"fake-msi-data")

    inspector = InstallerInspector()
    result = inspector.discover_silent_switches(str(installer))

    assert result["analysis"]["installer_type"] == "msi"
    assert "/qn" in result["discovery"]["switches"]
    assert result["discovery"]["confidence"] in {"medium", "high"}


def test_detects_nsis_engine_signature(tmp_path: Path) -> None:
    installer = tmp_path / "setup.exe"
    installer.write_bytes(b"MZ....Nullsoft Install System....")

    inspector = InstallerInspector()
    result = inspector.discover_silent_switches(str(installer))

    assert result["analysis"]["installer_type"] == "exe"
    assert result["analysis"]["installer_engine"] == "NSIS"
    assert "/S" in result["discovery"]["switches"]
    assert result["discovery"]["source"] == "research-db"


def test_non_exe_does_not_report_installer_engine(tmp_path: Path) -> None:
    installer = tmp_path / "notes.txt"
    installer.write_text("This text mentions NSIS but is not an installer.")

    inspector = InstallerInspector()
    result = inspector.discover_silent_switches(str(installer))

    assert result["analysis"]["installer_type"] == "unknown"
    assert result["analysis"]["installer_engine"] is None

