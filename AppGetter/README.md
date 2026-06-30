# AppGetter - IntuneWin Package Creator from Web Downloads

This tool automates the creation of IntuneWin packages from web-based application downloads with registry-based detection.

## Features

- ✅ Interactive input dialog for website URL and application details
- ✅ Download location support (URL, local installer file, or local download folder)
- ✅ Automatic download link discovery from websites
- ✅ Registry-based detection script (no external dependencies)
- ✅ Automatic uninstall script generation
- ✅ Content Prep Tool integration
- ✅ Complete metadata file generation (app.json, win32LobApp.json)
- ✅ Automatic version detection from website
- ✅ Smart installer type detection (EXE, MSI, MSIX, APPX)
- ✅ Silent switch intelligence engine (known profiles + web research + installer help probing)
- ✅ Windows 11 style WPF launcher UI (`AppGetter.UI.ps1`)
- ✅ Icon file handling
- ✅ Proper installer filename handling
- ✅ Version included in readme.txt

## Prerequisites

1. **Content Prep Tool** - Must be installed and accessible via `intunewinapputil` command
2. **PowerShell** - Version 5.1 or later
3. **Internet Access** - Required to download installers from websites

## Usage

### Interactive Mode (Recommended)

Simply run the script without parameters to open input dialogs:

```powershell
.\Create-IntuneWinFromWeb.ps1
```

### Windows 11 Style UI Launcher

Run the GUI frontend for easier operation:

```powershell
.\AppGetter.UI.ps1
```

The UI is tied directly to the backend script and supports:
- Download location input (URL / file / folder)
- Silent switch analysis for downloaded/uploaded installers
- One-click package generation with live log output

Dialog boxes will appear prompting you to enter:
- Website URL (e.g., "https://simion.com/")
- Application Name (e.g., "SIMION")

### Command Line Usage

#### Basic Usage with Website URL

```powershell
.\Create-IntuneWinFromWeb.ps1 -WebsiteUrl "https://simion.com/" -AppName "SIMION" -Publisher "Adaptas Solutions, LLC"
```

#### With Direct Download URL

```powershell
.\Create-IntuneWinFromWeb.ps1 -DownloadUrl "https://example.com/installer.exe" -AppName "MyApp" -Version "1.0.0"
```

#### With Download Location (local folder or file)

```powershell
.\Create-IntuneWinFromWeb.ps1 -DownloadLocation "C:\Users\Me\Downloads" -AppName "MyApp"
```

```powershell
.\Create-IntuneWinFromWeb.ps1 -InstallerPath "C:\Users\Me\Downloads\setup.exe" -AppName "MyApp"
```

#### With Specific Version

```powershell
.\Create-IntuneWinFromWeb.ps1 -WebsiteUrl "https://simion.com/" -AppName "SIMION" -Version "8.2.1.3"
```

#### With Custom Output Path

```powershell
.\Create-IntuneWinFromWeb.ps1 -WebsiteUrl "https://simion.com/" -AppName "SIMION" -OutputPath "C:\IntunePackages"
```

#### With Custom Icon

```powershell
.\Create-IntuneWinFromWeb.ps1 -WebsiteUrl "https://simion.com/" -AppName "SIMION" -IconPath "C:\Icons\simion-icon.png"
```

#### With Custom Install Command

```powershell
.\Create-IntuneWinFromWeb.ps1 -DownloadUrl "https://example.com/setup.exe" -AppName "MyApp" -InstallCommand '"setup.exe" /SILENT /NORESTART'
```

## Parameters

- **WebsiteUrl** (Optional): The URL of the website containing the download link
  - Example: `"https://simion.com/"`
  - Script will attempt to find download links on this page
  
- **DownloadUrl** (Optional): Direct download URL if known
  - If provided, script will skip website scanning and download directly
  - Example: `"https://example.com/installer.exe"`

- **DownloadLocation** (Optional): Generic source location provided by user
  - Supports web URLs, local installer file paths, or local folders
  - Local folders are scanned for the newest `.exe`, `.msi`, `.msix`, or `.appx`
  - Example: `"C:\Installers"`, `"https://example.com/setup.exe"`

- **InstallerPath** (Optional): Local installer path (for user-uploaded/downloader files)
  - If provided, download step is skipped and file is copied into package directory
  - Example: `"C:\Downloads\app-setup.exe"`
  
- **AppName** (Optional): The name of the application
  - If not provided, an input dialog will appear
  - Example: `"SIMION"`, `"MyApplication"`
  
- **Version** (Optional): Specific version to use
  - If not specified, script will attempt to extract from website or use "latest"
  - Example: `"8.2.1.3"`, `"1.0.0"`
  
- **Publisher** (Optional): Publisher name
  - Example: `"Adaptas Solutions, LLC"`, `"Microsoft Corporation"`
  
