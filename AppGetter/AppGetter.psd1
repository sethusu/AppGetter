@{
    ModuleVersion     = '2.0.0'
    GUID              = 'b4e9d3f2-0c5e-5a8b-9f7d-2e3c4b5d6e7f'
    Author            = 'AppGetter'
    CompanyName       = 'AppGetter'
    Copyright         = '(c) AppGetter. All rights reserved.'
    Description       = 'Create Intune Win32 packages from web-based application downloads.'
    PowerShellVersion = '5.1'
    RootModule        = 'AppGetter.psm1'
    FunctionsToExport = @(
        'Get-WebPackageDetails'
        'Get-DownloadLinksFromWeb'
        'Invoke-AppGetterPackaging'
        'Get-AppGetterSettings'
        'Save-AppGetterSettings'
        'Test-AppGetterPrerequisites'
        'Resolve-PackageIcon'
        'Resolve-PackageIconCandidates'
        'Set-AppGetterPackageIconFiles'
    )
    PrivateData       = @{
        PSData = @{
            Tags = @('Intune', 'Win32', 'MDM', 'Web')
        }
    }
}
