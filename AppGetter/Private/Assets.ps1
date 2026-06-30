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
        [string]$CustomInstallCommand
    )

    if ($CustomInstallCommand) {
        return $CustomInstallCommand
    }

    switch ($InstallerExtension.ToLower()) {
        '.msi' { return "msiexec /i `"$InstallerFileName`" /quiet /norestart" }
        '.msix' { return "Add-AppxPackage -Path `"$InstallerFileName`"" }
        '.appx' { return "Add-AppxPackage -Path `"$InstallerFileName`"" }
        default { return "`"$InstallerFileName`" /S" }
    }
}

function Get-IntuneUninstallCommandLine {
    return '%windir%\sysnative\windowspowershell\v1.0\powershell.exe -WindowStyle Hidden -ExecutionPolicy Bypass -File uninstall.ps1'
}

function Get-IntuneInstallCommandLine {
    return '%windir%\sysnative\windowspowershell\v1.0\powershell.exe -WindowStyle Hidden -ExecutionPolicy Bypass -File install.ps1'
}

function Get-InstallerFileNameFromUrl {
    param([string]$Url)

    $fileName = Split-Path -Leaf $Url
    if ($fileName -match '([^?]+)') {
        $fileName = $matches[1]
    }

    if ([string]::IsNullOrWhiteSpace($fileName)) {
        throw 'Could not determine installer file name from download URL.'
    }

    return $fileName
}

function Start-WebInstallerDownload {
    param(
        [string]$DownloadUrl,
        [string]$DownloadDirectory,
        [string]$FileName,
        [scriptblock]$OnProgress
    )

    $destination = Join-Path $DownloadDirectory $FileName
    Write-AppGetterProgress -Step 3 -StepName 'Downloading installer' -Percent 10 -Message "Starting download from $DownloadUrl" -OnProgress $OnProgress

    try {
        $ProgressPreference = 'SilentlyContinue'
        Invoke-WebRequest -Uri $DownloadUrl -OutFile $destination -UseBasicParsing -ErrorAction Stop

        if (-not (Test-Path $destination)) {
            throw 'Download completed but installer file was not found.'
        }

        $sizeMB = [math]::Round((Get-Item $destination).Length / 1MB, 2)
        Write-AppGetterProgress -Step 3 -StepName 'Downloading installer' -Percent 30 -Message "Downloaded $FileName ($sizeMB MB)" -OnProgress $OnProgress
        return $destination
    } catch {
        throw "Failed to download installer: $_"
    }
}

function Get-SanitizedPackageId {
    param([string]$AppName)
    return ($AppName -replace '[^a-zA-Z0-9]', '')
}
