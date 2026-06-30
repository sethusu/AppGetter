@{
    ModuleVersion     = '2.0.0'
    GUID              = 'b4e8d3f2-7c1a-4f9b-9d6e-2a3b4c5d6e7f'
    Author            = 'AppGetter'
    CompanyName       = 'AppGetter'
    Copyright         = '(c) AppGetter. All rights reserved.'
    Description       = 'Create Intune Win32 packages from web-based application downloads.'
    PowerShellVersion = '5.1'
    RootModule        = 'AppGetter.psm1'
    FunctionsToExport = @(
        'Invoke-AppGetterPackaging'
        'Invoke-InstallerSwitchAnalysis'
        'Get-AppGetterSettings'
        'Save-AppGetterSettings'
        'Test-AppGetterPrerequisites'
        'Resolve-PackageIcon'
        'Resolve-WebDownloadUrl'
        'Get-DownloadLinksFromWeb'
    )
    PrivateData       = @{
        PSData = @{
            Tags = @('Intune', 'Win32', 'MDM', 'WebDownload')
        }
    }
}
