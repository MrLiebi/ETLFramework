Set-StrictMode -Version Latest
. (Join-Path -Path (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))) -ChildPath 'TestHelpers.ps1')

Describe 'Wizard.Sources helper' {
    BeforeAll {
        $script:Module = Import-TestableAsset -RelativePath 'Wizard/Helpers/Wizard.Sources.ps1' -ModuleName 'Wizard.Sources.Tests' -AdditionalRelativePaths @(
            'Wizard/Helpers/Wizard.FileSources.ps1',
            'Wizard/Helpers/Wizard.Credentials.ps1',
            'Wizard/Helpers/Wizard.CustomScript.ps1',
            'Wizard/Helpers/Wizard.Prompts.ps1',
            'Wizard/Helpers/Wizard.Paths.ps1'
        )
    }

    AfterAll {
        Remove-TestModuleSafely -Module $script:Module
    }

    Context 'CSV source configuration' {
        It 'builds a CSV source configuration including file handling and wildcard properties' {
            Mock -ModuleName $script:Module.Name Read-FileSourceConfiguration {
                [PSCustomObject]@{ Path = 'INPUT\users.csv'; FilePattern = '*.csv' }
            }
            Mock -ModuleName $script:Module.Name Read-FileSourcePostImportConfiguration {
                [PSCustomObject]@{ BackupAfterImport = $true; BackupPath = 'INPUT\_Backup'; DeleteAfterImport = $false }
            }
            $script:InputAnswers = [System.Collections.Generic.Queue[string]]::new()
            foreach ($Answer in @(';', 'utf-8', '')) { [void]$script:InputAnswers.Enqueue($Answer) }
            Mock -ModuleName $script:Module.Name Read-InputValue { $script:InputAnswers.Dequeue() }

            $Result = Get-SourceConfigFromWizard -SourceType 'CSV' -ProjectName 'Demo' -StepId '01'

            $Result.Config.Path | Should -Be 'INPUT\users.csv'
            $Result.Config.FilePattern | Should -Be '*.csv'
            $Result.Config.Delimiter | Should -Be ';'
            $Result.Config.BackupAfterImport | Should -BeTrue
            $Result.Config.DeleteAfterImport | Should -BeFalse
            $Result.CreateInput | Should -BeTrue
            $Result.Properties | Should -Be @('*')
        }
    }

    Context 'CustomScript source configuration' {
        It 'builds a custom script configuration with parameter forwarding' {
            $ScriptPath = Join-Path -Path $TestDrive -ChildPath 'Get-Users.ps1'
            'param([string]$Environment)' | Set-Content -Path $ScriptPath -Encoding UTF8

            Mock -ModuleName $script:Module.Name Show-CustomScriptContractAndConfirm { $true }
            $script:InputAnswers = [System.Collections.Generic.Queue[string]]::new()
            foreach ($Answer in @($ScriptPath, 'Name,Mail')) { [void]$script:InputAnswers.Enqueue($Answer) }
            Mock -ModuleName $script:Module.Name Read-InputValue { $script:InputAnswers.Dequeue() }
            Mock -ModuleName $script:Module.Name Resolve-NormalizedPath { $ScriptPath }
            Mock -ModuleName $script:Module.Name Test-Path { $true }
            Mock -ModuleName $script:Module.Name Invoke-CustomScriptParameterWizard { @{ Environment = 'Prod' } }

            $Result = Get-SourceConfigFromWizard -SourceType 'CustomScript' -ProjectName 'Demo' -StepId '02'

            $Result.Config.ScriptPath | Should -Be $ScriptPath
            $Result.Config.Parameters.Environment | Should -Be 'Prod'
            $Result.Properties | Should -Be @('Name', 'Mail')
            $Result.CreateInput | Should -BeFalse
        }
    }
}
