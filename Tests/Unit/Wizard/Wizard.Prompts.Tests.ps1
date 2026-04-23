Set-StrictMode -Version Latest
. (Join-Path -Path (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))) -ChildPath 'TestHelpers.ps1')

Describe 'Wizard.Prompts helpers' {
    BeforeAll {
        Disable-EtlFrameworkWizardAutomationForInteractivePromptTests
        $script:Module = Import-TestableAsset -RelativePath 'Wizard/Helpers/Wizard.Prompts.ps1' -ModuleName 'Wizard.Prompts.Tests'
    }

    AfterAll {
        Remove-TestModuleSafely -Module $script:Module
        Enable-EtlFrameworkWizardAutomationAfterInteractivePromptTests
    }

    Context 'Read-InputValue' {
        It 'returns the default value when the user enters nothing' {
            Mock -ModuleName $script:Module.Name Read-Host { '' }
            Read-InputValue -Prompt 'Project Name' -Default 'MyETL' | Should -Be 'MyETL'
        }
    }

    Context 'Read-BooleanChoice' {
        It 'returns the default when the response is empty' {
            Mock -ModuleName $script:Module.Name Read-Host { '' }
            Read-BooleanChoice -Prompt 'Continue?' -Default $false | Should -BeFalse
        }
    }

    Context 'Read-PositiveInteger' {
        It 'retries until a valid positive integer is entered' {
            $script:Responses = [System.Collections.Generic.Queue[string]]::new()
            foreach ($Response in @('abc', '0', '3')) { [void]$script:Responses.Enqueue($Response) }
            Mock -ModuleName $script:Module.Name Read-Host { $script:Responses.Dequeue() }

            Read-PositiveInteger -Prompt 'Count' -Default 1 | Should -Be 3
        }
    }



    Context 'Read-NonNegativeInteger' {
        It 'retries until a valid non-negative integer is entered' {
            $script:Responses = [System.Collections.Generic.Queue[string]]::new()
            foreach ($Response in @('-1', 'abc', '0')) { [void]$script:Responses.Enqueue($Response) }
            Mock -ModuleName $script:Module.Name Read-Host { $script:Responses.Dequeue() }

            Read-NonNegativeInteger -Prompt 'Retry count' -Default 1 | Should -Be 0
        }
    }

    Context 'Read-ValidatedDateValue' {
        It 'retries until the entered date matches the expected format' {
            $script:Responses = [System.Collections.Generic.Queue[string]]::new()
            foreach ($Response in @('16.04.2026', '2026-04-16')) { [void]$script:Responses.Enqueue($Response) }
            Mock -ModuleName $script:Module.Name Read-InputValue { $script:Responses.Dequeue() }

            Read-ValidatedDateValue -Prompt 'Date' -Default '2026-04-15' | Should -Be '2026-04-16'
        }
    }



    Context 'Read-ValidatedTimeValue' {
        It 'retries until the entered time matches the expected format' {
            $script:Responses = [System.Collections.Generic.Queue[string]]::new()
            foreach ($Response in @('1:00', '01:00:00')) { [void]$script:Responses.Enqueue($Response) }
            Mock -ModuleName $script:Module.Name Read-InputValue { $script:Responses.Dequeue() }

            Read-ValidatedTimeValue -Prompt 'Time' -Default '00:30:00' | Should -Be '01:00:00'
        }
    }

    Context 'Get-ValidatedDaysOfWeek' {
        It 'normalizes and de-duplicates configured day names' {
            $Result = Get-ValidatedDaysOfWeek -DaysOfWeek @('monday', 'Friday', 'MONDAY')
            $Result | Should -Be @('Monday', 'Friday')
        }

        It 'throws for unsupported day names' {
            { Get-ValidatedDaysOfWeek -DaysOfWeek @('Funday') } | Should -Throw '*Unsupported day of week*'
        }
    }
}
