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
.PARAMETER InstallerPath
    Optional. Path to an installer file already on this computer. Used instead of downloading.
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
.PARAMETER LicenseInfo
    Optional. The licensing text ingested from the ServiceNow software record. AppGetter
    classifies it into a licensing pattern and applies that pattern to the package.
.PARAMETER LicenseType
    Optional. Explicit ServiceNow license type (for example 'Per device', 'Concurrent',
    'Freeware') that overrides classification from LicenseInfo.
.PARAMETER LicenseKey
    Optional. License key to apply. Overrides a key parsed out of LicenseInfo.
.PARAMETER LicenseServer
    Optional. License server as port@host for concurrent/floating licensing.
.PARAMETER LicenseServerVariable
    Optional. Environment variable the client reads to find the license server
    (defaults to the vendor variable detected in the installer, else LM_LICENSE_FILE).
.PARAMETER LicenseFilePath
    Optional. License file to ship inside the package and stage during install.
.PARAMETER LicenseFileTargetPath
    Optional. Absolute path the license file is copied to on the target device.
.PARAMETER VerifySilentSwitches
    Optional. Run ranked silent-install candidates in Windows Sandbox during packaging
    (also auto-runs when static confidence is low and Sandbox is available).
.PARAMETER UseGui
    Launch the graphical interface instead of running in CLI mode.
.EXAMPLE
    .\Create-IntuneWinFromWeb.ps1
.EXAMPLE
    .\Create-IntuneWinFromWeb.ps1 -WebsiteUrl "https://simion.com/" -AppName "SIMION"
.EXAMPLE
    .\Create-IntuneWinFromWeb.ps1 -DownloadUrl "https://example.com/installer.exe" -AppName "MyApp"
.EXAMPLE
    .\Create-IntuneWinFromWeb.ps1 -InstallerPath "C:\Installers\setup.exe" -AppName "MyApp"
.EXAMPLE
    .\Create-IntuneWinFromWeb.ps1 -DownloadUrl "https://example.com/setup.msi" -AppName "MyApp" `
        -LicenseInfo "Licensed - per device perpetual, 25 seats, license key 4XJ9-2210-KD77-9931"
.EXAMPLE
    .\Create-IntuneWinFromWeb.ps1 -InstallerPath "C:\Installers\sim.exe" -AppName "SIMION" `
        -LicenseInfo "Concurrent FlexLM, license server 27000@lm.corp.local"
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
    [string]$LicenseInfo,

    [Parameter(Mandatory = $false)]
    [string]$LicenseType,

    [Parameter(Mandatory = $false)]
    [string]$LicenseKey,

    [Parameter(Mandatory = $false)]
    [string]$LicenseServer,

    [Parameter(Mandatory = $false)]
    [string]$LicenseServerVariable,

    [Parameter(Mandatory = $false)]
    [string]$LicenseFilePath,

    [Parameter(Mandatory = $false)]
    [string]$LicenseFileTargetPath,

    [Parameter(Mandatory = $false)]
    [switch]$VerifySilentSwitches,

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

if (-not [string]::IsNullOrWhiteSpace($InstallerPath) -and -not (Test-Path -LiteralPath $InstallerPath -PathType Leaf)) {
    throw "Installer file not found: $InstallerPath"
}

