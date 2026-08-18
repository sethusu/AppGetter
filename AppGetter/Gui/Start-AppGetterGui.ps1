<#
.SYNOPSIS
    Launches the AppGetter graphical user interface.
.DESCRIPTION
    WPF-based GUI for packaging an installer from a direct download URL, a local file on this
    computer, or a download link found by scanning a website. Provides Content Prep Tool
    prerequisite checks, an output destination browser, live packaging progress, and icon preview.
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

# WinForms dialogs (folder/file pickers) render more reliably with visual styles enabled.
try {
    [System.Windows.Forms.Application]::EnableVisualStyles()
} catch {
    # Non-fatal -- dialogs can still open without visual styles.
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

    if (-not $OwnerWindow) {
        return $null
    }

    try {
        $helper = New-Object System.Windows.Interop.WindowInteropHelper($OwnerWindow)
        # Ensure the WPF HWND exists before parenting WinForms dialogs.
        $null = $helper.EnsureHandle()
        if ($helper.Handle -eq [IntPtr]::Zero) {
            return $null
        }

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

    # WinForms FolderBrowserDialog defaults RootFolder to Desktop. When SelectedPath
    # points at another drive (common for packaging folders like D:\...), ShowDialog
    # can throw / tear down the WPF host. Root at MyComputer so any path is valid.
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
        } catch {
            # Ignore unusable initial paths; dialog still opens at My Computer.
        }
    }

    $owner = Get-WinFormsOwnerWindow -OwnerWindow $OwnerWindow
    $result = [System.Windows.Forms.DialogResult]::Cancel
    $chosenPath = $null
    try {
        if ($owner) {
            $result = $dialog.ShowDialog($owner)
        } else {
            $result = $dialog.ShowDialog()
        }
        if ($result -eq [System.Windows.Forms.DialogResult]::OK) {
            $chosenPath = $dialog.SelectedPath
        }
    } finally {
        if ($owner) {
            try { $owner.ReleaseHandle() } catch { }
        }
        $dialog.Dispose()
    }

    return $chosenPath
}

function Show-OpenFileDialog {
    param(
        [string]$Filter = 'PNG images (*.png)|*.png|All files (*.*)|*.*',
        [string]$Title = 'Select a file',
        [string]$InitialDirectory,
        $OwnerWindow = $null
    )

    $dialog = New-Object System.Windows.Forms.OpenFileDialog
    $dialog.Filter = $Filter
    $dialog.Title = $Title
    $dialog.CheckFileExists = $true
    $dialog.Multiselect = $false
    if ($InitialDirectory -and (Test-Path -LiteralPath $InitialDirectory)) {
        $dialog.InitialDirectory = $InitialDirectory
    }

    $owner = Get-WinFormsOwnerWindow -OwnerWindow $OwnerWindow
    $result = [System.Windows.Forms.DialogResult]::Cancel
    $chosenPath = $null
    try {
        if ($owner) {
            $result = $dialog.ShowDialog($owner)
        } else {
            $result = $dialog.ShowDialog()
        }
        if ($result -eq [System.Windows.Forms.DialogResult]::OK) {
            $chosenPath = $dialog.FileName
        }
    } finally {
        if ($owner) {
            try { $owner.ReleaseHandle() } catch { }
        }
        $dialog.Dispose()
    }

    return $chosenPath
}

function New-WpfBitmapImage {
    param([string]$ImagePath)

    $bitmap = New-Object System.Windows.Media.Imaging.BitmapImage
    $bitmap.BeginInit()
    $bitmap.CacheOption = [System.Windows.Media.Imaging.BitmapCacheOption]::OnLoad
    $bitmap.UriSource = [Uri]::new((Resolve-Path $ImagePath).Path)
    $bitmap.EndInit()
    $bitmap.Freeze()
    return $bitmap
}