- **OutputPath** (Optional): Base directory for output. Default: `"D:\Intoon In Progress"`
  - Packages will be created in: `{OutputPath}\{PackageId}\{Version}\`
  
- **IconPath** (Optional): Path to icon file (PNG format recommended)
  - If not provided, script will look for `logo.png` in the parent directory
  - If neither found, package will be created without icon
  
- **InstallCommand** (Optional): Custom install command
  - If not provided, script will auto-detect based on installer type:
    - MSI: `msiexec /i "installer.msi" /quiet /norestart`
    - MSIX/APPX: `Add-AppxPackage -Path "installer.msix"`
    - EXE: `"installer.exe" /S`

- **DeveloperUrl** (Optional): Publisher/developer URL to enrich metadata and switch research
- **SupportUrl** (Optional): Support docs URL to research known installation switches

## What the Script Does

1. **Resolves Installer Source** - Uses `InstallerPath`, `DownloadLocation`, `DownloadUrl`, or website discovery
2. **Downloads/Copies** the installer into package folder
3. **Detects Version** - Attempts to extract version information from website
4. **Creates detection.ps1** - Registry-based detection script
5. **Creates uninstall.ps1** - Uninstall script that finds and executes the uninstaller
6. **Handles icon files** - Copies icon to package directory if available
7. **Creates metadata files**:
   - `readme.txt` - Documentation
   - `app.json` - Application metadata
   - `win32LobApp.json` - Intune app definition with detection script
8. **Analyzes Silent Switches** - Uses known profiles, documentation research, and installer help probing
9. **Packages with Content Prep Tool** - Creates the final `.intunewin` file

## Output Structure

```
{OutputPath}/
└── {PackageId}/
    ├── logo.png (optional, if exists)
    └── {Version}/
        ├── {InstallerFileName}.exe
        ├── detection.ps1
        ├── uninstall.ps1
        ├── app.json
        ├── win32LobApp.json
        ├── readme.txt
        ├── icon.png
        └── {InstallerFileName}.intunewin (created in parent directory)
```

## Detection Script

The detection script uses **registry-based detection** instead of external dependencies, making it reliable for Intune deployments:

- Checks `HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*`
- Checks `HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*`
- Verifies version matches or is higher than expected
- Returns appropriate exit codes for Intune
- Handles multiple installations and selects the highest version

## Uninstall Script

The uninstall script:
- Searches registry for uninstall string
- Prefers quiet uninstall if available
- Adds `/S` flag for Nullsoft installers if needed
- Executes uninstall and returns proper exit codes

## Examples

### Example 1: SIMION

```powershell
.\Create-IntuneWinFromWeb.ps1 -WebsiteUrl "https://simion.com/" -AppName "SIMION" -Publisher "Adaptas Solutions, LLC"
```

### Example 2: Direct Download URL

```powershell
.\Create-IntuneWinFromWeb.ps1 -DownloadUrl "https://example.com/app-installer.exe" -AppName "MyApp" -Version "2.0.0" -Publisher "MyCompany"
```

### Example 3: Custom Install Command

```powershell
.\Create-IntuneWinFromWeb.ps1 `
    -DownloadUrl "https://example.com/setup.exe" `
    -AppName "CustomApp" `
    -InstallCommand '"setup.exe" /VERYSILENT /SUPPRESSMSGBOXES' `
    -Publisher "CustomPublisher"
```

## Troubleshooting

### "No download links found on the website"
- The script may not have found download links using its pattern matching
- **Solution**: Provide a direct `-DownloadUrl` parameter instead
- Check the website manually to find the direct download link

### "intunewinapputil not found"
- Install Microsoft Win32 Content Prep Tool
- Ensure it's in your PATH or use full path
- Check if the alias is set: `Get-Command intunewinapputil`

### "Could not find downloaded installer file"
- Check the download directory for the file
- Verify the download URL is accessible
- Check file permissions
- Some websites may require authentication or have download restrictions

### Detection script not working
- Verify the app is actually installed
- Check registry keys manually: `Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*" | Where-Object { $_.DisplayName -like "*AppName*" }`
- Review detection script logs in: `%ProgramData%\Microsoft\IntuneManagementExtension\Logs\`
- Test detection script manually: `powershell -ExecutionPolicy Bypass -File detection.ps1` (should exit with code 0 if installed)

### Version extraction failed
- The script attempts to extract version from the website HTML
- If extraction fails, version will default to "latest"
- **Solution**: Provide `-Version` parameter explicitly

### Download requires authentication
- Some websites require login or have download restrictions
- **Solution**: 
  1. Download the installer manually
  2. Place it in the version directory
  3. Run the script with `-DownloadUrl` pointing to a local file path (if supported) or skip download step

## Notes

- The script assumes silent install with `/S` flag for EXE files. Adjust `installCommandLine` in JSON files if different flags are needed.
- Icon files should be PNG format for best compatibility with Intune.
- The script will overwrite existing files in the version directory.
- IntuneWin files are created in the parent directory (same level as version folder).
- **Download Link Discovery**: The script uses pattern matching to find download links. It looks for:
  - Links ending in `.exe`, `.msi`, `.msix`, `.appx`
  - Links containing "download", "install", or "setup" in the URL
  - Direct download URLs in page content
- **Version Detection**: The script attempts to extract version numbers from the website HTML using common patterns. If extraction fails, you can provide the version explicitly.

## SIMION-Specific Notes

For SIMION specifically:
- **Latest Version**: SIMION 8.2.1.3 (20260116) - Latest 8.2 Production Release
- **Website**: https://simion.com/
- **Download**: May require request/authentication. Check the download page for current requirements.
- **Publisher**: Adaptas Solutions, LLC (IMI Adaptas)
- **Documentation**: Available at https://simion.com/info/
- **System Requirements**: Windows 10/7, Linux (via Wine/CrossOver)

## Recent Improvements

### Version 1.0 (2026-01-23)
- ✅ Initial release
- ✅ Web-based download link discovery
- ✅ Automatic version extraction from websites
- ✅ Registry-based detection scripts
- ✅ Support for multiple installer types (EXE, MSI, MSIX, APPX)
- ✅ Interactive input dialogs
- ✅ Comprehensive metadata generation

## License

This script is provided as-is for creating IntuneWin packages from web-based application downloads.