if ([string]::IsNullOrWhiteSpace($WebsiteUrl) -and [string]::IsNullOrWhiteSpace($DownloadUrl) -and [string]::IsNullOrWhiteSpace($InstallerPath)) {
    Write-Host 'Website URL or Download URL not provided. Opening input dialog...' -ForegroundColor Cyan
    $hasDirectUrl = Get-InputFromDialog -Title 'AppGetter - Download Source' `
        -Prompt "Do you have a direct download URL?`n`nEnter 'yes' or 'y' for a direct link, or leave blank to search a website."

    if ($hasDirectUrl -and ($hasDirectUrl -match '^(yes|y)$')) {
        $DownloadUrl = Get-InputFromDialog -Title 'AppGetter - Enter Download URL' `
            -Prompt 'Enter the direct download URL:'
        if ([string]::IsNullOrWhiteSpace($DownloadUrl)) {
            throw 'Download URL is required.'
        }
    } else {
        $WebsiteUrl = Get-InputFromDialog -Title 'AppGetter - Enter Website URL' `
            -Prompt 'Enter the website URL containing the download link:'
        if ([string]::IsNullOrWhiteSpace($WebsiteUrl)) {
            throw 'Website URL is required.'
        }
    }
}

if ([string]::IsNullOrWhiteSpace($AppName)) {
    $AppName = Get-InputFromDialog -Title 'AppGetter - Enter Application Name' `
        -Prompt 'Enter the application name:'
    if ([string]::IsNullOrWhiteSpace($AppName)) {
        throw 'Application name is required.'
    }
}

if (-not $OutputPath) {
    $OutputPath = (Get-AppGetterSettings).OutputPath
}

try {
    if ([string]::IsNullOrWhiteSpace($InstallerPath) -and
        -not [string]::IsNullOrWhiteSpace($WebsiteUrl) -and [string]::IsNullOrWhiteSpace($DownloadUrl)) {
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

    $packParams = @{
        AppName       = $AppName
        WebsiteUrl    = $WebsiteUrl
        DownloadUrl   = $DownloadUrl
        InstallerPath = $InstallerPath
        DeveloperUrl  = $DeveloperUrl
        SupportUrl    = $SupportUrl
        Version       = $Version
        Publisher     = $Publisher
        OutputPath    = $OutputPath
        IconPath      = $IconPath
        InstallCommand = $InstallCommand
        LicenseInfo   = $LicenseInfo
        LicenseType   = $LicenseType
        LicenseKey    = $LicenseKey
        LicenseServer = $LicenseServer
        LicenseServerVariable = $LicenseServerVariable
        LicenseFilePath       = $LicenseFilePath
        LicenseFileTargetPath = $LicenseFileTargetPath
        OnProgress    = $onProgress
    }
    if ($VerifySilentSwitches) {
        $packParams.VerifySilentSwitches = $true
    }
    $result = Invoke-AppGetterPackaging @packParams

    if ($result.PackagingSucceeded) {
        Write-Host "`nPackage created successfully!" -ForegroundColor Green
    } else {
        Write-Host "`nPackage created with warnings (IntuneWin packaging step failed or Content Prep Tool unavailable)." -ForegroundColor Yellow
    }

    $intuneWinLine = if ($result.IntuneWinFile) { $result.IntuneWinFile } else { '(not created)' }
    $licensingLines = ''
    if ($result.Licensing -and $result.Licensing.Classified) {
        $licensingLines = @"

Licensing:
- Pattern: $($result.Licensing.PatternName) ($($result.Licensing.PatternId))
- License type: $($result.Licensing.LicenseType)
- Activation: $($result.Licensing.ActivationMethod)
- Confidence: $($result.Licensing.ConfidenceScore)/100
- Recommended Intune assignment: $($result.Licensing.AssignmentRecommendation)
- Manual review recommended: $(if ($result.Licensing.NeedsManualReview) { 'Yes' } else { 'No' })
"@
    }

    Write-Host @"

Package Details:
- Application: $($result.DisplayName)
- Package ID: $($result.PackageId)
- Version: $($result.Version)
- Publisher: $($result.Publisher)
- Installer Source: $($result.FinalDownloadUrl)
- Output Directory: $($result.VersionDirectory)
- IntuneWin Package: $intuneWinLine
$licensingLines
Files Created:
- install.ps1
- detection.ps1
- uninstall.ps1
- README.md
- readme.txt
- app.json
- win32LobApp.json
- licensing.json (when a licensing field was supplied)
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
