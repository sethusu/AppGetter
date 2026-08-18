$privateScripts = @(
    'Write-AppGetterLog.ps1'
    'Settings.ps1'
    'Assets.ps1'
    'Web.ps1'
    'SwitchDiscovery.ps1'
    'IconResolution.ps1'
    'Scripts.ps1'
    'Packaging.ps1'
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
    'Resolve-AppGetterInstallerSource'
    'Copy-AppGetterLocalInstaller'
    'Get-AppGetterInstallerFileNameFromUrl'
    'Get-PackageIdFromAppName'
    'Get-AppGetterDefaultBaseOutputPath'
    'Get-AppGetterBaseOutputPath'
    'Get-AppGetterAppOutputPath'
    'Get-AppGetterSettings'
    'Save-AppGetterSettings'
    'Test-AppGetterPrerequisites'
    'Resolve-AppGetterContentPrepToolPath'
    'Install-AppGetterContentPrepTool'
    'Resolve-PackageIcon'
    'Resolve-AppGetterIconCandidates'
    'Set-AppGetterPackageIconFiles'
)
