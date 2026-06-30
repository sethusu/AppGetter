$ModuleRoot = $PSScriptRoot
$Script:KnownInstallers = $null
$Script:ConfigPath = Join-Path ([Environment]::GetFolderPath('ApplicationData')) 'AppGetter\config.json'

function Import-KnownInstallers {
    if ($null -eq $Script:KnownInstallers) {
        $dataPath = Join-Path $ModuleRoot 'Data\known-installers.json'
        if (Test-Path $dataPath) {
            $Script:KnownInstallers = Get-Content -Path $dataPath -Raw | ConvertFrom-Json
        } else {
            $Script:KnownInstallers = @{ signatures = @(); probeSwitches = @(); commonSilentSwitches = @() }
        }
    }
    return $Script:KnownInstallers
}

function Get-DefaultAppGetterConfig {
    return [ordered]@{
        DownloadLocation   = Join-Path $env:USERPROFILE 'Downloads\AppGetter'
        OutputPath         = 'D:\Intoon In Progress'
        SupportUrl         = ''
        DeveloperUrl       = ''
        ServerPort         = 8765
        AutoDiscoverSwitches = $true
        TestInstallers     = $true
    }
}

function Get-AppGetterConfig {
    [CmdletBinding()]
    param()

    $defaults = Get-DefaultAppGetterConfig
    if (-not (Test-Path $Script:ConfigPath)) {
        return [pscustomobject]$defaults
    }

    try {
        $saved = Get-Content -Path $Script:ConfigPath -Raw | ConvertFrom-Json
        foreach ($key in $defaults.Keys) {
            if ($null -eq $saved.$key) {
                $saved | Add-Member -NotePropertyName $key -NotePropertyValue $defaults[$key] -Force
            }
        }
        return $saved
    } catch {
        return [pscustomobject]$defaults
    }
}

function Set-AppGetterConfig {
    [CmdletBinding()]
    param(
        [string]$DownloadLocation,
        [string]$OutputPath,
        [string]$SupportUrl,
        [string]$DeveloperUrl,
        [int]$ServerPort,
        [bool]$AutoDiscoverSwitches,
        [bool]$TestInstallers
    )

    $config = Get-AppGetterConfig
    if ($PSBoundParameters.ContainsKey('DownloadLocation')) { $config.DownloadLocation = $DownloadLocation }
    if ($PSBoundParameters.ContainsKey('OutputPath')) { $config.OutputPath = $OutputPath }
    if ($PSBoundParameters.ContainsKey('SupportUrl')) { $config.SupportUrl = $SupportUrl }
    if ($PSBoundParameters.ContainsKey('DeveloperUrl')) { $config.DeveloperUrl = $DeveloperUrl }
    if ($PSBoundParameters.ContainsKey('ServerPort')) { $config.ServerPort = $ServerPort }
    if ($PSBoundParameters.ContainsKey('AutoDiscoverSwitches')) { $config.AutoDiscoverSwitches = $AutoDiscoverSwitches }
    if ($PSBoundParameters.ContainsKey('TestInstallers')) { $config.TestInstallers = $TestInstallers }

    $configDir = Split-Path $Script:ConfigPath -Parent
    if (-not (Test-Path $configDir)) {
        New-Item -ItemType Directory -Path $configDir -Force | Out-Null
    }

    if ($config.DownloadLocation -and -not (Test-Path $config.DownloadLocation)) {
        New-Item -ItemType Directory -Path $config.DownloadLocation -Force | Out-Null
    }

    $config | ConvertTo-Json -Depth 5 | Set-Content -Path $Script:ConfigPath -Encoding UTF8
    return $config
}

function Get-InstallerBinaryStrings {
    param([string]$Path, [int]$MaxBytes = 2097152)

    $bytes = [System.IO.File]::ReadAllBytes($Path)
    $length = [Math]::Min($bytes.Length, $MaxBytes)
    $text = [System.Text.Encoding]::ASCII.GetString($bytes, 0, $length)
    return $text
}

