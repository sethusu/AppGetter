<#
.SYNOPSIS
    Launches AppGetter with the web UI and REST API backend.
.DESCRIPTION
    Starts the AppGetter API server and opens the Windows 11 style web UI
    in the default browser. All configuration is persisted in %APPDATA%\AppGetter.
.EXAMPLE
    .\Start-AppGetter.ps1
.EXAMPLE
    .\Start-AppGetter.ps1 -Port 9000 -NoBrowser
#>

[CmdletBinding()]
param(
    [int]$Port = 0,
    [switch]$NoBrowser
)

$ErrorActionPreference = 'Stop'
$scriptRoot = $PSScriptRoot
$moduleRoot = Join-Path $scriptRoot 'Modules'

Import-Module (Join-Path $moduleRoot 'AppGetter.Config.psm1') -Force
$config = Get-AppGetterConfig

if ($Port -eq 0) { $Port = $config.apiPort }
$url = "http://localhost:$Port/"

Write-Host @"

  ╔═══════════════════════════════════════╗
  ║           AppGetter v2.0              ║
  ║   IntuneWin Package Creator + UI      ║
  ╚═══════════════════════════════════════╝

"@ -ForegroundColor Cyan

Write-Host "Download Location: $($config.downloadLocation)" -ForegroundColor Gray
Write-Host "Package Output:  $($config.outputPath)" -ForegroundColor Gray
Write-Host "API + UI:        $url" -ForegroundColor Green
Write-Host ""

if (-not $NoBrowser -and $config.autoOpenBrowser) {
    Start-Process $url
}

$apiScript = Join-Path $scriptRoot 'Backend\Start-AppGetterApi.ps1'
& $apiScript -Port $Port -ModuleRoot $moduleRoot
