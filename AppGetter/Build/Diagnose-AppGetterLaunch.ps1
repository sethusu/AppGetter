<#
.SYNOPSIS
    Diagnoses AppGetter launch the same way AppGetter.exe does (for local Windows terminals).
.DESCRIPTION
    Prints resolved paths, probes the GUI script and XAML files, imports the module,
    and reports Content Prep Tool prerequisites. Optionally starts the GUI.
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
$tempRoot = if ($env:TEMP) { $env:TEMP } else { [System.IO.Path]::GetTempPath() }
$logPath = Join-Path $tempRoot 'AppGetter-launch.log'
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
Write-Host '--- XAML files ---' -ForegroundColor Cyan
foreach ($xamlName in @('AppGetter.MainWindow.xaml', 'AppGetter.LinkPickerDialog.xaml', 'AppGetter.IconPickerDialog.xaml')) {
    $xamlPath = Join-Path $appGetterRoot (Join-Path 'Gui' $xamlName)
    Write-Host ("  {0}  exists={1}" -f $xamlName, [bool](Test-Path -LiteralPath $xamlPath))
}

Write-Host ''
Write-Host '--- Parse check: module scripts ---' -ForegroundColor Cyan
$parseFailed = $false
foreach ($scriptFile in (Get-ChildItem -Path $appGetterRoot -Recurse -Include '*.ps1', '*.psm1' -File)) {
    $tokens = $null
    $errors = $null
    $null = [System.Management.Automation.Language.Parser]::ParseFile($scriptFile.FullName, [ref]$tokens, [ref]$errors)
    if ($errors -and $errors.Count -gt 0) {
        $parseFailed = $true
        Write-Host ("PARSE ERRORS in {0}:" -f $scriptFile.Name) -ForegroundColor Red
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
