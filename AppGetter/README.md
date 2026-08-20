# AppGetter

**Turn web downloads or local installer files into Intune Win32 packages in minutes.**

AppGetter automates the tedious parts of packaging desktop software for Microsoft Intune: downloading the installer from the web (or copying one already on your computer), generating `install.ps1` / `detection.ps1` / `uninstall.ps1`, resolving an app icon, building the `.intunewin` file with the Microsoft Win32 Content Prep Tool, and writing a field-by-field Intune upload guide.

AppGetter follows the [WinGetter](https://github.com/sethusu/WinGetter) (Wingetter) architecture and UI — the difference is the installer source: Wingetter pulls apps from Winget, AppGetter uses a download URL or a file on the computer running it.

Built for IT admins and packaging teams who need repeatable Win32 app onboarding without hand-writing detection scripts for every app.

---

## What you get

For each application, AppGetter produces:

| Output | Purpose |
|--------|---------|
| `{App}.intunewin` | Upload this to the Intune admin center |
| `install.ps1` | Silent install wrapper with Intune return codes |
| `detection.ps1` | Registry-based detection (no external dependencies on devices) |
| `uninstall.ps1` | Quiet uninstall from registry uninstall string |
| `README.md` | Copy/paste reference for every Intune portal field |
| `logo.png` / `icon.png` | App icon for Intune upload |
| `app.json` / `win32LobApp.json` | Metadata exports |
| `validation.json` | Written after a successful Test in Sandbox run |
| `sandbox-test-report.txt` | Chat-ready sandbox log (after Test in Sandbox) |

---

## Requirements

| Requirement | Notes |
|-------------|-------|
| **Windows 10/11** | PowerShell 5.1 or later |
| **[Win32 Content Prep Tool](https://github.com/microsoft/Microsoft-Win32-Content-Prep-Tool)** | `intunewinapputil` — install it from the GUI (via winget) if it is missing |
| **Internet Access** | Required when packaging from a website or direct download URL |

Run the built-in check from PowerShell:

```powershell
cd AppGetter
Import-Module .\AppGetter.psd1
Test-AppGetterPrerequisites
```

---

## Quick start (GUI — recommended)

1. **Clone or download** this repository.
2. Double-click **`Start-AppGetter.cmd`** (no elevated PowerShell required), or run from PowerShell:

```powershell
cd AppGetter
.\Create-IntuneWinFromWeb.ps1
```

Or launch the GUI directly:

```powershell
.\Gui\Start-AppGetterGui.ps1
```

3. Enter the **application name** and one of: a **website URL** (to scan for download links), a **direct download URL**, or a **local installer file** (Browse...).
4. Choose an **output folder** — each app gets its own subfolder (default: `Documents\AppGetter\{App}`).
5. Click **Create Package** and watch the live progress steps (the window stays responsive while packaging runs in the background).
6. Optionally click **Test in Sandbox** to confirm install, detection, and uninstall inside Windows Sandbox before uploading to Intune.
7. Open the output folder and upload the `.intunewin` to Intune using the included `README.md` as your field guide.

If the Content Prep Tool is missing, the header shows an **Install Content Prep** button that installs `intunewinapputil` via winget.

### Test in Sandbox

After a package is created (or when the output folder already contains `install.ps1`, `detection.ps1`, and `uninstall.ps1`), use **Test in Sandbox** to:

1. Launch Windows Sandbox with the package folder mapped in
2. Run `install.ps1`, confirm the step, then `detection.ps1`, then `uninstall.ps1`
3. Mark the package validated only when all three steps succeed and the install stayed silent (no installer UI)

Requires Windows 10/11 Pro, Enterprise, or Education with Windows Sandbox enabled. The dialog can prompt to enable the feature (admin approval; usually a reboot). Diagnostics are written next to the package as `sandbox-test-report.txt`, `sandbox-failure.log`, and `sandbox-logs\`.

---

## Deploy as an executable

Build a double-clickable `AppGetter.exe` (same ps2exe pipeline as Wingetter):

```powershell
cd AppGetter
.\Build\Build-AppGetterExe.ps1
```

This stages `dist\AppGetter` with `AppGetter.exe` next to the runtime files and creates
`dist\AppGetter-portable.zip` for sharing. End users just double-click `AppGetter.exe` —
no elevated PowerShell session required. If antivirus blocks the exe, `Start-AppGetter.cmd`
or `Launch-AppGetter.ps1` launch the same GUI. Startup problems are logged to
`%TEMP%\AppGetter-launch.log`.

---

## Quick start (CLI)

For scripting or automation:

```powershell
cd AppGetter

# Package from a website (scans for download links)
.\Create-IntuneWinFromWeb.ps1 -WebsiteUrl "https://simion.com/" -AppName "SIMION" -Publisher "Adaptas Solutions, LLC"

# Package from a direct download URL
.\Create-IntuneWinFromWeb.ps1 -DownloadUrl "https://example.com/installer.exe" -AppName "MyApp" -Version "1.0.0"

# Package an installer already on this computer
.\Create-IntuneWinFromWeb.ps1 -InstallerPath "C:\Installers\setup.exe" -AppName "MyApp" -Version "1.0.0"

# Custom output path and icon
.\Create-IntuneWinFromWeb.ps1 -DownloadUrl "https://example.com/setup.exe" -AppName "MyApp" `
    -OutputPath "C:\IntunePackages" `
    -IconPath "C:\Icons\myapp.png"
```

---

## Typical Intune workflow

1. **Package** the app with AppGetter on a Windows machine that has the Content Prep Tool installed.
2. **Review** the generated `README.md` in the version folder — it lists install command, detection method, publisher, description, and return codes.
3. **Upload** the `.intunewin` file in **Intune** → **Apps** → **Windows** → **Add** → **Windows app (Win32)**.
4. **Fill in** portal fields using the generated reference (or `win32LobApp.json` as a starting point).
5. **Assign** the app to a test group before broad rollout.
6. **Validate** on a pilot device — check `%ProgramData%\Microsoft\IntuneManagementExtension\Logs\` for install/detection logs.

---

## Output folder layout

```
Documents\AppGetter\
└── SIMION\
    ├── logo.png
    └── 8.2.1.3\
        ├── simion-setup.exe
        ├── install.ps1
        ├── detection.ps1
        ├── uninstall.ps1
        ├── README.md                 ← Intune upload cheat sheet
        ├── readme.txt
        ├── app.json
        ├── win32LobApp.json
        ├── icon.png
        └── ..\simion-setup.intunewin
```

Default output path and last-used settings are saved to:

`%AppData%\AppGetter\settings.json`

---

## Parameters

| Parameter | Description |
|-----------|-------------|
| **WebsiteUrl** | URL to scan for download links |
| **DownloadUrl** | Direct download URL (skips website scanning) |
| **InstallerPath** | Path to an installer file on this computer (skips downloading) |
| **AppName** | Application display name |
| **Version** | Optional version (auto-detected from website if omitted) |
| **Publisher** | Publisher name |
| **DeveloperUrl** | Optional developer site for logo/description lookup |
| **SupportUrl** | Optional docs page for silent install switch discovery |
| **OutputPath** | Base output directory |
| **IconPath** | Custom PNG icon |
| **InstallCommand** | Custom install command (auto-detected if omitted) |
| **UseGui** | Launch the WPF GUI |

---

## Repository layout

```
AppGetter/
├── README.md                          ← You are here
├── Create-IntuneWinFromWeb.ps1         ← CLI entry point (no args = GUI)
├── Launch-AppGetter.ps1               ← Double-click / ps2exe entry point
├── Start-AppGetter.cmd                ← Double-click helper (no build required)
├── AppGetter.psm1                     ← Core module
├── AppGetter.psd1
├── Private/                           ← Packaging, web download, icons, scripts
├── Gui/
│   ├── Start-AppGetterGui.ps1
│   ├── AppGetter.MainWindow.xaml      ← WPF UI
│   └── AppGetter.SandboxTestDialog.xaml
├── Private/
│   └── Sandbox.ps1                    ← Windows Sandbox install/detect/uninstall test
├── Tests/
│   └── Sandbox.Tests.ps1
├── Build/
│   └── Build-AppGetterExe.ps1         ← Builds AppGetter.exe + portable zip
└── Example-Usage.ps1
```

---

## PowerShell module (advanced)

```powershell
Import-Module .\AppGetter\AppGetter.psd1

Find-WebDownloadLinks -Url 'https://simion.com/' -AppName 'SIMION'
Invoke-AppGetterPackaging -AppName 'MyApp' -DownloadUrl 'https://example.com/setup.exe' -OutputPath 'C:\Out'
Invoke-AppGetterPackaging -AppName 'MyApp' -InstallerPath 'C:\Installers\setup.exe' -OutputPath 'C:\Out'
Install-AppGetterContentPrepTool   # installs intunewinapputil via winget if missing
```

---

## Troubleshooting

| Problem | What to try |
|---------|-------------|
| `intunewinapputil` not found | Click **Install Content Prep** in the GUI, run `Install-AppGetterContentPrepTool`, or install the [Content Prep Tool](https://github.com/microsoft/Microsoft-Win32-Content-Prep-Tool) manually |
| No download links found | Provide a direct `-DownloadUrl` or a local `-InstallerPath` instead of `-WebsiteUrl` |
| `AppGetter.exe` won't start | Check `%TEMP%\AppGetter-launch.log`; use `Start-AppGetter.cmd` or `Launch-AppGetter.ps1` instead |
| Packaging failed | Check `appgetter-packaging.log` in the version output folder and the GUI log panel |
| Test in Sandbox unavailable | Needs Windows Pro/Enterprise/Education with Sandbox enabled; Home is not supported |
| Sandbox install showed a dialog | Install was not silent — see `sandbox-failure.log` and re-package with better switches |
| Detection fails on devices | Run `detection.ps1` locally; review logs in `%ProgramData%\Microsoft\IntuneManagementExtension\Logs\` |
| GUI won't start | Run from PowerShell 5.1+ on Windows; WPF requires a desktop session |

More detail: [Troubleshooting-Guide.md](Troubleshooting-Guide.md)

---

## License

Provided as-is for creating Intune Win32 packages from web downloads or local installer files.
