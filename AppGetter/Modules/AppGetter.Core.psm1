# AppGetter.Core - Core download, packaging, and web scraping functions

function Get-DownloadLinksFromWeb {
    param(
        [string]$Url,
        [string]$AppName = ''
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
                if ($link -notlike "http*") {
                    $uri = New-Object System.Uri([System.Uri]$Url, $link)
                    $link = $uri.AbsoluteUri
                }
                if ($link -notin $downloadLinks) {
                    $downloadLinks += $link
                }
            }
        }

        if ($html -match "(https?://[^\s<>""']+\.(exe|msi|msix|appx))") {
            $directLink = $matches[1]
            if ($directLink -notin $downloadLinks) {
                $downloadLinks += $directLink
            }
        }

        return $downloadLinks
    }
    catch {
        return @()
    }
}

function Get-VersionFromWeb {
    param(
        [string]$Url,
        [string]$AppName = ''
    )

    try {
        $response = Invoke-WebRequest -Uri $Url -UseBasicParsing -ErrorAction Stop
        $html = $response.Content

        $versionPatterns = @(
            "Version\s+(\d+\.\d+\.\d+\.\d+)",
            "Version\s+(\d+\.\d+\.\d+)",
            "v(\d+\.\d+\.\d+\.\d+)",
            "v(\d+\.\d+\.\d+)"
        )

        if ($AppName) {
            $versionPatterns += "$AppName\s+(\d+\.\d+\.\d+\.\d+)"
            $versionPatterns += "$AppName\s+(\d+\.\d+\.\d+)"
        }

        foreach ($pattern in $versionPatterns) {
            if ($html -match $pattern) {
                return $matches[1]
            }
        }
    }
    catch { }

    return $null
}

function Get-DescriptionFromWeb {
    param(
        [string]$Url,
        [string]$AppName = ''
    )

    try {
        $response = Invoke-WebRequest -Uri $Url -UseBasicParsing -ErrorAction Stop
        $html = $response.Content

        if ($html -match '<meta\s+name=["'']description["'']\s+content=["'']([^"'']+)["'']') {
            return $matches[1].Trim()
        }

        if ($html -match '<meta\s+property=["'']og:description["'']\s+content=["'']([^"'']+)["'']') {
            return $matches[1].Trim()
        }
    }
    catch { }

    return $null
}

function Start-WebDownloadWithProgress {
    param(
        [string]$Url,
        [string]$OutputPath,
        [string]$FileName = ''
    )

    try {
        if ($Url -match '^https?://') {
            Invoke-WebRequest -Uri $Url -OutFile $OutputPath -UseBasicParsing -ErrorAction Stop
        }
        elseif (Test-Path $Url) {
            Copy-Item -Path $Url -Destination $OutputPath -Force
        }
        else {
            throw "Invalid URL or file path: $Url"
        }

        if (Test-Path $OutputPath) {
            $fileInfo = Get-Item $OutputPath
            return [PSCustomObject]@{
                success  = $true
                path     = $OutputPath
                fileName = if ($FileName) { $FileName } else { $fileInfo.Name }
                sizeMB   = [math]::Round($fileInfo.Length / 1MB, 2)
                hash     = (Get-FileHash -Path $OutputPath -Algorithm SHA256).Hash
            }
        }
    }
    catch {
        return [PSCustomObject]@{
            success = $false
            path    = $OutputPath
            message = $_.Exception.Message
        }
    }

    return [PSCustomObject]@{ success = $false; message = 'Download failed' }
}

