#Requires -Version 5.1

$script:ModuleRoot = $PSScriptRoot
$script:AppGetterRoot = Split-Path (Split-Path $ModuleRoot -Parent) -Parent
$script:DataRoot = Join-Path $AppGetterRoot 'data'
$script:ConfigRoot = Join-Path $env:LOCALAPPDATA 'AppGetter'
$script:SettingsPath = Join-Path $ConfigRoot 'settings.json'
$script:SwitchHistoryPath = Join-Path $ConfigRoot 'switch-history.json'
$script:KnownSwitchesPath = Join-Path $DataRoot 'KnownInstallSwitches.json'

function Get-AppGetterKnownSwitches {
    if (-not (Test-Path $script:KnownSwitchesPath)) {
        throw "Known install switches database not found at '$script:KnownSwitchesPath'."
    }
    return Get-Content -Path $script:KnownSwitchesPath -Raw | ConvertFrom-Json
}

function Get-DefaultAppGetterSettings {
    $defaultDownload = if ($env:USERPROFILE) {
        Join-Path $env:USERPROFILE 'Documents\AppGetter\Downloads'
    } else {
        'C:\AppGetter\Downloads'
    }

    [ordered]@{
        DownloadLocation   = $defaultDownload
        DocumentationUrls  = @()
        LastInstallerPath  = $null
        Theme              = 'System'
        AutoDiscoverSwitches = $true
    }
}

function Get-AppGetterSettings {
    <#
    .SYNOPSIS
        Returns persisted AppGetter settings including the configured download location.
    #>
    [CmdletBinding()]
    param()

    if (-not (Test-Path $script:ConfigRoot)) {
        New-Item -ItemType Directory -Path $script:ConfigRoot -Force | Out-Null
    }

    if (-not (Test-Path $script:SettingsPath)) {
        $defaults = Get-DefaultAppGetterSettings
        $defaults | ConvertTo-Json -Depth 5 | Set-Content -Path $script:SettingsPath -Encoding UTF8
        return [pscustomobject]$defaults
    }

    $settings = Get-Content -Path $script:SettingsPath -Raw | ConvertFrom-Json
  return [pscustomobject]@{
        DownloadLocation    = $settings.DownloadLocation
        DocumentationUrls   = @($settings.DocumentationUrls)
        LastInstallerPath   = $settings.LastInstallerPath
        Theme               = $settings.Theme
        AutoDiscoverSwitches = [bool]$settings.AutoDiscoverSwitches
    }
}

