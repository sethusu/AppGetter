if (-not $IsWindows) {
    Write-Error "AppGetter.UI.ps1 requires Windows PowerShell with WPF support."
    exit 1
}

try {
    Add-Type -AssemblyName PresentationFramework
    Add-Type -AssemblyName PresentationCore
    Add-Type -AssemblyName WindowsBase
    Add-Type -AssemblyName System.Windows.Forms
} catch {
    Write-Error "WPF assemblies could not be loaded. Run this UI on Windows Desktop with .NET/WPF available."
    exit 1
}

$backendModulePath = Join-Path $PSScriptRoot "AppGetter.Backend.psm1"
if (Test-Path -LiteralPath $backendModulePath) {
    Import-Module $backendModulePath -Force
}

$scriptPath = Join-Path $PSScriptRoot "Create-IntuneWinFromWeb.ps1"
if (-not (Test-Path -LiteralPath $scriptPath)) {
    [System.Windows.MessageBox]::Show("Could not find Create-IntuneWinFromWeb.ps1 in $PSScriptRoot", "AppGetter", "OK", "Error") | Out-Null
    exit 1
}

[xml]$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="AppGetter Installer Studio"
        Height="860"
        Width="1220"
        ResizeMode="CanResize"
        WindowStartupLocation="CenterScreen"
        Background="#F4F6FB"
        FontFamily="Segoe UI">
    <Grid Margin="18">
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto" />
            <RowDefinition Height="*" />
            <RowDefinition Height="240" />
            <RowDefinition Height="Auto" />
        </Grid.RowDefinitions>

        <Border Grid.Row="0" Background="#FFFFFF" CornerRadius="14" Padding="18" Margin="0,0,0,14">
            <StackPanel>
                <TextBlock Text="AppGetter Installer Studio" FontSize="30" FontWeight="SemiBold" Foreground="#1F2937" />
                <TextBlock Text="Windows 11 style launcher for source selection, silent switch analysis, and Intune package build." Margin="0,6,0,0" Foreground="#4B5563" FontSize="13"/>
            </StackPanel>
        </Border>

        <Grid Grid.Row="1">
            <Grid.ColumnDefinitions>
                <ColumnDefinition Width="*" />
                <ColumnDefinition Width="*" />
            </Grid.ColumnDefinitions>

            <Border Grid.Column="0" Background="#FFFFFF" CornerRadius="14" Padding="16" Margin="0,0,8,0">
                <StackPanel>
                    <TextBlock Text="Source Inputs" FontSize="18" FontWeight="SemiBold" Foreground="#1F2937" Margin="0,0,0,10"/>
                    <TextBlock Text="Download Location (URL, file path, or folder)" Foreground="#4B5563" />
                    <TextBox x:Name="TxtDownloadLocation" Height="34" Margin="0,4,0,10" BorderBrush="#D1D5DB" Background="#F9FAFB" />

                    <TextBlock Text="Direct Download URL" Foreground="#4B5563" />
                    <TextBox x:Name="TxtDownloadUrl" Height="34" Margin="0,4,0,10" BorderBrush="#D1D5DB" Background="#F9FAFB" />

                    <TextBlock Text="Website URL (for auto-discovery)" Foreground="#4B5563" />
                    <TextBox x:Name="TxtWebsiteUrl" Height="34" Margin="0,4,0,10" BorderBrush="#D1D5DB" Background="#F9FAFB" />

                    <TextBlock Text="Local Installer File" Foreground="#4B5563" />
                    <Grid Margin="0,4,0,0">
                        <Grid.ColumnDefinitions>
                            <ColumnDefinition Width="*" />
                            <ColumnDefinition Width="Auto" />
                        </Grid.ColumnDefinitions>
                        <TextBox x:Name="TxtInstallerPath" Height="34" Margin="0,0,8,0" BorderBrush="#D1D5DB" Background="#F9FAFB" />
                        <Button x:Name="BtnBrowseInstaller" Grid.Column="1" Content="Browse..." Height="34" Padding="14,0" Background="#E5E7EB" BorderBrush="#D1D5DB" />
                    </Grid>
                </StackPanel>
            </Border>

            <Border Grid.Column="1" Background="#FFFFFF" CornerRadius="14" Padding="16" Margin="8,0,0,0">
                <StackPanel>
                    <TextBlock Text="Application Metadata" FontSize="18" FontWeight="SemiBold" Foreground="#1F2937" Margin="0,0,0,10"/>
                    <TextBlock Text="Application Name" Foreground="#4B5563" />
                    <TextBox x:Name="TxtAppName" Height="34" Margin="0,4,0,10" BorderBrush="#D1D5DB" Background="#F9FAFB" />

                    <TextBlock Text="Version (optional)" Foreground="#4B5563" />
                    <TextBox x:Name="TxtVersion" Height="34" Margin="0,4,0,10" BorderBrush="#D1D5DB" Background="#F9FAFB" />

                    <TextBlock Text="Publisher (optional)" Foreground="#4B5563" />
                    <TextBox x:Name="TxtPublisher" Height="34" Margin="0,4,0,10" BorderBrush="#D1D5DB" Background="#F9FAFB" />

                    <TextBlock Text="Developer URL (optional)" Foreground="#4B5563" />
                    <TextBox x:Name="TxtDeveloperUrl" Height="34" Margin="0,4,0,10" BorderBrush="#D1D5DB" Background="#F9FAFB" />

                    <TextBlock Text="Support URL (optional)" Foreground="#4B5563" />
                    <TextBox x:Name="TxtSupportUrl" Height="34" Margin="0,4,0,10" BorderBrush="#D1D5DB" Background="#F9FAFB" />

                    <TextBlock Text="Output Path" Foreground="#4B5563" />
                    <Grid Margin="0,4,0,0">
                        <Grid.ColumnDefinitions>
                            <ColumnDefinition Width="*" />
                            <ColumnDefinition Width="Auto" />
                        </Grid.ColumnDefinitions>
                        <TextBox x:Name="TxtOutputPath" Height="34" Margin="0,0,8,0" BorderBrush="#D1D5DB" Background="#F9FAFB" Text="D:\Intoon In Progress" />
                        <Button x:Name="BtnBrowseOutput" Grid.Column="1" Content="Browse..." Height="34" Padding="14,0" Background="#E5E7EB" BorderBrush="#D1D5DB" />
                    </Grid>
                </StackPanel>
            </Border>
        </Grid>

        <Border Grid.Row="2" Background="#FFFFFF" CornerRadius="14" Padding="14" Margin="0,14,0,0">
            <Grid>
                <Grid.RowDefinitions>
                    <RowDefinition Height="Auto" />
                    <RowDefinition Height="*" />
                </Grid.RowDefinitions>
                <TextBlock Text="Execution Log" FontSize="16" FontWeight="SemiBold" Foreground="#1F2937" />
                <TextBox x:Name="TxtLog" Grid.Row="1" Margin="0,10,0,0" IsReadOnly="True" VerticalScrollBarVisibility="Auto" TextWrapping="Wrap" Background="#111827" Foreground="#E5E7EB" BorderBrush="#111827" FontFamily="Consolas" FontSize="12"/>
            </Grid>
        </Border>

        <Grid Grid.Row="3" Margin="0,14,0,0">
            <Grid.ColumnDefinitions>
                <ColumnDefinition Width="Auto" />
                <ColumnDefinition Width="Auto" />
                <ColumnDefinition Width="*" />
            </Grid.ColumnDefinitions>
            <Button x:Name="BtnAnalyze" Content="Analyze Silent Switches" Height="40" Padding="18,0" Margin="0,0,12,0" Background="#E0EAFF" Foreground="#1E40AF" BorderBrush="#BFDBFE" />
            <Button x:Name="BtnBuild" Grid.Column="1" Content="Build Package" Height="40" Padding="18,0" Background="#2563EB" Foreground="White" BorderBrush="#1D4ED8" />
            <TextBlock x:Name="TxtStatus" Grid.Column="2" VerticalAlignment="Center" TextAlignment="Right" Foreground="#374151" FontSize="13" />
        </Grid>
    </Grid>
