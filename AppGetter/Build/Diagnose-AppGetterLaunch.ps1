<#
.SYNOPSIS
    Diagnoses AppGetter launch the same way AppGetter.exe does (for local Windows terminals).
.DESCRIPTION
    Prints resolved paths, probes the GUI script, and optionally starts the GUI
    with the same EncodedCommand technique used by the compiled launcher.
.PARAMETER StartGui
    Actually start the GUI (default: only print diagnostics).
.EXAMPLE
    .\Build\Diagnose-AppGetterLaunch.ps1
.EXAMPLE
    .\Build\Diagnose-AppGetterLaunch.ps1 -StartGui
#>

[CmdletBinding()]
param(
    [switch]$StartGui
)

$ErrorActionPreference = 'Continue'
$appGetterRoot = Split-Path -Parent $PSScriptRoot
$guiScript = Join-Path $appGetterRoot 'Gui\Start-AppGetterGui.ps1'
$manifest = Join-Path $appGetterRoot 'AppGetter.psd1'
$launcher = Join-Path $appGetterRoot 'Launch-AppGetter.ps1'
$logPath = Join-Path $env:TEMP 'AppGetter-launch.log'
$windowsPowerShell = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'

Write-Host '=== AppGetter launch diagnosis ===' -ForegroundColor Cyan
Write-Host "PSVersion: $($PSVersionTable.PSVersion)"
Write-Host "Edition:   $($PSVersionTable.PSEdition)"
Write-Host "STA:       $([System.Threading.Thread]::CurrentThread.GetApartmentState())"
Write-Host "Root:      $appGetterRoot"
Write-Host "Has space: $($appGetterRoot -match '\s')"
Write-Host "Launcher:  $launcher  exists=$([bool](Test-Path -LiteralPath $launcher))"
Write-Host "GUI:       $guiScript  exists=$([bool](Test-Path -LiteralPath $guiScript))"
Write-Host "Manifest:  $manifest  exists=$([bool](Test-Path -LiteralPath $manifest))"
Write-Host "powershell.exe: $windowsPowerShell  exists=$([bool](Test-Path -LiteralPath $windowsPowerShell))"
Write-Host "Log path:  $logPath"

Write-Host ''
Write-Host '--- Parse check: Private scripts ---' -ForegroundColor Cyan
$privateDir = Join-Path $appGetterRoot 'Private'
$parseFailed = $false
foreach ($scriptPath in Get-ChildItem -LiteralPath $privateDir -Filter '*.ps1' -File) {
    $tokens = $null
    $errors = $null
    $null = [System.Management.Automation.Language.Parser]::ParseFile($scriptPath.FullName, [ref]$tokens, [ref]$errors)
    if ($errors -and $errors.Count -gt 0) {
        $parseFailed = $true
        Write-Host ("PARSE ERRORS in {0}:" -f $scriptPath.Name) -ForegroundColor Red
        $errors | ForEach-Object { Write-Host ("  {0}" -f $_) -ForegroundColor Red }
    }
}
if (-not $parseFailed) {
    Write-Host 'OK (no parse errors)' -ForegroundColor Green
}

Write-Host ''
Write-Host '--- Import module ---' -ForegroundColor Cyan
try {
    Import-Module $manifest -Force -ErrorAction Stop
    Write-Host 'Import-Module OK' -ForegroundColor Green
    Test-AppGetterPrerequisites | Format-List | Out-String | Write-Host
} catch {
    Write-Host ("Import-Module FAILED: {0}" -f $_.Exception.Message) -ForegroundColor Red
}

if (-not $StartGui) {
    Write-Host ''
    Write-Host 'Dry run only. To start the GUI:' -ForegroundColor Yellow
    Write-Host '  .\Build\Diagnose-AppGetterLaunch.ps1 -StartGui'
    Write-Host 'Or run the GUI directly:'
    Write-Host "  powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -File `"$guiScript`""
    return
}

Write-Host ''
Write-Host '--- Starting GUI in-process ---' -ForegroundColor Cyan
& $guiScript
