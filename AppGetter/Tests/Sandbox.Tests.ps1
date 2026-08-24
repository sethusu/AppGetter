BeforeAll {
    $moduleManifest = Join-Path $PSScriptRoot '..' 'AppGetter.psd1'
    Import-Module $moduleManifest -Force
}

Describe 'Test-AppGetterWindowsSandbox' {
    It 'Reports that Windows Sandbox is unavailable on non-Windows' {
        $result = Test-AppGetterWindowsSandbox
        $result.Enabled | Should -Be $false
        $result.PSObject.Properties.Name | Should -Contain 'Supported'
        $result.PSObject.Properties.Name | Should -Contain 'Reason'
        $result.PSObject.Properties.Name | Should -Contain 'FeatureName'
        $result.FeatureName | Should -Be 'Containers-DisposableClientVM'

        if ([System.Environment]::OSVersion.Platform -ne 'Win32NT') {
            $result.IsWindows | Should -Be $false
            $result.Supported | Should -Be $false
            $result.Reason | Should -Match 'Windows'
        }
    }
}

Describe 'ConvertTo-AppGetterXmlText' {
    It 'Escapes XML special characters in mapped folder paths' {
        InModuleScope AppGetter {
            ConvertTo-AppGetterXmlText -Value 'C:\Apps & Packages\<test>' |
                Should -Be 'C:\Apps &amp; Packages\&lt;test&gt;'
        }
    }

    It 'Returns an empty string for null or empty input' {
        InModuleScope AppGetter {
            ConvertTo-AppGetterXmlText -Value '' | Should -Be ''
            ConvertTo-AppGetterXmlText -Value $null | Should -Be ''
        }
    }
}

Describe 'New-AppGetterSandboxWsbContent' {
    It 'Maps the package and handshake folders and starts the guest script' {
        InModuleScope AppGetter {
            $wsb = New-AppGetterSandboxWsbContent `
                -HostPackagePath 'D:\Intune Packages\Google.Chrome\131.0' `
                -HostHandshakePath 'C:\Temp\AppGetterSandbox-abc'

            $wsb | Should -Match '<HostFolder>D:\\Intune Packages\\Google.Chrome\\131.0</HostFolder>'
            $wsb | Should -Match '<SandboxFolder>C:\\AppGetterPackage</SandboxFolder>'
            $wsb | Should -Match '<HostFolder>C:\\Temp\\AppGetterSandbox-abc</HostFolder>'
            $wsb | Should -Match '<SandboxFolder>C:\\AppGetterSandbox</SandboxFolder>'
            $wsb | Should -Match '<ReadOnly>true</ReadOnly>'
            $wsb | Should -Match '<ReadOnly>false</ReadOnly>'
            $wsb | Should -Match 'Start-AppGetterSandboxGuest.ps1'
            $wsb | Should -Match '<MemoryInMB>4096</MemoryInMB>'
            $wsb | Should -Match '<LogonCommand>'
        }
    }
}

Describe 'New-AppGetterSandboxGuestScript' {
    It 'Runs install, detection, and uninstall when commanded' {
        InModuleScope AppGetter {
            $script = New-AppGetterSandboxGuestScript
            $script | Should -Match 'install.ps1'
            $script | Should -Match 'detection.ps1'
            $script | Should -Match 'uninstall.ps1'
            $script | Should -Match "action"
            $script | Should -Match 'Waiting for confirmation in AppGetter'
            $script | Should -Match 'C:\\AppGetterTest'
            $script | Should -Match 'Copy-Item'
            $script | Should -Match 'Copy-PackageStepLogs'
            $script | Should -Match 'console-stdout.txt'
            $script | Should -Match 'IntuneManagementExtension\\Logs'
            $script | Should -Match 'Save-DesktopScreenshot'
            $script | Should -Match 'ui-activity.json'
            $script | Should -Match 'interactive window'
            $script | Should -Match 'AppGetterStep-'
            $script | Should -Match 'process.Refresh'
            $script | Should -Match 'Windows PowerShell transcript end'
            $script | Should -Match 'status.ndjson'
            $script | Should -Match 'Ignoring Inno extractor window'
            $script | Should -Match 'STEP_DONE'
        }
    }
}

