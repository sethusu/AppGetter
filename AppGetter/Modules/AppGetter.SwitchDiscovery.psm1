# AppGetter.SwitchDiscovery - Silent install switch research and testing

$script:KnownSwitchesPath = Join-Path (Split-Path $PSScriptRoot -Parent) 'Data\known-installer-switches.json'

function Get-KnownInstallerDatabase {
    if (-not (Test-Path $script:KnownSwitchesPath)) {
        throw "Known installer database not found: $script:KnownSwitchesPath"
    }
    return Get-Content -Path $script:KnownSwitchesPath -Raw | ConvertFrom-Json
}

function Get-InstallerType {
    param([string]$InstallerPath)

    if (-not (Test-Path $InstallerPath)) {
        throw "Installer not found: $InstallerPath"
    }

    $extension = [System.IO.Path]::GetExtension($InstallerPath).ToLower()
    $db = Get-KnownInstallerDatabase
    $fileName = Split-Path -Leaf $InstallerPath

    $result = @{
        path        = $InstallerPath
        fileName    = $fileName
        extension   = $extension
        framework   = 'unknown'
        displayName = 'Unknown Installer'
        confidence  = 'low'
        signatures  = @()
    }

    if ($extension -eq '.msi') {
        $result.framework = 'msi'
        $result.displayName = $db.frameworks.msi.displayName
        $result.confidence = 'high'
        return [PSCustomObject]$result
    }

    if ($extension -in @('.msix', '.appx', '.appxbundle', '.msixbundle')) {
        $result.framework = 'msix'
        $result.displayName = $db.frameworks.msix.displayName
        $result.confidence = 'high'
        return [PSCustomObject]$result
    }

    if ($extension -eq '.exe') {
        try {
            $bytes = [System.IO.File]::ReadAllBytes($InstallerPath)
            $text = [System.Text.Encoding]::ASCII.GetString($bytes)

            foreach ($fwKey in @('nsis', 'inno', 'installshield', 'wise', 'squirrel', 'burn')) {
                $fw = $db.frameworks.$fwKey
                foreach ($sig in $fw.signatures) {
                    if ($text -match [regex]::Escape($sig)) {
                        $result.framework = $fwKey
                        $result.displayName = $fw.displayName
                        $result.confidence = 'high'
                        $result.signatures += $sig
                    }
                }
            }

            $switchPatterns = @('/S', '/SILENT', '/VERYSILENT', '/quiet', '/qn', '/passive', '--silent')
            foreach ($pattern in $switchPatterns) {
                if ($text -match [regex]::Escape($pattern)) {
                    $result.signatures += "embedded:$pattern"
                }
            }
        }
        catch { }

        if ($result.framework -eq 'unknown') {
            $result.framework = 'generic_exe'
            $result.displayName = $db.frameworks.generic_exe.displayName
            $result.confidence = 'low'
        }
    }

    return [PSCustomObject]$result
}

function Get-KnownSilentSwitches {
    param([string]$InstallerPath)

    $installerType = Get-InstallerType -InstallerPath $InstallerPath
    $db = Get-KnownInstallerDatabase
    $fw = $db.frameworks.($installerType.framework)

    if (-not $fw) {
        $fw = $db.frameworks.generic_exe
    }

    $switches = @()
    foreach ($sw in $fw.silentSwitches) {
        $switches += [PSCustomObject]@{
            switch      = $sw.switch
            confidence  = $sw.confidence
            description = $sw.description
            source      = 'known-database'
            framework   = $installerType.framework
        }
    }

    return [PSCustomObject]@{
        installerType = $installerType
        switches      = $switches
        installCommandTemplate = ($fw.installCommandTemplate -replace '\{file\}', $installerType.fileName)
        helpSwitches  = @($fw.helpSwitches)
        status        = if ($installerType.confidence -eq 'high') { 'known' } else { 'needs-discovery' }
    }
}

