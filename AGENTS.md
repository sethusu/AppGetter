# AGENTS.md

## Project overview

`AppGetter/` is a standalone PowerShell tool that mirrors the [WinGetter](https://github.com/sethusu/WinGetter)
(Wingetter) architecture. It downloads a Windows application installer from the web and generates a Microsoft
Intune Win32 LOB (`.intunewin`) package plus its metadata (`install.ps1`, `detection.ps1`, `uninstall.ps1`,
`README.md`, `app.json`, `win32LobApp.json`, `readme.txt`). See `AppGetter/README.md` for full usage.

There is no build system, package manager, lockfile, or service — it is a PowerShell module + CLI/GUI tool.
The end user is expected to have the Microsoft Win32 Content Prep Tool (`intunewinapputil`) installed.

## Cursor Cloud specific instructions

This repo is a PowerShell CLI/GUI tool; the Cursor Cloud VM is Linux. PowerShell Core
(`pwsh`) and the `PSScriptAnalyzer` linter module are provisioned by the update script.

- Run the tool: `pwsh -NoProfile -File AppGetter/Create-IntuneWinFromWeb.ps1 ...`
- Lint: `pwsh -NoProfile -Command "Invoke-ScriptAnalyzer -Path AppGetter -Recurse -Severity Error,Warning"`
  - Current findings are Warnings only (e.g. `PSAvoidUsingWriteHost`) and are pre-existing/expected for a console tool.
- Syntax check: parse with `[System.Management.Automation.Language.Parser]::ParseFile(...)`.

Non-obvious caveats when running on Linux:
- Always pass `-OutputPath` to a Linux path (e.g. `/tmp/intune-out`). The default is the
  Windows path under `Documents\AppGetter Output`, which fails on Linux.
- Run non-interactively by always passing `-DownloadUrl` (or `-WebsiteUrl`) **and** `-AppName`.
  With no args the script launches the WPF GUI (Windows only) or opens Windows Forms input dialogs in CLI mode,
  which do not exist on Linux.
- The final packaging step (`intunewinapputil`, the Microsoft Win32 Content Prep Tool) is
  closed-source and **Windows-only** (.NET Framework 4.7.2; Linux only via Wine). It is an
  external prerequisite, not part of this repo. On Linux this step fails gracefully — the
  script still produces every other file and exits 0. Everything except the final
  `.intunewin` archive can be exercised on Linux.
- **Test in Sandbox** is Windows-only (Windows Sandbox / `Containers-DisposableClientVM`). On Linux,
  `Test-AppGetterWindowsSandbox` reports unsupported; host-side helpers and Pester tests under
  `AppGetter/Tests/Sandbox.Tests.ps1` still run.
- **Silent-switch Sandbox research trials** (`Test-InstallerCommandInSandbox`, `-VerifySilentSwitches`)
  are also Windows-only. On Linux, static fingerprinting/ranking still runs and packages are marked
  `verified=false`; candidate trials and ARP/UI evidence collection are skipped.
- Live Sandbox research Pester tests are tagged `SandboxLive` and are **excluded by default** from
  `AppGetter/Run-Tests.ps1` so Linux CI stays green. On a Windows Pro/Enterprise host with Sandbox
  enabled, run them with:
  `pwsh -NoProfile -File AppGetter/Run-Tests.ps1 -Tag SandboxLive -ExcludeTag @()`

Automated tests (optional): `pwsh -NoProfile -File AppGetter/Run-Tests.ps1`
Static silent-switch corpus: `AppGetter/Tests/SwitchDiscovery.Tests.ps1` (Linux-safe).
Validate packaging changes by running the script end-to-end against a real direct download URL
and inspecting the generated files.
