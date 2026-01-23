# SIMION Deployment Notes for Intune

This document contains specific information about deploying SIMION using AppGetter.

## SIMION Information

### Current Version
- **Latest Production Release**: SIMION 8.2.1.3 (20260116)
- **Latest Test Release**: SIMION 8.1.3.9 (20190914)
- **Website**: https://simion.com/
- **Publisher**: Adaptas Solutions, LLC (IMI Adaptas)

### System Requirements
- **Operating Systems**: Windows 10/7, Linux (via Wine/CrossOver Mac)
- **Architecture**: 64-bit (recommended), 32-bit available
- **RAM**: Varies based on array size (up to 190GB for large arrays)

## Download Information

### Download Process
SIMION downloads may require:
1. **Request Process**: Demo versions available upon request
2. **Licensed Users**: Updates available via "Check for Updates" button in SIMION
3. **Direct Download**: May require authentication or special access

### Download URL Discovery
When using AppGetter with SIMION:
1. The script will attempt to find download links on https://simion.com/
2. If automatic discovery fails, you may need to:
   - Request download link from vendor
   - Use direct download URL if you have access
   - Download manually and provide the file path

### Example Usage

```powershell
# Basic usage - script will attempt to find download link
.\Create-IntuneWinFromWeb.ps1 `
    -WebsiteUrl "https://simion.com/" `
    -AppName "SIMION" `
    -Publisher "Adaptas Solutions, LLC"

# With specific version
.\Create-IntuneWinFromWeb.ps1 `
    -WebsiteUrl "https://simion.com/" `
    -AppName "SIMION" `
    -Version "8.2.1.3" `
    -Publisher "Adaptas Solutions, LLC"

# With direct download URL (if you have it)
.\Create-IntuneWinFromWeb.ps1 `
    -DownloadUrl "https://simion.com/downloads/simion-8.2.1.3.exe" `
    -AppName "SIMION" `
    -Version "8.2.1.3" `
    -Publisher "Adaptas Solutions, LLC"
```

## Installation Considerations

### Silent Install
SIMION installer type and silent install flags:
- **Installer Type**: Typically EXE installer
- **Default Silent Flag**: `/S` (will be auto-detected)
- **Custom Flags**: May require specific flags - check SIMION documentation

### Installation Location
- Default installation path may vary
- Check SIMION documentation for default paths
- Registry entries will be created in standard Windows Uninstall locations

### License/Activation
- SIMION may require license activation after installation
- Consider post-install scripts for license configuration if needed
- Check SIMION documentation for automated license deployment

## Detection

### Registry Detection
SIMION should create registry entries in:
- `HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*`
- `HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*`

### Detection Script
The generated detection script will look for:
- DisplayName containing "SIMION"
- DisplayVersion matching or exceeding specified version
- Registry keys in standard uninstall locations

### Testing Detection
After creating the package, test detection:
```powershell
cd "D:\Intoon In Progress\SIMION\8.2.1.3"
powershell -ExecutionPolicy Bypass -File detection.ps1
echo "Exit Code: $LASTEXITCODE"
```

## Uninstall

### Uninstall Process
- Uninstall script will find uninstall string from registry
- Prefers quiet uninstall if available
- Adds `/S` flag for silent uninstall if needed

### Testing Uninstall
```powershell
# Check registry for uninstall string
Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*" | 
    Where-Object { $_.DisplayName -like "*SIMION*" } | 
    Select-Object DisplayName, UninstallString, QuietUninstallString
```

## Documentation Resources

### Official Documentation
- **Main Documentation**: https://simion.com/info/
- **Manual**: https://simion.com/manual/
- **System Requirements**: https://simion.com/info/system_requirements.html
- **Installation Guide**: Check manual Appendix B

### Support
- **Community/Support**: https://simion.com/community
- **Contact**: Available via website contact form
- **User Group**: SIMION Ion Optics Users Group

## Known Considerations

### Version Format
- SIMION versions follow format: `8.2.1.3` or `8.1.3.9`
- Version detection should work with standard version parsing
- If version extraction fails, provide `-Version` parameter explicitly

### Updates
- Licensed users can update via "Check for Updates" button in SIMION
- Updates are electronic downloads
- Version 8.x.y updates are available for version 8.x users

### Demo vs Full Version
- Demo versions have limited features
- Demo cannot save work or calculate custom geometries
- Full version required for production use

## Troubleshooting

### Download Issues
If download fails:
1. Check if login/authentication required
2. Verify download link is accessible
3. Consider manual download and direct URL
4. Contact vendor for direct download access

### Installation Issues
If installation fails:
1. Check installer type and silent flags
2. Verify system requirements met
3. Check for prerequisite software
4. Review SIMION installation documentation

### Detection Issues
If detection fails:
1. Verify SIMION is installed
2. Check registry entries manually
3. Review detection script logs
4. Ensure DisplayName matches expected format

## Additional Notes

### Package Structure
```
D:\Intoon In Progress\SIMION\
└── 8.2.1.3\
    ├── simion-installer.exe
    ├── detection.ps1
    ├── uninstall.ps1
    ├── app.json
    ├── win32LobApp.json
    ├── readme.txt
    └── icon.png (if available)
```

### Metadata
- **Package ID**: `SIMION` (sanitized from AppName)
- **Display Name**: `SIMION`
- **Publisher**: `Adaptas Solutions, LLC`
- **Source**: Web download (source = 3)

## Version History

### SIMION 8.2.1.3 (20260116)
- Latest 8.2 Production Release
- Released: January 16, 2026

### SIMION 8.1.3.9 (20190914)
- Latest 8.1 Test Release
- Released: September 14, 2019

### SIMION 8.1.1.32 (20130520)
- Latest 8.1 Production Release
- Released: May 20, 2013

## References

- [SIMION Website](https://simion.com/)
- [SIMION Documentation](https://simion.com/info/)
- [SIMION Manual](https://simion.com/manual/)
- [SIMION System Requirements](https://simion.com/info/system_requirements.html)
