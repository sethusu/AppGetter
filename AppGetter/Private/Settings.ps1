function Get-AppGetterConfigRoot {
    if ($env:APPDATA) {
        return Join-Path $env:APPDATA 'AppGetter'
    }
    return Join-Path $HOME '.config/AppGetter'
}

function Get-AppGetterDefaultBaseOutputPath {
    # Default base is a folder named after the app (AppGetter), matching Wingetter's layout.
    $homeDir = if ($env:USERPROFILE) {
        $env:USERPROFILE
    } elseif ($env:HOME) {
        $env:HOME
    } else {
        [Environment]::GetFolderPath('UserProfile')
    }
    if (-not $homeDir) {
        $homeDir = [System.IO.Path]::GetTempPath()
    }
    return (Join-Path $homeDir 'Documents\AppGetter')
}

function Get-AppGetterBaseOutputPath {
    param(
        [string]$Path,
        [string]$PackageId
    )

    if (-not $Path) {
        return Get-AppGetterDefaultBaseOutputPath
    }

    if ($PackageId -and ((Split-Path -Path $Path -Leaf) -eq $PackageId)) {
        $parent = Split-Path -Path $Path -Parent
        if ($parent) {
            return $parent
        }
    }

    return $Path
}

function Get-AppGetterAppOutputPath {
    param(
        [string]$BasePath,
        [Parameter(Mandatory = $true)]
        [string]$PackageId
    )

    $base = if ($BasePath) { $BasePath } else { Get-AppGetterDefaultBaseOutputPath }
    # If the caller already passed the app-named folder, keep it.
    if ((Split-Path -Path $base -Leaf) -eq $PackageId) {
        return $base
    }

    return (Join-Path $base $PackageId)
}

function Get-AppGetterSettings {
    $settingsPath = Join-Path (Get-AppGetterConfigRoot) 'settings.json'
    $defaults = @{
        OutputPath        = Get-AppGetterDefaultBaseOutputPath
        LastAppName       = ''
        LastWebsiteUrl    = ''
        LastDownloadUrl   = ''
        LastInstallerPath = ''
        LastLicenseInfo   = ''
    }

    if (Test-Path $settingsPath) {
        try {
            $saved = Get-Content -Path $settingsPath -Raw | ConvertFrom-Json
            # Enumerate a snapshot — assigning into the hashtable while enumerating
            # its live Keys collection throws "collection was modified".
            foreach ($key in @($defaults.Keys)) {
                if ($saved.PSObject.Properties.Name -contains $key -and $saved.$key) {
                    $defaults[$key] = $saved.$key
                }
            }
        } catch {
            Write-Warning 'Could not read settings file. Using defaults.'
        }
    }

    # Migrate the legacy default so existing installs land under Documents\AppGetter\{App}.
    $legacyDefault = Join-Path (Split-Path (Get-AppGetterDefaultBaseOutputPath) -Parent) 'AppGetter Output'
    if ($defaults.OutputPath -eq $legacyDefault) {
        $defaults.OutputPath = Get-AppGetterDefaultBaseOutputPath
    }

    return [PSCustomObject]$defaults
}

function Save-AppGetterSettings {
    param(
        [string]$OutputPath,
        [string]$LastAppName,
        [string]$LastWebsiteUrl,
        [string]$LastDownloadUrl,
        [string]$LastInstallerPath,
        [string]$LastLicenseInfo,
        [string]$PackageId
    )

    $settingsDir = Get-AppGetterConfigRoot
    if (-not (Test-Path $settingsDir)) {
        New-Item -ItemType Directory -Path $settingsDir -Force | Out-Null
    }

    $settingsPath = Join-Path $settingsDir 'settings.json'
    $current = Get-AppGetterSettings

    if ($PSBoundParameters.ContainsKey('OutputPath') -and $OutputPath) {
        # Persist the base folder; per-app paths are derived as {base}\{PackageId}.
        $current.OutputPath = Get-AppGetterBaseOutputPath -Path $OutputPath -PackageId $PackageId
    }
    if ($PSBoundParameters.ContainsKey('LastAppName') -and $LastAppName) {
        $current.LastAppName = $LastAppName
    }
    if ($PSBoundParameters.ContainsKey('LastWebsiteUrl')) {
        $current.LastWebsiteUrl = $LastWebsiteUrl
    }
    if ($PSBoundParameters.ContainsKey('LastDownloadUrl')) {
        $current.LastDownloadUrl = $LastDownloadUrl
    }
    if ($PSBoundParameters.ContainsKey('LastInstallerPath')) {
        $current.LastInstallerPath = $LastInstallerPath
    }
    if ($PSBoundParameters.ContainsKey('LastLicenseInfo')) {
        $current.LastLicenseInfo = $LastLicenseInfo
    }

    $current | ConvertTo-Json | Set-Content -Path $settingsPath -Encoding UTF8
}

