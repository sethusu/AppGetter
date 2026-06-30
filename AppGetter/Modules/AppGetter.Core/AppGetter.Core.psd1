@{
    RootModule        = 'AppGetter.Core.psm1'
    ModuleVersion     = '2.0.0'
    GUID              = 'a1b2c3d4-e5f6-7890-abcd-ef1234567890'
    Author            = 'AppGetter'
    Description       = 'Core backend for AppGetter: download location management, installer analysis, and silent switch discovery.'
    PowerShellVersion = '5.1'
    FunctionsToExport = @(
        'Get-AppGetterSettings'
        'Set-AppGetterSettings'
        'Import-InstallerToDownloadLocation'
        'Get-DownloadLinksFromWeb'
        'Get-InstallSwitchesFromWeb'
        'Get-InstallerFramework'
        'Test-InstallerSilentSwitch'
        'Find-InstallerSilentSwitch'
        'Save-InstallerSwitchResult'
        'Get-InstallerSwitchHistory'
        'Start-WebDownloadWithProgress'
    )
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()
}
