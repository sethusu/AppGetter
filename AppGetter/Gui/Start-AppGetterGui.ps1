<#
.SYNOPSIS
    Launches the AppGetter graphical user interface.
.DESCRIPTION
    WPF-based GUI for entering web download details, discovering installer links,
    choosing output destination, tracking live packaging progress, and previewing icons.
.EXAMPLE
    .\Start-AppGetterGui.ps1
#>

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

if (-not ($IsWindows -or ($PSVersionTable.PSVersion.Major -ge 6 -and $IsWindows))) {
    throw 'The AppGetter GUI requires Windows with a desktop session (WPF). Use Create-IntuneWinFromWeb.ps1 with parameters on other platforms.'
}

Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase
Add-Type -AssemblyName System.Windows.Forms

$moduleRoot = Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $moduleRoot 'AppGetter.psd1') -Force

$settings = Get-AppGetterSettings
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

function Show-FolderBrowser {
    param([string]$Description, [string]$SelectedPath)
    $dialog = New-Object System.Windows.Forms.FolderBrowserDialog
    $dialog.Description = $Description
    if ($SelectedPath -and (Test-Path $SelectedPath)) {
        $dialog.SelectedPath = $SelectedPath
    }
    if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        return $dialog.SelectedPath
    }
    return $null
}

function Show-OpenFileDialog {
    param([string]$Filter = 'PNG images (*.png)|*.png|All files (*.*)|*.*')
    $dialog = New-Object System.Windows.Forms.OpenFileDialog
    $dialog.Filter = $Filter
    if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        return $dialog.FileName
    }
    return $null
}

function Add-LogLine {
    param($LogControl, [string]$Message)
    $timestamp = Get-Date -Format 'HH:mm:ss'
    $LogControl.AppendText("[$timestamp] $Message`r`n")
    $LogControl.ScrollToEnd()
}

function New-LabeledTextBox {
    param(
        $Parent,
        [string]$Label,
        [string]$DefaultValue = '',
        [double]$LabelWidth = 130
    )

    $grid = New-Object System.Windows.Controls.Grid
    $grid.Margin = New-WpfThickness -Bottom 8
    $grid.ColumnDefinitions.Add((New-Object System.Windows.Controls.ColumnDefinition)) | Out-Null
    $grid.ColumnDefinitions.Add((New-Object System.Windows.Controls.ColumnDefinition)) | Out-Null
    $grid.ColumnDefinitions[0].Width = New-Object System.Windows.GridLength($LabelWidth)

    $labelControl = New-Object System.Windows.Controls.TextBlock
    $labelControl.Text = $Label
    $labelControl.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
    $labelControl.Margin = New-WpfThickness -Right 8
    [System.Windows.Controls.Grid]::SetColumn($labelControl, 0)

    $textBox = New-Object System.Windows.Controls.TextBox
    $textBox.Text = $DefaultValue
    $textBox.Padding = New-WpfThickness -Left 6 -Top 4 -Right 6 -Bottom 4
    [System.Windows.Controls.Grid]::SetColumn($textBox, 1)

    $grid.Children.Add($labelControl) | Out-Null
    $grid.Children.Add($textBox) | Out-Null
    $Parent.Children.Add($grid) | Out-Null
    return $textBox
}

$window = New-Object System.Windows.Window
$window.Title = 'AppGetter - Intune Win32 Package Creator'
$window.Width = 920
$window.Height = 720
$window.MinWidth = 800
$window.MinHeight = 640
$window.WindowStartupLocation = [System.Windows.WindowStartupLocation]::CenterScreen
$window.Background = ConvertTo-WpfBrush '#F3F6FA'

$root = New-Object System.Windows.Controls.Grid
$root.Margin = New-WpfThickness -Left 16 -Top 16 -Right 16 -Bottom 16
$root.RowDefinitions.Add((New-Object System.Windows.Controls.RowDefinition)) | Out-Null
$root.RowDefinitions.Add((New-Object System.Windows.Controls.RowDefinition)) | Out-Null
$root.RowDefinitions.Add((New-Object System.Windows.Controls.RowDefinition)) | Out-Null
$root.RowDefinitions[0].Height = New-Object System.Windows.GridLength(1, [System.Windows.GridUnitType]::Auto)
$root.RowDefinitions[1].Height = New-Object System.Windows.GridLength(1, [System.Windows.GridUnitType]::Star)
$root.RowDefinitions[2].Height = New-Object System.Windows.GridLength(220)

