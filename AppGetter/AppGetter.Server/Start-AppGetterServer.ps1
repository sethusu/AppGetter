<#
.SYNOPSIS
    Starts the AppGetter local REST API server and web UI.
.DESCRIPTION
    Serves a Windows 11-style web interface and REST API for installer
    download, analysis, and silent switch discovery.
.PARAMETER Port
    HTTP port to listen on. Defaults to config value or 8765.
.PARAMETER NoBrowser
    Do not auto-open the default browser.
.EXAMPLE
    .\Start-AppGetterServer.ps1
#>

[CmdletBinding()]
param(
    [int]$Port = 0,
    [switch]$NoBrowser
)

$ErrorActionPreference = 'Stop'
$ServerRoot = $PSScriptRoot
$AppRoot = Split-Path $ServerRoot -Parent
$CoreModule = Join-Path $AppRoot 'AppGetter.Core\AppGetter.Core.psm1'
$UiRoot = Join-Path $AppRoot 'AppGetter.UI'

if (-not (Test-Path $CoreModule)) {
    throw "AppGetter.Core module not found at $CoreModule"
}

Import-Module $CoreModule -Force
$config = Get-AppGetterConfig

if ($Port -eq 0) {
    $Port = [int]$config.ServerPort
    if ($Port -eq 0) { $Port = 8765 }
}

$MimeTypes = @{
    '.html' = 'text/html; charset=utf-8'
    '.css'  = 'text/css; charset=utf-8'
    '.js'   = 'application/javascript; charset=utf-8'
    '.json' = 'application/json; charset=utf-8'
    '.png'  = 'image/png'
    '.svg'  = 'image/svg+xml'
    '.ico'  = 'image/x-icon'
    '.woff2'= 'font/woff2'
}

function Write-JsonResponse {
    param($Context, $Data, [int]$StatusCode = 200)
    $json = $Data | ConvertTo-Json -Depth 10 -Compress
    $buffer = [System.Text.Encoding]::UTF8.GetBytes($json)
    $Context.Response.StatusCode = $StatusCode
    $Context.Response.ContentType = 'application/json; charset=utf-8'
    $Context.Response.Headers.Add('Access-Control-Allow-Origin', '*')
    $Context.Response.ContentLength64 = $buffer.Length
    $Context.Response.OutputStream.Write($buffer, 0, $buffer.Length)
    $Context.Response.Close()
}

function Write-ErrorResponse {
    param($Context, [string]$Message, [int]$StatusCode = 400)
    Write-JsonResponse -Context $Context -Data @{ success = $false; error = $Message } -StatusCode $StatusCode
}

function Read-RequestBody {
    param($Context)
    $reader = New-Object System.IO.StreamReader($Context.Request.InputStream, $Context.Request.ContentEncoding)
    $body = $reader.ReadToEnd()
    if ([string]::IsNullOrWhiteSpace($body)) { return @{} }
    return ($body | ConvertFrom-Json)
}

function Save-UploadedFile {
    param($Context, [string]$DestinationDir)

    if (-not (Test-Path $DestinationDir)) {
        New-Item -ItemType Directory -Path $DestinationDir -Force | Out-Null
    }

    $contentType = $Context.Request.ContentType
    if ($contentType -like 'multipart/form-data*') {
        $boundary = ($contentType -split 'boundary=')[1]
        $reader = New-Object System.IO.StreamReader($Context.Request.InputStream)
        $raw = $reader.ReadToEnd()
        $parts = $raw -split "--$boundary"

        foreach ($part in $parts) {
            if ($part -match 'filename="([^"]+)"') {
                $fileName = $matches[1]
                $fileStart = $part.IndexOf("`r`n`r`n")
                if ($fileStart -lt 0) { $fileStart = $part.IndexOf("`n`n") }
                if ($fileStart -ge 0) {
                    $fileContent = $part.Substring($fileStart).Trim()
                    $fileContent = $fileContent -replace "`r`n--$", '' -replace "`n--$", ''
                    $filePath = Join-Path $DestinationDir $fileName
                    [System.IO.File]::WriteAllBytes($filePath, [System.Text.Encoding]::GetEncoding('iso-8859-1').GetBytes($fileContent))
                    return $filePath
                }
            }
        }
    }

    # Raw body upload with filename in query
    $fileName = $Context.Request.QueryString['filename']
    if (-not $fileName) { $fileName = "upload_$(Get-Date -Format 'yyyyMMddHHmmss').exe" }
    $filePath = Join-Path $DestinationDir $fileName
    $stream = $Context.Request.InputStream
    $ms = New-Object System.IO.MemoryStream
    $stream.CopyTo($ms)
    [System.IO.File]::WriteAllBytes($filePath, $ms.ToArray())
    return $filePath
}

