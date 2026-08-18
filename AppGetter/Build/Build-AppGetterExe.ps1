<#
.SYNOPSIS
    Builds a double-clickable AppGetter.exe with ps2exe and stages a distributable folder.
.DESCRIPTION
    Installs the ps2exe PowerShell Gallery module if needed, copies AppGetter runtime
    files into dist\AppGetter, and compiles Launch-AppGetter.ps1 to AppGetter.exe
    (no console window). Run this on Windows with PowerShell 5.1+.

    The resulting folder can be zipped and shared. End users double-click AppGetter.exe
    -- no elevated PowerShell session required.
.PARAMETER OutputRoot
    Root folder for the staged build. Defaults to <repo>\dist.
.PARAMETER SkipZip
    Do not create AppGetter-portable.zip next to the staged folder.
.PARAMETER ForceReinstallPs2Exe
    Reinstall the ps2exe module even if it is already present.
.EXAMPLE
    .\Build\Build-AppGetterExe.ps1
.EXAMPLE
    .\Build\Build-AppGetterExe.ps1 -SkipZip
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$OutputRoot,

    [Parameter(Mandatory = $false)]
    [switch]$SkipZip,

    [Parameter(Mandatory = $false)]
    [switch]$ForceReinstallPs2Exe
)

$ErrorActionPreference = 'Stop'

if ($env:OS -ne 'Windows_NT') {
    throw 'Build-AppGetterExe.ps1 must be run on Windows (ps2exe requires Windows PowerShell / .NET Framework).'
}

$appGetterRoot = Split-Path -Parent $PSScriptRoot
$repoRoot = Split-Path -Parent $appGetterRoot
$launcherScript = Join-Path $appGetterRoot 'Launch-AppGetter.ps1'
$manifestPath = Join-Path $appGetterRoot 'AppGetter.psd1'

if (-not (Test-Path -LiteralPath $launcherScript)) {
    throw "Launcher not found: $launcherScript"
}

if (-not (Test-Path -LiteralPath $manifestPath)) {
    throw "Module manifest not found: $manifestPath"
}

$manifestData = Import-PowerShellDataFile -LiteralPath $manifestPath
$version = [string]$manifestData.ModuleVersion
if ([string]::IsNullOrWhiteSpace($version)) {
    $version = '0.0.0'
}
# File version wants four parts (e.g. 3.0.0.0).
$versionParts = @($version.Split('.'))
while ($versionParts.Count -lt 4) { $versionParts += '0' }
$fileVersion = ($versionParts[0..3] -join '.')

if (-not $OutputRoot) {
    $OutputRoot = Join-Path $repoRoot 'dist'
}

$stageDir = Join-Path $OutputRoot 'AppGetter'
$exePath = Join-Path $stageDir 'AppGetter.exe'
$zipPath = Join-Path $OutputRoot 'AppGetter-portable.zip'

Write-Host 'AppGetter ps2exe build' -ForegroundColor Cyan
Write-Host "  Version : $version ($fileVersion)"
Write-Host "  Source  : $appGetterRoot"
Write-Host "  Output  : $stageDir"

function Install-Ps2ExeModule {
    param([switch]$Force)

    $existing = Get-Module -ListAvailable -Name ps2exe | Select-Object -First 1
    if ($existing -and -not $Force) {
        Write-Host "Using ps2exe $($existing.Version) from $($existing.ModuleBase)" -ForegroundColor DarkGray
        Import-Module ps2exe -Force
        return
    }

    Write-Host 'Installing ps2exe from the PowerShell Gallery (CurrentUser)...' -ForegroundColor Yellow
    Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -Scope CurrentUser -ErrorAction SilentlyContinue | Out-Null
    Install-Module -Name ps2exe -Scope CurrentUser -Force -AllowClobber -SkipPublisherCheck
    Import-Module ps2exe -Force
}

Install-Ps2ExeModule -Force:$ForceReinstallPs2Exe

