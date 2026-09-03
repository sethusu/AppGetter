# Licensing pattern discovery and application.
#
# AppGetter ingests the licensing text that already lives on the ServiceNow software
# record, classifies it into a known licensing pattern, corroborates that pattern with
# evidence found inside the installer binary, and then applies the pattern to the
# generated Intune package (install command arguments, install.ps1 licensing stage,
# staged license artifacts, and package metadata).

function Get-AppGetterLicensingPatternCatalog {
    <#
    .SYNOPSIS
        Returns the ordered catalog of licensing patterns AppGetter can recognize.
    .DESCRIPTION
        Each pattern carries the weighted markers used to classify a ServiceNow
        licensing field, the activation method that must be applied at install time,
        and the Intune assignment style that suits the licensing model.
    #>
    return @(
        @{
            Id                       = 'open-source'
            Name                     = 'Open source'
            LicenseType              = 'Open source'
            ActivationMethod         = 'none'
            RequiredArtifact         = 'none'
            RequiresActivation       = $false
            AssignmentRecommendation = 'required'
            Guidance                 = 'No activation step. Record the license (for example GPL or MIT) on the ServiceNow software model for attribution and redistribution review.'
            Markers                  = @(
                @{ Pattern = 'open\s*source'; Weight = 40 }
                @{ Pattern = '\bfoss\b'; Weight = 30 }
                @{ Pattern = '\b(?:a|l)?gpl(?:v?[23])?\b'; Weight = 35 }
                @{ Pattern = 'mit licen[cs]e'; Weight = 35 }
                @{ Pattern = 'apache licen[cs]e'; Weight = 35 }
                @{ Pattern = 'bsd licen[cs]e'; Weight = 35 }
                @{ Pattern = 'mozilla public licen[cs]e'; Weight = 35 }
                @{ Pattern = 'eclipse public licen[cs]e'; Weight = 35 }
                @{ Pattern = 'public domain'; Weight = 30 }
            )
        }
        @{
            Id                       = 'freeware'
            Name                     = 'Freeware / no license required'
            LicenseType              = 'Freeware'
            ActivationMethod         = 'none'
            RequiredArtifact         = 'none'
            RequiresActivation       = $false
            AssignmentRecommendation = 'required'
            Guidance                 = 'No activation step. Safe to assign as Required; confirm the vendor permits commercial use inside the organization.'
            Markers                  = @(
                @{ Pattern = 'freeware'; Weight = 45 }
                @{ Pattern = 'no licen[cs]e (?:is )?(?:required|needed)'; Weight = 45 }
                @{ Pattern = 'no (?:activation|key|cost|charge|fee)'; Weight = 35 }
                @{ Pattern = 'free\s*(?:of charge|to use|for (?:commercial|business|internal|personal) use)'; Weight = 40 }
                @{ Pattern = '\bgratis\b'; Weight = 25 }
                @{ Pattern = '\bfree\b'; Weight = 12 }
            )
            NegativeMarkers          = @(
                @{ Pattern = '\btrial\b'; Weight = 25 }
                @{ Pattern = 'evaluation'; Weight = 25 }
            )
        }
        @{
            Id                       = 'trial'
            Name                     = 'Trial / evaluation'
            LicenseType              = 'Trial / evaluation'
            ActivationMethod         = 'trial'
            RequiredArtifact         = 'none'
            RequiresActivation       = $false
            AssignmentRecommendation = 'available'
            Guidance                 = 'Time-limited build. Assign as Available so the install is traceable to a requester, and schedule a ServiceNow follow-up before the trial expires.'
            Markers                  = @(
                @{ Pattern = '\btrial\b'; Weight = 45 }
                @{ Pattern = 'evaluation'; Weight = 40 }
                @{ Pattern = '\beval(?:uation)? (?:copy|licen[cs]e|version)\b'; Weight = 35 }
                @{ Pattern = '\bdemo\b'; Weight = 25 }
                @{ Pattern = '\b\d{1,3}[\s-]day\b'; Weight = 30 }
                @{ Pattern = 'time[\s-]limited'; Weight = 30 }
                @{ Pattern = 'expir\w*'; Weight = 15 }
            )
        }
        @{
            Id                       = 'subscription-user'
            Name                     = 'Per-user subscription (account sign-in)'
            LicenseType              = 'Per user (subscription)'
            ActivationMethod         = 'signin'
            RequiredArtifact         = 'none'
            RequiresActivation       = $true
            AssignmentRecommendation = 'available'
            Guidance                 = 'Entitlement follows the user account, so the installer itself carries no key. Assign as Available to licensed users (or to a group driven by the ServiceNow entitlement) and let first-launch sign-in activate the product.'
            Markers                  = @(
                @{ Pattern = 'subscription'; Weight = 35 }
                @{ Pattern = '\bsaas\b'; Weight = 30 }
                @{ Pattern = 'per[\s-]user'; Weight = 40 }
                @{ Pattern = 'named[\s-]user'; Weight = 40 }
                @{ Pattern = 'user[\s-]based'; Weight = 30 }
                @{ Pattern = 'assigned to (?:a |the )?user'; Weight = 30 }
                @{ Pattern = 'sign[\s-]?in|single sign[\s-]?on|\bsso\b|account[\s-]based'; Weight = 30 }
                @{ Pattern = 'microsoft 365|\bm365\b|office 365|\bo365\b|entra|azure ad'; Weight = 30 }
                @{ Pattern = '\b(?:annual|monthly|yearly)\b'; Weight = 15 }
            )
        }
        @{
            Id                       = 'device-perpetual'
            Name                     = 'Per-device perpetual (license key)'
            LicenseType              = 'Per device (perpetual)'
            ActivationMethod         = 'key'
            RequiredArtifact         = 'key'
            RequiresActivation       = $true
            AssignmentRecommendation = 'required'
            Guidance                 = 'Entitlement follows the device, so the key can be baked into the install. Assign as Required to the device group that matches the purchased seat count in ServiceNow.'
            Markers                  = @(
                @{ Pattern = 'per[\s-]device'; Weight = 45 }
                @{ Pattern = 'per[\s-]machine'; Weight = 40 }
                @{ Pattern = 'per[\s-]install(?:ation)?'; Weight = 30 }
                @{ Pattern = 'per[\s-]seat'; Weight = 25 }
                @{ Pattern = 'device[\s-]based'; Weight = 30 }
                @{ Pattern = 'node[\s-]?locked'; Weight = 40 }
                @{ Pattern = 'machine[\s-]bound'; Weight = 30 }
                @{ Pattern = 'perpetual'; Weight = 30 }
                @{ Pattern = 'one[\s-]time (?:purchase|fee|payment)'; Weight = 25 }
            )
        }
        @{
            Id                       = 'core-processor'
            Name                     = 'Per core / processor'
            LicenseType              = 'Per core / processor'
            ActivationMethod         = 'key'
            RequiredArtifact         = 'key'
            RequiresActivation       = $true
            AssignmentRecommendation = 'required'
            Guidance                 = 'Capacity-metered licensing. Confirm the core, socket, or instance count of every target device against the ServiceNow entitlement before broad assignment.'
            Markers                  = @(
                @{ Pattern = 'per[\s-]core'; Weight = 45 }
                @{ Pattern = 'per[\s-]processor'; Weight = 45 }
                @{ Pattern = 'per[\s-](?:socket|cpu)'; Weight = 35 }
                @{ Pattern = 'per[\s-]server'; Weight = 30 }
                @{ Pattern = 'per[\s-]instance'; Weight = 25 }
                @{ Pattern = 'core[\s-]based'; Weight = 30 }
            )
        }
        @{
            Id                       = 'concurrent-floating'
            Name                     = 'Concurrent / floating (license server)'
            LicenseType              = 'Concurrent / floating'
            ActivationMethod         = 'licenseserver'
            RequiredArtifact         = 'server'
            RequiresActivation       = $true
            AssignmentRecommendation = 'required'
            Guidance                 = 'Seats are checked out from a license server at launch. Point the client at the server during install and make sure the vendor daemon port is reachable from the target subnets.'
            Markers                  = @(
                @{ Pattern = 'concurrent'; Weight = 45 }
                @{ Pattern = 'floating'; Weight = 45 }
                @{ Pattern = 'network licen[cs]e'; Weight = 40 }
                @{ Pattern = 'licen[cs]e server'; Weight = 45 }
                @{ Pattern = 'flex(?:lm|net)'; Weight = 45 }
                @{ Pattern = '\b(?:lmgrd|lmutil|lmtools|lmadmin)\b'; Weight = 40 }
                @{ Pattern = '\brlm\b'; Weight = 30 }
                @{ Pattern = 'sentinel rms'; Weight = 35 }
                @{ Pattern = 'licen[cs]e manager'; Weight = 25 }
                @{ Pattern = 'served licen[cs]e'; Weight = 30 }
                @{ Pattern = 'token[\s-]based'; Weight = 25 }
                @{ Pattern = 'check(?:ed|s)?[\s-]?out'; Weight = 20 }
                @{ Pattern = '\b\d{2,5}@[a-z][a-z0-9.\-]*'; Weight = 35 }
            )
        }
        @{
            Id                       = 'license-file'
            Name                     = 'License file / entitlement certificate'
            LicenseType              = 'License file'
            ActivationMethod         = 'licensefile'
            RequiredArtifact         = 'file'
            RequiresActivation       = $true
            AssignmentRecommendation = 'required'
            Guidance                 = 'The product reads a license file from disk. Ship the file inside the package and copy it into place during install so the app is licensed on first launch.'
            Markers                  = @(
                @{ Pattern = 'licen[cs]e file'; Weight = 45 }
                @{ Pattern = 'licen[cs]e\.dat'; Weight = 45 }
                @{ Pattern = 'licen[cs]e\.lic'; Weight = 45 }
                @{ Pattern = '\.lic\b'; Weight = 30 }
                @{ Pattern = 'licen[cs]e certificate'; Weight = 30 }
                @{ Pattern = 'entitlement file'; Weight = 30 }
            )
        }
        @{
            Id                       = 'site-enterprise'
            Name                     = 'Site / enterprise agreement'
            LicenseType              = 'Site / Enterprise'
            ActivationMethod         = 'key'
            RequiredArtifact         = 'optional-key'
            RequiresActivation       = $false
            AssignmentRecommendation = 'required'
            Guidance                 = 'Covered organization-wide, so the package can be assigned broadly as Required. Apply the shared site key if the vendor issues one.'
            Markers                  = @(
                @{ Pattern = 'site licen[cs]e'; Weight = 50 }
                @{ Pattern = 'site[\s-]wide'; Weight = 35 }
                @{ Pattern = 'campus licen[cs]e'; Weight = 45 }
                @{ Pattern = 'enterprise (?:agreement|licen[cs]e)'; Weight = 45 }
                @{ Pattern = 'volume licen[cs]e|volume licensing'; Weight = 35 }
                @{ Pattern = 'unlimited (?:licen[cs]e|install|seat|user|device)'; Weight = 35 }
                @{ Pattern = 'organi[sz]ation[\s-]wide'; Weight = 35 }
                @{ Pattern = 'institution(?:al|[\s-]wide)'; Weight = 25 }
            )
        }
        @{
            Id                       = 'volume-activation'
            Name                     = 'Volume activation (MAK / KMS)'
            LicenseType              = 'Volume activation (MAK/KMS)'
            ActivationMethod         = 'volume'
            RequiredArtifact         = 'optional-key'
            RequiresActivation       = $true
            AssignmentRecommendation = 'required'
            Guidance                 = 'Activated through Microsoft volume activation. Let the existing KMS or ADBA infrastructure activate the product, or apply the MAK after install.'
            Markers                  = @(
                @{ Pattern = 'multiple activation key'; Weight = 50 }
                @{ Pattern = 'volume activation'; Weight = 45 }
                @{ Pattern = '\bmak\b'; Weight = 40 }
                @{ Pattern = '\bkms\b'; Weight = 40 }
                @{ Pattern = '\bgvlk\b|generic volume licen[cs]e key'; Weight = 45 }
                @{ Pattern = '\badba\b|active directory[\s-]based activation'; Weight = 40 }
            )
        }
        @{
            Id                       = 'dongle-hardware'
            Name                     = 'Hardware key / dongle'
            LicenseType              = 'Hardware key / dongle'
            ActivationMethod         = 'dongle'
            RequiredArtifact         = 'none'
            RequiresActivation       = $true
            AssignmentRecommendation = 'required'
            Guidance                 = 'Licensing is bound to a physical key, so the package cannot activate the product on its own. Make sure the dongle driver or runtime is deployed and the key is attached before first launch.'
            Markers                  = @(
                @{ Pattern = 'dongle'; Weight = 50 }
                @{ Pattern = 'hardware key'; Weight = 45 }
                @{ Pattern = 'usb (?:key|licen[cs]e|dongle)'; Weight = 40 }
                @{ Pattern = '\bhasp\b'; Weight = 45 }
                @{ Pattern = 'sentinel (?:hl|hasp|ldk)'; Weight = 45 }
                @{ Pattern = 'codemeter|\bwibu\b'; Weight = 45 }
                @{ Pattern = 'hardware lock'; Weight = 35 }
            )
        }
        @{
            Id                       = 'oem-bundled'
            Name                     = 'OEM / bundled with hardware'
            LicenseType              = 'OEM / bundled'
            ActivationMethod         = 'none'
            RequiredArtifact         = 'none'
            RequiresActivation       = $false
            AssignmentRecommendation = 'required'
            Guidance                 = 'Entitlement ships with the hardware. Limit assignment to the device group that owns the OEM entitlement rather than the whole estate.'
            Markers                  = @(
                @{ Pattern = '\boem\b'; Weight = 45 }
                @{ Pattern = 'bundled with (?:hardware|the device|the machine)'; Weight = 40 }
                @{ Pattern = 'pre[\s-]?install(?:ed)?'; Weight = 25 }
                @{ Pattern = 'shipped with (?:hardware|the device)'; Weight = 30 }
            )
        }
        @{
            Id                       = 'paid-key'
            Name                     = 'Purchased license key'
            LicenseType              = 'Paid (license key)'
            ActivationMethod         = 'key'
            RequiredArtifact         = 'key'
            RequiresActivation       = $true
            AssignmentRecommendation = 'available'
            Guidance                 = 'A purchased key activates the product. Apply the key during install when the installer accepts it, and keep the seat count reconciled with the ServiceNow entitlement.'
            Markers                  = @(
                @{ Pattern = 'licen[cs]e key'; Weight = 40 }
                @{ Pattern = 'product key'; Weight = 40 }
                @{ Pattern = 'serial (?:number|key)'; Weight = 40 }
                @{ Pattern = 'activation (?:key|code)'; Weight = 40 }
                @{ Pattern = 'registration (?:key|code)'; Weight = 35 }
                @{ Pattern = 'unlock code'; Weight = 30 }
                @{ Pattern = 'commercial licen[cs]e'; Weight = 30 }
                @{ Pattern = 'requires? (?:a |an )?licen[cs]e'; Weight = 25 }
                @{ Pattern = '\b(?:purchased|paid|procured|billable|chargeback)\b'; Weight = 20 }
                @{ Pattern = '\blicen[cs]ed\b'; Weight = 15 }
            )
        }
    )
}

