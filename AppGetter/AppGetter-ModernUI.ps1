<#
.SYNOPSIS
    Windows 11 style GUI wrapper for AppGetter backend.
.DESCRIPTION
    Collects AppGetter inputs in a modern WPF UI and invokes Create-IntuneWinFromWeb.ps1.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$BackendScriptPath = (Join-Path $PSScriptRoot "Create-IntuneWinFromWeb.ps1")
)

if (-not (Test-Path $BackendScriptPath)) {
    throw "Backend script not found: $BackendScriptPath"
}

Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase
Add-Type -AssemblyName System.Windows.Forms

[xml]$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="AppGetter - Modern Packager"
        Width="1180"
        Height="860"
        Background="#F3F6FB"
        WindowStartupLocation="CenterScreen"
        FontFamily="Segoe UI"
        ResizeMode="CanResize">
    <Grid Margin="18">
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
            <RowDefinition Height="220"/>
            <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>

        <Border Grid.Row="0" Background="White" CornerRadius="16" Padding="20" Margin="0,0,0,14">
            <StackPanel>
                <TextBlock Text="AppGetter" FontSize="28" FontWeight="SemiBold" Foreground="#1A1F36"/>
                <TextBlock Text="Intune package creation with download-location targeting and silent-switch intelligence"
                           Margin="0,8,0,0" Foreground="#4A5568" FontSize="13"/>
            </StackPanel>
        </Border>

        <Border Grid.Row="1" Background="White" CornerRadius="16" Padding="18" Margin="0,0,0,14">
            <ScrollViewer VerticalScrollBarVisibility="Auto">
                <Grid>
                    <Grid.ColumnDefinitions>
                        <ColumnDefinition Width="180"/>
                        <ColumnDefinition Width="*"/>
                        <ColumnDefinition Width="160"/>
                    </Grid.ColumnDefinitions>
                    <Grid.RowDefinitions>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="Auto"/>
                    </Grid.RowDefinitions>

                    <TextBlock Grid.Row="0" Grid.Column="0" Text="Application Name" Margin="0,8,10,8" VerticalAlignment="Center" FontWeight="SemiBold"/>
                    <TextBox x:Name="AppNameBox" Grid.Row="0" Grid.Column="1" Grid.ColumnSpan="2" Margin="0,6,0,6" Height="34" Padding="10,6"/>

                    <TextBlock Grid.Row="1" Grid.Column="0" Text="Website URL" Margin="0,8,10,8" VerticalAlignment="Center"/>
                    <TextBox x:Name="WebsiteUrlBox" Grid.Row="1" Grid.Column="1" Grid.ColumnSpan="2" Margin="0,6,0,6" Height="34" Padding="10,6"/>

                    <TextBlock Grid.Row="2" Grid.Column="0" Text="Direct Download URL" Margin="0,8,10,8" VerticalAlignment="Center"/>
                    <TextBox x:Name="DownloadUrlBox" Grid.Row="2" Grid.Column="1" Grid.ColumnSpan="2" Margin="0,6,0,6" Height="34" Padding="10,6"/>

                    <TextBlock Grid.Row="3" Grid.Column="0" Text="Local Installer File" Margin="0,8,10,8" VerticalAlignment="Center"/>
                    <TextBox x:Name="LocalInstallerBox" Grid.Row="3" Grid.Column="1" Margin="0,6,10,6" Height="34" Padding="10,6"/>
                    <Button x:Name="BrowseInstallerButton" Grid.Row="3" Grid.Column="2" Content="Browse..." Height="34" Margin="0,6,0,6"/>

                    <TextBlock Grid.Row="4" Grid.Column="0" Text="Download Location" Margin="0,8,10,8" VerticalAlignment="Center"/>
                    <TextBox x:Name="DownloadDirectoryBox" Grid.Row="4" Grid.Column="1" Margin="0,6,10,6" Height="34" Padding="10,6"/>
                    <Button x:Name="BrowseDownloadDirButton" Grid.Row="4" Grid.Column="2" Content="Browse..." Height="34" Margin="0,6,0,6"/>

                    <TextBlock Grid.Row="5" Grid.Column="0" Text="Output Path" Margin="0,8,10,8" VerticalAlignment="Center"/>
                    <TextBox x:Name="OutputPathBox" Grid.Row="5" Grid.Column="1" Margin="0,6,10,6" Height="34" Padding="10,6" Text="D:\Intoon In Progress"/>
                    <Button x:Name="BrowseOutputButton" Grid.Row="5" Grid.Column="2" Content="Browse..." Height="34" Margin="0,6,0,6"/>

                    <TextBlock Grid.Row="6" Grid.Column="0" Text="Publisher" Margin="0,8,10,8" VerticalAlignment="Center"/>
                    <TextBox x:Name="PublisherBox" Grid.Row="6" Grid.Column="1" Grid.ColumnSpan="2" Margin="0,6,0,6" Height="34" Padding="10,6"/>

                    <TextBlock Grid.Row="7" Grid.Column="0" Text="Version" Margin="0,8,10,8" VerticalAlignment="Center"/>
                    <TextBox x:Name="VersionBox" Grid.Row="7" Grid.Column="1" Grid.ColumnSpan="2" Margin="0,6,0,6" Height="34" Padding="10,6"/>

                    <TextBlock Grid.Row="8" Grid.Column="0" Text="Developer URL" Margin="0,8,10,8" VerticalAlignment="Center"/>
                    <TextBox x:Name="DeveloperUrlBox" Grid.Row="8" Grid.Column="1" Grid.ColumnSpan="2" Margin="0,6,0,6" Height="34" Padding="10,6"/>

                    <TextBlock Grid.Row="9" Grid.Column="0" Text="Support URL" Margin="0,8,10,8" VerticalAlignment="Center"/>
                    <TextBox x:Name="SupportUrlBox" Grid.Row="9" Grid.Column="1" Grid.ColumnSpan="2" Margin="0,6,0,6" Height="34" Padding="10,6"/>

                    <TextBlock Grid.Row="10" Grid.Column="0" Text="Custom Install Command" Margin="0,8,10,8" VerticalAlignment="Center"/>
                    <TextBox x:Name="InstallCommandBox" Grid.Row="10" Grid.Column="1" Grid.ColumnSpan="2" Margin="0,6,0,6" Height="34" Padding="10,6"/>
                </Grid>
            </ScrollViewer>
        </Border>

        <Border Grid.Row="2" Background="White" CornerRadius="16" Padding="16" Margin="0,0,0,14">
            <Grid>
                <Grid.RowDefinitions>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="*"/>
                </Grid.RowDefinitions>
                <StackPanel Orientation="Horizontal">
                    <CheckBox x:Name="DisableResearchCheck" Content="Disable web research for silent switches" Margin="0,0,22,0"/>
                    <CheckBox x:Name="DisableTestingCheck" Content="Disable help-probe switch testing"/>
                </StackPanel>
                <TextBox x:Name="LogBox"
                         Grid.Row="1"
                         Margin="0,12,0,0"
                         IsReadOnly="True"
                         TextWrapping="Wrap"
                         AcceptsReturn="True"
                         VerticalScrollBarVisibility="Auto"
                         HorizontalScrollBarVisibility="Auto"
                         Background="#0F172A"
                         Foreground="#D1FAE5"
                         FontFamily="Consolas"/>
            </Grid>
        </Border>

        <StackPanel Grid.Row="3" Orientation="Horizontal" HorizontalAlignment="Right">
            <Button x:Name="RunButton"
                    Content="Create Package"
                    Width="170"
                    Height="42"
                    Background="#0078D4"
                    Foreground="White"
                    FontWeight="SemiBold"
                    BorderThickness="0"
                    Margin="0,0,10,0"/>
            <Button x:Name="CloseButton" Content="Close" Width="110" Height="42"/>
        </StackPanel>
    </Grid>
