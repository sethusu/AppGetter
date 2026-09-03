BeforeAll {
    $moduleManifest = Join-Path $PSScriptRoot '..' 'AppGetter.psd1'
    Import-Module $moduleManifest -Force
}

Describe 'License type normalization' {
    It 'Returns canonical values unchanged' {
        ConvertTo-AppGetterLicenseType -Value 'Per User' | Should -Be 'Per User'
        ConvertTo-AppGetterLicenseType -Value 'open source' | Should -Be 'Open Source'
    }

    It 'Maps common ServiceNow-style aliases to canonical types' {
        ConvertTo-AppGetterLicenseType -Value 'Per Seat' | Should -Be 'Per User'
        ConvertTo-AppGetterLicenseType -Value 'named user' | Should -Be 'Per User'
        ConvertTo-AppGetterLicenseType -Value 'per machine' | Should -Be 'Per Device'
        ConvertTo-AppGetterLicenseType -Value 'Volume License' | Should -Be 'Site License'
        ConvertTo-AppGetterLicenseType -Value 'SaaS' | Should -Be 'Subscription'
        ConvertTo-AppGetterLicenseType -Value 'GPLv3' | Should -Be 'Open Source'
        ConvertTo-AppGetterLicenseType -Value 'shareware' | Should -Be 'Trial / Evaluation'
        ConvertTo-AppGetterLicenseType -Value 'freeware' | Should -Be 'Freeware'
    }

    It 'Defaults blank input to Unknown' {
        ConvertTo-AppGetterLicenseType -Value '' | Should -Be 'Unknown'
        ConvertTo-AppGetterLicenseType -Value '   ' | Should -Be 'Unknown'
    }

    It 'Preserves unrecognized values so ingested data is not lost' {
        ConvertTo-AppGetterLicenseType -Value 'Custom Corporate Agreement 42' | Should -Be 'Custom Corporate Agreement 42'
    }

    It 'Exposes the canonical license type list' {
        $types = Get-AppGetterLicenseTypes
        $types | Should -Contain 'Per User'
        $types | Should -Contain 'Open Source'
        $types | Should -Contain 'Unknown'
    }
}

