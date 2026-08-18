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

function Get-LocalInstallerVersion {
    param([string]$InstallerPath)

    if (-not $InstallerPath -or -not (Test-Path -LiteralPath $InstallerPath)) {
        return $null
    }

    try {
        $info = [System.Diagnostics.FileVersionInfo]::GetVersionInfo((Resolve-Path -LiteralPath $InstallerPath).Path)
        foreach ($candidate in @($info.ProductVersion, $info.FileVersion)) {
            if ($candidate -and $candidate -notmatch '^\s*$' -and $candidate -ne '0.0.0.0') {
                return ($candidate -replace '\s+', '').Trim()
            }
        }
    } catch {
        Write-Verbose "Could not read file version from $InstallerPath : $_"
    }

    return $null
}

function Copy-LocalInstallerToPackage {
    param(
        [Parameter(Mandatory = $true)]
        [string]$InstallerPath,
        [Parameter(Mandatory = $true)]
        [string]$DestinationDirectory,
        [scriptblock]$OnProgress
    )

    if (-not (Test-Path -LiteralPath $InstallerPath)) {
        throw "Local installer not found: $InstallerPath"
    }

    $sourceFile = Get-Item -LiteralPath $InstallerPath
    if ($sourceFile.PSIsContainer) {
        throw "InstallerPath must be a file, not a directory: $InstallerPath"
    }

    $destination = Join-Path $DestinationDirectory $sourceFile.Name
    Write-AppGetterLog -Message "Copying local installer: $($sourceFile.FullName)" -OnProgress $OnProgress
    Copy-Item -LiteralPath $sourceFile.FullName -Destination $destination -Force
    if (-not (Test-Path -LiteralPath $destination)) {
        throw "Failed to copy local installer to $destination"
    }

    $sizeMB = [math]::Round((Get-Item -LiteralPath $destination).Length / 1MB, 2)
    Write-AppGetterLog -Message "Copied: $($sourceFile.Name) ($sizeMB MB)" -Level Success -OnProgress $OnProgress
    return (Get-Item -LiteralPath $destination)
}

function Get-WebPackageDetails {
    param(
        [Parameter(Mandatory = $true)]
        [string]$AppName,
        [string]$WebsiteUrl,
        [string]$DownloadUrl,
        [string]$InstallerPath,
        [string]$DeveloperUrl,
        [string]$SupportUrl,
        [string]$Version,
        [string]$Publisher
    )

    $packageId = Get-PackageIdFromAppName -AppName $AppName
    $foundVersion = $Version
    $foundDescription = $null
    $installSwitchesInfo = $null

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

    if ([string]::IsNullOrWhiteSpace($foundVersion) -and $InstallerPath) {
        $fileVersion = Get-LocalInstallerVersion -InstallerPath $InstallerPath
        if ($fileVersion) {
            $foundVersion = $fileVersion
        }
    }

    if ([string]::IsNullOrWhiteSpace($foundVersion)) {
        $foundVersion = 'latest'
    }

    if ($SupportUrl) {
        $installSwitchesInfo = Get-WebInstallSwitches -Url $SupportUrl -AppName $AppName
    }

    if ([string]::IsNullOrWhiteSpace($foundDescription)) {
        $sourceNote = if ($InstallerPath) { 'Packaged from a local installer' } else { 'Downloaded from web' }
        $foundDescription = if ($Publisher) {
            "$AppName by $Publisher - $sourceNote"
        } else {
            "$AppName - $sourceNote"
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
        InstallerPath        = $InstallerPath
        DeveloperUrl         = $DeveloperUrl
        SupportUrl           = $SupportUrl
        Homepage             = if ($WebsiteUrl) { $WebsiteUrl } elseif ($DeveloperUrl) { $DeveloperUrl } else { '' }
        InstallSwitchesInfo  = $installSwitchesInfo
    }
}
