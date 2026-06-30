<#
.SYNOPSIS
    AppGetter REST API backend for the web UI.
.DESCRIPTION
    Starts an HTTP listener that exposes configuration, download, switch discovery,
    and packaging endpoints consumed by the AppGetter web UI.
#>

[CmdletBinding()]
param(
    [int]$Port = 0,
    [string]$ModuleRoot = ''
)

$ErrorActionPreference = 'Stop'

if (-not $ModuleRoot) {
    $ModuleRoot = Join-Path $PSScriptRoot '..\Modules'
}

Import-Module (Join-Path $ModuleRoot 'AppGetter.Config.psm1') -Force
Import-Module (Join-Path $ModuleRoot 'AppGetter.SwitchDiscovery.psm1') -Force
Import-Module (Join-Path $ModuleRoot 'AppGetter.Core.psm1') -Force

$config = Get-AppGetterConfig
if ($Port -eq 0) { $Port = $config.apiPort }

$uiRoot = Join-Path $PSScriptRoot '..\UI'
$prefix = "http://localhost:$Port/"

$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add($prefix)

function Send-JsonResponse {
    param(
        [System.Net.HttpListenerResponse]$Response,
        [object]$Data,
        [int]$StatusCode = 200
    )

    $json = $Data | ConvertTo-Json -Depth 10 -Compress:$false
    $buffer = [System.Text.Encoding]::UTF8.GetBytes($json)
    $Response.StatusCode = $StatusCode
    $Response.ContentType = 'application/json; charset=utf-8'
    $Response.Headers.Add('Access-Control-Allow-Origin', '*')
    $Response.Headers.Add('Access-Control-Allow-Methods', 'GET, POST, PUT, OPTIONS')
    $Response.Headers.Add('Access-Control-Allow-Headers', 'Content-Type')
    $Response.ContentLength64 = $buffer.Length
    $Response.OutputStream.Write($buffer, 0, $buffer.Length)
    $Response.Close()
}

function Send-TextResponse {
    param(
        [System.Net.HttpListenerResponse]$Response,
        [string]$Content,
        [string]$ContentType = 'text/plain'
    )

    $buffer = [System.Text.Encoding]::UTF8.GetBytes($Content)
    $Response.StatusCode = 200
    $Response.ContentType = $ContentType
    $Response.Headers.Add('Access-Control-Allow-Origin', '*')
    $Response.ContentLength64 = $buffer.Length
    $Response.OutputStream.Write($buffer, 0, $buffer.Length)
    $Response.Close()
}

function Send-FileResponse {
    param(
        [System.Net.HttpListenerResponse]$Response,
        [string]$FilePath,
        [string]$ContentType
    )

    if (-not (Test-Path $FilePath)) {
        $Response.StatusCode = 404
        $Response.Close()
        return
    }

    $bytes = [System.IO.File]::ReadAllBytes($FilePath)
    $Response.StatusCode = 200
    $Response.ContentType = $ContentType
    $Response.Headers.Add('Access-Control-Allow-Origin', '*')
    $Response.ContentLength64 = $bytes.Length
    $Response.OutputStream.Write($bytes, 0, $bytes.Length)
    $Response.Close()
}

function Read-RequestBody {
    param([System.Net.HttpListenerRequest]$Request)

    $reader = New-Object System.IO.StreamReader($Request.InputStream, $Request.ContentEncoding)
    $body = $reader.ReadToEnd()
    if ([string]::IsNullOrWhiteSpace($body)) { return @{} }
    return $body | ConvertFrom-Json
}

function Get-MimeType {
    param([string]$Path)
    $ext = [System.IO.Path]::GetExtension($Path).ToLower()
    switch ($ext) {
        '.html' { 'text/html; charset=utf-8' }
        '.css'  { 'text/css; charset=utf-8' }
        '.js'   { 'application/javascript; charset=utf-8' }
        '.json' { 'application/json; charset=utf-8' }
        '.png'  { 'image/png' }
        '.svg'  { 'image/svg+xml' }
        '.ico'  { 'image/x-icon' }
        default { 'application/octet-stream' }
    }
}

