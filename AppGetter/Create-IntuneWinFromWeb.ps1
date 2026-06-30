<#
.SYNOPSIS
    Creates an IntuneWin package from a web-based application download with registry-based detection.
.DESCRIPTION
    CLI entry point for AppGetter. For the graphical interface, run:
    .\Gui\Start-AppGetterGui.ps1
.PARAMETER WebsiteUrl
    The URL of the website containing the download link.
.PARAMETER DownloadUrl
    Optional. Direct download URL if known.
.PARAMETER AppName
    The application name.
.PARAMETER Version
    Optional. Specific version to use.
.PARAMETER Publisher
    Optional. Publisher name.
.PARAMETER DeveloperUrl
    Optional. Developer or publisher website URL.
.PARAMETER SupportUrl
    Optional. Support or documentation page URL.
.PARAMETER OutputPath
    Optional. Base output path. Defaults to the saved AppGetter settings path.
.PARAMETER IconPath
    Optional. Path to a custom PNG icon.
.PARAMETER InstallCommand
    Optional. Custom install command for the raw installer.
.PARAMETER UseGui
    Launch the graphical interface instead of running in CLI mode.
.EXAMPLE
    .\Create-IntuneWinFromWeb.ps1
.EXAMPLE
    .\Create-IntuneWinFromWeb.ps1 -WebsiteUrl "https://simion.com/" -AppName "SIMION"
.EXAMPLE
    .\Create-IntuneWinFromWeb.ps1 -DownloadUrl "https://example.com/setup.exe" -AppName "MyApp" -Version "1.0.0"
.EXAMPLE
    .\Create-IntuneWinFromWeb.ps1 -UseGui
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
    [switch]$UseGui
)

$ErrorActionPreference = 'Stop'
$moduleRoot = $PSScriptRoot

if ($UseGui -or (-not $PSBoundParameters.ContainsKey('AppName') -and -not $AppName)) {
    & (Join-Path $moduleRoot 'Gui\Start-AppGetterGui.ps1')
    return
}

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

function Select-DownloadLinkFromCli {
    param(
        [array]$Links,
        [string]$WebsiteUrl
    )

    if ($Links.Count -eq 1) {
        Write-Host "Found 1 download link: $($Links[0])" -ForegroundColor Green
        return $Links[0]
    }

    Write-Host "`nFound $($Links.Count) download links on ${WebsiteUrl}:" -ForegroundColor Green
    for ($i = 0; $i -lt $Links.Count; $i++) {
        $num = $i + 1
        Write-Host "  $num. $($Links[$i])" -ForegroundColor Cyan
    }

    Add-Type -AssemblyName Microsoft.VisualBasic
    $selectedNumber = [Microsoft.VisualBasic.Interaction]::InputBox(
        "Multiple links found. Enter the number (1-$($Links.Count)):",
        'AppGetter - Select Download Link',
        '1'
    )
    if ([string]::IsNullOrWhiteSpace($selectedNumber)) {
        throw 'No selection made.'
    }

    $parsedNumber = 0
    if (-not [int]::TryParse($selectedNumber.Trim(), [ref]$parsedNumber) -or $parsedNumber -lt 1 -or $parsedNumber -gt $Links.Count) {
        throw "Invalid selection: $selectedNumber"
    }

    return $Links[$parsedNumber - 1]
}

if ([string]::IsNullOrWhiteSpace($AppName)) {
    Write-Host 'Application name not provided. Opening input dialog...' -ForegroundColor Cyan
    $AppName = Get-InputFromDialog -Title 'AppGetter - Application Name' -Prompt 'Enter the application name:'
    if (-not $AppName) {
        throw 'Application name is required.'
    }
}

if ([string]::IsNullOrWhiteSpace($WebsiteUrl) -and [string]::IsNullOrWhiteSpace($DownloadUrl)) {
    Write-Host 'No URL provided. Opening input dialog...' -ForegroundColor Cyan
    $WebsiteUrl = Get-InputFromDialog -Title 'AppGetter - Website URL' -Prompt 'Enter the website URL or direct download URL:'
    if (-not $WebsiteUrl) {
        throw 'Website URL or Download URL is required.'
    }
    if ($WebsiteUrl -match '\.(exe|msi|msix|appx)(\?|$)') {
        $DownloadUrl = $WebsiteUrl
        $WebsiteUrl = $null
    }
}

if (-not $OutputPath) {
    $OutputPath = (Get-AppGetterSettings).OutputPath
}

$resolvedDownloadUrl = $DownloadUrl
if (-not $resolvedDownloadUrl -and $WebsiteUrl) {
    Write-Host "`n[Step 1: Finding download links]" -ForegroundColor Cyan
    $links = Get-WebDownloadLinks -WebsiteUrl $WebsiteUrl -AppName $AppName
    if ($links.Count -eq 0) {
        $manualUrl = Get-InputFromDialog -Title 'AppGetter - Direct Download URL' `
            -Prompt 'No download links found automatically. Enter a direct download URL (or leave blank to exit):'
        if (-not $manualUrl) {
            throw "No download links found on $WebsiteUrl."
        }
        $resolvedDownloadUrl = $manualUrl
    } else {
        $resolvedDownloadUrl = Select-DownloadLinkFromCli -Links $links -WebsiteUrl $WebsiteUrl
    }
}

try {
    $onProgress = {
        param($Event)
        if ($Event.Type -eq 'Progress') {
            $percent = if ($Event.Percent -ge 0) { " ($($Event.Percent)%)" } else { '' }
            $message = if ($Event.Message) { " - $($Event.Message)" } else { '' }
            Write-Host "[$($Event.StepName)]$percent$message" -ForegroundColor Cyan
        } elseif ($Event.Message) {
            Write-Host $Event.Message
        }
    }

    $result = Invoke-AppGetterPackaging -AppName $AppName -WebsiteUrl $WebsiteUrl -DownloadUrl $resolvedDownloadUrl `
        -Version $Version -Publisher $Publisher -DeveloperUrl $DeveloperUrl -SupportUrl $SupportUrl `
        -OutputPath $OutputPath -IconPath $IconPath -InstallCommand $InstallCommand -OnProgress $onProgress

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

Next Steps:
1. Review the generated files in: $($result.VersionDirectory)
2. Upload the .intunewin file to Intune
3. Use README.md as your Intune portal field guide
"@ -ForegroundColor Green
}
catch {
    Write-Host "`nPackaging failed: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
