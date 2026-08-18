<#
.SYNOPSIS
    Launches the AppGetter graphical user interface.
.DESCRIPTION
    WPF-based GUI aligned with Wingetter: installer source (URL or local file),
    output destination picker, live packaging progress, Content Prep Tool checks,
    and icon preview.
.EXAMPLE
    .\Start-AppGetterGui.ps1
#>

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase
Add-Type -AssemblyName System.Windows.Forms

try {
    [System.Windows.Forms.Application]::EnableVisualStyles()
} catch {
    # Non-fatal.
}

$moduleRoot = Split-Path -Parent $PSScriptRoot
$modulePath = Join-Path $moduleRoot 'AppGetter.psd1'
Import-Module $modulePath -Force

$brushConverter = New-Object System.Windows.Media.BrushConverter

function ConvertTo-WpfBrush {
    param([string]$Color)
    return $brushConverter.ConvertFromString($Color)
}

function New-WpfThickness {
    param(
        [double]$Left = 0,
        [double]$Top = 0,
        [double]$Right = 0,
        [double]$Bottom = 0
    )
    return New-Object System.Windows.Thickness($Left, $Top, $Right, $Bottom)
}

function Read-XamlWindow {
    param([string]$XamlPath)
    $xaml = Get-Content -Path $XamlPath -Raw
    $reader = New-Object System.Xml.XmlNodeReader ([xml]$xaml)
    return [Windows.Markup.XamlReader]::Load($reader)
}

function Get-WinFormsOwnerWindow {
    param($OwnerWindow)

    if (-not $OwnerWindow) { return $null }

    try {
        $helper = New-Object System.Windows.Interop.WindowInteropHelper($OwnerWindow)
        $null = $helper.EnsureHandle()
        if ($helper.Handle -eq [IntPtr]::Zero) { return $null }

        $owner = New-Object System.Windows.Forms.NativeWindow
        $owner.AssignHandle($helper.Handle)
        return $owner
    } catch {
        return $null
    }
}

function Show-FolderBrowser {
    param(
        [string]$Description,
        [string]$SelectedPath,
        $OwnerWindow = $null
    )

    $dialog = New-Object System.Windows.Forms.FolderBrowserDialog
    $dialog.Description = $Description
    $dialog.ShowNewFolderButton = $true
    $dialog.RootFolder = [Environment+SpecialFolder]::MyComputer

    if ($SelectedPath) {
        try {
            $candidate = [System.IO.Path]::GetFullPath($SelectedPath)
            if (Test-Path -LiteralPath $candidate) {
                $dialog.SelectedPath = $candidate
            }
        } catch { }
    }

    $owner = Get-WinFormsOwnerWindow -OwnerWindow $OwnerWindow
    $chosenPath = $null
    try {
        $result = if ($owner) { $dialog.ShowDialog($owner) } else { $dialog.ShowDialog() }
        if ($result -eq [System.Windows.Forms.DialogResult]::OK) {
            $chosenPath = $dialog.SelectedPath
        }
    } finally {
        if ($owner) { try { $owner.ReleaseHandle() } catch { } }
        $dialog.Dispose()
    }

    return $chosenPath
}

function Show-OpenFileDialog {
    param(
        [string]$Filter = 'PNG images (*.png)|*.png|All files (*.*)|*.*',
        $OwnerWindow = $null
    )

    $dialog = New-Object System.Windows.Forms.OpenFileDialog
    $dialog.Filter = $Filter
    $dialog.CheckFileExists = $true
    $dialog.Multiselect = $false

    $owner = Get-WinFormsOwnerWindow -OwnerWindow $OwnerWindow
    $chosenPath = $null
    try {
        $result = if ($owner) { $dialog.ShowDialog($owner) } else { $dialog.ShowDialog() }
        if ($result -eq [System.Windows.Forms.DialogResult]::OK) {
            $chosenPath = $dialog.FileName
        }
    } finally {
        if ($owner) { try { $owner.ReleaseHandle() } catch { } }
        $dialog.Dispose()
    }

    return $chosenPath
}

function Show-InstallerFileDialog {
    param($OwnerWindow = $null)

    return Show-OpenFileDialog -Filter 'Installers (*.exe;*.msi;*.msix;*.appx)|*.exe;*.msi;*.msix;*.appx|All files (*.*)|*.*' -OwnerWindow $OwnerWindow
}