Describe 'Sandbox silent-switch trial helpers' {
    It 'Generates a trial guest script that watches UI and writes trial-result.json' {
        $script = New-AppGetterSandboxTrialGuestScript
        $script | Should -Match 'trial-result.json'
        $script | Should -Match 'silentUiDetected'
        $script | Should -Match 'Get-UninstallRegistrySnapshot'
        $script | Should -Match 'interactive window'
        $script | Should -Match 'NOT SILENT'
    }

    It 'Treats UI detection as verification failure even with exit code 0' {
        InModuleScope AppGetter {
            $mapped = ConvertTo-AppGetterInstallerVerification -TrialResult ([PSCustomObject]@{
                    Verified = $false
                    ExitCode = 0
                    SilentUiDetected = $true
                    Message = 'not silent'
                    InstallEvidence = @(@{ DisplayName = 'App' })
                    TimedOut = $false
                    KilledForUi = $true
                })
            $mapped.Verified | Should -Be $false
            $mapped.SilentUiDetected | Should -Be $true
            Test-AppGetterAcceptedInstallExitCode -ExitCode 0 | Should -Be $true
            Test-AppGetterAcceptedInstallExitCode -ExitCode 1618 | Should -Be $false
        }
    }
}

Describe 'Resolve-AppGetterPackageVersionDirectory' {
    BeforeAll {
        $script:packageRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("appgetter-sandbox-pkg-{0}" -f ([Guid]::NewGuid().ToString('N')))
        $appRoot = Join-Path $script:packageRoot 'Google.Chrome'
        $versionDir = Join-Path $appRoot '131.0.6778.86'
        New-Item -ItemType Directory -Path $versionDir -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $versionDir 'install.ps1') -Value '# install'
        Set-Content -LiteralPath (Join-Path $versionDir 'detection.ps1') -Value '# detect'
        Set-Content -LiteralPath (Join-Path $versionDir 'uninstall.ps1') -Value '# uninstall'
        Set-Content -LiteralPath (Join-Path $versionDir 'setup.exe') -Value 'fake'
        $script:versionDir = $versionDir
        $script:appRoot = $appRoot
    }

    AfterAll {
        if ($script:packageRoot -and (Test-Path -LiteralPath $script:packageRoot)) {
            Remove-Item -LiteralPath $script:packageRoot -Recurse -Force
        }
    }

    It 'Returns the folder when it already contains install.ps1' {
        Resolve-AppGetterPackageVersionDirectory -Path $script:versionDir | Should -Be ([System.IO.Path]::GetFullPath($script:versionDir))
    }

    It 'Finds the version folder under an app output path' {
        Resolve-AppGetterPackageVersionDirectory -Path $script:appRoot -PackageId 'Google.Chrome' |
            Should -Be ([System.IO.Path]::GetFullPath($script:versionDir))
    }

    It 'Finds the app folder when given the base output path and package id' {
        Resolve-AppGetterPackageVersionDirectory -Path $script:packageRoot -PackageId 'Google.Chrome' |
            Should -Be ([System.IO.Path]::GetFullPath($script:versionDir))
    }

    It 'Prefers the requested version folder' {
        $other = Join-Path $script:appRoot '130.0.0.0'
        New-Item -ItemType Directory -Path $other -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $other 'install.ps1') -Value '# old'
        try {
            Resolve-AppGetterPackageVersionDirectory -Path $script:appRoot -PackageId 'Google.Chrome' -Version '131.0.6778.86' |
                Should -Be ([System.IO.Path]::GetFullPath($script:versionDir))
        } finally {
            Remove-Item -LiteralPath $other -Recurse -Force
        }
    }
}

