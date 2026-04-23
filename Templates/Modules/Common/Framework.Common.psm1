<#
.SYNOPSIS
Common utility module for the ETL framework runtime.

.DESCRIPTION
Provides shared helper functions for logging, configuration handling,
path resolution, retention cleanup, and dependency loading.

Used by the ETL runtime and all adapter modules to ensure consistent
behavior across the framework.

.VERSION
23.0.0

.AUTHOR
ETL Framework

.NOTES
- Central infrastructure module
- Must be loaded before adapter modules
- Provides logging and runtime helpers
- Comments and user-visible messages use American English spelling

.DEPENDENCIES
- .NET Framework 4.7 or higher
#>

$LoggingModulePath = Join-Path -Path $PSScriptRoot -ChildPath 'Framework.Logging.psm1'
$ValidationModulePath = Join-Path -Path $PSScriptRoot -ChildPath 'Framework.Validation.psm1'
Import-Module -Name $LoggingModulePath -ErrorAction Stop
Import-Module -Name $ValidationModulePath -ErrorAction Stop

$Script:RetentionCleanupState = @{}
$Script:ExcelDependencyState = @{}

function Get-EtlProjectRootPath {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory)][string] $ModuleRoot
    )

    if (-not [string]::IsNullOrWhiteSpace($env:ETL_PROJECT_ROOT)) {
        return [System.IO.Path]::GetFullPath($env:ETL_PROJECT_ROOT)
    }

    if (-not [string]::IsNullOrWhiteSpace($env:ETL_LOG_ROOT)) {
        return [System.IO.Path]::GetFullPath((Split-Path -Path $env:ETL_LOG_ROOT -Parent))
    }

    return [System.IO.Path]::GetFullPath((Split-Path -Path (Split-Path -Path (Split-Path -Path $ModuleRoot -Parent) -Parent) -Parent))
}

function Resolve-EtlProjectPath {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory)][string] $Path,
        [Parameter(Mandatory)][string] $ModuleRoot
    )

    if ([System.IO.Path]::IsPathRooted($Path)) {
        return [System.IO.Path]::GetFullPath($Path)
    }

    $ProjectRoot = Get-EtlProjectRootPath -ModuleRoot $ModuleRoot
    return [System.IO.Path]::GetFullPath((Join-Path -Path $ProjectRoot -ChildPath $Path))
}

function Get-ExcelDataReaderDependencyRoot {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory)][string] $ModuleRoot
    )

    $CandidateRoots = @(
        (Join-Path -Path $ModuleRoot -ChildPath '..\Dependencies\ExcelDataReader'),
        (Join-Path -Path (Split-Path -Path $ModuleRoot -Parent) -ChildPath 'Dependencies\ExcelDataReader')
    )

    return ($CandidateRoots |
        ForEach-Object { [System.IO.Path]::GetFullPath($_) } |
        Where-Object { Test-Path -Path $_ -PathType Container } |
        Select-Object -First 1)
}

function Import-EtlAssemblyIfNeeded {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory)][string] $AssemblyPath,
        [Parameter()][string] $TypeName
    )

    if (-not (Test-Path -Path $AssemblyPath -PathType Leaf)) {
        return $false
    }

    if ($TypeName -and ($TypeName -as [type])) {
        return $true
    }

    $ResolvedAssemblyPath = [System.IO.Path]::GetFullPath($AssemblyPath)
    if ($Script:ExcelDependencyState.ContainsKey($ResolvedAssemblyPath)) {
        return $true
    }

    $AssemblyFileName = [System.IO.Path]::GetFileName($ResolvedAssemblyPath)
    $AlreadyLoaded = [AppDomain]::CurrentDomain.GetAssemblies() |
        Where-Object {
            try { $_.Location -and ([System.IO.Path]::GetFileName($_.Location) -ieq $AssemblyFileName) }
            catch { $false }
        } |
        Select-Object -First 1

    if ($AlreadyLoaded) {
        $Script:ExcelDependencyState[$ResolvedAssemblyPath] = $true
        return $true
    }

    try { Unblock-File -Path $ResolvedAssemblyPath -ErrorAction SilentlyContinue } catch { Write-Verbose "Unable to unblock assembly [$ResolvedAssemblyPath]: $($_.Exception.Message)" }

    [void][System.Reflection.Assembly]::LoadFrom($ResolvedAssemblyPath)
    $Script:ExcelDependencyState[$ResolvedAssemblyPath] = $true
    return $true
}


