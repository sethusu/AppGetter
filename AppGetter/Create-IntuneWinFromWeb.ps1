<#
.SYNOPSIS
    Creates an Intune Win32 package from a web download in pure PowerShell.
.DESCRIPTION
    AppGetter mirrors WinGetter-style output for web/direct-download installers:
    install.ps1, detection.ps1, uninstall.ps1, README.md, readme.txt, app.json,
    win32LobApp.json, icon files, and optional .intunewin packaging.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$WebsiteUrl,

    [Parameter(Mandatory = $false)]
    [string]$DownloadUrl,

    [Parameter(Mandatory = $false)]
    [string]$AppName,

    [Parameter(Mandatory = $false)]
    [string]$Version,

    [Parameter(Mandatory = $false)]
    [string]$Publisher,

    [Parameter(Mandatory = $false)]
    [string]$OutputPath,

    [Parameter(Mandatory = $false)]
    [string]$IconPath,

    [Parameter(Mandatory = $false)]
    [string]$InstallCommand
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Write-Step {
    param(
        [int]$Step,
        [int]$Total,
        [string]$Name
    )

    Write-Host "`n[$Step/$Total] $Name" -ForegroundColor Cyan
}

function Get-AppGetterSettings {
    $settingsRoot = Get-AppGetterSettingsRoot
    $settingsPath = Join-Path $settingsRoot 'settings.json'
    $defaultOutputPath = if ($IsWindows) {
        Join-Path $env:USERPROFILE 'Documents\AppGetter Output'
    } else {
        '/tmp/appgetter-output'
    }

    $settings = @{
        OutputPath = $defaultOutputPath
        LastSourceUrl = ''
        LastPackageId = ''
    }

    if (Test-Path $settingsPath) {
        try {
            $savedSettings = Get-Content -Path $settingsPath -Raw | ConvertFrom-Json
            foreach ($key in $settings.Keys) {
                if ($savedSettings.PSObject.Properties.Name -contains $key -and $savedSettings.$key) {
                    $settings[$key] = $savedSettings.$key
                }
            }
        } catch {
            Write-Host "Unable to read settings file, using defaults." -ForegroundColor Yellow
        }
    }

    return [PSCustomObject]$settings
}

function Save-AppGetterSettings {
    param(
        [string]$OutputPath,
        [string]$LastSourceUrl,
        [string]$LastPackageId
    )

    $settingsDir = Get-AppGetterSettingsRoot
    if (-not (Test-Path $settingsDir)) {
        New-Item -ItemType Directory -Path $settingsDir -Force | Out-Null
    }

    $currentSettings = Get-AppGetterSettings
    if ($OutputPath) { $currentSettings.OutputPath = $OutputPath }
    if ($LastSourceUrl) { $currentSettings.LastSourceUrl = $LastSourceUrl }
    if ($LastPackageId) { $currentSettings.LastPackageId = $LastPackageId }

    $currentSettings | ConvertTo-Json | Set-Content -Path (Join-Path $settingsDir 'settings.json') -Encoding UTF8
}

function Get-AppGetterSettingsRoot {
    if ($env:APPDATA) {
        return (Join-Path $env:APPDATA 'AppGetter')
    }

    if ($env:XDG_CONFIG_HOME) {
        return (Join-Path $env:XDG_CONFIG_HOME 'appgetter')
    }

    if ($env:HOME) {
        return (Join-Path $env:HOME '.config/appgetter')
    }

    return '/tmp/appgetter-config'
}

function Get-InputFromDialog {
    param(
        [string]$Title,
        [string]$Prompt,
        [string]$DefaultValue = ''
    )

    if (-not $IsWindows) {
        throw "Interactive dialog mode is only available on Windows. Please provide -AppName and -DownloadUrl or -WebsiteUrl."
    }

    Add-Type -AssemblyName Microsoft.VisualBasic
    $result = [Microsoft.VisualBasic.Interaction]::InputBox($Prompt, $Title, $DefaultValue)
    if ([string]::IsNullOrWhiteSpace($result)) {
        return $null
    }

    return $result.Trim()
}

