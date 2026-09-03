BeforeAll {
    $moduleManifest = Join-Path $PSScriptRoot '..' 'AppGetter.psd1'
    Import-Module $moduleManifest -Force
}

Describe 'Resolve-AppGetterLicensingPattern' {
    It 'Maps common user-provided licensing language to a pattern' {
        InModuleScope AppGetter {
            $result = Resolve-AppGetterLicensingPattern `
                -InputText 'Named user annual subscription' `
                -Source 'UserProvided'

            $result.Pattern | Should -Be 'SeatBased'
            $result.Source | Should -Be 'UserProvided'
            $result.ConfidenceScore | Should -BeGreaterThan 0
        }
    }

    It 'Preserves unmapped user text as custom' {
        InModuleScope AppGetter {
            $result = Resolve-AppGetterLicensingPattern `
                -InputText 'Handled by separate procurement agreement' `
                -Source 'UserProvided'

            $result.Pattern | Should -Be 'Custom'
            $result.Notes | Should -Match 'procurement agreement'
        }
    }
}

Describe 'Get-WebPackageDetails licensing output' {
    It 'Uses user-provided licensing info when present' {
        InModuleScope AppGetter {
            $details = Get-WebPackageDetails `
                -AppName 'Contoso App' `
                -DownloadUrl 'https://example.invalid/app.msi' `
                -Publisher 'Contoso' `
                -LicensingInfo 'Perpetual one-time purchase'

            $details.Licensing.Pattern | Should -Be 'Perpetual'
            $details.Licensing.Source | Should -Be 'UserProvided'
            $details.Licensing.Notes | Should -Match 'one-time purchase'
        }
    }

    It 'Falls back to detected web licensing keywords when intake info is missing' {
        InModuleScope AppGetter {
            Mock -ModuleName AppGetter Invoke-WebRequest {
                [PSCustomObject]@{
                    Content = @'
<html><body>
Enterprise plan includes per user licensing with floating license server options.
</body></html>
'@
                }
            }

            $details = Get-WebPackageDetails `
                -AppName 'Contoso App' `
                -WebsiteUrl 'https://example.invalid/product' `
                -Publisher 'Contoso'

            $details.Licensing.Pattern | Should -Be 'SeatBased'
            $details.Licensing.Source | Should -Be 'DetectedFromWeb'
            $details.Licensing.EvidenceSummary.Count | Should -BeGreaterThan 0
        }
    }
}