function Set-IconPreview {
    param(
        $ImageControl,
        $StatusControl,
        [string]$ImagePath
    )

    if ($ImagePath -and (Test-Path -LiteralPath $ImagePath)) {
        try {
            $bitmap = New-Object System.Windows.Media.Imaging.BitmapImage
            $bitmap.BeginInit()
            $bitmap.CacheOption = [System.Windows.Media.Imaging.BitmapCacheOption]::OnLoad
            $bitmap.UriSource = [Uri]::new((Resolve-Path -LiteralPath $ImagePath).Path)
            $bitmap.EndInit()
            $bitmap.Freeze()
            $ImageControl.Source = $bitmap
            $StatusControl.Text = [System.IO.Path]::GetFileName($ImagePath)
            return
        } catch {
            $StatusControl.Text = "Could not load icon: $_"
        }
    }

    $ImageControl.Source = $null
}

function New-WpfBitmapImage {
    param([string]$ImagePath)

    $bitmap = New-Object System.Windows.Media.Imaging.BitmapImage
    $bitmap.BeginInit()
    $bitmap.CacheOption = [System.Windows.Media.Imaging.BitmapCacheOption]::OnLoad
    $bitmap.UriSource = [Uri]::new((Resolve-Path -LiteralPath $ImagePath).Path)
    $bitmap.EndInit()
    $bitmap.Freeze()
    return $bitmap
}

function Show-AppGetterIconPickerDialog {
    param(
        [array]$Candidates,
        [string]$DisplayName,
        [string]$PackageId,
        $OwnerWindow
    )

    if (-not $Candidates -or $Candidates.Count -lt 2) { return $null }

    $dialogPath = Join-Path $PSScriptRoot 'AppGetter.IconPickerDialog.xaml'
    $dialogWindow = Read-XamlWindow -XamlPath $dialogPath
    $dialogWindow.Owner = $OwnerWindow

    $summary = $dialogWindow.FindName('IconSummaryText')
    $panel = $dialogWindow.FindName('CandidatesPanel')
    $useButton = $dialogWindow.FindName('UseSelectedButton')
    $keepButton = $dialogWindow.FindName('KeepCurrentButton')

    $summary.Text = "Packaging finished for $DisplayName ($PackageId). Pick the icon that best represents this app for Intune upload."

    $selection = @{ Candidate = $Candidates[0] }
    $firstRadio = $null

    foreach ($candidate in $Candidates) {
        $card = New-Object System.Windows.Controls.Border
        $card.Width = 210
        $card.Margin = New-WpfThickness -Left 6 -Right 6
        $card.Padding = New-WpfThickness -Left 10 -Top 10 -Right 10 -Bottom 10
        $card.CornerRadius = New-Object System.Windows.CornerRadius(8)
        $card.BorderBrush = ConvertTo-WpfBrush '#D8DEE9'
        $card.BorderThickness = New-WpfThickness -Left 1 -Top 1 -Right 1 -Bottom 1
        $card.Background = [System.Windows.Media.Brushes]::White

        $stack = New-Object System.Windows.Controls.StackPanel
        $stack.HorizontalAlignment = [System.Windows.HorizontalAlignment]::Center

        $radio = New-Object System.Windows.Controls.RadioButton
        $radio.GroupName = 'AppGetterIconSelection'
        $radio.Content = if ($candidate.Label) { $candidate.Label } else { 'Option' }
        $radio.FontWeight = [System.Windows.FontWeights]::SemiBold
        $radio.HorizontalAlignment = [System.Windows.HorizontalAlignment]::Center
        $radio.Margin = New-WpfThickness -Bottom 8
        $radio.Tag = $candidate

        $capturedCandidate = $candidate
        $radio.Add_Checked({ $selection.Candidate = $capturedCandidate })

        if (-not $firstRadio) {
            $firstRadio = $radio
            $selection.Candidate = $candidate
        }

        $image = New-Object System.Windows.Controls.Image
        $image.Width = 128
        $image.Height = 128
        $image.Stretch = [System.Windows.Media.Stretch]::Uniform
        $image.Margin = New-WpfThickness -Bottom 8
        if ($candidate.Path -and (Test-Path -LiteralPath $candidate.Path)) {
            try {
                $image.Source = New-WpfBitmapImage -ImagePath $candidate.Path
            } catch {
                $image.Source = $null
            }
        }

        $sourceText = New-Object System.Windows.Controls.TextBlock
        $sourceText.Text = "Source: $($candidate.Source)"
        $sourceText.Foreground = ConvertTo-WpfBrush '#5C6B7A'
        $sourceText.FontSize = 12
        $sourceText.TextAlignment = [System.Windows.TextAlignment]::Center
        $sourceText.Margin = New-WpfThickness -Bottom 4

        $stack.Children.Add($radio) | Out-Null
        $stack.Children.Add($image) | Out-Null
        $stack.Children.Add($sourceText) | Out-Null
        $card.Child = $stack
        $panel.Children.Add($card) | Out-Null
    }

    if ($firstRadio) { $firstRadio.IsChecked = $true }

    $useButton.Add_Click({
        if ($selection.Candidate) {
            $dialogWindow.Tag = $selection.Candidate
            $dialogWindow.DialogResult = $true
            $dialogWindow.Close()
        }
    })

    $keepButton.Add_Click({
        $dialogWindow.Tag = $null
        $dialogWindow.DialogResult = $false
        $dialogWindow.Close()
    })

    if ($dialogWindow.ShowDialog()) {
        return $dialogWindow.Tag
    }
    return $null
}

