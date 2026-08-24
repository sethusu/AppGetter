function ConvertTo-AppGetterXmlText {
    param([string]$Value)

    if ([string]::IsNullOrEmpty($Value)) {
        return ''
    }

    return [System.Security.SecurityElement]::Escape($Value)
}

function Write-AppGetterSandboxJson {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,
        [Parameter(Mandatory = $true)]
        $Object
    )

    $directory = Split-Path -Path $Path -Parent
    if ($directory -and -not (Test-Path -LiteralPath $directory)) {
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
    }

    $json = $Object | ConvertTo-Json -Depth 8
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($json)
    $stream = $null
    try {
        $stream = [System.IO.File]::Open(
            $Path,
            [System.IO.FileMode]::Create,
            [System.IO.FileAccess]::Write,
            [System.IO.FileShare]::Read
        )
        $stream.Write($bytes, 0, $bytes.Length)
        $stream.Flush()
    } finally {
        if ($stream) {
            $stream.Dispose()
        }
    }
}

function Read-AppGetterSandboxJson {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    foreach ($candidate in @($Path, "$Path.tmp")) {
        if (-not (Test-Path -LiteralPath $candidate)) {
            continue
        }

        for ($attempt = 0; $attempt -lt 3; $attempt++) {
            try {
                $stream = [System.IO.File]::Open(
                    $candidate,
                    [System.IO.FileMode]::Open,
                    [System.IO.FileAccess]::Read,
                    [System.IO.FileShare]::ReadWrite
                )
                try {
                    $reader = New-Object System.IO.StreamReader($stream, [System.Text.Encoding]::UTF8, $true)
                    try {
                        $raw = $reader.ReadToEnd()
                    } finally {
                        $reader.Dispose()
                    }
                } finally {
                    $stream.Dispose()
                }

                if ([string]::IsNullOrWhiteSpace($raw)) {
                    break
                }

                return $raw | ConvertFrom-Json
            } catch {
                if ($attempt -lt 2) {
                    Start-Sleep -Milliseconds 50
                    continue
                }
            }
        }
    }

    return $null
}

function Read-AppGetterSandboxText {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,
        [switch]$Raw
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        if ($Raw) { return '' }
        return @()
    }

    try {
        $stream = [System.IO.File]::Open(
            $Path,
            [System.IO.FileMode]::Open,
            [System.IO.FileAccess]::Read,
            [System.IO.FileShare]::ReadWrite
        )
        try {
            $reader = New-Object System.IO.StreamReader($stream, [System.Text.Encoding]::UTF8, $true)
            try {
                $text = $reader.ReadToEnd()
            } finally {
                $reader.Dispose()
            }
        } finally {
            $stream.Dispose()
        }

        if ($Raw) {
            return $text
        }
        if ([string]::IsNullOrEmpty($text)) {
            return @()
        }
        return @($text -split '\r\n|\n|\r')
    } catch {
        if ($Raw) { return '' }
        return @()
    }
}

function Get-AppGetterSandboxFeatureName {
    return 'Containers-DisposableClientVM'
}

function Get-AppGetterWindowsSandboxExePath {
    $candidates = [System.Collections.Generic.List[string]]::new()
    if ($env:SystemRoot) {
        $candidates.Add((Join-Path $env:SystemRoot 'System32\WindowsSandbox.exe'))
        $candidates.Add((Join-Path $env:SystemRoot 'Sysnative\WindowsSandbox.exe'))
    }

    $cmd = Get-Command WindowsSandbox -ErrorAction SilentlyContinue
    if ($cmd) {
        if ($cmd.Source) { $candidates.Add([string]$cmd.Source) }
        if ($cmd.Path) { $candidates.Add([string]$cmd.Path) }
    }

    foreach ($candidate in $candidates) {
        if ($candidate -and (Test-Path -LiteralPath $candidate)) {
            return $candidate
        }
    }

    return $null
}

function Test-AppGetterWindowsSandbox {
    <#
    .SYNOPSIS
        Checks whether Windows Sandbox is available and enabled on this device.
    #>
    [CmdletBinding()]
    param()

    $featureName = Get-AppGetterSandboxFeatureName
    $result = [ordered]@{
        Enabled         = $false
        Supported       = $false
        RestartPending  = $false
        FeatureName     = $featureName
        FeatureState    = $null
        ExecutablePath  = $null
        Edition         = $null
        Reason          = $null
        IsWindows       = $false
    }

    if ([System.Environment]::OSVersion.Platform -ne 'Win32NT') {
        $result.Reason = 'Windows Sandbox is only available on Windows 10/11 Pro, Enterprise, or Education.'
        return [PSCustomObject]$result
    }

    $result.IsWindows = $true

    try {
        $result.Edition = [string](Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -ErrorAction Stop).EditionID
    } catch {
        $result.Edition = $null
    }

    $homeEditions = @('Core', 'CoreN', 'CoreSingleLanguage', 'CoreCountrySpecific')
    if ($result.Edition -and ($homeEditions -contains $result.Edition)) {
        $result.Reason = "Windows Sandbox is not available on Windows Home (edition: $($result.Edition)). Use Windows 10/11 Pro, Enterprise, or Education."
        return [PSCustomObject]$result
    }

    $result.ExecutablePath = Get-AppGetterWindowsSandboxExePath

    try {
        $feature = Get-WindowsOptionalFeature -Online -FeatureName $featureName -ErrorAction Stop
        $result.FeatureState = [string]$feature.State
        $result.Supported = $true
    } catch {
        if ($result.ExecutablePath) {
            $result.Supported = $true
        } else {
            $result.Reason = "Windows Sandbox is not available on this device. $($_.Exception.Message)"
            return [PSCustomObject]$result
        }
    }

    $state = [string]$result.FeatureState
    if ($state -eq 'EnablePending' -or $state -eq 'DisablePending') {
        $result.RestartPending = $true
    }

    if ($state -eq 'EnablePending') {
        $result.Reason = 'Windows Sandbox was enabled but Windows must be restarted before it can be used.'
        return [PSCustomObject]$result
    }

    if ($state -eq 'Disabled') {
        $result.Supported = $true
        $result.Reason = 'Windows Sandbox is not enabled on this device.'
        return [PSCustomObject]$result
    }

    if ($result.ExecutablePath) {
        $result.Enabled = $true
        $result.Supported = $true
        $result.Reason = $null
        return [PSCustomObject]$result
    }

    if ($state -eq 'Enabled') {
        $result.Supported = $true
        $result.Reason = 'Windows Sandbox is enabled but WindowsSandbox.exe was not found. Restart Windows and try again.'
        return [PSCustomObject]$result
    }

    $result.Supported = $true
    $result.Reason = 'Windows Sandbox is not enabled on this device.'
    return [PSCustomObject]$result
}

function Install-AppGetterWindowsSandbox {
    <#
    .SYNOPSIS
        Prompts for elevation and enables the Windows Sandbox optional feature.
    .DESCRIPTION
        Runs Enable-WindowsOptionalFeature for Containers-DisposableClientVM.
        A reboot is usually required before Windows Sandbox can start.
    #>
    [CmdletBinding()]
    param()

    $current = Test-AppGetterWindowsSandbox
    if ($current.Enabled) {
        return [PSCustomObject]@{
            Succeeded      = $true
            AlreadyEnabled = $true
            RestartNeeded  = $false
            Message        = 'Windows Sandbox is already enabled.'
            Sandbox        = $current
        }
    }

    if (-not $current.IsWindows) {
        throw $current.Reason
    }

    if ($current.RestartPending) {
        return [PSCustomObject]@{
            Succeeded      = $true
            AlreadyEnabled = $false
            RestartNeeded  = $true
            Message        = $current.Reason
            Sandbox        = $current
        }
    }

    if (-not $current.Supported) {
        throw $current.Reason
    }

    $resultPath = Join-Path ([System.IO.Path]::GetTempPath()) ("appgetter-sandbox-enable-{0}.json" -f ([Guid]::NewGuid().ToString('N')))
    $scriptPath = Join-Path ([System.IO.Path]::GetTempPath()) ("appgetter-enable-sandbox-{0}.ps1" -f ([Guid]::NewGuid().ToString('N')))

    $enableScript = @'
param([Parameter(Mandatory = $true)][string]$ResultPath)

$ErrorActionPreference = 'Stop'
$payload = @{
    Succeeded = $false
    RestartNeeded = $false
    State = $null
    Error = $null
    ExitCode = 0
}

try {
    $feature = Get-WindowsOptionalFeature -Online -FeatureName 'Containers-DisposableClientVM' -ErrorAction SilentlyContinue
    if ($feature -and [string]$feature.State -eq 'Enabled') {
        $payload.Succeeded = $true
        $payload.State = 'Enabled'
    } elseif ($feature -and [string]$feature.State -eq 'EnablePending') {
        $payload.Succeeded = $true
        $payload.RestartNeeded = $true
        $payload.State = 'EnablePending'
    } else {
        $enabled = Enable-WindowsOptionalFeature -Online -FeatureName 'Containers-DisposableClientVM' -All -NoRestart -ErrorAction Stop
        $payload.Succeeded = $true
        $payload.State = [string]$enabled.State
        $payload.RestartNeeded = [bool]$enabled.RestartNeeded
        if ($payload.State -eq 'EnablePending') {
            $payload.RestartNeeded = $true
        }
    }
} catch {
    $optionalError = $_.Exception.Message
    try {
        $dism = Start-Process -FilePath "$env:SystemRoot\System32\dism.exe" -ArgumentList @(
            '/online',
            '/enable-feature',
            '/featurename:Containers-DisposableClientVM',
            '/all',
            '/norestart'
        ) -Wait -PassThru -NoNewWindow
        $payload.ExitCode = [int]$dism.ExitCode
        if ($dism.ExitCode -eq 0 -or $dism.ExitCode -eq 3010) {
            $payload.Succeeded = $true
            $payload.RestartNeeded = ($dism.ExitCode -eq 3010)
            $payload.State = if ($dism.ExitCode -eq 3010) { 'EnablePending' } else { 'Enabled' }
            $payload.Error = $null
        } else {
            $payload.Error = "DISM failed with exit code $($dism.ExitCode). $optionalError"
        }
    } catch {
        $payload.Error = $_.Exception.Message
        if ($optionalError) {
            $payload.Error = "$optionalError $($_.Exception.Message)"
        }
    }
}

$payload | ConvertTo-Json | Set-Content -LiteralPath $ResultPath -Encoding UTF8
'@

    Set-Content -LiteralPath $scriptPath -Value $enableScript -Encoding UTF8

    try {
        $process = Start-Process -FilePath 'powershell.exe' -Verb RunAs -Wait -PassThru -ArgumentList @(
            '-NoProfile'
            '-ExecutionPolicy'
            'Bypass'
            '-File'
            $scriptPath
            '-ResultPath'
            $resultPath
        )

        if ($process -and $process.ExitCode -ne 0 -and -not (Test-Path -LiteralPath $resultPath)) {
            throw "Elevated enable step exited with code $($process.ExitCode)."
        }
    } catch {
        throw "Could not enable Windows Sandbox (administrator approval is required). $($_.Exception.Message)"
    } finally {
        Remove-Item -LiteralPath $scriptPath -Force -ErrorAction SilentlyContinue
    }

    $enableResult = Read-AppGetterSandboxJson -Path $resultPath
    Remove-Item -LiteralPath $resultPath -Force -ErrorAction SilentlyContinue

    if (-not $enableResult) {
        throw 'Windows Sandbox enable did not return a result. The elevation prompt may have been cancelled.'
    }

    if (-not $enableResult.Succeeded) {
        $errorText = if ($enableResult.Error) { [string]$enableResult.Error } else { 'Unknown error.' }
        throw "Failed to enable Windows Sandbox. $errorText"
    }

    $sandbox = Test-AppGetterWindowsSandbox
    $restartNeeded = [bool]$enableResult.RestartNeeded -or [bool]$sandbox.RestartPending
    $message = if ($restartNeeded) {
        'Windows Sandbox was enabled. Restart Windows, then click Test in Sandbox again.'
    } elseif ($sandbox.Enabled) {
        'Windows Sandbox is enabled.'
    } else {
        'Windows Sandbox enable finished. If Test in Sandbox still cannot start, restart Windows and try again.'
    }

    return [PSCustomObject]@{
        Succeeded      = $true
        AlreadyEnabled = $false
        RestartNeeded  = $restartNeeded
        Message        = $message
        Sandbox        = $sandbox
    }
}

function Resolve-AppGetterPackageVersionDirectory {
    <#
    .SYNOPSIS
        Finds a packaged version folder that contains install.ps1.
    #>
    [CmdletBinding()]
    param(
        [string]$Path,
        [string]$PackageId,
        [string]$Version
    )

    if ([string]::IsNullOrWhiteSpace($Path)) {
        return $null
    }

    $installHere = Join-Path $Path 'install.ps1'
    if (Test-Path -LiteralPath $installHere) {
        return [System.IO.Path]::GetFullPath($Path)
    }

    $searchRoots = [System.Collections.Generic.List[string]]::new()
    $searchRoots.Add($Path)
    if ($PackageId) {
        $appPath = Get-AppGetterAppOutputPath -BasePath $Path -PackageId $PackageId
        if ($appPath -and ($searchRoots -notcontains $appPath)) {
            $searchRoots.Add($appPath)
        }
    }

    foreach ($root in $searchRoots) {
        if (-not (Test-Path -LiteralPath $root)) {
            continue
        }

        if ($Version) {
            $versionDir = Join-Path $root $Version
            if (Test-Path -LiteralPath (Join-Path $versionDir 'install.ps1')) {
                return [System.IO.Path]::GetFullPath($versionDir)
            }
        }

        $candidates = @(Get-ChildItem -LiteralPath $root -Directory -ErrorAction SilentlyContinue |
            Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName 'install.ps1') })
        if ($candidates.Count -gt 0) {
            $latest = $candidates | Sort-Object LastWriteTime -Descending | Select-Object -First 1
            return $latest.FullName
        }
    }

    return $null
}

