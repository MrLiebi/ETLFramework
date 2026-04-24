Set-StrictMode -Version Latest
. (Join-Path -Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) -ChildPath 'TestHelpers.ps1')
$script:Module = $null

Describe 'Wizard.ProjectWizard helper' {
    BeforeAll {
        . (Join-Path -Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) -ChildPath 'TestHelpers.ps1')
        $script:Module = Import-TestableAsset -RelativePath 'Wizard/Helpers/Wizard.ProjectWizard.ps1' -ModuleName 'Wizard.ProjectWizard.Tests' -AdditionalRelativePaths @(
            'Wizard/Helpers/Wizard.LogFacade.ps1',
            'Wizard/Helpers/Wizard.Paths.ps1',
            'Wizard/Helpers/Wizard.Prompts.ps1',
            'Wizard/Helpers/Wizard.CustomScript.ps1',
            'Wizard/Helpers/Wizard.FileSources.ps1',
            'Wizard/Helpers/Wizard.Config.ps1',
            'Wizard/Helpers/Wizard.ProjectFiles.ps1',
            'Wizard/Helpers/Wizard.Credentials.ps1',
            'Wizard/Helpers/Wizard.Sources.ps1',
            'Wizard/Helpers/Wizard.Destinations.ps1',
            'Wizard/Helpers/Wizard.Adapter.ps1',
            'Wizard/Helpers/Wizard.Schedule.ps1'
        )
        $script:FrameworkRoot = Get-FrameworkRoot
        $script:ScriptPath = Join-Path -Path $script:FrameworkRoot -ChildPath 'New-ETLProject.ps1'
        Set-EtlFrameworkTestHostDefaults -Full
    }

    AfterAll {
        . (Join-Path -Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) -ChildPath 'TestHelpers.ps1')
        if ($script:Module) {
            Remove-TestModuleSafely -Module $script:Module
        }
    }

    BeforeEach {
        # Restore automation env after any test that called Disable-EtlFrameworkWizardAutomation*;
        # otherwise real Read-Choice + mocked Read-Host '' loops forever.
        Set-EtlFrameworkTestHostDefaults -Full
        Mock -ModuleName $script:Module.Name Clear-Host {}
        Mock -ModuleName $script:Module.Name Write-Host {}
        Mock -ModuleName $script:Module.Name Read-BooleanChoice { $false }
        Mock -ModuleName $script:Module.Name Read-Host { '' }
        Mock -ModuleName $script:Module.Name Initialize-WizardLogContext {
            [PSCustomObject]@{ LogFile = $LogFile; LogDirectory = $LogDirectory }
        }
        Mock -ModuleName $script:Module.Name Write-WizardException {}
        Mock -ModuleName $script:Module.Name Unblock-File {}
    }

    It 'creates a minimal CSV project when adapter and schedule are skipped' {
        $Base = Join-Path -Path $TestDrive -ChildPath 'Base'
        New-Item -Path $Base -ItemType Directory -Force | Out-Null

        $InputAnswers = [System.Collections.Generic.Queue[string]]::new()
        foreach ($Value in @('DemoCsv', $Base, 'ImportUsers')) { [void]$InputAnswers.Enqueue($Value) }
        Mock -ModuleName $script:Module.Name Read-InputValue { $InputAnswers.Dequeue() }

        $IntAnswers = [System.Collections.Generic.Queue[int]]::new()
        foreach ($Value in @(1, 14)) { [void]$IntAnswers.Enqueue($Value) }
        Mock -ModuleName $script:Module.Name Read-PositiveInteger { $IntAnswers.Dequeue() }

        $ChoiceAnswers = [System.Collections.Generic.Queue[string]]::new()
        foreach ($Value in @('INFO', 'CSV', 'CSV')) { [void]$ChoiceAnswers.Enqueue($Value) }
        Mock -ModuleName $script:Module.Name Read-Choice { $ChoiceAnswers.Dequeue() }

        Mock -ModuleName $script:Module.Name Get-SourceConfigFromWizard {
            [PSCustomObject]@{
                Config = [ordered]@{
                    Path = 'INPUT\users.csv'
                    FilePattern = '*.csv'
                    Delimiter = ';'
                    Encoding = 'utf-8'
                    BackupAfterImport = $true
                    BackupPath = 'INPUT\_Backup'
                    DeleteAfterImport = $false
                }
                Properties = @('*')
                CreateInput = $true
                CredentialSetup = $null
            }
        }
        Mock -ModuleName $script:Module.Name Get-DestinationConfigFromWizard {
            [PSCustomObject]@{
                Config = [ordered]@{
                    Path = 'OUTPUT\users.csv'
                    Delimiter = ';'
                    Encoding = 'utf-8'
                    Append = $false
                }
                CreateOutput = $true
                CredentialSetup = $null
            }
        }
        Mock -ModuleName $script:Module.Name Read-AdapterConfiguration { [PSCustomObject]@{ AdapterEnabled = $false; Config = [ordered]@{ AdapterEnabled = $false } } }
        Mock -ModuleName $script:Module.Name Read-ScheduleConfiguration { [PSCustomObject]@{ Enabled = $false } }
        Mock -ModuleName $script:Module.Name Initialize-ProjectCredential {}

        $ExitCode = Invoke-NewEtlProjectWizard -ScriptPath $script:ScriptPath -ScriptDirectory $script:FrameworkRoot -DefaultBaseDirectory $Base -RequireDotNet:$false

        $ProjectRoot = Join-Path -Path $Base -ChildPath 'DemoCsv'
        $ExitCode | Should -Be 0
        Test-Path -Path (Join-Path $ProjectRoot 'RUN\config.psd1') | Should -BeTrue
        Test-Path -Path (Join-Path $ProjectRoot 'RUN\Run-ETL.ps1') | Should -BeTrue
        Test-Path -Path (Join-Path $ProjectRoot 'INPUT') | Should -BeTrue
        Test-Path -Path (Join-Path $ProjectRoot 'INPUT\_Backup') | Should -BeTrue
        Test-Path -Path (Join-Path $ProjectRoot 'OUTPUT') | Should -BeTrue
        Test-Path -Path (Join-Path $ProjectRoot 'TASK') | Should -BeTrue
        $ConfigContent = Get-Content -Path (Join-Path $ProjectRoot 'RUN\config.psd1') -Raw
        $ConfigContent | Should -Match 'ImportUsers'
        $ConfigContent | Should -Match 'users\.csv'
        $ConfigContent | Should -Match 'AdapterEnabled = \$false'
    }

    It 'creates adapter, schedule, xlsx runtime and custom script artifacts for multi-step projects' {
        $Base = Join-Path -Path $TestDrive -ChildPath 'AdvancedBase'
        New-Item -Path $Base -ItemType Directory -Force | Out-Null
        $ScriptSource = Join-Path -Path $TestDrive -ChildPath 'Get-Users.ps1'
        'param([string]$Environment) [pscustomobject]@{ Name = "Alice" }' | Set-Content -Path $ScriptSource -Encoding UTF8

        $InputAnswers = [System.Collections.Generic.Queue[string]]::new()
        foreach ($Value in @('AdvancedProject', $Base, 'LoadWorkbook', 'RunCustom')) { [void]$InputAnswers.Enqueue($Value) }
        Mock -ModuleName $script:Module.Name Read-InputValue { $InputAnswers.Dequeue() }

        $IntAnswers = [System.Collections.Generic.Queue[int]]::new()
        foreach ($Value in @(2, 7)) { [void]$IntAnswers.Enqueue($Value) }
        Mock -ModuleName $script:Module.Name Read-PositiveInteger { $IntAnswers.Dequeue() }

        $ChoiceAnswers = [System.Collections.Generic.Queue[string]]::new()
        foreach ($Value in @('DEBUG', 'XLSX', 'MSSQL', 'CustomScript', 'CSV')) { [void]$ChoiceAnswers.Enqueue($Value) }
        Mock -ModuleName $script:Module.Name Read-Choice { $ChoiceAnswers.Dequeue() }

        Mock -ModuleName $script:Module.Name Get-SourceConfigFromWizard {
            param($SourceType)
            switch ($SourceType) {
                'XLSX' {
                    return [PSCustomObject]@{
                        Config = [ordered]@{ Path = 'INPUT\users.xlsx'; FilePattern = '*.xlsx'; Worksheet = 'Users' }
                        Properties = @('Name','Mail')
                        CreateInput = $true
                        CredentialSetup = $null
                    }
                }
                'CustomScript' {
                    return [PSCustomObject]@{
                        Config = [ordered]@{ ScriptPath = $ScriptSource; Parameters = [ordered]@{ Environment = 'Prod' } }
                        Properties = @('Name','Mail')
                        CreateInput = $false
                        CredentialSetup = $null
                    }
                }
            }
        }
        Mock -ModuleName $script:Module.Name Get-DestinationConfigFromWizard {
            param($DestinationType)
            switch ($DestinationType) {
                'MSSQL' {
                    return [PSCustomObject]@{
                        Config = [ordered]@{ Server = 'sql01'; Database = 'DW'; AuthenticationMode = 'Integrated' }
                        CreateOutput = $false
                        CredentialSetup = $null
                    }
                }
                'CSV' {
                    return [PSCustomObject]@{
                        Config = [ordered]@{ Path = 'OUTPUT\result.csv'; Delimiter = ';'; Encoding = 'utf-8' }
                        CreateOutput = $true
                        CredentialSetup = $null
                    }
                }
            }
        }
        Mock -ModuleName $script:Module.Name Initialize-ProjectCredential {}
        Mock -ModuleName $script:Module.Name Read-AdapterConfiguration {
            [PSCustomObject]@{
                AdapterEnabled = $true
                AdapterName = 'AdvancedProject'
                ConnectionString = 'Integrated Security=SSPI;Persist Security Info=False;Initial Catalog=FNMSStaging;Data Source=localhost'
                XmlFileName = 'Adapter.BAS.xml'
                Config = [ordered]@{ AdapterEnabled = $true; ConfigFile = 'Adapter.BAS.xml' }
            }
        }
        Mock -ModuleName $script:Module.Name Read-ScheduleConfiguration {
            [PSCustomObject]@{
                Enabled = $true
                TaskFolder = 'SoftwareOne\ETL'
                TaskName = 'AdvancedProject'
                ScheduleType = 'Daily'
                StartDate = '2026-01-01'
                StartTime = '01:00:00'
                Author = 'DOMAIN\svc-etl'
                Description = 'ETL Project Run - AdvancedProject'
                DaysInterval = '1'
                WeeksInterval = '1'
                DaysOfWeek = @('Monday')
            }
        }

        $ExitCode = Invoke-NewEtlProjectWizard -ScriptPath $script:ScriptPath -ScriptDirectory $script:FrameworkRoot -DefaultBaseDirectory $Base -RequireDotNet:$false

        $ProjectRoot = Join-Path -Path $Base -ChildPath 'AdvancedProject'
        $ExitCode | Should -Be 0
        Test-Path -Path (Join-Path $ProjectRoot 'PS') | Should -BeTrue
        Test-Path -Path (Join-Path $ProjectRoot 'RUN\Modules\Dependencies\ExcelDataReader') | Should -BeTrue
        Test-Path -Path (Join-Path $ProjectRoot 'RUN\Modules\Adapter\Adapter.BAS.xml') | Should -BeTrue
        Test-Path -Path (Join-Path $ProjectRoot 'TASK\AdvancedProject.task.xml') | Should -BeTrue
        Test-Path -Path (Join-Path $ProjectRoot 'TASK\Register-Task.ps1') | Should -BeTrue
        Assert-MockCalled -CommandName Initialize-ProjectCredential -ModuleName $script:Module.Name -Times 0 -Exactly
        (Get-Content -Path (Join-Path $ProjectRoot 'RUN\config.psd1') -Raw) | Should -Match 'RunCustom'
        $CustomScriptCopy = Join-Path $ProjectRoot 'PS\Step_02_RunCustom_Get-Users.ps1'
        Test-Path -Path $CustomScriptCopy | Should -BeTrue
        (Get-Content -Path $CustomScriptCopy -Raw) | Should -Match 'param'
    }

    It 'returns success without overwriting when the existing target directory is declined' {
        $Base = Join-Path -Path $TestDrive -ChildPath 'ExistingBase'
        $ProjectRoot = Join-Path -Path $Base -ChildPath 'ExistingProject'
        New-Item -Path $ProjectRoot -ItemType Directory -Force | Out-Null
        New-Item -Path (Join-Path $ProjectRoot 'sentinel.txt') -ItemType File -Force | Out-Null

        $InputAnswers = [System.Collections.Generic.Queue[string]]::new()
        foreach ($Value in @('ExistingProject', $Base)) { [void]$InputAnswers.Enqueue($Value) }
        Mock -ModuleName $script:Module.Name Read-InputValue { $InputAnswers.Dequeue() }
        Mock -ModuleName $script:Module.Name Read-BooleanChoice { $false }
        Mock -ModuleName $script:Module.Name Test-DirectoryWritable {}

        $ExitCode = Invoke-NewEtlProjectWizard -ScriptPath $script:ScriptPath -ScriptDirectory $script:FrameworkRoot -DefaultBaseDirectory $Base -RequireDotNet:$false

        $ExitCode | Should -Be 0
        Test-Path -Path (Join-Path $ProjectRoot 'sentinel.txt') | Should -BeTrue
        Test-Path -Path (Join-Path $ProjectRoot 'RUN') | Should -BeFalse
    }

    It 'returns a failure exit code when template validation fails' {
        Mock -ModuleName $script:Module.Name Test-PathExists {
            param($Path, $PathType, $Description)
            if ($Description -eq 'Template root directory') { return $false }
            return $true
        }
        Mock -ModuleName $script:Module.Name Initialize-WizardLogContext { [PSCustomObject]@{ } }
        Mock -ModuleName $script:Module.Name Write-WizardException {}

        $ExitCode = Invoke-NewEtlProjectWizard -ScriptPath $script:ScriptPath -ScriptDirectory $script:FrameworkRoot -RequireDotNet:$false

        $ExitCode | Should -Be 1
        Assert-MockCalled -CommandName Write-WizardException -ModuleName $script:Module.Name -Times 1 -Exactly
    }

    It 'discovers source and destination adapter types from template modules' {
        Mock -ModuleName $script:Module.Name Get-AvailableSourceTypes { @('CSV', 'JSON', 'XLSX') }
        Mock -ModuleName $script:Module.Name Get-AvailableDestinationTypes { @('CSV', 'MSSQL') }

        $Base = Join-Path -Path $TestDrive -ChildPath 'DynamicDiscoveryBase'
        New-Item -Path $Base -ItemType Directory -Force | Out-Null

        $InputAnswers = [System.Collections.Generic.Queue[string]]::new()
        foreach ($Value in @('DynamicProject', $Base, 'Step-01')) { [void]$InputAnswers.Enqueue($Value) }
        Mock -ModuleName $script:Module.Name Read-InputValue { $InputAnswers.Dequeue() }

        $IntAnswers = [System.Collections.Generic.Queue[int]]::new()
        foreach ($Value in @(1, 30)) { [void]$IntAnswers.Enqueue($Value) }
        Mock -ModuleName $script:Module.Name Read-PositiveInteger { $IntAnswers.Dequeue() }

        $ChoiceAnswers = [System.Collections.Generic.Queue[string]]::new()
        foreach ($Value in @('INFO', 'JSON', 'MSSQL')) { [void]$ChoiceAnswers.Enqueue($Value) }
        Mock -ModuleName $script:Module.Name Read-Choice { $ChoiceAnswers.Dequeue() }

        Mock -ModuleName $script:Module.Name Get-SourceConfigFromWizard {
            [PSCustomObject]@{
                Config = [ordered]@{ Path = 'INPUT\users.json'; FilePattern = '*.json' }
                Properties = @('*')
                CreateInput = $true
                CredentialSetup = $null
            }
        }
        Mock -ModuleName $script:Module.Name Get-DestinationConfigFromWizard {
            [PSCustomObject]@{
                Config = [ordered]@{ Server = 'sql01'; Database = 'DW'; AuthenticationMode = 'Integrated'; TableName = 'Users' }
                CreateOutput = $false
                CredentialSetup = $null
            }
        }
        Mock -ModuleName $script:Module.Name Read-AdapterConfiguration { [PSCustomObject]@{ AdapterEnabled = $false; Config = [ordered]@{ AdapterEnabled = $false } } }
        Mock -ModuleName $script:Module.Name Read-ScheduleConfiguration { [PSCustomObject]@{ Enabled = $false } }
        Mock -ModuleName $script:Module.Name Initialize-ProjectCredential {}

        $ExitCode = Invoke-NewEtlProjectWizard -ScriptPath $script:ScriptPath -ScriptDirectory $script:FrameworkRoot -DefaultBaseDirectory $Base -RequireDotNet:$false

        $ExitCode | Should -Be 0
        Assert-MockCalled -CommandName Get-AvailableSourceTypes -ModuleName $script:Module.Name -Times 1 -Exactly
        Assert-MockCalled -CommandName Get-AvailableDestinationTypes -ModuleName $script:Module.Name -Times 1 -Exactly
        Assert-MockCalled -CommandName Get-SourceConfigFromWizard -ModuleName $script:Module.Name -Times 1 -Exactly -ParameterFilter { $SourceType -eq 'JSON' }
        Assert-MockCalled -CommandName Get-DestinationConfigFromWizard -ModuleName $script:Module.Name -Times 1 -Exactly -ParameterFilter { $DestinationType -eq 'MSSQL' }
    }
}
