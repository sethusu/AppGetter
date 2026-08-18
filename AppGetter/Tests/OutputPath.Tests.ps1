Describe 'AppGetter output path helpers' {
    BeforeAll {
        $modulePath = Join-Path (Split-Path $PSScriptRoot -Parent) 'AppGetter.psd1'
        Import-Module $modulePath -Force
        $script:testRoot = Join-Path ([System.IO.Path]::GetTempPath()) 'AppGetterPathTests'
    }

    It 'defaults the base folder to Documents/AppGetter under the user profile' {
        $homeDir = if ($env:USERPROFILE) { $env:USERPROFILE } elseif ($env:HOME) { $env:HOME } else { [Environment]::GetFolderPath('UserProfile') }
        $expected = [System.IO.Path]::Combine($homeDir, 'Documents', 'AppGetter')
        Get-AppGetterDefaultBaseOutputPath | Should -Be $expected
    }

    It 'builds an app-named folder under the base path' {
        $base = Join-Path $script:testRoot 'Packages'
        $appPath = Get-AppGetterAppOutputPath -BasePath $base -PackageId 'SIMION'
        $appPath | Should -Be (Join-Path $base 'SIMION')
    }

    It 'does not double-nest when OutputPath already ends with PackageId' {
        $appPath = Join-Path (Join-Path $script:testRoot 'Packages') 'NotepadPlusPlus'
        $resolved = Get-AppGetterAppOutputPath -BasePath $appPath -PackageId 'NotepadPlusPlus'
        $resolved | Should -Be $appPath
    }

    It 'strips the app folder when recovering the base path' {
        $base = Join-Path $script:testRoot 'Packages'
        $appPath = Join-Path $base 'SevenZip'
        $resolved = Get-AppGetterBaseOutputPath -Path $appPath -PackageId 'SevenZip'
        $resolved | Should -Be $base
    }

    It 'falls back to the default base path when no path is supplied' {
        Get-AppGetterBaseOutputPath -Path '' -PackageId 'SIMION' | Should -Be (Get-AppGetterDefaultBaseOutputPath)
    }

    It 'derives a package id by stripping non-alphanumeric characters' {
        Get-PackageIdFromAppName -AppName 'Notepad++ 8.6' | Should -Be 'Notepad86'
        Get-PackageIdFromAppName -AppName 'SIMION' | Should -Be 'SIMION'
    }
}
