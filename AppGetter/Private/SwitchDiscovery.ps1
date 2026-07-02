function Get-InstallerFingerprint {
    param(
        [Parameter(Mandatory = $true)]
        [string]$InstallerPath,
        [string]$InstallerFileName
    )

    if (-not (Test-Path $InstallerPath)) {
        throw "Installer not found: $InstallerPath"
    }

    if ([string]::IsNullOrWhiteSpace($InstallerFileName)) {
        $InstallerFileName = Split-Path -Leaf $InstallerPath
    }

    $extension = [System.IO.Path]::GetExtension($InstallerFileName).ToLower()
    $fileInfo = Get-Item $InstallerPath
    $bytes = [System.IO.File]::ReadAllBytes($InstallerPath)
    $evidence = [System.Collections.Generic.List[string]]::new()
    $families = [System.Collections.Generic.List[string]]::new()

    $msiMagic = [byte[]](0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1)
    $isMsiContainer = Test-ByteSequence -Bytes $bytes -Pattern $msiMagic -AtStart

    if ($isMsiContainer) {
        $primaryType = 'msi'
        $families.Add('msi') | Out-Null
        $evidence.Add('Composite Document File (MSI) signature detected at file start.') | Out-Null
    }
    elseif ($extension -in '.msix', '.appx') {
        $primaryType = $extension.TrimStart('.')
        $families.Add($primaryType) | Out-Null
        $evidence.Add("File extension indicates $primaryType package.") | Out-Null
    }
    elseif ($bytes.Length -ge 2 -and $bytes[0] -eq 0x4D -and $bytes[1] -eq 0x5A) {
        $primaryType = 'exe'
        $evidence.Add('PE executable (MZ header) detected.') | Out-Null

        $asciiText = Get-InstallerAsciiText -Bytes $bytes -MaxLength 4194304
        $familyMarkers = @(
            @{ Family = 'inno'; Patterns = @('Inno Setup', '/VERYSILENT', '/SUPPRESSMSGBOXES') }
            @{ Family = 'nsis'; Patterns = @('Nullsoft', 'NSIS Error', 'NullsoftInst') }
            @{ Family = 'installshield'; Patterns = @('InstallShield', 'setup.iss', 'ISScript') }
            @{ Family = 'wixburn'; Patterns = @('.wixburn', 'BootstrapperApplication', 'WiX Toolset Bootstrapper', 'burn\engine') }
            @{ Family = 'msi-bridge'; Patterns = @('msi.dll', 'MsiInstallProduct', 'msiexec', 'Windows Installer') }
        )

        foreach ($marker in $familyMarkers) {
            $matchCount = 0
            $matchedPatterns = @()
            foreach ($pattern in $marker.Patterns) {
                if ($asciiText -like "*$pattern*") {
                    $matchCount++
                    $matchedPatterns += $pattern
                }
            }

            if ($matchCount -gt 0) {
                $families.Add($marker.Family) | Out-Null
                $evidence.Add("$($marker.Family) markers found: $($matchedPatterns -join ', ').") | Out-Null
            }
        }

        if ($families.Count -eq 0) {
            $families.Add('exe-unknown') | Out-Null
            $evidence.Add('No known installer-family markers detected in executable strings.') | Out-Null
        }
    }
    else {
        $primaryType = 'unknown'
        $families.Add('unknown') | Out-Null
        $evidence.Add('Installer type could not be classified from signature or extension.') | Out-Null
    }

    $nestedMsiOffset = Find-ByteSequenceOffset -Bytes $bytes -Pattern $msiMagic -SkipStart:$isMsiContainer
    $hasNestedMsi = $null -ne $nestedMsiOffset

    if ($hasNestedMsi) {
        $evidence.Add("Embedded MSI payload detected at byte offset $nestedMsiOffset.") | Out-Null
        if (-not $families.Contains('msi-bridge')) {
            $families.Add('msi-bridge') | Out-Null
        }
    }

    $confidence = 40
    if ($primaryType -eq 'msi') { $confidence = 90 }
    elseif ($families.Count -eq 1 -and $families[0] -ne 'exe-unknown') { $confidence = 75 }
    elseif ($families.Count -gt 1) { $confidence = 55 }
    else { $confidence = 35 }

    return [PSCustomObject]@{
        InstallerPath   = $InstallerPath
        InstallerFileName = $InstallerFileName
        Extension       = $extension
        FileSizeBytes   = $fileInfo.Length
        PrimaryType     = $primaryType
        Families        = @($families)
        DetectionEvidence = @($evidence)
        HasNestedMsi    = $hasNestedMsi
        NestedMsiOffset = $nestedMsiOffset
        Confidence      = $confidence
    }
}

