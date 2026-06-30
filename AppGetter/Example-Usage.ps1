# AppGetter usage examples (PowerShell-only)

Write-Host "Example 1: Interactive mode" -ForegroundColor Cyan
# .\Create-IntuneWinFromWeb.ps1

Write-Host "`nExample 2: Direct URL (recommended)" -ForegroundColor Cyan
# .\Create-IntuneWinFromWeb.ps1 `
#   -AppName "SIMION" `
#   -DownloadUrl "https://example.com/simion-setup.exe" `
#   -Publisher "Adaptas Solutions, LLC" `
#   -OutputPath "C:\IntunePackages"

Write-Host "`nExample 3: Website discovery mode" -ForegroundColor Cyan
# .\Create-IntuneWinFromWeb.ps1 `
#   -AppName "SIMION" `
#   -WebsiteUrl "https://simion.com/download"

Write-Host "`nExample 4: Custom install command" -ForegroundColor Cyan
# .\Create-IntuneWinFromWeb.ps1 `
#   -AppName "CustomApp" `
#   -DownloadUrl "https://example.com/setup.exe" `
#   -InstallCommand '"setup.exe" /VERYSILENT /SUPPRESSMSGBOXES'

Write-Host "`nExample 5: Launcher wrapper" -ForegroundColor Cyan
# .\Start-AppGetter.ps1 `
#   -AppName "Google Chrome" `
#   -DownloadUrl "https://example.com/chrome-enterprise.msi"
