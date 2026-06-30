# AppGetter

AppGetter now mirrors WinGetter-style packaging behavior, but for direct web installers and without any Python backend.

It generates:

- `{Installer}.intunewin` (when `intunewinapputil` is available)
- `install.ps1`
- `detection.ps1`
- `uninstall.ps1`
- `README.md` (Intune field-by-field upload guide)
- `readme.txt`
- `app.json`
- `win32LobApp.json`
- `icon.png` / `logo.png` (if provided or already present)

## Requirements

1. PowerShell 5.1+ (or PowerShell 7+)
2. Microsoft Win32 Content Prep Tool (`intunewinapputil`) on `PATH`
3. Internet access to download installer files

No Python runtime is required.

## Quick Start

### Interactive mode (Windows desktop)

```powershell
.\Create-IntuneWinFromWeb.ps1
```

### CLI mode (recommended for automation / non-Windows hosts)

```powershell
.\Create-IntuneWinFromWeb.ps1 `
  -DownloadUrl "https://example.com/installer.exe" `
  -AppName "Example.App" `
  -Publisher "Example Corp" `
  -OutputPath "C:\IntunePackages"
```

You can also use website discovery:

```powershell
.\Create-IntuneWinFromWeb.ps1 `
  -WebsiteUrl "https://example.com/downloads" `
  -AppName "Example.App"
```

## Parameters

- `WebsiteUrl` (optional): page used to discover installer links and metadata
- `DownloadUrl` (optional): direct installer URL
- `AppName` (required): display name / package label
- `Version` (optional): explicit version override
- `Publisher` (optional): publisher string for metadata
- `OutputPath` (optional): output root (saved in `%AppData%\AppGetter\settings.json`)
- `IconPath` (optional): path to custom icon (copied as `logo.png` and `icon.png`)
- `InstallCommand` (optional): raw installer command used inside `install.ps1`

## Output Layout

```text
{OutputPath}/
└── {PackageId}/
    ├── logo.png (optional)
    └── {Version}/
        ├── {InstallerFile}
        ├── install.ps1
        ├── detection.ps1
        ├── uninstall.ps1
        ├── README.md
        ├── readme.txt
        ├── app.json
        ├── win32LobApp.json
        ├── icon.png (optional)
        └── ..\{InstallerBaseName}.intunewin
```

## Notes

- On Linux/macOS, run non-interactively with `-AppName` and `-DownloadUrl` or `-WebsiteUrl`.
- If `intunewinapputil` is unavailable, AppGetter still generates all scripts/metadata and prints a packaging warning.
- `README.md` is intended to be a direct Intune upload checklist.