function Add-LogLine {
    param(
        $LogControl,
        [string]$Message
    )
    $timestamp = Get-Date -Format 'HH:mm:ss'
    $LogControl.AppendText("[$timestamp] $Message`r`n")
    $LogControl.ScrollToEnd()
}

$script:StepLabels = @(
    'Load package details'
    'Create output directories'
    'Resolve installer source'
    'Acquire installer file'
    'Calculate installer hash'
    'Discover silent install switches'
    'Generate install.ps1'
    'Generate detection.ps1'
    'Generate uninstall.ps1'
    'Resolve application icon'
    'Write metadata and README.md'
    'Create .intunewin package'
    'Finalize output'
)

$script:StepStates = @('Pending') * $script:StepLabels.Count

function Initialize-StepList {
    param($ListControl)
    $script:StepStates = @('Pending') * $script:StepLabels.Count
    $ListControl.Items.Clear()
    for ($i = 0; $i -lt $script:StepLabels.Count; $i++) {
        $ListControl.Items.Add((New-StepListItem -Index $i)) | Out-Null
    }
}

function Get-StepIcon {
    param([string]$State)
    switch ($State) {
        'Running' { return [char]0x25B6 }
        'Completed' { return [char]0x2713 }
        'Failed' { return [char]0x2717 }
        default { return [char]0x25CB }
    }
}

function New-StepListItem {
    param([int]$Index)
    return [PSCustomObject]@{
        Icon = Get-StepIcon $script:StepStates[$Index]
        Text = $script:StepLabels[$Index]
    }
}

function Update-StepList {
    param(
        $ListControl,
        [int]$StepIndex,
        [ValidateSet('Pending', 'Running', 'Completed', 'Failed')]
        [string]$State
    )

    if ($StepIndex -lt 0 -or $StepIndex -ge $script:StepStates.Count) { return }

    $script:StepStates[$StepIndex] = $State
    $ListControl.Items[$StepIndex] = New-StepListItem -Index $StepIndex
}

function Invoke-UiProgressUpdate {
    param(
        $Event,
        $ProgressBar,
        $ProgressStatus,
        $StepList,
        $LogText,
        $StepMap
    )

    if ($Event.Type -eq 'Progress') {
        if ($Event.Percent -ge 0) {
            $ProgressBar.Value = [math]::Min(100, $Event.Percent)
        }
        if ($Event.Message) {
            $ProgressStatus.Text = "$($Event.StepName): $($Event.Message)"
        } else {
            $ProgressStatus.Text = $Event.StepName
        }

        if ($StepMap.ContainsKey($Event.Step)) {
            $index = $StepMap[$Event.Step]
            for ($i = 0; $i -lt $index; $i++) {
                if ($script:StepStates[$i] -ne 'Failed') {
                    Update-StepList -ListControl $StepList -StepIndex $i -State Completed
                }
            }
            if ($Event.Status -eq 'Completed') {
                Update-StepList -ListControl $StepList -StepIndex $index -State Completed
            } elseif ($Event.Status -eq 'Failed') {
                Update-StepList -ListControl $StepList -StepIndex $index -State Failed
            } else {
                Update-StepList -ListControl $StepList -StepIndex $index -State Running
            }
        }

        if ($Event.Message) {
            Add-LogLine -LogControl $LogText -Message "$($Event.StepName) - $($Event.Message)"
        } else {
            Add-LogLine -LogControl $LogText -Message $Event.StepName
        }
    } elseif ($Event.Message) {
        Add-LogLine -LogControl $LogText -Message $Event.Message
    }
}

