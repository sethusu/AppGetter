@{
    ModuleVersion     = '2.2.0'
    GUID              = 'b4e9d3f2-0c5e-4a8b-9f7d-2e3c4b5a6d7e'
    Author            = 'AppGetter'
    CompanyName       = 'AppGetter'
    Copyright         = '(c) AppGetter. All rights reserved.'
    Description       = 'Create Intune Win32 packages from web downloads or local installer files.'
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
        'Resolve-PackageIcon'
        'Set-AppGetterPackageIconFiles'
        'Test-AppGetterWindowsSandbox'
        'Install-AppGetterWindowsSandbox'
        'Resolve-AppGetterPackageVersionDirectory'
        'Test-AppGetterSandboxPackage'
        'Get-AppGetterSandboxPackageInfo'
        'Start-AppGetterSandboxSession'
        'Set-AppGetterSandboxCommand'
        'Get-AppGetterSandboxStatus'
        'Get-AppGetterSandboxHeartbeat'
        'Get-AppGetterSandboxGuestLog'
        'Write-AppGetterSandboxTestReport'
        'Get-AppGetterSandboxTestReportPath'
        'Get-AppGetterPackageSilentInstallInfo'
        'Resolve-AppGetterSandboxStepStatus'
        'Stop-AppGetterSandboxSession'
        'Test-AppGetterSandboxConfirmations'
        'Complete-AppGetterSandboxTest'
        'Get-AppGetterPackageValidation'
    )
    PrivateData       = @{
        PSData = @{
            Tags = @('Intune', 'Web', 'Win32', 'MDM')
        }
    }
}