Describe 'Get-AppGetterSandboxPackageInfo' {
    It 'Requires install, detection, uninstall, and an installer file' {
        $temp = Join-Path ([System.IO.Path]::GetTempPath()) ("appgetter-sandbox-info-{0}" -f ([Guid]::NewGuid().ToString('N')))
        New-Item -ItemType Directory -Path $temp -Force | Out-Null
        try {
            $info = Get-AppGetterSandboxPackageInfo -VersionDirectory $temp
            $info.Ready | Should -Be $false
            $info.Reason | Should -Match 'install.ps1'

            Set-Content -LiteralPath (Join-Path $temp 'install.ps1') -Value '# install'
            Set-Content -LiteralPath (Join-Path $temp 'detection.ps1') -Value '# detect'
            Set-Content -LiteralPath (Join-Path $temp 'uninstall.ps1') -Value '# uninstall'
            $info = Get-AppGetterSandboxPackageInfo -VersionDirectory $temp
            $info.Ready | Should -Be $false
            $info.Reason | Should -Match 'installer'

            Set-Content -LiteralPath (Join-Path $temp 'app-setup.msi') -Value 'fake'
            '{"packageIdentifier":"Contoso.App","displayName":"Contoso App","version":"1.2.3"}' |
                Set-Content -LiteralPath (Join-Path $temp 'app.json') -Encoding UTF8
            $info = Get-AppGetterSandboxPackageInfo -VersionDirectory $temp
            $info.Ready | Should -Be $true
            $info.PackageId | Should -Be 'Contoso.App'
            $info.DisplayName | Should -Be 'Contoso App'
            $info.Version | Should -Be '1.2.3'
        } finally {
            Remove-Item -LiteralPath $temp -Recurse -Force
        }
    }
}

Describe 'Start-AppGetterSandboxSession' {
    It 'Writes WSB, guest script, and an install command without launching Sandbox' {
        $temp = Join-Path ([System.IO.Path]::GetTempPath()) ("appgetter-sandbox-session-{0}" -f ([Guid]::NewGuid().ToString('N')))
        New-Item -ItemType Directory -Path $temp -Force | Out-Null
        try {
            Set-Content -LiteralPath (Join-Path $temp 'install.ps1') -Value '# install'
            Set-Content -LiteralPath (Join-Path $temp 'detection.ps1') -Value '# detect'
            Set-Content -LiteralPath (Join-Path $temp 'uninstall.ps1') -Value '# uninstall'
            Set-Content -LiteralPath (Join-Path $temp 'setup.exe') -Value 'fake'
            '{"packageIdentifier":"Contoso.App","displayName":"Contoso App","version":"1.2.3"}' |
                Set-Content -LiteralPath (Join-Path $temp 'app.json') -Encoding UTF8

            $session = Start-AppGetterSandboxSession -VersionDirectory $temp -SkipLaunch
            try {
                $session.Launched | Should -Be $false
                $session.CurrentStep | Should -Be 'install'
                $session.PackageId | Should -Be 'Contoso.App'
                Test-Path -LiteralPath $session.WsbPath | Should -Be $true
                Test-Path -LiteralPath $session.GuestScriptPath | Should -Be $true
                $command = Get-Content -LiteralPath $session.CommandPath -Raw | ConvertFrom-Json
                $command.action | Should -Be 'install'
                $status = Get-AppGetterSandboxStatus -HandshakeDirectory $session.HandshakeDirectory
                $status.state | Should -Be 'waiting'
                (Get-Content -LiteralPath $session.WsbPath -Raw) | Should -Match 'AppGetterPackage'
            } finally {
                if ($session.HandshakeDirectory -and (Test-Path -LiteralPath $session.HandshakeDirectory)) {
                    Remove-Item -LiteralPath $session.HandshakeDirectory -Recurse -Force
                }
            }
        } finally {
            Remove-Item -LiteralPath $temp -Recurse -Force
        }
    }
}

