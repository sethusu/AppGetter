<#
.SYNOPSIS
    Runs AppGetter Pester tests.
#>
[CmdletBinding()]
param(
    [string]$Path = (Join-Path $PSScriptRoot 'Tests'),
    [string[]]$Tag,
    [string[]]$ExcludeTag = @('SandboxLive')
)

$ErrorActionPreference = 'Stop'

if (-not (Get-Module -ListAvailable -Name Pester | Where-Object { $_.Version -ge [version]'5.0.0' })) {
    Write-Host 'Installing Pester 5...' -ForegroundColor Cyan
    Install-Module Pester -MinimumVersion 5.0.0 -Scope CurrentUser -Force -SkipPublisherCheck
}

Import-Module Pester -MinimumVersion 5.0.0 -Force

$config = New-PesterConfiguration
$config.Run.Path = $Path
$config.Run.Exit = $true
$config.Output.Verbosity = 'Detailed'

if ($Tag -and $Tag.Count -gt 0) {
    $config.Filter.Tag = $Tag
}
if ($ExcludeTag -and $ExcludeTag.Count -gt 0) {
    $config.Filter.ExcludeTag = $ExcludeTag
}

Write-Host "Running Pester tests under $Path (ExcludeTag: $($ExcludeTag -join ', '))" -ForegroundColor Cyan
Invoke-Pester -Configuration $config
