# AGENTS.md

## Project overview

`AppGetter/` is a standalone PowerShell tool that mirrors the [WinGetter](https://github.com/sethusu/WinGetter)
(Wingetter) architecture and UI. It takes a Windows application installer — from a **download URL**, a **local
file on the machine running it**, or a **download link scanned from a website** — and generates a Microsoft
Intune Win32 LOB (`.intunewin`) package plus its metadata (`install.ps1`, `detection.ps1`, `uninstall.ps1`,
`README.md`, `app.json`, `win32LobApp.json`, `readme.txt`). See `AppGetter/README.md` for full usage.

It is a PowerShell module + CLI/GUI tool with no package manager or lockfile. It is deployed as a portable
executable: `AppGetter/Build/Build-AppGetterExe.ps1` compiles `Launch-AppGetter.ps1` into `AppGetter.exe`
with ps2exe (Windows only). The end user is expected to have the Microsoft Win32 Content Prep Tool
(`intunewinapputil`) installed; the GUI can install it via winget.

## Cursor Cloud specific instructions

This repo is a PowerShell CLI/GUI tool; the Cursor Cloud VM is Linux. PowerShell Core
(`pwsh`) and the `PSScriptAnalyzer` linter module are provisioned by the update script.

- Run the tool: `pwsh -NoProfile -File AppGetter/Create-IntuneWinFromWeb.ps1 ...`
- Tests: `pwsh -NoProfile -File AppGetter/Run-Tests.ps1` (Pester 5+; installed automatically from PSGallery if missing).
 - Suites cover output path helpers, installer source resolution, end-to-end packaging from a local file,
   and the GUI/executable contract (XAML control names vs. `FindName` calls, module exports, staged build files).
- Lint: `pwsh -NoProfile -Command "Invoke-ScriptAnalyzer -Path AppGetter -Recurse -Severity Error,Warning"`
 - Current findings are Warnings only (e.g. `PSAvoidUsingWriteHost`, `PSUseShouldProcessForStateChangingFunctions`,
   `PSAvoidUsingEmptyCatchBlock` in GUI/launcher code) and are expected — they match the upstream Wingetter patterns.
- Syntax check: parse with `[System.Management.Automation.Language.Parser]::ParseFile(...)`.

Non-obvious caveats when running on Linux:
- Always pass `-OutputPath` to a Linux path (e.g. `/tmp/intune-out`). The default is the
 user-profile path `Documents/AppGetter`, which is not a useful location on the VM.
- Run non-interactively by always passing `-DownloadUrl`, `-InstallerPath`, or `-WebsiteUrl` **and** `-AppName`.
 With no args the script launches the WPF GUI (Windows only) or opens Windows Forms input dialogs in CLI mode,
 which do not exist on Linux.
- The WPF GUI (`Gui/Start-AppGetterGui.ps1`), the ps2exe build, and `AppGetter.exe` cannot run on Linux.
 Validate GUI changes with `AppGetter/Tests/GuiContract.Tests.ps1` (control-name and deployment contract)
 plus a parse check; the packaging logic behind the GUI is exercised by the CLI/module end-to-end.
- The final packaging step (`intunewinapputil`, the Microsoft Win32 Content Prep Tool) is
  closed-source and **Windows-only** (.NET Framework 4.7.2; Linux only via Wine). It is an
  external prerequisite, not part of this repo. On Linux this step fails gracefully — the
  script still produces every other file and exits 0. Everything except the final
  `.intunewin` archive can be exercised on Linux.

Validate changes by running `AppGetter/Run-Tests.ps1` **and** running the script end-to-end against a
real direct download URL (and a local installer file) and inspecting the generated files.
