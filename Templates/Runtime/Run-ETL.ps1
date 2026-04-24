<#
.SYNOPSIS
Executes an ETL pipeline.

.DESCRIPTION
Main entry point for running ETL pipelines. Loads configuration,
imports required modules, executes extract and load phases, and
handles logging and error management.

.VERSION
1.0

.AUTHOR
ETL Framework

.PARAMETER ConfigPath
Path to the ETL configuration file.

.PARAMETER LogFile
Path to the log file.

.PARAMETER LogLevel
Logging level (INFO, DEBUG, WARN, ERROR).

.PARAMETER LogFileAppend
Indicates whether logs should be appended.

.NOTES
- Central runtime controller
- Loads Common and adapter modules via the modules layer
- Executes pipeline steps
- User-visible and log messages use American English spelling

.DEPENDENCIES
- Framework.Common.psm1
- Credential.Manager.psm1
#>

[CmdletBinding()]
param(
    [string] $ConfigPath = ".\config.psd1",
    [bool]   $LogFileAppend = $true
)

$ErrorActionPreference         = 'Stop'
$StopWatch                     = [System.Diagnostics.Stopwatch]::StartNew()

$ScriptDirectory               = Split-Path -Path $MyInvocation.MyCommand.Path -Parent
$ProjectRootPath               = Split-Path -Path $ScriptDirectory -Parent
$ScriptName                    = (Get-Item -Path $MyInvocation.MyCommand.Path).BaseName
$BuildDate                     = (Get-Item -Path $MyInvocation.MyCommand.Path).LastWriteTime.ToString("yyyy-MM-dd")

$ResolvedConfigPath            = if ([System.IO.Path]::IsPathRooted($ConfigPath)) {
    [System.IO.Path]::GetFullPath($ConfigPath)
} else {
    [System.IO.Path]::GetFullPath((Join-Path -Path $ScriptDirectory -ChildPath $ConfigPath))
}

$LogDirectory                  = Join-Path -Path $ProjectRootPath -ChildPath "LOG"
$Script:RunId                  = Get-Date -Format 'yyyyMMdd_HHmmss'
$LogFile                       = Join-Path -Path $LogDirectory -ChildPath ("{0}_01_{1}.log" -f $Script:RunId, $ScriptName)
$LogFileRetentionDays          = 30

$LoggingModulePath             = Join-Path -Path $ScriptDirectory -ChildPath 'Modules\Common\Framework.Logging.psm1'
$FlexeraModulePath             = Join-Path -Path $ScriptDirectory -ChildPath 'Modules\Adapter\Adapter.Flexera.psm1'
Import-Module -Name $LoggingModulePath -Force -ErrorAction Stop
if (Test-Path -Path $FlexeraModulePath -PathType Leaf) { Import-Module -Name $FlexeraModulePath -Force -ErrorAction Stop }
$Script:LogContext             = Initialize-EtlScriptLogContext -LogDirectory $LogDirectory -LogFile $LogFile -LogLevel 'INFO' -RetentionDays $LogFileRetentionDays -Append $LogFileAppend -CleanupKey ('Runtime::{0}' -f $ScriptName)

function Test-AdapterExecutionEnabled {
    [CmdletBinding()]
    param(
        [AllowNull()] $AdapterConfig
    )

    if ($null -eq $AdapterConfig) {
        return $false
    }

    $AdapterEnabledValue = $null
    if ($AdapterConfig -is [hashtable] -or $AdapterConfig -is [System.Collections.Specialized.OrderedDictionary]) {
        if ($AdapterConfig.Contains('AdapterEnabled')) {
            $AdapterEnabledValue = $AdapterConfig['AdapterEnabled']
        }
        elseif ($AdapterConfig.Contains('Enabled')) {
            $AdapterEnabledValue = $AdapterConfig['Enabled']
        }
    }
    elseif ($AdapterConfig.PSObject.Properties['AdapterEnabled']) {
        $AdapterEnabledValue = $AdapterConfig.AdapterEnabled
    }
    elseif ($AdapterConfig.PSObject.Properties['Enabled']) {
        $AdapterEnabledValue = $AdapterConfig.Enabled
    }

    $AdapterEnabledText = [string]$AdapterEnabledValue
    return ($AdapterEnabledText -match '^(?i:true|1|yes|y)$')
}

