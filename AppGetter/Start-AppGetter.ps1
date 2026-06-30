#Requires -Version 5.1

<#
.SYNOPSIS
    Starts the AppGetter backend API and desktop UI.
.DESCRIPTION
    Launches the ASP.NET Core API on http://localhost:5050, then opens the WinUI 3 desktop app.
    Build the solution on Windows first: dotnet build AppGetter\src\AppGetter.sln -c Release
#>

$ErrorActionPreference = 'Stop'
$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$srcRoot = Join-Path $scriptRoot 'src'
$apiProject = Join-Path $srcRoot 'AppGetter.Api\AppGetter.Api.csproj'
$appProject = Join-Path $srcRoot 'AppGetter.App\AppGetter.App.csproj'

function Test-DotNet {
    if (-not (Get-Command dotnet -ErrorAction SilentlyContinue)) {
        throw 'The .NET SDK is required. Install .NET 8 SDK from https://dotnet.microsoft.com/download'
    }
}

function Start-AppGetterApi {
    param([string]$Configuration = 'Release')

    $apiDll = Join-Path $srcRoot "AppGetter.Api\bin\$Configuration\net8.0\AppGetter.Api.dll"
    if (-not (Test-Path $apiDll)) {
        Write-Host 'Building AppGetter API...' -ForegroundColor Cyan
        dotnet build $apiProject -c $Configuration | Out-Host
    }

    Write-Host 'Starting AppGetter API on http://localhost:5050 ...' -ForegroundColor Green
    return Start-Process -FilePath 'dotnet' -ArgumentList @('run', '--project', $apiProject, '-c', $Configuration, '--no-launch-profile') -PassThru -WindowStyle Minimized
}

function Start-AppGetterUi {
    param([string]$Configuration = 'Release')

    $appExe = Join-Path $srcRoot "AppGetter.App\bin\$Configuration\net8.0-windows10.0.19041.0\AppGetter.App.exe"
    if (-not (Test-Path $appExe)) {
        Write-Host 'Building AppGetter desktop app...' -ForegroundColor Cyan
        dotnet build $appProject -c $Configuration | Out-Host
    }

    Write-Host 'Launching AppGetter desktop UI...' -ForegroundColor Green
    Start-Process -FilePath $appExe
}

Test-DotNet
$apiProcess = Start-AppGetterApi
Start-Sleep -Seconds 2
Start-AppGetterUi

Write-Host @"

AppGetter is running.
- API:    http://localhost:5050/swagger
- UI:     AppGetter desktop app
- Stop:   Close this window or stop the API process (PID $($apiProcess.Id))

"@ -ForegroundColor Cyan
