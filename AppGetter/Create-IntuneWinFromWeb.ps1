<#
.SYNOPSIS
    Creates an IntuneWin package from a download URL or a local installer file, with registry-based detection.
.DESCRIPTION
    CLI entry point for AppGetter. For the graphical interface, run:
    .\Launch-AppGetter.ps1   (or double-click AppGetter.exe / Start-AppGetter.cmd)
.PARAMETER DownloadUrl
    Direct download URL for the installer.
.PARAMETER InstallerPath
    Path to an installer that already exists on this computer. Takes precedence over
    DownloadUrl and WebsiteUrl.
.PARAMETER WebsiteUrl
    The URL of a website to scan for download links.
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
    Optional. Base output path. Defaults to saved AppGetter settings path.
.PARAMETER IconPath
    Optional. Path to a custom PNG icon.
.PARAMETER InstallCommand
    Optional. Custom install command.
.PARAMETER UseGui
    Launch the graphical interface instead of running in CLI mode.
.EXAMPLE
    .\Create-IntuneWinFromWeb.ps1
.EXAMPLE
    .\Create-IntuneWinFromWeb.ps1 -DownloadUrl "https://example.com/installer.exe" -AppName "MyApp"
.EXAMPLE
    .\Create-IntuneWinFromWeb.ps1 -InstallerPath "C:\Installers\setup.exe" -AppName "MyApp"
.EXAMPLE
    .\Create-IntuneWinFromWeb.ps1 -WebsiteUrl "https://simion.com/" -AppName "SIMION"
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
    [string]$InstallerPath,

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

if ($UseGui -or (
        -not $PSBoundParameters.ContainsKey('AppName') -and
        -not $AppName -and
        -not $WebsiteUrl -and
        -not $DownloadUrl -and
        -not $InstallerPath
    )) {
    & (Join-Path $moduleRoot 'Launch-AppGetter.ps1')
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

function Select-InstallerFileFromDialog {
    Add-Type -AssemblyName System.Windows.Forms
    $dialog = New-Object System.Windows.Forms.OpenFileDialog
    $dialog.Title = 'AppGetter - Select the installer to package'
    $dialog.Filter = 'Installers (*.exe;*.msi;*.msix;*.appx)|*.exe;*.msi;*.msix;*.appx|All files (*.*)|*.*'
    $dialog.CheckFileExists = $true
    try {
        if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
            return $dialog.FileName
        }
    } finally {
        $dialog.Dispose()
    }
    return $null
}

function Select-DownloadLinkFromCli {
    param([array]$Links)

    if ($Links.Count -eq 1) {
        Write-Host "Found 1 download link: $($Links[0])" -ForegroundColor Green
        return $Links[0]
    }

    Write-Host "`nFound $($Links.Count) potential download links:" -ForegroundColor Green
    for ($i = 0; $i -lt $Links.Count; $i++) {
        Write-Host "  $($i + 1). $($Links[$i])" -ForegroundColor Cyan
    }

    Add-Type -AssemblyName Microsoft.VisualBasic
    $selectedNumber = [Microsoft.VisualBasic.Interaction]::InputBox(
        "Multiple download links found. Enter the number (1-$($Links.Count)):",
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

if ([string]::IsNullOrWhiteSpace($WebsiteUrl) -and
    [string]::IsNullOrWhiteSpace($DownloadUrl) -and
    [string]::IsNullOrWhiteSpace($InstallerPath)) {

    Write-Host 'No installer source provided. Opening input dialog...' -ForegroundColor Cyan
    $sourceChoice = Get-InputFromDialog -Title 'AppGetter - Installer Source' `
        -Prompt "Where is the installer?`n`n  url     - direct download URL`n  file    - installer already on this computer`n  website - scan a website for download links" `
        -DefaultValue 'url'

    switch -Regex ($sourceChoice) {
        '^(?i)f(ile)?$' {
            $InstallerPath = Select-InstallerFileFromDialog
            if ([string]::IsNullOrWhiteSpace($InstallerPath)) {
                throw 'Installer file is required.'
            }
        }
        '^(?i)w(ebsite)?$' {
            $WebsiteUrl = Get-InputFromDialog -Title 'AppGetter - Enter Website URL' `
                -Prompt 'Enter the website URL containing the download link:'
            if ([string]::IsNullOrWhiteSpace($WebsiteUrl)) {
                throw 'Website URL is required.'
            }
        }
        default {
            $DownloadUrl = Get-InputFromDialog -Title 'AppGetter - Enter Download URL' `
                -Prompt 'Enter the direct download URL:'
            if ([string]::IsNullOrWhiteSpace($DownloadUrl)) {
                throw 'Download URL is required.'
            }
        }
    }
}

if (-not [string]::IsNullOrWhiteSpace($InstallerPath) -and -not (Test-Path -LiteralPath $InstallerPath)) {
    throw "Installer file not found: $InstallerPath"
}

if ([string]::IsNullOrWhiteSpace($AppName)) {
    $defaultName = if ($InstallerPath) { [System.IO.Path]::GetFileNameWithoutExtension($InstallerPath) } else { '' }
    $AppName = Get-InputFromDialog -Title 'AppGetter - Enter Application Name' `
        -Prompt 'Enter the application name:' -DefaultValue $defaultName
    if ([string]::IsNullOrWhiteSpace($AppName)) {
        throw 'Application name is required.'
    }
}

if (-not $OutputPath) {
    $OutputPath = (Get-AppGetterSettings).OutputPath
}

try {
    if (-not [string]::IsNullOrWhiteSpace($WebsiteUrl) -and
        [string]::IsNullOrWhiteSpace($DownloadUrl) -and
        [string]::IsNullOrWhiteSpace($InstallerPath)) {

        Write-Host "`n[Step 1: Finding download links]" -ForegroundColor Cyan
        $downloadLinks = Find-WebDownloadLinks -Url $WebsiteUrl -AppName $AppName
        if ($downloadLinks.Count -eq 0) {
            $directUrl = Get-InputFromDialog -Title 'AppGetter - Direct Download URL' `
                -Prompt 'No download links found automatically. Enter a direct download URL (or leave blank to exit):'
            if ([string]::IsNullOrWhiteSpace($directUrl)) {
                throw 'No download URL available.'
            }
            $DownloadUrl = $directUrl
        } elseif ($downloadLinks.Count -gt 1) {
            $DownloadUrl = Select-DownloadLinkFromCli -Links $downloadLinks
        } else {
            $DownloadUrl = $downloadLinks[0]
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

    $result = Invoke-AppGetterPackaging -AppName $AppName -WebsiteUrl $WebsiteUrl -DownloadUrl $DownloadUrl `
        -InstallerPath $InstallerPath -DeveloperUrl $DeveloperUrl -SupportUrl $SupportUrl -Version $Version `
        -Publisher $Publisher -OutputPath $OutputPath -IconPath $IconPath -InstallCommand $InstallCommand `
        -OnProgress $onProgress

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
- Installer source: $($result.SourceType)
- Installer location: $($result.SourceLocation)
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
