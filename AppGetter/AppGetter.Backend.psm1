Set-StrictMode -Version Latest

function Resolve-AppGetterDownloadLocation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$DownloadLocation
    )

    $resolved = [pscustomobject]@{
        SourceType    = "Unknown"
        DownloadUrl   = $null
        InstallerPath = $null
        Notes         = @()
    }

    if ([string]::IsNullOrWhiteSpace($DownloadLocation)) {
        $resolved.Notes += "No download location provided."
        return $resolved
    }

    if ($DownloadLocation -match '^https?://') {
        $resolved.SourceType = "WebUrl"
        $resolved.DownloadUrl = $DownloadLocation
        $resolved.Notes += "Download location resolved as direct web URL."
        return $resolved
    }

    if (-not (Test-Path -LiteralPath $DownloadLocation)) {
        $resolved.Notes += "Download location path does not exist: $DownloadLocation"
        return $resolved
    }

    $item = Get-Item -LiteralPath $DownloadLocation
    if ($item.PSIsContainer) {
        $knownInstallerExtensions = @(".exe", ".msi", ".msix", ".appx")
        $latestInstaller = Get-ChildItem -LiteralPath $DownloadLocation -File -ErrorAction SilentlyContinue |
            Where-Object { $knownInstallerExtensions -contains $_.Extension.ToLowerInvariant() } |
            Sort-Object LastWriteTimeUtc -Descending |
            Select-Object -First 1

        if ($latestInstaller) {
            $resolved.SourceType = "LocalDirectory"
            $resolved.InstallerPath = $latestInstaller.FullName
            $resolved.Notes += "Selected latest installer from directory: $($latestInstaller.Name)"
        } else {
            $resolved.SourceType = "LocalDirectory"
            $resolved.Notes += "Directory contains no supported installer files (.exe, .msi, .msix, .appx)."
        }

        return $resolved
    }

    $supportedExtensions = @(".exe", ".msi", ".msix", ".appx")
    if ($supportedExtensions -contains $item.Extension.ToLowerInvariant()) {
        $resolved.SourceType = "LocalFile"
        $resolved.InstallerPath = $item.FullName
        $resolved.Notes += "Download location resolved as local installer file."
    } else {
        $resolved.SourceType = "LocalFile"
        $resolved.InstallerPath = $item.FullName
        $resolved.Notes += "Resolved local file is not a known installer extension; proceeding anyway."
    }

    return $resolved
}

function Get-AppGetterInstallerProfile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$InstallerExtension
    )

    $extension = $InstallerExtension.ToLowerInvariant()
    switch ($extension) {
        ".msi" {
            return [pscustomobject]@{
                InstallCommandTemplate = 'msiexec /i "{0}" /quiet /norestart'
                CandidateSwitches      = @("/quiet", "/qn", "/norestart")
                Source                 = "MSI standard"
                Confidence             = "high"
            }
        }
        ".msix" {
            return [pscustomobject]@{
                InstallCommandTemplate = 'Add-AppxPackage -Path "{0}"'
                CandidateSwitches      = @()
                Source                 = "MSIX standard"
                Confidence             = "high"
            }
        }
        ".appx" {
            return [pscustomobject]@{
                InstallCommandTemplate = 'Add-AppxPackage -Path "{0}"'
                CandidateSwitches      = @()
                Source                 = "APPX standard"
                Confidence             = "high"
            }
        }
        default {
            return $null
        }
    }
}

