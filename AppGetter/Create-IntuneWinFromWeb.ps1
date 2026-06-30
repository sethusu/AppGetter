<#
.SYNOPSIS
    Creates an Intune Win32 package from a web download, mirroring WinGetter output behavior.
.DESCRIPTION
    AppGetter is now PowerShell-only. It downloads an installer from a direct URL or website discovery,
    then generates WinGetter-style package assets:
      - install.ps1 / detection.ps1 / uninstall.ps1
      - README.md + readme.txt
      - app.json + win32LobApp.json
      - icon.png (if provided or discovered)
      - .intunewin (when intunewinapputil is available)
.PARAMETER AppName
    Display name used for packaging output and detection matching.
.PARAMETER DownloadUrl
    Direct installer URL (recommended for non-interactive usage).
.PARAMETER WebsiteUrl
    Website to scan for installer links when DownloadUrl is not provided.
.PARAMETER Version
    Optional package version; defaults to detected value or "latest".
.PARAMETER Publisher
    Optional publisher; defaults to "Unknown".
.PARAMETER DeveloperUrl
    Optional website used in metadata and icon lookup.
.PARAMETER SupportUrl
    Optional support URL used in metadata.
.PARAMETER Description
    Optional description override.
.PARAMETER OutputPath
    Optional output root. Defaults to saved AppData settings or "Documents\AppGetter Output".
.PARAMETER IconPath
    Optional custom icon path.
.PARAMETER InstallCommand
    Optional raw installer command, for example `"setup.exe" /VERYSILENT`.
#>