function Set-IconPreview {
    param(
        $ImageControl,
        $StatusControl,
        [string]$ImagePath
    )

    if ($ImagePath -and (Test-Path $ImagePath)) {
        try {
            $ImageControl.Source = New-WpfBitmapImage -ImagePath $ImagePath
            $StatusControl.Text = [System.IO.Path]::GetFileName($ImagePath)
            return
        } catch {
            $StatusControl.Text = "Could not load icon: $_"
        }
    }

    $ImageControl.Source = $null
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

function Show-AppGetterLinkPickerDialog {
    param(
        [array]$Links,
        [string]$WebsiteUrl,
        $OwnerWindow
    )

    $dialogPath = Join-Path $PSScriptRoot 'AppGetter.LinkPickerDialog.xaml'
    $dialogWindow = Read-XamlWindow -XamlPath $dialogPath
    $dialogWindow.Owner = $OwnerWindow

    $summary = $dialogWindow.FindName('LinkSummaryText')
    $panel = $dialogWindow.FindName('ResultsPanel')
    $selectButton = $dialogWindow.FindName('SelectButton')
    $cancelButton = $dialogWindow.FindName('CancelButton')

    $summary.Text = "Found $($Links.Count) download link(s) on $WebsiteUrl. Select the installer you want to package."

    $dialogSelection = @{ Link = $null }
    $firstRadio = $null

    foreach ($link in $Links) {
        $border = New-Object System.Windows.Controls.Border
        $border.Margin = New-WpfThickness -Bottom 8
        $border.Padding = New-WpfThickness -Left 10 -Top 10 -Right 10 -Bottom 10
        $border.CornerRadius = New-Object System.Windows.CornerRadius(6)
        $border.BorderBrush = ConvertTo-WpfBrush '#D8DEE9'
        $border.BorderThickness = New-WpfThickness -Left 1 -Top 1 -Right 1 -Bottom 1
        $border.Background = [System.Windows.Media.Brushes]::White

        $stack = New-Object System.Windows.Controls.StackPanel
        $radio = New-Object System.Windows.Controls.RadioButton
        $radio.GroupName = 'AppGetterLinkSelection'
        $radio.Margin = New-WpfThickness -Bottom 4
        $radio.Content = Get-AppGetterInstallerFileNameFromUrl -Url $link
        $radio.FontWeight = [System.Windows.FontWeights]::SemiBold
        $radio.Tag = $link

        $capturedLink = $link
        $radio.Add_Checked({
                $dialogSelection.Link = $capturedLink
            })

        if (-not $firstRadio) {
            $firstRadio = $radio
            $dialogSelection.Link = $link
        }

        $urlText = New-Object System.Windows.Controls.TextBlock
        $urlText.Text = $link
        $urlText.Foreground = ConvertTo-WpfBrush '#5C6B7A'
        $urlText.TextWrapping = [System.Windows.TextWrapping]::Wrap
        $urlText.Margin = New-WpfThickness -Left 22

        $stack.Children.Add($radio) | Out-Null
        $stack.Children.Add($urlText) | Out-Null
        $border.Child = $stack
        $panel.Children.Add($border) | Out-Null
    }

    if ($firstRadio) {
        $firstRadio.IsChecked = $true
    }

    $selectButton.Add_Click({
            if ($dialogSelection.Link) {
                $dialogWindow.Tag = $dialogSelection.Link
                $dialogWindow.DialogResult = $true
                $dialogWindow.Close()
            } else {
                [System.Windows.MessageBox]::Show($dialogWindow, 'Please select a download link.', 'AppGetter', 'OK', 'Warning') | Out-Null
            }
        })

    $cancelButton.Add_Click({
            $dialogWindow.DialogResult = $false
            $dialogWindow.Close()
        })

    if ($dialogWindow.ShowDialog()) {
        return $dialogWindow.Tag
    }
    return $null
}

function Show-AppGetterIconPickerDialog {
    param(
        [array]$Candidates,
        [string]$DisplayName,
        [string]$PackageId,
        $OwnerWindow
    )

    if (-not $Candidates -or $Candidates.Count -lt 2) {
        return $null
    }

    $dialogPath = Join-Path $PSScriptRoot 'AppGetter.IconPickerDialog.xaml'
    $dialogWindow = Read-XamlWindow -XamlPath $dialogPath
    $dialogWindow.Owner = $OwnerWindow

    $summary = $dialogWindow.FindName('IconSummaryText')
    $panel = $dialogWindow.FindName('CandidatesPanel')
    $useButton = $dialogWindow.FindName('UseSelectedButton')
    $keepButton = $dialogWindow.FindName('KeepCurrentButton')

    $summary.Text = "Packaging finished for $DisplayName ($PackageId). Pick the icon that best represents this app for Intune upload."

    $selection = @{
        Candidate = $Candidates[0]
    }
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
        $radio.Add_Checked({
                $selection.Candidate = $capturedCandidate
            })

        if (-not $firstRadio) {
            $firstRadio = $radio
            $selection.Candidate = $candidate
        }

        $image = New-Object System.Windows.Controls.Image
        $image.Width = 128
        $image.Height = 128
        $image.Stretch = [System.Windows.Media.Stretch]::Uniform
        $image.Margin = New-WpfThickness -Bottom 8
        if ($candidate.Path -and (Test-Path $candidate.Path)) {
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

        $urlText = New-Object System.Windows.Controls.TextBlock
        $urlValue = [string]$candidate.Url
        $urlDisplay = if ($urlValue.Length -gt 48) { $urlValue.Substring(0, 45) + '...' } else { $urlValue }
        $urlText.Text = $urlDisplay
        $urlText.Foreground = ConvertTo-WpfBrush '#8A96A3'
        $urlText.FontSize = 11
        $urlText.TextWrapping = [System.Windows.TextWrapping]::Wrap
        $urlText.TextAlignment = [System.Windows.TextAlignment]::Center
        $urlText.ToolTip = $urlValue

        $stack.Children.Add($radio) | Out-Null
        $stack.Children.Add($image) | Out-Null
        $stack.Children.Add($sourceText) | Out-Null
        $stack.Children.Add($urlText) | Out-Null
        $card.Child = $stack
        $panel.Children.Add($card) | Out-Null
    }

    if ($firstRadio) {
        $firstRadio.IsChecked = $true
    }

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

function Invoke-PostPackagingIconSelection {
    param(
        [object]$Result,
        $OwnerWindow,
        $IconPreview,
        $IconStatus,
        $LogText
    )

    if ($Result.UsedCustomIcon) { return $Result }
    if (-not $Result.IconCandidates -or $Result.IconCandidates.Count -lt 2) { return $Result }
    if (-not $Result.LogoFile -or -not $Result.IconFile) { return $Result }

    $selected = Show-AppGetterIconPickerDialog -Candidates $Result.IconCandidates `
        -DisplayName $Result.DisplayName -PackageId $Result.PackageId -OwnerWindow $OwnerWindow

    if ($selected) {
        Set-AppGetterPackageIconFiles -SourceIconPath $selected.Path -LogoFilePath $Result.LogoFile -IconFilePath $Result.IconFile
        Set-IconPreview -ImageControl $IconPreview -StatusControl $IconStatus -ImagePath $Result.IconFile
        Add-LogLine -LogControl $LogText -Message "Applied selected icon from $($selected.Source): $($selected.Url)"
    } else {
        Add-LogLine -LogControl $LogText -Message 'Kept the default icon candidate from packaging.'
    }

    return $Result
}

$script:StepLabels = @(
    'Load package details'
    'Create output directories'
    'Resolve installer source'
    'Download or stage installer'
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

function Initialize-StepList {
    param($ListControl)
    $script:StepStates = @('Pending') * $script:StepLabels.Count
    $ListControl.Items.Clear()
    for ($i = 0; $i -lt $script:StepLabels.Count; $i++) {
        $ListControl.Items.Add((New-StepListItem -Index $i)) | Out-Null
    }
}

function Update-StepList {
    param(
        $ListControl,
        [int]$StepIndex,
        [ValidateSet('Pending', 'Running', 'Completed', 'Failed')]
        [string]$State
    )

    if ($StepIndex -lt 0 -or $StepIndex -ge $script:StepLabels.Count) {
        return
    }

    $script:StepStates[$StepIndex] = $State
    $ListControl.Items[$StepIndex] = New-StepListItem -Index $StepIndex
}

function Invoke-UiProgressUpdate {
    param(
        $ProgressEvent,
        $ProgressBar,
        $ProgressStatus,
        $StepList,
        $LogText,
        $StepMap
    )

    if ($ProgressEvent.Type -eq 'Progress') {
        if ($ProgressEvent.Percent -ge 0) {
            $ProgressBar.Value = [math]::Min(100, $ProgressEvent.Percent)
        }
        if ($ProgressEvent.Message) {
            $ProgressStatus.Text = "$($ProgressEvent.StepName): $($ProgressEvent.Message)"
        } else {
            $ProgressStatus.Text = $ProgressEvent.StepName
        }

        if ($StepMap.ContainsKey($ProgressEvent.Step)) {
            $index = $StepMap[$ProgressEvent.Step]
            for ($i = 0; $i -lt $index; $i++) {
                if ($script:StepStates[$i] -ne 'Failed') {
                    Update-StepList -ListControl $StepList -StepIndex $i -State Completed
                }
            }
            if ($ProgressEvent.Status -eq 'Completed') {
                Update-StepList -ListControl $StepList -StepIndex $index -State Completed
            } elseif ($ProgressEvent.Status -eq 'Failed') {
                Update-StepList -ListControl $StepList -StepIndex $index -State Failed
            } else {
                Update-StepList -ListControl $StepList -StepIndex $index -State Running
            }
        }

        if ($ProgressEvent.Message) {
            Add-LogLine -LogControl $LogText -Message "$($ProgressEvent.StepName) - $($ProgressEvent.Message)"
        } else {
            Add-LogLine -LogControl $LogText -Message $ProgressEvent.StepName
        }
    } elseif ($ProgressEvent.Message) {
        Add-LogLine -LogControl $LogText -Message $ProgressEvent.Message
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
            param($ModulePath, $Arguments, $Queue)
            Import-Module $ModulePath -Force
            $onProgress = {
                param($ProgressEvent)
                $null = $Queue.Enqueue($ProgressEvent)
            }
            $params = @{}
            foreach ($key in $Arguments.Keys) {
                $value = $Arguments[$key]
                if ($null -ne $value -and "$value" -ne '') {
                    $params[$key] = $value
                }
            }
            $params.OnProgress = $onProgress
            Invoke-AppGetterPackaging @params
        }).AddArgument($modulePath).
    AddArgument($PackArguments).
    AddArgument($ProgressQueue)

    return @{
        PowerShell  = $powershell
        Runspace    = $runspace
        AsyncResult = $powershell.BeginInvoke()
    }
}

function Start-AppGetterBackgroundLinkScan {
    param(
        [string]$WebsiteUrl,
        [string]$AppName
    )

    return Start-Job -ArgumentList $modulePath, $WebsiteUrl, $AppName -ScriptBlock {
        param($ModulePath, $Url, $Name)
        Import-Module $ModulePath -Force
        Find-WebDownloadLinks -Url $Url -AppName $Name
    }
}

# Main window
$mainXamlPath = Join-Path $PSScriptRoot 'AppGetter.MainWindow.xaml'
$window = Read-XamlWindow -XamlPath $mainXamlPath

$prereqText = $window.FindName('PrereqStatusText')
$installContentPrepButton = $window.FindName('InstallContentPrepButton')
$downloadUrlRadio = $window.FindName('DownloadUrlRadio')
$localFileRadio = $window.FindName('LocalFileRadio')
$websiteRadio = $window.FindName('WebsiteRadio')
$sourceBox = $window.FindName('SourceBox')
$browseSourceButton = $window.FindName('BrowseSourceButton')
$findLinksButton = $window.FindName('FindLinksButton')
$selectedAppText = $window.FindName('SelectedAppText')
$appNameBox = $window.FindName('AppNameBox')
$publisherBox = $window.FindName('PublisherBox')
$versionBox = $window.FindName('VersionBox')
$outputPathBox = $window.FindName('OutputPathBox')
$browseOutputButton = $window.FindName('BrowseOutputButton')
$developerUrlBox = $window.FindName('DeveloperUrlBox')
$supportUrlBox = $window.FindName('SupportUrlBox')
$installCommandBox = $window.FindName('InstallCommandBox')
$progressBar = $window.FindName('ProgressBar')
$progressStatus = $window.FindName('ProgressStatusText')
$stepList = $window.FindName('StepList')
$iconPreview = $window.FindName('IconPreview')
$iconStatus = $window.FindName('IconStatusText')
$browseIconButton = $window.FindName('BrowseIconButton')
$logText = $window.FindName('LogTextBox')
$openOutputButton = $window.FindName('OpenOutputButton')
$packButton = $window.FindName('PackButton')

$script:customIconPath = $null
$script:lastOutputDirectory = $null
$script:isRunning = $false
$script:resolvedDownloadUrl = $null
$script:linkScanJob = $null
$script:linkScanTimer = $null
$script:packTimer = $null
$script:packWorker = $null
$script:progressQueue = $null
$script:contentPrepInstallJob = $null
$script:contentPrepInstallTimer = $null

$stepMap = @{}
for ($i = 0; $i -lt $script:StepLabels.Count; $i++) {
    $stepMap[$i + 1] = $i
}

$settings = Get-AppGetterSettings
$script:baseOutputPath = Get-AppGetterBaseOutputPath -Path $settings.OutputPath -PackageId $settings.LastPackageId
$outputPathBox.Text = $script:baseOutputPath
$appNameBox.Text = $settings.LastAppName
$publisherBox.Text = $settings.LastPublisher
Initialize-StepList -ListControl $stepList

$script:sourceValues = @{
    DownloadUrl = $settings.LastDownloadUrl
    LocalFile   = $settings.LastInstallerPath
    Website     = $settings.LastWebsiteUrl
}
$script:currentSourceMode = $null

switch ($settings.LastSourceMode) {
    'LocalFile' { $localFileRadio.IsChecked = $true }
    'Website' { $websiteRadio.IsChecked = $true }
    default { $downloadUrlRadio.IsChecked = $true }
}

function Get-SelectedSourceMode {
    if ($localFileRadio.IsChecked) { return 'LocalFile' }
    if ($websiteRadio.IsChecked) { return 'Website' }
    return 'DownloadUrl'
}

function Get-CurrentPackageId {
    $appName = $appNameBox.Text.Trim()
    if ([string]::IsNullOrWhiteSpace($appName)) {
        return $null
    }
    return Get-PackageIdFromAppName -AppName $appName
}

function Update-OutputPathForApp {
    $packageId = Get-CurrentPackageId
    if ($packageId) {
        $outputPathBox.Text = Get-AppGetterAppOutputPath -BasePath $script:baseOutputPath -PackageId $packageId
    } else {
        $outputPathBox.Text = $script:baseOutputPath
    }
}

function Update-SourceModeDisplay {
    $mode = Get-SelectedSourceMode

    # Keep whatever the user typed for the mode they are leaving.
    if ($script:currentSourceMode -and $script:currentSourceMode -ne $mode) {
        $script:sourceValues[$script:currentSourceMode] = $sourceBox.Text
    }
    $script:currentSourceMode = $mode
    $script:resolvedDownloadUrl = $null

    switch ($mode) {
        'LocalFile' {
            $browseSourceButton.IsEnabled = $true
            $findLinksButton.IsEnabled = $false
            $sourceBox.ToolTip = 'Full path to an installer (.exe, .msi, .msix, .appx) on this computer.'
        }
        'Website' {
            $browseSourceButton.IsEnabled = $false
            $findLinksButton.IsEnabled = $true
            $sourceBox.ToolTip = 'Product page to scan for download links.'
        }
        default {
            $browseSourceButton.IsEnabled = $false
            $findLinksButton.IsEnabled = $false
            $sourceBox.ToolTip = 'Direct download URL for the installer.'
        }
    }

    $sourceBox.Text = [string]$script:sourceValues[$mode]
    Update-SelectedSourceDisplay
}

function Update-SelectedSourceDisplay {
    $mode = Get-SelectedSourceMode
    $value = $sourceBox.Text.Trim()

    if ([string]::IsNullOrWhiteSpace($value)) {
        $selectedAppText.Text = switch ($mode) {
            'LocalFile' { 'No installer file selected. Click Browse... to pick one.' }
            'Website' { 'No website entered. Enter a product page, then click Find Links...' }
            default { 'No download URL entered.' }
        }
        $selectedAppText.Foreground = ConvertTo-WpfBrush '#5C6B7A'
        return
    }

    switch ($mode) {
        'LocalFile' {
            if (Test-Path -LiteralPath $value) {
                $file = Get-Item -LiteralPath $value
                $sizeMB = [math]::Round($file.Length / 1MB, 2)
                $selectedAppText.Text = "Local installer: $($file.Name) ($sizeMB MB) | $($file.DirectoryName)"
                $selectedAppText.Foreground = ConvertTo-WpfBrush '#1B2A41'
            } else {
                $selectedAppText.Text = "File not found: $value"
                $selectedAppText.Foreground = ConvertTo-WpfBrush '#C62828'
            }
        }
        'Website' {
            if ($script:resolvedDownloadUrl) {
                $selectedAppText.Text = "Selected download link: $($script:resolvedDownloadUrl)"
                $selectedAppText.Foreground = ConvertTo-WpfBrush '#1B2A41'
            } else {
                $selectedAppText.Text = "Website: $value | Click Find Links... to choose an installer, or AppGetter picks the best match at packaging time."
                $selectedAppText.Foreground = ConvertTo-WpfBrush '#5C6B7A'
            }
        }
        default {
            $selectedAppText.Text = "Download URL: $value | File: $(Get-AppGetterInstallerFileNameFromUrl -Url $value)"
            $selectedAppText.Foreground = ConvertTo-WpfBrush '#1B2A41'
        }
    }
}

function Update-PrereqStatusDisplay {
    param(
        [object]$Prerequisites = $null
    )

    if (-not $Prerequisites) {
        $Prerequisites = Test-AppGetterPrerequisites
    }

    if ($Prerequisites.Issues.Count -eq 0) {
        $prereqText.Text = "Ready | Content Prep Tool: $($Prerequisites.ContentPrepToolPath)"
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

function Set-SourceControlsEnabled {
    param([bool]$Enabled)

    $sourceBox.IsEnabled = $Enabled
    $downloadUrlRadio.IsEnabled = $Enabled
    $localFileRadio.IsEnabled = $Enabled
    $websiteRadio.IsEnabled = $Enabled
    if ($Enabled) {
        $mode = Get-SelectedSourceMode
        $browseSourceButton.IsEnabled = ($mode -eq 'LocalFile')
        $findLinksButton.IsEnabled = ($mode -eq 'Website')
    } else {
        $browseSourceButton.IsEnabled = $false
        $findLinksButton.IsEnabled = $false
    }
}

function Set-PackControlsEnabled {
    param([bool]$Enabled)

    $packButton.IsEnabled = $Enabled
    $appNameBox.IsEnabled = $Enabled
    $publisherBox.IsEnabled = $Enabled
    $versionBox.IsEnabled = $Enabled
    $browseOutputButton.IsEnabled = $Enabled
    $browseIconButton.IsEnabled = $Enabled
    Set-SourceControlsEnabled -Enabled $Enabled

    if ($installContentPrepButton.Visibility -eq [System.Windows.Visibility]::Visible) {
        if (-not $Enabled) {
            $installContentPrepButton.IsEnabled = $false
        } else {
            # Keep disabled when winget itself is missing (tooltip explains why).
            $installContentPrepButton.IsEnabled = ($installContentPrepButton.ToolTip -notlike '*Winget is required*')
        }
    }
    if (-not $Enabled) {
        $openOutputButton.IsEnabled = $false
    }
}

$null = Update-PrereqStatusDisplay
Update-SourceModeDisplay
Update-OutputPathForApp

function Complete-AppGetterLinkScan {
    param(
        [array]$Links,
        [string]$WebsiteUrl,
        [object]$ErrorRecord = $null
    )

    Set-SourceControlsEnabled -Enabled $true
    $progressStatus.Text = 'Ready.'

    if ($ErrorRecord) {
        Add-LogLine -LogControl $logText -Message "Link scan failed: $($ErrorRecord.Exception.Message)"
        [System.Windows.MessageBox]::Show($window, "Could not scan the website.`n$($ErrorRecord.Exception.Message)", 'AppGetter', 'OK', 'Error') | Out-Null
        return
    }

    if ($Links.Count -eq 0) {
        Add-LogLine -LogControl $logText -Message "No download links found on $WebsiteUrl."
        [System.Windows.MessageBox]::Show($window, "No download links found on '$WebsiteUrl'.`n`nSwitch to Download URL and paste a direct link instead.", 'AppGetter', 'OK', 'Warning') | Out-Null
        return
    }

    Add-LogLine -LogControl $logText -Message "Found $($Links.Count) download link(s) on $WebsiteUrl."

    $picked = Show-AppGetterLinkPickerDialog -Links $Links -WebsiteUrl $WebsiteUrl -OwnerWindow $window
    if ($picked) {
        $script:resolvedDownloadUrl = $picked
        Add-LogLine -LogControl $logText -Message "Selected download link: $picked"
        Update-SelectedSourceDisplay
    } else {
        Add-LogLine -LogControl $logText -Message 'Download link selection cancelled.'
    }
}

function Invoke-AppGetterLinkScan {
    if ($script:isRunning) { return }

    $websiteUrl = $sourceBox.Text.Trim()
    if ([string]::IsNullOrWhiteSpace($websiteUrl)) {
        [System.Windows.MessageBox]::Show($window, 'Enter a website URL to scan for download links.', 'AppGetter', 'OK', 'Information') | Out-Null
        return
    }

    if ($script:linkScanTimer) {
        $script:linkScanTimer.Stop()
        $script:linkScanTimer = $null
    }
    if ($script:linkScanJob) {
        Remove-Job -Job $script:linkScanJob -Force -ErrorAction SilentlyContinue
        $script:linkScanJob = $null
    }

    Set-SourceControlsEnabled -Enabled $false
    $progressStatus.Text = "Scanning $websiteUrl for download links..."
    Add-LogLine -LogControl $logText -Message "Scanning $websiteUrl for download links..."

    $script:linkScanJob = Start-AppGetterBackgroundLinkScan -WebsiteUrl $websiteUrl -AppName $appNameBox.Text.Trim()

    $script:linkScanTimer = New-Object System.Windows.Threading.DispatcherTimer
    $script:linkScanTimer.Interval = [TimeSpan]::FromMilliseconds(200)
    $script:linkScanTimer.Add_Tick({
            if (-not $script:linkScanJob -or $script:linkScanJob.State -eq 'Running') { return }

            $script:linkScanTimer.Stop()
            $job = $script:linkScanJob
            $script:linkScanJob = $null
            $script:linkScanTimer = $null

            try {
                if ($job.State -eq 'Failed') {
                    $err = Receive-Job -Job $job -ErrorAction SilentlyContinue
                    throw ($err | Out-String)
                }
                $links = @(Receive-Job -Job $job)
                Complete-AppGetterLinkScan -Links $links -WebsiteUrl $websiteUrl
            } catch {
                Complete-AppGetterLinkScan -Links @() -WebsiteUrl $websiteUrl -ErrorRecord $_
            } finally {
                Remove-Job -Job $job -Force -ErrorAction SilentlyContinue
            }
        })
    $script:linkScanTimer.Start()
}

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
        if ($script:packWorker.PowerShell) {
            $script:packWorker.PowerShell.Dispose()
        }
        if ($script:packWorker.Runspace) {
            $script:packWorker.Runspace.Close()
        }
        $script:packWorker = $null
    }

    $script:progressQueue = $null
    $script:isRunning = $false
    Set-PackControlsEnabled -Enabled $true

    if ($ErrorRecord) {
        $progressStatus.Text = 'Packaging failed.'
        Add-LogLine -LogControl $logText -Message "Packaging failed: $($ErrorRecord.Exception.Message)"
        [System.Windows.MessageBox]::Show(
            $window,
            "Packaging failed.`n`n$($ErrorRecord.Exception.Message)`n`nSee appgetter-packaging.log in the output folder if it was created.",
            'AppGetter',
            'OK',
            'Error'
        ) | Out-Null
        return
    }

    $script:lastOutputDirectory = $Result.VersionDirectory
    $openOutputButton.IsEnabled = $true

    $Result = Invoke-PostPackagingIconSelection -Result $Result -OwnerWindow $window `
        -IconPreview $iconPreview -IconStatus $iconStatus -LogText $logText
    Set-IconPreview -ImageControl $iconPreview -StatusControl $iconStatus -ImagePath $Result.IconFile

    if ($Result.PackagingSucceeded) {
        $progressStatus.Text = 'Packaging completed successfully.'
        Add-LogLine -LogControl $logText -Message "Success: $($Result.IntuneWinFile)"
        [System.Windows.MessageBox]::Show(
            $window,
            "Package created successfully.`n`n$($Result.DisplayName)`n$($Result.IntuneWinFile)",
            'AppGetter',
            'OK',
            'Information'
        ) | Out-Null
    } else {
        $progressStatus.Text = 'Packaging completed with warnings.'
        Add-LogLine -LogControl $logText -Message 'Metadata and scripts created, but .intunewin packaging failed or Content Prep Tool is unavailable.'
        [System.Windows.MessageBox]::Show(
            $window,
            "Package files were created, but the .intunewin step did not complete.`n`nOutput: $($Result.VersionDirectory)`n`nCheck appgetter-packaging.log for details.",
            'AppGetter',
            'OK',
            'Warning'
        ) | Out-Null
    }
}