function Register-ExcelDependencyResolver {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory)][string] $DependencyRoot
    )

    if ($Script:ExcelDependencyState.ContainsKey('AssemblyResolveRegistered')) {
        return
    }

    $ResolvedRoot = [System.IO.Path]::GetFullPath($DependencyRoot)
    $ResolveHandler = [System.ResolveEventHandler]{
        param($AssemblySender, $AssemblyEventArgs)

        try {
            $RequestedAssemblyName = New-Object System.Reflection.AssemblyName($AssemblyEventArgs.Name)
            $RequestedFileName = "{0}.dll" -f $RequestedAssemblyName.Name
            $CandidatePath = Join-Path -Path $ResolvedRoot -ChildPath $RequestedFileName

            if (-not (Test-Path -Path $CandidatePath -PathType Leaf)) {
                return $null
            }

            $AlreadyLoadedAssembly = [AppDomain]::CurrentDomain.GetAssemblies() |
                Where-Object {
                    try { $_.GetName().Name -eq $RequestedAssemblyName.Name }
                    catch { $false }
                } |
                Select-Object -First 1

            if ($AlreadyLoadedAssembly) {
                return $AlreadyLoadedAssembly
            }

            try { Unblock-File -Path $CandidatePath -ErrorAction SilentlyContinue } catch { Write-Verbose "Unable to unblock dependency [$CandidatePath]: $($_.Exception.Message)" }
            return [System.Reflection.Assembly]::LoadFrom($CandidatePath)
        }
        catch {
            return $null
        }
    }

    [AppDomain]::CurrentDomain.add_AssemblyResolve($ResolveHandler)
    $Script:ExcelDependencyState['AssemblyResolveRegistered'] = $true
    $Script:ExcelDependencyState['AssemblyResolveHandler'] = $ResolveHandler
}

function Import-ExcelSupportAssemblies {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory)][string] $DependencyRoot
    )

    if (-not (Test-Path -Path $DependencyRoot -PathType Container)) {
        return
    }

    $SupportAssemblies = Get-ChildItem -Path $DependencyRoot -Filter '*.dll' -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -ine 'ExcelDataReader.dll' -and $_.Name -ine 'System.Text.Encoding.CodePages.dll' } |
        Sort-Object Name

    foreach ($AssemblyFile in $SupportAssemblies) {
        try {
            [void](Import-EtlAssemblyIfNeeded -AssemblyPath $AssemblyFile.FullName)
        }
        catch {
            # Optional preload only. Missing or incompatible support assemblies are retried through AssemblyResolve when needed.
            Write-Verbose ("Optional support assembly preload failed [{0}]: {1}" -f $AssemblyFile.FullName, $_.Exception.Message)
        }
    }
}

function Register-ExcelCodePageProvider {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory)][string] $DependencyRoot
    )

    if ($Script:ExcelDependencyState.ContainsKey('CodePagesProviderRegistered')) {
        return
    }

    $ProviderType = 'System.Text.CodePagesEncodingProvider' -as [type]
    if (-not $ProviderType) {
        $CodePagesAssemblyPath = Join-Path -Path $DependencyRoot -ChildPath 'System.Text.Encoding.CodePages.dll'
        if (Test-Path -Path $CodePagesAssemblyPath -PathType Leaf) {
            try {
                [void](Import-EtlAssemblyIfNeeded -AssemblyPath $CodePagesAssemblyPath -TypeName 'System.Text.CodePagesEncodingProvider')
                $ProviderType = 'System.Text.CodePagesEncodingProvider' -as [type]
            }
            catch {
                throw "Failed to load optional dependency System.Text.Encoding.CodePages.dll: $CodePagesAssemblyPath | $($_.Exception.Message)"
            }
        }
    }

    if ($ProviderType) {
        try {
            [System.Text.Encoding]::RegisterProvider($ProviderType::Instance)
            $Script:ExcelDependencyState['CodePagesProviderRegistered'] = $true
        }
        catch {
            throw "Failed to register code page provider for ExcelDataReader. | $($_.Exception.Message)"
        }
    }
}

