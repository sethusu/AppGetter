# AppGetter Troubleshooting Guide

This guide helps troubleshoot common issues when creating IntuneWin packages from web downloads.

## Common Issues and Solutions

### Issue: "No download links found on the website"

**Symptoms:**
- Script reports "No download links found on the website"
- Script exits with error

**Possible Causes:**
1. Website uses JavaScript to load download links dynamically
2. Download links are behind authentication/login
3. Download links use non-standard patterns
4. Website structure doesn't match expected patterns

**Solutions:**

1. **Use Direct Download URL** (Recommended)
   ```powershell
   .\Create-IntuneWinFromWeb.ps1 -DownloadUrl "https://example.com/installer.exe" -AppName "MyApp"
   ```

2. **Manually Find Download Link**
   - Open the website in a browser
   - Right-click on the download button/link
   - Select "Copy link address"
   - Use the copied URL with `-DownloadUrl` parameter

3. **Check Website Requirements**
   - Some websites require login before showing download links
   - Check if the website has a "Direct Download" or "Direct Link" option
   - Look for download links in the page source (View Source in browser)

### Issue: "Download failed" or "Could not download installer"

**Symptoms:**
- Script reports download failure
- File not found in output directory

**Possible Causes:**
1. Download URL requires authentication
2. Download URL has expired or changed
3. Network connectivity issues
4. Website blocks automated downloads
5. File size too large or timeout

**Solutions:**

1. **Test Download Manually**
   - Open the download URL in a browser
   - Verify the file downloads successfully
   - Check if login/authentication is required

2. **Use Manual Download**
   - Download the installer manually
   - Place it in the version directory
   - Re-run the script (it may skip download if file exists, or you can modify the script)

3. **Check Network/Firewall**
   - Verify internet connectivity
   - Check if corporate firewall blocks the download
   - Try downloading from a different network

4. **Increase Timeout** (if modifying script)
   - The script uses default web request timeout
   - For large files, you may need to increase timeout in the script

### Issue: "Version extraction failed"

**Symptoms:**
- Script reports "Version not found, using: latest"
- Version in metadata shows "latest" instead of actual version

**Possible Causes:**
1. Website doesn't display version in expected format
2. Version is in a different location on the page
3. Version format doesn't match expected patterns

**Solutions:**

1. **Provide Version Explicitly**
   ```powershell
   .\Create-IntuneWinFromWeb.ps1 -WebsiteUrl "https://example.com/" -AppName "MyApp" -Version "1.0.0"
   ```

2. **Check Website for Version**
   - Look for version information on the website
   - Check "About", "Release Notes", or "Downloads" pages
   - Version may be in the filename of the installer

3. **Extract from Installer**
   - After download, check installer properties
   - Right-click installer → Properties → Details tab
   - Use the version found there

### Issue: Detection script not working

**Symptoms:**
- App installs successfully but Intune reports as "not detected"
- Detection script exits with code 1
- Intune shows installation as failed

**Possible Causes:**
1. App name doesn't match registry entry
2. Version format mismatch
3. App installed in different location
4. Registry key structure different than expected

**Solutions:**

1. **Check Registry Manually**
   ```powershell
   Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*" | 
       Where-Object { $_.DisplayName -like "*AppName*" } | 
       Select-Object DisplayName, DisplayVersion, PSChildName
   ```

2. **Review Detection Logs**
   - Location: `%ProgramData%\Microsoft\IntuneManagementExtension\Logs\{PackageId}-detection.log`
   - Look for error messages or version mismatches
   - Check what registry keys were found

3. **Test Detection Script Manually**
   ```powershell
   cd "D:\Intoon In Progress\{PackageId}\{Version}"
   powershell -ExecutionPolicy Bypass -File detection.ps1
   echo "Exit Code: $LASTEXITCODE"
   ```
   - Should exit with code 0 if app is installed
   - Should exit with code 1 if app is not installed

4. **Update Detection Script**
   - If app name in registry is different, update the detection script
   - Modify the `$displayName` variable or search patterns
   - Re-package with Content Prep Tool after changes

### Issue: "intunewinapputil not found"

**Symptoms:**
- Script reports "intunewinapputil not found"
- Packaging step fails

**Solutions:**

1. **Install Content Prep Tool**
   - Download from: https://www.microsoft.com/en-us/download/details.aspx?id=103380
   - Install the tool
   - Ensure it's added to PATH

2. **Verify Installation**
   ```powershell
   Get-Command intunewinapputil
   ```
   - Should return command information
   - If not found, add installation directory to PATH

3. **Use Full Path**
   - If tool is installed but not in PATH, modify script to use full path
   - Example: `& "C:\Program Files (x86)\Microsoft Intune Win32 Content Prep Tool\IntuneWinAppUtil.exe" ...`

### Issue: Install command doesn't work

**Symptoms:**
- App doesn't install silently
- Installation shows UI or requires interaction
- Installation fails in Intune

**Possible Causes:**
1. Installer doesn't support `/S` flag
2. Different silent install flags required
3. Installer type detection incorrect

**Solutions:**

1. **Check Installer Documentation**
   - Look for silent install documentation
   - Common flags:
     - `/S` - Silent (Nullsoft, Inno Setup)
     - `/SILENT` - Silent (Inno Setup)
     - `/VERYSILENT` - Very Silent (Inno Setup)
     - `/quiet` - Quiet (Microsoft installers)
     - `/qn` - Quiet No UI (MSI)

