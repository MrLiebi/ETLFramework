# PS ETL Framework

PowerShell-based **ETL framework** (release **23.1.0**) for repeatable data pipelines: interactive **project wizard**, modular **sources** and **destinations**, central **logging** and **validation**, optional **adapters** (e.g. Flexera), and integration with the **Windows Credential Manager**.

The framework targets **Windows PowerShell 5.1**. Run the full test suite locally on **5.1** (see [Tests (local)](#tests-local)).

---

## Table of contents

1. [Features](#features)
2. [Requirements](#requirements)
3. [Installation / source](#installation--source)
4. [Create a new ETL project](#create-a-new-etl-project)
5. [Repository layout (overview)](#repository-layout-overview)
6. [Run a pipeline](#run-a-pipeline)
7. [Scheduled execution (task)](#scheduled-execution-task)
8. [Tests (local)](#tests-local)
9. [Further documentation](#further-documentation)
10. [Versioning](#versioning)

---

## Features

| Area | Description |
|------|-------------|
| **Wizard** | Interactive new-project flow: paths, sources, destinations, credentials, adapters, schedule, configuration files (`config.psd1`, etc.). |
| **Sources** | CSV, JSON/JSONL, XML, MSSQL, LDAP, XLSX (via bundled **ExcelDataReader** assemblies), custom **script** sources. |
| **Destinations** | CSV, MSSQL (including staging/swap flows in recent releases). |
| **Common** | `Framework.Common`, `Framework.Logging`, `Framework.Validation` for consistent behavior and diagnostics. |
| **Credentials** | `Credential.Manager` for secure use of stored credentials. |
| **Adapters** | e.g. **Flexera** BAS XML; toggled via configuration (`Config.Adapter.AdapterEnabled`). |
| **Runtime** | `Run-ETL.ps1` loads configuration and modules, runs extract/load, including log rotation and run id. |
| **Quality** | Pester unit tests, PSScriptAnalyzer, coverage manifest; see [Tests (local)](#tests-local). |

---

## Requirements

| Component | Notes |
|-----------|--------|
| **Windows PowerShell** | **5.1** (target runtime; PowerShell 7 is not assumed for production wizard/runtime paths). |
| **.NET Framework** | The wizard checks/installs a suitable version (default e.g. 4.7; see parameters below). |
| **Operating system** | Windows (Credential Manager, scheduled tasks, COM/Task Scheduler depending on feature). |
| **Optional** | SQL Server access, LDAP, Excel-free XLSX via DLLs under `Templates\Modules\Dependencies\ExcelDataReader`. |

For **test execution**, modules from the PowerShell Gallery are required (see [Tests (local)](#tests-local)).

---

## Installation / source

**GitHub:**  
[https://github.com/MrLiebi/ETLFramework](https://github.com/MrLiebi/ETLFramework)

```powershell
git clone https://github.com/MrLiebi/ETLFramework.git
Set-Location .\ETLFramework
```

On disk, this is the same tree as after `git clone` or extracting a release ZIP (e.g. `PS-ETL-Framework-v23.1.0`).

---

## Create a new ETL project

Run from the **framework root** (where `New-ETLProject.ps1` lives):

```powershell
Set-Location C:\Path\To\ETLFramework
.\New-ETLProject.ps1
```

### `New-ETLProject.ps1` parameters

| Parameter | Type | Description |
|-----------|------|-------------|
| `DefaultBaseDirectory` | `string` | Default base directory for new projects (e.g. `C:\ProgramData\SoftwareOne\01_Import`). |
| `LogFileAppend` | `bool` | Append to an existing log file. |
| `RequiredDotNetVersion` | `string` | `ValidateSet`: `'4.7'`, `'4.7.1'`, `'4.7.2'`, `'4.8'`, `'4.8.1'`. |
| `RequireDotNet` | `bool` | Whether to validate .NET Framework. |
| `AllowDotNetInstall` | `bool` | Whether a missing .NET install may be offered. |
| `DotNetOfflineInstallerPath` | `string` | Optional path to an offline installer. |

The flow uses `Wizard\Helpers\Wizard.EntryPoint.ps1`, loads `Wizard\Bootstrap.ps1`, and runs orchestration in `Wizard.ProjectWizard`. Prerequisites (.NET, etc.) are handled in the wizard via `Wizard.PreReqs`.

---

## Repository layout (overview)

**In the framework repository** (excerpt):

| Path | Role |
|------|------|
| `New-ETLProject.ps1` | Entry point: new project. |
| `Wizard\` | Bootstrap and wizard helpers. |
| `Templates\` | Templates for runtime (`Run-ETL.ps1`), modules (sources/destinations/common/...), task registration. |
| `Tests\` | Pester, analyzer, and helper scripts. |
| `CHANGELOG.md` | Version history. |

A **generated project** typically includes `RUN\` (runtime), `PS\` (custom scripts), configuration (`config.psd1`), log folders, etc., depending on wizard choices.

---

## Run a pipeline

In a **generated project** (not a bare framework clone without a created project), start the pipeline with the copied **`Run-ETL.ps1`**:

```powershell
Set-Location C:\Path\To\YourProject\RUN
.\Run-ETL.ps1 -ConfigPath ".\config.psd1" -LogFileAppend $true
```

Parameters and logging are documented in the template `Templates\Runtime\Run-ETL.ps1`; the generated project uses the paths and values produced by the wizard.

---

## Scheduled execution (task)

The **`Templates\Task\Register-Task.ps1`** template registers a Windows scheduled task (Scheduled Tasks API with fallback). After project creation, a tailored copy lives in the project; run with appropriate rights (administrator depending on configuration).

---

## Tests (local)

Prerequisites: **Windows PowerShell 5.1**, access to **PSGallery**.

```powershell
Set-Location <FrameworkRoot>
.\Tests\Install-TestDependencies.ps1
```

Installs **Pester** (>= 5.5) and **PSScriptAnalyzer** (>= 1.22).

**Full run** (syntax smoke, analyzer, Pester including **code coverage**):

```powershell
.\Tests\Invoke-ExtendedFrameworkTests.ps1
```

**Faster run** without coverage XML:

```powershell
.\Tests\Invoke-ExtendedFrameworkTests.ps1 -SkipCodeCoverage
```

Output files (by default; not committed because of `.gitignore`):

- `Tests\TestResults\pester-results.xml`
- `Tests\TestResults\coverage.xml`
- `Tests\TestResults\psscriptanalyzer-results.json`

More detail on test layers: [`Tests/README-Extended.md`](Tests/README-Extended.md).  
Tester notes and coverage hints: [`Tests/TESTER-AUDIT.md`](Tests/TESTER-AUDIT.md).
`RunEtl.RuntimeSmoke.Tests.ps1` resolves a compatible external host automatically (`powershell.exe` on Windows when available, otherwise `pwsh`) so the runtime smoke layer is not tied to one executable name.

---

## Further documentation

| File | Content |
|------|---------|
| [`CHANGELOG.md`](CHANGELOG.md) | Semantic version notes and release changes. |
| [`Tests/README-Extended.md`](Tests/README-Extended.md) | Test scope and local execution of the extended test harness. |
| [`Tests/TESTER-AUDIT.md`](Tests/TESTER-AUDIT.md) | Compact audit checklist for coverage and intentionally non-automated entry scripts. |

---

## Versioning

Current release line in the repository: **23.1.0** (see `CHANGELOG.md` and comments in entry scripts).
Repository-internal release traceability is tracked in `ReleaseManifest.psd1` (version, intended tag, release commit, release URL).

### GitHub releases (required practice)

Whenever you finish a **local framework release** (version numbers and `CHANGELOG.md` updated on `main`), also publish it on GitHub so others can find binaries, notes, and an exact Git ref:

1. Commit and push the release changes to `main`.
2. Create an **annotated tag** for that commit, e.g. `git tag -a v23.1.0 -m "PS ETL Framework 23.1.0"` then `git push origin v23.1.0`.
3. On GitHub, open **[Releases](https://github.com/MrLiebi/ETLFramework/releases)** → **Draft a new release** → choose that tag → set the title (e.g. `23.1.0`) → paste the matching **CHANGELOG** section into the description → **Publish release**.

Optional: attach a ZIP of the framework folder for users who do not use `git clone`. Do **not** move or reuse a tag after publish; create a new patch version instead.

---

## Author

Framework maintenance and wizard refactoring by **Alexander Liebold**; see also `New-ETLProject.ps1` and GitHub commit history.

---

## License

There is currently **no** `LICENSE` file in the repository. For public use, adding an explicit license is recommended; until then, default copyright rules apply.
