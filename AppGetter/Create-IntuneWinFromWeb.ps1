<#
.SYNOPSIS
    Creates an IntuneWin package from a web-based application download with registry-based detection.
.DESCRIPTION
    This script automates the process of:
    1. Finding download links on a website
    2. Downloading the installer with proper filename
    3. Creating registry-based detection script
    4. Creating uninstall script
    5. Packaging with Content Prep Tool (intunewinapputil)
    6. Updating all metadata files
.PARAMETER WebsiteUrl
    The URL of the website containing the download link (e.g., "https://simion.com/")
.PARAMETER DownloadUrl
    Optional. Direct download URL if known. If not provided, script will attempt to find it on the website.
.PARAMETER AppName
    The application name (e.g., "SIMION")
.PARAMETER Version
    Optional. Specific version to download. If not specified, will attempt to detect from website or use "latest".
.PARAMETER Publisher
    Optional. Publisher name (e.g., "Adaptas Solutions, LLC")
.PARAMETER OutputPath
    Optional. Base output path. Defaults to "D:\Intoon In Progress"
.PARAMETER IconPath
    Optional. Path to icon file. If not provided, will attempt to download from website.
.PARAMETER InstallCommand
    Optional. Custom install command. If not provided, will attempt to detect based on installer type.
.EXAMPLE
    .\Create-IntuneWinFromWeb.ps1 -WebsiteUrl "https://simion.com/" -AppName "SIMION" -Publisher "Adaptas Solutions, LLC"
.EXAMPLE
    .\Create-IntuneWinFromWeb.ps1 -DownloadUrl "https://example.com/installer.exe" -AppName "MyApp" -Version "1.0.0"
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$false)]
    [string]$WebsiteUrl,
    
    [Parameter(Mandatory=$false)]
    [string]$DownloadUrl,

    [Parameter(Mandatory=$false)]
    [string]$DownloadLocation,

    [Parameter(Mandatory=$false)]
    [string]$InstallerPath,
    
    [Parameter(Mandatory=$false)]
    [string]$AppName,
    
    [Parameter(Mandatory=$false)]
    [string]$Version,
    
    [Parameter(Mandatory=$false)]
    [string]$Publisher,

    [Parameter(Mandatory=$false)]
    [string]$DeveloperUrl,

    [Parameter(Mandatory=$false)]
    [string]$SupportUrl,
    
    [Parameter(Mandatory=$false)]
    [string]$OutputPath = "D:\Intoon In Progress",
    
    [Parameter(Mandatory=$false)]
    [string]$IconPath,
    
    [Parameter(Mandatory=$false)]
    [string]$InstallCommand
)

# Error handling
$ErrorActionPreference = "Stop"

# Import backend module for installer analysis and download location support
$backendModulePath = Join-Path $PSScriptRoot "AppGetter.Backend.psm1"
if (Test-Path -LiteralPath $backendModulePath) {
    Import-Module $backendModulePath -Force
} else {
    Write-Host "Warning: Backend module not found at $backendModulePath. Falling back to built-in logic." -ForegroundColor Yellow
}

$inputInstallerPath = $InstallerPath

# Function to show input dialog
function Get-InputFromDialog {
    param(
        [string]$Title,
        [string]$Prompt,
        [string]$DefaultValue = ""
    )
    
    Add-Type -AssemblyName Microsoft.VisualBasic
    $result = [Microsoft.VisualBasic.Interaction]::InputBox($Prompt, $Title, $DefaultValue)
    
    if ([string]::IsNullOrWhiteSpace($result)) {
        return $null
    }
    
    return $result.Trim()
}

# Function to write colored output
function Write-Step {
    param([string]$Message, [string]$Color = "Cyan")
    Write-Host "`n[$Message]" -ForegroundColor $Color
}

function Write-Success {
    param([string]$Message)
    Write-Host "[SUCCESS] $Message" -ForegroundColor Green
}

function Write-Error {
    param([string]$Message)
    Write-Host "[ERROR] $Message" -ForegroundColor Red
}

# Function to extract download links from HTML
function Get-DownloadLinksFromWeb {
    param(
        [string]$Url,
        [string]$AppName
    )
    
    try {
        Write-Host "Fetching webpage: $Url" -ForegroundColor Cyan
        $response = Invoke-WebRequest -Uri $Url -UseBasicParsing -ErrorAction Stop
        $html = $response.Content
        
        # Common patterns for download links
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
                # Convert relative URLs to absolute
                if ($link -notlike "http*") {
                    $uri = New-Object System.Uri([System.Uri]$Url, $link)
                    $link = $uri.AbsoluteUri
                }
                if ($link -notin $downloadLinks) {
                    $downloadLinks += $link
                }
            }
        }
        
        # Also look for direct download URLs in page text
        if ($html -match "(https?://[^\s<>""']+\.(exe|msi|msix|appx))") {
            $directLink = $matches[1]
            if ($directLink -notin $downloadLinks) {
                $downloadLinks += $directLink
            }
        }
        
        return $downloadLinks
    } catch {
        Write-Host "Error fetching webpage: $_" -ForegroundColor Yellow
        return @()
    }
}

# Function to extract version from website
function Get-VersionFromWeb {
    param(
        [string]$Url,
        [string]$AppName
    )
    
    try {
        $response = Invoke-WebRequest -Uri $Url -UseBasicParsing -ErrorAction Stop
        $html = $response.Content
        
        # Common version patterns
        $versionPatterns = @(
            "Version\s+(\d+\.\d+\.\d+\.\d+)",
            "Version\s+(\d+\.\d+\.\d+)",
            "v(\d+\.\d+\.\d+\.\d+)",
            "v(\d+\.\d+\.\d+)",
            "$AppName\s+(\d+\.\d+\.\d+\.\d+)",
            "$AppName\s+(\d+\.\d+\.\d+)"
        )
        
        foreach ($pattern in $versionPatterns) {
            if ($html -match $pattern) {
                return $matches[1]
            }
        }
    } catch {
        Write-Host "Could not extract version from website" -ForegroundColor Yellow
    }
    
    return $null
}

