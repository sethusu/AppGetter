$script:KnownSwitchDatabase = @{
    MSI = @(
        @{ Switch = '/quiet'; Confidence = 'Known'; Source = 'MSI Standard'; Description = 'No UI, basic logging' }
        @{ Switch = '/qn'; Confidence = 'Known'; Source = 'MSI Standard'; Description = 'No UI, no UI sequence' }
        @{ Switch = '/qb'; Confidence = 'Known'; Source = 'MSI Standard'; Description = 'Basic UI with progress bar' }
        @{ Switch = '/norestart'; Confidence = 'Known'; Source = 'MSI Standard'; Description = 'Suppress restart' }
    )
    NSIS = @(
        @{ Switch = '/S'; Confidence = 'Known'; Source = 'NSIS Standard'; Description = 'Silent install' }
    )
    InnoSetup = @(
        @{ Switch = '/VERYSILENT'; Confidence = 'Known'; Source = 'Inno Setup'; Description = 'No wizard or progress window' }
        @{ Switch = '/SILENT'; Confidence = 'Known'; Source = 'Inno Setup'; Description = 'Progress window only' }
        @{ Switch = '/SUPPRESSMSGBOXES'; Confidence = 'Known'; Source = 'Inno Setup'; Description = 'Suppress message boxes' }
        @{ Switch = '/NORESTART'; Confidence = 'Known'; Source = 'Inno Setup'; Description = 'Suppress restart' }
        @{ Switch = '/SP-'; Confidence = 'Known'; Source = 'Inno Setup'; Description = 'Disable startup prompt' }
    )
    InstallShield = @(
        @{ Switch = '/s'; Confidence = 'Known'; Source = 'InstallShield'; Description = 'Silent install' }
        @{ Switch = '/v"/qn"'; Confidence = 'Known'; Source = 'InstallShield MSI wrapper'; Description = 'Silent MSI inside setup.exe' }
    )
    WiXBurn = @(
        @{ Switch = '/quiet'; Confidence = 'Known'; Source = 'WiX Burn'; Description = 'Silent install' }
        @{ Switch = '/passive'; Confidence = 'Known'; Source = 'WiX Burn'; Description = 'Unattended with progress' }
    )
    Squirrel = @(
        @{ Switch = '--silent'; Confidence = 'Known'; Source = 'Squirrel'; Description = 'Silent install' }
    )
    EXE_Generic = @(
        @{ Switch = '/S'; Confidence = 'Heuristic'; Source = 'Common EXE'; Description = 'Common silent flag' }
        @{ Switch = '/silent'; Confidence = 'Heuristic'; Source = 'Common EXE'; Description = 'Common silent flag' }
        @{ Switch = '/quiet'; Confidence = 'Heuristic'; Source = 'Common EXE'; Description = 'Common silent flag' }
        @{ Switch = '/qn'; Confidence = 'Heuristic'; Source = 'Common EXE'; Description = 'MSI-style on some EXEs' }
    )
}

$script:FrameworkSignatures = @(
    @{ Name = 'NSIS'; Patterns = @('Nullsoft Install System', 'NSIS Error', 'NullsoftInst') }
    @{ Name = 'InnoSetup'; Patterns = @('Inno Setup Setup Data', 'Inno Setup Messages', 'jrsoftware.org') }
    @{ Name = 'InstallShield'; Patterns = @('InstallShield', 'ISSetup', 'Setup Launcher for InstallShield') }
    @{ Name = 'WiXBurn'; Patterns = @('WiX Toolset', 'burn engine', 'WixBundle') }
    @{ Name = 'Squirrel'; Patterns = @('Squirrel', 'Update.exe') }
    @{ Name = 'MSI'; Patterns = @() }
)