function Get-InstallerInfo {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$InstallerPath
    )

    if (-not (Test-Path $InstallerPath)) {
        throw "Installer not found: $InstallerPath"
    }

    $file = Get-Item $InstallerPath
    $known = Import-KnownInstallers
    $extension = $file.Extension.ToLower()
    $binaryText = ''
    $detectedType = 'Unknown EXE'
    $matchedSignature = $null

    if ($extension -in '.exe', '.msi', '.msix', '.appx', '.msixbundle', '.appxbundle') {
        if ($extension -ne '.msi') {
            $binaryText = Get-InstallerBinaryStrings -Path $file.FullName
        }
    }

    foreach ($sig in $known.signatures) {
        if ($sig.extensions -and ($extension -in $sig.extensions)) {
            $matchedSignature = $sig
            $detectedType = $sig.name
            break
        }
        foreach ($pattern in $sig.patterns) {
            if ($pattern -and $binaryText -like "*$pattern*") {
                $matchedSignature = $sig
                $detectedType = $sig.name
                break
            }
        }
        if ($matchedSignature) { break }
    }

    if ($extension -eq '.msi' -and -not $matchedSignature) {
        $matchedSignature = $known.signatures | Where-Object { $_.name -eq 'MSI Package' } | Select-Object -First 1
        $detectedType = 'MSI Package'
    }

    $hash = (Get-FileHash -Path $file.FullName -Algorithm SHA256).Hash
    $sizeMB = [Math]::Round($file.Length / 1MB, 2)

    return [pscustomobject]@{
        FileName          = $file.Name
        FullPath          = $file.FullName
        Extension         = $extension
        SizeBytes         = $file.Length
        SizeMB            = $sizeMB
        Sha256            = $hash
        InstallerType     = $detectedType
        KnownSignature    = if ($matchedSignature) { $matchedSignature.name } else { $null }
        KnownSwitches     = if ($matchedSignature) { @($matchedSignature.silentSwitches) } else { @() }
        Confidence        = if ($matchedSignature) { $matchedSignature.confidence } else { 'none' }
        Notes             = if ($matchedSignature) { $matchedSignature.notes } else { $null }
        LastModified      = $file.LastWriteTimeUtc.ToString('o')
    }
}

