function Get-AppGetterConfigDirectory {
    if ($env:APPDATA) {
        return Join-Path $env:APPDATA 'AppGetter'
    }

    $xdgConfig = if ($env:XDG_CONFIG_HOME) { $env:XDG_CONFIG_HOME } else { Join-Path $HOME '.config' }
    return Join-Path $xdgConfig 'AppGetter'
}

function Get-AppGetterDefaultOutputPath {
    if ($env:USERPROFILE) {
        return Join-Path $env:USERPROFILE 'Documents\AppGetter Output'
    }

    return Join-Path $HOME 'AppGetter Output'
}

function Get-AppGetterSettings {
    $settingsPath = Join-Path (Get-AppGetterConfigDirectory) 'settings.json'
    $defaults = @{
        OutputPath      = Get-AppGetterDefaultOutputPath
        LastWebsiteUrl  = ''
        LastAppName     = ''
        LastDownloadUrl = ''
    }

    if (Test-Path $settingsPath) {
        try {
            $saved = Get-Content -Path $settingsPath -Raw | ConvertFrom-Json
            foreach ($key in $defaults.Keys) {
                if ($saved.PSObject.Properties.Name -contains $key -and $saved.$key) {
                    $defaults[$key] = $saved.$key
                }
            }
        } catch {
            Write-Warning 'Could not read settings file. Using defaults.'
        }
    }

    return [PSCustomObject]$defaults
}

function Save-AppGetterSettings {
    param(
        [string]$OutputPath,
        [string]$LastWebsiteUrl,
        [string]$LastAppName,
        [string]$LastDownloadUrl
    )

    $settingsDir = Get-AppGetterConfigDirectory
    if (-not (Test-Path $settingsDir)) {
        New-Item -ItemType Directory -Path $settingsDir -Force | Out-Null
    }

    $settingsPath = Join-Path $settingsDir 'settings.json'
    $current = Get-AppGetterSettings

    if ($PSBoundParameters.ContainsKey('OutputPath') -and $OutputPath) {
        $current.OutputPath = $OutputPath
    }
    if ($PSBoundParameters.ContainsKey('LastWebsiteUrl') -and $LastWebsiteUrl) {
        $current.LastWebsiteUrl = $LastWebsiteUrl
    }
    if ($PSBoundParameters.ContainsKey('LastAppName') -and $LastAppName) {
        $current.LastAppName = $LastAppName
    }
    if ($PSBoundParameters.ContainsKey('LastDownloadUrl') -and $LastDownloadUrl) {
        $current.LastDownloadUrl = $LastDownloadUrl
    }

    $current | ConvertTo-Json | Set-Content -Path $settingsPath -Encoding UTF8
}

function Test-AppGetterPrerequisites {
    $results = [ordered]@{
        ContentPrepToolInstalled = $false
        ContentPrepToolPath      = ''
        PowerShellVersion        = $PSVersionTable.PSVersion.ToString()
        Issues                   = @()
    }

    $intunewinCmd = Get-Command intunewinapputil -ErrorAction SilentlyContinue
    if ($intunewinCmd) {
        $results.ContentPrepToolInstalled = $true
        $results.ContentPrepToolPath = $intunewinCmd.Source
    } else {
        $results.Issues += 'Microsoft Win32 Content Prep Tool (intunewinapputil) was not found on PATH.'
    }

    return [PSCustomObject]$results
}