function Get-AppGetterLicensingUnknownPattern {
    return @{
        Id                       = 'unknown'
        Name                     = 'Unknown licensing'
        LicenseType              = 'Unknown'
        ActivationMethod         = 'unknown'
        RequiredArtifact         = 'none'
        RequiresActivation       = $false
        AssignmentRecommendation = 'available'
        Guidance                 = 'AppGetter could not classify the licensing field. Review the ServiceNow record and re-run with an explicit -LicenseType so the package documents the correct model.'
        Markers                  = @()
    }
}

function Resolve-AppGetterLicenseTypeToPatternId {
    <#
    .SYNOPSIS
        Maps a ServiceNow license type value onto an AppGetter licensing pattern id.
    .DESCRIPTION
        Accepts a pattern id, an AppGetter license type label, or one of the common
        ServiceNow "License type" / "License metric" choice values.
    #>
    param([string]$LicenseType)

    if ([string]::IsNullOrWhiteSpace($LicenseType)) {
        return $null
    }

    $value = ($LicenseType -replace '[\s_/]+', '-').Trim('-').ToLowerInvariant()
    $catalog = Get-AppGetterLicensingPatternCatalog

    foreach ($pattern in $catalog) {
        if ($value -eq $pattern.Id) {
            return $pattern.Id
        }
        $typeSlug = ($pattern.LicenseType -replace '[^A-Za-z0-9]+', '-').Trim('-').ToLowerInvariant()
        if ($value -eq $typeSlug) {
            return $pattern.Id
        }
    }

    $synonyms = [ordered]@{
        'open-source'         = @('open-source', 'oss', 'foss', 'gpl', 'mit', 'apache', 'public-domain')
        'freeware'            = @('free', 'freeware', 'no-licen[cs]e', 'no-charge', 'no-cost', 'zero-cost')
        'trial'               = @('trial', 'evaluation', 'eval', 'demo', 'proof-of-concept', 'poc')
        'subscription-user'   = @('per-user', 'named-user', 'user', 'subscription', 'saas', 'user-subscription', 'named-user-subscription', 'per-user-subscription')
        'device-perpetual'    = @('per-device', 'per-machine', 'device', 'machine', 'per-install', 'per-installation', 'per-seat', 'seat', 'node-locked', 'perpetual', 'per-device-perpetual')
        'core-processor'      = @('per-core', 'per-processor', 'per-cpu', 'per-socket', 'per-server', 'per-instance', 'core', 'processor')
        'concurrent-floating' = @('concurrent', 'concurrent-user', 'floating', 'network', 'network-licen[cs]e', 'licen[cs]e-server', 'flexlm', 'flexnet', 'served')
        'license-file'        = @('licen[cs]e-file', 'entitlement-file', 'certificate', 'lic-file')
        'site-enterprise'     = @('site', 'site-licen[cs]e', 'enterprise', 'enterprise-agreement', 'campus', 'volume', 'volume-licen[cs]e', 'unlimited')
        'volume-activation'   = @('mak', 'kms', 'volume-activation', 'gvlk', 'adba')
        'dongle-hardware'     = @('dongle', 'hardware-key', 'hasp', 'usb-key', 'codemeter')
        'oem-bundled'         = @('oem', 'bundled', 'preinstalled', 'pre-installed')
        'paid-key'            = @('paid', 'purchased', 'commercial', 'licen[cs]e-key', 'product-key', 'serial', 'serial-number', 'activation-key', 'retail')
    }

    foreach ($key in $synonyms.Keys) {
        foreach ($synonym in $synonyms[$key]) {
            if ($value -match "^$synonym$") {
                return $key
            }
        }
    }

    return $null
}

