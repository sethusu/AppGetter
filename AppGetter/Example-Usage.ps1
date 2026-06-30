# Example usage for AppGetter (PowerShell-only workflow)

Write-Host "Example 1: Direct download URL" -ForegroundColor Cyan
# pwsh -NoProfile -File .\Create-IntuneWinFromWeb.ps1 `
#   -DownloadUrl "https://example.com/installer.msi" `
#   -AppName "Example App" `
#   -Publisher "Example Corp" `
#   -OutputPath "C:\IntunePackages"

Write-Host "`nExample 2: Discover installer from website" -ForegroundColor Cyan
# pwsh -NoProfile -File .\Create-IntuneWinFromWeb.ps1 `
#   -WebsiteUrl "https://vendor.example/downloads" `
#   -AppName "Vendor App"

Write-Host "`nExample 3: Custom install command for EXE" -ForegroundColor Cyan
# pwsh -NoProfile -File .\Create-IntuneWinFromWeb.ps1 `
#   -DownloadUrl "https://example.com/setup.exe" `
#   -AppName "Custom App" `
#   -InstallCommand '"setup.exe" /VERYSILENT /SUPPRESSMSGBOXES /NORESTART'
