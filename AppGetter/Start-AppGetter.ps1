<#
.SYNOPSIS
    Launches AppGetter in GUI (default) or CLI mode.
.DESCRIPTION
    Thin launcher for `Create-IntuneWinFromWeb.ps1`. By default it opens the
    PowerShell desktop GUI, mirroring WinGetter style usage. Use `-NoGui` to
    run the CLI workflow directly.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [switch]$NoGui
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$entryScript = Join-Path $scriptRoot "Create-IntuneWinFromWeb.ps1"
if (-not (Test-Path $entryScript)) {
    throw "Entry script not found: $entryScript"
}

Set-Location $scriptRoot
if ($NoGui) {
    & $entryScript -NoGui
    return
}

& $entryScript -UseGui
