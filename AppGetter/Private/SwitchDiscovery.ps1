$script:MsiOleSignature = [byte[]](0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1)

function Test-InstallerIsMsiContainer {
    param(
        [Parameter(Mandatory = $true)]
        [byte[]]$Bytes
    )

    if (-not $Bytes -or $Bytes.Length -lt $script:MsiOleSignature.Length) {
        return $false
    }

    for ($index = 0; $index -le $Bytes.Length - $script:MsiOleSignature.Length; $index++) {
        $matched = $true
        for ($offset = 0; $offset -lt $script:MsiOleSignature.Length; $offset++) {
            if ($Bytes[$index + $offset] -ne $script:MsiOleSignature[$offset]) {
                $matched = $false
                break
            }
        }
        if ($matched) {
            return $true
        }
    }

    return $false
}

function Get-InstallerBinarySample {
    param(
        [Parameter(Mandatory = $true)]
        [string]$InstallerPath,
        [int]$ByteLimit = 5MB
    )

    $stream = [System.IO.File]::OpenRead($InstallerPath)
    try {
        $bytesToRead = [Math]::Min([int64]$ByteLimit, $stream.Length)
        $buffer = New-Object byte[] $bytesToRead
        [void]$stream.Read($buffer, 0, $buffer.Length)
        return $buffer
    }
    finally {
        $stream.Dispose()
    }
}

function Get-InstallerBinaryStrings {
    param(
        [Parameter(Mandatory = $true)]
        [string]$InstallerPath,
        [int]$MinimumLength = 8,
        [int]$ByteLimit = 5MB
    )

    if ($IsLinux -or $IsMacOS) {
        $stringsCmd = Get-Command strings -ErrorAction SilentlyContinue
        if ($stringsCmd) {
            try {
                $output = & strings -n $MinimumLength $InstallerPath 2>$null
                if ($output) {
                    return @($output)
                }
            }
            catch {
                Write-AppGetterLog -Message "strings command failed, falling back to PowerShell extraction: $_" -Level Warning
            }
        }
    }

    $bytes = Get-InstallerBinarySample -InstallerPath $InstallerPath -ByteLimit $ByteLimit
    $text = [System.Text.Encoding]::ASCII.GetString($bytes)
    $utf16Text = [System.Text.Encoding]::Unicode.GetString($bytes)
    $combined = "$text $utf16Text"

    $matches = [regex]::Matches($combined, "[ -~]{$MinimumLength,}")
    $strings = foreach ($match in $matches) {
        $match.Value.Trim()
    }

    return @($strings | Where-Object { $_ } | Select-Object -Unique)
}

