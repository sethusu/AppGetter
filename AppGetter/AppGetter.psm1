$privateScripts = @(
    'Write-AppGetterLog.ps1'
    'Settings.ps1'
    'Assets.ps1'
    'Web.ps1'
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
    'Get-WebPackageDetails'
    'Get-DownloadLinksFromWeb'
    'Invoke-AppGetterPackaging'
    'Get-AppGetterSettings'
    'Save-AppGetterSettings'
    'Test-AppGetterPrerequisites'
    'Resolve-PackageIcon'
    'Resolve-PackageIconCandidates'
    'Set-AppGetterPackageIconFiles'
)