function Set-AppGetterSettings {
    <#
    .SYNOPSIS
        Updates AppGetter settings such as the download location.
    #>
    [CmdletBinding()]
    param(
        [string]$DownloadLocation,
        [string[]]$DocumentationUrls,
        [string]$LastInstallerPath,
        [string]$Theme,
        [bool]$AutoDiscoverSwitches
    )

    $settings = Get-AppGetterSettings
    if ($PSBoundParameters.ContainsKey('DownloadLocation')) {
        if ([string]::IsNullOrWhiteSpace($DownloadLocation)) {
            throw 'DownloadLocation cannot be empty.'
        }
        $resolved = [System.IO.Path]::GetFullPath($DownloadLocation)
        if (-not (Test-Path $resolved)) {
            New-Item -ItemType Directory -Path $resolved -Force | Out-Null
        }
        $settings.DownloadLocation = $resolved
    }
    if ($PSBoundParameters.ContainsKey('DocumentationUrls')) {
        $settings.DocumentationUrls = @($DocumentationUrls | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    }
    if ($PSBoundParameters.ContainsKey('LastInstallerPath')) {
        $settings.LastInstallerPath = $LastInstallerPath
    }
    if ($PSBoundParameters.ContainsKey('Theme')) {
        $settings.Theme = $Theme
    }
    if ($PSBoundParameters.ContainsKey('AutoDiscoverSwitches')) {
        $settings.AutoDiscoverSwitches = $AutoDiscoverSwitches
    }

    if (-not (Test-Path $script:ConfigRoot)) {
        New-Item -ItemType Directory -Path $script:ConfigRoot -Force | Out-Null
    }

    [ordered]@{
        DownloadLocation     = $settings.DownloadLocation
        DocumentationUrls    = @($settings.DocumentationUrls)
        LastInstallerPath    = $settings.LastInstallerPath
        Theme                = $settings.Theme
        AutoDiscoverSwitches = [bool]$settings.AutoDiscoverSwitches
    } | ConvertTo-Json -Depth 5 | Set-Content -Path $script:SettingsPath -Encoding UTF8

    return Get-AppGetterSettings
}

function Start-WebDownloadWithProgress {
    <#
    .SYNOPSIS
        Downloads a file from a URL to the specified output path.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Url,
        [Parameter(Mandatory)]
        [string]$OutputPath,
        [string]$FileName
    )

    $parent = Split-Path $OutputPath -Parent
    if ($parent -and -not (Test-Path $parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }

    Invoke-WebRequest -Uri $Url -OutFile $OutputPath -UseBasicParsing -ErrorAction Stop | Out-Null
    if (-not (Test-Path $OutputPath)) {
        throw "Download failed for '$Url'."
    }

    $fileInfo = Get-Item $OutputPath
    return [pscustomobject]@{
        Success   = $true
        Path      = $fileInfo.FullName
        FileName  = if ($FileName) { $FileName } else { $fileInfo.Name }
        SizeBytes = $fileInfo.Length
        SizeMB    = [math]::Round($fileInfo.Length / 1MB, 2)
    }
}

function Get-DownloadLinksFromWeb {
    <#
    .SYNOPSIS
        Scans a webpage for installer download links.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Url,
        [string]$AppName
    )

    $response = Invoke-WebRequest -Uri $Url -UseBasicParsing -ErrorAction Stop
    $html = $response.Content
    $patterns = @(
        "href\s*=\s*['""]([^'""]*\.(exe|msi|msix|appx|zip|7z))['""]",
        "href\s*=\s*['""]([^'""]*download[^'""]*)['""]",
        "href\s*=\s*['""]([^'""]*install[^'""]*)['""]",
        "href\s*=\s*['""]([^'""]*setup[^'""]*)['""]"
    )

    $downloadLinks = [System.Collections.Generic.List[string]]::new()
    foreach ($pattern in $patterns) {
        $matches = [regex]::Matches($html, $pattern, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
        foreach ($match in $matches) {
            $link = $match.Groups[1].Value
            if ($link -notlike 'http*') {
                $uri = [System.Uri]::new([System.Uri]$Url, $link)
                $link = $uri.AbsoluteUri
            }
            if (-not $downloadLinks.Contains($link)) {
                $downloadLinks.Add($link)
            }
        }
    }

    if ($html -match '(https?://[^\s<>""'']+\.(exe|msi|msix|appx))') {
        $directLink = $matches[1]
        if (-not $downloadLinks.Contains($directLink)) {
            $downloadLinks.Add($directLink)
        }
    }

    return ,$downloadLinks.ToArray()
}

function Get-InstallSwitchesFromWeb {
    <#
    .SYNOPSIS
        Scans documentation pages for silent install switch references.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Url,
        [string]$AppName
    )

    $foundInfo = [ordered]@{
        Url             = $Url
        InstallSwitches = @()
        BestPractices   = @()
        SilentFlags     = @()
        ExtractedCommands = @()
    }

    try {
        $response = Invoke-WebRequest -Uri $Url -UseBasicParsing -ErrorAction Stop
        $html = $response.Content
        $text = $html -replace '<[^>]+>', ' ' -replace '\s+', ' '

        $switchPatterns = @(
            '/S\b', '/SILENT', '/VERYSILENT', '/quiet', '/qn', '/qb', '/Q\b', '/s\b',
            'silent install', 'quiet install', 'unattended install', 'command line',
            'install switches', 'install parameters', 'deployment', 'msiexec'
        )

        foreach ($pattern in $switchPatterns) {
            if ($text -match $pattern -or $html -match $pattern) {
                $context = $text | Select-String -Pattern ".{0,120}$pattern.{0,120}" -AllMatches
                if ($context) {
                    foreach ($match in $context.Matches) {
                        $snippet = $match.Value.Trim()
                        if ($foundInfo.InstallSwitches -notcontains $snippet) {
                            $foundInfo.InstallSwitches += $snippet
                        }
                    }
                }
            }
        }

        $commandMatches = [regex]::Matches($text, '(?i)(msiexec\s+/i\s+[^\s]+\s+/q[^\s"]*|["'']?[\w\-\.]+\.(exe|msi)["'']?\s+(/[A-Za-z-]+|/quiet|/qn|/S|/SILENT|/VERYSILENT|--silent)[^\r\n]{0,80})')
        foreach ($match in $commandMatches) {
            $cmd = $match.Value.Trim()
            if ($foundInfo.ExtractedCommands -notcontains $cmd) {
                $foundInfo.ExtractedCommands += $cmd
            }
        }

        if ($text -match '(?i)(deployment|enterprise|administrator|silent|unattended)') {
            $foundInfo.BestPractices += 'Page contains deployment or enterprise installation information.'
        }
    } catch {
        Write-Warning "Could not scan page for install switches: $_"
    }

    return [pscustomobject]$foundInfo
}

