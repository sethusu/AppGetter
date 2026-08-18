# AppGetter Changelog

## Version 3.0 - 2026-08-18

### Wingetter-style UI and executable deployment

AppGetter now mirrors the [WinGetter](https://github.com/sethusu/WinGetter) (Wingetter) interface and
ships the same way — as a double-clickable executable. The one difference remains the installer
source: AppGetter takes a **download URL** or a **file already on the computer running it**, where
Wingetter takes a Winget package.

- **Executable deployment** — `Build/Build-AppGetterExe.ps1` compiles `Launch-AppGetter.ps1` into
  `AppGetter.exe` with ps2exe and stages a portable folder/zip. `Start-AppGetter.cmd` and
  `Build/Diagnose-AppGetterLaunch.ps1` mirror the Wingetter launch and troubleshooting helpers
- **Local installer files** — new `-InstallerPath` parameter on `Invoke-AppGetterPackaging` and
  `Create-IntuneWinFromWeb.ps1`; the file is staged into the package folder and its version is read
  from file version info (or the file name)
- **Wingetter-style GUI** — header prerequisite banner with an **Install Content Prep** button,
  source card, output destination browser, live step list, icon preview, and log panel
- **Download link picker** — scanning a website opens a radio-button dialog, the counterpart of
  Wingetter's search results dialog
- **Icon picker** — packaging collects up to three distinct icon candidates (installer resource,
  website logo, favicon) and offers a choice after packaging
- **Background packaging** — runs in a separate runspace with a progress queue, so the window stays
  responsive (previously the UI blocked during packaging)
- **Content Prep Tool parity** — `Resolve-AppGetterContentPrepToolPath` also probes the WinGet Links
  folder and both Program Files locations; `Install-AppGetterContentPrepTool` installs
  `Microsoft.Win32ContentPrepTool` via winget and refreshes the session PATH
- **Output layout** — packages always land in `{base}\{PackageId}\{Version}`, with the base folder
  remembered between runs. The default base moved from `Documents\AppGetter Output` to
  `Documents\AppGetter`; the old default is migrated automatically
- **Tests** — `Run-Tests.ps1` plus Pester suites covering output paths, installer source resolution,
  end-to-end packaging, and the GUI/executable contract

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
