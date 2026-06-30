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
Import-Module (Join-Path $moduleRoot 'AppGetter.psd1') -Force

$brushConverter = New-Object System.Windows.Media.BrushConverter

function ConvertTo-WpfBrush {
    param([string]$Color)
    return $brushConverter.ConvertFromString($Color)
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
    'Resolve download URL'
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
    param(
        $ListControl,
        [int]$StepIndex,
        [ValidateSet('Pending', 'Running', 'Completed', 'Failed')]
        [string]$State
    )

    if ($StepIndex -ge 0 -and $StepIndex -lt $script:StepStates.Count) {
        $script:StepStates[$StepIndex] = $State
        $ListControl.Items[$StepIndex] = New-StepListItem -Index $StepIndex
    }
}

function Reset-StepList {
    param($ListControl)
    Initialize-StepList -ListControl $ListControl
}

function Update-PrereqStatus {
    param($StatusControl)
    $prereq = Test-AppGetterPrerequisites
    if ($prereq.ContentPrepToolInstalled) {
        $StatusControl.Text = "Content Prep Tool found: $($prereq.ContentPrepToolPath)"
        $StatusControl.Foreground = ConvertTo-WpfBrush '#2E7D32'
    } else {
        $StatusControl.Text = 'Content Prep Tool (intunewinapputil) not found on PATH. Metadata will be created, but .intunewin packaging will fail.'
        $StatusControl.Foreground = ConvertTo-WpfBrush '#C62828'
    }
}

$windowPath = Join-Path $PSScriptRoot 'AppGetter.MainWindow.xaml'
$window = Read-XamlWindow -XamlPath $windowPath

$prereqStatus = $window.FindName('PrereqStatusText')
$appNameBox = $window.FindName('AppNameBox')
$publisherBox = $window.FindName('PublisherBox')
$websiteUrlBox = $window.FindName('WebsiteUrlBox')
$downloadUrlBox = $window.FindName('DownloadUrlBox')
$developerUrlBox = $window.FindName('DeveloperUrlBox')
$supportUrlBox = $window.FindName('SupportUrlBox')
$versionBox = $window.FindName('VersionBox')
$outputPathBox = $window.FindName('OutputPathBox')
$progressBar = $window.FindName('ProgressBar')
$progressStatus = $window.FindName('ProgressStatusText')
$stepList = $window.FindName('StepList')
$logText = $window.FindName('LogTextBox')
$iconPreview = $window.FindName('IconPreview')
$iconStatus = $window.FindName('IconStatusText')
$browseOutputButton = $window.FindName('BrowseOutputButton')
$browseIconButton = $window.FindName('BrowseIconButton')
$openOutputButton = $window.FindName('OpenOutputButton')
$packButton = $window.FindName('PackButton')

$settings = Get-AppGetterSettings
$outputPathBox.Text = $settings.OutputPath
$appNameBox.Text = $settings.LastAppName
$websiteUrlBox.Text = $settings.LastWebsiteUrl
$downloadUrlBox.Text = $settings.LastDownloadUrl

Update-PrereqStatus -StatusControl $prereqStatus
Initialize-StepList -ListControl $stepList
Add-LogLine -LogControl $logText -Message 'AppGetter ready.'

$script:CustomIconPath = $null
$script:LastOutputDirectory = $null
$script:IsPackaging = $false

$browseOutputButton.Add_Click({
    $selected = Show-FolderBrowser -Description 'Select output folder for AppGetter packages' -SelectedPath $outputPathBox.Text
    if ($selected) {
        $outputPathBox.Text = $selected
    }
})

$browseIconButton.Add_Click({
    $selected = Show-OpenFileDialog
    if ($selected) {
        $script:CustomIconPath = $selected
        Set-IconPreview -ImageControl $iconPreview -StatusControl $iconStatus -ImagePath $selected
        Add-LogLine -LogControl $logText -Message "Custom icon selected: $selected"
    }
})

$openOutputButton.Add_Click({
    if ($script:LastOutputDirectory -and (Test-Path $script:LastOutputDirectory)) {
        Start-Process explorer.exe $script:LastOutputDirectory | Out-Null
    }
})

