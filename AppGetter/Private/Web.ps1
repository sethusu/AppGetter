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

function Get-AppGetterDownloadLinkList {
    <#
    .SYNOPSIS
        Returns website download links as a flat list of strings.
    .DESCRIPTION
        Find-WebDownloadLinks returns its results wrapped in an outer array so a single
        link is not unrolled. Background jobs hand that wrapper back as one object, which
        would collapse every link into a single entry, so callers that cross a job or
        runspace boundary use this function instead.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$Url,
        [string]$AppName
    )

    $links = Find-WebDownloadLinks -Url $Url -AppName $AppName
    $flat = [System.Collections.Generic.List[string]]::new()
    foreach ($link in $links) {
        if ($link -is [string]) {
            $flat.Add($link)
        } elseif ($link) {
            foreach ($nested in $link) {
                if ($nested) { $flat.Add([string]$nested) }
            }
        }
    }

    return $flat.ToArray()
}

function Get-AppGetterInstallerFileNameFromUrl {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Url
    )

    $fileName = $null
    try {
        $uri = [Uri]$Url
        $fileName = [System.IO.Path]::GetFileName($uri.LocalPath)
    } catch {
        # Not an absolute URI (or an odd scheme) -- fall back to string parsing below.
        $fileName = ($Url -split '[?#]')[0]
        $fileName = ($fileName -split '[\\/]')[-1]
    }

    if ([string]::IsNullOrWhiteSpace($fileName)) {
        return 'installer.exe'
    }

    $fileName = [Uri]::UnescapeDataString($fileName)
    $invalidCharacters = [System.IO.Path]::GetInvalidFileNameChars()
    $fileName = ($fileName.ToCharArray() | ForEach-Object {
            if ($invalidCharacters -contains $_) { '_' } else { $_ }
        }) -join ''

    if ([string]::IsNullOrWhiteSpace([System.IO.Path]::GetExtension($fileName))) {
        $fileName = "$fileName.exe"
    }

    return $fileName
}

function Copy-AppGetterLocalInstaller {
    <#
    .SYNOPSIS
        Stages an installer that already exists on the machine running AppGetter.
    .DESCRIPTION
        Copies the selected file into the package version folder so the Content Prep Tool
        packages a self-contained folder, exactly as it does for downloaded installers.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$InstallerPath,
        [Parameter(Mandatory = $true)]
        [string]$DestinationDirectory,
        [scriptblock]$OnProgress
    )

    if (-not (Test-Path -LiteralPath $InstallerPath)) {
        throw "Installer file not found: $InstallerPath"
    }

    $sourceItem = Get-Item -LiteralPath $InstallerPath
    if ($sourceItem.PSIsContainer) {
        throw "Installer path must be a file, not a folder: $InstallerPath"
    }

    if (-not (Test-Path -LiteralPath $DestinationDirectory)) {
        New-Item -ItemType Directory -Path $DestinationDirectory -Force | Out-Null
    }

    $destinationPath = Join-Path $DestinationDirectory $sourceItem.Name
    $sizeMB = [math]::Round($sourceItem.Length / 1MB, 2)
    Write-AppGetterLog -Message "Copying local installer: $($sourceItem.FullName) ($sizeMB MB)" -OnProgress $OnProgress

    if ((Resolve-Path -LiteralPath $sourceItem.FullName).Path -ne $destinationPath) {
        Copy-Item -LiteralPath $sourceItem.FullName -Destination $destinationPath -Force
    }

    Write-AppGetterLog -Message "Staged installer: $($sourceItem.Name) ($sizeMB MB)" -Level Success -OnProgress $OnProgress
    return $destinationPath
}