function Test-LogLevelEnabled {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateSet('DEBUG','INFO','WARN','ERROR')][string] $ConfiguredLevel,
        [Parameter(Mandatory)][ValidateSet('DEBUG','INFO','WARN','ERROR')][string] $MessageLevel
    )

    Test-EtlLogLevelEnabled -ConfiguredLevel $ConfiguredLevel -MessageLevel $MessageLevel
}

function Write-Log {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)][string] $Message,
        [ValidateSet("DEBUG", "INFO", "WARN", "ERROR")][string] $Level = "INFO",
        [ValidateRange(1, 3650)][int] $RetentionDays = $LogFileRetentionDays
    )

    if ($Script:LogContext) {
        $Script:LogContext.RetentionDays = $RetentionDays
        if ($env:ETL_LOG_LEVEL) {
            $Script:LogContext.LogLevel = ([string]$env:ETL_LOG_LEVEL).ToUpperInvariant()
        }
    }

    $WriteEtlScriptLogCommand = Get-Command -Name 'Write-EtlScriptLog' -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($WriteEtlScriptLogCommand -and $Script:LogContext) {
        & $WriteEtlScriptLogCommand -Context $Script:LogContext -Message $Message -Level $Level
        return
    }

    $Timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $Entry = "$Timestamp [$Level] $Message"

    try {
        if (-not (Test-Path -Path $LogDirectory -PathType Container)) {
            New-Item -Path $LogDirectory -ItemType Directory -Force | Out-Null
        }
        Add-Content -Path $LogFile -Value $Entry
    }
    catch {
        Write-Verbose "Failed to append runtime log entry: $($_.Exception.Message)"
    }

    switch ($Level) {
        'ERROR' { Write-Warning $Entry }
        'WARN'  { Write-Warning $Entry }
        default { Write-Information -MessageData $Entry -InformationAction Continue }
    }
}

function Test-PathExists {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $Path,
        [Parameter(Mandatory)][ValidateSet('Leaf','Container')] [string] $PathType,
        [Parameter(Mandatory)][string] $Description
    )

    if (-not (Test-Path -Path $Path -PathType $PathType)) {
        Write-Log "$Description not found: $Path" -Level "ERROR"
        return $false
    }

    Write-Log "$Description validated: $Path" -Level "INFO"
    return $true
}

function Get-NormalizedPipelines {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][hashtable] $Config
    )

    $NormalizedPipelines = New-Object System.Collections.Generic.List[hashtable]

    if ($Config.ContainsKey('Pipelines')) {
        $Index = 0
        foreach ($Pipeline in @($Config.Pipelines)) {
            $Index++

            if ($null -eq $Pipeline) {
                throw "Pipeline entry at position $Index is null."
            }

            $StepId = if ($Pipeline.StepId) { [string]$Pipeline.StepId } else { "{0:D2}" -f $Index }
            $Name   = if ($Pipeline.Name)   { [string]$Pipeline.Name }   else { "Step-$StepId" }

            $NormalizedPipelines.Add(@{
                StepId      = $StepId
                Name        = $Name
                StepEnabled = ConvertTo-BooleanValue -Value $Pipeline.StepEnabled -Default $true
                Source      = $Pipeline.Source
                Destination = $Pipeline.Destination
                Properties  = @($Pipeline.Properties)
            })
        }
    }
    elseif ($Config.ContainsKey('Source') -and $Config.ContainsKey('Destination') -and $Config.ContainsKey('Properties')) {
        $NormalizedPipelines.Add(@{
            StepId      = '01'
            Name        = 'Default'
            StepEnabled = ConvertTo-BooleanValue -Value $Config.StepEnabled -Default $true
            Source      = $Config.Source
            Destination = $Config.Destination
            Properties  = @($Config.Properties)
        })
    }
    else {
        throw "Missing config section: Pipelines or legacy Source/Destination/Properties."
    }

    return @(
        $NormalizedPipelines.ToArray() |
            Sort-Object @{
                Expression = {
                    $StepIdText = [string]$_.StepId
                    $StepIdNumber = 0
                    if ([int]::TryParse($StepIdText, [ref]$StepIdNumber)) {
                        return $StepIdNumber
                    }

                    return [int]::MaxValue
                }
            }, @{ Expression = { [string]$_.StepId } }
    )
}