function Find-InstallerLinksFromWebsite {
    param([string]$Url)

    $response = Invoke-WebRequest -Uri $Url -UseBasicParsing
    $html = $response.Content
    $pattern = 'href\s*=\s*[''"]([^''"]+)[''"]'
    $linkMatches = [regex]::Matches($html, $pattern, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)

    $links = @()
    foreach ($match in $linkMatches) {
        $candidate = $match.Groups[1].Value
        if ($candidate -match '\.(exe|msi|msix|appx)(\?|$)' -or $candidate -match '(?i)(download|setup|installer)') {
            if ($candidate -notmatch '^https?://') {
                $candidate = ([System.Uri]::new([System.Uri]$Url, $candidate)).AbsoluteUri
            }
            $links += $candidate
        }
    }

    return $links | Select-Object -Unique
}

function Get-VersionFromHtml {
    param(
        [string]$Html,
        [string]$Name
    )

    $escapedName = [regex]::Escape($Name)
    $versionPatterns = @(
        "(?i)$escapedName[^0-9]{0,20}(\d+\.\d+\.\d+\.\d+)",
        "(?i)$escapedName[^0-9]{0,20}(\d+\.\d+\.\d+)",
        '(?i)version[^0-9]{0,10}(\d+\.\d+\.\d+\.\d+)',
        '(?i)version[^0-9]{0,10}(\d+\.\d+\.\d+)'
    )

    foreach ($versionPattern in $versionPatterns) {
        $versionMatch = [regex]::Match($Html, $versionPattern)
        if ($versionMatch.Success) {
            return $versionMatch.Groups[1].Value
        }
    }

    return $null
}

