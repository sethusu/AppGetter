BeforeAll {
    $moduleManifest = Join-Path $PSScriptRoot '..' 'AppGetter.psd1'
    Import-Module $moduleManifest -Force

    $script:licensingRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("appgetter-licensing-{0}" -f ([Guid]::NewGuid().ToString('N')))
    New-Item -ItemType Directory -Path $script:licensingRoot -Force | Out-Null

    function New-LicensingInstallerFixture {
        param(
            [string]$FileName,
            [byte[]]$Header,
            [string[]]$Markers
        )

        $bytes = [System.Collections.Generic.List[byte]]::new()
        $bytes.AddRange($Header)
        $bytes.AddRange([System.Text.Encoding]::ASCII.GetBytes("`0" + ($Markers -join "`0") + "`0"))
        $path = Join-Path $script:licensingRoot $FileName
        [System.IO.File]::WriteAllBytes($path, $bytes.ToArray())
        return $path
    }

    $oleHeader = [byte[]]@(0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1)
    $peHeader = [byte[]]@(0x4D, 0x5A, 0x90, 0x00)

    # Synthetic installers carrying only the licensing markers each test needs.
    $script:licensedMsi = New-LicensingInstallerFixture -FileName 'licensed-app.msi' -Header $oleHeader `
        -Markers @('Installer', 'ProductName', 'SERIALNUMBER', 'LicenseAgreement')
    $script:flexlmExe = New-LicensingInstallerFixture -FileName 'flexlm-setup.exe' -Header $peHeader `
        -Markers @('Inno Setup', '/VERYSILENT', '/SUPPRESSMSGBOXES', 'FLEXnet Licensing', 'lmgrd', 'license.dat')
    $script:dongleExe = New-LicensingInstallerFixture -FileName 'dongle-setup.exe' -Header $peHeader `
        -Markers @('Nullsoft Install System', 'Sentinel LDK', 'haspds_windows.dll')
    $script:plainExe = New-LicensingInstallerFixture -FileName 'plain-setup.exe' -Header $peHeader `
        -Markers @('Nullsoft Install System', 'NSIS Error')

    $script:licenseFile = Join-Path $script:licensingRoot 'license.dat'
    Set-Content -LiteralPath $script:licenseFile -Value 'SERVER lm.corp.local ANY 27000' -Encoding ascii

    # 1x1 PNG so end-to-end packaging never reaches out to the network for an icon.
    $script:iconFile = Join-Path $script:licensingRoot 'icon.png'
    [System.IO.File]::WriteAllBytes($script:iconFile, [Convert]::FromBase64String(
            'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8DwHwAFAAH/q842iQAAAABJRU5ErkJggg=='))
}

