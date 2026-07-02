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
    if ($sorted.Count -eq 1) {
        return ,$sorted
    }

    return $sorted
}

function Test-InstallerCommand {
    param(
        [Parameter(Mandatory = $true)]
        [string]$InstallerPath,
        [Parameter(Mandatory = $true)]
        [string]$Command
    )

    if (-not $IsWindows) {
        return [PSCustomObject]@{
            Verified   = $false
            ExitCode   = $null
            Message    = 'Runtime verification requires Windows and was skipped on this host.'
            Observable = $null
        }
    }

    Write-AppGetterLog -Message "Installer command verification is not yet automated; command marked unverified: $Command" -Level Warning
    return [PSCustomObject]@{
        Verified   = $false
        ExitCode   = $null
        Message    = 'Automated verification runner is not configured on this host.'
        Observable = $null
    }
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
        [switch]$SkipVerification
    )

    $fingerprint = Get-InstallerFingerprint -InstallerPath $InstallerPath
    $candidates = @(Find-InstallerSwitchCandidates -Fingerprint $fingerprint `
        -InstallerFileName $InstallerFileName -InstallSwitchesInfo $InstallSwitchesInfo)

    $recommended = if ($candidates.Count -gt 0) { $candidates[0] } else { $null }
    $confidenceScore = if ($recommended) { $recommended.Score } else { 0 }
    $confidenceScore = [Math]::Min(100, $confidenceScore + [Math]::Min(15, [int]($fingerprint.Confidence / 10)))

    $verification = $null
    $verified = $false
    if ($recommended -and -not $SkipVerification) {
        $verification = Test-InstallerCommand -InstallerPath $InstallerPath -Command $recommended.Command
        $verified = [bool]$verification.Verified
    }

    $needsManualReview = $confidenceScore -lt 70 -or -not $verified
    $evidenceSummary = @($fingerprint.DetectionEvidence)
    if ($recommended) {
        $evidenceSummary += "$($recommended.Source): $($recommended.Evidence) (score $($recommended.Score))"
    }
    if ($SupportUrl) {
        $evidenceSummary += "Support URL consulted: $SupportUrl"
    }
    if ($verification -and $verification.Message) {
        $evidenceSummary += $verification.Message
    }

    $alternativeCommands = @()
    if ($candidates.Count -gt 1) {
        $alternativeCommands = @($candidates | Select-Object -Skip 1 | ForEach-Object { $_.Command })
    }

    $recommendedCommand = if ($recommended) {
        $recommended.Command
    } else {
        Get-InstallerInstallCommand -InstallerFileName $InstallerFileName `
            -InstallerExtension ([System.IO.Path]::GetExtension($InstallerFileName)) `
            -DetectedSwitch (Get-DetectedSilentSwitch -InstallSwitchesInfo $InstallSwitchesInfo)
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
        Candidates            = $candidates
        Verification          = $verification
    }
}
