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

            It 'falls back to ETL_LOG_ROOT when ETL_PROJECT_ROOT is not set' {
                Remove-Item Env:ETL_PROJECT_ROOT -ErrorAction SilentlyContinue
                $ProjectRoot = [System.IO.Path]::GetFullPath((Join-Path -Path $TestDrive -ChildPath 'ProjectFromLogRoot'))
                $env:ETL_LOG_ROOT = Join-Path -Path $ProjectRoot -ChildPath 'LOG'
                $ModuleRoot = Join-Path -Path $ProjectRoot -ChildPath 'RUN/Modules/Source'

                Get-EtlProjectRootPath -ModuleRoot $ModuleRoot | Should -Be $ProjectRoot
            }

            It 'resolves relative project paths against the project root' {
                $ProjectRoot = [System.IO.Path]::GetFullPath((Join-Path -Path $TestDrive -ChildPath 'ProjectRoot'))
                $ModuleRoot = Join-Path -Path $ProjectRoot -ChildPath 'RUN/Modules/Source'
                $env:ETL_PROJECT_ROOT = $ProjectRoot
                Resolve-EtlProjectPath -Path 'DATA/input.json' -ModuleRoot $ModuleRoot |
                    Should -Be (Join-Path -Path $ProjectRoot -ChildPath 'DATA/input.json')
            }

            It 'returns rooted paths unchanged in Resolve-EtlProjectPath' {
                $ProjectRoot = [System.IO.Path]::GetFullPath((Join-Path -Path $TestDrive -ChildPath 'ProjectRoot'))
                $RootedFile = Join-Path -Path $ProjectRoot -ChildPath 'DATA/input.json'
                Resolve-EtlProjectPath -Path $RootedFile -ModuleRoot (Join-Path -Path $ProjectRoot -ChildPath 'RUN/Modules/Source') |
                    Should -Be $RootedFile
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

            It 'returns hashtable keys from Get-EtlObjectPropertyNames' {
                ((Get-EtlObjectPropertyNames -InputObject @{ FirstName = 'Alice'; LastName = 'Doe' }) | Sort-Object) -join ',' |
                    Should -Be 'FirstName,LastName'
            }
        }


        Context 'Import-EtlAssemblyIfNeeded' {
            It 'returns true when the assembly file is already loaded' {
                $AssemblyPath = [System.Management.Automation.PSObject].Assembly.Location

                Import-EtlAssemblyIfNeeded -AssemblyPath $AssemblyPath | Should -BeTrue
            }

            It 'returns false when the assembly file does not exist' {
                Import-EtlAssemblyIfNeeded -AssemblyPath (Join-Path -Path $TestDrive -ChildPath 'missing.dll') | Should -BeFalse
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

        Context 'Get-EtlStepLogSuffix and record preview helpers' {
            It 'returns null when no step id is set' {
                Remove-Item Env:ETL_STEP_ID -ErrorAction SilentlyContinue
                Get-EtlStepLogSuffix | Should -BeNullOrEmpty
            }

            It 'returns count and preview for record arrays' {
                $Result = Get-EtlRecordCountAndPreview -Records @(
                    [pscustomobject]@{ Name = 'Alice'; Mail = 'alice@example.org' },
                    [pscustomobject]@{ Name = 'Bob'; Mail = 'bob@example.org' }
                ) -PreviewCount 1

                $Result.Count | Should -Be 2
                @($Result.Preview).Count | Should -Be 1
                $Result.Preview[0] | Should -Match 'Name=Alice'
            }
        }

        Context 'Write-EtlExceptionDetails' {
            It 'writes message, location, stack and inner exception details' {
                $Logged = [System.Collections.Generic.List[string]]::new()
                Mock -ModuleName $script:Module.Name Write-EtlModuleLog {
                    param($Context, $Message, $Level)
                    [void]$Logged.Add($Message)
                }

                $Inner = [System.Exception]::new('Inner failure')
                $Top = [System.Exception]::new('Top failure', $Inner)
                $Record = [System.Management.Automation.ErrorRecord]::new($Top, 'TestId', [System.Management.Automation.ErrorCategory]::NotSpecified, $null)
                $Record | Add-Member -NotePropertyName ScriptStackTrace -NotePropertyValue 'at Test: line 5' -Force
                $Record | Add-Member -NotePropertyName InvocationInfo -NotePropertyValue ([pscustomobject]@{
                    ScriptLineNumber = 5
                    ScriptName = '/tmp/test.ps1'
                }) -Force

                Write-EtlExceptionDetails -Context @{} -ErrorRecord $Record -Prefix 'Prefix:'

                ($Logged -join ' | ') | Should -Match 'Prefix:\s+Top failure'
                ($Logged -join ' | ') | Should -Match 'Error location: Line 5'
                ($Logged -join ' | ') | Should -Match 'StackTrace: at Test: line 5'
                ($Logged -join ' | ') | Should -Match 'InnerException: Inner failure'
            }
        }

        Context 'Import-EtlCredentialSupport' {
            It 'returns immediately when Get-StoredCredential is already available' {
                Mock -ModuleName $script:Module.Name Get-Command { [pscustomobject]@{ Name = 'Get-StoredCredential' } } -ParameterFilter { $Name -eq 'Get-StoredCredential' }
                Mock -ModuleName $script:Module.Name Import-Module {}

                Import-EtlCredentialSupport -ModuleRoot (Join-Path -Path $TestDrive -ChildPath 'Modules')

                Assert-MockCalled -CommandName Import-Module -ModuleName $script:Module.Name -Times 0
            }

            It 'imports credential module from discovered candidate path' {
                $ProjectRoot = Join-Path -Path $TestDrive -ChildPath 'Project'
                $ModuleRoot = Join-Path -Path $ProjectRoot -ChildPath 'RUN/Modules/Source'
                $CredentialPath = Join-Path -Path $ProjectRoot -ChildPath 'RUN/Modules/Credential/Credential.Manager.psm1'
                New-Item -Path (Split-Path -Path $CredentialPath -Parent) -ItemType Directory -Force | Out-Null
                Set-Content -Path $CredentialPath -Value '# module' -Encoding UTF8

                Mock -ModuleName $script:Module.Name Get-Command { $null } -ParameterFilter { $Name -eq 'Get-StoredCredential' }
                Mock -ModuleName $script:Module.Name Import-Module {}

                Import-EtlCredentialSupport -ModuleRoot $ModuleRoot

                Assert-MockCalled -CommandName Import-Module -ModuleName $script:Module.Name -Times 1 -Exactly -ParameterFilter { $Name -eq $CredentialPath }
            }
        }
}
