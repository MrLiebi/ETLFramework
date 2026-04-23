<#
    Helper functions for New-ETLProject.ps1.
    File: Wizard.Schedule.ps1
#>

function Read-ScheduleConfiguration {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory)][string] $ProjectName
    )

    $CreateTask = Read-BooleanChoice -Prompt "Create Windows Task Scheduler XML for this project?" -Default $true

    if (-not $CreateTask) {
        return [PSCustomObject]@{
            Enabled = $false
        }
    }

    $TaskFolder    = Read-InputValue -Prompt '  > Task Folder' -Default 'SoftwareOne\ETL'
    $TaskName      = Read-InputValue -Prompt '  > Task Name' -Default $ProjectName
    $ScheduleType  = Read-Choice -Title 'SCHEDULE TYPE' -Options @('Daily', 'Weekly', 'Once')
    $StartDate     = Read-ValidatedDateValue -Prompt '  > Start Date (yyyy-MM-dd)' -Default (Get-Date -Format 'yyyy-MM-dd')
    $StartTime     = Read-ValidatedTimeValue -Prompt '  > Start Time (HH:mm:ss)' -Default '01:00:00'
    $Author        = Read-InputValue -Prompt '  > Task Author / UserId' -Default "$env:USERDOMAIN\$env:USERNAME"
    $Description   = Read-InputValue -Prompt '  > Task Description' -Default ("ETL Project Run - {0}" -f $ProjectName)

    $DaysInterval  = '1'
    $WeeksInterval = '1'
    $DaysOfWeek    = @('Monday')

    switch ($ScheduleType) {
        'Daily' {
            $DaysInterval = [string](Read-PositiveInteger -Prompt '  > Repeat every X day(s)' -Default 1)
        }
        'Weekly' {
            $WeeksInterval = [string](Read-PositiveInteger -Prompt '  > Repeat every X week(s)' -Default 1)
            $DaySelection = Read-InputValue -Prompt '  > Days of week (comma-separated, e.g. Monday,Wednesday,Friday)' -Default 'Monday'
            $DaysOfWeek = Get-ValidatedDaysOfWeek -DaysOfWeek @($DaySelection -split ',')
        }
        'Once' { }
    }

    return [PSCustomObject]@{
        Enabled       = $true
        TaskFolder    = $TaskFolder
        TaskName      = $TaskName
        ScheduleType  = $ScheduleType
        StartDate     = $StartDate
        StartTime     = $StartTime
        Author        = $Author
        Description   = $Description
        DaysInterval  = $DaysInterval
        WeeksInterval = $WeeksInterval
        DaysOfWeek    = $DaysOfWeek
    }
}

function New-TaskSchedulerTriggerXml {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory)][pscustomobject] $Schedule
    )

    $ValidatedStartDate = [datetime]::ParseExact([string]$Schedule.StartDate, 'yyyy-MM-dd', [System.Globalization.CultureInfo]::InvariantCulture)
    $ValidatedStartTime = [datetime]::ParseExact([string]$Schedule.StartTime, 'HH:mm:ss', [System.Globalization.CultureInfo]::InvariantCulture)
    $StartBoundary = "{0}T{1}" -f $ValidatedStartDate.ToString('yyyy-MM-dd', [System.Globalization.CultureInfo]::InvariantCulture), $ValidatedStartTime.ToString('HH:mm:ss', [System.Globalization.CultureInfo]::InvariantCulture)

    switch ($Schedule.ScheduleType) {
        'Daily' {
            return @"
    <CalendarTrigger>
      <StartBoundary>$StartBoundary</StartBoundary>
      <Enabled>true</Enabled>
      <ScheduleByDay>
        <DaysInterval>$($Schedule.DaysInterval)</DaysInterval>
      </ScheduleByDay>
    </CalendarTrigger>
"@
        }
        'Weekly' {
            $NormalizedDaysOfWeek = Get-ValidatedDaysOfWeek -DaysOfWeek @($Schedule.DaysOfWeek)
            $DaysXml = ($NormalizedDaysOfWeek | ForEach-Object { "          <$_ />" }) -join "`r`n"
            return @"
    <CalendarTrigger>
      <StartBoundary>$StartBoundary</StartBoundary>
      <Enabled>true</Enabled>
      <ScheduleByWeek>
        <WeeksInterval>$($Schedule.WeeksInterval)</WeeksInterval>
        <DaysOfWeek>
$DaysXml
        </DaysOfWeek>
      </ScheduleByWeek>
    </CalendarTrigger>
"@
        }
        'Once' {
            return @"
    <TimeTrigger>
      <StartBoundary>$StartBoundary</StartBoundary>
      <Enabled>true</Enabled>
    </TimeTrigger>
"@
        }
        default {
            throw "Unsupported schedule type: $($Schedule.ScheduleType)"
        }
    }
}