function Import-ExcelDataReaderAssemblies {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory)][string] $ModuleRoot
    )

    if ('ExcelDataReader.ExcelReaderFactory' -as [type]) {
        $ExistingDependencyRoot = Get-ExcelDataReaderDependencyRoot -ModuleRoot $ModuleRoot
        if (-not $ExistingDependencyRoot) { $ExistingDependencyRoot = $ModuleRoot }
        Register-ExcelDependencyResolver -DependencyRoot $ExistingDependencyRoot
        Import-ExcelSupportAssemblies -DependencyRoot $ExistingDependencyRoot
        Register-ExcelCodePageProvider -DependencyRoot $ExistingDependencyRoot
        return
    }

    $DependencyRoot = Get-ExcelDataReaderDependencyRoot -ModuleRoot $ModuleRoot
    if (-not $DependencyRoot) {
        throw "ExcelDataReader runtime directory not found. Expected under Modules\Dependencies\ExcelDataReader."
    }

    $PrimaryAssemblyPath = Join-Path -Path $DependencyRoot -ChildPath 'ExcelDataReader.dll'
    if (-not (Test-Path -Path $PrimaryAssemblyPath -PathType Leaf)) {
        throw "Required ExcelDataReader assembly not found: $PrimaryAssemblyPath"
    }

    Register-ExcelDependencyResolver -DependencyRoot $DependencyRoot
    Import-ExcelSupportAssemblies -DependencyRoot $DependencyRoot

    try {
        [void](Import-EtlAssemblyIfNeeded -AssemblyPath $PrimaryAssemblyPath -TypeName 'ExcelDataReader.ExcelReaderFactory')
    }
    catch {
        throw "Failed to load required ExcelDataReader assembly: $PrimaryAssemblyPath | $($_.Exception.Message)"
    }

    Register-ExcelCodePageProvider -DependencyRoot $DependencyRoot

    if (-not ('ExcelDataReader.ExcelReaderFactory' -as [type])) {
        throw 'ExcelDataReader type not available after assembly load: ExcelDataReader.ExcelReaderFactory'
    }
}


function Get-EtlObjectPropertyNames {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory)][AllowNull()][object] $InputObject
    )

    if ($null -eq $InputObject) { return @() }
    if ($InputObject -is [System.Data.DataRow]) { return @($InputObject.Table.Columns | ForEach-Object { $_.ColumnName }) }
    if ($InputObject -is [hashtable]) { return @($InputObject.Keys | ForEach-Object { [string]$_ }) }

    try {
        return @($InputObject.PSObject.Properties |
            Where-Object { $_.MemberType -in @('NoteProperty','Property','AliasProperty','ScriptProperty') } |
            ForEach-Object { $_.Name })
    }
    catch {
        return @()
    }
}

function Get-EtlObjectPreview {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter()][AllowNull()][object] $InputObject,
        [int] $MaxProperties = 8,
        [int] $MaxValueLength = 80
    )

    if ($null -eq $InputObject) { return '<null>' }

    $PropertyNames = @(Get-EtlObjectPropertyNames -InputObject $InputObject | Select-Object -First $MaxProperties)
    if ($PropertyNames.Count -eq 0) { return ([string]$InputObject) }

    $Parts = New-Object System.Collections.Generic.List[string]
    foreach ($PropertyName in $PropertyNames) {
        $Value = $null
        try {
            if ($InputObject -is [System.Data.DataRow]) {
                if ($InputObject.Table.Columns.Contains($PropertyName)) { $Value = $InputObject[$PropertyName] }
            }
            elseif ($InputObject -is [hashtable]) {
                $Value = $InputObject[$PropertyName]
            }
            else {
                $Property = $InputObject.PSObject.Properties[$PropertyName]
                if ($null -ne $Property) { $Value = $Property.Value }
            }
        }
        catch { $Value = '<unavailable>' }

        if ($null -eq $Value -or $Value -is [System.DBNull]) {
            $Text = '<null>'
        }
        else {
            $Text = [string]$Value
            if ($Text.Length -gt $MaxValueLength) { $Text = $Text.Substring(0, $MaxValueLength) + '...' }
        }

        [void]$Parts.Add(("{0}={1}" -f $PropertyName, $Text))
    }

    return ($Parts -join '; ')
}


function Get-EtlRecordCountAndPreview {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter()][AllowNull()][object[]] $Records,
        [int] $PreviewCount = 1
    )

    $SafeRecords = @($Records | Where-Object { $null -ne $_ })
    $Preview = @()

    if ($SafeRecords.Count -gt 0 -and $PreviewCount -gt 0) {
        $Preview = @(
            $SafeRecords |
                Select-Object -First $PreviewCount |
                ForEach-Object { Get-EtlObjectPreview -InputObject $_ }
        )
    }

    [PSCustomObject]@{
        Count   = $SafeRecords.Count
        Preview = $Preview
    }
}

