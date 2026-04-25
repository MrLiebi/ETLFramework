[CmdletBinding()]
param(
    [string]$FrameworkRoot,
    [string]$OutputRoot,
    [string[]]$Scenario = @(),
    [string]$PowerShellHostPath,
    [switch]$PassThru
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ScriptPath = if ($PSCommandPath) {
    $PSCommandPath
}
elseif ($MyInvocation.MyCommand.Path) {
    $MyInvocation.MyCommand.Path
}
else {
    throw 'Cannot resolve script path.'
}

$ScriptRoot = if ($PSScriptRoot -and -not [string]::IsNullOrWhiteSpace($PSScriptRoot)) {
    $PSScriptRoot
}
else {
    Split-Path -Path $ScriptPath -Parent
}

. (Join-Path -Path $ScriptRoot -ChildPath 'TestHelpers.ps1')
Set-EtlFrameworkTestHostDefaults -Full

if (-not $FrameworkRoot -or [string]::IsNullOrWhiteSpace($FrameworkRoot)) {
    $FrameworkRoot = Get-FrameworkRoot -StartPath $ScriptRoot
}

if (-not $OutputRoot -or [string]::IsNullOrWhiteSpace($OutputRoot)) {
    $OutputRoot = Join-Path -Path $ScriptRoot -ChildPath 'TestResults/GeneratedProjectMatrix'
}

function Resolve-MatrixPowerShellHostPath {
    [CmdletBinding()]
    param(
        [string]$HostPath
    )

    if (-not [string]::IsNullOrWhiteSpace($HostPath)) {
        return $HostPath
    }

    $HostCandidates = New-Object System.Collections.Generic.List[string]
    if ($env:OS -eq 'Windows_NT') {
        [void]$HostCandidates.Add('powershell.exe')
    }
    [void]$HostCandidates.Add('pwsh')
    [void]$HostCandidates.Add('powershell')

    foreach ($HostCandidate in $HostCandidates) {
        $HostCommand = Get-Command -Name $HostCandidate -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($null -eq $HostCommand) {
            continue
        }

        if ($HostCommand.PSObject.Properties['Path'] -and -not [string]::IsNullOrWhiteSpace([string]$HostCommand.Path)) {
            return [string]$HostCommand.Path
        }

        return [string]$HostCommand.Name
    }

    throw 'No compatible PowerShell host found. Install Windows PowerShell 5.1 or PowerShell 7 (pwsh).'
}

function Initialize-MatrixProjectLayout {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$FrameworkRootPath,
        [Parameter(Mandatory)][string]$ProjectRoot
    )

    $RunRoot = Join-Path -Path $ProjectRoot -ChildPath 'RUN'
    $LogRoot = Join-Path -Path $ProjectRoot -ChildPath 'LOG'
    $InputRoot = Join-Path -Path $ProjectRoot -ChildPath 'INPUT'
    $OutputDataRoot = Join-Path -Path $ProjectRoot -ChildPath 'OUTPUT'
    $ModulesRoot = Join-Path -Path $RunRoot -ChildPath 'Modules'

    foreach ($Directory in @($ProjectRoot, $RunRoot, $LogRoot, $InputRoot, $OutputDataRoot, $ModulesRoot)) {
        New-Item -Path $Directory -ItemType Directory -Force | Out-Null
    }

    Copy-Item -Path (Join-Path -Path $FrameworkRootPath -ChildPath 'Templates/Runtime/Run-ETL.ps1') -Destination (Join-Path -Path $RunRoot -ChildPath 'Run-ETL.ps1') -Force
    foreach ($ModuleGroup in @('Common', 'Credential', 'Source', 'Destination')) {
        Copy-Item -Path (Join-Path -Path $FrameworkRootPath -ChildPath ("Templates/Modules/{0}" -f $ModuleGroup)) -Destination (Join-Path -Path $ModulesRoot -ChildPath $ModuleGroup) -Recurse -Force
    }
}