$packButton.Add_Click({
    if ($script:IsPackaging) { return }

    $appName = $appNameBox.Text.Trim()
    $websiteUrl = $websiteUrlBox.Text.Trim()
    $downloadUrl = $downloadUrlBox.Text.Trim()

    if ([string]::IsNullOrWhiteSpace($appName)) {
        [System.Windows.MessageBox]::Show($window, 'Application name is required.', 'AppGetter', 'OK', 'Warning') | Out-Null
        return
    }

    if ([string]::IsNullOrWhiteSpace($websiteUrl) -and [string]::IsNullOrWhiteSpace($downloadUrl)) {
        [System.Windows.MessageBox]::Show($window, 'Provide a Website URL or Direct Download URL.', 'AppGetter', 'OK', 'Warning') | Out-Null
        return
    }

    $script:IsPackaging = $true
    $packButton.IsEnabled = $false
    $openOutputButton.IsEnabled = $false
    Reset-StepList -ListControl $stepList
    $progressBar.Value = 0
    $progressStatus.Text = 'Starting packaging...'
    Add-LogLine -LogControl $logText -Message "Packaging $appName..."

    $onProgress = {
        param($ProgressEvent)
        $window.Dispatcher.Invoke([Action]{
            if ($ProgressEvent.Type -eq 'Progress') {
                $stepIndex = [math]::Max(0, [math]::Min($ProgressEvent.Step - 1, $script:StepLabels.Count - 1))
                Update-StepList -ListControl $stepList -StepIndex $stepIndex -State 'Running'
                for ($i = 0; $i -lt $stepIndex; $i++) {
                    if ($script:StepStates[$i] -ne 'Completed') {
                        Update-StepList -ListControl $stepList -StepIndex $i -State 'Completed'
                    }
                }
                if ($ProgressEvent.Status -eq 'Completed') {
                    for ($i = 0; $i -lt $script:StepLabels.Count; $i++) {
                        Update-StepList -ListControl $stepList -StepIndex $i -State 'Completed'
                    }
                } elseif ($ProgressEvent.Status -eq 'Failed') {
                    Update-StepList -ListControl $stepList -StepIndex $stepIndex -State 'Failed'
                }
                $progressBar.Value = [math]::Max(0, [math]::Min(100, $ProgressEvent.Percent))
                $message = if ($ProgressEvent.Message) { " - $($ProgressEvent.Message)" } else { '' }
                $progressStatus.Text = "$($ProgressEvent.StepName)$message"
                Add-LogLine -LogControl $logText -Message "[$($ProgressEvent.StepName)]$message"
            } else {
                Add-LogLine -LogControl $logText -Message $ProgressEvent.Message
            }
        })
    }

    try {
        $result = Invoke-AppGetterPackaging -AppName $appName -WebsiteUrl $websiteUrl -DownloadUrl $downloadUrl `
            -DeveloperUrl $developerUrlBox.Text.Trim() -SupportUrl $supportUrlBox.Text.Trim() `
            -Version $versionBox.Text.Trim() -Publisher $publisherBox.Text.Trim() `
            -OutputPath $outputPathBox.Text.Trim() -IconPath $script:CustomIconPath -OnProgress $onProgress

        $script:LastOutputDirectory = $result.VersionDirectory
        $openOutputButton.IsEnabled = $true

        if ($result.IconFile) {
            Set-IconPreview -ImageControl $iconPreview -StatusControl $iconStatus -ImagePath $result.IconFile
        }

        if ($result.PackagingSucceeded) {
            Add-LogLine -LogControl $logText -Message "Package created: $($result.IntuneWinFile)"
            [System.Windows.MessageBox]::Show($window, "Package created successfully.`n`n$($result.IntuneWinFile)", 'AppGetter', 'OK', 'Information') | Out-Null
        } else {
            Add-LogLine -LogControl $logText -Message 'Metadata created. .intunewin packaging failed or Content Prep Tool unavailable.'
            [System.Windows.MessageBox]::Show($window, 'Metadata files were created, but .intunewin packaging failed or Content Prep Tool is unavailable.', 'AppGetter', 'OK', 'Warning') | Out-Null
        }
    }
    catch {
        Add-LogLine -LogControl $logText -Message "ERROR: $($_.Exception.Message)"
        $progressStatus.Text = 'Packaging failed.'
        [System.Windows.MessageBox]::Show($window, $_.Exception.Message, 'AppGetter', 'OK', 'Error') | Out-Null
    }
    finally {
        $script:IsPackaging = $false
        $packButton.IsEnabled = $true
    }
})

$null = $window.ShowDialog()
