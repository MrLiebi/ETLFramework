
# Extended test harness for the PS ETL framework

All prose in this document uses **American English** spelling, consistent with the rest of the framework repository.

This test package validates the framework on four levels:

1. **Parser / syntax smoke tests** for all `.ps1` and `.psm1` files  
2. **PSScriptAnalyzer** using settings compatible with `PSScriptAnalyzer 1.25.x`  
3. **Module / export smoke tests** for all importable runtime and wizard modules  
4. **Unit and near-integration tests** for core helpers and adapters  

## Cleanups vs. older versions

- No obsolete `ExcludePath` usage in `PSScriptAnalyzerSettings.psd1`  
- The central runner excludes the standalone analyzer smoke test by tag so analyzer findings are not produced twice  
- No legacy analyzer invocation with root `-Recurse` in the Pester smoke test  
- More robust runner without relying on empty `$PSScriptRoot` in default parameters  
- Additional **completeness check** via `CoverageManifest.psd1`  

## Coverage

Covered directly by unit and smoke tests, including:

- `Framework.Common`  
- `Framework.Logging`  
- `Framework.Validation`  
- `Source.CSV`  
- `Source.JSON`  
- `Source.XML`  
- `Source.CustomScript`  
- `Source.MSSQL`  
- `Source.LDAP` (configuration gates)  
- `Source.XLSX` (configuration gates)  
- `Destination.CSV`  
- `Destination.MSSQL`  
- `Wizard.Config`  
- `Wizard.Paths`  
- `Wizard.Adapter`  
- `Wizard.Schedule`  
- `Wizard.Logging`  
- Module import/export for all `.psm1` modules  

Interactive or side-effect-heavy entry scripts such as `New-ETLProject.ps1` and `Register-Task.ps1` are guarded via **syntax + analyzer + coverage manifest** instead of being executed automatically in the test run.
`Run-ETL.ps1` additionally has a non-interactive smoke test with mocked source/destination adapters to validate runtime orchestration and exit behavior without external systems.

## Run locally

```powershell
Set-Location <FrameworkRoot>
.\Tests\Install-TestDependencies.ps1
# Code coverage is on by default (coverage.xml under Tests\TestResults).
.\Tests\Invoke-ExtendedFrameworkTests.ps1
# Faster run without coverage:
# .\Tests\Invoke-ExtendedFrameworkTests.ps1 -SkipCodeCoverage
```

## Output

By default the runner writes to `Tests\TestResults`:

- `pester-results.xml`  
- `coverage.xml`  
- `psscriptanalyzer-results.json`  

## Compatibility fixes

- Central `Invoke-ScriptAnalyzerCompat` helper so file lists work with `PSScriptAnalyzer 1.25.x` on systems where `-Path` effectively accepts only a single string.  
- Runner and Pester smoke test now share the same compatible analyzer invocation.  

## Extended coverage

Additional mock/filesystem tests cover `Wizard.ProjectFiles`, `Wizard.FileSources`, `Wizard.Prompts`, `Wizard.Credentials`, `Wizard.Sources`, `Wizard.Destinations`, `Wizard.LogFacade`, `Destination.MSSQL`, `Source.MSSQL`, plus a bootstrap loader test.

Further wizard helper coverage includes:

- `Wizard.CustomScript`  
- `Read-AdapterConfiguration`  
- `Read-ScheduleConfiguration`  
- `New-TaskRegistrationScriptFile`  
- `Test-PathExists` / `Wizard.PreReqs` helper functions  
- `Read-NonNegativeInteger` / `Read-ValidatedTimeValue`  

## Framework 21.2.4 refactoring

For 21.2.4 the two large script entry points were decoupled:

- `New-ETLProject.ps1` now uses testable bootstrap / entry-point helpers  
- Separate `Setup` prerequisite orchestration was removed; .NET / runtime checks and optional installation run entirely in the wizard  

Additional unit tests cover `Wizard.EntryPoint` and `Wizard/Helpers/Wizard.PreReqs.ps1`.
