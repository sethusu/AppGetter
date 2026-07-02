# Silent Install Switch Discovery Proposal (for AppGetter)

## Goal

Increase AppGetter's success rate for unattended installation by replacing the current "best guess" logic with a deterministic, confidence-scored discovery pipeline that:

1. Detects installer family (`.msi`, `Inno`, `NSIS`, `InstallShield`, `WiX Burn`, custom EXE).
2. Selects the most likely silent command line (including restart suppression and logging).
3. Verifies the selected command before writing `install.ps1`.
4. Falls back safely when confidence is low.

## Current state in AppGetter

- `.msi` currently defaults to `msiexec /i "<file>" /quiet /norestart`.
- Unknown `.exe` defaults to `"<file>" /S`.
- Optional web-page scanning looks for generic switch text and only returns a narrow set of values.

This approach is quick but can fail for mixed or wrapped installers (MSI-inside-EXE, EXE-inside-MSI, InstallShield, Burn bundles).

## Proposed method: layered discovery with confidence scoring

Use a staged pipeline, where each stage can add evidence and increase confidence.

### Stage 1: Normalize and classify by file/container type

For the downloaded installer:

- Identify extension and magic/signature (not extension alone).
- If direct MSI signature is found, classify as MSI immediately.
- If EXE, continue into Stage 2.

Output:
- `PrimaryType` (`msi`, `exe`, `msix`, `appx`, `unknown`)
- `DetectionEvidence[]`
- Initial `Confidence` (0-100)

### Stage 2: EXE fingerprinting (static, no execution)

Scan binary metadata and strings for known markers:

- Inno Setup markers (`Inno Setup`, `/VERYSILENT`, `/SUPPRESSMSGBOXES`)
- NSIS markers (`Nullsoft`, `NSIS`, `/S`)
- InstallShield markers (`InstallShield`, `setup.iss`, `/v`)
- WiX Burn markers (`.wixburn`, `BootstrapperApplication`, `Burn`)
- MSI bridge clues (`msi.dll`, `MsiInstallProduct`, internal MSI package references)

Map fingerprints to candidate command templates:

- **MSI**: `msiexec /i "<file>" /qn /norestart /L*v "<log>"`
- **Inno**: `"<file>" /VERYSILENT /SUPPRESSMSGBOXES /NORESTART /LOG="<log>"`
- **NSIS**: `"<file>" /S`
- **InstallShield (MSI bootstrapper)**: `"<file>" /s /v"/qn /norestart /L*v \"<log>\""`
- **WiX Burn**: `"<file>" /quiet /norestart /log "<log>"`

If multiple families match, keep all candidates and lower confidence.

### Stage 3: Nested payload discovery (MSI-in-EXE / EXE-in-MSI)

Attempt non-invasive extraction/introspection:

- For MSI: inspect `File` table and embedded binaries for nested setup executables.
- For EXE: try extraction strategies (archive read, vendor-supported extract switches, layout mode where supported).
- If an internal MSI is found, prefer direct MSI install command over wrapper EXE (higher determinism).

Rules:
- Prefer direct MSI path when available and valid.
- Keep original EXE candidate as fallback.

### Stage 4: Vendor documentation lookup (support URL + optional web search)

Build targeted queries from discovered family + product metadata:

- `<product> silent install`
- `<product> unattended install`
- `<product> command line switches`
- `<product> installshield silent`

Parse only high-signal results:

- Vendor docs/release notes/enterprise deployment docs first.
- Community pages as low-confidence hints.

When docs provide exact command line, set this as top candidate and attach `SourceUrl`.

### Stage 5: Candidate ranking

Rank by weighted evidence:

- +50 exact vendor command
- +30 strong binary fingerprint
- +20 successful nested extraction
- +10 known family default
- -20 conflicting evidence
- -30 unsupported/ambiguous switches

Return:

- `RecommendedCommand`
- `AlternativeCommands[]`
- `ConfidenceScore`
- `EvidenceSummary`
- `NeedsManualReview` (true if score below threshold, e.g. <70)

## Verification strategy (must run before finalizing package)

### Verification principles

1. Never trust switch discovery without execution evidence.
2. Verify on Windows (same OS as target devices).
3. Treat "no UI + expected exit code + install artifact present" as success.

### Verification workflow

For top-ranked candidate:

1. Execute in isolated test context:
   - Prefer disposable VM/sandbox.
   - Run command with timeout and capture stdout/stderr.
2. Validate behavior:
   - No blocking UI windows.
   - Exit code in accepted set (`0`, `3010`, `1641`, `1618` as applicable).
   - Product install evidence appears (registry + file path + uninstall entry).
3. If failure or UI prompt appears:
   - Try next-ranked candidate.
   - Record reason and observed error.
4. Persist outcome in metadata for reuse.

### Reusable verification cache

Store per installer hash (e.g., SHA-256):

- `InstallerHash`
- `ProductName` / `Version`
- `VerifiedSilentCommand`
- `ExitCodeObserved`
- `VerificationDate`
- `VerificationHostInfo`

AppGetter can skip rediscovery when hash matches a previously verified installer.

## AppGetter integration design

Add a new internal module (example: `Private/SwitchDiscovery.ps1`) with:

- `Get-InstallerFingerprint`
- `Get-NestedInstallerCandidates`
- `Find-InstallerSwitchCandidates`
- `Test-InstallerCommand` (Windows-only runtime verification)
- `Resolve-InstallerInstallCommand` (final selection)

Update packaging flow:

1. Download installer.
2. Run switch discovery pipeline.
3. If confidence high and verification passes, use verified command in `install.ps1`.
4. If confidence low or verification unavailable, emit safe fallback + explicit warning in generated README.

## Fallback behavior when verification is unavailable

If AppGetter is running in Linux or no Windows verification host is configured:

- Still run Stage 1-4 and produce ranked recommendation.
- Mark command as `Unverified`.
- Include alternatives and exact evidence in generated README.
- Prefer conservative defaults:
  - MSI: `msiexec /i "<file>" /qn /norestart`
  - EXE: family-based best candidate, otherwise `"/S"` fallback with warning.

## Minimum acceptance criteria for rollout

1. Test corpus includes at least:
   - Direct MSI
   - Inno EXE
   - NSIS EXE
   - InstallShield EXE wrapping MSI
   - WiX Burn bootstrapper
   - One ambiguous/custom installer
2. Achieve target success rate:
   - >= 85% auto-detected + verified silent command on corpus.
3. Every failure yields actionable diagnostics (not silent fallback).

## Practical implementation roadmap

1. Implement static fingerprint + ranking first (fast win, no environment dependency).
2. Add nested extraction support and direct-MSI preference.
3. Add optional web lookup and source attribution.
4. Add Windows verification runner and command cache.
5. Expose confidence/evidence in GUI + CLI output so packagers can audit decisions.

## Why this method is likely to be most successful

- It combines deterministic signals (file signatures, installer-family markers, direct MSI detection) with authoritative documentation and real execution validation.
- It handles wrapper scenarios (MSI-in-EXE) that simple switch guessing misses.
- It treats verification as mandatory for "trusted" automation and gracefully degrades when verification is unavailable.