function Get-InstallerFramework {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$InstallerPath
    )

    if (-not (Test-Path $InstallerPath)) {
        throw "Installer not found: $InstallerPath"
    }

    $extension = [System.IO.Path]::GetExtension($InstallerPath).ToLowerInvariant()
    if ($extension -eq '.msi') {
        return [pscustomobject]@{
            Framework   = 'MSI'
            Extension   = $extension
            FileName    = Split-Path -Leaf $InstallerPath
            Confidence  = 'Known'
            DetectionMethod = 'Extension'
        }
    }

    if ($extension -in '.msix', '.appx') {
        return [pscustomobject]@{
            Framework   = 'MSIX'
            Extension   = $extension
            FileName    = Split-Path -Leaf $InstallerPath
            Confidence  = 'Known'
            DetectionMethod = 'Extension'
        }
    }

    $bytes = [System.IO.File]::ReadAllBytes($InstallerPath)
    $text = [System.Text.Encoding]::ASCII.GetString($bytes)

    foreach ($sig in $script:FrameworkSignatures) {
        foreach ($pattern in $sig.Patterns) {
            if ($text -like "*$pattern*") {
                return [pscustomobject]@{
                    Framework       = $sig.Name
                    Extension       = $extension
                    FileName        = Split-Path -Leaf $InstallerPath
                    Confidence      = 'High'
                    DetectionMethod = 'BinarySignature'
                    MatchedPattern  = $pattern
                }
            }
        }
    }

    return [pscustomobject]@{
        Framework       = 'EXE_Generic'
        Extension       = $extension
        FileName        = Split-Path -Leaf $InstallerPath
        Confidence      = 'Low'
        DetectionMethod = 'Fallback'
    }
}

function Get-KnownSilentSwitches {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Framework
    )

    $key = if ($script:KnownSwitchDatabase.ContainsKey($Framework)) {
        $Framework
    }
    else {
        'EXE_Generic'
    }

    return $script:KnownSwitchDatabase[$key]
}

function Get-SilentSwitchesFromWeb {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Url,
        [string]$AppName
    )

    $found = [ordered]@{
        InstallSwitches = @()
        BestPractices   = @()
        SourceUrl       = $Url
    }

    try {
        $response = Invoke-WebRequest -Uri $Url -UseBasicParsing -ErrorAction Stop
        $html = $response.Content
        $text = $html -replace '<[^>]+>', ' ' -replace '\s+', ' '

        $switchPatterns = @(
            '/VERYSILENT', '/SILENT', '/SUPPRESSMSGBOXES', '/NORESTART', '/SP-',
            '/S\b', '/quiet', '/qn', '/qb', '/passive', '--silent',
            'silent install', 'quiet install', 'unattended install', 'msiexec'
        )

        foreach ($pattern in $switchPatterns) {
            $matches = [regex]::Matches($text, ".{0,80}$pattern.{0,80}", [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
            foreach ($match in $matches) {
                $value = $match.Value.Trim()
                if ($found.InstallSwitches -notcontains $value) {
                    $found.InstallSwitches += $value
                }
            }
        }

        if ($text -match '(?i)(deployment|enterprise|administrator|silent|unattended)') {
            $found.BestPractices += 'Page contains deployment or enterprise installation information.'
        }
    }
    catch {
        Write-Warning "Web research failed for $Url : $_"
    }

    return [pscustomobject]$found
}

function Invoke-InstallerHelpProbe {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$InstallerPath,
        [int]$TimeoutSeconds = 15
    )

    $results = @()
    $helpArgs = @('/?', '/help', '--help', '-h', '/h')

    foreach ($arg in $helpArgs) {
        $probe = [ordered]@{
            Argument = $arg
            Success  = $false
            Output   = ''
            Switches = @()
        }

        try {
            $psi = New-Object System.Diagnostics.ProcessStartInfo
            $psi.FileName = $InstallerPath
            $psi.Arguments = $arg
            $psi.UseShellExecute = $false
            $psi.RedirectStandardOutput = $true
            $psi.RedirectStandardError = $true
            $psi.CreateNoWindow = $true

            $process = [System.Diagnostics.Process]::Start($psi)
            if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
                $process.Kill()
                $probe.Output = 'Timed out waiting for help output.'
                $results += [pscustomobject]$probe
                continue
            }

            $stdout = $process.StandardOutput.ReadToEnd()
            $stderr = $process.StandardError.ReadToEnd()
            $output = ($stdout + "`n" + $stderr).Trim()
            $probe.Output = $output
            $probe.Success = $output.Length -gt 0

            $switchMatches = [regex]::Matches($output, '(?i)(/[\w-]+|--[\w-]+|/quiet|/qn|/qb|/passive)')
            foreach ($match in $switchMatches) {
                $sw = $match.Value
                if ($probe.Switches -notcontains $sw) {
                    $probe.Switches += $sw
                }
            }
        }
        catch {
            $probe.Output = $_.Exception.Message
        }

        $results += [pscustomobject]$probe
    }

    return $results
}