function Handle-ApiRequest {
    param(
        [string]$Method,
        [string]$Path,
        [System.Net.HttpListenerRequest]$Request,
        [System.Net.HttpListenerResponse]$Response
    )

    try {
        switch -Regex ($Path) {
            '^/api/health$' {
                Send-JsonResponse -Response $Response -Data @{ status = 'ok'; version = '2.0'; platform = 'windows' }
            }

            '^/api/config$' {
                if ($Method -eq 'GET') {
                    Send-JsonResponse -Response $Response -Data (Get-AppGetterConfig)
                }
                elseif ($Method -eq 'PUT') {
                    $body = Read-RequestBody -Request $Request
                    $params = @{}
                    if ($body.downloadLocation) { $params.DownloadLocation = $body.downloadLocation }
                    if ($body.outputPath) { $params.OutputPath = $body.outputPath }
                    if ($body.apiPort) { $params.ApiPort = [int]$body.apiPort }
                    if ($null -ne $body.autoOpenBrowser) { $params.AutoOpenBrowser = [bool]$body.autoOpenBrowser }
                    if ($body.switchTestMode) { $params.SwitchTestMode = $body.switchTestMode }
                    $updated = Set-AppGetterConfig @params
                    Send-JsonResponse -Response $Response -Data $updated
                }
            }

            '^/api/config/validate-download-location$' {
                $body = Read-RequestBody -Request $Request
                $path = if ($body.path) { $body.path } else { (Get-AppGetterConfig).downloadLocation }
                Send-JsonResponse -Response $Response -Data (Test-DownloadLocation -Path $path)
            }

            '^/api/download/links$' {
                $body = Read-RequestBody -Request $Request
                $links = Get-DownloadLinksFromWeb -Url $body.url -AppName $body.appName
                Send-JsonResponse -Response $Response -Data @{ links = $links; count = $links.Count }
            }

            '^/api/download$' {
                $body = Read-RequestBody -Request $Request
                $config = Get-AppGetterConfig
                $downloadDir = if ($body.downloadLocation) { $body.downloadLocation } else { $config.downloadLocation }
                $appName = $body.appName
                $version = if ($body.version) { $body.version } else { 'latest' }
                $packageId = $appName -replace '[^a-zA-Z0-9]', ''
                $destDir = Join-Path (Join-Path $downloadDir $packageId) $version
                if (-not (Test-Path $destDir)) { New-Item -ItemType Directory -Path $destDir -Force | Out-Null }

                $fileName = Split-Path -Leaf $body.url
                if ($fileName -match '([^?]+)') { $fileName = $matches[1] }
                $destPath = Join-Path $destDir $fileName

                $result = Start-WebDownloadWithProgress -Url $body.url -OutputPath $destPath -FileName $fileName
                Send-JsonResponse -Response $Response -Data $result
            }

            '^/api/installer/analyze$' {
                $body = Read-RequestBody -Request $Request
                $installerPath = $body.installerPath
                $known = Get-KnownSilentSwitches -InstallerPath $installerPath
                Send-JsonResponse -Response $Response -Data $known
            }

            '^/api/installer/discover-switches$' {
                $body = Read-RequestBody -Request $Request
                $config = Get-AppGetterConfig
                $testMode = if ($body.testMode) { $body.testMode } else { $config.switchTestMode }
                $discovery = Find-SilentInstallSwitches `
                    -InstallerPath $body.installerPath `
                    -SupportUrl $body.supportUrl `
                    -AppName $body.appName `
                    -TestMode $testMode
                Send-JsonResponse -Response $Response -Data $discovery
            }

            '^/api/installer/test-switch$' {
                $body = Read-RequestBody -Request $Request
                $config = Get-AppGetterConfig
                $testMode = if ($body.mode) { $body.mode } else { $config.switchTestMode }
                $result = Test-SilentInstallSwitch `
                    -InstallerPath $body.installerPath `
                    -Switch $body.switch `
                    -Mode $testMode
                Send-JsonResponse -Response $Response -Data $result
            }

            '^/api/installer/upload$' {
                $body = Read-RequestBody -Request $Request
                $config = Get-AppGetterConfig
                $appName = if ($body.appName) { $body.appName } else { 'UploadedApp' }
                $version = if ($body.version) { $body.version } else { 'latest' }
                $packageId = $appName -replace '[^a-zA-Z0-9]', ''
                $destDir = Join-Path (Join-Path $config.downloadLocation $packageId) $version
                $result = Save-UploadedInstaller -SourcePath $body.sourcePath -DestinationDir $destDir -FileName $body.fileName
                Send-JsonResponse -Response $Response -Data $result
            }

            '^/api/package$' {
                $body = Read-RequestBody -Request $Request
                $result = Invoke-AppGetterPackage `
                    -AppName $body.appName `
                    -InstallerPath $body.installerPath `
                    -InstallCommand $body.installCommand `
                    -Version $body.version `
                    -Publisher $body.publisher `
                    -WebsiteUrl $body.websiteUrl `
                    -DownloadUrl $body.downloadUrl `
                    -SkipIntuneWin:($body.skipIntuneWin -eq $true)
                Send-JsonResponse -Response $Response -Data $result
            }

            default {
                Send-JsonResponse -Response $Response -Data @{ error = 'Not found' } -StatusCode 404
            }
        }
    }
    catch {
        Send-JsonResponse -Response $Response -Data @{
            error   = $_.Exception.Message
            details = $_.ScriptStackTrace
        } -StatusCode 500
    }
}

Write-Host "Starting AppGetter API on $prefix" -ForegroundColor Cyan
Write-Host "UI available at: ${prefix}index.html" -ForegroundColor Green

$listener.Start()

try {
    while ($listener.IsListening) {
        $context = $listener.GetContext()
        $request = $context.Request
        $response = $context.Response
        $path = $request.Url.LocalPath
        $method = $request.HttpMethod

        if ($method -eq 'OPTIONS') {
            $response.StatusCode = 204
            $response.Headers.Add('Access-Control-Allow-Origin', '*')
            $response.Headers.Add('Access-Control-Allow-Methods', 'GET, POST, PUT, OPTIONS')
            $response.Headers.Add('Access-Control-Allow-Headers', 'Content-Type')
            $response.Close()
            continue
        }

        if ($path -like '/api/*') {
            Handle-ApiRequest -Method $method -Path $path -Request $request -Response $response
            continue
        }

        $relativePath = $path.TrimStart('/')
        if ([string]::IsNullOrWhiteSpace($relativePath)) { $relativePath = 'index.html' }

        $filePath = Join-Path $uiRoot ($relativePath -replace '/', [System.IO.Path]::DirectorySeparatorChar)
        if (Test-Path $filePath -PathType Leaf) {
            Send-FileResponse -Response $response -FilePath $filePath -ContentType (Get-MimeType $filePath)
        }
        else {
            $indexPath = Join-Path $uiRoot 'index.html'
            if (Test-Path $indexPath) {
                Send-FileResponse -Response $response -FilePath $indexPath -ContentType 'text/html; charset=utf-8'
            }
            else {
                $response.StatusCode = 404
                $response.Close()
            }
        }
    }
}
finally {
    $listener.Stop()
    Write-Host 'AppGetter API stopped.' -ForegroundColor Yellow
}