function Test-EtlConfiguration {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][hashtable] $Config
    )

    try {
        $ResolvedPipelines = Get-NormalizedPipelines -Config $Config

        if (-not $ResolvedPipelines -or $ResolvedPipelines.Count -eq 0) {
            throw "No ETL pipelines defined."
        }

        foreach ($Pipeline in $ResolvedPipelines) {
            if (-not $Pipeline.StepEnabled) {
                Write-Log ("Step [{0}] is disabled in config. Validation of Source/Destination settings is skipped." -f $Pipeline.StepId) -Level "INFO"
                continue
            }

            if (-not $Pipeline.Source)             { throw "Missing config value: Pipeline[$($Pipeline.StepId)].Source" }
            if (-not $Pipeline.Destination)        { throw "Missing config value: Pipeline[$($Pipeline.StepId)].Destination" }
            if (-not $Pipeline.Properties)         { throw "Missing config value: Pipeline[$($Pipeline.StepId)].Properties" }

            if (-not $Pipeline.Source.Type)        { throw "Missing config value: Pipeline[$($Pipeline.StepId)].Source.Type" }
            if (-not $Pipeline.Source.Config)      { throw "Missing config value: Pipeline[$($Pipeline.StepId)].Source.Config" }
            if (-not $Pipeline.Destination.Type)   { throw "Missing config value: Pipeline[$($Pipeline.StepId)].Destination.Type" }
            if (-not $Pipeline.Destination.Config) { throw "Missing config value: Pipeline[$($Pipeline.StepId)].Destination.Config" }
        }

        if ($Config.ContainsKey('Adapter') -and $Config.Adapter -and (Test-AdapterExecutionEnabled -AdapterConfig $Config.Adapter)) {
            if (-not $Config.Adapter.ConfigFile) {
                throw "Missing config value: Adapter.ConfigFile"
            }
        }

        Write-Log "ETL configuration structure validated successfully." -Level "INFO"
        return $true
    }
    catch {
        Write-Log "ETL configuration validation failed: $($_.Exception.Message)" -Level "ERROR"
        return $false
    }
}

function Import-EtlSupportModules {
    [CmdletBinding()]
    param()

    $SupportModules = @(
        @{
            Name        = 'Common'
            Path        = Join-Path -Path $ScriptDirectory -ChildPath 'Modules\Common\Framework.Common.psm1'
            Description = 'Common runtime support module'
        },
        @{
            Name        = 'Credential'
            Path        = Join-Path -Path $ScriptDirectory -ChildPath 'Modules\Credential\Credential.Manager.psm1'
            Description = 'Credential support module'
        }
    )

    foreach ($SupportModule in $SupportModules) {
        if (-not (Test-PathExists -Path $SupportModule.Path -PathType Leaf -Description $SupportModule.Description)) {
            throw "Support module missing: $($SupportModule.Path)"
        }

        Import-Module -Name $SupportModule.Path -Force -ErrorAction Stop
        Write-Log "$($SupportModule.Name) support module imported successfully: $($SupportModule.Path)" -Level 'INFO'
    }
}

function Import-EtlAdapterModule {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateSet('Source','Destination')] [string] $AdapterRole,
        [Parameter(Mandatory)][string] $AdapterType
    )

    try {
        $ModulePath = Join-Path -Path $ScriptDirectory -ChildPath ("Modules\{0}\{0}.{1}.psm1" -f $AdapterRole, $AdapterType)

        if (-not (Test-PathExists -Path $ModulePath -PathType Leaf -Description "$AdapterRole adapter module")) {
            return $null
        }

        $ImportedModule = Import-Module -Name $ModulePath -Force -PassThru -ErrorAction Stop
        Write-Log "$AdapterRole adapter imported successfully: Type=$AdapterType | Path=$ModulePath" -Level "INFO"
        return $ImportedModule
    }
    catch {
        Write-Log "Failed to import $AdapterRole adapter [$AdapterType]: $($_.Exception.Message)" -Level "ERROR"
        return $null
    }
}

