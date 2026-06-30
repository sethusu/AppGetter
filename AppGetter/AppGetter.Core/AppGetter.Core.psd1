@{
    RootModule        = 'AppGetter.Core.psm1'
    ModuleVersion     = '2.0.0'
    GUID              = 'a1b2c3d4-e5f6-7890-abcd-ef1234567890'
    Author            = 'AppGetter'
    Description       = 'Core library for AppGetter - installer download, analysis, and silent switch discovery'
    PowerShellVersion = '5.1'
    FunctionsToExport = @(
        'Get-AppGetterConfig'
        'Set-AppGetterConfig'
        'Get-InstallerInfo'
        'Test-InstallerSilentSwitches'
        'Find-InstallerSilentSwitches'
        'Start-InstallerDownload'
        'Get-DownloadLinksFromWeb'
        'Get-InstallSwitchesFromWeb'
        'Start-WebDownloadWithProgress'
        'Get-VersionFromWeb'
        'Get-DescriptionFromWeb'
        'Get-LogoFromWeb'
        'Extract-IconFromExe'
    )
    PrivateData       = @{
        PSData = @{
            Tags = @('Intune', 'Installer', 'SilentInstall', 'Win32')
        }
    }
}
