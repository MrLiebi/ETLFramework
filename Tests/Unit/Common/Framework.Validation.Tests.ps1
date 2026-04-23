Set-StrictMode -Version Latest
. (Join-Path -Path (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))) -ChildPath 'TestHelpers.ps1')

Describe 'Framework.Validation' {
    BeforeAll {
        $script:Module = Import-TestableAsset -RelativePath 'Templates/Modules/Common/Framework.Validation.psm1'
    }

    AfterAll {
        Remove-TestModuleSafely -Module $script:Module
    }

        Context 'Get-ValidatedPropertySelection' {
            It 'returns wildcard when input is null or empty' {
                Get-ValidatedPropertySelection -Properties $null | Should -Be @('*')
                Get-ValidatedPropertySelection -Properties @('', '   ', $null) | Should -Be @('*')
            }

            It 'trims values and removes blanks' {
                Get-ValidatedPropertySelection -Properties @(' Name ', '', ' Mail', $null, 'Department ') |
                    Should -Be @('Name', 'Mail', 'Department')
            }
        }

        Context 'Get-EtlAuthenticationMode' {
            It 'returns the configured mode when present' {
                Get-EtlAuthenticationMode -Config @{ AuthenticationMode = 'CredentialManager' } |
                    Should -Be 'CredentialManager'
            }

            It 'falls back to the default when missing' {
                Get-EtlAuthenticationMode -Config @{} -Default 'Integrated' | Should -Be 'Integrated'
                Get-EtlAuthenticationMode -Config @{ AuthenticationMode = ' ' } -Default 'SqlLogin' | Should -Be 'SqlLogin'
            }
        }
}
