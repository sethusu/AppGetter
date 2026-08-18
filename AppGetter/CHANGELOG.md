# AppGetter Changelog

## Version 2.1.0

### WinGetter UI and executable parity

- GUI layout matches Wingetter: header prerequisite status, **Install Content Prep** button, output destination + Browse, live progress, icon preview, log panel, **Open Output Folder**
- Installer source is a **download URL** or a **local file** on the computer running AppGetter (`-InstallerPath` / Browse...)
- Same Content Prep Tool discovery as Wingetter (`intunewinapputil` / `IntuneWinAppUtil`, WinGet Links, Program Files) plus `Install-AppGetterContentPrepTool`
- Same output location dialog as Wingetter (My Computer root, new-folder button, parented to the WPF window) so Browse does not tear down the GUI
- Default output folder is `Documents\AppGetter\{PackageId}\`; existing `Documents\AppGetter Output` settings migrate
- Packaging runs in a background runspace so the GUI stays responsive
- Double-click executable: `Launch-AppGetter.ps1`, `Start-AppGetter.cmd`, and `Build\Build-AppGetterExe.ps1` (ps2exe portable `AppGetter.exe`)

### Silent install switch discovery

- **`Private/SwitchDiscovery.ps1`** — layered discovery pipeline: binary fingerprinting (MSI, Inno, NSIS, InstallShield, WiX Burn), nested MSI references, support-page switch hints, and confidence-scored candidate ranking
- **Packaging flow** — runs discovery after installer download and before `install.ps1` generation; user-provided `-InstallCommand` bypasses discovery
- **Metadata** — `README.md` and `app.json` include discovery evidence, confidence score, alternatives, and manual-review flag

## Version 2.0 - 2026-06-30

### WinGetter-style rewrite (PowerShell-only)

AppGetter has been restructured to mirror [WinGetter](https://github.com/sethusu/WinGetter) (Wingetter):

- **Removed Python backend** — no Flask server, no `requirements.txt`, no browser-based control center
- **PowerShell module** — `AppGetter.psm1` with `Private/` scripts for web download, packaging, scripts, icons, and settings
- **WPF GUI** — `Gui/Start-AppGetterGui.ps1` replaces the Python web dashboard
- **`install.ps1`** — silent install wrapper with Intune return codes (3010, 1641, 1618)
- **`README.md`** — field-by-field Intune portal upload reference in each package
- **Settings persistence** — `%AppData%\AppGetter\settings.json`
- **Prerequisite check** — `Test-AppGetterPrerequisites` verifies Content Prep Tool on PATH
- **Progress reporting** — step list and progress callbacks for CLI and GUI
- **Failure logging** — `appgetter-packaging.log` on packaging errors

### Breaking changes

- `Start-AppGetter.ps1` (Python launcher) removed — use `Create-IntuneWinFromWeb.ps1` or `Gui/Start-AppGetterGui.ps1`
- Default output path changed to `Documents\AppGetter Output` (was `D:\Intoon In Progress`)
- Intune install command now uses `install.ps1` wrapper instead of raw installer command

## Version 1.0 - 2026-01-23

### Initial Release

- Web-based download link discovery
- Registry-based detection scripts
- Support for EXE, MSI, MSIX, and APPX installers
- Content Prep Tool integration
- Metadata generation (app.json, win32LobApp.json)