function Start-AppGetterPackagingFromUi {
    $appName = $appNameBox.Text.Trim()
    if ([string]::IsNullOrWhiteSpace($appName)) {
        [System.Windows.MessageBox]::Show($window, 'Enter the application name before packaging.', 'AppGetter', 'OK', 'Warning') | Out-Null
        return
    }

    $mode = Get-SelectedSourceMode
    $sourceValue = $sourceBox.Text.Trim()
    if ([string]::IsNullOrWhiteSpace($sourceValue)) {
        $prompt = switch ($mode) {
            'LocalFile' { 'Choose the installer file to package.' }
            'Website' { 'Enter the website to scan for a download link.' }
            default { 'Enter the direct download URL for the installer.' }
        }
        [System.Windows.MessageBox]::Show($window, $prompt, 'AppGetter', 'OK', 'Warning') | Out-Null
        return
    }

    if ($mode -eq 'LocalFile' -and -not (Test-Path -LiteralPath $sourceValue)) {
        [System.Windows.MessageBox]::Show($window, "Installer file not found:`n$sourceValue", 'AppGetter', 'OK', 'Warning') | Out-Null
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
    $script:baseOutputPath = Get-AppGetterBaseOutputPath -Path $outputPathBox.Text.Trim() -PackageId $packageId
    # Always pack into a folder named after the app.
    $appOutputPath = Get-AppGetterAppOutputPath -BasePath $script:baseOutputPath -PackageId $packageId
    $outputPathBox.Text = $appOutputPath

    $packArguments = @{
        AppName               = $appName
        Publisher             = $publisherBox.Text.Trim()
        Version               = $versionBox.Text.Trim()
        DeveloperUrl          = $developerUrlBox.Text.Trim()
        SupportUrl            = $supportUrlBox.Text.Trim()
        InstallCommand        = $installCommandBox.Text.Trim()
        OutputPath            = $appOutputPath
        IconPath              = $script:customIconPath
        CollectIconCandidates = $true
    }

    switch ($mode) {
        'LocalFile' {
            $packArguments.InstallerPath = $sourceValue
        }
        'Website' {
            $packArguments.WebsiteUrl = $sourceValue
            if ($script:resolvedDownloadUrl) {
                $packArguments.DownloadUrl = $script:resolvedDownloadUrl
            }
        }
        default {
            $packArguments.DownloadUrl = $sourceValue
        }
    }

    $script:progressQueue = New-Object System.Collections.Concurrent.ConcurrentQueue[object]
    Add-LogLine -LogControl $logText -Message "Starting packaging for $appName ($mode)..."

    $script:packWorker = Start-AppGetterBackgroundPackaging -PackArguments $packArguments -ProgressQueue $script:progressQueue

    $script:packTimer = New-Object System.Windows.Threading.DispatcherTimer
    $script:packTimer.Interval = [TimeSpan]::FromMilliseconds(150)
    $script:packTimer.Add_Tick({
            $item = $null
            while ($script:progressQueue -and $script:progressQueue.TryDequeue([ref]$item)) {
                Invoke-UiProgressUpdate -ProgressEvent $item -ProgressBar $progressBar -ProgressStatus $progressStatus `
                    -StepList $stepList -LogText $logText -StepMap $stepMap
            }

            if (-not $script:packWorker) { return }

            if ($script:packWorker.AsyncResult.IsCompleted) {
                $item = $null
                while ($script:progressQueue -and $script:progressQueue.TryDequeue([ref]$item)) {
                    Invoke-UiProgressUpdate -ProgressEvent $item -ProgressBar $progressBar -ProgressStatus $progressStatus `
                        -StepList $stepList -LogText $logText -StepMap $stepMap
                }

                $worker = $script:packWorker
                try {
                    $result = $worker.PowerShell.EndInvoke($worker.AsyncResult)
                    if ($result -is [array] -and $result.Count -eq 1) {
                        $result = $result[0]
                    }
                    Complete-AppGetterPackaging -Result $result
                } catch {
                    Complete-AppGetterPackaging -ErrorRecord $_
                }
            }
        })
    $script:packTimer.Start()
}

