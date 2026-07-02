$script:InstallerFamilySignatures = @(
    @{ Name = 'InnoSetup'; Patterns = @('Inno Setup Setup Data', 'Inno Setup Messages', 'jrsoftware.org', '/VERYSILENT', '/SUPPRESSMSGBOXES') }
    @{ Name = 'NSIS'; Patterns = @('Nullsoft Install System', 'NSIS Error', 'NullsoftInst') }
    @{ Name = 'InstallShield'; Patterns = @('InstallShield', 'ISSetup', 'Setup Launcher for InstallShield', 'setup.iss') }
    @{ Name = 'WiXBurn'; Patterns = @('WiX Toolset', 'burn engine', 'WixBundle', '.wixburn', 'BootstrapperApplication') }
    @{ Name = 'Squirrel'; Patterns = @('Squirrel', 'Update.exe') }
)

$script:FamilyInstallTemplates = @{
    MSI           = 'msiexec /i "{0}" /qn /norestart'
    InnoSetup     = '"{0}" /VERYSILENT /SUPPRESSMSGBOXES /NORESTART /SP-'
    NSIS          = '"{0}" /S'
    InstallShield = '"{0}" /s /v"/qn /norestart"'
    WiXBurn       = '"{0}" /quiet /norestart'
    Squirrel      = '"{0}" --silent'
    MSIX          = 'Add-AppxPackage -Path "{0}"'
    APPX          = 'Add-AppxPackage -Path "{0}"'
    EXE_Generic   = '"{0}" /S'
}

$script:FamilyDefaultSwitches = @{
    MSI           = @('/qn', '/norestart')
    InnoSetup     = @('/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART', '/SP-')
    NSIS          = @('/S')
    InstallShield = @('/s', '/v"/qn /norestart"')
    WiXBurn       = @('/quiet', '/norestart')
    Squirrel      = @('--silent')
    EXE_Generic   = @('/S')
}

$script:MsiOleSignature = [byte[]](0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1)

function Test-InstallerMsiSignature {
    param([byte[]]$Bytes)

    if (-not $Bytes -or $Bytes.Length -lt $script:MsiOleSignature.Length) {
        return $false
    }

    for ($i = 0; $i -le ($Bytes.Length - $script:MsiOleSignature.Length); $i++) {
        $matched = $true
        for ($j = 0; $j -lt $script:MsiOleSignature.Length; $j++) {
            if ($Bytes[$i + $j] -ne $script:MsiOleSignature[$j]) {
                $matched = $false
                break
            }
        }
        if ($matched) { return $true }
    }

    return $false
}

