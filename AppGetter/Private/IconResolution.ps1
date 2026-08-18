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

function Export-IconFromExe {
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

function Get-AppGetterIconCandidateUrls {
    <#
    .SYNOPSIS
        Builds a scored list of candidate icon URLs for an application.
    #>
    param(
        [string]$WebsiteUrl,
        [string]$DeveloperUrl,
        [string]$AppName
    )

    $candidates = [System.Collections.ArrayList]@()
    $seenUrls = @{}

    function Add-Candidate {
        param([string]$Url, [string]$Source, [int]$Score)

        if ([string]::IsNullOrWhiteSpace($Url) -or $seenUrls.ContainsKey($Url)) {
            return
        }
        $seenUrls[$Url] = $true
        [void]$candidates.Add([PSCustomObject]@{
                Url    = $Url
                Source = $Source
                Score  = $Score
            })
    }

    $lowerName = ($AppName -replace '\s+', '' -replace '[^a-zA-Z0-9]', '').ToLower()

    $sites = @()
    if ($WebsiteUrl) { $sites += [PSCustomObject]@{ Url = $WebsiteUrl.TrimEnd('/'); Source = 'Website'; Score = 900 } }
    if ($DeveloperUrl) { $sites += [PSCustomObject]@{ Url = $DeveloperUrl.TrimEnd('/'); Source = 'Developer site'; Score = 800 } }

    foreach ($site in $sites) {
        if (-not $site.Url) { continue }

        $namedPaths = @()
        if ($lowerName) {
            $namedPaths = @("$lowerName.png", "$lowerName.svg", "images/$lowerName.png", "img/$lowerName.png")
        }

        $logoPaths = @(
            'logo.png', 'logo.svg', 'icon.png', 'icon.svg',
            'images/logo.png', 'images/icon.png', 'img/logo.png', 'img/icon.png',
            'static/images/logo.png', 'static/img/logo.png', 'static/logo.png',
            'assets/logo.png', 'assets/icon.png', 'assets/images/logo.png',
            'media/logo.png', 'media/icon.png', 'resources/logo.png',
            'www/logo.png', 'www/images/logo.png', 'public/logo.png',
            'app/logo.png', 'src/logo.png', 'dist/logo.png'
        )

        $pathIndex = 0
        foreach ($path in ($namedPaths + $logoPaths)) {
            Add-Candidate -Url "$($site.Url)/$path" -Source $site.Source -Score ($site.Score - $pathIndex)
            $pathIndex++
        }

        Add-Candidate -Url "$($site.Url)/favicon.png" -Source 'Favicon' -Score 400
        Add-Candidate -Url "$($site.Url)/favicon.ico" -Source 'Favicon' -Score 390

        try {
            $siteRoot = ([Uri]$site.Url).GetLeftPart([System.UriPartial]::Authority)
            if ($siteRoot) {
                Add-Candidate -Url "$siteRoot/favicon.ico" -Source 'Favicon' -Score 380
                Add-Candidate -Url "$siteRoot/apple-touch-icon.png" -Source 'Favicon' -Score 370
            }
        } catch {
            Write-Verbose "Could not derive site root from $($site.Url)"
        }
    }

    if ($lowerName) {
        Add-Candidate -Url "https://raw.githubusercontent.com/$lowerName/$lowerName/main/logo.png" -Source 'GitHub' -Score 300
        Add-Candidate -Url "https://raw.githubusercontent.com/$lowerName/$lowerName/master/logo.png" -Source 'GitHub' -Score 290
    }

    return @($candidates | Sort-Object -Property Score -Descending)
}

function Save-AppGetterIconFromUrl {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Url,
        [Parameter(Mandatory = $true)]
        [string]$OutputPath,
        [scriptblock]$OnProgress
    )

    try {
        Write-AppGetterLog -Message "Trying to download logo from: $Url" -OnProgress $OnProgress
        Invoke-WebRequest -Uri $Url -OutFile $OutputPath -UseBasicParsing -ErrorAction Stop -TimeoutSec 5
        if ((Test-Path $OutputPath) -and (Test-ImageFile -Path $OutputPath)) {
            Write-AppGetterLog -Message "Downloaded logo from: $Url" -Level Success -OnProgress $OnProgress
            return $true
        }
    } catch {
        Write-Verbose "Icon download failed for $Url : $_"
    }

    Remove-Item $OutputPath -Force -ErrorAction SilentlyContinue
    return $false
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

    $candidates = @(Get-AppGetterIconCandidateUrls -WebsiteUrl $WebsiteUrl -DeveloperUrl $DeveloperUrl -AppName $AppName |
            Select-Object -First 30)

    foreach ($candidate in $candidates) {
        if (Save-AppGetterIconFromUrl -Url $candidate.Url -OutputPath $OutputPath -OnProgress $OnProgress) {
            return $true
        }
    }

    if ($InstallerPath -and (Test-Path $InstallerPath) -and $InstallerPath -like '*.exe') {
        Write-AppGetterLog -Message 'Attempting to extract icon from installer executable...' -OnProgress $OnProgress
        if (Export-IconFromExe -ExePath $InstallerPath -OutputPath $OutputPath) {
            return $true
        }
    }

    return $false
}