function Start-AppGetterBackgroundPackaging {
    param(
        [hashtable]$PackArguments,
        [System.Collections.Concurrent.ConcurrentQueue[object]]$ProgressQueue
    )

    $runspace = [runspacefactory]::CreateRunspace()
    $runspace.Open()
    $powershell = [powershell]::Create()
    $powershell.Runspace = $runspace

    $null = $powershell.AddScript({
        param($ModulePath, $PackArgs, $Queue)
        Import-Module $ModulePath -Force
        $onProgress = {
            param($Event)
            $null = $Queue.Enqueue($Event)
        }
        $PackArgs.OnProgress = $onProgress
        Invoke-AppGetterPackaging @PackArgs
    }).AddArgument($modulePath).AddArgument($PackArguments).AddArgument($ProgressQueue)

    return @{
        PowerShell = $powershell
        Runspace = $runspace
        AsyncResult = $powershell.BeginInvoke()
    }
}

# Main window
$mainXamlPath = Join-Path $PSScriptRoot 'AppGetter.MainWindow.xaml'
$window = Read-XamlWindow -XamlPath $mainXamlPath

$prereqText = $window.FindName('PrereqStatusText')
$installContentPrepButton = $window.FindName('InstallContentPrepButton')
$appNameBox = $window.FindName('AppNameBox')
$publisherBox = $window.FindName('PublisherBox')
$sourceUrlRadio = $window.FindName('SourceUrlRadio')
$sourceLocalRadio = $window.FindName('SourceLocalRadio')
$urlSourcePanel = $window.FindName('UrlSourcePanel')
$localSourcePanel = $window.FindName('LocalSourcePanel')
$websiteUrlBox = $window.FindName('WebsiteUrlBox')
$downloadUrlBox = $window.FindName('DownloadUrlBox')
$localInstallerBox = $window.FindName('LocalInstallerBox')
$browseInstallerButton = $window.FindName('BrowseInstallerButton')
$selectedSourceText = $window.FindName('SelectedSourceText')
$outputPathBox = $window.FindName('OutputPathBox')
$browseOutputButton = $window.FindName('BrowseOutputButton')
$versionBox = $window.FindName('VersionBox')
$progressBar = $window.FindName('ProgressBar')
$progressStatus = $window.FindName('ProgressStatusText')
$stepList = $window.FindName('StepList')
$logText = $window.FindName('LogTextBox')
$iconPreview = $window.FindName('IconPreview')
$iconStatus = $window.FindName('IconStatusText')
$browseIconButton = $window.FindName('BrowseIconButton')
$openOutputButton = $window.FindName('OpenOutputButton')
$packButton = $window.FindName('PackButton')

$script:customIconPath = $null
$script:lastOutputDirectory = $null
$script:isRunning = $false
$script:packTimer = $null
$script:packWorker = $null
$script:progressQueue = $null
$script:contentPrepInstallJob = $null
$script:contentPrepInstallTimer = $null
$script:useLocalInstaller = $false

$stepMap = @{
    1 = 0; 2 = 1; 3 = 2; 4 = 3; 5 = 4; 6 = 5; 7 = 6; 8 = 7; 9 = 8; 10 = 9; 11 = 10; 12 = 11; 13 = 12
}

$settings = Get-AppGetterSettings
$script:baseOutputPath = Get-AppGetterBaseOutputPath -Path $settings.OutputPath -PackageId $settings.LastPackageId
$outputPathBox.Text = $script:baseOutputPath
$appNameBox.Text = $settings.LastAppName
$websiteUrlBox.Text = $settings.LastWebsiteUrl
$downloadUrlBox.Text = $settings.LastDownloadUrl
$localInstallerBox.Text = $settings.LastLocalInstallerPath

if ($settings.LastLocalInstallerPath -and (Test-Path -LiteralPath $settings.LastLocalInstallerPath)) {
    $sourceLocalRadio.IsChecked = $true
    $script:useLocalInstaller = $true
    $urlSourcePanel.Visibility = [System.Windows.Visibility]::Collapsed
    $localSourcePanel.Visibility = [System.Windows.Visibility]::Visible
}

Initialize-StepList -ListControl $stepList

function Update-OutputPathForAppName {
    $appName = $appNameBox.Text.Trim()
    if ($appName) {
        $packageId = Get-PackageIdFromAppName -AppName $appName
        $outputPathBox.Text = Get-AppGetterAppOutputPath -BasePath $script:baseOutputPath -PackageId $packageId
    } else {
        $outputPathBox.Text = $script:baseOutputPath
    }
}

