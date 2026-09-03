function Get-AppGetterLicenseCatalog {
    <#
    .SYNOPSIS
        Canonical licensing patterns aligned with ServiceNow SAM license metric / license type values.
    #>
    [CmdletBinding()]
    param()

    return @(
        [PSCustomObject]@{
            Pattern            = 'trial'
            DisplayName        = 'Evaluation / Trial'
            Aliases            = @('evaluation / trial', 'evaluation', 'trial', 'eval', 'demo', 'free trial', 'trial license')
            Family             = 'trial'
            Metric             = 'none'
            InstallContext     = 'system'
            AssignmentTarget   = 'device'
            RequiresLicenseKey = $false
            Priority           = 95
            AssignmentGuidance = 'Assign to a small pilot group only. Trial installs typically expire and should not be broadly required.'
            InstallGuidance    = 'No license key is injected. Confirm the vendor trial does not show a registration dialog during silent install.'
        }
        [PSCustomObject]@{
            Pattern            = 'openSource'
            DisplayName        = 'Open Source'
            Aliases            = @('open source', 'opensource', 'oss', 'gpl', 'lgpl', 'agpl', 'mit license', 'apache license', 'bsd license', 'mpl')
            Family             = 'openSource'
            Metric             = 'none'
            InstallContext     = 'system'
            AssignmentTarget   = 'device'
            RequiresLicenseKey = $false
            Priority           = 90
            AssignmentGuidance = 'Safe to assign as available or required to devices. Keep the upstream license text with the package notes.'
            InstallGuidance    = 'No product key. Install silently in system context.'
        }
        [PSCustomObject]@{
            Pattern            = 'concurrentUser'
            DisplayName        = 'Concurrent User'
            Aliases            = @('concurrent user', 'concurrent users', 'concurrent', 'floating', 'floating license', 'concurrent license')
            Family             = 'commercial'
            Metric             = 'concurrent'
            InstallContext     = 'system'
            AssignmentTarget   = 'device'
            RequiresLicenseKey = $true
            Priority           = 88
            AssignmentGuidance = 'Install per device; consumption is counted when a user checks out a seat. Do not treat each install as a named-user entitlement.'
            InstallGuidance    = 'System-context install. Supply a license server or seat key via APPGETTER_LICENSE_KEY when the vendor requires it.'
        }
        [PSCustomObject]@{
            Pattern            = 'perUser'
            DisplayName        = 'Per User'
            Aliases            = @('per user', 'per named user', 'named user', 'named user plus', 'user license')
            Family             = 'commercial'
            Metric             = 'perUser'
            InstallContext     = 'user'
            AssignmentTarget   = 'user'
            RequiresLicenseKey = $true
            Priority           = 86
            AssignmentGuidance = 'Assign to users (available or required). Intune should run the install as the logged-on user.'
            InstallGuidance    = 'User-context install. Append a license key when APPGETTER_LICENSE_KEY is set.'
        }
        [PSCustomObject]@{
            Pattern            = 'subscription'
            DisplayName        = 'Subscription'
            Aliases            = @('subscription', 'saas', 'software as a service', 'named user subscription', 'user subscription', 'subscription license')
            Family             = 'subscription'
            Metric             = 'perUser'
            InstallContext     = 'user'
            AssignmentTarget   = 'user'
            RequiresLicenseKey = $false
            Priority           = 84
            AssignmentGuidance = 'Assign to licensed users. Sign-in or tenant activation is usually required after install; do not treat this as a device-locked perpetual license.'
            InstallGuidance    = 'Prefer user context. No product key is injected; document any required account or tenant activation in Intune notes.'
        }
        [PSCustomObject]@{
            Pattern            = 'perDevice'
            DisplayName        = 'Per Device'
            Aliases            = @('per device', 'per named device', 'device license', 'device', 'device subscription')
            Family             = 'commercial'
            Metric             = 'perDevice'
            InstallContext     = 'system'
            AssignmentTarget   = 'device'
            RequiresLicenseKey = $true
            Priority           = 82
            AssignmentGuidance = 'Assign as required to devices (or available to device groups). Each targeted device consumes one right.'
            InstallGuidance    = 'System-context install. Append a license key when APPGETTER_LICENSE_KEY is set.'
        }
        [PSCustomObject]@{
            Pattern            = 'clientAccess'
            DisplayName        = 'Client Access License (CAL)'
            Aliases            = @('client access license (cal)', 'client access license', 'client access', 'cal')
            Family             = 'commercial'
            Metric             = 'cal'
            InstallContext     = 'system'
            AssignmentTarget   = 'device'
            RequiresLicenseKey = $false
            Priority           = 80
            AssignmentGuidance = 'The installed client is not itself the entitlement. Track CALs against the server product in ServiceNow; assign the client freely to devices that already have rights.'
            InstallGuidance    = 'Install the client silently in system context. Do not embed a CAL key in the Win32 package.'
        }
        [PSCustomObject]@{
            Pattern            = 'volume'
            DisplayName        = 'Volume'
            Aliases            = @('volume', 'volume license', 'vlk', 'mak', 'kms', 'volume licensing')
            Family             = 'commercial'
            Metric             = 'perDevice'
            InstallContext     = 'system'
            AssignmentTarget   = 'device'
            RequiresLicenseKey = $true
            Priority           = 78
            AssignmentGuidance = 'Assign to corporate devices covered by the volume agreement. Keep the MAK/KMS material out of source control; inject at install time.'
            InstallGuidance    = 'System-context install. Use APPGETTER_LICENSE_KEY for a MAK/PIDKEY when the vendor installer accepts one.'
        }
        [PSCustomObject]@{
            Pattern            = 'enterprise'
            DisplayName        = 'Enterprise / Unlimited'
            Aliases            = @('enterprise / unlimited', 'enterprise', 'enterprise agreement', 'unlimited', 'ea', 'eela', 'site wide')
            Family             = 'commercial'
            Metric             = 'unlimited'
            InstallContext     = 'system'
            AssignmentTarget   = 'device'
            RequiresLicenseKey = $false
            Priority           = 76
            AssignmentGuidance = 'Covered by an enterprise or unlimited grant. Safe to assign broadly to in-scope devices.'
            InstallGuidance    = 'System-context install. A shared enterprise key is optional; prefer organization-wide activation over a per-package key.'
        }
        [PSCustomObject]@{
            Pattern            = 'siteLicense'
            DisplayName        = 'Site License'
            Aliases            = @('site license', 'site', 'campus license', 'campus')
            Family             = 'commercial'
            Metric             = 'site'
            InstallContext     = 'system'
            AssignmentTarget   = 'device'
            RequiresLicenseKey = $false
            Priority           = 74
            AssignmentGuidance = 'Assign to devices at the licensed site or campus. Do not deploy outside the covered location.'
            InstallGuidance    = 'System-context install. Site keys are optional; document the covered location in package notes.'
        }
        [PSCustomObject]@{
            Pattern            = 'perCore'
            DisplayName        = 'Per Core'
            Aliases            = @('per core', 'core', 'pvu', 'processor value unit', 'core license')
            Family             = 'commercial'
            Metric             = 'core'
            InstallContext     = 'system'
            AssignmentTarget   = 'device'
            RequiresLicenseKey = $true
            Priority           = 72
            AssignmentGuidance = 'Target the specific servers/workstations whose cores are entitled. Do not assign to a broad device group without a core count review.'
            InstallGuidance    = 'System-context install. License keys or license files are commonly required for core-metered products.'
        }
        [PSCustomObject]@{
            Pattern            = 'perProcessor'
            DisplayName        = 'Per Processor'
            Aliases            = @('per processor', 'processor', 'cpu license', 'socket')
            Family             = 'commercial'
            Metric             = 'processor'
            InstallContext     = 'system'
            AssignmentTarget   = 'device'
            RequiresLicenseKey = $true
            Priority           = 70
            AssignmentGuidance = 'Assign only to machines whose CPU sockets are covered by the entitlement.'
            InstallGuidance    = 'System-context install. Supply a license key via APPGETTER_LICENSE_KEY when required.'
        }
        [PSCustomObject]@{
            Pattern            = 'perInstall'
            DisplayName        = 'Per Install'
            Aliases            = @('per install', 'per installation', 'install', 'installation')
            Family             = 'commercial'
            Metric             = 'perInstall'
            InstallContext     = 'system'
            AssignmentTarget   = 'device'
            RequiresLicenseKey = $true
            Priority           = 68
            AssignmentGuidance = 'Each successful install consumes a right. Prefer required device assignment with a tightly scoped group.'
            InstallGuidance    = 'System-context install. Append a license key when APPGETTER_LICENSE_KEY is set.'
        }
        [PSCustomObject]@{
            Pattern            = 'academic'
            DisplayName        = 'Academic'
            Aliases            = @('academic', 'education', 'educational', 'edu license', 'student')
            Family             = 'commercial'
            Metric             = 'perUser'
            InstallContext     = 'user'
            AssignmentTarget   = 'user'
            RequiresLicenseKey = $true
            Priority           = 66
            AssignmentGuidance = 'Assign only to users in the academic entitlement (students/faculty). Do not mix with commercial device groups.'
            InstallGuidance    = 'Prefer user context. Academic editions often need a school-issued key or sign-in.'
        }
        [PSCustomObject]@{
            Pattern            = 'oem'
            DisplayName        = 'OEM'
            Aliases            = @('oem', 'bundled', 'preinstalled')
            Family             = 'commercial'
            Metric             = 'perDevice'
            InstallContext     = 'system'
            AssignmentTarget   = 'device'
            RequiresLicenseKey = $false
            Priority           = 64
            AssignmentGuidance = 'OEM rights stay with the original hardware. Do not redeploy the package to other devices as if it were volume-licensed.'
            InstallGuidance    = 'System-context reinstall on the entitled device only. Do not inject a transferable key.'
        }
        [PSCustomObject]@{
            Pattern            = 'shareware'
            DisplayName        = 'Shareware'
            Aliases            = @('shareware')
            Family             = 'commercial'
            Metric             = 'perInstall'
            InstallContext     = 'system'
            AssignmentTarget   = 'device'
            RequiresLicenseKey = $true
            Priority           = 62
            AssignmentGuidance = 'Treat as unlicensed until a paid key is applied. Keep assignment limited until purchasing is confirmed in ServiceNow.'
            InstallGuidance    = 'May nag or expire without a key. APPGETTER_LICENSE_KEY is appended when present.'
        }
        [PSCustomObject]@{
            Pattern            = 'perpetual'
            DisplayName        = 'Perpetual'
            Aliases            = @('perpetual', 'perpetual license', 'perpetual + software assurance', 'buyout')
            Family             = 'commercial'
            Metric             = 'perInstall'
            InstallContext     = 'system'
            AssignmentTarget   = 'device'
            RequiresLicenseKey = $true
            Priority           = 60
            AssignmentGuidance = 'Rights do not expire. Still assign only to the devices or users covered by the purchased quantity.'
            InstallGuidance    = 'System-context install. Append a license key when APPGETTER_LICENSE_KEY is set.'
        }
        [PSCustomObject]@{
            Pattern            = 'freeware'
            DisplayName        = 'Freeware'
            Aliases            = @('freeware', 'free software', 'no cost', 'no license required', 'non-licensable', 'not licensable', 'non licensable', 'free')
            Family             = 'free'
            Metric             = 'none'
            InstallContext     = 'system'
            AssignmentTarget   = 'device'
            RequiresLicenseKey = $false
            Priority           = 50
            AssignmentGuidance = 'No entitlement tracking required. Safe to assign as available or required to devices.'
            InstallGuidance    = 'No product key. Install silently in system context.'
        }
    )
}

