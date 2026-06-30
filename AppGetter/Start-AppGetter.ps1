<#
.SYNOPSIS
    Starts AppGetter in PowerShell-only mode.
.DESCRIPTION
    Wrapper around Create-IntuneWinFromWeb.ps1 with a friendly entry point.
    No Python runtime or background service is required.
#>

[CmdletBinding()]
param(
    [string]$AppName,
    [string]$DownloadUrl,
    [string]$WebsiteUrl,
    [string]$Version,
    [string]$Publisher,
    [string]$DeveloperUrl,
    [string]$SupportUrl,
    [string]$Description,
    [string]$OutputPath,
    [string]$IconPath,
    [string]$InstallCommand
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$entryScript = Join-Path $scriptRoot "Create-IntuneWinFromWeb.ps1"

if (-not (Test-Path $entryScript)) {
    throw "Create-IntuneWinFromWeb.ps1 not found at: $entryScript"
}

Write-Host "Launching AppGetter packaging workflow..." -ForegroundColor Cyan

& $entryScript `
    -AppName $AppName `
    -DownloadUrl $DownloadUrl `
    -WebsiteUrl $WebsiteUrl `
    -Version $Version `
    -Publisher $Publisher `
    -DeveloperUrl $DeveloperUrl `
    -SupportUrl $SupportUrl `
    -Description $Description `
    -OutputPath $OutputPath `
    -IconPath $IconPath `
    -InstallCommand $InstallCommand
