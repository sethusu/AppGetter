Describe 'AppGetter GUI and executable deployment contract' {
    BeforeAll {
        $script:appGetterRoot = Split-Path $PSScriptRoot -Parent
        $script:guiRoot = Join-Path $script:appGetterRoot 'Gui'
        $script:guiScriptPath = Join-Path $script:guiRoot 'Start-AppGetterGui.ps1'
        $script:guiScriptText = Get-Content -Path $script:guiScriptPath -Raw

        $script:xamlNames = @{}
        foreach ($xamlFile in (Get-ChildItem -Path $script:guiRoot -Filter '*.xaml')) {
            $xml = [xml](Get-Content -Path $xamlFile.FullName -Raw)
            $names = [System.Collections.Generic.List[string]]::new()
            $walker = {
                param($node)
                foreach ($child in $node.ChildNodes) {
                    if ($child.NodeType -ne [System.Xml.XmlNodeType]::Element) { continue }
                    $nameAttribute = $child.GetAttribute('Name', 'http://schemas.microsoft.com/winfx/2006/xaml')
                    if ($nameAttribute) { $names.Add($nameAttribute) }
                    & $walker $child
                }
            }
            & $walker $xml
            $script:xamlNames[$xamlFile.Name] = $names
        }

        $script:allXamlNames = @($script:xamlNames.Values | ForEach-Object { $_ })
    }

    Context 'XAML windows' {
        It 'ships the main window plus the link and icon picker dialogs' {
            foreach ($xamlName in @('AppGetter.MainWindow.xaml', 'AppGetter.LinkPickerDialog.xaml', 'AppGetter.IconPickerDialog.xaml')) {
                Join-Path $script:guiRoot $xamlName | Should -Exist
            }
        }

        It 'parses every XAML file as valid XML' {
            foreach ($xamlFile in (Get-ChildItem -Path $script:guiRoot -Filter '*.xaml')) {
                { [xml](Get-Content -Path $xamlFile.FullName -Raw) } | Should -Not -Throw
            }
        }

        It 'exposes the Wingetter-style main window controls' {
            $expected = @(
                'PrereqStatusText', 'InstallContentPrepButton',
                'DownloadUrlRadio', 'LocalFileRadio', 'WebsiteRadio',
                'SourceBox', 'BrowseSourceButton', 'FindLinksButton', 'SelectedAppText',
                'AppNameBox', 'PublisherBox', 'VersionBox',
                'OutputPathBox', 'BrowseOutputButton',
                'ProgressBar', 'ProgressStatusText', 'StepList',
                'IconPreview', 'IconStatusText', 'BrowseIconButton',
                'LogTextBox', 'OpenOutputButton', 'PackButton'
            )
            foreach ($name in $expected) {
                $script:xamlNames['AppGetter.MainWindow.xaml'] | Should -Contain $name
            }
        }

        It 'exposes the picker dialog controls' {
            foreach ($name in @('LinkSummaryText', 'ResultsPanel', 'SelectButton', 'CancelButton')) {
                $script:xamlNames['AppGetter.LinkPickerDialog.xaml'] | Should -Contain $name
            }
            foreach ($name in @('IconSummaryText', 'CandidatesPanel', 'UseSelectedButton', 'KeepCurrentButton')) {
                $script:xamlNames['AppGetter.IconPickerDialog.xaml'] | Should -Contain $name
            }
        }
    }

    Context 'GUI script bindings' {
        It 'only binds control names that exist in the XAML' {
            $bound = [regex]::Matches($script:guiScriptText, "FindName\('([^']+)'\)") |
                ForEach-Object { $_.Groups[1].Value } |
                Sort-Object -Unique
            $bound.Count | Should -BeGreaterThan 0
            foreach ($name in $bound) {
                $script:allXamlNames | Should -Contain $name
            }
        }

        It 'calls the module functions it depends on' {
            foreach ($functionName in @(
                    'Invoke-AppGetterPackaging', 'Test-AppGetterPrerequisites', 'Install-AppGetterContentPrepTool',
                    'Get-AppGetterAppOutputPath', 'Get-AppGetterBaseOutputPath', 'Find-WebDownloadLinks',
                    'Set-AppGetterPackageIconFiles')) {
                $script:guiScriptText | Should -Match ([regex]::Escape($functionName))
            }
        }

        It 'exports every module function the GUI and CLI call' {
            $manifest = Import-PowerShellDataFile -LiteralPath (Join-Path $script:appGetterRoot 'AppGetter.psd1')
            foreach ($functionName in @(
                    'Invoke-AppGetterPackaging', 'Test-AppGetterPrerequisites', 'Install-AppGetterContentPrepTool',
                    'Get-AppGetterAppOutputPath', 'Get-AppGetterBaseOutputPath', 'Get-AppGetterSettings',
                    'Save-AppGetterSettings', 'Find-WebDownloadLinks', 'Get-PackageIdFromAppName',
                    'Get-AppGetterInstallerFileNameFromUrl', 'Set-AppGetterPackageIconFiles')) {
                $manifest.FunctionsToExport | Should -Contain $functionName
            }
        }
    }

    Context 'executable deployment' {
        It 'ships the launcher, cmd helper, and ps2exe build script' {
            Join-Path $script:appGetterRoot 'Launch-AppGetter.ps1' | Should -Exist
            Join-Path $script:appGetterRoot 'Start-AppGetter.cmd' | Should -Exist
            Join-Path $script:appGetterRoot 'Build/Build-AppGetterExe.ps1' | Should -Exist
        }

        It 'checks for runtime files that actually exist in the repository' {
            $launcherText = Get-Content -Path (Join-Path $script:appGetterRoot 'Launch-AppGetter.ps1') -Raw
            $required = [regex]::Matches($launcherText, "Name = '([^']+)' \}") | ForEach-Object { $_.Groups[1].Value }
            $required.Count | Should -BeGreaterThan 0
            foreach ($relativePath in $required) {
                Join-Path $script:appGetterRoot ($relativePath -replace '\\', '/') | Should -Exist
            }
        }

        It 'stages only files that exist when building the exe' {
            $buildText = Get-Content -Path (Join-Path $script:appGetterRoot 'Build/Build-AppGetterExe.ps1') -Raw
            $copyBlock = [regex]::Match($buildText, '\$copyItems = @\(([^)]*)\)')
            $copyBlock.Success | Should -BeTrue
            $items = [regex]::Matches($copyBlock.Groups[1].Value, "'([^']+)'") | ForEach-Object { $_.Groups[1].Value }
            $items | Should -Contain 'Gui'
            $items | Should -Contain 'Private'
            $items | Should -Contain 'Launch-AppGetter.ps1'
            foreach ($item in $items) {
                Join-Path $script:appGetterRoot $item | Should -Exist
            }
        }

        It 'compiles the launcher (not the GUI script) into the exe' {
            $buildText = Get-Content -Path (Join-Path $script:appGetterRoot 'Build/Build-AppGetterExe.ps1') -Raw
            $buildText | Should -Match "AppGetter\.exe"
            $buildText | Should -Match 'Launch-AppGetter\.ps1'
            $buildText | Should -Match '-noConsole'
        }
    }
}