if (-not (Get-Command Invoke-ps2exe -ErrorAction SilentlyContinue)) {
    throw 'Invoke-ps2exe was not found after importing the ps2exe module.'
}

if (Test-Path -LiteralPath $stageDir) {
    Write-Host "Cleaning previous stage: $stageDir" -ForegroundColor DarkGray
    Remove-Item -LiteralPath $stageDir -Recurse -Force
}

New-Item -ItemType Directory -Path $stageDir -Force | Out-Null

$copyItems = @(
    'Gui'
    'Private'
    'AppGetter.psd1'
    'AppGetter.psm1'
    'Create-IntuneWinFromWeb.ps1'
    'Launch-AppGetter.ps1'
    'Start-AppGetter.cmd'
    'README.md'
    'CHANGELOG.md'
)

foreach ($item in $copyItems) {
    $source = Join-Path $appGetterRoot $item
    if (-not (Test-Path -LiteralPath $source)) {
        Write-Warning "Skipping missing item: $item"
        continue
    }
    $destination = Join-Path $stageDir $item
    Copy-Item -LiteralPath $source -Destination $destination -Recurse -Force
}

Write-Host "Compiling $launcherScript -> $exePath" -ForegroundColor Cyan

# -noConsole: Windows GUI subsystem (no flash console). STA is used for WinExe hosts.
# Omit -requireAdmin so the exe runs without UAC elevation.
Invoke-ps2exe `
    -inputFile $launcherScript `
    -outputFile $exePath `
    -noConsole `
    -noOutput `
    -noError `
    -title 'AppGetter' `
    -description 'Create Intune Win32 packages from a download URL or a local installer file' `
    -company 'AppGetter' `
    -product 'AppGetter' `
    -copyright 'AppGetter' `
    -version $fileVersion

if (-not (Test-Path -LiteralPath $exePath)) {
    throw "ps2exe completed but AppGetter.exe was not created at $exePath"
}

# Leave Launch-AppGetter.ps1 in the stage for debugging; the exe is the primary entry point.
$readmeLines = @(
    '# AppGetter portable'
    ''
    "Version: $version"
    ''
    '## Run'
    ''
    '1. Double-click **AppGetter.exe** (no admin PowerShell required).'
    '2. Keep this folder intact - `AppGetter.exe` must stay next to `Gui\`, `Private\`, and `AppGetter.psd1`.'
    '3. The exe starts the GUI via Windows PowerShell 5.1 in a separate process.'
    '4. If antivirus blocks the exe, use `Start-AppGetter.cmd` or `Launch-AppGetter.ps1` instead.'
    ''
    '## Requirements'
    ''
    '- Windows 10/11 with PowerShell 5.1+'
    '- Microsoft Win32 Content Prep Tool (`intunewinapputil`) - install from the GUI if missing'
    ''
    '## CLI'
    ''
    '```powershell'
    '.\Create-IntuneWinFromWeb.ps1 -DownloadUrl "https://example.com/setup.exe" -AppName "MyApp"'
    '.\Create-IntuneWinFromWeb.ps1 -InstallerPath "C:\Installers\setup.exe" -AppName "MyApp"'
    '```'
    ''
)

Set-Content -LiteralPath (Join-Path $stageDir 'START-HERE.md') -Value $readmeLines -Encoding UTF8

if (-not $SkipZip) {
    if (Test-Path -LiteralPath $zipPath) {
        Remove-Item -LiteralPath $zipPath -Force
    }
    Write-Host "Creating zip: $zipPath" -ForegroundColor Cyan
    Compress-Archive -Path $stageDir -DestinationPath $zipPath -Force
}

Write-Host ''
Write-Host 'Build complete.' -ForegroundColor Green
Write-Host "  Folder : $stageDir"
Write-Host "  Exe    : $exePath"
if (-not $SkipZip) {
    Write-Host "  Zip    : $zipPath"
}
Write-Host ''
Write-Host 'Share the AppGetter folder (or zip). End users double-click AppGetter.exe.' -ForegroundColor Green
