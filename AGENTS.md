# AGENTS.md

## Project overview

`AppGetter/` is a PowerShell-only tool that downloads a Windows application installer from the web
and generates a Microsoft Intune Win32 LOB (`.intunewin`) package plus metadata (`install.ps1`,
`detection.ps1`, `uninstall.ps1`, `README.md`, `app.json`, `win32LobApp.json`, `readme.txt`).
See `AppGetter/README.md` for full usage and parameters.

The project mirrors the modular structure of [WinGetter](https://github.com/sethusu/WinGetter)
(Wingetter) but sources installers from web URLs instead of Winget. There is no Python backend,
Flask server, or browser UI.

## Cursor Cloud specific instructions

This repo is a PowerShell CLI tool; the Cursor Cloud VM is Linux. PowerShell Core
(`pwsh`) and the `PSScriptAnalyzer` linter module are provisioned by the update script.

- Run the tool: `pwsh -NoProfile -File AppGetter/Create-IntuneWinFromWeb.ps1 ...`
- Import module: `pwsh -NoProfile -Command "Import-Module AppGetter/AppGetter.psd1 -Force"`
- Lint: `pwsh -NoProfile -Command "Invoke-ScriptAnalyzer -Path AppGetter -Recurse -Severity Error,Warning"`
  - Current findings are Warnings only (e.g. `PSAvoidUsingWriteHost`) and are pre-existing/expected for a console tool.
- Syntax check: parse with `[System.Management.Automation.Language.Parser]::ParseFile(...)`.

Non-obvious caveats when running on Linux:
- Always pass `-OutputPath` to a Linux path (e.g. `/tmp/intune-out`). The default is
  `Documents\AppGetter Output` under the user profile.
- Run non-interactively by always passing `-DownloadUrl` (or `-WebsiteUrl`) **and** `-AppName`.
  With no args the script opens Windows Forms / `Microsoft.VisualBasic` input dialogs, which
  do not exist on Linux.
- The final packaging step (`intunewinapputil`, the Microsoft Win32 Content Prep Tool) is
  closed-source and **Windows-only** (.NET Framework 4.7.2; Linux only via Wine). It is an
  external prerequisite, not part of this repo. On Linux this step fails gracefully — the
  script still produces every other file. Everything except the final `.intunewin` archive
  can be exercised on Linux.

There are no automated tests. Validate changes by running the script end-to-end against a
real direct download URL and inspecting the generated files.