function Get-AppGetterInstallerEngineHint {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$InstallerPath
    )

    if (-not (Test-Path -LiteralPath $InstallerPath)) {
        return $null
    }

    try {
        $byteLimit = 5MB
        $stream = [System.IO.File]::OpenRead($InstallerPath)
        try {
            $bytesToRead = [Math]::Min([int64]$byteLimit, $stream.Length)
            $buffer = New-Object byte[] $bytesToRead
            [void]$stream.Read($buffer, 0, $buffer.Length)
        } finally {
            $stream.Dispose()
        }

        $ascii = [System.Text.Encoding]::ASCII.GetString($buffer)
        $utf16 = [System.Text.Encoding]::Unicode.GetString($buffer)
        $blob = "$ascii $utf16"
    } catch {
        return $null
    }

    $engineMap = @(
        @{
            Pattern    = '(?i)inno setup'
            Engine     = 'Inno Setup'
            Command    = '"{0}" /VERYSILENT /SUPPRESSMSGBOXES /NORESTART'
            Switches   = @("/VERYSILENT", "/SUPPRESSMSGBOXES", "/NORESTART")
            Confidence = "medium"
        },
        @{
            Pattern    = '(?i)nullsoft|nsis'
            Engine     = 'NSIS'
            Command    = '"{0}" /S'
            Switches   = @("/S")
            Confidence = "medium"
        },
        @{
            Pattern    = '(?i)installshield'
            Engine     = 'InstallShield'
            Command    = '"{0}" /s /v"/qn /norestart"'
            Switches   = @("/s", "/v")
            Confidence = "low"
        },
        @{
            Pattern    = '(?i)wix toolset|burn bootstrapper'
            Engine     = 'WiX Burn'
            Command    = '"{0}" /quiet /norestart'
            Switches   = @("/quiet", "/norestart")
            Confidence = "medium"
        },
        @{
            Pattern    = '(?i)advanced installer'
            Engine     = 'Advanced Installer'
            Command    = '"{0}" /exenoui /qn'
            Switches   = @("/exenoui", "/qn")
            Confidence = "low"
        },
        @{
            Pattern    = '(?i)squirrel'
            Engine     = 'Squirrel'
            Command    = '"{0}" --silent'
            Switches   = @("--silent")
            Confidence = "low"
        }
    )

    foreach ($entry in $engineMap) {
        if ($blob -match $entry.Pattern) {
            return [pscustomobject]@{
                EngineName      = $entry.Engine
                InstallCommand  = [string]::Format($entry.Command, [System.IO.Path]::GetFileName($InstallerPath))
                CandidateSwitches = $entry.Switches
                Source          = "Installer engine fingerprint"
                Confidence      = $entry.Confidence
            }
        }
    }

    return $null
}

function Get-AppGetterSwitchesFromText {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Text
    )

    $pattern = '(?i)(/VERYSILENT|/SILENT|/quiet|/qn|/qb|/norestart|/S\b|--silent|--quiet|--unattended)'
    $matches = [regex]::Matches($Text, $pattern)
    $switches = @()
    foreach ($match in $matches) {
        $switches += $match.Value
    }

    return $switches | Select-Object -Unique
}

function Get-AppGetterSwitchesFromDocumentation {
    [CmdletBinding()]
    param(
        [string[]]$Urls,
        [string]$AppName
    )

    $findings = [pscustomobject]@{
        Switches = @()
        Notes    = @()
    }

    if (-not $Urls -or $Urls.Count -eq 0) {
        return $findings
    }

    foreach ($url in ($Urls | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique)) {
        try {
            $response = Invoke-WebRequest -Uri $url -UseBasicParsing -ErrorAction Stop
            $content = $response.Content
            $matches = @(Get-AppGetterSwitchesFromText -Text $content)
            if ($matches.Count -gt 0) {
                $findings.Switches += $matches
                $findings.Notes += "Found switch guidance on $url"
            } else {
                $findings.Notes += "No clear silent switches found on $url"
            }
        } catch {
            $findings.Notes += "Could not inspect $url : $($_.Exception.Message)"
        }
    }

    $findings.Switches = @($findings.Switches | Select-Object -Unique)
    return $findings
}