# Function to extract icon from executable
function Extract-IconFromExe {
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
        public class IconExtractor {
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
        
        if ([IconExtractor]::ExtractToPng($ExePath, $OutputPath)) {
            if (Test-Path $OutputPath -and (Get-Item $OutputPath).Length -gt 0) {
                Write-Host "Extracted icon from installer executable" -ForegroundColor Green
                return $true
            }
        }
    } catch {
        # Icon extraction failed, continue
    }
    
    return $false
}

# Function to download logo from website
function Get-LogoFromWeb {
    param(
        [string]$WebsiteUrl,
        [string]$DeveloperUrl,
        [string]$AppName,
        [string]$OutputPath,
        [string]$InstallerPath = $null
    )
    
    $urls = @()
    
    # Extract base URLs
    $baseUrls = @()
    if ($WebsiteUrl) { $baseUrls += $WebsiteUrl.TrimEnd('/') }
    if ($DeveloperUrl) { $baseUrls += $DeveloperUrl.TrimEnd('/') }
    
    # Try common logo paths on websites
    foreach ($baseUrl in $baseUrls) {
        if ($baseUrl) {
            $logoPaths = @(
                "logo.png", "logo.svg", "icon.png", "icon.svg", "favicon.png", "favicon.ico",
                "images/logo.png", "images/icon.png", "img/logo.png", "img/icon.png",
                "static/images/logo.png", "static/img/logo.png", "static/logo.png",
                "assets/logo.png", "assets/icon.png", "assets/images/logo.png",
                "media/logo.png", "media/icon.png", "resources/logo.png",
                "www/logo.png", "www/images/logo.png", "public/logo.png",
                "app/logo.png", "src/logo.png", "dist/logo.png",
                "$($AppName.ToLower()).png", "$($AppName.ToLower()).svg"
            )
            
            foreach ($path in $logoPaths) {
                $urls += "$baseUrl/$path"
            }
        }
    }
    
    # Try common CDN/hosting patterns
    $cleanName = $AppName -replace '\s+', '' -replace '[^a-zA-Z0-9]', ''
    $lowerName = $cleanName.ToLower()
    if ($cleanName) {
        $urls += @(
            "https://raw.githubusercontent.com/$lowerName/$lowerName/main/logo.png",
            "https://raw.githubusercontent.com/$lowerName/$lowerName/master/logo.png"
        )
    }
    
    # Remove duplicates
    $urls = $urls | Select-Object -Unique
    
    # Try all URLs (limit to first 30)
    $urlsToTry = $urls | Select-Object -First 30
    foreach ($url in $urlsToTry) {
        try {
            Write-Host "Trying to download logo from: $url" -ForegroundColor Cyan
            $response = Invoke-WebRequest -Uri $url -OutFile $OutputPath -ErrorAction Stop -TimeoutSec 5
            if (Test-Path $OutputPath) {
                $fileInfo = Get-Item $OutputPath
                if ($fileInfo.Length -gt 0) {
                    # Verify it's a valid image
                    $bytes = [System.IO.File]::ReadAllBytes($OutputPath)
                    $isImage = $false
                    if ($bytes.Length -gt 8) {
                        # PNG signature: 89 50 4E 47
                        if (($bytes[0] -eq 0x89 -and $bytes[1] -eq 0x50 -and $bytes[2] -eq 0x4E -and $bytes[3] -eq 0x47) -or
                            # JPEG signature: FF D8 FF
                            ($bytes[0] -eq 0xFF -and $bytes[1] -eq 0xD8 -and $bytes[2] -eq 0xFF) -or
                            # GIF signature: GIF
                            ($bytes[0] -eq 0x47 -and $bytes[1] -eq 0x49 -and $bytes[2] -eq 0x46)) {
                            $isImage = $true
                        }
                    }
                    
                    if ($isImage -or $OutputPath -like "*.svg") {
                        Write-Success "Downloaded logo from: $url"
                        return $true
                    } else {
                        Remove-Item $OutputPath -ErrorAction SilentlyContinue
                    }
                }
            }
        } catch {
            if (Test-Path $OutputPath) {
                Remove-Item $OutputPath -ErrorAction SilentlyContinue
            }
        }
    }
    
    # Last resort: Try to extract icon from installer if it's an EXE
    if ($InstallerPath -and (Test-Path $InstallerPath) -and $InstallerPath -like "*.exe") {
        Write-Host "Attempting to extract icon from installer executable..." -ForegroundColor Cyan
        if (Extract-IconFromExe -ExePath $InstallerPath -OutputPath $OutputPath) {
            return $true
        }
    }
    
    return $false
}

# Function to extract description from website
function Get-DescriptionFromWeb {
    param(
        [string]$Url,
        [string]$AppName
    )
    
    try {
        Write-Host "Fetching webpage for description: $Url" -ForegroundColor Cyan
        $response = Invoke-WebRequest -Uri $Url -UseBasicParsing -ErrorAction Stop
        $html = $response.Content
        
        # Try to extract meta description
        if ($html -match '<meta\s+name=["'']description["'']\s+content=["'']([^"'']+)["'']') {
            $description = $matches[1]
            if ($description.Length -gt 20) {
                return $description
            }
        }
        
        # Try to extract from Open Graph description
        if ($html -match '<meta\s+property=["'']og:description["'']\s+content=["'']([^"'']+)["'']') {
            $description = $matches[1]
            if ($description.Length -gt 20) {
                return $description
            }
        }
        
        # Try to find description in common HTML patterns
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
        Write-Host "Could not extract description from website: $_" -ForegroundColor Yellow
    }
    
    return $null
}