function Test-AppGetterSandboxPackage {
    param(
        [Parameter(Mandatory = $true)]
        [string]$VersionDirectory
    )

    if (-not $VersionDirectory -or -not (Test-Path -LiteralPath $VersionDirectory)) {
        return $false
    }

    foreach ($name in @('install.ps1', 'detection.ps1', 'uninstall.ps1')) {
        if (-not (Test-Path -LiteralPath (Join-Path $VersionDirectory $name))) {
            return $false
        }
    }

    return $true
}

function Get-AppGetterSandboxPackageInfo {
    param(
        [Parameter(Mandatory = $true)]
        [string]$VersionDirectory
    )

    $dir = $VersionDirectory
    $packageId = ''
    $displayName = ''
    $version = ''
    if ($dir) {
        $version = Split-Path -Path $dir -Leaf
    }

    $appJsonPath = Join-Path $dir 'app.json'
    if ($dir -and (Test-Path -LiteralPath $appJsonPath)) {
        try {
            $app = Get-Content -LiteralPath $appJsonPath -Raw | ConvertFrom-Json
            if ($app.packageIdentifier) { $packageId = [string]$app.packageIdentifier }
            if ($app.displayName) { $displayName = [string]$app.displayName }
            if ($app.version) { $version = [string]$app.version }
        } catch {
            # Metadata is optional for sandbox testing.
        }
    }

    $installer = $null
    if ($dir -and (Test-Path -LiteralPath $dir)) {
        $installer = Get-ChildItem -LiteralPath $dir -File -ErrorAction SilentlyContinue |
            Where-Object {
                $_.Extension -in '.exe', '.msi', '.msix', '.appx' -and
                $_.Name -notlike '*intunewin*'
            } |
            Sort-Object LastWriteTime -Descending |
            Select-Object -First 1
    }

    $reason = $null
    if (-not $dir -or -not (Test-Path -LiteralPath $dir)) {
        $reason = 'Package folder was not found. Create a package first.'
    } elseif (-not (Test-Path -LiteralPath (Join-Path $dir 'install.ps1'))) {
        $reason = 'install.ps1 was not found. Create a package first.'
    } elseif (-not (Test-Path -LiteralPath (Join-Path $dir 'detection.ps1'))) {
        $reason = 'detection.ps1 was not found. Create a package first.'
    } elseif (-not (Test-Path -LiteralPath (Join-Path $dir 'uninstall.ps1'))) {
        $reason = 'uninstall.ps1 was not found. Create a package first.'
    } elseif (-not $installer) {
        $reason = 'No installer file (.exe, .msi, .msix, or .appx) was found in the package folder.'
    }

    return [PSCustomObject]@{
        Ready             = ($null -eq $reason)
        Reason            = $reason
        VersionDirectory  = if ($dir) { [System.IO.Path]::GetFullPath($dir) } else { $dir }
        PackageId         = $packageId
        DisplayName       = $displayName
        Version           = $version
        InstallerFile     = if ($installer) { $installer.FullName } else { $null }
        InstallScript     = Join-Path $dir 'install.ps1'
        DetectionScript   = Join-Path $dir 'detection.ps1'
        UninstallScript   = Join-Path $dir 'uninstall.ps1'
    }
}

function New-AppGetterSandboxGuestScript {
    return @'
# Windows Sandbox guest coordinator generated by AppGetter.
# Polls C:\AppGetterSandbox\command.json and runs install / detect / uninstall.

$ErrorActionPreference = 'Continue'
$mappedPackageRoot = 'C:\AppGetterPackage'
$packageRoot = 'C:\AppGetterTest'
$handshakeRoot = 'C:\AppGetterSandbox'
$commandPath = Join-Path $handshakeRoot 'command.json'
$statusPath = Join-Path $handshakeRoot 'status.json'
$statusNdjsonPath = Join-Path $handshakeRoot 'status.ndjson'
$heartbeatPath = Join-Path $handshakeRoot 'heartbeat.json'
$guestLogPath = Join-Path $handshakeRoot 'guest.log'

function Write-GuestLog {
    param([string]$Message)
    $line = '{0} {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Message
    try {
        Add-Content -LiteralPath $guestLogPath -Value $line -Encoding UTF8
    } catch { }
    Write-Host $line
}

function Write-GuestJson {
    param([string]$Path, $Object)
    $json = $Object | ConvertTo-Json -Depth 6
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($json)
    $stream = $null
    try {
        $stream = [System.IO.File]::Open(
            $Path,
            [System.IO.FileMode]::Create,
            [System.IO.FileAccess]::Write,
            [System.IO.FileShare]::Read
        )
        $stream.Write($bytes, 0, $bytes.Length)
        $stream.Flush()
    } finally {
        if ($stream) {
            $stream.Dispose()
        }
    }
}

function Write-Heartbeat {
    Write-GuestJson -Path $heartbeatPath -Object @{
        alive = $true
        updatedAt = (Get-Date).ToUniversalTime().ToString('o')
        computerName = $env:COMPUTERNAME
    }
}

function Write-Status {
    param(
        [string]$Step,
        [string]$State,
        [object]$ExitCode = $null,
        [string]$Message = '',
        [object]$SilentUiDetected = $null,
        [object]$SilentUiWindows = $null
    )
    $payload = @{
        step = $Step
        state = $State
        exitCode = $ExitCode
        message = $Message
        updatedAt = (Get-Date).ToUniversalTime().ToString('o')
    }
    if ($null -ne $SilentUiDetected) {
        $payload.silentUiDetected = [bool]$SilentUiDetected
    }
    if ($SilentUiWindows) {
        $payload.silentUiWindows = $SilentUiWindows
    }
    # Mapped-folder overwrites of status.json often stay stale on the host.
    # guest.log appends do propagate, so also append a status line and a new snapshot file.
    $json = $payload | ConvertTo-Json -Compress -Depth 6
    try {
        Add-Content -LiteralPath $statusNdjsonPath -Value $json -Encoding UTF8
    } catch { }
    $snapshot = Join-Path $handshakeRoot ('status-' + [DateTime]::UtcNow.ToString('yyyyMMddHHmmssfff') + '.json')
    try {
        Write-GuestJson -Path $snapshot -Object $payload
    } catch { }
    try {
        Write-GuestJson -Path $statusPath -Object $payload
    } catch { }
    if ($State -eq 'completed' -or $State -eq 'failed') {
        Write-GuestLog ("STEP_DONE step={0} state={1} exitCode={2}" -f $Step, $State, $ExitCode)
    }
}

function Read-CommandAction {
    if (-not (Test-Path -LiteralPath $commandPath)) {
        return $null
    }
    try {
        $raw = Get-Content -LiteralPath $commandPath -Raw
        if ([string]::IsNullOrWhiteSpace($raw)) { return $null }
        $cmd = $raw | ConvertFrom-Json
        return [string]$cmd.action
    } catch {
        return $null
    }
}

function Copy-PackageStepLogs {
    param(
        [string]$Step,
        [int]$ExitCode,
        [string]$StdoutPath,
        [string]$StderrPath
    )

    $stepLogDir = Join-Path $handshakeRoot ('logs\' + $Step)
    if (-not (Test-Path -LiteralPath $stepLogDir)) {
        New-Item -ItemType Directory -Path $stepLogDir -Force | Out-Null
    }

    Write-GuestJson -Path (Join-Path $stepLogDir 'step.json') -Object @{
        step = $Step
        exitCode = $ExitCode
        finishedAt = (Get-Date).ToUniversalTime().ToString('o')
        computerName = $env:COMPUTERNAME
    }

    foreach ($sourcePath in @($StdoutPath, $StderrPath)) {
        if ($sourcePath -and (Test-Path -LiteralPath $sourcePath)) {
            Copy-Item -LiteralPath $sourcePath -Destination (Join-Path $stepLogDir ([System.IO.Path]::GetFileName($sourcePath))) -Force -ErrorAction SilentlyContinue
        }
    }

    $imeLogs = Join-Path $env:ProgramData 'Microsoft\IntuneManagementExtension\Logs'
    if (Test-Path -LiteralPath $imeLogs) {
        Get-ChildItem -LiteralPath $imeLogs -File -ErrorAction SilentlyContinue | ForEach-Object {
            Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $stepLogDir $_.Name) -Force -ErrorAction SilentlyContinue
        }
        Write-GuestLog "Copied Intune logs for $Step to $stepLogDir"
    } else {
        Write-GuestLog "No Intune log folder found at $imeLogs"
    }
}

$uiIgnoreProcessNames = @(
    'powershell', 'powershell_ise', 'pwsh', 'cmd', 'conhost', 'explorer',
    'WindowsSandbox', 'WindowsSandboxClient', 'msedge', 'SearchHost', 'SearchUI',
    'StartMenuExperienceHost', 'ShellExperienceHost', 'TextInputHost',
    'ApplicationFrameHost', 'SystemSettings', 'dwm', 'sihost', 'ctfmon',
    'RuntimeBroker', 'LockApp', 'WWAHost'
)

function Test-IgnoredUiProcess {
    param([string]$ProcessName)
    foreach ($name in $uiIgnoreProcessNames) {
        if ([string]::Equals($name, $ProcessName, [StringComparison]::OrdinalIgnoreCase)) {
            return $true
        }
    }
    return $false
}

function Test-IgnoredInstallerSplash {
    param(
        [string]$ProcessName,
        [string]$Title
    )
    $t = ([string]$Title).Trim()
    if ($t -eq '(visible window, no title)') {
        $t = ''
    }
    # Inno Setup unpacks to {installer}.tmp. That process often has a generic
    # "Setup" window even under /VERYSILENT. The language wizard title is
    # "Select Setup Language", not "Setup".
    if ($ProcessName -match '\.tmp$') {
        if ([string]::IsNullOrWhiteSpace($t) -or $t -eq 'Setup' -or $t -eq 'Installing') {
            return $true
        }
    }
    return $false
}

function Get-InteractiveWindowSnapshot {
    $snapshot = @{}
    Get-Process -ErrorAction SilentlyContinue | ForEach-Object {
        if ($_.MainWindowHandle -ne 0 -and $_.MainWindowHandle -ne [IntPtr]::Zero) {
            $snapshot[$_.Id] = $true
        }
    }
    return $snapshot
}

function Save-DesktopScreenshot {
    param([string]$Path)
    try {
        Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
        Add-Type -AssemblyName System.Drawing -ErrorAction Stop
        $bounds = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
        $bmp = New-Object System.Drawing.Bitmap $bounds.Width, $bounds.Height
        $graphics = [System.Drawing.Graphics]::FromImage($bmp)
        $graphics.CopyFromScreen($bounds.Location, [System.Drawing.Point]::Empty, $bounds.Size)
        $directory = Split-Path -Path $Path -Parent
        if ($directory -and -not (Test-Path -LiteralPath $directory)) {
            New-Item -ItemType Directory -Path $directory -Force | Out-Null
        }
        $bmp.Save($Path, [System.Drawing.Imaging.ImageFormat]::Png)
        $graphics.Dispose()
        $bmp.Dispose()
        return $true
    } catch {
        Write-GuestLog "Could not capture screenshot: $_"
        return $false
    }
}

function Stop-ProcessTree {
    param([int]$Id)
    if ($Id -le 0) { return }
    try {
        & taskkill.exe /PID $Id /T /F | Out-Null
    } catch { }
}

function Invoke-PackageStep {
    param(
        [ValidateSet('install', 'detect', 'uninstall')]
        [string]$Step
    )

    $scriptName = switch ($Step) {
        'install' { 'install.ps1' }
        'detect' { 'detection.ps1' }
        'uninstall' { 'uninstall.ps1' }
    }
    $scriptPath = Join-Path $packageRoot $scriptName

    Write-Host ''
    Write-Host ('========== {0} ==========' -f $Step.ToUpper())
    Write-GuestLog "Starting $scriptName"
    Write-Status -Step $Step -State 'running' -Message "Running $scriptName"

    $stepLogDir = Join-Path $handshakeRoot ('logs\' + $Step)
    if (-not (Test-Path -LiteralPath $stepLogDir)) {
        New-Item -ItemType Directory -Path $stepLogDir -Force | Out-Null
    }

    if (-not (Test-Path -LiteralPath $scriptPath)) {
        Write-GuestLog "Missing $scriptPath"
        Write-Status -Step $Step -State 'failed' -ExitCode 1 -Message "$scriptName was not found in the mapped package folder."
        Copy-PackageStepLogs -Step $Step -ExitCode 1
        return
    }

    $logDir = Join-Path $env:ProgramData 'Microsoft\IntuneManagementExtension\Logs'
    if (-not (Test-Path -LiteralPath $logDir)) {
        New-Item -ItemType Directory -Path $logDir -Force | Out-Null
    }

    # Redirect to local disk. Mapped-folder stdout files stay open while the
    # host polls them, which can prevent powershell.exe from exiting.
    $localStepDir = Join-Path $env:TEMP ('AppGetterStep-' + $Step)
    if (Test-Path -LiteralPath $localStepDir) {
        Remove-Item -LiteralPath $localStepDir -Recurse -Force -ErrorAction SilentlyContinue
    }
    New-Item -ItemType Directory -Path $localStepDir -Force | Out-Null
    $stdoutPath = Join-Path $localStepDir 'console-stdout.txt'
    $stderrPath = Join-Path $localStepDir 'console-stderr.txt'

    function Copy-LiveStepOutput {
        try {
            if (Test-Path -LiteralPath $stdoutPath) {
                Copy-Item -LiteralPath $stdoutPath -Destination (Join-Path $stepLogDir 'console-stdout.txt') -Force -ErrorAction SilentlyContinue
            }
            if (Test-Path -LiteralPath $stderrPath) {
                Copy-Item -LiteralPath $stderrPath -Destination (Join-Path $stepLogDir 'console-stderr.txt') -Force -ErrorAction SilentlyContinue
            }
            $imeLogs = Join-Path $env:ProgramData 'Microsoft\IntuneManagementExtension\Logs'
            if (Test-Path -LiteralPath $imeLogs) {
                Get-ChildItem -LiteralPath $imeLogs -File -ErrorAction SilentlyContinue | ForEach-Object {
                    Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $stepLogDir $_.Name) -Force -ErrorAction SilentlyContinue
                }
            }
        } catch { }
    }

    function Test-LocalScriptFinished {
        foreach ($candidate in @($stdoutPath, $stderrPath)) {
            if (-not (Test-Path -LiteralPath $candidate)) { continue }
            try {
                $text = Get-Content -LiteralPath $candidate -Raw -ErrorAction Stop
                if ($text -match 'Windows PowerShell transcript end') { return $true }
                if ($text -match 'Install completed successfully') { return $true }
                if ($text -match 'Uninstall completed successfully') { return $true }
                if ($text -match 'not detected in registry, exiting with code') { return $true }
                if ($text -match 'is installed with version') { return $true }
                if ($text -match 'Uninstall returned exit code:') { return $true }
                if ($text -match 'Install failed with exit code') { return $true }
            } catch { }
        }
        return $false
    }

    # New visible windows during a silent step mean the installer ignored its
    # switches (for example Inno Setup Select Setup Language).
    $windowBaseline = Get-InteractiveWindowSnapshot
    $uiEvents = New-Object System.Collections.Generic.List[object]
    $killedForUi = $false
    $timedOut = $false
    $uiDetectedAt = $null
    $deadline = (Get-Date).AddMinutes(12)
    $ignoredSplashIds = @{}

    Set-Location -Path $packageRoot
    $process = Start-Process -FilePath 'powershell.exe' -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $scriptPath) -PassThru -NoNewWindow -RedirectStandardOutput $stdoutPath -RedirectStandardError $stderrPath

    $scriptFinished = $false
    while ($process) {
        try { $process.Refresh() } catch { }
        if ($process.HasExited) { break }

        Write-Heartbeat
        Copy-LiveStepOutput
        if ((Get-Date) -gt $deadline) {
            $timedOut = $true
            Write-GuestLog "Timed out waiting for $scriptName after 12 minutes. Stopping the process tree."
            Stop-ProcessTree -Id $process.Id
            break
        }

        Get-Process -ErrorAction SilentlyContinue | ForEach-Object {
            if ($_.MainWindowHandle -eq 0 -or $_.MainWindowHandle -eq [IntPtr]::Zero) { return }
            if ($windowBaseline.ContainsKey($_.Id)) { return }
            if (Test-IgnoredUiProcess -ProcessName $_.ProcessName) { return }

            $title = [string]$_.MainWindowTitle
            if ([string]::IsNullOrWhiteSpace($title)) {
                $title = '(visible window, no title)'
            }
            if (Test-IgnoredInstallerSplash -ProcessName $_.ProcessName -Title $title) {
                if (-not $ignoredSplashIds.ContainsKey($_.Id)) {
                    $ignoredSplashIds[$_.Id] = $true
                    Write-GuestLog ("Ignoring Inno extractor window '{0}' ({1}); this is not a setup wizard." -f $title, $_.ProcessName)
                }
                return
            }
            foreach ($existing in $uiEvents) {
                if ($existing.processId -eq $_.Id) { return }
            }
            $uiEvents.Add(@{
                processName = $_.ProcessName
                windowTitle = $title
                processId = $_.Id
                detectedAt = (Get-Date).ToUniversalTime().ToString('o')
            }) | Out-Null
            if (-not $uiDetectedAt) {
                $uiDetectedAt = Get-Date
                $shotPath = Join-Path $stepLogDir 'ui-detected.png'
                if (Save-DesktopScreenshot -Path $shotPath) {
                    Write-GuestLog "Saved UI screenshot to $shotPath"
                }
            }
            Write-GuestLog ("WARNING: interactive window detected during {0}: '{1}' ({2}). The step is not silent." -f $Step, $title, $_.ProcessName)
            Write-Status -Step $Step -State 'running' -Message ("NOT SILENT: interactive window '{0}' ({1}). Capturing diagnostics, then stopping the installer." -f $title, $_.ProcessName) -SilentUiDetected $true -SilentUiWindows @($uiEvents)
        }

        if ($uiDetectedAt -and -not $killedForUi) {
            $waited = ((Get-Date) - $uiDetectedAt).TotalSeconds
            if ($waited -ge 12) {
                $killedForUi = $true
                Write-GuestLog "Stopping $scriptName because an interactive window blocked a silent install."
                Stop-ProcessTree -Id $process.Id
                break
            }
        }

        if (-not $scriptFinished -and (Test-LocalScriptFinished)) {
            $scriptFinished = $true
            Write-GuestLog "$scriptName output ended; waiting for powershell.exe to exit."
            try { $process.WaitForExit(15000) | Out-Null } catch { }
            try { $process.Refresh() } catch { }
            if (-not $process.HasExited) {
                Write-GuestLog "$scriptName finished writing output but powershell.exe is still running. Stopping it so confirmation can continue."
                Stop-ProcessTree -Id $process.Id
            }
            break
        }

        Start-Sleep -Seconds 1
    }

    if ($process) {
        try { $process.Refresh() } catch { }
    }
    if ($process -and -not $process.HasExited) {
        try { $process.WaitForExit(20000) | Out-Null } catch { }
        try { $process.Refresh() } catch { }
    }
    if ($process -and -not $process.HasExited) {
        Stop-ProcessTree -Id $process.Id
        try { $process.WaitForExit(5000) | Out-Null } catch { }
        try { $process.Refresh() } catch { }
    }

    Copy-LiveStepOutput

    $exitCode = 1
    if ($killedForUi) {
        $exitCode = 1603
    } elseif ($timedOut) {
        $exitCode = 1603
    } else {
        $outputExit = $null
        foreach ($candidate in @($stdoutPath, $stderrPath)) {
            if (-not (Test-Path -LiteralPath $candidate)) { continue }
            try {
                $text = Get-Content -LiteralPath $candidate -Raw -ErrorAction Stop
                if ($text -match 'Install failed with exit code (-?\d+)') { $outputExit = [int]$Matches[1]; break }
                if ($text -match 'Uninstall returned exit code:\s*(-?\d+)') { $outputExit = [int]$Matches[1]; break }
                if ($text -match 'not detected in registry, exiting with code 1') { $outputExit = 1; break }
                if ($text -match 'Install completed successfully \(hard reboot required - 1641\)') { $outputExit = 1641; break }
                if ($text -match 'Install completed successfully \(reboot required - 3010\)') { $outputExit = 3010; break }
                if ($text -match 'Another installation is already in progress \(1618\)') { $outputExit = 1618; break }
                if ($text -match 'Install completed successfully') { $outputExit = 0; break }
                if ($text -match 'Uninstall completed successfully') { $outputExit = 0; break }
                if ($text -match 'is installed with version') { $outputExit = 0; break }
            } catch { }
        }
        if ($null -ne $outputExit) {
            $exitCode = $outputExit
        } elseif ($process -and $null -ne $process.ExitCode -and [int]$process.ExitCode -ge 0) {
            $exitCode = [int]$process.ExitCode
        } elseif ($scriptFinished) {
            $exitCode = 0
        }
    }

    $silentUi = ($uiEvents.Count -gt 0)
    if ($silentUi) {
        Write-GuestJson -Path (Join-Path $stepLogDir 'ui-activity.json') -Object @{
            step = $Step
            notSilent = $true
            killedForUi = $killedForUi
            timedOut = $timedOut
            events = @($uiEvents)
        }
    }

    Copy-PackageStepLogs -Step $Step -ExitCode $exitCode -StdoutPath $stdoutPath -StderrPath $stderrPath

    $message = "$scriptName finished with exit code $exitCode."
    if ($silentUi) {
        $titles = @($uiEvents | ForEach-Object { $_.windowTitle }) -join '; '
        $message = "$scriptName was not silent. Interactive window(s): $titles. Exit code $exitCode. Screenshot and logs were copied for diagnostics."
    } elseif ($timedOut) {
        $message = "$scriptName timed out after 12 minutes and was stopped. Exit code $exitCode."
    }
    Write-GuestLog $message
    Write-Host $message
    Write-Host 'Waiting for confirmation in AppGetter...'
    Write-Status -Step $Step -State 'completed' -ExitCode ([int]$exitCode) -Message $message -SilentUiDetected $silentUi -SilentUiWindows @($uiEvents)
}

