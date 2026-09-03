function Get-AppGetterLicenseTypes {
    <#
    .SYNOPSIS
        Returns the canonical license types AppGetter understands.
    .DESCRIPTION
        The list mirrors the ServiceNow software-model license field used when
        ingesting applications, so a value copied from ServiceNow maps 1:1 onto
        the packaged metadata.
    #>
    return @(
        'Per User'
        'Per Device'
        'Site License'
        'Subscription'
        'Freeware'
        'Open Source'
        'Trial / Evaluation'
        'Unknown'
    )
}

function ConvertTo-AppGetterLicenseType {
    <#
    .SYNOPSIS
        Normalizes a free-form license value (e.g. from a ServiceNow field) to a canonical AppGetter license type.
    .DESCRIPTION
        Values that already match a canonical type are returned as-is. Common
        aliases (per seat, named user, per machine, volume, SaaS, GPL, shareware...)
        are mapped onto the canonical set. Unrecognized values are preserved
        unchanged so nothing ingested from ServiceNow is lost.
    #>
    param(
        [string]$Value
    )

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return 'Unknown'
    }

    $trimmed = $Value.Trim()
    foreach ($canonical in (Get-AppGetterLicenseTypes)) {
        if ([string]::Equals($trimmed, $canonical, [StringComparison]::OrdinalIgnoreCase)) {
            return $canonical
        }
    }

    $normalized = ($trimmed -replace '[^a-zA-Z0-9]', ' ' -replace '\s+', ' ').Trim().ToLowerInvariant()

    $aliasMap = @(
        @{ Type = 'Per User';           Aliases = @('per user', 'per seat', 'seat', 'named user', 'user', 'user cal', 'per named user', 'concurrent user', 'per user subscription') }
        @{ Type = 'Per Device';         Aliases = @('per device', 'per machine', 'per computer', 'per workstation', 'device', 'machine', 'per install', 'per installation', 'node locked', 'per node') }
        @{ Type = 'Site License';       Aliases = @('site', 'site license', 'site licence', 'site wide', 'enterprise', 'enterprise license', 'volume', 'volume license', 'volume licensing', 'campus', 'unlimited', 'organization wide') }
        @{ Type = 'Subscription';       Aliases = @('subscription', 'saas', 'annual', 'annual license', 'monthly', 'term license', 'term') }
        @{ Type = 'Freeware';           Aliases = @('free', 'freeware', 'free of charge', 'gratis', 'no license required', 'no cost') }
        @{ Type = 'Open Source';        Aliases = @('open source', 'opensource', 'oss', 'foss', 'free and open source', 'mit', 'mit license', 'gpl', 'gplv2', 'gplv3', 'gpl v2', 'gpl v3', 'lgpl', 'agpl', 'apache', 'apache 2 0', 'apache license', 'bsd', 'bsd license', 'mpl', 'mozilla public license') }
        @{ Type = 'Trial / Evaluation'; Aliases = @('trial', 'free trial', 'evaluation', 'eval', 'shareware', 'demo', 'demo version', 'trial evaluation') }
        @{ Type = 'Unknown';            Aliases = @('unknown', 'none', 'n a', 'not applicable', 'tbd') }
    )

    foreach ($entry in $aliasMap) {
        foreach ($alias in $entry.Aliases) {
            if ($normalized -eq $alias) {
                return $entry.Type
            }
        }
    }

    return $trimmed
}

