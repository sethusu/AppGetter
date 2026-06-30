function Set-AppGetterPackageIconFiles {
    param(
        [Parameter(Mandatory = $true)]
        [string]$SourceIconPath,
        [Parameter(Mandatory = $true)]
        [string]$LogoFilePath,
        [Parameter(Mandatory = $true)]
        [string]$IconFilePath
    )

    $logoDir = Split-Path $LogoFilePath -Parent
    if (-not (Test-Path $logoDir)) {
        New-Item -ItemType Directory -Path $logoDir -Force | Out-Null
    }

    Copy-Item -Path $SourceIconPath -Destination $LogoFilePath -Force
    Copy-Item -Path $SourceIconPath -Destination $IconFilePath -Force
}

function Extract-IconFromExe {
    param(
        [string]$ExePath,
        [string]$OutputPath
    )

    try {
        Add-Type -TypeDefinition @"
        using System;
        using System.Drawing;
        using System.Drawing.Imaging;
        using System.Runtime.InteropServices;
        public class AppGetterIconExtractor {
            [DllImport("shell32.dll", CharSet = CharSet.Auto)]
            public static extern IntPtr ExtractIcon(IntPtr hInst, string lpszExeFileName, int nIconIndex);
            [DllImport("user32.dll")]
            public static extern bool DestroyIcon(IntPtr hIcon);

            public static bool ExtractToPng(string exePath, string outputPath) {
                try {
                    IntPtr hIcon = ExtractIcon(IntPtr.Zero, exePath, 0);
                    if (hIcon != IntPtr.Zero) {
                        Icon icon = Icon.FromHandle(hIcon);
                        using (Bitmap bmp = icon.ToBitmap()) {
                            bmp.Save(outputPath, ImageFormat.Png);
                        }
                        DestroyIcon(hIcon);
                        return true;
                    }
                } catch { }
                return false;
            }
        }
"@ -ErrorAction SilentlyContinue

        if ([AppGetterIconExtractor]::ExtractToPng($ExePath, $OutputPath)) {
            if ((Test-Path $OutputPath) -and (Get-Item $OutputPath).Length -gt 0) {
                return $true
            }
        }
    } catch {
        # Icon extraction is best-effort on Windows only.
    }

    return $false
}

function Test-ImageFile {
    param([string]$Path)

    if (-not (Test-Path $Path)) {
        return $false
    }

    $bytes = [System.IO.File]::ReadAllBytes($Path)
    if ($bytes.Length -le 8) {
        return $false
    }

    return (
        ($bytes[0] -eq 0x89 -and $bytes[1] -eq 0x50 -and $bytes[2] -eq 0x4E -and $bytes[3] -eq 0x47) -or
        ($bytes[0] -eq 0xFF -and $bytes[1] -eq 0xD8 -and $bytes[2] -eq 0xFF) -or
        ($bytes[0] -eq 0x47 -and $bytes[1] -eq 0x49 -and $bytes[2] -eq 0x46) -or
        ($Path -like '*.svg')
    )
}

function Get-PackageLogoFromWeb {
    param(
        [string]$WebsiteUrl,
        [string]$DeveloperUrl,
        [string]$AppName,
        [string]$OutputPath,
        [string]$InstallerPath = $null,
        [scriptblock]$OnProgress
    )

    $urls = @()
    $baseUrls = @()
    if ($WebsiteUrl) { $baseUrls += $WebsiteUrl.TrimEnd('/') }
    if ($DeveloperUrl) { $baseUrls += $DeveloperUrl.TrimEnd('/') }

    foreach ($baseUrl in $baseUrls) {
        if (-not $baseUrl) { continue }

        $logoPaths = @(
            'logo.png', 'logo.svg', 'icon.png', 'icon.svg', 'favicon.png', 'favicon.ico',
            'images/logo.png', 'images/icon.png', 'img/logo.png', 'img/icon.png',
            'static/images/logo.png', 'static/img/logo.png', 'static/logo.png',
            'assets/logo.png', 'assets/icon.png', 'assets/images/logo.png',
            'media/logo.png', 'media/icon.png', 'resources/logo.png',
            'www/logo.png', 'www/images/logo.png', 'public/logo.png',
            'app/logo.png', 'src/logo.png', 'dist/logo.png',
            "$($AppName.ToLower()).png", "$($AppName.ToLower()).svg"
        )

        foreach ($path in $logoPaths) {
            $urls += "$baseUrl/$path"
        }
    }

    $cleanName = $AppName -replace '\s+', '' -replace '[^a-zA-Z0-9]', ''
    $lowerName = $cleanName.ToLower()
    if ($cleanName) {
        $urls += @(
            "https://raw.githubusercontent.com/$lowerName/$lowerName/main/logo.png",
            "https://raw.githubusercontent.com/$lowerName/$lowerName/master/logo.png"
        )
    }

    $urls = $urls | Select-Object -Unique | Select-Object -First 30

    foreach ($url in $urls) {
        try {
            Write-AppGetterLog -Message "Trying to download logo from: $url" -OnProgress $OnProgress
            Invoke-WebRequest -Uri $url -OutFile $OutputPath -ErrorAction Stop -TimeoutSec 5
            if ((Test-Path $OutputPath) -and (Test-ImageFile -Path $OutputPath)) {
                Write-AppGetterLog -Message "Downloaded logo from: $url" -Level Success -OnProgress $OnProgress
                return $true
            }
            Remove-Item $OutputPath -ErrorAction SilentlyContinue
        } catch {
            Remove-Item $OutputPath -ErrorAction SilentlyContinue
        }
    }

    if ($InstallerPath -and (Test-Path $InstallerPath) -and $InstallerPath -like '*.exe') {
        Write-AppGetterLog -Message 'Attempting to extract icon from installer executable...' -OnProgress $OnProgress
        if (Extract-IconFromExe -ExePath $InstallerPath -OutputPath $OutputPath) {
            return $true
        }
    }

    return $false
}

function Resolve-PackageIcon {
    param(
        [string]$WebsiteUrl,
        [string]$DeveloperUrl,
        [string]$AppName,
        [string]$LogoFilePath,
        [string]$IconFilePath,
        [string]$IconPath,
        [string]$InstallerPath,
        [scriptblock]$OnProgress
    )

    if ($IconPath -and (Test-Path $IconPath)) {
        Set-AppGetterPackageIconFiles -SourceIconPath $IconPath -LogoFilePath $LogoFilePath -IconFilePath $IconFilePath
        return $true
    }

    if (Test-Path $LogoFilePath) {
        Copy-Item -Path $LogoFilePath -Destination $IconFilePath -Force
        return $true
    }

    $logoDownloaded = Get-PackageLogoFromWeb -WebsiteUrl $WebsiteUrl -DeveloperUrl $DeveloperUrl `
        -AppName $AppName -OutputPath $LogoFilePath -InstallerPath $InstallerPath -OnProgress $OnProgress

    if ($logoDownloaded -and (Test-Path $LogoFilePath)) {
        Copy-Item -Path $LogoFilePath -Destination $IconFilePath -Force
        return $true
    }

    return $false
}
