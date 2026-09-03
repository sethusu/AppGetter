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

function ConvertTo-AppGetterUserInstallCommand {
    <#
    .SYNOPSIS
        Builds an install command from user-supplied switches or a full command line.
    .DESCRIPTION
        Accepts either a complete command (msiexec /i setup.msi /qn, "setup.exe" /S)
        or arguments only (/VERYSILENT /NORESTART). Argument-only input is prefixed
        with the downloaded installer file name (msiexec /i for MSI).
    #>
    param(
        [string]$InstallerFileName,
        [string]$UserInput
    )

    if ([string]::IsNullOrWhiteSpace($UserInput)) {
        return $null
    }

    $trimmed = $UserInput.Trim()
    if ($InstallerFileName -and $trimmed.Contains('{installer}')) {
        $trimmed = $trimmed.Replace('{installer}', $InstallerFileName)
    }

    $looksLikeFullCommand = $false
    if ($trimmed -match '(?i)\bmsiexec\b') {
        $looksLikeFullCommand = $true
    } elseif ($trimmed -match '(?i)^\s*Add-AppxPackage\b') {
        $looksLikeFullCommand = $true
    } elseif ($trimmed -match '(?i)^\s*".+\.(exe|msi|msix|appx)"') {
        $looksLikeFullCommand = $true
    } elseif ($trimmed -match '(?i)^\s*\S+\.(exe|msi|msix|appx)(\s|$)') {
        $looksLikeFullCommand = $true
    } elseif ($InstallerFileName -and $trimmed.IndexOf($InstallerFileName, [StringComparison]::OrdinalIgnoreCase) -ge 0) {
        $looksLikeFullCommand = $true
    }

    if ($looksLikeFullCommand) {
        return $trimmed
    }

    if ([string]::IsNullOrWhiteSpace($InstallerFileName)) {
        return $trimmed
    }

    $extension = [System.IO.Path]::GetExtension($InstallerFileName)
    switch ($extension.ToLowerInvariant()) {
        '.msi' { return "msiexec /i `"$InstallerFileName`" $trimmed" }
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