function Get-InstallerFingerprint {
    param(
        [Parameter(Mandatory = $true)]
        [string]$InstallerPath,
        [string]$InstallerFileName
    )

    $extension = [System.IO.Path]::GetExtension($InstallerFileName).ToLowerInvariant()
    $bytes = Get-InstallerBinarySample -InstallerPath $InstallerPath
    $isMsiContainer = Test-InstallerIsMsiContainer -Bytes $bytes
    $evidence = [System.Collections.Generic.List[string]]::new()
    $matchedFamilies = [System.Collections.Generic.List[string]]::new()

    if ($extension -eq '.msi' -or $isMsiContainer) {
        if ($extension -eq '.msi') {
            $evidence.Add('File extension is .msi')
        }
        if ($isMsiContainer) {
            $evidence.Add('OLE compound document MSI signature detected')
        }
        $matchedFamilies.Add('msi')
    }

    switch ($extension) {
        '.msix' {
            return [PSCustomObject]@{
                PrimaryType       = 'msix'
                InstallerFamilies = @('msix')
                Confidence        = 95
                Evidence          = @('File extension is .msix')
                BinaryStrings     = @()
            }
        }
        '.appx' {
            return [PSCustomObject]@{
                PrimaryType       = 'appx'
                InstallerFamilies = @('appx')
                Confidence        = 95
                Evidence          = @('File extension is .appx')
                BinaryStrings     = @()
            }
        }
    }

    $binaryStrings = Get-InstallerBinaryStrings -InstallerPath $InstallerPath
    $blob = ($binaryStrings -join ' ').ToLowerInvariant()

    $familyMarkers = @(
        @{
            Family   = 'inno'
            Patterns = @('inno setup', '/verysilent', '/suppressmsgboxes')
            Evidence = 'Inno Setup markers found in binary'
        },
        @{
            Family   = 'nsis'
            Patterns = @('nullsoft', 'nsis')
            Evidence = 'NSIS / Nullsoft markers found in binary'
        },
        @{
            Family   = 'installshield'
            Patterns = @('installshield', 'setup.iss')
            Evidence = 'InstallShield markers found in binary'
        },
        @{
            Family   = 'wixburn'
            Patterns = @('.wixburn', 'bootstrapperapplication', 'wix toolset bootstrapper', 'burn\engine')
            Evidence = 'WiX Burn bootstrapper markers found in binary'
        },
        @{
            Family   = 'msi-bridge'
            Patterns = @('msi.dll', 'msiinstallproduct', 'msiexec')
            Evidence = 'MSI bridge references found in binary'
        }
    )

    foreach ($marker in $familyMarkers) {
        foreach ($pattern in $marker.Patterns) {
            if ($blob -like "*$pattern*") {
                if ($marker.Family -notin $matchedFamilies) {
                    $matchedFamilies.Add($marker.Family)
                    $evidence.Add($marker.Evidence)
                }
                break
            }
        }
    }

    if ($matchedFamilies.Count -eq 0 -and $extension -eq '.exe') {
        $matchedFamilies.Add('exe')
        $evidence.Add('PE executable with no recognized installer-family markers')
    }

    if ($matchedFamilies.Count -gt 1 -and $matchedFamilies -contains 'msi') {
        $nonMsiFamilies = @($matchedFamilies | Where-Object { $_ -ne 'msi' })
        if ($nonMsiFamilies.Count -gt 0) {
            $evidence.Add("Multiple installer families detected: $($matchedFamilies -join ', ')")
        }
    }

    $confidence = switch ($matchedFamilies.Count) {
        0 { 20 }
        1 {
            if ($matchedFamilies[0] -eq 'msi') { 90 }
            elseif ($matchedFamilies[0] -in 'inno', 'nsis', 'wixburn') { 75 }
            else { 55 }
        }
        default { 40 }
    }

    if ($extension -eq '.exe' -and -not $isMsiContainer) {
        $primaryType = 'exe'
    }
    elseif ($isMsiContainer -and $extension -ne '.msi') {
        $primaryType = 'exe'
    }
    elseif ($extension -eq '.msi') {
        $primaryType = 'msi'
    }
    else {
        $primaryType = if ($extension.TrimStart('.')) { $extension.TrimStart('.') } else { 'unknown' }
    }

    return [PSCustomObject]@{
        PrimaryType       = $primaryType
        InstallerFamilies = @($matchedFamilies)
        Confidence        = $confidence
        Evidence          = @($evidence)
        BinaryStrings     = $binaryStrings
        IsMsiContainer    = $isMsiContainer
    }
}

function Get-NestedInstallerCandidates {
    param(
        [Parameter(Mandatory = $true)]
        [string]$InstallerPath,
        [string]$InstallerFileName
    )

    $candidates = [System.Collections.Generic.List[hashtable]]::new()
    $bytes = Get-InstallerBinarySample -InstallerPath $InstallerPath -ByteLimit 25MB

    if (Test-InstallerIsMsiContainer -Bytes $bytes) {
        $candidates.Add(@{
            Type     = 'embedded-msi'
            Evidence = 'Embedded MSI OLE signature found inside installer binary'
            Score    = 20
        })
    }

    return @($candidates)
}

