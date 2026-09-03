# Example usage script for AppGetter
# This file demonstrates various ways to use Create-IntuneWinFromWeb.ps1

# Example 1: Launch GUI (recommended on Windows)
Write-Host 'Example 1: GUI mode' -ForegroundColor Cyan
# .\Create-IntuneWinFromWeb.ps1
# .\Create-IntuneWinFromWeb.ps1 -UseGui
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

# Example 4: Local installer file (no download)
Write-Host "`nExample 4: Local installer file" -ForegroundColor Cyan
# .\Create-IntuneWinFromWeb.ps1 `
#     -InstallerPath "C:\Installers\setup.exe" `
#     -AppName "MyApp" `
#     -Version "1.0.0" `
#     -Publisher "MyCompany"

# Example 5: With custom output path
Write-Host "`nExample 5: Custom output path" -ForegroundColor Cyan
# .\Create-IntuneWinFromWeb.ps1 `
#     -DownloadUrl "https://example.com/setup.exe" `
#     -AppName "MyApp" `
#     -OutputPath "C:\IntunePackages"

# Example 6: Licensing field ingested from ServiceNow
Write-Host "`nExample 6: Licensing from the ServiceNow software record" -ForegroundColor Cyan
# Per-device perpetual: the key is baked into the install command
# .\Create-IntuneWinFromWeb.ps1 `
#     -DownloadUrl "https://example.com/setup.msi" `
#     -AppName "MyApp" `
#     -LicenseInfo "Licensed - per device perpetual, 25 seats, license key 4XJ9-2210-KD77-9931, expires 2028-03-31"
#
# Concurrent/floating: the client is pointed at the license server during install
# .\Create-IntuneWinFromWeb.ps1 `
#     -InstallerPath "C:\Installers\sim.exe" `
#     -AppName "SIMION" `
#     -LicenseInfo "Concurrent FlexLM, license server 27000@lm.corp.local, 10 concurrent seats"
#
# License file: the file ships inside the .intunewin and is staged before install
# .\Create-IntuneWinFromWeb.ps1 `
#     -InstallerPath "C:\Installers\app.exe" `
#     -AppName "MyApp" `
#     -LicenseInfo "Node-locked, license file based" `
#     -LicenseFilePath "C:\Licenses\license.dat" `
#     -LicenseFileTargetPath "%ProgramData%\Vendor\license.dat"

# Example 7: PowerShell module (advanced)
Write-Host "`nExample 7: Module usage" -ForegroundColor Cyan
# Import-Module .\AppGetter.psd1
# Test-AppGetterPrerequisites
# Install-AppGetterContentPrepTool   # installs intunewinapputil via winget if missing
# Invoke-AppGetterPackaging -AppName "MyApp" -DownloadUrl "https://example.com/setup.exe"
# Invoke-AppGetterPackaging -AppName "MyApp" -InstallerPath "C:\Installers\setup.exe"
# Resolve-AppGetterLicensing -LicenseInfo "Concurrent FlexLM, license server 27000@lm.corp.local"
# Get-AppGetterLicensingPatternCatalog | Select-Object Id, LicenseType, ActivationMethod

# Example 8: Build the double-clickable AppGetter.exe (Windows only)
Write-Host "`nExample 8: Build AppGetter.exe" -ForegroundColor Cyan
# .\Build\Build-AppGetterExe.ps1
