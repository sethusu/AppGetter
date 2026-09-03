function Invoke-AppGetterPackaging {
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
        [string]$LicenseType,
        [string]$LicenseName,
        [string]$LicenseUrl,
        [string]$LicenseNotes,
        [string]$OutputPath = (Get-AppGetterSettings).OutputPath,
        [string]$IconPath,
        [string]$InstallCommand,
        [switch]$VerifySilentSwitches,
        [int]$MaxCandidatesToVerify = 3,
        [scriptblock]$OnProgress
    )

    $totalSteps = 14
    $versionDirectory = $null
    $failureLogPath = $null
    $intunewinFile = $null

    try {
        Write-AppGetterProgress -Step 1 -TotalSteps $totalSteps -StepName 'Loading package details' -Percent 5 `
            -Message "Preparing $AppName" -OnProgress $OnProgress

        $details = Get-WebPackageDetails -AppName $AppName -WebsiteUrl $WebsiteUrl -DownloadUrl $DownloadUrl `
            -DeveloperUrl $DeveloperUrl -SupportUrl $SupportUrl -Version $Version -Publisher $Publisher

        if (-not [string]::IsNullOrWhiteSpace($InstallerPath) -and $details.Description -like '*Downloaded from web') {
            $details.Description = $details.Description -replace 'Downloaded from web$', 'Packaged from local installer'
        }

        if (-not (Test-Path $OutputPath)) {
            New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null
        }

        Write-AppGetterProgress -Step 2 -TotalSteps $totalSteps -StepName 'Creating directories' -Percent 10 `
            -Message 'Creating output folders' -OnProgress $OnProgress

        $appDirectory = Join-Path $OutputPath $details.PackageId
        $versionDirectory = Join-Path $appDirectory $details.Version
        $failureLogPath = Join-Path $versionDirectory 'appgetter-packaging.log'
        if (-not (Test-Path $versionDirectory)) {
            New-Item -ItemType Directory -Path $versionDirectory -Force | Out-Null
        }

        if (-not [string]::IsNullOrWhiteSpace($InstallerPath)) {
            Write-AppGetterProgress -Step 3 -TotalSteps $totalSteps -StepName 'Resolving installer source' -Percent 15 `
                -Message 'Using local installer file' -OnProgress $OnProgress

            if (-not (Test-Path -LiteralPath $InstallerPath -PathType Leaf)) {
                throw "Installer file not found: $InstallerPath"
            }

            $sourceInstaller = Get-Item -LiteralPath $InstallerPath
            $finalDownloadUrl = $sourceInstaller.FullName
            $details | Add-Member -NotePropertyName FinalDownloadUrl -NotePropertyValue $finalDownloadUrl -Force
            $installerFileName = $sourceInstaller.Name

            Write-AppGetterProgress -Step 4 -TotalSteps $totalSteps -StepName 'Copying local installer' -Percent 25 `
                -Message $installerFileName -OnProgress $OnProgress

            $installerDestination = Join-Path $versionDirectory $installerFileName
            if ($sourceInstaller.FullName -ne $installerDestination) {
                Copy-Item -LiteralPath $sourceInstaller.FullName -Destination $installerDestination -Force
            }
            $sizeMB = [math]::Round((Get-Item -LiteralPath $installerDestination).Length / 1MB, 2)
            Write-AppGetterLog -Message "Copied local installer: $installerFileName ($sizeMB MB)" -Level Success -OnProgress $OnProgress
        } else {
            Write-AppGetterProgress -Step 3 -TotalSteps $totalSteps -StepName 'Resolving download URL' -Percent 15 `
                -Message 'Finding installer download link' -OnProgress $OnProgress

            $finalDownloadUrl = Resolve-WebDownloadUrl -WebsiteUrl $WebsiteUrl -DownloadUrl $DownloadUrl `
                -AppName $AppName -OnProgress $OnProgress
            $details | Add-Member -NotePropertyName FinalDownloadUrl -NotePropertyValue $finalDownloadUrl -Force

            $installerFileName = Split-Path -Leaf $finalDownloadUrl
            if ($installerFileName -match '([^?]+)') {
                $installerFileName = $matches[1]
            }

            Write-AppGetterProgress -Step 4 -TotalSteps $totalSteps -StepName 'Downloading installer' -Percent 25 `
                -Message $installerFileName -OnProgress $OnProgress

            $installerDestination = Join-Path $versionDirectory $installerFileName
            $null = Start-WebInstallerDownload -Url $finalDownloadUrl -OutputPath $installerDestination `
                -FileName $installerFileName -OnProgress $OnProgress
        }

        $installerFile = Get-Item $installerDestination
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
            if ($VerifySilentSwitches) {
                Write-AppGetterLog -Message 'Silent switch Sandbox verification requested (-VerifySilentSwitches).' -OnProgress $OnProgress
            }

            $resolveParams = @{
                InstallerPath           = $installerFile.FullName
                InstallerFileName       = $installerFileName
                AppName                 = $AppName
                InstallSwitchesInfo     = $details.InstallSwitchesInfo
                SupportUrl              = $SupportUrl
                InstallerHash           = $installerHash
                MaxCandidatesToVerify   = $MaxCandidatesToVerify
            }
            if ($VerifySilentSwitches) {
                $resolveParams.VerifySilentSwitches = $true
            }

            $switchDiscoveryResult = Resolve-InstallerInstallCommand @resolveParams

            $installerInstallCommand = $switchDiscoveryResult.RecommendedCommand

            $reviewNote = if ($switchDiscoveryResult.NeedsManualReview) { ' (manual review recommended)' } else { '' }
            $verifiedNote = if ($switchDiscoveryResult.Verified) { 'verified' } else { 'unverified' }
            $cacheNote = if ($switchDiscoveryResult.UsedCache) { ', cache-hit' } else { '' }
            Write-AppGetterLog -Message "Silent install discovery: family=$($switchDiscoveryResult.InstallerFamily), confidence=$($switchDiscoveryResult.ConfidenceScore), $verifiedNote$cacheNote$reviewNote" `
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
        $hasIcon = Resolve-PackageIcon -WebsiteUrl $WebsiteUrl -DeveloperUrl $DeveloperUrl -AppName $AppName `
            -LogoFilePath $logoFilePath -IconFilePath $iconFilePath -IconPath $IconPath `
            -InstallerPath $installerFile.FullName -OnProgress $OnProgress

        Write-AppGetterProgress -Step 11 -TotalSteps $totalSteps -StepName 'Identifying licensing pattern' -Percent 80 `
            -Message $AppName -OnProgress $OnProgress
        $licenseInfo = Resolve-AppGetterLicenseInfo -AppName $AppName `
            -LicenseType $LicenseType -LicenseName $LicenseName -LicenseUrl $LicenseUrl -LicenseNotes $LicenseNotes `
            -WebsiteUrl $WebsiteUrl -DeveloperUrl $DeveloperUrl -SupportUrl $SupportUrl -OnProgress $OnProgress

        Write-AppGetterProgress -Step 12 -TotalSteps $totalSteps -StepName 'Writing metadata' -Percent 85 -OnProgress $OnProgress
        $metadata = New-AppGetterMetadataFiles -PackageDetails $details -VersionDirectory $versionDirectory `
            -InstallerFileName $installerFile.Name -InstallerHash $installerHash `
            -InstallerInstallCommand $installerInstallCommand -DetectionScript $detectionScript `
            -InstallScript $installScript -UninstallScript $uninstallScript -IconFilePath $iconFilePath `
            -FinalDownloadUrl $finalDownloadUrl -SwitchDiscoveryResult $switchDiscoveryResult `
            -LicenseInfo $licenseInfo

        Write-AppGetterProgress -Step 13 -TotalSteps $totalSteps -StepName 'Packaging .intunewin' -Percent 90 -OnProgress $OnProgress
        $contentPrepPath = Resolve-ContentPrepToolPath
        $packagingSucceeded = $false

        if (-not $contentPrepPath) {
            Write-AppGetterLog -Message 'intunewinapputil not found. Use Install-AppGetterContentPrepTool or install Microsoft Win32 Content Prep Tool and ensure it is on PATH.' `
                -Level Warning -OnProgress $OnProgress
            Write-AppGetterProgress -Step 14 -TotalSteps $totalSteps -StepName 'Complete with warnings' -Percent 100 `
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
                    Write-AppGetterProgress -Step 14 -TotalSteps $totalSteps -StepName 'Complete' -Percent 100 `
                        -Message "Created $intunewinFile ($intunewinSize MB)" -Status Completed -OnProgress $OnProgress
                } else {
                    throw 'Content Prep Tool failed or output file was not created.'
                }
            } catch {
                Write-AppGetterLog -Message "Failed to create IntuneWin package: $_" -Level Warning -OnProgress $OnProgress
                Write-AppGetterFailureLog -LogPath $failureLogPath -Step 'Packaging .intunewin' -ErrorRecord $_
                Write-AppGetterProgress -Step 14 -TotalSteps $totalSteps -StepName 'Complete with warnings' -Percent 100 `
                    -Message 'Metadata created, but .intunewin packaging failed.' -Status Completed -OnProgress $OnProgress
            }
        }

        Save-AppGetterSettings -OutputPath $OutputPath -LastAppName $AppName `
            -LastWebsiteUrl $WebsiteUrl -LastDownloadUrl $DownloadUrl `
            -LastInstallerPath $InstallerPath -PackageId $details.PackageId

        return [PSCustomObject]@{
            Success              = $true
            PackagingSucceeded   = $packagingSucceeded
            PackageId            = $details.PackageId
            DisplayName          = $details.DisplayName
            Version              = $details.Version
            Publisher            = $details.Publisher
            VersionDirectory     = $versionDirectory
            IntuneWinFile        = if ($packagingSucceeded) { $intunewinFile } else { $null }
            IconFile             = if ($hasIcon -and (Test-Path $iconFilePath)) { $iconFilePath } else { $null }
            LogoFile             = if (Test-Path $logoFilePath) { $logoFilePath } else { $null }
            InstallerFile        = $installerFile.FullName
            FinalDownloadUrl     = $finalDownloadUrl
            License              = $licenseInfo
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