function Get-NestedInstallerCandidates {
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Fingerprint
    )

    $candidates = [System.Collections.Generic.List[hashtable]]::new()

    if ($Fingerprint.PrimaryType -eq 'msi' -or $Fingerprint.HasNestedMsi) {
        $candidates.Add(@{
            Family      = 'msi'
            Command     = "msiexec /i `"$($Fingerprint.InstallerFileName)`" /qn /norestart"
            Evidence    = 'Direct or embedded MSI container — prefer msiexec over wrapper EXE.'
            ConfidenceBonus = 20
        }) | Out-Null
    }

    return @($candidates)
}

function Get-InstallerFamilyCommandTemplates {
    param(
        [Parameter(Mandatory = $true)]
        [string]$InstallerFileName,
        [Parameter(Mandatory = $true)]
        [string[]]$Families
    )

    $templates = [System.Collections.Generic.List[hashtable]]::new()

    foreach ($family in $Families) {
        switch ($family) {
            'msi' {
                $templates.Add(@{
                    Family = 'msi'
                    Command = "msiexec /i `"$InstallerFileName`" /qn /norestart"
                    Evidence = 'MSI family default command.'
                    ConfidenceBonus = 30
                }) | Out-Null
            }
            'inno' {
                $templates.Add(@{
                    Family = 'inno'
                    Command = "`"$InstallerFileName`" /VERYSILENT /SUPPRESSMSGBOXES /NORESTART"
                    Evidence = 'Inno Setup silent install switches.'
                    ConfidenceBonus = 30
                }) | Out-Null
            }
            'nsis' {
                $templates.Add(@{
                    Family = 'nsis'
                    Command = "`"$InstallerFileName`" /S"
                    Evidence = 'NSIS silent switch (/S is case-sensitive).'
                    ConfidenceBonus = 30
                }) | Out-Null
            }
            'installshield' {
                $templates.Add(@{
                    Family = 'installshield'
                    Command = "`"$InstallerFileName`" /s /v`"/qn /norestart`""
                    Evidence = 'InstallShield wrapper with MSI quiet passthrough.'
                    ConfidenceBonus = 30
                }) | Out-Null
            }
            'wixburn' {
                $templates.Add(@{
                    Family = 'wixburn'
                    Command = "`"$InstallerFileName`" /quiet /norestart"
                    Evidence = 'WiX Burn bootstrapper quiet mode.'
                    ConfidenceBonus = 30
                }) | Out-Null
            }
            'msi-bridge' {
                if (-not ($Families -contains 'msi')) {
                    $templates.Add(@{
                        Family = 'msi-bridge'
                        Command = "`"$InstallerFileName`" /quiet /norestart"
                        Evidence = 'MSI bridge/wrapper — Burn-style quiet switches.'
                        ConfidenceBonus = 20
                    }) | Out-Null
                }
            }
            'msix' {
                $templates.Add(@{
                    Family = 'msix'
                    Command = "Add-AppxPackage -Path `"$InstallerFileName`""
                    Evidence = 'MSIX package install via Add-AppxPackage.'
                    ConfidenceBonus = 30
                }) | Out-Null
            }
            'appx' {
                $templates.Add(@{
                    Family = 'appx'
                    Command = "Add-AppxPackage -Path `"$InstallerFileName`""
                    Evidence = 'APPX package install via Add-AppxPackage.'
                    ConfidenceBonus = 30
                }) | Out-Null
            }
            default {
                if ($family -eq 'exe-unknown') {
                    $templates.Add(@{
                        Family = 'exe-unknown'
                        Command = "`"$InstallerFileName`" /S"
                        Evidence = 'Generic EXE fallback (/S).'
                        ConfidenceBonus = 10
                    }) | Out-Null
                }
            }
        }
    }

    if ($templates.Count -eq 0) {
        $templates.Add(@{
            Family = 'fallback'
            Command = "`"$InstallerFileName`" /S"
            Evidence = 'No family match — conservative /S fallback.'
            ConfidenceBonus = 10
        }) | Out-Null
    }

    return @($templates)
}