function Import-InstallerToDownloadLocation {
    <#
    .SYNOPSIS
        Imports an installer via URL download or local file copy into the configured download location.
    #>
    [CmdletBinding()]
    param(
        [string]$DownloadUrl,
        [string]$LocalFilePath,
        [string]$TargetFileName,
        [string]$DownloadLocation
    )

    if ([string]::IsNullOrWhiteSpace($DownloadUrl) -and [string]::IsNullOrWhiteSpace($LocalFilePath)) {
        throw 'Provide either DownloadUrl or LocalFilePath.'
    }

    $settings = Get-AppGetterSettings
    $destinationRoot = if ($DownloadLocation) { $DownloadLocation } else { $settings.DownloadLocation }
    if (-not (Test-Path $destinationRoot)) {
        New-Item -ItemType Directory -Path $destinationRoot -Force | Out-Null
    }

    if (-not [string]::IsNullOrWhiteSpace($LocalFilePath)) {
        if (-not (Test-Path $LocalFilePath)) {
            throw "Local installer not found at '$LocalFilePath'."
        }
        $sourceFile = Get-Item $LocalFilePath
        $fileName = if ($TargetFileName) { $TargetFileName } else { $sourceFile.Name }
        $destinationPath = Join-Path $destinationRoot $fileName
        Copy-Item -Path $sourceFile.FullName -Destination $destinationPath -Force
    } else {
        $fileName = if ($TargetFileName) {
            $TargetFileName
        } else {
            $leaf = Split-Path -Leaf $DownloadUrl
            if ($leaf -match '([^?]+)') { $matches[1] } else { $leaf }
        }
        $destinationPath = Join-Path $destinationRoot $fileName
        Start-WebDownloadWithProgress -Url $DownloadUrl -OutputPath $destinationPath -FileName $fileName | Out-Null
    }

    Set-AppGetterSettings -LastInstallerPath $destinationPath | Out-Null

    return [pscustomobject]@{
        Path      = $destinationPath
        FileName  = Split-Path $destinationPath -Leaf
        Source    = if ($LocalFilePath) { 'LocalUpload' } else { 'DownloadUrl' }
        Directory = $destinationRoot
    }
}