$header = New-Object System.Windows.Controls.TextBlock
$header.Text = 'Create Intune Win32 packages from web downloads'
$header.FontSize = 20
$header.FontWeight = [System.Windows.FontWeights]::SemiBold
$header.Margin = New-WpfThickness -Bottom 12
[System.Windows.Controls.Grid]::SetRow($header, 0)

$body = New-Object System.Windows.Controls.Grid
$body.ColumnDefinitions.Add((New-Object System.Windows.Controls.ColumnDefinition)) | Out-Null
$body.ColumnDefinitions.Add((New-Object System.Windows.Controls.ColumnDefinition)) | Out-Null
$body.ColumnDefinitions[0].Width = New-Object System.Windows.GridLength(1.4, [System.Windows.GridUnitType]::Star)
$body.ColumnDefinitions[1].Width = New-Object System.Windows.GridLength(1, [System.Windows.GridUnitType]::Star)
[System.Windows.Controls.Grid]::SetRow($body, 1)

$formCard = New-Object System.Windows.Controls.Border
$formCard.Background = [System.Windows.Media.Brushes]::White
$formCard.CornerRadius = New-Object System.Windows.CornerRadius(8)
$formCard.Padding = New-WpfThickness -Left 14 -Top 14 -Right 14 -Bottom 14
$formCard.BorderBrush = ConvertTo-WpfBrush '#D8DEE9'
$formCard.BorderThickness = New-WpfThickness -Left 1 -Top 1 -Right 1 -Bottom 1
$formCard.Margin = New-WpfThickness -Right 8
[System.Windows.Controls.Grid]::SetColumn($formCard, 0)

$formStack = New-Object System.Windows.Controls.StackPanel
$appNameBox = New-LabeledTextBox -Parent $formStack -Label 'Application name' -DefaultValue $settings.LastAppName
$websiteBox = New-LabeledTextBox -Parent $formStack -Label 'Website URL' -DefaultValue $settings.LastWebsiteUrl
$downloadBox = New-LabeledTextBox -Parent $formStack -Label 'Direct download URL' -DefaultValue $settings.LastDownloadUrl
$publisherBox = New-LabeledTextBox -Parent $formStack -Label 'Publisher'
$versionBox = New-LabeledTextBox -Parent $formStack -Label 'Version (optional)'
$developerBox = New-LabeledTextBox -Parent $formStack -Label 'Developer URL'
$supportBox = New-LabeledTextBox -Parent $formStack -Label 'Support/docs URL'
$installCmdBox = New-LabeledTextBox -Parent $formStack -Label 'Install command'

$outputGrid = New-Object System.Windows.Controls.Grid
$outputGrid.Margin = New-WpfThickness -Bottom 8
$outputGrid.ColumnDefinitions.Add((New-Object System.Windows.Controls.ColumnDefinition)) | Out-Null
$outputGrid.ColumnDefinitions.Add((New-Object System.Windows.Controls.ColumnDefinition)) | Out-Null
$outputGrid.ColumnDefinitions.Add((New-Object System.Windows.Controls.ColumnDefinition)) | Out-Null
$outputGrid.ColumnDefinitions[0].Width = New-Object System.Windows.GridLength(130)
$outputGrid.ColumnDefinitions[2].Width = New-Object System.Windows.GridLength(90)

$outputLabel = New-Object System.Windows.Controls.TextBlock
$outputLabel.Text = 'Output folder'
$outputLabel.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
[System.Windows.Controls.Grid]::SetColumn($outputLabel, 0)

$outputBox = New-Object System.Windows.Controls.TextBox
$outputBox.Text = $settings.OutputPath
$outputBox.Padding = New-WpfThickness -Left 6 -Top 4 -Right 6 -Bottom 4
$outputBox.Margin = New-WpfThickness -Right 6
[System.Windows.Controls.Grid]::SetColumn($outputBox, 1)

$browseOutputButton = New-Object System.Windows.Controls.Button
$browseOutputButton.Content = 'Browse'
$browseOutputButton.Padding = New-WpfThickness -Left 10 -Top 4 -Right 10 -Bottom 4
[System.Windows.Controls.Grid]::SetColumn($browseOutputButton, 2)

$outputGrid.Children.Add($outputLabel) | Out-Null
$outputGrid.Children.Add($outputBox) | Out-Null
$outputGrid.Children.Add($browseOutputButton) | Out-Null
$formStack.Children.Add($outputGrid) | Out-Null