function Get-InstallerFingerprint {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$InstallerPath
    )

    if (-not (Test-Path $InstallerPath)) {
        throw "Installer not found: $InstallerPath"
    }

    $file = Get-Item $InstallerPath
    $extension = $file.Extension.ToLowerInvariant()
    $fileName = $file.Name
    $evidence = [System.Collections.Generic.List[string]]::new()
    $matchedFamilies = [System.Collections.Generic.List[string]]::new()

    $bytes = $null
    $asciiText = $null

    if ($extension -in '.msi', '.msix', '.appx') {
        $primaryType = switch ($extension) {
            '.msi' { 'msi' }
            '.msix' { 'msix' }
            '.appx' { 'appx' }
        }
        $evidence.Add("Extension indicates $primaryType container.")
        return [PSCustomObject]@{
            PrimaryType       = $primaryType
            InstallerFamily   = switch ($primaryType) { 'msi' { 'MSI' } 'msix' { 'MSIX' } default { 'APPX' } }
            FileName          = $fileName
            Extension         = $extension
            DetectionEvidence = $evidence
            MatchedFamilies   = @($(switch ($primaryType) { 'msi' { 'MSI' } 'msix' { 'MSIX' } default { 'APPX' } }))
            Confidence        = 90
            HasMsiSignature   = ($primaryType -eq 'msi')
        }
    }

    $bytes = [System.IO.File]::ReadAllBytes($InstallerPath)
    $asciiText = [System.Text.Encoding]::ASCII.GetString($bytes)

    if (Test-InstallerMsiSignature -Bytes $bytes) {
        $evidence.Add('MSI OLE compound document signature found in file bytes.')
        return [PSCustomObject]@{
            PrimaryType       = 'msi'
            InstallerFamily   = 'MSI'
            FileName          = $fileName
            Extension         = $extension
            DetectionEvidence = $evidence
            MatchedFamilies   = @('MSI')
            Confidence        = 95
            HasMsiSignature   = $true
        }
    }

    foreach ($sig in $script:InstallerFamilySignatures) {
        foreach ($pattern in $sig.Patterns) {
            if ($asciiText -like "*$pattern*") {
                if ($matchedFamilies -notcontains $sig.Name) {
                    $matchedFamilies.Add($sig.Name)
                    $evidence.Add("Matched $($sig.Name) marker: $pattern")
                }
            }
        }
    }

    if ($asciiText -match 'MsiInstallProduct|msi\.dll|msiexec') {
        $evidence.Add('Found MSI bridge markers (MsiInstallProduct/msi.dll/msiexec).')
        if ($matchedFamilies -notcontains 'InstallShield') {
            $matchedFamilies.Add('InstallShield')
        }
    }

    $primaryType = 'exe'
    $installerFamily = if ($matchedFamilies.Count -eq 1) {
        $matchedFamilies[0]
    } elseif ($matchedFamilies.Count -gt 1) {
        $matchedFamilies[0]
    } else {
        'EXE_Generic'
    }

    $confidence = switch ($matchedFamilies.Count) {
        0 { 35 }
        1 { 75 }
        default { 55 }
    }

    if ($matchedFamilies.Count -gt 1) {
        $evidence.Add("Multiple installer families detected: $($matchedFamilies -join ', ').")
    }

    return [PSCustomObject]@{
        PrimaryType       = $primaryType
        InstallerFamily   = $installerFamily
        FileName          = $fileName
        Extension         = $extension
        DetectionEvidence = $evidence
        MatchedFamilies   = @($matchedFamilies)
        Confidence        = $confidence
        HasMsiSignature   = $false
    }
}

function Get-NestedInstallerCandidates {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$InstallerPath,
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Fingerprint
    )

    $candidates = [System.Collections.Generic.List[object]]::new()
    $bytes = [System.IO.File]::ReadAllBytes($InstallerPath)
    $asciiText = [System.Text.Encoding]::ASCII.GetString($bytes)

    if ($Fingerprint.PrimaryType -eq 'msi') {
        if ($asciiText -match '\.exe|setup\.exe|install\.exe') {
            $candidates.Add([PSCustomObject]@{
                Type       = 'NestedExecutableReference'
                Evidence   = 'MSI container references embedded executable setup patterns.'
                Confidence = 40
            })
        }
        return @($candidates)
    }

    if (Test-InstallerMsiSignature -Bytes $bytes) {
        $candidates.Add([PSCustomObject]@{
            Type       = 'EmbeddedMsi'
            Evidence   = 'MSI OLE signature found inside EXE wrapper.'
            Confidence = 80
            PreferMsi  = $true
        })
    }

    if ($asciiText -match 'MsiInstallProduct|_MSIExecute|msiexec /i') {
        $candidates.Add([PSCustomObject]@{
            Type       = 'MsiBridge'
            Evidence   = 'Binary contains MSI installation API references.'
            Confidence = 65
            PreferMsi  = $true
        })
    }

    return @($candidates)
}

