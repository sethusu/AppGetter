# AppGetter v2.0

AppGetter automates Intune Win32 package creation from web-based installer downloads. Version 2.0 adds a local REST API backend and a Windows 11-style web UI for managing downloads, analyzing installers, and discovering silent install switches.

## What's New in v2.0

- **Configurable download location** — Set where installers are saved via Settings or the API
- **Installer analysis** — Detect installer type (NSIS, Inno Setup, MSI, etc.) and test whether silent switches are known
- **Silent switch discovery** — Research documentation, probe installer help text, and rank candidate switches
- **Modern web UI** — Windows 11 Fluent Design interface served locally at `http://localhost:8765`
- **REST API** — Programmatic access to all features for automation

## Quick Start

```powershell
# Launch the web UI (opens browser automatically)
.\Start-AppGetter.ps1

# Custom port, no browser
.\Start-AppGetter.ps1 -Port 9000 -NoBrowser
```

The UI opens at `http://localhost:8765` by default.

## Architecture

```
AppGetter/
├── Start-AppGetter.ps1              # Application launcher
├── AppGetter.Core/                  # PowerShell module (installer logic)
│   ├── AppGetter.Core.psm1
│   └── Data/known-installers.json   # Installer signature database
├── AppGetter.Server/                # Local HTTP server + REST API
│   └── Start-AppGetterServer.ps1
├── AppGetter.UI/                    # Windows 11 web interface
│   ├── index.html
│   ├── css/app.css
│   └── js/app.js
└── Create-IntuneWinFromWeb.ps1      # Original Intune packaging script
```

## Web UI Pages

| Page | Purpose |
|------|---------|
| **Dashboard** | Overview of download location, installer count, recent files |
| **Download** | Download from URL, scan websites for links, upload installers |
| **Analyze** | Test if silent install switches are known for an installer |
| **Discover Switches** | Research docs and probe installer to find silent switches |
| **Settings** | Configure download location, output path, discovery preferences |

## REST API

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/api/health` | Server status |
| GET | `/api/config` | Get configuration |
| PUT | `/api/config` | Update configuration |
| POST | `/api/download-links` | Scan a website for download links |
| POST | `/api/download` | Download an installer |
| GET | `/api/installers` | List installers in download location |
| POST | `/api/upload` | Upload an installer file |
| POST | `/api/analyze` | Analyze installer and test silent switches |
| POST | `/api/discover-switches` | Discover silent install switches |

### Example: Set download location

```powershell
Invoke-RestMethod -Method PUT -Uri http://localhost:8765/api/config `
    -ContentType 'application/json' `
    -Body '{"downloadLocation": "C:\\Installers"}'
```

### Example: Analyze an installer

```powershell
Invoke-RestMethod -Method POST -Uri http://localhost:8765/api/analyze `
    -ContentType 'application/json' `
    -Body '{"installerPath": "C:\\Installers\\setup.exe"}'
```

## Silent Switch Discovery

AppGetter uses multiple methods to find silent install switches:

1. **Signature database** — Matches installer binaries against known frameworks (NSIS, Inno Setup, InstallShield, WiX, Squirrel, etc.)
2. **Web research** — Scans support/documentation pages for switch references
3. **Installer probe** — Runs the installer with `/?`, `/help`, `--help` to extract switch info from help text (no actual install)
4. **Extension defaults** — MSI (`/quiet`), MSIX (`Add-AppxPackage`), EXE fallback (`/S`)

## PowerShell Module

The core logic is also available as a PowerShell module:

```powershell
Import-Module .\AppGetter.Core\AppGetter.Core.psm1

# Configure download location
Set-AppGetterConfig -DownloadLocation 'C:\Installers'

# Download an installer
Start-InstallerDownload -DownloadUrl 'https://example.com/setup.exe'

# Analyze silent switches
Test-InstallerSilentSwitches -InstallerPath 'C:\Installers\setup.exe'

# Discover switches (research + probe)
Find-InstallerSilentSwitches -InstallerPath 'C:\Installers\setup.exe' -AppName 'MyApp'
```

## Original Script

The original `Create-IntuneWinFromWeb.ps1` script remains available for full IntuneWin packaging workflows:

```powershell
.\Create-IntuneWinFromWeb.ps1 -WebsiteUrl "https://simion.com/" -AppName "SIMION"
```

## Prerequisites

1. **Windows 10/11** with PowerShell 5.1+
2. **Internet access** for downloads and web research
3. **Content Prep Tool** (`intunewinapputil`) — required only for IntuneWin packaging via the original script

## Configuration

Settings are stored at `%APPDATA%\AppGetter\config.json`:

| Setting | Default | Description |
|---------|---------|-------------|
| DownloadLocation | `%USERPROFILE%\Downloads\AppGetter` | Where installers are saved |
| OutputPath | `D:\Intoon In Progress` | IntuneWin package output path |
| ServerPort | `8765` | Local web server port |
| AutoDiscoverSwitches | `true` | Auto-discover switches during analysis |
| TestInstallers | `true` | Probe installers for help text |

## License

Provided as-is for creating IntuneWin packages from web-based application downloads.
