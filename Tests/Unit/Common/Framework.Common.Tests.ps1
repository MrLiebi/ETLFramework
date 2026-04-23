Set-StrictMode -Version Latest
. (Join-Path -Path (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))) -ChildPath 'TestHelpers.ps1')

Describe 'Framework.Common' {
    BeforeAll {
        $null = Set-FrameworkTestEnvironment
        $script:Module = Import-TestableAsset -RelativePath 'Templates/Modules/Common/Framework.Common.psm1'
    }

    AfterAll {
        Remove-TestModuleSafely -Module $script:Module
        Clear-FrameworkTestEnvironment
    }

        Context 'Get-EtlProjectRootPath and Resolve-EtlProjectPath' {
            It 'prefers ETL_PROJECT_ROOT over derived paths' {
                $env:ETL_PROJECT_ROOT = 'C:\ETL\ProjectRoot'
                Get-EtlProjectRootPath -ModuleRoot 'C:\ETL\ProjectRoot\RUN\Modules\Source' | Should -Be 'C:\ETL\ProjectRoot'
            }

            It 'resolves relative project paths against the project root' {
                $env:ETL_PROJECT_ROOT = 'C:\ETL\ProjectRoot'
                Resolve-EtlProjectPath -Path 'DATA\input.json' -ModuleRoot 'C:\ETL\ProjectRoot\RUN\Modules\Source' |
                    Should -Be 'C:\ETL\ProjectRoot\DATA\input.json'
            }
        }

        Context 'Get-EtlObjectPreview' {
            It 'formats a compact preview for custom objects' {
                $Preview = Get-EtlObjectPreview -InputObject ([PSCustomObject]@{ Name = 'Alice'; Mail = 'alice@example.org' })
                $Preview | Should -Match 'Name=Alice'
                $Preview | Should -Match 'Mail=alice@example.org'
            }

            It 'returns <null> for null input' {
                Get-EtlObjectPreview -InputObject $null | Should -Be '<null>'
            }
        }


        Context 'Import-EtlAssemblyIfNeeded' {
            It 'returns true when the assembly file is already loaded' {
                $AssemblyPath = [System.Management.Automation.PSObject].Assembly.Location

                Import-EtlAssemblyIfNeeded -AssemblyPath $AssemblyPath | Should -BeTrue
            }
        }

        Context 'New-EtlModuleContext' {
            It 'uses environment values and source role naming' {
                $env:ETL_LOG_ROOT = 'C:\Logs'
                $env:ETL_RUN_ID = 'RUN_123'
                $Context = New-EtlModuleContext -ModulePath 'C:\Framework\Templates\Modules\Source\Source.JSON.psm1' -ModuleRoot 'C:\Framework\Templates\Modules\Source'

                $Context.ModuleName | Should -Be 'Source.JSON'
                $Context.ModuleRole | Should -Be '02'
                $Context.ModuleRunId | Should -Be 'RUN_123'
                $Context.ModuleLogDirectory | Should -Be 'C:\Logs'
            }
        }

        Context 'Get-EtlModuleLogFilePath' {
            It 'includes the ETL step suffix when present' {
                $env:ETL_STEP_ID = 'Step 01/Import'
                $Path = Get-EtlModuleLogFilePath -Context @{
                    ModuleLogDirectory = 'C:\Logs'
                    ModuleRunId = 'RUN_123'
                    ModuleLogFileNameBase = '02_Source.JSON'
                }

                $Path | Should -Be 'C:\Logs\RUN_123_02_Source.JSON_Step_Step_01_Import.log'
            }
        }
}