function Get-AppGetterNormalizedLicenseText {
    param([string]$Text)

    if ([string]::IsNullOrWhiteSpace($Text)) {
        return ''
    }

    $normalized = $Text -replace '<[^>]+>', ' '
    $normalized = $normalized -replace '&nbsp;', ' '
    $normalized = $normalized -replace '&amp;', '&'
    $normalized = $normalized -replace '\s+', ' '
    return $normalized.Trim()
}

function Get-AppGetterLicenseDetailsFromText {
    <#
    .SYNOPSIS
        Extracts the concrete licensing artifacts embedded in a ServiceNow licensing field.
    .DESCRIPTION
        Pulls out the license key, license server, license file, environment variable,
        seat count, expiry date, and approval/chargeback signals so the packaging run can
        apply them instead of asking the operator to retype them.
    #>
    param([string]$Text)

    $details = [ordered]@{
        LicenseKey            = $null
        LicenseServer         = $null
        LicenseServerVariable = $null
        LicenseFileName       = $null
        LicenseFileTargetPath = $null
        LicenseQuantity       = $null
        LicenseExpiry         = $null
        RequiresApproval      = $false
        Evidence              = @()
    }

    $normalized = Get-AppGetterNormalizedLicenseText -Text $Text
    if ([string]::IsNullOrWhiteSpace($normalized)) {
        return [PSCustomObject]$details
    }

    $evidence = [System.Collections.Generic.List[string]]::new()

    # License key. Reject prose ("license key: required") by demanding a digit-bearing token.
    $keyStopWords = @(
        'required', 'requested', 'pending', 'unknown', 'none', 'provided', 'managed',
        'attached', 'available', 'applicable', 'purchased', 'included', 'vault', 'servicenow'
    )
    $keyMatch = [regex]::Match(
        $normalized,
        '(?i)\b(?:licen[cs]e|product|serial|activation|registration|unlock|auth(?:orization)?)\s*(?:key|code|number|no\.?|id|#)?\s*(?:is\b|:|=|#)\s*"?([A-Za-z0-9][A-Za-z0-9-]{5,})"?'
    )
    if ($keyMatch.Success) {
        $candidate = $keyMatch.Groups[1].Value.Trim().TrimEnd('.', ',', ';')
        $isStopWord = $false
        foreach ($stopWord in $keyStopWords) {
            if ($candidate -ieq $stopWord) {
                $isStopWord = $true
                break
            }
        }
        if (-not $isStopWord -and $candidate -match '\d' -and $candidate.Length -ge 6) {
            $details.LicenseKey = $candidate
            $evidence.Add('License key parsed from the licensing field (value redacted in package metadata)') | Out-Null
        }
    }

    # License server, either "license server: 27000@host" or a bare port@host token.
    # Host parts must end on an alphanumeric so sentence punctuation is not absorbed.
    $hostPattern = '[A-Za-z0-9](?:[A-Za-z0-9.\-]*[A-Za-z0-9])?'
    $serverMatch = [regex]::Match(
        $normalized,
        "(?i)\b(?:licen[cs]e\s*server|licen[cs]e\s*host|server)\s*(?:is\b|:|=)?\s*`"?(\d{2,5}@$hostPattern|$hostPattern`:\d{2,5})`"?"
    )
    if (-not $serverMatch.Success) {
        $serverMatch = [regex]::Match($normalized, "\b(\d{2,5}@$hostPattern)")
    }
    if ($serverMatch.Success) {
        $details.LicenseServer = $serverMatch.Groups[1].Value.Trim()
        $evidence.Add("License server parsed from the licensing field: $($details.LicenseServer)") | Out-Null
    }

    # Vendor license environment variable, matched case-sensitively so prose is ignored.
    $variableMatch = [regex]::Match($Text, '\b([A-Z][A-Z0-9]{1,}_LICENSE(?:_FILE|_SERVER|_PATH)?|LM_LICENSE_FILE|RLM_LICENSE|LSFORCEHOST|LSHOST)\b')
    if ($variableMatch.Success) {
        $details.LicenseServerVariable = $variableMatch.Groups[1].Value
        $evidence.Add("License environment variable named in the licensing field: $($details.LicenseServerVariable)") | Out-Null
    }

    $fileMatch = [regex]::Match($normalized, '(?i)\b([A-Za-z0-9][\w.\-]*\.(?:lic|dat|licx|entitlement))\b')
    if ($fileMatch.Success) {
        $details.LicenseFileName = $fileMatch.Groups[1].Value
        $evidence.Add("License file named in the licensing field: $($details.LicenseFileName)") | Out-Null
    }

    $targetMatch = [regex]::Match(
        $normalized,
        '(?i)(?:copy|place|install|put|deploy|store)\s+(?:the\s+)?(?:licen[cs]e\s+)?(?:file\s+)?(?:to|in|into|at|under)\s+"?((?:[A-Za-z]:\\|%[^%]+%\\|\\\\)[^\s";,]+)"?'
    )
    if ($targetMatch.Success) {
        $details.LicenseFileTargetPath = $targetMatch.Groups[1].Value.TrimEnd('.', ',', ';')
        $evidence.Add("License file destination parsed from the licensing field: $($details.LicenseFileTargetPath)") | Out-Null
    }

    $quantityMatch = [regex]::Match($normalized, '(?i)\b(\d{1,6})\s*(?:x\s*)?(?:seats?|licen[cs]es?|users?|devices?|installs?|nodes?|copies|cores?)\b')
    if ($quantityMatch.Success) {
        $parsedQuantity = 0
        if ([int]::TryParse($quantityMatch.Groups[1].Value, [ref]$parsedQuantity) -and $parsedQuantity -gt 0) {
            $details.LicenseQuantity = $parsedQuantity
            $evidence.Add("Entitlement quantity parsed from the licensing field: $parsedQuantity") | Out-Null
        }
    }

    $expiryMatch = [regex]::Match(
        $normalized,
        '(?i)\b(?:expir\w*|renew\w*|valid\s+(?:un)?til|end(?:s|ing)?\s+(?:on|date)|term\s+ends?)\s*(?:on|:|=)?\s*(\d{4}-\d{2}-\d{2}|\d{1,2}[/-]\d{1,2}[/-]\d{2,4}|[A-Z][a-z]{2,8}\s+\d{1,2},?\s+\d{4})'
    )
    if ($expiryMatch.Success) {
        $details.LicenseExpiry = $expiryMatch.Groups[1].Value.Trim()
        $evidence.Add("Entitlement expiry parsed from the licensing field: $($details.LicenseExpiry)") | Out-Null
    }

    if ($normalized -match '(?i)\b(?:manager approval|approval required|requires approval|request required|restricted|entitlement required|charge[\s-]?back|cost cent(?:er|re)|purchase order)\b') {
        $details.RequiresApproval = $true
        $evidence.Add('Licensing field indicates an approval or chargeback step before install') | Out-Null
    }

    $details.Evidence = @($evidence)
    return [PSCustomObject]$details
}

function Get-AppGetterLicenseKeyPropertyName {
    <#
    .SYNOPSIS
        Finds the installer property that accepts a license key.
    .DESCRIPTION
        Searches installer binary strings for a curated set of MSI public properties
        known to carry license keys. Only exact, unambiguous tokens are accepted so a
        key is never injected into a property the installer does not understand.
    #>
    param([string[]]$BinaryStrings)

    if (-not $BinaryStrings -or $BinaryStrings.Count -eq 0) {
        return $null
    }

    $knownProperties = @(
        'SERIALNUMBER', 'SERIAL_NUMBER', 'LICENSEKEY', 'LICENSE_KEY', 'LICKEY',
        'PIDKEY', 'PRODUCTKEY', 'PRODUCT_KEY', 'ACTIVATIONKEY', 'ACTIVATION_KEY',
        'REGISTRATIONKEY', 'LICENSECODE', 'LICENSE_CODE'
    )

    $joined = ($BinaryStrings -join "`n")
    foreach ($property in $knownProperties) {
        if ([regex]::IsMatch($joined, "(?<![A-Za-z0-9_])$([regex]::Escape($property))(?![A-Za-z0-9_])")) {
            return $property
        }
    }

    return $null
}

function Get-AppGetterInstallerLicenseEvidence {
    <#
    .SYNOPSIS
        Corroborates a licensing pattern with evidence found inside the installer.
    .DESCRIPTION
        Looks for license-manager runtimes, dongle drivers, activation prompts, and
        key-bearing installer properties, and returns per-pattern score boosts.
    #>
    param([string[]]$BinaryStrings)

    $result = [ordered]@{
        Boosts          = @{}
        Evidence        = @()
        KeyPropertyName = $null
        ServerVariable  = $null
    }

    if (-not $BinaryStrings -or $BinaryStrings.Count -eq 0) {
        return [PSCustomObject]$result
    }

    $joined = ($BinaryStrings -join "`n").ToLowerInvariant()
    $boosts = @{}
    $evidence = [System.Collections.Generic.List[string]]::new()
    $serverVariable = $null

    $signatures = @(
        @{ PatternId = 'concurrent-floating'; Weight = 30; Label = 'FlexNet/FLEXlm license manager'; Markers = @('flexlm', 'flexnet', 'lmgrd', 'lmutil', 'flexnet licensing'); Variable = 'LM_LICENSE_FILE' }
        @{ PatternId = 'concurrent-floating'; Weight = 25; Label = 'Reprise License Manager'; Markers = @('rlm_license', 'reprise license'); Variable = 'RLM_LICENSE' }
        @{ PatternId = 'concurrent-floating'; Weight = 25; Label = 'Sentinel RMS license server'; Markers = @('sentinel rms', 'lservnt', 'lsforcehost'); Variable = 'LSFORCEHOST' }
        @{ PatternId = 'dongle-hardware'; Weight = 30; Label = 'HASP/Sentinel hardware key runtime'; Markers = @('hasp', 'sentinel hl', 'sentinel ldk', 'haspds', 'aksusb') }
        @{ PatternId = 'dongle-hardware'; Weight = 30; Label = 'CodeMeter/WIBU hardware key runtime'; Markers = @('codemeter', 'wibukey', 'wibu-systems') }
        @{ PatternId = 'license-file'; Weight = 25; Label = 'license file lookup'; Markers = @('license.dat', 'license.lic', 'licensefile', 'license file not found') }
        @{ PatternId = 'trial'; Weight = 20; Label = 'trial/expiry enforcement strings'; Markers = @('trial period', 'trial expired', 'evaluation period', 'days remaining') }
        @{ PatternId = 'subscription-user'; Weight = 20; Label = 'account sign-in activation'; Markers = @('sign in to activate', 'sign in with your', 'subscription expired', 'oauth', 'login.microsoftonline.com') }
        @{ PatternId = 'volume-activation'; Weight = 25; Label = 'volume activation client'; Markers = @('slmgr', 'ospp.vbs', 'kms host', 'sppsvc') }
        @{ PatternId = 'paid-key'; Weight = 20; Label = 'license key entry prompt'; Markers = @('enter your license key', 'enter serial number', 'product key', 'registration code') }
    )

    foreach ($signature in $signatures) {
        $matched = @($signature.Markers | Where-Object { $joined.Contains($_) })
        if ($matched.Count -eq 0) {
            continue
        }

        $patternId = [string]$signature.PatternId
        if (-not $boosts.ContainsKey($patternId)) {
            $boosts[$patternId] = 0
        }
        $boosts[$patternId] = [Math]::Max([int]$boosts[$patternId], [int]$signature.Weight)
        $evidence.Add("Installer binary evidence for $patternId - $($signature.Label): matched $($matched -join ', ')") | Out-Null

        if ($signature.ContainsKey('Variable') -and -not $serverVariable) {
            $serverVariable = [string]$signature.Variable
        }
    }

    $keyProperty = Get-AppGetterLicenseKeyPropertyName -BinaryStrings $BinaryStrings
    if ($keyProperty) {
        foreach ($patternId in @('paid-key', 'device-perpetual')) {
            if (-not $boosts.ContainsKey($patternId)) {
                $boosts[$patternId] = 0
            }
            $boosts[$patternId] = [Math]::Max([int]$boosts[$patternId], 15)
        }
        $evidence.Add("Installer exposes a license key property: $keyProperty") | Out-Null
    }

    $result.Boosts = $boosts
    $result.Evidence = @($evidence)
    $result.KeyPropertyName = $keyProperty
    $result.ServerVariable = $serverVariable
    return [PSCustomObject]$result
}

function Get-AppGetterLicensingPattern {
    <#
    .SYNOPSIS
        Scores every licensing pattern against a licensing field and returns the winner.
    #>
    param(
        [string]$LicenseInfo,
        [string]$LicenseType,
        [hashtable]$InstallerBoosts
    )

    $normalized = (Get-AppGetterNormalizedLicenseText -Text $LicenseInfo).ToLowerInvariant()
    $forcedPatternId = Resolve-AppGetterLicenseTypeToPatternId -LicenseType $LicenseType
    $catalog = Get-AppGetterLicensingPatternCatalog

    $scored = [System.Collections.Generic.List[object]]::new()
    $order = 0
    foreach ($pattern in $catalog) {
        $order++
        $score = 0
        $matchedMarkers = [System.Collections.Generic.List[string]]::new()

        if ($normalized) {
            foreach ($marker in $pattern.Markers) {
                if ($normalized -match $marker.Pattern) {
                    $score += [int]$marker.Weight
                    $matchedMarkers.Add([string]$Matches[0]) | Out-Null
                }
            }

            if ($pattern.ContainsKey('NegativeMarkers')) {
                foreach ($negative in $pattern.NegativeMarkers) {
                    if ($normalized -match $negative.Pattern) {
                        $score -= [int]$negative.Weight
                    }
                }
            }
        }

        $installerBoost = 0
        if ($InstallerBoosts -and $InstallerBoosts.ContainsKey($pattern.Id)) {
            $installerBoost = [int]$InstallerBoosts[$pattern.Id]
            $score += $installerBoost
        }

        if ($forcedPatternId -and $pattern.Id -eq $forcedPatternId) {
            $score += 70
        }

        $scored.Add([PSCustomObject]@{
                Pattern        = $pattern
                Score          = [Math]::Min(100, [Math]::Max(0, $score))
                MatchedMarkers = @($matchedMarkers)
                InstallerBoost = $installerBoost
                Order          = $order
            }) | Out-Null
    }

    # Catalog order breaks score ties so the same field always yields the same pattern.
    $ranked = @($scored | Sort-Object -Property @{ Expression = 'Score'; Descending = $true }, @{ Expression = 'Order'; Descending = $false })
    $best = $ranked[0]

    if ($best.Score -le 0) {
        return [PSCustomObject]@{
            Pattern         = Get-AppGetterLicensingUnknownPattern
            Score           = 0
            MatchedMarkers  = @()
            InstallerBoost  = 0
            Ranked          = $ranked
            ForcedPatternId = $forcedPatternId
        }
    }

    return [PSCustomObject]@{
        Pattern         = $best.Pattern
        Score           = $best.Score
        MatchedMarkers  = @($best.MatchedMarkers)
        InstallerBoost  = $best.InstallerBoost
        Ranked          = $ranked
        ForcedPatternId = $forcedPatternId
    }
}

function Protect-AppGetterLicenseKey {
    <#
    .SYNOPSIS
        Masks a license key so it can be written into package metadata safely.
    #>
    param([string]$LicenseKey)

    if ([string]::IsNullOrWhiteSpace($LicenseKey)) {
        return $null
    }

    $trimmed = $LicenseKey.Trim()
    if ($trimmed.Length -le 8) {
        return ('*' * $trimmed.Length)
    }

    $head = $trimmed.Substring(0, 4)
    $tail = $trimmed.Substring($trimmed.Length - 4)
    return "$head$('*' * [Math]::Min(12, $trimmed.Length - 8))$tail"
}

function Get-AppGetterRedactedLicenseInfo {
    <#
    .SYNOPSIS
        Removes secret values from the licensing text before it is persisted.
    #>
    param(
        [string]$LicenseInfo,
        [string[]]$Secrets
    )

    $text = Get-AppGetterNormalizedLicenseText -Text $LicenseInfo
    if ([string]::IsNullOrWhiteSpace($text)) {
        return ''
    }

    foreach ($secret in @($Secrets)) {
        if ([string]::IsNullOrWhiteSpace($secret)) {
            continue
        }
        $text = $text.Replace($secret, (Protect-AppGetterLicenseKey -LicenseKey $secret))
    }

    return $text
}

function Resolve-AppGetterLicensing {
    <#
    .SYNOPSIS
        Identifies the licensing pattern for an application and resolves how to apply it.
    .DESCRIPTION
        Classifies the licensing text ingested from ServiceNow, corroborates it against
        evidence inside the installer, extracts the license key, server, or file that the
        pattern needs, and returns the resolution that packaging applies to install.ps1,
        the install command, and the package metadata.
    .PARAMETER LicenseInfo
        The raw licensing text from the ServiceNow software record.
    .PARAMETER LicenseType
        Optional. An explicit ServiceNow license type that overrides text classification.
    .PARAMETER LicenseKey
        Optional. License key to apply. Overrides any key parsed from LicenseInfo.
    .PARAMETER LicenseServer
        Optional. License server as port@host. Overrides any server parsed from LicenseInfo.
    .PARAMETER LicenseServerVariable
        Optional. Environment variable the client reads to find the license server.
    .PARAMETER LicenseFilePath
        Optional. Path to a license file to ship inside the package.
    .PARAMETER LicenseFileTargetPath
        Optional. Absolute path the license file is copied to on the target device.
    .PARAMETER InstallerPath
        Optional. Installer to fingerprint for licensing evidence.
    .PARAMETER Fingerprint
        Optional. An installer fingerprint already produced by switch discovery, reused
        to avoid reading the installer twice.
    .EXAMPLE
        Resolve-AppGetterLicensing -LicenseInfo 'Concurrent - FlexLM, license server 27000@lm.corp.local'
    #>
    [CmdletBinding()]
    param(
        [string]$LicenseInfo,
        [string]$LicenseType,
        [string]$LicenseKey,
        [string]$LicenseServer,
        [string]$LicenseServerVariable,
        [string]$LicenseFilePath,
        [string]$LicenseFileTargetPath,
        [string]$InstallerPath,
        [pscustomobject]$Fingerprint
    )

    $binaryStrings = @()
    if ($Fingerprint -and $Fingerprint.BinaryStrings) {
        $binaryStrings = @($Fingerprint.BinaryStrings)
    } elseif ($InstallerPath -and (Test-Path -LiteralPath $InstallerPath -PathType Leaf)) {
        try {
            $binaryStrings = @((Get-InstallerFingerprint -InstallerPath $InstallerPath).BinaryStrings)
        } catch {
            $binaryStrings = @()
        }
    }

    $installerEvidence = Get-AppGetterInstallerLicenseEvidence -BinaryStrings $binaryStrings
    $textDetails = Get-AppGetterLicenseDetailsFromText -Text $LicenseInfo
    $classification = Get-AppGetterLicensingPattern -LicenseInfo $LicenseInfo -LicenseType $LicenseType `
        -InstallerBoosts $installerEvidence.Boosts

    $pattern = $classification.Pattern
    $confidence = [int]$classification.Score

    $evidence = [System.Collections.Generic.List[string]]::new()
    if ([string]::IsNullOrWhiteSpace($LicenseInfo)) {
        $evidence.Add('No licensing field was supplied; licensing was not classified from ServiceNow data') | Out-Null
    } else {
        $evidence.Add("ServiceNow licensing field ingested: $($classification.MatchedMarkers.Count) marker(s) matched pattern '$($pattern.Id)'") | Out-Null
        if ($classification.MatchedMarkers.Count -gt 0) {
            $evidence.Add("Matched licensing terms: $(($classification.MatchedMarkers | Select-Object -Unique) -join ', ')") | Out-Null
        }
    }
    if ($classification.ForcedPatternId) {
        $evidence.Add("Explicit license type '$LicenseType' resolved to pattern '$($classification.ForcedPatternId)'") | Out-Null
    }
    foreach ($item in @($textDetails.Evidence)) {
        $evidence.Add([string]$item) | Out-Null
    }
    foreach ($item in @($installerEvidence.Evidence)) {
        $evidence.Add([string]$item) | Out-Null
    }

    # Explicit parameters always win over values parsed out of the licensing text.
    $resolvedKey = if ($LicenseKey) { $LicenseKey.Trim() } else { $textDetails.LicenseKey }
    $resolvedServer = if ($LicenseServer) { $LicenseServer.Trim() } else { $textDetails.LicenseServer }
    $resolvedFileTarget = if ($LicenseFileTargetPath) { $LicenseFileTargetPath.Trim() } else { $textDetails.LicenseFileTargetPath }

    $resolvedVariable = $LicenseServerVariable
    if (-not $resolvedVariable) { $resolvedVariable = $textDetails.LicenseServerVariable }
    if (-not $resolvedVariable) { $resolvedVariable = $installerEvidence.ServerVariable }
    if (-not $resolvedVariable -and $resolvedServer) { $resolvedVariable = 'LM_LICENSE_FILE' }

    $resolvedFileName = $null
    if ($LicenseFilePath) {
        $resolvedFileName = Split-Path -Leaf $LicenseFilePath
    } elseif ($textDetails.LicenseFileName) {
        $resolvedFileName = $textDetails.LicenseFileName
    }

    # A supplied artifact can outrank a weakly matched pattern: a license file or a
    # license server is a stronger statement of intent than a few keyword hits.
    if ($LicenseFilePath -and $pattern.ActivationMethod -ne 'licensefile' -and $confidence -lt 60) {
        $pattern = Get-AppGetterLicensingPatternCatalog | Where-Object { $_.Id -eq 'license-file' } | Select-Object -First 1
        $confidence = [Math]::Max($confidence, 70)
        $evidence.Add('A license file was supplied, so the license-file pattern was selected') | Out-Null
    } elseif ($resolvedServer -and $pattern.ActivationMethod -ne 'licenseserver' -and $confidence -lt 60) {
        $pattern = Get-AppGetterLicensingPatternCatalog | Where-Object { $_.Id -eq 'concurrent-floating' } | Select-Object -First 1
        $confidence = [Math]::Max($confidence, 70)
        $evidence.Add('A license server was supplied, so the concurrent/floating pattern was selected') | Out-Null
    } elseif ($resolvedKey -and $pattern.ActivationMethod -notin @('key', 'volume') -and $confidence -lt 50) {
        $pattern = Get-AppGetterLicensingPatternCatalog | Where-Object { $_.Id -eq 'paid-key' } | Select-Object -First 1
        $confidence = [Math]::Max($confidence, 60)
        $evidence.Add('A license key was supplied, so the purchased-key pattern was selected') | Out-Null
    }

    $activationMethod = [string]$pattern.ActivationMethod

    $missingArtifacts = [System.Collections.Generic.List[string]]::new()
    switch ($pattern.RequiredArtifact) {
        'key' {
            if (-not $resolvedKey) {
                $missingArtifacts.Add('license key') | Out-Null
            }
        }
        'server' {
            if (-not $resolvedServer) {
                $missingArtifacts.Add('license server (port@host)') | Out-Null
            }
        }
        'file' {
            if (-not $LicenseFilePath) {
                $missingArtifacts.Add('license file') | Out-Null
            }
        }
    }

    $keyPropertyName = $installerEvidence.KeyPropertyName
    $complianceNotes = [System.Collections.Generic.List[string]]::new()
    if ($textDetails.LicenseQuantity) {
        $complianceNotes.Add("Entitlement covers $($textDetails.LicenseQuantity) seat(s); keep the Intune assignment within that count and reconcile installs back to ServiceNow.") | Out-Null
    }
    if ($textDetails.LicenseExpiry) {
        $complianceNotes.Add("Entitlement expiry recorded as $($textDetails.LicenseExpiry); plan renewal or removal before that date.") | Out-Null
    }
    if ($textDetails.RequiresApproval) {
        $complianceNotes.Add('The licensing field indicates approval or chargeback is required, so publish this app as Available behind the existing ServiceNow request flow.') | Out-Null
    }
    foreach ($missing in $missingArtifacts) {
        $complianceNotes.Add("Pattern '$($pattern.Name)' expects a $missing, which was not supplied; the package documents the requirement instead of applying it.") | Out-Null
    }
    if ($activationMethod -eq 'key' -and $resolvedKey -and -not $keyPropertyName) {
        $complianceNotes.Add('A license key was supplied but no key-bearing installer property was detected, so the key is documented for a post-install step rather than injected into the install command.') | Out-Null
    }

    $assignmentRecommendation = [string]$pattern.AssignmentRecommendation
    $guidance = [string]$pattern.Guidance
    if ($textDetails.RequiresApproval -and $assignmentRecommendation -ne 'available') {
        $assignmentRecommendation = 'available'
        $guidance = "$guidance Because the licensing field calls for approval or chargeback, publish this package as Available behind the request flow rather than Required."
    }

    $classified = -not [string]::IsNullOrWhiteSpace($LicenseInfo) -or [bool]$classification.ForcedPatternId
    $needsManualReview = (-not $classified) -or $confidence -lt 60 -or $missingArtifacts.Count -gt 0 -or $pattern.Id -eq 'unknown'

    return [PSCustomObject]@{
        PatternId                = [string]$pattern.Id
        PatternName              = [string]$pattern.Name
        LicenseType              = [string]$pattern.LicenseType
        ActivationMethod         = $activationMethod
        RequiresActivation       = [bool]$pattern.RequiresActivation
        AssignmentRecommendation = $assignmentRecommendation
        Guidance                 = $guidance
        ConfidenceScore          = [int]$confidence
        NeedsManualReview        = [bool]$needsManualReview
        Classified               = [bool]$classified
        EvidenceSummary          = @($evidence)
        ComplianceNotes          = @($complianceNotes)
        MissingArtifacts         = @($missingArtifacts)
        RawLicenseInfo           = (Get-AppGetterNormalizedLicenseText -Text $LicenseInfo)
        RedactedLicenseInfo      = (Get-AppGetterRedactedLicenseInfo -LicenseInfo $LicenseInfo -Secrets @($resolvedKey))
        LicenseKey               = $resolvedKey
        LicenseKeyMasked         = (Protect-AppGetterLicenseKey -LicenseKey $resolvedKey)
        HasLicenseKey            = [bool]$resolvedKey
        LicenseKeyPropertyName   = $keyPropertyName
        LicenseServer            = $resolvedServer
        LicenseServerVariable    = $resolvedVariable
        LicenseFileSourcePath    = $LicenseFilePath
        LicenseFileName          = $resolvedFileName
        LicenseFileTargetPath    = $resolvedFileTarget
        LicenseQuantity          = $textDetails.LicenseQuantity
        LicenseExpiry            = $textDetails.LicenseExpiry
        RequiresApproval         = [bool]$textDetails.RequiresApproval
        AppliedToInstallCommand  = $false
        PackagedLicenseFile      = $null
    }
}

function Add-AppGetterLicenseInstallArgument {
    <#
    .SYNOPSIS
        Applies a license key to an install command when the installer accepts one.
    .DESCRIPTION
        Only msiexec command lines and WiX Burn bootstrappers reliably accept public
        MSI properties on the command line, so the key is appended for those and left
        alone everywhere else. The returned object records what happened either way.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$InstallCommand,
        [string]$InstallerFamily,
        [string]$PropertyName,
        [string]$LicenseKey
    )

    $result = [PSCustomObject]@{
        InstallCommand = $InstallCommand
        Applied        = $false
        Reason         = $null
    }

    if ([string]::IsNullOrWhiteSpace($LicenseKey)) {
        $result.Reason = 'No license key was supplied.'
        return $result
    }

    if ([string]::IsNullOrWhiteSpace($PropertyName)) {
        $result.Reason = 'No key-bearing installer property was detected, so the key was not injected into the install command.'
        return $result
    }

    $family = if ($InstallerFamily) { $InstallerFamily.ToLowerInvariant() } else { '' }
    $isMsiExec = $InstallCommand -match '(?i)^\s*msiexec\b'
    $isBurn = $family -match 'wixburn'

    if (-not $isMsiExec -and -not $isBurn) {
        $result.Reason = "Installer family '$InstallerFamily' does not accept MSI properties on the command line, so the key was documented for a post-install step instead."
        return $result
    }

    if ($InstallCommand -match "(?i)(?<![A-Za-z0-9_])$([regex]::Escape($PropertyName))\s*=") {
        $result.Reason = "The install command already sets $PropertyName."
        return $result
    }

    $result.InstallCommand = "$InstallCommand $PropertyName=`"$LicenseKey`""
    $result.Applied = $true
    $result.Reason = "License key applied through the $PropertyName property."
    return $result
}

function ConvertTo-AppGetterScriptLiteral {
    <#
    .SYNOPSIS
        Escapes a value for embedding in a single-quoted PowerShell string literal.
    #>
    param([string]$Value)

    if ($null -eq $Value) {
        return ''
    }

    return ($Value -replace "'", "''")
}

function New-AppGetterLicenseInstallStage {
    <#
    .SYNOPSIS
        Builds the licensing stage embedded into a package's install.ps1.
    .DESCRIPTION
        Emits the pre-install steps the resolved licensing pattern needs: staging a
        license file, pointing the client at a license server, or logging that the
        pattern activates elsewhere. Returns an empty string when there is nothing to do.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Licensing
    )

    if (-not $Licensing -or -not $Licensing.Classified) {
        return ''
    }

    $lines = [System.Collections.Generic.List[string]]::new()
    $patternLiteral = ConvertTo-AppGetterScriptLiteral -Value "$($Licensing.PatternName) (activation: $($Licensing.ActivationMethod))"
    $lines.Add("    Write-Host 'Licensing pattern: $patternLiteral'") | Out-Null

    # Artifacts are staged whenever they were supplied, not only when they match the
    # primary activation method: a floating-license app often needs both a local
    # license file and a server pointer.
    if ($Licensing.PackagedLicenseFile) {
        $target = if ($Licensing.LicenseFileTargetPath) {
            $Licensing.LicenseFileTargetPath
        } else {
            "%ProgramData%\AppGetter\Licenses\$($Licensing.LicenseFileName)"
        }
        $sourceLiteral = ConvertTo-AppGetterScriptLiteral -Value $Licensing.PackagedLicenseFile
        $targetLiteral = ConvertTo-AppGetterScriptLiteral -Value $target
        $lines.Add("    `$licenseSource = Join-Path `$scriptRoot '$sourceLiteral'") | Out-Null
        # ExpandEnvironmentVariables covers %VAR% targets and leaves plain paths untouched.
        $lines.Add("    `$licenseTarget = [Environment]::ExpandEnvironmentVariables('$targetLiteral')") | Out-Null
        $lines.Add('    if (Test-Path -LiteralPath $licenseSource) {') | Out-Null
        $lines.Add('        $licenseTargetDir = Split-Path -Parent $licenseTarget') | Out-Null
        $lines.Add('        if ($licenseTargetDir -and -not (Test-Path -LiteralPath $licenseTargetDir)) {') | Out-Null
        $lines.Add('            New-Item -ItemType Directory -Path $licenseTargetDir -Force | Out-Null') | Out-Null
        $lines.Add('        }') | Out-Null
        $lines.Add('        Copy-Item -LiteralPath $licenseSource -Destination $licenseTarget -Force') | Out-Null
        $lines.Add('        Write-Host "Staged license file to $licenseTarget"') | Out-Null
        $lines.Add('    } else {') | Out-Null
        $lines.Add("        Write-Host 'WARNING: license file was not found in the package; the app will install unlicensed.'") | Out-Null
        $lines.Add('    }') | Out-Null
    } elseif ($Licensing.ActivationMethod -eq 'licensefile') {
        $lines.Add("    Write-Host 'WARNING: this app is licensed by license file, but no license file was included in the package.'") | Out-Null
    }

    if ($Licensing.LicenseServer -and $Licensing.LicenseServerVariable) {
        $serverLiteral = ConvertTo-AppGetterScriptLiteral -Value $Licensing.LicenseServer
        $variableLiteral = ConvertTo-AppGetterScriptLiteral -Value $Licensing.LicenseServerVariable
        $lines.Add("    `$licenseServer = '$serverLiteral'") | Out-Null
        $lines.Add("    `$licenseVariable = '$variableLiteral'") | Out-Null
        $lines.Add('    [Environment]::SetEnvironmentVariable($licenseVariable, $licenseServer, "Machine")') | Out-Null
        $lines.Add('    Set-Item -Path "env:$licenseVariable" -Value $licenseServer') | Out-Null
        $lines.Add('    Write-Host "Pointed $licenseVariable at $licenseServer for the machine and this install session"') | Out-Null
    } elseif ($Licensing.ActivationMethod -eq 'licenseserver') {
        $lines.Add("    Write-Host 'WARNING: this app checks out a served license, but no license server was supplied.'") | Out-Null
    }

    switch ($Licensing.ActivationMethod) {
        'licensefile' { }
        'licenseserver' { }
        'key' {
            if ($Licensing.AppliedToInstallCommand) {
                $lines.Add("    Write-Host 'License key is applied through the $($Licensing.LicenseKeyPropertyName) installer property (value redacted).'") | Out-Null
            } elseif ($Licensing.HasLicenseKey) {
                $lines.Add("    Write-Host 'A license key is on file for this app but the installer does not accept it on the command line; activate after install.'") | Out-Null
            } else {
                $lines.Add("    Write-Host 'This app needs a license key that was not supplied; it will install unlicensed.'") | Out-Null
            }
        }
        'signin' {
            $lines.Add("    Write-Host 'Entitlement is per user; the product activates when the assigned user signs in after install.'") | Out-Null
        }
        'dongle' {
            $lines.Add("    Write-Host 'Licensing is bound to a hardware key; confirm the dongle driver is present and the key is attached.'") | Out-Null
        }
        'volume' {
            $lines.Add("    Write-Host 'Licensing uses Microsoft volume activation; KMS/ADBA or a MAK activates the product after install.'") | Out-Null
        }
        'trial' {
            $lines.Add("    Write-Host 'This is a trial/evaluation build and will expire.'") | Out-Null
        }
        'none' {
            $lines.Add("    Write-Host 'No activation step is required for this licensing pattern.'") | Out-Null
        }
        default {
            $lines.Add("    Write-Host 'Licensing pattern could not be classified; review the ServiceNow record before broad deployment.'") | Out-Null
        }
    }

    return ($lines -join "`n")
}

