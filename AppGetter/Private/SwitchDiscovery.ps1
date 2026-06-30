$script:KnownSwitchesByExtension = @{
    '.msi'  = @('/quiet', '/qn', '/norestart')
    '.msix' = @('Add-AppxPackage -Path <installer>')
    '.appx' = @('Add-AppxPackage -Path <installer>')
}

$script:ExeFamilySignatures = @{
    'inno setup'              = @{ Tokens = @('/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART'); Reason = 'Detected Inno Setup bootstrap markers in the installer binary.' }
    'nullsoft install system' = @{ Tokens = @('/S'); Reason = 'Detected NSIS bootstrap markers in the installer binary.' }
    'installshield'           = @{ Tokens = @('/s', '/v"/qn"'); Reason = 'Detected InstallShield bootstrap markers in the installer binary.' }
    'wix toolset'             = @{ Tokens = @('/quiet', '/passive', '/norestart'); Reason = 'Detected WiX bootstrap markers in the installer binary.' }
}

function Remove-DuplicateStrings {
    param([string[]]$Values)

    $seen = @{}
    $deduped = [System.Collections.Generic.List[string]]::new()
    foreach ($value in $Values) {
        $normalized = $value.Trim()
        if (-not $normalized) { continue }
        $key = $normalized.ToLowerInvariant()
        if (-not $seen.ContainsKey($key)) {
            $deduped.Add($normalized)
            $seen[$key] = $true
        }
    }
    return $deduped.ToArray()
}

function Get-BinaryStrings {
    param(
        [string]$InstallerPath,
        [int]$MaxBytes = 8MB
    )

    $bytes = [System.IO.File]::ReadAllBytes($InstallerPath)
    if ($bytes.Length -gt $MaxBytes) {
        $bytes = $bytes[0..($MaxBytes - 1)]
    }

    $asciiPattern = [regex]'[ -~]{4,}'
    $asciiMatches = $asciiPattern.Matches([System.Text.Encoding]::Latin1.GetString($bytes))
    $strings = foreach ($match in $asciiMatches) { $match.Value }

    $utf16Pattern = [regex]'(?:[ -~]\x00){4,}'
    $utf16Matches = $utf16Pattern.Matches($bytes)
    foreach ($match in $utf16Matches) {
        try {
            $strings += [System.Text.Encoding]::Unicode.GetString($match.Value)
        } catch {
            continue
        }
    }

    return Remove-DuplicateStrings -Values $strings
}