$iconGrid = New-Object System.Windows.Controls.Grid
$iconGrid.Margin = New-WpfThickness -Bottom 8
$iconGrid.ColumnDefinitions.Add((New-Object System.Windows.Controls.ColumnDefinition)) | Out-Null
$iconGrid.ColumnDefinitions.Add((New-Object System.Windows.Controls.ColumnDefinition)) | Out-Null
$iconGrid.ColumnDefinitions.Add((New-Object System.Windows.Controls.ColumnDefinition)) | Out-Null
$iconGrid.ColumnDefinitions[0].Width = New-Object System.Windows.GridLength(130)
$iconGrid.ColumnDefinitions[2].Width = New-Object System.Windows.GridLength(90)

$iconLabel = New-Object System.Windows.Controls.TextBlock
$iconLabel.Text = 'Custom icon'
$iconLabel.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
[System.Windows.Controls.Grid]::SetColumn($iconLabel, 0)

$iconBox = New-Object System.Windows.Controls.TextBox
$iconBox.Padding = New-WpfThickness -Left 6 -Top 4 -Right 6 -Bottom 4
$iconBox.Margin = New-WpfThickness -Right 6
[System.Windows.Controls.Grid]::SetColumn($iconBox, 1)

$browseIconButton = New-Object System.Windows.Controls.Button
$browseIconButton.Content = 'Browse'
$browseIconButton.Padding = New-WpfThickness -Left 10 -Top 4 -Right 10 -Bottom 4
[System.Windows.Controls.Grid]::SetColumn($browseIconButton, 2)

$iconGrid.Children.Add($iconLabel) | Out-Null
$iconGrid.Children.Add($iconBox) | Out-Null
$iconGrid.Children.Add($browseIconButton) | Out-Null
$formStack.Children.Add($iconGrid) | Out-Null

$buttonRow = New-Object System.Windows.Controls.StackPanel
$buttonRow.Orientation = [System.Windows.Controls.Orientation]::Horizontal
$buttonRow.Margin = New-WpfThickness -Top 8

$findLinksButton = New-Object System.Windows.Controls.Button
$findLinksButton.Content = 'Find download links'
$findLinksButton.Padding = New-WpfThickness -Left 12 -Top 6 -Right 12 -Bottom 6
$findLinksButton.Margin = New-WpfThickness -Right 8

$createButton = New-Object System.Windows.Controls.Button
$createButton.Content = 'Create Package'
$createButton.Padding = New-WpfThickness -Left 16 -Top 6 -Right 16 -Bottom 6
$createButton.FontWeight = [System.Windows.FontWeights]::SemiBold
$createButton.Background = ConvertTo-WpfBrush '#2563EB'
$createButton.Foreground = [System.Windows.Media.Brushes]::White

$openFolderButton = New-Object System.Windows.Controls.Button
$openFolderButton.Content = 'Open output folder'
$openFolderButton.Padding = New-WpfThickness -Left 12 -Top 6 -Right 12 -Bottom 6
$openFolderButton.Margin = New-WpfThickness -Left 8
$openFolderButton.IsEnabled = $false

$buttonRow.Children.Add($findLinksButton) | Out-Null
$buttonRow.Children.Add($createButton) | Out-Null
$buttonRow.Children.Add($openFolderButton) | Out-Null
$formStack.Children.Add($buttonRow) | Out-Null

$formCard.Child = $formStack

$rightColumn = New-Object System.Windows.Controls.StackPanel
$rightColumn.Margin = New-WpfThickness -Left 8
[System.Windows.Controls.Grid]::SetColumn($rightColumn, 1)

$progressLabel = New-Object System.Windows.Controls.TextBlock
$progressLabel.Text = 'Progress'
$progressLabel.FontWeight = [System.Windows.FontWeights]::SemiBold
$progressLabel.Margin = New-WpfThickness -Bottom 6

$progressBar = New-Object System.Windows.Controls.ProgressBar
$progressBar.Height = 18
$progressBar.Minimum = 0
$progressBar.Maximum = 100
$progressBar.Margin = New-WpfThickness -Bottom 8

$statusText = New-Object System.Windows.Controls.TextBlock
$statusText.Text = 'Ready'
$statusText.Foreground = ConvertTo-WpfBrush '#5C6B7A'
$statusText.Margin = New-WpfThickness -Bottom 12
$statusText.TextWrapping = [System.Windows.TextWrapping]::Wrap

