<#
.SYNOPSIS
Creates Intune Win32 packaging artifacts from a web installer URL.
.DESCRIPTION
AppGetter now mirrors the WinGetter packaging model while staying PowerShell-only:
download installer -> generate install/detection/uninstall scripts -> write metadata ->
run intunewinapputil.
.PARAMETER WebsiteUrl
Web page that contains installer links.
.PARAMETER DownloadUrl
Direct installer URL. Prefer this for non-interactive runs.
.PARAMETER AppName
Display name for the package.
.PARAMETER Version
Package version. Defaults to a value inferred from URL/content or "latest".
.PARAMETER Publisher
Publisher used in metadata.
.PARAMETER OutputPath
Base output folder. Defaults to saved settings, then Documents/AppGetter Output.
.PARAMETER IconPath
Optional custom icon file copied to logo.png/icon.png.
.PARAMETER InstallCommand
Optional raw installer command executed by generated install.ps1.
#>

[CmdletBinding()]
param(
    [string]$WebsiteUrl,
    [string]$DownloadUrl,
    [string]$AppName,
    [string]$Version,
    [string]$Publisher,
    [string]$OutputPath,
    [string]$IconPath,
    [string]$InstallCommand
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

function Write-Step {
    param([string]$Message)
    Write-Host "`n[$Message]" -ForegroundColor Cyan
}

function Write-Success {
    param([string]$Message)
    Write-Host "[SUCCESS] $Message" -ForegroundColor Green
}

function Get-AppGetterSettingsPath {
    if ($env:APPDATA) {
        $base = Join-Path $env:APPDATA "AppGetter"
    } elseif ($env:HOME) {
        $base = Join-Path $env:HOME ".appgetter"
    } else {
        $base = Join-Path ([System.IO.Path]::GetTempPath()) "AppGetter"
    }
    if (-not (Test-Path $base)) {
        New-Item -ItemType Directory -Path $base -Force | Out-Null
    }
    return Join-Path $base "settings.json"
}

function Get-AppGetterSettings {
    $fallbackOutput = if ($env:HOME) {
        Join-Path $env:HOME "Documents/AppGetter Output"
    } else {
        Join-Path ([System.IO.Path]::GetTempPath()) "AppGetter Output"
    }

    $defaults = @{
        OutputPath = $fallbackOutput
        LastPackageId = ""
    }

    $path = Get-AppGetterSettingsPath
    if (Test-Path $path) {
        try {
            $loaded = Get-Content -Path $path -Raw | ConvertFrom-Json
            if ($loaded.OutputPath) { $defaults.OutputPath = $loaded.OutputPath }
            if ($loaded.LastPackageId) { $defaults.LastPackageId = $loaded.LastPackageId }
        } catch {
            Write-Host "Unable to parse settings.json, using defaults." -ForegroundColor Yellow
        }
    }

    return [pscustomobject]$defaults
}

function Save-AppGetterSettings {
    param([string]$OutputPath, [string]$LastPackageId)
    $settings = Get-AppGetterSettings
    if ($OutputPath) { $settings.OutputPath = $OutputPath }
    if ($LastPackageId) { $settings.LastPackageId = $LastPackageId }
    $settings | ConvertTo-Json | Set-Content -Path (Get-AppGetterSettingsPath) -Encoding UTF8
}

function Get-DownloadLinksFromWeb {
    param([string]$Url)
    $response = Invoke-WebRequest -Uri $Url -UseBasicParsing
    $html = $response.Content
    $patterns = @(
        'href\s*=\s*["'']([^"''\s>]+\.(exe|msi|msix|appx))(["''\s>])',
        'https?://[^\s"''<>]+\.(exe|msi|msix|appx)'
    )

    $results = New-Object System.Collections.Generic.List[string]
    foreach ($pattern in $patterns) {
        $matches = [regex]::Matches($html, $pattern, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
        foreach ($match in $matches) {
            $link = if ($match.Groups[1].Success) { $match.Groups[1].Value } else { $match.Value }
            if ($link -notmatch '^https?://') {
                $link = [System.Uri]::new([System.Uri]$Url, $link).AbsoluteUri
            }
            if (-not $results.Contains($link)) {
                $results.Add($link)
            }
        }
    }
    return $results
}

function Resolve-Version {
    param([string]$ExplicitVersion, [string]$DownloadUrl, [string]$WebsiteUrl)
    if ($ExplicitVersion) { return $ExplicitVersion }
    if ($DownloadUrl -match '(\d+\.\d+\.\d+\.\d+|\d+\.\d+\.\d+)') {
        return $matches[1]
    }
    if ($WebsiteUrl) {
        try {
            $html = (Invoke-WebRequest -Uri $WebsiteUrl -UseBasicParsing).Content
            if ($html -match '(?i)\bversion\D+(\d+\.\d+\.\d+\.\d+|\d+\.\d+\.\d+)\b') {
                return $matches[1]
            }
        } catch {
            Write-Host "Version could not be extracted from website." -ForegroundColor Yellow
        }
    }
    return "latest"
}

function Resolve-Description {
    param([string]$AppName, [string]$Publisher, [string]$WebsiteUrl)
    if ($WebsiteUrl) {
        try {
            $html = (Invoke-WebRequest -Uri $WebsiteUrl -UseBasicParsing).Content
            if ($html -match '<meta\s+name=["'']description["'']\s+content=["'']([^"'']+)["'']') {
                return $matches[1].Trim()
            }
            if ($html -match '<meta\s+property=["'']og:description["'']\s+content=["'']([^"'']+)["'']') {
                return $matches[1].Trim()
            }
        } catch {
            Write-Host "Description extraction failed, using default." -ForegroundColor Yellow
        }
    }

    if ($Publisher) {
        return "$AppName by $Publisher packaged with AppGetter."
    }
    return "$AppName packaged with AppGetter."
}

function Get-InstallerInstallCommand {
    param([string]$InstallerFileName, [string]$InstallerExtension)
    $ext = $InstallerExtension.ToLowerInvariant()
    switch ($ext) {
        ".msi"  { return "msiexec /i `"$InstallerFileName`" /quiet /norestart" }
        ".msix" { return "Add-AppxPackage -Path `"$InstallerFileName`"" }
        ".appx" { return "Add-AppxPackage -Path `"$InstallerFileName`"" }
        default { return "`"$InstallerFileName`" /S" }
    }
}

function New-InstallScript {
    param([string]$PackageId, [string]$DisplayName, [string]$ExpectedVersion, [string]$RawInstallCommand)
    return @"
# Install script for $DisplayName
# Intune Win32 deployment script generated by AppGetter

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
        default { Stop-Transcript; exit `$process.ExitCode }
    }
}
catch {
    Write-Host "Install failed: `$_"
    Stop-Transcript
    exit 1
}
"@
}

function New-DetectionScript {
    param([string]$PackageId, [string]$DisplayName, [string]$ExpectedVersion)
    return @"
# Registry-based detection script for $DisplayName
# Intune Win32 deployment script generated by AppGetter

`$ErrorActionPreference = 'Continue'
`$packageId = '$PackageId'
`$displayName = '$DisplayName'
`$expectedVersion = '$ExpectedVersion'
`$logPath = "`$env:ProgramData\Microsoft\IntuneManagementExtension\Logs\`$packageId-detection.log"

Start-Transcript -Path `$logPath -Force
`$registryPaths = @(
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
    'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
)

`$foundVersions = @()
foreach (`$path in `$registryPaths) {
    try {
        `$keys = Get-ItemProperty `$path -ErrorAction SilentlyContinue | Where-Object {
            (`$_.DisplayName -and `$_.DisplayName -like "*$DisplayName*") -or
            (`$_.PSChildName -and (`$_.PSChildName -like "*$PackageId*" -or `$_.PSChildName -like "*$($PackageId.ToLower())*"))
        }
        foreach (`$key in `$keys) {
            if (`$key.DisplayVersion) {
                `$foundVersions += `$key.DisplayVersion
            }
        }
    } catch {
        Write-Host "Failed to inspect `$path: `$_"
    }
}

if (`$foundVersions.Count -eq 0) {
    Stop-Transcript
    exit 1
}

`$detectedVersion = (`$foundVersions | Sort-Object { try { [version]`$_ } catch { [version]'0.0.0' } } -Descending | Select-Object -First 1)
if ([string]::IsNullOrWhiteSpace(`$expectedVersion) -or `$expectedVersion -eq 'latest') {
    Stop-Transcript
    exit 0
}

try {
    if ([version]`$detectedVersion -ge [version]`$expectedVersion) {
        Stop-Transcript
        exit 0
    }
    Stop-Transcript
    exit 1
}
catch {
    if (`$detectedVersion -ge `$expectedVersion) {
        Stop-Transcript
        exit 0
    }
    Stop-Transcript
    exit 1
}
"@
}

function New-UninstallScript {
    param([string]$PackageId, [string]$DisplayName)
    return @"
# Uninstall script for $DisplayName
# Intune Win32 deployment script generated by AppGetter

`$ErrorActionPreference = 'Stop'
`$packageId = '$PackageId'
`$displayName = '$DisplayName'
`$logPath = "`$env:ProgramData\Microsoft\IntuneManagementExtension\Logs\`$packageId-uninstall.log"

Start-Transcript -Path `$logPath -Force
`$registryPaths = @(
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
    'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
)

`$uninstallString = `$null
`$quietUninstallString = `$null
foreach (`$path in `$registryPaths) {
    `$match = Get-ItemProperty `$path -ErrorAction SilentlyContinue | Where-Object {
        (`$_.DisplayName -and `$_.DisplayName -like "*$DisplayName*") -or
        (`$_.PSChildName -and (`$_.PSChildName -like "*$PackageId*" -or `$_.PSChildName -like "*$($PackageId.ToLower())*"))
    } | Select-Object -First 1
    if (`$match) {
        `$uninstallString = `$match.UninstallString
        `$quietUninstallString = `$match.QuietUninstallString
        break
    }
}

if (-not `$uninstallString) {
    Stop-Transcript
    exit 1
}

`$cmd = if (`$quietUninstallString) { `$quietUninstallString } else { `$uninstallString }
if (`$cmd -notmatch '/S' -and `$cmd -match '\.exe') {
    `$cmd = `$cmd -replace '"([^"]+\.exe)"', '"`$1" /S'
}
`$process = Start-Process -FilePath 'cmd.exe' -ArgumentList "/c `$cmd" -Wait -PassThru -NoNewWindow

if (`$process.ExitCode -eq 0 -or `$process.ExitCode -eq 3010) {
    Stop-Transcript
    exit 0
}
Stop-Transcript
exit `$process.ExitCode
"@
}

function Resolve-Icon {
    param([string]$IconPath, [string]$WebsiteUrl, [string]$AppDirectory, [string]$VersionDirectory)
    $logoPath = Join-Path $AppDirectory "logo.png"
    $iconPathFinal = Join-Path $VersionDirectory "icon.png"

    if ($IconPath -and (Test-Path $IconPath)) {
        Copy-Item -Path $IconPath -Destination $logoPath -Force
        Copy-Item -Path $IconPath -Destination $iconPathFinal -Force
        return $iconPathFinal
    }
    if (Test-Path $logoPath) {
        Copy-Item -Path $logoPath -Destination $iconPathFinal -Force
        return $iconPathFinal
    }

    if (-not $WebsiteUrl) {
        return $null
    }

    $faviconCandidates = @(
        [System.Uri]::new([System.Uri]$WebsiteUrl, "/favicon.ico").AbsoluteUri,
        [System.Uri]::new([System.Uri]$WebsiteUrl, "/favicon.png").AbsoluteUri
    )
    foreach ($candidate in $faviconCandidates) {
        try {
            Invoke-WebRequest -Uri $candidate -OutFile $logoPath -UseBasicParsing
            Copy-Item -Path $logoPath -Destination $iconPathFinal -Force
            return $iconPathFinal
        } catch {
            if (Test-Path $logoPath) {
                Remove-Item $logoPath -Force -ErrorAction SilentlyContinue
            }
        }
    }
    return $null
}

function Get-ReadmeMarkdown {
    param(
        [string]$AppName,
        [string]$PackageId,
        [string]$Version,
        [string]$Description,
        [string]$Publisher,
        [string]$WebsiteUrl,
        [string]$InstallerFileName,
        [string]$IntuneWinFileName,
        [string]$InstallerHash,
        [string]$RawInstallCommand,
        [bool]$HasIcon
    )

    $intuneInstall = '%windir%\sysnative\windowspowershell\v1.0\powershell.exe -WindowStyle Hidden -ExecutionPolicy Bypass -File install.ps1'
    $intuneUninstall = '%windir%\sysnative\windowspowershell\v1.0\powershell.exe -WindowStyle Hidden -ExecutionPolicy Bypass -File uninstall.ps1'
    $generatedAt = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

    return @"
# $AppName - Intune Win32 Package

Generated by **AppGetter** on $generatedAt.

## Application Description

$Description

## Intune Portal Upload Reference

| Intune field | Value |
|---|---|
| **Display name** | $AppName |
| **Description** | $Description |
| **Publisher** | $Publisher |
| **Version** | $Version |
| **Package identifier** | ``$PackageId`` |
| **Information URL** | $WebsiteUrl |
| **Install command** | ``$intuneInstall`` |
| **Uninstall command** | ``$intuneUninstall`` |
| **Setup file** | ``$InstallerFileName`` |
| **IntuneWin package** | ``$IntuneWinFileName`` |
| **Installer SHA-256** | ``$InstallerHash`` |
| **Detection method** | PowerShell script (registry-based version check) |
| **Install behavior** | System |
| **Device restart behavior** | Based on return code |
| **Return codes** | 0, 1707 success; 3010, 1641 reboot; 1618 retry |
| **Icon included** | $(if ($HasIcon) { "Yes (`icon.png`)" } else { "No" }) |

## Package Contents

- ``install.ps1`` silent installer wrapper.
- ``detection.ps1`` registry detection script.
- ``uninstall.ps1`` quiet uninstall script.
- ``app.json`` metadata export.
- ``win32LobApp.json`` Graph Win32 LOB template.
- ``readme.txt`` plain text companion.

## Raw Installer Command

``````powershell
$RawInstallCommand
``````
"@
}

Write-Step "Step 1: Resolving input values"
$settings = Get-AppGetterSettings

if (-not $AppName) {
    $AppName = Read-Host "Enter application name"
}
if (-not $AppName) {
    throw "AppName is required."
}

if (-not $OutputPath) {
    $OutputPath = $settings.OutputPath
}
if (-not (Test-Path $OutputPath)) {
    New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null
}

$finalDownloadUrl = $DownloadUrl
if (-not $finalDownloadUrl) {
    if (-not $WebsiteUrl) {
        throw "Provide either -DownloadUrl or -WebsiteUrl."
    }
    Write-Step "Step 2: Discovering installer URL from website"
    $links = Get-DownloadLinksFromWeb -Url $WebsiteUrl
    if (-not $links -or $links.Count -eq 0) {
        throw "No installer links (.exe/.msi/.msix/.appx) were found at $WebsiteUrl."
    }
    $finalDownloadUrl = $links[0]
    Write-Success "Resolved installer URL: $finalDownloadUrl"
}

$packageId = ($AppName -replace '[^a-zA-Z0-9\.-]', '.').Trim('.')
if (-not $packageId) {
    $packageId = ($AppName -replace '\s+', '')
}
$resolvedVersion = Resolve-Version -ExplicitVersion $Version -DownloadUrl $finalDownloadUrl -WebsiteUrl $WebsiteUrl
$description = Resolve-Description -AppName $AppName -Publisher $Publisher -WebsiteUrl $WebsiteUrl
if (-not $Publisher) { $Publisher = "Unknown" }
if (-not $WebsiteUrl) { $WebsiteUrl = "" }

Write-Step "Step 3: Creating output structure"
$appDirectory = Join-Path $OutputPath $packageId
$versionDirectory = Join-Path $appDirectory $resolvedVersion
New-Item -ItemType Directory -Path $versionDirectory -Force | Out-Null

Write-Step "Step 4: Downloading installer"
$installerFileName = [System.IO.Path]::GetFileName(($finalDownloadUrl -split '\?')[0])
if (-not $installerFileName) {
    throw "Could not derive installer filename from URL."
}
$installerPath = Join-Path $versionDirectory $installerFileName
Invoke-WebRequest -Uri $finalDownloadUrl -OutFile $installerPath -UseBasicParsing
$installerFile = Get-Item $installerPath
Write-Success "Downloaded $installerFileName"

Write-Step "Step 5: Building commands and scripts"
$rawInstallCommand = if ($InstallCommand) {
    $InstallCommand
} else {
    Get-InstallerInstallCommand -InstallerFileName $installerFile.Name -InstallerExtension $installerFile.Extension
}
$installScript = New-InstallScript -PackageId $packageId -DisplayName $AppName -ExpectedVersion $resolvedVersion -RawInstallCommand $rawInstallCommand
$detectionScript = New-DetectionScript -PackageId $packageId -DisplayName $AppName -ExpectedVersion $resolvedVersion
$uninstallScript = New-UninstallScript -PackageId $packageId -DisplayName $AppName

$installerHash = (Get-FileHash -Path $installerPath -Algorithm SHA256).Hash
$iconFilePath = Resolve-Icon -IconPath $IconPath -WebsiteUrl $WebsiteUrl -AppDirectory $appDirectory -VersionDirectory $versionDirectory

Write-Step "Step 6: Writing metadata and helper files"
$installScriptPath = Join-Path $versionDirectory "install.ps1"
$detectionScriptPath = Join-Path $versionDirectory "detection.ps1"
$uninstallScriptPath = Join-Path $versionDirectory "uninstall.ps1"
$readmePath = Join-Path $versionDirectory "README.md"
$legacyReadmePath = Join-Path $versionDirectory "readme.txt"
$appJsonPath = Join-Path $versionDirectory "app.json"
$win32JsonPath = Join-Path $versionDirectory "win32LobApp.json"

$installScript | Set-Content -Path $installScriptPath -Encoding UTF8
$detectionScript | Set-Content -Path $detectionScriptPath -Encoding UTF8
$uninstallScript | Set-Content -Path $uninstallScriptPath -Encoding UTF8

$intuneInstallCommand = '%windir%\sysnative\windowspowershell\v1.0\powershell.exe -WindowStyle Hidden -ExecutionPolicy Bypass -File install.ps1'
$intuneUninstallCommand = '%windir%\sysnative\windowspowershell\v1.0\powershell.exe -WindowStyle Hidden -ExecutionPolicy Bypass -File uninstall.ps1'
$intuneWinFileName = "$($installerFile.BaseName).intunewin"

$readmeMarkdown = Get-ReadmeMarkdown `
    -AppName $AppName `
    -PackageId $packageId `
    -Version $resolvedVersion `
    -Description $description `
    -Publisher $Publisher `
    -WebsiteUrl $WebsiteUrl `
    -InstallerFileName $installerFile.Name `
    -IntuneWinFileName $intuneWinFileName `
    -InstallerHash $installerHash `
    -RawInstallCommand $rawInstallCommand `
    -HasIcon ([bool](Test-Path $iconFilePath))
$readmeMarkdown | Set-Content -Path $readmePath -Encoding UTF8

@"
Package $packageId $resolvedVersion from web download

Display name: $AppName
Version: $resolvedVersion
Publisher: $Publisher
Download URL: $finalDownloadUrl
Install command: $intuneInstallCommand
Uninstall command: $intuneUninstallCommand

See README.md for full Intune upload reference.
"@ | Set-Content -Path $legacyReadmePath -Encoding UTF8

$appJson = @{
    packageIdentifier = $packageId
    displayName = $AppName
    description = $description
    version = $resolvedVersion
    source = 3
    publisher = $Publisher
    informationUrl = $WebsiteUrl
    publisherUrl = $WebsiteUrl
    supportUrl = $WebsiteUrl
    installerType = 7
    installerUrl = $finalDownloadUrl
    hash = $installerHash
    installCommandLine = $intuneInstallCommand
    uninstallCommandLine = $intuneUninstallCommand
    installerFilename = $installerFile.Name
    installerContext = 2
    architecture = 2
}
$appJson | ConvertTo-Json -Depth 10 | Set-Content -Path $appJsonPath -Encoding UTF8

$detectionScriptBase64 = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($detectionScript))
$iconBase64 = ""
if ($iconFilePath -and (Test-Path $iconFilePath)) {
    $iconBase64 = [Convert]::ToBase64String([System.IO.File]::ReadAllBytes($iconFilePath))
}
$win32Json = @{
    "@odata.type" = "#microsoft.graph.win32LobApp"
    description = $description
    developer = $Publisher
    displayName = $AppName
    informationUrl = $WebsiteUrl
    largeIcon = if ($iconBase64) { @{ type = "image/png"; value = $iconBase64 } } else { $null }
    notes = "Generated by AppGetter at $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') [Web|$packageId]"
    publisher = $Publisher
    fileName = $intuneWinFileName
    allowAvailableUninstall = $true
    applicableArchitectures = "x64"
    detectionRules = @(
        @{
            "@odata.type" = "#microsoft.graph.win32LobAppPowerShellScriptDetection"
            enforceSignatureCheck = $false
            runAs32Bit = $false
            scriptContent = $detectionScriptBase64
        }
    )
    displayVersion = $resolvedVersion
    installCommandLine = $intuneInstallCommand
    installExperience = @{
        deviceRestartBehavior = "basedOnReturnCode"
        runAsAccount = "system"
    }
    minimumSupportedOperatingSystem = @{ v10_2004 = $true }
    minimumSupportedWindowsRelease = "2004"
    returnCodes = @(
        @{ returnCode = 0; type = "success" }
        @{ returnCode = 1707; type = "success" }
        @{ returnCode = 3010; type = "softReboot" }
        @{ returnCode = 1641; type = "hardReboot" }
        @{ returnCode = 1618; type = "retry" }
    )
    setupFilePath = $installerFile.Name
    uninstallCommandLine = $intuneUninstallCommand
}
if (-not $iconBase64) { $win32Json.Remove("largeIcon") }
$win32Json | ConvertTo-Json -Depth 10 | Set-Content -Path $win32JsonPath -Encoding UTF8

Write-Step "Step 7: Creating .intunewin package"
$packagingSucceeded = $false
$intuneWinPath = Join-Path $appDirectory $intuneWinFileName
$intuneWinCmd = Get-Command intunewinapputil -ErrorAction SilentlyContinue
if (-not $intuneWinCmd) {
    Write-Host "intunewinapputil was not found on PATH. Metadata files were still generated." -ForegroundColor Yellow
} else {
    if (Test-Path $intuneWinPath) {
        Remove-Item -Path $intuneWinPath -Force
    }
    & intunewinapputil -c $versionDirectory -s $installerFile.Name -o $appDirectory -q
    if ($LASTEXITCODE -eq 0 -and (Test-Path $intuneWinPath)) {
        $packagingSucceeded = $true
        Write-Success "Created package: $intuneWinPath"
    } else {
        Write-Host "intunewinapputil returned an error. Verify the command output and retry." -ForegroundColor Yellow
    }
}

Save-AppGetterSettings -OutputPath $OutputPath -LastPackageId $packageId

Write-Step "Summary"
Write-Host @"
Package Details:
- Application: $AppName
- Package ID: $packageId
- Version: $resolvedVersion
- Publisher: $Publisher
- Installer: $installerFileName
- Download URL: $finalDownloadUrl
- Output Directory: $versionDirectory
- IntuneWin Package: $(if ($packagingSucceeded) { $intuneWinPath } else { "(not created)" })

Files Created:
- install.ps1
- detection.ps1
- uninstall.ps1
- README.md
- readme.txt
- app.json
- win32LobApp.json
- icon.png (if available)
- $installerFileName
"@ -ForegroundColor Green