function Import-EtlAdapterModules {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][array] $Pipelines
    )

    $ImportedModules = @{}
    $RequiredModules = New-Object System.Collections.Generic.List[hashtable]
    $Seen = @{}

    foreach ($Pipeline in @($Pipelines | Where-Object { $_.StepEnabled })) {
        foreach ($ModuleInfo in @(
            @{ Role = 'Source';      Type = [string]$Pipeline.Source.Type },
            @{ Role = 'Destination'; Type = [string]$Pipeline.Destination.Type }
        )) {
            $Key = "{0}|{1}" -f $ModuleInfo.Role, $ModuleInfo.Type
            if (-not $Seen.ContainsKey($Key)) {
                $Seen[$Key] = $true
                $RequiredModules.Add($ModuleInfo)
            }
        }
    }

    foreach ($ModuleInfo in $RequiredModules) {
        $ImportedModule = Import-EtlAdapterModule -AdapterRole $ModuleInfo.Role -AdapterType $ModuleInfo.Type
        if (-not $ImportedModule) {
            return $null
        }

        $Key = "{0}|{1}" -f $ModuleInfo.Role, $ModuleInfo.Type
        $ImportedModules[$Key] = $ImportedModule
    }

    return $ImportedModules
}

function Get-EtlAdapterCommand {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][hashtable] $ImportedModules,
        [Parameter(Mandatory)][ValidateSet('Source','Destination')] [string] $AdapterRole,
        [Parameter(Mandatory)][string] $AdapterType,
        [Parameter(Mandatory)][ValidateSet('Invoke-Extract','Invoke-Load')] [string] $CommandName
    )

    $Key = "{0}|{1}" -f $AdapterRole, $AdapterType

    if (-not $ImportedModules.ContainsKey($Key)) {
        throw "Imported module not found for $Key"
    }

    $Module = $ImportedModules[$Key]

    if (-not $Module) {
        throw "Imported module instance is null for $Key"
    }

    if ($Module.ExportedCommands -and $Module.ExportedCommands.ContainsKey($CommandName)) {
        return $Module.ExportedCommands[$CommandName]
    }

    $Command = Get-Command -Name $CommandName -ErrorAction SilentlyContinue |
        Where-Object {
            $_.Source -eq $Module.Name -or
            $_.ModuleName -eq $Module.Name
        } |
        Select-Object -First 1

    if (-not $Command) {
        throw "Command '$CommandName' not found in module '$($Module.Name)'"
    }

    return $Command
}

function Initialize-ModuleRuntimeContext {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][hashtable] $Config
    )

    $env:ETL_RUN_ID = $Script:RunId
    $env:ETL_LOG_ROOT = $LogDirectory
    $env:ETL_PROJECT_ROOT = $ProjectRootPath

    if ($Config.Logging -and $Config.Logging.RetentionDays) {
        $env:ETL_LOG_RETENTION_DAYS = [string]$Config.Logging.RetentionDays
    }
    else {
        $env:ETL_LOG_RETENTION_DAYS = [string]$LogFileRetentionDays
    }

    if ($Config.Logging -and $Config.Logging.Level) {
        $ConfiguredLogLevel = ([string]$Config.Logging.Level).ToUpperInvariant()

        switch ($ConfiguredLogLevel) {
            'VERBOSE' { $env:ETL_LOG_LEVEL = 'DEBUG' }
            'DEBUG'   { $env:ETL_LOG_LEVEL = 'DEBUG' }
            'INFO'    { $env:ETL_LOG_LEVEL = 'INFO' }
            'WARN'    { $env:ETL_LOG_LEVEL = 'WARN' }
            'ERROR'   { $env:ETL_LOG_LEVEL = 'ERROR' }
            default   { $env:ETL_LOG_LEVEL = 'INFO' }
        }
    }
    else {
        $env:ETL_LOG_LEVEL = 'INFO'
    }

    if ($Config.Logging -and $Config.Logging.ModuleLogs) {
        $env:ETL_MODULE_LOGS = [string]$Config.Logging.ModuleLogs
    }
    else {
        $env:ETL_MODULE_LOGS = 'True'
    }

    Write-Log "RunId: $($env:ETL_RUN_ID)" -Level "INFO"
    Write-Log "ModuleLogRoot: $($env:ETL_LOG_ROOT)" -Level "INFO"
    Write-Log "ModuleLogLevel: $($env:ETL_LOG_LEVEL)" -Level "INFO"
    Write-Log "ModuleLogsEnabled: $($env:ETL_MODULE_LOGS)" -Level "INFO"
}