Describe 'Provided license type (e.g. ServiceNow ingest) wins' {
    It 'Uses the provided value without detection and normalizes it' {
        $info = Resolve-AppGetterLicenseInfo -AppName 'Sample' -LicenseType 'per seat' -LicenseNotes 'Contract 123'
        $info.LicenseType | Should -Be 'Per User'
        $info.Source | Should -Be 'provided'
        $info.ConfidenceScore | Should -Be 100
        $info.NeedsManualReview | Should -Be $false
        $info.Notes | Should -Be 'Contract 123'
    }

    It 'Keeps provided license name and URL' {
        $info = Resolve-AppGetterLicenseInfo -AppName 'Sample' -LicenseType 'Open Source' `
            -LicenseName 'MIT License' -LicenseUrl 'https://example.com/license'
        $info.LicenseName | Should -Be 'MIT License'
        $info.LicenseUrl | Should -Be 'https://example.com/license'
    }
}

Describe 'License pattern detection from text' {
    It 'Identifies named open-source licenses' {
        $info = Resolve-AppGetterLicenseInfo -AppName 'Sample' `
            -PageText 'This project is released under the MIT License. Source code on GitHub.'
        $info.LicenseType | Should -Be 'Open Source'
        $info.LicenseName | Should -Be 'MIT License'
        $info.Source | Should -Be 'detected'
        $info.ConfidenceScore | Should -BeGreaterOrEqual 70
        $info.NeedsManualReview | Should -Be $false
        ($info.EvidenceSummary -join ' ') | Should -Match 'MIT'
    }

    It 'Identifies GPL wording' {
        $info = Resolve-AppGetterLicenseInfo -AppName 'Sample' `
            -PageText 'Distributed under the GNU General Public License version 3.'
        $info.LicenseType | Should -Be 'Open Source'
        $info.LicenseName | Should -Be 'GNU GPL'
    }

    It 'Identifies freeware wording' {
        $info = Resolve-AppGetterLicenseInfo -AppName 'Sample' `
            -PageText 'This tool is freeware and may be used free of charge in any environment.'
        $info.LicenseType | Should -Be 'Freeware'
        $info.Source | Should -Be 'detected'
    }

    It 'Identifies per-user commercial licensing' {
        $info = Resolve-AppGetterLicenseInfo -AppName 'Sample' `
            -PageText 'Pricing starts at $49 per-user with named user licenses available for teams.'
        $info.LicenseType | Should -Be 'Per User'
    }

    It 'Identifies per-device licensing' {
        $info = Resolve-AppGetterLicenseInfo -AppName 'Sample' `
            -PageText 'A license is required per device. Node-locked activation keys are issued per workstation.'
        $info.LicenseType | Should -Be 'Per Device'
    }

    It 'Identifies subscription licensing' {
        $info = Resolve-AppGetterLicenseInfo -AppName 'Sample' `
            -PageText 'Available as a subscription: billed per month or per year with automatic updates.'
        $info.LicenseType | Should -Be 'Subscription'
    }

    It 'Identifies trial / evaluation offerings' {
        $info = Resolve-AppGetterLicenseInfo -AppName 'Sample' `
            -PageText 'Download the 30-day trial and evaluate before purchasing. Shareware distribution allowed.'
        $info.LicenseType | Should -Be 'Trial / Evaluation'
    }

    It 'Reduces confidence and flags review when patterns conflict' {
        $info = Resolve-AppGetterLicenseInfo -AppName 'Sample' `
            -PageText 'Free trial available. Licensed per device. Also sold per-user.'
        $info.NeedsManualReview | Should -Be $true
        ($info.EvidenceSummary -join ' ') | Should -Match 'Conflicting'
    }

    It 'Returns Unknown with manual review when nothing matches' {
        $info = Resolve-AppGetterLicenseInfo -AppName 'Sample' -PageText 'A great application for everyone.'
        $info.LicenseType | Should -Be 'Unknown'
        $info.Source | Should -Be 'default'
        $info.ConfidenceScore | Should -Be 0
        $info.NeedsManualReview | Should -Be $true
    }

    It 'Returns Unknown when no inputs are available at all' {
        $info = Resolve-AppGetterLicenseInfo -AppName 'Sample'
        $info.LicenseType | Should -Be 'Unknown'
        $info.NeedsManualReview | Should -Be $true
    }
}

Describe 'License info is applied to package metadata' {
    BeforeEach {
        $script:tempDir = Join-Path ([System.IO.Path]::GetTempPath()) ("appgetter-license-{0}" -f ([Guid]::NewGuid().ToString('N')))
        New-Item -ItemType Directory -Path $script:tempDir -Force | Out-Null
    }

    AfterEach {
        if ($script:tempDir -and (Test-Path -LiteralPath $script:tempDir)) {
            Remove-Item -LiteralPath $script:tempDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'Writes the licensing block into app.json, README.md, readme.txt, and win32LobApp notes' {
        $versionDirectory = $script:tempDir
        InModuleScope AppGetter -Parameters @{ VersionDirectory = $versionDirectory } {
            param($VersionDirectory)

            $details = [PSCustomObject]@{
                PackageId    = 'SampleApp'
                DisplayName  = 'Sample App'
                Version      = '1.0.0'
                Publisher    = 'Sample Corp'
                Developer    = 'Sample Corp'
                Description  = 'Sample description'
                WebsiteUrl   = 'https://example.com'
                DownloadUrl  = 'https://example.com/setup.msi'
                DeveloperUrl = ''
                SupportUrl   = ''
                Homepage     = 'https://example.com'
            }

            $licenseInfo = Resolve-AppGetterLicenseInfo -AppName 'Sample App' -LicenseType 'Site License' `
                -LicenseNotes 'ServiceNow SW model 001'

            $null = New-AppGetterMetadataFiles -PackageDetails $details -VersionDirectory $VersionDirectory `
                -InstallerFileName 'setup.msi' -InstallerHash 'ABC123' `
                -InstallerInstallCommand 'msiexec /i "setup.msi" /qn' `
                -DetectionScript '# detect' -InstallScript '# install' -UninstallScript '# uninstall' `
                -IconFilePath (Join-Path $VersionDirectory 'icon.png') `
                -FinalDownloadUrl 'https://example.com/setup.msi' `
                -LicenseInfo $licenseInfo
        }

        $appJson = Get-Content -LiteralPath (Join-Path $versionDirectory 'app.json') -Raw | ConvertFrom-Json
        $appJson.licenseType | Should -Be 'Site License'
        $appJson.licensing.licenseType | Should -Be 'Site License'
        $appJson.licensing.source | Should -Be 'provided'
        $appJson.licensing.notes | Should -Be 'ServiceNow SW model 001'
        $appJson.licensing.needsManualReview | Should -Be $false

        $readme = Get-Content -LiteralPath (Join-Path $versionDirectory 'README.md') -Raw
        $readme | Should -Match '\*\*License type\*\*\s*\|\s*Site License'
        $readme | Should -Match '## Licensing'

        $legacyReadme = Get-Content -LiteralPath (Join-Path $versionDirectory 'readme.txt') -Raw
        $legacyReadme | Should -Match 'License type: Site License'

        $win32 = Get-Content -LiteralPath (Join-Path $versionDirectory 'win32LobApp.json') -Raw | ConvertFrom-Json
        $win32.notes | Should -Match 'License: Site License'
    }

    It 'Still writes metadata when no license info is supplied (backward compatible)' {
        $versionDirectory = $script:tempDir
        InModuleScope AppGetter -Parameters @{ VersionDirectory = $versionDirectory } {
            param($VersionDirectory)

            $details = [PSCustomObject]@{
                PackageId    = 'SampleApp'
                DisplayName  = 'Sample App'
                Version      = '1.0.0'
                Publisher    = 'Sample Corp'
                Developer    = 'Sample Corp'
                Description  = 'Sample description'
                WebsiteUrl   = ''
                DownloadUrl  = ''
                DeveloperUrl = ''
                SupportUrl   = ''
                Homepage     = ''
            }

            $null = New-AppGetterMetadataFiles -PackageDetails $details -VersionDirectory $VersionDirectory `
                -InstallerFileName 'setup.msi' -InstallerHash 'ABC123' `
                -InstallerInstallCommand 'msiexec /i "setup.msi" /qn' `
                -DetectionScript '# detect' -InstallScript '# install' -UninstallScript '# uninstall' `
                -IconFilePath (Join-Path $VersionDirectory 'icon.png') `
                -FinalDownloadUrl 'https://example.com/setup.msi'
        }

        $appJson = Get-Content -LiteralPath (Join-Path $versionDirectory 'app.json') -Raw | ConvertFrom-Json
        $appJson.PSObject.Properties['licensing'] | Should -BeNullOrEmpty
        Test-Path -LiteralPath (Join-Path $versionDirectory 'README.md') | Should -Be $true
    }
}
