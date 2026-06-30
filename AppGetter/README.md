# AppGetter v2.0 - Backend, Silent Switch Discovery, and Desktop UI

AppGetter automates Intune Win32 package creation from web installers. Version 2 adds a persistent download location, silent install switch analysis/discovery, a REST API backend, and a Windows 11-style desktop UI.

## What's New in v2.0

- **Configurable download location** — save and validate where installers are stored (`%LOCALAPPDATA%\AppGetter\config.json`)
- **Silent switch analysis** — detect MSI, NSIS, Inno Setup, InstallShield, and WiX frameworks
- **Switch discovery pipeline** — documentation research, help probing (`/?`, `--help`), and optional live testing
- **ASP.NET Core API** — `http://localhost:5050` with Swagger
- **WinUI 3 desktop app** — modern navigation, Mica backdrop, Settings and Installer Analysis pages

## Architecture

```
WinUI 3 Desktop App (AppGetter.App)
        |
        v
ASP.NET Core API (AppGetter.Api)  :5050
        |
        +-- ConfigService (download/output paths)
        +-- InstallerAnalysisService (framework detect, research, test)
        |
PowerShell Modules (AppGetter/Modules)
        |
Create-IntuneWinFromWeb.ps1 (original CLI workflow)
```

## Prerequisites

| Component | Requirement |
|-----------|-------------|
| OS | Windows 10/11 (desktop UI and installer testing) |
| PowerShell | 5.1+ (script and modules) |
| .NET SDK | 8.0+ (API and WinUI app) |
| Windows App SDK | Installed with WinUI project restore |
| Content Prep Tool | `intunewinapputil` in PATH (packaging only) |

## Quick Start (Desktop UI)

```powershell
cd AppGetter
.\Start-AppGetter.ps1
```

This builds (if needed), starts the API, and launches the WinUI app.

### API only

```powershell
.\Start-AppGetterApi.ps1
```

Swagger UI: http://localhost:5050/swagger

## Settings — Download Location

Use **Settings** in the desktop app or the API:

```http
GET  /api/config
PUT  /api/config
POST /api/config/validate-path
```

Config is stored at:

```
%LOCALAPPDATA%\AppGetter\config.json
```

Default download path: `%USERPROFILE%\Downloads\AppGetter`

## Installer Analysis

### Desktop UI

1. Open **Installer Analysis**
2. Enter a download URL or upload an installer
3. Optionally add a support/documentation URL for web research
4. Click **Analyze switches** (safe) or **Discover switches** (probes help + optional live tests)
5. Review candidates and the recommended install command

### PowerShell module

```powershell
.\Test-InstallerSwitches.ps1 -InstallerPath C:\Downloads\setup.exe -SupportUrl https://vendor.com/docs -ProbeHelp
```

### API

```http
POST /api/installers/analyze
POST /api/installers/discover
POST /api/installers/upload
POST /api/installers/download
```

Example analyze request:

```json
{
  "installerPath": "C:\\Users\\you\\Downloads\\AppGetter\\setup.exe",
  "supportUrl": "https://vendor.com/silent-install",
  "probeHelp": true,
  "testInstall": false,
  "dryRun": true
}
```

### Switch discovery methods

| Method | Description |
|--------|-------------|
| Framework detection | Binary signatures for NSIS, Inno, InstallShield, WiX |
| Known switch database | Per-framework defaults (e.g. `/VERYSILENT` for Inno) |
| Web research | Scrapes support URLs for switch documentation |
| Help probe | Runs `/?`, `--help`, etc. and parses output |
| Live testing | Optional; runs installer with candidate switches (use a VM) |

## Original CLI Script

The original workflow still works and now uses modules when present:

```powershell
.\Create-IntuneWinFromWeb.ps1 -WebsiteUrl "https://simion.com/" -AppName "SIMION" -SupportUrl "https://simion.com/info/"
```

New parameter: `-SupportUrl` for silent switch research.

## Project Layout

```
AppGetter/
├── Modules/
│   ├── AppGetter.Config/
│   ├── AppGetter.SilentSwitch/
│   └── AppGetter.Core/
├── src/
│   ├── AppGetter.sln
│   ├── AppGetter.Api/          # REST backend
│   ├── AppGetter.App/          # WinUI 3 desktop UI
│   └── AppGetter.Shared/       # Shared models
├── Create-IntuneWinFromWeb.ps1
├── Start-AppGetter.ps1
├── Start-AppGetterApi.ps1
└── Test-InstallerSwitches.ps1
```

## Build from Source (Windows)

```powershell
cd AppGetter\src
dotnet build AppGetter.sln -c Release
```

## Safety Notes

- **Dry-run** is enabled by default for switch testing
- **Live installer tests** can install software on the host — use a VM or snapshot
- MSI live tests are skipped; use `msiexec` in a controlled environment
- Help probing and framework detection are read-only and safe

## License

Provided as-is for creating IntuneWin packages from web-based application downloads.
