#!/usr/bin/env bash
# Idempotent Cloud Agent setup for the AppGetter PowerShell tool.
# The base image already provides PowerShell Core (pwsh); this script ensures the
# PowerShell modules needed for linting (PSScriptAnalyzer) and the test suite
# (Pester 5) are installed for the current user. Safe to run repeatedly.
set -euo pipefail

if ! command -v pwsh >/dev/null 2>&1; then
  echo "ERROR: pwsh (PowerShell Core) is not installed in the base image." >&2
  exit 1
fi

pwsh -NoProfile -Command '
  $ErrorActionPreference = "Stop"
  Set-PSRepository -Name PSGallery -InstallationPolicy Trusted -ErrorAction SilentlyContinue

  $modules = @(
    @{ Name = "PSScriptAnalyzer"; Min = [version]"1.21.0" },
    @{ Name = "Pester";           Min = [version]"5.0.0"  }
  )

  foreach ($m in $modules) {
    $have = Get-Module -ListAvailable -Name $m.Name |
      Where-Object { $_.Version -ge $m.Min } |
      Sort-Object Version -Descending |
      Select-Object -First 1
    if ($have) {
      Write-Host ("{0} already present: {1}" -f $m.Name, $have.Version)
    } else {
      Write-Host ("Installing {0} (>= {1})..." -f $m.Name, $m.Min)
      Install-Module -Name $m.Name -MinimumVersion $m.Min -Scope CurrentUser -Force -SkipPublisherCheck
    }
  }
'

echo "AppGetter environment setup complete."