function Update-AppGetterSessionPath {
    $machinePath = [System.Environment]::GetEnvironmentVariable('Path', 'Machine')
    $userPath = [System.Environment]::GetEnvironmentVariable('Path', 'User')
    $parts = @($machinePath, $userPath) | Where-Object { $_ }
    if ($parts.Count -gt 0) {
        $separator = [System.IO.Path]::PathSeparator
        $env:Path = ($parts -join $separator)
    }
}

function Resolve-ContentPrepToolPath {
    Update-AppGetterSessionPath

    $commandNames = @('intunewinapputil', 'IntuneWinAppUtil')
    foreach ($name in $commandNames) {
        $cmd = Get-Command $name -ErrorAction SilentlyContinue
        if ($cmd -and $cmd.Source) {
            return [string]$cmd.Source
        }
    }

    $candidates = [System.Collections.Generic.List[string]]::new()
    if ($env:LOCALAPPDATA) {
        $candidates.Add((Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Links\IntuneWinAppUtil.exe'))
        $candidates.Add((Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Links\intunewinapputil.exe'))
    }

    $programFilesX86 = ${env:ProgramFiles(x86)}
    if ($programFilesX86) {
        $candidates.Add((Join-Path $programFilesX86 'Microsoft Win32 Content Prep Tool\IntuneWinAppUtil.exe'))
    }
    if ($env:ProgramFiles) {
        $candidates.Add((Join-Path $env:ProgramFiles 'Microsoft Win32 Content Prep Tool\IntuneWinAppUtil.exe'))
    }

    foreach ($candidate in $candidates) {
        if ($candidate -and (Test-Path -LiteralPath $candidate)) {
            return $candidate
        }
    }

    return $null
}

function Get-AppGetterWingetExecutable {
    $candidates = [System.Collections.Generic.List[string]]::new()

    $cmd = Get-Command winget -ErrorAction SilentlyContinue
    if ($cmd) {
        if ($cmd.Source) { $candidates.Add([string]$cmd.Source) }
        if ($cmd.Path) { $candidates.Add([string]$cmd.Path) }
    }

    if ($env:LOCALAPPDATA) {
        $candidates.Add((Join-Path $env:LOCALAPPDATA 'Microsoft\WindowsApps\winget.exe'))
    }

    try {
        $appx = Get-AppxPackage -Name Microsoft.DesktopAppInstaller -ErrorAction SilentlyContinue |
            Sort-Object -Property Version -Descending |
            Select-Object -First 1
        if ($appx -and $appx.InstallLocation) {
            $candidates.Add((Join-Path $appx.InstallLocation 'winget.exe'))
        }
    } catch {
        Write-Verbose "Get-AppxPackage for DesktopAppInstaller failed: $_"
    }

    foreach ($candidate in $candidates) {
        if ($candidate -and (Test-Path -LiteralPath $candidate)) {
            return $candidate
        }
    }

    # Fall back to PATH resolution; App Execution Aliases may still work interactively.
    return 'winget'
}

function Test-AppGetterPrerequisites {
    $results = [ordered]@{
        WingetInstalled          = $false
        WingetVersion            = ''
        ContentPrepToolInstalled = $false
        ContentPrepToolPath      = ''
        PowerShellVersion        = $PSVersionTable.PSVersion.ToString()
        Issues                   = @()
    }

    try {
        $wingetExe = Get-AppGetterWingetExecutable
        $wingetVersion = & $wingetExe --version 2>&1
        if ($LASTEXITCODE -eq 0) {
            $results.WingetInstalled = $true
            $results.WingetVersion = ($wingetVersion | Out-String).Trim() -replace "`0", ''
        }
    } catch {
        Write-Verbose "Winget check failed: $_"
    }

    $contentPrepPath = Resolve-ContentPrepToolPath
    if ($contentPrepPath) {
        $results.ContentPrepToolInstalled = $true
        $results.ContentPrepToolPath = $contentPrepPath
    } else {
        $results.Issues += 'Microsoft Win32 Content Prep Tool (intunewinapputil) was not found on PATH.'
    }

    return [PSCustomObject]$results
}

function Install-AppGetterContentPrepTool {
    <#
    .SYNOPSIS
        Installs the Microsoft Win32 Content Prep Tool via winget.
    .DESCRIPTION
        Runs `winget install --exact --id Microsoft.Win32ContentPrepTool` non-interactively,
        refreshes the session PATH, and re-checks whether intunewinapputil is available.
    .PARAMETER PackageId
        Winget package ID. Defaults to Microsoft.Win32ContentPrepTool.
    .PARAMETER Force
        Pass --force to winget install.
    .EXAMPLE
        Install-AppGetterContentPrepTool
    #>
    [CmdletBinding()]
    param(
        [string]$PackageId = 'Microsoft.Win32ContentPrepTool',
        [switch]$Force
    )

    $alreadyPresent = Resolve-ContentPrepToolPath
    if ($alreadyPresent -and -not $Force) {
        return [PSCustomObject]@{
            Succeeded           = $true
            AlreadyInstalled    = $true
            ExitCode            = 0
            PackageId           = $PackageId
            ContentPrepToolPath = $alreadyPresent
            Output              = "Content Prep Tool is already available at $alreadyPresent"
            Prerequisites       = Test-AppGetterPrerequisites
        }
    }

    $wingetExe = $null
    try {
        $wingetExe = Get-AppGetterWingetExecutable
        $null = & $wingetExe --version 2>&1
        if ($LASTEXITCODE -ne 0) {
            throw 'Winget returned a non-zero exit code.'
        }
    } catch {
        throw "Winget is required to install the Content Prep Tool. $_"
    }

    $wingetArguments = [System.Collections.Generic.List[string]]::new()
    $wingetArguments.AddRange([string[]]@(
        'install'
        '--exact'
        '--id'
        $PackageId
        '--accept-source-agreements'
        '--accept-package-agreements'
        '--disable-interactivity'
    ))
    if ($Force) {
        $wingetArguments.Add('--force')
    }

    $previousOutputEncoding = [Console]::OutputEncoding
    $previousPreference = $OutputEncoding
    try {
        [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
        $OutputEncoding = [System.Text.Encoding]::UTF8
        $output = & $wingetExe @wingetArguments 2>&1
        $exitCode = $LASTEXITCODE
    } finally {
        [Console]::OutputEncoding = $previousOutputEncoding
        $OutputEncoding = $previousPreference
    }

    $outputText = (($output | Out-String) -replace "`0", '').Trim()
    # 0 = success; -1978335189 / 0x8A15002B = no applicable upgrade / already installed
    $alreadyInstalledExit = -1978335189
    $succeeded = ($exitCode -eq 0 -or $exitCode -eq $alreadyInstalledExit)

    Update-AppGetterSessionPath
    $contentPrepPath = Resolve-ContentPrepToolPath
    if ($contentPrepPath) {
        $succeeded = $true
    }

    $prereqs = Test-AppGetterPrerequisites
    if (-not $succeeded) {
        $message = if ($outputText) { $outputText } else { "winget install failed with exit code $exitCode" }
        throw "Failed to install Content Prep Tool ($PackageId). $message"
    }

    return [PSCustomObject]@{
        Succeeded           = $true
        AlreadyInstalled    = ($exitCode -eq $alreadyInstalledExit -or [bool]$alreadyPresent)
        ExitCode            = $exitCode
        PackageId           = $PackageId
        ContentPrepToolPath = $contentPrepPath
        Output              = $outputText
        Prerequisites       = $prereqs
    }
}
