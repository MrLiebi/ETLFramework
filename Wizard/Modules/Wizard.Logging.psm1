<#
    Dedicated logging module for the ETL Project Wizard.
#>

function Initialize-WizardLogContext {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$LogDirectory,
        [Parameter(Mandatory)][string]$LogFile,
        [ValidateSet('DEBUG','INFO','WARN','ERROR')][string]$LogLevel = 'INFO',
        [ValidateRange(1,3650)][int]$RetentionDays = 30,
        [bool]$Append = $true,
        [string]$CleanupKey = 'ProjectWizard'
    )

    if (-not (Test-Path -LiteralPath $LogDirectory)) {
        New-Item -Path $LogDirectory -ItemType Directory -Force | Out-Null
    }

    if (-not $Append -and (Test-Path -LiteralPath $LogFile)) {
        Remove-Item -LiteralPath $LogFile -Force -ErrorAction SilentlyContinue
    }

    $context = [pscustomobject]@{
        LogDirectory   = $LogDirectory
        LogFile        = $LogFile
        LogLevel       = $LogLevel
        RetentionDays  = $RetentionDays
        CleanupKey     = $CleanupKey
        CleanupDone    = $false
    }

    Invoke-WizardLogCleanup -Context $context
    return $context
}

function Invoke-WizardLogCleanup {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Context
    )

    if ($Context.CleanupDone) {
        return
    }

    $threshold = (Get-Date).AddDays(-1 * [int]$Context.RetentionDays)
    Get-ChildItem -LiteralPath $Context.LogDirectory -Filter '*.log' -File -ErrorAction SilentlyContinue |
        Where-Object { $_.LastWriteTime -lt $threshold } |
        ForEach-Object {
            Remove-Item -LiteralPath $_.FullName -Force -ErrorAction SilentlyContinue
        }

    $Context.CleanupDone = $true
}

function Write-WizardLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Context,
        [Parameter(Mandatory)][string]$Message,
        [ValidateSet('DEBUG','INFO','WARN','ERROR')][string]$Level = 'INFO'
    )

    $levelOrder = @{ DEBUG = 1; INFO = 2; WARN = 3; ERROR = 4 }
    if ($levelOrder[$Level] -lt $levelOrder[$Context.LogLevel]) {
        return
    }

    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $line = '{0} [{1}] {2}' -f $timestamp, $Level, $Message

    switch ($Level) {
        'DEBUG' { Write-Verbose $line }
        'INFO'  { Write-Information -MessageData $line -InformationAction Continue }
        'WARN'  { Write-Warning $line }
        'ERROR' { Write-Warning $line }
    }

    Add-Content -LiteralPath $Context.LogFile -Value $line -Encoding UTF8
}

function Write-WizardException {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Context,
        [Parameter(Mandatory)][System.Management.Automation.ErrorRecord]$ErrorRecord,
        [string]$Prefix = 'ERROR:'
    )

    Write-WizardLog -Context $Context -Message ("{0} {1}" -f $Prefix, $ErrorRecord.Exception.Message) -Level 'ERROR'

    if ($ErrorRecord.InvocationInfo.ScriptLineNumber) {
        Write-WizardLog -Context $Context -Message ("Error location: Line {0} | Script: {1}" -f $ErrorRecord.InvocationInfo.ScriptLineNumber, $ErrorRecord.InvocationInfo.ScriptName) -Level 'ERROR'
    }

    if ($ErrorRecord.ScriptStackTrace) {
        Write-WizardLog -Context $Context -Message ("StackTrace: {0}" -f $ErrorRecord.ScriptStackTrace) -Level 'ERROR'
    }
}

Export-ModuleMember -Function Initialize-WizardLogContext, Write-WizardLog, Write-WizardException