$prereq = Test-AppGetterPrerequisites
$prereqCard = New-Object System.Windows.Controls.Border
$prereqCard.Background = [System.Windows.Media.Brushes]::White
$prereqCard.CornerRadius = New-Object System.Windows.CornerRadius(8)
$prereqCard.Padding = New-WpfThickness -Left 12 -Top 12 -Right 12 -Bottom 12
$prereqCard.BorderBrush = ConvertTo-WpfBrush '#D8DEE9'
$prereqCard.BorderThickness = New-WpfThickness -Left 1 -Top 1 -Right 1 -Bottom 1
$prereqCard.Margin = New-WpfThickness -Bottom 8

$prereqStack = New-Object System.Windows.Controls.StackPanel
$prereqTitle = New-Object System.Windows.Controls.TextBlock
$prereqTitle.Text = 'Prerequisites'
$prereqTitle.FontWeight = [System.Windows.FontWeights]::SemiBold
$prereqTitle.Margin = New-WpfThickness -Bottom 6
$prereqStack.Children.Add($prereqTitle) | Out-Null

$contentPrepStatus = if ($prereq.ContentPrepToolInstalled) { 'Installed' } else { 'Not found on PATH' }
$contentPrepLine = New-Object System.Windows.Controls.TextBlock
$contentPrepLine.Text = "Content Prep Tool: $contentPrepStatus"
$contentPrepLine.Foreground = if ($prereq.ContentPrepToolInstalled) { ConvertTo-WpfBrush '#15803D' } else { ConvertTo-WpfBrush '#B45309' }
$prereqStack.Children.Add($contentPrepLine) | Out-Null
$prereqCard.Child = $prereqStack

$rightColumn.Children.Add($progressLabel) | Out-Null
$rightColumn.Children.Add($progressBar) | Out-Null
$rightColumn.Children.Add($statusText) | Out-Null
$rightColumn.Children.Add($prereqCard) | Out-Null

$body.Children.Add($formCard) | Out-Null
$body.Children.Add($rightColumn) | Out-Null

$logCard = New-Object System.Windows.Controls.Border
$logCard.Background = [System.Windows.Media.Brushes]::White
$logCard.CornerRadius = New-Object System.Windows.CornerRadius(8)
$logCard.Padding = New-WpfThickness -Left 10 -Top 10 -Right 10 -Bottom 10
$logCard.BorderBrush = ConvertTo-WpfBrush '#D8DEE9'
$logCard.BorderThickness = New-WpfThickness -Left 1 -Top 1 -Right 1 -Bottom 1
$logCard.Margin = New-WpfThickness -Top 12
[System.Windows.Controls.Grid]::SetRow($logCard, 2)

$logText = New-Object System.Windows.Controls.TextBox
$logText.IsReadOnly = $true
$logText.TextWrapping = [System.Windows.TextWrapping]::Wrap
$logText.VerticalScrollBarVisibility = [System.Windows.Controls.ScrollBarVisibility]::Auto
$logText.FontFamily = New-Object System.Windows.Media.FontFamily('Consolas')
$logText.Background = ConvertTo-WpfBrush '#FBFCFE'
$logCard.Child = $logText

$root.Children.Add($header) | Out-Null
$root.Children.Add($body) | Out-Null
$root.Children.Add($logCard) | Out-Null
$window.Content = $root

$script:lastResult = $null
$script:isRunning = $false

$browseOutputButton.Add_Click({
    $selected = Show-FolderBrowser -Description 'Select output folder for AppGetter packages' -SelectedPath $outputBox.Text
    if ($selected) { $outputBox.Text = $selected }
})

$browseIconButton.Add_Click({
    $selected = Show-OpenFileDialog
    if ($selected) { $iconBox.Text = $selected }
})

$findLinksButton.Add_Click({
    if ([string]::IsNullOrWhiteSpace($websiteBox.Text)) {
        [System.Windows.MessageBox]::Show($window, 'Enter a Website URL first.', 'AppGetter', 'OK', 'Warning') | Out-Null
        return
    }
    try {
        Add-LogLine -LogControl $logText -Message "Scanning $($websiteBox.Text) for download links..."
        $links = Get-DownloadLinksFromWeb -Url $websiteBox.Text -AppName $appNameBox.Text
        if ($links.Count -eq 0) {
            Add-LogLine -LogControl $logText -Message 'No download links found.'
            return
        }
        Add-LogLine -LogControl $logText -Message "Found $($links.Count) link(s). Using first installer match."
        $selected = $links | Where-Object { $_ -match '\.(exe|msi|msix|appx)(\?|$)' } | Select-Object -First 1
        if (-not $selected) { $selected = $links[0] }
        $downloadBox.Text = $selected
        Add-LogLine -LogControl $logText -Message "Selected: $selected"
    } catch {
        Add-LogLine -LogControl $logText -Message "Link discovery failed: $_"
    }
})