$downloadUrlRadio.Add_Checked({ Update-SourceModeDisplay })
$localFileRadio.Add_Checked({ Update-SourceModeDisplay })
$websiteRadio.Add_Checked({ Update-SourceModeDisplay })

$sourceBox.Add_TextChanged({
        $script:resolvedDownloadUrl = $null
        Update-SelectedSourceDisplay
    })

$appNameBox.Add_LostFocus({ Update-OutputPathForApp })

$browseSourceButton.Add_Click({
        try {
            $initialDirectory = $null
            if ($sourceBox.Text -and (Test-Path -LiteralPath $sourceBox.Text)) {
                $initialDirectory = Split-Path -Parent $sourceBox.Text
            }

            $path = Show-OpenFileDialog -OwnerWindow $window -Title 'Select the installer to package' `
                -InitialDirectory $initialDirectory `
                -Filter 'Installers (*.exe;*.msi;*.msix;*.appx)|*.exe;*.msi;*.msix;*.appx|All files (*.*)|*.*'

            if ($path) {
                $sourceBox.Text = $path
                if ([string]::IsNullOrWhiteSpace($appNameBox.Text)) {
                    $appNameBox.Text = [System.IO.Path]::GetFileNameWithoutExtension($path)
                    Update-OutputPathForApp
                }
                Add-LogLine -LogControl $logText -Message "Local installer selected: $path"
            }
        } catch {
            Add-LogLine -LogControl $logText -Message "File browser failed: $($_.Exception.Message)"
            [System.Windows.MessageBox]::Show(
                $window,
                "Could not open the file browser.`n`n$($_.Exception.Message)",
                'AppGetter',
                'OK',
                'Error'
            ) | Out-Null
        }
    })

