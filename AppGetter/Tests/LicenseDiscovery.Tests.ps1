BeforeAll {
    $moduleManifest = Join-Path $PSScriptRoot '..' 'AppGetter.psd1'
    Import-Module $moduleManifest -Force
    $script:fixtureRoot = Join-Path $PSScriptRoot 'Fixtures' 'Installers'
}

Describe 'Get-AppGetterLicenseCatalog' {
    It 'Includes the ServiceNow license metrics used for packaging' {
        $patterns = Get-AppGetterLicenseCatalog | ForEach-Object { $_.Pattern }
        $patterns | Should -Contain 'freeware'
        $patterns | Should -Contain 'openSource'
        $patterns | Should -Contain 'perDevice'
        $patterns | Should -Contain 'perUser'
        $patterns | Should -Contain 'concurrentUser'
        $patterns | Should -Contain 'subscription'
        $patterns | Should -Contain 'volume'
        $patterns | Should -Contain 'enterprise'
        $patterns | Should -Contain 'siteLicense'
    }
}

Describe 'Resolve-AppGetterLicensePattern' {
    It 'Maps ServiceNow Per Device to the per-device pattern' {
        $result = Resolve-AppGetterLicensePattern -LicenseInfo 'Per Device'
        $result.Pattern | Should -Be 'perDevice'
        $result.Source | Should -Be 'servicenow'
        $result.InstallContext | Should -Be 'system'
        $result.AssignmentTarget | Should -Be 'device'
        $result.RequiresLicenseKey | Should -Be $true
        $result.ConfidenceScore | Should -Be 100
        $result.SourceText | Should -Be 'Per Device'
    }

    It 'Maps Per Named User and Named User Plus to per-user' {
        $named = Resolve-AppGetterLicensePattern -LicenseInfo 'Per Named User'
        $named.Pattern | Should -Be 'perUser'
        $named.InstallContext | Should -Be 'user'
        $named.AssignmentTarget | Should -Be 'user'

        $plus = Resolve-AppGetterLicensePattern -LicenseInfo 'Named User Plus'
        $plus.Pattern | Should -Be 'perUser'
    }

    It 'Maps User Subscription to the subscription pattern' {
        $result = Resolve-AppGetterLicensePattern -LicenseInfo 'User Subscription'
        $result.Pattern | Should -Be 'subscription'
        $result.InstallContext | Should -Be 'user'
        $result.RequiresLicenseKey | Should -Be $false
    }

    It 'Prefers Concurrent User over a generic user match' {
        $result = Resolve-AppGetterLicensePattern -LicenseInfo 'Concurrent User'
        $result.Pattern | Should -Be 'concurrentUser'
        $result.Metric | Should -Be 'concurrent'
        $result.InstallContext | Should -Be 'system'
    }

    It 'Maps Freeware, Open Source, and Subscription ServiceNow values' {
        (Resolve-AppGetterLicensePattern -LicenseInfo 'Freeware').Pattern | Should -Be 'freeware'
        (Resolve-AppGetterLicensePattern -LicenseInfo 'Open Source').Pattern | Should -Be 'openSource'
        $subscription = Resolve-AppGetterLicensePattern -LicenseInfo 'Subscription'
        $subscription.Pattern | Should -Be 'subscription'
        $subscription.InstallContext | Should -Be 'user'
        $subscription.RequiresLicenseKey | Should -Be $false
    }

    It 'Maps volume, site, enterprise, CAL, and core metrics' {
        (Resolve-AppGetterLicensePattern -LicenseInfo 'Volume License').Pattern | Should -Be 'volume'
        (Resolve-AppGetterLicensePattern -LicenseInfo 'Site License').Pattern | Should -Be 'siteLicense'
        (Resolve-AppGetterLicensePattern -LicenseInfo 'Enterprise Agreement').Pattern | Should -Be 'enterprise'
        (Resolve-AppGetterLicensePattern -LicenseInfo 'Client Access License (CAL)').Pattern | Should -Be 'clientAccess'
        (Resolve-AppGetterLicensePattern -LicenseInfo 'Per Core').Pattern | Should -Be 'perCore'
        (Resolve-AppGetterLicensePattern -LicenseInfo 'Per Processor').Pattern | Should -Be 'perProcessor'
    }

    It 'Treats an unrecognized ServiceNow value as unknown with manual review' {
        $result = Resolve-AppGetterLicensePattern -LicenseInfo 'Custom Metric XYZ-99'
        $result.Pattern | Should -Be 'unknown'
        $result.Source | Should -Be 'servicenow'
        $result.SourceText | Should -Be 'Custom Metric XYZ-99'
        $result.NeedsManualReview | Should -Be $true
        $result.InstallContext | Should -Be 'system'
    }

    It 'Infers open source from application metadata when no ServiceNow field is provided' {
        $result = Resolve-AppGetterLicensePattern -AppName 'Example Editor' `
            -Description 'A free open source text editor released under the MIT license'
        $result.Pattern | Should -Be 'openSource'
        $result.Source | Should -Be 'inferred'
        $result.NeedsManualReview | Should -Be $true
        $result.ConfidenceScore | Should -BeLessThan 60
    }

    It 'Returns unknown when nothing can be identified' {
        $result = Resolve-AppGetterLicensePattern -AppName 'Contoso Helper' -Description 'Packaged from local installer'
        $result.Pattern | Should -Be 'unknown'
        $result.Source | Should -Be 'none'
        $result.NeedsManualReview | Should -Be $true
    }

    It 'Uses the ServiceNow field even when description mentions a different license' {
        $result = Resolve-AppGetterLicensePattern -LicenseInfo 'Per Device' `
            -AppName 'Example' -Description 'This product is freeware'
        $result.Pattern | Should -Be 'perDevice'
        $result.Source | Should -Be 'servicenow'
    }
}