function Clear-ModuleRuntimeContext {
    [CmdletBinding()]
    param()

    Remove-Item Env:ETL_RUN_ID -ErrorAction SilentlyContinue
    Remove-Item Env:ETL_LOG_ROOT -ErrorAction SilentlyContinue
    Remove-Item Env:ETL_PROJECT_ROOT -ErrorAction SilentlyContinue
    Remove-Item Env:ETL_LOG_RETENTION_DAYS -ErrorAction SilentlyContinue
    Remove-Item Env:ETL_LOG_LEVEL -ErrorAction SilentlyContinue
    Remove-Item Env:ETL_MODULE_LOGS -ErrorAction SilentlyContinue
    Remove-Item Env:ETL_STEP_ID -ErrorAction SilentlyContinue
    Remove-Item Env:ETL_STEP_NAME -ErrorAction SilentlyContinue
}

function Set-EtlStepRuntimeContext {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory)][hashtable] $Pipeline
    )

    $env:ETL_STEP_ID = [string]$Pipeline.StepId
    $env:ETL_STEP_NAME = [string]$Pipeline.Name
}

function Get-PipelineObjectPreview {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object] $InputObject
    )

    $PreviewCommand = Get-Command -Name 'Get-EtlObjectPreview' -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($PreviewCommand) {
        return (& $PreviewCommand -InputObject $InputObject)
    }

    if ($null -eq $InputObject) { return '<null>' }

    try {
        $Properties = @($InputObject.PSObject.Properties | Select-Object -First 8)
        if ($Properties.Count -gt 0) {
            return (($Properties | ForEach-Object { '{0}={1}' -f $_.Name, $(if ($null -eq $_.Value) { '<null>' } else { [string]$_.Value }) }) -join '; ')
        }
    }
    catch {
        return [string]$InputObject
    }

    return [string]$InputObject
}

function Clear-EtlStepRuntimeContext {
    [CmdletBinding()]
    param()

    Remove-Item Env:ETL_STEP_ID -ErrorAction SilentlyContinue
    Remove-Item Env:ETL_STEP_NAME -ErrorAction SilentlyContinue
}

function Clear-EtlSourceRuntimeContext {
    [CmdletBinding()]
    param()

    Remove-Item Env:ETL_LAST_SOURCE_FILE -ErrorAction SilentlyContinue
    Remove-Item Env:ETL_LAST_SOURCE_TYPE -ErrorAction SilentlyContinue
}

function ConvertTo-BooleanValue {
    [CmdletBinding()]
    param(
        [AllowNull()] $Value,
        [bool] $Default = $false
    )

    if ($null -eq $Value) {
        return $Default
    }

    if ($Value -is [bool]) {
        return [bool]$Value
    }

    $Text = ([string]$Value).Trim()
    if ([string]::IsNullOrWhiteSpace($Text)) {
        return $Default
    }

    return $Text -match '^(?i:true|1|yes|y)$'
}