function Get-InstallerFamilyCommandTemplate {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Family,
        [Parameter(Mandatory = $true)]
        [string]$InstallerFileName
    )

    switch ($Family) {
        'msi' {
            return @{
                Command  = "msiexec /i `"$InstallerFileName`" /qn /norestart"
                Switches = @('/qn', '/norestart')
                Source   = 'MSI family default'
            }
        }
        'inno' {
            return @{
                Command  = "`"$InstallerFileName`" /VERYSILENT /SUPPRESSMSGBOXES /NORESTART"
                Switches = @('/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART')
                Source   = 'Inno Setup family default'
            }
        }
        'nsis' {
            return @{
                Command  = "`"$InstallerFileName`" /S"
                Switches = @('/S')
                Source   = 'NSIS family default'
            }
        }
        'installshield' {
            return @{
                Command  = "`"$InstallerFileName`" /s /v`"/qn /norestart`""
                Switches = @('/s', '/v"/qn /norestart"')
                Source   = 'InstallShield family default'
            }
        }
        'wixburn' {
            return @{
                Command  = "`"$InstallerFileName`" /quiet /norestart"
                Switches = @('/quiet', '/norestart')
                Source   = 'WiX Burn family default'
            }
        }
        'msi-bridge' {
            return @{
                Command  = "`"$InstallerFileName`" /s /v`"/qn /norestart`""
                Switches = @('/s', '/v"/qn /norestart"')
                Source   = 'MSI bootstrapper default'
            }
        }
        'msix' {
            return @{
                Command  = "Add-AppxPackage -Path `"$InstallerFileName`""
                Switches = @()
                Source   = 'MSIX family default'
            }
        }
        'appx' {
            return @{
                Command  = "Add-AppxPackage -Path `"$InstallerFileName`""
                Switches = @()
                Source   = 'APPX family default'
            }
        }
        default {
            return @{
                Command  = "`"$InstallerFileName`" /S"
                Switches = @('/S')
                Source   = 'Generic EXE fallback'
            }
        }
    }
}

function Get-SwitchCandidatesFromDocumentation {
    param(
        [string]$SupportUrl,
        [string]$WebsiteUrl,
        [string]$DeveloperUrl,
        [string]$AppName,
        [hashtable]$InstallSwitchesInfo,
        [string]$InstallerFileName
    )

    $candidates = [System.Collections.Generic.List[hashtable]]::new()
    $urls = @($SupportUrl, $WebsiteUrl, $DeveloperUrl) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique

    if ($InstallSwitchesInfo -and $InstallSwitchesInfo.InstallSwitches.Count -gt 0) {
        $switchText = $InstallSwitchesInfo.InstallSwitches -join ' '
        $docCommand = Get-InstallCommandFromSwitchText -SwitchText $switchText -InstallerFileName $InstallerFileName
        if ($docCommand) {
            $candidates.Add(@{
                Command    = $docCommand.Command
                Score      = 50
                Source     = 'Vendor documentation'
                SourceUrl  = $SupportUrl
                Switches   = $docCommand.Switches
                Evidence   = "Support page switch text: $($docCommand.Evidence)"
            })
        }
    }

    foreach ($url in $urls) {
        try {
            $response = Invoke-WebRequest -Uri $url -UseBasicParsing -ErrorAction Stop
            $text = $response.Content -replace '<[^>]+>', ' '
            $docCommand = Get-InstallCommandFromSwitchText -SwitchText $text -InstallerFileName $InstallerFileName
            if ($docCommand) {
                $candidates.Add(@{
                    Command   = $docCommand.Command
                    Score     = if ($url -eq $SupportUrl) { 50 } else { 35 }
                    Source    = 'Web documentation'
                    SourceUrl = $url
                    Switches  = $docCommand.Switches
                    Evidence  = "Found switch guidance on $url"
                })
            }
        }
        catch {
            Write-AppGetterLog -Message "Could not scan $url for install switches: $_" -Level Warning
        }
    }

    return @($candidates)
}

function Get-InstallCommandFromSwitchText {
    param(
        [string]$SwitchText,
        [string]$InstallerFileName
    )

    if ([string]::IsNullOrWhiteSpace($SwitchText)) {
        return $null
    }

    if ($SwitchText -match '(?i)msiexec\s+/i[^`"''\r\n]{0,120}') {
        $msiFragment = $matches[0].Trim()
        return @{
            Command  = $msiFragment -replace '(?i)\S+\.msi', "`"$InstallerFileName`""
            Switches = @('/i', '/qn', '/quiet', '/norestart') | Where-Object { $msiFragment -match [regex]::Escape($_) }
            Evidence = $msiFragment
        }
    }

    $switchPriority = @('/VERYSILENT', '/SILENT', '/quiet', '/qn', '/S', '/s', '--silent')
    foreach ($switch in $switchPriority) {
        $escaped = [regex]::Escape($switch)
        if ($SwitchText -match "(?i)$escaped") {
            $extra = @()
            if ($switch -match 'VERYSILENT|SILENT' -and $SwitchText -match '/SUPPRESSMSGBOXES') {
                $extra += '/SUPPRESSMSGBOXES'
            }
            if ($SwitchText -match '/NORESTART') {
                $extra += '/NORESTART'
            }
            $allSwitches = @($switch) + $extra
            return @{
                Command  = "`"$InstallerFileName`" $($allSwitches -join ' ')"
                Switches = $allSwitches
                Evidence = ($allSwitches -join ' ')
            }
        }
    }

    return $null
}