function Test-InstallerSilentSwitches {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$InstallerPath,
        [string[]]$CandidateSwitches,
        [switch]$DryRun,
        [int]$TimeoutSeconds = 30
    )

    if (-not (Test-Path $InstallerPath)) {
        throw "Installer not found: $InstallerPath"
    }

    $framework = Get-InstallerFramework -InstallerPath $InstallerPath
    if (-not $CandidateSwitches -or $CandidateSwitches.Count -eq 0) {
        $known = Get-KnownSilentSwitches -Framework $framework.Framework
        $CandidateSwitches = $known | ForEach-Object { $_.Switch }
    }

    $results = @()
    foreach ($switch in ($CandidateSwitches | Select-Object -Unique)) {
        $test = [ordered]@{
            Switch       = $switch
            Status       = 'NotTested'
            ExitCode     = $null
            DurationMs   = $null
            HasUiWindow  = $null
            Message      = ''
            Recommended  = $false
        }

        if ($DryRun) {
            $test.Status = 'DryRun'
            $test.Message = "Would test: `"$($framework.FileName)`" $switch"
            $results += [pscustomobject]$test
            continue
        }

        if ($framework.Extension -eq '.msi') {
            $test.Message = 'MSI installers should be tested with msiexec in a controlled VM.'
            $test.Status = 'Skipped'
            $results += [pscustomobject]$test
            continue
        }

        try {
            $sw = [System.Diagnostics.Stopwatch]::StartNew()
            $psi = New-Object System.Diagnostics.ProcessStartInfo
            $psi.FileName = $InstallerPath
            $psi.Arguments = $switch
            $psi.UseShellExecute = $false
            $psi.CreateNoWindow = $true

            $process = [System.Diagnostics.Process]::Start($psi)
            if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
                $process.Kill()
                $test.Status = 'Timeout'
                $test.Message = 'Installer did not exit within timeout; may be waiting for UI input.'
            }
            else {
                $test.ExitCode = $process.ExitCode
                $test.Status = if ($process.ExitCode -eq 0) { 'Success' } else { 'Failed' }
                $test.Message = "Exit code: $($process.ExitCode)"
                if ($process.ExitCode -eq 0) {
                    $test.Recommended = $true
                }
            }

            $sw.Stop()
            $test.DurationMs = $sw.ElapsedMilliseconds
        }
        catch {
            $test.Status = 'Error'
            $test.Message = $_.Exception.Message
        }

        $results += [pscustomobject]$test
    }

    return $results
}

function New-InstallCommand {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$InstallerFileName,
        [Parameter(Mandatory)]
        [string]$Framework,
        [string[]]$SelectedSwitches
    )

    $extension = [System.IO.Path]::GetExtension($InstallerFileName).ToLowerInvariant()

    if ($extension -eq '.msi') {
        return "msiexec /i `"$InstallerFileName`" /quiet /norestart"
    }

    if ($extension -in '.msix', '.appx') {
        return "Add-AppxPackage -Path `"$InstallerFileName`""
    }

    $switchText = if ($SelectedSwitches -and $SelectedSwitches.Count -gt 0) {
        ($SelectedSwitches | Select-Object -Unique) -join ' '
    }
    else {
        $known = Get-KnownSilentSwitches -Framework $Framework
        ($known | Select-Object -First 1).Switch
    }

    return "`"$InstallerFileName`" $switchText"
}

function Find-InstallerSilentSwitches {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$InstallerPath,
        [string]$SupportUrl,
        [string]$AppName,
        [switch]$ProbeHelp,
        [switch]$TestInstall,
        [switch]$DryRun
    )

    $framework = Get-InstallerFramework -InstallerPath $InstallerPath
    $known = Get-KnownSilentSwitches -Framework $framework.Framework
    $candidates = [System.Collections.Generic.List[object]]::new()

    foreach ($item in $known) {
        $candidates.Add([pscustomobject]@{
            Switch     = $item.Switch
            Confidence = $item.Confidence
            Source     = $item.Source
            Description = $item.Description
        })
    }

    $webInfo = $null
    if ($SupportUrl) {
        $webInfo = Get-SilentSwitchesFromWeb -Url $SupportUrl -AppName $AppName
        foreach ($snippet in $webInfo.InstallSwitches) {
            $switchMatches = [regex]::Matches($snippet, '(?i)(/VERYSILENT|/SILENT|/SUPPRESSMSGBOXES|/NORESTART|/SP-|/S\b|/quiet|/qn|/qb|/passive|--silent)')
            foreach ($match in $switchMatches) {
                $sw = $match.Value
                if (-not ($candidates.Switch -contains $sw)) {
                    $candidates.Add([pscustomobject]@{
                        Switch      = $sw
                        Confidence  = 'Medium'
                        Source      = 'WebDocumentation'
                        Description = $snippet.Substring(0, [Math]::Min(120, $snippet.Length))
                    })
                }
            }
        }
    }

    $helpProbes = @()
    if ($ProbeHelp -and $framework.Extension -eq '.exe') {
        $helpProbes = Invoke-InstallerHelpProbe -InstallerPath $InstallerPath
        foreach ($probe in $helpProbes) {
            foreach ($sw in $probe.Switches) {
                if (-not ($candidates.Switch -contains $sw)) {
                    $candidates.Add([pscustomobject]@{
                        Switch      = $sw
                        Confidence  = 'Medium'
                        Source      = "HelpProbe($($probe.Argument))"
                        Description = 'Found in installer help output'
                    })
                }
            }
        }
    }

    $testResults = @()
    if ($TestInstall) {
        $testResults = Test-InstallerSilentSwitches -InstallerPath $InstallerPath -CandidateSwitches ($candidates.Switch) -DryRun:$DryRun
        foreach ($test in $testResults | Where-Object { $_.Recommended }) {
            $match = $candidates | Where-Object { $_.Switch -eq $test.Switch } | Select-Object -First 1
            if ($match) {
                $match.Confidence = 'Verified'
            }
        }
    }

    $recommended = $candidates |
        Sort-Object @{
            Expression = {
                switch ($_.Confidence) {
                    'Verified' { 0 }
                    'Known' { 1 }
                    'High' { 2 }
                    'Medium' { 3 }
                    default { 4 }
                }
            }
        }, Switch |
        Select-Object -First 1

  $installCommand = New-InstallCommand -InstallerFileName $framework.FileName -Framework $framework.Framework -SelectedSwitches @($recommended.Switch)

    return [pscustomobject]@{
        InstallerPath   = $InstallerPath
        Framework       = $framework
        Candidates      = $candidates
        WebResearch     = $webInfo
        HelpProbes      = $helpProbes
        TestResults     = $testResults
        RecommendedSwitch = $recommended
        InstallCommand  = $installCommand
        Status          = if ($recommended.Confidence -in 'Known', 'Verified', 'High') { 'Known' } else { 'NeedsDiscovery' }
    }
}

Export-ModuleMember -Function *