function Find-InstallerSwitchCandidates {
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Fingerprint,
        [hashtable]$InstallSwitchesInfo,
        [string]$InstallerExtension
    )

    $candidates = [System.Collections.Generic.List[hashtable]]::new()
    $baseConfidence = $Fingerprint.Confidence

    foreach ($nested in Get-NestedInstallerCandidates -Fingerprint $Fingerprint) {
        $candidates.Add(@{
            Command = $nested.Command
            Family = $nested.Family
            Evidence = @($nested.Evidence)
            Confidence = [math]::Min(100, $baseConfidence + $nested.ConfidenceBonus)
            Source = 'nested-payload'
        }) | Out-Null
    }

    foreach ($template in Get-InstallerFamilyCommandTemplates -InstallerFileName $Fingerprint.InstallerFileName -Families $Fingerprint.Families) {
        $existing = $candidates | Where-Object { $_.Command -eq $template.Command }
        if ($existing) { continue }

        $candidates.Add(@{
            Command = $template.Command
            Family = $template.Family
            Evidence = @($template.Evidence) + $Fingerprint.DetectionEvidence
            Confidence = [math]::Min(100, $baseConfidence + $template.ConfidenceBonus)
            Source = 'family-template'
        }) | Out-Null
    }

    if ($InstallSwitchesInfo -and $InstallSwitchesInfo.InstallSwitches.Count -gt 0) {
        $webCommand = Get-WebDerivedInstallCommand -InstallerFileName $Fingerprint.InstallerFileName `
            -InstallerExtension $InstallerExtension -InstallSwitchesInfo $InstallSwitchesInfo

        if ($webCommand) {
            $candidates.Add(@{
                Command = $webCommand.Command
                Family = 'vendor-docs'
                Evidence = @($webCommand.Evidence) + @('Support/documentation page scan.')
                Confidence = [math]::Min(100, $baseConfidence + $webCommand.ConfidenceBonus)
                Source = 'vendor-docs'
                SourceUrl = $webCommand.SourceUrl
            }) | Out-Null
        }
    }

    if ($Fingerprint.Families.Count -gt 2) {
        foreach ($candidate in $candidates) {
            $candidate.Confidence = [math]::Max(0, $candidate.Confidence - 20)
            $candidate.Evidence += 'Conflicting installer-family markers lowered confidence.'
        }
    }

  return @(
        $candidates |
            ForEach-Object {
                [PSCustomObject]$_
            } |
            Sort-Object Confidence -Descending
    )
}

function Get-WebDerivedInstallCommand {
    param(
        [string]$InstallerFileName,
        [string]$InstallerExtension,
        [hashtable]$InstallSwitchesInfo
    )

    if (-not $InstallSwitchesInfo -or $InstallSwitchesInfo.InstallSwitches.Count -eq 0) {
        return $null
    }

    $switchText = ($InstallSwitchesInfo.InstallSwitches -join ' ')

    if ($switchText -match 'msiexec\s+/i\s+["'']?[^"'']+\.(msi|exe)["'']?\s+(/qn|/quiet|/qb)') {
        return @{
            Command = ($matches[0] -replace '["'']', '"')
            Evidence = 'Vendor documentation contains explicit msiexec install command.'
            ConfidenceBonus = 50
            SourceUrl = $InstallSwitchesInfo.SourceUrl
        }
    }

    if ($InstallerExtension -eq '.msi' -and ($switchText -match '/qn|/quiet|/qb')) {
        $quietSwitch = if ($switchText -match '/qn') { '/qn' } elseif ($switchText -match '/quiet') { '/quiet' } else { '/qb' }
        return @{
            Command = "msiexec /i `"$InstallerFileName`" $quietSwitch /norestart"
            Evidence = "Vendor documentation references MSI quiet switch $quietSwitch."
            ConfidenceBonus = 50
            SourceUrl = $InstallSwitchesInfo.SourceUrl
        }
    }

    $detectedSwitch = Get-DetectedSilentSwitch -InstallSwitchesInfo $InstallSwitchesInfo
    if ($detectedSwitch) {
        return @{
            Command = "`"$InstallerFileName`" $detectedSwitch"
            Evidence = "Vendor documentation references silent switch $detectedSwitch."
            ConfidenceBonus = 40
            SourceUrl = $InstallSwitchesInfo.SourceUrl
        }
    }

    if ($switchText -match '/passive|/layout|/norestart') {
        $switches = @()
        if ($switchText -match '/quiet') { $switches += '/quiet' }
        elseif ($switchText -match '/passive') { $switches += '/passive' }
        if ($switchText -match '/norestart') { $switches += '/norestart' }
        if ($switches.Count -gt 0) {
            return @{
                Command = "`"$InstallerFileName`" $($switches -join ' ')"
                Evidence = 'Vendor documentation references bootstrapper switches.'
                ConfidenceBonus = 35
                SourceUrl = $InstallSwitchesInfo.SourceUrl
            }
        }
    }

    return $null
}

