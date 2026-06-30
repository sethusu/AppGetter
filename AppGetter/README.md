# AppGetter - IntuneWin Package Creator from Web Downloads

AppGetter now mirrors the WinGetter operating model: a PowerShell-first toolchain with GUI entry, CLI support, generated install/detection/uninstall scripts, and direct `intunewinapputil` packaging.

## What you get per package

- `{InstallerBaseName}.intunewin`
- `install.ps1`
- `detection.ps1`
- `uninstall.ps1`
- `README.md` and `readme.txt`
- `app.json` and `win32LobApp.json`
- `icon.png` (when available)

## Requirements

1. **Windows 10/11** (desktop session for GUI mode)
2. **PowerShell 5.1+ / PowerShell 7+**
3. **Microsoft Win32 Content Prep Tool** available as `intunewinapputil`

## Quick start (GUI - recommended)

From the `AppGetter` folder:

```powershell
.\Start-AppGetter.ps1
```

Or directly:

```powershell
.\Create-IntuneWinFromWeb.ps1
```

No parameters opens the desktop GUI, similar to WinGetter workflow.

## Quick start (CLI)

```powershell
.\Create-IntuneWinFromWeb.ps1 -AppName "SIMION" -WebsiteUrl "https://simion.com/"
```

Direct URL mode:

```powershell
.\Create-IntuneWinFromWeb.ps1 `
  -AppName "MyApp" `
  -DownloadUrl "https://example.com/setup.exe" `
  -Version "1.0.0"
```

## CLI parameters

- `WebsiteUrl` - Website that contains a download link
- `DownloadUrl` - Direct installer URL
- `AppName` - Display name used in generated artifacts
- `Version` - Optional explicit version (falls back to detected/`latest`)
- `Publisher` - Optional publisher label
- `DeveloperUrl` - Optional vendor website
- `SupportUrl` - Optional support/docs page
- `OutputPath` - Optional output root (persisted in settings)
- `IconPath` - Optional custom icon path
- `InstallCommand` - Optional installer command override
- `UseGui` - Force GUI launch
- `NoGui` - Keep CLI mode when no other arguments are provided

## Behavior notes

- `install.ps1` runs the resolved silent install command and returns installer exit codes for Intune handling.
- `detection.ps1` and `uninstall.ps1` are registry-driven and do not require Python or Winget on endpoints.
- AppGetter writes and reuses output-path settings in `%AppData%\AppGetter\settings.json` (Windows) or a home-directory fallback.
- Packaging requires `intunewinapputil`; AppGetter fails early if it is missing.

## Output layout

```text
{OutputPath}\{PackageId}\{Version}\
  ├── {InstallerFileName}
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

## Troubleshooting highlights

- If no links are discovered from `WebsiteUrl`, provide `DownloadUrl`.
- If the installer needs non-default silent switches, pass `InstallCommand`.
- If detection fails in Intune, run `detection.ps1` manually and inspect `%ProgramData%\Microsoft\IntuneManagementExtension\Logs\`.
- If packaging fails, verify `Get-Command intunewinapputil`.
