<#
.SYNOPSIS
    Double-click / ps2exe entry point for the AppGetter GUI.
.DESCRIPTION
    Resolves the AppGetter install folder whether running as a .ps1 or as a
    compiled AppGetter.exe (ps2exe), then launches Gui\Start-AppGetterGui.ps1.
    Designed to run without an elevated PowerShell session.

    When compiled with ps2exe, the GUI is started in a separate Windows
    PowerShell 5.1 process. Loading the module inside the ps2exe host breaks
    parsing of regex literals that use {n,} quantifiers.

    The child process is started with -EncodedCommand so paths that contain
    spaces are not mangled by Start-Process -ArgumentList quoting.
.NOTES
    Build with: .\Build\Build-AppGetterExe.ps1
    Startup log: %TEMP%\AppGetter-launch.log
#>

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

# Capture at script scope -- $MyInvocation inside functions refers to the function.
$scriptInvocation = $MyInvocation

function Get-AppGetterAppRoot {
    param($Invocation)

    # ExternalScript = running as .ps1; otherwise compiled by ps2exe.
    if ($Invocation.MyCommand.CommandType -eq 'ExternalScript') {
        $candidate = Split-Path -Parent -Path $Invocation.MyCommand.Definition
        if ($candidate) {
            return (Resolve-Path -LiteralPath $candidate).Path
        }
    }

    # ps2exe sets $PSScriptRoot to the directory containing the .exe in current builds.
    if ($PSScriptRoot) {
        return (Resolve-Path -LiteralPath $PSScriptRoot).Path
    }

    $commandLineExe = [Environment]::GetCommandLineArgs()[0]
    if ($commandLineExe) {
        $fromArgs = Split-Path -Parent -Path $commandLineExe
        if ($fromArgs -and (Test-Path -LiteralPath $fromArgs)) {
            return (Resolve-Path -LiteralPath $fromArgs).Path
        }
    }

    try {
        $processPath = [System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
        if ($processPath) {
            $fromProcess = Split-Path -Parent -Path $processPath
            if ($fromProcess -and (Test-Path -LiteralPath $fromProcess)) {
                return (Resolve-Path -LiteralPath $fromProcess).Path
            }
        }
    } catch {
        # Ignore and fall through.
    }

    return (Resolve-Path -LiteralPath (Get-Location).Path).Path
}

function Show-AppGetterStartupError {
    param([string]$Message)

    try {
        Add-Type -AssemblyName PresentationFramework -ErrorAction Stop
        [System.Windows.MessageBox]::Show(
            $Message,
            'AppGetter',
            [System.Windows.MessageBoxButton]::OK,
            [System.Windows.MessageBoxImage]::Error
        ) | Out-Null
    } catch {
        Write-Error $Message
    }
}

function Write-AppGetterLaunchLog {
    param(
        [string]$LogPath,
        [string]$Message
    )

    $logDirectory = Split-Path -Parent -Path $LogPath
    if ($logDirectory -and -not (Test-Path -LiteralPath $logDirectory)) {
        New-Item -ItemType Directory -Path $logDirectory -Force | Out-Null
    }

    $line = '{0:yyyy-MM-dd HH:mm:ss.fff}  {1}' -f (Get-Date), $Message
    Add-Content -LiteralPath $LogPath -Value $line -Encoding UTF8
}

function Start-AppGetterGuiProcess {
    param(
        [Parameter(Mandatory = $true)]
        [string]$AppRoot,

        [Parameter(Mandatory = $true)]
        [string]$GuiScript,

        [Parameter(Mandatory = $true)]
        [string]$LogPath
    )

    $windowsPowerShell = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    if (-not (Test-Path -LiteralPath $windowsPowerShell)) {
        throw "Windows PowerShell not found at $windowsPowerShell"
    }

    # Escape single quotes for embedding inside a single-quoted PowerShell literal.
    $appRootLiteral = $AppRoot.Replace("'", "''")
    $guiScriptLiteral = $GuiScript.Replace("'", "''")
    $logPathLiteral = $LogPath.Replace("'", "''")

    # Child script: run GUI; on failure write log + MessageBox (console may be hidden).
    $childScript = @"
`$ErrorActionPreference = 'Stop'
`$appGetterLog = '$logPathLiteral'
function Write-AppGetterChildLog([string]`$Message) {
    Add-Content -LiteralPath `$appGetterLog -Value (('{0:yyyy-MM-dd HH:mm:ss.fff}  CHILD  {1}' -f (Get-Date), `$Message)) -Encoding UTF8
}
try {
    Write-AppGetterChildLog 'Starting GUI'
    Write-AppGetterChildLog 'AppRoot=$appRootLiteral'
    Write-AppGetterChildLog 'GuiScript=$guiScriptLiteral'
    Set-Location -LiteralPath '$appRootLiteral'
    & '$guiScriptLiteral'
    Write-AppGetterChildLog 'GUI exited normally'
} catch {
    Write-AppGetterChildLog ('ERROR: ' + `$_.Exception.Message)
    Write-AppGetterChildLog (`$_.ScriptStackTrace)
    try {
        Add-Type -AssemblyName PresentationFramework -ErrorAction Stop
        [System.Windows.MessageBox]::Show(
            ('AppGetter GUI failed to start:`n`n' + `$_.Exception.Message + '`n`nSee log:`n' + `$appGetterLog),
            'AppGetter',
            [System.Windows.MessageBoxButton]::OK,
            [System.Windows.MessageBoxImage]::Error
        ) | Out-Null
    } catch { }
    exit 1
}
"@

    # -EncodedCommand avoids Start-Process ArgumentList quoting bugs with spaces in paths.
    $encodedCommand = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($childScript))

    Write-AppGetterLaunchLog -LogPath $LogPath -Message "powershell=$windowsPowerShell"
    Write-AppGetterLaunchLog -LogPath $LogPath -Message "appRoot=$AppRoot"
    Write-AppGetterLaunchLog -LogPath $LogPath -Message "guiScript=$GuiScript"

    $attempts = @(
        @{
            Name           = 'hidden-encoded'
            Arguments      = "-NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -EncodedCommand $encodedCommand"
            CreateNoWindow = $true
            WindowStyle    = [System.Diagnostics.ProcessWindowStyle]::Hidden
        },
        @{
            Name           = 'normal-encoded-fallback'
            Arguments      = "-NoProfile -ExecutionPolicy Bypass -STA -EncodedCommand $encodedCommand"
            CreateNoWindow = $false
            WindowStyle    = [System.Diagnostics.ProcessWindowStyle]::Normal
        }
    )

    foreach ($attempt in $attempts) {
        Write-AppGetterLaunchLog -LogPath $LogPath -Message ("Starting child attempt={0}" -f $attempt.Name)

        $startInfo = New-Object System.Diagnostics.ProcessStartInfo
        $startInfo.FileName = $windowsPowerShell
        $startInfo.Arguments = $attempt.Arguments
        $startInfo.WorkingDirectory = $AppRoot
        $startInfo.UseShellExecute = $false
        $startInfo.CreateNoWindow = [bool]$attempt.CreateNoWindow
        $startInfo.WindowStyle = $attempt.WindowStyle

        $process = New-Object System.Diagnostics.Process
        $process.StartInfo = $startInfo
        if (-not $process.Start()) {
            Write-AppGetterLaunchLog -LogPath $LogPath -Message ("childStartFailed attempt={0}" -f $attempt.Name)
            continue
        }

        Write-AppGetterLaunchLog -LogPath $LogPath -Message ("childPid={0} attempt={1}" -f $process.Id, $attempt.Name)

        # If the child dies immediately, try one fallback before giving up.
        if ($process.WaitForExit(4000)) {
            $exitCode = $process.ExitCode
            Write-AppGetterLaunchLog -LogPath $LogPath -Message ("childExitedEarly exitCode={0} attempt={1}" -f $exitCode, $attempt.Name)
            continue
        }

        Write-AppGetterLaunchLog -LogPath $LogPath -Message ("childRunning attempt={0} -- launch looks healthy" -f $attempt.Name)
        return $process
    }

    $tail = ''
    if (Test-Path -LiteralPath $LogPath) {
        $tail = (Get-Content -LiteralPath $LogPath -Tail 30) -join "`n"
    }
    throw "AppGetter GUI process exited immediately after all launch attempts.`n`nLog: $LogPath`n`n$tail"
}

try {
    $tempRoot = if ($env:TEMP) { $env:TEMP } else { [System.IO.Path]::GetTempPath() }
    $logPath = Join-Path $tempRoot 'AppGetter-launch.log'
    '' | Set-Content -LiteralPath $logPath -Encoding UTF8

    $appRoot = Get-AppGetterAppRoot -Invocation $scriptInvocation
    $guiScript = Join-Path $appRoot 'Gui\Start-AppGetterGui.ps1'
    $moduleManifest = Join-Path $appRoot 'AppGetter.psd1'
    $mainWindowXaml = Join-Path $appRoot 'Gui\AppGetter.MainWindow.xaml'
    $linkDialogXaml = Join-Path $appRoot 'Gui\AppGetter.LinkPickerDialog.xaml'
    $iconDialogXaml = Join-Path $appRoot 'Gui\AppGetter.IconPickerDialog.xaml'
    $isCompiled = $scriptInvocation.MyCommand.CommandType -ne 'ExternalScript'

    Write-AppGetterLaunchLog -LogPath $logPath -Message ("isCompiled={0}" -f $isCompiled)
    Write-AppGetterLaunchLog -LogPath $logPath -Message ("appRoot={0}" -f $appRoot)

    $requiredRuntimeFiles = @(
        @{ Path = $guiScript; Name = 'Gui\Start-AppGetterGui.ps1' }
        @{ Path = $moduleManifest; Name = 'AppGetter.psd1' }
        @{ Path = $mainWindowXaml; Name = 'Gui\AppGetter.MainWindow.xaml' }
        @{ Path = $linkDialogXaml; Name = 'Gui\AppGetter.LinkPickerDialog.xaml' }
        @{ Path = $iconDialogXaml; Name = 'Gui\AppGetter.IconPickerDialog.xaml' }
    )

    $missing = @(
        $requiredRuntimeFiles |
            Where-Object { -not (Test-Path -LiteralPath $_.Path) } |
            ForEach-Object { $_.Name }
    )

    if ($missing.Count -gt 0) {
        $missingText = ($missing -join ', ')
        throw "AppGetter runtime files are missing next to the launcher: $missingText.`nLooked in: $appRoot`n`nKeep AppGetter.exe in the same folder as Gui\, Private\, and AppGetter.psd1."
    }

    Set-Location -LiteralPath $appRoot

    if ($isCompiled) {
        Start-AppGetterGuiProcess -AppRoot $appRoot -GuiScript $guiScript -LogPath $logPath | Out-Null
    } else {
        Write-AppGetterLaunchLog -LogPath $logPath -Message 'Running GUI in-process (not compiled)'
        & $guiScript
    }
} catch {
    $message = "AppGetter failed to start:`n`n{0}" -f $_.Exception.Message
    if ($logPath) {
        try { Write-AppGetterLaunchLog -LogPath $logPath -Message ("FATAL: " + $_.Exception.Message) } catch { }
        $message += "`n`nLog: $logPath"
    }
    Show-AppGetterStartupError -Message $message
    exit 1
}