$deadline = (Get-Date).AddMinutes(2)
while (-not (Test-Path -LiteralPath (Join-Path $mappedPackageRoot 'install.ps1'))) {
    if ((Get-Date) -gt $deadline) {
        Write-GuestLog "Mapped package folder not available: $mappedPackageRoot"
        Write-Status -Step 'idle' -State 'failed' -ExitCode 1 -Message 'Mapped package folder was not available inside Windows Sandbox.'
        return
    }
    Start-Sleep -Seconds 1
}

if (-not (Test-Path -LiteralPath $handshakeRoot)) {
    New-Item -ItemType Directory -Path $handshakeRoot -Force | Out-Null
}

if (-not (Test-Path -LiteralPath $packageRoot)) {
    New-Item -ItemType Directory -Path $packageRoot -Force | Out-Null
}
Copy-Item -Path (Join-Path $mappedPackageRoot '*') -Destination $packageRoot -Recurse -Force
Write-GuestLog "Copied package files to $packageRoot"

Write-GuestLog 'Windows Sandbox guest coordinator is ready.'
Write-Heartbeat
Write-Status -Step 'idle' -State 'waiting' -Message 'Waiting for the first test command from AppGetter.'

$lastAction = ''
while ($true) {
    Write-Heartbeat
    $action = Read-CommandAction
    if ($action -and $action -ne $lastAction) {
        $lastAction = $action
        switch ($action) {
            'install' { Invoke-PackageStep -Step 'install' }
            'detect' { Invoke-PackageStep -Step 'detect' }
            'uninstall' { Invoke-PackageStep -Step 'uninstall' }
            'shutdown' {
                Write-GuestLog 'Shutdown requested.'
                Write-Status -Step 'shutdown' -State 'completed' -ExitCode 0 -Message 'Sandbox shutdown requested.'
                Start-Sleep -Seconds 1
                Stop-Computer -Force
                return
            }
            default {
                Write-GuestLog "Ignoring command: $action"
            }
        }
    }
    Start-Sleep -Seconds 1
}
'@
}

