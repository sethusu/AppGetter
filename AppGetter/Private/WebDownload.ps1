function Get-DownloadLinksFromWeb {
    param(
        [string]$Url,
        [string]$AppName
    )

    try {
        $response = Invoke-WebRequest -Uri $Url -UseBasicParsing -ErrorAction Stop
        $html = $response.Content

        $patterns = @(
            "href\s*=\s*['""]([^'""]*\.(exe|msi|msix|appx|zip|7z))['""]",
            "href\s*=\s*['""]([^'""]*download[^'""]*)['""]",
            "href\s*=\s*['""]([^'""]*install[^'""]*)['""]",
            "href\s*=\s*['""]([^'""]*setup[^'""]*)['""]"
        )

        $downloadLinks = @()
        foreach ($pattern in $patterns) {
            $patternMatches = [regex]::Matches($html, $pattern, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
            foreach ($match in $patternMatches) {
                $link = $match.Groups[1].Value
                if ($link -notlike 'http*') {
                    $uri = [System.Uri]::new([System.Uri]$Url, $link)
                    $link = $uri.AbsoluteUri
                }
                if ($link -notin $downloadLinks) {
                    $downloadLinks += $link
                }
            }
        }

        if ($html -match '(https?://[^\s<>""'']+\.(exe|msi|msix|appx))') {
            $directLink = $matches[1]
            if ($directLink -notin $downloadLinks) {
                $downloadLinks += $directLink
            }
        }

        return $downloadLinks
    } catch {
        Write-Warning "Error fetching webpage: $_"
        return @()
    }
}

function Get-VersionFromWeb {
    param(
        [string]$Url,
        [string]$AppName
    )

    try {
        $response = Invoke-WebRequest -Uri $Url -UseBasicParsing -ErrorAction Stop
        $html = $response.Content

        $versionPatterns = @(
            'Version\s+(\d+\.\d+\.\d+\.\d+)',
            'Version\s+(\d+\.\d+\.\d+)',
            'v(\d+\.\d+\.\d+\.\d+)',
            'v(\d+\.\d+\.\d+)',
            "$([regex]::Escape($AppName))\s+(\d+\.\d+\.\d+\.\d+)",
            "$([regex]::Escape($AppName))\s+(\d+\.\d+\.\d+)"
        )

        foreach ($pattern in $versionPatterns) {
            if ($html -match $pattern) {
                return $matches[1]
            }
        }
    } catch {
        Write-Warning 'Could not extract version from website.'
    }

    return $null
}

function Get-DescriptionFromWeb {
    param(
        [string]$Url,
        [string]$AppName
    )

    try {
        $response = Invoke-WebRequest -Uri $Url -UseBasicParsing -ErrorAction Stop
        $html = $response.Content

        if ($html -match '<meta\s+name=["'']description["'']\s+content=["'']([^"'']+)["'']') {
            $description = $matches[1]
            if ($description.Length -gt 20) {
                return $description
            }
        }

        if ($html -match '<meta\s+property=["'']og:description["'']\s+content=["'']([^"'']+)["'']') {
            $description = $matches[1]
            if ($description.Length -gt 20) {
                return $description
            }
        }
    } catch {
        Write-Warning "Could not extract description from website: $_"
    }

    return $null
}

function Resolve-WebDownloadUrl {
    param(
        [string]$WebsiteUrl,
        [string]$DownloadUrl,
        [string]$AppName,
        [scriptblock]$OnProgress
    )

    if (-not [string]::IsNullOrWhiteSpace($DownloadUrl)) {
        return $DownloadUrl.Trim()
    }

    if ([string]::IsNullOrWhiteSpace($WebsiteUrl)) {
        throw 'WebsiteUrl or DownloadUrl is required.'
    }

    Write-AppGetterLog -Message "Searching for download links on: $WebsiteUrl" -OnProgress $OnProgress
    $downloadLinks = Get-DownloadLinksFromWeb -Url $WebsiteUrl -AppName $AppName

    if ($downloadLinks.Count -eq 0) {
        throw "No download links found on the website: $WebsiteUrl"
    }

    $selectedUrl = $downloadLinks |
        Where-Object { $_ -like '*.exe' -or $_ -like '*.msi' -or $_ -like '*.msix' -or $_ -like '*.appx' } |
        Select-Object -First 1

    if (-not $selectedUrl) {
        $selectedUrl = $downloadLinks[0]
    }

    return $selectedUrl
}

function Get-InstallerFileNameFromUrl {
    param([string]$Url)

    $fileName = Split-Path -Leaf $Url
    if ($fileName -match '([^?]+)') {
        $fileName = $matches[1]
    }

    if ([string]::IsNullOrWhiteSpace($fileName)) {
        throw "Could not determine installer file name from URL: $Url"
    }

    return $fileName
}

function Start-WebInstallerDownload {
    param(
        [string]$DownloadUrl,
        [string]$DownloadDirectory,
        [string]$InstallerFileName,
        [scriptblock]$OnProgress
    )

    $outputPath = Join-Path $DownloadDirectory $InstallerFileName
    Write-AppGetterLog -Message "Downloading from: $DownloadUrl" -OnProgress $OnProgress

    try {
        Invoke-WebRequest -Uri $DownloadUrl -OutFile $outputPath -UseBasicParsing -ErrorAction Stop
    } catch {
        throw "Download failed: $_"
    }

    if (-not (Test-Path $outputPath)) {
        throw 'Download completed but installer file was not found.'
    }

    $sizeMB = [math]::Round((Get-Item $outputPath).Length / 1MB, 2)
    Write-AppGetterLog -Message "Downloaded: $InstallerFileName ($sizeMB MB)" -Level Success -OnProgress $OnProgress

    return $outputPath
}

function Resolve-WebPackageMetadata {
    param(
        [string]$AppName,
        [string]$Version,
        [string]$Publisher,
        [string]$WebsiteUrl,
        [string]$DeveloperUrl,
        [string]$SupportUrl,
        [string]$DownloadUrl
    )

    $resolvedVersion = $Version
    if ([string]::IsNullOrWhiteSpace($resolvedVersion) -and $WebsiteUrl) {
        $resolvedVersion = Get-VersionFromWeb -Url $WebsiteUrl -AppName $AppName
    }
    if ([string]::IsNullOrWhiteSpace($resolvedVersion)) {
        $resolvedVersion = 'latest'
    }

    $description = $null
    foreach ($url in @($WebsiteUrl, $DeveloperUrl)) {
        if ($url -and -not $description) {
            $description = Get-DescriptionFromWeb -Url $url -AppName $AppName
        }
    }

    return New-AppGetterPackageDetails -AppName $AppName -Version $resolvedVersion `
        -Publisher $Publisher -WebsiteUrl $WebsiteUrl -DeveloperUrl $DeveloperUrl `
        -SupportUrl $SupportUrl -DownloadUrl $DownloadUrl -Description $description
}
