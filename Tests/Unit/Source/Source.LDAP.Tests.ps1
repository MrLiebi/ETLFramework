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
        Context 'Helper functions' {
            It 'returns explicit property selection when wildcard is absent' {
                Get-ValidatedLdapProperties -Properties @('mail', 'cn') | Should -Be @('mail', 'cn')
            }

            It 'returns wildcard when wildcard is explicitly requested' {
                Get-ValidatedLdapProperties -Properties @('mail', '*', 'cn') | Should -Be @('*')
            }

            It 'converts AD file time values and handles invalid input' {
                $UtcValue = [datetime]'2026-04-20T10:30:00Z'
                Convert-ADFileTime -Value ($UtcValue.ToFileTimeUtc()) | Should -Be '2026-04-20 10:30:00'
                Convert-ADFileTime -Value 0 | Should -BeNullOrEmpty
                Convert-ADFileTime -Value $null | Should -BeNullOrEmpty
            }

            It 'converts LDAP value variants (GUID, bytes, timestamps)' {
                $Guid = [guid]'00112233-4455-6677-8899-aabbccddeeff'
                Convert-LdapValue -Value $Guid.ToByteArray() -AttributeName 'objectGuid' | Should -Be $Guid.ToString()
                Convert-LdapValue -Value $Guid.ToString() -AttributeName 'objectGuid' | Should -Be $Guid.ToString()

                $FileTimeValue = ([datetime]'2026-04-20T10:30:00Z').ToFileTimeUtc()
                Convert-LdapValue -Value $FileTimeValue -AttributeName 'lastLogonTimestamp' | Should -Be '2026-04-20 10:30:00'

                $ByteText = [System.Text.Encoding]::UTF8.GetBytes("alpha$([char]0)")
                Convert-LdapValue -Value $ByteText -AttributeName 'description' | Should -Be 'alpha'
                Convert-LdapValue -Value 'S-1-5-18' -AttributeName 'objectSid' | Should -Be 'S-1-5-18'
            }
        }

        Context 'Authentication and connection guard helpers' {
            It 'returns Integrated authentication mode by default' {
                Get-AuthenticationMode -Config @{} | Should -Be 'Integrated'
            }

            It 'allows localhost during non-interactive sessions' {
                Remove-Item Env:ETL_ALLOW_DB_CONNECTIONS -ErrorAction SilentlyContinue
                { Assert-NonInteractiveLdapConnectionAllowed -Config @{ Server = 'localhost' } } | Should -Not -Throw
            }

            It 'blocks non-localhost servers by default during non-interactive sessions' {
                Remove-Item Env:ETL_ALLOW_DB_CONNECTIONS -ErrorAction SilentlyContinue
                { Assert-NonInteractiveLdapConnectionAllowed -Config @{ Server = 'ldap.example.org' } } |
                    Should -Throw '*blocked LDAP connection*'
            }

            It 'allows non-localhost servers when ETL_ALLOW_DB_CONNECTIONS is enabled' {
                $env:ETL_ALLOW_DB_CONNECTIONS = '1'
                { Assert-NonInteractiveLdapConnectionAllowed -Config @{ Server = 'ldap.example.org' } } | Should -Not -Throw
                Remove-Item Env:ETL_ALLOW_DB_CONNECTIONS -ErrorAction SilentlyContinue
            }

            It 'returns without error when server is empty' {
                Remove-Item Env:ETL_ALLOW_DB_CONNECTIONS -ErrorAction SilentlyContinue
                { Assert-NonInteractiveLdapConnectionAllowed -Config @{ Server = '' } } | Should -Not -Throw
            }
        }

        Context 'Entry metadata helpers' {
            It 'resolves LDAP attribute names case-insensitively' {
                $Entry = [pscustomobject]@{
                    Attributes = [pscustomobject]@{
                        AttributeNames = @('mail', 'sAMAccountName')
                    }
                }

                Resolve-LdapAttributeName -Entry $Entry -RequestedName 'MAIL' | Should -Be 'mail'
                Resolve-LdapAttributeName -Entry $Entry -RequestedName 'missing' | Should -BeNullOrEmpty
            }

            It 'returns distinguishedName from entry metadata when requested' {
                $Entry = [pscustomobject]@{
                    DistinguishedName = 'CN=Alice,DC=example,DC=org'
                }

                Get-EntryMetaValue -Entry $Entry -RequestedName 'distinguishedName' | Should -Be 'CN=Alice,DC=example,DC=org'
                Get-EntryMetaValue -Entry $Entry -RequestedName 'mail' | Should -BeNullOrEmpty
            }

            It 'captures LDAP entry snapshots with attribute statistics' {
                $Entry = [pscustomobject]@{
                    DistinguishedName = 'CN=Alice,DC=example,DC=org'
                    Attributes = [pscustomobject]@{
                        AttributeNames = @('mail', 'cn')
                    }
                }

                $Snapshot = Get-LdapEntrySnapshot -Entry $Entry
                $Snapshot.DistinguishedName | Should -Be 'CN=Alice,DC=example,DC=org'
                $Snapshot.AttributeCount | Should -Be 2
                ($Snapshot.AttributeNames -join ',') | Should -Be 'cn,mail'
            }
        }

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
