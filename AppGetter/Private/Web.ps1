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
                    $uri = New-Object System.Uri([System.Uri]$Url, $link)
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
            "$AppName\s+(\d+\.\d+\.\d+\.\d+)",
            "$AppName\s+(\d+\.\d+\.\d+)"
        )

        foreach ($pattern in $versionPatterns) {
            if ($html -match $pattern) {
                return $matches[1]
            }
        }
    } catch {
        Write-Warning 'Could not extract version from website'
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
        Write-Warning "Could not extract description from website: $_"
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
        BestPractices   = @()
        SilentFlags     = @()
    }

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
        Write-Warning "Could not scan page for install switches: $_"
    }

    return $foundInfo
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
        throw 'Either WebsiteUrl or DownloadUrl must be provided.'
    }

    Write-AppGetterProgress -Step 1 -StepName 'Finding download URL' -Percent 20 -Message "Scanning $WebsiteUrl" -OnProgress $OnProgress
    $downloadLinks = Get-DownloadLinksFromWeb -Url $WebsiteUrl -AppName $AppName

    if ($downloadLinks.Count -eq 0) {
        throw 'No download links found on the website. Provide a direct DownloadUrl instead.'
    }

    $selectedUrl = $downloadLinks | Where-Object {
        $_ -like '*.exe' -or $_ -like '*.msi' -or $_ -like '*.msix' -or $_ -like '*.appx'
    } | Select-Object -First 1

    if ([string]::IsNullOrWhiteSpace($selectedUrl)) {
        $selectedUrl = $downloadLinks[0]
    }

    return $selectedUrl
}

function Get-WebPackageDetails {
    param(
        [Parameter(Mandatory = $true)]
        [string]$AppName,
        [string]$WebsiteUrl,
        [string]$DownloadUrl,
        [string]$Version,
        [string]$Publisher,
        [string]$DeveloperUrl,
        [string]$SupportUrl,
        [scriptblock]$OnProgress
    )

    $packageId = $AppName -replace '[^a-zA-Z0-9]', ''
    $resolvedDownloadUrl = Resolve-WebDownloadUrl -WebsiteUrl $WebsiteUrl -DownloadUrl $DownloadUrl -AppName $AppName -OnProgress $OnProgress

    $foundVersion = $Version
    $foundDescription = $null
    $installSwitchesInfo = $null

    $urlsToCheck = @()
    if ($WebsiteUrl) { $urlsToCheck += $WebsiteUrl }
    if ($DeveloperUrl) { $urlsToCheck += $DeveloperUrl }

    foreach ($url in $urlsToCheck) {
        if (-not $foundDescription) {
            $foundDescription = Get-DescriptionFromWeb -Url $url -AppName $AppName
        }
    }

    if ([string]::IsNullOrWhiteSpace($foundVersion) -and $WebsiteUrl) {
        $extractedVersion = Get-VersionFromWeb -Url $WebsiteUrl -AppName $AppName
        if ($extractedVersion) {
            $foundVersion = $extractedVersion
        }
    }

    if ([string]::IsNullOrWhiteSpace($foundVersion)) {
        $foundVersion = 'latest'
    }

    if ($SupportUrl) {
        $installSwitchesInfo = Get-InstallSwitchesFromWeb -Url $SupportUrl -AppName $AppName
    }

    if ([string]::IsNullOrWhiteSpace($foundDescription)) {
        $foundDescription = if ($Publisher) {
            "$AppName by $Publisher - Downloaded from web"
        } else {
            "$AppName - Downloaded from web"
        }
    }

    $detectedSwitch = $null
    if ($installSwitchesInfo -and $installSwitchesInfo.InstallSwitches.Count -gt 0) {
        $switchText = $installSwitchesInfo.InstallSwitches -join ' '
        if ($switchText -match '/VERYSILENT') {
            $detectedSwitch = '/VERYSILENT'
        } elseif ($switchText -match '/SILENT') {
            $detectedSwitch = '/SILENT'
        } elseif ($switchText -match '/S\b') {
            $detectedSwitch = '/S'
        }
    }

    return [PSCustomObject]@{
        PackageId            = $packageId
        DisplayName          = $AppName
        Version              = $foundVersion
        Publisher            = if ($Publisher) { $Publisher } else { 'Unknown' }
        Developer            = if ($Publisher) { $Publisher } else { 'Unknown' }
        Description          = $foundDescription
        Homepage             = if ($WebsiteUrl) { $WebsiteUrl } elseif ($DeveloperUrl) { $DeveloperUrl } else { '' }
        DownloadUrl          = $resolvedDownloadUrl
        DeveloperUrl         = $DeveloperUrl
        SupportUrl           = $SupportUrl
        WebsiteUrl           = $WebsiteUrl
        InstallSwitchesInfo  = $installSwitchesInfo
        DetectedInstallSwitch = $detectedSwitch
    }
}

function Get-InstallerFileNameFromUrl {
    param([string]$Url)

    $fileName = Split-Path -Leaf $Url
    if ($fileName -match '([^?]+)') {
        $fileName = $matches[1]
    }
    return $fileName
}
