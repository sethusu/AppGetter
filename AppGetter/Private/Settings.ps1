function Get-AppGetterConfigRoot {
    if ($env:APPDATA) {
        return Join-Path $env:APPDATA 'AppGetter'
    }
    $homeDir = if ($env:HOME) { $env:HOME } else { [System.IO.Path]::GetTempPath() }
    return [System.IO.Path]::Combine($homeDir, '.config', 'AppGetter')
}

function Get-AppGetterDefaultBaseOutputPath {
    # Default base is a folder named after the app (AppGetter), not a generic "Output" suffix.
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
    return [System.IO.Path]::Combine($homeDir, 'Documents', 'AppGetter')
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
        LastPackageId     = ''
        LastPublisher     = ''
        LastSourceMode    = 'DownloadUrl'
        LastDownloadUrl   = ''
        LastWebsiteUrl    = ''
        LastInstallerPath = ''
    }

    if (Test-Path $settingsPath) {
        try {
            $saved = Get-Content -Path $settingsPath -Raw | ConvertFrom-Json
            foreach ($key in @($defaults.Keys)) {
                if ($saved.PSObject.Properties.Name -contains $key -and $saved.$key) {
                    $defaults[$key] = $saved.$key
                }
            }
        } catch {
            Write-Warning 'Could not read settings file. Using defaults.'
        }
    }

    # Migrate the pre-3.0 default so existing installs land under Documents\AppGetter\{App}.
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
        [string]$LastPackageId,
        [string]$LastPublisher,
        [ValidateSet('DownloadUrl', 'LocalFile', 'Website')]
        [string]$LastSourceMode,
        [string]$LastDownloadUrl,
        [string]$LastWebsiteUrl,
        [string]$LastInstallerPath
    )

    $settingsDir = Get-AppGetterConfigRoot
    if (-not (Test-Path $settingsDir)) {
        New-Item -ItemType Directory -Path $settingsDir -Force | Out-Null
    }

    $settingsPath = Join-Path $settingsDir 'settings.json'
    $current = Get-AppGetterSettings

    if ($PSBoundParameters.ContainsKey('OutputPath') -and $OutputPath) {
        # Persist the base folder; per-app paths are derived as {base}\{PackageId}.
        $current.OutputPath = Get-AppGetterBaseOutputPath -Path $OutputPath -PackageId $LastPackageId
    }
    if ($PSBoundParameters.ContainsKey('LastAppName') -and $LastAppName) {
        $current.LastAppName = $LastAppName
    }
    if ($PSBoundParameters.ContainsKey('LastPackageId') -and $LastPackageId) {
        $current.LastPackageId = $LastPackageId
    }
    if ($PSBoundParameters.ContainsKey('LastPublisher') -and $LastPublisher) {
        $current.LastPublisher = $LastPublisher
    }
    if ($PSBoundParameters.ContainsKey('LastSourceMode') -and $LastSourceMode) {
        $current.LastSourceMode = $LastSourceMode
    }
    if ($PSBoundParameters.ContainsKey('LastDownloadUrl') -and $LastDownloadUrl) {
        $current.LastDownloadUrl = $LastDownloadUrl
    }
    if ($PSBoundParameters.ContainsKey('LastWebsiteUrl') -and $LastWebsiteUrl) {
        $current.LastWebsiteUrl = $LastWebsiteUrl
    }
    if ($PSBoundParameters.ContainsKey('LastInstallerPath') -and $LastInstallerPath) {
        $current.LastInstallerPath = $LastInstallerPath
    }

    $current | ConvertTo-Json | Set-Content -Path $settingsPath -Encoding UTF8
}

function Update-AppGetterSessionPath {
    if (-not $IsWindows -and $PSVersionTable.PSEdition -eq 'Core') {
        return
    }

    $machinePath = [System.Environment]::GetEnvironmentVariable('Path', 'Machine')
    $userPath = [System.Environment]::GetEnvironmentVariable('Path', 'User')
    $parts = @($machinePath, $userPath) | Where-Object { $_ }
    if ($parts.Count -gt 0) {
        $env:Path = ($parts -join ';')
    }
}

function Resolve-AppGetterContentPrepToolPath {
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
    if ($script:AppGetterWingetExePath -and (Test-Path -LiteralPath $script:AppGetterWingetExePath)) {
        return $script:AppGetterWingetExePath
    }

    $candidates = [System.Collections.Generic.List[string]]::new()

    $cmd = Get-Command winget -ErrorAction SilentlyContinue
    if ($cmd) {
        if ($cmd.Source) { $candidates.Add([string]$cmd.Source) }
        if ($cmd.Path) { $candidates.Add([string]$cmd.Path) }
    }

    if ($env:LOCALAPPDATA) {
        $candidates.Add((Join-Path $env:LOCALAPPDATA 'Microsoft\WindowsApps\winget.exe'))
    }

    foreach ($candidate in $candidates) {
        if ($candidate -and (Test-Path -LiteralPath $candidate)) {
            $script:AppGetterWingetExePath = $candidate
            return $script:AppGetterWingetExePath
        }
    }

    # Fall back to PATH resolution; App Execution Aliases may still work interactively.
    $script:AppGetterWingetExePath = 'winget'
    return $script:AppGetterWingetExePath
}

function Test-AppGetterPrerequisites {
    $results = [ordered]@{
        ContentPrepToolInstalled = $false
        ContentPrepToolPath      = ''
        WingetInstalled          = $false
        WingetVersion            = ''
        PowerShellVersion        = $PSVersionTable.PSVersion.ToString()
        Issues                   = @()
    }

    $contentPrepPath = Resolve-AppGetterContentPrepToolPath
    if ($contentPrepPath) {
        $results.ContentPrepToolInstalled = $true
        $results.ContentPrepToolPath = $contentPrepPath
    } else {
        $results.Issues += 'Microsoft Win32 Content Prep Tool (intunewinapputil) was not found on PATH.'
    }

    # Winget is not required to package an app; it is only used to install the Content Prep Tool.
    try {
        $wingetExe = Get-AppGetterWingetExecutable
        $wingetVersion = & $wingetExe --version 2>&1
        if ($LASTEXITCODE -eq 0) {
            $results.WingetInstalled = $true
            $results.WingetVersion = ($wingetVersion | Out-String).Trim() -replace "`0", ''
        }
    } catch {
        Write-Verbose "Winget version check failed: $_"
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

    $alreadyPresent = Resolve-AppGetterContentPrepToolPath
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
    $contentPrepPath = Resolve-AppGetterContentPrepToolPath
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