function Update-SelectedSourceDisplay {
    if ($script:useLocalInstaller) {
        $path = $localInstallerBox.Text.Trim()
        if ($path -and (Test-Path -LiteralPath $path)) {
            $selectedSourceText.Text = "Local installer: $path"
            $selectedSourceText.Foreground = ConvertTo-WpfBrush '#1B2A41'
        } else {
            $selectedSourceText.Text = 'Choose a local installer file (.exe, .msi, .msix, or .appx).'
            $selectedSourceText.Foreground = ConvertTo-WpfBrush '#5C6B7A'
        }
    } else {
        $website = $websiteUrlBox.Text.Trim()
        $download = $downloadUrlBox.Text.Trim()
        if ($download) {
            $selectedSourceText.Text = "Direct download: $download"
            $selectedSourceText.Foreground = ConvertTo-WpfBrush '#1B2A41'
        } elseif ($website) {
            $selectedSourceText.Text = "Website scan: $website"
            $selectedSourceText.Foreground = ConvertTo-WpfBrush '#1B2A41'
        } else {
            $selectedSourceText.Text = 'Provide a Website URL or Direct Download URL.'
            $selectedSourceText.Foreground = ConvertTo-WpfBrush '#5C6B7A'
        }
    }
}

function Update-PrereqStatusDisplay {
    param([object]$Prerequisites = $null)

    if (-not $Prerequisites) {
        $Prerequisites = Test-AppGetterPrerequisites
    }

    if ($Prerequisites.ContentPrepToolInstalled) {
        $wingetPart = if ($Prerequisites.WingetInstalled) { " | Winget $($Prerequisites.WingetVersion)" } else { '' }
        $prereqText.Text = "Ready | Content Prep Tool: $($Prerequisites.ContentPrepToolPath)$wingetPart"
        $prereqText.Foreground = ConvertTo-WpfBrush '#2E7D32'
    } else {
        $prereqText.Text = 'Missing prerequisites: ' + ($Prerequisites.Issues -join ' ')
        $prereqText.Foreground = ConvertTo-WpfBrush '#C62828'
    }

    $showInstall = -not [bool]$Prerequisites.ContentPrepToolInstalled
    if ($showInstall) {
        $installContentPrepButton.Visibility = [System.Windows.Visibility]::Visible
        $installContentPrepButton.IsEnabled = [bool]$Prerequisites.WingetInstalled
        if (-not $Prerequisites.WingetInstalled) {
            $installContentPrepButton.ToolTip = 'Winget is required to install the Content Prep Tool.'
        } else {
            $installContentPrepButton.ToolTip = 'Install Microsoft Win32 Content Prep Tool (intunewinapputil) via winget'
        }
    } else {
        $installContentPrepButton.Visibility = [System.Windows.Visibility]::Collapsed
    }

    return $Prerequisites
}

$null = Update-PrereqStatusDisplay
Update-OutputPathForAppName
Update-SelectedSourceDisplay
Add-LogLine -LogControl $logText -Message 'AppGetter ready.'

function Set-PackControlsEnabled {
    param([bool]$Enabled)
    $packButton.IsEnabled = $Enabled
    $appNameBox.IsEnabled = $Enabled
    $publisherBox.IsEnabled = $Enabled
    $sourceUrlRadio.IsEnabled = $Enabled
    $sourceLocalRadio.IsEnabled = $Enabled
    $websiteUrlBox.IsEnabled = $Enabled
    $downloadUrlBox.IsEnabled = $Enabled
    $localInstallerBox.IsEnabled = $Enabled
    $browseInstallerButton.IsEnabled = $Enabled
    $browseOutputButton.IsEnabled = $Enabled
    $browseIconButton.IsEnabled = $Enabled
    $versionBox.IsEnabled = $Enabled
    if ($installContentPrepButton.Visibility -eq [System.Windows.Visibility]::Visible) {
        $installContentPrepButton.IsEnabled = $Enabled -and ($installContentPrepButton.ToolTip -notlike '*Winget is required*')
    }
    if (-not $Enabled) {
        $openOutputButton.IsEnabled = $false
    }
}

$sourceUrlRadio.Add_Checked({
    $script:useLocalInstaller = $false
    $urlSourcePanel.Visibility = [System.Windows.Visibility]::Visible
    $localSourcePanel.Visibility = [System.Windows.Visibility]::Collapsed
    Update-SelectedSourceDisplay
})

