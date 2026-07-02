# Silent Switch Research Evidence

This file records the concrete command-driven evidence used to shape the proposal.

## Existing AppGetter behavior

- `Get-InstallerInstallCommand` currently sets:
  - MSI: `msiexec /i "<file>" /quiet /norestart`
  - Default EXE: `"<file>" /S`
- `Get-WebInstallSwitches` searches broad text patterns and `Get-DetectedSilentSwitch` only resolves `/S`, `/SILENT`, `/VERYSILENT`.

## Environment checks

Command:
- `which pwsh && pwsh -NoProfile -Command '$PSVersionTable.PSVersion.ToString()'`

Observed output:
- `/usr/bin/pwsh`
- `7.6.3`

## Sample installers used

Command:
- Python download script against:
  - `https://www.7-zip.org/a/7z2409-x64.msi`
  - `https://www.7-zip.org/a/7z2409-x64.exe`
  - `https://aka.ms/vs/17/release/vc_redist.x64.exe`

Observed output:
- `7z2409-x64.msi bytes 1987584`
- `7z2409-x64.exe bytes 1637343`
- `vc_redist.x64.exe bytes 25635768`

## Container identification (`file`)

Command:
- `file /tmp/installer-research/7z2409-x64.msi /tmp/installer-research/7z2409-x64.exe /tmp/installer-research/vc_redist.x64.exe`

Observed output:
- `7z2409-x64.msi`: `Composite Document ... MSI Installer ...`
- `7z2409-x64.exe`: `PE32 executable`
- `vc_redist.x64.exe`: `PE32 executable`

## Wrapper/family signals (`strings` + `rg`)

Command:
- `strings -n 8 /tmp/installer-research/vc_redist.x64.exe | rg -i "wixbundle|bootstrapper|burn|quiet|passive|norestart|layout|msi|msiexec"`

Observed output (selected):
- `.wixburn`
- `BootstrapperApplicationCreate`
- `WiX Toolset Bootstrapper`
- Multiple `burn\\engine\\...` source path markers
- MSI execution/layout related strings (`execute MSI package`, `layout`)

## Conclusion from command evidence

- Static inspection can reliably identify direct MSI vs EXE wrappers.
- Wrapper EXEs can expose installer family markers (for example WiX Burn) without running the binary.
- This supports a high-confidence staged discovery method before runtime verification.
