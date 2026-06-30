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

function Start-WebInstallerDownload {
    param(
        [string]$DownloadUrl,
        [string]$OutputPath,
        [string]$FileName,
        [scriptblock]$OnProgress
    )

    Write-AppGetterProgress -Step 4 -StepName 'Downloading installer' -Percent 10 -Message "Starting download from $DownloadUrl" -OnProgress $OnProgress

    try {
        Invoke-WebRequest -Uri $DownloadUrl -OutFile $OutputPath -UseBasicParsing -ErrorAction Stop
    } catch {
        throw "Download failed: $_"
    }

    if (-not (Test-Path $OutputPath)) {
        throw 'Download completed but output file was not found.'
    }

    $sizeMB = [math]::Round((Get-Item $OutputPath).Length / 1MB, 2)
    Write-AppGetterProgress -Step 4 -StepName 'Downloading installer' -Percent 100 -Message "Downloaded $FileName ($sizeMB MB)" -OnProgress $OnProgress
}
