# AppGetter — Intune Win32 packages from web downloads

**Turn web-based application installers into Intune Win32 packages in minutes.**

AppGetter automates the tedious parts of packaging desktop software for Microsoft Intune: downloading the installer from a website or direct URL, generating `install.ps1` / `detection.ps1` / `uninstall.ps1`, resolving an app icon, building the `.intunewin` file with the Microsoft Win32 Content Prep Tool, and writing a field-by-field Intune upload guide.

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
| **Internet access** | Required to download installers from the web |

Run the built-in check from PowerShell:

```powershell
cd AppGetter
Import-Module .\AppGetter.psd1
Test-AppGetterPrerequisites
```

---

## Quick start (GUI — recommended)

1. Open **PowerShell** on a Windows machine with the Content Prep Tool installed.
2. Run:

```powershell
cd AppGetter
.\Create-IntuneWinFromWeb.ps1
```

Or launch the GUI directly:

```powershell
.\Gui\Start-AppGetterGui.ps1
```

3. Enter the **application name**, a **website URL** or **direct download URL**, and an **output folder**.
4. Optionally fill in publisher, version, developer URL, and support URL.
5. Click **Create Package** and wait for the progress steps to finish.
6. If multiple icons were found, pick the best match in the **icon picker** dialog.
7. Open the output folder and upload the `.intunewin` to Intune using the included `README.md` as your field guide.

---

## Quick start (CLI)

For scripting or automation:

```powershell
cd AppGetter

# Package from a website (scans for download links)
.\Create-IntuneWinFromWeb.ps1 -WebsiteUrl "https://simion.com/" -AppName "SIMION" -Publisher "Adaptas Solutions, LLC"

# Direct download URL
.\Create-IntuneWinFromWeb.ps1 -DownloadUrl "https://example.com/setup.exe" -AppName "MyApp" -Version "1.0.0"

# Custom output path and icon
.\Create-IntuneWinFromWeb.ps1 -DownloadUrl "https://example.com/app.msi" -AppName "MyApp" `
    -OutputPath "C:\IntunePackages" `
    -IconPath "C:\Icons\myapp.png"
```

---

## Typical Intune workflow

1. **Package** the app with AppGetter on a Windows machine that has the Content Prep Tool.
2. **Review** the generated `README.md` in the version folder — it lists install command, detection method, publisher, description, and return codes.
3. **Upload** the `.intunewin` file in **Intune** → **Apps** → **Windows** → **Add** → **Windows app (Win32)**.
4. **Fill in** portal fields using the generated reference (or `win32LobApp.json` as a starting point).
5. **Assign** the app to a test group before broad rollout.
6. **Validate** on a pilot device — check `%ProgramData%\Microsoft\IntuneManagementExtension\Logs\` or `%ProgramData%\Microsoft\IntuneManagementExtension\Logs\` for install/detection logs.

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
        ├── README.md
        ├── readme.txt
        ├── app.json
        ├── win32LobApp.json
        ├── icon.png
        ├── .icon-candidates\
        └── ..\simion-setup.intunewin
```

Default output path and last-used settings are saved to:

`%AppData%\AppGetter\settings.json`

---

## GUI features

- **Website link discovery** with a picker when multiple download links are found
- **Live progress** — step list, progress bar, and log panel
- **Icon preview** when a custom icon is selected
- **Icon picker after packaging** — choose among up to 3 downloaded icon candidates
- **Custom icon** — browse for your own PNG before packaging
- **Open output folder** when done

---

## Parameters (CLI)

| Parameter | Description |
|-----------|-------------|
| `-WebsiteUrl` | Page to scan for download links |
| `-DownloadUrl` | Direct installer URL (skips website scan) |
| `-AppName` | Application display name |
| `-Version` | Version string (auto-detected from website if omitted) |
| `-Publisher` | Publisher name |
| `-DeveloperUrl` | Developer/publisher site (helps icon and description discovery) |
| `-SupportUrl` | Support/docs page (helps silent switch discovery) |
| `-OutputPath` | Base output folder (default: saved settings path) |
| `-IconPath` | Custom PNG icon |
| `-InstallCommand` | Override auto-detected install command |
| `-UseGui` | Launch the WPF GUI |

---

## Repository layout

```
AppGetter/
├── Create-IntuneWinFromWeb.ps1   ← CLI entry point (no args = GUI)
├── AppGetter.psd1 / AppGetter.psm1
├── Private/                      ← Packaging, web download, icons, scripts
├── Gui/
│   ├── Start-AppGetterGui.ps1
│   └── *.xaml                    ← WPF UI
├── Example-Usage.ps1
└── README.md
```

---

## PowerShell module (advanced)

```powershell
Import-Module .\AppGetter.psd1

Get-WebDownloadLinks -WebsiteUrl 'https://example.com/download'
Invoke-AppGetterPackaging -AppName 'MyApp' -DownloadUrl 'https://example.com/setup.exe' -OutputPath 'C:\Out'
```

---

## Troubleshooting

| Problem | What to try |
|---------|-------------|
| `intunewinapputil` not found | Install the [Content Prep Tool](https://github.com/microsoft/Microsoft-Win32-Content-Prep-Tool) and add it to PATH |
| No download links found | Use **Find Links** in the GUI or pass `-DownloadUrl` with a direct installer URL |
| Packaging failed | Check `appgetter-packaging.log` in the version output folder and the GUI log panel |
| Wrong icon | Use the icon picker after packaging, or set a custom PNG before packaging |
| Detection fails on devices | Run `detection.ps1` locally; review Intune Management Extension logs |
| GUI won't start | Run from PowerShell 5.1+ on Windows; WPF requires a desktop session |

See also [Troubleshooting-Guide.md](Troubleshooting-Guide.md).

---

## License

Provided as-is for creating Intune Win32 packages from web-based application downloads.
