function Get-InstallerBinaryStrings {
    param(
        [Parameter(Mandatory = $true)]
        [byte[]]$Bytes,
        [int]$MinLength = 8
    )

    $strings = [System.Collections.Generic.List[string]]::new()
    $current = [System.Text.StringBuilder]::new()

    foreach ($byte in $Bytes) {
        if ($byte -ge 32 -and $byte -le 126) {
            [void]$current.Append([char]$byte)
        } else {
            if ($current.Length -ge $MinLength) {
                $strings.Add($current.ToString())
            }
            [void]$current.Clear()
        }
    }

    if ($current.Length -ge $MinLength) {
        $strings.Add($current.ToString())
    }

    return $strings
}

function Test-InstallerMsiSignature {
    param([byte[]]$Bytes)

    return $Bytes.Length -ge 8 -and
        $Bytes[0] -eq 0xD0 -and $Bytes[1] -eq 0xCF -and
        $Bytes[2] -eq 0x11 -and $Bytes[3] -eq 0xE0 -and
        $Bytes[4] -eq 0xA1 -and $Bytes[5] -eq 0xB1 -and
        $Bytes[6] -eq 0x1A -and $Bytes[7] -eq 0xE1
}

function Test-InstallerPeSignature {
    param([byte[]]$Bytes)

    return $Bytes.Length -ge 2 -and $Bytes[0] -eq 0x4D -and $Bytes[1] -eq 0x5A
}

function Get-InstallerFingerprint {
    param(
        [Parameter(Mandatory = $true)]
        [string]$InstallerPath
    )

    $extension = [System.IO.Path]::GetExtension($InstallerPath).ToLower()
    $bytes = [System.IO.File]::ReadAllBytes($InstallerPath)
    $strings = Get-InstallerBinaryStrings -Bytes $bytes
    $joinedStrings = ($strings -join "`n").ToLower()

    $families = [System.Collections.Generic.List[string]]::new()
    $evidence = [System.Collections.Generic.List[string]]::new()
    $primaryType = 'unknown'
    $confidence = 0

    if (Test-InstallerMsiSignature -Bytes $bytes) {
        $primaryType = 'msi'
        $families.Add('msi')
        $evidence.Add('OLE compound document signature (MSI container)')
        $confidence = 95
    } elseif ($extension -eq '.msix' -or $extension -eq '.appx') {
        $primaryType = $extension.TrimStart('.')
        $families.Add($primaryType)
        $evidence.Add("File extension indicates $($primaryType.ToUpper()) package")
        $confidence = 90
    } elseif (Test-InstallerPeSignature -Bytes $bytes -or $extension -eq '.exe') {
        $primaryType = 'exe'
        $evidence.Add('PE32 executable signature (MZ header)')

        $familyMarkers = @(
            @{
                Family  = 'inno'
                Markers = @('inno setup', 'innosetup', '/verysilent', '/suppressmsgboxes')
                Weight  = 30
            }
            @{
                Family  = 'nsis'
                Markers = @('nullsoft', 'nsis error', 'nsis.')
                Weight  = 30
            }
            @{
                Family  = 'installshield'
                Markers = @('installshield', 'setup.iss', 'isscript')
                Weight  = 30
            }
            @{
                Family  = 'wixburn'
                Markers = @('.wixburn', 'bootstrapperapplication', 'wix toolset bootstrapper', 'burn\engine')
                Weight  = 30
            }
            @{
                Family  = 'msi-bridge'
                Markers = @('msi.dll', 'msiinstallproduct', 'msiexec /i', 'execute msi package')
                Weight  = 20
            }
        )

        foreach ($familyInfo in $familyMarkers) {
            $matchedMarkers = @($familyInfo.Markers | Where-Object { $joinedStrings -like "*$_*" })
            if ($matchedMarkers.Count -gt 0) {
                if ($familyInfo.Family -eq 'msi-bridge') {
                    if (-not $families.Contains('msi-bridge')) {
                        $families.Add('msi-bridge')
                    }
                } else {
                    $families.Add($familyInfo.Family)
                }
                $evidence.Add("$($familyInfo.Family): matched $($matchedMarkers -join ', ')")
                $confidence = [Math]::Max($confidence, $familyInfo.Weight)
            }
        }

        if ($families.Count -eq 0) {
            $evidence.Add('No known installer-family markers found in binary strings')
            $confidence = 10
        } elseif ($families.Count -gt 1) {
            $evidence.Add("Multiple installer families detected: $($families -join ', ')")
            $confidence = [Math]::Max(10, $confidence - 20)
        } else {
            $confidence = [Math]::Min(85, $confidence + 20)
        }
    } elseif ($extension -eq '.msi') {
        $primaryType = 'msi'
        $families.Add('msi')
        $evidence.Add('File extension is .msi')
        $confidence = 70
    } else {
        $evidence.Add("Unrecognized installer type (extension: $extension)")
        $confidence = 5
    }

    return [PSCustomObject]@{
        PrimaryType       = $primaryType
        Families          = @($families)
        DetectionEvidence = @($evidence)
        Confidence        = $confidence
        BinaryStrings     = $strings
    }
}

