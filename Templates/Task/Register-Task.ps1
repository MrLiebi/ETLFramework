<#
.SYNOPSIS
Registers a Windows Scheduled Task for an ETL pipeline.

.VERSION
23.0.0

.NOTES
User-visible messages use American English spelling.
#>

[CmdletBinding()]
param(
    [string] $TaskName = '__TASK_FULL_NAME__',
    [string] $TaskXmlPath = '.\__TASK_XML_FILE__',
    [string] $RunAsUser = '__RUN_AS_USER__',
    [SecureString] $RunAsPassword,
    [bool] $LogFileAppend = $true,
    [switch] $ShowWarningsInGui
)

function Write-Ui {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $Message,
        [string] $ForegroundColor
    )

    Write-Information -MessageData $Message -InformationAction Continue
}

$ErrorActionPreference = 'Stop'
$StopWatch = [System.Diagnostics.Stopwatch]::StartNew()
$ScriptDirectory = Split-Path -Path $MyInvocation.MyCommand.Path -Parent
$ProjectRootPath = Split-Path -Path $ScriptDirectory -Parent
$ScriptName = (Get-Item -Path $MyInvocation.MyCommand.Path).BaseName
$BuildDate = (Get-Item -Path $MyInvocation.MyCommand.Path).LastWriteTime.ToString('yyyy-MM-dd')
$LogDirectory = Join-Path -Path $ProjectRootPath -ChildPath 'LOG'
$Script:RunId = Get-Date -Format 'yyyyMMdd_HHmmss'
$LogFile = Join-Path -Path $LogDirectory -ChildPath ("{0}_90_{1}.log" -f $Script:RunId, $ScriptName)
$LogFileRetentionDays = 30

$LoggingModulePath = Join-Path -Path $ProjectRootPath -ChildPath 'RUN\Modules\Common\Framework.Logging.psm1'
if (-not (Test-Path -Path $LoggingModulePath -PathType Leaf)) {
    $LoggingModulePath = Join-Path -Path (Split-Path -Path $ScriptDirectory -Parent) -ChildPath 'Modules\Common\Framework.Logging.psm1'
}
Import-Module -Name $LoggingModulePath -Force -ErrorAction Stop
$Script:LogContext = Initialize-EtlScriptLogContext -LogDirectory $LogDirectory -LogFile $LogFile -LogLevel 'INFO' -RetentionDays $LogFileRetentionDays -Append $LogFileAppend -CleanupKey ('Task::{0}' -f $ScriptName)

function Write-Log {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $Message,
        [ValidateSet('DEBUG','INFO','WARN','ERROR')][string] $Level = 'INFO'
    )
    Write-EtlScriptLog -Context $Script:LogContext -Message $Message -Level $Level
}

function Show-WarningPopup {
    param(
        [Parameter(Mandatory)][string] $Message,
        [Parameter(Mandatory)][string] $Title
    )

    if (-not $ShowWarningsInGui) {
        Write-Log "GUI warning suppressed. $Title | $Message" -Level 'DEBUG'
        return
    }

    try {
        Add-Type -AssemblyName PresentationFramework
        [void][System.Windows.MessageBox]::Show($Message, $Title, [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Warning)
    }
    catch {
        Write-Log "Popup could not be displayed: $($_.Exception.Message)" -Level 'WARN'
    }
}


function Convert-SecureStringToPlainText {
    [CmdletBinding()]
    param([Parameter(Mandatory)][SecureString] $SecureString)

    $Bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($SecureString)
    try { return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($Bstr) }
    finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($Bstr) }
}

function Convert-EtlTaskRunPasswordToSecureString {
    [CmdletBinding()]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingConvertToSecureStringWithPlainText', 'ConvertTo-SecureString', Justification = 'Non-interactive task registration uses ETL_TASK_RUNAS_PASSWORD.')]
    param(
        [Parameter(Mandatory)][string] $PlainText
    )

    return ConvertTo-SecureString -String $PlainText -AsPlainText -Force
}

