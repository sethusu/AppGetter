<#
.SYNOPSIS
    Launches the AppGetter graphical user interface.
.DESCRIPTION
    WPF-based GUI for entering web download details, choosing output destination,
    tracking live packaging progress, and previewing icons.
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

function Set-IconPreview {
    param(
        $ImageControl,
        $StatusControl,
        [string]$ImagePath
    )

    if ($ImagePath -and (Test-Path $ImagePath)) {
        try {
            $bitmap = New-Object System.Windows.Media.Imaging.BitmapImage
            $bitmap.BeginInit()
            $bitmap.CacheOption = [System.Windows.Media.Imaging.BitmapCacheOption]::OnLoad
            $bitmap.UriSource = [Uri]::new((Resolve-Path $ImagePath).Path)
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
    $bitmap.UriSource = [Uri]::new((Resolve-Path $ImagePath).Path)
    $bitmap.EndInit()
    $bitmap.Freeze()
    return $bitmap
}

function Show-AppGetterDownloadLinkDialog {
    param(
        [array]$Links,
        [string]$WebsiteUrl,
        $OwnerWindow
    )

    $dialogPath = Join-Path $PSScriptRoot 'AppGetter.DownloadLinkDialog.xaml'
    $dialogWindow = Read-XamlWindow -XamlPath $dialogPath
    $dialogWindow.Owner = $OwnerWindow

    $summary = $dialogWindow.FindName('LinkSummaryText')
    $panel = $dialogWindow.FindName('ResultsPanel')
    $selectButton = $dialogWindow.FindName('SelectButton')
    $cancelButton = $dialogWindow.FindName('CancelButton')

    $summary.Text = "Found $($Links.Count) download link(s) on '$WebsiteUrl'. Select the installer to package."

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

        $radio = New-Object System.Windows.Controls.RadioButton
        $radio.GroupName = 'AppGetterLinkSelection'
        $radio.Content = $link
        $radio.Tag = $link
        $radio.TextWrapping = [System.Windows.TextWrapping]::Wrap

        $capturedLink = $link
        $radio.Add_Checked({ $dialogSelection.Link = $capturedLink })

        if (-not $firstRadio) {
            $firstRadio = $radio
            $dialogSelection.Link = $link
        }

        $border.Child = $radio
        $panel.Children.Add($border) | Out-Null
    }

    if ($firstRadio) { $firstRadio.IsChecked = $true }

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
        if ($candidate.Path -and (Test-Path $candidate.Path)) {
            try { $image.Source = New-WpfBitmapImage -ImagePath $candidate.Path } catch { $image.Source = $null }
        }

        $sourceText = New-Object System.Windows.Controls.TextBlock
        $sourceText.Text = "Source: $($candidate.Source)"
        $sourceText.Foreground = ConvertTo-WpfBrush '#5C6B7A'
        $sourceText.FontSize = 12
        $sourceText.TextAlignment = [System.Windows.TextAlignment]::Center

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

    if ($dialogWindow.ShowDialog()) { return $dialogWindow.Tag }
    return $null
}

function Add-LogLine {
    param($LogControl, [string]$Message)
    $timestamp = Get-Date -Format 'HH:mm:ss'
    $LogControl.AppendText("[$timestamp] $Message`r`n")
    $LogControl.ScrollToEnd()
}

$script:StepLabels = @(
    'Load package details'
    'Create output directories'
    'Download installer from web'
    'Calculate installer hash'
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
    param($ListControl, [int]$StepIndex, [ValidateSet('Pending', 'Running', 'Completed', 'Failed')][string]$State)
    if ($StepIndex -lt 0 -or $StepIndex -ge $script:StepLabels.Count) { return }
    $script:StepStates[$StepIndex] = $State
    $ListControl.Items[$StepIndex] = New-StepListItem -Index $StepIndex
}

function Invoke-UiProgressUpdate {
    param($Event, $ProgressBar, $ProgressStatus, $StepList, $LogText, $StepMap)

    if ($Event.Type -eq 'Progress') {
        if ($Event.Percent -ge 0) { $ProgressBar.Value = [math]::Min(100, $Event.Percent) }
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
        param($ModulePath, $PackArguments, $Queue)
        Import-Module $ModulePath -Force
        $onProgress = { param($Event) $null = $Queue.Enqueue($Event) }
        $params = @{
            AppName = $PackArguments.AppName
            OutputPath = $PackArguments.OutputPath
            OnProgress = $onProgress
            CollectIconCandidates = [bool]$PackArguments.CollectIconCandidates
        }
        foreach ($key in @('WebsiteUrl', 'DownloadUrl', 'Version', 'Publisher', 'DeveloperUrl', 'SupportUrl', 'IconPath', 'InstallCommand')) {
            if ($PackArguments.ContainsKey($key) -and $PackArguments[$key]) {
                $params[$key] = $PackArguments[$key]
            }
        }
        Invoke-AppGetterPackaging @params
    }).AddArgument($modulePath).AddArgument($PackArguments).AddArgument($ProgressQueue)

    return @{
        PowerShell = $powershell
        Runspace = $runspace
        AsyncResult = $powershell.BeginInvoke()
    }
}

