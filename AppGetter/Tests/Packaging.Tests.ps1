Describe 'AppGetter packaging from a local installer file' {
    BeforeAll {
        $modulePath = Join-Path (Split-Path $PSScriptRoot -Parent) 'AppGetter.psd1'
        Import-Module $modulePath -Force

        $script:testRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('AppGetterPackagingTests-' + [Guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $script:testRoot -Force | Out-Null

        # Keep settings writes inside the test folder instead of the real user profile.
        $script:originalAppData = $env:APPDATA
        $env:APPDATA = Join-Path $script:testRoot 'appdata'

        $script:installerPath = Join-Path $script:testRoot 'fabrikam-setup-3.1.4.exe'
        Set-Content -Path $script:installerPath -Value 'MZ fake installer payload for packaging tests' -Encoding ASCII

        # 1x1 transparent PNG so packaging uses a custom icon and never reaches the network.
        $script:iconPath = Join-Path $script:testRoot 'custom-icon.png'
        $pngBase64 = 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=='
        [System.IO.File]::WriteAllBytes($script:iconPath, [Convert]::FromBase64String($pngBase64))

        $script:outputRoot = Join-Path $script:testRoot 'out'
        $script:result = Invoke-AppGetterPackaging -AppName 'Fabrikam Tools' -InstallerPath $script:installerPath `
            -Publisher 'Fabrikam Inc' -OutputPath $script:outputRoot -IconPath $script:iconPath 6> $null
    }

    AfterAll {
        $env:APPDATA = $script:originalAppData
        if ($script:testRoot -and (Test-Path $script:testRoot)) {
            Remove-Item -Path $script:testRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'reports the local file as the installer source' {
        $script:result.Success | Should -BeTrue
        $script:result.SourceType | Should -Be 'LocalFile'
        $script:result.SourceLocation | Should -Be (Resolve-Path -LiteralPath $script:installerPath).Path
    }

    It 'packages into {base}/{PackageId}/{Version}' {
        $expected = Join-Path (Join-Path $script:outputRoot 'FabrikamTools') '3.1.4'
        $script:result.VersionDirectory | Should -Be $expected
    }

    It 'copies the installer next to the generated scripts' {
        Join-Path $script:result.VersionDirectory 'fabrikam-setup-3.1.4.exe' | Should -Exist
    }

    It 'writes every Intune package file' {
        foreach ($fileName in @('install.ps1', 'detection.ps1', 'uninstall.ps1', 'README.md', 'readme.txt', 'app.json', 'win32LobApp.json', 'icon.png')) {
            Join-Path $script:result.VersionDirectory $fileName | Should -Exist
        }
    }

    It 'records the installer source in app.json' {
        $appJson = Get-Content -Path (Join-Path $script:result.VersionDirectory 'app.json') -Raw | ConvertFrom-Json
        $appJson.installerSourceType | Should -Be 'LocalFile'
        $appJson.installerSourcePath | Should -Be (Resolve-Path -LiteralPath $script:installerPath).Path
        $appJson.installerFilename | Should -Be 'fabrikam-setup-3.1.4.exe'
    }

    It 'documents the installer source in README.md' {
        $readme = Get-Content -Path (Join-Path $script:result.VersionDirectory 'README.md') -Raw
        $readme | Should -Match 'Local installer file on the packaging computer'
    }

    It 'embeds the custom icon in win32LobApp.json' {
        $win32 = Get-Content -Path (Join-Path $script:result.VersionDirectory 'win32LobApp.json') -Raw | ConvertFrom-Json
        $win32.largeIcon.type | Should -Be 'image/png'
        $win32.displayName | Should -Be 'Fabrikam Tools'
        $win32.publisher | Should -Be 'Fabrikam Inc'
    }

    It 'completes without the Content Prep Tool but reports packaging as unfinished' {
        # intunewinapputil is Windows-only, so on Linux the .intunewin step is skipped by design.
        if (Resolve-AppGetterContentPrepToolPath) {
            $script:result.PackagingSucceeded | Should -BeTrue
        } else {
            $script:result.PackagingSucceeded | Should -BeFalse
            $script:result.IntuneWinFile | Should -BeNullOrEmpty
        }
    }

    It 'remembers the base output folder and source mode in settings' {
        $settings = Get-AppGetterSettings
        $settings.OutputPath | Should -Be $script:outputRoot
        $settings.LastSourceMode | Should -Be 'LocalFile'
        $settings.LastPackageId | Should -Be 'FabrikamTools'
    }
}