# Function to scan pages for install switches and best practices
function Get-InstallSwitchesFromWeb {
    param(
        [string]$Url,
        [string]$AppName
    )
    
    $foundInfo = @{
        InstallSwitches = @()
        BestPractices = @()
        SilentFlags = @()
    }
    
    try {
        Write-Host "Scanning page for install switches: $Url" -ForegroundColor Cyan
        $response = Invoke-WebRequest -Uri $Url -UseBasicParsing -ErrorAction Stop
        $html = $response.Content
        $text = $html -replace '<[^>]+>', ' ' -replace '\s+', ' '
        
        # Look for common install switch patterns
        $switchPatterns = @(
            '/S', '/SILENT', '/VERYSILENT', '/quiet', '/qn', '/qb', '/Q', '/s',
            'silent install', 'quiet install', 'unattended install', 'command line',
            'install switches', 'install parameters', 'deployment', 'msiexec'
        )
        
        foreach ($pattern in $switchPatterns) {
            if ($text -match $pattern -or $html -match $pattern) {
                # Try to extract context around the match
                $context = $text | Select-String -Pattern ".{0,100}$pattern.{0,100}" -AllMatches
                if ($context) {
                    foreach ($match in $context.Matches) {
                        $foundInfo.InstallSwitches += $match.Value.Trim()
                    }
                }
            }
        }
        
        # Look for documentation sections
        if ($text -match '(?i)(deployment|enterprise|administrator|silent|unattended)') {
            $foundInfo.BestPractices += "Page contains deployment/enterprise installation information"
        }
        
    } catch {
        Write-Host "Could not scan page for install switches: $_" -ForegroundColor Yellow
    }
    
    return $foundInfo
}

# Function to download with progress
function Start-WebDownloadWithProgress {
    param(
        [string]$Url,
        [string]$OutputPath,
        [string]$FileName
    )
    
    Write-Host "Downloading from: $Url" -ForegroundColor Cyan
    
    try {
        $ProgressPreference = 'Continue'
        Invoke-WebRequest -Uri $Url -OutFile $OutputPath -UseBasicParsing -ErrorAction Stop
        
        if (Test-Path $OutputPath) {
            $fileInfo = Get-Item $OutputPath
            $sizeMB = [math]::Round($fileInfo.Length / 1MB, 2)
            Write-Success "Downloaded: $FileName ($sizeMB MB)"
            return $true
        }
    } catch {
        Write-Error "Download failed: $_"
        return $false
    }
    
    return $false
}

$downloadLocationResolution = $null
if (-not [string]::IsNullOrWhiteSpace($DownloadLocation) -and [string]::IsNullOrWhiteSpace($inputInstallerPath) -and [string]::IsNullOrWhiteSpace($DownloadUrl)) {
    try {
        $downloadLocationResolution = Resolve-AppGetterDownloadLocation -DownloadLocation $DownloadLocation
        if ($downloadLocationResolution.DownloadUrl) {
            $DownloadUrl = $downloadLocationResolution.DownloadUrl
        }
        if ($downloadLocationResolution.InstallerPath) {
            $inputInstallerPath = $downloadLocationResolution.InstallerPath
        }

        foreach ($note in $downloadLocationResolution.Notes) {
            Write-Host "Download location note: $note" -ForegroundColor Cyan
        }
    } catch {
        Write-Host "Warning: could not resolve download location: $_" -ForegroundColor Yellow
    }
}

# Prompt for required information if not provided
if ([string]::IsNullOrWhiteSpace($WebsiteUrl) -and [string]::IsNullOrWhiteSpace($DownloadUrl) -and [string]::IsNullOrWhiteSpace($inputInstallerPath)) {
    Write-Host "No source input provided. Opening input dialog..." -ForegroundColor Cyan

    $sourceChoice = Get-InputFromDialog -Title "AppGetter - Source Type" -Prompt "Select source type:`n`nEnter:`n  - 'url' for direct installer URL`n  - 'website' to discover link from website`n  - 'file' for local installer path`n  - 'folder' for local download folder"

    switch -Regex ($sourceChoice) {
        "^(url|u)$" {
            $DownloadUrl = Get-InputFromDialog -Title "AppGetter - Enter Download URL" -Prompt "Enter direct download URL:`n`nExample: https://example.com/installer.exe"
            if ([string]::IsNullOrWhiteSpace($DownloadUrl)) {
                Write-Error "Download URL is required. Exiting."
                exit 1
            }
            Write-Success "Using direct download URL: $DownloadUrl"
        }
        "^(file|f)$" {
            $inputInstallerPath = Get-InputFromDialog -Title "AppGetter - Installer File" -Prompt "Enter full installer file path:`n`nExample: C:\Installers\setup.exe"
            if ([string]::IsNullOrWhiteSpace($inputInstallerPath) -or -not (Test-Path -LiteralPath $inputInstallerPath)) {
                Write-Error "Valid installer file path is required. Exiting."
                exit 1
            }
            Write-Success "Using local installer file: $inputInstallerPath"
        }
        "^(folder|dir|d)$" {
            $DownloadLocation = Get-InputFromDialog -Title "AppGetter - Download Folder" -Prompt "Enter download folder path containing installer files:"
            if ([string]::IsNullOrWhiteSpace($DownloadLocation)) {
                Write-Error "Download folder path is required. Exiting."
                exit 1
            }
            $downloadLocationResolution = Resolve-AppGetterDownloadLocation -DownloadLocation $DownloadLocation
            if (-not $downloadLocationResolution.InstallerPath) {
                Write-Error "No supported installer file found in the provided folder. Exiting."
                exit 1
            }
            $inputInstallerPath = $downloadLocationResolution.InstallerPath
            Write-Success "Using local installer from folder: $inputInstallerPath"
        }
        default {
            $WebsiteUrl = Get-InputFromDialog -Title "AppGetter - Enter Website URL" -Prompt "Enter website URL containing the download link:`n`nExample: https://simion.com/"
            if ([string]::IsNullOrWhiteSpace($WebsiteUrl)) {
                Write-Error "Website URL is required. Exiting."
                exit 1
            }
            Write-Success "Using website URL: $WebsiteUrl"
        }
    }

    Write-Host "`nGathering additional information..." -ForegroundColor Cyan
    $DeveloperUrl = Get-InputFromDialog -Title "AppGetter - Developer/Publisher Page" -Prompt "Enter developer/publisher URL (optional):`n`nExample: https://www.wolfvision.com/"
    $SupportUrl = Get-InputFromDialog -Title "AppGetter - Support/Documentation Page" -Prompt "Enter support/documentation URL (optional):`n`nExample: https://www.wolfvision.com/support"
}