function Resolve-InstallerInstallCommand {
    param(
        [Parameter(Mandatory = $true)]
        [string]$InstallerPath,
        [string]$InstallerFileName,
        [string]$InstallerExtension,
        [hashtable]$InstallSwitchesInfo,
        [string]$SupportUrl
    )

    if ([string]::IsNullOrWhiteSpace($InstallerFileName)) {
        $InstallerFileName = Split-Path -Leaf $InstallerPath
    }

    if ([string]::IsNullOrWhiteSpace($InstallerExtension)) {
        $InstallerExtension = [System.IO.Path]::GetExtension($InstallerFileName).ToLower()
    }

    if ($InstallSwitchesInfo -and $SupportUrl -and -not $InstallSwitchesInfo.SourceUrl) {
        $InstallSwitchesInfo.SourceUrl = $SupportUrl
    }

    Write-AppGetterLog -Message "Discovering silent install switches for $InstallerFileName"

    $fingerprint = Get-InstallerFingerprint -InstallerPath $InstallerPath -InstallerFileName $InstallerFileName
    $candidates = Find-InstallerSwitchCandidates -Fingerprint $fingerprint -InstallSwitchesInfo $InstallSwitchesInfo `
        -InstallerExtension $InstallerExtension

    $topCandidate = if ($candidates.Count -gt 0) { $candidates[0] } else { $null }

    if (-not $topCandidate) {
        $fallbackCommand = Get-InstallerInstallCommand -InstallerFileName $InstallerFileName `
            -InstallerExtension $InstallerExtension -DetectedSwitch (Get-DetectedSilentSwitch -InstallSwitchesInfo $InstallSwitchesInfo)

        Write-AppGetterLog -Message 'No switch candidates ranked; using legacy fallback command.' -Level Warning

        return [PSCustomObject]@{
            RecommendedCommand   = $fallbackCommand
            AlternativeCommands  = @()
            ConfidenceScore      = 25
            EvidenceSummary      = @('Legacy fallback used because discovery produced no candidates.')
            NeedsManualReview    = $true
            Verified             = $false
            PrimaryType          = $fingerprint.PrimaryType
            InstallerFamilies    = $fingerprint.Families
            Fingerprint          = $fingerprint
            Candidates           = @()
        }
    }

    $confidenceThreshold = 70
    $needsManualReview = $topCandidate.Confidence -lt $confidenceThreshold
    $isWindows = $IsWindows -or ($PSVersionTable.Platform -eq 'Win32NT')

    $evidenceSummary = @(
        "Primary type: $($fingerprint.PrimaryType)"
        "Detected families: $($fingerprint.Families -join ', ')"
    ) + @($topCandidate.Evidence | Select-Object -Unique)

    if ($needsManualReview) {
        Write-AppGetterLog -Message "Silent install confidence $($topCandidate.Confidence) is below threshold $confidenceThreshold; manual review recommended." -Level Warning
    }
    else {
        Write-AppGetterLog -Message "Selected silent install command (confidence $($topCandidate.Confidence)): $($topCandidate.Command)" -Level Success
    }

    if (-not $isWindows) {
        Write-AppGetterLog -Message 'Runtime verification skipped (non-Windows host). Command marked unverified.' -Level Warning
    }

    $alternatives = @($candidates | Select-Object -Skip 1 | ForEach-Object { $_.Command })

    return [PSCustomObject]@{
        RecommendedCommand   = $topCandidate.Command
        AlternativeCommands  = $alternatives
        ConfidenceScore      = $topCandidate.Confidence
        EvidenceSummary      = $evidenceSummary
        NeedsManualReview    = $needsManualReview
        Verified             = $false
        PrimaryType          = $fingerprint.PrimaryType
        InstallerFamilies    = $fingerprint.Families
        SelectedFamily       = $topCandidate.Family
        SelectedSource       = $topCandidate.Source
        Fingerprint          = $fingerprint
        Candidates           = $candidates
    }
}

