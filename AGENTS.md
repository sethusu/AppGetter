# AGENTS.md

## Project overview

`AppGetter/` is a PowerShell-only tool that mirrors the [WinGetter](https://github.com/sethusu/WinGetter) architecture for **web-based** application downloads instead of Winget. It downloads a Windows installer from the web and generates a Microsoft Intune Win32 LOB (`.intunewin`) package plus metadata (`install.ps1`, `detection.ps1`, `uninstall.ps1`, `app.json`, `win32LobApp.json`, `README.md`, `readme.txt`). See `AppGetter/README.md` for full usage.

There is no build system, package manager, lockfile, Python backend, or web server — it is a PowerShell module with CLI and WPF GUI entry points.

## Cursor Cloud specific instructions

This repo is a PowerShell CLI tool; the Cursor Cloud VM is Linux. PowerShell Core (`pwsh`) and `PSScriptAnalyzer` are provisioned by the update script.

- Run the tool: `pwsh -NoProfile -File AppGetter/Create-IntuneWinFromWeb.ps1 ...`
- Lint: `pwsh -NoProfile -Command "Invoke-ScriptAnalyzer -Path AppGetter -Recurse -Severity Error,Warning"`
  - Current findings are Warnings only (e.g. `PSAvoidUsingWriteHost`) and are expected for a console tool.
- Syntax check: parse with `[System.Management.Automation.Language.Parser]::ParseFile(...)`.

Non-obvious caveats when running on Linux:
- Always pass `-OutputPath` to a Linux path (e.g. `/tmp/intune-out`). The default is a Windows `Documents\AppGetter Output` path.
- Run non-interactively by passing `-DownloadUrl` (or `-WebsiteUrl`) **and** `-AppName`. With no args the script launches the WPF GUI, which requires Windows.
- The final packaging step (`intunewinapputil`) is **Windows-only**. On Linux this step fails gracefully — the script still produces every other file. Everything except the final `.intunewin` archive can be exercised on Linux.
- The WPF GUI (`Gui/Start-AppGetterGui.ps1`) is Windows-only.

There are no automated tests. Validate changes by running the script end-to-end against a real direct download URL and inspecting the generated files.
