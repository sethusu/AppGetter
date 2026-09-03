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

function Test-AppGetterLooksLikeFullInstallCommand {
    param(
        [Parameter(Mandatory = $true)]
        [string]$UserInput,
        [string]$InstallerFileName
    )

    $trimmed = $UserInput.Trim()
    if ($trimmed -match '(?i)^(msiexec|add-appxpackage)\b') {
        return $true
    }
    if ($trimmed -match '(?i)^cmd(\.exe)?\s+/c\b') {
        return $true
    }
    if ($InstallerFileName -and ($trimmed -like "*$InstallerFileName*")) {
        return $true
    }
    # Quoted executable or an explicit path, not just switches like /S or ALLUSERS=1
    if ($trimmed -match '^["''][^"'']+\.(exe|msi|msix|appx|msp|bat|cmd)["'']') {
        return $true
    }
    if ($trimmed -match '(?i)^(\.\\|[a-z]:\\|\\\\)') {
        return $true
    }
    # Unix-style path to an installer, not a switch like /VERYSILENT or /qn
    if ($trimmed -match '(?i)^/.+\.(exe|msi|msix|appx|msp|bat|cmd)(\s|$)') {
        return $true
    }
    return $false
}

function Resolve-AppGetterManualInstallCommand {
    <#
    .SYNOPSIS
        Turns user-supplied silent switches or a full command into an install.ps1 command.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$InstallerFileName,
        [Parameter(Mandatory = $true)]
        [string]$UserInput
    )

    $trimmed = $UserInput.Trim()
    if ([string]::IsNullOrWhiteSpace($trimmed)) {
        throw 'User-provided install arguments were empty.'
    }

    if (Test-AppGetterLooksLikeFullInstallCommand -UserInput $trimmed -InstallerFileName $InstallerFileName) {
        return $trimmed
    }

    $extension = [System.IO.Path]::GetExtension($InstallerFileName)
    if (-not $extension) {
        $extension = ''
    }

    switch ($extension.ToLower()) {
        '.msi' {
            if ($trimmed -match '(?i)(^|\s)/i(\s|$)') {
                return "msiexec $trimmed"
            }
            return "msiexec /i `"$InstallerFileName`" $trimmed"
        }
        '.msix' { return "Add-AppxPackage -Path `"$InstallerFileName`"" }
        '.appx' { return "Add-AppxPackage -Path `"$InstallerFileName`"" }
        default { return "`"$InstallerFileName`" $trimmed" }
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