function Get-AppGetterSwitchesFromInstallerHelp {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$InstallerPath,
        [int]$TimeoutSeconds = 20
    )

    $result = [pscustomobject]@{
        Switches = @()
        Notes    = @()
    }

    if (-not (Test-Path -LiteralPath $InstallerPath)) {
        $result.Notes += "Installer path not found for help probing."
        return $result
    }

    if ($InstallerPath.ToLowerInvariant().EndsWith(".msi")) {
        $result.Switches += @("/quiet", "/qn", "/norestart")
        $result.Notes += "MSI installer uses standard switches."
        return $result
    }

    if (-not ($InstallerPath.ToLowerInvariant().EndsWith(".exe"))) {
        $result.Notes += "Help probing is only applied to EXE installers."
        return $result
    }

    $probes = @("/?", "/help", "-?", "--help")
    foreach ($probe in $probes) {
        $tempOutput = [System.IO.Path]::GetTempFileName()
        try {
            $quotedInstaller = '"' + $InstallerPath.Replace('"', '""') + '"'
            $cmdLine = "$quotedInstaller $probe > `"$tempOutput`" 2>&1"
            $process = Start-Process -FilePath "cmd.exe" -ArgumentList "/c $cmdLine" -PassThru -WindowStyle Hidden

            if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
                try {
                    $process.Kill()
                    $result.Notes += "Probe '$probe' timed out after $TimeoutSeconds seconds."
                } catch {
                    $result.Notes += "Probe '$probe' timed out and process kill failed."
                }
                continue
            }

            $output = ""
            if (Test-Path -LiteralPath $tempOutput) {
                $output = Get-Content -LiteralPath $tempOutput -Raw -ErrorAction SilentlyContinue
            }

            if (-not [string]::IsNullOrWhiteSpace($output)) {
                $found = @(Get-AppGetterSwitchesFromText -Text $output)
                if ($found.Count -gt 0) {
                    $result.Switches += $found
                    $result.Notes += "Installer help output for '$probe' exposed switches."
                } else {
                    $result.Notes += "Help output for '$probe' contained no recognizable switches."
                }
            } else {
                $result.Notes += "Probe '$probe' produced no console output."
            }
        } catch {
            $result.Notes += "Probe '$probe' failed: $($_.Exception.Message)"
        } finally {
            if (Test-Path -LiteralPath $tempOutput) {
                Remove-Item -LiteralPath $tempOutput -Force -ErrorAction SilentlyContinue
            }
        }
    }

    $result.Switches = @($result.Switches | Select-Object -Unique)
    return $result
}

function Find-AppGetterSilentInstallCommand {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$InstallerPath,
        [Parameter(Mandatory = $true)]
        [string]$InstallerFileName,
        [string]$AppName,
        [string[]]$DocumentationUrls
    )

    $analysis = [ordered]@{
        InstallCommand    = $null
        Source            = "Unknown"
        Confidence        = "low"
        DetectedSwitches  = @()
        ResearchNotes     = @()
        EngineHint        = $null
        NeedsManualReview = $false
    }

    $extension = [System.IO.Path]::GetExtension($InstallerFileName)
    $profile = Get-AppGetterInstallerProfile -InstallerExtension $extension
    if ($profile) {
        $analysis.InstallCommand = [string]::Format($profile.InstallCommandTemplate, $InstallerFileName)
        $analysis.Source = $profile.Source
        $analysis.Confidence = $profile.Confidence
        $analysis.DetectedSwitches = $profile.CandidateSwitches
        $analysis.ResearchNotes += "Applied built-in installer profile for $extension."
        return [pscustomobject]$analysis
    }

    $docFindings = Get-AppGetterSwitchesFromDocumentation -Urls $DocumentationUrls -AppName $AppName
    if ($docFindings.Switches.Count -gt 0) {
        $primarySwitch = $docFindings.Switches | Select-Object -First 1
        $analysis.InstallCommand = "`"$InstallerFileName`" $primarySwitch"
        $analysis.Source = "Documentation research"
        $analysis.Confidence = "medium"
        $analysis.DetectedSwitches = $docFindings.Switches
        $analysis.ResearchNotes += $docFindings.Notes
    } else {
        $analysis.ResearchNotes += $docFindings.Notes
    }

    $helpFindings = Get-AppGetterSwitchesFromInstallerHelp -InstallerPath $InstallerPath
    if (-not $analysis.InstallCommand -and $helpFindings.Switches.Count -gt 0) {
        $primarySwitch = $helpFindings.Switches | Select-Object -First 1
        $analysis.InstallCommand = "`"$InstallerFileName`" $primarySwitch"
        $analysis.Source = "Installer help probing"
        $analysis.Confidence = "medium"
        $analysis.DetectedSwitches = $helpFindings.Switches
    } elseif ($helpFindings.Switches.Count -gt 0) {
        $analysis.DetectedSwitches = @($analysis.DetectedSwitches + $helpFindings.Switches | Select-Object -Unique)
    }
    $analysis.ResearchNotes += $helpFindings.Notes

    $engineHint = Get-AppGetterInstallerEngineHint -InstallerPath $InstallerPath
    if (-not $analysis.InstallCommand -and $engineHint) {
        $analysis.InstallCommand = $engineHint.InstallCommand
        $analysis.Source = $engineHint.Source
        $analysis.Confidence = $engineHint.Confidence
        $analysis.EngineHint = $engineHint.EngineName
        $analysis.DetectedSwitches = $engineHint.CandidateSwitches
        $analysis.ResearchNotes += "Installer fingerprint indicates engine: $($engineHint.EngineName)"
    } elseif ($engineHint) {
        $analysis.EngineHint = $engineHint.EngineName
        $analysis.ResearchNotes += "Installer fingerprint also indicates engine: $($engineHint.EngineName)"
    }

    if (-not $analysis.InstallCommand) {
        $analysis.InstallCommand = "`"$InstallerFileName`" /S"
        $analysis.Source = "Fallback default"
        $analysis.Confidence = "low"
        $analysis.DetectedSwitches = @("/S")
        $analysis.NeedsManualReview = $true
        $analysis.ResearchNotes += "No explicit switch guidance found. Fallback switch selected; verify in lab."
    }

    return [pscustomobject]$analysis
}

Export-ModuleMember -Function Resolve-AppGetterDownloadLocation, Find-AppGetterSilentInstallCommand