function Write-EtlExceptionDetails {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory)][hashtable] $Context,
        [Parameter(Mandatory)][System.Management.Automation.ErrorRecord] $ErrorRecord,
        [string] $Prefix = ''
    )

    $EffectivePrefix = if ([string]::IsNullOrWhiteSpace($Prefix)) { '' } else { "$Prefix " }
    Write-EtlModuleLog -Context $Context -Message ("{0}{1}" -f $EffectivePrefix, $ErrorRecord.Exception.Message) -Level 'ERROR'

    if ($ErrorRecord.InvocationInfo) {
        $InvocationScriptName = if ([string]::IsNullOrWhiteSpace([string]$ErrorRecord.InvocationInfo.ScriptName)) { '<interactive>' } else { [string]$ErrorRecord.InvocationInfo.ScriptName }
        Write-EtlModuleLog -Context $Context -Message ("{0}Error location: Line {1} | Script: {2}" -f $EffectivePrefix, $ErrorRecord.InvocationInfo.ScriptLineNumber, $InvocationScriptName) -Level 'ERROR'
    }

    if ($ErrorRecord.ScriptStackTrace) {
        Write-EtlModuleLog -Context $Context -Message ("{0}StackTrace: {1}" -f $EffectivePrefix, $ErrorRecord.ScriptStackTrace) -Level 'ERROR'
    }

    if ($ErrorRecord.Exception.InnerException) {
        Write-EtlModuleLog -Context $Context -Message ("{0}InnerException: {1}" -f $EffectivePrefix, $ErrorRecord.Exception.InnerException.Message) -Level 'ERROR'
    }
}


function Import-EtlCredentialSupport {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory)][string] $ModuleRoot
    )

    if (Get-Command -Name Get-StoredCredential -ErrorAction SilentlyContinue) {
        return
    }

    $ProjectRoot = Get-EtlProjectRootPath -ModuleRoot $ModuleRoot
    $CandidatePaths = @(
        (Join-Path -Path $ProjectRoot -ChildPath 'RUN\Modules\Credential\Credential.Manager.psm1'),
        (Join-Path -Path (Split-Path -Path $ModuleRoot -Parent) -ChildPath 'Credential\Credential.Manager.psm1'),
        (Join-Path -Path $ModuleRoot -ChildPath '..\Credential\Credential.Manager.psm1')
    ) |
        ForEach-Object {
            try { [System.IO.Path]::GetFullPath($_) }
            catch { $_ }
        } |
        Select-Object -Unique

    $CredentialModulePath = $CandidatePaths |
        Where-Object { Test-Path -Path $_ -PathType Leaf } |
        Select-Object -First 1

    if (-not $CredentialModulePath) {
        throw "Credential support module not found. Expected Credential.Manager.psm1 next to the ETL runtime or module root."
    }

    Import-Module -Name $CredentialModulePath -Force -ErrorAction Stop
}

function New-EtlModuleContext {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory)][string] $ModulePath,
        [Parameter(Mandatory)][string] $ModuleRoot
    )

    $ModuleName = [System.IO.Path]::GetFileNameWithoutExtension($ModulePath)
    $ModuleRole = if ($ModuleName -like 'Source.*') { '02' } else { '03' }
    $RunId = if ($env:ETL_RUN_ID) { $env:ETL_RUN_ID } else { Get-Date -Format 'yyyyMMdd_HHmmss' }
    $LogDirectory = if ($env:ETL_LOG_ROOT) { $env:ETL_LOG_ROOT } else { Join-Path -Path (Get-EtlProjectRootPath -ModuleRoot $ModuleRoot) -ChildPath 'LOG' }

    @{
        ModuleName             = $ModuleName
        ModuleRole             = $ModuleRole
        ModuleRoot             = $ModuleRoot
        ModuleRunId            = $RunId
        ModuleLogDirectory     = $LogDirectory
        ModuleRetentionDays    = if ($env:ETL_LOG_RETENTION_DAYS) { [int]$env:ETL_LOG_RETENTION_DAYS } else { 30 }
        ModuleLogLevel         = if ($env:ETL_LOG_LEVEL) { $env:ETL_LOG_LEVEL.ToUpperInvariant() } else { 'INFO' }
        ModuleLogFileNameBase  = "{0}_{1}" -f $ModuleRole, $ModuleName
        CleanupKey             = "Module::{0}::{1}" -f $ModuleName, $RunId
    }
}