</Window>
"@

$reader = New-Object System.Xml.XmlNodeReader $xaml
$window = [Windows.Markup.XamlReader]::Load($reader)

function Find-Control {
    param([string]$Name)
    return $window.FindName($Name)
}

$txtDownloadLocation = Find-Control "TxtDownloadLocation"
$txtDownloadUrl = Find-Control "TxtDownloadUrl"
$txtWebsiteUrl = Find-Control "TxtWebsiteUrl"
$txtInstallerPath = Find-Control "TxtInstallerPath"
$txtAppName = Find-Control "TxtAppName"
$txtVersion = Find-Control "TxtVersion"
$txtPublisher = Find-Control "TxtPublisher"
$txtDeveloperUrl = Find-Control "TxtDeveloperUrl"
$txtSupportUrl = Find-Control "TxtSupportUrl"
$txtOutputPath = Find-Control "TxtOutputPath"
$txtLog = Find-Control "TxtLog"
$txtStatus = Find-Control "TxtStatus"
$btnBrowseInstaller = Find-Control "BtnBrowseInstaller"
$btnBrowseOutput = Find-Control "BtnBrowseOutput"
$btnAnalyze = Find-Control "BtnAnalyze"
$btnBuild = Find-Control "BtnBuild"

function Add-Log {
    param([string]$Message)
    if ([string]::IsNullOrWhiteSpace($Message)) {
        return
    }

    $txtLog.AppendText("$Message`r`n")
    $txtLog.ScrollToEnd()
}