function Get-SwitchCandidatesFromInstallerHelp {
    param(
        [Parameter(Mandatory = $true)]
        [string]$InstallerPath,
        [Parameter(Mandatory = $true)]
        [string]$InstallerFileName,
        [int]$TimeoutSeconds = 20
    )

    if (-not $IsWindows) {
        return @()
    }

    if ($InstallerPath.ToLowerInvariant().EndsWith('.msi')) {
        return @(@{
            Command  = "msiexec /i `"$InstallerFileName`" /qn /norestart"
            Score    = 30
            Source   = 'Installer help probing'
            Switches = @('/qn', '/norestart')
            Evidence = 'MSI installer uses standard switches'
        })
    }

    if (-not $InstallerPath.ToLowerInvariant().EndsWith('.exe')) {
        return @()
    }

    $candidates = [System.Collections.Generic.List[hashtable]]::new()
    $probes = @('/?', '/help', '-?', '--help')

    foreach ($probe in $probes) {
        $tempOutput = [System.IO.Path]::GetTempFileName()
        try {
            $quotedInstaller = '"' + $InstallerPath.Replace('"', '""') + '"'
            $cmdLine = "$quotedInstaller $probe > `"$tempOutput`" 2>&1"
            $process = Start-Process -FilePath 'cmd.exe' -ArgumentList "/c $cmdLine" -PassThru -WindowStyle Hidden

            if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
                try { $process.Kill() } catch { }
                continue
            }

            if (-not (Test-Path -LiteralPath $tempOutput)) {
                continue
            }

            $output = Get-Content -LiteralPath $tempOutput -Raw -ErrorAction SilentlyContinue
            $docCommand = Get-InstallCommandFromSwitchText -SwitchText $output -InstallerFileName $InstallerFileName
            if ($docCommand) {
                $candidates.Add(@{
                    Command  = $docCommand.Command
                    Score    = 30
                    Source   = 'Installer help probing'
                    Switches = $docCommand.Switches
                    Evidence = "Installer help output for '$probe'"
                })
                break
            }
        }
        catch {
            Write-AppGetterLog -Message "Installer help probe '$probe' failed: $_" -Level Warning
        }
        finally {
            if (Test-Path -LiteralPath $tempOutput) {
                Remove-Item -LiteralPath $tempOutput -Force -ErrorAction SilentlyContinue
            }
        }
    }

    return @($candidates)
}

