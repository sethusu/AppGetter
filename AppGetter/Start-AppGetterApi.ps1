#Requires -Version 5.1

<#
.SYNOPSIS
    Starts only the AppGetter backend API.
#>

$ErrorActionPreference = 'Stop'
$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$apiProject = Join-Path $scriptRoot 'src\AppGetter.Api\AppGetter.Api.csproj'

if (-not (Get-Command dotnet -ErrorAction SilentlyContinue)) {
    throw 'The .NET SDK is required.'
}

Write-Host 'Starting AppGetter API on http://localhost:5050' -ForegroundColor Green
dotnet run --project $apiProject --no-launch-profile
