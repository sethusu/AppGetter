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

function Get-AppGetterInstallerExtensionFromBytes {
    <#
    .SYNOPSIS
        Detects .msi / .exe / .msix from file signatures (not the file name).
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return $null
    }

    try {
        $stream = [System.IO.File]::Open($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
        try {
            $header = New-Object byte[] 8
            $read = $stream.Read($header, 0, 8)
            if ($read -lt 2) {
                return $null
            }

            # OLE compound document used by MSI
            if ($read -ge 8 -and
                $header[0] -eq 0xD0 -and $header[1] -eq 0xCF -and
                $header[2] -eq 0x11 -and $header[3] -eq 0xE0 -and
                $header[4] -eq 0xA1 -and $header[5] -eq 0xB1 -and
                $header[6] -eq 0x1A -and $header[7] -eq 0xE1) {
                return '.msi'
            }

            # ZIP / MSIX / APPX — only trust explicit package extensions.
            if ($header[0] -eq 0x50 -and $header[1] -eq 0x4B) {
                $name = [System.IO.Path]::GetFileName($Path).ToLowerInvariant()
                if ($name.EndsWith('.msix')) { return '.msix' }
                if ($name.EndsWith('.appx')) { return '.appx' }
                return $null
            }

            # PE executable
            if ($header[0] -eq 0x4D -and $header[1] -eq 0x5A) {
                return '.exe'
            }
        } finally {
            $stream.Dispose()
        }
    } catch {
        return $null
    }

    return $null
}

function Test-AppGetterInstallerCandidateFile {
    param(
        [Parameter(Mandatory = $true)]
        [System.IO.FileInfo]$File
    )

    if ($File.Name -like '*intunewin*') {
        return $false
    }

    $ext = $File.Extension.ToLowerInvariant()
    if ($ext -in '.exe', '.msi', '.msix', '.appx') {
        return $true
    }

    # Extensionless marketing URLs (e.g. .../download-the-v-one-software) still count
    # when the on-disk payload is a real installer.
    $detected = Get-AppGetterInstallerExtensionFromBytes -Path $File.FullName
    return [bool]$detected
}

function Repair-AppGetterInstallerFileName {
    <#
    .SYNOPSIS
        Renames a downloaded installer so it has the correct .msi/.exe extension.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,
        [string]$PreferredFileName
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Installer file not found: $Path"
    }

    $directory = Split-Path -Path $Path -Parent
    $currentName = [System.IO.Path]::GetFileName($Path)
    $detectedExt = Get-AppGetterInstallerExtensionFromBytes -Path $Path
    if (-not $detectedExt) {
        $length = (Get-Item -LiteralPath $Path).Length
        $preview = ''
        try {
            $bytes = [System.IO.File]::ReadAllBytes($Path)
            $take = [Math]::Min(80, $bytes.Length)
            $preview = [System.Text.Encoding]::ASCII.GetString($bytes, 0, $take) -replace '\s+', ' '
        } catch { }

        throw ("Downloaded file is not a Windows installer (.exe/.msi). Size=$length bytes. Preview='$preview'")
    }

    $baseName = if (-not [string]::IsNullOrWhiteSpace($PreferredFileName)) {
        [System.IO.Path]::GetFileNameWithoutExtension($PreferredFileName)
    } else {
        [System.IO.Path]::GetFileNameWithoutExtension($currentName)
    }
    if ([string]::IsNullOrWhiteSpace($baseName) -or $baseName -eq $currentName) {
        # Extensionless current name: use it as the base.
        $baseName = [System.IO.Path]::GetFileNameWithoutExtension($currentName)
        if ([string]::IsNullOrWhiteSpace($baseName)) {
            $baseName = $currentName
        }
    }

    # Sanitize odd URL leaf names.
    $baseName = ($baseName -replace '[<>:"/\\|?*]', '-').Trim().TrimEnd('.')
    if ([string]::IsNullOrWhiteSpace($baseName)) {
        $baseName = 'setup'
    }

    $targetName = "$baseName$detectedExt"
    $targetPath = Join-Path $directory $targetName

    if ([string]::Equals($Path, $targetPath, [StringComparison]::OrdinalIgnoreCase)) {
        return [PSCustomObject]@{
            Path = $Path
            FileName = $currentName
            Renamed = $false
            PreviousFileName = $currentName
            Extension = $detectedExt
        }
    }

    if (Test-Path -LiteralPath $targetPath) {
        Remove-Item -LiteralPath $targetPath -Force -ErrorAction SilentlyContinue
    }
    Move-Item -LiteralPath $Path -Destination $targetPath -Force

    return [PSCustomObject]@{
        Path = $targetPath
        FileName = $targetName
        Renamed = $true
        PreviousFileName = $currentName
        Extension = $detectedExt
    }
}

function Update-AppGetterPackageInstallerReferences {
    <#
    .SYNOPSIS
        Updates install.ps1 / app.json / silent-switches.json when an installer is renamed.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$VersionDirectory,
        [Parameter(Mandatory = $true)]
        [string]$OldFileName,
        [Parameter(Mandatory = $true)]
        [string]$NewFileName
    )

    if ([string]::Equals($OldFileName, $NewFileName, [StringComparison]::OrdinalIgnoreCase)) {
        return
    }

    $installScript = Join-Path $VersionDirectory 'install.ps1'
    if (Test-Path -LiteralPath $installScript) {
        $raw = Get-Content -LiteralPath $installScript -Raw -ErrorAction SilentlyContinue
        if ($raw -and $raw.Contains($OldFileName)) {
            $updated = $raw.Replace($OldFileName, $NewFileName)
            Set-Content -LiteralPath $installScript -Value $updated -Encoding UTF8
        }
    }

    foreach ($name in @('app.json', 'silent-switches.json', 'README.md', 'readme.txt')) {
        $path = Join-Path $VersionDirectory $name
        if (-not (Test-Path -LiteralPath $path)) { continue }
        try {
            $raw = Get-Content -LiteralPath $path -Raw -ErrorAction Stop
            if ($raw -and $raw.Contains($OldFileName)) {
                Set-Content -LiteralPath $path -Value ($raw.Replace($OldFileName, $NewFileName)) -Encoding UTF8
            }
        } catch { }
    }
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