function Copy-AppGetterLicenseArtifact {
    <#
    .SYNOPSIS
        Copies a license file into the package so it ships inside the .intunewin.
    .DESCRIPTION
        Returns the package-relative path of the staged file, which install.ps1 uses
        to place the license on the target device.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$LicenseFilePath,
        [Parameter(Mandatory = $true)]
        [string]$VersionDirectory
    )

    if (-not (Test-Path -LiteralPath $LicenseFilePath -PathType Leaf)) {
        throw "License file not found: $LicenseFilePath"
    }

    $licenseDirectory = Join-Path $VersionDirectory 'license'
    if (-not (Test-Path -LiteralPath $licenseDirectory)) {
        New-Item -ItemType Directory -Path $licenseDirectory -Force | Out-Null
    }

    $fileName = Split-Path -Leaf $LicenseFilePath
    $destination = Join-Path $licenseDirectory $fileName
    Copy-Item -LiteralPath $LicenseFilePath -Destination $destination -Force

    # install.ps1 always runs on Windows, so emit a Windows-relative path regardless of packaging host.
    return "license\$fileName"
}

function Get-AppGetterSanitizedLicensing {
    <#
    .SYNOPSIS
        Returns a copy of a licensing resolution with the plaintext license key removed.
    .DESCRIPTION
        Packaging returns this copy to callers so a key never travels into GUI logs or
        console transcripts once it has been applied to the package.
    #>
    param([pscustomobject]$Licensing)

    if (-not $Licensing) {
        return $null
    }

    $copy = [ordered]@{}
    foreach ($property in $Licensing.PSObject.Properties) {
        $copy[$property.Name] = $property.Value
    }
    $copy['LicenseKey'] = $null

    return [PSCustomObject]$copy
}

