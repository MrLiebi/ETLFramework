# PS ETL Framework

[![CI](https://github.com/MrLiebi/ETLFramework/actions/workflows/ci.yml/badge.svg)](https://github.com/MrLiebi/ETLFramework/actions/workflows/ci.yml)

PowerShell-based **ETL framework** (release **22.x**) for repeatable data pipelines: interactive **project wizard**, modular **sources** and **destinations**, central **logging** and **validation**, optional **adapters** (e.g. Flexera), and integration with the **Windows Credential Manager**.

The framework targets **Windows PowerShell 5.1**. GitHub **CI** runs the full test suite on **5.1** as well.

Documentation, comments, and user-visible messages use **American English** spelling (for example *behavior*, *recognize*, *finalize*).

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
9. [Continuous integration (GitHub)](#continuous-integration-github)
10. [Further documentation](#further-documentation)
11. [Versioning](#versioning)

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

On disk, this is the same tree as after `git clone` or extracting a release ZIP (e.g. `PS-ETL-Framework-v22.0.0`).

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

---

## Continuous integration (GitHub)

On **push** and **pull request** to `main`, [`.github/workflows/ci.yml`](.github/workflows/ci.yml):

1. Checkout  
2. `Tests\Install-TestDependencies.ps1` under **Windows PowerShell 5.1**  
3. `Tests\Invoke-ExtendedFrameworkTests.ps1` (analyzer + Pester + coverage)  
4. On failure: uploads `Tests\TestResults\` as an artifact named `test-results-<run_id>`, kept **7 days** (then GitHub deletes it automatically).

Status badge at the top of this README.

To remove old workflow runs from GitHub: **Actions** → **CI** → select runs → **…** → **Delete**. That only affects GitHub metadata and artifacts, not your local clone.

---

## Further documentation

| File | Content |
|------|---------|
| [`CHANGELOG.md`](CHANGELOG.md) | Semantic version notes, breaking changes, security and stability fixes. |
| [`Tests/README-Extended.md`](Tests/README-Extended.md) | Test harness architecture, coverage, PSScriptAnalyzer 1.25.x compatibility. |
| [`Tests/TESTER-AUDIT.md`](Tests/TESTER-AUDIT.md) | Audit summary, scripts intentionally not executed in automation. |

---

## Versioning

Current release line in the repository: **22.0.0** (see `CHANGELOG.md` and comments in entry scripts). Use Git **tags** or release branches on GitHub for reproducible snapshots.

---

## Author

Framework maintenance and wizard refactoring by **Alexander Liebold**; see also `New-ETLProject.ps1` and GitHub commit history.

---

## License

There is currently **no** `LICENSE` file in the repository. For public use, adding an explicit license is recommended; until then, default copyright rules apply.
