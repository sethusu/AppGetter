function Extract-IconFromExe {
    param(
        [string]$ExePath,
        [string]$OutputPath
    )

    if (-not $IsWindows) {
        return $false
    }

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
            return (Test-Path $OutputPath) -and ((Get-Item $OutputPath).Length -gt 0)
        }
    } catch {
        return $false
    }

    return $false
}

function Test-ValidImageFile {
    param([string]$Path)

    if (-not (Test-Path $Path)) { return $false }
    $bytes = [System.IO.File]::ReadAllBytes($Path)
    if ($bytes.Length -lt 8) { return $false }

    if ($bytes[0] -eq 0x89 -and $bytes[1] -eq 0x50 -and $bytes[2] -eq 0x4E -and $bytes[3] -eq 0x47) { return $true }
    if ($bytes[0] -eq 0xFF -and $bytes[1] -eq 0xD8 -and $bytes[2] -eq 0xFF) { return $true }
    if ($bytes[0] -eq 0x47 -and $bytes[1] -eq 0x49 -and $bytes[2] -eq 0x46) { return $true }
    return $Path -like '*.svg'
}

function Get-PackageLogoFromWeb {
    param(
        [string]$WebsiteUrl,
        [string]$DeveloperUrl,
        [string]$AppName,
        [string]$OutputPath,
        [string]$InstallerPath,
        [scriptblock]$OnProgress
    )

    $urls = [System.Collections.Generic.List[string]]::new()
    $baseUrls = @()
    if ($WebsiteUrl) { $baseUrls += $WebsiteUrl.TrimEnd('/') }
    if ($DeveloperUrl) { $baseUrls += $DeveloperUrl.TrimEnd('/') }

    foreach ($baseUrl in $baseUrls) {
        $logoPaths = @(
            'logo.png', 'icon.png', 'favicon.png', 'favicon.ico',
            'images/logo.png', 'images/icon.png', 'assets/logo.png', 'assets/icon.png'
        )
        foreach ($path in $logoPaths) {
            $urls.Add("$baseUrl/$path")
        }
    }

    $cleanName = ($AppName -replace '\s+', '' -replace '[^a-zA-Z0-9]', '').ToLowerInvariant()
    if ($cleanName) {
        $urls.Add("https://raw.githubusercontent.com/$cleanName/$cleanName/main/logo.png")
    }

    foreach ($url in ($urls | Select-Object -Unique | Select-Object -First 30)) {
        try {
            Write-AppGetterLog -Message "Trying logo URL: $url" -OnProgress $OnProgress
            Invoke-WebRequest -Uri $url -OutFile $OutputPath -TimeoutSec 5 -ErrorAction Stop
            if (Test-ValidImageFile -Path $OutputPath) {
                return $true
            }
            Remove-Item $OutputPath -ErrorAction SilentlyContinue
        } catch {
            if (Test-Path $OutputPath) {
                Remove-Item $OutputPath -ErrorAction SilentlyContinue
            }
        }
    }

    if ($InstallerPath -and (Test-Path $InstallerPath) -and $InstallerPath -like '*.exe') {
        if (Extract-IconFromExe -ExePath $InstallerPath -OutputPath $OutputPath) {
            return $true
        }
    }

    return $false
}

function Set-AppGetterPackageIconFiles {
    param(
        [Parameter(Mandatory = $true)]
        [string]$SourceIconPath,
        [Parameter(Mandatory = $true)]
        [string]$LogoFilePath,
        [Parameter(Mandatory = $true)]
        [string]$IconFilePath
    )

    $logoDirectory = Split-Path $LogoFilePath -Parent
    if (-not (Test-Path $logoDirectory)) {
        New-Item -ItemType Directory -Path $logoDirectory -Force | Out-Null
    }

    Copy-Item -Path $SourceIconPath -Destination $LogoFilePath -Force
    Copy-Item -Path $SourceIconPath -Destination $IconFilePath -Force
}

function Resolve-PackageIcon {
    param(
        [string]$WebsiteUrl,
        [string]$DeveloperUrl,
        [string]$AppName,
        [string]$LogoFilePath,
        [string]$IconFilePath,
        [string]$InstallerPath,
        [string]$CustomIconPath,
        [scriptblock]$OnProgress
    )

    if ($CustomIconPath -and (Test-Path $CustomIconPath)) {
        Set-AppGetterPackageIconFiles -SourceIconPath $CustomIconPath -LogoFilePath $LogoFilePath -IconFilePath $IconFilePath
        return $true
    }

    if (Test-Path $LogoFilePath) {
        Copy-Item -Path $LogoFilePath -Destination $IconFilePath -Force
        return $true
    }

    $downloaded = Get-PackageLogoFromWeb -WebsiteUrl $WebsiteUrl -DeveloperUrl $DeveloperUrl `
        -AppName $AppName -OutputPath $LogoFilePath -InstallerPath $InstallerPath -OnProgress $OnProgress

    if ($downloaded -and (Test-Path $LogoFilePath)) {
        Copy-Item -Path $LogoFilePath -Destination $IconFilePath -Force
        return $true
    }

    return $false
}
