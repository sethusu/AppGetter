# Silent Install Switch Discovery Proposal

## Goal

Improve AppGetter's install command generation so silent switch selection is:

1. **More accurate** across installer ecosystems.
2. **Evidence-based** (with confidence + source tracing).
3. **Verifiable** before package output is finalized.

---

## Why this change is needed

Current behavior is intentionally simple:

- `.msi` => `msiexec /i "<file>" /quiet /norestart`
- `.exe` => detected support-page switch, else default `/S`

This works for some EXE installers but misses many common families:

- Inno Setup (`/VERYSILENT /SUPPRESSMSGBOXES /SP- /NORESTART`)
- NSIS (`/S`, case-sensitive)
- InstallShield wrappers (`/s /v"/qn /norestart"`)
- WiX Burn bundles (`/quiet /norestart`)
- Advanced Installer EXE bootstrapper (`/exenoui /qn /norestart`)
- Squirrel (`--silent`)

It also does not currently classify wrapper/nested scenarios:

- MSI inside EXE
- EXE inside MSI custom action

---

## Recommended strategy: layered discovery pipeline

Use a **ranked candidate model** instead of a single guessed switch.

### Phase 1: Local static classification (fast, offline, deterministic)

Input: downloaded installer path.

1. **Detect container type by extension + magic bytes**
   - `.msi`: MSI route.
   - `.exe`: PE route.
2. **For MSI**
   - Set primary command to `msiexec /i "<installer>" /qn /norestart`.
   - Parse MSI metadata if possible (ProductCode, UpgradeCode, Manufacturer, ProductName) for output quality.
3. **For EXE**
   - Extract UTF-8/UTF-16 strings and look for known family signatures.
   - Build confidence score from signature hits.

#### Suggested EXE family signatures and preferred silent command

- **Inno Setup**
  - Markers: `Inno Setup Setup Data`, `JR.Inno.Setup`
  - Command: `"<installer>" /VERYSILENT /SUPPRESSMSGBOXES /SP- /NORESTART`
- **NSIS**
  - Markers: `Nullsoft`, `NSIS`
  - Command: `"<installer>" /S`
- **InstallShield (MSI wrapper patterns)**
  - Markers: `InstallShield`, `setup.inx`, `ISSetup.dll`
  - Command: `"<installer>" /s /v"/qn /norestart"`
- **WiX Burn**
  - Markers: `WixBundle`, `Burn`
  - Command: `"<installer>" /quiet /norestart`
- **Advanced Installer EXE bootstrapper**
  - Markers: `Advanced Installer`, `AI_DATA`, `aiu`
  - Command: `"<installer>" /exenoui /qn /norestart`
- **Squirrel**
  - Markers: `Squirrel`, `SquirrelAware`
  - Command: `"<installer>" --silent`

If no high-confidence family match exists, keep fallback candidates:

1. `"<installer>" /S`
2. `"<installer>" /silent`
3. `"<installer>" /quiet`

### Phase 2: Nested installer detection

This is the key for "MSI in EXE" and "EXE in MSI" cases.

1. **EXE contains MSI (preferred path)**
   - Attempt extraction/listing (`7z l`, `7z x`, vendor `/extract`, `/a`).
   - If `.msi` is recovered, switch to MSI command strategy (`msiexec /i ... /qn /norestart`).
   - Record extracted MSI metadata.
2. **MSI launches embedded EXE**
   - Parse MSI tables/custom action text for embedded EXE command hints.
   - Keep MSI as primary installer but attach warning/evidence that silent behavior may depend on embedded EXE.

### Phase 3: Documentation/web enrichment (optional but high value)

Use `SupportUrl` (and optionally developer docs) to find vendor-confirmed syntax:

- Search page text for explicit command examples.
- Prefer snippets containing executable name + switches.
- Map discovered switches to candidate list and raise confidence.

### Phase 4: Candidate ranking and explainability

Return a ranked list, not only one string:

- `Command`
- `Confidence` (0.0-1.0)
- `Evidence` array (`signature_match`, `support_page_snippet`, `extracted_msi`, etc.)
- `Family` (`Inno`, `NSIS`, `MSI`, `Unknown`)

Output JSON example:

- `silentSwitchPlan.json` in version folder
- Include chosen command and alternates

---

## Verification plan (required for production reliability)

Silent switch discovery must be validated with runtime evidence.

## Verification levels

1. **Level A - Static only** (Linux-compatible)
   - Signature-based classification unit tests.
   - Confidence/ranking tests from known sample strings.
2. **Level B - Installer execution smoke tests** (Windows CI/runner)
   - Run selected candidate with timeout.
   - Accept known success/reboot/busy codes (0, 3010, 1641, 1618).
   - Detect obvious failures quickly (help text/invalid switch exit).
3. **Level C - UI-silence validation** (Windows sandbox, optional)
   - Install in disposable VM/session.
   - Assert no interactive prompt blocks execution.
   - Capture log artifacts for review.

## Practical runtime verification loop

For each candidate in rank order:

1. Run with timeout and logging enabled when supported.
2. If return code indicates invalid arguments/failure, mark candidate failed.
3. If return code is accepted and install footprint appears (registry/file checks), mark candidate verified.
4. Persist winner in a local switch cache keyed by installer fingerprint (hash + publisher + product).

---

## How to integrate into AppGetter

## New module

Add `Private/SilentSwitchDiscovery.ps1` with:

- `Get-InstallerSilentSwitchPlan`
- `Get-ExeInstallerFamily`
- `Get-InstallerExtractionHints`
- `Test-SilentInstallCandidate` (Windows-only guarded)

## Packaging flow changes

In `Invoke-AppGetterPackaging`:

1. After download/hash, call `Get-InstallerSilentSwitchPlan`.
2. Use `Plan.SelectedCommand` unless `-InstallCommand` is provided.
3. Write `silentSwitchPlan.json` to output.
4. Add plan summary to generated `README.md`.

## CLI/GUI options to add

- `-SkipSwitchVerification` (default: false on Windows, true on non-Windows)
- `-SwitchDiscoveryMode [Fast|Balanced|Thorough]`
- `-SwitchCachePath`

---

## Proposed rollout

1. **Milestone 1:** Static classifier + ranked candidates + JSON evidence output.
2. **Milestone 2:** Nested extraction path for MSI-in-EXE.
3. **Milestone 3:** Windows runtime candidate verification + cache.
4. **Milestone 4:** GUI display of evidence/confidence and manual override UX.

---

## Evidence gathered during this investigation

1. MSI has a stable silent model (`msiexec /qn` or `/quiet`) and admin extraction (`/a`) in Microsoft docs.
2. Common EXE frameworks have distinct silent conventions and official docs:
   - Inno Setup, NSIS, InstallShield, WiX Burn.
3. Real sample inspection showed:
   - `winscp.exe` includes explicit `Inno Setup Setup Data` strings (strong family signal).
   - `firefox.msi` metadata indicates WiX-built MSI and includes custom action text invoking a wrapped EXE with `/S` (evidence that nested behavior exists and should be surfaced, not ignored).

---

## Success criteria for AppGetter implementation

The implementation is successful when:

1. `.msi` installers always produce correct silent commands and metadata.
2. `.exe` installers return a ranked candidate list with explainable evidence.
3. Nested MSI/EXE cases are detected and annotated.
4. On Windows validation runs, selected command succeeds for a representative corpus and outperforms the current `/S` fallback hit rate.
5. Generated package output includes discovery evidence (`silentSwitchPlan.json`) for operator trust and troubleshooting.