function Get-GeneratedProjectMatrixScenarios {
    [CmdletBinding()]
    param()

    $Scenarios = @(
        @{
            Name = 'csv_basic'
            Description = 'CSV source to CSV destination with backup'
            Setup = {
                param($ProjectRoot)
                $InputFile = Join-Path -Path $ProjectRoot -ChildPath 'INPUT/users.csv'
                "Id;Name`n1;Alice`n2;Bob" | Set-Content -Path $InputFile -Encoding UTF8
            }
            Config = {
                @'
@{
    Logging = @{
        Level = 'INFO'
        RetentionDays = 30
        ModuleLogs = $true
    }
    Pipelines = @(
        @{
            StepId = '01'
            Name = 'CsvBasic'
            StepEnabled = $true
            Source = @{
                Type = 'CSV'
                Config = @{
                    Path = 'INPUT'
                    FilePattern = 'users.csv'
                    Delimiter = ';'
                    Encoding = 'UTF8'
                    BackupAfterImport = $true
                    BackupPath = 'INPUT/_Backup'
                    DeleteAfterImport = $false
                }
            }
            Destination = @{
                Type = 'CSV'
                Config = @{
                    Path = 'OUTPUT/users_out.csv'
                    Delimiter = ';'
                    Encoding = 'UTF8'
                    Append = $false
                    Force = $true
                }
            }
            Properties = @('Id', 'Name')
        }
    )
    Adapter = @{
        AdapterEnabled = $false
    }
}
'@
            }
            Validate = {
                param($Execution)
                if ($Execution.ExitCode -ne 0) {
                    throw "Expected success exit code 0, got $($Execution.ExitCode)."
                }

                $OutputFile = Join-Path -Path $Execution.ProjectRoot -ChildPath 'OUTPUT/users_out.csv'
                if (-not (Test-Path -LiteralPath $OutputFile -PathType Leaf)) {
                    throw "Expected output file missing: $OutputFile"
                }

                $OutputText = Get-Content -Path $OutputFile -Raw
                if ($OutputText -notmatch 'Alice' -or $OutputText -notmatch 'Bob') {
                    throw 'Output file does not contain expected CSV rows.'
                }

                $BackupRoot = Join-Path -Path $Execution.ProjectRoot -ChildPath 'INPUT/_Backup'
                $BackupFiles = @(Get-ChildItem -Path $BackupRoot -Filter 'users_*.csv' -File -ErrorAction SilentlyContinue)
                if ($BackupFiles.Count -lt 1) {
                    throw 'Expected at least one backup file for CSV source.'
                }
            }
        }
        @{
            Name = 'json_rootpath'
            Description = 'JSON root path extraction to CSV'
            Setup = {
                param($ProjectRoot)
                $InputFile = Join-Path -Path $ProjectRoot -ChildPath 'INPUT/users.json'
                @'
{
  "records": [
    { "User": "Alice", "Mail": "alice@example.org" },
    { "User": "Bob",   "Mail": "bob@example.org" }
  ]
}
'@ | Set-Content -Path $InputFile -Encoding UTF8
            }
            Config = {
                @'
@{
    Logging = @{
        Level = 'INFO'
        RetentionDays = 30
        ModuleLogs = $true
    }
    Pipelines = @(
        @{
            StepId = '01'
            Name = 'JsonRootPath'
            StepEnabled = $true
            Source = @{
                Type = 'JSON'
                Config = @{
                    Path = 'INPUT/users.json'
                    Format = 'Json'
                    RootPath = 'records'
                    BackupAfterImport = $false
                    DeleteAfterImport = $false
                }
            }
            Destination = @{
                Type = 'CSV'
                Config = @{
                    Path = 'OUTPUT/users_from_json.csv'
                    Delimiter = ';'
                    Encoding = 'UTF8'
                    Append = $false
                    Force = $true
                }
            }
            Properties = @('User', 'Mail')
        }
    )
    Adapter = @{
        AdapterEnabled = $false
    }
}
'@
            }
            Validate = {
                param($Execution)
                if ($Execution.ExitCode -ne 0) {
                    throw "Expected success exit code 0, got $($Execution.ExitCode)."
                }

                $OutputFile = Join-Path -Path $Execution.ProjectRoot -ChildPath 'OUTPUT/users_from_json.csv'
                if (-not (Test-Path -LiteralPath $OutputFile -PathType Leaf)) {
                    throw "Expected output file missing: $OutputFile"
                }

                $OutputText = Get-Content -Path $OutputFile -Raw
                if ($OutputText -notmatch 'alice@example.org' -or $OutputText -notmatch 'bob@example.org') {
                    throw 'Output file does not contain expected JSON-derived rows.'
                }
            }
        }
        @{
            Name = 'xml_delete_after_import'
            Description = 'XML extraction and source deletion after import'
            Setup = {
                param($ProjectRoot)
                $InputFile = Join-Path -Path $ProjectRoot -ChildPath 'INPUT/users.xml'
                @'
<Root>
  <User><Id>1</Id><Name>Alice</Name></User>
  <User><Id>2</Id><Name>Bob</Name></User>
</Root>
'@ | Set-Content -Path $InputFile -Encoding UTF8
            }
            Config = {
                @'
@{
    Logging = @{
        Level = 'INFO'
        RetentionDays = 30
        ModuleLogs = $true
    }
    Pipelines = @(
        @{
            StepId = '01'
            Name = 'XmlDeleteAfterImport'
            StepEnabled = $true
            Source = @{
                Type = 'XML'
                Config = @{
                    Path = 'INPUT/users.xml'
                    RecordXPath = '/Root/User'
                    BackupAfterImport = $false
                    DeleteAfterImport = $true
                }
            }
            Destination = @{
                Type = 'CSV'
                Config = @{
                    Path = 'OUTPUT/users_from_xml.csv'
                    Delimiter = ';'
                    Encoding = 'UTF8'
                    Append = $false
                    Force = $true
                }
            }
            Properties = @('Id', 'Name')
        }
    )
    Adapter = @{
        AdapterEnabled = $false
    }
}
'@
            }
            Validate = {
                param($Execution)
                if ($Execution.ExitCode -ne 0) {
                    throw "Expected success exit code 0, got $($Execution.ExitCode)."
                }

                $OutputFile = Join-Path -Path $Execution.ProjectRoot -ChildPath 'OUTPUT/users_from_xml.csv'
                if (-not (Test-Path -LiteralPath $OutputFile -PathType Leaf)) {
                    throw "Expected output file missing: $OutputFile"
                }

                $SourceFile = Join-Path -Path $Execution.ProjectRoot -ChildPath 'INPUT/users.xml'
                if (Test-Path -LiteralPath $SourceFile -PathType Leaf) {
                    throw "Expected source XML file to be deleted after import: $SourceFile"
                }
            }
        }
        @{
            Name = 'missing_adapter_failure'
            Description = 'Failing scenario with missing adapter modules'
            Setup = {
                param($ProjectRoot)
            }
            Config = {
                @'
@{
    Logging = @{
        Level = 'INFO'
        RetentionDays = 30
        ModuleLogs = $true
    }
    Pipelines = @(
        @{
            StepId = '01'
            Name = 'MissingAdapter'
            StepEnabled = $true
            Source = @{
                Type = 'DoesNotExist'
                Config = @{}
            }
            Destination = @{
                Type = 'DoesNotExist'
                Config = @{}
            }
            Properties = @('*')
        }
    )
    Adapter = @{
        AdapterEnabled = $false
    }
}
'@
            }
            Validate = {
                param($Execution)
                if ($Execution.ExitCode -eq 0) {
                    throw 'Expected non-zero exit code when adapter modules are missing.'
                }

                if ($Execution.CommandOutput -notmatch 'Adapter module import failed') {
                    throw 'Expected runtime error output about adapter module import failure.'
                }
            }
        }
    )

    return $Scenarios
}