function Resolve-InstallerCandidatePath {
    if (-not [string]::IsNullOrWhiteSpace($txtInstallerPath.Text) -and (Test-Path -LiteralPath $txtInstallerPath.Text)) {
        return $txtInstallerPath.Text
    }

    if (-not [string]::IsNullOrWhiteSpace($txtDownloadLocation.Text)) {
        $resolved = Resolve-AppGetterDownloadLocation -DownloadLocation $txtDownloadLocation.Text
        if ($resolved.InstallerPath) {
            return $resolved.InstallerPath
        }
    }

    return $null
}

$btnBrowseInstaller.Add_Click({
    $dialog = New-Object System.Windows.Forms.OpenFileDialog
    $dialog.Filter = "Installer files (*.exe;*.msi;*.msix;*.appx)|*.exe;*.msi;*.msix;*.appx|All files (*.*)|*.*"
    if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        $txtInstallerPath.Text = $dialog.FileName
    }
})

$btnBrowseOutput.Add_Click({
    $dialog = New-Object System.Windows.Forms.FolderBrowserDialog
    if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        $txtOutputPath.Text = $dialog.SelectedPath
    }
})

$btnAnalyze.Add_Click({
    $installerCandidate = Resolve-InstallerCandidatePath
    if (-not $installerCandidate) {
        [System.Windows.MessageBox]::Show("Provide an installer file path or a valid download location containing an installer.", "AppGetter") | Out-Null
        return
    }

    $installerFileName = [System.IO.Path]::GetFileName($installerCandidate)
    $docs = @($txtSupportUrl.Text, $txtDeveloperUrl.Text, $txtWebsiteUrl.Text) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique

    Add-Log "Analyzing installer: $installerCandidate"
    $analysis = Find-AppGetterSilentInstallCommand -InstallerPath $installerCandidate -InstallerFileName $installerFileName -AppName $txtAppName.Text -DocumentationUrls $docs
    Add-Log "Recommended command: $($analysis.InstallCommand)"
    Add-Log "Source: $($analysis.Source) | Confidence: $($analysis.Confidence)"

    if ($analysis.DetectedSwitches.Count -gt 0) {
        Add-Log "Detected switches: $($analysis.DetectedSwitches -join ', ')"
    }

    foreach ($note in $analysis.ResearchNotes) {
        Add-Log "Research note: $note"
    }

    if ($analysis.NeedsManualReview) {
        Add-Log "Manual review recommended before production deployment."
    }
})

