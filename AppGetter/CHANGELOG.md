# AppGetter Changelog

## Version 2.3.0 - Unreleased

### Licensing pattern discovery and application
- New **licensing field** ingested from the ServiceNow software record (`-LicenseInfo`, plus a
  "Licensing (ServiceNow field)" box in the GUI with a live pattern preview). AppGetter identifies
  which licensing pattern the app follows and applies it to the package instead of only recording it
- `Private/Licensing.ps1` classifies the field against 13 patterns — open source, freeware, trial,
  per-user subscription, per-device perpetual, per core/processor, concurrent/floating, license file,
  site/enterprise, volume activation (MAK/KMS), hardware dongle, OEM, and purchased key — and
  corroborates the winner with installer evidence (FlexNet/FLEXlm, RLM, Sentinel RMS, HASP,
  CodeMeter, volume activation clients, trial and sign-in prompts, key-bearing MSI properties)
- Extracts the license key, `port@host` server, vendor license environment variable, license file
  name and destination, seat count, expiry date, and approval/chargeback signals out of the field
- **Applies** the pattern: keys are appended to install commands that accept MSI properties
  (`msiexec`, WiX Burn) through the property detected in the installer; license files ship inside
  the package under `license\` and are staged during install; license servers are set through the
  vendor environment variable. Sign-in, dongle, volume, and trial patterns are logged in the
  install transcript
- Writes `licensing.json`, a `licensing` block in `app.json`, a **Licensing** section in the
  generated `README.md`, and a licensing summary in the `win32LobApp` notes — including a
  recommended Intune assignment type and compliance notes for seat counts and expiry dates
- License keys are masked wherever persisted, redacted from the licensing text kept in metadata,
  stripped from the object returned to callers, and replaced with `***REDACTED***` in the
  `install.ps1` transcript
- New parameters: `-LicenseInfo`, `-LicenseType`, `-LicenseKey`, `-LicenseServer`,
  `-LicenseServerVariable`, `-LicenseFilePath`, `-LicenseFileTargetPath`. `-LicenseType` accepts
  pattern ids, AppGetter license types, or common ServiceNow *License type* / *License metric* values
- Pester coverage: `Tests/Licensing.Tests.ps1` (Linux-safe)
- Packaging is now 14 steps instead of 13. Packaging without a licensing field produces the same
  output as before

### Silent switch Sandbox research
- Added Windows Sandbox **candidate trials** during discovery (`Test-InstallerCommandInSandbox`) that prove silence (no installer UI), accepted exit codes, and new ARP install evidence — not just post-package success
- Packaging can force trials with `-VerifySilentSwitches` (CLI/GUI); trials also auto-run when static confidence is low/ambiguous and Sandbox is available
- SHA-256 silent-switch cache under `%AppData%\AppGetter\silent-switch-cache.json`
- Writes `silent-switches.json` next to each package; optional winget catalog hints as candidates
- Pester coverage: `Tests/SwitchDiscovery.Tests.ps1` (Linux-safe corpus) and `-Tag SandboxLive` for live trial hosts
- **Restore missing installer for Sandbox**: when a package folder is pulled/copied without the `.msi`/`.exe`, `Restore-AppGetterPackageInstaller` re-downloads from `app.json` `installerUrl` (used by Test in Sandbox / trial sessions). `Get-AppGetterLiveTestInstaller` caches a real 7-Zip MSI for SandboxLive tests

## Version 2.2.0 - 2026-08-20

### Test in Sandbox
- Added a **Test in Sandbox** button that launches Windows Sandbox against the packaged app folder (mirrors Wingetter)
- Checks whether Windows Sandbox (`Containers-DisposableClientVM`) is enabled; if it is not, prompts to enable it (administrator approval, usually a reboot)
- Inside the sandbox, runs `install.ps1`, then `detection.ps1`, then `uninstall.ps1`, waiting for host confirmation after each step
- Marks the package validated (`validation.json` plus `sandboxValidated` on `app.json`) only when install, detect, and uninstall are all confirmed and the install stayed silent
- Watches for installer dialogs; if one appears, screenshots the desktop, stops the hung installer, and refuses to mark the package validated
- Writes chat-ready `sandbox-test-report.txt` and `sandbox-failure.log` (plus `sandbox-logs\`) into the package folder
- Windows Home and non-Windows hosts get a clear unsupported message instead of a failed launch
- Pester coverage under `Tests/Sandbox.Tests.ps1` (run via `Run-Tests.ps1`)

## Version 2.1 - Unreleased

### Wingetter UI parity and executable deployment

AppGetter now follows the Wingetter GUI architecture and ships the same executable
deployment pipeline:

- **`Build/Build-AppGetterExe.ps1`** — compiles `Launch-AppGetter.ps1` into a double-clickable
  `AppGetter.exe` with ps2exe, stages `dist\AppGetter`, and zips `AppGetter-portable.zip`
- **`Launch-AppGetter.ps1`** / **`Start-AppGetter.cmd`** — launcher entry points (exe, cmd, or ps1)
  with startup logging to `%TEMP%\AppGetter-launch.log`
- **Local installer support** — new `-InstallerPath` parameter (CLI and `Invoke-AppGetterPackaging`)
  and a "Local Installer File" browse field in the GUI package an installer already on this
  computer instead of downloading it
- **Non-blocking GUI packaging** — packaging runs in a background runspace with a progress queue,
  so the window stays responsive (same pattern as Wingetter)
- **Install Content Prep from the GUI** — `Install-AppGetterContentPrepTool` installs the Microsoft
  Win32 Content Prep Tool via winget; the header shows an "Install Content Prep" button when the
  tool is missing
- **Stronger Content Prep detection** — `Resolve-ContentPrepToolPath` refreshes the session PATH and
  checks winget link and Program Files locations (same checks as Wingetter); packaging invokes the
  resolved executable path
- **Wingetter output layout** — output destination is a base folder with a per-app subfolder
  (`Documents\AppGetter\{App}` by default); the browse dialog roots at My Computer and is parented
  to the main window
- **Settings** — persists the base output folder and the last installer path; legacy
  `Documents\AppGetter Output` default migrates automatically

## Unreleased

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