function Invoke-GeneratedProjectScenario {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][hashtable]$Definition,
        [Parameter(Mandatory)][string]$FrameworkRootPath,
        [Parameter(Mandatory)][string]$OutputRootPath,
        [Parameter(Mandatory)][string]$HostPath
    )

    $ScenarioName = [string]$Definition.Name
    $ScenarioRoot = Join-Path -Path $OutputRootPath -ChildPath $ScenarioName
    if (Test-Path -LiteralPath $ScenarioRoot) {
        Remove-Item -Path $ScenarioRoot -Recurse -Force
    }

    Initialize-MatrixProjectLayout -FrameworkRootPath $FrameworkRootPath -ProjectRoot $ScenarioRoot
    & $Definition.Setup $ScenarioRoot

    $RunRoot = Join-Path -Path $ScenarioRoot -ChildPath 'RUN'
    $ConfigPath = Join-Path -Path $RunRoot -ChildPath 'config.psd1'
    (& $Definition.Config) | Set-Content -Path $ConfigPath -Encoding UTF8

    $StopWatch = [System.Diagnostics.Stopwatch]::StartNew()
    Push-Location -Path $RunRoot
    try {
        $CommandOutput = & $HostPath -NoProfile -File (Join-Path -Path $RunRoot -ChildPath 'Run-ETL.ps1') -ConfigPath '.\config.psd1' 2>&1
    }
    finally {
        Pop-Location
    }
    $ExitCode = $LASTEXITCODE
    $StopWatch.Stop()

    $Execution = [PSCustomObject]@{
        Name          = $ScenarioName
        Description   = [string]$Definition.Description
        ProjectRoot   = $ScenarioRoot
        ExitCode      = $ExitCode
        DurationMs    = [int]$StopWatch.ElapsedMilliseconds
        CommandOutput = (($CommandOutput | Out-String).Trim())
    }

    & $Definition.Validate $Execution

    return $Execution
}

