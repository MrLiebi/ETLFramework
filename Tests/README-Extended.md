
# Extended test harness for the PS ETL framework

This document describes the **current** automated test setup used by the framework.

## Test layers

The suite validates the framework on four levels:

1. Parser/syntax smoke tests for all `.ps1` and `.psm1` files  
2. `PSScriptAnalyzer` checks via `PSScriptAnalyzerSettings.psd1`  
3. Module import/export smoke tests for runtime and wizard modules  
4. Unit and near-integration tests for high-value helpers and adapters  

`Run-ETL.ps1` is additionally covered by a non-interactive smoke test with mocked adapters.  
The smoke test resolves a compatible external host automatically (`powershell.exe` on Windows when available, otherwise `pwsh`/`powershell`).

## Run locally

```powershell
Set-Location <FrameworkRoot>
.\Tests\Install-TestDependencies.ps1
.\Tests\Invoke-ExtendedFrameworkTests.ps1
# Optional: faster run without coverage output
# .\Tests\Invoke-ExtendedFrameworkTests.ps1 -SkipCodeCoverage
```

## Output artifacts

By default the runner writes to `Tests\TestResults`:

- `pester-results.xml`  
- `coverage.xml`  
- `psscriptanalyzer-results.json`  

## Coverage scope (high level)

Covered directly by unit and smoke tests include:

- Common modules: `Framework.Common`, `Framework.Logging`, `Framework.Validation`
- Source modules: CSV, JSON, XML, CustomScript, MSSQL, LDAP (config gates), XLSX (config gates)
- Destination modules: CSV, MSSQL
- Wizard helpers and wizard logging module
- Module import/export smoke for all framework `.psm1` modules

Interactive or side-effect-heavy entry scripts (`New-ETLProject.ps1`, `Register-Task.ps1`) are validated via syntax/analyzer/manifest checks instead of full automated execution.
