#Requires -Version 5.1

<#
.SYNOPSIS
    Analyzes an installer for silent install switches using AppGetter modules.
.EXAMPLE
    .\Test-InstallerSwitches.ps1 -InstallerPath C:\Downloads\setup.exe -SupportUrl https://vendor.com/docs
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$InstallerPath,
    [string]$SupportUrl,
    [string]$AppName,
    [switch]$ProbeHelp,
    [switch]$TestInstall,
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'
$moduleRoot = Join-Path $PSScriptRoot 'Modules'
Import-Module (Join-Path $moduleRoot 'AppGetter.Config') -Force
Import-Module (Join-Path $moduleRoot 'AppGetter.SilentSwitch') -Force

$result = Find-InstallerSilentSwitches `
    -InstallerPath $InstallerPath `
    -SupportUrl $SupportUrl `
    -AppName $AppName `
    -ProbeHelp:$ProbeHelp `
    -TestInstall:$TestInstall `
    -DryRun:$DryRun

$result | ConvertTo-Json -Depth 6
Write-Host "`nRecommended install command:" -ForegroundColor Green
Write-Host $result.InstallCommand