function Get-AppGetterLicenseSignals {
    <#
    .SYNOPSIS
        Scans plain text for licensing-pattern signals and returns scored candidates.
    #>
    param(
        [string]$Text,
        [string]$SourceLabel = 'text'
    )

    $signals = [System.Collections.Generic.List[hashtable]]::new()
    if ([string]::IsNullOrWhiteSpace($Text)) {
        return @($signals)
    }

    $namedLicensePatterns = @(
        @{ Name = 'MIT License';                    Pattern = '(?i)\bMIT\s+Licen[cs]e\b' }
        @{ Name = 'GNU GPL';                        Pattern = '(?i)GNU\s+General\s+Public\s+Licen[cs]e|\bGPL\s*v?\s*[23]\b' }
        @{ Name = 'GNU LGPL';                       Pattern = '(?i)GNU\s+Lesser\s+General\s+Public\s+Licen[cs]e|\bLGPL\b' }
        @{ Name = 'GNU AGPL';                       Pattern = '(?i)GNU\s+Affero\s+General\s+Public\s+Licen[cs]e|\bAGPL\b' }
        @{ Name = 'Apache License';                 Pattern = '(?i)Apache\s+Licen[cs]e(\s*,?\s*Version\s*2\.0)?' }
        @{ Name = 'BSD License';                    Pattern = '(?i)\bBSD\s+([23]-Clause\s+)?Licen[cs]e\b' }
        @{ Name = 'Mozilla Public License';         Pattern = '(?i)Mozilla\s+Public\s+Licen[cs]e|\bMPL\s*2\.0\b' }
        @{ Name = 'Eclipse Public License';         Pattern = '(?i)Eclipse\s+Public\s+Licen[cs]e' }
        @{ Name = 'ISC License';                    Pattern = '(?i)\bISC\s+Licen[cs]e\b' }
        @{ Name = 'zlib License';                   Pattern = '(?i)\bzlib\s+Licen[cs]e\b' }
    )

    foreach ($named in $namedLicensePatterns) {
        $match = [regex]::Match($Text, $named.Pattern)
        if ($match.Success) {
            $signals.Add(@{
                    LicenseType = 'Open Source'
                    LicenseName = $named.Name
                    Score       = 75
                    Evidence    = "$($SourceLabel): matched named license '$($match.Value.Trim())'"
                })
        }
    }

    $typePatterns = @(
        @{ Type = 'Open Source';        Score = 30; Pattern = '(?i)\bopen[\s-]?source\b' }
        @{ Type = 'Freeware';           Score = 40; Pattern = '(?i)\bfreeware\b|free\s+of\s+charge|completely\s+free|free\s+for\s+(both\s+)?(personal|private)\s+and\s+commercial\s+use' }
        @{ Type = 'Per User';           Score = 35; Pattern = '(?i)\bper[\s-]user\b|\bper[\s-]seat\b|\bnamed[\s-]user\b|\buser\s+licen[cs]es?\b' }
        @{ Type = 'Per Device';         Score = 35; Pattern = '(?i)\bper[\s-](device|machine|computer|workstation)\b|\bnode[\s-]locked\b' }
        @{ Type = 'Site License';       Score = 35; Pattern = '(?i)\bsite[\s-](wide\s+)?licen[cs]e\b|\bvolume\s+licen[cs]\w*\b|\benterprise\s+licen[cs]e\b|\bunlimited\s+installations?\b' }
        @{ Type = 'Subscription';       Score = 30; Pattern = '(?i)\bsubscription\b|\bper\s+(month|year)\b|\bannual(ly)?\s+(licen[cs]e|billing|plan)\b|/\s*(month|year|mo|yr)\b' }
        @{ Type = 'Trial / Evaluation'; Score = 25; Pattern = '(?i)\bfree\s+trial\b|\b\d+[\s-]day\s+trial\b|\bevaluation\s+(version|copy|licen[cs]e)\b|\bshareware\b|\btry\s+before\s+you\s+buy\b' }
    )

    foreach ($typePattern in $typePatterns) {
        $match = [regex]::Match($Text, $typePattern.Pattern)
        if ($match.Success) {
            $signals.Add(@{
                    LicenseType = $typePattern.Type
                    LicenseName = $null
                    Score       = $typePattern.Score
                    Evidence    = "$($SourceLabel): matched '$($match.Value.Trim())'"
                })
        }
    }

    return @($signals)
}