function Get-InstallCommandFromFamily {
    param(
        [string]$InstallerFileName,
        [string]$InstallerFamily,
        [string[]]$SelectedSwitches
    )

    if ($script:FamilyInstallTemplates.ContainsKey($InstallerFamily)) {
        $template = $script:FamilyInstallTemplates[$InstallerFamily]
        return ($template -f $InstallerFileName)
    }

    $switchText = if ($SelectedSwitches -and $SelectedSwitches.Count -gt 0) {
        ($SelectedSwitches | Select-Object -Unique) -join ' '
    } else {
        '/S'
    }

    return "`"$InstallerFileName`" $switchText"
}

function Find-InstallerSwitchCandidates {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$InstallerPath,
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Fingerprint,
        [array]$NestedCandidates = @(),
        [hashtable]$InstallSwitchesInfo,
        [string]$AppName
    )

    $installerFileName = $Fingerprint.FileName
    $candidates = [System.Collections.Generic.List[object]]::new()

    $familiesToEvaluate = if ($Fingerprint.MatchedFamilies -and $Fingerprint.MatchedFamilies.Count -gt 0) {
        $Fingerprint.MatchedFamilies
    } else {
        @($Fingerprint.InstallerFamily)
    }

    foreach ($family in ($familiesToEvaluate | Select-Object -Unique)) {
        $score = 10
        $evidence = @("Known family default for $family.")

        if ($family -eq $Fingerprint.InstallerFamily -and $Fingerprint.Confidence -ge 70) {
            $score += 30
            $evidence += 'Strong binary fingerprint match.'
        }

        if ($NestedCandidates | Where-Object { $_.PreferMsi -and $family -eq 'InstallShield' }) {
            $score += 20
            $evidence += 'Nested MSI evidence supports InstallShield MSI passthrough.'
        }

        if ($NestedCandidates | Where-Object { $_.PreferMsi -and $family -eq 'MSI' }) {
            $score += 20
            $evidence += 'Embedded MSI detected; direct MSI install preferred.'
            $family = 'MSI'
        }

        $switches = if ($script:FamilyDefaultSwitches.ContainsKey($family)) {
            $script:FamilyDefaultSwitches[$family]
        } else {
            @('/S')
        }

        $candidates.Add([PSCustomObject]@{
            InstallerFamily = $family
            Switches        = $switches
            InstallCommand  = Get-InstallCommandFromFamily -InstallerFileName $installerFileName -InstallerFamily $family -SelectedSwitches $switches
            Score           = $score
            Source          = 'FamilyDefault'
            Evidence        = ($evidence -join ' ')
        })
    }

    if ($InstallSwitchesInfo -and $InstallSwitchesInfo.InstallSwitches.Count -gt 0) {
        $switchText = $InstallSwitchesInfo.InstallSwitches -join ' '
        $extractedSwitches = [regex]::Matches($switchText, '(?i)(/VERYSILENT|/SILENT|/SUPPRESSMSGBOXES|/NORESTART|/SP-|/S\b|/quiet|/qn|/qb|/passive|--silent|/s\b)')

        foreach ($match in $extractedSwitches) {
            $sw = $match.Value
            $switchList = @($sw)
            $installCommand = "`"$installerFileName`" $($switchList -join ' ')"

            $candidates.Add([PSCustomObject]@{
                InstallerFamily = $Fingerprint.InstallerFamily
                Switches        = $switchList
                InstallCommand  = $installCommand
                Score           = 50
                Source          = 'VendorDocumentation'
                Evidence        = "Support page documents switch: $sw"
            })
        }
    }

    if ($candidates.Count -eq 0) {
        $candidates.Add([PSCustomObject]@{
            InstallerFamily = 'EXE_Generic'
            Switches        = @('/S')
            InstallCommand  = Get-InstallCommandFromFamily -InstallerFileName $installerFileName -InstallerFamily 'EXE_Generic'
            Score           = 10
            Source          = 'Fallback'
            Evidence        = 'No family markers found; using conservative /S fallback.'
        })
    }

    $uniqueCandidates = $candidates |
        Sort-Object Score -Descending |
        Group-Object InstallCommand |
        ForEach-Object { $_.Group | Select-Object -First 1 }

    return @($uniqueCandidates)
}

function Test-InstallerCommand {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$InstallerPath,
        [Parameter(Mandatory = $true)]
        [string]$InstallCommand,
        [int]$TimeoutSeconds = 30
    )

    if (-not $IsWindows) {
        return [PSCustomObject]@{
            Verified = $false
            Status   = 'Skipped'
            Message  = 'Runtime verification requires Windows.'
        }
    }

    if (-not (Test-Path $InstallerPath)) {
        throw "Installer not found: $InstallerPath"
    }

    try {
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = 'cmd.exe'
        $psi.Arguments = "/c $InstallCommand"
        $psi.UseShellExecute = $false
        $psi.CreateNoWindow = $true
        $psi.WorkingDirectory = Split-Path -Parent $InstallerPath

        $process = [System.Diagnostics.Process]::Start($psi)
        if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
            $process.Kill()
            return [PSCustomObject]@{
                Verified = $false
                Status   = 'Timeout'
                Message  = 'Installer did not exit within timeout; may require UI input.'
            }
        }

        $acceptedCodes = @(0, 3010, 1641, 1618)
        $verified = $process.ExitCode -in $acceptedCodes

        return [PSCustomObject]@{
            Verified = $verified
            Status   = if ($verified) { 'Success' } else { 'Failed' }
            ExitCode = $process.ExitCode
            Message  = "Exit code: $($process.ExitCode)"
        }
    }
    catch {
        return [PSCustomObject]@{
            Verified = $false
            Status   = 'Error'
            Message  = $_.Exception.Message
        }
    }
}

