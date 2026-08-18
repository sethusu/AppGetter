Describe 'AppGetter installer source resolution' {
    BeforeAll {
        $modulePath = Join-Path (Split-Path $PSScriptRoot -Parent) 'AppGetter.psd1'
        Import-Module $modulePath -Force

        $script:testRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('AppGetterSourceTests-' + [Guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $script:testRoot -Force | Out-Null

        $script:localInstaller = Join-Path $script:testRoot 'contoso-setup-4.2.1.exe'
        Set-Content -Path $script:localInstaller -Value 'MZ not a real installer' -Encoding ASCII
    }

    AfterAll {
        if ($script:testRoot -and (Test-Path $script:testRoot)) {
            Remove-Item -Path $script:testRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    Context 'file names derived from download URLs' {
        It 'takes the file name from a direct URL' {
            Get-AppGetterInstallerFileNameFromUrl -Url 'https://example.com/files/setup.exe' | Should -Be 'setup.exe'
        }

        It 'ignores query strings and fragments' {
            Get-AppGetterInstallerFileNameFromUrl -Url 'https://example.com/d/app-1.2.3.msi?token=abc#frag' | Should -Be 'app-1.2.3.msi'
        }

        It 'falls back to an .exe name when the URL has no file extension' {
            Get-AppGetterInstallerFileNameFromUrl -Url 'https://example.com/download' | Should -Be 'download.exe'
        }

        It 'decodes percent-encoded file names' {
            Get-AppGetterInstallerFileNameFromUrl -Url 'https://example.com/My%20App%20Setup.exe' | Should -Be 'My App Setup.exe'
        }
    }

    Context 'local installer files' {
        It 'resolves a local file as a LocalFile source' {
            $source = Resolve-AppGetterInstallerSource -InstallerPath $script:localInstaller -AppName 'Contoso'
            $source.SourceType | Should -Be 'LocalFile'
            $source.FileName | Should -Be 'contoso-setup-4.2.1.exe'
            $source.Location | Should -Be (Resolve-Path -LiteralPath $script:localInstaller).Path
        }

        It 'prefers the local file over a download URL' {
            $source = Resolve-AppGetterInstallerSource -InstallerPath $script:localInstaller `
                -DownloadUrl 'https://example.com/other.exe' -AppName 'Contoso'
            $source.SourceType | Should -Be 'LocalFile'
        }

        It 'throws when the local file does not exist' {
            { Resolve-AppGetterInstallerSource -InstallerPath (Join-Path $script:testRoot 'missing.exe') -AppName 'Contoso' } |
                Should -Throw '*not found*'
        }

        It 'stages the local installer into the package folder' {
            $destination = Join-Path $script:testRoot 'staged'
            $staged = Copy-AppGetterLocalInstaller -InstallerPath $script:localInstaller -DestinationDirectory $destination
            $staged | Should -Be (Join-Path $destination 'contoso-setup-4.2.1.exe')
            Test-Path -LiteralPath $staged | Should -BeTrue
        }
    }

    Context 'direct download URLs' {
        It 'resolves a direct URL as a DownloadUrl source without touching the network' {
            $source = Resolve-AppGetterInstallerSource -DownloadUrl 'https://example.com/files/setup.exe' -AppName 'Contoso'
            $source.SourceType | Should -Be 'DownloadUrl'
            $source.Location | Should -Be 'https://example.com/files/setup.exe'
            $source.FileName | Should -Be 'setup.exe'
        }

        It 'throws when no source is supplied at all' {
            { Resolve-AppGetterInstallerSource -AppName 'Contoso' } | Should -Throw '*required*'
        }
    }

    Context 'package details for local installers' {
        It 'detects the version from the installer file name' {
            $details = Get-WebPackageDetails -AppName 'Contoso Suite' -InstallerPath $script:localInstaller -Publisher 'Contoso'
            $details.Version | Should -Be '4.2.1'
            $details.SourceType | Should -Be 'LocalFile'
            $details.PackageId | Should -Be 'ContosoSuite'
        }

        It 'honours an explicit version override' {
            $details = Get-WebPackageDetails -AppName 'Contoso Suite' -InstallerPath $script:localInstaller -Version '9.9.9'
            $details.Version | Should -Be '9.9.9'
        }
    }
}