$sourceLocalRadio.Add_Checked({
    $script:useLocalInstaller = $true
    $urlSourcePanel.Visibility = [System.Windows.Visibility]::Collapsed
    $localSourcePanel.Visibility = [System.Windows.Visibility]::Visible
    Update-SelectedSourceDisplay
})

$appNameBox.Add_TextChanged({ Update-OutputPathForAppName })
$websiteUrlBox.Add_TextChanged({ Update-SelectedSourceDisplay })
$downloadUrlBox.Add_TextChanged({ Update-SelectedSourceDisplay })
$localInstallerBox.Add_TextChanged({ Update-SelectedSourceDisplay })

$browseInstallerButton.Add_Click({
    try {
        $path = Show-InstallerFileDialog -OwnerWindow $window
        if ($path) {
            $localInstallerBox.Text = $path
            Update-SelectedSourceDisplay
            Add-LogLine -LogControl $logText -Message "Local installer selected: $path"
            if ($path -like '*.exe' -and -not $script:customIconPath) {
                $tempIcon = Join-Path $env:TEMP "appgetter-preview-icon.png"
                if (Extract-IconFromExe -ExePath $path -OutputPath $tempIcon) {
                    Set-IconPreview -ImageControl $iconPreview -StatusControl $iconStatus -ImagePath $tempIcon
                }
            }
        }
    } catch {
        Add-LogLine -LogControl $logText -Message "Installer browser failed: $($_.Exception.Message)"
    }
})

