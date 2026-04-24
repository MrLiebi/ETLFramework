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

    Context 'LDAP source configuration' {
        It 'builds an LDAP source config with credential setup and explicit properties' {
            $script:InputAnswers = [System.Collections.Generic.Queue[string]]::new()
            foreach ($Answer in @(
                'dc01.example.org',
                'dc=example,dc=org',
                '(objectClass=user)',
                'sAMAccountName,mail'
            )) { [void]$script:InputAnswers.Enqueue($Answer) }

            Mock -ModuleName $script:Module.Name Read-InputValue { $script:InputAnswers.Dequeue() }
            Mock -ModuleName $script:Module.Name Read-CredentialTargetConfiguration {
                [PSCustomObject]@{
                    AuthenticationMode = 'CredentialManager'
                    CredentialTarget   = 'Demo/LDAP'
                    CreateCredential   = $true
                    UserName           = 'svc_ldap'
                    Password           = (ConvertTo-SecureString 'pw' -AsPlainText -Force)
                }
            }

            $Result = Get-SourceConfigFromWizard -SourceType 'LDAP' -ProjectName 'Demo' -StepId '03'

            $Result.Config.Server | Should -Be 'dc01.example.org'
            $Result.Config.AuthenticationMode | Should -Be 'CredentialManager'
            $Result.Config.CredentialTarget | Should -Be 'Demo/LDAP'
            $Result.CredentialSetup.Target | Should -Be 'Demo/LDAP'
            $Result.Properties | Should -Be @('sAMAccountName', 'mail')
        }
    }

    Context 'MSSQL source configuration' {
        It 'builds an MSSQL source config and supports wildcard properties' {
            $script:InputAnswers = [System.Collections.Generic.Queue[string]]::new()
            foreach ($Answer in @(
                'sql01',
                'FNMSCompliance',
                'SELECT TOP 10 * FROM dbo.Users',
                '*'
            )) { [void]$script:InputAnswers.Enqueue($Answer) }

            Mock -ModuleName $script:Module.Name Read-InputValue { $script:InputAnswers.Dequeue() }
            Mock -ModuleName $script:Module.Name Read-CredentialTargetConfiguration {
                [PSCustomObject]@{
                    AuthenticationMode = 'WindowsAuthentication'
                    CredentialTarget   = $null
                    CreateCredential   = $false
                    UserName           = ''
                    Password           = $null
                }
            }

            $Result = Get-SourceConfigFromWizard -SourceType 'MSSQL' -ProjectName 'Demo' -StepId '04'

            $Result.Config.Server | Should -Be 'sql01'
            $Result.Config.Query | Should -Be 'SELECT TOP 10 * FROM dbo.Users'
            $Result.Config.AuthenticationMode | Should -Be 'WindowsAuthentication'
            $Result.Properties | Should -Be @('*')
            $Result.CredentialSetup | Should -BeNullOrEmpty
        }
    }

    Context 'JSON source configuration' {
        It 'builds a JSON source config and preserves selected properties' {
            Mock -ModuleName $script:Module.Name Read-FileSourceConfiguration {
                [PSCustomObject]@{ Path = 'INPUT\accounts'; FilePattern = 'accounts.json*' }
            }
            Mock -ModuleName $script:Module.Name Read-FileSourcePostImportConfiguration {
                [PSCustomObject]@{ BackupAfterImport = $true; BackupPath = 'INPUT\_Backup'; DeleteAfterImport = $false }
            }
            Mock -ModuleName $script:Module.Name Read-Choice { 'JsonL' }
            $script:InputAnswers = [System.Collections.Generic.Queue[string]]::new()
            foreach ($Answer in @(
                'payload.items',
                'id,mail'
            )) { [void]$script:InputAnswers.Enqueue($Answer) }
            Mock -ModuleName $script:Module.Name Read-InputValue { $script:InputAnswers.Dequeue() }

            $Result = Get-SourceConfigFromWizard -SourceType 'JSON' -ProjectName 'Demo' -StepId '05'

            $Result.Config.Path | Should -Be 'INPUT\accounts'
            $Result.Config.Format | Should -Be 'JsonL'
            $Result.Config.RootPath | Should -Be 'payload.items'
            $Result.Properties | Should -Be @('id', 'mail')
            $Result.CreateInput | Should -BeTrue
        }
    }

    Context 'XML source configuration' {
        It 'builds an XML source config with wildcard fallback on empty property input' {
            Mock -ModuleName $script:Module.Name Read-FileSourceConfiguration {
                [PSCustomObject]@{ Path = 'INPUT\data.xml'; FilePattern = $null }
            }
            Mock -ModuleName $script:Module.Name Read-FileSourcePostImportConfiguration {
                [PSCustomObject]@{ BackupAfterImport = $false; BackupPath = 'INPUT\_Backup'; DeleteAfterImport = $false }
            }
            $script:InputAnswers = [System.Collections.Generic.Queue[string]]::new()
            foreach ($Answer in @(
                '/root/item',
                ''
            )) { [void]$script:InputAnswers.Enqueue($Answer) }
            Mock -ModuleName $script:Module.Name Read-InputValue { $script:InputAnswers.Dequeue() }

            $Result = Get-SourceConfigFromWizard -SourceType 'XML' -ProjectName 'Demo' -StepId '06'

            $Result.Config.Path | Should -Be 'INPUT\data.xml'
            $Result.Config.RecordXPath | Should -Be '/root/item'
            $Result.Properties | Should -Be @('*')
            $Result.CreateInput | Should -BeTrue
        }
    }

    Context 'XLSX source configuration' {
        It 'builds an XLSX source config including numeric row/column settings' {
            Mock -ModuleName $script:Module.Name Read-FileSourceConfiguration {
                [PSCustomObject]@{ Path = 'INPUT\book.xlsx'; FilePattern = '*.xlsx' }
            }
            Mock -ModuleName $script:Module.Name Read-FileSourcePostImportConfiguration {
                [PSCustomObject]@{ BackupAfterImport = $true; BackupPath = 'INPUT\Archive'; DeleteAfterImport = $false }
            }
            $script:IntAnswers = [System.Collections.Generic.Queue[int]]::new()
            foreach ($Answer in @(1,2,1)) { [void]$script:IntAnswers.Enqueue($Answer) }
            Mock -ModuleName $script:Module.Name Read-PositiveInteger { $script:IntAnswers.Dequeue() }
            $script:InputAnswers = [System.Collections.Generic.Queue[string]]::new()
            foreach ($Answer in @(
                'Sheet1',
                'Name,Mail'
            )) { [void]$script:InputAnswers.Enqueue($Answer) }
            Mock -ModuleName $script:Module.Name Read-InputValue { $script:InputAnswers.Dequeue() }

            $Result = Get-SourceConfigFromWizard -SourceType 'XLSX' -ProjectName 'Demo' -StepId '07'

            $Result.Config.Path | Should -Be 'INPUT\book.xlsx'
            $Result.Config.WorksheetName | Should -Be 'Sheet1'
            $Result.Config.HeaderRowNumber | Should -Be '1'
            $Result.Config.DataStartRowNumber | Should -Be '2'
            $Result.Config.FirstDataColumn | Should -Be '1'
            $Result.Properties | Should -Be @('Name', 'Mail')
            $Result.CreateInput | Should -BeTrue
        }
    }

    Context 'CustomScript validation' {
        It 'throws when custom script contract is not accepted' {
            Mock -ModuleName $script:Module.Name Show-CustomScriptContractAndConfirm { $false }

            { Get-SourceConfigFromWizard -SourceType 'CustomScript' -ProjectName 'Demo' -StepId '08' } |
                Should -Throw '*contract was not accepted*'
        }
    }
}
