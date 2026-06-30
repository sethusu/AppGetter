function Set-AppGetterPackageIconFiles {
    param(
        [Parameter(Mandatory = $true)]
        [string]$SourceIconPath,
        [string]$LogoFilePath,
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

    if (-not ($IsWindows -or $PSVersionTable.PSVersion.Major -ge 6 -and $IsWindows)) {
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
            if ((Test-Path $OutputPath) -and (Get-Item $OutputPath).Length -gt 0) {
                return $true
            }
        }
    } catch {
        # Icon extraction is best-effort on Windows only
    }

    return $false
}

function Test-ImageBytes {
    param([byte[]]$Bytes)

    if (-not $Bytes -or $Bytes.Length -lt 8) {
        return $false
    }

    if ($Bytes[0] -eq 0x89 -and $Bytes[1] -eq 0x50 -and $Bytes[2] -eq 0x4E -and $Bytes[3] -eq 0x47) { return $true }
    if ($Bytes[0] -eq 0xFF -and $Bytes[1] -eq 0xD8 -and $Bytes[2] -eq 0xFF) { return $true }
    if ($Bytes[0] -eq 0x47 -and $Bytes[1] -eq 0x49 -and $Bytes[2] -eq 0x46) { return $true }
    return $false
}

function Get-PackageLogoFromWeb {
    param(
        [string]$AppName,
        [string]$WebsiteUrl,
        [string]$DeveloperUrl,
        [string]$OutputPath,
        [string]$InstallerPath,
        [scriptblock]$OnProgress
    )

    $urls = @()
    $baseUrls = @()
    if ($WebsiteUrl) { $baseUrls += $WebsiteUrl.TrimEnd('/') }
    if ($DeveloperUrl) { $baseUrls += $DeveloperUrl.TrimEnd('/') }

    foreach ($baseUrl in $baseUrls) {
        if ($baseUrl) {
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
            Write-AppGetterProgress -Step 8 -StepName 'Resolving icon' -Percent 75 -Message "Trying $url" -OnProgress $OnProgress
            Invoke-WebRequest -Uri $url -OutFile $OutputPath -ErrorAction Stop -TimeoutSec 5
            if (Test-Path $OutputPath) {
                $bytes = [System.IO.File]::ReadAllBytes($OutputPath)
                if ((Test-ImageBytes -Bytes $bytes) -or $OutputPath -like '*.svg') {
                    return $true
                }
                Remove-Item $OutputPath -ErrorAction SilentlyContinue
            }
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

function Resolve-PackageIconCandidates {
    param(
        [string]$AppName,
        [string]$WebsiteUrl,
        [string]$DeveloperUrl,
        [string]$InstallerPath,
        [string]$StagingDirectory,
        [int]$MaximumCount = 3,
        [scriptblock]$OnProgress
    )

    if (-not (Test-Path $StagingDirectory)) {
        New-Item -ItemType Directory -Path $StagingDirectory -Force | Out-Null
    }

    $candidates = @()
    $baseUrls = @()
    if ($WebsiteUrl) { $baseUrls += $WebsiteUrl.TrimEnd('/') }
    if ($DeveloperUrl) { $baseUrls += $DeveloperUrl.TrimEnd('/') }

    $iconPaths = @('logo.png', 'icon.png', 'favicon.png', 'images/logo.png', 'assets/logo.png')
    $index = 0

    foreach ($baseUrl in $baseUrls) {
        foreach ($path in $iconPaths) {
            if ($candidates.Count -ge $MaximumCount) { break }
            $url = "$baseUrl/$path"
            $candidatePath = Join-Path $StagingDirectory "candidate-$index.png"
            try {
                Invoke-WebRequest -Uri $url -OutFile $candidatePath -ErrorAction Stop -TimeoutSec 5
                if ((Test-Path $candidatePath) -and (Test-ImageBytes -Bytes ([System.IO.File]::ReadAllBytes($candidatePath)))) {
                    $candidates += [PSCustomObject]@{
                        Path   = $candidatePath
                        Url    = $url
                        Source = 'Website'
                        Label  = "Website: $path"
                    }
                    $index++
                } else {
                    Remove-Item $candidatePath -ErrorAction SilentlyContinue
                }
            } catch {
                if (Test-Path $candidatePath) {
                    Remove-Item $candidatePath -ErrorAction SilentlyContinue
                }
            }
        }
    }

    if ($candidates.Count -lt $MaximumCount -and $InstallerPath -and (Test-Path $InstallerPath) -and $InstallerPath -like '*.exe') {
        $exeCandidate = Join-Path $StagingDirectory 'candidate-installer.png'
        if (Extract-IconFromExe -ExePath $InstallerPath -OutputPath $exeCandidate) {
            $candidates += [PSCustomObject]@{
                Path   = $exeCandidate
                Url    = $InstallerPath
                Source = 'Installer EXE'
                Label  = 'Installer icon'
            }
        }
    }

    return $candidates
}

function Resolve-PackageIcon {
    param(
        [string]$AppName,
        [string]$WebsiteUrl,
        [string]$DeveloperUrl,
        [string]$LogoFilePath,
        [string]$InstallerPath,
        [scriptblock]$OnProgress
    )

    return Get-PackageLogoFromWeb -AppName $AppName -WebsiteUrl $WebsiteUrl -DeveloperUrl $DeveloperUrl `
        -OutputPath $LogoFilePath -InstallerPath $InstallerPath -OnProgress $OnProgress
}