function Search-InstallSwitchesFromWeb {
    param(
        [string]$Url,
        [string]$AppName = ''
    )

    $found = @{
        switches      = @()
        contexts      = @()
        bestPractices = @()
        source        = $Url
    }

    if ([string]::IsNullOrWhiteSpace($Url)) { return $found }

    try {
        $response = Invoke-WebRequest -Uri $Url -UseBasicParsing -ErrorAction Stop
        $html = $response.Content
        $text = $html -replace '<[^>]+>', ' ' -replace '\s+', ' '

        $switchRegex = '(?i)(/S\b|/SILENT\b|/VERYSILENT\b|/quiet\b|/qn\b|/qb\b|/passive\b|/s\b|--silent\b|SUPPRESSMSGBOXES|NORESTART|INSTALLDIR=|REBOOT=)'
        $matches = [regex]::Matches($text, $switchRegex)
        $seen = @{}

        foreach ($match in $matches) {
            $sw = $match.Value.Trim()
            if ($seen.ContainsKey($sw)) { continue }
            $seen[$sw] = $true

            $start = [math]::Max(0, $match.Index - 80)
            $len = [math]::Min(200, $text.Length - $start)
            $context = $text.Substring($start, $len).Trim()

            $found.switches += [PSCustomObject]@{
                switch     = $sw
                confidence = 'medium'
                source     = 'web-research'
                context    = $context
            }
            $found.contexts += $context
        }

        if ($text -match '(?i)(deployment|enterprise|administrator|silent|unattended|command.?line)') {
            $found.bestPractices += 'Page contains deployment/enterprise installation information'
        }
    }
    catch {
        $found.bestPractices += "Web research failed: $_"
    }

    return $found
}

function Invoke-InstallerHelpProbe {
    param(
        [string]$InstallerPath,
        [string[]]$HelpSwitches = @('/?', '/help', '-h', '--help')
    )

    $results = @()
    $installerDir = Split-Path -Parent $InstallerPath
    $fileName = Split-Path -Leaf $InstallerPath

    foreach ($helpSwitch in $HelpSwitches) {
        $probe = @{
            helpSwitch = $helpSwitch
            success    = $false
            exitCode   = -1
            output     = ''
            switches   = @()
        }

        try {
            $psi = New-Object System.Diagnostics.ProcessStartInfo
            $psi.FileName = $InstallerPath
            $psi.Arguments = $helpSwitch
            $psi.WorkingDirectory = $installerDir
            $psi.UseShellExecute = $false
            $psi.RedirectStandardOutput = $true
            $psi.RedirectStandardError = $true
            $psi.CreateNoWindow = $true

            $process = [System.Diagnostics.Process]::Start($psi)
            $stdout = $process.StandardOutput.ReadToEnd()
            $stderr = $process.StandardError.ReadToEnd()
            $process.WaitForExit(15000)

            $output = "$stdout`n$stderr"
            $probe.output = $output.Substring(0, [math]::Min(4000, $output.Length))
            $probe.exitCode = $process.ExitCode
            $probe.success = $output.Length -gt 10

            $switchMatches = [regex]::Matches($output, '(?i)(/S\b|/SILENT\b|/VERYSILENT\b|/quiet\b|/qn\b|/passive\b|/s\b|--silent\b|SUPPRESSMSGBOXES)')
            foreach ($m in $switchMatches) {
                if ($probe.switches -notcontains $m.Value) {
                    $probe.switches += $m.Value
                }
            }
        }
        catch {
            $probe.output = "Probe failed: $_"
        }

        $results += [PSCustomObject]$probe
    }

    return $results
}

