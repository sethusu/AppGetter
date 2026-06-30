<#
.SYNOPSIS
    Creates an IntuneWin package from a web-based application download with registry-based detection.
.DESCRIPTION
    CLI entry point for AppGetter. Downloads an installer from the web, generates install/detection/uninstall
    scripts, metadata files, and packages the result with the Microsoft Win32 Content Prep Tool.

    Requires intunewinapputil on PATH. No Python or other runtime dependencies.
.PARAMETER WebsiteUrl
    Website URL to scan for download links.
.PARAMETER DownloadUrl
    Direct download URL. Skips website scanning when provided.
.PARAMETER AppName
    Application display name.
.PARAMETER Version
    Optional version override.
.PARAMETER Publisher
    Optional publisher name.
.PARAMETER DeveloperUrl
    Optional developer/publisher site used for icon and description discovery.
.PARAMETER SupportUrl
    Optional documentation URL scanned for silent install switches.
.PARAMETER OutputPath
    Base output folder. Defaults to saved AppGetter settings.
.PARAMETER IconPath
    Optional custom PNG icon path.
.PARAMETER InstallCommand
    Optional custom raw installer command. When omitted, switches are discovered automatically.
.PARAMETER AllowRuntimeProbe
    Probe EXE installers with /? and --help on Windows to discover silent switches.
.EXAMPLE
    .\Create-IntuneWinFromWeb.ps1 -DownloadUrl "https://example.com/setup.exe" -AppName "MyApp"
.EXAMPLE
    .\Create-IntuneWinFromWeb.ps1 -WebsiteUrl "https://simion.com/" -AppName "SIMION" -Publisher "Adaptas Solutions, LLC"
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
    [string]$DeveloperUrl,

    [Parameter(Mandatory = $false)]
    [string]$SupportUrl,

    [Parameter(Mandatory = $false)]
    [string]$OutputPath,

    [Parameter(Mandatory = $false)]
    [string]$IconPath,

    [Parameter(Mandatory = $false)]
    [string]$InstallCommand,

    [Parameter(Mandatory = $false)]
    [switch]$AllowRuntimeProbe
)

$ErrorActionPreference = 'Stop'
$moduleRoot = $PSScriptRoot
Import-Module (Join-Path $moduleRoot 'AppGetter.psd1') -Force

function Get-InputFromDialog {
    param(
        [string]$Title,
        [string]$Prompt,
        [string]$DefaultValue = ''
    )

    Add-Type -AssemblyName Microsoft.VisualBasic
    $result = [Microsoft.VisualBasic.Interaction]::InputBox($Prompt, $Title, $DefaultValue)
    if ([string]::IsNullOrWhiteSpace($result)) {
        return $null
    }
    return $result.Trim()
}

function Select-DownloadUrlFromCli {
    param([string[]]$DownloadLinks)

    if ($DownloadLinks.Count -eq 1) {
        Write-Host "Found 1 download link: $($DownloadLinks[0])" -ForegroundColor Green
        return $DownloadLinks[0]
    }

    Write-Host "`nFound $($DownloadLinks.Count) potential download links:" -ForegroundColor Green
    for ($i = 0; $i -lt $DownloadLinks.Count; $i++) {
        Write-Host "  $($i + 1). $($DownloadLinks[$i])" -ForegroundColor Cyan
    }

    Add-Type -AssemblyName Microsoft.VisualBasic
    $prompt = "Enter the number (1-$($DownloadLinks.Count)):"
    $selectedNumber = [Microsoft.VisualBasic.Interaction]::InputBox($prompt, 'AppGetter - Select Download Link', '1')
    if ([string]::IsNullOrWhiteSpace($selectedNumber)) {
        throw 'No download link selected.'
    }

    $parsedNumber = 0
    if (-not [int]::TryParse($selectedNumber.Trim(), [ref]$parsedNumber) -or $parsedNumber -lt 1 -or $parsedNumber -gt $DownloadLinks.Count) {
        throw "Invalid selection: $selectedNumber"
    }

    return $DownloadLinks[$parsedNumber - 1]
}