$mainXamlPath = Join-Path $PSScriptRoot 'AppGetter.MainWindow.xaml'
$window = Read-XamlWindow -XamlPath $mainXamlPath

$prereqText = $window.FindName('PrereqStatusText')
$appNameBox = $window.FindName('AppNameBox')
$websiteUrlBox = $window.FindName('WebsiteUrlBox')
$downloadUrlBox = $window.FindName('DownloadUrlBox')
$findLinksButton = $window.FindName('FindLinksButton')
$outputPathBox = $window.FindName('OutputPathBox')
$browseOutputButton = $window.FindName('BrowseOutputButton')
$versionBox = $window.FindName('VersionBox')
$publisherBox = $window.FindName('PublisherBox')
$developerUrlBox = $window.FindName('DeveloperUrlBox')
$supportUrlBox = $window.FindName('SupportUrlBox')
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
$script:packTimer = $null
$script:packWorker = $null
$script:progressQueue = $null

$stepMap = @{ 1 = 0; 2 = 1; 3 = 2; 4 = 3; 5 = 4; 6 = 5; 7 = 6; 8 = 7; 9 = 8; 10 = 9; 12 = 10 }

$settings = Get-AppGetterSettings
$outputPathBox.Text = $settings.OutputPath
$appNameBox.Text = $settings.LastAppName
$websiteUrlBox.Text = $settings.LastWebsiteUrl
$downloadUrlBox.Text = $settings.LastDownloadUrl
Initialize-StepList -ListControl $stepList

$prereqs = Test-AppGetterPrerequisites
if ($prereqs.Issues.Count -eq 0) {
    $prereqText.Text = "Ready | Content Prep Tool: $($prereqs.ContentPrepToolPath)"
    $prereqText.Foreground = ConvertTo-WpfBrush '#2E7D32'
} else {
    $prereqText.Text = 'Missing prerequisites: ' + ($prereqs.Issues -join ' ')
    $prereqText.Foreground = ConvertTo-WpfBrush '#C62828'
}

function Set-PackControlsEnabled {
    param([bool]$Enabled)
    $packButton.IsEnabled = $Enabled
    $findLinksButton.IsEnabled = $Enabled
    $browseOutputButton.IsEnabled = $Enabled
    $browseIconButton.IsEnabled = $Enabled
    if (-not $Enabled) { $openOutputButton.IsEnabled = $false }
}

function Complete-AppGetterPackaging {
    param([object]$Result = $null, [object]$ErrorRecord = $null)

    if ($script:packTimer) { $script:packTimer.Stop(); $script:packTimer = $null }
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

    if (-not $Result.UsedCustomIcon -and $Result.IconCandidates -and $Result.IconCandidates.Count -ge 2 -and $Result.LogoFile -and $Result.IconFile) {
        $selected = Show-AppGetterIconPickerDialog -Candidates $Result.IconCandidates -DisplayName $Result.DisplayName `
            -PackageId $Result.PackageId -OwnerWindow $window
        if ($selected) {
            Set-AppGetterPackageIconFiles -SourceIconPath $selected.Path -LogoFilePath $Result.LogoFile -IconFilePath $Result.IconFile
            Add-LogLine -LogControl $logText -Message "Applied selected icon from $($selected.Source)"
        }
    }

    Set-IconPreview -ImageControl $iconPreview -StatusControl $iconStatus -ImagePath $Result.IconFile

    if ($Result.PackagingSucceeded) {
        $progressStatus.Text = 'Packaging completed successfully.'
        Add-LogLine -LogControl $logText -Message "Success: $($Result.IntuneWinFile)"
        [System.Windows.MessageBox]::Show($window, "Package created successfully.`n`n$($Result.DisplayName)`n$($Result.IntuneWinFile)", 'AppGetter', 'OK', 'Information') | Out-Null
    } else {
        $progressStatus.Text = 'Packaging completed with warnings.'
        Add-LogLine -LogControl $logText -Message 'Metadata created, but .intunewin packaging failed or Content Prep Tool is unavailable.'
        [System.Windows.MessageBox]::Show($window, "Package files were created, but the .intunewin step did not complete.`n`nOutput: $($Result.VersionDirectory)", 'AppGetter', 'OK', 'Warning') | Out-Null
    }
}

