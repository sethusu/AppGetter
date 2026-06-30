# AGENTS.md

## Project overview

`AppGetter/` is a PowerShell-first Intune packaging tool centered on
`Create-IntuneWinFromWeb.ps1` with a desktop GUI launcher at
`AppGetter/Gui/Start-AppGetterGui.ps1`. It downloads a Windows installer and
generates an Intune Win32 package plus metadata/scripts (`install.ps1`,
`detection.ps1`, `uninstall.ps1`, `app.json`, `win32LobApp.json`,
`README.md`, `readme.txt`).

There is no build system, package manager, lockfile, or service — it is a local PowerShell tool.

## Cursor Cloud specific instructions

This repo is a PowerShell packaging tool; the Cursor Cloud VM is Linux.
PowerShell Core (`pwsh`) and the `PSScriptAnalyzer` linter module are provisioned by the update script.

- Run CLI mode: `pwsh -NoProfile -File AppGetter/Create-IntuneWinFromWeb.ps1 -AppName ... -DownloadUrl ... -OutputPath /tmp/intune-out`
- Lint: `pwsh -NoProfile -Command "Invoke-ScriptAnalyzer -Path AppGetter -Recurse -Severity Error,Warning"`
  - Current findings are Warnings only (e.g. `PSAvoidUsingWriteHost`) and are pre-existing/expected for a console tool.
- Syntax check: parse with `[System.Management.Automation.Language.Parser]::ParseFile(...)`.

Non-obvious caveats when running on Linux:
- Always pass `-OutputPath` to a Linux path (e.g. `/tmp/intune-out`). The default is the
  Windows path `D:\Intoon In Progress`, which fails on Linux.
- Run non-interactively by always passing `-DownloadUrl` (or `-WebsiteUrl`) **and** `-AppName`.
  With no args the script launches the Windows Forms GUI, which is unavailable on Linux.
- The final packaging step (`intunewinapputil`, Microsoft Win32 Content Prep Tool) is an
  external prerequisite and expected to be available on end-user Windows hosts. On Linux,
  command availability depends on environment configuration.

There are no automated tests. Validate changes by running the script end-to-end against a
real direct download URL and inspecting the generated files.
