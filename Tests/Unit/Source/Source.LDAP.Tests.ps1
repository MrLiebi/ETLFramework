Set-StrictMode -Version Latest
. (Join-Path -Path (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))) -ChildPath 'TestHelpers.ps1')

$Workspace = Set-FrameworkTestEnvironment -ProjectRoot (Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath ([System.Guid]::NewGuid().Guid))
$script:ProjectRoot = $Workspace.ProjectRoot
$null = Import-TestableAsset -RelativePath 'Templates/Modules/Source/Source.LDAP.psm1'

Describe 'Source.LDAP module' {
    AfterAll {
        . (Join-Path -Path (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))) -ChildPath 'TestHelpers.ps1')
        Remove-TestModuleSafely -Module 'Source.LDAP'
        Clear-FrameworkTestEnvironment
    }

    InModuleScope 'Source.LDAP' {
        Context 'Invoke-Extract configuration gate' {
            It 'throws when mandatory LDAP fields are missing' {
                { Invoke-Extract -Config @{} -Properties @('*') } |
                    Should -Throw '*Source LDAP configuration is invalid*'
            }

            It 'throws when CredentialManager mode lacks CredentialTarget' {
                $Bad = @{
                    Server             = 'ldap.example.com'
                    SearchBase         = 'dc=example,dc=com'
                    Filter             = '(objectClass=user)'
                    AuthenticationMode = 'CredentialManager'
                }
                { Invoke-Extract -Config $Bad -Properties @('cn') } |
                    Should -Throw '*Source LDAP configuration is invalid*'
            }
        }
    }
}