[CmdletBinding()]
param(
    [string]$AppName,
    [string]$DownloadUrl,
    [string]$WebsiteUrl,
    [string]$Version,
    [string]$Publisher,
    [string]$DeveloperUrl,
    [string]$SupportUrl,
    [string]$Description,
    [string]$OutputPath,
    [string]$IconPath,
    [string]$InstallCommand
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

function Write-AppGetterMessage {
    param(
        [string]$Message,
        [ValidateSet("Info", "Success", "Warning", "Error", "Step")]
        [string]$Level = "Info"
    )

    switch ($Level) {
        "Success" { Write-Host "[SUCCESS] $Message" -ForegroundColor Green }
        "Warning" { Write-Host "[WARNING] $Message" -ForegroundColor Yellow }
        "Error" { Write-Host "[ERROR] $Message" -ForegroundColor Red }
        "Step" { Write-Host "`n[$Message]" -ForegroundColor Cyan }
        default { Write-Host $Message }
    }
}

function Get-AppGetterConfigRoot {
    if ($env:APPDATA) {
        return $env:APPDATA
    }
    if ($env:XDG_CONFIG_HOME) {
        return $env:XDG_CONFIG_HOME
    }
    if ($env:HOME) {
        return (Join-Path $env:HOME ".config")
    }
    return (Get-Location).Path
}

function Get-HomePath {
    if ($env:USERPROFILE) { return $env:USERPROFILE }
    if ($env:HOME) { return $env:HOME }
    return (Get-Location).Path
}

function Get-AppGetterSettings {
    $settingsPath = Join-Path (Get-AppGetterConfigRoot) "AppGetter/settings.json"
    $defaults = @{
        OutputPath = Join-Path (Get-HomePath) "Documents/AppGetter Output"
        LastDownloadUrl = ""
        LastWebsiteUrl = ""
        LastAppName = ""
    }

    if (Test-Path $settingsPath) {
        try {
            $saved = Get-Content -Path $settingsPath -Raw | ConvertFrom-Json
            foreach ($key in $defaults.Keys) {
                if ($saved.PSObject.Properties.Name -contains $key -and $saved.$key) {
                    $defaults[$key] = [string]$saved.$key
                }
            }
        } catch {
            Write-AppGetterMessage -Level Warning -Message "Could not parse settings file; defaults will be used."
        }
    }

    [PSCustomObject]$defaults
}

function Save-AppGetterSettings {
    param(
        [string]$OutputPath,
        [string]$LastDownloadUrl,
        [string]$LastWebsiteUrl,
        [string]$LastAppName
    )

    $settingsDir = Join-Path (Get-AppGetterConfigRoot) "AppGetter"
    if (-not (Test-Path $settingsDir)) {
        New-Item -ItemType Directory -Path $settingsDir -Force | Out-Null
    }

    $current = Get-AppGetterSettings
    if ($OutputPath) { $current.OutputPath = $OutputPath }
    if ($LastDownloadUrl) { $current.LastDownloadUrl = $LastDownloadUrl }
    if ($LastWebsiteUrl) { $current.LastWebsiteUrl = $LastWebsiteUrl }
    if ($LastAppName) { $current.LastAppName = $LastAppName }

    $settingsPath = Join-Path $settingsDir "settings.json"
    $current | ConvertTo-Json | Set-Content -Path $settingsPath -Encoding UTF8
}

function Test-AppGetterPrerequisites {
    $results = [ordered]@{
        PowerShellVersion = $PSVersionTable.PSVersion.ToString()
        ContentPrepToolInstalled = $false
        ContentPrepToolPath = ""
        Issues = @()
    }

    $intuneWin = Get-Command intunewinapputil -ErrorAction SilentlyContinue
    if ($intuneWin) {
        $results.ContentPrepToolInstalled = $true
        $results.ContentPrepToolPath = $intuneWin.Source
    } else {
        $results.Issues += "intunewinapputil was not found on PATH."
    }

    [PSCustomObject]$results
}

function Get-ConsoleInput {
    param(
        [string]$Prompt,
        [string]$Default = ""
    )

    $suffix = if ($Default) { " [$Default]" } else { "" }
    $value = Read-Host "$Prompt$suffix"
    if ([string]::IsNullOrWhiteSpace($value)) {
        return $Default
    }
    $value.Trim()
}

function Resolve-PackageId {
    param([string]$Name)
    ($Name -replace "[^a-zA-Z0-9]+", ".").Trim(".")
}

function Get-InstallerFileNameFromUrl {
    param([string]$Url)

    $file = Split-Path -Leaf ([Uri]$Url).AbsolutePath
    if ([string]::IsNullOrWhiteSpace($file)) {
        throw "Could not derive installer filename from URL: $Url"
    }
    $file
}

function Get-DownloadLinksFromWebsite {
    param(
        [string]$Url,
        [string]$AppName
    )

    $response = Invoke-WebRequest -Uri $Url -UseBasicParsing -ErrorAction Stop
    $html = $response.Content
    $links = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $regex = 'href\s*=\s*["'']([^"'']+)["'']'
    $linkMatches = [regex]::Matches($html, $regex, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    foreach ($match in $linkMatches) {
        $raw = $match.Groups[1].Value
        if ($raw -notmatch '\.(exe|msi|msix|appx)(\?|$)' -and $raw -notmatch '(download|setup|installer)') {
            continue
        }

        try {
            $resolved = if ($raw -match '^https?://') { $raw } else { ([Uri]::new([Uri]$Url, $raw)).AbsoluteUri }
            if ($resolved) { [void]$links.Add($resolved) }
        } catch {
            continue
        }
    }

    if ($AppName) {
        $preferred = $links | Where-Object { $_ -match [regex]::Escape($AppName) }
        if ($preferred.Count -gt 0) {
            return @($preferred + ($links | Where-Object { $_ -notin $preferred }))
        }
    }

    @($links)
}

function Get-VersionFromText {
    param([string]$Text)
    if ($Text -match '(?<!\d)(\d+\.\d+\.\d+\.\d+)(?!\d)') { return $matches[1] }
    if ($Text -match '(?<!\d)(\d+\.\d+\.\d+)(?!\d)') { return $matches[1] }
    $null
}

function Get-DescriptionFromWebsite {
    param([string]$Url)
    try {
        $response = Invoke-WebRequest -Uri $Url -UseBasicParsing -ErrorAction Stop
        $html = $response.Content
        if ($html -match '<meta\s+name=["'']description["'']\s+content=["'']([^"'']+)["'']') {
            return $matches[1].Trim()
        }
        if ($html -match '<meta\s+property=["'']og:description["'']\s+content=["'']([^"'']+)["'']') {
            return $matches[1].Trim()
        }
    } catch {
        return $null
    }
    $null
}

function Get-InstallerInstallCommand {
    param(
        [string]$InstallerFileName,
        [string]$InstallerExtension,
        [string]$FallbackSwitch
    )

    switch ($InstallerExtension.ToLowerInvariant()) {
        ".msi" { "msiexec /i `"$InstallerFileName`" /quiet /norestart" }
        ".msix" { "Add-AppxPackage -Path `"$InstallerFileName`"" }
        ".appx" { "Add-AppxPackage -Path `"$InstallerFileName`"" }
        default { "`"$InstallerFileName`" $FallbackSwitch" }
    }
}

function Get-ImageMimeType {
    param([byte[]]$Bytes)
    if (-not $Bytes -or $Bytes.Length -lt 4) { return $null }
    if ($Bytes[0] -eq 0x89 -and $Bytes[1] -eq 0x50 -and $Bytes[2] -eq 0x4E -and $Bytes[3] -eq 0x47) { return "image/png" }
    if ($Bytes.Length -ge 3 -and $Bytes[0] -eq 0xFF -and $Bytes[1] -eq 0xD8 -and $Bytes[2] -eq 0xFF) { return "image/jpeg" }
    if ($Bytes.Length -ge 3 -and $Bytes[0] -eq 0x47 -and $Bytes[1] -eq 0x49 -and $Bytes[2] -eq 0x46) { return "image/gif" }
    $null
}

function New-InstallScriptContent {
    param(
        [string]$PackageId,
        [string]$DisplayName,
        [string]$Version,
        [string]$InstallCommand
    )
@"
# Install script for $DisplayName
# Intune Win32 app deployment - generated by AppGetter

`$ErrorActionPreference = 'Stop'
`$packageId = '$PackageId'
`$displayName = '$DisplayName'
`$expectedVersion = '$Version'
`$logPath = "`$env:ProgramData\Microsoft\IntuneManagementExtension\Logs\`$packageId-install.log"

Start-Transcript -Path `$logPath -Force
Write-Host "Starting install for `$displayName (`$packageId) version `$expectedVersion"

try {
    `$scriptRoot = Split-Path -Parent `$MyInvocation.MyCommand.Path
    Set-Location -Path `$scriptRoot

    `$installCommand = @'
$InstallCommand
'@

    Write-Host "Executing install command: `$installCommand"
    `$process = Start-Process -FilePath 'cmd.exe' -ArgumentList "/c `$installCommand" -Wait -PassThru -NoNewWindow

    switch (`$process.ExitCode) {
        0 { Write-Host 'Install completed successfully.'; Stop-Transcript; exit 0 }
        3010 { Write-Host 'Install completed successfully (reboot required - 3010).'; Stop-Transcript; exit 3010 }
        1641 { Write-Host 'Install completed successfully (hard reboot required - 1641).'; Stop-Transcript; exit 1641 }
        1618 { Write-Host 'Another installation is already in progress (1618).'; Stop-Transcript; exit 1618 }
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

function New-DetectionScriptContent {
    param(
        [string]$PackageId,
        [string]$DisplayName,
        [string]$Version
    )

    $firstWord = ($DisplayName -split '\s+')[0]
@"
# Registry-based detection script for $DisplayName
# Intune Win32 app deployment - generated by AppGetter

`$ErrorActionPreference = 'Continue'
`$packageId = '$PackageId'
`$version = '$Version'
`$displayName = '$DisplayName'
`$logPath = "`$env:ProgramData\Microsoft\IntuneManagementExtension\Logs\`$packageId-detection.log"

Start-Transcript -Path `$logPath -Force
Write-Host "Starting `$packageId `$version detection (registry-based)"

`$registryPaths = @(
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
    'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
)

`$matches = @()
foreach (`$path in `$registryPaths) {
    try {
        `$entries = Get-ItemProperty `$path -ErrorAction SilentlyContinue | Where-Object {
            (`$_.DisplayName -and (`$_.DisplayName -like '*$DisplayName*' -or `$_.DisplayName -like '*$firstWord*')) -or
            (`$_.PSChildName -and `$_.PSChildName -like '*$PackageId*')
        }
        foreach (`$entry in `$entries) {
            if (`$entry.DisplayVersion) {
                `$matches += [PSCustomObject]@{
                    DisplayName = `$entry.DisplayName
                    DisplayVersion = `$entry.DisplayVersion
                }
            }
        }
    } catch {
        Write-Host "Error checking `$path : `$_"
    }
}

if (`$matches.Count -eq 0) {
    Write-Host "`$packageId not detected in registry."
    Stop-Transcript
    exit 1
}

`$installedVersion = (`$matches | Sort-Object { try { [version]`$_.DisplayVersion } catch { [version]'0.0.0' } } -Descending | Select-Object -First 1).DisplayVersion
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
} catch {
    if (`$installedVersion -ge `$version) {
        Stop-Transcript
        exit 0
    }
}

Stop-Transcript
exit 1
"@
}

function New-UninstallScriptContent {
    param(
        [string]$PackageId,
        [string]$DisplayName
    )
@"
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
    `$items = Get-ItemProperty `$path -ErrorAction SilentlyContinue | Where-Object {
        `$_.DisplayName -like '*$DisplayName*' -or
        `$_.PSChildName -like '*$PackageId*'
    }
    foreach (`$item in `$items) {
        `$uninstallString = `$item.UninstallString
        `$quietUninstallString = `$item.QuietUninstallString
        if (`$uninstallString) { break }
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

try {
    `$process = Start-Process -FilePath 'cmd.exe' -ArgumentList "/c `$command" -Wait -PassThru -NoNewWindow
    if (`$process.ExitCode -eq 0 -or `$process.ExitCode -eq 3010) {
        Stop-Transcript
        exit 0
    }
    Stop-Transcript
    exit `$process.ExitCode
}
catch {
    Write-Host "Uninstall error: `$_"
    Stop-Transcript
    exit 1
}
"@
}

function New-AppReadmeMarkdown {
    param(
        [pscustomobject]$Package,
        [string]$InstallerFileName,
        [string]$InstallerHash,
        [string]$InstallerCommand,
        [string]$IntuneWinFileName,
        [bool]$HasIcon
    )

    $installCmd = "%windir%\sysnative\windowspowershell\v1.0\powershell.exe -WindowStyle Hidden -ExecutionPolicy Bypass -File install.ps1"
    $uninstallCmd = "%windir%\sysnative\windowspowershell\v1.0\powershell.exe -WindowStyle Hidden -ExecutionPolicy Bypass -File uninstall.ps1"
@"
# $($Package.DisplayName) - Intune Win32 Package

Generated by **AppGetter** on $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss').

## Intune Portal Upload Reference

| Intune field | Value |
|---|---|
| Name / Display name | $($Package.DisplayName) |
| Description | $($Package.Description) |
| Publisher | $($Package.Publisher) |
| Developer | $($Package.Publisher) |
| App version / Display version | $($Package.Version) |
| Package identifier | $($Package.PackageId) |
| Information URL | $($Package.InformationUrl) |
| Install command | $installCmd |
| Uninstall command | $uninstallCmd |
| Setup file | $InstallerFileName |
| IntuneWin package | $IntuneWinFileName |
| Installer SHA-256 | $InstallerHash |
| Raw installer command | $InstallerCommand |
| Detection method | PowerShell script (registry-based version check) |
| Applicable architecture | x64 |
| Minimum Windows release | Windows 10 2004 |
| Return codes | 0, 1707 (success); 3010, 1641 (reboot); 1618 (retry) |
| Icon included | $(if ($HasIcon) { "Yes (icon.png)" } else { "No" }) |

## Package Contents

- install.ps1
- detection.ps1
- uninstall.ps1
- README.md
- readme.txt
- app.json
- win32LobApp.json
- icon.png (if available)
"@
}

function New-MetadataFiles {
    param(
        [pscustomobject]$Package,
        [string]$VersionDirectory,
        [string]$InstallerFileName,
        [string]$InstallerHash,
        [string]$InstallerCommand,
        [string]$InstallScript,
        [string]$DetectionScript,
        [string]$UninstallScript,
        [string]$IconFilePath
    )

    $installPsPath = Join-Path $VersionDirectory "install.ps1"
    $detectPsPath = Join-Path $VersionDirectory "detection.ps1"
    $uninstallPsPath = Join-Path $VersionDirectory "uninstall.ps1"
    $readmePath = Join-Path $VersionDirectory "README.md"
    $legacyReadmePath = Join-Path $VersionDirectory "readme.txt"
    $appJsonPath = Join-Path $VersionDirectory "app.json"
    $win32Path = Join-Path $VersionDirectory "win32LobApp.json"
    $intuneWinFileName = "$([System.IO.Path]::GetFileNameWithoutExtension($InstallerFileName)).intunewin"

    $installIntune = "%windir%\sysnative\windowspowershell\v1.0\powershell.exe -WindowStyle Hidden -ExecutionPolicy Bypass -File install.ps1"
    $uninstallIntune = "%windir%\sysnative\windowspowershell\v1.0\powershell.exe -WindowStyle Hidden -ExecutionPolicy Bypass -File uninstall.ps1"

    $InstallScript | Set-Content -Path $installPsPath -Encoding UTF8
    $DetectionScript | Set-Content -Path $detectPsPath -Encoding UTF8
    $UninstallScript | Set-Content -Path $uninstallPsPath -Encoding UTF8

    $hasIcon = Test-Path $IconFilePath
    $readme = New-AppReadmeMarkdown -Package $Package -InstallerFileName $InstallerFileName -InstallerHash $InstallerHash -InstallerCommand $InstallerCommand -IntuneWinFileName $intuneWinFileName -HasIcon $hasIcon
    $readme | Set-Content -Path $readmePath -Encoding UTF8

    @"
Package $($Package.PackageId) $($Package.Version) from web download

Display name: $($Package.DisplayName)
Version: $($Package.Version)
Publisher: $($Package.Publisher)
Download URL: $($Package.DownloadUrl)
Install command: $installIntune
Uninstall command: $uninstallIntune
"@ | Set-Content -Path $legacyReadmePath -Encoding UTF8

    $appJson = @{
        packageIdentifier = $Package.PackageId
        displayName = $Package.DisplayName
        description = $Package.Description
        version = $Package.Version
        source = 3
        publisher = $Package.Publisher
        informationUrl = $Package.InformationUrl
        publisherUrl = $Package.InformationUrl
        supportUrl = $Package.SupportUrl
        installerType = 7
        installerUrl = $Package.DownloadUrl
        hash = $InstallerHash
        installCommandLine = $installIntune
        uninstallCommandLine = $uninstallIntune
        installerFilename = $InstallerFileName
        installerContext = 2
        architecture = 2
    }
    $appJson | ConvertTo-Json -Depth 10 | Set-Content -Path $appJsonPath -Encoding UTF8

    $detectionBase64 = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($DetectionScript))
    $iconBase64 = ""
    $iconMime = "image/png"
    if ($hasIcon) {
        $iconBytes = [System.IO.File]::ReadAllBytes($IconFilePath)
        $iconBase64 = [Convert]::ToBase64String($iconBytes)
        $detected = Get-ImageMimeType -Bytes $iconBytes
        if ($detected) {
            $iconMime = $detected
        }
    }

    $win32 = @{
        "@odata.type" = "#microsoft.graph.win32LobApp"
        description = $Package.Description
        developer = $Package.Publisher
        displayName = $Package.DisplayName
        informationUrl = $Package.InformationUrl
        largeIcon = if ($iconBase64) { @{ type = $iconMime; value = $iconBase64 } } else { $null }
        notes = "Generated by AppGetter at $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') [Web|$($Package.PackageId)]"
        publisher = $Package.Publisher
        fileName = $intuneWinFileName
        allowAvailableUninstall = $true
        applicableArchitectures = "x64"
        detectionRules = @(
            @{
                "@odata.type" = "#microsoft.graph.win32LobAppPowerShellScriptDetection"
                enforceSignatureCheck = $false
                runAs32Bit = $false
                scriptContent = $detectionBase64
            }
        )
        displayVersion = $Package.Version
        installCommandLine = $installIntune
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
        setupFilePath = $InstallerFileName
        uninstallCommandLine = $uninstallIntune
    }
    if (-not $iconBase64) {
        $win32.Remove("largeIcon")
    }
    $win32 | ConvertTo-Json -Depth 10 | Set-Content -Path $win32Path -Encoding UTF8

    [PSCustomObject]@{
        IntuneWinFileName = $intuneWinFileName
        InstallScriptPath = $installPsPath
        DetectionScriptPath = $detectPsPath
        UninstallScriptPath = $uninstallPsPath
        ReadmePath = $readmePath
        AppJsonPath = $appJsonPath
        Win32LobAppJsonPath = $win32Path
    }
}

function Resolve-IconFile {
    param(
        [string]$AppDirectory,
        [string]$VersionDirectory,
        [string]$WebsiteUrl,
        [string]$DeveloperUrl,
        [string]$IconPath
    )

    $logoFilePath = Join-Path $AppDirectory "logo.png"
    $iconFilePath = Join-Path $VersionDirectory "icon.png"

    if ($IconPath -and (Test-Path $IconPath)) {
        Copy-Item -Path $IconPath -Destination $logoFilePath -Force
        Copy-Item -Path $IconPath -Destination $iconFilePath -Force
        return $iconFilePath
    }

    if (Test-Path $logoFilePath) {
        Copy-Item -Path $logoFilePath -Destination $iconFilePath -Force
        return $iconFilePath
    }

    $bases = @($WebsiteUrl, $DeveloperUrl) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    foreach ($base in $bases) {
        foreach ($candidate in @("favicon.ico", "favicon.png", "apple-touch-icon.png")) {
            try {
                $uri = ([Uri]::new([Uri]$base, $candidate)).AbsoluteUri
                Invoke-WebRequest -Uri $uri -OutFile $logoFilePath -UseBasicParsing -TimeoutSec 8 -ErrorAction Stop
                if ((Get-Item $logoFilePath).Length -gt 0) {
                    Copy-Item -Path $logoFilePath -Destination $iconFilePath -Force
                    return $iconFilePath
                }
            } catch {
                continue
            }
        }
    }

    $null
}

function Invoke-AppGetterPackaging {
    param(
        [string]$AppName,
        [string]$Version,
        [string]$Publisher,
        [string]$Description,
        [string]$DownloadUrl,
        [string]$WebsiteUrl,
        [string]$DeveloperUrl,
        [string]$SupportUrl,
        [string]$OutputPath,
        [string]$IconPath,
        [string]$InstallCommand
    )

    $packageId = Resolve-PackageId -Name $AppName
    $resolvedVersion = if ($Version) { $Version } else { "latest" }
    $resolvedPublisher = if ($Publisher) { $Publisher } else { "Unknown" }
    $descriptionText = if ($Description) { $Description } else { "$AppName package created from a web download." }

    if (-not $DownloadUrl -and $WebsiteUrl) {
        Write-AppGetterMessage -Level Step -Message "Step 1: Discovering download links"
        $candidates = Get-DownloadLinksFromWebsite -Url $WebsiteUrl -AppName $AppName
        if ($candidates.Count -eq 0) {
            throw "No installer links found on $WebsiteUrl. Provide -DownloadUrl."
        }
        $DownloadUrl = ($candidates | Where-Object { $_ -match '\.(exe|msi|msix|appx)(\?|$)' } | Select-Object -First 1)
        if (-not $DownloadUrl) {
            $DownloadUrl = $candidates[0]
        }
    }

    if (-not $DownloadUrl) {
        throw "Download URL is required. Use -DownloadUrl or -WebsiteUrl."
    }

    if (-not $Version) {
        $resolvedVersion = Get-VersionFromText -Text $DownloadUrl
        if (-not $resolvedVersion -and $WebsiteUrl) {
            $websiteVersion = Get-VersionFromText -Text ((Invoke-WebRequest -Uri $WebsiteUrl -UseBasicParsing -ErrorAction SilentlyContinue).Content)
            if ($websiteVersion) {
                $resolvedVersion = $websiteVersion
            }
        }
        if (-not $resolvedVersion) {
            $resolvedVersion = "latest"
        }
    }

    if (-not $Description -and $WebsiteUrl) {
        $detectedDescription = Get-DescriptionFromWebsite -Url $WebsiteUrl
        if ($detectedDescription) {
            $descriptionText = $detectedDescription
        }
    }

    Write-AppGetterMessage -Level Step -Message "Step 2: Creating directories"
    if (-not (Test-Path $OutputPath)) {
        New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null
    }

    $appDirectory = Join-Path $OutputPath $packageId
    $versionDirectory = Join-Path $appDirectory $resolvedVersion
    New-Item -ItemType Directory -Path $versionDirectory -Force | Out-Null

    Write-AppGetterMessage -Level Step -Message "Step 3: Downloading installer"
    $installerFileName = Get-InstallerFileNameFromUrl -Url $DownloadUrl
    $installerPath = Join-Path $versionDirectory $installerFileName
    Invoke-WebRequest -Uri $DownloadUrl -OutFile $installerPath -UseBasicParsing -ErrorAction Stop

    if (-not (Test-Path $installerPath)) {
        throw "Installer download failed: $DownloadUrl"
    }

    $installerFile = Get-Item $installerPath
    $installCommandRaw = if ($InstallCommand) {
        $InstallCommand
    } else {
        Get-InstallerInstallCommand -InstallerFileName $installerFile.Name -InstallerExtension $installerFile.Extension -FallbackSwitch "/S"
    }
    $installerHash = (Get-FileHash -Path $installerPath -Algorithm SHA256).Hash

    Write-AppGetterMessage -Level Step -Message "Step 4: Generating scripts and metadata"
    $installScript = New-InstallScriptContent -PackageId $packageId -DisplayName $AppName -Version $resolvedVersion -InstallCommand $installCommandRaw
    $detectionScript = New-DetectionScriptContent -PackageId $packageId -DisplayName $AppName -Version $resolvedVersion
    $uninstallScript = New-UninstallScriptContent -PackageId $packageId -DisplayName $AppName

    $iconFilePath = Resolve-IconFile -AppDirectory $appDirectory -VersionDirectory $versionDirectory -WebsiteUrl $WebsiteUrl -DeveloperUrl $DeveloperUrl -IconPath $IconPath

    $package = [PSCustomObject]@{
        PackageId = $packageId
        DisplayName = $AppName
        Version = $resolvedVersion
        Publisher = $resolvedPublisher
        Description = $descriptionText
        DownloadUrl = $DownloadUrl
        InformationUrl = if ($WebsiteUrl) { $WebsiteUrl } elseif ($DeveloperUrl) { $DeveloperUrl } else { "" }
        SupportUrl = if ($SupportUrl) { $SupportUrl } elseif ($WebsiteUrl) { $WebsiteUrl } else { "" }
    }

    $metadata = New-MetadataFiles -Package $package -VersionDirectory $versionDirectory -InstallerFileName $installerFileName -InstallerHash $installerHash -InstallerCommand $installCommandRaw -InstallScript $installScript -DetectionScript $detectionScript -UninstallScript $uninstallScript -IconFilePath $iconFilePath

    Write-AppGetterMessage -Level Step -Message "Step 5: Running intunewinapputil"
    $intuneWinPath = Join-Path (Split-Path $versionDirectory -Parent) $metadata.IntuneWinFileName
    $packagingSucceeded = $false
    if (Get-Command intunewinapputil -ErrorAction SilentlyContinue) {
        if (Test-Path $intuneWinPath) {
            Remove-Item -Path $intuneWinPath -Force
        }
        & intunewinapputil -c $versionDirectory -s $installerFileName -o (Split-Path $versionDirectory -Parent) -q
        if ($LASTEXITCODE -eq 0 -and (Test-Path $intuneWinPath)) {
            $packagingSucceeded = $true
        } else {
            Write-AppGetterMessage -Level Warning -Message "Metadata was created but .intunewin packaging failed."
        }
    } else {
        Write-AppGetterMessage -Level Warning -Message "intunewinapputil was not found; metadata was generated without .intunewin."
    }

    Save-AppGetterSettings -OutputPath $OutputPath -LastDownloadUrl $DownloadUrl -LastWebsiteUrl $WebsiteUrl -LastAppName $AppName

    [PSCustomObject]@{
        Package = $package
        VersionDirectory = $versionDirectory
        InstallerFile = $installerPath
        IntuneWinFile = if ($packagingSucceeded) { $intuneWinPath } else { $null }
        PackagingSucceeded = $packagingSucceeded
    }
}

try {
    $settings = Get-AppGetterSettings

    if (-not $OutputPath) {
        $OutputPath = $settings.OutputPath
    }

    if (-not $AppName) {
        $AppName = Get-ConsoleInput -Prompt "Application name" -Default $settings.LastAppName
    }
    if (-not $DownloadUrl -and -not $WebsiteUrl) {
        $sourceMode = Get-ConsoleInput -Prompt "Use direct download URL? (y/n)" -Default "y"
        if ($sourceMode -match "^(y|yes)$") {
            $DownloadUrl = Get-ConsoleInput -Prompt "Direct download URL" -Default $settings.LastDownloadUrl
        } else {
            $WebsiteUrl = Get-ConsoleInput -Prompt "Website URL to scan" -Default $settings.LastWebsiteUrl
        }
    }

    if ([string]::IsNullOrWhiteSpace($AppName)) {
        throw "AppName is required."
    }

    Write-AppGetterMessage -Level Step -Message "Prerequisite check"
    $prereqs = Test-AppGetterPrerequisites
    if ($prereqs.ContentPrepToolInstalled) {
        Write-AppGetterMessage -Level Success -Message "Found intunewinapputil at: $($prereqs.ContentPrepToolPath)"
    } else {
        Write-AppGetterMessage -Level Warning -Message ($prereqs.Issues -join " ")
    }

    $result = Invoke-AppGetterPackaging -AppName $AppName -Version $Version -Publisher $Publisher -Description $Description -DownloadUrl $DownloadUrl -WebsiteUrl $WebsiteUrl -DeveloperUrl $DeveloperUrl -SupportUrl $SupportUrl -OutputPath $OutputPath -IconPath $IconPath -InstallCommand $InstallCommand

    Write-AppGetterMessage -Level Step -Message "Summary"
    Write-Host @"
Package Details:
- Application: $($result.Package.DisplayName)
- Package ID: $($result.Package.PackageId)
- Version: $($result.Package.Version)
- Publisher: $($result.Package.Publisher)
- Output Directory: $($result.VersionDirectory)
- Installer: $($result.InstallerFile)
- IntuneWin Package: $(if ($result.IntuneWinFile) { $result.IntuneWinFile } else { "(not created)" })
"@ -ForegroundColor Green
}
catch {
    Write-AppGetterMessage -Level Error -Message $_.Exception.Message
    exit 1
}