function Resolve-AppGetterInstallerSource {
    <#
    .SYNOPSIS
        Decides where the installer comes from: a local file, a direct URL, or a scanned website.
    #>
    param(
        [string]$DownloadUrl,
        [string]$WebsiteUrl,
        [string]$InstallerPath,
        [string]$AppName,
        [scriptblock]$OnProgress
    )

    if (-not [string]::IsNullOrWhiteSpace($InstallerPath)) {
        if (-not (Test-Path -LiteralPath $InstallerPath)) {
            throw "Installer file not found: $InstallerPath"
        }
        $resolved = (Resolve-Path -LiteralPath $InstallerPath).Path
        Write-AppGetterLog -Message "Using local installer file: $resolved" -Level Success -OnProgress $OnProgress
        return [PSCustomObject]@{
            SourceType = 'LocalFile'
            Location   = $resolved
            FileName   = [System.IO.Path]::GetFileName($resolved)
        }
    }

    $resolvedUrl = Resolve-WebDownloadUrl -WebsiteUrl $WebsiteUrl -DownloadUrl $DownloadUrl -AppName $AppName -OnProgress $OnProgress
    $sourceType = if (-not [string]::IsNullOrWhiteSpace($DownloadUrl)) { 'DownloadUrl' } else { 'Website' }

    return [PSCustomObject]@{
        SourceType = $sourceType
        Location   = $resolvedUrl
        FileName   = Get-AppGetterInstallerFileNameFromUrl -Url $resolvedUrl
    }
}

function Get-AppGetterLocalInstallerVersion {
    param([string]$InstallerPath)

    if ([string]::IsNullOrWhiteSpace($InstallerPath) -or -not (Test-Path -LiteralPath $InstallerPath)) {
        return $null
    }

    try {
        $versionInfo = (Get-Item -LiteralPath $InstallerPath).VersionInfo
        foreach ($candidate in @($versionInfo.ProductVersion, $versionInfo.FileVersion)) {
            if (-not [string]::IsNullOrWhiteSpace($candidate)) {
                $trimmed = $candidate.Trim()
                if ($trimmed -match '^\d+(\.\d+){1,3}') {
                    return $matches[0]
                }
            }
        }
    } catch {
        Write-AppGetterLog -Message "Could not read version info from installer: $_" -Level Warning
    }

    # Fall back to a version embedded in the file name (e.g. setup-8.2.1.3.exe).
    $fileName = [System.IO.Path]::GetFileNameWithoutExtension($InstallerPath)
    if ($fileName -match '(\d+(\.\d+){1,3})') {
        return $matches[1]
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
    $isLocalSource = -not [string]::IsNullOrWhiteSpace($InstallerPath)

    $urlsToCheck = @()
    if ($WebsiteUrl) { $urlsToCheck += $WebsiteUrl }
    if ($DeveloperUrl) { $urlsToCheck += $DeveloperUrl }

    foreach ($url in $urlsToCheck) {
        if (-not $foundDescription) {
            $foundDescription = Get-WebAppDescription -Url $url -AppName $AppName
        }
    }

    if ([string]::IsNullOrWhiteSpace($foundVersion) -and $isLocalSource) {
        $localVersion = Get-AppGetterLocalInstallerVersion -InstallerPath $InstallerPath
        if ($localVersion) {
            $foundVersion = $localVersion
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

    if ([string]::IsNullOrWhiteSpace($foundDescription)) {
        $origin = if ($isLocalSource) { 'Packaged from a local installer file' } else { 'Downloaded from web' }
        $foundDescription = if ($Publisher) {
            "$AppName by $Publisher - $origin"
        } else {
            "$AppName - $origin"
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
        SourceType           = if ($isLocalSource) { 'LocalFile' } elseif ($DownloadUrl) { 'DownloadUrl' } else { 'Website' }
        DeveloperUrl         = $DeveloperUrl
        SupportUrl           = $SupportUrl
        Homepage             = if ($WebsiteUrl) { $WebsiteUrl } elseif ($DeveloperUrl) { $DeveloperUrl } else { '' }
        InstallSwitchesInfo  = $installSwitchesInfo
    }
}
