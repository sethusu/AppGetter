<#
.SYNOPSIS
    Launches the AppGetter graphical user interface.
.DESCRIPTION
    WPF-based GUI for entering a download URL or picking a local installer file,
    choosing output destination, tracking live packaging progress, previewing icons, and testing packages in Windows Sandbox.
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
        if ($PackArguments.ContainsKey('VerifySilentSwitches') -and $PackArguments.VerifySilentSwitches) {
            $params.VerifySilentSwitches = $true
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

function Get-SandboxStepIcon {
    param([string]$State)
    switch ($State) {
        'Running' { return [char]0x25B6 }
        'Awaiting' { return [char]0x25B6 }
        'Confirmed' { return [char]0x2713 }
        'Failed' { return [char]0x2717 }
        default { return [char]0x25CB }
    }
}

function New-SandboxStepView {
    param(
        [string]$Title,
        [string]$State,
        [string]$Detail
    )
    return [PSCustomObject]@{
        Icon = Get-SandboxStepIcon $State
        Title = $Title
        Detail = $Detail
        State = $State
    }
}

function Update-SandboxDialogStepList {
    if (-not $script:sandboxDialog) { return }
    $ui = $script:sandboxDialog
    $ui.StepList.Items.Clear()
    foreach ($name in $ui.StepOrder) {
        $ui.StepList.Items.Add((New-SandboxStepView -Title $ui.StepTitles[$name] -State $ui.StepStates[$name] -Detail $ui.StepDetails[$name])) | Out-Null
    }
}

function Set-SandboxDialogLog {
    param([string]$Text)
    if (-not $script:sandboxDialog) { return }
    if ($Text -eq $script:sandboxDialog.LastLog) { return }
    $script:sandboxDialog.LastLog = $Text
    $script:sandboxDialog.LogBox.Text = $Text
    $script:sandboxDialog.LogBox.CaretIndex = $script:sandboxDialog.LogBox.Text.Length
    $script:sandboxDialog.LogBox.ScrollToEnd()
}

function Save-SandboxDialogReport {
    param(
        [string]$Outcome = 'in-progress',
        [string]$Message = ''
    )

    if (-not $script:sandboxDialog -or -not $script:sandboxDialog.Session) {
        return $null
    }

    try {
        $report = Write-AppGetterSandboxTestReport `
            -VersionDirectory $script:sandboxDialog.Session.VersionDirectory `
            -HandshakeDirectory $script:sandboxDialog.Session.HandshakeDirectory `
            -Confirmations $script:sandboxDialog.Confirmations `
            -Outcome $Outcome `
            -Message $Message
        $script:sandboxDialog.Report = $report
        return $report
    } catch {
        return $null
    }
}

function Copy-SandboxDialogReportToClipboard {
    param($Report)

    if (-not $Report -or -not $Report.Text) {
        return $false
    }

    try {
        [System.Windows.Clipboard]::SetText([string]$Report.Text)
        return $true
    } catch {
        return $false
    }
}

function Complete-SandboxDialog {
    param(
        [bool]$Validated,
        [object]$Validation = $null,
        [string]$Message = ''
    )

    if (-not $script:sandboxDialog -or $script:sandboxDialog.Finished) { return }
    $script:sandboxDialog.Finished = $true

    $outcome = if ($Validated) { 'validated' } else { 'failed' }
    $report = Save-SandboxDialogReport -Outcome $outcome -Message $Message
    $copied = Copy-SandboxDialogReportToClipboard -Report $report

    $script:sandboxDialog.Result = [PSCustomObject]@{
        Validated = $Validated
        Validation = $Validation
        Message = $Message
        ReportPath = if ($report) { $report.Path } else { $null }
        ReportText = if ($report) { $report.Text } else { $null }
        ReportCopied = $copied
        FailureLogPath = if ($report) { $report.FailureLogPath } else { $null }
    }

    if ($script:sandboxDialog.Timer) {
        try { $script:sandboxDialog.Timer.Stop() } catch { }
    }
    try {
        Stop-AppGetterSandboxSession -HandshakeDirectory $script:sandboxDialog.Session.HandshakeDirectory
    } catch { }

    $script:sandboxDialog.Window.Tag = $script:sandboxDialog.Result
    try {
        $script:sandboxDialog.Window.DialogResult = $Validated
    } catch { }
    try {
        $script:sandboxDialog.Window.Close()
    } catch { }
}

function Confirm-CurrentSandboxStep {
    param([bool]$Succeeded)

    if (-not $script:sandboxDialog -or $script:sandboxDialog.Finished) { return }
    $ui = $script:sandboxDialog
    $step = $ui.CurrentStep
    if ($ui.StepStates[$step] -ne 'Awaiting') { return }

    $status = Resolve-AppGetterSandboxStepStatus -HandshakeDirectory $ui.Session.HandshakeDirectory -Step $step -LogText $ui.LastLog
    $exitCode = $null
    $message = ''
    $silentUi = $false
    if ($status) {
        $exitCode = $status.exitCode
        $message = [string]$status.message
        if ($status.PSObject.Properties['silentUiDetected']) {
            $silentUi = [bool]$status.silentUiDetected
        }
    }
    if (-not $silentUi -and $message -match '(?i)not silent') {
        $silentUi = $true
    }

    if ($Succeeded) {
        $ui.Confirmations[$step] = @{
            Confirmed = $true
            ExitCode = $exitCode
            ConfirmedAt = (Get-Date).ToUniversalTime().ToString('o')
            Message = $message
            SilentUiDetected = $silentUi
        }
        $ui.StepStates[$step] = 'Confirmed'
        $ui.StepDetails[$step] = if ($silentUi) {
            "Confirmed, but NOT SILENT. Exit code: $exitCode"
        } else {
            "Confirmed. Exit code: $exitCode"
        }
        $ui.ConfirmButton.IsEnabled = $false
        $ui.FailButton.IsEnabled = $false

        $index = [array]::IndexOf($ui.StepOrder, $step)
        if ($index -lt ($ui.StepOrder.Count - 1)) {
            $next = $ui.StepOrder[$index + 1]
            $ui.CurrentStep = $next
            $ui.StepStates[$next] = 'Running'
            $ui.StepDetails[$next] = "Running $next in Windows Sandbox..."
            $ui.StatusText.Text = "Confirmed $step. Starting $next..."
            Set-AppGetterSandboxCommand -HandshakeDirectory $ui.Session.HandshakeDirectory -Action $next
            Update-SandboxDialogStepList
        } else {
            $validation = Complete-AppGetterSandboxTest -VersionDirectory $ui.Session.VersionDirectory -Confirmations $ui.Confirmations
            $ok = [bool]$validation.Validated
            $doneMessage = if ($ok) {
                'All three steps were confirmed. This package is marked as validated.'
            } else {
                'All three steps were confirmed, but silent-install validation failed (an installer dialog appeared). The package was not marked as validated. See sandbox-failure.log in the package folder.'
            }
            Complete-SandboxDialog -Validated $ok -Validation $validation -Message $doneMessage
        }
        return
    }

    $ui.Confirmations[$step] = @{
        Confirmed = $false
        ExitCode = $exitCode
        ConfirmedAt = (Get-Date).ToUniversalTime().ToString('o')
        Message = $message
        SilentUiDetected = $silentUi
    }
    $ui.StepStates[$step] = 'Failed'
    $ui.StepDetails[$step] = "Not confirmed. Exit code: $exitCode"
    $null = Complete-AppGetterSandboxTest -VersionDirectory $ui.Session.VersionDirectory -Confirmations $ui.Confirmations
    Complete-SandboxDialog -Validated $false -Message "$step was not confirmed. The package was not marked as validated."
}

function Update-SandboxDialogFromStatus {
    if (-not $script:sandboxDialog -or $script:sandboxDialog.Finished) { return }
    $ui = $script:sandboxDialog

    $logText = Get-AppGetterSandboxGuestLog -HandshakeDirectory $ui.Session.HandshakeDirectory -IncludeStepLogs
    if ($logText) {
        Set-SandboxDialogLog -Text $logText
    }

    $heartbeat = Get-AppGetterSandboxHeartbeat -HandshakeDirectory $ui.Session.HandshakeDirectory
    if ($heartbeat) {
        $ui.HeartbeatSeen = $true
    } elseif (-not $ui.HeartbeatSeen) {
        $elapsed = (Get-Date) - $ui.Session.StartedAt
        if ($elapsed.TotalSeconds -gt 120) {
            $ui.StatusText.Text = 'Windows Sandbox did not start in time.'
            Complete-SandboxDialog -Validated $false -Message 'Windows Sandbox did not start. Confirm the feature is enabled, virtualization is available, and try again.'
            return
        }
        $ui.StatusText.Text = "Starting Windows Sandbox... ($([int]$elapsed.TotalSeconds)s)"
        return
    }

    $step = $ui.CurrentStep
    if ($ui.StepStates[$step] -eq 'Awaiting') {
        $ui.ConfirmButton.IsEnabled = $true
        $ui.FailButton.IsEnabled = $true
        Update-SandboxDialogStepList
        return
    }

    $status = Resolve-AppGetterSandboxStepStatus -HandshakeDirectory $ui.Session.HandshakeDirectory -Step $step -LogText $ui.LastLog
    if (-not $status) { return }

    $statusStep = [string]$status.step
    $state = [string]$status.state

    if ($statusStep -eq $step -and $state -eq 'running') {
        $ui.StepStates[$step] = 'Running'
        $ui.StepDetails[$step] = [string]$status.message
        $ui.StatusText.Text = [string]$status.message
        $ui.ConfirmButton.IsEnabled = $false
        $ui.FailButton.IsEnabled = $false
    } elseif ($statusStep -eq $step -and ($state -eq 'completed' -or $state -eq 'failed')) {
        $ui.StepStates[$step] = 'Awaiting'
        $exitLabel = if ($null -ne $status.exitCode) { "Exit code: $($status.exitCode). " } else { '' }
        $silentUi = $false
        if ($status.PSObject.Properties['silentUiDetected']) {
            $silentUi = [bool]$status.silentUiDetected
        }
        if (-not $silentUi -and [string]$status.message -match '(?i)not silent') {
            $silentUi = $true
        }
        $ui.StepDetails[$step] = "$exitLabel$($status.message) Confirm this step in AppGetter to continue."
        if ($silentUi) {
            $ui.StatusText.Text = "NOT SILENT: an installer dialog appeared. Use Step failed, or confirm to continue testing. The package will not be marked validated."
        } else {
            $ui.StatusText.Text = "Confirm $step, then the next script will run."
        }
        $ui.ConfirmButton.IsEnabled = $true
        $ui.FailButton.IsEnabled = $true
    }

    Update-SandboxDialogStepList
}

function Show-AppGetterSandboxTestDialog {
    param(
        [object]$Session,
        $OwnerWindow
    )

    $dialogPath = Join-Path $PSScriptRoot 'AppGetter.SandboxTestDialog.xaml'
    $dialogWindow = Read-XamlWindow -XamlPath $dialogPath
    $dialogWindow.Owner = $OwnerWindow

    $summary = $dialogWindow.FindName('PackageSummaryText')
    $statusText = $dialogWindow.FindName('StatusText')
    $stepList = $dialogWindow.FindName('StepList')
    $logBox = $dialogWindow.FindName('LogTextBox')
    $confirmButton = $dialogWindow.FindName('ConfirmButton')
    $failButton = $dialogWindow.FindName('FailButton')
    $cancelButton = $dialogWindow.FindName('CancelButton')
    $copyReportButton = $dialogWindow.FindName('CopyReportButton')

    $displayName = if ($Session.DisplayName) { $Session.DisplayName } else { 'Packaged application' }
    $packageId = if ($Session.PackageId) { $Session.PackageId } else { '' }
    $version = if ($Session.Version) { $Session.Version } else { '' }
    $summary.Text = "$displayName $(if ($packageId) { "($packageId)" }) $(if ($version) { "version $version" })`nPackage folder: $($Session.VersionDirectory)"

    $script:sandboxDialog = @{
        Window = $dialogWindow
        StatusText = $statusText
        StepList = $stepList
        LogBox = $logBox
        ConfirmButton = $confirmButton
        FailButton = $failButton
        CopyReportButton = $copyReportButton
        Session = $Session
        Timer = $null
        CurrentStep = 'install'
        StepOrder = @('install', 'detect', 'uninstall')
        StepTitles = @{
            install = '1. Install (install.ps1)'
            detect = '2. Detect (detection.ps1)'
            uninstall = '3. Uninstall (uninstall.ps1)'
        }
        StepDetails = @{
            install = 'Windows Sandbox is starting. install.ps1 will run automatically.'
            detect = 'Runs after install is confirmed.'
            uninstall = 'Runs after detection is confirmed.'
        }
        StepStates = @{
            install = 'Running'
            detect = 'Pending'
            uninstall = 'Pending'
        }
        Confirmations = @{
            install = @{ Confirmed = $false; ExitCode = $null; ConfirmedAt = $null; Message = ''; SilentUiDetected = $false }
            detect = @{ Confirmed = $false; ExitCode = $null; ConfirmedAt = $null; Message = ''; SilentUiDetected = $false }
            uninstall = @{ Confirmed = $false; ExitCode = $null; ConfirmedAt = $null; Message = ''; SilentUiDetected = $false }
        }
        HeartbeatSeen = $false
        Finished = $false
        Result = $null
        Report = $null
        LastLog = ''
    }

    Update-SandboxDialogStepList
    $statusText.Text = 'Starting Windows Sandbox and running install.ps1...'

    $sandboxTimer = New-Object System.Windows.Threading.DispatcherTimer
    $sandboxTimer.Interval = [TimeSpan]::FromMilliseconds(500)
    $sandboxTimer.Add_Tick({ Update-SandboxDialogFromStatus })
    $script:sandboxDialog.Timer = $sandboxTimer
    $sandboxTimer.Start()

    $confirmButton.Add_Click({ Confirm-CurrentSandboxStep -Succeeded $true })
    $failButton.Add_Click({ Confirm-CurrentSandboxStep -Succeeded $false })
    if ($copyReportButton) {
        $copyReportButton.Add_Click({
            $report = Save-SandboxDialogReport -Outcome 'in-progress' -Message 'Copied from Test in Sandbox dialog.'
            if (-not $report) {
                $script:sandboxDialog.StatusText.Text = 'Could not write a sandbox report yet.'
                return
            }
            $copied = Copy-SandboxDialogReportToClipboard -Report $report
            if ($copied) {
                $script:sandboxDialog.StatusText.Text = "Chat-ready log copied. Saved to $($report.Path)"
            } else {
                $script:sandboxDialog.StatusText.Text = "Chat-ready log saved to $($report.Path)"
            }
        })
    }
    $cancelButton.Add_Click({
        Complete-SandboxDialog -Validated $false -Message 'Sandbox test was cancelled. The package was not marked as validated.'
    })
    $dialogWindow.Add_Closing({
        if ($script:sandboxDialog -and -not $script:sandboxDialog.Finished) {
            Complete-SandboxDialog -Validated $false -Message 'Sandbox test was closed before validation completed.'
        }
    })

    [void]$dialogWindow.ShowDialog()
    if ($script:sandboxDialog -and $script:sandboxDialog.Timer) {
        try { $script:sandboxDialog.Timer.Stop() } catch { }
    }
    $result = $null
    if ($dialogWindow.Tag) {
        $result = $dialogWindow.Tag
    } elseif ($script:sandboxDialog -and $script:sandboxDialog.Result) {
        $result = $script:sandboxDialog.Result
    }
    $script:sandboxDialog = $null
    if ($result) { return $result }
    return [PSCustomObject]@{
        Validated = $false
        Validation = $null
        Message = 'Sandbox test ended without a result.'
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
$verifySilentSwitchesCheckBox = $window.FindName('VerifySilentSwitchesCheckBox')
$progressBar = $window.FindName('ProgressBar')
$progressStatus = $window.FindName('ProgressStatusText')
$stepList = $window.FindName('StepList')
$iconPreview = $window.FindName('IconPreview')
$iconStatus = $window.FindName('IconStatusText')
$browseIconButton = $window.FindName('BrowseIconButton')
$logText = $window.FindName('LogTextBox')
$openOutputButton = $window.FindName('OpenOutputButton')
$testSandboxButton = $window.FindName('TestSandboxButton')
$sandboxStatusText = $window.FindName('SandboxStatusText')
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


function Get-AppGetterPackageIdPreviewFromUi {
    return (Get-AppGetterPackageIdPreview -AppName $appNameBox.Text.Trim())
}

function Get-CurrentSandboxPackageDirectory {
    $packageId = Get-AppGetterPackageIdPreviewFromUi
    $version = ''
    if ($versionBox.Text) {
        $version = $versionBox.Text.Trim()
    }
    $path = ''
    if ($outputPathBox.Text) {
        $path = $outputPathBox.Text.Trim()
    }

    if ($path) {
        $resolved = Resolve-AppGetterPackageVersionDirectory -Path $path -PackageId $packageId -Version $version
        if ($resolved) {
            return $resolved
        }
    }

    if ($script:lastOutputDirectory -and (Test-AppGetterSandboxPackage -VersionDirectory $script:lastOutputDirectory)) {
        return $script:lastOutputDirectory
    }

    return $null
}

function Update-SandboxTestButtonState {
    $dir = Get-CurrentSandboxPackageDirectory
    $ready = [bool]($dir -and (Test-AppGetterSandboxPackage -VersionDirectory $dir) -and -not $script:isRunning)
    $testSandboxButton.IsEnabled = $ready

    if (-not $dir) {
        $sandboxStatusText.Text = 'Create a package, then use Test in Sandbox to validate install, detection, and uninstall.'
        $sandboxStatusText.Foreground = ConvertTo-WpfBrush '#5C6B7A'
        return
    }

    $validation = Get-AppGetterPackageValidation -VersionDirectory $dir
    if ($validation.Validated) {
        $when = ''
        if ($validation.ValidatedAt) {
            $when = " at $($validation.ValidatedAt)"
        }
        $sandboxStatusText.Text = "Validated in Windows Sandbox$when"
        $sandboxStatusText.Foreground = ConvertTo-WpfBrush '#2E7D32'
    } else {
        $sandboxStatusText.Text = 'Package ready. Test in Sandbox to confirm install, detection, and uninstall.'
        $sandboxStatusText.Foreground = ConvertTo-WpfBrush '#5C6B7A'
    }
}

function Invoke-AppGetterSandboxTestFromUi {
    if ($script:isRunning) { return }

    $dir = Get-CurrentSandboxPackageDirectory
    if (-not $dir) {
        [System.Windows.MessageBox]::Show(
            $window,
            'Create a package first. Test in Sandbox needs install.ps1, detection.ps1, and uninstall.ps1.',
            'AppGetter',
            'OK',
            'Warning'
        ) | Out-Null
        return
    }

    $info = Get-AppGetterSandboxPackageInfo -VersionDirectory $dir -RestoreInstaller
    if (-not $info.Ready) {
        [System.Windows.MessageBox]::Show($window, $info.Reason, 'AppGetter', 'OK', 'Warning') | Out-Null
        return
    }
    if ($info.InstallerRestore -and $info.InstallerRestore.Restored) {
        Add-LogLine -LogControl $logText -Message $info.InstallerRestore.Message
    }

    $sandbox = Test-AppGetterWindowsSandbox
    if (-not $sandbox.Enabled) {
        if (-not $sandbox.Supported) {
            [System.Windows.MessageBox]::Show($window, $sandbox.Reason, 'AppGetter', 'OK', 'Error') | Out-Null
            return
        }

        if ($sandbox.RestartPending) {
            [System.Windows.MessageBox]::Show($window, $sandbox.Reason, 'AppGetter', 'OK', 'Information') | Out-Null
            return
        }

        $confirm = [System.Windows.MessageBox]::Show(
            $window,
            "Windows Sandbox is not enabled on this device.`n`n$($sandbox.Reason)`n`nEnable Windows Sandbox now? This requires administrator approval and usually a restart.",
            'AppGetter',
            'YesNo',
            'Question'
        )
        if ($confirm -ne [System.Windows.MessageBoxResult]::Yes) { return }

        try {
            $enableResult = Install-AppGetterWindowsSandbox
            Add-LogLine -LogControl $logText -Message $enableResult.Message
            [System.Windows.MessageBox]::Show($window, $enableResult.Message, 'AppGetter', 'OK', 'Information') | Out-Null
            if ($enableResult.RestartNeeded -or -not $enableResult.Sandbox.Enabled) {
                return
            }
        } catch {
            Add-LogLine -LogControl $logText -Message "Could not enable Windows Sandbox: $($_.Exception.Message)"
            [System.Windows.MessageBox]::Show(
                $window,
                "Could not enable Windows Sandbox.`n`n$($_.Exception.Message)",
                'AppGetter',
                'OK',
                'Error'
            ) | Out-Null
            return
        }
    }

    try {
        Add-LogLine -LogControl $logText -Message "Starting Windows Sandbox test for $($info.DisplayName) $($info.Version)..."
        $session = Start-AppGetterSandboxSession -VersionDirectory $dir
        $result = Show-AppGetterSandboxTestDialog -Session $session -OwnerWindow $window
        if ($result -and $result.Message) {
            Add-LogLine -LogControl $logText -Message $result.Message
        }
        if ($result -and $result.ReportPath) {
            Add-LogLine -LogControl $logText -Message "Sandbox report: $($result.ReportPath)"
        }
        if ($result -and $result.FailureLogPath) {
            Add-LogLine -LogControl $logText -Message "Sandbox failure log: $($result.FailureLogPath)"
        }

        $dialogMessage = if ($result -and $result.Message) { [string]$result.Message } else { '' }
        if ($result -and $result.FailureLogPath) {
            $dialogMessage = "$dialogMessage`n`nFailure log (upload this for diagnostics):`n$($result.FailureLogPath)"
        }
        if ($result -and $result.ReportPath) {
            $dialogMessage = "$dialogMessage`n`nA chat-ready log was saved to:`n$($result.ReportPath)"
            if ($result.ReportCopied) {
                $dialogMessage = "$dialogMessage`n`nThe log is also on the clipboard so you can paste it into chat."
            }
        }

        if ($result.Validated) {
            [System.Windows.MessageBox]::Show($window, $dialogMessage, 'AppGetter', 'OK', 'Information') | Out-Null
        } elseif ($dialogMessage) {
            [System.Windows.MessageBox]::Show($window, $dialogMessage, 'AppGetter', 'OK', 'Warning') | Out-Null
        }
    } catch {
        Add-LogLine -LogControl $logText -Message "Sandbox test failed: $($_.Exception.Message)"
        [System.Windows.MessageBox]::Show(
            $window,
            "Sandbox test failed.`n`n$($_.Exception.Message)",
            'AppGetter',
            'OK',
            'Error'
        ) | Out-Null
    } finally {
        Update-SandboxTestButtonState
    }
}


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
    if ($verifySilentSwitchesCheckBox) {
        $verifySilentSwitchesCheckBox.IsEnabled = $Enabled
    }
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
        $testSandboxButton.IsEnabled = $false
    } else {
        Update-SandboxTestButtonState
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

    Update-SandboxTestButtonState

    if ($Result.PackagingSucceeded) {
        $progressStatus.Text = 'Packaging completed successfully.'
        Add-LogLine -LogControl $logText -Message "Success: $($Result.IntuneWinFile)"
        [System.Windows.MessageBox]::Show(
            $window,
            "Package created successfully.`n`n$($Result.DisplayName)`n$($Result.IntuneWinFile)`n`nYou can click Test in Sandbox to confirm install, detection, and uninstall.",
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
        VerifySilentSwitches = [bool]($verifySilentSwitchesCheckBox -and $verifySilentSwitchesCheckBox.IsChecked)
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

$testSandboxButton.Add_Click({
    if ($script:isRunning) { return }
    Invoke-AppGetterSandboxTestFromUi
})

$appNameBox.Add_TextChanged({
    if (-not $script:isRunning) {
        Update-SandboxTestButtonState
    }
})

$versionBox.Add_TextChanged({
    if (-not $script:isRunning) {
        Update-SandboxTestButtonState
    }
})

$outputPathBox.Add_TextChanged({
    if (-not $script:isRunning) {
        Update-SandboxTestButtonState
    }
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
Update-SandboxTestButtonState
[void]$window.ShowDialog()
