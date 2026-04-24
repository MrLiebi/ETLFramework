Set-StrictMode -Version Latest
. (Join-Path -Path (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))) -ChildPath 'TestHelpers.ps1')

$Workspace = Set-FrameworkTestEnvironment -ProjectRoot (Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath ([System.Guid]::NewGuid().Guid))
$script:ProjectRoot = $Workspace.ProjectRoot
$null = Import-TestableAsset -RelativePath 'Templates/Modules/Source/Source.MSSQL.psm1' -AdditionalRelativePaths @(
    'Templates/Modules/Common/Framework.Common.psm1',
    'Templates/Modules/Common/Framework.Logging.psm1',
    'Templates/Modules/Common/Framework.Validation.psm1',
    'Templates/Modules/Credential/Credential.Manager.psm1'
)

Describe 'Source.MSSQL module' {
    AfterAll {
        . (Join-Path -Path (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))) -ChildPath 'TestHelpers.ps1')
        Remove-TestModuleSafely -Module 'Source.MSSQL'
        Clear-FrameworkTestEnvironment
    }

    InModuleScope 'Source.MSSQL' {
    Context 'Test-ExtractConfiguration' {
        It 'accepts a full explicit configuration' {
            Test-ExtractConfiguration -Config @{ ConnectionString = 'Server=sql01;Database=FNMS;'; Query = 'SELECT 1' } | Should -BeTrue
        }

        It 'returns false when the query is missing' {
            Test-ExtractConfiguration -Config @{ Server = 'sql01'; Database = 'FNMS' } | Should -BeFalse
        }

        It 'returns false when credential-manager mode lacks a target' {
            Test-ExtractConfiguration -Config @{ Server = 'sql01'; Database = 'FNMS'; Query = 'SELECT 1'; AuthenticationMode = 'CredentialManager' } | Should -BeFalse
        }
    }

    Context 'Connection helpers' {
        It 'returns Integrated by default when AuthenticationMode is missing' {
            Get-AuthenticationMode -Config @{} | Should -Be 'Integrated'
        }

        It 'returns the provided connection string unchanged' {
            Get-SqlConnectionString -Config @{ ConnectionString = 'Server=override;Database=Demo;' } | Should -Be 'Server=override;Database=Demo;'
        }

        It 'builds an integrated-security connection string when credentials are not required' {
            Mock -ModuleName 'Source.MSSQL' Get-AuthenticationMode { 'WindowsAuthentication' }

            Get-SqlConnectionString -Config @{ Server = 'sql01'; Database = 'FNMS' } |
                Should -Be 'Server=sql01;Database=FNMS;Integrated Security=True;'
        }

        It 'returns null when credential-manager mode is not active' {
            Mock -ModuleName 'Source.MSSQL' Get-AuthenticationMode { 'WindowsAuthentication' }

            Get-SqlConnectionCredential -Config @{ AuthenticationMode = 'WindowsAuthentication' } | Should -BeNullOrEmpty
        }

        It 'throws when credential-manager mode has no target' {
            Mock -ModuleName 'Source.MSSQL' Get-AuthenticationMode { 'CredentialManager' }

            { Get-SqlConnectionCredential -Config @{ AuthenticationMode = 'CredentialManager' } } |
                Should -Throw '*CredentialTarget for AuthenticationMode=CredentialManager*'
        }

        It 'builds a credential-based connection string when credential manager is enabled' {
            Mock -ModuleName 'Source.MSSQL' Get-AuthenticationMode { 'CredentialManager' }
            Mock -ModuleName 'Source.MSSQL' Get-SqlConnectionCredential { [pscustomobject]@{ UserName = 'etl'; Password = 's3cr3t' } }

            Get-SqlConnectionString -Config @{ Server = 'sql01'; Database = 'FNMS'; AuthenticationMode = 'CredentialManager'; CredentialTarget = 'Target/One' } |
                Should -Be 'Server=sql01;Database=FNMS;Persist Security Info=False;'
        }

        It 'converts plain credential secret to SecureString' {
            $Secure = ConvertTo-SecurePasswordForSql -CredentialSecret 's3cr3t'
            $Secure.GetType().FullName | Should -Be 'System.Security.SecureString'
            $Secure.IsReadOnly() | Should -BeTrue
        }

        It 'returns an existing SecureString unchanged' {
            $SecureInput = ConvertTo-SecureString 's3cr3t' -AsPlainText -Force
            (ConvertTo-SecurePasswordForSql -CredentialSecret $SecureInput) | Should -Be $SecureInput
        }

        It 'creates SqlConnection from explicit connection string' {
            $Connection = New-SqlConnection -Config @{ ConnectionString = 'Server=override;Database=Demo;' }
            try {
                $Connection.ConnectionString | Should -Be 'Server=override;Database=Demo;'
            }
            finally {
                if ($Connection) { $Connection.Dispose() }
            }
        }

        It 'creates a SqlConnection with SqlCredential in credential-manager mode' {
            Mock -ModuleName 'Source.MSSQL' Get-AuthenticationMode { 'CredentialManager' }
            Mock -ModuleName 'Source.MSSQL' Get-SqlConnectionCredential { [pscustomobject]@{ UserName = 'etl'; Password = 's3cr3t' } }

            $Connection = New-SqlConnection -Config @{ Server = 'sql01'; Database = 'FNMS'; AuthenticationMode = 'CredentialManager'; CredentialTarget = 'Target/One' }
            try {
                $Connection.GetType().FullName | Should -Be 'System.Data.SqlClient.SqlConnection'
                $Connection.ConnectionString | Should -Match 'Data Source=sql01'
                $Connection.ConnectionString | Should -Not -Match 'Password='
            }
            finally {
                if ($Connection) { $Connection.Dispose() }
            }
        }
    }

    Context 'Non-interactive connection guard' {
        It 'allows localhost server during non-interactive tests' {
            $env:ETL_TEST_NONINTERACTIVE = '1'
            { Assert-NonInteractiveSqlConnectionAllowed -Config @{ Server = 'localhost' } } | Should -Not -Throw
        }

        It 'blocks external server during non-interactive tests unless override is enabled' {
            $env:ETL_TEST_NONINTERACTIVE = '1'
            Remove-Item Env:ETL_ALLOW_DB_CONNECTIONS -ErrorAction SilentlyContinue
            { Assert-NonInteractiveSqlConnectionAllowed -Config @{ Server = 'sql01.example.org' } } |
                Should -Throw '*blocked MSSQL source connection*'
        }

        It 'allows external server when override is enabled' {
            $env:ETL_TEST_NONINTERACTIVE = '1'
            $env:ETL_ALLOW_DB_CONNECTIONS = '1'
            { Assert-NonInteractiveSqlConnectionAllowed -Config @{ Server = 'sql01.example.org' } } | Should -Not -Throw
            Remove-Item Env:ETL_ALLOW_DB_CONNECTIONS -ErrorAction SilentlyContinue
        }
    }
    }
}
