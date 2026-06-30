function Get-AppGetterConfigPath {
    [CmdletBinding()]
    param()

    $configDir = Join-Path $env:LOCALAPPDATA 'AppGetter'
    if (-not (Test-Path $configDir)) {
        New-Item -ItemType Directory -Path $configDir -Force | Out-Null
    }

    return Join-Path $configDir 'config.json'
}

function Get-AppGetterConfig {
    [CmdletBinding()]
    param()

    $configPath = Get-AppGetterConfigPath
    $defaultConfig = [ordered]@{
        downloadPath        = Join-Path $env:USERPROFILE 'Downloads\AppGetter'
        outputPath          = 'D:\Intoon In Progress'
        contentPrepToolPath = ''
        apiBaseUrl          = 'http://localhost:5050'
        recentDownloadUrls  = @()
        recentPackages      = @()
        lastUpdated         = (Get-Date).ToString('o')
    }

    if (-not (Test-Path $configPath)) {
        $defaultConfig | ConvertTo-Json -Depth 5 | Set-Content -Path $configPath -Encoding UTF8
        return [pscustomobject]$defaultConfig
    }

    try {
        $config = Get-Content -Path $configPath -Raw -Encoding UTF8 | ConvertFrom-Json
        foreach ($key in $defaultConfig.Keys) {
            if (-not ($config.PSObject.Properties.Name -contains $key)) {
                $config | Add-Member -NotePropertyName $key -NotePropertyValue $defaultConfig[$key] -Force
            }
        }
        return $config
    }
    catch {
        Write-Warning "Failed to read config, using defaults: $_"
        return [pscustomobject]$defaultConfig
    }
}

function Set-AppGetterConfig {
    [CmdletBinding()]
    param(
        [string]$DownloadPath,
        [string]$OutputPath,
        [string]$ContentPrepToolPath,
        [string]$ApiBaseUrl,
        [string[]]$RecentDownloadUrls,
        [hashtable[]]$RecentPackages
    )

    $config = Get-AppGetterConfig
    if ($DownloadPath) { $config.downloadPath = $DownloadPath }
    if ($OutputPath) { $config.outputPath = $OutputPath }
    if ($ContentPrepToolPath) { $config.contentPrepToolPath = $ContentPrepToolPath }
    if ($ApiBaseUrl) { $config.apiBaseUrl = $ApiBaseUrl }
    if ($RecentDownloadUrls) { $config.recentDownloadUrls = $RecentDownloadUrls }
    if ($RecentPackages) { $config.recentPackages = $RecentPackages }

    $config.lastUpdated = (Get-Date).ToString('o')
    $configPath = Get-AppGetterConfigPath
    $config | ConvertTo-Json -Depth 5 | Set-Content -Path $configPath -Encoding UTF8
    return $config
}

function Reset-AppGetterConfig {
    [CmdletBinding()]
    param()

    $configPath = Get-AppGetterConfigPath
    if (Test-Path $configPath) {
        Remove-Item -Path $configPath -Force
    }

    return Get-AppGetterConfig
}

function Test-AppGetterPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path,
        [switch]$CreateIfMissing
    )

    $result = [ordered]@{
        Path       = $Path
        Exists     = $false
        Writable   = $false
        FreeSpaceGB = $null
        Message    = ''
    }

    if ([string]::IsNullOrWhiteSpace($Path)) {
        $result.Message = 'Path is empty.'
        return [pscustomobject]$result
    }

    if (-not (Test-Path $Path)) {
        if ($CreateIfMissing) {
            try {
                New-Item -ItemType Directory -Path $Path -Force | Out-Null
            }
            catch {
                $result.Message = "Could not create path: $_"
                return [pscustomobject]$result
            }
        }
        else {
            $result.Message = 'Path does not exist.'
            return [pscustomobject]$result
        }
    }

    $result.Exists = $true

    try {
        $testFile = Join-Path $Path ".appgetter-write-test"
        'test' | Set-Content -Path $testFile -Encoding UTF8 -ErrorAction Stop
        Remove-Item -Path $testFile -Force -ErrorAction Stop
        $result.Writable = $true
    }
    catch {
        $result.Message = "Path is not writable: $_"
        return [pscustomobject]$result
    }

    try {
        $drive = (Resolve-Path $Path).Drive.Name
        $freeBytes = (Get-PSDrive -Name $drive).Free
        if ($null -ne $freeBytes) {
            $result.FreeSpaceGB = [math]::Round($freeBytes / 1GB, 2)
        }
    }
    catch {
        # Non-fatal
    }

    $result.Message = 'Path is valid and writable.'
    return [pscustomobject]$result
}