function Get-SwitchTokensFromText {
    param([string]$Text)

    $pattern = '(?:^|[\s"''])(/VERYSILENT|/SILENT|/SUPPRESSMSGBOXES|/NORESTART|/S\b|/Q\b|/QN\b|/QB\b|/quiet\b|/passive\b|--silent\b|--quiet\b|--help\b|/help\b|/\?\b|-h\b|-q\b|-s\b)(?=$|[\s"''])'
    $matches = [regex]::Matches($Text, $pattern, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    $tokens = foreach ($match in $matches) { $match.Groups[1].Value.Trim() }
    return Remove-DuplicateStrings -Values $tokens
}

function Get-KnownExeFamilySwitches {
    param([string[]]$BinaryStrings)

    $allText = ($BinaryStrings -join ' ').ToLowerInvariant()
    foreach ($signature in $script:ExeFamilySignatures.Keys) {
        if ($allText.Contains($signature)) {
            $data = $script:ExeFamilySignatures[$signature]
            return @{
                Family  = $signature
                Switches = $data.Tokens
                Reason  = $data.Reason
            }
        }
    }

    return @{}
}

function Get-SwitchesFromDocumentation {
    param([string[]]$Urls)

    $findings = [System.Collections.Generic.List[object]]::new()
    $discovered = [System.Collections.Generic.List[string]]::new()

    foreach ($url in $Urls) {
        if ([string]::IsNullOrWhiteSpace($url)) { continue }
        try {
            $response = Invoke-WebRequest -Uri $url -UseBasicParsing -TimeoutSec 8 -ErrorAction Stop
            $text = ($response.Content -replace '<[^>]+>', ' ') -replace '\s+', ' '
            $switches = Get-SwitchTokensFromText -Text $text
            if ($switches.Count -gt 0) {
                $findings.Add([PSCustomObject]@{
                    Url     = $url
                    Switches = $switches
                    Summary = 'Found potential silent switches in documentation content.'
                })
                foreach ($switch in $switches) { $discovered.Add($switch) }
            }
        } catch {
            $findings.Add([PSCustomObject]@{
                Url     = $url
                Switches = @()
                Summary = 'Unable to fetch or parse this page.'
            })
        }
    }

    return @{
        Switches = Remove-DuplicateStrings -Values $discovered.ToArray()
        Findings = $findings.ToArray()
    }
}

function Test-InstallerHelpOutput {
    param([string]$InstallerPath)

    if (-not $IsWindows) {
        return @{
            Supported = $false
            Reason    = 'Installer probing is only supported on Windows hosts.'
            Switches  = @()
            Attempts  = @()
        }
    }

    $probeFlags = @('/?', '-?', '/h', '--help', '/help')
    $attempts = [System.Collections.Generic.List[object]]::new()
    $discovered = [System.Collections.Generic.List[string]]::new()

    foreach ($flag in $probeFlags) {
        try {
            $output = (& $InstallerPath $flag 2>&1 | Out-String)
            $switches = Get-SwitchTokensFromText -Text $output
            foreach ($switch in $switches) { $discovered.Add($switch) }
            $attempts.Add([PSCustomObject]@{
                Flag       = $flag
                ReturnCode = $LASTEXITCODE
                Switches   = $switches
            })
            if ($switches.Count -gt 0) { break }
        } catch {
            $attempts.Add([PSCustomObject]@{
                Flag   = $flag
                Switches = @()
                Error  = $_.Exception.Message
            })
        }
    }

    return @{
        Supported = $true
        Switches  = Remove-DuplicateStrings -Values $discovered.ToArray()
        Attempts  = $attempts.ToArray()
    }
}

function Get-RecommendedInstallCommand {
    param(
        [string]$FileName,
        [string]$Extension,
        [string[]]$Switches
    )

    if ($Extension -eq '.msi') {
        return "msiexec /i `"$FileName`" /quiet /norestart"
    }
    if ($Extension -in '.msix', '.appx') {
        return "Add-AppxPackage -Path `"$FileName`""
    }
    if (-not $Switches -or $Switches.Count -eq 0) {
        return "`"$FileName`" /S"
    }
    return "`"$FileName`" $($Switches[0])"
}

function Invoke-InstallerSwitchAnalysis {
    param(
        [Parameter(Mandatory = $true)]
        [string]$InstallerPath,
        [string]$AppName,
        [string[]]$ResearchUrls = @(),
        [switch]$AllowRuntimeProbe
    )

    $path = Resolve-Path -Path $InstallerPath
    $extension = [System.IO.Path]::GetExtension($path).ToLowerInvariant()
    $knownSwitches = @()
    if ($script:KnownSwitchesByExtension.ContainsKey($extension)) {
        $knownSwitches = $script:KnownSwitchesByExtension[$extension]
    }

    $discoveredSwitches = [System.Collections.Generic.List[string]]::new()
    $methodsUsed = [System.Collections.Generic.List[string]]::new()
    $insights = [System.Collections.Generic.List[string]]::new()

    if ($extension -eq '.exe') {
        $methodsUsed.Add('binary-static-analysis')
        $binaryStrings = Get-BinaryStrings -InstallerPath $path
        $familyResult = Get-KnownExeFamilySwitches -BinaryStrings $binaryStrings
        if ($familyResult.Count -gt 0) {
            $knownSwitches += $familyResult.Switches
            $insights.Add($familyResult.Reason)
        }
        foreach ($token in (Get-SwitchTokensFromText -Text ($binaryStrings -join ' '))) {
            $discoveredSwitches.Add($token)
        }
    }

    $researchResult = @{ Switches = @(); Findings = @() }
    if ($ResearchUrls -and $ResearchUrls.Count -gt 0) {
        $methodsUsed.Add('documentation-research')
        $researchResult = Get-SwitchesFromDocumentation -Urls $ResearchUrls
        foreach ($switch in $researchResult.Switches) { $discoveredSwitches.Add($switch) }
    }

    $probeResult = @{
        Supported = $false
        Reason    = 'Runtime probing was not requested.'
        Switches  = @()
        Attempts  = @()
    }
    if ($AllowRuntimeProbe -and $extension -eq '.exe') {
        $methodsUsed.Add('runtime-probe')
        $probeResult = Test-InstallerHelpOutput -InstallerPath $path
        foreach ($switch in $probeResult.Switches) { $discoveredSwitches.Add($switch) }
    }

    $knownSwitches = Remove-DuplicateStrings -Values $knownSwitches
    $discovered = Remove-DuplicateStrings -Values $discoveredSwitches.ToArray()
    $allSwitches = Remove-DuplicateStrings -Values ($knownSwitches + $discovered)

    $status = if ($knownSwitches.Count -gt 0) {
        'known'
    } elseif ($discovered.Count -gt 0) {
        'discovered'
    } else {
        'missing'
    }

    return [PSCustomObject]@{
        AppName                   = $AppName
        InstallerFileName         = [System.IO.Path]::GetFileName($path)
        InstallerPath             = $path
        Extension                 = $extension
        Status                    = $status
        KnownSwitches             = $knownSwitches
        DiscoveredSwitches        = $discovered
        RecommendedSwitches       = $allSwitches
        RecommendedInstallCommand = (Get-RecommendedInstallCommand -FileName ([System.IO.Path]::GetFileName($path)) -Extension $extension -Switches $allSwitches)
        MethodsUsed               = $methodsUsed.ToArray()
        Insights                  = $insights.ToArray()
        Research                  = $researchResult
        RuntimeProbe              = $probeResult
    }
}
