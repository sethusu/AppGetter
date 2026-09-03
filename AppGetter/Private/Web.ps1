function Find-WebDownloadLinks {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Url,
        [string]$AppName
    )

    try {
        Write-AppGetterLog -Message "Fetching webpage: $Url"
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

        return ,$downloadLinks
    } catch {
        Write-AppGetterLog -Message "Error fetching webpage: $_" -Level Warning
        return @()
    }
}

function Get-WebAppVersion {
    param(
        [string]$Url,
        [string]$AppName
    )

    if ([string]::IsNullOrWhiteSpace($Url)) {
        return $null
    }

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

function Get-WebAppDescription {
    param(
        [string]$Url,
        [string]$AppName
    )

    if ([string]::IsNullOrWhiteSpace($Url)) {
        return $null
    }

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
        Write-AppGetterLog -Message "Could not extract description from website: $_" -Level Warning
    }

    return $null
}

function Get-WebInstallSwitches {
    param(
        [string]$Url,
        [string]$AppName
    )

    $foundInfo = @{
        InstallSwitches = @()
        BestPractices   = @()
    }

    if ([string]::IsNullOrWhiteSpace($Url)) {
        return $foundInfo
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
        Write-AppGetterLog -Message "Could not scan page for install switches: $_" -Level Warning
    }

    return $foundInfo
}

function Get-DetectedSilentSwitch {
    param([hashtable]$InstallSwitchesInfo)

    if (-not $InstallSwitchesInfo -or $InstallSwitchesInfo.InstallSwitches.Count -eq 0) {
        return $null
    }

    $switchText = $InstallSwitchesInfo.InstallSwitches -join ' '
    if ($switchText -match '/S\b|/SILENT|/VERYSILENT') {
        if ($switchText -match '/VERYSILENT') { return '/VERYSILENT' }
        if ($switchText -match '/SILENT') { return '/SILENT' }
        return '/S'
    }

    return $null
}

function Resolve-AppGetterLicensingPattern {
    param(
        [string]$InputText,
        [string]$Source = 'Unknown',
        [string[]]$Evidence = @(),
        [string[]]$SourceUrls = @()
    )

    $normalized = if ([string]::IsNullOrWhiteSpace($InputText)) {
        ''
    } else {
        (($InputText -replace '<[^>]+>', ' ') -replace '\s+', ' ').Trim()
    }

    $pattern = 'Unknown'
    $confidence = 0
    $detectionNote = 'No licensing signal was detected.'
    $evidenceSummary = @($Evidence)

    if ($normalized) {
        $rules = @(
            @{ Pattern = 'OpenSource'; Confidence = 95; Regex = '(?i)\b(open[\s-]?source|gpl(?:v?\d+)?|mit license|apache license|bsd license|mozilla public license|mpl\b|lgpl\b)\b'; Note = 'Open-source licensing keywords were found.' },
            @{ Pattern = 'Trialware'; Confidence = 88; Regex = '(?i)\b(trial|evaluation|eval version|14-day|30-day|60-day|expires)\b'; Note = 'Trial or evaluation licensing keywords were found.' },
            @{ Pattern = 'SeatBased'; Confidence = 82; Regex = '(?i)\b(named user|per user|per-device|per device|seat|concurrent user|floating license|license server)\b'; Note = 'Seat/user/device licensing keywords were found.' },
            @{ Pattern = 'Subscription'; Confidence = 84; Regex = '(?i)\b(subscription|monthly|annual|yearly|saas)\b'; Note = 'Subscription licensing keywords were found.' },
            @{ Pattern = 'Perpetual'; Confidence = 80; Regex = '(?i)\b(perpetual|lifetime|one-time purchase|one time purchase)\b'; Note = 'Perpetual licensing keywords were found.' },
            @{ Pattern = 'Freeware'; Confidence = 78; Regex = '(?i)\b(freeware|free to use|free edition)\b'; Note = 'Free-use licensing keywords were found.' }
        )

        foreach ($rule in $rules) {
            if ($normalized -match $rule.Regex) {
                $pattern = $rule.Pattern
                $confidence = $rule.Confidence
                $detectionNote = $rule.Note
                break
            }
        }

        if ($pattern -eq 'Unknown') {
            if ($normalized -match '(?i)^\s*(n/?a|unknown|tbd|not provided)\s*$') {
                $detectionNote = 'Licensing info was explicitly unknown in the source input.'
                $confidence = 100
            } elseif ($Source -eq 'UserProvided') {
                $pattern = 'Custom'
                $confidence = 65
                $detectionNote = 'User-provided licensing text did not map to a known pattern, so it was preserved as custom.'
            }
        }
    }

    if ($evidenceSummary.Count -eq 0 -and $normalized) {
        $previewLength = [Math]::Min(160, $normalized.Length)
        $evidenceSummary = @("Input preview: $($normalized.Substring(0, $previewLength))")
    }

    return [PSCustomObject]@{
        Pattern        = $pattern
        Source         = $Source
        ConfidenceScore = $confidence
        Notes          = if ($normalized) { $normalized } else { '' }
        DetectionNote  = $detectionNote
        EvidenceSummary = $evidenceSummary
        SourceUrls     = @($SourceUrls)
    }
}