$findLinksButton.Add_Click({ Invoke-AppGetterLinkScan })

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
                Update-OutputPathForApp
                Save-AppGetterSettings -OutputPath $script:baseOutputPath -LastPackageId (Get-CurrentPackageId)
                Add-LogLine -LogControl $logText -Message "Output base folder set to: $path"
            }
        } catch {
            Add-LogLine -LogControl $logText -Message "Folder browser failed: $($_.Exception.Message)"
            [System.Windows.MessageBox]::Show(
                $window,
                "Could not open the folder browser.`n`n$($_.Exception.Message)",
                'AppGetter',
                'OK',
                'Error'
            ) | Out-Null
        }
    })

$browseIconButton.Add_Click({
        try {
            $path = Show-OpenFileDialog -OwnerWindow $window -Title 'Select a custom icon'
            if ($path) {
                $script:customIconPath = $path
                Set-IconPreview -ImageControl $iconPreview -StatusControl $iconStatus -ImagePath $path
                Add-LogLine -LogControl $logText -Message "Custom icon selected: $path"
            }
        } catch {
            Add-LogLine -LogControl $logText -Message "Icon browser failed: $($_.Exception.Message)"
            [System.Windows.MessageBox]::Show(
                $window,
                "Could not open the file browser.`n`n$($_.Exception.Message)",
                'AppGetter',
                'OK',
                'Error'
            ) | Out-Null
        }
    })