function Split-TaskIdentity {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $FullTaskName
    )

    $Normalized = ([string]$FullTaskName).Trim()
    if ([string]::IsNullOrWhiteSpace($Normalized)) {
        throw 'Task name must not be empty.'
    }

    $Normalized = $Normalized.Trim('\')
    $Segments = @($Normalized -split '\\' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    if ($Segments.Count -eq 0) {
        throw "Failed to parse scheduled task name: $FullTaskName"
    }

    $TaskLeafName = $Segments[-1]
    $TaskPath = if ($Segments.Count -gt 1) {
        '\' + (($Segments[0..($Segments.Count - 2)] -join '\') + '\')
    }
    else {
        '\'
    }

    return @{
        TaskPath = $TaskPath
        TaskName = $TaskLeafName
    }
}

function Get-OrCreateTaskFolder {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] $ScheduleService,
        [Parameter(Mandatory)][string] $TaskPath
    )

    $RootFolder = $ScheduleService.GetFolder('\')
    if ($TaskPath -eq '\') {
        return $RootFolder
    }

    $CurrentFolder = $RootFolder
    $FolderSegments = @($TaskPath.Trim('\') -split '\\' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    foreach ($Segment in $FolderSegments) {
        try {
            $CurrentFolder = $CurrentFolder.GetFolder($Segment)
        }
        catch {
            Write-Log "Creating scheduled task folder: $Segment" -Level 'INFO'
            $CurrentFolder = $CurrentFolder.CreateFolder($Segment, $null)
        }
    }

    return $CurrentFolder
}

function Register-TaskDefinitionWithScheduledTasksModule {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $FullTaskName,
        [Parameter(Mandatory)][string] $TaskXmlPath,
        [Parameter(Mandatory)][string] $RunAsUser,
        [Parameter(Mandatory)][SecureString] $RunAsPassword
    )

    $TaskIdentity = Split-TaskIdentity -FullTaskName $FullTaskName
    $TaskXmlContent = Get-Content -Path $TaskXmlPath -Raw -Encoding Unicode
    $PlainPassword = Convert-SecureStringToPlainText -SecureString $RunAsPassword

    try {
        Import-Module ScheduledTasks -ErrorAction Stop

        if ($TaskIdentity.TaskPath -ne '\') {
            $ScheduleService = New-Object -ComObject 'Schedule.Service'
            try {
                $ScheduleService.Connect()
                [void](Get-OrCreateTaskFolder -ScheduleService $ScheduleService -TaskPath $TaskIdentity.TaskPath)
            }
            finally {
                if ($ScheduleService) {
                    try { [System.Runtime.InteropServices.Marshal]::ReleaseComObject($ScheduleService) | Out-Null } catch { Write-Verbose "Failed to release Schedule.Service COM object: $($_.Exception.Message)" }
                }
            }
        }

        $RegisterParams = @{
            TaskName = $TaskIdentity.TaskName
            Xml      = $TaskXmlContent
            User     = $RunAsUser
            Password = $PlainPassword
            Force    = $true
        }
        if ($TaskIdentity.TaskPath -ne '\') {
            $RegisterParams.TaskPath = $TaskIdentity.TaskPath
        }

        Write-Log "Registering scheduled task via ScheduledTasks module. TaskPath=$($TaskIdentity.TaskPath) | TaskName=$($TaskIdentity.TaskName)" -Level 'INFO'
        Register-ScheduledTask @RegisterParams | Out-Null
        Write-Log "Scheduled task registered successfully via ScheduledTasks module: $FullTaskName" -Level 'INFO'
    }
    catch {
        Write-Log "ScheduledTasks module registration failed, falling back to COM API: $($_.Exception.Message)" -Level 'WARN'
        Register-TaskDefinitionWithCom -FullTaskName $FullTaskName -TaskXmlPath $TaskXmlPath -RunAsUser $RunAsUser -RunAsPassword $RunAsPassword
    }
    finally {
        $PlainPassword = $null
        [System.GC]::Collect()
    }
}

function Register-TaskDefinitionWithCom {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $FullTaskName,
        [Parameter(Mandatory)][string] $TaskXmlPath,
        [Parameter(Mandatory)][string] $RunAsUser,
        [Parameter(Mandatory)][SecureString] $RunAsPassword
    )

    $TaskIdentity = Split-TaskIdentity -FullTaskName $FullTaskName
    $TaskXmlContent = Get-Content -Path $TaskXmlPath -Raw -Encoding Unicode
    $PlainPassword = Convert-SecureStringToPlainText -SecureString $RunAsPassword

    try {
        $ScheduleService = New-Object -ComObject 'Schedule.Service'
        $ScheduleService.Connect()
        $TaskFolder = Get-OrCreateTaskFolder -ScheduleService $ScheduleService -TaskPath $TaskIdentity.TaskPath

        Write-Log "Registering scheduled task via Schedule.Service COM API. TaskPath=$($TaskIdentity.TaskPath) | TaskName=$($TaskIdentity.TaskName)" -Level 'INFO'
        [void]$TaskFolder.RegisterTask(
            $TaskIdentity.TaskName,
            $TaskXmlContent,
            6,
            $RunAsUser,
            $PlainPassword,
            1,
            $null
        )

        Write-Log "Scheduled task registered successfully via COM API: $FullTaskName" -Level 'INFO'
    }
    finally {
        $PlainPassword = $null
        [System.GC]::Collect()
    }
}

