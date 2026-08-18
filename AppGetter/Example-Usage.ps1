# Example usage script for AppGetter
# This file demonstrates various ways to use Create-IntuneWinFromWeb.ps1

# Example 1: Launch GUI (recommended on Windows)
Write-Host 'Example 1: GUI mode' -ForegroundColor Cyan
# Double-click AppGetter.exe (after .\Build\Build-AppGetterExe.ps1)
# or Start-AppGetter.cmd, or:
# .\Create-IntuneWinFromWeb.ps1
# .\Create-IntuneWinFromWeb.ps1 -UseGui
# .\Gui\Start-AppGetterGui.ps1
# .\Launch-AppGetter.ps1

# Example 2: Direct download URL
Write-Host "`nExample 2: Direct download URL" -ForegroundColor Cyan
# .\Create-IntuneWinFromWeb.ps1 `
#     -DownloadUrl "https://example.com/installer.exe" `
#     -AppName "MyApp" `
#     -Version "1.0.0" `
#     -Publisher "MyCompany"

# Example 3: Local installer already on this computer
Write-Host "`nExample 3: Local installer" -ForegroundColor Cyan
# .\Create-IntuneWinFromWeb.ps1 `
#     -InstallerPath "C:\Installers\setup.exe" `
#     -AppName "MyApp" `
#     -Publisher "MyCompany"

# Example 4: SIMION from website
Write-Host "`nExample 4: SIMION from website" -ForegroundColor Cyan
# .\Create-IntuneWinFromWeb.ps1 `
#     -WebsiteUrl "https://simion.com/" `
#     -AppName "SIMION" `
#     -Publisher "Adaptas Solutions, LLC"

# Example 5: Custom output path
Write-Host "`nExample 5: Custom output path" -ForegroundColor Cyan
# .\Create-IntuneWinFromWeb.ps1 `
#     -DownloadUrl "https://example.com/setup.exe" `
#     -AppName "MyApp" `
#     -OutputPath "C:\IntunePackages"

# Example 6: PowerShell module (advanced)
Write-Host "`nExample 6: Module usage" -ForegroundColor Cyan
# Import-Module .\AppGetter.psd1
# Test-AppGetterPrerequisites
# Install-AppGetterContentPrepTool
# Invoke-AppGetterPackaging -AppName "MyApp" -DownloadUrl "https://example.com/setup.exe"
# Invoke-AppGetterPackaging -AppName "MyApp" -InstallerPath "C:\Installers\setup.exe"
