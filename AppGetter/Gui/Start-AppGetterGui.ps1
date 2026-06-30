<#
.SYNOPSIS
    Starts the AppGetter desktop GUI.
#>

[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

if (-not $IsWindows) {
    throw "AppGetter GUI requires Windows desktop PowerShell components."
}

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$scriptRoot = Split-Path -Parent $PSScriptRoot
$entryScript = Join-Path $scriptRoot "Create-IntuneWinFromWeb.ps1"
if (-not (Test-Path $entryScript)) {
    throw "Entry script not found: $entryScript"
}

$form = New-Object System.Windows.Forms.Form
$form.Text = "AppGetter"
$form.Size = New-Object System.Drawing.Size(920, 720)
$form.StartPosition = "CenterScreen"

$title = New-Object System.Windows.Forms.Label
$title.Text = "AppGetter - IntuneWin Packaging"
$title.Font = New-Object System.Drawing.Font("Segoe UI", 14, [System.Drawing.FontStyle]::Bold)
$title.Location = New-Object System.Drawing.Point(16, 12)
$title.Size = New-Object System.Drawing.Size(600, 34)
$form.Controls.Add($title)

$desc = New-Object System.Windows.Forms.Label
$desc.Text = "WinGetter-style flow: provide app metadata, then click Create Package."
$desc.Location = New-Object System.Drawing.Point(18, 44)
$desc.Size = New-Object System.Drawing.Size(860, 24)
$form.Controls.Add($desc)

$fields = @(
    @{ Name = "AppName"; Label = "App name*"; Y = 80; Width = 280 },
    @{ Name = "WebsiteUrl"; Label = "Website URL"; Y = 128; Width = 420 },
    @{ Name = "DownloadUrl"; Label = "Direct download URL"; Y = 176; Width = 420 },
    @{ Name = "Version"; Label = "Version"; Y = 224; Width = 180 },
    @{ Name = "Publisher"; Label = "Publisher"; Y = 224; X = 430; Width = 250 },
    @{ Name = "DeveloperUrl"; Label = "Developer URL"; Y = 272; Width = 420 },
    @{ Name = "SupportUrl"; Label = "Support URL"; Y = 320; Width = 420 },
    @{ Name = "OutputPath"; Label = "Output path"; Y = 368; Width = 620; Default = "$env:USERPROFILE\Documents\AppGetter Output" },
    @{ Name = "InstallCommand"; Label = "Install command override"; Y = 416; Width = 620 },
    @{ Name = "IconPath"; Label = "Custom icon path (.png)"; Y = 464; Width = 620 }
)

$textBoxes = @{}
foreach ($field in $fields) {
    $label = New-Object System.Windows.Forms.Label
    $label.Text = $field.Label
    $x = if ($field.ContainsKey("X")) { $field.X } else { 18 }
    $label.Location = New-Object System.Drawing.Point($x, $field.Y)
    $label.Size = New-Object System.Drawing.Size(220, 20)
    $form.Controls.Add($label)

    $tb = New-Object System.Windows.Forms.TextBox
    $tb.Name = $field.Name
    $tb.Location = New-Object System.Drawing.Point($x, ($field.Y + 20))
    $tb.Size = New-Object System.Drawing.Size($field.Width, 26)
    if ($field.ContainsKey("Default") -and -not [string]::IsNullOrWhiteSpace($field.Default)) {
        $tb.Text = $field.Default
    }
    $form.Controls.Add($tb)
    $textBoxes[$field.Name] = $tb
}

$browseOutput = New-Object System.Windows.Forms.Button
$browseOutput.Text = "Browse..."
$browseOutput.Location = New-Object System.Drawing.Point(648, 387)
$browseOutput.Size = New-Object System.Drawing.Size(90, 24)
$form.Controls.Add($browseOutput)

$browseIcon = New-Object System.Windows.Forms.Button
$browseIcon.Text = "Browse..."
$browseIcon.Location = New-Object System.Drawing.Point(648, 483)
$browseIcon.Size = New-Object System.Drawing.Size(90, 24)
$form.Controls.Add($browseIcon)

$statusLabel = New-Object System.Windows.Forms.Label
$statusLabel.Text = "Ready."
$statusLabel.Location = New-Object System.Drawing.Point(18, 518)
$statusLabel.Size = New-Object System.Drawing.Size(860, 20)
$form.Controls.Add($statusLabel)

$runButton = New-Object System.Windows.Forms.Button
$runButton.Text = "Create Package"
$runButton.Location = New-Object System.Drawing.Point(760, 386)
$runButton.Size = New-Object System.Drawing.Size(130, 34)
$form.Controls.Add($runButton)

$logBox = New-Object System.Windows.Forms.TextBox
$logBox.Multiline = $true
$logBox.ScrollBars = "Vertical"
$logBox.ReadOnly = $true
$logBox.Font = New-Object System.Drawing.Font("Consolas", 9)
$logBox.Location = New-Object System.Drawing.Point(18, 544)
$logBox.Size = New-Object System.Drawing.Size(872, 130)
$form.Controls.Add($logBox)

$browseOutput.Add_Click({
    $dialog = New-Object System.Windows.Forms.FolderBrowserDialog
    $dialog.Description = "Select AppGetter output folder"
    if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        $textBoxes["OutputPath"].Text = $dialog.SelectedPath
    }
})