function Find-InstallerSwitchCandidates {
    param(
        [Parameter(Mandatory = $true)]
        [string]$InstallerPath,
        [Parameter(Mandatory = $true)]
        [string]$InstallerFileName,
        [string]$AppName,
        [string]$SupportUrl,
        [string]$WebsiteUrl,
        [string]$DeveloperUrl,
        [hashtable]$InstallSwitchesInfo
    )

    $fingerprint = Get-InstallerFingerprint -InstallerPath $InstallerPath -InstallerFileName $InstallerFileName
    $nestedCandidates = Get-NestedInstallerCandidates -InstallerPath $InstallerPath -InstallerFileName $InstallerFileName
    $ranked = [System.Collections.Generic.List[hashtable]]::new()
    $evidenceSummary = [System.Collections.Generic.List[string]]::new()
    foreach ($item in $fingerprint.Evidence) {
        $evidenceSummary.Add([string]$item)
    }

    foreach ($family in $fingerprint.InstallerFamilies) {
        $template = Get-InstallerFamilyCommandTemplate -Family $family -InstallerFileName $InstallerFileName
        $score = switch ($family) {
            'msi' { 90 }
            'msix' { 95 }
            'appx' { 95 }
            'inno' { 75 }
            'nsis' { 75 }
            'wixburn' { 75 }
            default { 55 }
        }
        if ($fingerprint.InstallerFamilies.Count -gt 1) {
            $score -= 20
            $evidenceSummary.Add("Conflicting family evidence reduced confidence for $family")
        }

        $ranked.Add(@{
            Command  = $template.Command
            Score    = $score
            Source   = $template.Source
            Family   = $family
            Switches = $template.Switches
            Evidence = "Binary fingerprint: $family"
        })
    }

    foreach ($nested in $nestedCandidates) {
        $evidenceSummary.Add($nested.Evidence)
        foreach ($candidate in $ranked) {
            if ($candidate.Family -in 'installshield', 'msi-bridge', 'wixburn') {
                $candidate.Score += $nested.Score
            }
        }
    }

    foreach ($docCandidate in (Get-SwitchCandidatesFromDocumentation -SupportUrl $SupportUrl -WebsiteUrl $WebsiteUrl `
            -DeveloperUrl $DeveloperUrl -AppName $AppName -InstallSwitchesInfo $InstallSwitchesInfo `
            -InstallerFileName $InstallerFileName)) {
        $ranked.Add($docCandidate)
        $evidenceSummary.Add($docCandidate.Evidence)
    }

    foreach ($helpCandidate in (Get-SwitchCandidatesFromInstallerHelp -InstallerPath $InstallerPath -InstallerFileName $InstallerFileName)) {
        $ranked.Add($helpCandidate)
        $evidenceSummary.Add($helpCandidate.Evidence)
    }

    if ($ranked.Count -eq 0) {
        $fallback = Get-InstallerFamilyCommandTemplate -Family 'exe' -InstallerFileName $InstallerFileName
        $ranked.Add(@{
            Command  = $fallback.Command
            Score    = 10
            Source   = $fallback.Source
            Family   = 'exe'
            Switches = $fallback.Switches
            Evidence = 'No installer-family evidence found'
        })
        $evidenceSummary.Add('Applied generic /S fallback')
    }

    $deduped = @{}
    foreach ($candidate in $ranked) {
        $key = $candidate.Command.ToLowerInvariant()
        if (-not $deduped.ContainsKey($key) -or $deduped[$key].Score -lt $candidate.Score) {
            $deduped[$key] = $candidate
        }
    }

    $sorted = @($deduped.Values | Sort-Object -Property Score -Descending)
    return [PSCustomObject]@{
        Fingerprint      = $fingerprint
        Candidates       = $sorted
        EvidenceSummary  = @($evidenceSummary | Select-Object -Unique)
        NestedCandidates = $nestedCandidates
    }
}