function Get-AppGetterUnknownLicensePattern {
    param(
        [string]$SourceText,
        [string]$Source
    )

    return [PSCustomObject]@{
        Pattern            = 'unknown'
        DisplayName        = 'Unknown'
        SourceText         = $SourceText
        Source             = $Source
        Family             = 'unknown'
        Metric             = 'unknown'
        InstallContext     = 'system'
        AssignmentTarget   = 'device'
        RequiresLicenseKey = $false
        ConfidenceScore    = 0
        NeedsManualReview  = $true
        MatchedAlias       = $null
        EvidenceSummary    = @('No ServiceNow license metric/type matched; defaulting to system-context install.')
        AssignmentGuidance = 'Review the ServiceNow software record and set License info before broad assignment.'
        InstallGuidance    = 'No license pattern applied beyond the default system-context Win32 install.'
        CatalogEntry       = $null
    }
}

function ConvertTo-AppGetterLicenseNormalizedText {
    param([string]$Text)

    if ([string]::IsNullOrWhiteSpace($Text)) {
        return ''
    }

    $normalized = $Text.Trim().ToLowerInvariant()
    $normalized = $normalized -replace '[_\-]+', ' '
    $normalized = $normalized -replace '[^\p{L}\p{N}\s+/()]', ' '
    $normalized = $normalized -replace '\s+', ' '
    return $normalized.Trim()
}