2. **Test Install Command Manually**
   ```powershell
   .\installer.exe /S
   # Or test other flags
   .\installer.exe /SILENT
   ```

3. **Provide Custom Install Command**
   ```powershell
   .\Create-IntuneWinFromWeb.ps1 `
       -DownloadUrl "https://example.com/installer.exe" `
       -AppName "MyApp" `
       -InstallCommand '"installer.exe" /VERYSILENT /SUPPRESSMSGBOXES'
   ```

4. **Check Installer Type**
   - EXE installers may use different flags
   - MSI installers use `msiexec` command
   - Check installer properties or documentation

### Issue: Uninstall script doesn't work

**Symptoms:**
- Uninstall fails in Intune
- Uninstall script exits with error

**Solutions:**

1. **Check Registry for Uninstall String**
   ```powershell
   Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*" | 
       Where-Object { $_.DisplayName -like "*AppName*" } | 
       Select-Object DisplayName, UninstallString, QuietUninstallString
   ```

2. **Review Uninstall Logs**
   - Location: `%ProgramData%\Microsoft\IntuneManagementExtension\Logs\{PackageId}-uninstall.log`
   - Check for error messages

3. **Test Uninstall Manually**
   - Run the uninstall command from the registry manually
   - Verify it works before deploying

### Issue: Website requires authentication

**Symptoms:**
- Download fails with authentication error
- Website redirects to login page

**Solutions:**

1. **Use a local installer** (Recommended)
   - Download the installer manually after logging in
   - Point AppGetter at the file on this computer:
     ```powershell
     .\Create-IntuneWinFromWeb.ps1 -InstallerPath "C:\Downloads\setup.exe" -AppName "MyApp"
     ```
   - In the GUI, choose **Local installer** and **Browse...**

2. **Use a direct download URL**
   - Use the direct download URL (may be temporary)
   - Provide `-DownloadUrl` with the direct link

2. **Check for Public Download Links**
   - Some websites have public download links
   - Look for "Direct Download" or "Mirror" links
   - Check if there's a demo/trial version available publicly

3. **Contact Vendor**
   - For enterprise software, contact vendor for direct download links
   - Request installer for automated deployment
   - Some vendors provide special download portals for IT admins

## Best Practices

### 1. Test Before Deploying
- Always test the installer manually first
- Verify silent install flags work
- Test detection script after installation
- Check uninstall process

### 2. Document Custom Requirements
- Note any special install flags
- Document authentication requirements
- Keep track of download URLs (they may change)

### 3. Version Management
- Always specify version explicitly when known
- Keep track of version numbers for updates
- Document version format if non-standard

### 4. Registry Inspection
- Before creating packages, inspect registry entries
- Note exact DisplayName and DisplayVersion formats
- Check for multiple installations

### 5. Log Review
- Regularly check Intune Management Extension logs
- Review detection and uninstall logs
- Keep logs for troubleshooting

## Getting Help

### Check Logs
- **Detection Logs**: `%ProgramData%\Microsoft\IntuneManagementExtension\Logs\{PackageId}-detection.log`
- **Uninstall Logs**: `%ProgramData%\Microsoft\IntuneManagementExtension\Logs\{PackageId}-uninstall.log`
- **Intune Logs**: `%ProgramData%\Microsoft\IntuneManagementExtension\Logs\*.log`

### Manual Testing
```powershell
# Test detection
cd "D:\Intoon In Progress\{PackageId}\{Version}"
powershell -ExecutionPolicy Bypass -File detection.ps1
echo "Exit Code: $LASTEXITCODE"

# Test install command
.\installer.exe /S

# Check registry
Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*" | 
    Where-Object { $_.DisplayName -like "*AppName*" }
```

### Re-packaging After Fixes
1. Update the local script files (detection.ps1, uninstall.ps1)
2. Re-run `intunewinapputil` to regenerate `.intunewin` package
3. Upload new package to Intune
4. Verify detection works on next sync cycle

### Issue: Content Prep Tool not found

**Symptoms:**
- GUI header shows a red prerequisite warning
- Metadata is created but `.intunewin` is missing

**Solutions:**

1. Click **Install Content Prep** in the GUI header (uses winget)
2. From PowerShell: `Install-AppGetterContentPrepTool`
3. Or install manually: `winget install --exact --id Microsoft.Win32ContentPrepTool`
4. Confirm `intunewinapputil` is on PATH, then restart AppGetter

### Issue: GUI Browse... crashes or does nothing

AppGetter uses the same output-folder dialog as WinGetter: rooted at **My Computer**, parented to the main window, with **Make New Folder** enabled. If a saved path is on another drive, the dialog still opens. Failures show an error message instead of closing the GUI.

### Issue: AppGetter.exe flashes and exits

- Keep `AppGetter.exe` next to `Gui\`, `Private\`, and `AppGetter.psd1`
- Check `%TEMP%\AppGetter-launch.log`
- On Windows, run `.\Build\Diagnose-AppGetterLaunch.ps1`
- If antivirus blocks the exe, use `Start-AppGetter.cmd` or `Launch-AppGetter.ps1`

## Additional Resources

- [Intune Management Extension Logs](https://learn.microsoft.com/mem/intune/apps/troubleshoot-app-install)
- [Win32 App Management](https://learn.microsoft.com/mem/intune/apps/apps-win32-app-management)
- [Content Prep Tool Documentation](https://learn.microsoft.com/mem/intune/apps/apps-win32-prepare)