Describe 'Test-AppGetterSandboxConfirmations and Complete-AppGetterSandboxTest' {
    BeforeEach {
        $script:validationDir = Join-Path ([System.IO.Path]::GetTempPath()) ("appgetter-sandbox-valid-{0}" -f ([Guid]::NewGuid().ToString('N')))
        New-Item -ItemType Directory -Path $script:validationDir -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $script:validationDir 'install.ps1') -Value '# install'
        Set-Content -LiteralPath (Join-Path $script:validationDir 'detection.ps1') -Value '# detect'
        Set-Content -LiteralPath (Join-Path $script:validationDir 'uninstall.ps1') -Value '# uninstall'
        Set-Content -LiteralPath (Join-Path $script:validationDir 'setup.exe') -Value 'fake'
        '{"packageIdentifier":"Contoso.App","displayName":"Contoso App","version":"1.2.3"}' |
            Set-Content -LiteralPath (Join-Path $script:validationDir 'app.json') -Encoding UTF8
    }

    AfterEach {
        if ($script:validationDir -and (Test-Path -LiteralPath $script:validationDir)) {
            Remove-Item -LiteralPath $script:validationDir -Recurse -Force
        }
    }

    It 'Requires confirmation of install, detect, and uninstall' {
        $partial = @{
            install = @{ Confirmed = $true; ExitCode = 0 }
            detect = @{ Confirmed = $true; ExitCode = 0 }
            uninstall = @{ Confirmed = $false; ExitCode = 1 }
        }
        Test-AppGetterSandboxConfirmations -Confirmations $partial | Should -Be $false

        $complete = @{
            install = @{ Confirmed = $true; ExitCode = 0 }
            detect = @{ Confirmed = $true; ExitCode = 1 }
            uninstall = @{ Confirmed = $true; ExitCode = 0 }
        }
        Test-AppGetterSandboxConfirmations -Confirmations $complete | Should -Be $true
    }

    It 'Does not treat a UI language dialog as a successful silent install' {
        $uiShown = @{
            install = @{ Confirmed = $true; ExitCode = 1603; SilentUiDetected = $true; Message = 'Select Setup Language' }
            detect = @{ Confirmed = $true; ExitCode = 0 }
            uninstall = @{ Confirmed = $true; ExitCode = 0 }
        }
        Test-AppGetterSandboxConfirmations -Confirmations $uiShown | Should -Be $false

        $result = Complete-AppGetterSandboxTest -VersionDirectory $script:validationDir -Confirmations $uiShown
        $result.Validated | Should -Be $false
        $app = Get-Content -LiteralPath (Join-Path $script:validationDir 'app.json') -Raw | ConvertFrom-Json
        $app.sandboxValidated | Should -Be $false
    }

    It 'Marks the package validated only when all three steps are confirmed' {
        $allConfirmed = @{
            install = @{ Confirmed = $true; ExitCode = 0; Message = 'installed' }
            detect = @{ Confirmed = $true; ExitCode = 0; Message = 'detected' }
            uninstall = @{ Confirmed = $true; ExitCode = 0; Message = 'uninstalled' }
        }

        $result = Complete-AppGetterSandboxTest -VersionDirectory $script:validationDir -Confirmations $allConfirmed
        $result.Validated | Should -Be $true
        $result.Method | Should -Be 'WindowsSandbox'
        $result.Exists | Should -Be $true
        Test-Path -LiteralPath (Join-Path $script:validationDir 'validation.json') | Should -Be $true

        $app = Get-Content -LiteralPath (Join-Path $script:validationDir 'app.json') -Raw | ConvertFrom-Json
        $app.sandboxValidated | Should -Be $true
        $app.sandboxValidationMethod | Should -Be 'WindowsSandbox'
    }

    It 'Does not mark the package validated when a step is rejected' {
        $rejected = @{
            install = @{ Confirmed = $true; ExitCode = 0 }
            detect = @{ Confirmed = $false; ExitCode = 1 }
            uninstall = @{ Confirmed = $false; ExitCode = $null }
        }

        $result = Complete-AppGetterSandboxTest -VersionDirectory $script:validationDir -Confirmations $rejected
        $result.Validated | Should -Be $false
        $app = Get-Content -LiteralPath (Join-Path $script:validationDir 'app.json') -Raw | ConvertFrom-Json
        $app.sandboxValidated | Should -Be $false
    }
}

