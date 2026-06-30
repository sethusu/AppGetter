@{
    RootModule        = 'AppGetter.SilentSwitch.psm1'
    ModuleVersion     = '2.0.0'
    GUID              = 'b2c3d4e5-f6a7-8901-bcde-f12345678901'
    Author            = 'AppGetter'
    Description       = 'Detect, research, and test silent install switches for Windows installers.'
    FunctionsToExport = @(
        'Get-InstallerFramework',
        'Get-KnownSilentSwitches',
        'Get-SilentSwitchesFromWeb',
        'Invoke-InstallerHelpProbe',
        'Test-InstallerSilentSwitches',
        'Find-InstallerSilentSwitches',
        'New-InstallCommand'
    )
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()
}