function Invoke-PostImportSourceFileActions {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][hashtable] $Pipeline
    )

    $SourceType = [string]$Pipeline.Source.Type
    if ($SourceType -notin @('CSV','XLSX','XML','JSON')) {
        return
    }

    $SelectedSourceFile = $env:ETL_LAST_SOURCE_FILE
    if ([string]::IsNullOrWhiteSpace($SelectedSourceFile)) {
        Write-Log ("Step [{0}] source file post-processing skipped because no selected source file was registered by the source adapter." -f $Pipeline.StepId) -Level 'WARN'
        return
    }

    if (-not (Test-Path -Path $SelectedSourceFile -PathType Leaf)) {
        Write-Log ("Step [{0}] source file post-processing skipped because the selected source file no longer exists: {1}" -f $Pipeline.StepId, $SelectedSourceFile) -Level 'WARN'
        return
    }

    $SourceConfig = $Pipeline.Source.Config
    $DeleteFlagValue = if ($SourceConfig.ContainsKey('DeleteAfterImport')) { $SourceConfig.DeleteAfterImport } elseif ($SourceConfig.ContainsKey('DeleteAfterRead')) { $SourceConfig.DeleteAfterRead } else { $null }
    $BackupAfterImport = ConvertTo-BooleanValue -Value $SourceConfig.BackupAfterImport -Default $false
    $DeleteAfterImport = ConvertTo-BooleanValue -Value $DeleteFlagValue -Default $false
    $BackupPath = if ($SourceConfig.ContainsKey('BackupPath') -and -not [string]::IsNullOrWhiteSpace([string]$SourceConfig.BackupPath)) { [string]$SourceConfig.BackupPath } else { 'INPUT\_Backup' }

    if (-not $BackupAfterImport -and -not $DeleteAfterImport) {
        Write-Log ("Step [{0}] no post-import source file actions requested for file: {1}" -f $Pipeline.StepId, $SelectedSourceFile) -Level 'DEBUG'
        return
    }

    if ($BackupAfterImport) {
        $ResolvedBackupRoot = Resolve-NormalizedPath -Path $BackupPath -BasePath $ProjectRootPath
        if (-not (Test-Path -Path $ResolvedBackupRoot -PathType Container)) {
            New-Item -Path $ResolvedBackupRoot -ItemType Directory -Force | Out-Null
            Write-Log ("Step [{0}] created backup target directory: {1}" -f $Pipeline.StepId, $ResolvedBackupRoot) -Level 'INFO'
        }

        $Timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
        $TargetFileName = '{0}_{1}{2}' -f [System.IO.Path]::GetFileNameWithoutExtension($SelectedSourceFile), $Timestamp, [System.IO.Path]::GetExtension($SelectedSourceFile)
        $BackupFilePath = Join-Path -Path $ResolvedBackupRoot -ChildPath $TargetFileName
        Copy-Item -Path $SelectedSourceFile -Destination $BackupFilePath -Force -ErrorAction Stop
        Write-Log ("Step [{0}] backed up source file: {1} -> {2}" -f $Pipeline.StepId, $SelectedSourceFile, $BackupFilePath) -Level 'INFO'
    }

    if ($DeleteAfterImport) {
        Remove-Item -Path $SelectedSourceFile -Force -ErrorAction Stop
        Write-Log ("Step [{0}] deleted source file after successful import: {1}" -f $Pipeline.StepId, $SelectedSourceFile) -Level 'WARN'
    }
}

