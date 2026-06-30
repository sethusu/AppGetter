function Invoke-AppGetterPackaging {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$AppName,
        [string]$WebsiteUrl,
        [string]$DownloadUrl,
        [string]$Version,
        [string]$Publisher,
        [string]$DeveloperUrl,
        [string]$SupportUrl,
        [string]$OutputPath = (Get-AppGetterSettings).OutputPath,
        [string]$IconPath,
        [string]$InstallCommand,
        [switch]$CollectIconCandidates,
        [scriptblock]$OnProgress
    )

    if ([string]::IsNullOrWhiteSpace($WebsiteUrl) -and [string]::IsNullOrWhiteSpace($DownloadUrl)) {
        throw 'Either WebsiteUrl or DownloadUrl must be provided.'
    }

    $totalSteps = 12
    $versionDirectory = $null
    $failureLogPath = $null
    $intunewinFile = $null

    try {
        Write-AppGetterProgress -Step 1 -TotalSteps $totalSteps -StepName 'Loading package details' -Percent 5 -Message "Resolving details for $AppName" -OnProgress $OnProgress
        $details = Get-WebPackageDetails -AppName $AppName -WebsiteUrl $WebsiteUrl -DownloadUrl $DownloadUrl `
            -Version $Version -Publisher $Publisher -DeveloperUrl $DeveloperUrl -SupportUrl $SupportUrl -OnProgress $OnProgress

        if (-not (Test-Path $OutputPath)) {
            New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null
        }

        Write-AppGetterProgress -Step 2 -TotalSteps $totalSteps -StepName 'Creating directories' -Percent 10 -Message 'Creating output folders' -OnProgress $OnProgress
        $appDirectory = Join-Path $OutputPath $details.PackageId
        $versionDirectory = Join-Path $appDirectory $details.Version
        $failureLogPath = Join-Path $versionDirectory 'appgetter-packaging.log'
        if (-not (Test-Path $versionDirectory)) {
            New-Item -ItemType Directory -Path $versionDirectory -Force | Out-Null
        }

        $installerFileName = Get-InstallerFileNameFromUrl -Url $details.DownloadUrl
        $installerPath = Join-Path $versionDirectory $installerFileName

        Write-AppGetterProgress -Step 3 -TotalSteps $totalSteps -StepName 'Downloading installer' -Percent 15 -Message $details.DownloadUrl -OnProgress $OnProgress
        Start-WebInstallerDownload -DownloadUrl $details.DownloadUrl -OutputPath $installerPath -FileName $installerFileName -OnProgress $OnProgress

        $installerFile = Get-Item $installerPath
        if ($installerFile.Extension -in '.zip', '.7z') {
            throw 'Archive installers require manual extraction. Provide an extracted installer or custom InstallCommand.'
        }

        if ([string]::IsNullOrWhiteSpace($InstallCommand)) {
            $installerInstallCommand = Get-InstallerInstallCommand -InstallerFileName $installerFile.Name `
                -InstallerExtension $installerFile.Extension -DetectedSwitch $details.DetectedInstallSwitch
        } else {
            $installerInstallCommand = $InstallCommand
        }

        Write-AppGetterProgress -Step 5 -TotalSteps $totalSteps -StepName 'Calculating hash' -Percent 35 -Message $installerFile.Name -OnProgress $OnProgress
        $installerHash = (Get-FileHash -Path $installerFile.FullName -Algorithm SHA256).Hash

        Write-AppGetterProgress -Step 6 -TotalSteps $totalSteps -StepName 'Generating install.ps1' -Percent 45 -OnProgress $OnProgress
        $installScript = New-AppGetterInstallScript -PackageId $details.PackageId -DisplayName $details.DisplayName `
            -Version $details.Version -InstallCommand $installerInstallCommand

        Write-AppGetterProgress -Step 7 -TotalSteps $totalSteps -StepName 'Generating detection.ps1' -Percent 55 -OnProgress $OnProgress
        $detectionScript = New-AppGetterDetectionScript -PackageId $details.PackageId -DisplayName $details.DisplayName -Version $details.Version

        Write-AppGetterProgress -Step 8 -TotalSteps $totalSteps -StepName 'Generating uninstall.ps1' -Percent 65 -OnProgress $OnProgress
        $uninstallScript = New-AppGetterUninstallScript -PackageId $details.PackageId -DisplayName $details.DisplayName

        Write-AppGetterProgress -Step 9 -TotalSteps $totalSteps -StepName 'Resolving icon' -Percent 72 -OnProgress $OnProgress
        $iconFilePath = Join-Path $versionDirectory 'icon.png'
        $logoFilePath = Join-Path $appDirectory 'logo.png'
        $iconCandidates = @()
        $iconStagingDirectory = Join-Path $versionDirectory '.icon-candidates'
        $usedCustomIcon = $false

        if ($IconPath -and (Test-Path $IconPath)) {
            Set-AppGetterPackageIconFiles -SourceIconPath $IconPath -LogoFilePath $logoFilePath -IconFilePath $iconFilePath
            $usedCustomIcon = $true
        } elseif (Test-Path $logoFilePath) {
            Copy-Item -Path $logoFilePath -Destination $iconFilePath -Force
        } elseif ($CollectIconCandidates) {
            $iconCandidates = @(Resolve-PackageIconCandidates -AppName $details.DisplayName `
                -WebsiteUrl $details.WebsiteUrl -DeveloperUrl $details.DeveloperUrl `
                -InstallerPath $installerFile.FullName -MaximumCount 3 -StagingDirectory $iconStagingDirectory -OnProgress $OnProgress)
            if ($iconCandidates.Count -gt 0) {
                Set-AppGetterPackageIconFiles -SourceIconPath $iconCandidates[0].Path -LogoFilePath $logoFilePath -IconFilePath $iconFilePath
            }
        } else {
            $logoDownloaded = Get-PackageLogoFromWeb -AppName $details.DisplayName -WebsiteUrl $details.WebsiteUrl `
                -DeveloperUrl $details.DeveloperUrl -OutputPath $logoFilePath -InstallerPath $installerFile.FullName -OnProgress $OnProgress
            if ($logoDownloaded -and (Test-Path $logoFilePath)) {
                Copy-Item -Path $logoFilePath -Destination $iconFilePath -Force
            }
        }

        Write-AppGetterProgress -Step 10 -TotalSteps $totalSteps -StepName 'Writing metadata' -Percent 80 -OnProgress $OnProgress
        $metadata = New-AppGetterMetadataFiles -PackageDetails $details -VersionDirectory $versionDirectory `
            -InstallerFileName $installerFile.Name -InstallerHash $installerHash `
            -InstallerInstallCommand $installerInstallCommand -DetectionScript $detectionScript `
            -InstallScript $installScript -UninstallScript $uninstallScript -IconFilePath $iconFilePath

        Write-AppGetterProgress -Step 11 -TotalSteps $totalSteps -StepName 'Packaging .intunewin' -Percent 88 -OnProgress $OnProgress
        $intunewinCmd = Get-Command intunewinapputil -ErrorAction SilentlyContinue
        $packagingSucceeded = $false
        if (-not $intunewinCmd) {
            Write-AppGetterLog -Message 'intunewinapputil not found. Install Microsoft Win32 Content Prep Tool and ensure it is on PATH.' -Level Warning -OnProgress $OnProgress
            Write-AppGetterProgress -Step 12 -TotalSteps $totalSteps -StepName 'Complete with warnings' -Percent 100 -Message 'Metadata created, but Content Prep Tool is unavailable.' -Status Completed -OnProgress $OnProgress
        } else {
            $outputDirectory = Split-Path $versionDirectory -Parent
            $intunewinFile = Join-Path $outputDirectory $metadata.IntuneWinFileName
            if (Test-Path $intunewinFile) {
                Remove-Item -Path $intunewinFile -Force
            }

            try {
                & intunewinapputil -c $versionDirectory -s $installerFile.Name -o $outputDirectory -q
                if ($LASTEXITCODE -eq 0 -and (Test-Path $intunewinFile)) {
                    $packagingSucceeded = $true
                    $intunewinSize = [math]::Round((Get-Item $intunewinFile).Length / 1MB, 2)
                    Write-AppGetterProgress -Step 12 -TotalSteps $totalSteps -StepName 'Complete' -Percent 100 -Message "Created $intunewinFile ($intunewinSize MB)" -Status Completed -OnProgress $OnProgress
                } else {
                    throw 'Content Prep Tool failed or output file was not created.'
                }
            } catch {
                Write-AppGetterLog -Message "Failed to create IntuneWin package: $_" -Level Warning -OnProgress $OnProgress
                Write-AppGetterFailureLog -LogPath $failureLogPath -Step 'Packaging .intunewin' -ErrorRecord $_
                Write-AppGetterProgress -Step 12 -TotalSteps $totalSteps -StepName 'Complete with warnings' -Percent 100 -Message 'Metadata created, but .intunewin packaging failed.' -Status Completed -OnProgress $OnProgress
            }
        }

        Save-AppGetterSettings -OutputPath $OutputPath -LastAppName $AppName `
            -LastWebsiteUrl $WebsiteUrl -LastDownloadUrl $details.DownloadUrl

        return [PSCustomObject]@{
            Success              = $true
            PackagingSucceeded   = $packagingSucceeded
            PackageId            = $details.PackageId
            DisplayName          = $details.DisplayName
            Version              = $details.Version
            Publisher            = $details.Publisher
            VersionDirectory     = $versionDirectory
            IntuneWinFile        = if ($packagingSucceeded) { $intunewinFile } else { $null }
            IconFile             = if (Test-Path $iconFilePath) { $iconFilePath } else { $null }
            LogoFile             = if (Test-Path $logoFilePath) { $logoFilePath } else { $null }
            IconCandidates       = $iconCandidates
            UsedCustomIcon       = $usedCustomIcon
            IconStagingDirectory = if ($iconCandidates.Count -gt 0) { $iconStagingDirectory } else { $null }
            InstallerFile        = $installerFile.FullName
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

        Write-AppGetterProgress -Step 0 -TotalSteps $totalSteps -StepName 'Failed' -Percent 0 -Message $_.Exception.Message -Status Failed -OnProgress $OnProgress
        throw
    }
}