Describe 'License pattern application during packaging' {
    It 'Writes license.json, user-context win32LobApp, and a license-key block for Per User' {
        $output = Join-Path ([System.IO.Path]::GetTempPath()) ("appgetter-license-{0}" -f ([Guid]::NewGuid().ToString('N')))
        $installer = Join-Path $script:fixtureRoot 'sample.msi'
        try {
            $result = Invoke-AppGetterPackaging -AppName 'Contoso App' -InstallerPath $installer `
                -Publisher 'Contoso' -Version '1.2.3' -LicenseInfo 'Per User' -OutputPath $output

            $result.License.Pattern | Should -Be 'perUser'
            Test-Path -LiteralPath (Join-Path $result.VersionDirectory 'license.json') | Should -Be $true

            $app = Get-Content -LiteralPath (Join-Path $result.VersionDirectory 'app.json') -Raw | ConvertFrom-Json
            $app.licensing.pattern | Should -Be 'perUser'
            $app.licensing.source | Should -Be 'servicenow'
            $app.licensing.installContext | Should -Be 'user'

            $win32 = Get-Content -LiteralPath (Join-Path $result.VersionDirectory 'win32LobApp.json') -Raw | ConvertFrom-Json
            $win32.installExperience.runAsAccount | Should -Be 'user'
            $win32.notes | Should -Match 'Per User'

            $install = Get-Content -LiteralPath (Join-Path $result.VersionDirectory 'install.ps1') -Raw
            $install | Should -Match 'Licensing: Per User'
            $install | Should -Match 'APPGETTER_LICENSE_KEY'
            $install | Should -Match 'PIDKEY='

            $readme = Get-Content -LiteralPath (Join-Path $result.VersionDirectory 'README.md') -Raw
            $readme | Should -Match '## Licensing'
            $readme | Should -Match 'Per User'
            $readme | Should -Match '\| \*\*Install behavior\*\* \| User \|'
        } finally {
            if (Test-Path -LiteralPath $output) {
                Remove-Item -LiteralPath $output -Recurse -Force
            }
        }
    }

    It 'Keeps system context and skips license-key injection for Freeware' {
        $output = Join-Path ([System.IO.Path]::GetTempPath()) ("appgetter-license-free-{0}" -f ([Guid]::NewGuid().ToString('N')))
        $installer = Join-Path $script:fixtureRoot 'sample.msi'
        try {
            $result = Invoke-AppGetterPackaging -AppName 'Free Utility' -InstallerPath $installer `
                -Publisher 'Contoso' -Version '9.0.0' -LicenseInfo 'Freeware' -OutputPath $output

            $result.License.Pattern | Should -Be 'freeware'
            $result.License.RequiresLicenseKey | Should -Be $false

            $win32 = Get-Content -LiteralPath (Join-Path $result.VersionDirectory 'win32LobApp.json') -Raw | ConvertFrom-Json
            $win32.installExperience.runAsAccount | Should -Be 'system'

            $install = Get-Content -LiteralPath (Join-Path $result.VersionDirectory 'install.ps1') -Raw
            $install | Should -Match 'Licensing: Freeware'
            $install | Should -Not -Match 'APPGETTER_LICENSE_KEY'
        } finally {
            if (Test-Path -LiteralPath $output) {
                Remove-Item -LiteralPath $output -Recurse -Force
            }
        }
    }
}
