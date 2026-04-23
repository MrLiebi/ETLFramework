Set-StrictMode -Version Latest
. (Join-Path -Path (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))) -ChildPath 'TestHelpers.ps1')

Describe 'Source.CustomScript module' {
    BeforeAll {
        $Workspace = Set-FrameworkTestEnvironment -ProjectRoot (Join-Path -Path $TestDrive -ChildPath 'CustomScriptProject')
        $script:ProjectRoot = $Workspace.ProjectRoot
        $script:Module = Import-TestableAsset -RelativePath 'Templates/Modules/Source/Source.CustomScript.psm1'
    }

    AfterAll {
        Remove-TestModuleSafely -Module $script:Module
        Clear-FrameworkTestEnvironment
    }

    Context 'Invoke-Extract integration' {
        It 'executes a project custom script and filters the emitted properties' {
            $ScriptPath = Join-Path -Path $env:ETL_PROJECT_ROOT -ChildPath 'PS\Get-Users.ps1'
            New-Item -Path (Split-Path -Path $ScriptPath -Parent) -ItemType Directory -Force | Out-Null
            @'
param([string]$Environment)
@(
    [PSCustomObject]@{ Name = "$Environment-Alice"; Mail = 'alice@example.org'; Department = 'IT' },
    [PSCustomObject]@{ Name = "$Environment-Bob";   Mail = 'bob@example.org';   Department = 'HR' }
)
'@ | Set-Content -Path $ScriptPath -Encoding UTF8

            $Rows = @(Invoke-Extract -Config @{ ScriptPath = '.\PS\Get-Users.ps1'; Parameters = @{ Environment = 'Prod' } } -Properties @('Name', 'Mail'))

            $Rows.Count | Should -Be 2
            $Rows[0].Name | Should -Be 'Prod-Alice'
            @($Rows[0].PSObject.Properties.Name) | Should -Be @('Name', 'Mail')
        }

        It 'fails when the custom script returns a plain string' {
            $ScriptPath = Join-Path -Path $env:ETL_PROJECT_ROOT -ChildPath 'PS\Get-Invalid.ps1'
            New-Item -Path (Split-Path -Path $ScriptPath -Parent) -ItemType Directory -Force | Out-Null
            "'plain text'" | Set-Content -Path $ScriptPath -Encoding UTF8

            {
                @(Invoke-Extract -Config @{ ScriptPath = '.\PS\Get-Invalid.ps1' } -Properties @('*'))
            } | Should -Throw
        }
    }
}