if ([string]::IsNullOrWhiteSpace($WebsiteUrl) -and [string]::IsNullOrWhiteSpace($DownloadUrl)) {
    Write-Host 'No download source provided. Opening input dialog...' -ForegroundColor Cyan
    $sourceChoice = Get-InputFromDialog -Title 'AppGetter - Download Source' `
        -Prompt "Enter:`n  yes = direct download URL`n  no  = search a website for download links"

    if ($sourceChoice -match '^(yes|y)$') {
        $DownloadUrl = Get-InputFromDialog -Title 'AppGetter - Download URL' -Prompt 'Enter the direct download URL:'
        if ([string]::IsNullOrWhiteSpace($DownloadUrl)) {
            throw 'Download URL is required.'
        }
    } else {
        $WebsiteUrl = Get-InputFromDialog -Title 'AppGetter - Website URL' -Prompt 'Enter the website URL to scan for download links:'
        if ([string]::IsNullOrWhiteSpace($WebsiteUrl)) {
            throw 'Website URL is required.'
        }
    }

    if ([string]::IsNullOrWhiteSpace($DeveloperUrl)) {
        $DeveloperUrl = Get-InputFromDialog -Title 'AppGetter - Developer URL' -Prompt 'Optional developer/publisher URL (leave blank to skip):'
    }
    if ([string]::IsNullOrWhiteSpace($SupportUrl)) {
        $SupportUrl = Get-InputFromDialog -Title 'AppGetter - Support URL' -Prompt 'Optional support/documentation URL (leave blank to skip):'
    }
}

if ([string]::IsNullOrWhiteSpace($AppName)) {
    $AppName = Get-InputFromDialog -Title 'AppGetter - Application Name' -Prompt 'Enter the application name:'
    if ([string]::IsNullOrWhiteSpace($AppName)) {
        throw 'Application name is required.'
    }
}

if (-not $OutputPath) {
    $OutputPath = (Get-AppGetterSettings).OutputPath
}

if ([string]::IsNullOrWhiteSpace($DownloadUrl) -and -not [string]::IsNullOrWhiteSpace($WebsiteUrl)) {
    $links = Get-DownloadLinksFromWeb -Url $WebsiteUrl -AppName $AppName
    if ($links.Count -eq 0) {
        $manualUrl = Get-InputFromDialog -Title 'AppGetter - Direct Download URL' `
            -Prompt 'No links were found automatically. Enter a direct download URL:'
        if ([string]::IsNullOrWhiteSpace($manualUrl)) {
            throw "No download links found on $WebsiteUrl"
        }
        $DownloadUrl = $manualUrl
    } else {
        $DownloadUrl = Select-DownloadUrlFromCli -DownloadLinks $links
    }
}

$onProgress = {
    param($ProgressEvent)
    if ($ProgressEvent.Type -eq 'Progress') {
        $percent = if ($ProgressEvent.Percent -ge 0) { " ($($ProgressEvent.Percent)%)" } else { '' }
        $message = if ($ProgressEvent.Message) { " - $($ProgressEvent.Message)" } else { '' }
        Write-Host "[$($ProgressEvent.StepName)]$percent$message" -ForegroundColor Cyan
    } else {
        Write-Host $ProgressEvent.Message
    }
}

try {
    $result = Invoke-AppGetterPackaging -AppName $AppName -WebsiteUrl $WebsiteUrl -DownloadUrl $DownloadUrl `
        -Version $Version -Publisher $Publisher -DeveloperUrl $DeveloperUrl -SupportUrl $SupportUrl `
        -OutputPath $OutputPath -IconPath $IconPath -InstallCommand $InstallCommand `
        -AllowRuntimeProbe:$AllowRuntimeProbe -OnProgress $onProgress

    if ($result.PackagingSucceeded) {
        Write-Host "`nPackage created successfully!" -ForegroundColor Green
    } else {
        Write-Host "`nPackage created with warnings (IntuneWin packaging step failed or Content Prep Tool unavailable)." -ForegroundColor Yellow
    }

    $intuneWinLine = if ($result.IntuneWinFile) { $result.IntuneWinFile } else { '(not created)' }
    Write-Host @"

Package Details:
- Application: $($result.DisplayName)
- Package ID: $($result.PackageId)
- Version: $($result.Version)
- Publisher: $($result.Publisher)
- Download URL: $($result.DownloadUrl)
- Output Directory: $($result.VersionDirectory)
- IntuneWin Package: $intuneWinLine

Files Created:
- install.ps1
- detection.ps1
- uninstall.ps1
- README.md
- readme.txt
- app.json
- win32LobApp.json
- icon.png (if available)
- appgetter-packaging.log (on failure)

Next Steps:
1. Review the generated files in: $($result.VersionDirectory)
2. Upload the .intunewin file to Intune using README.md as your field guide
"@ -ForegroundColor Green
}
catch {
    Write-Host "[ERROR] $_" -ForegroundColor Red
    exit 1
}
