<#
.SYNOPSIS
Shared logging infrastructure for ETL framework scripts and modules.

.DESCRIPTION
Provides consistent log-level handling, log retention, file creation,
and structured error logging for runtime, setup, tooling, and modules.

.VERSION
1.0
#>

$Script:EtlLogRetentionState = @{}

function Test-EtlLogLevelEnabled {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateSet('DEBUG','INFO','WARN','ERROR')][string] $ConfiguredLevel,
        [Parameter(Mandatory)][ValidateSet('DEBUG','INFO','WARN','ERROR')][string] $MessageLevel
    )

    $Rank = @{ DEBUG = 1; INFO = 2; WARN = 3; ERROR = 4 }
    $EffectiveConfiguredLevel = if ($Rank.ContainsKey($ConfiguredLevel)) { $ConfiguredLevel } else { 'INFO' }
    return ($Rank[$MessageLevel] -ge $Rank[$EffectiveConfiguredLevel])
}

function Write-EtlMessageStream {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $Entry,
        [Parameter(Mandatory)][ValidateSet('DEBUG','INFO','WARN','ERROR')][string] $Level
    )

    switch ($Level) {
        'ERROR' { Write-Error -Message $Entry }
        'WARN'  { Write-Warning $Entry }
        'DEBUG' { Write-Verbose $Entry }
        default { Write-Information $Entry -InformationAction Continue }
    }
}

function Invoke-EtlLogRetentionCleanup {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $LogDirectory,
        [Parameter(Mandatory)][ValidateRange(1,3650)][int] $RetentionDays,
        [Parameter(Mandatory)][string] $CleanupKey
    )

    if ($Script:EtlLogRetentionState.ContainsKey($CleanupKey)) { return }
    $Script:EtlLogRetentionState[$CleanupKey] = $true

    if (-not (Test-Path -Path $LogDirectory -PathType Container)) { return }

    $Cutoff = (Get-Date).AddDays(-$RetentionDays)
    Get-ChildItem -Path $LogDirectory -File -ErrorAction SilentlyContinue |
        Where-Object { $_.LastWriteTime -lt $Cutoff -and $_.Extension -ieq '.log' } |
        Remove-Item -Force -ErrorAction SilentlyContinue
}

function Initialize-EtlScriptLogContext {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $LogDirectory,
        [Parameter(Mandatory)][string] $LogFile,
        [Parameter()][ValidateSet('DEBUG','INFO','WARN','ERROR')][string] $LogLevel = 'INFO',
        [Parameter()][ValidateRange(1,3650)][int] $RetentionDays = 30,
        [Parameter()][bool] $Append = $true,
        [Parameter()][string] $CleanupKey = 'Script'
    )

    return @{
        LogDirectory = $LogDirectory
        LogFile = $LogFile
        LogLevel = $LogLevel
        RetentionDays = $RetentionDays
        Append = $Append
        HasWrittenFirstLog = $false
        CleanupKey = $CleanupKey
    }
}

function Write-EtlScriptLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][hashtable] $Context,
        [Parameter(Mandatory)][string] $Message,
        [ValidateSet('DEBUG','INFO','WARN','ERROR')][string] $Level = 'INFO'
    )

    try {
        $ConfiguredLogLevel = if ($env:ETL_LOG_LEVEL) { ([string]$env:ETL_LOG_LEVEL).ToUpperInvariant() } else { [string]$Context.LogLevel }
        if ([string]::IsNullOrWhiteSpace($ConfiguredLogLevel)) { $ConfiguredLogLevel = 'INFO' }
        if (-not (Test-EtlLogLevelEnabled -ConfiguredLevel $ConfiguredLogLevel -MessageLevel $Level)) { return }

        if (-not (Test-Path -Path $Context.LogDirectory -PathType Container)) {
            New-Item -Path $Context.LogDirectory -ItemType Directory -Force | Out-Null
        }

        if ($Context.RetentionDays -gt 0) {
            Invoke-EtlLogRetentionCleanup -LogDirectory $Context.LogDirectory -RetentionDays ([int]$Context.RetentionDays) -CleanupKey ([string]$Context.CleanupKey)
        }

        $Timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
        $Entry = "$Timestamp [$Level] $Message"

        if (-not $Context.Append -and -not $Context.HasWrittenFirstLog) {
            Set-Content -Path $Context.LogFile -Value $Entry -Force
        }
        elseif ($Context.HasWrittenFirstLog -or (Test-Path -Path $Context.LogFile -PathType Leaf)) {
            Add-Content -Path $Context.LogFile -Value $Entry
        }
        else {
            Set-Content -Path $Context.LogFile -Value $Entry -Force
        }

        $Context.HasWrittenFirstLog = $true
        Write-EtlMessageStream -Entry $Entry -Level $Level
    }
    catch {
        Write-Warning "Failed to write log entry: $($_.Exception.Message)"
    }
}

function Write-EtlScriptException {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][hashtable] $Context,
        [Parameter(Mandatory)] $ErrorRecord,
        [Parameter()][string] $Prefix = 'Script failure:'
    )

    $Message = if ($ErrorRecord -and $ErrorRecord.Exception) { $ErrorRecord.Exception.Message } else { [string]$ErrorRecord }
    Write-EtlScriptLog -Context $Context -Message "$Prefix $Message" -Level 'ERROR'

    if ($ErrorRecord.InvocationInfo) {
        Write-EtlScriptLog -Context $Context -Message ("Error location: Line {0} | Script: {1}" -f $ErrorRecord.InvocationInfo.ScriptLineNumber, $ErrorRecord.InvocationInfo.ScriptName) -Level 'ERROR'
    }

    if ($ErrorRecord.ScriptStackTrace) {
        Write-EtlScriptLog -Context $Context -Message ("StackTrace: {0}" -f $ErrorRecord.ScriptStackTrace) -Level 'ERROR'
    }
}

Export-ModuleMember -Function `
    Test-EtlLogLevelEnabled, `
    Write-EtlMessageStream, `
    Invoke-EtlLogRetentionCleanup, `
    Initialize-EtlScriptLogContext, `
    Write-EtlScriptLog, `
    Write-EtlScriptException