function Save-UploadedInstaller {
    param(
        [string]$SourcePath,
        [string]$DestinationDir,
        [string]$FileName = ''
    )

    if (-not (Test-Path $SourcePath)) {
        throw "Source file not found: $SourcePath"
    }

    if (-not (Test-Path $DestinationDir)) {
        New-Item -ItemType Directory -Path $DestinationDir -Force | Out-Null
    }

    if (-not $FileName) {
        $FileName = Split-Path -Leaf $SourcePath
    }

    $destPath = Join-Path $DestinationDir $FileName
    Copy-Item -Path $SourcePath -Destination $destPath -Force

    return [PSCustomObject]@{
        path     = $destPath
        fileName = $FileName
        sizeMB   = [math]::Round((Get-Item $destPath).Length / 1MB, 2)
        hash     = (Get-FileHash -Path $destPath -Algorithm SHA256).Hash
    }
}

function New-InstallCommand {
    param(
        [string]$InstallerPath,
        [string]$CustomCommand = '',
        [string]$SupportUrl = '',
        [string]$AppName = '',
        [string]$TestMode = 'dry-run'
    )

    if ($CustomCommand) {
        return [PSCustomObject]@{
            command = $CustomCommand
            source  = 'user-provided'
            status  = 'known'
        }
    }

    Import-Module (Join-Path $PSScriptRoot 'AppGetter.SwitchDiscovery.psm1') -Force
    $discovery = Find-SilentInstallSwitches -InstallerPath $InstallerPath -SupportUrl $SupportUrl -AppName $AppName -TestMode $TestMode

    return [PSCustomObject]@{
        command  = $discovery.recommendedCommand
        source   = 'auto-discovery'
        status   = $discovery.status
        switches = $discovery.switches
        tests    = $discovery.tests
        installerType = $discovery.installerType
    }
}

function Invoke-AppGetterPackage {
    param(
        [string]$AppName,
        [string]$InstallerPath,
        [string]$InstallCommand,
        [string]$Version = 'latest',
        [string]$Publisher = '',
        [string]$WebsiteUrl = '',
        [string]$DownloadUrl = '',
        [switch]$SkipIntuneWin
    )

    Import-Module (Join-Path $PSScriptRoot 'AppGetter.Config.psm1') -Force
    $config = Get-AppGetterConfig

    $packageId = $AppName -replace '[^a-zA-Z0-9]', ''
    $appDirectory = Join-Path $config.outputPath $packageId
    $versionDirectory = Join-Path $appDirectory $Version

    if (-not (Test-Path $versionDirectory)) {
        New-Item -ItemType Directory -Path $versionDirectory -Force | Out-Null
    }

    $installerFileName = Split-Path -Leaf $InstallerPath
    $destInstaller = Join-Path $versionDirectory $installerFileName
    if ($InstallerPath -ne $destInstaller) {
        Copy-Item -Path $InstallerPath -Destination $destInstaller -Force
    }

    $installerHash = (Get-FileHash -Path $destInstaller -Algorithm SHA256).Hash

    $detectionScript = @"
# Registry-based detection script for $AppName
`$packageId = "$packageId"
`$version = "$Version"
`$displayName = "$AppName"
`$logPath = "`$env:ProgramData\Microsoft\IntuneManagementExtension\Logs\`$packageId-detection.log"
Start-Transcript -Path `$logPath -Force
Write-Host "Starting `$packageId `$version detection"
`$registryPaths = @("HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*", "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*")
`$found = `$false; `$installedVersion = `$null; `$allMatchingVersions = @()
foreach (`$regPath in `$registryPaths) {
    `$allKeys = Get-ItemProperty `$regPath -ErrorAction SilentlyContinue
    if (`$allKeys) {
        `$uninstallKeys = `$allKeys | Where-Object { `$_.DisplayName -like "*$AppName*" }
        foreach (`$key in `$uninstallKeys) {
            if (`$key.DisplayVersion) { `$allMatchingVersions += @{ DisplayVersion = `$key.DisplayVersion } }
        }
    }
}
if (`$allMatchingVersions.Count -gt 0) {
    `$installedVersion = (`$allMatchingVersions | Sort-Object { try { [version]`$_.DisplayVersion } catch { [version]"0.0.0" } } -Descending)[0].DisplayVersion
    `$found = `$true
}
if (`$found -and (`$version -eq "latest" -or [version]`$installedVersion -ge [version]`$version)) { Stop-Transcript; Exit 0 }
Stop-Transcript; Exit 1
"@

    $uninstallScript = @"