$browseOutputButton.Add_Click({
    try {
        $initialPath = $script:baseOutputPath
        if (-not $initialPath -and $outputPathBox.Text) {
            $initialPath = $outputPathBox.Text.Trim()
        }

        $path = Show-FolderBrowser `
            -Description 'Select base output folder (each app gets its own subfolder)' `
            -SelectedPath $initialPath `
            -OwnerWindow $window

        if ($path) {
            $script:baseOutputPath = $path
            Update-OutputPathForAppName
            $packageId = $null
            $appName = $appNameBox.Text.Trim()
            if ($appName) { $packageId = Get-PackageIdFromAppName -AppName $appName }
            Save-AppGetterSettings -OutputPath $script:baseOutputPath -LastPackageId $packageId
            Add-LogLine -LogControl $logText -Message "Output base folder set to: $path"
        }
    } catch {
        Add-LogLine -LogControl $logText -Message "Folder browser failed: $($_.Exception.Message)"
        [System.Windows.MessageBox]::Show($window, "Could not open the folder browser.`n`n$($_.Exception.Message)", 'AppGetter', 'OK', 'Error') | Out-Null
    }
})

$browseIconButton.Add_Click({
    try {
        $path = Show-OpenFileDialog -OwnerWindow $window
        if ($path) {
            $script:customIconPath = $path
            Set-IconPreview -ImageControl $iconPreview -StatusControl $iconStatus -ImagePath $path
            Add-LogLine -LogControl $logText -Message "Custom icon selected: $path"
        }
    } catch {
        Add-LogLine -LogControl $logText -Message "Icon browser failed: $($_.Exception.Message)"
    }
})

$openOutputButton.Add_Click({
    if ($script:lastOutputDirectory -and (Test-Path -LiteralPath $script:lastOutputDirectory)) {
        Start-Process explorer.exe $script:lastOutputDirectory | Out-Null
    }
})

function Complete-AppGetterPackaging {
    param(
        [object]$Result = $null,
        [object]$ErrorRecord = $null
    )

    if ($script:packTimer) {
        $script:packTimer.Stop()
        $script:packTimer = $null
    }

    if ($script:packWorker) {
        if ($script:packWorker.PowerShell) { $script:packWorker.PowerShell.Dispose() }
        if ($script:packWorker.Runspace) { $script:packWorker.Runspace.Close() }
        $script:packWorker = $null
    }

    $script:progressQueue = $null
    $script:isRunning = $false
    Set-PackControlsEnabled -Enabled $true

    if ($ErrorRecord) {
        $progressStatus.Text = 'Packaging failed.'
        Add-LogLine -LogControl $logText -Message "Packaging failed: $($ErrorRecord.Exception.Message)"
        [System.Windows.MessageBox]::Show($window, "Packaging failed.`n`n$($ErrorRecord.Exception.Message)", 'AppGetter', 'OK', 'Error') | Out-Null
        return
    }

    $script:lastOutputDirectory = $Result.VersionDirectory
    $openOutputButton.IsEnabled = $true
    Set-IconPreview -ImageControl $iconPreview -StatusControl $iconStatus -ImagePath $Result.IconFile

    if ($Result.PackagingSucceeded) {
        $progressStatus.Text = 'Packaging completed successfully.'
        Add-LogLine -LogControl $logText -Message "Success: $($Result.IntuneWinFile)"
        [System.Windows.MessageBox]::Show($window, "Package created successfully.`n`n$($Result.DisplayName)`n$($Result.IntuneWinFile)", 'AppGetter', 'OK', 'Information') | Out-Null
    } else {
        $progressStatus.Text = 'Packaging completed with warnings.'
        Add-LogLine -LogControl $logText -Message 'Metadata and scripts created, but .intunewin packaging failed or Content Prep Tool is unavailable.'
        [System.Windows.MessageBox]::Show($window, "Package files were created, but the .intunewin step did not complete.`n`nOutput: $($Result.VersionDirectory)", 'AppGetter', 'OK', 'Warning') | Out-Null
    }
}

function Start-AppGetterPackagingFromUi {
    $appName = $appNameBox.Text.Trim()
    if ([string]::IsNullOrWhiteSpace($appName)) {
        [System.Windows.MessageBox]::Show($window, 'Application name is required.', 'AppGetter', 'OK', 'Warning') | Out-Null
        return
    }

  if ($script:useLocalInstaller) {
        $localPath = $localInstallerBox.Text.Trim()
        if ([string]::IsNullOrWhiteSpace($localPath) -or -not (Test-Path -LiteralPath $localPath)) {
            [System.Windows.MessageBox]::Show($window, 'Choose a valid local installer file.', 'AppGetter', 'OK', 'Warning') | Out-Null
            return
        }
        if (-not (Test-AppGetterInstallerExtension -Path $localPath)) {
            [System.Windows.MessageBox]::Show($window, 'Local installer must be .exe, .msi, .msix, or .appx.', 'AppGetter', 'OK', 'Warning') | Out-Null
            return
        }
    } elseif ([string]::IsNullOrWhiteSpace($websiteUrlBox.Text.Trim()) -and [string]::IsNullOrWhiteSpace($downloadUrlBox.Text.Trim())) {
        [System.Windows.MessageBox]::Show($window, 'Provide a Website URL, Direct Download URL, or local installer.', 'AppGetter', 'OK', 'Warning') | Out-Null
        return
    }

    if ([string]::IsNullOrWhiteSpace($outputPathBox.Text)) {
        [System.Windows.MessageBox]::Show($window, 'Choose an output destination folder.', 'AppGetter', 'OK', 'Warning') | Out-Null
        return
    }

    $script:isRunning = $true
    Set-PackControlsEnabled -Enabled $false
    $progressBar.Value = 0
    Initialize-StepList -ListControl $stepList

    $packageId = Get-PackageIdFromAppName -AppName $appName
    $outputPath = $outputPathBox.Text.Trim()
    $script:baseOutputPath = Get-AppGetterBaseOutputPath -Path $outputPath -PackageId $packageId
    $appOutputPath = Get-AppGetterAppOutputPath -BasePath $script:baseOutputPath -PackageId $packageId
    $outputPathBox.Text = $appOutputPath
    Save-AppGetterSettings -OutputPath $script:baseOutputPath -LastPackageId $packageId -LastAppName $appName `
        -LastWebsiteUrl $websiteUrlBox.Text.Trim() -LastDownloadUrl $downloadUrlBox.Text.Trim() `
        -LastLocalInstallerPath $localInstallerBox.Text.Trim()

    $packArguments = @{
        AppName     = $appName
        Publisher   = $publisherBox.Text.Trim()
        Version     = $versionBox.Text.Trim()
        OutputPath  = $appOutputPath
        IconPath    = $script:customIconPath
        WebsiteUrl  = $websiteUrlBox.Text.Trim()
        DownloadUrl = $downloadUrlBox.Text.Trim()
    }
    if ($script:useLocalInstaller) {
        $packArguments.LocalInstallerPath = $localInstallerBox.Text.Trim()
        $packArguments.WebsiteUrl = ''
        $packArguments.DownloadUrl = ''
    }

    $script:progressQueue = New-Object System.Collections.Concurrent.ConcurrentQueue[object]
    Add-LogLine -LogControl $logText -Message "Starting packaging for $appName..."

    $script:packWorker = Start-AppGetterBackgroundPackaging -PackArguments $packArguments -ProgressQueue $script:progressQueue

    $script:packTimer = New-Object System.Windows.Threading.DispatcherTimer
    $script:packTimer.Interval = [TimeSpan]::FromMilliseconds(150)
    $script:packTimer.Add_Tick({
        $item = $null
        while ($script:progressQueue -and $script:progressQueue.TryDequeue([ref]$item)) {
            Invoke-UiProgressUpdate -Event $item -ProgressBar $progressBar -ProgressStatus $progressStatus `
                -StepList $stepList -LogText $logText -StepMap $stepMap
        }

        if (-not $script:packWorker) { return }

        if ($script:packWorker.AsyncResult.IsCompleted) {
            while ($script:progressQueue -and $script:progressQueue.TryDequeue([ref]$item)) {
                Invoke-UiProgressUpdate -Event $item -ProgressBar $progressBar -ProgressStatus $progressStatus `
                    -StepList $stepList -LogText $logText -StepMap $stepMap
            }

            $worker = $script:packWorker
            try {
                $result = $worker.PowerShell.EndInvoke($worker.AsyncResult)
                if ($result -is [array] -and $result.Count -eq 1) { $result = $result[0] }
                Complete-AppGetterPackaging -Result $result
            } catch {
                Complete-AppGetterPackaging -ErrorRecord $_
            }
        }
    })
    $script:packTimer.Start()
}