if ([string]::IsNullOrWhiteSpace($AppName)) {
    $AppName = Get-InputFromDialog -Title "AppGetter - Enter Application Name" -Prompt "Enter the application name:`n`nExample: SIMION"
    
    if ([string]::IsNullOrWhiteSpace($AppName)) {
        Write-Error "Application name is required. Exiting."
        exit 1
    }
}

# Step 1: Resolve installer source
Write-Step "Step 1: Resolving installer source"
$finalDownloadUrl = $DownloadUrl
$usingLocalInstaller = $false

if (-not [string]::IsNullOrWhiteSpace($inputInstallerPath)) {
    if (-not (Test-Path -LiteralPath $inputInstallerPath)) {
        Write-Error "Installer path not found: $inputInstallerPath"
        exit 1
    }

    $usingLocalInstaller = $true
    Write-Success "Using local installer: $inputInstallerPath"
} elseif ([string]::IsNullOrWhiteSpace($finalDownloadUrl) -and -not [string]::IsNullOrWhiteSpace($WebsiteUrl)) {
    Write-Host "Searching for download links on: $WebsiteUrl" -ForegroundColor Cyan
    $downloadLinks = Get-DownloadLinksFromWeb -Url $WebsiteUrl -AppName $AppName
    
    if ($downloadLinks.Count -eq 0) {
        Write-Host "No download links found automatically on the website." -ForegroundColor Yellow
        Write-Host "You can provide a direct download URL instead." -ForegroundColor Yellow
        
        # Offer to input direct download URL
        $directUrl = Get-InputFromDialog -Title "AppGetter - Direct Download URL" -Prompt "No download links found automatically.`n`nEnter a direct download URL (or leave blank to exit):`n`nExample: https://example.com/installer.exe"
        
        if (-not [string]::IsNullOrWhiteSpace($directUrl)) {
            $finalDownloadUrl = $directUrl
            Write-Success "Using provided direct download URL: $finalDownloadUrl"
        } else {
            Write-Error "No download URL available. Exiting."
            exit 1
        }
    } else {
        # Process found download links
        Write-Host "Found $($downloadLinks.Count) potential download link(s):" -ForegroundColor Yellow
        for ($i = 0; $i -lt $downloadLinks.Count; $i++) {
            Write-Host "  [$($i+1)] $($downloadLinks[$i])" -ForegroundColor Cyan
        }
        
        # Use the first link that looks like an installer
        $selectedUrl = $downloadLinks | Where-Object { $_ -like "*.exe" -or $_ -like "*.msi" -or $_ -like "*.msix" -or $_ -like "*.appx" } | Select-Object -First 1
        
        if ([string]::IsNullOrWhiteSpace($selectedUrl) -and $downloadLinks.Count -gt 0) {
            $selectedUrl = $downloadLinks[0]
        }
        
        if (-not [string]::IsNullOrWhiteSpace($selectedUrl)) {
            $finalDownloadUrl = $selectedUrl
            Write-Success "Selected download URL: $finalDownloadUrl"
        } else {
            Write-Error "Could not determine download URL from found links. Exiting."
            exit 1
        }
    }
} elseif (-not [string]::IsNullOrWhiteSpace($finalDownloadUrl)) {
    Write-Success "Using provided download URL: $finalDownloadUrl"
} else {
    Write-Error "No installer source available. Provide DownloadUrl, WebsiteUrl, InstallerPath, or DownloadLocation."
    exit 1
}

# Step 2: Extract version and description if not provided
Write-Step "Step 2: Determining version and description"
$foundVersion = $Version
$foundDescription = $null

# Extract description from website/developer pages
$urlsToCheck = @()
if ($WebsiteUrl) { $urlsToCheck += $WebsiteUrl }
if ($DeveloperUrl) { $urlsToCheck += $DeveloperUrl }

foreach ($url in $urlsToCheck) {
    if (-not $foundDescription) {
        $foundDescription = Get-DescriptionFromWeb -Url $url -AppName $AppName
        if ($foundDescription) {
            Write-Success "Extracted description from: $url"
            break
        }
    }
}

if ([string]::IsNullOrWhiteSpace($foundVersion) -and -not [string]::IsNullOrWhiteSpace($WebsiteUrl)) {
    $extractedVersion = Get-VersionFromWeb -Url $WebsiteUrl -AppName $AppName
    if ($extractedVersion) {
        $foundVersion = $extractedVersion
        Write-Success "Extracted version from website: $foundVersion"
    }
}

if ([string]::IsNullOrWhiteSpace($foundVersion)) {
    $foundVersion = "latest"
    Write-Host "Version not found, using: $foundVersion" -ForegroundColor Yellow
}

# Scan support/documentation pages for install switches
$installSwitchesInfo = $null
if ($SupportUrl) {
    Write-Host "Scanning support/documentation page for install switches..." -ForegroundColor Cyan
    $installSwitchesInfo = Get-InstallSwitchesFromWeb -Url $SupportUrl -AppName $AppName
    if ($installSwitchesInfo.InstallSwitches.Count -gt 0) {
        Write-Host "Found install switch information:" -ForegroundColor Green
        foreach ($switch in $installSwitchesInfo.InstallSwitches | Select-Object -First 3) {
            Write-Host "  - $switch" -ForegroundColor Cyan
        }
    }
    if ($installSwitchesInfo.BestPractices.Count -gt 0) {
        Write-Host "Found best practices information:" -ForegroundColor Green
        foreach ($practice in $installSwitchesInfo.BestPractices) {
            Write-Host "  - $practice" -ForegroundColor Cyan
        }
    }
}

