@{
    RootModule        = 'AppGetter.Config.psm1'
    ModuleVersion     = '2.0.0'
    GUID              = 'a1b2c3d4-e5f6-7890-abcd-ef1234567890'
    Author            = 'AppGetter'
    Description       = 'Persistent configuration for AppGetter download and output locations.'
    FunctionsToExport = @(
        'Get-AppGetterConfig',
        'Set-AppGetterConfig',
        'Reset-AppGetterConfig',
        'Test-AppGetterPath',
        'Get-AppGetterConfigPath'
    )
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()
}
