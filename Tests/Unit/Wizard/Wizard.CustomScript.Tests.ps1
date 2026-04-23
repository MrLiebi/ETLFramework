Set-StrictMode -Version Latest
. (Join-Path -Path (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))) -ChildPath 'TestHelpers.ps1')

Describe 'Wizard.CustomScript helpers' {
    BeforeAll {
        $script:Module = Import-TestableAsset -RelativePath 'Wizard/Helpers/Wizard.CustomScript.ps1' -ModuleName 'Wizard.CustomScript.Tests'
    }

    AfterAll {
        Remove-TestModuleSafely -Module $script:Module
    }

    Context 'Get-CustomScriptParameterMetadata' {
        It 'parses supported parameter metadata including mandatory flags and defaults' {
            $ScriptPath = Join-Path -Path $TestDrive -ChildPath 'Get-Data.ps1'
            @'
param(
    [Parameter(Mandatory = $true)]
    [string]$Name,
    [switch]$Enabled,
    [string[]]$Tags = @('A','B'),
    [int]$Retries = 3
)
'@ | Set-Content -Path $ScriptPath -Encoding UTF8

            $Metadata = @(Get-CustomScriptParameterMetadata -ScriptPath $ScriptPath)

            $Metadata.Count | Should -Be 4
            ($Metadata | Where-Object Name -eq 'Name').IsMandatory | Should -BeTrue
            ($Metadata | Where-Object Name -eq 'Enabled').IsSwitch | Should -BeTrue
            ($Metadata | Where-Object Name -eq 'Tags').DefaultValue | Should -Be 'A,B'
            ($Metadata | Where-Object Name -eq 'Retries').DefaultValue | Should -Be '3'
        }
    }

    Context 'Read-CustomScriptParameterConfiguration' {
        It 'collects mandatory and selected optional parameters from detected metadata' {
            $ScriptPath = Join-Path -Path $TestDrive -ChildPath 'Invoke-Demo.ps1'
            @'
param(
    [Parameter(Mandatory = $true)]
    [string]$Name,
    [switch]$Enabled,
    [string]$Comment = 'hello'
)
'@ | Set-Content -Path $ScriptPath -Encoding UTF8

            $script:InputAnswers = [System.Collections.Generic.Queue[string]]::new()
            foreach ($Answer in @('Alice', 'Custom comment')) { [void]$script:InputAnswers.Enqueue($Answer) }
            $script:BooleanAnswers = [System.Collections.Generic.Queue[bool]]::new()
            foreach ($Answer in @($true, $true, $true, $true)) { [void]$script:BooleanAnswers.Enqueue($Answer) }

            Mock -ModuleName $script:Module.Name Read-InputValue { $script:InputAnswers.Dequeue() }
            Mock -ModuleName $script:Module.Name Read-BooleanChoice { $script:BooleanAnswers.Dequeue() }

            $Configuration = Read-CustomScriptParameterConfiguration -ScriptPath $ScriptPath -StepId '01'

            $Configuration['Name'] | Should -Be 'Alice'
            $Configuration['Enabled'] | Should -BeTrue
            $Configuration['Comment'] | Should -Be 'Custom comment'
        }

        It 'stores boolean custom script parameters as real booleans' {
            $ScriptPath = Join-Path -Path $TestDrive -ChildPath 'Invoke-Boolean.ps1'
            @'
param(
    [Parameter(Mandatory = $true)]
    [bool]$Enabled,
    [switch]$Flag
)
'@ | Set-Content -Path $ScriptPath -Encoding UTF8

            $script:BooleanAnswers = [System.Collections.Generic.Queue[bool]]::new()
            foreach ($Answer in @($true, $true, $true, $false)) { [void]$script:BooleanAnswers.Enqueue($Answer) }
            Mock -ModuleName $script:Module.Name Read-BooleanChoice { $script:BooleanAnswers.Dequeue() }

            $Configuration = Read-CustomScriptParameterConfiguration -ScriptPath $ScriptPath -StepId '02'

            $Configuration['Enabled'] | Should -BeTrue
            $Configuration['Flag'] | Should -BeFalse
        }
    }

    Context 'Show-CustomScriptContractAndConfirm' {
        It 'returns the confirmation choice from the wizard prompt' {
            Mock -ModuleName $script:Module.Name Read-BooleanChoice { $false }
            Show-CustomScriptContractAndConfirm -StepId '03' | Should -BeFalse
        }
    }

    Context 'Invoke-CustomScriptParameterWizard' {
        It 'delegates to the parameter configuration reader' {
            Mock -ModuleName $script:Module.Name Read-CustomScriptParameterConfiguration { @{ Name = 'Alice' } }

            $Result = Invoke-CustomScriptParameterWizard -ScriptPath 'C:\Temp\Demo.ps1' -StepId '05'
            $Result['Name'] | Should -Be 'Alice'
            Should -Invoke Read-CustomScriptParameterConfiguration -ModuleName $script:Module.Name -Times 1
        }
    }
}
