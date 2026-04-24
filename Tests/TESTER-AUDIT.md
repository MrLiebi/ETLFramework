# Tester audit

All prose in this document uses **American English** spelling, consistent with the rest of the framework repository.

This note lists what is currently verified by automated tests and what is intentionally excluded because of interactive/system side effects.

## Covered in automation

- Syntax/parsing checks for framework scripts and modules.
- PSScriptAnalyzer checks via the central runner configuration.
- Module import/export smoke tests for `.psm1` modules.
- Unit and near-integration tests for core modules and wizard helpers.
- Dedicated non-interactive runtime smoke tests for `Run-ETL.ps1`.

Reference: `Tests/CoverageManifest.psd1`.

## Intentionally not executed in automation

- `New-ETLProject.ps1`  
- `Templates/Runtime/Run-ETL.ps1` (full production flow is not executed directly; a dedicated mocked runtime smoke test validates non-interactive orchestration behavior via `powershell.exe` when available and falls back to `pwsh`)  
- `Templates/Task/Register-Task.ps1`  
- `Wizard/Helpers/Wizard.PreReqs.ps1` (direct unit tests and indirect wizard flow only; no real installer execution)  

These entry scripts are interactive or have system/admin/COM side effects and are therefore covered via syntax, analyzer, and manifest checks. For `Run-ETL.ps1`, a dedicated non-interactive runtime smoke test additionally validates orchestration behavior and exit-code handling with host selection that works on both Windows PowerShell and PowerShell 7 environments.

## Note

Run the full suite locally with `Tests\Invoke-ExtendedFrameworkTests.ps1` on **Windows PowerShell 5.1** (this repository does not define GitHub Actions workflows).