function Start-AppGetterPackagingFromUi {
    if ([string]::IsNullOrWhiteSpace($appNameBox.Text)) {
        [System.Windows.MessageBox]::Show($window, 'Enter an application name before packaging.', 'AppGetter', 'OK', 'Warning') | Out-Null
        return
    }

    if ([string]::IsNullOrWhiteSpace($websiteUrlBox.Text) -and [string]::IsNullOrWhiteSpace($downloadUrlBox.Text)) {
        [System.Windows.MessageBox]::Show($window, 'Enter a website URL or direct download URL.', 'AppGetter', 'OK', 'Warning') | Out-Null
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

    $packArguments = @{
        AppName = $appNameBox.Text.Trim()
        WebsiteUrl = $websiteUrlBox.Text.Trim()
        DownloadUrl = $downloadUrlBox.Text.Trim()
        Version = $versionBox.Text.Trim()
        Publisher = $publisherBox.Text.Trim()
        DeveloperUrl = $developerUrlBox.Text.Trim()
        SupportUrl = $supportUrlBox.Text.Trim()
        OutputPath = $outputPathBox.Text.Trim()
        IconPath = $script:customIconPath
        CollectIconCandidates = $true
    }

    Save-AppGetterSettings -OutputPath $packArguments.OutputPath -LastAppName $packArguments.AppName `
        -LastWebsiteUrl $packArguments.WebsiteUrl -LastDownloadUrl $packArguments.DownloadUrl

    $script:progressQueue = New-Object System.Collections.Concurrent.ConcurrentQueue[object]
    Add-LogLine -LogControl $logText -Message "Starting packaging for $($packArguments.AppName)..."

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
            $item = $null
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

$findLinksButton.Add_Click({
    if ([string]::IsNullOrWhiteSpace($websiteUrlBox.Text)) {
        [System.Windows.MessageBox]::Show($window, 'Enter a website URL to scan for download links.', 'AppGetter', 'OK', 'Information') | Out-Null
        return
    }

    try {
        Add-LogLine -LogControl $logText -Message "Scanning $($websiteUrlBox.Text) for download links..."
        $links = Get-WebDownloadLinks -WebsiteUrl $websiteUrlBox.Text.Trim() -AppName $appNameBox.Text.Trim()
        if ($links.Count -eq 0) {
            Add-LogLine -LogControl $logText -Message 'No download links found.'
            [System.Windows.MessageBox]::Show($window, 'No download links were found on that page.', 'AppGetter', 'OK', 'Warning') | Out-Null
            return
        }

        $picked = Show-AppGetterDownloadLinkDialog -Links $links -WebsiteUrl $websiteUrlBox.Text.Trim() -OwnerWindow $window
        if ($picked) {
            $downloadUrlBox.Text = $picked
            Add-LogLine -LogControl $logText -Message "Selected download link: $picked"
        }
    } catch {
        Add-LogLine -LogControl $logText -Message "Link scan failed: $($_.Exception.Message)"
    }
})

$browseOutputButton.Add_Click({
    $path = Show-FolderBrowser -Description 'Select output destination for AppGetter packages' -SelectedPath $outputPathBox.Text
    if ($path) {
        $outputPathBox.Text = $path
        Save-AppGetterSettings -OutputPath $path
    }
})

$browseIconButton.Add_Click({
    $path = Show-OpenFileDialog
    if ($path) {
        $script:customIconPath = $path
        Set-IconPreview -ImageControl $iconPreview -StatusControl $iconStatus -ImagePath $path
        Add-LogLine -LogControl $logText -Message "Custom icon selected: $path"
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

$window.Add_Closed({
    if ($script:packTimer) { $script:packTimer.Stop() }
    if ($script:packWorker -and $script:packWorker.PowerShell) {
        try { $script:packWorker.PowerShell.Stop() } catch { }
        $script:packWorker.PowerShell.Dispose()
        $script:packWorker.Runspace.Close()
    }
})

Add-LogLine -LogControl $logText -Message 'AppGetter GUI ready.'
[void]$window.ShowDialog()