function New-AppGetterSandboxWsbContent {
    param(
        [Parameter(Mandatory = $true)]
        [string]$HostPackagePath,
        [Parameter(Mandatory = $true)]
        [string]$HostHandshakePath,
        [string]$PackageSandboxPath = 'C:\AppGetterPackage',
        [string]$HandshakeSandboxPath = 'C:\AppGetterSandbox',
        [int]$MemoryInMB = 4096,
        [string]$GuestScriptFileName = 'Start-AppGetterSandboxGuest.ps1'
    )

    $packageHost = ConvertTo-AppGetterXmlText -Value $HostPackagePath.TrimEnd('\')
    $handshakeHost = ConvertTo-AppGetterXmlText -Value $HostHandshakePath.TrimEnd('\')
    $packageSandbox = ConvertTo-AppGetterXmlText -Value $PackageSandboxPath
    $handshakeSandbox = ConvertTo-AppGetterXmlText -Value $HandshakeSandboxPath
    # Sandbox-side Windows paths must not use Join-Path (that resolves drives on the host).
    $guestScript = ($HandshakeSandboxPath.TrimEnd('\')) + '\' + $GuestScriptFileName
    $logonCommand = ConvertTo-AppGetterXmlText -Value (
        "powershell.exe -NoProfile -ExecutionPolicy Bypass -NoExit -WindowStyle Normal -File `"$guestScript`""
    )
    $memory = [int]$MemoryInMB
    if ($memory -lt 2048) {
        $memory = 2048
    }

    return @"
<Configuration>
  <VGpu>Enable</VGpu>
  <Networking>Default</Networking>
  <MappedFolders>
    <MappedFolder>
      <HostFolder>$packageHost</HostFolder>
      <SandboxFolder>$packageSandbox</SandboxFolder>
      <ReadOnly>true</ReadOnly>
    </MappedFolder>
    <MappedFolder>
      <HostFolder>$handshakeHost</HostFolder>
      <SandboxFolder>$handshakeSandbox</SandboxFolder>
      <ReadOnly>false</ReadOnly>
    </MappedFolder>
  </MappedFolders>
  <LogonCommand>
    <Command>$logonCommand</Command>
  </LogonCommand>
  <MemoryInMB>$memory</MemoryInMB>
  <ClipboardRedirection>Enable</ClipboardRedirection>
</Configuration>
"@
}

function Start-AppGetterSandboxSession {
    <#
    .SYNOPSIS
        Creates a Windows Sandbox session that can install, detect, and uninstall a packaged app.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$VersionDirectory,
        [switch]$SkipLaunch,
        [int]$MemoryInMB = 4096
    )

    $package = Get-AppGetterSandboxPackageInfo -VersionDirectory $VersionDirectory
    if (-not $package.Ready) {
        throw $package.Reason
    }

    $sessionId = [Guid]::NewGuid().ToString('N')
    $handshake = Join-Path ([System.IO.Path]::GetTempPath()) "AppGetterSandbox-$sessionId"
    New-Item -ItemType Directory -Path $handshake -Force | Out-Null

    $guestScriptPath = Join-Path $handshake 'Start-AppGetterSandboxGuest.ps1'
    Set-Content -LiteralPath $guestScriptPath -Value (New-AppGetterSandboxGuestScript) -Encoding UTF8

    Write-AppGetterSandboxJson -Path (Join-Path $handshake 'command.json') -Object @{
        action   = 'install'
        issuedAt = (Get-Date).ToUniversalTime().ToString('o')
    }

    Write-AppGetterSandboxJson -Path (Join-Path $handshake 'status.json') -Object @{
        step      = 'idle'
        state     = 'waiting'
        exitCode  = $null
        message   = 'Waiting for Windows Sandbox to start.'
        updatedAt = (Get-Date).ToUniversalTime().ToString('o')
    }

    $wsbPath = Join-Path $handshake 'AppGetterSandbox.wsb'
    $wsb = New-AppGetterSandboxWsbContent `
        -HostPackagePath $package.VersionDirectory `
        -HostHandshakePath $handshake `
        -MemoryInMB $MemoryInMB
    Set-Content -LiteralPath $wsbPath -Value $wsb -Encoding UTF8

    $launched = $false
    $processId = $null
    if (-not $SkipLaunch) {
        $sandbox = Test-AppGetterWindowsSandbox
        if (-not $sandbox.Enabled) {
            throw $sandbox.Reason
        }

        $process = Start-Process -FilePath $sandbox.ExecutablePath -ArgumentList @("`"$wsbPath`"") -PassThru
        $launched = $true
        if ($process) {
            $processId = $process.Id
        }
    }

    return [PSCustomObject]@{
        SessionId           = $sessionId
        HandshakeDirectory  = $handshake
        WsbPath             = $wsbPath
        GuestScriptPath     = $guestScriptPath
        VersionDirectory    = $package.VersionDirectory
        PackageId           = $package.PackageId
        DisplayName         = $package.DisplayName
        Version             = $package.Version
        CommandPath         = Join-Path $handshake 'command.json'
        StatusPath          = Join-Path $handshake 'status.json'
        HeartbeatPath       = Join-Path $handshake 'heartbeat.json'
        GuestLogPath        = Join-Path $handshake 'guest.log'
        Launched            = $launched
        ProcessId           = $processId
        CurrentStep         = 'install'
        StartedAt           = Get-Date
    }
}

function Set-AppGetterSandboxCommand {
    param(
        [Parameter(Mandatory = $true)]
        [string]$HandshakeDirectory,
        [Parameter(Mandatory = $true)]
        [ValidateSet('install', 'detect', 'uninstall', 'shutdown', 'idle')]
        [string]$Action
    )

    $path = Join-Path $HandshakeDirectory 'command.json'
    Write-AppGetterSandboxJson -Path $path -Object @{
        action   = $Action
        issuedAt = (Get-Date).ToUniversalTime().ToString('o')
    }
}

function Get-AppGetterSandboxStatus {
    param(
        [Parameter(Mandatory = $true)]
        [string]$HandshakeDirectory
    )

    $candidates = New-Object System.Collections.Generic.List[object]

    foreach ($name in @('status.json')) {
        $obj = Read-AppGetterSandboxJson -Path (Join-Path $HandshakeDirectory $name)
        if ($obj) {
            $candidates.Add($obj) | Out-Null
        }
    }

    Get-ChildItem -LiteralPath $HandshakeDirectory -File -Filter 'status-*.json' -ErrorAction SilentlyContinue | ForEach-Object {
        $obj = Read-AppGetterSandboxJson -Path $_.FullName
        if ($obj) {
            $candidates.Add($obj) | Out-Null
        }
    }

    $ndjsonPath = Join-Path $HandshakeDirectory 'status.ndjson'
    if (Test-Path -LiteralPath $ndjsonPath) {
        foreach ($line in @(Read-AppGetterSandboxText -Path $ndjsonPath)) {
            if ([string]::IsNullOrWhiteSpace($line)) { continue }
            try {
                $candidates.Add(($line | ConvertFrom-Json)) | Out-Null
            } catch { }
        }
    }

    if ($candidates.Count -eq 0) {
        return $null
    }

    $best = $candidates[0]
    $bestTime = [datetime]::MinValue
    foreach ($candidate in $candidates) {
        $stamp = [datetime]::MinValue
        if ($candidate.updatedAt) {
            try { $stamp = [datetime]$candidate.updatedAt } catch { }
        }
        if ($stamp -ge $bestTime) {
            $bestTime = $stamp
            $best = $candidate
        }
    }

    return $best
}

function Get-AppGetterSandboxHeartbeat {
    param(
        [Parameter(Mandatory = $true)]
        [string]$HandshakeDirectory
    )

    $path = Join-Path $HandshakeDirectory 'heartbeat.json'
    $heartbeat = Read-AppGetterSandboxJson -Path $path
    if (-not $heartbeat) {
        return $null
    }

    $updatedAt = $null
    if ($heartbeat.updatedAt) {
        try {
            $updatedAt = [datetime]$heartbeat.updatedAt
        } catch {
            $updatedAt = $null
        }
    }

    $ageSeconds = $null
    if ($updatedAt) {
        $ageSeconds = [math]::Max(0, ((Get-Date).ToUniversalTime() - $updatedAt.ToUniversalTime()).TotalSeconds)
    }

    return [PSCustomObject]@{
        Alive      = [bool]$heartbeat.alive
        UpdatedAt  = $updatedAt
        AgeSeconds = $ageSeconds
        Raw        = $heartbeat
    }
}

function Get-AppGetterSandboxGuestLog {
    param(
        [Parameter(Mandatory = $true)]
        [string]$HandshakeDirectory,
        [int]$Tail = 40,
        [switch]$IncludeStepLogs
    )

    $blocks = New-Object System.Collections.Generic.List[string]
    $path = Join-Path $HandshakeDirectory 'guest.log'
    if (Test-Path -LiteralPath $path) {
        $lines = @(Read-AppGetterSandboxText -Path $path)
        if ($Tail -gt 0 -and $lines.Count -gt $Tail) {
            $lines = $lines | Select-Object -Last $Tail
        }
        if ($lines) {
            $blocks.Add(($lines -join "`r`n")) | Out-Null
        }
    }

    if ($IncludeStepLogs) {
        foreach ($step in @('install', 'detect', 'uninstall')) {
            $stepDir = Join-Path (Join-Path $HandshakeDirectory 'logs') $step
            if (-not (Test-Path -LiteralPath $stepDir)) {
                continue
            }

            $ime = Get-ChildItem -LiteralPath $stepDir -File -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -like '*-install.log' -or $_.Name -like '*-detection.log' -or $_.Name -like '*-uninstall.log' } |
                Sort-Object LastWriteTime -Descending |
                Select-Object -First 1
            if (-not $ime) {
                $ime = Get-ChildItem -LiteralPath $stepDir -File -ErrorAction SilentlyContinue |
                    Where-Object { $_.Name -eq 'console-stdout.txt' } |
                    Select-Object -First 1
            }
            if ($ime) {
                $stepLines = @(Read-AppGetterSandboxText -Path $ime.FullName)
                if ($Tail -gt 0 -and $stepLines.Count -gt $Tail) {
                    $stepLines = $stepLines | Select-Object -Last $Tail
                }
                if ($stepLines) {
                    $blocks.Add(('--- {0} ({1}) ---' -f $step, $ime.Name)) | Out-Null
                    $blocks.Add(($stepLines -join "`r`n")) | Out-Null
                }
            }
        }
    }

    return ($blocks -join "`r`n")
}

function Limit-AppGetterReportText {
    param(
        [string]$Text,
        [int]$MaxChars = 14000
    )

    if ([string]::IsNullOrEmpty($Text)) {
        return ''
    }
    if ($Text.Length -le $MaxChars) {
        return $Text
    }

    $keepHead = [int]($MaxChars * 0.65)
    $keepTail = $MaxChars - $keepHead - 80
    if ($keepTail -lt 500) {
        $keepTail = 500
        $keepHead = $MaxChars - $keepTail - 80
    }

    $omitted = $Text.Length - $MaxChars
    return (
        $Text.Substring(0, $keepHead) +
        "`r`n`r`n[... truncated $omitted characters ...]`r`n`r`n" +
        $Text.Substring($Text.Length - $keepTail)
    )
}

function Read-AppGetterTextFile {
    param(
        [string]$Path,
        [int]$MaxChars = 14000
    )

    if (-not $Path -or -not (Test-Path -LiteralPath $Path)) {
        return ''
    }

    try {
        $raw = Get-Content -LiteralPath $Path -Raw -ErrorAction Stop
        return (Limit-AppGetterReportText -Text $raw -MaxChars $MaxChars)
    } catch {
        return ''
    }
}

function Copy-AppGetterSandboxLogsToPackage {
    param(
        [string]$HandshakeDirectory,
        [string]$VersionDirectory
    )

    if (-not $HandshakeDirectory -or -not $VersionDirectory) {
        return $null
    }
    if (-not (Test-Path -LiteralPath $HandshakeDirectory) -or -not (Test-Path -LiteralPath $VersionDirectory)) {
        return $null
    }

    $dest = Join-Path $VersionDirectory 'sandbox-logs'
    if (Test-Path -LiteralPath $dest) {
        Remove-Item -LiteralPath $dest -Recurse -Force -ErrorAction SilentlyContinue
    }
    New-Item -ItemType Directory -Path $dest -Force | Out-Null

    $guestLog = Join-Path $HandshakeDirectory 'guest.log'
    if (Test-Path -LiteralPath $guestLog) {
        Copy-Item -LiteralPath $guestLog -Destination (Join-Path $dest 'guest.log') -Force -ErrorAction SilentlyContinue
    }

    foreach ($name in @('command.json', 'status.json', 'heartbeat.json', 'status.ndjson')) {
        $source = Join-Path $HandshakeDirectory $name
        if (Test-Path -LiteralPath $source) {
            Copy-Item -LiteralPath $source -Destination (Join-Path $dest $name) -Force -ErrorAction SilentlyContinue
        }
    }
    Get-ChildItem -LiteralPath $HandshakeDirectory -File -Filter 'status-*.json' -ErrorAction SilentlyContinue | ForEach-Object {
        Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $dest $_.Name) -Force -ErrorAction SilentlyContinue
    }

    $logsRoot = Join-Path $HandshakeDirectory 'logs'
    if (Test-Path -LiteralPath $logsRoot) {
        Copy-Item -Path $logsRoot -Destination (Join-Path $dest 'steps') -Recurse -Force -ErrorAction SilentlyContinue
    }

    return $dest
}

function Get-AppGetterSandboxTestReportPath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$VersionDirectory
    )

    return (Join-Path $VersionDirectory 'sandbox-test-report.txt')
}

function Get-AppGetterInstallCommandFromScript {
    param([string]$ScriptPath)

    if (-not $ScriptPath -or -not (Test-Path -LiteralPath $ScriptPath)) {
        return ''
    }

    try {
        $raw = Get-Content -LiteralPath $ScriptPath -Raw -ErrorAction Stop
        $match = [regex]::Match($raw, '(?s)\$installCommand = @''(.*?)''@')
        if ($match.Success) {
            return $match.Groups[1].Value.Trim()
        }
    } catch {
        return ''
    }

    return ''
}

function Get-AppGetterPackageSilentInstallInfo {
    param(
        [Parameter(Mandatory = $true)]
        [string]$VersionDirectory
    )

    $installer = $null
    if (Test-Path -LiteralPath $VersionDirectory) {
        $installer = Get-ChildItem -LiteralPath $VersionDirectory -File -ErrorAction SilentlyContinue |
            Where-Object {
                $_.Extension -in '.exe', '.msi', '.msix', '.appx' -and
                $_.Name -notlike '*intunewin*'
            } |
            Sort-Object LastWriteTime -Descending |
            Select-Object -First 1
    }

    $discovery = $null
    $appJsonPath = Join-Path $VersionDirectory 'app.json'
    if (Test-Path -LiteralPath $appJsonPath) {
        try {
            $app = Get-Content -LiteralPath $appJsonPath -Raw | ConvertFrom-Json
            if ($app.switchDiscovery) {
                $discovery = $app.switchDiscovery
            }
        } catch {
            $discovery = $null
        }
    }

    $manifest = $null
    $manifestPath = Join-Path $VersionDirectory 'silent-switches.json'
    if (Test-Path -LiteralPath $manifestPath) {
        try {
            $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
        } catch {
            $manifest = $null
        }
    }

    $packagedCommand = Get-AppGetterInstallCommandFromScript -ScriptPath (Join-Path $VersionDirectory 'install.ps1')

    $resolved = $null
    if ($installer) {
        try {
            $resolved = Resolve-InstallerInstallCommand `
                -InstallerPath $installer.FullName `
                -InstallerFileName $installer.Name `
                -SkipVerification
        } catch {
            $resolved = $null
        }
    }

    $recommended = $null
    if ($resolved) {
        $recommended = [PSCustomObject]@{
            Engine              = [string]$resolved.InstallerFamily
            EngineSource        = 'switchDiscovery'
            PrimaryType         = [string]$resolved.PrimaryType
            ConfidenceScore     = $resolved.ConfidenceScore
            Command             = [string]$resolved.RecommendedCommand
            Verified            = [bool]$resolved.Verified
            NeedsManualReview   = [bool]$resolved.NeedsManualReview
            EvidenceSummary     = @($resolved.EvidenceSummary)
            AlternativeCommands = @($resolved.AlternativeCommands)
        }
    } elseif ($discovery) {
        $recommended = [PSCustomObject]@{
            Engine              = [string]$discovery.installerFamily
            EngineSource        = 'app.json'
            PrimaryType         = [string]$discovery.primaryType
            ConfidenceScore     = $discovery.confidenceScore
            Command             = if ($discovery.recommendedCommand) { [string]$discovery.recommendedCommand } else { $packagedCommand }
            Verified            = [bool]$discovery.verified
            NeedsManualReview   = [bool]$discovery.needsManualReview
            EvidenceSummary     = @($discovery.evidenceSummary)
            AlternativeCommands = @($discovery.alternativeCommands)
        }
    } elseif ($manifest) {
        $recommended = [PSCustomObject]@{
            Engine              = [string]$manifest.engine
            EngineSource        = 'silent-switches.json'
            PrimaryType         = [string]$manifest.primaryType
            ConfidenceScore     = $manifest.confidenceScore
            Command             = if ($manifest.command) { [string]$manifest.command } else { $packagedCommand }
            Verified            = [bool]$manifest.verified
            NeedsManualReview   = [bool]$manifest.needsManualReview
            EvidenceSummary     = @($manifest.evidenceSummary)
            AlternativeCommands = @($manifest.alternativeCommands)
        }
    }

    $mismatch = $false
    $mismatchReason = ''
    if ($packagedCommand -and $recommended -and $recommended.Command) {
        if (-not [string]::Equals($packagedCommand, [string]$recommended.Command, [StringComparison]::OrdinalIgnoreCase)) {
            $mismatch = $true
            $mismatchReason = "Packaged install.ps1 uses '$packagedCommand' but the discovered command for this installer is '$($recommended.Command)'."
        }
    }

    return [PSCustomObject]@{
        Discovery        = $discovery
        Manifest         = $manifest
        ManifestPath     = $manifestPath
        PackagedCommand  = $packagedCommand
        Recommended      = $recommended
        InstallerPath    = if ($installer) { $installer.FullName } else { $null }
        Mismatch         = $mismatch
        MismatchReason   = $mismatchReason
    }
}

function Write-AppGetterSandboxTestReport {
    <#
    .SYNOPSIS
        Writes a chat-ready sandbox test report next to the packaged app.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$VersionDirectory,
        [string]$HandshakeDirectory,
        [hashtable]$Confirmations,
        [string]$Outcome = 'in-progress',
        [string]$Message = ''
    )

    $info = $null
    try {
        $info = Get-AppGetterSandboxPackageInfo -VersionDirectory $VersionDirectory
    } catch {
        $info = $null
    }

    $silentInfo = $null
    try {
        $silentInfo = Get-AppGetterPackageSilentInstallInfo -VersionDirectory $VersionDirectory
    } catch {
        $silentInfo = $null
    }

    $copiedLogs = $null
    if ($HandshakeDirectory) {
        $copiedLogs = Copy-AppGetterSandboxLogsToPackage -HandshakeDirectory $HandshakeDirectory -VersionDirectory $VersionDirectory
    }

    $builder = New-Object System.Text.StringBuilder
    [void]$builder.AppendLine('=== AppGetter sandbox test report ===')
    [void]$builder.AppendLine('Paste this entire file into chat if a sandbox install/detect/uninstall needs diagnosis.')
    [void]$builder.AppendLine(('Generated (UTC): {0}' -f (Get-Date).ToUniversalTime().ToString('o')))
    [void]$builder.AppendLine(('Outcome: {0}' -f $Outcome))
    if ($Message) {
        [void]$builder.AppendLine(('Message: {0}' -f $Message))
    }
    [void]$builder.AppendLine('')

    $displayName = if ($info -and $info.DisplayName) { $info.DisplayName } else { '' }
    $packageId = if ($info -and $info.PackageId) { $info.PackageId } else { '' }
    $version = if ($info -and $info.Version) { $info.Version } else { '' }
    [void]$builder.AppendLine('--- Package ---')
    [void]$builder.AppendLine(('Display name: {0}' -f $displayName))
    [void]$builder.AppendLine(('Package ID: {0}' -f $packageId))
    [void]$builder.AppendLine(('Version: {0}' -f $version))
    [void]$builder.AppendLine(('Package folder: {0}' -f $VersionDirectory))
    if ($HandshakeDirectory) {
        [void]$builder.AppendLine(('Handshake folder: {0}' -f $HandshakeDirectory))
    }
    if ($copiedLogs) {
        [void]$builder.AppendLine(('Copied sandbox logs: {0}' -f $copiedLogs))
    }
    [void]$builder.AppendLine('')

    [void]$builder.AppendLine('--- Silent install verification ---')
    if ($silentInfo -and $silentInfo.Recommended) {
        $plan = $silentInfo.Recommended
        [void]$builder.AppendLine(('Installer family: {0} (source: {1})' -f $plan.Engine, $plan.EngineSource))
        if ($plan.PrimaryType) {
            [void]$builder.AppendLine(('Primary type: {0}' -f $plan.PrimaryType))
        }
        if ($null -ne $plan.ConfidenceScore) {
            [void]$builder.AppendLine(('Confidence score: {0}' -f $plan.ConfidenceScore))
        }
        [void]$builder.AppendLine(('Packaged / discovered command: {0}' -f $plan.Command))
        [void]$builder.AppendLine(('Verified: {0}' -f $plan.Verified))
        if ($plan.NeedsManualReview) {
            [void]$builder.AppendLine('Needs manual review: True')
        }
        foreach ($evidence in @($plan.EvidenceSummary)) {
            if ($evidence) {
                [void]$builder.AppendLine(('Evidence: {0}' -f $evidence))
            }
        }
        foreach ($alt in @($plan.AlternativeCommands)) {
            if ($alt) {
                [void]$builder.AppendLine(('Alternative: {0}' -f $alt))
            }
        }
    } elseif ($silentInfo -and $silentInfo.Manifest) {
        [void]$builder.AppendLine(('Engine: {0}' -f $silentInfo.Manifest.engine))
        [void]$builder.AppendLine(('Command: {0}' -f $silentInfo.Manifest.command))
        [void]$builder.AppendLine(('Verified: {0}' -f $silentInfo.Manifest.verified))
    } else {
        [void]$builder.AppendLine('No switchDiscovery metadata or silent-switches.json was found to verify.')
    }

    if ($silentInfo -and $silentInfo.PackagedCommand) {
        [void]$builder.AppendLine(('Packaged install.ps1 command: {0}' -f $silentInfo.PackagedCommand))
    }
    if ($silentInfo -and $silentInfo.InstallerPath) {
        [void]$builder.AppendLine(('Installer file: {0}' -f $silentInfo.InstallerPath))
    }
    if ($silentInfo -and $silentInfo.Mismatch) {
        [void]$builder.AppendLine(('WARNING: {0}' -f $silentInfo.MismatchReason))
        [void]$builder.AppendLine('Test in Sandbox runs the packaged install.ps1 as-is. Re-create the package with this AppGetter version to bake in verified silent switches.')
    }
    [void]$builder.AppendLine('')

    [void]$builder.AppendLine('--- Step results ---')
    foreach ($step in @('install', 'detect', 'uninstall')) {
        $item = $null
        if ($Confirmations -and $Confirmations.ContainsKey($step)) {
            $item = $Confirmations[$step]
        }
        $confirmed = if ($item) { Get-ConfirmationValue -Item $item -Name 'Confirmed' } else { $null }
        $exitCode = if ($item) { Get-ConfirmationValue -Item $item -Name 'ExitCode' } else { $null }
        $stepMessage = if ($item) { Get-ConfirmationValue -Item $item -Name 'Message' } else { $null }
        $confirmedAt = if ($item) { Get-ConfirmationValue -Item $item -Name 'ConfirmedAt' } else { $null }
        $silentUi = if ($item) { Get-ConfirmationValue -Item $item -Name 'SilentUiDetected' } else { $null }
        [void]$builder.AppendLine(('{0}: confirmed={1}; exitCode={2}; silentUi={3}; at={4}; message={5}' -f $step, $confirmed, $exitCode, $silentUi, $confirmedAt, $stepMessage))
    }
    [void]$builder.AppendLine('')

    $statusJson = ''
    $statusNdjson = ''
    $commandJson = ''
    if ($HandshakeDirectory) {
        $latestStatus = Get-AppGetterSandboxStatus -HandshakeDirectory $HandshakeDirectory
        if ($latestStatus) {
            $statusJson = ($latestStatus | ConvertTo-Json -Depth 6)
        } else {
            $statusJson = Read-AppGetterTextFile -Path (Join-Path $HandshakeDirectory 'status.json') -MaxChars 4000
        }
        $statusNdjson = Read-AppGetterTextFile -Path (Join-Path $HandshakeDirectory 'status.ndjson') -MaxChars 8000
        $commandJson = Read-AppGetterTextFile -Path (Join-Path $HandshakeDirectory 'command.json') -MaxChars 2000
    }
    if ($commandJson) {
        [void]$builder.AppendLine('--- command.json ---')
        [void]$builder.AppendLine($commandJson)
        [void]$builder.AppendLine('')
    }
    if ($statusJson) {
        [void]$builder.AppendLine('--- status.json ---')
        [void]$builder.AppendLine($statusJson)
        [void]$builder.AppendLine('')
    }
    if ($statusNdjson) {
        [void]$builder.AppendLine('--- status.ndjson ---')
        [void]$builder.AppendLine($statusNdjson)
        [void]$builder.AppendLine('')
    }

    $guestLogText = ''
    if ($HandshakeDirectory) {
        $guestLogText = Read-AppGetterTextFile -Path (Join-Path $HandshakeDirectory 'guest.log') -MaxChars 12000
    } elseif ($copiedLogs) {
        $guestLogText = Read-AppGetterTextFile -Path (Join-Path $copiedLogs 'guest.log') -MaxChars 12000
    }
    [void]$builder.AppendLine('--- Guest coordinator log ---')
    if ($guestLogText) {
        [void]$builder.AppendLine($guestLogText)
    } else {
        [void]$builder.AppendLine('(no guest.log yet)')
    }
    [void]$builder.AppendLine('')

    $logRoot = $null
    if ($HandshakeDirectory -and (Test-Path -LiteralPath (Join-Path $HandshakeDirectory 'logs'))) {
        $logRoot = Join-Path $HandshakeDirectory 'logs'
    } elseif ($copiedLogs -and (Test-Path -LiteralPath (Join-Path $copiedLogs 'steps'))) {
        $logRoot = Join-Path $copiedLogs 'steps'
    }

    foreach ($step in @('install', 'detect', 'uninstall')) {
        [void]$builder.AppendLine(('--- {0} logs ---' -f $step))
        if (-not $logRoot) {
            [void]$builder.AppendLine('(no copied step logs)')
            [void]$builder.AppendLine('')
            continue
        }

        $stepDir = Join-Path $logRoot $step
        if (-not (Test-Path -LiteralPath $stepDir)) {
            [void]$builder.AppendLine('(step not run or logs were not copied)')
            [void]$builder.AppendLine('')
            continue
        }

        $preferred = @(
            (Join-Path $stepDir 'step.json')
            (Join-Path $stepDir 'ui-activity.json')
            (Join-Path $stepDir 'console-stdout.txt')
            (Join-Path $stepDir 'console-stderr.txt')
        )
        $imeFiles = @(Get-ChildItem -LiteralPath $stepDir -File -ErrorAction SilentlyContinue |
            Where-Object { $_.Extension -eq '.log' } |
            Sort-Object Name)
        foreach ($filePath in @($preferred + @($imeFiles | ForEach-Object { $_.FullName }))) {
            if (-not $filePath -or -not (Test-Path -LiteralPath $filePath)) {
                continue
            }
            $content = Read-AppGetterTextFile -Path $filePath -MaxChars 10000
            if (-not $content) {
                continue
            }
            [void]$builder.AppendLine(('[{0}]' -f ([System.IO.Path]::GetFileName($filePath))))
            [void]$builder.AppendLine($content)
            [void]$builder.AppendLine('')
        }
    }

    $text = $builder.ToString()
    $text = Limit-AppGetterReportText -Text $text -MaxChars 80000
    $reportPath = Get-AppGetterSandboxTestReportPath -VersionDirectory $VersionDirectory
    Set-Content -LiteralPath $reportPath -Value $text -Encoding UTF8

    $failureLog = Write-AppGetterSandboxFailureLog `
        -VersionDirectory $VersionDirectory `
        -ReportText $text `
        -Outcome $Outcome `
        -Message $Message `
        -Confirmations $Confirmations `
        -PackageInfo $info `
        -CopiedLogsPath $copiedLogs `
        -HandshakeDirectory $HandshakeDirectory

    return [PSCustomObject]@{
        Path              = $reportPath
        Text              = $text
        CopiedLogsPath    = $copiedLogs
        FailureLogPath    = $failureLog
        Outcome           = $Outcome
    }
}

function Get-AppGetterSandboxFailureLogPath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$VersionDirectory
    )

    return (Join-Path $VersionDirectory 'sandbox-failure.log')
}

function Write-AppGetterSandboxFailureLog {
    param(
        [Parameter(Mandatory = $true)]
        [string]$VersionDirectory,
        [string]$ReportText,
        [string]$Outcome,
        [string]$Message,
        [hashtable]$Confirmations,
        $PackageInfo,
        [string]$CopiedLogsPath,
        [string]$HandshakeDirectory
    )

    $failed = $Outcome -ne 'validated'
    $silentUi = $false
    $uiTitles = @()
    if ($Confirmations -and $Confirmations.ContainsKey('install')) {
        $silentUi = [bool](Get-ConfirmationValue -Item $Confirmations['install'] -Name 'SilentUiDetected')
    }

    $uiActivity = $null
    foreach ($root in @($HandshakeDirectory, $CopiedLogsPath)) {
        if (-not $root) { continue }
        $candidate = Join-Path (Join-Path (Join-Path $root 'logs') 'install') 'ui-activity.json'
        if (-not (Test-Path -LiteralPath $candidate)) {
            $candidate = Join-Path (Join-Path (Join-Path $root 'steps') 'install') 'ui-activity.json'
        }
        if (Test-Path -LiteralPath $candidate) {
            try {
                $uiActivity = Get-Content -LiteralPath $candidate -Raw | ConvertFrom-Json
                $silentUi = $true
                if ($uiActivity.events) {
                    $uiTitles = @($uiActivity.events | ForEach-Object { $_.windowTitle })
                }
            } catch { }
            break
        }
    }

    if (-not $failed -and -not $silentUi) {
        $existing = Get-AppGetterSandboxFailureLogPath -VersionDirectory $VersionDirectory
        if (Test-Path -LiteralPath $existing) {
            Remove-Item -LiteralPath $existing -Force -ErrorAction SilentlyContinue
        }
        return $null
    }

    $displayName = if ($PackageInfo -and $PackageInfo.DisplayName) { $PackageInfo.DisplayName } else { '' }
    $packageId = if ($PackageInfo -and $PackageInfo.PackageId) { $PackageInfo.PackageId } else { '' }
    $version = if ($PackageInfo -and $PackageInfo.Version) { $PackageInfo.Version } else { '' }

    $why = $Message
    if ($silentUi) {
        $titleText = if ($uiTitles.Count -gt 0) { ($uiTitles -join '; ') } else { 'an installer dialog' }
        $why = "Install was not silent. Windows Sandbox showed interactive UI ($titleText). Intune Win32 installs cannot click through that dialog."
        if ($Message) {
            $why = "$why $Message"
        }
    } elseif (-not $why) {
        $why = "Sandbox test outcome: $Outcome"
    }

    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add('AppGetter sandbox failure') | Out-Null
    $lines.Add(('Generated (UTC): {0}' -f (Get-Date).ToUniversalTime().ToString('o'))) | Out-Null
    $lines.Add(('Package: {0} ({1}) {2}' -f $displayName, $packageId, $version)) | Out-Null
    $lines.Add(('Package folder: {0}' -f $VersionDirectory)) | Out-Null
    $lines.Add(('What failed: {0}' -f $why)) | Out-Null
    if ($silentUi) {
        $lines.Add('Silent UI: yes. Re-package so install.ps1 uses verified silent switches. Inno /VERYSILENT /LANG=english, then re-test.') | Out-Null
    }
    $lines.Add('') | Out-Null
    $lines.Add('Upload this file together with sandbox-test-report.txt and the sandbox-logs folder.') | Out-Null
    $lines.Add('') | Out-Null
    if ($ReportText) {
        $lines.Add('--- Full report ---') | Out-Null
        $lines.Add($ReportText) | Out-Null
    }

    $failurePath = Get-AppGetterSandboxFailureLogPath -VersionDirectory $VersionDirectory
    Set-Content -LiteralPath $failurePath -Value ($lines -join "`r`n") -Encoding UTF8

    if ($CopiedLogsPath -and (Test-Path -LiteralPath $CopiedLogsPath)) {
        Copy-Item -LiteralPath $failurePath -Destination (Join-Path $CopiedLogsPath 'sandbox-failure.log') -Force -ErrorAction SilentlyContinue
        $reportPath = Get-AppGetterSandboxTestReportPath -VersionDirectory $VersionDirectory
        if (Test-Path -LiteralPath $reportPath) {
            Copy-Item -LiteralPath $reportPath -Destination (Join-Path $CopiedLogsPath 'sandbox-test-report.txt') -Force -ErrorAction SilentlyContinue
        }
    }

    return $failurePath
}

function Get-AppGetterSandboxStepScriptName {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('install', 'detect', 'uninstall')]
        [string]$Step
    )

    switch ($Step) {
        'install' { return 'install.ps1' }
        'detect' { return 'detection.ps1' }
        'uninstall' { return 'uninstall.ps1' }
    }
}