</Window>
"@

$reader = New-Object System.Xml.XmlNodeReader $xaml
$window = [Windows.Markup.XamlReader]::Load($reader)

function Get-Control {
    param([string]$Name)
    return $window.FindName($Name)
}

$appNameBox = Get-Control "AppNameBox"
$websiteUrlBox = Get-Control "WebsiteUrlBox"
$downloadUrlBox = Get-Control "DownloadUrlBox"
$localInstallerBox = Get-Control "LocalInstallerBox"
$downloadDirectoryBox = Get-Control "DownloadDirectoryBox"
$outputPathBox = Get-Control "OutputPathBox"
$publisherBox = Get-Control "PublisherBox"
$versionBox = Get-Control "VersionBox"
$developerUrlBox = Get-Control "DeveloperUrlBox"
$supportUrlBox = Get-Control "SupportUrlBox"
$installCommandBox = Get-Control "InstallCommandBox"
$disableResearchCheck = Get-Control "DisableResearchCheck"
$disableTestingCheck = Get-Control "DisableTestingCheck"
$logBox = Get-Control "LogBox"
$browseInstallerButton = Get-Control "BrowseInstallerButton"
$browseDownloadDirButton = Get-Control "BrowseDownloadDirButton"
$browseOutputButton = Get-Control "BrowseOutputButton"
$runButton = Get-Control "RunButton"
$closeButton = Get-Control "CloseButton"

function Add-LogLine {
    param([string]$Message)
    $timestamp = Get-Date -Format "HH:mm:ss"
    $logBox.AppendText("[$timestamp] $Message`r`n")
    $logBox.ScrollToEnd()
}

