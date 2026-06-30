# Example usage script for AppGetter
# This file demonstrates various ways to use Create-IntuneWinFromWeb.ps1

# Example 1: Launch GUI
Write-Host "Example 1: GUI mode" -ForegroundColor Cyan
# .\Start-AppGetter.ps1
# .\Create-IntuneWinFromWeb.ps1

# Example 2: SIMION from website
Write-Host "`nExample 2: SIMION from website" -ForegroundColor Cyan
# .\Create-IntuneWinFromWeb.ps1 `
#     -WebsiteUrl "https://simion.com/" `
#     -AppName "SIMION" `
#     -Publisher "Adaptas Solutions, LLC"

# Example 3: Direct download URL
Write-Host "`nExample 3: Direct download URL" -ForegroundColor Cyan
# .\Create-IntuneWinFromWeb.ps1 `
#     -DownloadUrl "https://example.com/installer.exe" `
#     -AppName "MyApp" `
#     -Version "1.0.0" `
#     -Publisher "MyCompany"

# Example 4: Module API
Write-Host "`nExample 4: PowerShell module API" -ForegroundColor Cyan
# Import-Module .\AppGetter.psd1
# Invoke-AppGetterPackaging -AppName "MyApp" -DownloadUrl "https://example.com/setup.exe" -OutputPath "C:\IntunePackages"

# Example 5: Custom install command
Write-Host "`nExample 5: Custom install command" -ForegroundColor Cyan
# .\Create-IntuneWinFromWeb.ps1 `
#     -DownloadUrl "https://example.com/setup.exe" `
#     -AppName "CustomApp" `
#     -InstallCommand '"setup.exe" /VERYSILENT /SUPPRESSMSGBOXES' `
#     -Publisher "CustomPublisher"
