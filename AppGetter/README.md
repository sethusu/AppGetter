# AppGetter

**Turn any installer — a download link or a file already on your PC — into an Intune Win32 package.**

AppGetter is the [WinGetter](https://github.com/sethusu/WinGetter) (Wingetter) workflow with a different
front door. Wingetter packages what it finds in Winget; AppGetter packages **the URL you paste** or **the
installer sitting on the computer running it**. Everything after that is the same: `.intunewin` packaging
with the Microsoft Win32 Content Prep Tool, the same prerequisite checks, the same output location
dialog, and the same generated install/detection/uninstall scripts and Intune upload guide.

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

---

## Requirements

| Requirement | Notes |
|-------------|-------|
| **Windows 10/11** | PowerShell 5.1 or later |
| **[Win32 Content Prep Tool](https://github.com/microsoft/Microsoft-Win32-Content-Prep-Tool)** | `intunewinapputil` must be on your PATH — the GUI can install it for you via winget |
| **Internet access** | Only when packaging from a download URL or website |

The GUI checks prerequisites on startup. If the Content Prep Tool is missing, an **Install Content Prep**
button appears in the header and runs `winget install --exact --id Microsoft.Win32ContentPrepTool`.

From PowerShell:

```powershell
cd AppGetter
Import-Module .\AppGetter.psd1
Test-AppGetterPrerequisites
```

---

## Quick start (executable — recommended)

Build a portable, double-clickable `AppGetter.exe` on a Windows machine:

```powershell
cd AppGetter
.\Build\Build-AppGetterExe.ps1
```

This stages `dist\AppGetter\` (and `dist\AppGetter-portable.zip`) containing `AppGetter.exe` next to
`Gui\`, `Private\`, and `AppGetter.psd1`. Share the folder or zip — end users double-click
**AppGetter.exe**; no admin PowerShell session is required.

If you would rather not build anything, double-click **`Start-AppGetter.cmd`** in the source tree, or run:

```powershell
.\Launch-AppGetter.ps1
```

Launch problems are logged to `%TEMP%\AppGetter-launch.log`; run `.\Build\Diagnose-AppGetterLaunch.ps1`
to print resolved paths, parse checks, and prerequisites.

---

## Using the GUI

1. Pick an **installer source**:
   - **Download URL** — paste a direct link to the installer.
   - **Local file on this computer** — click **Browse...** and choose an `.exe`, `.msi`, `.msix`, or `.appx`.
   - **Website (scan for links)** — enter a product page and click **Find Links...** to choose from the
     download links found.
2. Enter the **application name** (required), plus optional publisher and version.
3. Choose the **output destination**. Each app is packaged into its own subfolder:
   `{base}\{PackageId}\{Version}`. The base folder is remembered between runs.
4. Optionally expand **Optional details** for developer/support URLs and an install command override.
5. Click **Create Package** and watch the step list, progress bar, and log.
6. When packaging finishes, pick the best **icon** if more than one candidate was found, then click
   **Open Output Folder** and upload the `.intunewin` using the generated `README.md` as your field guide.

---

## Quick start (CLI)

For scripting or automation:

```powershell
cd AppGetter

# Package from a direct download URL
.\Create-IntuneWinFromWeb.ps1 -DownloadUrl "https://example.com/installer.exe" -AppName "MyApp" -Version "1.0.0"

# Package an installer that is already on this computer
.\Create-IntuneWinFromWeb.ps1 -InstallerPath "C:\Installers\setup.exe" -AppName "MyApp"

# Package from a website (scans for download links)
.\Create-IntuneWinFromWeb.ps1 -WebsiteUrl "https://simion.com/" -AppName "SIMION" -Publisher "Adaptas Solutions, LLC"

# Custom output path and icon
.\Create-IntuneWinFromWeb.ps1 -DownloadUrl "https://example.com/setup.exe" -AppName "MyApp" `
    -OutputPath "C:\IntunePackages" `
    -IconPath "C:\Icons\myapp.png"
```

Running `.\Create-IntuneWinFromWeb.ps1` with no arguments launches the GUI.

---

## Typical Intune workflow

1. **Package** the app with AppGetter on a Windows machine that has the Content Prep Tool installed.
2. **Review** the generated `README.md` in the version folder — it lists install command, detection method,
   publisher, description, installer source, and return codes.
3. **Upload** the `.intunewin` file in **Intune** → **Apps** → **Windows** → **Add** → **Windows app (Win32)**.
4. **Fill in** portal fields using the generated reference (or `win32LobApp.json` as a starting point).
5. **Assign** the app to a test group before broad rollout.
6. **Validate** on a pilot device — check `%ProgramData%\Microsoft\IntuneManagementExtension\Logs\` for
   install/detection logs.

---

## Output folder layout

```
Documents\AppGetter\
└── SIMION\
    ├── logo.png
    ├── simion-setup.intunewin
    └── 8.2.1.3\
        ├── simion-setup.exe
        ├── install.ps1
        ├── detection.ps1
        ├── uninstall.ps1
        ├── README.md                 ← Intune upload cheat sheet
        ├── readme.txt
        ├── app.json
        ├── win32LobApp.json
        └── icon.png
```

Default output path and last-used settings are saved to:

`%AppData%\AppGetter\settings.json`

---

## Parameters

| Parameter | Description |
|-----------|-------------|
| **DownloadUrl** | Direct download URL for the installer |
| **InstallerPath** | Installer already present on this computer (wins over the URL options) |
| **WebsiteUrl** | Page to scan for download links |
| **AppName** | Application display name |
| **Version** | Optional version (auto-detected from the installer or website if omitted) |
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
├── AppGetter.exe                       ← built by Build\Build-AppGetterExe.ps1 into dist\
├── Launch-AppGetter.ps1                ← GUI entry point (also the ps2exe input)
├── Start-AppGetter.cmd                 ← double-click helper for the source tree
├── Create-IntuneWinFromWeb.ps1         ← CLI entry point (no args = GUI)
├── AppGetter.psm1 / AppGetter.psd1     ← Core module
├── Private/                            ← Packaging, source resolution, icons, scripts, settings
├── Gui/
│   ├── Start-AppGetterGui.ps1
│   ├── AppGetter.MainWindow.xaml
│   ├── AppGetter.LinkPickerDialog.xaml
│   └── AppGetter.IconPickerDialog.xaml
├── Build/
│   ├── Build-AppGetterExe.ps1
│   └── Diagnose-AppGetterLaunch.ps1
├── Tests/                              ← Pester suites
└── Run-Tests.ps1
```

---

## PowerShell module (advanced)

```powershell
Import-Module .\AppGetter\AppGetter.psd1

Find-WebDownloadLinks -Url 'https://simion.com/' -AppName 'SIMION'
Invoke-AppGetterPackaging -AppName 'MyApp' -DownloadUrl 'https://example.com/setup.exe' -OutputPath 'C:\Out'
Invoke-AppGetterPackaging -AppName 'MyApp' -InstallerPath 'C:\Installers\setup.exe' -OutputPath 'C:\Out'
```

---

## Tests

```powershell
.\Run-Tests.ps1
```

Pester 5+ is installed automatically if missing. The suites cover output path helpers, installer source
resolution, end-to-end packaging from a local file, and the GUI/executable contract (XAML control names,
module exports, and staged build files).

---

## Troubleshooting

| Problem | What to try |
|---------|-------------|
| `intunewinapputil` not found | Click **Install Content Prep** in the GUI, or install the [Content Prep Tool](https://github.com/microsoft/Microsoft-Win32-Content-Prep-Tool) and add it to PATH |
| No download links found | Switch the source to **Download URL** and paste a direct link |
| Packaging failed | Check `appgetter-packaging.log` in the version output folder and the GUI log panel |
| Detection fails on devices | Run `detection.ps1` locally; review logs in `%ProgramData%\Microsoft\IntuneManagementExtension\Logs\` |
| `AppGetter.exe` does nothing | Check `%TEMP%\AppGetter-launch.log`, then run `.\Build\Diagnose-AppGetterLaunch.ps1` |
| Antivirus blocks the exe | Use `Start-AppGetter.cmd` or `Launch-AppGetter.ps1` instead |
| GUI won't start | Run from PowerShell 5.1+ on Windows; WPF requires a desktop session |

More detail: [Troubleshooting-Guide.md](Troubleshooting-Guide.md)

---

## License

Provided as-is for creating Intune Win32 packages from application installers.