function Resolve-InstallerInstallCommand {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$InstallerPath,
        [hashtable]$InstallSwitchesInfo,
        [string]$AppName,
        [switch]$SkipVerification,
        [scriptblock]$OnProgress
    )

    Write-AppGetterLog -Message 'Analyzing installer for silent install switches' -Level Step -OnProgress $OnProgress

    $fingerprint = Get-InstallerFingerprint -InstallerPath $InstallerPath
    Write-AppGetterLog -Message "Detected installer family: $($fingerprint.InstallerFamily) (confidence $($fingerprint.Confidence))" `
        -OnProgress $OnProgress

    $nestedCandidates = Get-NestedInstallerCandidates -InstallerPath $InstallerPath -Fingerprint $fingerprint
    if ($nestedCandidates.Count -gt 0) {
        Write-AppGetterLog -Message "Nested payload signals: $($nestedCandidates.Count)" -OnProgress $OnProgress
    }

    $candidates = Find-InstallerSwitchCandidates -InstallerPath $InstallerPath -Fingerprint $fingerprint `
        -NestedCandidates $nestedCandidates -InstallSwitchesInfo $InstallSwitchesInfo -AppName $AppName

    $topCandidate = $candidates | Sort-Object Score -Descending | Select-Object -First 1
    $alternatives = @($candidates | Sort-Object Score -Descending | Select-Object -Skip 1)

    $confidenceScore = [math]::Min(100, [int]$topCandidate.Score)
    if ($fingerprint.Confidence -ge 75 -and $topCandidate.Source -eq 'FamilyDefault') {
        $confidenceScore = [math]::Min(100, $confidenceScore + 15)
    }
    if ($topCandidate.Source -eq 'VendorDocumentation') {
        $confidenceScore = [math]::Min(100, $confidenceScore + 10)
    }
    if ($fingerprint.MatchedFamilies.Count -gt 1) {
        $confidenceScore = [math]::Max(0, $confidenceScore - 20)
    }

    $verification = $null
    $verified = $false
    if (-not $SkipVerification) {
        $verification = Test-InstallerCommand -InstallerPath $InstallerPath -InstallCommand $topCandidate.InstallCommand
        $verified = $verification.Verified
        if ($verified) {
            $confidenceScore = [math]::Min(100, $confidenceScore + 25)
            Write-AppGetterLog -Message 'Silent install command verified on this host.' -Level Success -OnProgress $OnProgress
        } elseif ($verification.Status -eq 'Skipped') {
            Write-AppGetterLog -Message 'Runtime verification skipped (non-Windows host).' -Level Warning -OnProgress $OnProgress
        } else {
            Write-AppGetterLog -Message "Runtime verification not successful: $($verification.Message)" -Level Warning -OnProgress $OnProgress
        }
    }

    $needsManualReview = ($confidenceScore -lt 70) -or (-not $verified -and $verification -and $verification.Status -ne 'Skipped')
    if ($needsManualReview) {
        Write-AppGetterLog -Message "Silent install command needs manual review (confidence $confidenceScore)." -Level Warning -OnProgress $OnProgress
    } else {
        Write-AppGetterLog -Message "Selected install command (confidence $confidenceScore): $($topCandidate.InstallCommand)" `
            -Level Success -OnProgress $OnProgress
    }

    $evidenceSummary = @(
        $fingerprint.DetectionEvidence
        $topCandidate.Evidence
    ) | Where-Object { $_ } | Select-Object -Unique

    return [PSCustomObject]@{
        InstallCommand      = $topCandidate.InstallCommand
        ConfidenceScore     = $confidenceScore
        NeedsManualReview   = $needsManualReview
        Verified            = $verified
        InstallerFamily     = $topCandidate.InstallerFamily
        RecommendedCommand  = $topCandidate.InstallCommand
        AlternativeCommands = @($alternatives | ForEach-Object { $_.InstallCommand })
        Candidates          = $candidates
        Fingerprint         = $fingerprint
        NestedCandidates    = $nestedCandidates
        EvidenceSummary     = $evidenceSummary
        Verification        = $verification
    }
}
