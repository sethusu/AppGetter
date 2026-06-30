<#
.SYNOPSIS
    Launches the AppGetter web UI and API server.
.DESCRIPTION
    Entry point for the AppGetter application. Starts the local server
    with the Windows 11-style web interface.
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

$AppRoot = $PSScriptRoot
$ServerScript = Join-Path $AppRoot 'AppGetter.Server\Start-AppGetterServer.ps1'

if (-not (Test-Path $ServerScript)) {
    Write-Host "AppGetter server not found at: $ServerScript" -ForegroundColor Red
    exit 1
}

$params = @{}
if ($Port -gt 0) { $params.Port = $Port }
if ($NoBrowser) { $params.NoBrowser = $true }

& $ServerScript @params