function Get-AppGetterLicensingSummary {
    <#
    .SYNOPSIS
        Renders a one-line summary of a licensing resolution for logs and the UI.
    #>
    param([pscustomobject]$Licensing)

    if (-not $Licensing) {
        return 'Licensing: not evaluated'
    }

    if (-not $Licensing.Classified) {
        return 'Licensing: no licensing field supplied'
    }

    $parts = [System.Collections.Generic.List[string]]::new()
    $parts.Add("$($Licensing.PatternName)") | Out-Null
    $parts.Add("activation=$($Licensing.ActivationMethod)") | Out-Null
    $parts.Add("confidence=$($Licensing.ConfidenceScore)/100") | Out-Null
    $parts.Add("assignment=$($Licensing.AssignmentRecommendation)") | Out-Null
    if ($Licensing.NeedsManualReview) {
        $parts.Add('manual review recommended') | Out-Null
    }

    return "Licensing: $($parts -join ', ')"
}

function Get-AppGetterPackageLicensingInfo {
    <#
    .SYNOPSIS
        Reads the licensing decision back out of a generated package folder.
    .DESCRIPTION
        Prefers licensing.json and falls back to the licensing block in app.json, so a
        package that was shared without the manifest still reports its licensing model.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$VersionDirectory
    )

    $manifestPath = Join-Path $VersionDirectory 'licensing.json'
    if (Test-Path -LiteralPath $manifestPath) {
        try {
            return (Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json)
        } catch {
            Write-Verbose "Could not read licensing.json: $_"
        }
    }

    $appJsonPath = Join-Path $VersionDirectory 'app.json'
    if (Test-Path -LiteralPath $appJsonPath) {
        try {
            $app = Get-Content -LiteralPath $appJsonPath -Raw | ConvertFrom-Json
            if ($app.licensing) {
                return $app.licensing
            }
        } catch {
            Write-Verbose "Could not read app.json: $_"
        }
    }

    return $null
}