function Register-TaskDefinition {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $FullTaskName,
        [Parameter(Mandatory)][string] $TaskXmlPath,
        [Parameter(Mandatory)][string] $RunAsUser,
        [Parameter(Mandatory)][SecureString] $RunAsPassword
    )

    Register-TaskDefinitionWithScheduledTasksModule -FullTaskName $FullTaskName -TaskXmlPath $TaskXmlPath -RunAsUser $RunAsUser -RunAsPassword $RunAsPassword
}

try {
    Write-Log '--- SCRIPT STARTED ---' -Level 'INFO'
    Write-Log "Name: $ScriptName | BuildDate: $BuildDate" -Level 'INFO'
    Write-Log "TaskName: $TaskName" -Level 'INFO'
    Write-Log "RunAsUser: $RunAsUser" -Level 'INFO'
    Write-Log ("ShowWarningsInGui: {0}" -f [bool]$ShowWarningsInGui) -Level 'DEBUG'

    $CurrentIdentity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $CurrentPrincipal = New-Object Security.Principal.WindowsPrincipal($CurrentIdentity)
    $IsAdmin = $CurrentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if (-not $IsAdmin) {
        $AdminMessage = "Register-Task.ps1 must be run with administrator privileges.`n`nPlease start PowerShell as Administrator and run the script again."
        Write-Ui ''
        Write-Ui 'ERROR: Register-Task.ps1 must be started with Administrator rights.' -ForegroundColor Red
        Write-Ui 'Please open PowerShell as Administrator and run the script again.' -ForegroundColor Yellow
        Write-Ui ''
        Write-Log 'Script was not started with Administrator rights.' -Level 'ERROR'
        Show-WarningPopup -Message $AdminMessage -Title 'Administrator rights required'
        exit 1
    }

    if (-not [System.IO.Path]::IsPathRooted($TaskXmlPath)) {
        $TaskXmlPath = Join-Path -Path $ScriptDirectory -ChildPath $TaskXmlPath
    }
    Write-Log "Resolved TaskXmlPath: $TaskXmlPath" -Level 'INFO'

    if (-not (Test-Path -Path $TaskXmlPath -PathType Leaf)) {
        throw "Task XML file not found: $TaskXmlPath"
    }

    if ($null -eq $RunAsPassword) {
        if ($env:ETL_TEST_NONINTERACTIVE -eq '1') {
            if ([string]::IsNullOrWhiteSpace($env:ETL_TASK_RUNAS_PASSWORD)) {
                throw 'Non-interactive mode is enabled, but ETL_TASK_RUNAS_PASSWORD is not set.'
            }

            $RunAsPassword = Convert-EtlTaskRunPasswordToSecureString -PlainText $env:ETL_TASK_RUNAS_PASSWORD
            Write-Log 'RunAs password provided via ETL_TASK_RUNAS_PASSWORD in non-interactive mode.' -Level 'INFO'
        }
        elseif (-not [string]::IsNullOrWhiteSpace($env:ETL_TASK_RUNAS_PASSWORD)) {
            $RunAsPassword = Convert-EtlTaskRunPasswordToSecureString -PlainText $env:ETL_TASK_RUNAS_PASSWORD
            Write-Log 'RunAs password provided via ETL_TASK_RUNAS_PASSWORD (automated host).' -Level 'INFO'
        }
        else {
            Write-Ui ''
            Write-Ui "Enter password for scheduled task account: $RunAsUser" -ForegroundColor Yellow
            $RunAsPassword = Read-Host 'Password' -AsSecureString
        }
    }

    Write-Ui "Registering scheduled task: $TaskName" -ForegroundColor Cyan
    Register-TaskDefinitionWithScheduledTasksModule -FullTaskName $TaskName -TaskXmlPath $TaskXmlPath -RunAsUser $RunAsUser -RunAsPassword $RunAsPassword

    $StopWatch.Stop()
    Write-Log ("Task registration completed successfully in {0}" -f $StopWatch.Elapsed.ToString('hh\:mm\:ss\.fff')) -Level 'INFO'
    exit 0
}
catch {
    $StopWatch.Stop()
    Write-EtlScriptException -Context $Script:LogContext -ErrorRecord $_ -Prefix 'Task registration failed:'
    exit 1
}
finally {
    Write-Log '--- SCRIPT EXECUTION ENDED ---' -Level 'INFO'
}
