#Requires -Version 5.1

<#
.SYNOPSIS
    Launches the AppGetter Windows 11 style desktop UI.
.EXAMPLE
    .\Launch-AppGetterUI.ps1
#>

$ErrorActionPreference = 'Stop'

if ($PSVersionTable.PSEdition -ne 'Desktop') {
    Write-Warning 'AppGetter UI requires Windows PowerShell 5.1 with WPF support.'
}

$uiScript = Join-Path $PSScriptRoot 'AppGetter.UI.ps1'
if (-not (Test-Path $uiScript)) {
    throw "UI script not found at '$uiScript'."
}

. $uiScript
