# AppGetter (PowerShell-only)

**Turn direct web installer URLs into Intune Win32 packages with WinGetter-style outputs.**

AppGetter now mirrors the packaging behavior and output shape of WinGetter while keeping web download as the source. There is no Python backend or background service.

## What you get

For each app package:

- `{InstallerBase}.intunewin` (when `intunewinapputil` is available)
- `install.ps1`
- `detection.ps1`
- `uninstall.ps1`
- `README.md` (field-by-field Intune upload reference)
- `readme.txt` (legacy summary)
- `app.json`
- `win32LobApp.json`
- `logo.png` / `icon.png` (when found or supplied)

## Requirements

1. Windows PowerShell 5.1+ (or PowerShell 7+ on Windows)
2. Microsoft Win32 Content Prep Tool on PATH (`intunewinapputil`)
3. Internet access to fetch the installer URL

## Quick start

Run interactive mode:

```powershell
.\Create-IntuneWinFromWeb.ps1
```

Run non-interactive mode:

```powershell
.\Create-IntuneWinFromWeb.ps1 `
  -AppName "SIMION" `
  -DownloadUrl "https://example.com/simion-setup.exe" `
  -Publisher "Adaptas Solutions, LLC" `
  -OutputPath "C:\IntunePackages"
```

Website discovery mode:

```powershell
.\Create-IntuneWinFromWeb.ps1 `
  -AppName "SIMION" `
  -WebsiteUrl "https://simion.com/download"
```

## Launcher

`Start-AppGetter.ps1` is now a pure PowerShell wrapper over the packaging script:

```powershell
.\Start-AppGetter.ps1 -AppName "SIMION" -DownloadUrl "https://example.com/setup.exe"
```

## Output layout

```text
{OutputPath}\
└── {PackageId}\
    ├── logo.png
    └── {Version}\
        ├── installer.exe|msi|msix|appx
        ├── install.ps1
        ├── detection.ps1
        ├── uninstall.ps1
        ├── README.md
        ├── readme.txt
        ├── app.json
        ├── win32LobApp.json
        ├── icon.png
        └── ..\installer.intunewin
```

## Notes

- EXE installers default to `"/S"` unless you provide `-InstallCommand`.
- Packaging continues even when `intunewinapputil` is missing; metadata/scripts are still generated.
- Settings are persisted at `%AppData%\AppGetter\settings.json` for the last-used output and source inputs.
