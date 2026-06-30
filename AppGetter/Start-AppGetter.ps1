<#
.SYNOPSIS
    Launches AppGetter packaging directly (PowerShell-only).
.DESCRIPTION
    Convenience wrapper for Create-IntuneWinFromWeb.ps1.
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
    [string]$OutputPath,

    [Parameter(Mandatory = $false)]
    [string]$IconPath,

    [Parameter(Mandatory = $false)]
    [string]$InstallCommand
)

$ErrorActionPreference = 'Stop'
$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$entryScript = Join-Path $scriptRoot 'Create-IntuneWinFromWeb.ps1'

if (-not (Test-Path $entryScript)) {
    throw "Entry script not found: $entryScript"
}

& $entryScript `
    -WebsiteUrl $WebsiteUrl `
    -DownloadUrl $DownloadUrl `
    -AppName $AppName `
    -Version $Version `
    -Publisher $Publisher `
    -OutputPath $OutputPath `
    -IconPath $IconPath `
    -InstallCommand $InstallCommand
