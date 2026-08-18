# AppGetter

**Turn a download URL or a local installer into an Intune Win32 package in minutes.**

AppGetter mirrors [WinGetter](https://github.com/sethusu/WinGetter) (Wingetter): the same WPF GUI, the same Content Prep Tool checks, the same output-folder dialog, and the same `.intunewin` packaging. The difference is the installer source — AppGetter uses a **direct download URL** or an **installer file already on this computer**, instead of Winget search.

Built for IT admins and packaging teams who need repeatable Win32 app onboarding for software that is not in Winget.

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
| **[Win32 Content Prep Tool](https://github.com/microsoft/Microsoft-Win32-Content-Prep-Tool)** | `intunewinapputil` on PATH — install with `winget install --exact --id Microsoft.Win32ContentPrepTool` or the GUI **Install Content Prep** button |

Run the built-in check from PowerShell:

```powershell
cd AppGetter
Import-Module .\AppGetter.psd1
Test-AppGetterPrerequisites
# If Content Prep Tool is missing:
Install-AppGetterContentPrepTool
```

---

## Quick start (GUI — recommended)

### Option A — Double-click `AppGetter.exe` (easiest)

1. On a Windows machine, build once from the repo:

```powershell
cd AppGetter
.\Build\Build-AppGetterExe.ps1
```

2. Open `dist\AppGetter\` (or unzip `dist\AppGetter-portable.zip` on another PC).
3. Double-click **AppGetter.exe** — no elevated PowerShell required.
4. Keep the whole folder together (`Gui\`, `Private\`, `AppGetter.psd1` must stay next to the exe).

The exe is a thin stub that starts the GUI in Windows PowerShell 5.1 (separate process).

From the source tree without building, you can also double-click `AppGetter\Start-AppGetter.cmd`.

### Option B — Run from PowerShell

1. **Clone or download** this repository.
2. Open **PowerShell** (not necessarily elevated).
3. Run:

```powershell
cd AppGetter
.\Create-IntuneWinFromWeb.ps1
```

Or launch the GUI directly:

```powershell
.\Gui\Start-AppGetterGui.ps1
```

4. Enter the **application name**.
5. Choose **Download URL** and paste the installer URL, **or** choose **Local installer** and **Browse...** to a file on this computer.
6. Choose an **output folder** (default base: `Documents\AppGetter`; each app uses a subfolder named after the app).
7. Click **Create Package** and wait for the progress steps to finish.
8. Open the output folder and upload the `.intunewin` to Intune using the included `README.md` as your field guide.

---

## Quick start (CLI)

For scripting or automation:

```powershell
cd AppGetter

# Package from a direct download URL
.\Create-IntuneWinFromWeb.ps1 -DownloadUrl "https://example.com/installer.exe" -AppName "MyApp" -Version "1.0.0"

# Package from an installer already on this computer
.\Create-IntuneWinFromWeb.ps1 -InstallerPath "C:\Installers\setup.exe" -AppName "MyApp" -Publisher "MyCompany"

# Package from a website (scans for download links)
.\Create-IntuneWinFromWeb.ps1 -WebsiteUrl "https://simion.com/" -AppName "SIMION" -Publisher "Adaptas Solutions, LLC"

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

Existing installs that stored `Documents\AppGetter Output` are migrated to `Documents\AppGetter`.

---

## GUI features

- **Download URL or local installer** — paste a URL, or Browse to an `.exe` / `.msi` / `.msix` / `.appx` on this computer
- **Live progress** — step list, progress bar, and log panel (packaging runs in the background so the window stays responsive)
- **Output destination** — same folder picker as WinGetter (My Computer root, new-folder button, parented to the main window)
- **Install Content Prep** — appears in the header when `intunewinapputil` is missing; installs `Microsoft.Win32ContentPrepTool` via winget
- **Custom icon** — browse for your own PNG before packaging
- **Open output folder** when done

---

## Parameters

| Parameter | Description |
|-----------|-------------|
| **WebsiteUrl** | URL to scan for download links |
| **DownloadUrl** | Direct download URL (skips website scanning) |
| **InstallerPath** | Path to an installer already on this computer |
| **AppName** | Application display name |
| **Version** | Optional version (auto-detected from website or file version if omitted) |
| **Publisher** | Publisher name |
| **DeveloperUrl** | Optional developer site for logo/description lookup |
| **SupportUrl** | Optional docs page for silent install switch discovery |
| **OutputPath** | Base output directory. Defaults to `Documents\AppGetter`; each package is written to `{OutputPath}\{PackageId}\` |
| **IconPath** | Custom PNG icon |
| **InstallCommand** | Custom install command (auto-detected if omitted) |
| **UseGui** | Launch the WPF GUI |

---

## Building AppGetter.exe (ps2exe)

On Windows:

```powershell
.\Build\Build-AppGetterExe.ps1
```

This installs the Gallery `ps2exe` module (CurrentUser) if needed, stages runtime files under `..\dist\AppGetter\`, compiles `Launch-AppGetter.ps1` to `AppGetter.exe` (no console, no admin manifest), and creates `..\dist\AppGetter-portable.zip`.

The `.exe` is a thin stub: it starts `Gui\Start-AppGetterGui.ps1` in a separate Windows PowerShell 5.1 process. Launch uses `-EncodedCommand` so folders with spaces work, and writes `%TEMP%\AppGetter-launch.log`.

To diagnose on Windows without rebuilding:

```powershell
.\Build\Diagnose-AppGetterLaunch.ps1
.\Build\Diagnose-AppGetterLaunch.ps1 -StartGui
```

---

## Repository layout

```
AppGetter/
├── README.md                          ← You are here
├── Launch-AppGetter.ps1               ← ps2exe / double-click launcher
├── Start-AppGetter.cmd                ← Source-tree double-click helper
├── Build/
│   └── Build-AppGetterExe.ps1         ← Compiles AppGetter.exe with ps2exe
├── Create-IntuneWinFromWeb.ps1         ← CLI entry point (no args = GUI)
├── Gui/
│   ├── Start-AppGetterGui.ps1
│   └── AppGetter.MainWindow.xaml      ← WPF UI
├── AppGetter.psm1                     ← Core module
├── Private/                           ← Packaging, web download, icons, scripts
└── Tests/
```

---

## PowerShell module (advanced)

```powershell
Import-Module .\AppGetter\AppGetter.psd1

Find-WebDownloadLinks -Url 'https://simion.com/' -AppName 'SIMION'
Invoke-AppGetterPackaging -AppName 'MyApp' -DownloadUrl 'https://example.com/setup.exe' -OutputPath 'C:\Out'
Invoke-AppGetterPackaging -AppName 'MyApp' -InstallerPath 'C:\Installers\setup.exe' -OutputPath 'C:\Out'
Test-AppGetterPrerequisites
Install-AppGetterContentPrepTool
```

---

## Tests

```powershell
.\Run-Tests.ps1
.\Build\Test-PackagingScripts.ps1   # launcher / build script sanity checks
```

---

## Troubleshooting

| Problem | What to try |
|---------|-------------|
| `intunewinapputil` not found | Click **Install Content Prep** in the GUI, run `Install-AppGetterContentPrepTool`, or `winget install --exact --id Microsoft.Win32ContentPrepTool` |
| No download links found | Provide a direct `-DownloadUrl` or `-InstallerPath` instead of `-WebsiteUrl` |
| Packaging failed | Check `appgetter-packaging.log` in the version output folder and the GUI log panel |
| Detection fails on devices | Run `detection.ps1` locally; review logs in `%ProgramData%\Microsoft\IntuneManagementExtension\Logs\` |
| GUI won't start | Double-click `AppGetter.exe` from a built `dist\AppGetter` folder, or run from PowerShell 5.1+ on Windows; WPF requires a desktop session |
| Antivirus blocks `AppGetter.exe` | ps2exe wrappers are occasionally flagged; build from source with `.\Build\Build-AppGetterExe.ps1` or use `Start-AppGetter.cmd` / the `.ps1` entry points |

More detail: [Troubleshooting-Guide.md](Troubleshooting-Guide.md)

---

## License

Provided as-is for creating Intune Win32 packages from web downloads or local installers.