$openFolderButton.Add_Click({
    if ($script:lastResult -and $script:lastResult.VersionDirectory -and (Test-Path $script:lastResult.VersionDirectory)) {
        Start-Process explorer.exe $script:lastResult.VersionDirectory | Out-Null
    }
})

$createButton.Add_Click({
    if ($script:isRunning) { return }

    if ([string]::IsNullOrWhiteSpace($appNameBox.Text)) {
        [System.Windows.MessageBox]::Show($window, 'Application name is required.', 'AppGetter', 'OK', 'Warning') | Out-Null
        return
    }
    if ([string]::IsNullOrWhiteSpace($websiteBox.Text) -and [string]::IsNullOrWhiteSpace($downloadBox.Text)) {
        [System.Windows.MessageBox]::Show($window, 'Enter a Website URL or Direct download URL.', 'AppGetter', 'OK', 'Warning') | Out-Null
        return
    }

    $script:isRunning = $true
    $createButton.IsEnabled = $false
    $findLinksButton.IsEnabled = $false
    $progressBar.Value = 0
    $statusText.Text = 'Packaging...'
    Add-LogLine -LogControl $logText -Message 'Starting packaging...'

    $params = @{
        AppName      = $appNameBox.Text.Trim()
        WebsiteUrl   = $websiteBox.Text.Trim()
        DownloadUrl  = $downloadBox.Text.Trim()
        Version      = $versionBox.Text.Trim()
        Publisher    = $publisherBox.Text.Trim()
        DeveloperUrl = $developerBox.Text.Trim()
        SupportUrl   = $supportBox.Text.Trim()
        OutputPath   = $outputBox.Text.Trim()
        IconPath     = $iconBox.Text.Trim()
        InstallCommand = $installCmdBox.Text.Trim()
        CollectIconCandidates = $true
        OnProgress = {
            param($Event)
            if ($Event.Type -eq 'Progress') {
                $window.Dispatcher.Invoke([action]{
                    $progressBar.Value = [math]::Max(0, [math]::Min(100, $Event.Percent))
                    $statusText.Text = if ($Event.Message) { "$($Event.StepName) - $($Event.Message)" } else { $Event.StepName }
                    Add-LogLine -LogControl $logText -Message "[$($Event.StepName)] $($Event.Message)"
                })
            } elseif ($Event.Message) {
                $window.Dispatcher.Invoke([action]{
                    Add-LogLine -LogControl $logText -Message $Event.Message
                })
            }
        }
    }

    try {
        $result = Invoke-AppGetterPackaging @params
        $script:lastResult = $result
        $openFolderButton.IsEnabled = $true

        if ($result.PackagingSucceeded) {
            $statusText.Text = 'Package created successfully.'
            Add-LogLine -LogControl $logText -Message "Created: $($result.IntuneWinFile)"
            [System.Windows.MessageBox]::Show($window, "Package created successfully.`n`n$($result.VersionDirectory)", 'AppGetter', 'OK', 'Information') | Out-Null
        } else {
            $statusText.Text = 'Metadata created; .intunewin step incomplete.'
            Add-LogLine -LogControl $logText -Message 'Packaging completed with warnings. Check appgetter-packaging.log if needed.'
            [System.Windows.MessageBox]::Show($window, 'Metadata files were created, but the .intunewin step did not complete. Ensure intunewinapputil is on PATH.', 'AppGetter', 'OK', 'Warning') | Out-Null
        }
    } catch {
        $statusText.Text = 'Packaging failed.'
        Add-LogLine -LogControl $logText -Message "ERROR: $_"
        [System.Windows.MessageBox]::Show($window, "Packaging failed:`n$_", 'AppGetter', 'OK', 'Error') | Out-Null
    } finally {
        $script:isRunning = $false
        $createButton.IsEnabled = $true
        $findLinksButton.IsEnabled = $true
    }
})

Add-LogLine -LogControl $logText -Message 'AppGetter ready. Enter application details and click Create Package.'
$null = $window.ShowDialog()