function Test-InstallerSilentSwitches {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$InstallerPath,

        [string[]]$CandidateSwitches,

        [switch]$IncludeProbeResults
    )

    $info = Get-InstallerInfo -InstallerPath $InstallerPath
    $known = Import-KnownInstallers
    $fileName = $info.FileName
    $results = [System.Collections.Generic.List[object]]::new()

    $switchList = if ($CandidateSwitches) {
        $CandidateSwitches
    } elseif ($info.KnownSwitches.Count -gt 0) {
        $info.KnownSwitches
    } else {
        @()
    }

    $status = 'unknown'
    $recommendedCommand = $null
    $source = 'none'

    if ($info.Extension -eq '.msi') {
        $status = 'known'
        $recommendedCommand = "msiexec /i `"$fileName`" /quiet /norestart"
        $source = 'msi-default'
        $results.Add([pscustomobject]@{
            Switch = '/quiet /norestart'
            Source = 'msi-default'
            Confidence = 'high'
            Verified = $true
        })
    } elseif ($info.Extension -in '.msix', '.appx', '.msixbundle', '.appxbundle') {
        $status = 'known'
        $recommendedCommand = "Add-AppxPackage -Path `"$fileName`""
        $source = 'msix-default'
        $results.Add([pscustomobject]@{
            Switch = 'Add-AppxPackage'
            Source = 'msix-default'
            Confidence = 'high'
            Verified = $true
        })
    } elseif ($info.KnownSwitches.Count -gt 0) {
        $status = 'known'
        $primarySwitch = $info.KnownSwitches[0]
        $recommendedCommand = "`"$fileName`" $primarySwitch"
        $source = "signature:$($info.KnownSignature)"
        foreach ($sw in $info.KnownSwitches) {
            $results.Add([pscustomobject]@{
                Switch = $sw
                Source = $source
                Confidence = $info.Confidence
                Verified = $false
            })
        }
    } else {
        $status = 'needs-discovery'
    }

    return [pscustomobject]@{
        InstallerPath      = $InstallerPath
        InstallerType      = $info.InstallerType
        Status             = $status
        RecommendedCommand = $recommendedCommand
        Source             = $source
        Candidates         = @($results)
        NeedsDiscovery     = ($status -eq 'needs-discovery')
    }
}

function Invoke-InstallerHelpProbe {
    param(
        [string]$InstallerPath,
        [string[]]$ProbeSwitches
    )

    $findings = [System.Collections.Generic.List[object]]::new()
    $known = Import-KnownInstallers
    $switches = if ($ProbeSwitches) { $ProbeSwitches } else { @($known.probeSwitches) }

    foreach ($probe in $switches) {
        try {
            $psi = New-Object System.Diagnostics.ProcessStartInfo
            $psi.FileName = $InstallerPath
            $psi.Arguments = $probe
            $psi.UseShellExecute = $false
            $psi.RedirectStandardOutput = $true
            $psi.RedirectStandardError = $true
            $psi.CreateNoWindow = $true

            $process = [System.Diagnostics.Process]::Start($psi)
            if (-not $process.WaitForExit(15000)) {
                $process.Kill()
                continue
            }

            $output = ($process.StandardOutput.ReadToEnd() + $process.StandardError.ReadToEnd())
            if ([string]::IsNullOrWhiteSpace($output)) { continue }

            $found = @()
            foreach ($silent in $known.commonSilentSwitches) {
                if ($output -match [regex]::Escape($silent)) {
                    $found += $silent
                }
            }

            if ($output -match '(?i)silent|quiet|unattended|suppress') {
                $findings.Add([pscustomobject]@{
                    ProbeSwitch = $probe
                    ExitCode    = $process.ExitCode
                    FoundSwitches = $found
                    Snippet     = ($output.Substring(0, [Math]::Min(500, $output.Length)) -replace '\s+', ' ').Trim()
                })
            }
        } catch {
            # Probe failures are expected for some installers
        }
    }

    return @($findings)
}

function Find-InstallerSilentSwitches {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$InstallerPath,

        [string]$SupportUrl,
        [string]$AppName,
        [switch]$SkipProbe,
        [switch]$SkipWebResearch
    )

    $config = Get-AppGetterConfig
    $info = Get-InstallerInfo -InstallerPath $InstallerPath
    $known = Import-KnownInstallers
    $discovery = [ordered]@{
        InstallerPath = $InstallerPath
        InstallerType = $info.InstallerType
        Methods       = @()
        Candidates    = @()
        RecommendedCommand = $null
        Confidence    = 'low'
    }

    # Method 1: Known signature database
    if ($info.KnownSwitches.Count -gt 0) {
        $discovery.Methods += 'signature-database'
        foreach ($sw in $info.KnownSwitches) {
            $discovery.Candidates += [pscustomobject]@{
                Switch = $sw
                Source = "signature:$($info.KnownSignature)"
                Confidence = $info.Confidence
            }
        }
    }

    # Method 2: Web research
    $researchUrl = if ($SupportUrl) { $SupportUrl } elseif ($config.SupportUrl) { $config.SupportUrl } else { $null }
    if (-not $SkipWebResearch -and $researchUrl) {
        $webInfo = Get-InstallSwitchesFromWeb -Url $researchUrl -AppName $AppName
        if ($webInfo.InstallSwitches.Count -gt 0) {
            $discovery.Methods += 'web-research'
            $switchText = $webInfo.InstallSwitches -join ' '
            foreach ($silent in $known.commonSilentSwitches) {
                if ($switchText -match [regex]::Escape($silent)) {
                    $discovery.Candidates += [pscustomobject]@{
                        Switch = $silent
                        Source = 'web-research'
                        Confidence = 'medium'
                        Context = ($webInfo.InstallSwitches | Select-Object -First 1)
                    }
                }
            }
        }
    }

    # Method 3: Installer help probe (safe - no actual install)
    if (-not $SkipProbe -and $config.TestInstallers -and $info.Extension -eq '.exe') {
        $probes = Invoke-InstallerHelpProbe -InstallerPath $InstallerPath
        if ($probes.Count -gt 0) {
            $discovery.Methods += 'installer-probe'
            foreach ($probe in $probes) {
                foreach ($sw in $probe.FoundSwitches) {
                    $discovery.Candidates += [pscustomobject]@{
                        Switch = $sw
                        Source = 'installer-probe'
                        Confidence = 'medium'
                        Context = $probe.Snippet
                    }
                }
            }
        }
    }

    # Method 4: Extension-based defaults
    if ($info.Extension -eq '.msi') {
        $discovery.Methods += 'extension-default'
        $discovery.Candidates += [pscustomobject]@{
            Switch = '/quiet /norestart'
            Source = 'extension-default'
            Confidence = 'high'
        }
    } elseif ($info.Extension -in '.msix', '.appx') {
        $discovery.Methods += 'extension-default'
        $discovery.Candidates += [pscustomobject]@{
            Switch = 'Add-AppxPackage'
            Source = 'extension-default'
            Confidence = 'high'
        }
    } elseif ($discovery.Candidates.Count -eq 0) {
        $discovery.Methods += 'fallback-default'
        $discovery.Candidates += [pscustomobject]@{
            Switch = '/S'
            Source = 'fallback-default'
            Confidence = 'low'
        }
    }

    # Deduplicate and rank candidates
    $ranked = $discovery.Candidates |
        Sort-Object -Property @{ Expression = {
            switch ($_.Confidence) { 'high' { 3 } 'medium' { 2 } default { 1 } }
        } } -Descending |
        Group-Object Switch |
        ForEach-Object { $_.Group | Select-Object -First 1 }

    $discovery.Candidates = @($ranked)
    if ($ranked.Count -gt 0) {
        $best = $ranked[0]
        $discovery.Confidence = $best.Confidence
        if ($info.Extension -eq '.msi') {
            $discovery.RecommendedCommand = "msiexec /i `"$($info.FileName)`" /quiet /norestart"
        } elseif ($info.Extension -in '.msix', '.appx') {
            $discovery.RecommendedCommand = "Add-AppxPackage -Path `"$($info.FileName)`""
        } else {
            $discovery.RecommendedCommand = "`"$($info.FileName)`" $($best.Switch)"
        }
    }

    return [pscustomobject]$discovery
}

