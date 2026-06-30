<#
.SYNOPSIS
    Creates an IntuneWin package from a web-based application download with registry-based detection.
.DESCRIPTION
    CLI entry point for AppGetter. For the graphical interface, run:
    .\Gui\Start-AppGetterGui.ps1
    or
    .\Start-AppGetter.ps1
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
    Optional. Base output path. Defaults to saved AppGetter settings.
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
    .\Create-IntuneWinFromWeb.ps1 -DownloadUrl "https://example.com/installer.exe" -AppName "MyApp"
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

$hasCliInput = $PSBoundParameters.ContainsKey('AppName') -or $AppName -or $WebsiteUrl -or $DownloadUrl

if ($UseGui -or -not $hasCliInput) {
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

if ([string]::IsNullOrWhiteSpace($AppName)) {
    Write-Host 'Application name not provided. Opening input dialog...' -ForegroundColor Cyan
    $AppName = Get-InputFromDialog -Title 'AppGetter - Application Name' -Prompt 'Enter the application name:'
    if ([string]::IsNullOrWhiteSpace($AppName)) {
        Write-Host '[ERROR] Application name is required.' -ForegroundColor Red
        exit 1
    }
}

if ([string]::IsNullOrWhiteSpace($WebsiteUrl) -and [string]::IsNullOrWhiteSpace($DownloadUrl)) {
    Write-Host 'No URL provided. Opening input dialog...' -ForegroundColor Cyan
    $DownloadUrl = Get-InputFromDialog -Title 'AppGetter - Download URL' -Prompt 'Enter a website URL or direct download URL:'
    if ([string]::IsNullOrWhiteSpace($DownloadUrl)) {
        Write-Host '[ERROR] WebsiteUrl or DownloadUrl is required.' -ForegroundColor Red
        exit 1
    }
    if ($DownloadUrl -match '\.(exe|msi|msix|appx)(\?|$)') {
        # direct download
    } else {
        $WebsiteUrl = $DownloadUrl
        $DownloadUrl = $null
    }
}

if (-not $OutputPath) {
    $OutputPath = (Get-AppGetterSettings).OutputPath
}

try {
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

    $result = Invoke-AppGetterPackaging -AppName $AppName -WebsiteUrl $WebsiteUrl -DownloadUrl $DownloadUrl `
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