function Test-ByteSequence {
    param(
        [byte[]]$Bytes,
        [byte[]]$Pattern,
        [switch]$AtStart
    )

    if (-not $Bytes -or -not $Pattern -or $Bytes.Length -lt $Pattern.Length) {
        return $false
    }

    if ($AtStart) {
        for ($i = 0; $i -lt $Pattern.Length; $i++) {
            if ($Bytes[$i] -ne $Pattern[$i]) { return $false }
        }
        return $true
    }

    return $null -ne (Find-ByteSequenceOffset -Bytes $Bytes -Pattern $Pattern)
}

function Find-ByteSequenceOffset {
    param(
        [byte[]]$Bytes,
        [byte[]]$Pattern,
        [switch]$SkipStart
    )

    if (-not $Bytes -or -not $Pattern -or $Bytes.Length -lt $Pattern.Length) {
        return $null
    }

    $startIndex = if ($SkipStart) { $Pattern.Length } else { 0 }
    for ($i = $startIndex; $i -le ($Bytes.Length - $Pattern.Length); $i++) {
        $matched = $true
        for ($j = 0; $j -lt $Pattern.Length; $j++) {
            if ($Bytes[$i + $j] -ne $Pattern[$j]) {
                $matched = $false
                break
            }
        }
        if ($matched) { return $i }
    }

    return $null
}

function Get-InstallerAsciiText {
    param(
        [byte[]]$Bytes,
        [int]$MaxLength = 4194304
    )

    $length = [math]::Min($Bytes.Length, $MaxLength)
    $builder = [System.Text.StringBuilder]::new()

    for ($i = 0; $i -lt $length; $i++) {
        $byte = $Bytes[$i]
        if ($byte -ge 32 -and $byte -le 126) {
            [void]$builder.Append([char]$byte)
        }
        else {
            [void]$builder.Append(' ')
        }
    }

    return $builder.ToString()
}
