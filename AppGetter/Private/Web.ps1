function Get-WebDownloadLinks {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$WebsiteUrl,
        [string]$AppName
    )

    try {
        Write-AppGetterLog -Message "Fetching webpage: $WebsiteUrl" -Level Info
        $response = Invoke-WebRequest -Uri $WebsiteUrl -UseBasicParsing -ErrorAction Stop
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
                    $uri = New-Object System.Uri([System.Uri]$WebsiteUrl, $link)
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
        Write-AppGetterLog -Message "Error fetching webpage: $_" -Level Warning
        return @()
    }
}

function Get-VersionFromWeb {
    param(
        [string]$Url,
        [string]$AppName
    )

    if ([string]::IsNullOrWhiteSpace($Url)) { return $null }

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
        Write-AppGetterLog -Message 'Could not extract version from website' -Level Warning
    }

    return $null
}

function Get-DescriptionFromWeb {
    param(
        [string]$Url,
        [string]$AppName
    )

    if ([string]::IsNullOrWhiteSpace($Url)) { return $null }

    try {
        $response = Invoke-WebRequest -Uri $Url -UseBasicParsing -ErrorAction Stop
        $html = $response.Content

        if ($html -match '<meta\s+name=["'']description["'']\s+content=["'']([^"'']+)["'']') {
            $description = $matches[1]
            if ($description.Length -gt 20) { return $description }
        }

        if ($html -match '<meta\s+property=["'']og:description["'']\s+content=["'']([^"'']+)["'']') {
            $description = $matches[1]
            if ($description.Length -gt 20) { return $description }
        }

        $patterns = @(
            '<p[^>]*class=["''][^"'']*description[^"'']*["''][^>]*>([^<]+)</p>',
            '<div[^>]*class=["''][^"'']*description[^"'']*["''][^>]*>([^<]+)</div>',
            '<div[^>]*id=["''][^"'']*description[^"'']*["''][^>]*>([^<]+)</div>'
        )

        foreach ($pattern in $patterns) {
            if ($html -match $pattern) {
                $description = $matches[1] -replace '\s+', ' ' | ForEach-Object { $_.Trim() }
                if ($description.Length -gt 20 -and $description.Length -lt 500) {
                    return $description
                }
            }
        }
    } catch {
        Write-AppGetterLog -Message "Could not extract description from website: $_" -Level Warning
    }

    return $null
}

function Get-InstallSwitchesFromWeb {
    param(
        [string]$Url,
        [string]$AppName
    )

    $foundInfo = @{
        InstallSwitches = @()
        BestPractices = @()
    }

    if ([string]::IsNullOrWhiteSpace($Url)) { return $foundInfo }

    try {
        $response = Invoke-WebRequest -Uri $Url -UseBasicParsing -ErrorAction Stop
        $html = $response.Content
        $text = $html -replace '<[^>]+>', ' ' -replace '\s+', ' '

        $switchPatterns = @(
            '/S', '/SILENT', '/VERYSILENT', '/quiet', '/qn', '/qb', '/Q', '/s',
            'silent install', 'quiet install', 'unattended install', 'command line',
            'install switches', 'install parameters', 'deployment', 'msiexec'
        )

        foreach ($pattern in $switchPatterns) {
            if ($text -match $pattern -or $html -match $pattern) {
                $context = $text | Select-String -Pattern ".{0,100}$pattern.{0,100}" -AllMatches
                if ($context) {
                    foreach ($match in $context.Matches) {
                        $foundInfo.InstallSwitches += $match.Value.Trim()
                    }
                }
            }
        }

        if ($text -match '(?i)(deployment|enterprise|administrator|silent|unattended)') {
            $foundInfo.BestPractices += 'Page contains deployment/enterprise installation information'
        }
    } catch {
        Write-AppGetterLog -Message "Could not scan page for install switches: $_" -Level Warning
    }

    return $foundInfo
}