function Get-NestedInstallerCandidates {
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Fingerprint,
        [Parameter(Mandatory = $true)]
        [string]$InstallerFileName
    )

    $candidates = [System.Collections.Generic.List[hashtable]]::new()
    $joinedStrings = ($Fingerprint.BinaryStrings -join "`n")

    $msiReferences = [regex]::Matches($joinedStrings, '(?i)([A-Za-z0-9._-]+\.msi)') |
        ForEach-Object { $_.Groups[1].Value } |
        Select-Object -Unique

    foreach ($msiName in $msiReferences) {
        $candidates.Add(@{
                Type     = 'nested-msi-reference'
                FileName = $msiName
                Evidence = "Embedded MSI reference found in binary: $msiName"
                Command  = "msiexec /i `"$msiName`" /qn /norestart /L*v `"%TEMP%\$([System.IO.Path]::GetFileNameWithoutExtension($msiName))-install.log`""
                Score    = 20
            })
    }

    if ($Fingerprint.Families -contains 'msi-bridge' -and $candidates.Count -eq 0) {
        $candidates.Add(@{
                Type     = 'msi-bridge'
                FileName = $InstallerFileName
                Evidence = 'MSI bridge markers found without extractable MSI filename'
                Command  = "`"$InstallerFileName`" /s /v`"/qn /norestart /L*v \`"%TEMP%\$([System.IO.Path]::GetFileNameWithoutExtension($InstallerFileName))-install.log\`"`""
                Score    = 15
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

    $logBase = [System.IO.Path]::GetFileNameWithoutExtension($InstallerFileName)

    switch ($Family) {
        'msi' {
            return "msiexec /i `"$InstallerFileName`" /qn /norestart /L*v `"%TEMP%\$logBase-install.log`""
        }
        'inno' {
            return "`"$InstallerFileName`" /VERYSILENT /SUPPRESSMSGBOXES /NORESTART /LOG=`"%TEMP%\$logBase-install.log`""
        }
        'nsis' {
            return "`"$InstallerFileName`" /S"
        }
        'installshield' {
            return "`"$InstallerFileName`" /s /v`"/qn /norestart /L*v \`"%TEMP%\$logBase-install.log\`"`""
        }
        'wixburn' {
            return "`"$InstallerFileName`" /quiet /norestart /log `"%TEMP%\$logBase-install.log`""
        }
        default {
            return "`"$InstallerFileName`" /S"
        }
    }
}

function Find-InstallerSwitchCandidates {
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Fingerprint,
        [Parameter(Mandatory = $true)]
        [string]$InstallerFileName,
        [hashtable]$InstallSwitchesInfo
    )

    $candidates = [System.Collections.Generic.List[hashtable]]::new()
    $seenCommands = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)

    function Add-Candidate {
        param(
            [string]$Command,
            [int]$Score,
            [string]$Source,
            [string]$Evidence
        )

        if ([string]::IsNullOrWhiteSpace($Command)) {
            return
        }

        if ($seenCommands.Add($Command)) {
            $candidates.Add(@{
                    Command  = $Command
                    Score    = $Score
                    Source   = $Source
                    Evidence = $Evidence
                })
        }
    }

    if ($Fingerprint.PrimaryType -eq 'msi' -or $Fingerprint.Families -contains 'msi') {
        $msiScore = if ($Fingerprint.Confidence -ge 90) { 60 } else { 40 }
        Add-Candidate -Command (Get-InstallerFamilyCommandTemplate -Family 'msi' -InstallerFileName $InstallerFileName) `
            -Score $msiScore -Source 'family-default' -Evidence 'Direct MSI container'
    }

    if ($Fingerprint.PrimaryType -eq 'msix' -or $Fingerprint.PrimaryType -eq 'appx') {
        Add-Candidate -Command "Add-AppxPackage -Path `"$InstallerFileName`"" `
            -Score 40 -Source 'family-default' -Evidence "$($Fingerprint.PrimaryType.ToUpper()) package"
    }

    foreach ($family in $Fingerprint.Families) {
        if ($family -eq 'msi-bridge') {
            continue
        }

        $command = Get-InstallerFamilyCommandTemplate -Family $family -InstallerFileName $InstallerFileName
        Add-Candidate -Command $command -Score 30 -Source 'family-fingerprint' `
            -Evidence "Binary fingerprint matched installer family: $family"
    }

    $nestedCandidates = Get-NestedInstallerCandidates -Fingerprint $Fingerprint -InstallerFileName $InstallerFileName
    foreach ($nested in $nestedCandidates) {
        Add-Candidate -Command $nested.Command -Score $nested.Score -Source 'nested-discovery' -Evidence $nested.Evidence
    }

    if ($InstallSwitchesInfo -and $InstallSwitchesInfo.InstallSwitches.Count -gt 0) {
        $switchText = ($InstallSwitchesInfo.InstallSwitches -join ' ')
        $detectedSwitch = Get-DetectedSilentSwitch -InstallSwitchesInfo $InstallSwitchesInfo
        if ($detectedSwitch) {
            $webCommand = "`"$InstallerFileName`" $detectedSwitch"
            Add-Candidate -Command $webCommand -Score 50 -Source 'vendor-documentation' `
                -Evidence "Support page switch text: $switchText"
        } else {
            Add-Candidate -Command "`"$InstallerFileName`" /S" -Score 25 -Source 'vendor-documentation' `
                -Evidence "Support page mentions install switches but no exact match was parsed: $switchText"
        }
    }

    if ($candidates.Count -eq 0) {
        if ($Fingerprint.PrimaryType -eq 'exe') {
            Add-Candidate -Command "`"$InstallerFileName`" /S" -Score 10 -Source 'fallback' `
                -Evidence 'Unknown EXE installer; using conservative /S fallback'
        } elseif ($Fingerprint.PrimaryType -eq 'msi') {
            Add-Candidate -Command (Get-InstallerFamilyCommandTemplate -Family 'msi' -InstallerFileName $InstallerFileName) `
                -Score 10 -Source 'fallback' -Evidence 'MSI fallback quiet install'
        }
    }

    if ($candidates.Count -gt 1) {
        $familyCount = @($Fingerprint.Families | Where-Object { $_ -ne 'msi-bridge' }).Count
        if ($familyCount -gt 1) {
            foreach ($candidate in $candidates) {
                if ($candidate.Source -eq 'family-fingerprint') {
                    $candidate.Score = [Math]::Max(0, $candidate.Score - 20)
                    $candidate.Evidence = "$($candidate.Evidence); reduced score due to conflicting family markers"
                }
            }
        }
    }

    $sorted = @($candidates | Sort-Object { $_.Score } -Descending)
    # Always return a Object[] of hashtables (never a bare hashtable or nested array).
    $result = [System.Collections.Generic.List[hashtable]]::new()
    foreach ($item in $sorted) {
        if ($item -is [hashtable]) {
            $result.Add($item) | Out-Null
        }
    }
    return ,$result.ToArray()
}

function Get-AppGetterSilentSwitchCachePath {
    return (Join-Path (Get-AppGetterConfigRoot) 'silent-switch-cache.json')
}

function Get-AppGetterSilentSwitchCache {
    $path = Get-AppGetterSilentSwitchCachePath
    if (-not (Test-Path -LiteralPath $path)) {
        return @{}
    }

    try {
        $raw = Get-Content -LiteralPath $path -Raw -ErrorAction Stop | ConvertFrom-Json
        $map = @{}
        foreach ($prop in $raw.PSObject.Properties) {
            $map[$prop.Name] = $prop.Value
        }
        return $map
    } catch {
        return @{}
    }
}

function Get-AppGetterSilentSwitchCacheEntry {
    param(
        [Parameter(Mandatory = $true)]
        [string]$InstallerHash
    )

    if ([string]::IsNullOrWhiteSpace($InstallerHash)) {
        return $null
    }

    $cache = Get-AppGetterSilentSwitchCache
    $key = $InstallerHash.ToUpperInvariant()
    if (-not $cache.ContainsKey($key)) {
        return $null
    }

    return $cache[$key]
}

function Set-AppGetterSilentSwitchCacheEntry {
    param(
        [Parameter(Mandatory = $true)]
        [string]$InstallerHash,
        [Parameter(Mandatory = $true)]
        [string]$VerifiedSilentCommand,
        [string]$ProductName = '',
        [string]$Version = '',
        [object]$ExitCodeObserved = $null,
        [string]$InstallerFamily = '',
        [string[]]$EvidenceSummary = @()
    )

    if ([string]::IsNullOrWhiteSpace($InstallerHash) -or [string]::IsNullOrWhiteSpace($VerifiedSilentCommand)) {
        return
    }

    $path = Get-AppGetterSilentSwitchCachePath
    $directory = Split-Path -Path $path -Parent
    if ($directory -and -not (Test-Path -LiteralPath $directory)) {
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
    }

    $cache = Get-AppGetterSilentSwitchCache
    $key = $InstallerHash.ToUpperInvariant()
    $cache[$key] = [ordered]@{
        InstallerHash          = $key
        ProductName            = $ProductName
        Version                = $Version
        VerifiedSilentCommand  = $VerifiedSilentCommand
        ExitCodeObserved       = $ExitCodeObserved
        InstallerFamily        = $InstallerFamily
        EvidenceSummary        = @($EvidenceSummary)
        VerificationDate       = (Get-Date).ToUniversalTime().ToString('o')
        VerificationHostInfo   = [ordered]@{
            OSVersion = [string][System.Environment]::OSVersion.VersionString
            MachineName = [string][System.Environment]::MachineName
            IsWindows = [bool]([System.Environment]::OSVersion.Platform -eq 'Win32NT')
        }
    }

    ($cache | ConvertTo-Json -Depth 8) | Set-Content -LiteralPath $path -Encoding UTF8
}

function Find-WingetSilentSwitchCandidate {
    param(
        [string]$AppName,
        [string]$InstallerFileName
    )

    if ([string]::IsNullOrWhiteSpace($AppName)) {
        return $null
    }

    if ([System.Environment]::OSVersion.Platform -ne 'Win32NT') {
        return $null
    }

    $winget = $null
    try {
        $winget = Get-AppGetterWingetExecutable
    } catch {
        return $null
    }
    if (-not $winget) {
        return $null
    }

    try {
        $showOutput = & $winget show --name $AppName --accept-source-agreements 2>&1 | Out-String
        if ([string]::IsNullOrWhiteSpace($showOutput)) {
            return $null
        }

        $silent = $null
        if ($showOutput -match '(?im)Silent:\s*(.+)$') {
            $silent = $Matches[1].Trim()
        } elseif ($showOutput -match '(?im)SilentWithProgress:\s*(.+)$') {
            $silent = $Matches[1].Trim()
        }

        if ([string]::IsNullOrWhiteSpace($silent)) {
            return $null
        }

        $command = if ($silent -match [regex]::Escape($InstallerFileName) -or $silent -match 'msiexec') {
            $silent
        } else {
            "`"$InstallerFileName`" $silent"
        }

        return @{
            Command  = $command
            Score    = 45
            Source   = 'winget-catalog'
            Evidence = "winget show reported silent switches for '$AppName': $silent"
        }
    } catch {
        return $null
    }
}

function Test-InstallerCommand {
    param(
        [Parameter(Mandatory = $true)]
        [string]$InstallerPath,
        [Parameter(Mandatory = $true)]
        [string]$Command,
        [string]$AppName = '',
        [switch]$AllowSandboxVerification,
        [int]$TimeoutSeconds = 900,
        [switch]$SkipLaunch
    )

    if (-not $AllowSandboxVerification) {
        return [PSCustomObject]@{
            Verified   = $false
            ExitCode   = $null
            Message    = 'Sandbox verification was not requested for this packaging run.'
            Observable = $null
            Method     = $null
        }
    }

    if ([System.Environment]::OSVersion.Platform -ne 'Win32NT') {
        return [PSCustomObject]@{
            Verified   = $false
            ExitCode   = $null
            Message    = 'Runtime verification requires Windows Sandbox and was skipped on this host.'
            Observable = $null
            Method     = $null
        }
    }

    return Test-InstallerCommandInSandbox `
        -InstallerPath $InstallerPath `
        -Command $Command `
        -AppName $AppName `
        -TimeoutSeconds $TimeoutSeconds `
        -SkipLaunch:$SkipLaunch
}

function Resolve-InstallerInstallCommand {
    param(
        [Parameter(Mandatory = $true)]
        [string]$InstallerPath,
        [Parameter(Mandatory = $true)]
        [string]$InstallerFileName,
        [string]$AppName,
        [hashtable]$InstallSwitchesInfo,
        [string]$SupportUrl,
        [switch]$SkipVerification,
        [switch]$VerifySilentSwitches,
        [int]$MaxCandidatesToVerify = 3,
        [int]$TimeoutSeconds = 900,
        [string]$InstallerHash
    )

    if (-not $InstallerHash -and (Test-Path -LiteralPath $InstallerPath)) {
        try {
            $InstallerHash = (Get-FileHash -Path $InstallerPath -Algorithm SHA256).Hash
        } catch {
            $InstallerHash = $null
        }
    }

    $fingerprint = Get-InstallerFingerprint -InstallerPath $InstallerPath
    $foundCandidates = Find-InstallerSwitchCandidates -Fingerprint $fingerprint `
        -InstallerFileName $InstallerFileName -InstallSwitchesInfo $InstallSwitchesInfo
    $candidateArray = @()
    foreach ($item in @($foundCandidates)) {
        if ($item -is [hashtable] -and $item.ContainsKey('Command')) {
            $candidateArray += ,$item
        }
    }

    $wingetCandidate = Find-WingetSilentSwitchCandidate -AppName $AppName -InstallerFileName $InstallerFileName
    if ($wingetCandidate) {
        $exists = $false
        foreach ($existing in $candidateArray) {
            if ([string]::Equals($existing.Command, $wingetCandidate.Command, [StringComparison]::OrdinalIgnoreCase)) {
                $existing.Score = [Math]::Max([int]$existing.Score, [int]$wingetCandidate.Score)
                $existing.Evidence = "$($existing.Evidence); $($wingetCandidate.Evidence)"
                $exists = $true
                break
            }
        }
        if (-not $exists) {
            $candidateArray += ,$wingetCandidate
        }
        $candidateArray = @($candidateArray | Sort-Object { $_.Score } -Descending)
    }

    $recommended = if ($candidateArray.Count -gt 0) { $candidateArray[0] } else { $null }
    $confidenceScore = if ($recommended) { [int]$recommended.Score } else { 0 }
    $confidenceScore = [Math]::Min(100, $confidenceScore + [Math]::Min(15, [int]($fingerprint.Confidence / 10)))

    $evidenceSummary = [System.Collections.Generic.List[string]]::new()
    foreach ($item in @($fingerprint.DetectionEvidence)) {
        $evidenceSummary.Add([string]$item) | Out-Null
    }
    if ($recommended) {
        $evidenceSummary.Add("$($recommended.Source): $($recommended.Evidence) (score $($recommended.Score))") | Out-Null
    }
    if ($SupportUrl) {
        $evidenceSummary.Add("Support URL consulted: $SupportUrl") | Out-Null
    }

    $verification = $null
    $verified = $false
    $verificationAttempts = @()

    $cached = $null
    if ($InstallerHash) {
        $cached = Get-AppGetterSilentSwitchCacheEntry -InstallerHash $InstallerHash
    }
    if ($cached -and $cached.VerifiedSilentCommand) {
        $recommendedCommand = [string]$cached.VerifiedSilentCommand
        $verified = $true
        $confidenceScore = [Math]::Min(100, [Math]::Max($confidenceScore, 90))
        $evidenceSummary.Add("Reused SHA-256 cache entry verified on $($cached.VerificationDate)") | Out-Null
        $verification = [PSCustomObject]@{
            Verified   = $true
            ExitCode   = $cached.ExitCodeObserved
            Message    = "Loaded verified silent command from local cache for hash $InstallerHash."
            Observable = $cached
            Method     = 'Cache'
        }

        $alternativeCommands = @($candidateArray | ForEach-Object { $_.Command } |
                Where-Object { -not [string]::Equals($_, $recommendedCommand, [StringComparison]::OrdinalIgnoreCase) })

        return [PSCustomObject]@{
            RecommendedCommand    = $recommendedCommand
            AlternativeCommands   = @($alternativeCommands)
            ConfidenceScore       = $confidenceScore
            EvidenceSummary       = @($evidenceSummary)
            NeedsManualReview     = $false
            Verified              = $true
            InstallerFamily       = if ($fingerprint.Families.Count -gt 0) { ($fingerprint.Families -join ', ') } else { $fingerprint.PrimaryType }
            PrimaryType           = $fingerprint.PrimaryType
            Fingerprint           = $fingerprint
            Candidates            = $candidateArray
            Verification          = $verification
            VerificationAttempts  = @()
            InstallerHash         = $InstallerHash
            UsedCache             = $true
        }
    }

    $sandboxAvailable = $false
    if ([System.Environment]::OSVersion.Platform -eq 'Win32NT') {
        try {
            $sandboxAvailable = [bool](Test-AppGetterWindowsSandbox).Enabled
        } catch {
            $sandboxAvailable = $false
        }
    }

    $familyCount = @($fingerprint.Families | Where-Object { $_ -and $_ -ne 'msi-bridge' }).Count
    $ambiguous = $familyCount -gt 1 -or $fingerprint.Confidence -lt 40
    $shouldVerify = (-not $SkipVerification) -and (
        $VerifySilentSwitches -or
        (($confidenceScore -lt 70 -or $ambiguous) -and $sandboxAvailable)
    )

    if ($recommended -and $shouldVerify) {
        $maxTry = [Math]::Max(1, [int]$MaxCandidatesToVerify)
        $toTry = @($candidateArray | Select-Object -First $maxTry)
        foreach ($candidate in $toTry) {
            Write-AppGetterLog -Message "Sandbox-verifying silent candidate: $($candidate.Command)" -Level Info
            $attempt = Test-InstallerCommand `
                -InstallerPath $InstallerPath `
                -Command $candidate.Command `
                -AppName $AppName `
                -AllowSandboxVerification `
                -TimeoutSeconds $TimeoutSeconds
            $verificationAttempts += ,[PSCustomObject]@{
                Command = $candidate.Command
                Source = $candidate.Source
                Score = $candidate.Score
                Result = $attempt
            }
            if ($attempt -and $attempt.Verified) {
                $recommended = $candidate
                $verification = $attempt
                $verified = $true
                $confidenceScore = [Math]::Min(100, [Math]::Max($confidenceScore, 90))
                $evidenceSummary.Add("Sandbox verified: $($attempt.Message)") | Out-Null
                break
            } elseif ($attempt -and $attempt.Message) {
                $evidenceSummary.Add("Sandbox rejected '$($candidate.Command)': $($attempt.Message)") | Out-Null
            }
        }

        if (-not $verified -and $verificationAttempts.Count -gt 0) {
            $verification = $verificationAttempts[-1].Result
        }
    } elseif ($recommended -and -not $SkipVerification -and -not $shouldVerify) {
        $verification = Test-InstallerCommand -InstallerPath $InstallerPath -Command $recommended.Command -AppName $AppName
        if ($verification -and $verification.Message) {
            $evidenceSummary.Add($verification.Message) | Out-Null
        }
    }

    $needsManualReview = $confidenceScore -lt 70 -or -not $verified

    $alternativeCommands = @()
    if ($candidateArray.Count -gt 1) {
        $chosen = if ($recommended) { $recommended.Command } else { $null }
        $alternativeCommands = @($candidateArray | ForEach-Object { $_.Command } |
                Where-Object { $chosen -and -not [string]::Equals($_, $chosen, [StringComparison]::OrdinalIgnoreCase) })
    }

    $recommendedCommand = if ($recommended) {
        $recommended.Command
    } else {
        Get-InstallerInstallCommand -InstallerFileName $InstallerFileName `
            -InstallerExtension ([System.IO.Path]::GetExtension($InstallerFileName)) `
            -DetectedSwitch (Get-DetectedSilentSwitch -InstallSwitchesInfo $InstallSwitchesInfo)
    }

    if ($verified -and $InstallerHash) {
        Set-AppGetterSilentSwitchCacheEntry `
            -InstallerHash $InstallerHash `
            -VerifiedSilentCommand $recommendedCommand `
            -ProductName $AppName `
            -ExitCodeObserved $(if ($verification) { $verification.ExitCode } else { $null }) `
            -InstallerFamily $(if ($fingerprint.Families.Count -gt 0) { ($fingerprint.Families -join ', ') } else { $fingerprint.PrimaryType }) `
            -EvidenceSummary @($evidenceSummary)
    }

    return [PSCustomObject]@{
        RecommendedCommand    = $recommendedCommand
        AlternativeCommands   = $alternativeCommands
        ConfidenceScore       = $confidenceScore
        EvidenceSummary       = @($evidenceSummary)
        NeedsManualReview     = $needsManualReview
        Verified              = $verified
        InstallerFamily       = if ($fingerprint.Families.Count -gt 0) { ($fingerprint.Families -join ', ') } else { $fingerprint.PrimaryType }
        PrimaryType           = $fingerprint.PrimaryType
        Fingerprint           = $fingerprint
        Candidates            = $candidateArray
        Verification          = $verification
        VerificationAttempts  = @($verificationAttempts)
        InstallerHash         = $InstallerHash
        UsedCache             = $false
    }
}