function Get-WebLicensePageInfo {
    <#
    .SYNOPSIS
        Fetches a web page and returns its plain text plus any license/EULA link found on it.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$Url
    )

    try {
        $response = Invoke-WebRequest -Uri $Url -UseBasicParsing -ErrorAction Stop
        $html = $response.Content

        $licenseLink = $null
        $linkMatch = [regex]::Match($html, "(?i)href\s*=\s*['""]([^'""]*(licen[cs]e|eula|legal|terms)[^'""]*)['""]")
        if ($linkMatch.Success) {
            $link = $linkMatch.Groups[1].Value
            if ($link -notlike 'http*') {
                try {
                    $uri = New-Object System.Uri([System.Uri]$Url, $link)
                    $link = $uri.AbsoluteUri
                } catch {
                    $link = $null
                }
            }
            $licenseLink = $link
        }

        $text = $html -replace '<script[\s\S]*?</script>', ' ' -replace '<style[\s\S]*?</style>', ' ' `
            -replace '<[^>]+>', ' ' -replace '\s+', ' '

        return [PSCustomObject]@{
            Url         = $Url
            Text        = $text
            LicenseLink = $licenseLink
        }
    } catch {
        Write-AppGetterLog -Message "Could not fetch page for license discovery ($Url): $_" -Level Warning
        return $null
    }
}

function Resolve-AppGetterLicenseInfo {
    <#
    .SYNOPSIS
        Identifies the licensing pattern for an application and returns license metadata to apply to the package.
    .DESCRIPTION
        Mirrors the silent-switch discovery architecture:
        1. An explicitly provided license type (e.g. ingested from the ServiceNow
           licensing field) always wins and is normalized to the canonical set.
        2. Otherwise the application's web pages (website, developer, support,
           plus any license/EULA page linked from them) and any provided text
           are scanned for licensing-pattern signals (named open-source
           licenses, freeware wording, per-user/per-device/site/subscription/
           trial pricing language).
        3. Signals are scored and ranked; conflicting patterns lower the
           confidence and flag the package for manual review.
    .PARAMETER LicenseType
        Explicit license type, e.g. the value from the ServiceNow field. Skips detection.
    .PARAMETER PageText
        Optional raw text blobs to analyze in addition to (or instead of) URLs.
        Useful for offline analysis or pasting a ServiceNow description.
    #>
    param(
        [string]$AppName,
        [string]$LicenseType,
        [string]$LicenseName,
        [string]$LicenseUrl,
        [string]$LicenseNotes,
        [string]$WebsiteUrl,
        [string]$DeveloperUrl,
        [string]$SupportUrl,
        [string[]]$PageText = @(),
        [scriptblock]$OnProgress
    )

    $evidenceSummary = [System.Collections.Generic.List[string]]::new()
    $appLabel = if ([string]::IsNullOrWhiteSpace($AppName)) { 'application' } else { $AppName }

    if (-not [string]::IsNullOrWhiteSpace($LicenseType)) {
        $normalizedType = ConvertTo-AppGetterLicenseType -Value $LicenseType
        if (-not [string]::Equals($normalizedType, $LicenseType.Trim(), [StringComparison]::OrdinalIgnoreCase)) {
            $evidenceSummary.Add("Provided license type '$LicenseType' normalized to '$normalizedType'") | Out-Null
        } else {
            $evidenceSummary.Add("License type provided by caller: '$normalizedType'") | Out-Null
        }

        Write-AppGetterLog -Message "Using provided license type for ${appLabel}: $normalizedType" -Level Success -OnProgress $OnProgress

        return [PSCustomObject]@{
            LicenseType       = $normalizedType
            LicenseName       = $LicenseName
            LicenseUrl        = $LicenseUrl
            Notes             = $LicenseNotes
            Source            = 'provided'
            ConfidenceScore   = 100
            EvidenceSummary   = @($evidenceSummary)
            NeedsManualReview = $false
        }
    }

    $signals = [System.Collections.Generic.List[hashtable]]::new()
    $discoveredLicenseUrl = $LicenseUrl

    foreach ($blob in @($PageText)) {
        foreach ($signal in (Get-AppGetterLicenseSignals -Text $blob -SourceLabel 'provided text')) {
            $signals.Add($signal)
        }
    }

    $urlsToScan = [System.Collections.Generic.List[string]]::new()
    foreach ($url in @($WebsiteUrl, $DeveloperUrl, $SupportUrl)) {
        if (-not [string]::IsNullOrWhiteSpace($url) -and -not $urlsToScan.Contains($url)) {
            $urlsToScan.Add($url)
        }
    }

    foreach ($url in $urlsToScan) {
        $pageInfo = Get-WebLicensePageInfo -Url $url
        if (-not $pageInfo) {
            continue
        }

        foreach ($signal in (Get-AppGetterLicenseSignals -Text $pageInfo.Text -SourceLabel $url)) {
            $signals.Add($signal)
        }

        if (-not $discoveredLicenseUrl -and $pageInfo.LicenseLink) {
            $discoveredLicenseUrl = $pageInfo.LicenseLink
            $evidenceSummary.Add("License page link discovered: $discoveredLicenseUrl") | Out-Null

            $licensePageInfo = Get-WebLicensePageInfo -Url $discoveredLicenseUrl
            if ($licensePageInfo) {
                foreach ($signal in (Get-AppGetterLicenseSignals -Text $licensePageInfo.Text -SourceLabel $discoveredLicenseUrl)) {
                    $signals.Add($signal)
                }
            }
        }
    }

    if ($signals.Count -eq 0) {
        $evidenceSummary.Add('No licensing-pattern signals found; set the license type manually (e.g. from the ServiceNow field)') | Out-Null
        Write-AppGetterLog -Message "License pattern for $appLabel not identified; marked Unknown (manual review recommended)." -Level Warning -OnProgress $OnProgress

        return [PSCustomObject]@{
            LicenseType       = 'Unknown'
            LicenseName       = $LicenseName
            LicenseUrl        = $discoveredLicenseUrl
            Notes             = $LicenseNotes
            Source            = 'default'
            ConfidenceScore   = 0
            EvidenceSummary   = @($evidenceSummary)
            NeedsManualReview = $true
        }
    }

    $scoresByType = @{}
    $bestNameByType = @{}
    foreach ($signal in $signals) {
        $type = [string]$signal.LicenseType
        if (-not $scoresByType.ContainsKey($type)) {
            $scoresByType[$type] = 0
        }
        $scoresByType[$type] = [Math]::Min(95, [int]$scoresByType[$type] + [int]$signal.Score)
        if ($signal.LicenseName -and -not $bestNameByType.ContainsKey($type)) {
            $bestNameByType[$type] = [string]$signal.LicenseName
        }
        $evidenceSummary.Add([string]$signal.Evidence) | Out-Null
    }

    $ranked = @($scoresByType.GetEnumerator() | Sort-Object { [int]$_.Value } -Descending)
    $topType = [string]$ranked[0].Key
    $confidence = [int]$ranked[0].Value

    if ($ranked.Count -gt 1) {
        $runnerUp = [int]$ranked[1].Value
        if ($runnerUp -ge ($confidence - 10)) {
            $confidence = [Math]::Max(10, $confidence - 15)
            $evidenceSummary.Add("Conflicting license patterns detected ($(@($ranked | ForEach-Object { $_.Key }) -join ', ')); confidence reduced") | Out-Null
        }
    }

    $detectedName = $LicenseName
    if (-not $detectedName -and $bestNameByType.ContainsKey($topType)) {
        $detectedName = $bestNameByType[$topType]
    }

    $needsManualReview = $confidence -lt 70
    $reviewNote = if ($needsManualReview) { ' (manual review recommended)' } else { '' }
    Write-AppGetterLog -Message "License pattern identified for ${appLabel}: $topType, confidence=$confidence$reviewNote" `
        -Level $(if ($needsManualReview) { 'Warning' } else { 'Success' }) -OnProgress $OnProgress

    return [PSCustomObject]@{
        LicenseType       = $topType
        LicenseName       = $detectedName
        LicenseUrl        = $discoveredLicenseUrl
        Notes             = $LicenseNotes
        Source            = 'detected'
        ConfidenceScore   = $confidence
        EvidenceSummary   = @($evidenceSummary)
        NeedsManualReview = $needsManualReview
    }
}
