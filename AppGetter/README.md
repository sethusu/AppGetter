# AppGetter

PowerShell-only Intune Win32 packaging from web installers.

AppGetter now mirrors WinGetter-style outputs without a Python backend. It downloads an installer from a direct URL (or discovers one from a website), generates packaging scripts and metadata, and invokes `intunewinapputil`.

## What it generates

For each app:

- `{Installer}.intunewin`
- `install.ps1`
- `detection.ps1`
- `uninstall.ps1`
- `README.md`
- `readme.txt`
- `app.json`
- `win32LobApp.json`
- `logo.png` / `icon.png` (if provided or discovered)

## Requirements

1. PowerShell 5.1+ (or PowerShell 7+).
2. Microsoft Win32 Content Prep Tool on PATH as `intunewinapputil`.
3. Internet access for website/installer download.

## Quick start

```powershell
pwsh -NoProfile -File .\Create-IntuneWinFromWeb.ps1 `
  -DownloadUrl "https://example.com/installer.msi" `
  -AppName "Example App" `
  -Publisher "Example Corp" `
  -OutputPath "C:\IntunePackages"
```

Website discovery flow:

```powershell
pwsh -NoProfile -File .\Create-IntuneWinFromWeb.ps1 `
  -WebsiteUrl "https://vendor.example/downloads" `
  -AppName "Example App"
```

## Parameters

- `WebsiteUrl`: Website containing installer links.
- `DownloadUrl`: Direct installer URL (`.exe`, `.msi`, `.msix`, `.appx`).
- `AppName`: Package display name.
- `Version`: Optional fixed version override.
- `Publisher`: Optional publisher metadata value.
- `OutputPath`: Optional output root; defaults to saved settings.
- `IconPath`: Optional icon copied as both `logo.png` and `icon.png`.
- `InstallCommand`: Optional raw installer command for generated `install.ps1`.

## Output layout

```text
{OutputPath}/
└── {PackageId}/
    ├── logo.png
    ├── {InstallerBaseName}.intunewin
    └── {Version}/
        ├── installer.ext
        ├── install.ps1
        ├── detection.ps1
        ├── uninstall.ps1
        ├── README.md
        ├── readme.txt
        ├── app.json
        ├── win32LobApp.json
        └── icon.png
```

## Notes

- `install.ps1` wraps the raw installer command and normalizes Intune return codes.
- Detection is registry-based and does not require winget/Python on endpoints.
- If `intunewinapputil` is missing, script/metadata files are still produced.
