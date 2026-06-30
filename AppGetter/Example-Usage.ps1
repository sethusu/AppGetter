# Example usage for the PowerShell-only AppGetter workflow

Write-Host "Example 1: Interactive mode (Windows desktop only)" -ForegroundColor Cyan
# .\Create-IntuneWinFromWeb.ps1

Write-Host "`nExample 2: Direct installer URL" -ForegroundColor Cyan
# .\Create-IntuneWinFromWeb.ps1 `
#   -DownloadUrl "https://example.com/installer.exe" `
#   -AppName "Example.App" `
#   -Publisher "Example Corp" `
#   -OutputPath "C:\IntunePackages"

Write-Host "`nExample 3: Website discovery mode" -ForegroundColor Cyan
# .\Create-IntuneWinFromWeb.ps1 `
#   -WebsiteUrl "https://example.com/downloads" `
#   -AppName "Example.App"

Write-Host "`nExample 4: Custom install command override" -ForegroundColor Cyan
# .\Create-IntuneWinFromWeb.ps1 `
#   -DownloadUrl "https://example.com/setup.exe" `
#   -AppName "Example.App" `
#   -InstallCommand '"setup.exe" /VERYSILENT /SUPPRESSMSGBOXES /NORESTART'

Write-Host "`nExample 5: Use wrapper launcher" -ForegroundColor Cyan
# .\Start-AppGetter.ps1 `
#   -DownloadUrl "https://example.com/installer.msi" `
#   -AppName "Example.MsiApp"