function Get-WebLicensingSignals {
    param(
        [string[]]$Urls
    )

    $uniqueUrls = @()
    foreach ($url in $Urls) {
        if (-not [string]::IsNullOrWhiteSpace($url) -and $url -notin $uniqueUrls) {
            $uniqueUrls += $url
        }
    }

    $combinedTextParts = @()
    $evidence = @()
    $snippetPattern = '(?i).{0,80}\b(license|licensing|subscription|trial|evaluation|open source|perpetual|seat|named user|concurrent|floating)\b.{0,80}'

    foreach ($url in $uniqueUrls) {
        try {
            $response = Invoke-WebRequest -Uri $url -UseBasicParsing -ErrorAction Stop
            $text = (($response.Content -replace '<[^>]+>', ' ') -replace '\s+', ' ').Trim()
            if (-not [string]::IsNullOrWhiteSpace($text)) {
                $combinedTextParts += $text
            }

            $matches = [regex]::Matches($text, $snippetPattern)
            foreach ($match in $matches) {
                if ($evidence.Count -ge 5) { break }
                $snippet = $match.Value.Trim()
                if ($snippet -and $snippet -notin $evidence) {
                    $evidence += ("{0} :: {1}" -f $url, $snippet)
                }
            }
        } catch {
            Write-AppGetterLog -Message "Could not scan page for licensing keywords: $url" -Level Warning
        }
    }

    return [PSCustomObject]@{
        CombinedText = ($combinedTextParts -join ' ')
        Evidence     = $evidence
        UrlsChecked  = $uniqueUrls
    }
}

function Start-WebInstallerDownload {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Url,
        [Parameter(Mandatory = $true)]
        [string]$OutputPath,
        [string]$FileName,
        [scriptblock]$OnProgress
    )

    Write-AppGetterLog -Message "Downloading from: $Url" -OnProgress $OnProgress

    try {
        Invoke-WebRequest -Uri $Url -OutFile $OutputPath -UseBasicParsing -ErrorAction Stop

        if (Test-Path $OutputPath) {
            $fileInfo = Get-Item $OutputPath
            $sizeMB = [math]::Round($fileInfo.Length / 1MB, 2)
            Write-AppGetterLog -Message "Downloaded: $FileName ($sizeMB MB)" -Level Success -OnProgress $OnProgress
            return $true
        }
    } catch {
        throw "Download failed: $_"
    }

    return $false
}

