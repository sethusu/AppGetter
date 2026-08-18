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
        [string]$DetectedSwitch
    )

    switch ($InstallerExtension.ToLower()) {
        '.msi' { return "msiexec /i `"$InstallerFileName`" /quiet /norestart" }
        '.msix' { return "Add-AppxPackage -Path `"$InstallerFileName`"" }
        '.appx' { return "Add-AppxPackage -Path `"$InstallerFileName`"" }
        default {
            $switchToUse = if ($DetectedSwitch) { $DetectedSwitch } else { '/S' }
            return "`"$InstallerFileName`" $switchToUse"
        }
    }
}

function Get-IntuneUninstallCommandLine {
    return '%windir%\sysnative\windowspowershell\v1.0\powershell.exe -WindowStyle Hidden -ExecutionPolicy Bypass -File uninstall.ps1'
}

function Get-IntuneInstallCommandLine {
    return '%windir%\sysnative\windowspowershell\v1.0\powershell.exe -WindowStyle Hidden -ExecutionPolicy Bypass -File install.ps1'
}

function Get-PackageIdFromAppName {
    param([string]$AppName)
    return ($AppName -replace '[^a-zA-Z0-9]', '')
}

function Get-VersionFromInstallerPath {
    param([string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path)) {
        return $null
    }

    $name = [System.IO.Path]::GetFileNameWithoutExtension($Path)
    if ($name -match '(\d+\.\d+\.\d+\.\d+)') {
        return $matches[1]
    }
    if ($name -match '(\d+\.\d+\.\d+)') {
        return $matches[1]
    }
    if ($name -match '(\d+\.\d+)') {
        return $matches[1]
    }

    return $null
}

function Test-AppGetterInstallerExtension {
    param([string]$Path)

    $extension = [System.IO.Path]::GetExtension($Path).ToLower()
    return $extension -in '.exe', '.msi', '.msix', '.appx'
}
