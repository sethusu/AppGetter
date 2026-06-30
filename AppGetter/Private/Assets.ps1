function Get-ImageMimeType {
    param(
        [Parameter(Mandatory = $true)]
        [byte[]]$Bytes
    )

    if (-not $Bytes -or $Bytes.Length -lt 4) {
        return $null
    }

    if ($Bytes[0] -eq 0x89 -and $Bytes[1] -eq 0x50 -and $Bytes[2] -eq 0x4E -and $Bytes[3] -eq 0x47) {
        return 'image/png'
    }

    if ($Bytes.Length -ge 3 -and $Bytes[0] -eq 0xFF -and $Bytes[1] -eq 0xD8 -and $Bytes[2] -eq 0xFF) {
        return 'image/jpeg'
    }

    if ($Bytes.Length -ge 3 -and $Bytes[0] -eq 0x47 -and $Bytes[1] -eq 0x49 -and $Bytes[2] -eq 0x46) {
        return 'image/gif'
    }

    return $null
}

function Get-InstallerInstallCommand {
    param(
        [string]$InstallerFileName,
        [string]$InstallerExtension,
        [string[]]$SilentSwitches = @()
    )

    switch ($InstallerExtension.ToLower()) {
        '.msi' { return "msiexec /i `"$InstallerFileName`" /quiet /norestart" }
        '.msix' { return "Add-AppxPackage -Path `"$InstallerFileName`"" }
        '.appx' { return "Add-AppxPackage -Path `"$InstallerFileName`"" }
        default {
            if ($SilentSwitches -and $SilentSwitches.Count -gt 0) {
                return "`"$InstallerFileName`" $($SilentSwitches[0])"
            }
            return "`"$InstallerFileName`" /S"
        }
    }
}

function Get-IntuneUninstallCommandLine {
    return '%windir%\sysnative\windowspowershell\v1.0\powershell.exe -WindowStyle Hidden -ExecutionPolicy Bypass -File uninstall.ps1'
}

function Get-IntuneInstallCommandLine {
    return '%windir%\sysnative\windowspowershell\v1.0\powershell.exe -WindowStyle Hidden -ExecutionPolicy Bypass -File install.ps1'
}

function New-AppGetterPackageId {
    param([string]$AppName)
    return ($AppName -replace '[^a-zA-Z0-9]', '')
}

function New-AppGetterPackageDetails {
    param(
        [string]$AppName,
        [string]$Version,
        [string]$Publisher,
        [string]$WebsiteUrl,
        [string]$DeveloperUrl,
        [string]$SupportUrl,
        [string]$DownloadUrl,
        [string]$Description
    )

    $packageId = New-AppGetterPackageId -AppName $AppName
    $homepage = if ($WebsiteUrl) { $WebsiteUrl } elseif ($DeveloperUrl) { $DeveloperUrl } else { '' }
    $resolvedDescription = if ($Description) {
        $Description
    } elseif ($Publisher) {
        "$AppName by $Publisher - packaged from web download"
    } else {
        "$AppName - packaged from web download"
    }

    return [PSCustomObject]@{
        PackageId     = $packageId
        DisplayName   = $AppName
        Version       = $Version
        Publisher     = if ($Publisher) { $Publisher } else { 'Unknown' }
        Developer     = if ($Publisher) { $Publisher } else { 'Unknown' }
        Homepage      = $homepage
        WebsiteUrl    = $WebsiteUrl
        DeveloperUrl  = $DeveloperUrl
        SupportUrl    = $SupportUrl
        DownloadUrl   = $DownloadUrl
        Description   = $resolvedDescription
    }
}
