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
        [switch]$AllowRuntimeProbe,
        [scriptblock]$OnProgress
    )

    $totalSteps = 12
    $versionDirectory = $null
    $failureLogPath = $null
    $intunewinFile = $null

    try {
        Write-AppGetterProgress -Step 1 -TotalSteps $totalSteps -StepName 'Resolving download URL' -Percent 5 `
            -Message "Preparing package for $AppName" -OnProgress $OnProgress

        $resolvedDownloadUrl = Resolve-WebDownloadUrl -WebsiteUrl $WebsiteUrl -DownloadUrl $DownloadUrl `
            -AppName $AppName -OnProgress $OnProgress

        $details = Resolve-WebPackageMetadata -AppName $AppName -Version $Version -Publisher $Publisher `
            -WebsiteUrl $WebsiteUrl -DeveloperUrl $DeveloperUrl -SupportUrl $SupportUrl `
            -DownloadUrl $resolvedDownloadUrl

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

        $installerFileName = Get-InstallerFileNameFromUrl -Url $resolvedDownloadUrl
        Write-AppGetterProgress -Step 3 -TotalSteps $totalSteps -StepName 'Downloading installer' -Percent 15 `
            -Message $installerFileName -OnProgress $OnProgress

        $installerPath = Start-WebInstallerDownload -DownloadUrl $resolvedDownloadUrl `
            -DownloadDirectory $versionDirectory -InstallerFileName $installerFileName -OnProgress $OnProgress
        $installerFile = Get-Item $installerPath

        Write-AppGetterProgress -Step 4 -TotalSteps $totalSteps -StepName 'Analyzing install switches' -Percent 30 `
            -Message $installerFile.Name -OnProgress $OnProgress

        $researchUrls = @($SupportUrl, $WebsiteUrl, $DeveloperUrl) | Where-Object { $_ }
        $switchAnalysis = Invoke-InstallerSwitchAnalysis -InstallerPath $installerFile.FullName `
            -AppName $AppName -ResearchUrls $researchUrls -AllowRuntimeProbe:$AllowRuntimeProbe

        if ([string]::IsNullOrWhiteSpace($InstallCommand)) {
            $installerInstallCommand = $switchAnalysis.RecommendedInstallCommand
        } else {
            $installerInstallCommand = $InstallCommand
        }

        Write-AppGetterProgress -Step 5 -TotalSteps $totalSteps -StepName 'Calculating hash' -Percent 40 `
            -Message $installerFile.Name -OnProgress $OnProgress
        $installerHash = (Get-FileHash -Path $installerFile.FullName -Algorithm SHA256).Hash

        Write-AppGetterProgress -Step 6 -TotalSteps $totalSteps -StepName 'Generating install.ps1' -Percent 50 -OnProgress $OnProgress
        $installScript = New-AppGetterInstallScript -PackageId $details.PackageId -DisplayName $details.DisplayName `
            -Version $details.Version -InstallCommand $installerInstallCommand

        Write-AppGetterProgress -Step 7 -TotalSteps $totalSteps -StepName 'Generating detection.ps1' -Percent 60 -OnProgress $OnProgress
        $detectionScript = New-AppGetterDetectionScript -PackageId $details.PackageId -DisplayName $details.DisplayName `
            -Version $details.Version

        Write-AppGetterProgress -Step 8 -TotalSteps $totalSteps -StepName 'Generating uninstall.ps1' -Percent 68 -OnProgress $OnProgress
        $uninstallScript = New-AppGetterUninstallScript -PackageId $details.PackageId -DisplayName $details.DisplayName

        Write-AppGetterProgress -Step 9 -TotalSteps $totalSteps -StepName 'Resolving icon' -Percent 75 -OnProgress $OnProgress
        $iconFilePath = Join-Path $versionDirectory 'icon.png'
        $logoFilePath = Join-Path $appDirectory 'logo.png'
        $null = Resolve-PackageIcon -WebsiteUrl $WebsiteUrl -DeveloperUrl $DeveloperUrl -AppName $AppName `
            -LogoFilePath $logoFilePath -IconFilePath $iconFilePath -InstallerPath $installerFile.FullName `
            -CustomIconPath $IconPath -OnProgress $OnProgress

        Write-AppGetterProgress -Step 10 -TotalSteps $totalSteps -StepName 'Writing metadata' -Percent 82 -OnProgress $OnProgress
        $metadata = New-AppGetterMetadataFiles -PackageDetails $details -VersionDirectory $versionDirectory `
            -InstallerFileName $installerFile.Name -InstallerHash $installerHash `
            -InstallerInstallCommand $installerInstallCommand -DetectionScript $detectionScript `
            -InstallScript $installScript -UninstallScript $uninstallScript -IconFilePath $iconFilePath

        Write-AppGetterProgress -Step 11 -TotalSteps $totalSteps -StepName 'Packaging .intunewin' -Percent 90 -OnProgress $OnProgress
        $intunewinCmd = Get-Command intunewinapputil -ErrorAction SilentlyContinue
        $packagingSucceeded = $false

        if (-not $intunewinCmd) {
            Write-AppGetterLog -Message 'intunewinapputil not found. Install Microsoft Win32 Content Prep Tool and ensure it is on PATH.' `
                -Level Warning -OnProgress $OnProgress
            Write-AppGetterProgress -Step 12 -TotalSteps $totalSteps -StepName 'Complete with warnings' -Percent 100 `
                -Message 'Metadata created, but Content Prep Tool is unavailable.' -Status Completed -OnProgress $OnProgress
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
                    Write-AppGetterProgress -Step 12 -TotalSteps $totalSteps -StepName 'Complete' -Percent 100 `
                        -Message "Created $intunewinFile ($intunewinSize MB)" -Status Completed -OnProgress $OnProgress
                } else {
                    throw 'Content Prep Tool failed or output file was not created.'
                }
            } catch {
                Write-AppGetterLog -Message "Failed to create IntuneWin package: $_" -Level Warning -OnProgress $OnProgress
                Write-AppGetterFailureLog -LogPath $failureLogPath -Step 'Packaging .intunewin' -ErrorRecord $_
                Write-AppGetterProgress -Step 12 -TotalSteps $totalSteps -StepName 'Complete with warnings' -Percent 100 `
                    -Message 'Metadata created, but .intunewin packaging failed.' -Status Completed -OnProgress $OnProgress
            }
        }

        Save-AppGetterSettings -OutputPath $OutputPath -LastAppName $AppName `
            -LastDownloadUrl $resolvedDownloadUrl -LastWebsiteUrl $WebsiteUrl

        return [PSCustomObject]@{
            Success              = $true
            PackagingSucceeded   = $packagingSucceeded
            PackageId            = $details.PackageId
            DisplayName          = $details.DisplayName
            Version              = $details.Version
            Publisher            = $details.Publisher
            DownloadUrl          = $resolvedDownloadUrl
            VersionDirectory     = $versionDirectory
            IntuneWinFile        = if ($packagingSucceeded) { $intunewinFile } else { $null }
            IconFile             = if (Test-Path $iconFilePath) { $iconFilePath } else { $null }
            LogoFile             = if (Test-Path $logoFilePath) { $logoFilePath } else { $null }
            InstallerFile        = $installerFile.FullName
            InstallerInstallCommand = $installerInstallCommand
            SwitchAnalysis       = $switchAnalysis
            Metadata             = $metadata
            Details              = $details
        }
    }
    catch {
        if ($versionDirectory -and -not $failureLogPath) {
            $failureLogPath = Join-Path $versionDirectory 'appgetter-packaging.log'
        }
        if ($failureLogPath) {
            $parent = Split-Path $failureLogPath -Parent
            if ($parent -and -not (Test-Path $parent)) {
                New-Item -ItemType Directory -Path $parent -Force | Out-Null
            }
            Write-AppGetterFailureLog -LogPath $failureLogPath -Step 'Packaging' -ErrorRecord $_
        }

        Write-AppGetterProgress -Step 0 -TotalSteps $totalSteps -StepName 'Failed' -Percent 0 `
            -Message $_.Exception.Message -Status Failed -OnProgress $OnProgress
        throw
    }
}