function Test-AppGetterLicenseAliasMatch {
    param(
        [string]$Haystack,
        [string]$Alias
    )

    if ([string]::IsNullOrWhiteSpace($Haystack) -or [string]::IsNullOrWhiteSpace($Alias)) {
        return $false
    }

    $escaped = [regex]::Escape($Alias)
    return [regex]::IsMatch($Haystack, "(?<![\p{L}\p{N}])$escaped(?![\p{L}\p{N}])")
}

function Resolve-AppGetterLicenseCatalogMatch {
    param(
        [string]$NormalizedText,
        [int]$MinimumScore = 70
    )

    if ([string]::IsNullOrWhiteSpace($NormalizedText)) {
        return $null
    }

    $best = $null
    foreach ($entry in Get-AppGetterLicenseCatalog) {
        $displayNormalized = ConvertTo-AppGetterLicenseNormalizedText -Text $entry.DisplayName
        $patternNormalized = ConvertTo-AppGetterLicenseNormalizedText -Text $entry.Pattern
        $score = 0
        $matchedAlias = $null

        if ($NormalizedText -eq $displayNormalized -or $NormalizedText -eq $patternNormalized) {
            $score = 100
            $matchedAlias = $entry.DisplayName
        } else {
            foreach ($alias in @($entry.Aliases | Sort-Object { $_.Length } -Descending)) {
                $aliasNormalized = ConvertTo-AppGetterLicenseNormalizedText -Text $alias
                if ([string]::IsNullOrWhiteSpace($aliasNormalized)) {
                    continue
                }
                if ($NormalizedText -eq $aliasNormalized) {
                    $score = 95
                    $matchedAlias = $alias
                    break
                }
                if (Test-AppGetterLicenseAliasMatch -Haystack $NormalizedText -Alias $aliasNormalized) {
                    $candidate = 70 + [Math]::Min(20, $aliasNormalized.Length)
                    if ($candidate -gt $score) {
                        $score = $candidate
                        $matchedAlias = $alias
                    }
                }
            }
        }

        if ($score -lt $MinimumScore) {
            continue
        }

        $isBetter = $false
        if (-not $best) {
            $isBetter = $true
        } elseif ($score -gt $best.Score) {
            $isBetter = $true
        } elseif ($score -eq $best.Score -and $entry.Priority -gt $best.Entry.Priority) {
            $isBetter = $true
        }

        if ($isBetter) {
            $best = [PSCustomObject]@{
                Entry        = $entry
                Score        = $score
                MatchedAlias = $matchedAlias
            }
        }
    }

    return $best
}

