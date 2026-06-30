function Import-AppGetterModules {
    [CmdletBinding()]
    param(
        [string]$ModuleRoot = (Join-Path $PSScriptRoot '..')
    )

    $modules = @('AppGetter.Config', 'AppGetter.SilentSwitch', 'AppGetter.Core')
    foreach ($name in $modules) {
        $path = Join-Path $ModuleRoot $name
        if (Test-Path $path) {
            Import-Module $path -Force -ErrorAction Stop
        }
    }
}

function Get-DownloadLinksFromWeb {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
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
            $matches = [regex]::Matches($html, $pattern, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
            foreach ($match in $matches) {
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
    }
    catch {
        Write-Warning "Error fetching webpage: $_"
        return @()
    }
}

function Get-VersionFromWeb {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
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
    }
    catch {
        Write-Warning "Could not extract version from website"
    }

    return $null
}

function Get-DescriptionFromWeb {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Url,
        [string]$AppName
    )

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
    }
    catch {
        Write-Warning "Could not extract description: $_"
    }

    return $null
}

function Start-WebDownloadWithProgress {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Url,
        [Parameter(Mandatory)]
        [string]$OutputPath,
        [string]$FileName
    )

    if (-not $FileName) {
        $FileName = Split-Path -Leaf $OutputPath
    }

    try {
        Invoke-WebRequest -Uri $Url -OutFile $OutputPath -UseBasicParsing -ErrorAction Stop
        if (Test-Path $OutputPath) {
            $sizeMB = [math]::Round((Get-Item $OutputPath).Length / 1MB, 2)
            return [pscustomobject]@{
                Success  = $true
                Path     = $OutputPath
                FileName = $FileName
                SizeMB   = $sizeMB
            }
        }
    }
    catch {
        return [pscustomobject]@{
            Success = $false
            Path    = $OutputPath
            Message = $_.Exception.Message
        }
    }

    return [pscustomobject]@{ Success = $false; Path = $OutputPath; Message = 'Unknown download failure' }
}

function New-AppGetterPackageContext {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$AppName,
        [string]$Version = 'latest',
        [string]$DownloadUrl,
        [string]$WebsiteUrl,
        [string]$SupportUrl,
        [string]$Publisher,
        [string]$OutputPath,
        [string]$InstallCommand
    )

    $config = Get-AppGetterConfig
    if (-not $OutputPath) {
        $OutputPath = $config.outputPath
    }

    $packageId = $AppName -replace '[^a-zA-Z0-9]', ''
    $versionDirectory = Join-Path (Join-Path $OutputPath $packageId) $Version

    return [pscustomobject]@{
        AppName          = $AppName
        PackageId        = $packageId
        Version          = $Version
        DownloadUrl      = $DownloadUrl
        WebsiteUrl       = $WebsiteUrl
        SupportUrl       = $SupportUrl
        Publisher        = $Publisher
        OutputPath       = $OutputPath
        VersionDirectory = $versionDirectory
        InstallCommand   = $InstallCommand
        Config           = $config
    }
}

Export-ModuleMember -Function *