# Uninstall script for $AppName
`$displayName = "$AppName"
`$logPath = "`$env:ProgramData\Microsoft\IntuneManagementExtension\Logs\$packageId-uninstall.log"
Start-Transcript -Path `$logPath -Force
`$registryPaths = @("HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*", "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*")
`$uninstallCmd = `$null
foreach (`$regPath in `$registryPaths) {
    `$key = Get-ItemProperty `$regPath -ErrorAction SilentlyContinue | Where-Object { `$_.DisplayName -like "*$AppName*" } | Select-Object -First 1
    if (`$key) { `$uninstallCmd = if (`$key.QuietUninstallString) { `$key.QuietUninstallString } else { `$key.UninstallString }; break }
}
if (-not `$uninstallCmd) { Stop-Transcript; Exit 1 }
if (`$uninstallCmd -notmatch "/S" -and `$uninstallCmd -match "\.exe") { `$uninstallCmd = `$uninstallCmd -replace '"([^"]+\.exe)"', '"`$1" /S' }
`$process = Start-Process -FilePath "cmd.exe" -ArgumentList "/c `$uninstallCmd" -Wait -PassThru -NoNewWindow
Stop-Transcript; Exit `$process.ExitCode
"@

    $detectionScript | Set-Content -Path (Join-Path $versionDirectory 'detection.ps1') -Encoding UTF8
    $uninstallScript | Set-Content -Path (Join-Path $versionDirectory 'uninstall.ps1') -Encoding UTF8

    $description = "$AppName - packaged by AppGetter"
    if ($Publisher) { $description = "$AppName by $Publisher" }

    $appJson = @{
        packageIdentifier    = $packageId
        displayName          = $AppName
        description          = $description
        version              = $Version
        publisher            = if ($Publisher) { $Publisher } else { 'Unknown' }
        installerUrl         = if ($DownloadUrl) { $DownloadUrl } else { $InstallerPath }
        hash                 = $installerHash
        installCommandLine   = $InstallCommand
        uninstallCommandLine = '%windir%\sysnative\windowspowershell\v1.0\powershell.exe -WindowStyle Hidden -ExecutionPolicy Bypass -File uninstall.ps1'
        installerFilename    = $installerFileName
    }
    $appJson | ConvertTo-Json -Depth 5 | Set-Content -Path (Join-Path $versionDirectory 'app.json') -Encoding UTF8

    $intunewinFile = $null
    if (-not $SkipIntuneWin) {
        $intunewinCmd = Get-Command intunewinapputil -ErrorAction SilentlyContinue
        if ($intunewinCmd) {
            $outputDirectory = Split-Path $versionDirectory
            $baseName = [System.IO.Path]::GetFileNameWithoutExtension($installerFileName)
            $intunewinFile = Join-Path $outputDirectory "$baseName.intunewin"
            & intunewinapputil -c $versionDirectory -s $installerFileName -o $outputDirectory -q
        }
    }

    Add-RecentApp -AppName $AppName -InstallerPath $destInstaller -InstallCommand $InstallCommand

    return [PSCustomObject]@{
        success          = $true
        packageId        = $packageId
        version          = $Version
        outputDirectory  = $versionDirectory
        installerPath    = $destInstaller
        installCommand   = $InstallCommand
        intunewinFile    = $intunewinFile
        hash             = $installerHash
    }
}

Export-ModuleMember -Function @(
    'Get-DownloadLinksFromWeb',
    'Get-VersionFromWeb',
    'Get-DescriptionFromWeb',
    'Start-WebDownloadWithProgress',
    'Save-UploadedInstaller',
    'New-InstallCommand',
    'Invoke-AppGetterPackage'
)