function Get-InstallerBinarySignature {
    param(
        [Parameter(Mandatory)]
        [string]$InstallerPath,
        [int]$MaxBytes = 1048576
    )

    $stream = [System.IO.File]::OpenRead($InstallerPath)
    try {
        $length = [Math]::Min($stream.Length, $MaxBytes)
        $buffer = New-Object byte[] $length
        [void]$stream.Read($buffer, 0, $length)
        return [System.Text.Encoding]::ASCII.GetString($buffer)
    } finally {
        $stream.Dispose()
    }
}

function Get-InstallerFramework {
    <#
    .SYNOPSIS
        Identifies the likely installer framework for a file.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$InstallerPath
    )

    if (-not (Test-Path $InstallerPath)) {
        throw "Installer not found at '$InstallerPath'."
    }

    $file = Get-Item $InstallerPath
    $extension = $file.Extension.ToLowerInvariant()
    $database = Get-AppGetterKnownSwitches
    $binaryText = Get-InstallerBinarySignature -InstallerPath $file.FullName

    $matchedFramework = $null
    foreach ($framework in $database.frameworks) {
        if ($framework.extensions -contains $extension) {
            $signatureMatch = $false
            foreach ($signature in $framework.signatures) {
                if ($binaryText -like "*$signature*") {
                    $signatureMatch = $true
                    break
                }
            }
            if ($signatureMatch -or $framework.signatures.Count -eq 0) {
                if (-not $matchedFramework -or $framework.signatures.Count -gt 0) {
                    $matchedFramework = $framework
                }
            }
        }
    }

    if (-not $matchedFramework) {
        $matchedFramework = $database.frameworks | Where-Object { $_.id -eq 'generic-exe' } | Select-Object -First 1
    }

    $productMatch = $null
    foreach ($product in $database.knownProducts) {
        if ($file.Name -like $product.pattern) {
            $productMatch = $product
            break
        }
    }

    return [pscustomobject]@{
        FileName          = $file.Name
        Extension         = $extension
        FrameworkId       = $matchedFramework.id
        FrameworkName     = $matchedFramework.name
        DefaultSwitch     = $matchedFramework.silentSwitch
        InstallCommand    = $matchedFramework.installCommandTemplate -replace '\{file\}', $file.Name
        Confidence        = if ($productMatch) { $productMatch.confidence } else { $matchedFramework.confidence }
        ProductMatch      = if ($productMatch) { $productMatch.pattern } else { $null }
        ProductCommand    = if ($productMatch) { $productMatch.installCommand -replace '\{file\}', $file.Name } else { $null }
    }
}

function Invoke-InstallerHelpProbe {
    param(
        [Parameter(Mandatory)]
        [string]$InstallerPath,
        [string[]]$HelpArguments,
        [int]$TimeoutSeconds = 12
    )

    $file = Get-Item $InstallerPath
    $results = @()

    foreach ($helpArg in $HelpArguments) {
        $stdoutFile = [System.IO.Path]::GetTempFileName()
        $stderrFile = [System.IO.Path]::GetTempFileName()
        try {
            $process = Start-Process -FilePath $file.FullName -ArgumentList $helpArg -PassThru -WindowStyle Hidden -RedirectStandardOutput $stdoutFile -RedirectStandardError $stderrFile
            $completed = $process.WaitForExit($TimeoutSeconds * 1000)
            if (-not $completed) {
                try { $process.Kill() } catch { }
                continue
            }

            $stdout = if (Test-Path $stdoutFile) { Get-Content $stdoutFile -Raw -ErrorAction SilentlyContinue } else { '' }
            $stderr = if (Test-Path $stderrFile) { Get-Content $stderrFile -Raw -ErrorAction SilentlyContinue } else { '' }
            $combined = (($stdout, $stderr) -join "`n").Trim()
            if ($combined.Length -gt 0) {
                $results += [pscustomobject]@{
                    Argument = $helpArg
                    ExitCode = $process.ExitCode
                    Output   = $combined
                }
            }
        } catch {
            # Some installers reject help probes; continue testing.
        } finally {
            Remove-Item $stdoutFile, $stderrFile -ErrorAction SilentlyContinue
        }
    }

    return $results
}

