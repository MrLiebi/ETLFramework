# Changelog

All notable changes to this ETL Framework are documented in this file.
This project follows semantic versioning.
Documentation and in-script comments and user-visible strings use **American English** spelling (for example *behavior*, *recognize*, *finalize*).

## [23.1.0] - 2026-04-24

### Release reference
- Release metadata for this version is tracked in `ReleaseManifest.psd1` (`Version=23.1.0`, `Tag=v23.1.0`, `ReleaseCommit=c8f9592`) to keep repository-internal traceability even before tag/release publication is externally visible.

### Added
- Added non-interactive runtime smoke tests for `Templates/Runtime/Run-ETL.ps1` that validate both a successful end-to-end pipeline execution and a failing adapter-import path.
- Added dynamic wizard adapter-template discovery helpers so source/destination options are resolved from available `Source.*.psm1` and `Destination.*.psm1` templates.

### Changed
- Hardened MSSQL source and destination credential handling by creating SQL connections with `SqlCredential` for `CredentialManager` mode instead of constructing password-bearing connection strings.
- Updated wizard step configuration flow to use dynamically discovered source/destination type lists instead of hard-coded option arrays.
- Expanded unit coverage for MSSQL connection construction and wizard template discovery, and updated tester documentation to include the runtime smoke layer.
- Bumped the framework release line to **23.1.0** across entry scripts, templates, runtime modules, wizard banner, and documentation.

---

## [23.0.0] - 2026-04-23

### Changed
- Bumped the framework release line to **23.0.0** (Release 23) across entry scripts, templates, runtime modules, wizard banner, and documentation.

---

## [22.0.0] - 2026-04-21

### Added
- Unit tests for **`Source.LDAP`** and **`Source.XLSX`** that exercise early `Invoke-Extract` configuration validation (no directory service or Excel runtime required).
- Coverage manifest entries so LDAP and XLSX sources participate in the same **Unit** coverage tracking as other high-value modules.

### Changed
- Raised the framework release line to **22.0.0** (Release 22) across templates, runtime, wizard banner, and entry scripts.
- Removed Git-specific artifacts from the framework tree (for example `.gitignore` and the former `New-ReleaseCommit.ps1` helper).
- Extended framework test runner: **Pester code coverage is on by default**; use **`-SkipCodeCoverage`** for a faster run without `coverage.xml`.
- **`Tests/README-Extended.md`**: documented default coverage behavior, the new switch, and LDAP/XLSX in the covered-components list.
- **`Wizard.ProjectWizard` tests**: each `BeforeEach` restores **`Set-EtlFrameworkTestHostDefaults -Full`** so wizard automation env vars stay consistent with mocked `Read-Host` (avoids fragile `Read-Choice` loops when another test temporarily disables automation).

---

## [21.2.5] - 2026-04-21

### Added
- Expanded unit coverage for `Destination.MSSQL`, `Source.MSSQL`, and the already-loaded assembly branch in `Framework.Common`.
- Added direct tests for SQL identifier/literal helpers, MSSQL connection-string branches, and core value-conversion helpers.

### Changed
- Updated tester documentation and coverage manifest notes to reflect the broader unit coverage set.

---

## [21.2.4] - 2026-04-20

### Fixed
- Hardened MSSQL destination SQL literal handling for table drop and staging swap operations.
- Replaced the task registration path with a ScheduledTasks-first implementation and kept COM as fallback.
- Removed a few silent failure paths in the runtime and framework helpers.
- Corrected wizard config rendering so numeric retention values stay numeric in generated PSD1 files.
- Tightened CSV header detection to normalize BOM-prefixed headers before comparison.
- Restricted Flexera adapter import discovery to imports directly under the `<Imports>` container so nested or auxiliary `<Import>` nodes are no longer treated as runnable entries.

### Changed
- Kept the framework release line aligned across templates, runtime, wizard, and tests.

---

## [21.2.1] - 2026-04-16

### Changed
- Refactored `New-ETLProject.ps1` into a thin entry-point wrapper with bootstrap helpers.
- Moved the former prerequisite workflow fully into `Wizard/Helpers/Wizard.PreReqs.ps1` and removed the separate setup entry path.
- Added unit tests for the new wrapper/helper layers and wizard prerequisite flow.

## [20.0.0] - 2026-04-14

### Additional framework updates before final testing
- Custom source scripts are now copied into a project-root `PS` directory instead of `RUN\CustomScripts`.
- Added file-based source modules for `XML` and `JSON`/`JSONL` including wizard support and post-import file handling.
- Updated `Config.Adapter.AdapterEnabled` generation to emit PowerShell booleans (`$true` / `$false`) instead of string literals.

### Changed
- Finalized the framework as the consolidated production release `20.0.0`.
- Unified version metadata across the framework entry scripts, runtime, templates, setup scripts, wizard components, and modules.
- Cleaned and consolidated the changelog to remove duplicate sections, obsolete intermediate notes, and inconsistent version markers.

### Breaking Changes
- Standardized the adapter configuration switch on `Config.Adapter.AdapterEnabled`.
- Removed the requirement to register scheduled tasks through `schtasks.exe` with a password on the command line.
- Replaced hidden runtime-only credential coupling with explicit credential module imports in adapters that require stored credentials.

### Security
- Reworked scheduled task registration to use the Windows Task Scheduler COM API instead of exposing the run-as password in process arguments.
- Preserved secure credential handling by preventing repeated Credential Manager interop type registration and by keeping credential retrieval out of configuration output.

### Stability
- Fixed LDAP module assembly fallback handling so module import no longer fails because logging is called before initialization.
- Hardened Credential Manager support to remain idempotent across repeated imports during wizard execution.
- Added deterministic overwrite cleanup in the wizard before regenerating project artifacts.
- Added transactional MSSQL load protection for standard loads and staging-table swap protection for `DropCreate = True` loads.
- Improved MSSQL destination schema inference by unioning buffered sample columns instead of relying on the first row only.
- Kept backward compatibility for legacy projects that still use `Config.Adapter.Enabled`.

## [19.0.1] - 2026-04-14

### Changed
- Renamed the adapter configuration switch from `Config.Adapter.Enabled` to `Config.Adapter.AdapterEnabled` for configuration consistency.
- Updated the wizard scaffolding and generated `config.psd1` output to emit `AdapterEnabled` for the adapter section.
- Kept runtime compatibility for legacy projects that still use `Config.Adapter.Enabled`.

## [19.0.0] - 2026-04-14

### Fixed
- Fixed LDAP assembly fallback logging so the module no longer calls `Write-ModuleLog` before the function exists.
- Hardened credential support loading by making source and destination adapters import the credential module explicitly when required.
- Made Credential Manager interop idempotent to prevent `Add-Type` collisions during repeated wizard credential initialization.
- Reworked scheduled-task registration to use the Windows Task Scheduler COM API instead of passing the password to `schtasks.exe` on the command line.
- Added deterministic overwrite cleanup in the project wizard by removing previously generated `RUN` and `TASK` artifacts before regeneration.
- Improved MSSQL destination schema inference by unioning column names across the buffered sample instead of relying on the first row only.
- Added transaction-based protection for `DropCreate = False` loads and staging-table swap protection for `DropCreate = True` loads so failed runs do not leave partially loaded targets behind.
- Bumped the entire framework, templates, setup scripts, and release metadata to `19.0.0`.