AfterAll {
    if ($script:licensingRoot -and (Test-Path -LiteralPath $script:licensingRoot)) {
        Remove-Item -LiteralPath $script:licensingRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Describe 'Licensing pattern catalog' {
    It 'Exposes unique pattern ids' {
        $ids = @((Get-AppGetterLicensingPatternCatalog).Id)
        $ids.Count | Should -BeGreaterThan 10
        ($ids | Select-Object -Unique).Count | Should -Be $ids.Count
    }

    It 'Declares a known activation method and assignment for every pattern' {
        $activationMethods = @('none', 'key', 'licensefile', 'licenseserver', 'signin', 'dongle', 'volume', 'trial')
        foreach ($pattern in (Get-AppGetterLicensingPatternCatalog)) {
            $pattern.ActivationMethod | Should -BeIn $activationMethods
            $pattern.AssignmentRecommendation | Should -BeIn @('required', 'available')
            $pattern.RequiredArtifact | Should -BeIn @('none', 'key', 'optional-key', 'server', 'file')
            $pattern.Markers.Count | Should -BeGreaterThan 0
            $pattern.LicenseType | Should -Not -BeNullOrEmpty
            $pattern.Guidance | Should -Not -BeNullOrEmpty
        }
    }
}

Describe 'Classifying the ServiceNow licensing field' {
    It 'Identifies <expected> from "<field>"' -ForEach @(
        @{ Field = 'Licensed - per device, perpetual. License key: 4XJ9-2210-KD77-9931'; Expected = 'device-perpetual'; Activation = 'key' }
        @{ Field = 'Concurrent / floating license via FlexLM. License server 27000@lm.corp.local'; Expected = 'concurrent-floating'; Activation = 'licenseserver' }
        @{ Field = 'Freeware - no license required for internal use'; Expected = 'freeware'; Activation = 'none' }
        @{ Field = 'Open source (MIT License)'; Expected = 'open-source'; Activation = 'none' }
        @{ Field = '30-day trial / evaluation only'; Expected = 'trial'; Activation = 'trial' }
        @{ Field = 'Per user subscription (Microsoft 365), assigned to user'; Expected = 'subscription-user'; Activation = 'signin' }
        @{ Field = 'Site license - campus wide, unlimited installs'; Expected = 'site-enterprise'; Activation = 'key' }
        @{ Field = 'Requires HASP USB dongle attached to the workstation'; Expected = 'dongle-hardware'; Activation = 'dongle' }
        @{ Field = 'MAK volume activation through KMS'; Expected = 'volume-activation'; Activation = 'volume' }
        @{ Field = 'Per core licensing, 16 cores'; Expected = 'core-processor'; Activation = 'key' }
        @{ Field = 'OEM - bundled with hardware'; Expected = 'oem-bundled'; Activation = 'none' }
        @{ Field = 'Purchased license key required for activation'; Expected = 'paid-key'; Activation = 'key' }
    ) {
        $resolved = Resolve-AppGetterLicensing -LicenseInfo $Field
        $resolved.PatternId | Should -Be $expected
        $resolved.ActivationMethod | Should -Be $activation
        $resolved.Classified | Should -Be $true
        $resolved.ConfidenceScore | Should -BeGreaterThan 0
    }

    It 'Prefers trial over freeware when the field says free trial' {
        $resolved = Resolve-AppGetterLicensing -LicenseInfo 'Free 30-day trial download'
        $resolved.PatternId | Should -Be 'trial'
    }

    It 'Flags an empty licensing field as unclassified and needing review' {
        $resolved = Resolve-AppGetterLicensing -LicenseInfo ''
        $resolved.PatternId | Should -Be 'unknown'
        $resolved.Classified | Should -Be $false
        $resolved.NeedsManualReview | Should -Be $true
        $resolved.ConfidenceScore | Should -Be 0
    }

    It 'Flags licensing text with no recognizable terms as unknown' {
        $resolved = Resolve-AppGetterLicensing -LicenseInfo 'Ask the vendor'
        $resolved.PatternId | Should -Be 'unknown'
        $resolved.NeedsManualReview | Should -Be $true
    }

    It 'Returns the same pattern for the same field on every run' {
        $field = 'Per device perpetual, concurrent seats also available'
        $first = Resolve-AppGetterLicensing -LicenseInfo $field
        $second = Resolve-AppGetterLicensing -LicenseInfo $field
        $second.PatternId | Should -Be $first.PatternId
        $second.ConfidenceScore | Should -Be $first.ConfidenceScore
    }

    It 'Lets an explicit license type override the licensing text' {
        $resolved = Resolve-AppGetterLicensing -LicenseInfo 'Freeware, no license needed' -LicenseType 'Concurrent'
        $resolved.PatternId | Should -Be 'concurrent-floating'
        ($resolved.EvidenceSummary -join ' ') | Should -Match 'Explicit license type'
    }

    It 'Strips HTML markup out of a licensing field copied from a ServiceNow form' {
        $resolved = Resolve-AppGetterLicensing -LicenseInfo '<p>Concurrent&nbsp;license server 27000@lm.corp.local</p>'
        $resolved.PatternId | Should -Be 'concurrent-floating'
        $resolved.LicenseServer | Should -Be '27000@lm.corp.local'
        $resolved.RawLicenseInfo | Should -Not -Match '<p>'
    }
}

Describe 'Mapping ServiceNow license type values' {
    It 'Maps "<value>" to <expected>' -ForEach @(
        @{ Value = 'Per user'; Expected = 'subscription-user' }
        @{ Value = 'Named user'; Expected = 'subscription-user' }
        @{ Value = 'Per device'; Expected = 'device-perpetual' }
        @{ Value = 'Per seat'; Expected = 'device-perpetual' }
        @{ Value = 'Concurrent'; Expected = 'concurrent-floating' }
        @{ Value = 'Per core'; Expected = 'core-processor' }
        @{ Value = 'Site license'; Expected = 'site-enterprise' }
        @{ Value = 'MAK'; Expected = 'volume-activation' }
        @{ Value = 'Freeware'; Expected = 'freeware' }
        @{ Value = 'Open source'; Expected = 'open-source' }
        @{ Value = 'Trial'; Expected = 'trial' }
        @{ Value = 'OEM'; Expected = 'oem-bundled' }
        @{ Value = 'device-perpetual'; Expected = 'device-perpetual' }
        @{ Value = 'Per device (perpetual)'; Expected = 'device-perpetual' }
    ) {
        Resolve-AppGetterLicenseTypeToPatternId -LicenseType $value | Should -Be $expected
    }

    It 'Returns nothing for an unmapped or empty value' {
        Resolve-AppGetterLicenseTypeToPatternId -LicenseType '' | Should -BeNullOrEmpty
        Resolve-AppGetterLicenseTypeToPatternId -LicenseType 'Something bespoke' | Should -BeNullOrEmpty
    }
}

Describe 'Extracting licensing details from the field' {
    It 'Pulls out the key, seat count, and expiry' {
        $details = Get-AppGetterLicenseDetailsFromText -Text 'Per device. 25 seats purchased. License key: 4XJ9-2210-KD77-9931. Expires 2028-03-31.'
        $details.LicenseKey | Should -Be '4XJ9-2210-KD77-9931'
        $details.LicenseQuantity | Should -Be 25
        $details.LicenseExpiry | Should -Be '2028-03-31'
    }

    It 'Does not mistake prose for a license key' {
        foreach ($text in @('License key: required', 'Product key is pending', 'Serial number: unknown')) {
            (Get-AppGetterLicenseDetailsFromText -Text $text).LicenseKey | Should -BeNullOrEmpty
        }
    }

    It 'Reads a license server without absorbing sentence punctuation' {
        $details = Get-AppGetterLicenseDetailsFromText -Text 'Floating license. License server 27000@lm.corp.local. Ten seats.'
        $details.LicenseServer | Should -Be '27000@lm.corp.local'
    }

    It 'Reads a bare port@host token' {
        (Get-AppGetterLicenseDetailsFromText -Text 'Served from 1055@flex01.corp.example').LicenseServer | Should -Be '1055@flex01.corp.example'
    }

    It 'Reads a vendor license environment variable named in the field' {
        (Get-AppGetterLicenseDetailsFromText -Text 'Set RLM_LICENSE to the server').LicenseServerVariable | Should -Be 'RLM_LICENSE'
    }

    It 'Reads the license file name and its destination' {
        $details = Get-AppGetterLicenseDetailsFromText -Text 'Copy license.dat to C:\ProgramData\Vendor\license.dat before launch'
        $details.LicenseFileName | Should -Be 'license.dat'
        $details.LicenseFileTargetPath | Should -Be 'C:\ProgramData\Vendor\license.dat'
    }

    It 'Detects an approval or chargeback requirement' {
        (Get-AppGetterLicenseDetailsFromText -Text 'Requires manager approval and a cost center').RequiresApproval | Should -Be $true
        (Get-AppGetterLicenseDetailsFromText -Text 'Freeware').RequiresApproval | Should -Be $false
    }

    It 'Returns empty details for an empty field' {
        $details = Get-AppGetterLicenseDetailsFromText -Text ''
        $details.LicenseKey | Should -BeNullOrEmpty
        $details.LicenseServer | Should -BeNullOrEmpty
        $details.RequiresApproval | Should -Be $false
    }
}

Describe 'Protecting license keys' {
    It 'Masks the middle of a key and keeps only the outer characters' {
        InModuleScope AppGetter {
            $masked = Protect-AppGetterLicenseKey -LicenseKey '4XJ9-2210-KD77-9931'
            $masked | Should -Match '^4XJ9\*+9931$'
            $masked | Should -Not -Match '2210'
        }
    }

    It 'Masks a short key completely' {
        InModuleScope AppGetter {
            Protect-AppGetterLicenseKey -LicenseKey 'ABC123' | Should -Be '******'
        }
    }

    It 'Redacts the key out of the licensing text kept in metadata' {
        $resolved = Resolve-AppGetterLicensing -LicenseInfo 'Per device. License key: 4XJ9-2210-KD77-9931'
        $resolved.RedactedLicenseInfo | Should -Not -Match '2210-KD77'
        $resolved.LicenseKeyMasked | Should -Not -Match '2210'
        $resolved.LicenseKey | Should -Be '4XJ9-2210-KD77-9931'
    }

    It 'Removes the plaintext key from the object handed back to callers' {
        InModuleScope AppGetter {
            $resolved = Resolve-AppGetterLicensing -LicenseInfo 'Per device. License key: 4XJ9-2210-KD77-9931'
            $sanitized = Get-AppGetterSanitizedLicensing -Licensing $resolved
            $sanitized.LicenseKey | Should -BeNullOrEmpty
            $sanitized.LicenseKeyMasked | Should -Be $resolved.LicenseKeyMasked
            $sanitized.HasLicenseKey | Should -Be $true
        }
    }
}

Describe 'Corroborating licensing with installer evidence' {
    It 'Raises the floating-license pattern for an installer carrying FlexNet strings' {
        $resolved = Resolve-AppGetterLicensing -LicenseInfo 'Licensed software' -InstallerPath $script:flexlmExe
        $resolved.PatternId | Should -Be 'concurrent-floating'
        $resolved.LicenseServerVariable | Should -Be 'LM_LICENSE_FILE'
        ($resolved.EvidenceSummary -join ' ') | Should -Match 'FlexNet'
    }

    It 'Raises the dongle pattern for an installer carrying Sentinel/HASP strings' {
        $resolved = Resolve-AppGetterLicensing -LicenseInfo 'Licensed software' -InstallerPath $script:dongleExe
        $resolved.PatternId | Should -Be 'dongle-hardware'
        $resolved.ActivationMethod | Should -Be 'dongle'
    }

    It 'Detects the installer property that accepts a license key' {
        $resolved = Resolve-AppGetterLicensing -LicenseInfo 'Per device, license key 4XJ9-2210-KD77-9931' `
            -InstallerPath $script:licensedMsi
        $resolved.LicenseKeyPropertyName | Should -Be 'SERIALNUMBER'
    }

    It 'Reports no key property for an installer that exposes none' {
        $resolved = Resolve-AppGetterLicensing -LicenseInfo 'Per device, license key 4XJ9-2210-KD77-9931' `
            -InstallerPath $script:plainExe
        $resolved.LicenseKeyPropertyName | Should -BeNullOrEmpty
    }

    It 'Reuses a fingerprint from switch discovery instead of re-reading the installer' {
        $fingerprint = Get-InstallerFingerprint -InstallerPath $script:flexlmExe
        $resolved = Resolve-AppGetterLicensing -LicenseInfo 'Licensed software' -Fingerprint $fingerprint
        $resolved.PatternId | Should -Be 'concurrent-floating'
    }

    It 'Does not classify from installer evidence alone when no licensing field was supplied' {
        $resolved = Resolve-AppGetterLicensing -InstallerPath $script:flexlmExe
        $resolved.Classified | Should -Be $false
        $resolved.NeedsManualReview | Should -Be $true
    }
}

Describe 'Selecting a pattern from a supplied artifact' {
    It 'Chooses the license-file pattern when a license file is supplied for a vague field' {
        $resolved = Resolve-AppGetterLicensing -LicenseInfo 'Licensed' -LicenseFilePath $script:licenseFile
        $resolved.PatternId | Should -Be 'license-file'
        $resolved.LicenseFileName | Should -Be 'license.dat'
    }

    It 'Chooses the floating pattern when only a license server is supplied' {
        $resolved = Resolve-AppGetterLicensing -LicenseInfo 'Licensed' -LicenseServer '27000@lm.corp.local'
        $resolved.PatternId | Should -Be 'concurrent-floating'
        $resolved.LicenseServerVariable | Should -Be 'LM_LICENSE_FILE'
    }

    It 'Lets explicit parameters win over values parsed from the field' {
        $resolved = Resolve-AppGetterLicensing `
            -LicenseInfo 'Concurrent, license server 27000@old.corp.local, key 1111-2222-3333' `
            -LicenseServer '27009@new.corp.local' -LicenseKey 'AAAA-9999-BBBB' -LicenseServerVariable 'MYAPP_LICENSE_FILE'
        $resolved.LicenseServer | Should -Be '27009@new.corp.local'
        $resolved.LicenseKey | Should -Be 'AAAA-9999-BBBB'
        $resolved.LicenseServerVariable | Should -Be 'MYAPP_LICENSE_FILE'
    }

    It 'Reports the artifact a pattern still needs' {
        $resolved = Resolve-AppGetterLicensing -LicenseInfo 'Concurrent floating license, checked out at launch'
        $resolved.MissingArtifacts | Should -Contain 'license server (port@host)'
        $resolved.NeedsManualReview | Should -Be $true
    }
}

Describe 'Recommending an Intune assignment' {
    It 'Recommends Required where the license covers the device' {
        (Resolve-AppGetterLicensing -LicenseInfo 'Freeware').AssignmentRecommendation | Should -Be 'required'
        (Resolve-AppGetterLicensing -LicenseInfo 'Site license, campus wide').AssignmentRecommendation | Should -Be 'required'
    }

    It 'Recommends Available where a seat is consumed per user' {
        (Resolve-AppGetterLicensing -LicenseInfo 'Per user subscription, named user').AssignmentRecommendation | Should -Be 'available'
    }

    It 'Downgrades a Required pattern to Available when the field demands approval' {
        $resolved = Resolve-AppGetterLicensing -LicenseInfo 'Per device perpetual. Requires manager approval.'
        $resolved.AssignmentRecommendation | Should -Be 'available'
        $resolved.Guidance | Should -Match 'Available behind the request flow'
    }

    It 'Turns seat counts and expiry dates into compliance notes' {
        $resolved = Resolve-AppGetterLicensing -LicenseInfo 'Per device, 25 seats, expires 2028-03-31'
        ($resolved.ComplianceNotes -join ' ') | Should -Match '25 seat'
        ($resolved.ComplianceNotes -join ' ') | Should -Match '2028-03-31'
    }
}

Describe 'Applying a license key to the install command' {
    It 'Appends the detected property to an msiexec command line' {
        $result = Add-AppGetterLicenseInstallArgument `
            -InstallCommand 'msiexec /i "app.msi" /qn /norestart' `
            -InstallerFamily 'msi' -PropertyName 'SERIALNUMBER' -LicenseKey '4XJ9-2210'
        $result.Applied | Should -Be $true
        $result.InstallCommand | Should -Be 'msiexec /i "app.msi" /qn /norestart SERIALNUMBER="4XJ9-2210"'
    }

    It 'Appends the property to a WiX Burn bootstrapper, which passes it through to the MSI' {
        $result = Add-AppGetterLicenseInstallArgument `
            -InstallCommand '"setup.exe" /quiet /norestart' `
            -InstallerFamily 'wixburn' -PropertyName 'LICENSEKEY' -LicenseKey '4XJ9-2210'
        $result.Applied | Should -Be $true
        $result.InstallCommand | Should -Match 'LICENSEKEY="4XJ9-2210"$'
    }

    It 'Leaves installers that do not take MSI properties untouched' {
        foreach ($family in @('inno', 'nsis', 'installshield')) {
            $result = Add-AppGetterLicenseInstallArgument `
                -InstallCommand '"setup.exe" /VERYSILENT' `
                -InstallerFamily $family -PropertyName 'SERIALNUMBER' -LicenseKey '4XJ9-2210'
            $result.Applied | Should -Be $false
            $result.InstallCommand | Should -Be '"setup.exe" /VERYSILENT'
            $result.Reason | Should -Match 'does not accept MSI properties'
        }
    }

    It 'Does nothing when no key or no property is known' {
        (Add-AppGetterLicenseInstallArgument -InstallCommand 'msiexec /i "app.msi" /qn' -PropertyName 'SERIALNUMBER' -LicenseKey '').Applied |
            Should -Be $false
        (Add-AppGetterLicenseInstallArgument -InstallCommand 'msiexec /i "app.msi" /qn' -PropertyName '' -LicenseKey '4XJ9-2210').Applied |
            Should -Be $false
    }

    It 'Does not add the property twice' {
        $result = Add-AppGetterLicenseInstallArgument `
            -InstallCommand 'msiexec /i "app.msi" /qn SERIALNUMBER="EXISTING"' `
            -InstallerFamily 'msi' -PropertyName 'SERIALNUMBER' -LicenseKey '4XJ9-2210'
        $result.Applied | Should -Be $false
        $result.Reason | Should -Match 'already sets SERIALNUMBER'
    }
}

Describe 'Building the install.ps1 licensing stage' {
    It 'Emits nothing when licensing was never classified' {
        $resolved = Resolve-AppGetterLicensing -LicenseInfo ''
        New-AppGetterLicenseInstallStage -Licensing $resolved | Should -BeNullOrEmpty
    }

    It 'Points the client at the license server through the vendor variable' {
        $resolved = Resolve-AppGetterLicensing -LicenseInfo 'Concurrent FlexLM, license server 27000@lm.corp.local'
        $stage = New-AppGetterLicenseInstallStage -Licensing $resolved
        $stage | Should -Match 'LM_LICENSE_FILE'
        $stage | Should -Match '27000@lm\.corp\.local'
        $stage | Should -Match 'SetEnvironmentVariable'
    }

    It 'Warns when a served license has no server to point at' {
        $resolved = Resolve-AppGetterLicensing -LicenseInfo 'Concurrent floating license'
        New-AppGetterLicenseInstallStage -Licensing $resolved | Should -Match 'no license server was supplied'
    }

    It 'Stages a packaged license file and expands an environment-variable target' {
        $resolved = Resolve-AppGetterLicensing -LicenseInfo 'License file based' -LicenseFilePath $script:licenseFile `
            -LicenseFileTargetPath '%ProgramData%\Vendor\license.dat'
        $resolved.PackagedLicenseFile = 'license\license.dat'
        $stage = New-AppGetterLicenseInstallStage -Licensing $resolved
        $stage | Should -Match 'ExpandEnvironmentVariables'
        $stage | Should -Match 'Copy-Item'
        $stage | Should -Match 'license\\license\.dat'
    }

    It 'Stages both artifacts when a floating license also ships a license file' {
        $resolved = Resolve-AppGetterLicensing -LicenseInfo 'Concurrent FlexLM, license server 27000@lm.corp.local' `
            -LicenseFilePath $script:licenseFile
        $resolved.PackagedLicenseFile = 'license\license.dat'
        $stage = New-AppGetterLicenseInstallStage -Licensing $resolved
        $stage | Should -Match 'Copy-Item'
        $stage | Should -Match 'LM_LICENSE_FILE'
    }

    It 'Explains patterns that activate outside the package' -ForEach @(
        @{ Field = 'Per user subscription, named user'; Expected = 'signs in' }
        @{ Field = 'Requires HASP dongle'; Expected = 'hardware key' }
        @{ Field = 'MAK volume activation'; Expected = 'volume activation' }
        @{ Field = '30-day trial'; Expected = 'trial/evaluation' }
        @{ Field = 'Freeware'; Expected = 'No activation step' }
    ) {
        $resolved = Resolve-AppGetterLicensing -LicenseInfo $field
        New-AppGetterLicenseInstallStage -Licensing $resolved | Should -Match ([regex]::Escape($expected))
    }

    It 'Produces a stage that is valid PowerShell' {
        $resolved = Resolve-AppGetterLicensing -LicenseInfo "Concurrent FlexLM, license server 27000@lm.corp.local, don't forget"
        $resolved.PackagedLicenseFile = 'license\license.dat'
        $stage = New-AppGetterLicenseInstallStage -Licensing $resolved
        $errors = $null
        [void][System.Management.Automation.Language.Parser]::ParseInput($stage, [ref]$null, [ref]$errors)
        $errors.Count | Should -Be 0
    }
}

Describe 'Staging a license file into the package' {
    It 'Copies the file under license\ and returns a Windows-relative path' {
        InModuleScope AppGetter {
            $packageDir = Join-Path ([System.IO.Path]::GetTempPath()) ("appgetter-pkg-{0}" -f ([Guid]::NewGuid().ToString('N')))
            New-Item -ItemType Directory -Path $packageDir -Force | Out-Null
            $source = Join-Path $packageDir 'source.lic'
            Set-Content -LiteralPath $source -Value 'LICENSE' -Encoding ascii
            try {
                $relative = Copy-AppGetterLicenseArtifact -LicenseFilePath $source -VersionDirectory $packageDir
                $relative | Should -Be 'license\source.lic'
                Test-Path -LiteralPath (Join-Path (Join-Path $packageDir 'license') 'source.lic') | Should -Be $true
            } finally {
                Remove-Item -LiteralPath $packageDir -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }

    It 'Throws when the license file does not exist' {
        InModuleScope AppGetter {
            { Copy-AppGetterLicenseArtifact -LicenseFilePath '/does/not/exist.lic' -VersionDirectory ([System.IO.Path]::GetTempPath()) } |
                Should -Throw '*License file not found*'
        }
    }
}

Describe 'Summarizing a licensing resolution' {
    It 'Reports the pattern, activation, confidence, and assignment' {
        $summary = Get-AppGetterLicensingSummary -Licensing (Resolve-AppGetterLicensing -LicenseInfo 'Freeware')
        $summary | Should -Match 'Freeware'
        $summary | Should -Match 'activation=none'
        $summary | Should -Match 'confidence='
        $summary | Should -Match 'assignment=required'
    }

    It 'Says so when no licensing field was supplied' {
        Get-AppGetterLicensingSummary -Licensing (Resolve-AppGetterLicensing -LicenseInfo '') |
            Should -Match 'no licensing field supplied'
    }
}

Describe 'Applying licensing during packaging' {
    BeforeAll {
        $script:packRoot = Join-Path $script:licensingRoot 'out'
        $script:keyPackage = Invoke-AppGetterPackaging -AppName 'Licensed App' -InstallerPath $script:licensedMsi `
            -OutputPath $script:packRoot -Version '3.1.0' -Publisher 'Vendor Inc' -IconPath $script:iconFile `
            -LicenseInfo 'Licensed - per device perpetual. 25 seats purchased. License key: 4XJ9-2210-KD77-9931. Expires 2028-03-31.'

        $script:serverPackage = Invoke-AppGetterPackaging -AppName 'Flex CAD' -InstallerPath $script:flexlmExe `
            -OutputPath $script:packRoot -Version '2026.1' -IconPath $script:iconFile `
            -LicenseInfo 'Concurrent / floating license (FlexLM). License server 27000@lm.corp.local. 10 concurrent seats.' `
            -LicenseFilePath $script:licenseFile -LicenseFileTargetPath '%ProgramData%\FlexCAD\license.dat'

        $script:plainPackage = Invoke-AppGetterPackaging -AppName 'No License App' -InstallerPath $script:plainExe `
            -OutputPath $script:packRoot -Version '1.0.0' -IconPath $script:iconFile
    }

    It 'Bakes the license key into the install command through the detected property' {
        $script:keyPackage.Licensing.PatternId | Should -Be 'device-perpetual'
        $script:keyPackage.Licensing.AppliedToInstallCommand | Should -Be $true
        $installScript = Get-Content -LiteralPath (Join-Path $script:keyPackage.VersionDirectory 'install.ps1') -Raw
        $installScript | Should -Match 'SERIALNUMBER="4XJ9-2210-KD77-9931"'
    }

    It 'Redacts the license key from the install transcript' {
        $installScript = Get-Content -LiteralPath (Join-Path $script:keyPackage.VersionDirectory 'install.ps1') -Raw
        $installScript | Should -Match '\*\*\*REDACTED\*\*\*'
        $installScript | Should -Match 'Executing install command: \$loggedCommand'
    }

    It 'Keeps the plaintext key out of the object returned to the caller' {
        $script:keyPackage.Licensing.LicenseKey | Should -BeNullOrEmpty
        $script:keyPackage.Licensing.LicenseKeyMasked | Should -Not -BeNullOrEmpty
    }

    It 'Writes a licensing.json manifest with the masked key only' {
        $manifestPath = Join-Path $script:keyPackage.VersionDirectory 'licensing.json'
        Test-Path -LiteralPath $manifestPath | Should -Be $true
        $manifestText = Get-Content -LiteralPath $manifestPath -Raw
        $manifestText | Should -Not -Match '2210-KD77'
        $manifest = $manifestText | ConvertFrom-Json
        $manifest.patternId | Should -Be 'device-perpetual'
        $manifest.licenseKeyProperty | Should -Be 'SERIALNUMBER'
        $manifest.licenseQuantity | Should -Be 25
        $manifest.licenseExpiry | Should -Be '2028-03-31'
        $manifest.generatedAt | Should -Not -BeNullOrEmpty
    }

    It 'Records licensing in app.json and the win32LobApp notes' {
        $app = Get-Content -LiteralPath (Join-Path $script:keyPackage.VersionDirectory 'app.json') -Raw | ConvertFrom-Json
        $app.licensing.patternId | Should -Be 'device-perpetual'
        $app.licensing.activationMethod | Should -Be 'key'

        $win32 = Get-Content -LiteralPath (Join-Path $script:keyPackage.VersionDirectory 'win32LobApp.json') -Raw | ConvertFrom-Json
        $win32.notes | Should -Match 'Licensing: Per device \(perpetual\)'
    }

    It 'Documents licensing in README.md and readme.txt' {
        $readme = Get-Content -LiteralPath (Join-Path $script:keyPackage.VersionDirectory 'README.md') -Raw
        $readme | Should -Match '## Licensing'
        $readme | Should -Match '\| \*\*License type\*\* \| Per device \(perpetual\) \|'
        $readme | Should -Match 'Licensing evidence'
        $readme | Should -Not -Match '2210-KD77'

        $legacy = Get-Content -LiteralPath (Join-Path $script:keyPackage.VersionDirectory 'readme.txt') -Raw
        $legacy | Should -Match 'Licensing: Per device \(perpetual\)'
    }

    It 'Ships the license file inside the package and stages it during install' {
        $script:serverPackage.Licensing.PatternId | Should -Be 'concurrent-floating'
        $script:serverPackage.Licensing.PackagedLicenseFile | Should -Be 'license\license.dat'
        Test-Path -LiteralPath (Join-Path $script:serverPackage.VersionDirectory 'license/license.dat') | Should -Be $true

        $installScript = Get-Content -LiteralPath (Join-Path $script:serverPackage.VersionDirectory 'install.ps1') -Raw
        $installScript | Should -Match 'Staged license file to'
        $installScript | Should -Match '%ProgramData%\\FlexCAD\\license\.dat'
    }

    It 'Points the client at the license server during install' {
        $script:serverPackage.Licensing.LicenseServer | Should -Be '27000@lm.corp.local'
        $installScript = Get-Content -LiteralPath (Join-Path $script:serverPackage.VersionDirectory 'install.ps1') -Raw
        $installScript | Should -Match "\`$licenseVariable = 'LM_LICENSE_FILE'"
        $installScript | Should -Match "\`$licenseServer = '27000@lm\.corp\.local'"
    }

    It 'Generates install scripts that are valid PowerShell' {
        foreach ($package in @($script:keyPackage, $script:serverPackage, $script:plainPackage)) {
            $errors = $null
            [void][System.Management.Automation.Language.Parser]::ParseFile(
                (Join-Path $package.VersionDirectory 'install.ps1'), [ref]$null, [ref]$errors)
            $errors.Count | Should -Be 0
        }
    }

    It 'Leaves packages built without a licensing field unchanged' {
        $script:plainPackage.Licensing.Classified | Should -Be $false
        Test-Path -LiteralPath (Join-Path $script:plainPackage.VersionDirectory 'licensing.json') | Should -Be $false

        $app = Get-Content -LiteralPath (Join-Path $script:plainPackage.VersionDirectory 'app.json') -Raw | ConvertFrom-Json
        $app.PSObject.Properties.Name | Should -Not -Contain 'licensing'

        $readme = Get-Content -LiteralPath (Join-Path $script:plainPackage.VersionDirectory 'README.md') -Raw
        $readme | Should -Not -Match '## Licensing'

        $installScript = Get-Content -LiteralPath (Join-Path $script:plainPackage.VersionDirectory 'install.ps1') -Raw
        $installScript | Should -Not -Match 'Licensing pattern'
        $installScript | Should -Match 'Executing install command: \$installCommand'
    }

    It 'Fails fast when the license file is missing' {
        { Invoke-AppGetterPackaging -AppName 'Missing License' -InstallerPath $script:plainExe `
                -OutputPath $script:packRoot -LicenseFilePath (Join-Path $script:licensingRoot 'absent.lic') } |
            Should -Throw '*License file not found*'
    }
}

Describe 'Reading licensing back out of a package' {
    It 'Prefers licensing.json' {
        $info = Get-AppGetterPackageLicensingInfo -VersionDirectory $script:keyPackage.VersionDirectory
        $info.patternId | Should -Be 'device-perpetual'
        $info.generatedAt | Should -Not -BeNullOrEmpty
    }

    It 'Falls back to the licensing block in app.json' {
        $copy = Join-Path $script:licensingRoot 'pkg-copy'
        New-Item -ItemType Directory -Path $copy -Force | Out-Null
        Copy-Item -LiteralPath (Join-Path $script:keyPackage.VersionDirectory 'app.json') -Destination $copy -Force
        $info = Get-AppGetterPackageLicensingInfo -VersionDirectory $copy
        $info.patternId | Should -Be 'device-perpetual'
        $info.generatedAt | Should -BeNullOrEmpty
    }

    It 'Returns nothing for a folder with no licensing metadata' {
        Get-AppGetterPackageLicensingInfo -VersionDirectory $script:licensingRoot | Should -BeNullOrEmpty
    }
}
