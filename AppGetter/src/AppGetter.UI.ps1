#Requires -Version 5.1

<#
.SYNOPSIS
    AppGetter Windows 11 style desktop UI.
.DESCRIPTION
    WPF front-end for download location management, installer import,
    silent switch testing, and switch discovery.
#>

param(
    [switch]$NoModuleReload
)

$ErrorActionPreference = 'Stop'

$script:UiRoot = $PSScriptRoot
$script:AppGetterRoot = Split-Path $UiRoot -Parent
$script:ModulePath = Join-Path $AppGetterRoot 'Modules\AppGetter.Core\AppGetter.Core.psd1'

if (-not (Test-Path $script:ModulePath)) {
    throw "AppGetter.Core module not found at '$script:ModulePath'."
}

if (-not $NoModuleReload) {
    Import-Module $script:ModulePath -Force
}

Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase
Add-Type -AssemblyName System.Windows.Forms

function Show-OpenFileDialog {
    param([string]$Filter = 'Installers (*.exe;*.msi;*.msix;*.appx)|*.exe;*.msi;*.msix;*.appx|All files (*.*)|*.*')
    $dialog = New-Object System.Windows.Forms.OpenFileDialog
    $dialog.Filter = $Filter
    $dialog.Title = 'Select installer file'
    if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        return $dialog.FileName
    }
    return $null
}

function Show-FolderBrowserDialog {
    param([string]$Description = 'Select download location')
    $dialog = New-Object System.Windows.Forms.FolderBrowserDialog
    $dialog.Description = $Description
    $dialog.ShowNewFolderButton = $true
    if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        return $dialog.SelectedPath
    }
    return $null
}

function Set-StatusBadge {
    param(
        $BadgeBorder,
        $BadgeText,
        [string]$Status
    )

    switch ($Status) {
        'Known' {
            $BadgeBorder.Background = '#E7F6E7'
            $BadgeText.Foreground = '#107C10'
            $BadgeText.Text = 'Known switches'
        }
        'Partial' {
            $BadgeBorder.Background = '#FFF4E5'
            $BadgeText.Foreground = '#CA5010'
            $BadgeText.Text = 'Partial match'
        }
        'Unknown' {
            $BadgeBorder.Background = '#FDE7E9'
            $BadgeText.Foreground = '#C42B1C'
            $BadgeText.Text = 'Needs discovery'
        }
        default {
            $BadgeBorder.Background = '#F0F0F0'
            $BadgeText.Foreground = '#5C5C5C'
            $BadgeText.Text = 'Not analyzed'
        }
    }
}

function Update-InstallerStatusPanel {
    param($Window)

    $installerPath = $Window.FindName('TxtInstallerPath').Text
    $badgeBorder = $Window.FindName('StatusBadgeBorder')
    $badgeText = $Window.FindName('StatusBadgeText')
    $resultBox = $Window.FindName('TxtAnalysisResult')

    if ([string]::IsNullOrWhiteSpace($installerPath) -or -not (Test-Path $installerPath)) {
        Set-StatusBadge -BadgeBorder $badgeBorder -BadgeText $badgeText -Status 'None'
        $resultBox.Text = 'Import or select an installer to analyze silent install switches.'
        return
    }

    try {
        $analysis = Test-InstallerSilentSwitch -InstallerPath $installerPath -IncludeHelpProbe
        Set-StatusBadge -BadgeBorder $badgeBorder -BadgeText $badgeText -Status $analysis.Status
        $Window.FindName('TxtInstallCommand').Text = $analysis.InstallCommand

        $lines = @(
            "Status: $($analysis.Status)",
            "Framework: $($analysis.Framework)",
            "Confidence: $($analysis.Confidence)",
            "Source: $($analysis.Source)",
            "Recommended command:",
            $analysis.InstallCommand,
            '',
            'Evidence:'
        )
        $lines += $analysis.Evidence
        $resultBox.Text = ($lines -join [Environment]::NewLine)

        if ($analysis.RequiresDiscovery) {
            $Window.FindName('BtnDiscover').IsEnabled = $true
        } else {
            $Window.FindName('BtnDiscover').IsEnabled = $true
        }
    } catch {
        $resultBox.Text = "Analysis failed: $_"
        Set-StatusBadge -BadgeBorder $badgeBorder -BadgeText $badgeText -Status 'Unknown'
    }
}

