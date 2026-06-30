# Example usage script for AppGetter
# This file demonstrates WinGetter-style GUI + CLI usage

# Example 1: Launch desktop GUI (recommended)
Write-Host "Example 1: Launch GUI" -ForegroundColor Cyan
# .\Start-AppGetter.ps1
# or
# .\Create-IntuneWinFromWeb.ps1

# Example 2: SIMION with website URL (CLI)
Write-Host "`nExample 2: SIMION from website" -ForegroundColor Cyan
.\Create-IntuneWinFromWeb.ps1 `
    -WebsiteUrl "https://simion.com/" `
    -AppName "SIMION" `
    -Publisher "Adaptas Solutions, LLC"

# Example 3: Direct download URL
Write-Host "`nExample 3: Direct download URL" -ForegroundColor Cyan
# .\Create-IntuneWinFromWeb.ps1 `
#     -DownloadUrl "https://example.com/installer.exe" `
#     -AppName "MyApp" `
#     -Version "1.0.0" `
#     -Publisher "MyCompany"

# Example 4: With specific version
Write-Host "`nExample 4: SIMION with specific version" -ForegroundColor Cyan
# .\Create-IntuneWinFromWeb.ps1 `
#     -WebsiteUrl "https://simion.com/" `
#     -AppName "SIMION" `
#     -Version "8.2.1.3" `
#     -Publisher "Adaptas Solutions, LLC"

# Example 5: With custom output path
Write-Host "`nExample 5: Custom output path" -ForegroundColor Cyan
# .\Create-IntuneWinFromWeb.ps1 `
#     -WebsiteUrl "https://simion.com/" `
#     -AppName "SIMION" `
#     -OutputPath "C:\IntunePackages"

# Example 6: With custom icon
Write-Host "`nExample 6: Custom icon" -ForegroundColor Cyan
# .\Create-IntuneWinFromWeb.ps1 `
#     -WebsiteUrl "https://simion.com/" `
#     -AppName "SIMION" `
#     -IconPath "D:\Intoon In Progress\AppGetter\logo.png"

# Example 7: With custom install command
Write-Host "`nExample 7: Custom install command" -ForegroundColor Cyan
# .\Create-IntuneWinFromWeb.ps1 `
#     -DownloadUrl "https://example.com/setup.exe" `
#     -AppName "CustomApp" `
#     -InstallCommand '"setup.exe" /VERYSILENT /SUPPRESSMSGBOXES' `
#     -Publisher "CustomPublisher"

# Example 8: Force GUI with switch
Write-Host "`nExample 8: Force GUI" -ForegroundColor Cyan
# .\Create-IntuneWinFromWeb.ps1 -UseGui

# Example 9: MSI installer
Write-Host "`nExample 9: MSI installer" -ForegroundColor Cyan
# .\Create-IntuneWinFromWeb.ps1 `
#     -DownloadUrl "https://example.com/installer.msi" `
#     -AppName "MSIApp" `
#     -Publisher "MSIPublisher"
#     # Install command will auto-detect as: msiexec /i "installer.msi" /quiet /norestart
