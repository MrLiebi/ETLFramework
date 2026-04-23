# Tester audit

All prose in this document uses **American English** spelling, consistent with the rest of the framework repository.

## Cleaned up

- More robust script path resolution in the runner  
- Unified analyzer targets  
- Legacy `ExcludePath` usage remains removed  
- Replaced obsolete root analyzer invocation in the Pester smoke test  
- Structural fixes for tests-only vs merged package layouts  

## Completeness

- All 34 framework source artifacts (`.ps1` / `.psm1`) are listed in `CoverageManifest.psd1`  
- All 15 modules (`.psm1`) are included in the export/import smoke test  
- Additional unit suites for `Source.XML`, `Source.CustomScript`, `Source.MSSQL`, `Destination.MSSQL`, `Wizard.Adapter`, `Wizard.Schedule`, `Wizard.Logging`  

## Intentionally not executed in automation

- `New-ETLProject.ps1`  
- `Templates/Runtime/Run-ETL.ps1`  
- `Templates/Task/Register-Task.ps1`  
- `Wizard/Helpers/Wizard.PreReqs.ps1` (direct unit tests and indirect wizard flow only; no real installer execution)  

These entry scripts are interactive or have system/admin/COM side effects and are therefore covered via syntax, analyzer, and manifest checks.

## Note

The review here was static and package-focused. **GitHub Actions** now runs the full suite on **Windows PowerShell 5.1** on every push/PR (see `.github/workflows/ci.yml`).

## Latest compatibility fixes

- Added central `Invoke-ScriptAnalyzerCompat` helper so file lists work with `PSScriptAnalyzer 1.25.x` on systems where `-Path` effectively accepts only a single string.  
- Runner and Pester smoke test now share the same compatible analyzer invocation.  

- Fixed parser issues in `Sort-ScriptAnalyzerFindings`; invalid Linux-style line continuations were replaced with valid PowerShell property arrays.  
- Reduced duplicate analyzer runs: `Smoke/ScriptAnalyzer.Tests.ps1` remains available for standalone Pester but is excluded by tag from the central runner.  