function New-TaskSchedulerXmlContent {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory)][string] $ProjectName,
        [Parameter(Mandatory)][string] $RunScriptPath,
        [Parameter(Mandatory)][string] $WorkingDirectory,
        [Parameter(Mandatory)][pscustomobject] $Schedule
    )

    $TriggerXml = New-TaskSchedulerTriggerXml -Schedule $Schedule
    $ExecutionTimeLimit = 'PT12H'
    $Command = "$env:WINDIR\System32\WindowsPowerShell\v1.0\powershell.exe"
    $Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$RunScriptPath`""

    $TaskFolderNormalized = ([string]$Schedule.TaskFolder).Trim('\')
    if ([string]::IsNullOrWhiteSpace($TaskFolderNormalized)) {
        $TaskUri = "\" + $Schedule.TaskName
    }
    else {
        $TaskUri = "\" + $TaskFolderNormalized + "\" + $Schedule.TaskName
    }

    $AuthorEscaped = ConvertTo-XmlEscapedValue -Value $Schedule.Author
    $DescriptionEscaped = ConvertTo-XmlEscapedValue -Value $Schedule.Description
    $WorkingDirectoryEscaped = ConvertTo-XmlEscapedValue -Value $WorkingDirectory
    $CommandEscaped = ConvertTo-XmlEscapedValue -Value $Command
    $ArgumentsEscaped = ConvertTo-XmlEscapedValue -Value $Arguments
    $UserIdEscaped = ConvertTo-XmlEscapedValue -Value $Schedule.Author
    $UriEscaped = ConvertTo-XmlEscapedValue -Value $TaskUri

    return @"
<?xml version="1.0" encoding="UTF-16"?>
<Task version="1.3" xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task">
  <RegistrationInfo>
    <Author>$AuthorEscaped</Author>
    <Description>$DescriptionEscaped</Description>
    <URI>$UriEscaped</URI>
  </RegistrationInfo>
  <Triggers>
$TriggerXml
  </Triggers>
  <Principals>
    <Principal id="Author">
      <UserId>$UserIdEscaped</UserId>
      <LogonType>Password</LogonType>
      <RunLevel>HighestAvailable</RunLevel>
    </Principal>
  </Principals>
  <Settings>
    <MultipleInstancesPolicy>IgnoreNew</MultipleInstancesPolicy>
    <DisallowStartIfOnBatteries>false</DisallowStartIfOnBatteries>
    <StopIfGoingOnBatteries>false</StopIfGoingOnBatteries>
    <AllowHardTerminate>true</AllowHardTerminate>
    <StartWhenAvailable>true</StartWhenAvailable>
    <RunOnlyIfNetworkAvailable>false</RunOnlyIfNetworkAvailable>
    <IdleSettings>
      <StopOnIdleEnd>false</StopOnIdleEnd>
      <RestartOnIdle>false</RestartOnIdle>
    </IdleSettings>
    <AllowStartOnDemand>true</AllowStartOnDemand>
    <Enabled>true</Enabled>
    <Hidden>false</Hidden>
    <RunOnlyIfIdle>false</RunOnlyIfIdle>
    <WakeToRun>false</WakeToRun>
    <ExecutionTimeLimit>$ExecutionTimeLimit</ExecutionTimeLimit>
    <Priority>7</Priority>
  </Settings>
  <Actions Context="Author">
    <Exec>
      <Command>$CommandEscaped</Command>
      <Arguments>$ArgumentsEscaped</Arguments>
      <WorkingDirectory>$WorkingDirectoryEscaped</WorkingDirectory>
    </Exec>
  </Actions>
</Task>
"@
}

function New-TaskSchedulerDefinitionFile {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory)][string] $TaskDirectory,
        [Parameter(Mandatory)][string] $RunScriptPath,
        [Parameter(Mandatory)][string] $WorkingDirectory,
        [Parameter(Mandatory)][pscustomobject] $Schedule
    )

    if (-not $Schedule.Enabled) {
        Write-Log "Task XML generation skipped by user." -Level "WARN"
        return $null
    }

    $SafeTaskFileName = Get-SafePathSegment -Value ([string]$Schedule.TaskName) -Fallback 'ETL-Task'
    if ($SafeTaskFileName -ne [string]$Schedule.TaskName) {
        Write-Log "Task name normalized for XML file path from [$($Schedule.TaskName)] to [$SafeTaskFileName]." -Level 'WARN'
    }

    $TaskFilePath = Join-Path -Path $TaskDirectory -ChildPath ("{0}.task.xml" -f $SafeTaskFileName)
    $XmlContent = New-TaskSchedulerXmlContent `
        -ProjectName $Schedule.TaskName `
        -RunScriptPath $RunScriptPath `
        -WorkingDirectory $WorkingDirectory `
        -Schedule $Schedule

    Assert-NoUnresolvedTemplateTokens -Content $XmlContent -Description 'task scheduler XML'
    Set-Content -Path $TaskFilePath -Value $XmlContent -Encoding Unicode
    Write-Log "Task Scheduler XML created: $TaskFilePath" -Level "INFO"
    return $TaskFilePath
}

function New-TaskRegistrationScriptFile {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory)][pscustomobject] $Schedule,
        [Parameter(Mandatory)][string] $TaskDirectory,
        [Parameter(Mandatory)][string] $TaskTemplatePath
    )

    if (-not (Test-PathExists -Path $TaskTemplatePath -PathType Leaf -Description 'Task registration template')) {
        throw "Task registration template missing: $TaskTemplatePath"
    }

    $NormalizedTaskFolder = ([string]$Schedule.TaskFolder).Trim('\')
    if ([string]::IsNullOrWhiteSpace($NormalizedTaskFolder)) {
        $FullTaskName = $Schedule.TaskName
    }
    else {
        $FullTaskName = "{0}\{1}" -f $NormalizedTaskFolder, $Schedule.TaskName
    }

    $TaskXmlFile = "{0}.task.xml" -f (Get-SafePathSegment -Value ([string]$Schedule.TaskName) -Fallback 'ETL-Task')
    $DefaultRunAsUser = $Schedule.Author

    $Content = Get-Content -Path $TaskTemplatePath -Raw
    $Content = $Content.Replace('__TASK_FULL_NAME__', $FullTaskName)
    $Content = $Content.Replace('__TASK_XML_FILE__', $TaskXmlFile)
    $Content = $Content.Replace('__RUN_AS_USER__', $DefaultRunAsUser)

    Assert-NoUnresolvedTemplateTokens -Content $Content -Description 'task registration helper script'

    $ScriptPath = Join-Path -Path $TaskDirectory -ChildPath 'Register-Task.ps1'
    Set-Content -Path $ScriptPath -Value $Content -Encoding UTF8

    $WrittenContent = Get-Content -Path $ScriptPath -Raw
    Assert-NoUnresolvedTemplateTokens -Content $WrittenContent -Description 'written task registration helper script'
    Write-Log "Task registration helper script created from template: $ScriptPath" -Level "INFO"
    return $ScriptPath
}

