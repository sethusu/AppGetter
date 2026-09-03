BeforeAll {
    $moduleManifest = Join-Path $PSScriptRoot '..' 'AppGetter.psd1'
    Import-Module $moduleManifest -Force
    $script:fixtureRoot = Join-Path $PSScriptRoot 'Fixtures' 'Installers'
}

Describe 'Installer fingerprint corpus' {
    It 'Detects direct MSI containers' {
        $path = Join-Path $script:fixtureRoot 'sample.msi'
        $fp = Get-InstallerFingerprint -InstallerPath $path
        $fp.PrimaryType | Should -Be 'msi'
        $fp.Families | Should -Contain 'msi'
        $fp.Confidence | Should -BeGreaterOrEqual 90
    }

    It 'Detects Inno Setup EXEs and recommends /VERYSILENT' {
        $path = Join-Path $script:fixtureRoot 'inno-setup.exe'
        $resolved = Resolve-InstallerInstallCommand -InstallerPath $path `
            -InstallerFileName 'inno-setup.exe' -AppName 'Inno Sample' -SkipVerification
        $resolved.PrimaryType | Should -Be 'exe'
        $resolved.InstallerFamily | Should -Match 'inno'
        $resolved.RecommendedCommand | Should -Match '/VERYSILENT'
        $resolved.ConfidenceScore | Should -BeGreaterThan 20
        $resolved.Verified | Should -Be $false
    }

    It 'Detects NSIS EXEs and recommends /S' {
        $path = Join-Path $script:fixtureRoot 'nsis-setup.exe'
        $resolved = Resolve-InstallerInstallCommand -InstallerPath $path `
            -InstallerFileName 'nsis-setup.exe' -SkipVerification
        $resolved.InstallerFamily | Should -Match 'nsis'
        $resolved.RecommendedCommand | Should -Match '/S'
    }

    It 'Detects InstallShield EXEs' {
        $path = Join-Path $script:fixtureRoot 'installshield-setup.exe'
        $resolved = Resolve-InstallerInstallCommand -InstallerPath $path `
            -InstallerFileName 'installshield-setup.exe' -SkipVerification
        $resolved.InstallerFamily | Should -Match 'installshield'
        $resolved.RecommendedCommand | Should -Match '/s'
    }

    It 'Detects WiX Burn bootstrappers and recommends /quiet' {
        $path = Join-Path $script:fixtureRoot 'wixburn-setup.exe'
        $resolved = Resolve-InstallerInstallCommand -InstallerPath $path `
            -InstallerFileName 'wixburn-setup.exe' -SkipVerification
        $resolved.InstallerFamily | Should -Match 'wixburn'
        $resolved.RecommendedCommand | Should -Match '/quiet'
    }

    It 'Keeps low confidence for ambiguous custom EXEs' {
        $path = Join-Path $script:fixtureRoot 'ambiguous-setup.exe'
        $resolved = Resolve-InstallerInstallCommand -InstallerPath $path `
            -InstallerFileName 'ambiguous-setup.exe' -SkipVerification
        $resolved.PrimaryType | Should -Be 'exe'
        $resolved.ConfidenceScore | Should -BeLessThan 70
        $resolved.NeedsManualReview | Should -Be $true
        $resolved.RecommendedCommand | Should -Match '/S'
    }

    It 'Surfaces nested MSI references for MSI-bridge EXEs' {
        $path = Join-Path $script:fixtureRoot 'msi-bridge-setup.exe'
        $resolved = Resolve-InstallerInstallCommand -InstallerPath $path `
            -InstallerFileName 'msi-bridge-setup.exe' -SkipVerification
        $allCommands = @($resolved.RecommendedCommand) + @($resolved.AlternativeCommands)
        ($allCommands -join '`n') | Should -Match 'payload\.msi'
        $resolved.EvidenceSummary -join '`n' | Should -Match 'msi'
    }
}

Describe 'Manual install arguments' {
    It 'Appends EXE switches to the installer file name' {
        $command = Resolve-AppGetterManualInstallCommand -InstallerFileName 'setup.exe' -UserInput '/VERYSILENT /NORESTART /LANG=english'
        $command | Should -Be '"setup.exe" /VERYSILENT /NORESTART /LANG=english'
    }

    It 'Builds an msiexec command from MSI switches' {
        $command = Resolve-AppGetterManualInstallCommand -InstallerFileName 'app.msi' -UserInput '/qn ALLUSERS=1'
        $command | Should -Be 'msiexec /i "app.msi" /qn ALLUSERS=1'
    }

    It 'Keeps a full msiexec command unchanged' {
        $command = Resolve-AppGetterManualInstallCommand -InstallerFileName 'app.msi' `
            -UserInput 'msiexec /i "app.msi" /qn /norestart'
        $command | Should -Be 'msiexec /i "app.msi" /qn /norestart'
    }

    It 'Keeps a quoted full EXE command unchanged' {
        $command = Resolve-AppGetterManualInstallCommand -InstallerFileName 'setup.exe' `
            -UserInput '"setup.exe" /S /D=C:\Apps\Foo'
        $command | Should -Be '"setup.exe" /S /D=C:\Apps\Foo'
    }

    It 'Treats a short /S switch as arguments, not a full command' {
        $command = Resolve-AppGetterManualInstallCommand -InstallerFileName 'setup.exe' -UserInput '/S'
        $command | Should -Be '"setup.exe" /S'
    }
}

