<#
.SYNOPSIS
Convenience launcher for the AppGetter packaging script.
.DESCRIPTION
Executes Create-IntuneWinFromWeb.ps1 with passed-through parameters.
#>

[CmdletBinding()]
param(
    [string]$WebsiteUrl,
    [string]$DownloadUrl,
    [string]$AppName,
    [string]$Version,
    [string]$Publisher,
    [string]$OutputPath,
    [string]$IconPath,
    [string]$InstallCommand
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$entryScript = Join-Path $scriptRoot "Create-IntuneWinFromWeb.ps1"

if (-not (Test-Path $entryScript)) {
    throw "Create-IntuneWinFromWeb.ps1 was not found at $entryScript"
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
