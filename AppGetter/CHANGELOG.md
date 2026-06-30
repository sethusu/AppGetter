# AppGetter Changelog

## Version 2.0 - 2026-06-30

### Major rewrite — WinGetter-style PowerShell module (no Python)

- **Removed Python backend** — Flask API, `requirements.txt`, and browser-based web UI are gone
- **PowerShell module architecture** — `AppGetter.psm1` / `AppGetter.psd1` with `Private/` submodules mirroring [WinGetter](https://github.com/sethusu/WinGetter)
- **WPF GUI** — Native Windows GUI via `Gui/Start-AppGetterGui.ps1` (no web server)
- **`install.ps1` generation** — Intune install wrapper with proper return codes (3010, 1641, 1618)
- **`README.md` Intune cheat sheet** — Field-by-field portal upload reference per package
- **Settings persistence** — `%AppData%\AppGetter\settings.json` for output path and last-used values
- **Progress callbacks** — Live step/progress reporting for CLI and GUI
- **Prerequisite check** — `Test-AppGetterPrerequisites` validates Content Prep Tool on PATH
- **Failure logging** — `appgetter-packaging.log` written on packaging errors

## Version 1.0 - 2026-01-23

### Initial Release

#### Features
- **Web-Based Download**: Automatically finds and downloads installers from websites
- **Download Link Discovery**: Scans websites for download links using pattern matching
- **Direct Download Support**: Supports direct download URLs when provided
- **Version Detection**: Attempts to extract version information from websites
- **Interactive Input Dialogs**: User-friendly input dialogs for website URL and app name
- **Registry-Based Detection**: Creates detection scripts that check Windows registry
- **Automatic Uninstall Scripts**: Generates uninstall scripts from registry entries
- **Multiple Installer Types**: Supports EXE, MSI, MSIX, and APPX installers
- **Smart Install Command Detection**: Auto-detects appropriate install commands based on installer type
- **Content Prep Tool Integration**: Automatically packages with IntuneWin Content Prep Tool
- **Complete Metadata Generation**: Creates app.json and win32LobApp.json files
- **Icon Handling**: Supports custom icons or automatic icon discovery
- **Comprehensive Documentation**: Includes README, troubleshooting guide, and examples

#### Technical Details

##### Download Link Discovery
The script searches for download links using multiple patterns:
- Links ending in `.exe`, `.msi`, `.msix`, `.appx`
- Links containing "download", "install", or "setup" in the URL
- Direct download URLs in page content
- Supports relative and absolute URLs

##### Version Extraction
Attempts to extract version from website HTML using patterns:
- `Version X.X.X.X` or `Version X.X.X`
- `vX.X.X.X` or `vX.X.X`
- `AppName X.X.X.X` or `AppName X.X.X`
- Falls back to "latest" if extraction fails

##### Installer Type Detection
Auto-detects installer type and generates appropriate commands:
- **MSI**: `msiexec /i "installer.msi" /quiet /norestart`
- **MSIX/APPX**: `Add-AppxPackage -Path "installer.msix"`
- **EXE**: `"installer.exe" /S` (default, can be customized)

##### Detection Script
- Checks standard Windows Uninstall registry locations
- Handles multiple installations (selects highest version)
- Supports version comparison (equal or higher)
- Comprehensive logging for troubleshooting

##### Uninstall Script
- Finds uninstall string from registry
- Prefers quiet uninstall when available
- Adds `/S` flag for Nullsoft installers if needed
- Proper exit code handling

#### Files Created
- `Create-IntuneWinFromWeb.ps1` - Main script
- `README.md` - Comprehensive documentation
- `Example-Usage.ps1` - Usage examples
- `Troubleshooting-Guide.md` - Troubleshooting guide
- `SIMION-Deployment-Notes.md` - SIMION-specific deployment notes
- `CHANGELOG.md` - This file

#### Known Limitations
- Download link discovery may not work for JavaScript-heavy websites
- Version extraction may fail for non-standard version formats
- Some websites require authentication (manual download recommended)
- Archive files (ZIP, 7Z) require manual extraction

#### Future Enhancements
- Enhanced JavaScript rendering for dynamic websites
- Support for authenticated downloads
- Archive file extraction support
- Enhanced version detection patterns
- Support for more installer types
- Automatic icon extraction from websites
- Batch processing for multiple applications

#### Testing
- Tested with SIMION website structure
- Verified download link discovery patterns
- Tested registry-based detection scripts
- Verified Content Prep Tool integration

#### Documentation
- Comprehensive README with examples
- Detailed troubleshooting guide
- SIMION-specific deployment notes
- Usage examples for common scenarios
