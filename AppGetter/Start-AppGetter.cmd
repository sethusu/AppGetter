@echo off
REM Double-click helper for the source tree (no build required).
REM For a packaged AppGetter.exe, run: .\Build\Build-AppGetterExe.ps1
start "" "%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -STA -File "%~dp0Launch-AppGetter.ps1"