# Step 3: Create directory structure
Write-Step "Step 3: Creating directory structure"
$packageId = $AppName -replace '[^a-zA-Z0-9]', ''
$appDirectory = Join-Path $OutputPath $packageId
$versionDirectory = Join-Path $appDirectory $foundVersion

if (-not (Test-Path $versionDirectory)) {
    New-Item -ItemType Directory -Path $versionDirectory -Force | Out-Null
    Write-Success "Created directory: $versionDirectory"
} else {
    Write-Host "Directory already exists: $versionDirectory" -ForegroundColor Yellow
}

# Step 4: Stage installer
Write-Step "Step 4: Staging installer"
$stagedInstallerPath = $null
if ($usingLocalInstaller) {
    $sourceInstaller = Get-Item -LiteralPath $inputInstallerPath
    $installerFileName = $sourceInstaller.Name
    $stagedInstallerPath = Join-Path $versionDirectory $installerFileName

    if ($sourceInstaller.FullName -ne $stagedInstallerPath) {
        Copy-Item -LiteralPath $sourceInstaller.FullName -Destination $stagedInstallerPath -Force
        Write-Success "Copied local installer to package folder: $installerFileName"
    } else {
        Write-Success "Installer already in package folder: $installerFileName"
    }
} else {
    $installerFileName = Split-Path -Leaf $finalDownloadUrl
    if ($installerFileName -match "([^?]+)") {
        $installerFileName = $matches[1]
    }

    $stagedInstallerPath = Join-Path $versionDirectory $installerFileName
    if (-not (Start-WebDownloadWithProgress -Url $finalDownloadUrl -OutputPath $stagedInstallerPath -FileName $installerFileName)) {
        Write-Error "Failed to download installer"
        exit 1
    }
}

$installerFile = Get-Item $stagedInstallerPath
$installerExtension = $installerFile.Extension.ToLower()