$openOutputButton.Add_Click({
        if ($script:lastOutputDirectory -and (Test-Path $script:lastOutputDirectory)) {
            Start-Process explorer.exe $script:lastOutputDirectory | Out-Null
        }
    })

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

        if ($script:contentPrepInstallTimer) {
            $script:contentPrepInstallTimer.Stop()
        }

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
                    if ($result -is [array] -and $result.Count -eq 1) {
                        $result = $result[0]
                    }

                    $prereqs = if ($result.Prerequisites) { $result.Prerequisites } else { Test-AppGetterPrerequisites }
                    $null = Update-PrereqStatusDisplay -Prerequisites $prereqs

                    if ($result.Succeeded -and $prereqs.ContentPrepToolInstalled) {
                        $pathNote = if ($result.ContentPrepToolPath) { $result.ContentPrepToolPath } else { 'available on PATH' }
                        Add-LogLine -LogControl $logText -Message "Content Prep Tool installed: $pathNote"
                        [System.Windows.MessageBox]::Show(
                            $window,
                            "Content Prep Tool is ready.`n`n$pathNote",
                            'AppGetter',
                            'OK',
                            'Information'
                        ) | Out-Null
                    } else {
                        throw 'Install finished but intunewinapputil is still not available. You may need to restart AppGetter or add the tool to PATH.'
                    }
                } catch {
                    Add-LogLine -LogControl $logText -Message "Content Prep Tool install failed: $($_.Exception.Message)"
                    $null = Update-PrereqStatusDisplay
                    [System.Windows.MessageBox]::Show(
                        $window,
                        "Could not install the Content Prep Tool.`n`n$($_.Exception.Message)",
                        'AppGetter',
                        'OK',
                        'Error'
                    ) | Out-Null
                } finally {
                    Remove-Job -Job $job -Force -ErrorAction SilentlyContinue
                }
            })
        $script:contentPrepInstallTimer.Start()
    })

$window.Add_Closed({
        if ($script:linkScanTimer) { $script:linkScanTimer.Stop() }
        if ($script:packTimer) { $script:packTimer.Stop() }
        if ($script:contentPrepInstallTimer) { $script:contentPrepInstallTimer.Stop() }
        if ($script:linkScanJob) { Remove-Job -Job $script:linkScanJob -Force -ErrorAction SilentlyContinue }
        if ($script:contentPrepInstallJob) { Remove-Job -Job $script:contentPrepInstallJob -Force -ErrorAction SilentlyContinue }
        if ($script:packWorker -and $script:packWorker.PowerShell) {
            try { $script:packWorker.PowerShell.Stop() } catch { }
            $script:packWorker.PowerShell.Dispose()
            $script:packWorker.Runspace.Close()
        }
    })

if ($settings.LastAppName) {
    Add-LogLine -LogControl $logText -Message "Last packaged app: $($settings.LastAppName)"
}

Add-LogLine -LogControl $logText -Message 'AppGetter GUI ready.'
[void]$window.ShowDialog()
