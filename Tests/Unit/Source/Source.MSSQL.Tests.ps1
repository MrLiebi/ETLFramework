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
                Should -Be 'Server=sql01;Database=FNMS;User ID=etl;Password=s3cr3t;'
        }
    }
    }
}