Describe 'Silent switch cache and verification mapping' {
    BeforeEach {
        $script:cachePath = Join-Path ([System.IO.Path]::GetTempPath()) ("appgetter-cache-{0}.json" -f ([Guid]::NewGuid().ToString('N')))
        Mock -ModuleName AppGetter Get-AppGetterSilentSwitchCachePath { $script:cachePath }
    }

    AfterEach {
        if ($script:cachePath -and (Test-Path -LiteralPath $script:cachePath)) {
            Remove-Item -LiteralPath $script:cachePath -Force -ErrorAction SilentlyContinue
        }
    }

    It 'Persists and reuses a verified SHA-256 cache entry' {
        InModuleScope AppGetter {
            $hash = 'ABC123HASH'
            Set-AppGetterSilentSwitchCacheEntry `
                -InstallerHash $hash `
                -VerifiedSilentCommand '"setup.exe" /VERYSILENT' `
                -ProductName 'Sample' `
                -ExitCodeObserved 0 `
                -InstallerFamily 'inno' `
                -EvidenceSummary @('sandbox verified')

            $entry = Get-AppGetterSilentSwitchCacheEntry -InstallerHash $hash
            $entry.VerifiedSilentCommand | Should -Be '"setup.exe" /VERYSILENT'
            $entry.ExitCodeObserved | Should -Be 0
        }

        $path = Join-Path $script:fixtureRoot 'inno-setup.exe'
        $resolved = Resolve-InstallerInstallCommand -InstallerPath $path `
            -InstallerFileName 'inno-setup.exe' -AppName 'Sample' `
            -InstallerHash 'ABC123HASH' -SkipVerification
        # SkipVerification still allows cache reuse for hash hits
        $resolved.UsedCache | Should -Be $true
        $resolved.Verified | Should -Be $true
        $resolved.RecommendedCommand | Should -Be '"setup.exe" /VERYSILENT'
        $resolved.NeedsManualReview | Should -Be $false
    }

    It 'Maps trial failure when UI appeared even if exit code is 0' {
        InModuleScope AppGetter {
            $trial = [PSCustomObject]@{
                Verified = $false
                ExitCode = 0
                SilentUiDetected = $true
                SilentUiWindows = @(@{ windowTitle = 'Select Setup Language' })
                Message = 'Trial was not silent.'
                InstallEvidence = @(@{ DisplayName = 'App' })
                TimedOut = $false
                KilledForUi = $true
            }
            $mapped = ConvertTo-AppGetterInstallerVerification -TrialResult $trial
            $mapped.Verified | Should -Be $false
            $mapped.SilentUiDetected | Should -Be $true
            $mapped.ExitCode | Should -Be 0
            $mapped.Observable.KilledForUi | Should -Be $true
        }
    }

    It 'Accepts only success and reboot exit codes' {
        Test-AppGetterAcceptedInstallExitCode -ExitCode 0 | Should -Be $true
        Test-AppGetterAcceptedInstallExitCode -ExitCode 3010 | Should -Be $true
        Test-AppGetterAcceptedInstallExitCode -ExitCode 1641 | Should -Be $true
        Test-AppGetterAcceptedInstallExitCode -ExitCode 1618 | Should -Be $false
        Test-AppGetterAcceptedInstallExitCode -ExitCode 1603 | Should -Be $false
    }
}