function Show-AppGetterWindow {
    $settings = Get-AppGetterSettings
    $themePath = Join-Path $script:UiRoot 'Themes\Win11Theme.xaml'
    $themeXaml = Get-Content -Path $themePath -Raw

    [xml]$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="AppGetter"
        Height="760"
        Width="1100"
        MinHeight="640"
        MinWidth="900"
        WindowStartupLocation="CenterScreen"
        Background="#F3F3F3"
        FontFamily="Segoe UI Variable Text, Segoe UI">
    <Grid Margin="24">
        <Grid.ColumnDefinitions>
            <ColumnDefinition Width="220"/>
            <ColumnDefinition Width="*"/>
        </Grid.ColumnDefinitions>

        <Border Grid.Column="0" Background="White" CornerRadius="8" BorderBrush="#E5E5E5" BorderThickness="1" Padding="16" Margin="0,0,16,0">
            <StackPanel>
                <TextBlock Text="AppGetter" FontSize="22" FontWeight="SemiBold" Margin="0,0,0,4"/>
                <TextBlock Text="Intune package assistant" FontSize="12" Foreground="#5C5C5C" Margin="0,0,0,20"/>
                <RadioButton x:Name="NavHome" Content="Home" IsChecked="True" GroupName="Nav"/>
                <RadioButton x:Name="NavInstaller" Content="Installer source" GroupName="Nav"/>
                <RadioButton x:Name="NavSwitches" Content="Silent switches" GroupName="Nav"/>
                <RadioButton x:Name="NavSettings" Content="Settings" GroupName="Nav"/>
            </StackPanel>
        </Border>

        <ScrollViewer Grid.Column="1" VerticalScrollBarVisibility="Auto">
            <StackPanel x:Name="MainContent">

                <!-- Home -->
                <StackPanel x:Name="PageHome">
                    <TextBlock Text="Welcome to AppGetter" FontSize="28" FontWeight="SemiBold" Margin="0,0,0,8"/>
                    <TextBlock Text="Configure a download location, import installers, test silent switches, and discover missing deployment flags."
                               TextWrapping="Wrap" Foreground="#5C5C5C" Margin="0,0,0,20"/>
                    <Border Background="White" CornerRadius="8" BorderBrush="#E5E5E5" BorderThickness="1" Padding="20" Margin="0,0,0,16">
                        <StackPanel>
                            <TextBlock Text="Quick start" FontSize="18" FontWeight="SemiBold" Margin="0,0,0,12"/>
                            <TextBlock Text="1. Set your download folder in Settings" Margin="0,0,0,6"/>
                            <TextBlock Text="2. Import an installer from URL or local file" Margin="0,0,0,6"/>
                            <TextBlock Text="3. Test whether silent install switches are known" Margin="0,0,0,6"/>
                            <TextBlock Text="4. Discover missing switches from docs or installer help output"/>
                        </StackPanel>
                    </Border>
                    <Border Background="White" CornerRadius="8" BorderBrush="#E5E5E5" BorderThickness="1" Padding="20">
                        <StackPanel>
                            <TextBlock Text="Current download location" FontSize="16" FontWeight="SemiBold" Margin="0,0,0,8"/>
                            <TextBlock x:Name="TxtHomeDownloadLocation" TextWrapping="Wrap" Foreground="#5C5C5C"/>
                        </StackPanel>
                    </Border>
                </StackPanel>

                <!-- Installer source -->
                <StackPanel x:Name="PageInstaller" Visibility="Collapsed">
                    <TextBlock Text="Installer source" FontSize="28" FontWeight="SemiBold" Margin="0,0,0,16"/>
                    <Border Background="White" CornerRadius="8" BorderBrush="#E5E5E5" BorderThickness="1" Padding="20" Margin="0,0,0,16">
                        <StackPanel>
                            <TextBlock Text="Download from URL" FontSize="16" FontWeight="SemiBold" Margin="0,0,0,8"/>
                            <TextBlock Text="Download URL" FontSize="13" Foreground="#5C5C5C" Margin="0,0,0,6"/>
                            <TextBox x:Name="TxtDownloadUrl" Padding="10,8" Margin="0,0,0,12"/>
                            <Button x:Name="BtnDownload" Content="Download to folder" Padding="16,8" HorizontalAlignment="Left" Background="#0078D4" Foreground="White" BorderThickness="0"/>
                        </StackPanel>
                    </Border>
                    <Border Background="White" CornerRadius="8" BorderBrush="#E5E5E5" BorderThickness="1" Padding="20" Margin="0,0,0,16">
                        <StackPanel>
                            <TextBlock Text="Upload local installer" FontSize="16" FontWeight="SemiBold" Margin="0,0,0,8"/>
                            <TextBlock Text="Copy a local installer into your configured download location." FontSize="13" Foreground="#5C5C5C" TextWrapping="Wrap" Margin="0,0,0,12"/>
                            <Button x:Name="BtnBrowseInstaller" Content="Browse and import" Padding="16,8" HorizontalAlignment="Left" Background="White" BorderBrush="#E5E5E5" BorderThickness="1"/>
                        </StackPanel>
                    </Border>
                    <Border Background="White" CornerRadius="8" BorderBrush="#E5E5E5" BorderThickness="1" Padding="20">
                        <StackPanel>
                            <TextBlock Text="Active installer" FontSize="16" FontWeight="SemiBold" Margin="0,0,0,8"/>
                            <TextBox x:Name="TxtInstallerPath" Padding="10,8" Margin="0,0,0,12"/>
                            <Button x:Name="BtnUseLastInstaller" Content="Use last imported installer" Padding="16,8" HorizontalAlignment="Left" Background="White" BorderBrush="#E5E5E5" BorderThickness="1"/>
                        </StackPanel>
                    </Border>
                </StackPanel>

                <!-- Silent switches -->
                <StackPanel x:Name="PageSwitches" Visibility="Collapsed">
                    <TextBlock Text="Silent install switches" FontSize="28" FontWeight="SemiBold" Margin="0,0,0,16"/>
                    <Border x:Name="StatusBadgeBorder" Background="#F0F0F0" CornerRadius="12" Padding="10,4" HorizontalAlignment="Left" Margin="0,0,0,16">
                        <TextBlock x:Name="StatusBadgeText" Text="Not analyzed" Foreground="#5C5C5C"/>
                    </Border>
                    <Border Background="White" CornerRadius="8" BorderBrush="#E5E5E5" BorderThickness="1" Padding="20" Margin="0,0,0,16">
                        <StackPanel>
                            <TextBlock Text="Installer path" FontSize="13" Foreground="#5C5C5C" Margin="0,0,0,6"/>
                            <TextBox x:Name="TxtSwitchInstallerPath" Padding="10,8" Margin="0,0,0,12"/>
                            <StackPanel Orientation="Horizontal">
                                <Button x:Name="BtnTestSwitches" Content="Test switches" Padding="16,8" Margin="0,0,8,0" Background="#0078D4" Foreground="White" BorderThickness="0"/>
                                <Button x:Name="BtnDiscover" Content="Discover missing switches" Padding="16,8" Margin="0,0,8,0" Background="#0078D4" Foreground="White" BorderThickness="0"/>
                                <Button x:Name="BtnSaveCommand" Content="Save result" Padding="16,8" Background="White" BorderBrush="#E5E5E5" BorderThickness="1"/>
                            </StackPanel>
                        </StackPanel>
                    </Border>
                    <Border Background="White" CornerRadius="8" BorderBrush="#E5E5E5" BorderThickness="1" Padding="20" Margin="0,0,0,16">
                        <StackPanel>
                            <TextBlock Text="Documentation URLs (optional)" FontSize="16" FontWeight="SemiBold" Margin="0,0,0,8"/>
                            <TextBlock Text="One URL per line. Used for research when switches are unknown." FontSize="13" Foreground="#5C5C5C" Margin="0,0,0,8"/>
                            <TextBox x:Name="TxtDocUrls" AcceptsReturn="True" Height="80" TextWrapping="Wrap" Padding="10,8"/>
                        </StackPanel>
                    </Border>
                    <Border Background="White" CornerRadius="8" BorderBrush="#E5E5E5" BorderThickness="1" Padding="20" Margin="0,0,0,16">
                        <StackPanel>
                            <TextBlock Text="Recommended install command" FontSize="16" FontWeight="SemiBold" Margin="0,0,0,8"/>
                            <TextBox x:Name="TxtInstallCommand" Padding="10,8"/>
                        </StackPanel>
                    </Border>
                    <Border Background="White" CornerRadius="8" BorderBrush="#E5E5E5" BorderThickness="1" Padding="20">
                        <StackPanel>
                            <TextBlock Text="Analysis details" FontSize="16" FontWeight="SemiBold" Margin="0,0,0,8"/>
                            <TextBox x:Name="TxtAnalysisResult" IsReadOnly="True" TextWrapping="Wrap" AcceptsReturn="True" Height="180" Padding="10,8" Background="#FAFAFA"/>
                        </StackPanel>
                    </Border>
                </StackPanel>

                <!-- Settings -->
                <StackPanel x:Name="PageSettings" Visibility="Collapsed">
                    <TextBlock Text="Settings" FontSize="28" FontWeight="SemiBold" Margin="0,0,0,16"/>
                    <Border Background="White" CornerRadius="8" BorderBrush="#E5E5E5" BorderThickness="1" Padding="20" Margin="0,0,0,16">
                        <StackPanel>
                            <TextBlock Text="Download location" FontSize="16" FontWeight="SemiBold" Margin="0,0,0,8"/>
                            <TextBlock Text="All downloaded and imported installers are stored here." FontSize="13" Foreground="#5C5C5C" Margin="0,0,0,8"/>
                            <TextBox x:Name="TxtDownloadLocation" Padding="10,8" Margin="0,0,0,12"/>
                            <StackPanel Orientation="Horizontal">
                                <Button x:Name="BtnBrowseDownloadLocation" Content="Browse" Padding="16,8" Margin="0,0,8,0" Background="White" BorderBrush="#E5E5E5" BorderThickness="1"/>
                                <Button x:Name="BtnSaveSettings" Content="Save settings" Padding="16,8" Background="#0078D4" Foreground="White" BorderThickness="0"/>
                            </StackPanel>
                        </StackPanel>
                    </Border>
                    <Border Background="White" CornerRadius="8" BorderBrush="#E5E5E5" BorderThickness="1" Padding="20">
                        <StackPanel>
                            <CheckBox x:Name="ChkAutoDiscover" Content="Automatically attempt switch discovery after import" Margin="0,0,0,8"/>
                            <TextBlock Text="Default documentation URLs" FontSize="13" Foreground="#5C5C5C" Margin="0,8,0,6"/>
                            <TextBox x:Name="TxtDefaultDocUrls" AcceptsReturn="True" Height="80" TextWrapping="Wrap" Padding="10,8"/>
                        </StackPanel>
                    </Border>
                </StackPanel>

            </StackPanel>
        </ScrollViewer>
    </Grid>
</Window>
"@

    $reader = New-Object System.Xml.XmlNodeReader $xaml
    $window = [Windows.Markup.XamlReader]::Load($reader)

    # Apply theme resources
    $themeDict = [Windows.Markup.XamlReader]::Load([System.Xml.XmlReader]::Create([System.IO.StringReader]$themeXaml))
    $window.Resources.MergedDictionaries.Add($themeDict) | Out-Null

    # Initialize fields
    $window.FindName('TxtDownloadLocation').Text = $settings.DownloadLocation
    $window.FindName('TxtHomeDownloadLocation').Text = $settings.DownloadLocation
    $window.FindName('ChkAutoDiscover').IsChecked = [bool]$settings.AutoDiscoverSwitches
    if ($settings.DocumentationUrls.Count -gt 0) {
        $docText = $settings.DocumentationUrls -join [Environment]::NewLine
        $window.FindName('TxtDefaultDocUrls').Text = $docText
        $window.FindName('TxtDocUrls').Text = $docText
    }
    if ($settings.LastInstallerPath -and (Test-Path $settings.LastInstallerPath)) {
        $window.FindName('TxtInstallerPath').Text = $settings.LastInstallerPath
        $window.FindName('TxtSwitchInstallerPath').Text = $settings.LastInstallerPath
    }

    function Show-Page {
        param([string]$PageName)
        foreach ($page in @('PageHome', 'PageInstaller', 'PageSwitches', 'PageSettings')) {
            $window.FindName($page).Visibility = if ($page -eq $PageName) { 'Visible' } else { 'Collapsed' }
        }
    }

    $window.FindName('NavHome').Add_Checked({ Show-Page 'PageHome' })
    $window.FindName('NavInstaller').Add_Checked({ Show-Page 'PageInstaller' })
    $window.FindName('NavSwitches').Add_Checked({
        Show-Page 'PageSwitches'
        $path = $window.FindName('TxtInstallerPath').Text
        if (-not [string]::IsNullOrWhiteSpace($path)) {
            $window.FindName('TxtSwitchInstallerPath').Text = $path
        }
        Update-InstallerStatusPanel -Window $window
    })
    $window.FindName('NavSettings').Add_Checked({ Show-Page 'PageSettings' })

    $window.FindName('BtnBrowseDownloadLocation').Add_Click({
        $selected = Show-FolderBrowserDialog
        if ($selected) {
            $window.FindName('TxtDownloadLocation').Text = $selected
        }
    })

    $window.FindName('BtnSaveSettings').Add_Click({
        try {
            $docUrls = $window.FindName('TxtDefaultDocUrls').Text -split "`r?`n" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
            $updated = Set-AppGetterSettings `
                -DownloadLocation $window.FindName('TxtDownloadLocation').Text `
                -DocumentationUrls $docUrls `
                -AutoDiscoverSwitches ([bool]$window.FindName('ChkAutoDiscover').IsChecked)
            $window.FindName('TxtHomeDownloadLocation').Text = $updated.DownloadLocation
            $window.FindName('TxtDocUrls').Text = ($updated.DocumentationUrls -join [Environment]::NewLine)
            [System.Windows.MessageBox]::Show('Settings saved successfully.', 'AppGetter', 'OK', 'Information') | Out-Null
        } catch {
            [System.Windows.MessageBox]::Show("Failed to save settings: $_", 'AppGetter', 'OK', 'Error') | Out-Null
        }
    })

    $window.FindName('BtnDownload').Add_Click({
        try {
            $url = $window.FindName('TxtDownloadUrl').Text.Trim()
            if ([string]::IsNullOrWhiteSpace($url)) {
                throw 'Enter a download URL first.'
            }
            $imported = Import-InstallerToDownloadLocation -DownloadUrl $url
            $window.FindName('TxtInstallerPath').Text = $imported.Path
            $window.FindName('TxtSwitchInstallerPath').Text = $imported.Path
            if ([bool](Get-AppGetterSettings).AutoDiscoverSwitches) {
                Update-InstallerStatusPanel -Window $window
            }
            [System.Windows.MessageBox]::Show("Installer saved to:`n$($imported.Path)", 'AppGetter', 'OK', 'Information') | Out-Null
        } catch {
            [System.Windows.MessageBox]::Show("Download failed: $_", 'AppGetter', 'OK', 'Error') | Out-Null
        }
    })

    $window.FindName('BtnBrowseInstaller').Add_Click({
        try {
            $localPath = Show-OpenFileDialog
            if (-not $localPath) { return }
            $imported = Import-InstallerToDownloadLocation -LocalFilePath $localPath
            $window.FindName('TxtInstallerPath').Text = $imported.Path
            $window.FindName('TxtSwitchInstallerPath').Text = $imported.Path
            if ([bool](Get-AppGetterSettings).AutoDiscoverSwitches) {
                Update-InstallerStatusPanel -Window $window
            }
            [System.Windows.MessageBox]::Show("Installer imported to:`n$($imported.Path)", 'AppGetter', 'OK', 'Information') | Out-Null
        } catch {
            [System.Windows.MessageBox]::Show("Import failed: $_", 'AppGetter', 'OK', 'Error') | Out-Null
        }
    })

    $window.FindName('BtnUseLastInstaller').Add_Click({
        $settings = Get-AppGetterSettings
        if ($settings.LastInstallerPath) {
            $window.FindName('TxtInstallerPath').Text = $settings.LastInstallerPath
            $window.FindName('TxtSwitchInstallerPath').Text = $settings.LastInstallerPath
        }
    })

    $window.FindName('BtnTestSwitches').Add_Click({
        $path = $window.FindName('TxtSwitchInstallerPath').Text.Trim()
        $window.FindName('TxtInstallerPath').Text = $path
        Update-InstallerStatusPanel -Window $window
    })

    $window.FindName('BtnDiscover').Add_Click({
        try {
            $path = $window.FindName('TxtSwitchInstallerPath').Text.Trim()
            if ([string]::IsNullOrWhiteSpace($path) -or -not (Test-Path $path)) {
                throw 'Select a valid installer path first.'
            }
            $docUrls = $window.FindName('TxtDocUrls').Text -split "`r?`n" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
            $discovery = Find-InstallerSilentSwitch -InstallerPath $path -DocumentationUrls $docUrls -SaveResult
            $window.FindName('TxtInstallCommand').Text = $discovery.InstallCommand
            Set-StatusBadge -BadgeBorder $window.FindName('StatusBadgeBorder') -BadgeText $window.FindName('StatusBadgeText') -Status $discovery.Status

            $lines = @(
                "Status: $($discovery.Status)",
                "Confidence: $($discovery.Confidence)",
                "Method: $($discovery.Method)",
                "Help probes run: $($discovery.HelpProbeCount)",
                '',
                'Recommended command:',
                $discovery.InstallCommand,
                '',
                'Evidence:'
            )
            $lines += $discovery.Evidence
            $window.FindName('TxtAnalysisResult').Text = ($lines -join [Environment]::NewLine)
            [System.Windows.MessageBox]::Show('Switch discovery completed.', 'AppGetter', 'OK', 'Information') | Out-Null
        } catch {
            [System.Windows.MessageBox]::Show("Discovery failed: $_", 'AppGetter', 'OK', 'Error') | Out-Null
        }
    })

    $window.FindName('BtnSaveCommand').Add_Click({
        try {
            $path = $window.FindName('TxtSwitchInstallerPath').Text.Trim()
            $command = $window.FindName('TxtInstallCommand').Text.Trim()
            if ([string]::IsNullOrWhiteSpace($path) -or -not (Test-Path $path)) {
                throw 'Select a valid installer path first.'
            }
            if ([string]::IsNullOrWhiteSpace($command)) {
                throw 'Install command is empty.'
            }
            Save-InstallerSwitchResult -InstallerPath $path -InstallCommand $command -Source 'UI' -Confidence 'High' | Out-Null
            [System.Windows.MessageBox]::Show('Install command saved for future reuse.', 'AppGetter', 'OK', 'Information') | Out-Null
        } catch {
            [System.Windows.MessageBox]::Show("Save failed: $_", 'AppGetter', 'OK', 'Error') | Out-Null
        }
    })

    return $window
}

$window = Show-AppGetterWindow
[void]$window.ShowDialog()