Describe 'Write-AppGetterSandboxTestReport' {
    It 'Writes a chat-ready report with silent-switch and step log sections' {
        $temp = Join-Path ([System.IO.Path]::GetTempPath()) ("appgetter-sandbox-report-{0}" -f ([Guid]::NewGuid().ToString('N')))
        $handshake = Join-Path ([System.IO.Path]::GetTempPath()) ("appgetter-sandbox-hs-{0}" -f ([Guid]::NewGuid().ToString('N')))
        New-Item -ItemType Directory -Path $temp -Force | Out-Null
        New-Item -ItemType Directory -Path $handshake -Force | Out-Null
        try {
            $installScript = @"
`$installCommand = @'
"PrusaSlicer.exe" /S
'@
"@
            Set-Content -LiteralPath (Join-Path $temp 'install.ps1') -Value $installScript
            Set-Content -LiteralPath (Join-Path $temp 'detection.ps1') -Value '# detect'
            Set-Content -LiteralPath (Join-Path $temp 'uninstall.ps1') -Value '# uninstall'
            Set-Content -LiteralPath (Join-Path $temp 'PrusaSlicer.exe') -Value 'MZ Inno Setup Setup Data' -Encoding ASCII
            '{"packageIdentifier":"Prusa3D.PrusaSlicer","displayName":"PrusaSlicer","version":"2.9.6"}' |
                Set-Content -LiteralPath (Join-Path $temp 'app.json') -Encoding UTF8

            $installLogs = Join-Path (Join-Path $handshake 'logs') 'install'
            New-Item -ItemType Directory -Path $installLogs -Force | Out-Null
            Set-Content -LiteralPath (Join-Path $handshake 'guest.log') -Value '2026-08-20 Starting install.ps1'
            Set-Content -LiteralPath (Join-Path $installLogs 'console-stdout.txt') -Value 'Executing install command: "PrusaSlicer.exe" /S'
            Set-Content -LiteralPath (Join-Path $installLogs 'Prusa3D.PrusaSlicer-install.log') -Value 'Install failed with exit code 1'
            '{"action":"install"}' | Set-Content -LiteralPath (Join-Path $handshake 'command.json') -Encoding UTF8
            '{"step":"install","state":"completed","exitCode":1}' | Set-Content -LiteralPath (Join-Path $handshake 'status.json') -Encoding UTF8

            $confirmations = @{
                install = @{ Confirmed = $false; ExitCode = 1; Message = 'install.ps1 finished with exit code 1.' }
                detect = @{ Confirmed = $false; ExitCode = $null; Message = '' }
                uninstall = @{ Confirmed = $false; ExitCode = $null; Message = '' }
            }

            $report = Write-AppGetterSandboxTestReport -VersionDirectory $temp -HandshakeDirectory $handshake `
                -Confirmations $confirmations -Outcome 'failed' -Message 'install was not confirmed.'

            Test-Path -LiteralPath $report.Path | Should -Be $true
            $report.Path | Should -Match 'sandbox-test-report\.txt$'
            $report.Text | Should -Match 'AppGetter sandbox test report'
            $report.Text | Should -Match 'Prusa3D.PrusaSlicer'
            $report.Text | Should -Match '/VERYSILENT'
            $report.Text | Should -Match 'WARNING'
            $report.Text | Should -Match 'exitCode=1'
            $report.Text | Should -Match 'Guest coordinator log'
            $report.Text | Should -Match 'Install failed with exit code 1'
            Test-Path -LiteralPath (Join-Path $temp 'sandbox-logs') | Should -Be $true
            Test-Path -LiteralPath (Join-Path (Join-Path $temp 'sandbox-logs') 'guest.log') | Should -Be $true
            Test-Path -LiteralPath (Join-Path $temp 'sandbox-failure.log') | Should -Be $true
            (Get-Content -LiteralPath (Join-Path $temp 'sandbox-failure.log') -Raw) | Should -Match 'What failed'
        } finally {
            Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue
            Remove-Item -LiteralPath $handshake -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

Describe 'Set-AppGetterSandboxCommand' {
    It 'Updates command.json with the next action' {
        $handshake = Join-Path ([System.IO.Path]::GetTempPath()) ("appgetter-sandbox-cmd-{0}" -f ([Guid]::NewGuid().ToString('N')))
        New-Item -ItemType Directory -Path $handshake -Force | Out-Null
        try {
            Set-AppGetterSandboxCommand -HandshakeDirectory $handshake -Action detect
            $command = Get-Content -LiteralPath (Join-Path $handshake 'command.json') -Raw | ConvertFrom-Json
            $command.action | Should -Be 'detect'
        } finally {
            Remove-Item -LiteralPath $handshake -Recurse -Force
        }
    }
}

Describe 'Resolve-AppGetterSandboxStepStatus' {
    It 'Falls back to guest.log when status.json is still running' {
        $handshake = Join-Path ([System.IO.Path]::GetTempPath()) ("appgetter-sandbox-status-{0}" -f ([Guid]::NewGuid().ToString('N')))
        New-Item -ItemType Directory -Path $handshake -Force | Out-Null
        try {
            @{
                step = 'install'
                state = 'running'
                exitCode = $null
                message = 'Running install.ps1'
                updatedAt = (Get-Date).ToUniversalTime().ToString('o')
            } | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $handshake 'status.json') -Encoding UTF8

            @(
                '2026-08-19 21:25:00 Starting install.ps1'
                '2026-08-19 21:25:46 install.ps1 finished with exit code 0.'
            ) | Set-Content -LiteralPath (Join-Path $handshake 'guest.log') -Encoding UTF8

            $status = Resolve-AppGetterSandboxStepStatus -HandshakeDirectory $handshake -Step install
            $status.state | Should -Be 'completed'
            $status.exitCode | Should -Be 0
            $status.source | Should -Be 'guest.log'
        } finally {
            Remove-Item -LiteralPath $handshake -Recurse -Force
        }
    }

    It 'Prefers status.json when it reports completion' {
        $handshake = Join-Path ([System.IO.Path]::GetTempPath()) ("appgetter-sandbox-status-{0}" -f ([Guid]::NewGuid().ToString('N')))
        New-Item -ItemType Directory -Path $handshake -Force | Out-Null
        try {
            @{
                step = 'install'
                state = 'completed'
                exitCode = 0
                message = 'install.ps1 finished with exit code 0.'
                updatedAt = (Get-Date).ToUniversalTime().ToString('o')
            } | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $handshake 'status.json') -Encoding UTF8

            $status = Resolve-AppGetterSandboxStepStatus -HandshakeDirectory $handshake -Step install
            $status.state | Should -Be 'completed'
            $status.exitCode | Should -Be 0
            $status.PSObject.Properties.Name | Should -Not -Contain 'source'
        } finally {
            Remove-Item -LiteralPath $handshake -Recurse -Force
        }
    }

    It 'Reads status.json written with shared file access' {
        $handshake = Join-Path ([System.IO.Path]::GetTempPath()) ("appgetter-sandbox-status-{0}" -f ([Guid]::NewGuid().ToString('N')))
        New-Item -ItemType Directory -Path $handshake -Force | Out-Null
        try {
            InModuleScope AppGetter -Parameters @{ HandshakeDirectory = $handshake } {
                $path = Join-Path $HandshakeDirectory 'status.json'
                Write-AppGetterSandboxJson -Path $path -Object @{
                    step = 'detect'
                    state = 'completed'
                    exitCode = 1
                    message = 'detection.ps1 finished with exit code 1.'
                    updatedAt = (Get-Date).ToUniversalTime().ToString('o')
                }
            }

            $status = Resolve-AppGetterSandboxStepStatus -HandshakeDirectory $handshake -Step detect
            $status.state | Should -Be 'completed'
            $status.exitCode | Should -Be 1
        } finally {
            Remove-Item -LiteralPath $handshake -Recurse -Force
        }
    }

    It 'Treats an install transcript as completed while status.json is still running' {
        $handshake = Join-Path ([System.IO.Path]::GetTempPath()) ("appgetter-sandbox-status-{0}" -f ([Guid]::NewGuid().ToString('N')))
        $stepDir = Join-Path $handshake 'logs\install'
        New-Item -ItemType Directory -Path $stepDir -Force | Out-Null
        try {
            @{
                step = 'install'
                state = 'running'
                exitCode = $null
                message = 'Running install.ps1'
                updatedAt = (Get-Date).ToUniversalTime().ToString('o')
            } | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $handshake 'status.json') -Encoding UTF8

            @(
                'Starting install for PrusaSlicer (Prusa3D.PrusaSlicer) version 2.9.6'
                'Executing install command: "PrusaSlicer_2.9.6_Machine_X64_inno_en-US.exe" /VERYSILENT /NORESTART /SUPPRESSMSGBOXES /SP- /LANG=english'
                'Install completed successfully.'
                'Windows PowerShell transcript end'
                'End time: 20260819214839'
            ) | Set-Content -LiteralPath (Join-Path $stepDir 'console-stdout.txt') -Encoding UTF8

            $status = Resolve-AppGetterSandboxStepStatus -HandshakeDirectory $handshake -Step install
            $status.state | Should -Be 'completed'
            $status.exitCode | Should -Be 0
            $status.source | Should -Be 'step-log'
        } finally {
            Remove-Item -LiteralPath $handshake -Recurse -Force
        }
    }

    It 'Treats dialog log text as completed when handshake files still say running' {
        $handshake = Join-Path ([System.IO.Path]::GetTempPath()) ("appgetter-sandbox-status-{0}" -f ([Guid]::NewGuid().ToString('N')))
        New-Item -ItemType Directory -Path $handshake -Force | Out-Null
        try {
            @{
                step = 'install'
                state = 'running'
                exitCode = $null
                message = 'Running install.ps1'
                updatedAt = (Get-Date).ToUniversalTime().ToString('o')
            } | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $handshake 'status.json') -Encoding UTF8

            $logText = @"
Install completed successfully.
Windows PowerShell transcript end
End time: 20260819214839
"@
            $status = Resolve-AppGetterSandboxStepStatus -HandshakeDirectory $handshake -Step install -LogText $logText
            $status.state | Should -Be 'completed'
            $status.exitCode | Should -Be 0
        } finally {
            Remove-Item -LiteralPath $handshake -Recurse -Force
        }
    }

    It 'Prefers append-only status.ndjson over a stale status.json' {
        $handshake = Join-Path ([System.IO.Path]::GetTempPath()) ("appgetter-sandbox-status-{0}" -f ([Guid]::NewGuid().ToString('N')))
        New-Item -ItemType Directory -Path $handshake -Force | Out-Null
        try {
            @{
                step = 'install'
                state = 'running'
                exitCode = $null
                message = 'Running install.ps1'
                updatedAt = '2026-08-20T03:48:23.2090493Z'
            } | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $handshake 'status.json') -Encoding UTF8

            @(
                '{"step":"install","state":"running","message":"Running install.ps1","updatedAt":"2026-08-20T03:48:23.2090493Z"}'
                '{"step":"install","state":"completed","exitCode":0,"message":"install.ps1 finished with exit code 0.","updatedAt":"2026-08-20T03:48:41.3036224Z"}'
            ) | Set-Content -LiteralPath (Join-Path $handshake 'status.ndjson') -Encoding UTF8

            $status = Get-AppGetterSandboxStatus -HandshakeDirectory $handshake
            $status.state | Should -Be 'completed'
            $status.exitCode | Should -Be 0
        } finally {
            Remove-Item -LiteralPath $handshake -Recurse -Force
        }
    }

    It 'Treats a successful install transcript as completed even if coordinator said not silent' {
        $handshake = Join-Path ([System.IO.Path]::GetTempPath()) ("appgetter-sandbox-status-{0}" -f ([Guid]::NewGuid().ToString('N')))
        New-Item -ItemType Directory -Path $handshake -Force | Out-Null
        try {
            @{
                step = 'install'
                state = 'running'
                message = 'Running install.ps1'
                updatedAt = '2026-08-20T03:48:23.2090493Z'
            } | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $handshake 'status.json') -Encoding UTF8

            @(
                '2026-08-19 21:48:23 Starting install.ps1'
                '2026-08-19 21:48:31 WARNING: interactive window detected during install: ''Setup'' (PrusaSlicer_2.9.6_Machine_X64_inno_en-US.tmp). The step is not silent.'
                '2026-08-19 21:48:41 install.ps1 was not silent. Interactive window(s): Setup. Exit code 1. Screenshot and logs were copied for diagnostics.'
            ) | Set-Content -LiteralPath (Join-Path $handshake 'guest.log') -Encoding UTF8

            $stepDir = Join-Path $handshake 'logs\install'
            New-Item -ItemType Directory -Path $stepDir -Force | Out-Null
            @(
                'Install completed successfully.'
                'Windows PowerShell transcript end'
            ) | Set-Content -LiteralPath (Join-Path $stepDir 'console-stdout.txt') -Encoding UTF8

            $status = Resolve-AppGetterSandboxStepStatus -HandshakeDirectory $handshake -Step install
            $status.state | Should -Be 'completed'
            $status.exitCode | Should -Be 0
        } finally {
            Remove-Item -LiteralPath $handshake -Recurse -Force
        }
    }
}
