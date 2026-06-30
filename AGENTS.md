# AGENTS.md

## Project overview

`AppGetter/` is a standalone PowerShell tool that downloads a Windows application installer from the web
and generates a Microsoft Intune Win32 LOB (`.intunewin`) package plus its metadata (`install.ps1`,
`detection.ps1`, `uninstall.ps1`, `app.json`, `win32LobApp.json`, `README.md`, `readme.txt`).
See `AppGetter/README.md` for full usage and parameters.

The project mirrors the [WinGetter](https://github.com/sethusu/WinGetter) architecture: a PowerShell module
(`AppGetter.psd1` / `AppGetter.psm1`), `Private/` helpers, a WPF GUI under `Gui/`, and a CLI entry point
(`Create-IntuneWinFromWeb.ps1`). There is no Python backend or web dashboard.

There is no build system, package manager, lockfile, or service — it is a one-shot CLI/GUI PowerShell tool.

## Cursor Cloud specific instructions

This repo is a PowerShell CLI/GUI tool; the Cursor Cloud VM is Linux. PowerShell Core
(`pwsh`) and the `PSScriptAnalyzer` linter module are provisioned by the update script.

- Run the tool: `pwsh -NoProfile -File AppGetter/Create-IntuneWinFromWeb.ps1 ...`
- Lint: `pwsh -NoProfile -Command "Invoke-ScriptAnalyzer -Path AppGetter -Recurse -Severity Error,Warning"`
  - Current findings are Warnings only (e.g. `PSAvoidUsingWriteHost`) and are pre-existing/expected for a console tool.
- Syntax check: parse with `[System.Management.Automation.Language.Parser]::ParseFile(...)`.

Non-obvious caveats when running on Linux:
- Always pass `-OutputPath` to a Linux path (e.g. `/tmp/intune-out`). The default uses
  `%USERPROFILE%\Documents\AppGetter Output`, which resolves under the Linux home directory but may differ from Windows expectations.
- Run non-interactively by always passing `-DownloadUrl` (or `-WebsiteUrl`) **and** `-AppName`.
  With no args the script launches the WPF GUI, which does not exist on Linux.
- The final packaging step (`intunewinapputil`, the Microsoft Win32 Content Prep Tool) is
  closed-source and **Windows-only** (.NET Framework 4.7.2). It is an external prerequisite, not part of this repo.
  On Linux this step fails gracefully — the script still produces every other file. Everything except the final
  `.intunewin` archive can be exercised on Linux when `-DownloadUrl` points to a reachable installer URL.

There are no automated tests. Validate changes by running the script end-to-end against a
real direct download URL and inspecting the generated files.