function Get-DescriptionFromHtml {
    param([string]$Html)

    $metaPattern = '<meta\s+(?:name|property)=["''](?:description|og:description)["'']\s+content=["'']([^"'']+)["'']'
    $metaMatch = [regex]::Match($Html, $metaPattern, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    if ($metaMatch.Success -and $metaMatch.Groups[1].Value.Length -gt 15) {
        return $metaMatch.Groups[1].Value.Trim()
    }

    return $null
}

function Get-InstallerInstallCommand {
    param(
        [string]$InstallerFileName,
        [string]$InstallerExtension
    )

    switch ($InstallerExtension.ToLower()) {
        '.msi' { return "msiexec /i `"$InstallerFileName`" /quiet /norestart" }
        '.msix' { return "Add-AppxPackage -Path `"$InstallerFileName`"" }
        '.appx' { return "Add-AppxPackage -Path `"$InstallerFileName`"" }
        default { return "`"$InstallerFileName`" /S" }
    }
}

function Get-IntuneInstallCommandLine {
    return '%windir%\sysnative\windowspowershell\v1.0\powershell.exe -WindowStyle Hidden -ExecutionPolicy Bypass -File install.ps1'
}

function Get-IntuneUninstallCommandLine {
    return '%windir%\sysnative\windowspowershell\v1.0\powershell.exe -WindowStyle Hidden -ExecutionPolicy Bypass -File uninstall.ps1'
}

function New-InstallScript {
    param(
        [string]$PackageId,
        [string]$DisplayName,
        [string]$ExpectedVersion,
        [string]$RawInstallCommand
    )

    return @"
# Install script for $DisplayName
# Intune Win32 app deployment - generated by AppGetter

`$ErrorActionPreference = 'Stop'
`$packageId = '$PackageId'
`$displayName = '$DisplayName'
`$expectedVersion = '$ExpectedVersion'
`$logPath = "`$env:ProgramData\Microsoft\IntuneManagementExtension\Logs\`$packageId-install.log"

Start-Transcript -Path `$logPath -Force
Write-Host "Starting install for `$displayName (`$packageId) version `$expectedVersion"

try {
 `$scriptRoot = Split-Path -Parent `$MyInvocation.MyCommand.Path
 Set-Location -Path `$scriptRoot

 `$installCommand = @'
$RawInstallCommand
'@

 Write-Host "Executing install command: `$installCommand"
 `$process = Start-Process -FilePath 'cmd.exe' -ArgumentList "/c `$installCommand" -Wait -PassThru -NoNewWindow

 switch (`$process.ExitCode) {
  0 { Stop-Transcript; exit 0 }
  3010 { Stop-Transcript; exit 3010 }
  1641 { Stop-Transcript; exit 1641 }
  1618 { Stop-Transcript; exit 1618 }
  default {
   Write-Host "Install failed with exit code `$(`$process.ExitCode)"
   Stop-Transcript
   exit `$process.ExitCode
  }
 }
}
catch {
 Write-Host "Install error: `$_"
 Stop-Transcript
 exit 1
}
"@
}

function New-DetectionScript {
    param(
        [string]$PackageId,
        [string]$DisplayName,
        [string]$ExpectedVersion
    )

    return @"
# Registry-based detection script for $DisplayName
# Intune Win32 app deployment - generated by AppGetter

`$ErrorActionPreference = 'Continue'
`$packageId = '$PackageId'
`$displayName = '$DisplayName'
`$version = '$ExpectedVersion'
`$logPath = "`$env:ProgramData\Microsoft\IntuneManagementExtension\Logs\`$packageId-detection.log"

Start-Transcript -Path `$logPath -Force
Write-Host "Starting detection for `$displayName (`$packageId), expected version `$version"

`$registryPaths = @(
 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
)

`$matches = @()
foreach (`$path in `$registryPaths) {
 try {
  `$entries = Get-ItemProperty `$path -ErrorAction SilentlyContinue
  if (-not `$entries) { continue }
  foreach (`$entry in `$entries) {
   if (`$entry.DisplayName -like '*$DisplayName*' -or `$entry.PSChildName -like '*$PackageId*') {
    if (`$entry.DisplayVersion) {
     `$matches += [PSCustomObject]@{
      Name = `$entry.DisplayName
      Version = `$entry.DisplayVersion
     }
    }
   }
  }
 } catch {
  Write-Host "Error reading registry path `$path : `$_"
 }
}

if (`$matches.Count -eq 0) {
 Write-Host 'Application not detected.'
 Stop-Transcript
 exit 1
}

`$installedVersion = (`$matches | Sort-Object {
 try { [version]`$_.Version } catch { [version]'0.0.0' }
} -Descending | Select-Object -First 1).Version

Write-Host "Detected version: `$installedVersion"

if ([string]::IsNullOrWhiteSpace(`$version) -or `$version -eq 'latest') {
 Stop-Transcript
 exit 0
}

try {
 if ([version]`$installedVersion -ge [version]`$version) {
  Stop-Transcript
  exit 0
 }
 Stop-Transcript
 exit 1
} catch {
 if (`$installedVersion -ge `$version) {
  Stop-Transcript
  exit 0
 }
 Stop-Transcript
 exit 1
}
"@
}

function New-UninstallScript {
    param(
        [string]$PackageId,
        [string]$DisplayName
    )

    return @"
# Uninstall script for $DisplayName
# Intune Win32 app deployment - generated by AppGetter

`$ErrorActionPreference = 'Stop'
`$packageId = '$PackageId'
`$displayName = '$DisplayName'
`$logPath = "`$env:ProgramData\Microsoft\IntuneManagementExtension\Logs\`$packageId-uninstall.log"

Start-Transcript -Path `$logPath -Force
Write-Host "Starting uninstall for `$displayName (`$packageId)"

`$registryPaths = @(
 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
)

`$uninstallString = `$null
`$quietUninstallString = `$null
foreach (`$path in `$registryPaths) {
 `$entries = Get-ItemProperty `$path -ErrorAction SilentlyContinue | Where-Object {
  `$_.DisplayName -like '*$DisplayName*' -or `$_.PSChildName -like '*$PackageId*'
 }
 foreach (`$entry in `$entries) {
  if (`$entry.DisplayName -like '*$DisplayName*') {
   `$uninstallString = `$entry.UninstallString
   `$quietUninstallString = `$entry.QuietUninstallString
   break
  }
 }
 if (`$uninstallString) { break }
}

if (-not `$uninstallString) {
 Write-Host 'Uninstall string not found in registry.'
 Stop-Transcript
 exit 1
}

`$command = if (`$quietUninstallString) { `$quietUninstallString } else { `$uninstallString }
if (`$command -notmatch '/S' -and `$command -match '\.exe') {
 `$command = `$command -replace '"([^"]+\.exe)"', '"`$1" /S'
}

`$process = Start-Process -FilePath 'cmd.exe' -ArgumentList "/c `$command" -Wait -PassThru -NoNewWindow
if (`$process.ExitCode -eq 0 -or `$process.ExitCode -eq 3010) {
 Stop-Transcript
 exit 0
}

Stop-Transcript
exit `$process.ExitCode
"@
}

function New-ReadmeMarkdown {
    param(
        [pscustomobject]$PackageDetails,
        [string]$InstallerFileName,
        [string]$InstallerHash,
        [string]$IntuneWinFileName,
        [string]$InstallerInstallCommand,
        [bool]$HasIcon
    )

    $generatedAt = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $publisherValue = if ($PackageDetails.Publisher) { $PackageDetails.Publisher } else { 'Unknown' }
    $descriptionValue = if ($PackageDetails.Description) { $PackageDetails.Description } else { '_No description was discovered from the website._' }

    return @"
# $($PackageDetails.DisplayName) - Intune Win32 Package

Generated by **AppGetter** on $generatedAt.

## Application Description

$descriptionValue

## Intune Portal Upload Reference

| Intune field | Value |
|---|---|
| **Name / Display name** | $($PackageDetails.DisplayName) |
| **Description** | $descriptionValue |
| **Publisher** | $publisherValue |
| **App version / Display version** | $($PackageDetails.Version) |
| **Package identifier** | ``$($PackageDetails.PackageId)`` |
| **Information URL** | $($PackageDetails.InformationUrl) |
| **Download URL** | $($PackageDetails.DownloadUrl) |
| **Install command (installer)** | ``$InstallerInstallCommand`` |
| **Install command (Intune)** | ``$(Get-IntuneInstallCommandLine)`` |
| **Uninstall command (Intune)** | ``$(Get-IntuneUninstallCommandLine)`` |
| **Setup file / Installer file name** | ``$InstallerFileName`` |
| **IntuneWin package file** | ``$IntuneWinFileName`` |
| **Installer SHA-256** | ``$InstallerHash`` |
| **Detection method** | PowerShell script (registry-based version check) |
| **Applicable architecture** | x64 |
| **Minimum Windows release** | Windows 10 2004 (20H1) |
| **Install behavior** | System |
| **Allow available uninstall** | Yes |
| **Return codes** | 0, 1707 (success); 3010, 1641 (reboot); 1618 (retry) |
| **Icon included** | $(if ($HasIcon) { 'Yes (icon.png)' } else { 'No' }) |

## Package Contents

| File | Purpose |
|---|---|
| ``install.ps1`` | Silent install wrapper with Intune return-code handling |
| ``detection.ps1`` | Registry-based detection |
| ``uninstall.ps1`` | Quiet uninstall wrapper |
| ``README.md`` | This Intune upload guide |
| ``readme.txt`` | Legacy plain-text reference |
| ``app.json`` | AppGetter metadata export |
| ``win32LobApp.json`` | Microsoft Graph ``win32LobApp`` definition |

## Next Steps

1. Review and test the generated scripts in this folder.
2. Upload ``$IntuneWinFileName`` in Intune (**Apps** -> **Windows** -> **Add** -> **Windows app (Win32)**).
3. Use the table values above during wizard configuration.
4. Assign the app to a pilot group before broad rollout.
"@
}

function Get-ImageMimeType {
    param([byte[]]$Bytes)

    if ($Bytes.Length -lt 4) { return $null }
    if ($Bytes[0] -eq 0x89 -and $Bytes[1] -eq 0x50 -and $Bytes[2] -eq 0x4E -and $Bytes[3] -eq 0x47) { return 'image/png' }
    if ($Bytes[0] -eq 0xFF -and $Bytes[1] -eq 0xD8 -and $Bytes[2] -eq 0xFF) { return 'image/jpeg' }
    if ($Bytes[0] -eq 0x47 -and $Bytes[1] -eq 0x49 -and $Bytes[2] -eq 0x46) { return 'image/gif' }
    return $null
}

$settings = Get-AppGetterSettings
if (-not $OutputPath) {
    $OutputPath = $settings.OutputPath
}

if ([string]::IsNullOrWhiteSpace($AppName)) {
    $AppName = Get-InputFromDialog -Title 'AppGetter - Application Name' -Prompt 'Enter the application name or package label:' -DefaultValue $settings.LastPackageId
}
if ([string]::IsNullOrWhiteSpace($AppName)) {
    throw 'AppName is required.'
}

if ([string]::IsNullOrWhiteSpace($DownloadUrl) -and [string]::IsNullOrWhiteSpace($WebsiteUrl)) {
    $DownloadUrl = Get-InputFromDialog -Title 'AppGetter - Download URL' -Prompt 'Enter direct installer URL (or leave blank to discover from website):'
    if ([string]::IsNullOrWhiteSpace($DownloadUrl)) {
        $WebsiteUrl = Get-InputFromDialog -Title 'AppGetter - Website URL' -Prompt 'Enter website URL to discover installer links:'
    }
}

if ([string]::IsNullOrWhiteSpace($DownloadUrl) -and [string]::IsNullOrWhiteSpace($WebsiteUrl)) {
    throw 'Provide DownloadUrl or WebsiteUrl.'
}

$totalSteps = 12
Write-Step -Step 1 -Total $totalSteps -Name 'Selecting download source'
$finalDownloadUrl = $DownloadUrl

if (-not $finalDownloadUrl) {
    $links = Find-InstallerLinksFromWebsite -Url $WebsiteUrl
    if ($links.Count -eq 0) {
        throw "No installer links were discovered on $WebsiteUrl. Use -DownloadUrl with a direct installer link."
    }

    $finalDownloadUrl = $links |
        Where-Object { $_ -match '\.(exe|msi|msix|appx)(\?|$)' } |
        Select-Object -First 1

    if (-not $finalDownloadUrl) {
        $finalDownloadUrl = $links[0]
    }
    Write-Host "Using discovered installer URL: $finalDownloadUrl" -ForegroundColor Green
} else {
    Write-Host "Using provided installer URL: $finalDownloadUrl" -ForegroundColor Green
}

Write-Step -Step 2 -Total $totalSteps -Name 'Reading metadata from source'
$pageHtml = $null
if ($WebsiteUrl) {
    try {
        $pageHtml = (Invoke-WebRequest -Uri $WebsiteUrl -UseBasicParsing).Content
    } catch {
        Write-Host "Website metadata lookup skipped: $_" -ForegroundColor Yellow
    }
}

if (-not $Version -and $pageHtml) {
    $Version = Get-VersionFromHtml -Html $pageHtml -Name $AppName
}
if (-not $Version) { $Version = 'latest' }

$description = if ($pageHtml) { Get-DescriptionFromHtml -Html $pageHtml } else { $null }
if (-not $description) { $description = "$AppName package generated by AppGetter from web download." }

Write-Step -Step 3 -Total $totalSteps -Name 'Creating output folders'
$packageId = ($AppName -replace '[^a-zA-Z0-9\.\-_]', '').Trim('.')
if ([string]::IsNullOrWhiteSpace($packageId)) {
    $packageId = ($AppName -replace '[^a-zA-Z0-9]', '')
}
$appDirectory = Join-Path $OutputPath $packageId
$versionDirectory = Join-Path $appDirectory $Version
New-Item -ItemType Directory -Path $versionDirectory -Force | Out-Null

Write-Step -Step 4 -Total $totalSteps -Name 'Downloading installer'
$installerFileName = [System.IO.Path]::GetFileName($finalDownloadUrl.Split('?')[0])
if ([string]::IsNullOrWhiteSpace($installerFileName)) {
    throw 'Unable to determine installer file name from URL.'
}
$installerPath = Join-Path $versionDirectory $installerFileName
Invoke-WebRequest -Uri $finalDownloadUrl -OutFile $installerPath -UseBasicParsing
$installerFile = Get-Item $installerPath

Write-Step -Step 5 -Total $totalSteps -Name 'Building install command'
$rawInstallCommand = if ($InstallCommand) {
    $InstallCommand
} else {
    Get-InstallerInstallCommand -InstallerFileName $installerFile.Name -InstallerExtension $installerFile.Extension
}

Write-Step -Step 6 -Total $totalSteps -Name 'Calculating installer hash'
$installerHash = (Get-FileHash -Path $installerFile.FullName -Algorithm SHA256).Hash

Write-Step -Step 7 -Total $totalSteps -Name 'Generating install/detection/uninstall scripts'
$installScript = New-InstallScript -PackageId $packageId -DisplayName $AppName -ExpectedVersion $Version -RawInstallCommand $rawInstallCommand
$detectionScript = New-DetectionScript -PackageId $packageId -DisplayName $AppName -ExpectedVersion $Version
$uninstallScript = New-UninstallScript -PackageId $packageId -DisplayName $AppName

$installScriptPath = Join-Path $versionDirectory 'install.ps1'
$detectionScriptPath = Join-Path $versionDirectory 'detection.ps1'
$uninstallScriptPath = Join-Path $versionDirectory 'uninstall.ps1'

$installScript | Set-Content -Path $installScriptPath -Encoding UTF8
$detectionScript | Set-Content -Path $detectionScriptPath -Encoding UTF8
$uninstallScript | Set-Content -Path $uninstallScriptPath -Encoding UTF8

Write-Step -Step 8 -Total $totalSteps -Name 'Resolving icon'
$iconFilePath = Join-Path $versionDirectory 'icon.png'
$logoFilePath = Join-Path $appDirectory 'logo.png'

if ($IconPath -and (Test-Path $IconPath)) {
    Copy-Item -Path $IconPath -Destination $logoFilePath -Force
    Copy-Item -Path $IconPath -Destination $iconFilePath -Force
    Write-Host 'Using user-supplied icon.' -ForegroundColor Green
} elseif (Test-Path $logoFilePath) {
    Copy-Item -Path $logoFilePath -Destination $iconFilePath -Force
    Write-Host 'Using existing app-level logo.png.' -ForegroundColor Green
} else {
    Write-Host 'No icon provided/found; package will be created without icon.' -ForegroundColor Yellow
}

Write-Step -Step 9 -Total $totalSteps -Name 'Writing README and metadata'
$packageDetails = [PSCustomObject]@{
    PackageId = $packageId
    DisplayName = $AppName
    Version = $Version
    Publisher = if ($Publisher) { $Publisher } else { 'Unknown' }
    InformationUrl = if ($WebsiteUrl) { $WebsiteUrl } else { '' }
    DownloadUrl = $finalDownloadUrl
    Description = $description
}

$intuneWinFileName = "$($installerFile.BaseName).intunewin"
$hasIcon = Test-Path $iconFilePath
$readmeMd = New-ReadmeMarkdown -PackageDetails $packageDetails -InstallerFileName $installerFile.Name -InstallerHash $installerHash -IntuneWinFileName $intuneWinFileName -InstallerInstallCommand $rawInstallCommand -HasIcon $hasIcon
$readmeTxt = @"
Package $($packageDetails.PackageId) $($packageDetails.Version) from web download

Display name: $($packageDetails.DisplayName)
Version: $($packageDetails.Version)
Publisher: $($packageDetails.Publisher)
Information URL: $($packageDetails.InformationUrl)
Download URL: $($packageDetails.DownloadUrl)

Install command (Intune):
$(Get-IntuneInstallCommandLine)

Uninstall command (Intune):
$(Get-IntuneUninstallCommandLine)

See README.md for full Intune upload guidance.
"@

$readmeMd | Set-Content -Path (Join-Path $versionDirectory 'README.md') -Encoding UTF8
$readmeTxt | Set-Content -Path (Join-Path $versionDirectory 'readme.txt') -Encoding UTF8

$appJson = @{
    packageIdentifier = $packageDetails.PackageId
    displayName = $packageDetails.DisplayName
    description = $packageDetails.Description
    version = $packageDetails.Version
    source = 3
    publisher = $packageDetails.Publisher
    informationUrl = $packageDetails.InformationUrl
    publisherUrl = $packageDetails.InformationUrl
    supportUrl = $packageDetails.InformationUrl
    installerType = 7
    installerUrl = $packageDetails.DownloadUrl
    hash = $installerHash
    installCommandLine = (Get-IntuneInstallCommandLine)
    uninstallCommandLine = (Get-IntuneUninstallCommandLine)
    installerFilename = $installerFile.Name
    installerContext = 2
    architecture = 2
}
$appJson | ConvertTo-Json -Depth 10 | Set-Content -Path (Join-Path $versionDirectory 'app.json') -Encoding UTF8

$detectionScriptBase64 = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($detectionScript))
$iconBase64 = ''
$iconMimeType = 'image/png'
if ($hasIcon) {
    $iconBytes = [System.IO.File]::ReadAllBytes($iconFilePath)
    $iconBase64 = [Convert]::ToBase64String($iconBytes)
    $mimeType = Get-ImageMimeType -Bytes $iconBytes
    if ($mimeType) { $iconMimeType = $mimeType }
}

$win32LobAppJson = @{
    '@odata.type' = '#microsoft.graph.win32LobApp'
    description = $packageDetails.Description
    developer = $packageDetails.Publisher
    displayName = $packageDetails.DisplayName
    informationUrl = $packageDetails.InformationUrl
    largeIcon = if ($iconBase64) { @{ type = $iconMimeType; value = $iconBase64 } } else { $null }
    notes = "Generated by AppGetter at $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') [Web|$($packageDetails.PackageId)]"
    publisher = $packageDetails.Publisher
    fileName = $intuneWinFileName
    allowAvailableUninstall = $true
    applicableArchitectures = 'x64'
    detectionRules = @(
        @{
            '@odata.type' = '#microsoft.graph.win32LobAppPowerShellScriptDetection'
            enforceSignatureCheck = $false
            runAs32Bit = $false
            scriptContent = $detectionScriptBase64
        }
    )
    displayVersion = $packageDetails.Version
    installCommandLine = (Get-IntuneInstallCommandLine)
    installExperience = @{
        deviceRestartBehavior = 'basedOnReturnCode'
        runAsAccount = 'system'
    }
    minimumSupportedOperatingSystem = @{ v10_2004 = $true }
    minimumSupportedWindowsRelease = '2004'
    returnCodes = @(
        @{ returnCode = 0; type = 'success' }
        @{ returnCode = 1707; type = 'success' }
        @{ returnCode = 3010; type = 'softReboot' }
        @{ returnCode = 1641; type = 'hardReboot' }
        @{ returnCode = 1618; type = 'retry' }
    )
    setupFilePath = $installerFile.Name
    uninstallCommandLine = (Get-IntuneUninstallCommandLine)
}
if (-not $iconBase64) {
    $win32LobAppJson.Remove('largeIcon')
}
$win32LobAppJson | ConvertTo-Json -Depth 10 | Set-Content -Path (Join-Path $versionDirectory 'win32LobApp.json') -Encoding UTF8

Write-Step -Step 10 -Total $totalSteps -Name 'Creating .intunewin package'
$outputDirectory = Split-Path $versionDirectory -Parent
$intuneWinPath = Join-Path $outputDirectory $intuneWinFileName
$packagingSucceeded = $false
$intunewinTool = Get-Command intunewinapputil -ErrorAction SilentlyContinue

if ($intunewinTool) {
    if (Test-Path $intuneWinPath) {
        Remove-Item -Path $intuneWinPath -Force
    }

    & intunewinapputil -c $versionDirectory -s $installerFile.Name -o $outputDirectory -q
    if ($LASTEXITCODE -eq 0 -and (Test-Path $intuneWinPath)) {
        $packagingSucceeded = $true
    } else {
        Write-Host 'Packaging step failed, but scripts and metadata were generated.' -ForegroundColor Yellow
    }
} else {
    Write-Host 'intunewinapputil not found. Packaging skipped; metadata/scripts are ready.' -ForegroundColor Yellow
}

Write-Step -Step 11 -Total $totalSteps -Name 'Saving AppGetter settings'
Save-AppGetterSettings -OutputPath $OutputPath -LastSourceUrl $(if ($WebsiteUrl) { $WebsiteUrl } else { $finalDownloadUrl }) -LastPackageId $packageId

Write-Step -Step 12 -Total $totalSteps -Name 'Completed'
Write-Host @"
Package Details:
- Application: $($packageDetails.DisplayName)
- Package ID: $($packageDetails.PackageId)
- Version: $($packageDetails.Version)
- Publisher: $($packageDetails.Publisher)
- Download URL: $($packageDetails.DownloadUrl)
- Output directory: $versionDirectory
- IntuneWin package: $(if ($packagingSucceeded) { $intuneWinPath } else { '(not created)' })

Files created:
- install.ps1
- detection.ps1
- uninstall.ps1
- README.md
- readme.txt
- app.json
- win32LobApp.json
- $($installerFile.Name)
"@ -ForegroundColor Green