function Resolve-WebDownloadUrl {
    param(
        [string]$WebsiteUrl,
        [string]$DownloadUrl,
        [string]$AppName,
        [scriptblock]$OnProgress
    )

    if (-not [string]::IsNullOrWhiteSpace($DownloadUrl)) {
        Write-AppGetterLog -Message "Using provided download URL: $DownloadUrl" -Level Success -OnProgress $OnProgress
        return $DownloadUrl
    }

    if ([string]::IsNullOrWhiteSpace($WebsiteUrl)) {
        throw 'Website URL or Download URL is required.'
    }

    Write-AppGetterLog -Message "Searching for download links on: $WebsiteUrl" -OnProgress $OnProgress
    $downloadLinks = Find-WebDownloadLinks -Url $WebsiteUrl -AppName $AppName

    if ($downloadLinks.Count -eq 0) {
        throw "No download links found on the website: $WebsiteUrl"
    }

    $selectedUrl = $downloadLinks | Where-Object {
        $_ -like '*.exe' -or $_ -like '*.msi' -or $_ -like '*.msix' -or $_ -like '*.appx'
    } | Select-Object -First 1

    if ([string]::IsNullOrWhiteSpace($selectedUrl)) {
        $selectedUrl = $downloadLinks[0]
    }

    Write-AppGetterLog -Message "Selected download URL: $selectedUrl" -Level Success -OnProgress $OnProgress
    return $selectedUrl
}

function Get-WebPackageDetails {
    param(
        [Parameter(Mandatory = $true)]
        [string]$AppName,
        [string]$WebsiteUrl,
        [string]$DownloadUrl,
        [string]$DeveloperUrl,
        [string]$SupportUrl,
        [string]$Version,
        [string]$Publisher,
        [string]$LicensingInfo
    )

    $packageId = Get-PackageIdFromAppName -AppName $AppName
    $foundVersion = $Version
    $foundDescription = $null
    $installSwitchesInfo = $null
    $resolvedLicensing = $null

    $urlsToCheck = @()
    if ($WebsiteUrl) { $urlsToCheck += $WebsiteUrl }
    if ($DeveloperUrl) { $urlsToCheck += $DeveloperUrl }

    foreach ($url in $urlsToCheck) {
        if (-not $foundDescription) {
            $foundDescription = Get-WebAppDescription -Url $url -AppName $AppName
        }
    }

    if ([string]::IsNullOrWhiteSpace($foundVersion) -and $WebsiteUrl) {
        $extractedVersion = Get-WebAppVersion -Url $WebsiteUrl -AppName $AppName
        if ($extractedVersion) {
            $foundVersion = $extractedVersion
        }
    }

    if ([string]::IsNullOrWhiteSpace($foundVersion)) {
        $foundVersion = 'latest'
    }

    if ($SupportUrl) {
        $installSwitchesInfo = Get-WebInstallSwitches -Url $SupportUrl -AppName $AppName
    }

    if (-not [string]::IsNullOrWhiteSpace($LicensingInfo)) {
        $resolvedLicensing = Resolve-AppGetterLicensingPattern -InputText $LicensingInfo -Source 'UserProvided'
    } else {
        $licensingSignals = Get-WebLicensingSignals -Urls @($WebsiteUrl, $DeveloperUrl, $SupportUrl)
        $resolvedLicensing = Resolve-AppGetterLicensingPattern -InputText $licensingSignals.CombinedText `
            -Source 'DetectedFromWeb' -Evidence $licensingSignals.Evidence -SourceUrls $licensingSignals.UrlsChecked
    }

    if ([string]::IsNullOrWhiteSpace($foundDescription)) {
        $foundDescription = if ($Publisher) {
            "$AppName by $Publisher - Downloaded from web"
        } else {
            "$AppName - Downloaded from web"
        }
    }

    return [PSCustomObject]@{
        PackageId            = $packageId
        DisplayName          = $AppName
        Version              = $foundVersion
        Publisher            = if ($Publisher) { $Publisher } else { 'Unknown' }
        Developer            = if ($Publisher) { $Publisher } else { 'Unknown' }
        Description          = $foundDescription
        WebsiteUrl           = $WebsiteUrl
        DownloadUrl          = $DownloadUrl
        DeveloperUrl         = $DeveloperUrl
        SupportUrl           = $SupportUrl
        Homepage             = if ($WebsiteUrl) { $WebsiteUrl } elseif ($DeveloperUrl) { $DeveloperUrl } else { '' }
        InstallSwitchesInfo  = $installSwitchesInfo
        Licensing            = $resolvedLicensing
    }
}