function Resolve-WebDownloadUrl {
    param(
        [string]$WebsiteUrl,
        [string]$DownloadUrl,
        [string]$AppName
    )

    if (-not [string]::IsNullOrWhiteSpace($DownloadUrl)) {
        return $DownloadUrl
    }

    if ([string]::IsNullOrWhiteSpace($WebsiteUrl)) {
        throw 'Provide either -WebsiteUrl or -DownloadUrl.'
    }

    $downloadLinks = Get-WebDownloadLinks -WebsiteUrl $WebsiteUrl -AppName $AppName
    if ($downloadLinks.Count -eq 0) {
        throw "No download links found on $WebsiteUrl. Provide -DownloadUrl with a direct installer link."
    }

    $selectedUrl = $downloadLinks | Where-Object { $_ -like '*.exe' -or $_ -like '*.msi' -or $_ -like '*.msix' -or $_ -like '*.appx' } | Select-Object -First 1
    if (-not $selectedUrl) {
        $selectedUrl = $downloadLinks[0]
    }

    return $selectedUrl
}

function Get-WebPackageDetails {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$AppName,
        [string]$WebsiteUrl,
        [string]$DownloadUrl,
        [string]$Version,
        [string]$Publisher,
        [string]$DeveloperUrl,
        [string]$SupportUrl,
        [string]$InstallCommand
    )

    $resolvedDownloadUrl = Resolve-WebDownloadUrl -WebsiteUrl $WebsiteUrl -DownloadUrl $DownloadUrl -AppName $AppName
    $packageId = Get-SanitizedPackageId -AppName $AppName

    $resolvedVersion = $Version
    if ([string]::IsNullOrWhiteSpace($resolvedVersion)) {
        foreach ($url in @($WebsiteUrl, $DeveloperUrl, $SupportUrl)) {
            if (-not [string]::IsNullOrWhiteSpace($url)) {
                $extractedVersion = Get-VersionFromWeb -Url $url -AppName $AppName
                if ($extractedVersion) {
                    $resolvedVersion = $extractedVersion
                    break
                }
            }
        }
    }
    if ([string]::IsNullOrWhiteSpace($resolvedVersion)) {
        $resolvedVersion = 'latest'
    }

    $description = $null
    foreach ($url in @($WebsiteUrl, $DeveloperUrl, $SupportUrl)) {
        if (-not [string]::IsNullOrWhiteSpace($url)) {
            $description = Get-DescriptionFromWeb -Url $url -AppName $AppName
            if ($description) { break }
        }
    }
    if (-not $description) {
        if ($Publisher) {
            $description = "$AppName by $Publisher - Downloaded from web"
        } else {
            $description = "$AppName - Downloaded from web"
        }
    }

    $homepage = if ($WebsiteUrl) { $WebsiteUrl } elseif ($DeveloperUrl) { $DeveloperUrl } else { $resolvedDownloadUrl }
    $installSwitchesInfo = $null
    if ($SupportUrl) {
        $installSwitchesInfo = Get-InstallSwitchesFromWeb -Url $SupportUrl -AppName $AppName
    }

    $customInstallCommand = $InstallCommand
    if (-not $customInstallCommand -and $installSwitchesInfo -and $installSwitchesInfo.InstallSwitches.Count -gt 0) {
        $switchText = $installSwitchesInfo.InstallSwitches -join ' '
        if ($switchText -match '/VERYSILENT') {
            $customInstallCommand = "`"$(Get-InstallerFileNameFromUrl -Url $resolvedDownloadUrl)`" /VERYSILENT"
        } elseif ($switchText -match '/SILENT') {
            $customInstallCommand = "`"$(Get-InstallerFileNameFromUrl -Url $resolvedDownloadUrl)`" /SILENT"
        }
    }

    return [PSCustomObject]@{
        PackageId = $packageId
        DisplayName = $AppName
        Version = $resolvedVersion
        Publisher = if ($Publisher) { $Publisher } else { 'Unknown' }
        Developer = if ($Publisher) { $Publisher } else { 'Unknown' }
        Description = $description
        Homepage = $homepage
        WebsiteUrl = $WebsiteUrl
        DeveloperUrl = $DeveloperUrl
        SupportUrl = $SupportUrl
        DownloadUrl = $resolvedDownloadUrl
        InstallCommand = $customInstallCommand
        InstallSwitchesInfo = $installSwitchesInfo
    }
}
