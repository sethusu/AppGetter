<#
.SYNOPSIS
    Launches the AppGetter graphical user interface.
.DESCRIPTION
    WPF-based GUI for entering a download URL or picking a local installer file,
    choosing output destination, tracking live packaging progress, and previewing icons.
    Mirrors the Wingetter GUI architecture: packaging runs in a background runspace so
    the window stays responsive, and the Content Prep Tool can be installed from the UI.
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
    # Non-fatal — dialogs can still open without visual styles.
}

$moduleRoot = Split-Path -Parent $PSScriptRoot
$modulePath = Join-Path $moduleRoot 'AppGetter.psd1'
Import-Module $modulePath -Force

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
    $chosenPath = $null
    try {
        $result = if ($owner) { $dialog.ShowDialog($owner) } else { $dialog.ShowDialog() }
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
        [string]$Title = '',
        $OwnerWindow = $null
    )

    $dialog = New-Object System.Windows.Forms.OpenFileDialog
    $dialog.Filter = $Filter
    if ($Title) {
        $dialog.Title = $Title
    }
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
        if ($owner) {
            try { $owner.ReleaseHandle() } catch { }
        }
        $dialog.Dispose()
    }

    return $chosenPath
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

function Get-AppGetterPackageIdPreview {
    param([string]$AppName)
    return ($AppName -replace '[^a-zA-Z0-9]', '')
}

$script:StepLabels = @(
    'Load package details'
    'Create output directories'
    'Resolve installer source'
    'Download or copy installer'
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

    if ($StepIndex -lt 0 -or $StepIndex -ge $script:StepLabels.Count) {
        return
    }

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
                for ($i = $index; $i -lt $script:StepLabels.Count; $i++) {
                    Update-StepList -ListControl $StepList -StepIndex $i -State Completed
                }
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
        $onProgress = {
            param($Event)
            $null = $Queue.Enqueue($Event)
        }
        $params = @{
            AppName    = $PackArguments.AppName
            OutputPath = $PackArguments.OutputPath
            OnProgress = $onProgress
        }
        foreach ($key in @('WebsiteUrl', 'DownloadUrl', 'InstallerPath', 'DeveloperUrl', 'SupportUrl', 'Version', 'Publisher', 'IconPath')) {
            if ($PackArguments[$key]) { $params[$key] = $PackArguments[$key] }
        }
        Invoke-AppGetterPackaging @params
    }).AddArgument($modulePath).
      AddArgument($PackArguments).
      AddArgument($ProgressQueue)

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
$websiteUrlBox = $window.FindName('WebsiteUrlBox')
$downloadUrlBox = $window.FindName('DownloadUrlBox')
$installerPathBox = $window.FindName('InstallerPathBox')
$browseInstallerButton = $window.FindName('BrowseInstallerButton')
$developerUrlBox = $window.FindName('DeveloperUrlBox')
$supportUrlBox = $window.FindName('SupportUrlBox')
$versionBox = $window.FindName('VersionBox')
$outputPathBox = $window.FindName('OutputPathBox')
$browseOutputButton = $window.FindName('BrowseOutputButton')
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
$script:contentPrepInstallJob = $null
$script:contentPrepInstallTimer = $null

$stepMap = @{
    1 = 0; 2 = 1; 3 = 2; 4 = 3; 5 = 4; 6 = 5; 7 = 6; 8 = 7; 9 = 8; 10 = 9; 11 = 10; 12 = 11; 13 = 12
}

