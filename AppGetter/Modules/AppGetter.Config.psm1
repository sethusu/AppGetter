# AppGetter.Config - Persistent configuration management

$script:ConfigFileName = 'config.json'
$script:DefaultConfig = @{
    downloadLocation = "$env:USERPROFILE\Documents\AppGetter\Downloads"
    outputPath       = "$env:USERPROFILE\Documents\AppGetter\Packages"
    apiPort          = 8765
    autoOpenBrowser  = $true
    switchTestMode   = 'dry-run'
    recentApps       = @()
}

function Get-AppGetterConfigPath {
    $configDir = Join-Path $env:APPDATA 'AppGetter'
    if (-not (Test-Path $configDir)) {
        New-Item -ItemType Directory -Path $configDir -Force | Out-Null
    }
    return Join-Path $configDir $script:ConfigFileName
}

function Get-AppGetterConfig {
    $configPath = Get-AppGetterConfigPath
    if (-not (Test-Path $configPath)) {
        return [PSCustomObject]($script:DefaultConfig.Clone())
    }

    try {
        $config = Get-Content -Path $configPath -Raw | ConvertFrom-Json
        $merged = $script:DefaultConfig.Clone()
        foreach ($key in $config.PSObject.Properties.Name) {
            $merged[$key] = $config.$key
        }
        return [PSCustomObject]$merged
    }
    catch {
        return [PSCustomObject]($script:DefaultConfig.Clone())
    }
}

function Set-AppGetterConfig {
    param(
        [string]$DownloadLocation,
        [string]$OutputPath,
        [int]$ApiPort = 0,
        [bool]$AutoOpenBrowser,
        [string]$SwitchTestMode
    )

    $config = Get-AppGetterConfig
    if ($PSBoundParameters.ContainsKey('DownloadLocation') -and $DownloadLocation) {
        $config.downloadLocation = $DownloadLocation
    }
    if ($PSBoundParameters.ContainsKey('OutputPath') -and $OutputPath) {
        $config.outputPath = $OutputPath
    }
    if ($PSBoundParameters.ContainsKey('ApiPort') -and $ApiPort -gt 0) {
        $config.apiPort = $ApiPort
    }
    if ($PSBoundParameters.ContainsKey('AutoOpenBrowser')) {
        $config.autoOpenBrowser = $AutoOpenBrowser
    }
    if ($PSBoundParameters.ContainsKey('SwitchTestMode') -and $SwitchTestMode) {
        $config.switchTestMode = $SwitchTestMode
    }

    $config | ConvertTo-Json -Depth 5 | Set-Content -Path (Get-AppGetterConfigPath) -Encoding UTF8
    return $config
}

function Test-DownloadLocation {
    param([string]$Path)

    $result = @{
        path      = $Path
        valid     = $false
        writable  = $false
        exists    = $false
        freeSpaceGB = 0
        message   = ''
    }

    if ([string]::IsNullOrWhiteSpace($Path)) {
        $result.message = 'Path is empty'
        return [PSCustomObject]$result
    }

    $result.exists = Test-Path $Path
    if (-not $result.exists) {
        try {
            New-Item -ItemType Directory -Path $Path -Force | Out-Null
            $result.exists = $true
        }
        catch {
            $result.message = "Cannot create directory: $_"
            return [PSCustomObject]$result
        }
    }

    try {
        $testFile = Join-Path $Path ".appgetter-write-test"
        'test' | Set-Content -Path $testFile -Force
        Remove-Item -Path $testFile -Force
        $result.writable = $true
    }
    catch {
        $result.message = "Directory is not writable: $_"
        return [PSCustomObject]$result
    }

  try {
        $drive = (Get-Item $Path).PSDrive.Name
        $disk = Get-PSDrive -Name $drive -ErrorAction SilentlyContinue
        if ($disk) {
            $result.freeSpaceGB = [math]::Round($disk.Free / 1GB, 2)
        }
    }
    catch { }

    $result.valid = $true
    $result.message = 'Download location is valid and writable'
    return [PSCustomObject]$result
}

function Get-AppGetterPackagePath {
    param(
        [string]$AppName,
        [string]$Version = 'latest'
    )

    $config = Get-AppGetterConfig
    $packageId = $AppName -replace '[^a-zA-Z0-9]', ''
    return Join-Path (Join-Path $config.outputPath $packageId) $Version
}

function Add-RecentApp {
    param(
        [string]$AppName,
        [string]$InstallerPath,
        [string]$InstallCommand
    )

    $config = Get-AppGetterConfig
    $recent = @($config.recentApps)
    $entry = @{
        appName        = $AppName
        installerPath  = $InstallerPath
        installCommand = $InstallCommand
        timestamp      = (Get-Date -Format 'o')
    }
    $recent = ,$entry + ($recent | Where-Object { $_.appName -ne $AppName } | Select-Object -First 9)
    Set-AppGetterConfig -DownloadLocation $config.downloadLocation -OutputPath $config.outputPath
    $configPath = Get-AppGetterConfigPath
    $saved = Get-Content $configPath -Raw | ConvertFrom-Json
    $saved | Add-Member -NotePropertyName recentApps -NotePropertyValue $recent -Force
    $saved | ConvertTo-Json -Depth 5 | Set-Content -Path $configPath -Encoding UTF8
}

Export-ModuleMember -Function @(
    'Get-AppGetterConfigPath',
    'Get-AppGetterConfig',
    'Set-AppGetterConfig',
    'Test-DownloadLocation',
    'Get-AppGetterPackagePath',
    'Add-RecentApp'
)