function Invoke-ApiRoute {
    param($Context)

    $method = $Context.Request.HttpMethod.ToUpper()
    $path = $Context.Request.Url.AbsolutePath.TrimEnd('/')
    if ([string]::IsNullOrEmpty($path)) { $path = '/' }

    # CORS preflight
    if ($method -eq 'OPTIONS') {
        $Context.Response.StatusCode = 204
        $Context.Response.Headers.Add('Access-Control-Allow-Origin', '*')
        $Context.Response.Headers.Add('Access-Control-Allow-Methods', 'GET, POST, PUT, OPTIONS')
        $Context.Response.Headers.Add('Access-Control-Allow-Headers', 'Content-Type')
        $Context.Response.Close()
        return
    }

    try {
        switch -Regex ($path) {
            '^/api/health$' {
                if ($method -ne 'GET') { throw 'Method not allowed' }
                Write-JsonResponse -Context $Context -Data @{
                    success = $true
                    service = 'AppGetter'
                    version = '2.0.0'
                    platform = 'Windows'
                }
            }

            '^/api/config$' {
                if ($method -eq 'GET') {
                    Write-JsonResponse -Context $Context -Data @{ success = $true; config = (Get-AppGetterConfig) }
                } elseif ($method -eq 'PUT' -or $method -eq 'POST') {
                    $body = Read-RequestBody -Context $Context
                    $params = @{}
                    if ($body.downloadLocation) { $params.DownloadLocation = $body.downloadLocation }
                    if ($body.outputPath) { $params.OutputPath = $body.outputPath }
                    if ($body.supportUrl) { $params.SupportUrl = $body.supportUrl }
                    if ($body.developerUrl) { $params.DeveloperUrl = $body.developerUrl }
                    if ($null -ne $body.serverPort) { $params.ServerPort = [int]$body.serverPort }
                    if ($null -ne $body.autoDiscoverSwitches) { $params.AutoDiscoverSwitches = [bool]$body.autoDiscoverSwitches }
                    if ($null -ne $body.testInstallers) { $params.TestInstallers = [bool]$body.testInstallers }
                    $updated = Set-AppGetterConfig @params
                    Write-JsonResponse -Context $Context -Data @{ success = $true; config = $updated }
                } else { throw 'Method not allowed' }
            }

            '^/api/download-links$' {
                if ($method -ne 'POST') { throw 'Method not allowed' }
                $body = Read-RequestBody -Context $Context
                if (-not $body.url) { throw 'url is required' }
                $links = Get-DownloadLinksFromWeb -Url $body.url -AppName $body.appName
                Write-JsonResponse -Context $Context -Data @{ success = $true; links = $links }
            }

            '^/api/download$' {
                if ($method -ne 'POST') { throw 'Method not allowed' }
                $body = Read-RequestBody -Context $Context
                if (-not $body.url) { throw 'url is required' }
                $cfg = Get-AppGetterConfig
                $dest = if ($body.destination) { $body.destination } else { $cfg.DownloadLocation }
                $result = Start-InstallerDownload -DownloadUrl $body.url -FileName $body.fileName -DestinationPath $dest
                Write-JsonResponse -Context $Context -Data @{ success = $true; download = $result }
            }

            '^/api/installers$' {
                if ($method -ne 'GET') { throw 'Method not allowed' }
                $cfg = Get-AppGetterConfig
                $dir = $Context.Request.QueryString['path']
                if (-not $dir) { $dir = $cfg.DownloadLocation }
                if (-not (Test-Path $dir)) {
                    Write-JsonResponse -Context $Context -Data @{ success = $true; installers = @(); path = $dir }
                    return
                }
                $extensions = @('.exe', '.msi', '.msix', '.appx', '.msixbundle', '.appxbundle', '.zip', '.7z')
                $files = Get-ChildItem -Path $dir -File | Where-Object { $_.Extension.ToLower() -in $extensions }
                $installers = $files | ForEach-Object {
                    @{
                        name = $_.Name
                        path = $_.FullName
                        sizeBytes = $_.Length
                        sizeMB = [Math]::Round($_.Length / 1MB, 2)
                        modified = $_.LastWriteTimeUtc.ToString('o')
                    }
                }
                Write-JsonResponse -Context $Context -Data @{ success = $true; installers = $installers; path = $dir }
            }

            '^/api/upload$' {
                if ($method -ne 'POST') { throw 'Method not allowed' }
                $cfg = Get-AppGetterConfig
                $dest = $Context.Request.QueryString['path']
                if (-not $dest) { $dest = $cfg.DownloadLocation }
                $filePath = Save-UploadedFile -Context $Context -DestinationDir $dest
                Write-JsonResponse -Context $Context -Data @{ success = $true; filePath = $filePath; fileName = (Split-Path $filePath -Leaf) }
            }

            '^/api/analyze$' {
                if ($method -ne 'POST') { throw 'Method not allowed' }
                $body = Read-RequestBody -Context $Context
                if (-not $body.installerPath) { throw 'installerPath is required' }
                $info = Get-InstallerInfo -InstallerPath $body.installerPath
                $test = Test-InstallerSilentSwitches -InstallerPath $body.installerPath
                Write-JsonResponse -Context $Context -Data @{
                    success = $true
                    info = $info
                    switchTest = $test
                }
            }

            '^/api/discover-switches$' {
                if ($method -ne 'POST') { throw 'Method not allowed' }
                $body = Read-RequestBody -Context $Context
                if (-not $body.installerPath) { throw 'installerPath is required' }
                $discovery = Find-InstallerSilentSwitches `
                    -InstallerPath $body.installerPath `
                    -SupportUrl $body.supportUrl `
                    -AppName $body.appName `
                    -SkipProbe:([bool]$body.skipProbe) `
                    -SkipWebResearch:([bool]$body.skipWebResearch)
                Write-JsonResponse -Context $Context -Data @{ success = $true; discovery = $discovery }
            }

            default {
                # Serve static UI files
                $relativePath = if ($path -eq '/') { '/index.html' } else { $path }
                $filePath = Join-Path $UiRoot ($relativePath.TrimStart('/'))

                if (-not (Test-Path $filePath) -or (Get-Item $filePath).PSIsContainer) {
                    $filePath = Join-Path $UiRoot 'index.html'
                }

                if (-not (Test-Path $filePath)) {
                    Write-ErrorResponse -Context $Context -Message 'Not found' -StatusCode 404
                    return
                }

                $ext = [System.IO.Path]::GetExtension($filePath).ToLower()
                $contentType = if ($MimeTypes.ContainsKey($ext)) { $MimeTypes[$ext] } else { 'application/octet-stream' }
                $bytes = [System.IO.File]::ReadAllBytes($filePath)
                $Context.Response.StatusCode = 200
                $Context.Response.ContentType = $contentType
                $Context.Response.ContentLength64 = $bytes.Length
                $Context.Response.OutputStream.Write($bytes, 0, $bytes.Length)
                $Context.Response.Close()
            }
        }
    } catch {
        Write-ErrorResponse -Context $Context -Message $_.Exception.Message -StatusCode 500
    }
}

# Start HTTP listener
$prefix = "http://localhost:$Port/"
$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add($prefix)

try {
    $listener.Start()
} catch {
    Write-Host "Failed to start server on $prefix" -ForegroundColor Red
    Write-Host "Try running as Administrator or use a different port with -Port parameter." -ForegroundColor Yellow
    Write-Host $_.Exception.Message -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "  AppGetter Server" -ForegroundColor Cyan
Write-Host "  ================" -ForegroundColor Cyan
Write-Host "  URL:  $prefix" -ForegroundColor Green
Write-Host "  API:  ${prefix}api/health" -ForegroundColor Green
Write-Host "  Press Ctrl+C to stop" -ForegroundColor Yellow
Write-Host ""

if (-not $NoBrowser) {
    Start-Process $prefix
}

try {
    while ($listener.IsListening) {
        $context = $listener.GetContext()
        Invoke-ApiRoute -Context $context
    }
} finally {
    $listener.Stop()
    $listener.Close()
}