$browseIcon.Add_Click({
    $dialog = New-Object System.Windows.Forms.OpenFileDialog
    $dialog.Filter = "PNG files (*.png)|*.png|All files (*.*)|*.*"
    if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        $textBoxes["IconPath"].Text = $dialog.FileName
    }
})

$runButton.Add_Click({
    $appName = $textBoxes["AppName"].Text.Trim()
    $websiteUrl = $textBoxes["WebsiteUrl"].Text.Trim()
    $downloadUrl = $textBoxes["DownloadUrl"].Text.Trim()
    if ([string]::IsNullOrWhiteSpace($appName)) {
        [System.Windows.Forms.MessageBox]::Show("App name is required.", "AppGetter", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null
        return
    }

    if ([string]::IsNullOrWhiteSpace($websiteUrl) -and [string]::IsNullOrWhiteSpace($downloadUrl)) {
        [System.Windows.Forms.MessageBox]::Show("Provide either Website URL or Direct download URL.", "AppGetter", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null
        return
    }

    $arguments = @()
    foreach ($name in @("AppName", "WebsiteUrl", "DownloadUrl", "Version", "Publisher", "DeveloperUrl", "SupportUrl", "OutputPath", "InstallCommand", "IconPath")) {
        $value = $textBoxes[$name].Text.Trim()
        if (-not [string]::IsNullOrWhiteSpace($value)) {
            $arguments += "-$name"
            $arguments += $value
        }
    }

    $runButton.Enabled = $false
    $statusLabel.Text = "Packaging in progress..."
    $logBox.Clear()
    $form.Refresh()

    try {
        $allOutput = & $entryScript @arguments 2>&1
        if ($allOutput) {
            $logBox.Text = ($allOutput | Out-String)
        }
        if ($LASTEXITCODE -eq 0 -or $null -eq $LASTEXITCODE) {
            $statusLabel.Text = "Done."
            [System.Windows.Forms.MessageBox]::Show("Package flow completed. Review logs for details.", "AppGetter", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
        } else {
            $statusLabel.Text = "Failed."
            [System.Windows.Forms.MessageBox]::Show("Packaging failed. Review logs.", "AppGetter", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null
        }
    }
    catch {
        $statusLabel.Text = "Failed."
        $logBox.Text += "`r`nERROR: $($_.Exception.Message)"
        [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, "AppGetter", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null
    }
    finally {
        $runButton.Enabled = $true
    }
})

[void]$form.ShowDialog()
