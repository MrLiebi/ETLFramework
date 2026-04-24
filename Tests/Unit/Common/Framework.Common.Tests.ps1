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
                $ProjectRoot = [System.IO.Path]::GetFullPath((Join-Path -Path $TestDrive -ChildPath 'ProjectRoot'))
                $ModuleRoot = Join-Path -Path $ProjectRoot -ChildPath 'RUN/Modules/Source'
                $env:ETL_PROJECT_ROOT = $ProjectRoot
                Get-EtlProjectRootPath -ModuleRoot $ModuleRoot | Should -Be $ProjectRoot
            }

            It 'resolves relative project paths against the project root' {
                $ProjectRoot = [System.IO.Path]::GetFullPath((Join-Path -Path $TestDrive -ChildPath 'ProjectRoot'))
                $ModuleRoot = Join-Path -Path $ProjectRoot -ChildPath 'RUN/Modules/Source'
                $env:ETL_PROJECT_ROOT = $ProjectRoot
                Resolve-EtlProjectPath -Path 'DATA/input.json' -ModuleRoot $ModuleRoot |
                    Should -Be (Join-Path -Path $ProjectRoot -ChildPath 'DATA/input.json')
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
                $LogRoot = Join-Path -Path $TestDrive -ChildPath 'Logs'
                $ModuleRoot = Join-Path -Path $TestDrive -ChildPath 'Templates/Modules/Source'
                $ModulePath = Join-Path -Path $ModuleRoot -ChildPath 'Source.JSON.psm1'
                $env:ETL_LOG_ROOT = $LogRoot
                $env:ETL_RUN_ID = 'RUN_123'
                $Context = New-EtlModuleContext -ModulePath $ModulePath -ModuleRoot $ModuleRoot

                $Context.ModuleName | Should -Be 'Source.JSON'
                $Context.ModuleRole | Should -Be '02'
                $Context.ModuleRunId | Should -Be 'RUN_123'
                $Context.ModuleLogDirectory | Should -Be $LogRoot
            }
        }

        Context 'Get-EtlModuleLogFilePath' {
            It 'includes the ETL step suffix when present' {
                $env:ETL_STEP_ID = 'Step 01/Import'
                $LogRoot = Join-Path -Path $TestDrive -ChildPath 'Logs'
                $Path = Get-EtlModuleLogFilePath -Context @{
                    ModuleLogDirectory = $LogRoot
                    ModuleRunId = 'RUN_123'
                    ModuleLogFileNameBase = '02_Source.JSON'
                }

                $Path | Should -Be (Join-Path -Path $LogRoot -ChildPath 'RUN_123_02_Source.JSON_Step_Step_01_Import.log')
            }
        }
}
