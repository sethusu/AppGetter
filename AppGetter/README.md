# AppGetter - IntuneWin Package Creator from Web Downloads

**Turn web-downloaded Windows installers into Intune Win32 packages in minutes.**

AppGetter automates the tedious parts of packaging desktop software for Microsoft Intune: downloading the installer from the web, generating `install.ps1` / `detection.ps1` / `uninstall.ps1`, resolving an app icon, building the `.intunewin` file with the Microsoft Win32 Content Prep Tool, and writing a field-by-field Intune upload guide.

Built for IT admins and packaging teams who want repeatable Win32 app onboarding without hand-writing detection scripts for every app.

---

## What you get

For each application, AppGetter produces:

| Output | Purpose |
|--------|---------|
| `{Installer}.intunewin` | Upload this to the Intune admin center |
| `install.ps1` | Silent install wrapper with Intune return codes |
| `detection.ps1` | Registry-based detection (no external dependencies on devices) |
| `uninstall.ps1` | Quiet uninstall from registry uninstall string |
| `README.md` | Copy/paste reference for every Intune portal field |
| `logo.png` / `icon.png` | App icon for Intune upload |
| `app.json` / `win32LobApp.json` | Metadata exports |

---

## Requirements

| Requirement | Notes |
|-------------|-------|
| **Windows 10/11** | PowerShell 5.1 or later |
| **[Win32 Content Prep Tool](https://github.com/microsoft/Microsoft-Win32-Content-Prep-Tool)** | `intunewinapputil` must be on your PATH |
| **Internet access** | Required to download installers from websites |

Run the built-in check from PowerShell:

```powershell
cd AppGetter
Import-Module .\AppGetter.psd1
Test-AppGetterPrerequisites
```

---

## Quick start (GUI — recommended)

1. **Clone or download** this repository.
2. Open **PowerShell** on Windows.
3. Run:

```powershell
cd AppGetter
.\Start-AppGetter.ps1
```

Or launch the GUI directly:

```powershell
.\Gui\Start-AppGetterGui.ps1
```

4. Enter the **application name** and either a **website URL** or **direct download URL**.
5. Optionally click **Find download links** to discover installer URLs from a website.
6. Choose an **output folder** (default: `Documents\AppGetter Output`).
7. Click **Create Package** and wait for the progress steps to finish.
8. Open the output folder and upload the `.intunewin` to Intune using the included `README.md` as your field guide.

---

## Quick start (CLI)

For scripting or automation:

```powershell
cd AppGetter

# Package from a website (auto-discovers download link)
.\Create-IntuneWinFromWeb.ps1 -WebsiteUrl "https://simion.com/" -AppName "SIMION" -Publisher "Adaptas Solutions, LLC"

# Package from a direct download URL
.\Create-IntuneWinFromWeb.ps1 -DownloadUrl "https://example.com/installer.exe" -AppName "MyApp" -Version "1.0.0"

# Custom output path and icon
.\Create-IntuneWinFromWeb.ps1 -DownloadUrl "https://example.com/setup.exe" -AppName "MyApp" `
    -OutputPath "C:\IntunePackages" `
    -IconPath "C:\Icons\myapp.png"
```

Run with no parameters to open the GUI:

```powershell
.\Create-IntuneWinFromWeb.ps1
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
Documents\AppGetter Output\
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
        ├── .icon-candidates\         ← Alternate icons (GUI)
        └── ..\simion-setup.intunewin
```

Default output path and last-used settings are saved to:

`%AppData%\AppGetter\settings.json`

---

## Parameters

- **WebsiteUrl** — Website containing download links (script will scan for `.exe`, `.msi`, etc.)
- **DownloadUrl** — Direct download URL (skips website scanning)
- **AppName** — Application display name
- **Version** — Optional version override (auto-detected from website if omitted)
- **Publisher** — Optional publisher name
- **DeveloperUrl** — Optional developer/publisher site (helps icon and description discovery)
- **SupportUrl** — Optional support/docs page (helps silent install switch discovery)
- **OutputPath** — Base output directory (default from settings)
- **IconPath** — Optional custom PNG icon
- **InstallCommand** — Optional custom raw installer command (auto-detected by file type if omitted)

---

## PowerShell module (advanced)

```powershell
Import-Module .\AppGetter\AppGetter.psd1

Get-DownloadLinksFromWeb -Url 'https://example.com/' -AppName 'MyApp'
Invoke-AppGetterPackaging -AppName 'MyApp' -DownloadUrl 'https://example.com/setup.exe' -OutputPath 'C:\Out'
```

---

## Repository layout

```
AppGetter/
├── README.md                          ← You are here
├── Create-IntuneWinFromWeb.ps1        ← CLI entry point (no args = GUI)
├── Start-AppGetter.ps1                ← One-command GUI launcher
├── AppGetter.psm1                     ← Core module
├── AppGetter.psd1
├── Gui/
│   └── Start-AppGetterGui.ps1         ← WPF GUI
├── Private/                           ← Packaging, web download, icons, scripts
└── Example-Usage.ps1
```

---

## Troubleshooting

| Problem | What to try |
|---------|-------------|
| `intunewinapputil` not found | Install the [Content Prep Tool](https://github.com/microsoft/Microsoft-Win32-Content-Prep-Tool) and add it to PATH |
| No download links found | Provide a direct `-DownloadUrl` instead of `-WebsiteUrl` |
| Packaging failed | Check `appgetter-packaging.log` in the version output folder and the GUI log panel |
| Detection fails on devices | Run `detection.ps1` locally; review logs in `%ProgramData%\Microsoft\IntuneManagementExtension\Logs\` |
| GUI won't start | Run from PowerShell 5.1+ on Windows; WPF requires a desktop session |

---

## License

Provided as-is for creating Intune Win32 packages from web-based application downloads.