function Get-SwitchCandidatesFromHelpOutput {
    param(
        [string]$HelpOutput,
        [string[]]$CommonSwitches
    )

    $found = [System.Collections.Generic.List[string]]::new()
    foreach ($switch in $CommonSwitches) {
        $escaped = [regex]::Escape($switch)
        if ($HelpOutput -match "(?i)\b$escaped\b") {
            if (-not $found.Contains($switch)) {
                $found.Add($switch)
            }
        }
    }

    $silentKeywords = 'silent|quiet|unattended|suppress|norestart|passive'
    if ($HelpOutput -match "(?i)($silentKeywords)") {
        $lineMatches = [regex]::Matches($HelpOutput, "(?im)^.*($silentKeywords).*\/[A-Za-z-]+.*$")
        foreach ($match in $lineMatches) {
            $switchMatches = [regex]::Matches($match.Value, '/[A-Za-z-]+')
            foreach ($switchMatch in $switchMatches) {
                $candidate = $switchMatch.Value
                if (-not $found.Contains($candidate)) {
                    $found.Add($candidate)
                }
            }
        }
    }

    return ,$found.ToArray()
}

function Get-InstallerSwitchHistory {
    [CmdletBinding()]
    param()

    if (-not (Test-Path $script:SwitchHistoryPath)) {
        return @()
    }

    $history = Get-Content -Path $script:SwitchHistoryPath -Raw | ConvertFrom-Json
    return @($history)
}

function Save-InstallerSwitchResult {
    <#
    .SYNOPSIS
        Persists a discovered install command for future reuse.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$InstallerPath,
        [Parameter(Mandatory)]
        [string]$InstallCommand,
        [string]$Source = 'UserConfirmed',
        [string]$Confidence = 'High'
    )

    if (-not (Test-Path $script:ConfigRoot)) {
        New-Item -ItemType Directory -Path $script:ConfigRoot -Force | Out-Null
    }

    $file = Get-Item $InstallerPath
    $hash = (Get-FileHash -Path $file.FullName -Algorithm SHA256).Hash
    $entry = [ordered]@{
        FileName        = $file.Name
        FileHash        = $hash
        InstallCommand  = $InstallCommand
        Source          = $Source
        Confidence      = $Confidence
        DiscoveredAtUtc = (Get-Date).ToUniversalTime().ToString('o')
    }

    $history = @(Get-InstallerSwitchHistory)
    $history = @($history | Where-Object { $_.FileHash -ne $hash })
    $history += ,[pscustomobject]$entry
    $history | ConvertTo-Json -Depth 5 | Set-Content -Path $script:SwitchHistoryPath -Encoding UTF8

    return [pscustomobject]$entry
}

