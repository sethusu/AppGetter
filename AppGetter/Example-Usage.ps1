# Example usage script for AppGetter
# This file demonstrates various ways to use Create-IntuneWinFromWeb.ps1

# Example 1: Launch GUI (recommended on Windows)
Write-Host "Example 1: GUI mode" -ForegroundColor Cyan
# .\Create-IntuneWinFromWeb.ps1
# .\Gui\Start-AppGetterGui.ps1

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

# Example 4: With specific version
Write-Host "`nExample 4: With specific version" -ForegroundColor Cyan
# .\Create-IntuneWinFromWeb.ps1 `
#     -WebsiteUrl "https://simion.com/" `
#     -AppName "SIMION" `
#     -Version "8.2.1.3" `
#     -Publisher "Adaptas Solutions, LLC"

# Example 5: Custom output path
Write-Host "`nExample 5: Custom output path" -ForegroundColor Cyan
# .\Create-IntuneWinFromWeb.ps1 `
#     -DownloadUrl "https://example.com/setup.exe" `
#     -AppName "MyApp" `
#     -OutputPath "C:\IntunePackages"

# Example 6: Custom icon
Write-Host "`nExample 6: Custom icon" -ForegroundColor Cyan
# .\Create-IntuneWinFromWeb.ps1 `
#     -DownloadUrl "https://example.com/setup.exe" `
#     -AppName "MyApp" `
#     -IconPath "C:\Icons\myapp.png"

# Example 7: Custom install command
Write-Host "`nExample 7: Custom install command" -ForegroundColor Cyan
# .\Create-IntuneWinFromWeb.ps1 `
#     -DownloadUrl "https://example.com/setup.exe" `
#     -AppName "CustomApp" `
#     -InstallCommand '"setup.exe" /VERYSILENT /SUPPRESSMSGBOXES' `
#     -Publisher "CustomPublisher"

# Example 8: PowerShell module usage
Write-Host "`nExample 8: Module API" -ForegroundColor Cyan
# Import-Module .\AppGetter.psd1
# Test-AppGetterPrerequisites
# Invoke-AppGetterPackaging -AppName "MyApp" -DownloadUrl "https://example.com/setup.exe" -OutputPath "C:\Out"