function Resolve-AppGetterIconCandidates {
    <#
    .SYNOPSIS
        Downloads up to MaximumCount distinct icon candidates so the GUI can offer a choice.
    .DESCRIPTION
        The installer's own icon is tried first because it is the most trustworthy signal for
        Intune packaging, followed by scored website/favicon candidates. Duplicates are removed
        by file hash so the picker never shows the same image twice.
    #>
    param(
        [string]$WebsiteUrl,
        [string]$DeveloperUrl,
        [string]$AppName,
        [string]$InstallerPath = $null,
        [int]$MaximumCount = 3,
        [string]$StagingDirectory = $null,
        [scriptblock]$OnProgress
    )

    if ($MaximumCount -lt 1) {
        return @()
    }

    if (-not $StagingDirectory) {
        $tempRoot = if ($env:TEMP) { $env:TEMP } else { [System.IO.Path]::GetTempPath() }
        $StagingDirectory = Join-Path $tempRoot ("appgetter-icon-candidates-{0}" -f ([Guid]::NewGuid().ToString('N')))
    }
    if (-not (Test-Path $StagingDirectory)) {
        New-Item -ItemType Directory -Path $StagingDirectory -Force | Out-Null
    }

    $results = [System.Collections.ArrayList]@()
    $seenHashes = @{}

    if ($InstallerPath -and (Test-Path $InstallerPath) -and $InstallerPath -like '*.exe') {
        $installerCandidatePath = Join-Path $StagingDirectory 'candidate-installer.png'
        if (Export-IconFromExe -ExePath $InstallerPath -OutputPath $installerCandidatePath) {
            $fileHash = (Get-FileHash -Path $installerCandidatePath -Algorithm SHA256).Hash
            $seenHashes[$fileHash] = $true
            [void]$results.Add([PSCustomObject]@{
                    Path   = $installerCandidatePath
                    Url    = $InstallerPath
                    Source = 'Installer'
                    Score  = 1100
                    Label  = "Option $($results.Count + 1)"
                })
        }
    }

    foreach ($candidate in (Get-AppGetterIconCandidateUrls -WebsiteUrl $WebsiteUrl -DeveloperUrl $DeveloperUrl -AppName $AppName)) {
        if ($results.Count -ge $MaximumCount) { break }

        $stagingPath = Join-Path $StagingDirectory ("candidate-{0}.png" -f ($results.Count + 1))
        if (-not (Save-AppGetterIconFromUrl -Url $candidate.Url -OutputPath $stagingPath -OnProgress $OnProgress)) {
            continue
        }

        $fileHash = (Get-FileHash -Path $stagingPath -Algorithm SHA256).Hash
        if ($seenHashes.ContainsKey($fileHash)) {
            Remove-Item $stagingPath -Force -ErrorAction SilentlyContinue
            continue
        }
        $seenHashes[$fileHash] = $true

        [void]$results.Add([PSCustomObject]@{
                Path   = $stagingPath
                Url    = $candidate.Url
                Source = $candidate.Source
                Score  = $candidate.Score
                Label  = "Option $($results.Count + 1)"
            })
    }

    if ($results.Count -eq 0) {
        Write-AppGetterLog -Message "No icon candidates could be downloaded for $AppName" -Level Warning -OnProgress $OnProgress
    } else {
        Write-AppGetterLog -Message "Collected $($results.Count) icon candidate(s) for $AppName" -Level Success -OnProgress $OnProgress
    }

    return @($results)
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