$packButton.Add_Click({
    if ($script:isRunning) { return }
    Start-AppGetterPackagingFromUi
})

$installContentPrepButton.Add_Click({
    if ($script:isRunning -or $script:contentPrepInstallJob) { return }

    $confirm = [System.Windows.MessageBox]::Show(
        $window,
        "Install Microsoft Win32 Content Prep Tool via winget?`n`nwinget install --exact --id Microsoft.Win32ContentPrepTool",
        'AppGetter',
        'YesNo',
        'Question'
    )
    if ($confirm -ne [System.Windows.MessageBoxResult]::Yes) { return }

    $installContentPrepButton.IsEnabled = $false
    $prereqText.Text = 'Installing Content Prep Tool via winget...'
    $prereqText.Foreground = ConvertTo-WpfBrush '#5C6B7A'
    Add-LogLine -LogControl $logText -Message 'Installing Microsoft.Win32ContentPrepTool via winget...'

    $script:contentPrepInstallJob = Start-Job -ArgumentList $modulePath -ScriptBlock {
        param($ModulePath)
        Import-Module $ModulePath -Force
        Install-AppGetterContentPrepTool
    }

    if ($script:contentPrepInstallTimer) { $script:contentPrepInstallTimer.Stop() }

    $script:contentPrepInstallTimer = New-Object System.Windows.Threading.DispatcherTimer
    $script:contentPrepInstallTimer.Interval = [TimeSpan]::FromMilliseconds(250)
    $script:contentPrepInstallTimer.Add_Tick({
        if (-not $script:contentPrepInstallJob -or $script:contentPrepInstallJob.State -eq 'Running') { return }

        $script:contentPrepInstallTimer.Stop()
        $job = $script:contentPrepInstallJob
        $script:contentPrepInstallJob = $null
        $script:contentPrepInstallTimer = $null

        try {
            if ($job.State -eq 'Failed') {
                $err = Receive-Job -Job $job -ErrorAction SilentlyContinue
                throw (($err | Out-String).Trim())
            }

            $result = Receive-Job -Job $job
            if ($result -is [array] -and $result.Count -eq 1) { $result = $result[0] }

            if ($result.AlreadyInstalled) {
                Add-LogLine -LogControl $logText -Message "Content Prep Tool already available: $($result.ContentPrepToolPath)"
            } else {
                Add-LogLine -LogControl $logText -Message "Content Prep Tool installed: $($result.ContentPrepToolPath)"
            }
            Update-PrereqStatusDisplay -Prerequisites $result.Prerequisites
        } catch {
            Add-LogLine -LogControl $logText -Message "Content Prep Tool install failed: $($_.Exception.Message)"
            [System.Windows.MessageBox]::Show($window, "Failed to install Content Prep Tool.`n`n$($_.Exception.Message)", 'AppGetter', 'OK', 'Error') | Out-Null
            Update-PrereqStatusDisplay
        } finally {
            Remove-Job -Job $job -Force -ErrorAction SilentlyContinue
        }
    })
    $script:contentPrepInstallTimer.Start()
})

$null = $window.ShowDialog()
