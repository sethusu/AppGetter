# AppGetter - IntuneWin Package Creator from Web Downloads

**Turn web installers into Intune Win32 packages in minutes.**

AppGetter automates packaging desktop software from web downloads for Microsoft Intune: downloading the installer, generating `install.ps1` / `detection.ps1` / `uninstall.ps1`, resolving an app icon, building the `.intunewin` file with the Microsoft Win32 Content Prep Tool, and writing a field-by-field Intune upload guide.

Built for IT admins who need repeatable Win32 app onboarding from vendor websites without hand-writing detection scripts for every app.

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
| **Windows 10/11** (recommended) | PowerShell 5.1 or later; packaging and icon extraction work best on Windows |
| **[Win32 Content Prep Tool](https://github.com/microsoft/Microsoft-Win32-Content-Prep-Tool)** | `intunewinapputil` must be on your PATH |

Run the built-in prerequisite check:

```powershell
cd AppGetter
Import-Module .\AppGetter.psd1
Test-AppGetterPrerequisites
```

No Python, Flask, or other background services are required.

---

## Quick start (CLI)

```powershell
cd AppGetter

# Direct download URL
.\Create-IntuneWinFromWeb.ps1 -DownloadUrl "https://example.com/setup.exe" -AppName "MyApp"

# Scan a website for download links
.\Create-IntuneWinFromWeb.ps1 -WebsiteUrl "https://simion.com/" -AppName "SIMION" -Publisher "Adaptas Solutions, LLC"

# Interactive mode (input dialogs)
.\Create-IntuneWinFromWeb.ps1
```

---

## PowerShell module (advanced)

```powershell
Import-Module .\AppGetter\AppGetter.psd1

Invoke-AppGetterPackaging `
    -AppName "MyApp" `
    -DownloadUrl "https://example.com/setup.exe" `
    -OutputPath "C:\IntunePackages"

Invoke-InstallerSwitchAnalysis -InstallerPath "C:\temp\setup.exe" -AppName "MyApp"
```

---

## Parameters

| Parameter | Description |
|-----------|-------------|
| `WebsiteUrl` | Website to scan for `.exe`, `.msi`, `.msix`, or `.appx` download links |
| `DownloadUrl` | Direct download URL (skips website scanning) |
| `AppName` | Application display name |
| `Version` | Optional version override (auto-detected from website when possible) |
| `Publisher` | Publisher name |
| `DeveloperUrl` | Optional site used for icon/description discovery |
| `SupportUrl` | Optional documentation URL scanned for silent install switches |
| `OutputPath` | Base output folder (default: `Documents\AppGetter Output`) |
| `IconPath` | Custom PNG icon |
| `InstallCommand` | Custom raw installer command |
| `AllowRuntimeProbe` | Probe EXE help output on Windows for silent switches |

---

## Output folder layout

```
Documents\AppGetter Output\
└── MyApp\
    ├── logo.png
    └── 1.0.0\
        ├── setup.exe
        ├── install.ps1
        ├── detection.ps1
        ├── uninstall.ps1
        ├── README.md
        ├── readme.txt
        ├── app.json
        ├── win32LobApp.json
        ├── icon.png
        └── ..\setup.intunewin
```

Default output path and last-used settings are saved to:

`%AppData%\AppGetter\settings.json`

---

## Silent switch discovery

AppGetter discovers install switches in pure PowerShell:

1. Known patterns by installer type (MSI, MSIX, APPX)
2. EXE bootstrap family detection (Inno Setup, NSIS, InstallShield, WiX)
3. Documentation page scanning (`SupportUrl`, `WebsiteUrl`, `DeveloperUrl`)
4. Optional runtime probe (`-AllowRuntimeProbe` on Windows)

---

## Typical Intune workflow

1. Package the app with AppGetter on a Windows machine with the Content Prep Tool installed.
2. Review the generated `README.md` in the version folder.
3. Upload the `.intunewin` file in **Intune** → **Apps** → **Windows** → **Add** → **Windows app (Win32)**.
4. Fill in portal fields using the generated reference (or `win32LobApp.json` as a starting point).
5. Assign to a test group and validate on a pilot device.

---

## Repository layout

```
AppGetter/
├── Create-IntuneWinFromWeb.ps1   ← CLI entry point
├── AppGetter.psd1                ← Module manifest
├── AppGetter.psm1                ← Module loader
├── Private/
│   ├── Packaging.ps1             ← Main packaging workflow
│   ├── WebDownload.ps1           ← Download link discovery and download
│   ├── SwitchDiscovery.ps1       ← Silent switch analysis
│   ├── Scripts.ps1               ← install/detection/uninstall/readme generation
│   ├── IconResolution.ps1        ← Icon download and EXE extraction
│   ├── Settings.ps1              ← Persistent settings and prerequisites
│   └── ...
└── README.md
```

---

## Troubleshooting

| Problem | What to try |
|---------|-------------|
| `intunewinapputil` not found | Install the [Content Prep Tool](https://github.com/microsoft/Microsoft-Win32-Content-Prep-Tool) and add it to PATH |
| No download links found | Provide `-DownloadUrl` with a direct installer link |
| Packaging failed | Check `appgetter-packaging.log` in the version output folder |
| Detection fails on devices | Run `detection.ps1` locally; review `%ProgramData%\Microsoft\IntuneManagementExtension\Logs\` |

See also `Troubleshooting-Guide.md`.

---

## License

Provided as-is for creating Intune Win32 packages from web-based application downloads.