function Get-AppGetterSandboxStepCompletionFromText {
    param(
        [string]$Text,
        [Parameter(Mandatory = $true)]
        [ValidateSet('install', 'detect', 'uninstall')]
        [string]$Step,
        [string]$Source = 'log'
    )

    if ([string]::IsNullOrWhiteSpace($Text)) {
        return $null
    }

    $scriptName = Get-AppGetterSandboxStepScriptName -Step $Step
    $finished = $false
    $exitCode = $null
    $message = $null

    if ($Text -match ([regex]::Escape($scriptName) + ' finished with exit code (-?\d+)\.')) {
        $finished = $true
        $exitCode = [int]$Matches[1]
        $message = "$scriptName finished with exit code $exitCode."
    }

    if ($Text -match 'Windows PowerShell transcript end') {
        $finished = $true
        if (-not $message) {
            $message = "$scriptName finished (transcript ended)."
        }
    }

    switch ($Step) {
        'install' {
            if ($Text -match 'Install completed successfully \(hard reboot required - 1641\)') {
                $finished = $true
                if ($null -eq $exitCode) { $exitCode = 1641 }
            } elseif ($Text -match 'Install completed successfully \(reboot required - 3010\)') {
                $finished = $true
                if ($null -eq $exitCode) { $exitCode = 3010 }
            } elseif ($Text -match 'Install completed successfully') {
                $finished = $true
                if ($null -eq $exitCode) { $exitCode = 0 }
            } elseif ($Text -match 'Another installation is already in progress \(1618\)') {
                $finished = $true
                if ($null -eq $exitCode) { $exitCode = 1618 }
            } elseif ($Text -match 'Install failed with exit code (-?\d+)') {
                $finished = $true
                if ($null -eq $exitCode) { $exitCode = [int]$Matches[1] }
            }
        }
        'detect' {
            if ($Text -match 'not detected in registry, exiting with code 1') {
                $finished = $true
                if ($null -eq $exitCode) { $exitCode = 1 }
            } elseif ($Text -match 'is installed with version' -or $Text -match 'Detected version:') {
                $finished = $true
                if ($null -eq $exitCode) { $exitCode = 0 }
            }
        }
        'uninstall' {
            if ($Text -match 'Uninstall completed successfully') {
                $finished = $true
                if ($null -eq $exitCode) { $exitCode = 0 }
            } elseif ($Text -match 'Uninstall returned exit code:\s*(-?\d+)') {
                $finished = $true
                if ($null -eq $exitCode) { $exitCode = [int]$Matches[1] }
            } elseif ($Text -match 'Uninstall string not found') {
                $finished = $true
                if ($null -eq $exitCode) { $exitCode = 1 }
            }
        }
    }

    if ($Text -match ([regex]::Escape($scriptName) + ' was not silent') -or
        $Text -match ('STEP_DONE step=' + [regex]::Escape($Step)) -or
        $Text -match 'Waiting for confirmation in AppGetter') {
        $finished = $true
        if ($null -eq $exitCode -and $Text -match 'Exit code (\-?\d+)') {
            $exitCode = [int]$Matches[1]
        }
        if ($null -eq $exitCode -and $Text -match ('STEP_DONE step=' + [regex]::Escape($Step) + ' state=\S+ exitCode=(\-?\d+)')) {
            $exitCode = [int]$Matches[1]
        }
        if (-not $message) {
            $message = "$scriptName finished."
        }
    }

    # Packaged install.ps1 success beats a false "not silent" kill/exit code.
    if ($Step -eq 'install' -and $Text -match 'Install completed successfully') {
        $finished = $true
        if ($Text -match 'hard reboot required - 1641') {
            $exitCode = 1641
        } elseif ($Text -match 'reboot required - 3010') {
            $exitCode = 3010
        } else {
            $exitCode = 0
        }
        $message = "$scriptName finished with exit code $exitCode."
    }

    if (-not $finished) {
        return $null
    }
    if ($null -eq $exitCode) {
        $exitCode = 0
    }
    if (-not $message) {
        $message = "$scriptName finished with exit code $exitCode."
    }

    return [PSCustomObject]@{
        step = $Step
        state = 'completed'
        exitCode = $exitCode
        message = $message
        source = $Source
    }
}