function Invoke-EtlStep {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][hashtable] $Pipeline,
        [Parameter(Mandatory)][hashtable] $ImportedModules
    )

    $StepStopWatch = [System.Diagnostics.Stopwatch]::StartNew()

    try {
        $StepId          = [string]$Pipeline.StepId
        $StepName        = [string]$Pipeline.Name
        $SourceType      = [string]$Pipeline.Source.Type
        $DestinationType = [string]$Pipeline.Destination.Type
        $Properties      = @($Pipeline.Properties)
        $PipelineRows    = 0
        $FirstRowLogged  = $false

        $ExtractCommand = Get-EtlAdapterCommand -ImportedModules $ImportedModules -AdapterRole 'Source' -AdapterType $SourceType -CommandName 'Invoke-Extract'
        $LoadCommand    = Get-EtlAdapterCommand -ImportedModules $ImportedModules -AdapterRole 'Destination' -AdapterType $DestinationType -CommandName 'Invoke-Load'
        $DestinationConfig = @{}
        foreach ($Entry in $Pipeline.Destination.Config.GetEnumerator()) {
            $DestinationConfig[$Entry.Key] = $Entry.Value
        }
        $DestinationConfig['_PipelineProperties'] = $Properties

        Set-EtlStepRuntimeContext -Pipeline $Pipeline
        Clear-EtlSourceRuntimeContext

        Write-Log ("Executing ETL step [{0}] {1}: [{2}] --> [{3}]" -f $StepId, $StepName, $SourceType, $DestinationType) -Level "INFO"
        Write-Log ("Step [{0}] property selection: {1}" -f $StepId, (($Properties | ForEach-Object { $_ }) -join ', ')) -Level "INFO"
        Write-Log ("Step [{0}] source config keys: {1}" -f $StepId, (($Pipeline.Source.Config.Keys | Sort-Object) -join ', ')) -Level "INFO"
        Write-Log ("Step [{0}] destination config keys: {1}" -f $StepId, (($Pipeline.Destination.Config.Keys | Sort-Object) -join ', ')) -Level "INFO"
        Write-Log ("Step [{0}] pipeline handoff tracing activated." -f $StepId) -Level "INFO"

        & $ExtractCommand -Config $Pipeline.Source.Config -Properties $Properties |
            ForEach-Object {
                $PipelineRows++

                if (-not $FirstRowLogged) {
                    $FirstRowLogged = $true
                    try {
                        Write-Log ("Step [{0}] first pipeline handoff preview: {1}" -f $StepId, (Get-PipelineObjectPreview -InputObject $_)) -Level "INFO"
                    }
                    catch {
                        Write-Log ("Step [{0}] first pipeline handoff preview unavailable: {1}" -f $StepId, $_.Exception.Message) -Level "WARN"
                    }
                }

                $_
            } |
            & $LoadCommand -Config $DestinationConfig

        Invoke-PostImportSourceFileActions -Pipeline $Pipeline

        $StepStopWatch.Stop()

        if ($PipelineRows -eq 0) {
            Write-Log ("ETL step [{0}] completed successfully with zero rows transferred. Duration: {1}" -f $StepId, $StepStopWatch.Elapsed.ToString("hh\:mm\:ss\.fff")) -Level "WARN"
        }
        else {
            Write-Log ("ETL step [{0}] completed successfully. Rows transferred: [{1}] | Duration: {2}" -f $StepId, $PipelineRows, $StepStopWatch.Elapsed.ToString("hh\:mm\:ss\.fff")) -Level "INFO"
        }

        return $true
    }
    catch {
        $StepStopWatch.Stop()
        Write-Log ("ETL step [{0}] failed after {1}: {2}" -f $Pipeline.StepId, $StepStopWatch.Elapsed.ToString("hh\:mm\:ss\.fff"), $_.Exception.Message) -Level "ERROR"
        return $false
    }
    finally {
        Clear-EtlSourceRuntimeContext
        Clear-EtlStepRuntimeContext
    }
}

function Invoke-EtlPipelines {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][hashtable] $Config,
        [Parameter(Mandatory)][hashtable] $ImportedModules
    )

    try {
        $Pipelines = Get-NormalizedPipelines -Config $Config
        Write-Log ("Configured ETL steps: {0}" -f $Pipelines.Count) -Level "INFO"
        $EnabledPipelines = @($Pipelines | Where-Object { $_.StepEnabled })
        $DisabledPipelines = @($Pipelines | Where-Object { -not $_.StepEnabled })
        Write-Log ("Enabled ETL steps: {0} | Disabled ETL steps: {1}" -f $EnabledPipelines.Count, $DisabledPipelines.Count) -Level "INFO"

        foreach ($Pipeline in $DisabledPipelines) {
            Write-Log ("Skipping ETL step [{0}] {1} because StepEnabled=False." -f $Pipeline.StepId, $Pipeline.Name) -Level "WARN"
        }

        foreach ($Pipeline in $EnabledPipelines) {
            if (-not (Invoke-EtlStep -Pipeline $Pipeline -ImportedModules $ImportedModules)) {
                return $false
            }
        }

        if ($EnabledPipelines.Count -eq 0) {
            Write-Log "No enabled ETL steps found. Nothing to execute." -Level "WARN"
        }
        else {
            Write-Log "All enabled ETL steps executed successfully." -Level "INFO"
        }

        return $true
    }
    catch {
        Write-Log "ETL pipeline execution failed: $($_.Exception.Message)" -Level "ERROR"
        return $false
    }
}

