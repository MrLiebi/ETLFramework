
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

## Generated project matrix environment

To validate generated project layouts with different runtime configs, use the matrix runner:

```powershell
Set-Location <FrameworkRoot>
.\Tests\Invoke-GeneratedProjectMatrix.ps1
```

Default scenarios:

- `csv_basic` (CSV -> CSV, backup after import)
- `json_rootpath` (JSON with `RootPath` -> CSV)
- `xml_delete_after_import` (XML -> CSV, delete source after import)
- `missing_adapter_failure` (expected runtime failure path for missing adapters)

Run only selected scenarios:

```powershell
.\Tests\Invoke-GeneratedProjectMatrix.ps1 -Scenario @('csv_basic','missing_adapter_failure')
```

Artifacts are written below `Tests\TestResults\GeneratedProjectMatrix`, one isolated generated project per scenario.

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