function Get-AppGetterSandboxStepCompletionFromLog {
    param(
        [Parameter(Mandatory = $true)]
        [string]$HandshakeDirectory,
        [Parameter(Mandatory = $true)]
        [ValidateSet('install', 'detect', 'uninstall')]
        [string]$Step
    )

    $chunks = New-Object System.Collections.Generic.List[string]
    $guestLog = Join-Path $HandshakeDirectory 'guest.log'
    if (Test-Path -LiteralPath $guestLog) {
        $chunks.Add((Read-AppGetterSandboxText -Path $guestLog -Raw)) | Out-Null
    }

    $stepDir = Join-Path (Join-Path $HandshakeDirectory 'logs') $Step
    if (Test-Path -LiteralPath $stepDir) {
        Get-ChildItem -LiteralPath $stepDir -File -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -eq 'console-stdout.txt' -or $_.Name -eq 'console-stderr.txt' -or $_.Name -like '*.log' } |
            ForEach-Object {
                $chunks.Add((Read-AppGetterSandboxText -Path $_.FullName -Raw)) | Out-Null
            }
    }

    $text = ($chunks -join "`n")
    $source = if ($text -match 'Windows PowerShell transcript end' -or $text -match 'Install completed successfully') {
        'step-log'
    } else {
        'guest.log'
    }

    return Get-AppGetterSandboxStepCompletionFromText -Text $text -Step $Step -Source $source
}

function Resolve-AppGetterSandboxStepStatus {
    param(
        [Parameter(Mandatory = $true)]
        [string]$HandshakeDirectory,
        [Parameter(Mandatory = $true)]
        [ValidateSet('install', 'detect', 'uninstall')]
        [string]$Step,
        [string]$LogText
    )

    $status = Get-AppGetterSandboxStatus -HandshakeDirectory $HandshakeDirectory
    if ($status) {
        $statusStep = [string]$status.step
        $state = [string]$status.state
        if ($statusStep -eq $Step -and ($state -eq 'completed' -or $state -eq 'failed')) {
            return $status
        }
    }

    $logStatus = Get-AppGetterSandboxStepCompletionFromLog -HandshakeDirectory $HandshakeDirectory -Step $Step
    if (-not $logStatus -and $LogText) {
        $logStatus = Get-AppGetterSandboxStepCompletionFromText -Text $LogText -Step $Step -Source 'dialog-log'
    }
    if ($logStatus) {
        return $logStatus
    }

    if ($status) {
        $statusStep = [string]$status.step
        $state = [string]$status.state
        if ($statusStep -eq $Step -and $state -eq 'running') {
            return $status
        }
    }

    return $null
}

function Stop-AppGetterSandboxSession {
    param(
        [Parameter(Mandatory = $true)]
        [string]$HandshakeDirectory,
        [switch]$Cleanup
    )

    if (Test-Path -LiteralPath $HandshakeDirectory) {
        Set-AppGetterSandboxCommand -HandshakeDirectory $HandshakeDirectory -Action shutdown
    }

    if ($Cleanup -and (Test-Path -LiteralPath $HandshakeDirectory)) {
        Start-Sleep -Milliseconds 400
        Remove-Item -LiteralPath $HandshakeDirectory -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Get-ConfirmationValue {
    param($Item, [string]$Name)

    if ($null -eq $Item) {
        return $null
    }

    if ($Item -is [hashtable]) {
        if ($Item.ContainsKey($Name)) {
            return $Item[$Name]
        }
        return $null
    }

    $property = $Item.PSObject.Properties[$Name]
    if ($property) {
        return $property.Value
    }
    return $null
}

function Test-AppGetterSandboxConfirmations {
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Confirmations
    )

    foreach ($step in @('install', 'detect', 'uninstall')) {
        if (-not $Confirmations.ContainsKey($step)) {
            return $false
        }
        if (-not [bool](Get-ConfirmationValue -Item $Confirmations[$step] -Name 'Confirmed')) {
            return $false
        }
    }

    if ([bool](Get-ConfirmationValue -Item $Confirmations['install'] -Name 'SilentUiDetected')) {
        return $false
    }

    return $true
}

function ConvertTo-SandboxStepRecord {
    param($Item)

    $confirmedAt = Get-ConfirmationValue -Item $Item -Name 'ConfirmedAt'
    if (-not $confirmedAt -and [bool](Get-ConfirmationValue -Item $Item -Name 'Confirmed')) {
        $confirmedAt = (Get-Date).ToUniversalTime().ToString('o')
    }

    return [ordered]@{
        confirmed         = [bool](Get-ConfirmationValue -Item $Item -Name 'Confirmed')
        exitCode          = (Get-ConfirmationValue -Item $Item -Name 'ExitCode')
        confirmedAt       = $confirmedAt
        message           = [string](Get-ConfirmationValue -Item $Item -Name 'Message')
        silentUiDetected  = [bool](Get-ConfirmationValue -Item $Item -Name 'SilentUiDetected')
    }
}

function Complete-AppGetterSandboxTest {
    <#
    .SYNOPSIS
        Writes validation.json when install, detect, and uninstall were all confirmed.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$VersionDirectory,
        [Parameter(Mandatory = $true)]
        [hashtable]$Confirmations
    )

    if (-not (Test-Path -LiteralPath $VersionDirectory)) {
        throw "Package folder was not found: $VersionDirectory"
    }

    $validated = Test-AppGetterSandboxConfirmations -Confirmations $Confirmations
    $validatedAt = if ($validated) { (Get-Date).ToUniversalTime().ToString('o') } else { $null }

    $info = Get-AppGetterSandboxPackageInfo -VersionDirectory $VersionDirectory
    $payload = [ordered]@{
        validated   = $validated
        method      = 'WindowsSandbox'
        validatedAt = $validatedAt
        packageId   = $info.PackageId
        displayName = $info.DisplayName
        version     = $info.Version
        steps       = [ordered]@{
            install   = ConvertTo-SandboxStepRecord -Item $Confirmations['install']
            detect    = ConvertTo-SandboxStepRecord -Item $Confirmations['detect']
            uninstall = ConvertTo-SandboxStepRecord -Item $Confirmations['uninstall']
        }
    }

    $validationPath = Join-Path $VersionDirectory 'validation.json'
    ($payload | ConvertTo-Json -Depth 8) | Set-Content -LiteralPath $validationPath -Encoding UTF8

    $appJsonPath = Join-Path $VersionDirectory 'app.json'
    if (Test-Path -LiteralPath $appJsonPath) {
        try {
            $app = Get-Content -LiteralPath $appJsonPath -Raw | ConvertFrom-Json
            $app | Add-Member -NotePropertyName sandboxValidated -NotePropertyValue $validated -Force
            $app | Add-Member -NotePropertyName sandboxValidatedAt -NotePropertyValue $validatedAt -Force
            $app | Add-Member -NotePropertyName sandboxValidationMethod -NotePropertyValue 'WindowsSandbox' -Force
            $app | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $appJsonPath -Encoding UTF8
        } catch {
            Write-Warning "Could not update app.json with sandbox validation: $_"
        }
    }

    return Get-AppGetterPackageValidation -VersionDirectory $VersionDirectory
}