function Resolve-NormalizedPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $Path,
        [string] $BasePath = $ScriptDirectory
    )

    if ([string]::IsNullOrWhiteSpace($Path)) {
        throw 'Path value is empty and cannot be normalized.'
    }

    if ([System.IO.Path]::IsPathRooted($Path)) {
        return [System.IO.Path]::GetFullPath($Path)
    }

    return [System.IO.Path]::GetFullPath((Join-Path -Path $BasePath -ChildPath $Path))
}

try {
    Write-Log "--- SCRIPT STARTED ---" -Level "INFO"
    Write-Log "Name: $ScriptName | BuildDate: $BuildDate" -Level "INFO"
    Write-Log "ResolvedConfigPath: $ResolvedConfigPath" -Level "INFO"
    Write-Log "ProjectRootPath: $ProjectRootPath" -Level "INFO"

    if (-not (Test-PathExists -Path $ResolvedConfigPath -PathType Leaf -Description "ETL configuration file")) {
        throw "ETL configuration file validation failed."
    }

    $Config = Import-PowerShellDataFile -Path $ResolvedConfigPath

    if ($Config.Logging -and $Config.Logging.RetentionDays) {
        $LogFileRetentionDays = [int]$Config.Logging.RetentionDays
    }

    if ($Config.Logging -and $Config.Logging.Level) {
        switch -Regex (([string]$Config.Logging.Level).ToUpperInvariant()) {
            '^DEBUG$'   { $VerbosePreference = 'Continue' }
            '^VERBOSE$' { $VerbosePreference = 'Continue' }
            default     { $VerbosePreference = 'SilentlyContinue' }
        }
    }

    if (-not (Test-EtlConfiguration -Config $Config)) {
        throw "ETL configuration is invalid."
    }

    Initialize-ModuleRuntimeContext -Config $Config
    Import-EtlSupportModules

    $ResolvedPipelines = Get-NormalizedPipelines -Config $Config
    $ImportedModules = Import-EtlAdapterModules -Pipelines $ResolvedPipelines

    if (-not $ImportedModules) {
        throw "Adapter module import failed."
    }

    $ExecutionSucceeded = Invoke-EtlPipelines -Config $Config -ImportedModules $ImportedModules

    if (-not $ExecutionSucceeded) {
        throw "ETL pipeline execution failed."
    }

    if ($Config.ContainsKey('Adapter') -and (Test-AdapterExecutionEnabled -AdapterConfig $Config.Adapter)) {
        $AdapterCommand = Get-Command -Name 'Invoke-FlexeraBusinessAdapter' -ErrorAction SilentlyContinue | Select-Object -First 1
        if (-not $AdapterCommand) {
            throw "Flexera Business Adapter execution is enabled, but the adapter module is not available: $FlexeraModulePath"
        }

        $AdapterSucceeded = Invoke-FlexeraBusinessAdapter -Config $Config -RuntimeRoot $ScriptDirectory -LogDirectory $LogDirectory -RunId $Script:RunId -WriteLog ${function:Write-Log} -ResolveNormalizedPath ${function:Resolve-NormalizedPath}
        if (-not $AdapterSucceeded) {
            throw 'Flexera Business Adapter execution failed.'
        }
    }
    else {
        Write-Log 'Flexera Business Adapter execution skipped. Config.Adapter.AdapterEnabled is not set to $true.' -Level 'INFO'
    }

    $StopWatch.Stop()
    Write-Log ("Execution completed successfully in {0}" -f $StopWatch.Elapsed.ToString("hh\:mm\:ss\.fff")) -Level "INFO"
    Write-Log "--- SCRIPT COMPLETED SUCCESSFULLY ---" -Level "INFO"
    exit 0
}
catch {
    $StopWatch.Stop()
    Write-EtlScriptException -Context $Script:LogContext -ErrorRecord $_ -Prefix 'FATAL SCRIPT ERROR:'
    Write-Log ("Execution failed after {0}" -f $StopWatch.Elapsed.ToString("hh\:mm\:ss\.fff")) -Level "ERROR"
    exit 1
}
finally {
    Clear-ModuleRuntimeContext
    [System.GC]::Collect()
    Write-Log "--- SCRIPT EXECUTION ENDED ---" -Level "INFO"
}