Describe 'Sandbox trial session contract' {
    It 'Builds a trial package with installer and trial-request.json' {
        $installer = Join-Path $script:fixtureRoot 'nsis-setup.exe'
        $temp = Join-Path ([System.IO.Path]::GetTempPath()) ("appgetter-trial-pkg-{0}" -f ([Guid]::NewGuid().ToString('N')))
        try {
            $pkg = New-AppGetterSandboxTrialPackage `
                -InstallerPath $installer `
                -Command '"nsis-setup.exe" /S' `
                -AppName 'NSIS Sample' `
                -DestinationPath $temp
            Test-Path -LiteralPath $pkg.RequestPath | Should -Be $true
            Test-Path -LiteralPath $pkg.InstallerPath | Should -Be $true
            $request = Get-Content -LiteralPath $pkg.RequestPath -Raw | ConvertFrom-Json
            $request.command | Should -Be '"nsis-setup.exe" /S'
            $request.appName | Should -Be 'NSIS Sample'
        } finally {
            if (Test-Path -LiteralPath $temp) {
                Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }

    It 'Prepares a trial Sandbox session without launching' {
        $installer = Join-Path $script:fixtureRoot 'inno-setup.exe'
        $session = $null
        try {
            $session = Start-AppGetterSandboxTrialSession `
                -InstallerPath $installer `
                -Command '"inno-setup.exe" /VERYSILENT /SUPPRESSMSGBOXES' `
                -AppName 'Inno Sample' `
                -SkipLaunch
            $session.Launched | Should -Be $false
            Test-Path -LiteralPath $session.WsbPath | Should -Be $true
            Test-Path -LiteralPath $session.GuestScriptPath | Should -Be $true
            (Get-Content -LiteralPath $session.GuestScriptPath -Raw) | Should -Match 'trial-result.json'
            (Get-Content -LiteralPath $session.GuestScriptPath -Raw) | Should -Match 'interactive window'
            (Get-Content -LiteralPath $session.GuestScriptPath -Raw) | Should -Match 'Uninstall'
            (Get-Content -LiteralPath $session.WsbPath -Raw) | Should -Match 'Start-AppGetterSandboxTrialGuest.ps1'
        } finally {
            if ($session) {
                Stop-AppGetterSandboxTrialSession -Session $session -Cleanup
            }
        }
    }

    It 'Returns unverified when Sandbox verification is not requested' {
        $installer = Join-Path $script:fixtureRoot 'inno-setup.exe'
        $resolved = Resolve-InstallerInstallCommand -InstallerPath $installer `
            -InstallerFileName 'inno-setup.exe' -AppName 'Inno Sample'
        $resolved.Verified | Should -Be $false
        ($resolved.EvidenceSummary -join ' ') | Should -Match 'not requested|skipped|Sandbox verification was not requested|static'
    }

    It 'SkipLaunch trial verification returns prepared session metadata' {
        $installer = Join-Path $script:fixtureRoot 'wixburn-setup.exe'
        $result = Test-InstallerCommandInSandbox `
            -InstallerPath $installer `
            -Command '"wixburn-setup.exe" /quiet /norestart' `
            -AppName 'Burn Sample' `
            -SkipLaunch
        $result.Verified | Should -Be $false
        $result.Method | Should -Be 'WindowsSandbox'
        $result.Session | Should -Not -BeNullOrEmpty
        Stop-AppGetterSandboxTrialSession -Session $result.Session -Cleanup
    }
}

Describe 'SandboxLive silent-switch research trials' -Tag 'SandboxLive' {
    BeforeAll {
        $script:sandbox = Test-AppGetterWindowsSandbox
        $script:canLive = [bool]($script:sandbox.Enabled)
        $script:liveMsi = $null
        if (-not $script:canLive) {
            Write-Host "Skipping SandboxLive tests: $($script:sandbox.Reason)" -ForegroundColor Yellow
        } else {
            try {
                $script:liveMsi = Get-AppGetterLiveTestInstaller -Kind msi
            } catch {
                Write-Host "Skipping SandboxLive installer download: $_" -ForegroundColor Yellow
                $script:canLive = $false
            }
        }
    }

    It 'Downloads a real MSI for Sandbox research when Sandbox is available' -Skip:(-not $script:canLive) {
        $script:liveMsi | Should -Not -BeNullOrEmpty
        Test-Path -LiteralPath $script:liveMsi.Path | Should -Be $true
        $script:liveMsi.Length | Should -BeGreaterThan 100000
        $script:liveMsi.FileName | Should -Match '\.msi$'
    }

    It 'Rejects a clearly non-silent command against a real MSI when Sandbox is available' -Skip:(-not $script:canLive) {
        # Empty/invalid msiexec args should not verify as a silent success.
        $result = Test-InstallerCommandInSandbox `
            -InstallerPath $script:liveMsi.Path `
            -Command ("msiexec /i `"{0}`"" -f $script:liveMsi.FileName) `
            -AppName $script:liveMsi.AppName `
            -TimeoutSeconds 300
        $result.Method | Should -Be 'WindowsSandbox'
        # Without /qn this typically shows UI or fails verification criteria.
        $result.Verified | Should -Be $false
        $result.Message | Should -Not -BeNullOrEmpty
    }

    It 'Marks Verified only when silence, exit code, and ARP evidence all pass' -Skip:(-not $script:canLive) {
        InModuleScope AppGetter {
            $ok = ConvertTo-AppGetterInstallerVerification -TrialResult ([PSCustomObject]@{
                    Verified = $true
                    ExitCode = 0
                    SilentUiDetected = $false
                    Message = 'Trial verified silent install.'
                    InstallEvidence = @(@{ DisplayName = '7-Zip' })
                    TimedOut = $false
                    KilledForUi = $false
                })
            $ok.Verified | Should -Be $true

            $ui = ConvertTo-AppGetterInstallerVerification -TrialResult ([PSCustomObject]@{
                    Verified = $false
                    ExitCode = 0
                    SilentUiDetected = $true
                    Message = 'not silent'
                    InstallEvidence = @(@{ DisplayName = '7-Zip' })
                    TimedOut = $false
                    KilledForUi = $true
                })
            $ui.Verified | Should -Be $false
        }
    }
}
