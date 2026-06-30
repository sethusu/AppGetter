@{
    ModuleVersion     = '2.0.0'
    GUID              = 'b4e9d3f2-0c5e-4a8b-9f7d-2e3c4b5a6d7e'
    Author            = 'AppGetter'
    CompanyName       = 'AppGetter'
    Copyright         = '(c) AppGetter. All rights reserved.'
    Description       = 'Create Intune Win32 packages from web-based application downloads.'
    PowerShellVersion = '5.1'
    RootModule        = 'AppGetter.psm1'
    FunctionsToExport = @(
        'Invoke-AppGetterPackaging'
        'Find-WebDownloadLinks'
        'Get-WebPackageDetails'
        'Get-AppGetterSettings'
        'Save-AppGetterSettings'
        'Test-AppGetterPrerequisites'
        'Resolve-PackageIcon'
        'Set-AppGetterPackageIconFiles'
    )
    PrivateData       = @{
        PSData = @{
            Tags = @('Intune', 'Web', 'Win32', 'MDM')
        }
    }
}