function Test-SilentInstallSwitch {
    param(
        [string]$InstallerPath,
        [string]$Switch,
        [ValidateSet('dry-run', 'execute')]
        [string]$Mode = 'dry-run',
        [int]$TimeoutSeconds = 120
    )

    $fileName = Split-Path -Leaf $InstallerPath
    $installerDir = Split-Path -Parent $InstallerPath

    $result = @{
        switch         = $Switch
        mode           = $Mode
        success        = $false
        exitCode       = -1
        durationMs     = 0
        showedUI       = $null
        message        = ''
        installCommand = "`"$fileName`" $Switch"
    }

    if ($Mode -eq 'dry-run') {
        $result.success = $true
        $result.message = 'Dry-run: switch recorded without executing installer'
        return [PSCustomObject]$result
    }

    $sw = [Diagnostics.Stopwatch]::StartNew()
    try {
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = $InstallerPath
        $psi.Arguments = $Switch
        $psi.WorkingDirectory = $installerDir
        $psi.UseShellExecute = $false
        $psi.CreateNoWindow = $true

        $process = [System.Diagnostics.Process]::Start($psi)
        $completed = $process.WaitForExit($TimeoutSeconds * 1000)

        $result.exitCode = if ($completed) { $process.ExitCode } else { -2 }
        $result.durationMs = $sw.ElapsedMilliseconds
        $result.success = $completed -and $result.exitCode -in @(0, 3010, 1641, 1707)
        $result.message = if (-not $completed) { 'Timed out' } elseif ($result.success) { 'Install completed successfully' } else { "Exit code: $($result.exitCode)" }
    }
    catch {
        $result.message = "Test failed: $_"
    }

    return [PSCustomObject]$result
}

function Find-SilentInstallSwitches {
    param(
        [Parameter(Mandatory)]
        [string]$InstallerPath,
        [string]$SupportUrl = '',
        [string]$AppName = '',
        [ValidateSet('dry-run', 'execute')]
        [string]$TestMode = 'dry-run'
    )

    if (-not (Test-Path $InstallerPath)) {
        throw "Installer not found: $InstallerPath"
    }

    $known = Get-KnownSilentSwitches -InstallerPath $InstallerPath
    $allSwitches = @{}
    $tests = @()

    foreach ($sw in $known.switches) {
        $key = $sw.switch.ToLower()
        if (-not $allSwitches.ContainsKey($key)) {
            $allSwitches[$key] = $sw
        }
    }

    if ($SupportUrl) {
        $web = Search-InstallSwitchesFromWeb -Url $SupportUrl -AppName $AppName
        foreach ($sw in $web.switches) {
            $key = $sw.switch.ToLower()
            if (-not $allSwitches.ContainsKey($key)) {
                $allSwitches[$key] = $sw
            }
        }
    }

    if ($known.helpSwitches.Count -gt 0) {
        $probes = Invoke-InstallerHelpProbe -InstallerPath $InstallerPath -HelpSwitches $known.helpSwitches
        foreach ($probe in $probes) {
            foreach ($sw in $probe.switches) {
                $key = $sw.ToLower()
                if (-not $allSwitches.ContainsKey($key)) {
                    $allSwitches[$key] = [PSCustomObject]@{
                        switch     = $sw
                        confidence = 'medium'
                        source     = 'help-probe'
                        description = "Found in help output ($($probe.helpSwitch))"
                    }
                }
            }
        }
    }

    $ranked = $allSwitches.Values | Sort-Object @{
        Expression = {
            switch ($_.confidence) {
                'high' { 0 }
                'medium' { 1 }
                default { 2 }
            }
        }
    }, @{ Expression = { $_.switch } }

    $topSwitch = if ($ranked.Count -gt 0) { $ranked[0].switch } else { '/S' }
    $fileName = Split-Path -Leaf $InstallerPath

    if ($known.installerType.extension -eq '.msi') {
        $recommendedCommand = "msiexec /i `"$fileName`" /quiet /norestart"
    }
    elseif ($known.installerType.extension -in @('.msix', '.appx')) {
        $recommendedCommand = "Add-AppxPackage -Path `"$fileName`""
    }
    else {
        $recommendedCommand = "`"$fileName`" $topSwitch"
    }

    foreach ($sw in ($ranked | Select-Object -First 5)) {
        $tests += Test-SilentInstallSwitch -InstallerPath $InstallerPath -Switch $sw.switch -Mode $TestMode
    }

    $status = if ($known.status -eq 'known' -and $ranked.Count -gt 0) { 'known' }
              elseif ($ranked.Count -gt 0) { 'discovered' }
              else { 'unknown' }

    return [PSCustomObject]@{
        installerPath       = $InstallerPath
        installerType         = $known.installerType
        status                = $status
        switches              = @($ranked)
        recommendedCommand    = $recommendedCommand
        tests                 = @($tests)
        switchCount           = $ranked.Count
        needsManualDiscovery  = ($status -eq 'unknown')
    }
}

Export-ModuleMember -Function @(
    'Get-KnownInstallerDatabase',
    'Get-InstallerType',
    'Get-KnownSilentSwitches',
    'Search-InstallSwitchesFromWeb',
    'Invoke-InstallerHelpProbe',
    'Test-SilentInstallSwitch',
    'Find-SilentInstallSwitches'
)