function Quote-Argument {
    param([string]$Value)
    if ([string]::IsNullOrWhiteSpace($Value)) {
        return '""'
    }
    return '"' + ($Value.Replace('"', '\"')) + '"'
}

function Select-FolderPath {
    $dialog = New-Object System.Windows.Forms.FolderBrowserDialog
    $dialog.ShowNewFolderButton = $true
    if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        return $dialog.SelectedPath
    }
    return $null
}

$browseInstallerButton.Add_Click({
    $dialog = New-Object System.Windows.Forms.OpenFileDialog
    $dialog.Filter = "Installer files|*.exe;*.msi;*.msix;*.appx;*.zip;*.7z|All files|*.*"
    if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        $localInstallerBox.Text = $dialog.FileName
    }
})

$browseDownloadDirButton.Add_Click({
    $selected = Select-FolderPath
    if ($selected) {
        $downloadDirectoryBox.Text = $selected
    }
})

$browseOutputButton.Add_Click({
    $selected = Select-FolderPath
    if ($selected) {
        $outputPathBox.Text = $selected
    }
})

$closeButton.Add_Click({ $window.Close() })

$runButton.Add_Click({
    if ([string]::IsNullOrWhiteSpace($appNameBox.Text)) {
        [System.Windows.MessageBox]::Show("Application Name is required.", "Validation", "OK", "Warning") | Out-Null
        return
    }

    if ([string]::IsNullOrWhiteSpace($websiteUrlBox.Text) -and
        [string]::IsNullOrWhiteSpace($downloadUrlBox.Text) -and
        [string]::IsNullOrWhiteSpace($localInstallerBox.Text)) {
        [System.Windows.MessageBox]::Show("Provide at least one installer source: Website URL, Direct Download URL, or Local Installer File.", "Validation", "OK", "Warning") | Out-Null
        return
    }

    $argumentPairs = [ordered]@{
        AppName = $appNameBox.Text
        WebsiteUrl = $websiteUrlBox.Text
        DownloadUrl = $downloadUrlBox.Text
        LocalInstallerPath = $localInstallerBox.Text
        DownloadDirectory = $downloadDirectoryBox.Text
        OutputPath = $outputPathBox.Text
        Publisher = $publisherBox.Text
        Version = $versionBox.Text
        DeveloperUrl = $developerUrlBox.Text
        SupportUrl = $supportUrlBox.Text
        InstallCommand = $installCommandBox.Text
    }

    $argumentList = @(
        "-NoProfile",
        "-ExecutionPolicy", "Bypass",
        "-File", (Quote-Argument -Value $BackendScriptPath)
    )

    foreach ($key in $argumentPairs.Keys) {
        $value = $argumentPairs[$key]
        if (-not [string]::IsNullOrWhiteSpace($value)) {
            $argumentList += "-$key"
            $argumentList += (Quote-Argument -Value $value)
        }
    }

    if ($disableResearchCheck.IsChecked -eq $true) {
        $argumentList += "-DisableSwitchResearch"
    }
    if ($disableTestingCheck.IsChecked -eq $true) {
        $argumentList += "-DisableSwitchTesting"
    }

    $powershellExe = if (Get-Command powershell.exe -ErrorAction SilentlyContinue) { "powershell.exe" } else { "pwsh.exe" }
    $arguments = $argumentList -join " "

    Add-LogLine "Running backend script..."
    Add-LogLine "$powershellExe $arguments"

    try {
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = $powershellExe
        $psi.Arguments = $arguments
        $psi.UseShellExecute = $false
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError = $true
        $psi.CreateNoWindow = $true

        $process = New-Object System.Diagnostics.Process
        $process.StartInfo = $psi
        [void]$process.Start()
        $stdout = $process.StandardOutput.ReadToEnd()
        $stderr = $process.StandardError.ReadToEnd()
        $process.WaitForExit()

        if (-not [string]::IsNullOrWhiteSpace($stdout)) {
            Add-LogLine $stdout.Trim()
        }
        if (-not [string]::IsNullOrWhiteSpace($stderr)) {
            Add-LogLine ("[stderr] " + $stderr.Trim())
        }

        if ($process.ExitCode -eq 0) {
            Add-LogLine "Package build completed successfully."
            [System.Windows.MessageBox]::Show("Package build completed successfully.", "AppGetter", "OK", "Information") | Out-Null
        } else {
            Add-LogLine "Package build failed with exit code $($process.ExitCode)."
            [System.Windows.MessageBox]::Show("Package build failed. Review log output in the window.", "AppGetter", "OK", "Error") | Out-Null
        }
    } catch {
        Add-LogLine "Execution error: $_"
        [System.Windows.MessageBox]::Show("Failed to start backend process: $_", "AppGetter", "OK", "Error") | Out-Null
    }
})

[void]$window.ShowDialog()
