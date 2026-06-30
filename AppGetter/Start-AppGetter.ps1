<#
.SYNOPSIS
    Starts the AppGetter graphical interface with one command.
.DESCRIPTION
    Launches the WPF-based AppGetter GUI. No Python or web server required.
.EXAMPLE
    .\Start-AppGetter.ps1
#>

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
& (Join-Path $scriptRoot 'Gui\Start-AppGetterGui.ps1')
