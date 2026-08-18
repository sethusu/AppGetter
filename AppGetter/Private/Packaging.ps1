function Invoke-AppGetterPackaging {
    <#
    .SYNOPSIS
        Creates an Intune Win32 package from a download URL or a local installer file.
    .PARAMETER InstallerPath
        Path to an installer that already exists on this computer. Takes precedence over
        DownloadUrl and WebsiteUrl.
    .PARAMETER DownloadUrl
        Direct download URL for the installer.
    .PARAMETER WebsiteUrl
        Page to scan for download links when no direct URL is supplied.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$AppName,
        [string]$WebsiteUrl,
        [string]$DownloadUrl,
        [string]$InstallerPath,
        [string]$DeveloperUrl,
        [string]$SupportUrl,
        [string]$Version,
        [string]$Publisher,
        [string]$OutputPath = (Get-AppGetterSettings).OutputPath,
        [string]$IconPath,
        [string]$InstallCommand,
        [switch]$CollectIconCandidates,
        [scriptblock]$OnProgress
    )

    $totalSteps = 13
    $versionDirectory = $null
    $failureLogPath = $null
    $intunewinFile = $null

    try {
        Write-AppGetterProgress -Step 1 -TotalSteps $totalSteps -StepName 'Loading package details' -Percent 5 `
            -Message "Preparing $AppName" -OnProgress $OnProgress

        $details = Get-WebPackageDetails -AppName $AppName -WebsiteUrl $WebsiteUrl -DownloadUrl $DownloadUrl `
            -InstallerPath $InstallerPath -DeveloperUrl $DeveloperUrl -SupportUrl $SupportUrl `
            -Version $Version -Publisher $Publisher

        Write-AppGetterProgress -Step 2 -TotalSteps $totalSteps -StepName 'Creating directories' -Percent 10 `
            -Message 'Creating output folders' -OnProgress $OnProgress

        # Always place packages under a folder named after the app (PackageId).
        # If OutputPath already ends with that folder, do not nest a second copy.
        $appDirectory = Get-AppGetterAppOutputPath -BasePath $OutputPath -PackageId $details.PackageId
        $baseOutputPath = Get-AppGetterBaseOutputPath -Path $appDirectory -PackageId $details.PackageId
        if (-not (Test-Path $baseOutputPath)) {
            New-Item -ItemType Directory -Path $baseOutputPath -Force | Out-Null
        }
        $versionDirectory = Join-Path $appDirectory $details.Version
        $failureLogPath = Join-Path $versionDirectory 'appgetter-packaging.log'
        if (-not (Test-Path $versionDirectory)) {
            New-Item -ItemType Directory -Path $versionDirectory -Force | Out-Null
        }

        Write-AppGetterProgress -Step 3 -TotalSteps $totalSteps -StepName 'Resolving installer source' -Percent 15 `
            -Message 'Determining where the installer comes from' -OnProgress $OnProgress

        $source = Resolve-AppGetterInstallerSource -DownloadUrl $DownloadUrl -WebsiteUrl $WebsiteUrl `
            -InstallerPath $InstallerPath -AppName $AppName -OnProgress $OnProgress
        $details | Add-Member -NotePropertyName SourceType -NotePropertyValue $source.SourceType -Force
        $details | Add-Member -NotePropertyName SourceLocation -NotePropertyValue $source.Location -Force
        $finalDownloadUrl = if ($source.SourceType -eq 'LocalFile') { $null } else { $source.Location }
        $details | Add-Member -NotePropertyName FinalDownloadUrl -NotePropertyValue $finalDownloadUrl -Force

        if ($source.SourceType -eq 'LocalFile') {
            Write-AppGetterProgress -Step 4 -TotalSteps $totalSteps -StepName 'Staging local installer' -Percent 25 `
                -Message $source.FileName -OnProgress $OnProgress
            $stagedInstallerPath = Copy-AppGetterLocalInstaller -InstallerPath $source.Location `
                -DestinationDirectory $versionDirectory -OnProgress $OnProgress
        } else {
            Write-AppGetterProgress -Step 4 -TotalSteps $totalSteps -StepName 'Downloading installer' -Percent 25 `
                -Message $source.FileName -OnProgress $OnProgress
            $stagedInstallerPath = Join-Path $versionDirectory $source.FileName
            $null = Start-WebInstallerDownload -Url $source.Location -OutputPath $stagedInstallerPath `
                -FileName $source.FileName -OnProgress $OnProgress
        }

        $installerFile = Get-Item -LiteralPath $stagedInstallerPath
        $installerExtension = $installerFile.Extension.ToLower()

        if ($installerExtension -in '.zip', '.7z') {
            throw 'Archive files require manual extraction. Provide InstallCommand after extracting the installer.'
        }

        Write-AppGetterProgress -Step 5 -TotalSteps $totalSteps -StepName 'Calculating hash' -Percent 32 `
            -Message $installerFile.Name -OnProgress $OnProgress

        $installerHash = (Get-FileHash -Path $installerFile.FullName -Algorithm SHA256).Hash

        Write-AppGetterProgress -Step 6 -TotalSteps $totalSteps -StepName 'Discovering silent install switches' -Percent 40 `
            -Message $installerFile.Name -OnProgress $OnProgress

        $switchDiscoveryResult = $null
        if ([string]::IsNullOrWhiteSpace($InstallCommand)) {
            $switchDiscoveryResult = Resolve-InstallerInstallCommand -InstallerPath $installerFile.FullName `
                -InstallerFileName $installerFile.Name -AppName $AppName `
                -InstallSwitchesInfo $details.InstallSwitchesInfo -SupportUrl $SupportUrl

            $installerInstallCommand = $switchDiscoveryResult.RecommendedCommand

            $reviewNote = if ($switchDiscoveryResult.NeedsManualReview) { ' (manual review recommended)' } else { '' }
            $verifiedNote = if ($switchDiscoveryResult.Verified) { 'verified' } else { 'unverified' }
            Write-AppGetterLog -Message "Silent install discovery: family=$($switchDiscoveryResult.InstallerFamily), confidence=$($switchDiscoveryResult.ConfidenceScore), $verifiedNote$reviewNote" `
                -Level $(if ($switchDiscoveryResult.NeedsManualReview) { 'Warning' } else { 'Success' }) -OnProgress $OnProgress
            Write-AppGetterLog -Message "Selected install command: $installerInstallCommand" -OnProgress $OnProgress
        } else {
            $installerInstallCommand = $InstallCommand
            Write-AppGetterLog -Message 'Using user-provided install command; silent switch discovery skipped.' -OnProgress $OnProgress
        }

        Write-AppGetterProgress -Step 7 -TotalSteps $totalSteps -StepName 'Generating install.ps1' -Percent 48 -OnProgress $OnProgress
        $installScript = New-AppGetterInstallScript -PackageId $details.PackageId -DisplayName $details.DisplayName `
            -Version $details.Version -InstallCommand $installerInstallCommand

        Write-AppGetterProgress -Step 8 -TotalSteps $totalSteps -StepName 'Generating detection.ps1' -Percent 58 -OnProgress $OnProgress
        $detectionScript = New-AppGetterDetectionScript -PackageId $details.PackageId -DisplayName $details.DisplayName `
            -Version $details.Version

        Write-AppGetterProgress -Step 9 -TotalSteps $totalSteps -StepName 'Generating uninstall.ps1' -Percent 68 -OnProgress $OnProgress
        $uninstallScript = New-AppGetterUninstallScript -PackageId $details.PackageId -DisplayName $details.DisplayName

        Write-AppGetterProgress -Step 10 -TotalSteps $totalSteps -StepName 'Resolving icon' -Percent 75 -OnProgress $OnProgress
        $iconFilePath = Join-Path $versionDirectory 'icon.png'
        $logoFilePath = Join-Path $appDirectory 'logo.png'
        $iconStagingDirectory = Join-Path $versionDirectory '.icon-candidates'
        $iconCandidates = @()
        $usedCustomIcon = $false

        if ($IconPath -and (Test-Path $IconPath)) {
            Set-AppGetterPackageIconFiles -SourceIconPath $IconPath -LogoFilePath $logoFilePath -IconFilePath $iconFilePath
            $usedCustomIcon = $true
        } elseif (Test-Path $logoFilePath) {
            Copy-Item -Path $logoFilePath -Destination $iconFilePath -Force
        } elseif ($CollectIconCandidates) {
            $iconCandidates = @(Resolve-AppGetterIconCandidates -WebsiteUrl $WebsiteUrl -DeveloperUrl $DeveloperUrl `
                    -AppName $AppName -InstallerPath $installerFile.FullName -MaximumCount 3 `
                    -StagingDirectory $iconStagingDirectory -OnProgress $OnProgress)
            if ($iconCandidates.Count -gt 0) {
                Set-AppGetterPackageIconFiles -SourceIconPath $iconCandidates[0].Path -LogoFilePath $logoFilePath -IconFilePath $iconFilePath
            }
        } else {
            $null = Resolve-PackageIcon -WebsiteUrl $WebsiteUrl -DeveloperUrl $DeveloperUrl -AppName $AppName `
                -LogoFilePath $logoFilePath -IconFilePath $iconFilePath -IconPath $IconPath `
                -InstallerPath $installerFile.FullName -OnProgress $OnProgress
        }

        Write-AppGetterProgress -Step 11 -TotalSteps $totalSteps -StepName 'Writing metadata' -Percent 83 -OnProgress $OnProgress
        $metadata = New-AppGetterMetadataFiles -PackageDetails $details -VersionDirectory $versionDirectory `
            -InstallerFileName $installerFile.Name -InstallerHash $installerHash `
            -InstallerInstallCommand $installerInstallCommand -DetectionScript $detectionScript `
            -InstallScript $installScript -UninstallScript $uninstallScript -IconFilePath $iconFilePath `
            -FinalDownloadUrl $finalDownloadUrl -SourceType $source.SourceType -SourceLocation $source.Location `
            -SwitchDiscoveryResult $switchDiscoveryResult

        Write-AppGetterProgress -Step 12 -TotalSteps $totalSteps -StepName 'Packaging .intunewin' -Percent 90 -OnProgress $OnProgress
        $contentPrepPath = Resolve-AppGetterContentPrepToolPath
        $packagingSucceeded = $false

        if (-not $contentPrepPath) {
            Write-AppGetterLog -Message 'intunewinapputil not found. Use Install-AppGetterContentPrepTool or install Microsoft Win32 Content Prep Tool and ensure it is on PATH.' `
                -Level Warning -OnProgress $OnProgress
            Write-AppGetterProgress -Step 13 -TotalSteps $totalSteps -StepName 'Complete with warnings' -Percent 100 `
                -Message 'Metadata created, but Content Prep Tool is unavailable.' -Status Completed -OnProgress $OnProgress
        } else {
            $outputDirectory = Split-Path $versionDirectory -Parent
            $intunewinFile = Join-Path $outputDirectory $metadata.IntuneWinFileName
            if (Test-Path $intunewinFile) {
                Remove-Item -Path $intunewinFile -Force
            }

            try {
                & $contentPrepPath -c $versionDirectory -s $installerFile.Name -o $outputDirectory -q
                if ($LASTEXITCODE -eq 0 -and (Test-Path $intunewinFile)) {
                    $packagingSucceeded = $true
                    $intunewinSize = [math]::Round((Get-Item $intunewinFile).Length / 1MB, 2)
                    Write-AppGetterProgress -Step 13 -TotalSteps $totalSteps -StepName 'Complete' -Percent 100 `
                        -Message "Created $intunewinFile ($intunewinSize MB)" -Status Completed -OnProgress $OnProgress
                } else {
                    throw 'Content Prep Tool failed or output file was not created.'
                }
            } catch {
                Write-AppGetterLog -Message "Failed to create IntuneWin package: $_" -Level Warning -OnProgress $OnProgress
                Write-AppGetterFailureLog -LogPath $failureLogPath -Step 'Packaging .intunewin' -ErrorRecord $_
                Write-AppGetterProgress -Step 13 -TotalSteps $totalSteps -StepName 'Complete with warnings' -Percent 100 `
                    -Message 'Metadata created, but .intunewin packaging failed.' -Status Completed -OnProgress $OnProgress
            }
        }

        $sourceMode = switch ($source.SourceType) {
            'LocalFile' { 'LocalFile' }
            'DownloadUrl' { 'DownloadUrl' }
            default { 'Website' }
        }
        Save-AppGetterSettings -OutputPath $baseOutputPath -LastAppName $AppName -LastPackageId $details.PackageId `
            -LastPublisher $Publisher -LastSourceMode $sourceMode -LastWebsiteUrl $WebsiteUrl `
            -LastDownloadUrl $DownloadUrl -LastInstallerPath $InstallerPath

        return [PSCustomObject]@{
            Success              = $true
            PackagingSucceeded   = $packagingSucceeded
            PackageId            = $details.PackageId
            DisplayName          = $details.DisplayName
            Version              = $details.Version
            Publisher            = $details.Publisher
            AppDirectory         = $appDirectory
            VersionDirectory     = $versionDirectory
            IntuneWinFile        = if ($packagingSucceeded) { $intunewinFile } else { $null }
            IconFile             = if (Test-Path $iconFilePath) { $iconFilePath } else { $null }
            LogoFile             = if (Test-Path $logoFilePath) { $logoFilePath } else { $null }
            IconCandidates       = $iconCandidates
            UsedCustomIcon       = $usedCustomIcon
            IconStagingDirectory = if ($iconCandidates.Count -gt 0) { $iconStagingDirectory } else { $null }
            InstallerFile        = $installerFile.FullName
            SourceType           = $source.SourceType
            SourceLocation       = $source.Location
            FinalDownloadUrl     = $finalDownloadUrl
            Metadata             = $metadata
            Details              = $details
        }
    }
    catch {
        if ($versionDirectory -and -not $failureLogPath) {
            $failureLogPath = Join-Path $versionDirectory 'appgetter-packaging.log'
        }
        if ($failureLogPath) {
            if (-not (Test-Path (Split-Path $failureLogPath -Parent))) {
                New-Item -ItemType Directory -Path (Split-Path $failureLogPath -Parent) -Force | Out-Null
            }
            $failedStep = if ($_.TargetObject) { $_.TargetObject } else { 'Packaging' }
            Write-AppGetterFailureLog -LogPath $failureLogPath -Step $failedStep -ErrorRecord $_
        }

        Write-AppGetterProgress -Step 0 -TotalSteps $totalSteps -StepName 'Failed' -Percent 0 `
            -Message $_.Exception.Message -Status Failed -OnProgress $OnProgress
        throw
    }
}
