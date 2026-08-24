$privateScripts = @(
    'Write-AppGetterLog.ps1'
    'Settings.ps1'
    'Assets.ps1'
    'Web.ps1'
    'SwitchDiscovery.ps1'
    'IconResolution.ps1'
    'Scripts.ps1'
    'Packaging.ps1'
    'Sandbox.ps1'
)

$privateRoot = Join-Path $PSScriptRoot 'Private'
foreach ($scriptName in $privateScripts) {
    $scriptPath = Join-Path $privateRoot $scriptName
    if (Test-Path $scriptPath) {
        . $scriptPath
    }
}

Export-ModuleMember -Function @(
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
    'Test-InstallerCommandInSandbox'
    'Start-AppGetterSandboxTrialSession'
    'Get-AppGetterSandboxTrialResult'
    'Wait-AppGetterSandboxTrialResult'
    'Stop-AppGetterSandboxTrialSession'
    'New-AppGetterSandboxTrialPackage'
    'New-AppGetterSandboxTrialGuestScript'
    'Test-AppGetterAcceptedInstallExitCode'
    'Resolve-InstallerInstallCommand'
    'Get-InstallerFingerprint'
)
