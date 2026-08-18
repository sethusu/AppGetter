Describe 'AppGetter output path helpers' {
    BeforeAll {
        $modulePath = Join-Path (Split-Path $PSScriptRoot -Parent) 'AppGetter.psd1'
        Import-Module $modulePath -Force
        $script:testRoot = Join-Path ([System.IO.Path]::GetTempPath()) 'AppGetterPathTests'
    }

    It 'defaults the base folder to Documents/AppGetter under the user profile' {
        $homeDir = if ($env:USERPROFILE) { $env:USERPROFILE } elseif ($env:HOME) { $env:HOME } else { [Environment]::GetFolderPath('UserProfile') }
        $docsFolder = if ($env:OS -eq 'Windows_NT') { 'Documents\AppGetter' } else { 'Documents/AppGetter' }
        $expected = Join-Path $homeDir $docsFolder
        Get-AppGetterDefaultBaseOutputPath | Should -Be $expected
    }

    It 'builds an app-named folder under the base path' {
        $base = Join-Path $script:testRoot 'Packages'
        $appPath = Get-AppGetterAppOutputPath -BasePath $base -PackageId 'SIMION'
        $appPath | Should -Be (Join-Path $base 'SIMION')
    }

    It 'does not double-nest when OutputPath already ends with PackageId' {
        $appPath = Join-Path (Join-Path $script:testRoot 'Packages') 'NotepadPP'
        $resolved = Get-AppGetterAppOutputPath -BasePath $appPath -PackageId 'NotepadPP'
        $resolved | Should -Be $appPath
    }

    It 'strips the app folder when recovering the base path' {
        $base = Join-Path $script:testRoot 'Packages'
        $appPath = Join-Path $base 'MyApp'
        $resolved = Get-AppGetterBaseOutputPath -Path $appPath -PackageId 'MyApp'
        $resolved | Should -Be $base
    }
}
