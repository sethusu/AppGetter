@{
    RootModule        = 'AppGetter.Core.psm1'
    ModuleVersion     = '2.0.0'
    GUID              = 'c3d4e5f6-a7b8-9012-cdef-123456789012'
    Author            = 'AppGetter'
    Description       = 'Core AppGetter functions for download discovery and package preparation.'
    RequiredModules   = @('AppGetter.Config', 'AppGetter.SilentSwitch')
    FunctionsToExport = @(
        'Get-DownloadLinksFromWeb',
        'Get-VersionFromWeb',
        'Get-DescriptionFromWeb',
        'Start-WebDownloadWithProgress',
        'Import-AppGetterModules',
        'New-AppGetterPackageContext'
    )
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()
}