function New-AppGetterLicensePatternResult {
    param(
        [pscustomobject]$Entry,
        [string]$SourceText,
        [string]$Source,
        [int]$ConfidenceScore,
        [string]$MatchedAlias,
        [string[]]$EvidenceSummary
    )

    $needsReview = ($ConfidenceScore -lt 60) -or [bool]$Entry.RequiresLicenseKey

    return [PSCustomObject]@{
        Pattern            = $Entry.Pattern
        DisplayName        = $Entry.DisplayName
        SourceText         = $SourceText
        Source             = $Source
        Family             = $Entry.Family
        Metric             = $Entry.Metric
        InstallContext     = $Entry.InstallContext
        AssignmentTarget   = $Entry.AssignmentTarget
        RequiresLicenseKey = [bool]$Entry.RequiresLicenseKey
        ConfidenceScore    = $ConfidenceScore
        NeedsManualReview  = $needsReview
        MatchedAlias       = $MatchedAlias
        EvidenceSummary    = @($EvidenceSummary)
        AssignmentGuidance = $Entry.AssignmentGuidance
        InstallGuidance    = $Entry.InstallGuidance
        CatalogEntry       = $Entry
    }
}

function Resolve-AppGetterLicensePattern {
    <#
    .SYNOPSIS
        Identify a ServiceNow-aligned licensing pattern and the packaging behavior to apply.
    .DESCRIPTION
        Maps a ServiceNow license metric/type field (and optional app description hints) to a
        canonical pattern used for Intune install context, assignment notes, and license-key handling.
    #>
    [CmdletBinding()]
    param(
        [string]$LicenseInfo,
        [string]$AppName,
        [string]$Publisher,
        [string]$Description
    )

    $fieldText = if ($LicenseInfo) { $LicenseInfo.Trim() } else { '' }
    $normalizedField = ConvertTo-AppGetterLicenseNormalizedText -Text $fieldText

    if ($normalizedField) {
        $match = Resolve-AppGetterLicenseCatalogMatch -NormalizedText $normalizedField -MinimumScore 70
        if ($match) {
            $evidence = @(
                "ServiceNow license field: $fieldText"
                "Matched pattern '$($match.Entry.DisplayName)' via '$($match.MatchedAlias)'"
            )
            return New-AppGetterLicensePatternResult -Entry $match.Entry -SourceText $fieldText `
                -Source 'servicenow' -ConfidenceScore $match.Score -MatchedAlias $match.MatchedAlias `
                -EvidenceSummary $evidence
        }

        $unknown = Get-AppGetterUnknownLicensePattern -SourceText $fieldText -Source 'servicenow'
        $unknown.EvidenceSummary = @(
            "ServiceNow license field was provided but not recognized: $fieldText"
            'Defaulting to system-context install until the value is mapped.'
        )
        return $unknown
    }

    $hintParts = @($AppName, $Publisher, $Description) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    $hintText = ($hintParts -join ' ').Trim()
    $normalizedHint = ConvertTo-AppGetterLicenseNormalizedText -Text $hintText
    if ($normalizedHint) {
        $inferred = Resolve-AppGetterLicenseCatalogMatch -NormalizedText $normalizedHint -MinimumScore 80
        if ($inferred) {
            $confidence = [Math]::Min(55, $inferred.Score - 30)
            $evidence = @(
                "No ServiceNow license field provided; inferred from application metadata"
                "Matched '$($inferred.Entry.DisplayName)' via '$($inferred.MatchedAlias)'"
            )
            $result = New-AppGetterLicensePatternResult -Entry $inferred.Entry -SourceText '' `
                -Source 'inferred' -ConfidenceScore $confidence -MatchedAlias $inferred.MatchedAlias `
                -EvidenceSummary $evidence
            $result.NeedsManualReview = $true
            return $result
        }
    }

    return Get-AppGetterUnknownLicensePattern -SourceText '' -Source 'none'
}