# Step 5: Determine install command
Write-Step "Step 5: Determining install command"
$switchAnalysis = $null
if ([string]::IsNullOrWhiteSpace($InstallCommand)) {
    $docResearchUrls = @()
    if ($SupportUrl) { $docResearchUrls += $SupportUrl }
    if ($DeveloperUrl) { $docResearchUrls += $DeveloperUrl }
    if ($WebsiteUrl) { $docResearchUrls += $WebsiteUrl }
    $docResearchUrls = $docResearchUrls | Select-Object -Unique

    if (Get-Command Find-AppGetterSilentInstallCommand -ErrorAction SilentlyContinue) {
        $switchAnalysis = Find-AppGetterSilentInstallCommand -InstallerPath $stagedInstallerPath -InstallerFileName $installerFileName -AppName $AppName -DocumentationUrls $docResearchUrls
        $installCommand = $switchAnalysis.InstallCommand
    } elseif ($installerExtension -eq ".msi") {
        $installCommand = "msiexec /i `"$installerFileName`" /quiet /norestart"
    } elseif ($installerExtension -eq ".msix" -or $installerExtension -eq ".appx") {
        $installCommand = "Add-AppxPackage -Path `"$installerFileName`""
    } elseif ($installerExtension -eq ".zip" -or $installerExtension -eq ".7z") {
        Write-Error "Archive files require manual extraction. Please provide InstallCommand parameter."
        exit 1
    } else {
        $installCommand = "`"$installerFileName`" /S"
    }

    Write-Success "Detected install command: $installCommand"
    if ($switchAnalysis) {
        Write-Host "Switch source: $($switchAnalysis.Source) | Confidence: $($switchAnalysis.Confidence)" -ForegroundColor Green
        if ($switchAnalysis.EngineHint) {
            Write-Host "Installer engine hint: $($switchAnalysis.EngineHint)" -ForegroundColor Cyan
        }
        if ($switchAnalysis.NeedsManualReview) {
            Write-Host "Switches may require manual verification in a test VM." -ForegroundColor Yellow
        }
    }
} else {
    Write-Success "Using provided install command: $InstallCommand"
    $installCommand = $InstallCommand
}

# Step 6: Get installer hash
Write-Step "Step 6: Calculating installer hash"
try {
    $installerHash = (Get-FileHash -Path $installerFile.FullName -Algorithm SHA256).Hash
    Write-Success "Installer SHA256: $installerHash"
} catch {
    Write-Error "Failed to calculate hash: $_"
    $installerHash = ""
}

# Step 7: Create registry-based detection script
Write-Step "Step 7: Creating registry-based detection script"
$detectionScript = @"
# Registry-based detection script for $AppName
# Checks for $AppName installation in Windows Uninstall registry keys

`$packageId = "$packageId"
`$version = "$foundVersion"
`$displayName = "$AppName"

# Start transcript for logging
`$logPath = "`$env:ProgramData\Microsoft\IntuneManagementExtension\Logs\`$packageId-detection.log"
Start-Transcript -Path `$logPath -Force
Write-Host "Starting `$packageId `$version detection (Registry-based)"

# Registry paths to check
`$registryPaths = @(
    "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
    "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*"
)

`$found = `$false
`$installedVersion = `$null
`$allMatchingVersions = @()

# Search for application in registry
foreach (`$regPath in `$registryPaths) {
    try {
        `$allKeys = Get-ItemProperty `$regPath -ErrorAction SilentlyContinue
        
        if (`$allKeys) {
            `$uninstallKeys = `$allKeys | Where-Object {
                `$_.DisplayName -like "*$AppName*" -or 
                `$_.PSChildName -like "*$($packageId.ToLower())*" -or
                `$_.PSChildName -like "*$($packageId)*"
            }
            
            if (`$uninstallKeys) {
                foreach (`$key in `$uninstallKeys) {
                    Write-Host "Found registry key: `$(`$key.PSChildName)"
                    Write-Host "DisplayName: `$(`$key.DisplayName)"
                    Write-Host "DisplayVersion: `$(`$key.DisplayVersion)"
                    
                    if (`$key.DisplayName -like "*$AppName*" -and `$key.DisplayVersion) {
                        `$allMatchingVersions += @{
                            DisplayName = `$key.DisplayName
                            DisplayVersion = `$key.DisplayVersion
                            PSChildName = `$key.PSChildName
                        }
                    }
                }
            }
        }
    }
    catch {
        Write-Host "Error checking registry path `$regPath : `$_"
    }
}

# Find the highest version among all matching installations
if (`$allMatchingVersions.Count -gt 0) {
    Write-Host "Found `$(`$allMatchingVersions.Count) matching installation(s)"
    
    if (`$allMatchingVersions.Count -eq 1) {
        `$highestVersion = `$allMatchingVersions[0]
        `$installedVersion = `$highestVersion['DisplayVersion']
        `$found = `$true
        Write-Host "Found version: `$installedVersion"
    } else {
        try {
            `$sortedVersions = `$allMatchingVersions | Sort-Object -Property @{
                Expression = {
                    try {
                        [version]`$_.DisplayVersion
                    } catch {
                        [version]"0.0.0"
                    }
                }
            } -Descending
            
            if (`$sortedVersions -and `$sortedVersions.Count -gt 0) {
                `$highestVersion = `$sortedVersions[0]
                `$installedVersion = `$highestVersion['DisplayVersion']
                `$found = `$true
                Write-Host "Highest version found: `$installedVersion"
            }
        } catch {
            Write-Host "Error during sorting: `$_, using first match"
            `$highestVersion = `$allMatchingVersions[0]
            `$installedVersion = `$highestVersion['DisplayVersion']
            `$found = `$true
        }
    }
}

# Verify version if found
if (`$found) {
    if (`$null -eq `$version -or `$version -eq "" -or `$version -eq "latest") {
        Write-Host "`$packageId version `$installedVersion is installed, exiting with code 0"
        Stop-Transcript
        Exit 0
    }
    
    if (`$installedVersion -eq `$version) {
        Write-Host "`$packageId version `$version is installed, exiting with code 0"
        Stop-Transcript
        Exit 0
    }
    
    # Compare versions
    try {
        `$installedVer = [version]`$installedVersion
        `$expectedVer = [version]`$version
        
        if (`$installedVer -ge `$expectedVer) {
            Write-Host "`$packageId is installed with version `$installedVersion (equal or higher than expected `$version), exit code 0"
            Stop-Transcript
            Exit 0
        }
        else {
            Write-Host "`$packageId is installed but version `$installedVersion is lower than expected `$version, exit code 1"
            Stop-Transcript
            Exit 1
        }
    }
    catch {
        if (`$installedVersion -ge `$version) {
            Write-Host "`$packageId is installed with version `$installedVersion (equal or higher than expected `$version), exit code 0"
            Stop-Transcript
            Exit 0
        }
        else {
            Write-Host "`$packageId is installed but version `$installedVersion is lower than expected `$version, exit code 1"
            Stop-Transcript
            Exit 1
        }
    }
}

Write-Host "`$packageId not detected in registry, exiting with code 1"
Stop-Transcript
Exit 1
"@

$detectionScriptPath = Join-Path $versionDirectory "detection.ps1"
$detectionScript | Set-Content -Path $detectionScriptPath -Encoding UTF8
Write-Success "Created detection script: detection.ps1"

# Step 8: Create uninstall script
Write-Step "Step 8: Creating uninstall script"
$uninstallScript = @"
# Uninstall script for $AppName
# Uses registry to find and execute the uninstaller

`$packageId = "$packageId"
`$action = "uninstall"
`$displayName = "$AppName"

# Start transcript for logging
`$logPath = "`$env:ProgramData\Microsoft\IntuneManagementExtension\Logs\`$packageId-`$action.log"
Start-Transcript -Path `$logPath -Force
Write-Host "Starting `$packageId `$action"

# Registry paths to check
`$registryPaths = @(
    "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
    "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*"
)

`$uninstallString = `$null
`$quietUninstallString = `$null

# Search for application uninstall string in registry
foreach (`$regPath in `$registryPaths) {
    try {
        `$uninstallKeys = Get-ItemProperty `$regPath -ErrorAction SilentlyContinue | Where-Object {
            `$_.DisplayName -like "*$AppName*" -or 
            `$_.PSChildName -like "*$($packageId.ToLower())*" -or
            `$_.PSChildName -like "*$($packageId)*"
        }
        
        if (`$uninstallKeys) {
            foreach (`$key in `$uninstallKeys) {
                if (`$key.DisplayName -like "*$AppName*" -or `$key.DisplayName -eq `$AppName) {
                    `$uninstallString = `$key.UninstallString
                    `$quietUninstallString = `$key.QuietUninstallString
                    Write-Host "Found uninstall string: `$uninstallString"
                    break
                }
            }
            if (`$uninstallString) { break }
        }
    }
    catch {
        Write-Host "Error checking registry path `$regPath : `$_"
    }
}

if (-not `$uninstallString) {
    Write-Host "Uninstall string not found in registry for `$packageId"
    Stop-Transcript
    Exit 1
}

# Prefer quiet uninstall if available
`$uninstallCmd = if (`$quietUninstallString) { `$quietUninstallString } else { `$uninstallString }

# For Nullsoft installers, add /S for silent uninstall if not already present
if (`$uninstallCmd -notmatch "/S" -and `$uninstallCmd -match "\.exe") {
    `$uninstallCmd = `$uninstallCmd -replace '"([^"]+\.exe)"', '"`$1" /S'
    Write-Host "Added /S flag for silent uninstall"
}

Write-Host "Executing uninstall command: `$uninstallCmd"

try {
    `$process = Start-Process -FilePath "cmd.exe" -ArgumentList "/c `$uninstallCmd" -Wait -PassThru -NoNewWindow
    
    if (`$process.ExitCode -eq 0) {
        Write-Host "Package `$packageId uninstalled successfully"
        Stop-Transcript
        Exit 0
    }
    else {
        Write-Host "Uninstall returned exit code: `$(`$process.ExitCode)"
        Stop-Transcript
        Exit `$process.ExitCode
    }
}
catch {
    Write-Host "Error during uninstall: `$_"
    Stop-Transcript
    Exit 1
}
"@

$uninstallScriptPath = Join-Path $versionDirectory "uninstall.ps1"
$uninstallScript | Set-Content -Path $uninstallScriptPath -Encoding UTF8
Write-Success "Created uninstall script: uninstall.ps1"

# Step 9: Handle icon file
Write-Step "Step 9: Handling icon file"
$iconFilePath = Join-Path $versionDirectory "icon.png"
$logoFilePath = Join-Path $appDirectory "logo.png"
$logoDownloaded = $false

if ($IconPath -and (Test-Path $IconPath)) {
    Copy-Item -Path $IconPath -Destination $iconFilePath -Force
    Write-Success "Copied icon from: $IconPath"
} elseif (Test-Path $logoFilePath) {
    Copy-Item -Path $logoFilePath -Destination $iconFilePath -Force
    Write-Success "Copied logo.png from parent directory"
} else {
    # Try to download logo from website/developer pages
    Write-Host "Attempting to download logo automatically..." -ForegroundColor Cyan
    $urlsToTry = @()
    if ($WebsiteUrl) { $urlsToTry += $WebsiteUrl }
    if ($DeveloperUrl) { $urlsToTry += $DeveloperUrl }
    
    # Try website URL first, then developer URL
    $logoDownloaded = Get-LogoFromWeb -WebsiteUrl $WebsiteUrl -DeveloperUrl $DeveloperUrl -AppName $AppName -OutputPath $logoFilePath -InstallerPath $stagedInstallerPath
    if ($logoDownloaded -and (Test-Path $logoFilePath)) {
        Copy-Item -Path $logoFilePath -Destination $iconFilePath -Force
        Write-Success "Downloaded and copied logo automatically"
    }
    
    if (-not $logoDownloaded) {
        Write-Host "No icon file found. You may need to add one manually." -ForegroundColor Yellow
    }
}

# Step 10: Create readme.txt
Write-Step "Step 10: Creating readme.txt"
$installerSourceReference = if ($usingLocalInstaller) { $inputInstallerPath } else { $finalDownloadUrl }
$switchSource = if ($switchAnalysis) { $switchAnalysis.Source } else { "User-provided or legacy default" }
$switchConfidence = if ($switchAnalysis) { $switchAnalysis.Confidence } else { "n/a" }
$switchesFound = if ($switchAnalysis -and $switchAnalysis.DetectedSwitches.Count -gt 0) { ($switchAnalysis.DetectedSwitches -join ", ") } else { "None detected" }
$switchResearchNotes = if ($switchAnalysis -and $switchAnalysis.ResearchNotes.Count -gt 0) { ($switchAnalysis.ResearchNotes -join "`n- ") } else { "No automated research notes available." }
$needsManualSwitchReview = if ($switchAnalysis -and $switchAnalysis.NeedsManualReview) { "Yes" } else { "No" }

# Use extracted description if available, otherwise create default
if ([string]::IsNullOrWhiteSpace($foundDescription)) {
    $description = "$AppName - Downloaded from web"
    if (-not [string]::IsNullOrWhiteSpace($Publisher)) {
        $description = "$AppName by $Publisher - Downloaded from web"
    }
} else {
    $description = $foundDescription
}

$readmeContent = @"
Package $packageId $foundVersion from Web Download

Display name: $AppName
Version: $foundVersion
Publisher: $(if ($Publisher) { $Publisher } else { "Unknown" })
Website: $(if ($WebsiteUrl) { $WebsiteUrl } else { "N/A" })
Installer Source: $installerSourceReference

Install script:
$installCommand

Uninstall script:
%windir%\sysnative\windowspowershell\v1.0\powershell.exe -WindowStyle Hidden -ExecutionPolicy Bypass -File uninstall.ps1

Description:
$description

Notes:
- This package was created using AppGetter
- Installer source: $installerSourceReference
$(if ($DeveloperUrl) { "- Developer URL: $DeveloperUrl`n" })$(if ($SupportUrl) { "- Support/Documentation URL: $SupportUrl`n" })- Created: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
$(if ($installSwitchesInfo -and $installSwitchesInfo.BestPractices.Count -gt 0) { "`nInstall Information Found:`n" + ($installSwitchesInfo.BestPractices -join "`n") + "`n" })

Silent Switch Analysis:
- Source: $switchSource
- Confidence: $switchConfidence
- Candidate Switches: $switchesFound
- Needs Manual Review: $needsManualSwitchReview
- Research Notes:
- $switchResearchNotes
"@

$readmePath = Join-Path $versionDirectory "readme.txt"
$readmeContent | Set-Content -Path $readmePath -Encoding UTF8
Write-Success "Created readme.txt"

# Step 11: Create app.json
Write-Step "Step 11: Creating app.json"
$appJson = @{
    packageIdentifier = $packageId
    displayName = $AppName
    description = $description
    version = $foundVersion
    source = 3  # Web download
    publisher = if ($Publisher) { $Publisher } else { "Unknown" }
    informationUrl = if ($WebsiteUrl) { $WebsiteUrl } elseif ($DeveloperUrl) { $DeveloperUrl } else { "" }
    publisherUrl = if ($DeveloperUrl) { $DeveloperUrl } elseif ($WebsiteUrl) { $WebsiteUrl } else { "" }
    supportUrl = if ($SupportUrl) { $SupportUrl } elseif ($WebsiteUrl) { $WebsiteUrl } else { "" }
    installerType = 7
    installerUrl = if ($finalDownloadUrl) { $finalDownloadUrl } else { "" }
    hash = $installerHash
    installCommandLine = $installCommand
    uninstallCommandLine = "%windir%\\sysnative\\windowspowershell\\v1.0\\powershell.exe -WindowStyle Hidden -ExecutionPolicy Bypass -File uninstall.ps1"
    installerFilename = $installerFileName
    installerContext = 2
    architecture = 2
    installerSource = $installerSourceReference
    installSwitchSource = $switchSource
    installSwitchConfidence = $switchConfidence
}

$appJsonPath = Join-Path $versionDirectory "app.json"
$appJson | ConvertTo-Json -Depth 10 | Set-Content -Path $appJsonPath -Encoding UTF8
Write-Success "Created app.json"

# Step 12: Create win32LobApp.json
Write-Step "Step 12: Creating win32LobApp.json"
$detectionScriptBase64 = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($detectionScript))

# Read icon file if it exists and convert to base64
$iconBase64 = ""
if (Test-Path $iconFilePath) {
    try {
        $iconBytes = [System.IO.File]::ReadAllBytes($iconFilePath)
        $iconBase64 = [Convert]::ToBase64String($iconBytes)
    } catch {
        Write-Host "Warning: Could not read icon file for base64 encoding" -ForegroundColor Yellow
    }
}

$win32LobAppJson = @{
    "@odata.type" = "#microsoft.graph.win32LobApp"
    description = $description
    developer = if ($Publisher) { $Publisher } else { "Unknown" }
    displayName = $AppName
    informationUrl = if ($WebsiteUrl) { $WebsiteUrl } elseif ($DeveloperUrl) { $DeveloperUrl } else { "" }
    largeIcon = if ($iconBase64) {
        @{
            type = "image/png"
            value = $iconBase64
        }
    } else {
        $null
    }
    notes = "Generated by AppGetter at $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') [Source|$packageId|Switch:$switchSource|Confidence:$switchConfidence]"
    publisher = if ($Publisher) { $Publisher } else { "Unknown" }
    fileName = "$($installerFile.BaseName).intunewin"
    allowAvailableUninstall = $true
    applicableArchitectures = "x64"
    detectionRules = @(
        @{
            "@odata.type" = "#microsoft.graph.win32LobAppPowerShellScriptDetection"
            enforceSignatureCheck = $false
            runAs32Bit = $false
            scriptContent = $detectionScriptBase64
        }
    )
    displayVersion = $foundVersion
    installCommandLine = $installCommand
    installExperience = @{
        deviceRestartBehavior = "basedOnReturnCode"
        runAsAccount = "system"
    }
    minimumSupportedOperatingSystem = @{
        v10_2004 = $true
    }
    minimumSupportedWindowsRelease = "2004"
    returnCodes = @(
        @{ returnCode = 0; type = "success" }
        @{ returnCode = 1707; type = "success" }
        @{ returnCode = 3010; type = "softReboot" }
        @{ returnCode = 1641; type = "hardReboot" }
        @{ returnCode = 1618; type = "retry" }
    )
    setupFilePath = $installerFileName
    uninstallCommandLine = "%windir%\\sysnative\\windowspowershell\\v1.0\\powershell.exe -WindowStyle Hidden -ExecutionPolicy Bypass -File uninstall.ps1"
}

# Remove null largeIcon if no icon
if (-not $iconBase64) {
    $win32LobAppJson.Remove('largeIcon')
}

$win32LobAppJsonPath = Join-Path $versionDirectory "win32LobApp.json"
$win32LobAppJson | ConvertTo-Json -Depth 10 | Set-Content -Path $win32LobAppJsonPath -Encoding UTF8
Write-Success "Created win32LobApp.json"

# Step 13: Package with Content Prep Tool
Write-Step "Step 13: Packaging with Content Prep Tool (intunewinapputil)"
$outputDirectory = Split-Path $versionDirectory
$intunewinFile = Join-Path $outputDirectory "$($installerFile.BaseName).intunewin"
try {
    $intunewinCmd = Get-Command intunewinapputil -ErrorAction SilentlyContinue
    if (-not $intunewinCmd) {
        throw "intunewinapputil not found. Is Content Prep Tool installed and in PATH?"
    }
    
    if (Test-Path $intunewinFile) {
        Remove-Item -Path $intunewinFile -Force
        Write-Host "Removed existing intunewin file" -ForegroundColor Yellow
    }
    
    Write-Host "Running: intunewinapputil -c `"$versionDirectory`" -s `"$installerFileName`" -o `"$outputDirectory`" -q"
    
    & intunewinapputil -c $versionDirectory -s $installerFileName -o $outputDirectory -q
    
    if ($LASTEXITCODE -eq 0 -and (Test-Path $intunewinFile)) {
        Write-Success "Created IntuneWin package: $intunewinFile"
        $fileInfo = Get-Item $intunewinFile
        Write-Host "File size: $([math]::Round($fileInfo.Length / 1MB, 2)) MB" -ForegroundColor Green
    } else {
        throw "Content Prep Tool failed or output file not found"
    }
    
} catch {
    Write-Error "Failed to create IntuneWin package: $_"
    Write-Host "You can manually run: intunewinapputil -c `"$versionDirectory`" -s `"$installerFileName`" -o `"$outputDirectory`" -q" -ForegroundColor Yellow
}

# Summary
Write-Step "Summary" "Green"
Write-Host @"
Package created successfully!

Package Details:
- Application: $AppName
- Package ID: $packageId
- Version: $foundVersion
- Publisher: $(if ($Publisher) { $Publisher } else { "Unknown" })
- Installer: $installerFileName
- Installer Source: $installerSourceReference
- Output Directory: $versionDirectory
- IntuneWin Package: $intunewinFile

Files Created:
- detection.ps1 (Registry-based detection)
- uninstall.ps1 (Uninstall script)
- app.json (Application metadata)
- win32LobApp.json (Intune app definition)
- readme.txt (Documentation)
- icon.png (Application icon, if available)
- $installerFileName (Installer file)
- $($installerFile.BaseName).intunewin (Intune package)

Next Steps:
1. Review the generated files in: $versionDirectory
2. Test the detection script if needed
3. Upload the .intunewin file to Intune
"@ -ForegroundColor Green
