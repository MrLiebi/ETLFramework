Set-StrictMode -Version Latest
. (Join-Path -Path (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))) -ChildPath 'TestHelpers.ps1')

Describe 'Wizard.Destinations helper' {
    BeforeAll {
        $script:Module = Import-TestableAsset -RelativePath 'Wizard/Helpers/Wizard.Destinations.ps1' -ModuleName 'Wizard.Destinations.Tests' -AdditionalRelativePaths @(
            'Wizard/Helpers/Wizard.Credentials.ps1',
            'Wizard/Helpers/Wizard.Prompts.ps1'
        )
    }

    AfterAll {
        Remove-TestModuleSafely -Module $script:Module
    }

    Context 'CSV destination configuration' {
        It 'creates a CSV destination in the OUTPUT folder' {
            $script:InputAnswers = [System.Collections.Generic.Queue[string]]::new()
            foreach ($Answer in @('users.csv', ';', 'UTF8')) { [void]$script:InputAnswers.Enqueue($Answer) }
            $script:BooleanAnswers = [System.Collections.Generic.Queue[object]]::new()
            [void]$script:BooleanAnswers.Enqueue($false)

            Mock -ModuleName $script:Module.Name Read-InputValue { $script:InputAnswers.Dequeue() }
            Mock -ModuleName $script:Module.Name Read-BooleanChoice { $script:BooleanAnswers.Dequeue() }

            $Result = Get-DestinationConfigFromWizard -DestinationType 'CSV' -ProjectName 'Demo' -StepId '03'

            $Result.Config.Path | Should -Be 'OUTPUT\users.csv'
            $Result.Config.Append | Should -BeFalse
            $Result.Config.Force | Should -BeTrue
            $Result.CreateOutput | Should -BeTrue
        }
    }

    Context 'MSSQL destination configuration' {
        It 'creates an MSSQL destination with integrated authentication' {
            $script:InputAnswers = [System.Collections.Generic.Queue[string]]::new()
            foreach ($Answer in @('sql01', 'TargetDb', 'dbo', 'Users')) { [void]$script:InputAnswers.Enqueue($Answer) }

            Mock -ModuleName $script:Module.Name Read-InputValue { $script:InputAnswers.Dequeue() }
            Mock -ModuleName $script:Module.Name Read-BooleanChoice { $true }
            Mock -ModuleName $script:Module.Name Read-CredentialTargetConfiguration {
                [PSCustomObject]@{
                    AuthenticationMode = 'Integrated'
                    CredentialTarget   = $null
                    CreateCredential   = $false
                    UserName           = $null
                    Password           = $null
                }
            }

            $Result = Get-DestinationConfigFromWizard -DestinationType 'MSSQL' -ProjectName 'Demo' -StepId '04'

            $Result.Config.Server | Should -Be 'sql01'
            $Result.Config.AuthenticationMode | Should -Be 'Integrated'
            $Result.Config.DropCreate | Should -BeTrue
            $Result.Config.FailOnConversionError | Should -BeFalse
            $Result.CredentialSetup | Should -BeNullOrEmpty
            $Result.CreateOutput | Should -BeFalse
        }
    }
}