$ResolvedOutputRoot = [System.IO.Path]::GetFullPath($OutputRoot)
$null = New-Item -Path $ResolvedOutputRoot -ItemType Directory -Force
$ResolvedHostPath = Resolve-MatrixPowerShellHostPath -HostPath $PowerShellHostPath

$AllScenarios = @(Get-GeneratedProjectMatrixScenarios)
$ScenarioMap = @{}
foreach ($Definition in $AllScenarios) {
    $ScenarioMap[[string]$Definition.Name] = $Definition
}

$ScenarioNames = if (@($Scenario).Count -gt 0) {
    @($Scenario | ForEach-Object { [string]$_ } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
}
else {
    @($AllScenarios | ForEach-Object { [string]$_.Name })
}

$UnknownScenarios = @($ScenarioNames | Where-Object { -not $ScenarioMap.ContainsKey($_) })
if ($UnknownScenarios.Count -gt 0) {
    $KnownScenarios = @($AllScenarios | ForEach-Object { [string]$_.Name }) -join ', '
    throw "Unknown scenario(s): $($UnknownScenarios -join ', '). Known scenarios: $KnownScenarios"
}

$Results = New-Object System.Collections.Generic.List[object]
foreach ($ScenarioName in $ScenarioNames) {
    $Definition = $ScenarioMap[$ScenarioName]
    try {
        $Execution = Invoke-GeneratedProjectScenario -Definition $Definition -FrameworkRootPath $FrameworkRoot -OutputRootPath $ResolvedOutputRoot -HostPath $ResolvedHostPath
        $Results.Add([PSCustomObject]@{
            Name        = $Execution.Name
            Description = $Execution.Description
            Passed      = $true
            ExitCode    = $Execution.ExitCode
            DurationMs  = $Execution.DurationMs
            ProjectRoot = $Execution.ProjectRoot
            Error       = ''
        }) | Out-Null
    }
    catch {
        $Results.Add([PSCustomObject]@{
            Name        = $ScenarioName
            Description = [string]$Definition.Description
            Passed      = $false
            ExitCode    = $LASTEXITCODE
            DurationMs  = 0
            ProjectRoot = Join-Path -Path $ResolvedOutputRoot -ChildPath $ScenarioName
            Error       = $_.Exception.Message
        }) | Out-Null
    }
}

$ResultArray = @($Results.ToArray())
$FailedCount = @($ResultArray | Where-Object { -not $_.Passed }).Count
$Summary = [PSCustomObject]@{
    FrameworkRoot = $FrameworkRoot
    OutputRoot    = $ResolvedOutputRoot
    HostPath      = $ResolvedHostPath
    Total         = $ResultArray.Count
    Passed        = @($ResultArray | Where-Object { $_.Passed }).Count
    Failed        = $FailedCount
    Results       = $ResultArray
}

if ($PassThru) {
    $Summary
}
else {
    $Summary | Format-List | Out-Host
}

if ($FailedCount -gt 0) {
    exit 1
}
