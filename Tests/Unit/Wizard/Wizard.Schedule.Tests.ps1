
Set-StrictMode -Version Latest
. (Join-Path -Path (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))) -ChildPath 'TestHelpers.ps1')

Describe 'Wizard.Schedule helpers' {
    BeforeAll {
        $script:OriginalWindir = $env:WINDIR
        if ([string]::IsNullOrWhiteSpace($env:WINDIR)) {
            $env:WINDIR = 'C:\Windows'
        }

        $script:Module = Import-TestableAsset -RelativePath 'Wizard/Helpers/Wizard.Schedule.ps1' -ModuleName 'Wizard.Schedule.Tests' -AdditionalRelativePaths @(
            'Wizard/Helpers/Wizard.Config.ps1',
            'Wizard/Helpers/Wizard.Paths.ps1',
            'Wizard/Helpers/Wizard.ProjectFiles.ps1',
            'Wizard/Helpers/Wizard.Prompts.ps1'
        )
    }

    AfterAll {
        Remove-TestModuleSafely -Module $script:Module
        $env:WINDIR = $script:OriginalWindir
    }



        Context 'Read-ScheduleConfiguration' {
            It 'returns a disabled schedule when task creation is skipped' {
                Mock -ModuleName $script:Module.Name Read-BooleanChoice { $false }
                (Read-ScheduleConfiguration -ProjectName 'Demo').Enabled | Should -BeFalse
            }

            It 'builds a weekly schedule using validated inputs' {
                $script:InputAnswers = [System.Collections.Generic.Queue[string]]::new()
                foreach ($Answer in @('SoftwareOne\ETL', 'Weekly Demo', 'DOMAIN\svc-etl', 'Nightly ETL', 'Monday, Friday')) {
                    [void]$script:InputAnswers.Enqueue($Answer)
                }

                Mock -ModuleName $script:Module.Name Read-BooleanChoice { $true }
                Mock -ModuleName $script:Module.Name Read-Choice { 'Weekly' }
                Mock -ModuleName $script:Module.Name Read-InputValue { $script:InputAnswers.Dequeue() }
                Mock -ModuleName $script:Module.Name Read-ValidatedDateValue { '2026-04-20' }
                Mock -ModuleName $script:Module.Name Read-ValidatedTimeValue { '05:30:00' }
                Mock -ModuleName $script:Module.Name Read-PositiveInteger { 2 }

                $Result = Read-ScheduleConfiguration -ProjectName 'DemoProject'

                $Result.Enabled | Should -BeTrue
                $Result.ScheduleType | Should -Be 'Weekly'
                $Result.WeeksInterval | Should -Be '2'
                $Result.DaysOfWeek | Should -Be @('Monday', 'Friday')
            }
        }

        Context 'New-TaskSchedulerTriggerXml' {
            It 'renders a daily trigger' {
                $Xml = New-TaskSchedulerTriggerXml -Schedule ([PSCustomObject]@{
                    ScheduleType = 'Daily'
                    StartDate    = '2026-04-15'
                    StartTime    = '01:30:00'
                    DaysInterval = '2'
                })

                $Xml | Should -Match '<ScheduleByDay>'
                $Xml | Should -Match '<DaysInterval>2</DaysInterval>'
                $Xml | Should -Match '<StartBoundary>2026-04-15T01:30:00</StartBoundary>'
            }

            It 'renders a weekly trigger with normalized days' {
                $Xml = New-TaskSchedulerTriggerXml -Schedule ([PSCustomObject]@{
                    ScheduleType  = 'Weekly'
                    StartDate     = '2026-04-15'
                    StartTime     = '05:00:00'
                    WeeksInterval = '1'
                    DaysOfWeek    = @('monday', 'Friday')
                })

                $Xml | Should -Match '<ScheduleByWeek>'
                $Xml | Should -Match '<Monday />'
                $Xml | Should -Match '<Friday />'
            }

            It 'renders a one-time trigger' {
                $Xml = New-TaskSchedulerTriggerXml -Schedule ([PSCustomObject]@{
                    ScheduleType = 'Once'
                    StartDate    = '2026-04-15'
                    StartTime    = '23:15:00'
                })

                $Xml | Should -Match '<TimeTrigger>'
                $Xml | Should -Match '<StartBoundary>2026-04-15T23:15:00</StartBoundary>'
            }
        }

        Context 'New-TaskSchedulerXmlContent' {
            It 'builds task scheduler XML with escaped metadata and URI' {
                $Schedule = [PSCustomObject]@{
                    TaskFolder    = 'SoftwareOne\ETL'
                    TaskName      = 'Demo Task'
                    ScheduleType  = 'Daily'
                    StartDate     = '2026-04-15'
                    StartTime     = '01:00:00'
                    Author        = 'DOMAIN\svc-etl'
                    Description   = 'Import A & B'
                    DaysInterval  = '1'
                    WeeksInterval = '1'
                    DaysOfWeek    = @('Monday')
                }

                $Xml = New-TaskSchedulerXmlContent -ProjectName 'Demo' -RunScriptPath 'C:\ETL\RUN\Run-ETL.ps1' -WorkingDirectory 'C:\ETL\RUN' -Schedule $Schedule

                $Xml | Should -Match '<URI>\\SoftwareOne\\ETL\\Demo Task</URI>'
                $Xml | Should -Match 'Import A &amp; B'
                $Xml | Should -Match 'powershell.exe'
                $Xml | Should -Match 'Run-ETL.ps1'
            }
        }

        Context 'New-TaskRegistrationScriptFile' {
            It 'writes a registration helper script from the task template' {
                $TaskDirectory = Join-Path -Path $TestDrive -ChildPath 'TASKREG'
                New-Item -Path $TaskDirectory -ItemType Directory -Force | Out-Null
                $TaskTemplatePath = Join-Path -Path $TestDrive -ChildPath 'Register-Task.Template.ps1'
                @'
Task=__TASK_FULL_NAME__
Xml=__TASK_XML_FILE__
User=__RUN_AS_USER__
'@ | Set-Content -Path $TaskTemplatePath -Encoding UTF8

                $Schedule = [PSCustomObject]@{
                    TaskFolder = 'SoftwareOne\ETL'
                    TaskName   = 'Daily Import'
                    Author     = 'DOMAIN\svc-etl'
                }

                $ScriptPath = New-TaskRegistrationScriptFile -Schedule $Schedule -TaskDirectory $TaskDirectory -TaskTemplatePath $TaskTemplatePath

                Test-Path -Path $ScriptPath -PathType Leaf | Should -BeTrue
                $Content = Get-Content -Path $ScriptPath -Raw
                $Content | Should -Match ([regex]::Escape('SoftwareOne\ETL\Daily Import'))
                $Content | Should -Match 'Daily Import.task.xml'
                $Content | Should -Match ([regex]::Escape('DOMAIN\svc-etl'))
            }
        }

        Context 'New-TaskSchedulerDefinitionFile' {
            It 'writes the generated XML to a task file' {
                $TaskDirectory = Join-Path -Path $TestDrive -ChildPath 'TASK'
                New-Item -Path $TaskDirectory -ItemType Directory -Force | Out-Null

                $Schedule = [PSCustomObject]@{
                    Enabled       = $true
                    TaskFolder    = 'SoftwareOne\ETL'
                    TaskName      = 'Daily Import'
                    ScheduleType  = 'Daily'
                    StartDate     = '2026-04-15'
                    StartTime     = '03:00:00'
                    Author        = 'DOMAIN\svc-etl'
                    Description   = 'ETL Project Run'
                    DaysInterval  = '1'
                    WeeksInterval = '1'
                    DaysOfWeek    = @('Monday')
                }

                $TaskFile = New-TaskSchedulerDefinitionFile -TaskDirectory $TaskDirectory -RunScriptPath 'C:\ETL\RUN\Run-ETL.ps1' -WorkingDirectory 'C:\ETL\RUN' -Schedule $Schedule

                Test-Path -Path $TaskFile -PathType Leaf | Should -BeTrue
                (Get-Content -Path $TaskFile -Encoding Unicode -Raw) | Should -Match '<Task version="1.3"'
            }
        }
}
