# AppGetter

**Turn web downloads or local installer files into Intune Win32 packages in minutes.**

AppGetter automates the tedious parts of packaging desktop software for Microsoft Intune: downloading the installer from the web (or copying one already on your computer), generating `install.ps1` / `detection.ps1` / `uninstall.ps1`, resolving an app icon, building the `.intunewin` file with the Microsoft Win32 Content Prep Tool, and writing a field-by-field Intune upload guide.

AppGetter follows the [WinGetter](https://github.com/sethusu/WinGetter) (Wingetter) architecture and UI — the difference is the installer source: Wingetter pulls apps from Winget, AppGetter uses a download URL or a file on the computer running it.

Built for IT admins and packaging teams who need repeatable Win32 app onboarding without hand-writing detection scripts for every app.

---

## What you get

For each application, AppGetter produces:

| Output | Purpose |
|--------|---------|
| `{App}.intunewin` | Upload this to the Intune admin center |
| `install.ps1` | Silent install wrapper with Intune return codes |
| `detection.ps1` | Registry-based detection (no external dependencies on devices) |
| `uninstall.ps1` | Quiet uninstall from registry uninstall string |
| `README.md` | Copy/paste reference for every Intune portal field |
| `logo.png` / `icon.png` | App icon for Intune upload |
| `app.json` / `win32LobApp.json` | Metadata exports |
| `validation.json` | Written after a successful Test in Sandbox run |
| `silent-switches.json` | Silent-switch discovery result (command, confidence, verified flag) |
| `licensing.json` | Licensing pattern, activation plan, and compliance notes (when a licensing field was supplied) |
| `license\` | License file shipped with the package (when the licensing pattern needs one) |
| `sandbox-test-report.txt` | Chat-ready sandbox log (after Test in Sandbox) |

---

## Requirements

| Requirement | Notes |
|-------------|-------|
| **Windows 10/11** | PowerShell 5.1 or later |
| **[Win32 Content Prep Tool](https://github.com/microsoft/Microsoft-Win32-Content-Prep-Tool)** | `intunewinapputil` — install it from the GUI (via winget) if it is missing |
| **Internet Access** | Required when packaging from a website or direct download URL |

Run the built-in check from PowerShell:

```powershell
cd AppGetter
Import-Module .\AppGetter.psd1
Test-AppGetterPrerequisites
```

---

## Quick start (GUI — recommended)

1. **Clone or download** this repository.
2. Double-click **`Start-AppGetter.cmd`** (no elevated PowerShell required), or run from PowerShell:

```powershell
cd AppGetter
.\Create-IntuneWinFromWeb.ps1
```

Or launch the GUI directly:

```powershell
.\Gui\Start-AppGetterGui.ps1
```

3. Enter the **application name** and one of: a **website URL** (to scan for download links), a **direct download URL**, or a **local installer file** (Browse...).
4. Choose an **output folder** — each app gets its own subfolder (default: `Documents\AppGetter\{App}`).
5. Click **Create Package** and watch the live progress steps (the window stays responsive while packaging runs in the background).
6. Optionally click **Test in Sandbox** to confirm install, detection, and uninstall inside Windows Sandbox before uploading to Intune.
7. Open the output folder and upload the `.intunewin` to Intune using the included `README.md` as your field guide.

If the Content Prep Tool is missing, the header shows an **Install Content Prep** button that installs `intunewinapputil` via winget.

### Test in Sandbox

After a package is created (or when the output folder already contains `install.ps1`, `detection.ps1`, and `uninstall.ps1`), use **Test in Sandbox** to:

1. Launch Windows Sandbox with the package folder mapped in
2. Run `install.ps1`, confirm the step, then `detection.ps1`, then `uninstall.ps1`
3. Mark the package validated only when all three steps succeed and the install stayed silent (no installer UI)

Requires Windows 10/11 Pro, Enterprise, or Education with Windows Sandbox enabled. The dialog can prompt to enable the feature (admin approval; usually a reboot). Diagnostics are written next to the package as `sandbox-test-report.txt`, `sandbox-failure.log`, and `sandbox-logs\`.

---

## Licensing

Paste the licensing field from the ServiceNow software record into **Licensing (ServiceNow field)** and AppGetter identifies which licensing pattern the application follows, then applies that pattern to the package. The status line under the field names the pattern as you type.

```powershell
# Per-device perpetual with a key: the key is baked into the install command
.\Create-IntuneWinFromWeb.ps1 -DownloadUrl "https://example.com/setup.msi" -AppName "MyApp" `
    -LicenseInfo "Licensed - per device perpetual, 25 seats, license key 4XJ9-2210-KD77-9931, expires 2028-03-31"

# Concurrent/floating: the client is pointed at the license server during install
.\Create-IntuneWinFromWeb.ps1 -InstallerPath "C:\Installers\sim.exe" -AppName "SIMION" `
    -LicenseInfo "Concurrent FlexLM, license server 27000@lm.corp.local, 10 concurrent seats"

# License file: the file ships inside the .intunewin and is staged before install
.\Create-IntuneWinFromWeb.ps1 -InstallerPath "C:\Installers\app.exe" -AppName "MyApp" `
    -LicenseInfo "Node-locked, license file based" `
    -LicenseFilePath "C:\Licenses\license.dat" -LicenseFileTargetPath "%ProgramData%\Vendor\license.dat"
```

### Patterns AppGetter recognizes

| Pattern | Activation | Suggested Intune assignment |
|---------|-----------|-----------------------------|
| Open source | none | Required |
| Freeware / no license required | none | Required |
| Trial / evaluation | expires | Available |
| Per-user subscription | account sign-in | Available |
| Per-device perpetual | license key | Required |
| Per core / processor | license key | Required |
| Concurrent / floating | license server | Required |
| License file / entitlement certificate | license file | Required |
| Site / enterprise agreement | shared key (optional) | Required |
| Volume activation (MAK / KMS) | KMS, ADBA, or MAK | Required |
| Hardware key / dongle | physical key | Required |
| OEM / bundled with hardware | none | Required |
| Purchased license key | license key | Available |

Classification reads the licensing text and corroborates it against strings inside the installer — FlexNet/FLEXlm, RLM, Sentinel RMS, HASP, CodeMeter, volume activation clients, trial-expiry and sign-in prompts, and key-bearing MSI properties. The same pass pulls the license key, `port@host` server, vendor environment variable, license file name and destination, seat count, expiry date, and any approval or chargeback requirement out of the field, so those rarely need to be typed twice.

### How the pattern is applied

| Activation | What the package does |
|-----------|----------------------|
| License key | Appends the property detected in the installer (for example `SERIALNUMBER="…"`) to `msiexec` command lines and WiX Burn bootstrappers. Other installer families do not accept MSI properties on the command line, so the key is documented for a post-install step instead |
| License file | Copies the file into the package under `license\` and stages it to the target path in `install.ps1` before the installer runs |
| License server | Sets the vendor variable (`LM_LICENSE_FILE`, `RLM_LICENSE`, `LSFORCEHOST`, or one named in the field) machine-wide and for the install session |
| Sign-in, dongle, volume, trial | Logged in the install transcript, so a device that shows up unlicensed explains itself in the Intune logs |

Every supplied artifact is applied, not just the one matching the primary pattern — a floating-license app that also needs a local `license.dat` gets both.

The result lands in `licensing.json`, the `licensing` block in `app.json`, a **Licensing** section in the generated `README.md`, and the `win32LobApp` notes, together with a confidence score, the evidence behind the classification, and compliance notes for seat counts and expiry dates. Low confidence or a missing artifact sets a manual-review flag rather than guessing.

License keys are masked wherever they are persisted (`4XJ9***********9931`), redacted out of the licensing text stored in metadata, and replaced with `***REDACTED***` in the `install.ps1` transcript.

Pass `-LicenseType` to override classification. It accepts pattern ids, the license types in the table above, or the usual ServiceNow *License type* / *License metric* choice values (`Per user`, `Named user`, `Per device`, `Concurrent`, `Per core`, `Site license`, `MAK`, `OEM`, and so on).

---

## Deploy as an executable

Build a double-clickable `AppGetter.exe` (same ps2exe pipeline as Wingetter):

```powershell
cd AppGetter
.\Build\Build-AppGetterExe.ps1
```

This stages `dist\AppGetter` with `AppGetter.exe` next to the runtime files and creates
`dist\AppGetter-portable.zip` for sharing. End users just double-click `AppGetter.exe` —
no elevated PowerShell session required. If antivirus blocks the exe, `Start-AppGetter.cmd`
or `Launch-AppGetter.ps1` launch the same GUI. Startup problems are logged to
`%TEMP%\AppGetter-launch.log`.

---

## Quick start (CLI)

For scripting or automation:

```powershell
cd AppGetter

# Package from a website (scans for download links)
.\Create-IntuneWinFromWeb.ps1 -WebsiteUrl "https://simion.com/" -AppName "SIMION" -Publisher "Adaptas Solutions, LLC"

# Package from a direct download URL
.\Create-IntuneWinFromWeb.ps1 -DownloadUrl "https://example.com/installer.exe" -AppName "MyApp" -Version "1.0.0"

# Package an installer already on this computer
.\Create-IntuneWinFromWeb.ps1 -InstallerPath "C:\Installers\setup.exe" -AppName "MyApp" -Version "1.0.0"

# Custom output path and icon
.\Create-IntuneWinFromWeb.ps1 -DownloadUrl "https://example.com/setup.exe" -AppName "MyApp" `
    -OutputPath "C:\IntunePackages" `
    -IconPath "C:\Icons\myapp.png"
```

---

## Typical Intune workflow

1. **Package** the app with AppGetter on a Windows machine that has the Content Prep Tool installed.
2. **Review** the generated `README.md` in the version folder — it lists install command, detection method, publisher, description, and return codes.
3. **Upload** the `.intunewin` file in **Intune** → **Apps** → **Windows** → **Add** → **Windows app (Win32)**.
4. **Fill in** portal fields using the generated reference (or `win32LobApp.json` as a starting point).
5. **Assign** the app to a test group before broad rollout.
6. **Validate** on a pilot device — check `%ProgramData%\Microsoft\IntuneManagementExtension\Logs\` for install/detection logs.

---

## Output folder layout

```
Documents\AppGetter\
└── SIMION\
    ├── logo.png
    └── 8.2.1.3\
        ├── simion-setup.exe
        ├── install.ps1
        ├── detection.ps1
        ├── uninstall.ps1
        ├── README.md                 ← Intune upload cheat sheet
        ├── readme.txt
        ├── app.json
        ├── win32LobApp.json
        ├── licensing.json            ← licensing pattern and activation plan
        ├── license\                  ← license file, when the pattern needs one
        ├── icon.png
        └── ..\simion-setup.intunewin
```

Default output path and last-used settings are saved to:

`%AppData%\AppGetter\settings.json`

---

## Parameters

| Parameter | Description |
|-----------|-------------|
| **WebsiteUrl** | URL to scan for download links |
| **DownloadUrl** | Direct download URL (skips website scanning) |
| **InstallerPath** | Path to an installer file on this computer (skips downloading) |
| **AppName** | Application display name |
| **Version** | Optional version (auto-detected from website if omitted) |
| **Publisher** | Publisher name |
| **DeveloperUrl** | Optional developer site for logo/description lookup |
| **SupportUrl** | Optional docs page for silent install switch discovery |
| **OutputPath** | Base output directory |
| **IconPath** | Custom PNG icon |
| **InstallCommand** | Custom install command (auto-detected if omitted) |
| **LicenseInfo** | Licensing text from the ServiceNow software record; AppGetter identifies the licensing pattern and applies it |
| **LicenseType** | Explicit ServiceNow license type, overriding classification from `LicenseInfo` |
| **LicenseKey** | License key to apply (also parsed from `LicenseInfo` when present) |
| **LicenseServer** | License server as `port@host` for concurrent/floating licensing |
| **LicenseServerVariable** | Environment variable the client reads to find the license server |
| **LicenseFilePath** | License file to ship inside the package and stage during install |
| **LicenseFileTargetPath** | Absolute path the license file is copied to on the device |
| **VerifySilentSwitches** | Trial ranked silent-switch candidates in Windows Sandbox during packaging |
| **UseGui** | Launch the WPF GUI |

---

## Repository layout

```
AppGetter/
├── README.md                          ← You are here
├── Create-IntuneWinFromWeb.ps1         ← CLI entry point (no args = GUI)
├── Launch-AppGetter.ps1               ← Double-click / ps2exe entry point
├── Start-AppGetter.cmd                ← Double-click helper (no build required)
├── AppGetter.psm1                     ← Core module
├── AppGetter.psd1
├── Private/                           ← Packaging, web download, icons, scripts
├── Gui/
│   ├── Start-AppGetterGui.ps1
│   ├── AppGetter.MainWindow.xaml      ← WPF UI
│   └── AppGetter.SandboxTestDialog.xaml
├── Private/
│   └── Sandbox.ps1                    ← Windows Sandbox install/detect/uninstall test
├── Private/
│   └── Licensing.ps1                  ← Licensing pattern discovery and application
├── Tests/
│   ├── Sandbox.Tests.ps1
│   ├── SwitchDiscovery.Tests.ps1
│   └── Licensing.Tests.ps1
├── Build/
│   └── Build-AppGetterExe.ps1         ← Builds AppGetter.exe + portable zip
└── Example-Usage.ps1
```

---

## PowerShell module (advanced)

```powershell
Import-Module .\AppGetter\AppGetter.psd1

Find-WebDownloadLinks -Url 'https://simion.com/' -AppName 'SIMION'
Invoke-AppGetterPackaging -AppName 'MyApp' -DownloadUrl 'https://example.com/setup.exe' -OutputPath 'C:\Out'
Invoke-AppGetterPackaging -AppName 'MyApp' -InstallerPath 'C:\Installers\setup.exe' -OutputPath 'C:\Out'
Install-AppGetterContentPrepTool   # installs intunewinapputil via winget if missing

# Licensing on its own, without packaging anything
Resolve-AppGetterLicensing -LicenseInfo 'Concurrent FlexLM, license server 27000@lm.corp.local'
Get-AppGetterLicensingPatternCatalog | Select-Object Id, LicenseType, ActivationMethod
Get-AppGetterPackageLicensingInfo -VersionDirectory 'C:\Out\MyApp\1.0.0'
```

---

## Troubleshooting

| Problem | What to try |
|---------|-------------|
| `intunewinapputil` not found | Click **Install Content Prep** in the GUI, run `Install-AppGetterContentPrepTool`, or install the [Content Prep Tool](https://github.com/microsoft/Microsoft-Win32-Content-Prep-Tool) manually |
| No download links found | Provide a direct `-DownloadUrl` or a local `-InstallerPath` instead of `-WebsiteUrl` |
| `AppGetter.exe` won't start | Check `%TEMP%\AppGetter-launch.log`; use `Start-AppGetter.cmd` or `Launch-AppGetter.ps1` instead |
| Packaging failed | Check `appgetter-packaging.log` in the version output folder and the GUI log panel |
| Test in Sandbox unavailable | Needs Windows Pro/Enterprise/Education with Sandbox enabled; Home is not supported |
| Sandbox says no installer file | Package folder needs the `.msi`/`.exe` beside `install.ps1`. AppGetter auto-restores it from `app.json` `installerUrl` when you click **Test in Sandbox**; otherwise re-run packaging or copy the installer back into the version folder |
| Sandbox install showed a dialog | Install was not silent — see `sandbox-failure.log` and re-package with better switches |
| Detection fails on devices | Run `detection.ps1` locally; review logs in `%ProgramData%\Microsoft\IntuneManagementExtension\Logs\` |
| Licensing pattern is `unknown` | The licensing field had no recognizable terms — pass `-LicenseType` (or pick one in the GUI) so the package documents the right model |
| License key was not applied to the install command | The installer exposes no key-bearing MSI property, or its family does not accept properties on the command line. `licensing.json` records the reason; activate after install instead |
| App installs but reports unlicensed | Check the licensing lines at the top of `%ProgramData%\Microsoft\IntuneManagementExtension\Logs\{App}-install.log`, then confirm the license server is reachable or the license file landed at its target path |
| GUI won't start | Run from PowerShell 5.1+ on Windows; WPF requires a desktop session |

More detail: [Troubleshooting-Guide.md](Troubleshooting-Guide.md)

---

## License

Provided as-is for creating Intune Win32 packages from web downloads or local installer files.
