<#
.SYNOPSIS
    Starts the AppGetter web control center with one command.
.DESCRIPTION
    This launcher script:
      1) Detects a Python runtime
      2) Installs backend dependencies (unless skipped)
      3) Sets the backend port
      4) Starts the Flask backend (`python -m backend.app`)
      5) Optionally opens the UI in a browser
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [int]$Port = 8765,

    [Parameter(Mandatory = $false)]
    [switch]$SkipDependencyInstall,

    [Parameter(Mandatory = $false)]
    [switch]$NoBrowser
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

function Get-PythonCommand {
    $candidates = @("python", "python3", "py")
    foreach ($candidate in $candidates) {
        $cmd = Get-Command $candidate -ErrorAction SilentlyContinue
        if ($cmd) {
            return $candidate
        }
    }
    return $null
}

function Invoke-Python {
    param(
        [Parameter(Mandatory = $true)]
        [string]$PythonCommand,

        [Parameter(Mandatory = $true)]
        [string[]]$Arguments
    )

    if ($PythonCommand -eq "py") {
        & py -3 @Arguments
    } else {
        & $PythonCommand @Arguments
    }

    if ($LASTEXITCODE -ne 0) {
        throw "Python command failed: $PythonCommand $($Arguments -join ' ')"
    }
}

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $scriptRoot

$python = Get-PythonCommand
if (-not $python) {
    throw "Python was not found. Install Python 3 and retry."
}

Write-Host "Using Python command: $python" -ForegroundColor Cyan

$requirementsPath = Join-Path $scriptRoot "requirements.txt"
if (-not (Test-Path $requirementsPath)) {
    throw "requirements.txt not found at: $requirementsPath"
}

if (-not $SkipDependencyInstall) {
    Write-Host "Installing dependencies from requirements.txt..." -ForegroundColor Cyan
    Invoke-Python -PythonCommand $python -Arguments @("-m", "pip", "install", "-r", $requirementsPath)
} else {
    Write-Host "Skipping dependency installation." -ForegroundColor Yellow
}

$url = "http://localhost:$Port"
$env:APPGETTER_PORT = "$Port"

Write-Host "Starting AppGetter backend on $url" -ForegroundColor Green
Write-Host "Press Ctrl+C to stop." -ForegroundColor DarkGray

if (-not $NoBrowser) {
    try {
        Start-Process $url | Out-Null
    } catch {
        Write-Host "Could not auto-open browser. Open $url manually." -ForegroundColor Yellow
    }
}

Invoke-Python -PythonCommand $python -Arguments @("-m", "backend.app")