$settings = Get-AppGetterSettings
$script:baseOutputPath = Get-AppGetterBaseOutputPath -Path $settings.OutputPath `
    -PackageId (Get-AppGetterPackageIdPreview -AppName $settings.LastAppName)
$appNameBox.Text = $settings.LastAppName
$websiteUrlBox.Text = $settings.LastWebsiteUrl
$downloadUrlBox.Text = $settings.LastDownloadUrl
$installerPathBox.Text = $settings.LastInstallerPath
Initialize-StepList -ListControl $stepList

function Update-OutputPathForApp {
    $packageId = Get-AppGetterPackageIdPreview -AppName $appNameBox.Text.Trim()
    if ($packageId) {
        $outputPathBox.Text = Get-AppGetterAppOutputPath -BasePath $script:baseOutputPath -PackageId $packageId
    } else {
        $outputPathBox.Text = $script:baseOutputPath
    }
}

Update-OutputPathForApp

function Update-PrereqStatusDisplay {
    param(
        [object]$Prerequisites = $null
    )

    if (-not $Prerequisites) {
        $Prerequisites = Test-AppGetterPrerequisites
    }

    if ($Prerequisites.ContentPrepToolInstalled) {
        $prereqText.Text = "Ready | Content Prep Tool: $($Prerequisites.ContentPrepToolPath)"
        $prereqText.Foreground = ConvertTo-WpfBrush '#2E7D32'
    } else {
        $prereqText.Text = 'Content Prep Tool (intunewinapputil) not found on PATH. Metadata will be created, but .intunewin packaging will fail.'
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

function Set-PackControlsEnabled {
    param([bool]$Enabled)
    $packButton.IsEnabled = $Enabled
    $appNameBox.IsEnabled = $Enabled
    $publisherBox.IsEnabled = $Enabled
    $websiteUrlBox.IsEnabled = $Enabled
    $downloadUrlBox.IsEnabled = $Enabled
    $installerPathBox.IsEnabled = $Enabled
    $browseInstallerButton.IsEnabled = $Enabled
    $developerUrlBox.IsEnabled = $Enabled
    $supportUrlBox.IsEnabled = $Enabled
    $versionBox.IsEnabled = $Enabled
    $browseOutputButton.IsEnabled = $Enabled
    $browseIconButton.IsEnabled = $Enabled
    if ($installContentPrepButton.Visibility -eq [System.Windows.Visibility]::Visible) {
        if (-not $Enabled) {
            $installContentPrepButton.IsEnabled = $false
        } else {
            # Keep disabled when Winget itself is missing (tooltip explains why).
            $installContentPrepButton.IsEnabled = ($installContentPrepButton.ToolTip -notlike '*Winget is required*')
        }
    }
    if (-not $Enabled) {
        $openOutputButton.IsEnabled = $false
    }
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

    if ($Result.IconFile) {
        Set-IconPreview -ImageControl $iconPreview -StatusControl $iconStatus -ImagePath $Result.IconFile
    }

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
    $websiteUrl = $websiteUrlBox.Text.Trim()
    $downloadUrl = $downloadUrlBox.Text.Trim()
    $installerPath = $installerPathBox.Text.Trim()

    if ([string]::IsNullOrWhiteSpace($appName)) {
        [System.Windows.MessageBox]::Show($window, 'Application name is required.', 'AppGetter', 'OK', 'Warning') | Out-Null
        return
    }

    if ([string]::IsNullOrWhiteSpace($websiteUrl) -and [string]::IsNullOrWhiteSpace($downloadUrl) -and [string]::IsNullOrWhiteSpace($installerPath)) {
        [System.Windows.MessageBox]::Show($window, 'Provide a Website URL, a Direct Download URL, or a Local Installer File.', 'AppGetter', 'OK', 'Warning') | Out-Null
        return
    }

    if ($installerPath -and -not (Test-Path -LiteralPath $installerPath -PathType Leaf)) {
        [System.Windows.MessageBox]::Show($window, "Installer file not found:`n$installerPath", 'AppGetter', 'OK', 'Warning') | Out-Null
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

    $packageId = Get-AppGetterPackageIdPreview -AppName $appName
    $outputPath = $outputPathBox.Text.Trim()
    $script:baseOutputPath = Get-AppGetterBaseOutputPath -Path $outputPath -PackageId $packageId
    # Always pack into a folder named after the app.
    $outputPathBox.Text = Get-AppGetterAppOutputPath -BasePath $script:baseOutputPath -PackageId $packageId
    Save-AppGetterSettings -OutputPath $script:baseOutputPath -PackageId $packageId

    $packArguments = @{
        AppName       = $appName
        WebsiteUrl    = $websiteUrl
        DownloadUrl   = $downloadUrl
        InstallerPath = $installerPath
        DeveloperUrl  = $developerUrlBox.Text.Trim()
        SupportUrl    = $supportUrlBox.Text.Trim()
        Version       = $versionBox.Text.Trim()
        Publisher     = $publisherBox.Text.Trim()
        OutputPath    = $script:baseOutputPath
        IconPath      = $script:customIconPath
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
            $item = $null
            while ($script:progressQueue -and $script:progressQueue.TryDequeue([ref]$item)) {
                Invoke-UiProgressUpdate -Event $item -ProgressBar $progressBar -ProgressStatus $progressStatus `
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

$appNameBox.Add_LostFocus({
    if (-not $script:isRunning) {
        Update-OutputPathForApp
    }
})

$browseInstallerButton.Add_Click({
    try {
        $path = Show-OpenFileDialog `
            -Filter 'Installers (*.exe;*.msi;*.msix;*.appx)|*.exe;*.msi;*.msix;*.appx|All files (*.*)|*.*' `
            -Title 'Select the installer file to package' `
            -OwnerWindow $window
        if ($path) {
            $installerPathBox.Text = $path
            Add-LogLine -LogControl $logText -Message "Local installer selected: $path"
        }
    } catch {
        Add-LogLine -LogControl $logText -Message "Installer browser failed: $($_.Exception.Message)"
        [System.Windows.MessageBox]::Show(
            $window,
            "Could not open the file browser.`n`n$($_.Exception.Message)",
            'AppGetter',
            'OK',
            'Error'
        ) | Out-Null
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
            Update-OutputPathForApp
            $packageId = Get-AppGetterPackageIdPreview -AppName $appNameBox.Text.Trim()
            Save-AppGetterSettings -OutputPath $script:baseOutputPath -PackageId $packageId
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
        $path = Show-OpenFileDialog -OwnerWindow $window
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
    if ($script:packTimer) { $script:packTimer.Stop() }
    if ($script:contentPrepInstallTimer) { $script:contentPrepInstallTimer.Stop() }
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