function Get-AppGetterPackageValidation {
    param(
        [Parameter(Mandatory = $true)]
        [string]$VersionDirectory
    )

    $path = Join-Path $VersionDirectory 'validation.json'
    if (-not (Test-Path -LiteralPath $path)) {
        return [PSCustomObject]@{
            Validated    = $false
            Method       = $null
            ValidatedAt  = $null
            PackageId    = $null
            Version      = $null
            Steps        = $null
            Path         = $path
            Exists       = $false
        }
    }

    try {
        $data = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
        return [PSCustomObject]@{
            Validated    = [bool]$data.validated
            Method       = [string]$data.method
            ValidatedAt  = $data.validatedAt
            PackageId    = [string]$data.packageId
            Version      = [string]$data.version
            Steps        = $data.steps
            Path         = $path
            Exists       = $true
        }
    } catch {
        return [PSCustomObject]@{
            Validated    = $false
            Method       = $null
            ValidatedAt  = $null
            PackageId    = $null
            Version      = $null
            Steps        = $null
            Path         = $path
            Exists       = $true
        }
    }
}

function Test-AppGetterAcceptedInstallExitCode {
    param([object]$ExitCode)

    if ($null -eq $ExitCode) {
        return $false
    }

    try {
        $code = [int]$ExitCode
    } catch {
        return $false
    }

    return ($code -eq 0 -or $code -eq 3010 -or $code -eq 1641)
}

function New-AppGetterSandboxTrialGuestScript {
    <#
    .SYNOPSIS
        Guest coordinator for silent-switch discovery trials (single install command + evidence).
    #>
    return @'
$ErrorActionPreference = 'Continue'
$handshakeRoot = 'C:\AppGetterSandbox'
$mappedPackageRoot = 'C:\AppGetterPackage'
$packageRoot = 'C:\AppGetterTrial'
$ProgressPreference = 'SilentlyContinue'

function Write-GuestLog {
    param([string]$Message)
    $line = '{0} {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Message
    Write-Host $line
    try {
        Add-Content -LiteralPath (Join-Path $handshakeRoot 'guest.log') -Value $line -Encoding UTF8 -ErrorAction Stop
    } catch { }
}

function Write-GuestJson {
    param([string]$Path, $Object)
    $directory = Split-Path -Path $Path -Parent
    if ($directory -and -not (Test-Path -LiteralPath $directory)) {
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
    }
    $json = $Object | ConvertTo-Json -Depth 8
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($json)
    $tmp = "$Path.tmp"
    [System.IO.File]::WriteAllBytes($tmp, $bytes)
    Move-Item -LiteralPath $tmp -Destination $Path -Force
}

function Write-Heartbeat {
    Write-GuestJson -Path (Join-Path $handshakeRoot 'heartbeat.json') -Object @{
        alive = $true
        updatedAt = (Get-Date).ToUniversalTime().ToString('o')
        computerName = $env:COMPUTERNAME
    }
}

function Write-Status {
    param(
        [string]$Step,
        [string]$State,
        [object]$ExitCode = $null,
        [string]$Message = '',
        [bool]$SilentUiDetected = $false,
        [object[]]$SilentUiWindows = @()
    )

    $payload = [ordered]@{
        step = $Step
        state = $State
        exitCode = $ExitCode
        message = $Message
        updatedAt = (Get-Date).ToUniversalTime().ToString('o')
        computerName = $env:COMPUTERNAME
        silentUiDetected = [bool]$SilentUiDetected
        silentUiWindows = @($SilentUiWindows)
    }
    Write-GuestJson -Path (Join-Path $handshakeRoot 'status.json') -Object $payload
    try {
        Add-Content -LiteralPath (Join-Path $handshakeRoot 'status.ndjson') -Value (($payload | ConvertTo-Json -Compress -Depth 6)) -Encoding UTF8
    } catch { }
}

$uiIgnoreProcessNames = @(
    'powershell', 'powershell_ise', 'pwsh', 'cmd', 'conhost', 'explorer',
    'WindowsSandbox', 'WindowsSandboxClient', 'msedge', 'SearchHost', 'SearchUI',
    'StartMenuExperienceHost', 'ShellExperienceHost', 'TextInputHost',
    'ApplicationFrameHost', 'SystemSettings', 'dwm', 'sihost', 'ctfmon',
    'RuntimeBroker', 'LockApp', 'WWAHost'
)

function Test-IgnoredUiProcess {
    param([string]$ProcessName)
    foreach ($name in $uiIgnoreProcessNames) {
        if ([string]::Equals($name, $ProcessName, [StringComparison]::OrdinalIgnoreCase)) {
            return $true
        }
    }
    return $false
}

function Test-IgnoredInstallerSplash {
    param([string]$ProcessName, [string]$Title)
    $t = ([string]$Title).Trim()
    if ($t -eq '(visible window, no title)') { $t = '' }
    if ($ProcessName -match '\.tmp$') {
        if ([string]::IsNullOrWhiteSpace($t) -or $t -eq 'Setup' -or $t -eq 'Installing') {
            return $true
        }
    }
    return $false
}

function Get-InteractiveWindowSnapshot {
    $snapshot = @{}
    Get-Process -ErrorAction SilentlyContinue | ForEach-Object {
        if ($_.MainWindowHandle -ne 0 -and $_.MainWindowHandle -ne [IntPtr]::Zero) {
            $snapshot[$_.Id] = $true
        }
    }
    return $snapshot
}

function Save-DesktopScreenshot {
    param([string]$Path)
    try {
        Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
        Add-Type -AssemblyName System.Drawing -ErrorAction Stop
        $bounds = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
        $bmp = New-Object System.Drawing.Bitmap $bounds.Width, $bounds.Height
        $graphics = [System.Drawing.Graphics]::FromImage($bmp)
        $graphics.CopyFromScreen($bounds.Location, [System.Drawing.Point]::Empty, $bounds.Size)
        $directory = Split-Path -Path $Path -Parent
        if ($directory -and -not (Test-Path -LiteralPath $directory)) {
            New-Item -ItemType Directory -Path $directory -Force | Out-Null
        }
        $bmp.Save($Path, [System.Drawing.Imaging.ImageFormat]::Png)
        $graphics.Dispose()
        $bmp.Dispose()
        return $true
    } catch {
        Write-GuestLog "Could not capture screenshot: $_"
        return $false
    }
}

function Stop-ProcessTree {
    param([int]$Id)
    if ($Id -le 0) { return }
    try { & taskkill.exe /PID $Id /T /F | Out-Null } catch { }
}

function Get-UninstallRegistrySnapshot {
    $entries = @{}
    $roots = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall',
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall'
    )
    foreach ($root in $roots) {
        if (-not (Test-Path -LiteralPath $root)) { continue }
        Get-ChildItem -LiteralPath $root -ErrorAction SilentlyContinue | ForEach-Object {
            try {
                $props = Get-ItemProperty -LiteralPath $_.PSPath -ErrorAction Stop
                $displayName = [string]$props.DisplayName
                if ([string]::IsNullOrWhiteSpace($displayName)) { return }
                $key = ($_.PSPath + '|' + $displayName).ToLowerInvariant()
                $entries[$key] = [PSCustomObject]@{
                    DisplayName = $displayName
                    DisplayVersion = [string]$props.DisplayVersion
                    Publisher = [string]$props.Publisher
                    UninstallString = [string]$props.UninstallString
                    Path = $_.PSPath
                }
            } catch { }
        }
    }
    return $entries
}

function Read-TrialRequest {
    foreach ($candidate in @(
            (Join-Path $packageRoot 'trial-request.json'),
            (Join-Path $mappedPackageRoot 'trial-request.json'),
            (Join-Path $handshakeRoot 'trial-request.json')
        )) {
        if (Test-Path -LiteralPath $candidate) {
            try {
                return (Get-Content -LiteralPath $candidate -Raw -ErrorAction Stop | ConvertFrom-Json)
            } catch { }
        }
    }
    return $null
}

if (-not (Test-Path -LiteralPath $handshakeRoot)) {
    New-Item -ItemType Directory -Path $handshakeRoot -Force | Out-Null
}
if (-not (Test-Path -LiteralPath $packageRoot)) {
    New-Item -ItemType Directory -Path $packageRoot -Force | Out-Null
}

$deadline = (Get-Date).AddMinutes(2)
while (-not (Test-Path -LiteralPath (Join-Path $mappedPackageRoot 'trial-request.json'))) {
    if ((Get-Date) -gt $deadline) {
        Write-GuestLog "Mapped trial package not available: $mappedPackageRoot"
        Write-GuestJson -Path (Join-Path $handshakeRoot 'trial-result.json') -Object @{
            verified = $false
            exitCode = 1
            silentUiDetected = $false
            message = 'Mapped trial package was not available inside Windows Sandbox.'
            installEvidence = @()
        }
        return
    }
    Start-Sleep -Seconds 1
}

Copy-Item -Path (Join-Path $mappedPackageRoot '*') -Destination $packageRoot -Recurse -Force
Write-GuestLog "Copied trial files to $packageRoot"
Write-Heartbeat
Write-Status -Step 'trial' -State 'running' -Message 'Starting silent-switch discovery trial.'

$request = Read-TrialRequest
if (-not $request -or [string]::IsNullOrWhiteSpace([string]$request.command)) {
    Write-GuestJson -Path (Join-Path $handshakeRoot 'trial-result.json') -Object @{
        verified = $false
        exitCode = 1
        silentUiDetected = $false
        message = 'trial-request.json was missing or did not include a command.'
        installEvidence = @()
    }
    Write-Status -Step 'trial' -State 'failed' -ExitCode 1 -Message 'Missing trial command.'
    return
}

$command = [string]$request.command
$appName = [string]$request.appName
$stepLogDir = Join-Path $handshakeRoot 'logs\trial'
New-Item -ItemType Directory -Path $stepLogDir -Force | Out-Null

$before = Get-UninstallRegistrySnapshot
$windowBaseline = Get-InteractiveWindowSnapshot
$uiEvents = New-Object System.Collections.Generic.List[object]
$killedForUi = $false
$timedOut = $false
$uiDetectedAt = $null
$ignoredSplashIds = @{}
$localStepDir = Join-Path $env:TEMP 'AppGetterTrial'
if (Test-Path -LiteralPath $localStepDir) {
    Remove-Item -LiteralPath $localStepDir -Recurse -Force -ErrorAction SilentlyContinue
}
New-Item -ItemType Directory -Path $localStepDir -Force | Out-Null
$stdoutPath = Join-Path $localStepDir 'console-stdout.txt'
$stderrPath = Join-Path $localStepDir 'console-stderr.txt'

Set-Location -Path $packageRoot
Write-GuestLog "Executing trial command: $command"
$process = Start-Process -FilePath 'cmd.exe' -ArgumentList @('/c', $command) -PassThru -NoNewWindow `
    -RedirectStandardOutput $stdoutPath -RedirectStandardError $stderrPath
$deadline = (Get-Date).AddMinutes(12)

while ($process) {
    try { $process.Refresh() } catch { }
    if ($process.HasExited) { break }
    Write-Heartbeat
    if ((Get-Date) -gt $deadline) {
        $timedOut = $true
        Write-GuestLog 'Timed out waiting for trial command after 12 minutes.'
        Stop-ProcessTree -Id $process.Id
        break
    }

    Get-Process -ErrorAction SilentlyContinue | ForEach-Object {
        if ($_.MainWindowHandle -eq 0 -or $_.MainWindowHandle -eq [IntPtr]::Zero) { return }
        if ($windowBaseline.ContainsKey($_.Id)) { return }
        if (Test-IgnoredUiProcess -ProcessName $_.ProcessName) { return }
        $title = [string]$_.MainWindowTitle
        if ([string]::IsNullOrWhiteSpace($title)) { $title = '(visible window, no title)' }
        if (Test-IgnoredInstallerSplash -ProcessName $_.ProcessName -Title $title) {
            if (-not $ignoredSplashIds.ContainsKey($_.Id)) {
                $ignoredSplashIds[$_.Id] = $true
                Write-GuestLog ("Ignoring Inno extractor window '{0}' ({1})." -f $title, $_.ProcessName)
            }
            return
        }
        foreach ($existing in $uiEvents) {
            if ($existing.processId -eq $_.Id) { return }
        }
        $uiEvents.Add(@{
            processName = $_.ProcessName
            windowTitle = $title
            processId = $_.Id
            detectedAt = (Get-Date).ToUniversalTime().ToString('o')
        }) | Out-Null
        if (-not $uiDetectedAt) {
            $uiDetectedAt = Get-Date
            $shotPath = Join-Path $stepLogDir 'ui-detected.png'
            if (Save-DesktopScreenshot -Path $shotPath) {
                Write-GuestLog "Saved UI screenshot to $shotPath"
            }
        }
        Write-GuestLog ("WARNING: interactive window during trial: '{0}' ({1})." -f $title, $_.ProcessName)
        Write-Status -Step 'trial' -State 'running' -Message ("NOT SILENT: '{0}' ({1})" -f $title, $_.ProcessName) `
            -SilentUiDetected $true -SilentUiWindows @($uiEvents)
    }

    if ($uiDetectedAt -and -not $killedForUi) {
        if (((Get-Date) - $uiDetectedAt).TotalSeconds -ge 12) {
            $killedForUi = $true
            Write-GuestLog 'Stopping trial because an interactive window blocked a silent install.'
            Stop-ProcessTree -Id $process.Id
            break
        }
    }
    Start-Sleep -Seconds 1
}

if ($process -and -not $process.HasExited) {
    try { $process.WaitForExit(20000) | Out-Null } catch { }
    try { $process.Refresh() } catch { }
}
if ($process -and -not $process.HasExited) {
    Stop-ProcessTree -Id $process.Id
}

$exitCode = 1603
if ($killedForUi -or $timedOut) {
    $exitCode = 1603
} elseif ($process -and $null -ne $process.ExitCode) {
    $exitCode = [int]$process.ExitCode
}

foreach ($sourcePath in @($stdoutPath, $stderrPath)) {
    if ($sourcePath -and (Test-Path -LiteralPath $sourcePath)) {
        Copy-Item -LiteralPath $sourcePath -Destination (Join-Path $stepLogDir ([System.IO.Path]::GetFileName($sourcePath))) -Force -ErrorAction SilentlyContinue
    }
}