function Test-InstallerCommand {
    param(
        [Parameter(Mandatory = $true)]
        [string]$InstallerPath,
        [Parameter(Mandatory = $true)]
        [string]$InstallCommand,
        [int]$TimeoutSeconds = 300
    )

    if (-not $IsWindows) {
        return [PSCustomObject]@{
            Verified = $false
            Reason   = 'Runtime verification requires Windows'
            ExitCode = $null
        }
    }

    $tempOutput = [System.IO.Path]::GetTempFileName()
    try {
        $cmdLine = "$InstallCommand > `"$tempOutput`" 2>&1"
        $process = Start-Process -FilePath 'cmd.exe' -ArgumentList "/c $cmdLine" -Wait -PassThru -WindowStyle Hidden

        if ($process.ExitCode -in 0, 3010, 1641, 1618) {
            return [PSCustomObject]@{
                Verified = $true
                Reason   = "Exit code $($process.ExitCode)"
                ExitCode = $process.ExitCode
            }
        }

        return [PSCustomObject]@{
            Verified = $false
            Reason   = "Exit code $($process.ExitCode)"
            ExitCode = $process.ExitCode
        }
    }
    catch {
        return [PSCustomObject]@{
            Verified = $false
            Reason   = $_.Exception.Message
            ExitCode = $null
        }
    }
    finally {
        if (Test-Path -LiteralPath $tempOutput) {
            Remove-Item -LiteralPath $tempOutput -Force -ErrorAction SilentlyContinue
        }
    }
}

function Resolve-InstallerInstallCommand {
    param(
        [Parameter(Mandatory = $true)]
        [string]$InstallerPath,
        [Parameter(Mandatory = $true)]
        [string]$InstallerFileName,
        [string]$AppName,
        [string]$SupportUrl,
        [string]$WebsiteUrl,
        [string]$DeveloperUrl,
        [hashtable]$InstallSwitchesInfo,
        [switch]$SkipVerification,
        [scriptblock]$OnProgress
    )

    $discovery = Find-InstallerSwitchCandidates -InstallerPath $InstallerPath -InstallerFileName $InstallerFileName `
        -AppName $AppName -SupportUrl $SupportUrl -WebsiteUrl $WebsiteUrl -DeveloperUrl $DeveloperUrl `
        -InstallSwitchesInfo $InstallSwitchesInfo

    $topCandidate = $discovery.Candidates | Select-Object -First 1
    $alternatives = @($discovery.Candidates | Select-Object -Skip 1 | ForEach-Object { $_.Command })
    $confidenceScore = [Math]::Min(100, [Math]::Max(0, [int]$topCandidate.Score))
    $verified = $false
    $verificationReason = 'Verification skipped'

    if (-not $SkipVerification -and $IsWindows) {
        $verification = Test-InstallerCommand -InstallerPath $InstallerPath -InstallCommand $topCandidate.Command
        $verified = $verification.Verified
        $verificationReason = $verification.Reason
        if ($verified) {
            $confidenceScore = [Math]::Min(100, $confidenceScore + 15)
        }
        else {
            $confidenceScore = [Math]::Max(0, $confidenceScore - 15)
            Write-AppGetterLog -Message "Primary install command verification failed: $verificationReason" -Level Warning -OnProgress $OnProgress
        }
    }
    elseif (-not $IsWindows) {
        $verificationReason = 'Runtime verification unavailable on non-Windows host'
    }

    $needsManualReview = $confidenceScore -lt 70 -or (-not $verified -and $IsWindows -and -not $SkipVerification)
    $installerFamily = if ($topCandidate.Family) { $topCandidate.Family } else { $discovery.Fingerprint.PrimaryType }

    Write-AppGetterLog -Message "Silent install discovery: family=$installerFamily, confidence=$confidenceScore, command=$($topCandidate.Command)" `
        -Level $(if ($needsManualReview) { 'Warning' } else { 'Success' }) -OnProgress $OnProgress

    if ($needsManualReview) {
        Write-AppGetterLog -Message 'Install command needs manual review before production deployment.' -Level Warning -OnProgress $OnProgress
    }

    return [PSCustomObject]@{
        InstallCommand       = $topCandidate.Command
        ConfidenceScore      = $confidenceScore
        NeedsManualReview    = $needsManualReview
        Verified             = $verified
        InstallerFamily      = $installerFamily
        Source               = $topCandidate.Source
        DetectedSwitches     = @($topCandidate.Switches)
        AlternativeCommands  = $alternatives
        EvidenceSummary      = $discovery.EvidenceSummary
        VerificationReason   = $verificationReason
        Fingerprint          = $discovery.Fingerprint
        Candidates           = $discovery.Candidates
    }
}