function Get-EtlStepLogSuffix {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param()

    $StepId = if (-not [string]::IsNullOrWhiteSpace($env:ETL_STEP_ID)) { [string]$env:ETL_STEP_ID } else { $null }
    if ([string]::IsNullOrWhiteSpace($StepId)) {
        return $null
    }

    $SanitizedStepId = ($StepId -replace '[^A-Za-z0-9._-]', '_')
    return "Step_{0}" -f $SanitizedStepId
}

function Get-EtlModuleLogFilePath {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory)][hashtable] $Context
    )

    $FileNameBase = $Context.ModuleLogFileNameBase
    $StepSuffix = Get-EtlStepLogSuffix

    if (-not [string]::IsNullOrWhiteSpace($StepSuffix)) {
        return Join-Path -Path $Context.ModuleLogDirectory -ChildPath ("{0}_{1}_{2}.log" -f $Context.ModuleRunId, $FileNameBase, $StepSuffix)
    }

    return Join-Path -Path $Context.ModuleLogDirectory -ChildPath ("{0}_{1}.log" -f $Context.ModuleRunId, $FileNameBase)
}

function Write-EtlModuleLog {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory)][hashtable] $Context,
        [Parameter(Mandatory)][string] $Message,
        [ValidateSet('INFO','WARN','ERROR','DEBUG')][string] $Level = 'INFO'
    )

    try {
        $ModuleLogsEnabled = $true
        if (-not [string]::IsNullOrWhiteSpace($env:ETL_MODULE_LOGS)) {
            [void][bool]::TryParse($env:ETL_MODULE_LOGS, [ref]$ModuleLogsEnabled)
        }

        if (-not $ModuleLogsEnabled) { return }

        $EffectiveLogLevel = if ($env:ETL_LOG_LEVEL) { ([string]$env:ETL_LOG_LEVEL).ToUpperInvariant() } else { [string]$Context.ModuleLogLevel }
        if ([string]::IsNullOrWhiteSpace($EffectiveLogLevel)) {
            $EffectiveLogLevel = 'INFO'
        }
        $Context.ModuleLogLevel = $EffectiveLogLevel

        if (-not (Test-EtlLogLevelEnabled -ConfiguredLevel $Context.ModuleLogLevel -MessageLevel $Level)) {
            return
        }

        if (-not (Test-Path -Path $Context.ModuleLogDirectory -PathType Container)) {
            New-Item -Path $Context.ModuleLogDirectory -ItemType Directory -Force | Out-Null
        }

        Invoke-EtlLogRetentionCleanup -LogDirectory $Context.ModuleLogDirectory -RetentionDays $Context.ModuleRetentionDays -CleanupKey $Context.CleanupKey

        $Timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
        $Entry = "$Timestamp [$Level] $Message"
        $ModuleLogFile = Get-EtlModuleLogFilePath -Context $Context

        if (Test-Path -Path $ModuleLogFile -PathType Leaf) {
            Add-Content -Path $ModuleLogFile -Value $Entry
        }
        else {
            Set-Content -Path $ModuleLogFile -Value $Entry -Force
        }

        Write-EtlMessageStream -Entry $Entry -Level $Level
    }
    catch {
        Write-Warning "Failed to write module log entry: $($_.Exception.Message)"
    }
}

Export-ModuleMember -Function `
    Test-EtlLogLevelEnabled, `
    Write-EtlMessageStream, `
    Invoke-EtlLogRetentionCleanup, `
    Get-EtlProjectRootPath, `
    Resolve-EtlProjectPath, `
    Get-ExcelDataReaderDependencyRoot, `
    Import-EtlAssemblyIfNeeded, `
    Register-ExcelDependencyResolver, `
    Import-ExcelSupportAssemblies, `
    Register-ExcelCodePageProvider, `
    Import-ExcelDataReaderAssemblies, `
    New-EtlModuleContext, `
    Get-EtlStepLogSuffix, `
    Get-EtlModuleLogFilePath, `
    Get-EtlObjectPropertyNames, `
    Get-EtlObjectPreview, `
    Get-EtlRecordCountAndPreview, `
    Write-EtlExceptionDetails, `
    Write-EtlModuleLog, `
    Get-ValidatedPropertySelection, `
    Get-EtlAuthenticationMode, `
    Import-EtlCredentialSupport