function Start-InstallerDownload {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$DownloadUrl,

        [string]$FileName,
        [string]$DestinationPath
    )

    $config = Get-AppGetterConfig
    $destDir = if ($DestinationPath) { $DestinationPath } else { $config.DownloadLocation }

    if (-not (Test-Path $destDir)) {
        New-Item -ItemType Directory -Path $destDir -Force | Out-Null
    }

    if (-not $FileName) {
        $FileName = Split-Path -Leaf $DownloadUrl
        if ($FileName -match '([^?]+)') { $FileName = $matches[1] }
    }

    $outputPath = Join-Path $destDir $FileName
    $success = Start-WebDownloadWithProgress -Url $DownloadUrl -OutputPath $outputPath -FileName $FileName

    if (-not $success) {
        throw "Download failed for $DownloadUrl"
    }

    return [pscustomobject]@{
        Success      = $true
        FilePath     = $outputPath
        FileName     = $FileName
        DownloadUrl  = $DownloadUrl
        SizeBytes    = (Get-Item $outputPath).Length
    }
}

# --- Shared web/download helpers (from original script) ---

function Get-DownloadLinksFromWeb {
    param([string]$Url, [string]$AppName)

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
                if ($link -notin $downloadLinks) { $downloadLinks += $link }
            }
        }

        if ($html -match '(https?://[^\s<>""'']+\.(exe|msi|msix|appx))') {
            $directLink = $matches[1]
            if ($directLink -notin $downloadLinks) { $downloadLinks += $directLink }
        }

        return $downloadLinks
    } catch {
        return @()
    }
}

function Get-VersionFromWeb {
    param([string]$Url, [string]$AppName)

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
            if ($html -match $pattern) { return $matches[1] }
        }
    } catch { }

    return $null
}

function Get-DescriptionFromWeb {
    param([string]$Url, [string]$AppName)

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
    } catch { }

    return $null
}

function Get-LogoFromWeb {
    param([string]$Url, [string]$AppName, [string]$OutputPath)

    $commonPaths = @('/logo.png', '/images/logo.png', '/assets/logo.png', '/img/logo.png', '/static/logo.png')
    foreach ($path in $commonPaths) {
        try {
            $logoUrl = (New-Object System.Uri([System.Uri]$Url, $path)).AbsoluteUri
            $response = Invoke-WebRequest -Uri $logoUrl -UseBasicParsing -ErrorAction Stop
            if ($response.StatusCode -eq 200 -and $response.Headers['Content-Type'] -like 'image/*') {
                $logoPath = Join-Path $OutputPath 'logo.png'
                [System.IO.File]::WriteAllBytes($logoPath, $response.Content)
                return $logoPath
            }
        } catch { }
    }
    return $null
}

function Get-InstallSwitchesFromWeb {
    param([string]$Url, [string]$AppName)

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
    } catch { }

    return $foundInfo
}

function Start-WebDownloadWithProgress {
    param([string]$Url, [string]$OutputPath, [string]$FileName)

    try {
        Invoke-WebRequest -Uri $Url -OutFile $OutputPath -UseBasicParsing -ErrorAction Stop
        return (Test-Path $OutputPath)
    } catch {
        return $false
    }
}

function Extract-IconFromExe {
    param([string]$ExePath, [string]$OutputPath)

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
    public static void SaveIcon(string exePath, string outputPath) {
        IntPtr hIcon = ExtractIcon(IntPtr.Zero, exePath, 0);
        if (hIcon != IntPtr.Zero) {
            using (Icon icon = Icon.FromHandle(hIcon)) {
                using (Bitmap bmp = icon.ToBitmap()) {
                    bmp.Save(outputPath, ImageFormat.Png);
                }
            }
            DestroyIcon(hIcon);
        }
    }
}
"@ -ErrorAction SilentlyContinue

        [IconExtractor]::SaveIcon($ExePath, $OutputPath)
        return (Test-Path $OutputPath)
    } catch {
        return $false
    }
}

Export-ModuleMember -Function @(
    'Get-AppGetterConfig', 'Set-AppGetterConfig', 'Get-InstallerInfo',
    'Test-InstallerSilentSwitches', 'Find-InstallerSilentSwitches', 'Start-InstallerDownload',
    'Get-DownloadLinksFromWeb', 'Get-InstallSwitchesFromWeb', 'Start-WebDownloadWithProgress',
    'Get-VersionFromWeb', 'Get-DescriptionFromWeb', 'Get-LogoFromWeb', 'Extract-IconFromExe'
)