Start-Sleep -Seconds 2
$after = Get-UninstallRegistrySnapshot
$installEvidence = New-Object System.Collections.Generic.List[object]
foreach ($key in $after.Keys) {
    if ($before.ContainsKey($key)) { continue }
    $entry = $after[$key]
    $nameMatch = $true
    if (-not [string]::IsNullOrWhiteSpace($appName)) {
        $nameMatch = $entry.DisplayName -like ("*{0}*" -f $appName) -or $appName -like ("*{0}*" -f $entry.DisplayName)
    }
    if ($nameMatch -or [string]::IsNullOrWhiteSpace($appName)) {
        $installEvidence.Add($entry) | Out-Null
    }
}

# If AppName filter excluded everything, keep all new ARP entries as weak evidence.
if ($installEvidence.Count -eq 0) {
    foreach ($key in $after.Keys) {
        if (-not $before.ContainsKey($key)) {
            $installEvidence.Add($after[$key]) | Out-Null
        }
    }
}

$silentUi = ($uiEvents.Count -gt 0)
$acceptedExit = ($exitCode -eq 0 -or $exitCode -eq 3010 -or $exitCode -eq 1641)
$verified = (-not $silentUi) -and $acceptedExit -and ($installEvidence.Count -gt 0)

$message = "Trial finished with exit code $exitCode."
if ($silentUi) {
    $titles = @($uiEvents | ForEach-Object { $_.windowTitle }) -join '; '
    $message = "Trial was not silent. Interactive window(s): $titles. Exit code $exitCode."
} elseif (-not $acceptedExit) {
    $message = "Trial command failed with exit code $exitCode."
} elseif ($installEvidence.Count -eq 0) {
    $message = "Trial exit code $exitCode was accepted, but no new uninstall registry evidence was found."
} else {
    $message = "Trial verified silent install. Exit code $exitCode. New ARP entries: $($installEvidence.Count)."
}

$result = [ordered]@{
    verified = [bool]$verified
    exitCode = [int]$exitCode
    silentUiDetected = [bool]$silentUi
    silentUiWindows = @($uiEvents)
    message = $message
    command = $command
    appName = $appName
    installEvidence = @($installEvidence)
    timedOut = [bool]$timedOut
    killedForUi = [bool]$killedForUi
    finishedAt = (Get-Date).ToUniversalTime().ToString('o')
}
Write-GuestJson -Path (Join-Path $handshakeRoot 'trial-result.json') -Object $result
Write-GuestJson -Path (Join-Path $stepLogDir 'trial-result.json') -Object $result
Write-GuestLog $message
Write-Status -Step 'trial' -State $(if ($verified) { 'completed' } else { 'failed' }) `
    -ExitCode $exitCode -Message $message -SilentUiDetected $silentUi -SilentUiWindows @($uiEvents)

Start-Sleep -Seconds 2
try { Stop-Computer -Force } catch { }
'@
}

function New-AppGetterSandboxTrialPackage {
    param(
        [Parameter(Mandatory = $true)]
        [string]$InstallerPath,
        [Parameter(Mandatory = $true)]
        [string]$Command,
        [string]$AppName = '',
        [string]$DestinationPath
    )

    if (-not (Test-Path -LiteralPath $InstallerPath -PathType Leaf)) {
        throw "Installer file not found: $InstallerPath"
    }

    if (-not $DestinationPath) {
        $DestinationPath = Join-Path ([System.IO.Path]::GetTempPath()) ("AppGetterTrialPkg-{0}" -f ([Guid]::NewGuid().ToString('N')))
    }

    if (-not (Test-Path -LiteralPath $DestinationPath)) {
        New-Item -ItemType Directory -Path $DestinationPath -Force | Out-Null
    }

    $installerName = [System.IO.Path]::GetFileName($InstallerPath)
    $destInstaller = Join-Path $DestinationPath $installerName
    if ((Resolve-Path -LiteralPath $InstallerPath).Path -ne (Join-Path $DestinationPath $installerName)) {
        Copy-Item -LiteralPath $InstallerPath -Destination $destInstaller -Force
    }

    $request = [ordered]@{
        command = $Command
        appName = $AppName
        installerFileName = $installerName
        createdAt = (Get-Date).ToUniversalTime().ToString('o')
    }
    Write-AppGetterSandboxJson -Path (Join-Path $DestinationPath 'trial-request.json') -Object $request

    return [PSCustomObject]@{
        PackageDirectory = $DestinationPath
        InstallerPath = $destInstaller
        RequestPath = (Join-Path $DestinationPath 'trial-request.json')
        Command = $Command
        AppName = $AppName
    }
}

function Start-AppGetterSandboxTrialSession {
    <#
    .SYNOPSIS
        Starts a Windows Sandbox session that runs one silent-switch discovery trial.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$InstallerPath,
        [Parameter(Mandatory = $true)]
        [string]$Command,
        [string]$AppName = '',
        [switch]$SkipLaunch,
        [int]$MemoryInMB = 4096
    )

    $sessionId = [Guid]::NewGuid().ToString('N')
    $handshake = Join-Path ([System.IO.Path]::GetTempPath()) "AppGetterTrialSandbox-$sessionId"
    New-Item -ItemType Directory -Path $handshake -Force | Out-Null

    $package = New-AppGetterSandboxTrialPackage -InstallerPath $InstallerPath -Command $Command -AppName $AppName

    $guestScriptPath = Join-Path $handshake 'Start-AppGetterSandboxTrialGuest.ps1'
    Set-Content -LiteralPath $guestScriptPath -Value (New-AppGetterSandboxTrialGuestScript) -Encoding UTF8

    Write-AppGetterSandboxJson -Path (Join-Path $handshake 'trial-request.json') -Object @{
        command = $Command
        appName = $AppName
        installerFileName = [System.IO.Path]::GetFileName($InstallerPath)
        createdAt = (Get-Date).ToUniversalTime().ToString('o')
    }

    Write-AppGetterSandboxJson -Path (Join-Path $handshake 'status.json') -Object @{
        step = 'trial'
        state = 'waiting'
        exitCode = $null
        message = 'Waiting for Windows Sandbox trial to start.'
        updatedAt = (Get-Date).ToUniversalTime().ToString('o')
    }

    $wsbPath = Join-Path $handshake 'AppGetterTrialSandbox.wsb'
    $wsb = New-AppGetterSandboxWsbContent `
        -HostPackagePath $package.PackageDirectory `
        -HostHandshakePath $handshake `
        -MemoryInMB $MemoryInMB `
        -GuestScriptFileName 'Start-AppGetterSandboxTrialGuest.ps1'
    Set-Content -LiteralPath $wsbPath -Value $wsb -Encoding UTF8

    $launched = $false
    $processId = $null
    if (-not $SkipLaunch) {
        $sandbox = Test-AppGetterWindowsSandbox
        if (-not $sandbox.Enabled) {
            throw $sandbox.Reason
        }

        $process = Start-Process -FilePath $sandbox.ExecutablePath -ArgumentList @("`"$wsbPath`"") -PassThru
        $launched = $true
        if ($process) {
            $processId = $process.Id
        }
    }

    return [PSCustomObject]@{
        SessionId = $sessionId
        HandshakeDirectory = $handshake
        PackageDirectory = $package.PackageDirectory
        WsbPath = $wsbPath
        GuestScriptPath = $guestScriptPath
        ResultPath = (Join-Path $handshake 'trial-result.json')
        StatusPath = (Join-Path $handshake 'status.json')
        HeartbeatPath = (Join-Path $handshake 'heartbeat.json')
        GuestLogPath = (Join-Path $handshake 'guest.log')
        Command = $Command
        AppName = $AppName
        InstallerPath = $InstallerPath
        Launched = $launched
        ProcessId = $processId
        StartedAt = Get-Date
    }
}

function Get-AppGetterSandboxTrialResult {
    param(
        [Parameter(Mandatory = $true)]
        [string]$HandshakeDirectory
    )

    $path = Join-Path $HandshakeDirectory 'trial-result.json'
    $obj = Read-AppGetterSandboxJson -Path $path
    if (-not $obj) {
        return $null
    }

    return [PSCustomObject]@{
        Verified = [bool]$obj.verified
        ExitCode = $obj.exitCode
        SilentUiDetected = [bool]$obj.silentUiDetected
        SilentUiWindows = @($obj.silentUiWindows)
        Message = [string]$obj.message
        Command = [string]$obj.command
        AppName = [string]$obj.appName
        InstallEvidence = @($obj.installEvidence)
        TimedOut = [bool]$obj.timedOut
        KilledForUi = [bool]$obj.killedForUi
        FinishedAt = $obj.finishedAt
        Path = $path
        Raw = $obj
    }
}

function Wait-AppGetterSandboxTrialResult {
    param(
        [Parameter(Mandatory = $true)]
        [string]$HandshakeDirectory,
        [int]$TimeoutSeconds = 900,
        [int]$PollMilliseconds = 1000
    )

    $deadline = (Get-Date).AddSeconds([Math]::Max(30, $TimeoutSeconds))
    while ((Get-Date) -lt $deadline) {
        $result = Get-AppGetterSandboxTrialResult -HandshakeDirectory $HandshakeDirectory
        if ($result) {
            return $result
        }
        Start-Sleep -Milliseconds $PollMilliseconds
    }

    return $null
}

function Stop-AppGetterSandboxTrialSession {
    param(
        [Parameter(Mandatory = $true)]
        $Session,
        [switch]$Cleanup
    )

    if ($Session.HandshakeDirectory -and (Test-Path -LiteralPath $Session.HandshakeDirectory)) {
        # Trial guest self-shuts down; best-effort cleanup only.
        if ($Cleanup) {
            Start-Sleep -Milliseconds 500
            Remove-Item -LiteralPath $Session.HandshakeDirectory -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    if ($Cleanup -and $Session.PackageDirectory -and (Test-Path -LiteralPath $Session.PackageDirectory)) {
        Remove-Item -LiteralPath $Session.PackageDirectory -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function ConvertTo-AppGetterInstallerVerification {
    param(
        $TrialResult,
        [string]$FallbackMessage = 'Sandbox trial did not produce a result.'
    )

    if (-not $TrialResult) {
        return [PSCustomObject]@{
            Verified = $false
            ExitCode = $null
            Message = $FallbackMessage
            Observable = $null
            SilentUiDetected = $false
            InstallEvidence = @()
            Method = 'WindowsSandbox'
        }
    }

    $evidenceNames = @($TrialResult.InstallEvidence | ForEach-Object {
            if ($_.DisplayName) { [string]$_.DisplayName } elseif ($_.displayName) { [string]$_.displayName } else { $null }
        } | Where-Object { $_ })

    return [PSCustomObject]@{
        Verified = [bool]$TrialResult.Verified
        ExitCode = $TrialResult.ExitCode
        Message = [string]$TrialResult.Message
        Observable = [PSCustomObject]@{
            SilentUiDetected = [bool]$TrialResult.SilentUiDetected
            InstallEvidenceCount = @($TrialResult.InstallEvidence).Count
            InstallEvidenceNames = $evidenceNames
            TimedOut = [bool]$TrialResult.TimedOut
            KilledForUi = [bool]$TrialResult.KilledForUi
        }
        SilentUiDetected = [bool]$TrialResult.SilentUiDetected
        InstallEvidence = @($TrialResult.InstallEvidence)
        Method = 'WindowsSandbox'
    }
}

function Test-InstallerCommandInSandbox {
    <#
    .SYNOPSIS
        Runs one silent-install candidate command inside Windows Sandbox and returns verification evidence.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$InstallerPath,
        [Parameter(Mandatory = $true)]
        [string]$Command,
        [string]$AppName = '',
        [int]$TimeoutSeconds = 900,
        [switch]$SkipLaunch
    )

    # Allow SkipLaunch session preparation on any OS so unit tests can validate WSB/guest contracts.
    if (([System.Environment]::OSVersion.Platform -ne 'Win32NT') -and -not $SkipLaunch) {
        return ConvertTo-AppGetterInstallerVerification -TrialResult $null `
            -FallbackMessage 'Sandbox silent-switch trials require Windows and were skipped on this host.'
    }

    if (([System.Environment]::OSVersion.Platform -eq 'Win32NT') -and -not $SkipLaunch) {
        $sandbox = Test-AppGetterWindowsSandbox
        if (-not $sandbox.Enabled) {
            return ConvertTo-AppGetterInstallerVerification -TrialResult $null `
                -FallbackMessage ("Windows Sandbox is not available for silent-switch verification. {0}" -f $sandbox.Reason)
        }
    }

    $session = $null
    try {
        $session = Start-AppGetterSandboxTrialSession `
            -InstallerPath $InstallerPath `
            -Command $Command `
            -AppName $AppName `
            -SkipLaunch:$SkipLaunch

        if ($SkipLaunch) {
            return [PSCustomObject]@{
                Verified = $false
                ExitCode = $null
                Message = 'Sandbox trial session prepared but not launched (SkipLaunch).'
                Observable = [PSCustomObject]@{
                    SessionId = $session.SessionId
                    HandshakeDirectory = $session.HandshakeDirectory
                    PackageDirectory = $session.PackageDirectory
                    WsbPath = $session.WsbPath
                }
                SilentUiDetected = $false
                InstallEvidence = @()
                Method = 'WindowsSandbox'
                Session = $session
            }
        }

        Write-AppGetterLog -Message "Sandbox trial started for command: $Command" -Level Info
        $trial = Wait-AppGetterSandboxTrialResult -HandshakeDirectory $session.HandshakeDirectory -TimeoutSeconds $TimeoutSeconds
        $verification = ConvertTo-AppGetterInstallerVerification -TrialResult $trial `
            -FallbackMessage "Sandbox trial timed out after $TimeoutSeconds seconds without writing trial-result.json."
        $verification | Add-Member -NotePropertyName Session -NotePropertyValue $session -Force
        return $verification
    } catch {
        return ConvertTo-AppGetterInstallerVerification -TrialResult $null `
            -FallbackMessage ("Sandbox trial failed to start: {0}" -f $_.Exception.Message)
    } finally {
        if ($session -and -not $SkipLaunch) {
            Stop-AppGetterSandboxTrialSession -Session $session -Cleanup
        }
    }
}