function Test-InstallerSilentSwitch {
    <#
    .SYNOPSIS
        Tests whether silent install switches are known for an installer.
    .OUTPUTS
        PSCustomObject with Status (Known, Partial, Unknown), recommended command, and evidence.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$InstallerPath,
        [string[]]$DocumentationUrls,
        [switch]$IncludeHelpProbe
    )

    if (-not (Test-Path $InstallerPath)) {
        throw "Installer not found at '$InstallerPath'."
    }

    $database = Get-AppGetterKnownSwitches
    $file = Get-Item $InstallerPath
    $hash = (Get-FileHash -Path $file.FullName -Algorithm SHA256).Hash
    $history = Get-InstallerSwitchHistory | Where-Object { $_.FileHash -eq $hash } | Select-Object -First 1
    if ($history) {
        return [pscustomobject]@{
            Status           = 'Known'
            InstallerPath    = $file.FullName
            FileName         = $file.Name
            Framework        = 'Previously discovered'
            InstallCommand   = $history.InstallCommand
            Confidence       = $history.Confidence
            Source           = "History ($($history.Source))"
            Evidence         = @("Matched saved result from $($history.DiscoveredAtUtc)")
            RequiresDiscovery = $false
        }
    }

    $framework = Get-InstallerFramework -InstallerPath $file.FullName
    $installCommand = if ($framework.ProductCommand) { $framework.ProductCommand } else { $framework.InstallCommand }
    $evidence = @("Detected framework: $($framework.FrameworkName)")
    if ($framework.ProductMatch) {
        $evidence += "Matched known product pattern: $($framework.ProductMatch)"
    }

    $status = switch ($framework.Confidence) {
        'High' { 'Known' }
        'Medium' { 'Partial' }
        default { 'Unknown' }
    }

    $helpEvidence = @()
    if ($IncludeHelpProbe -or $status -eq 'Unknown') {
        $helpResults = Invoke-InstallerHelpProbe -InstallerPath $file.FullName -HelpArguments $database.helpArguments
        foreach ($help in $helpResults) {
            $switches = Get-SwitchCandidatesFromHelpOutput -HelpOutput $help.Output -CommonSwitches $database.commonSilentSwitches
            if ($switches.Count -gt 0) {
                $helpEvidence += "Help probe '$($help.Argument)' mentions: $($switches -join ', ')"
                if ($status -eq 'Unknown') {
                    $installCommand = "`"$($file.Name)`" $($switches -join ' ')"
                    $status = 'Partial'
                }
            }
        }
        $evidence += $helpEvidence
    }

    if ($DocumentationUrls -and $DocumentationUrls.Count -gt 0) {
        foreach ($docUrl in $DocumentationUrls) {
            $webInfo = Get-InstallSwitchesFromWeb -Url $docUrl
            if ($webInfo.ExtractedCommands.Count -gt 0) {
                $evidence += "Documentation command: $($webInfo.ExtractedCommands[0])"
                if ($status -ne 'Known') {
                    $installCommand = $webInfo.ExtractedCommands[0]
                    $status = 'Partial'
                }
            } elseif ($webInfo.InstallSwitches.Count -gt 0) {
                $evidence += "Documentation snippet: $($webInfo.InstallSwitches[0])"
            }
        }
    }

    return [pscustomobject]@{
        Status            = $status
        InstallerPath     = $file.FullName
        FileName          = $file.Name
        Framework         = $framework.FrameworkName
        InstallCommand    = $installCommand
        Confidence        = $framework.Confidence
        Source            = if ($framework.ProductMatch) { 'KnownProductDatabase' } else { 'FrameworkHeuristics' }
        Evidence          = $evidence
        RequiresDiscovery = ($status -eq 'Unknown')
    }
}

function Find-InstallerSilentSwitch {
    <#
    .SYNOPSIS
        Discovers silent install switches by researching documentation and probing installer help output.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$InstallerPath,
        [string[]]$DocumentationUrls,
        [string[]]$ResearchUrls,
        [switch]$SaveResult
    )

    $settings = Get-AppGetterSettings
    $urls = @()
    if ($DocumentationUrls) { $urls += $DocumentationUrls }
    if ($ResearchUrls) { $urls += $ResearchUrls }
    if ($settings.DocumentationUrls) { $urls += $settings.DocumentationUrls }
    $urls = $urls | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique

    $initial = Test-InstallerSilentSwitch -InstallerPath $InstallerPath -DocumentationUrls $urls -IncludeHelpProbe
    if ($initial.Status -eq 'Known' -and $initial.Confidence -eq 'High') {
        return [pscustomobject]@{
            Status          = $initial.Status
            InstallCommand  = $initial.InstallCommand
            Confidence      = $initial.Confidence
            Method          = $initial.Source
            Evidence        = $initial.Evidence
            ResearchedUrls  = $urls
            HelpProbeCount  = 0
        }
    }

    $database = Get-AppGetterKnownSwitches
    $file = Get-Item $InstallerPath
    $evidence = [System.Collections.Generic.List[string]]::new()
    foreach ($item in $initial.Evidence) { $evidence.Add($item) }

    $bestCommand = $initial.InstallCommand
    $bestConfidence = $initial.Confidence
    $bestMethod = $initial.Source

    foreach ($url in $urls) {
        $webInfo = Get-InstallSwitchesFromWeb -Url $url
        if ($webInfo.ExtractedCommands.Count -gt 0) {
            $bestCommand = $webInfo.ExtractedCommands[0]
            $bestConfidence = 'High'
            $bestMethod = "Documentation ($url)"
            $evidence.Add("Extracted install command from $url")
            break
        }

        $switchText = ($webInfo.InstallSwitches -join ' ')
        if ($switchText -match '/VERYSILENT') {
            $bestCommand = "`"$($file.Name)`" /VERYSILENT /NORESTART /SUPPRESSMSGBOXES"
            $bestConfidence = 'Medium'
            $bestMethod = "Documentation ($url)"
            $evidence.Add('Documentation references /VERYSILENT')
            break
        } elseif ($switchText -match '/SILENT') {
            $bestCommand = "`"$($file.Name)`" /SILENT /NORESTART"
            $bestConfidence = 'Medium'
            $bestMethod = "Documentation ($url)"
            $evidence.Add('Documentation references /SILENT')
        } elseif ($switchText -match '/S\b|/quiet|/qn') {
            $bestCommand = "`"$($file.Name)`" /S"
            $bestConfidence = 'Medium'
            $bestMethod = "Documentation ($url)"
            $evidence.Add('Documentation references common silent switch')
        }
    }

    $helpResults = Invoke-InstallerHelpProbe -InstallerPath $file.FullName -HelpArguments $database.helpArguments
    $discoveredSwitches = [System.Collections.Generic.List[string]]::new()
    foreach ($help in $helpResults) {
        $switches = Get-SwitchCandidatesFromHelpOutput -HelpOutput $help.Output -CommonSwitches $database.commonSilentSwitches
        foreach ($switch in $switches) {
            if (-not $discoveredSwitches.Contains($switch)) {
                $discoveredSwitches.Add($switch)
            }
        }
        if ($switches.Count -gt 0) {
            $evidence.Add("Installer help '$($help.Argument)' suggests: $($switches -join ', ')")
        }
    }

    if ($discoveredSwitches.Count -gt 0 -and $bestConfidence -ne 'High') {
        $bestCommand = "`"$($file.Name)`" $($discoveredSwitches -join ' ')"
        $bestConfidence = 'Medium'
        $bestMethod = 'InstallerHelpProbe'
    }

    if ($bestConfidence -eq 'Low' -or [string]::IsNullOrWhiteSpace($bestCommand)) {
        $framework = Get-InstallerFramework -InstallerPath $file.FullName
        $bestCommand = $framework.InstallCommand
        $bestConfidence = 'Low'
        $bestMethod = 'FrameworkFallback'
        $evidence.Add("Falling back to $($framework.FrameworkName) default switches.")
    }

    $status = switch ($bestConfidence) {
        'High' { 'Known' }
        'Medium' { 'Partial' }
        default { 'Unknown' }
    }

    if ($SaveResult -and $bestCommand) {
        Save-InstallerSwitchResult -InstallerPath $file.FullName -InstallCommand $bestCommand -Source $bestMethod -Confidence $bestConfidence | Out-Null
    }

    return [pscustomobject]@{
        Status         = $status
        InstallCommand = $bestCommand
        Confidence     = $bestConfidence
        Method         = $bestMethod
        Evidence       = $evidence.ToArray()
        ResearchedUrls = $urls
        HelpProbeCount = $helpResults.Count
    }
}

Export-ModuleMember -Function (Get-Command -Module $MyInvocation.MyCommand.ScriptBlock.Module.Name | Select-Object -ExpandProperty Name)