$script:currentProcess = $null
$btnBuild.Add_Click({
    if ([string]::IsNullOrWhiteSpace($txtAppName.Text)) {
        [System.Windows.MessageBox]::Show("Application Name is required.", "AppGetter") | Out-Null
        return
    }

    if ($script:currentProcess -and -not $script:currentProcess.HasExited) {
        [System.Windows.MessageBox]::Show("A build is already running.", "AppGetter") | Out-Null
        return
    }

    $argumentParts = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "`"$scriptPath`"")
    if (-not [string]::IsNullOrWhiteSpace($txtWebsiteUrl.Text)) { $argumentParts += @("-WebsiteUrl", "`"$($txtWebsiteUrl.Text)`"") }
    if (-not [string]::IsNullOrWhiteSpace($txtDownloadUrl.Text)) { $argumentParts += @("-DownloadUrl", "`"$($txtDownloadUrl.Text)`"") }
    if (-not [string]::IsNullOrWhiteSpace($txtDownloadLocation.Text)) { $argumentParts += @("-DownloadLocation", "`"$($txtDownloadLocation.Text)`"") }
    if (-not [string]::IsNullOrWhiteSpace($txtInstallerPath.Text)) { $argumentParts += @("-InstallerPath", "`"$($txtInstallerPath.Text)`"") }
    if (-not [string]::IsNullOrWhiteSpace($txtVersion.Text)) { $argumentParts += @("-Version", "`"$($txtVersion.Text)`"") }
    if (-not [string]::IsNullOrWhiteSpace($txtPublisher.Text)) { $argumentParts += @("-Publisher", "`"$($txtPublisher.Text)`"") }
    if (-not [string]::IsNullOrWhiteSpace($txtDeveloperUrl.Text)) { $argumentParts += @("-DeveloperUrl", "`"$($txtDeveloperUrl.Text)`"") }
    if (-not [string]::IsNullOrWhiteSpace($txtSupportUrl.Text)) { $argumentParts += @("-SupportUrl", "`"$($txtSupportUrl.Text)`"") }
    if (-not [string]::IsNullOrWhiteSpace($txtOutputPath.Text)) { $argumentParts += @("-OutputPath", "`"$($txtOutputPath.Text)`"") }
    $argumentParts += @("-AppName", "`"$($txtAppName.Text)`"")

    $arguments = $argumentParts -join " "
    Add-Log "Executing: powershell.exe $arguments"

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = "powershell.exe"
    $psi.Arguments = $arguments
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true

    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $psi
    $process.EnableRaisingEvents = $true
    $script:currentProcess = $process
    $txtStatus.Text = "Build running..."

    $outputHandler = {
        param($sender, $eventArgs)
        if ($eventArgs.Data) {
            $window.Dispatcher.Invoke([Action]{
                Add-Log $eventArgs.Data
            })
        }
    }.GetNewClosure()

    $errorHandler = {
        param($sender, $eventArgs)
        if ($eventArgs.Data) {
            $window.Dispatcher.Invoke([Action]{
                Add-Log "[stderr] $($eventArgs.Data)"
            })
        }
    }.GetNewClosure()

    $exitHandler = {
        $window.Dispatcher.Invoke([Action]{
            $txtStatus.Text = "Build finished (see log)."
            Add-Log "Process exit code: $($script:currentProcess.ExitCode)"
        })
    }.GetNewClosure()

    $process.add_OutputDataReceived($outputHandler)
    $process.add_ErrorDataReceived($errorHandler)
    $process.add_Exited($exitHandler)

    [void]$process.Start()
    $process.BeginOutputReadLine()
    $process.BeginErrorReadLine()
})

$txtStatus.Text = "Ready."
[void]$window.ShowDialog()