function ConvertTo-AppGetterLicenseMetadata {
    param([pscustomobject]$LicensePattern)

    if (-not $LicensePattern) {
        return $null
    }

    return [ordered]@{
        pattern            = $LicensePattern.Pattern
        displayName        = $LicensePattern.DisplayName
        sourceText         = $LicensePattern.SourceText
        source             = $LicensePattern.Source
        family             = $LicensePattern.Family
        metric             = $LicensePattern.Metric
        installContext     = $LicensePattern.InstallContext
        assignmentTarget   = $LicensePattern.AssignmentTarget
        requiresLicenseKey = [bool]$LicensePattern.RequiresLicenseKey
        confidenceScore    = [int]$LicensePattern.ConfidenceScore
        needsManualReview  = [bool]$LicensePattern.NeedsManualReview
        matchedAlias       = $LicensePattern.MatchedAlias
        evidenceSummary    = @($LicensePattern.EvidenceSummary)
        assignmentGuidance = $LicensePattern.AssignmentGuidance
        installGuidance    = $LicensePattern.InstallGuidance
        generatedAt        = (Get-Date).ToUniversalTime().ToString('o')
    }
}

function Get-AppGetterLicenseInstallContext {
    param([pscustomobject]$LicensePattern)

    if ($LicensePattern -and $LicensePattern.InstallContext -eq 'user') {
        return 'user'
    }
    return 'system'
}
