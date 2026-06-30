# AppGetter v2.0 - IntuneWin Package Creator

AppGetter automates creating IntuneWin packages from web-based application downloads with registry-based detection, silent install switch discovery, and a modern Windows 11 web UI.

## What's New in v2.0

- **Configurable download location** — persist your preferred download and output paths
- **Silent switch analysis** — detect known installer frameworks (NSIS, Inno Setup, MSI, WiX, etc.)
- **Switch discovery** — research documentation, probe help output, and test switches
- **Modern Windows 11 UI** — Fluent Design web interface served locally
- **REST API backend** — modular PowerShell modules powering the UI and automation

## Quick Start

### Launch the UI (Recommended)

```powershell
.\Start-AppGetter.ps1
```

This starts the API server on port 8765 (configurable) and opens the web UI in your browser.

### Original CLI Mode

The original script still works for command-line usage:

```powershell
.\Create-IntuneWinFromWeb.ps1 -WebsiteUrl "https://example.com/" -AppName "MyApp"
```

## Architecture

```
AppGetter/
├── Start-AppGetter.ps1              # Main launcher (API + UI)
├── Create-IntuneWinFromWeb.ps1      # Original CLI script
├── Modules/
│   ├── AppGetter.Config.psm1        # Persistent configuration
│   ├── AppGetter.Core.psm1          # Download, packaging, web scraping
│   └── AppGetter.SwitchDiscovery.psm1  # Silent switch research & testing
├── Backend/
│   └── Start-AppGetterApi.ps1       # REST API server
├── UI/
│   ├── index.html                   # Windows 11 Fluent web UI
│   ├── css/fluent.css
│   └── js/                          # API client and app logic
└── Data/
    └── known-installer-switches.json  # Installer framework database
```

## Features

### Download Location Configuration

Configure where installers are downloaded and where packages are output:

- Settings are stored in `%APPDATA%\AppGetter\config.json`
- Validate paths for writability and free disk space
- Per-app folder structure: `{downloadLocation}/{AppName}/{version}/`

### Silent Install Switch Discovery

AppGetter analyzes installers through multiple methods:

| Method | Description |
|--------|-------------|
| **Known Database** | Matches installer type (NSIS, Inno, MSI, InstallShield, WiX, etc.) |
| **Binary Analysis** | Scans executable for framework signatures and embedded switches |
| **Web Research** | Scrapes support/documentation pages for deployment flags |
| **Help Probing** | Runs `/?`, `/help` to extract switches from help output |
| **Switch Testing** | Dry-run or execute mode to validate switches |

### Switch Test Modes

- **Dry Run** (default, safe) — records switches without executing the installer
- **Execute** (caution) — actually runs the installer with each switch candidate

### Intune Package Building

Generates the complete package:

- `detection.ps1` — registry-based detection
- `uninstall.ps1` — silent uninstall script
- `app.json` — application metadata
- `win32LobApp.json` — Intune app definition
- `.intunewin` — packaged via Content Prep Tool

## API Endpoints

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/api/health` | GET | Health check |
| `/api/config` | GET/PUT | Read/update configuration |
| `/api/config/validate-download-location` | POST | Validate a download path |
| `/api/download/links` | POST | Scan website for download links |
| `/api/download` | POST | Download installer to configured location |
| `/api/installer/analyze` | POST | Quick installer type analysis |
| `/api/installer/discover-switches` | POST | Full switch discovery pipeline |
| `/api/installer/test-switch` | POST | Test a specific silent switch |
| `/api/installer/upload` | POST | Import a local installer file |
| `/api/package` | POST | Build Intune package |

## Prerequisites

1. **Windows 10/11** with PowerShell 5.1+
2. **Content Prep Tool** — for `.intunewin` packaging (`intunewinapputil` in PATH)
3. **Internet access** — for downloading installers and web research

## Usage Workflow

1. **Configure** — Set your download location and output path in Settings
2. **Download** — Point to a URL, scan a website, or import a local installer
3. **Analyze Switches** — Run discovery to find or verify silent install flags
4. **Build Package** — Generate detection scripts, metadata, and IntuneWin file
5. **Deploy** — Upload the `.intunewin` file to Microsoft Intune

## Supported Installer Types

| Framework | Silent Switch | Confidence |
|-----------|--------------|------------|
| MSI | `/quiet /norestart` | High |
| NSIS | `/S` | High |
| Inno Setup | `/VERYSILENT /SUPPRESSMSGBOXES` | High |
| InstallShield | `/s /v"/qn"` | High |
| WiX Burn | `/quiet` | High |
| Squirrel/Electron | `--silent` | High |
| Generic EXE | `/S` (best guess) | Low |

## Troubleshooting

### API won't start
- Ensure port 8765 is not in use, or change it in Settings
- Run PowerShell as Administrator if needed for HttpListener

### Switch discovery returns "unknown"
- Provide a support/documentation URL for web research
- Try help probing by ensuring the installer supports `/?` or `/help`
- Use Execute test mode only in a VM or test machine

### intunewinapputil not found
- Install Microsoft Win32 Content Prep Tool
- Check: `Get-Command intunewinapputil`

## License

Provided as-is for creating IntuneWin packages from web-based application downloads.
