@{
    ModuleVersion     = '2.1.0'
    GUID              = 'b4e9d3f2-0c5e-4a8b-9f7d-2e3c4b5a6d7e'
    Author            = 'AppGetter'
    CompanyName       = 'AppGetter'
    Copyright         = '(c) AppGetter. All rights reserved.'
    Description       = 'Create Intune Win32 packages from a download URL or a local installer.'
    PowerShellVersion = '5.1'
    RootModule        = 'AppGetter.psm1'
    FunctionsToExport = @(
        'Invoke-AppGetterPackaging'
        'Find-WebDownloadLinks'
        'Get-WebPackageDetails'
        'Get-AppGetterDefaultBaseOutputPath'
        'Get-AppGetterBaseOutputPath'
        'Get-AppGetterAppOutputPath'
        'Get-AppGetterSettings'
        'Save-AppGetterSettings'
        'Test-AppGetterPrerequisites'
        'Install-AppGetterContentPrepTool'
        'Get-PackageIdFromAppName'
        'Resolve-PackageIcon'
        'Set-AppGetterPackageIconFiles'
    )
    PrivateData       = @{
        PSData = @{
            Tags = @('Intune', 'Web', 'Win32', 'MDM')
        }
    }
}
