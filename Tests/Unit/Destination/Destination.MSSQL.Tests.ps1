. (Join-Path -Path (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))) -ChildPath 'TestHelpers.ps1')

$Workspace = Set-FrameworkTestEnvironment -ProjectRoot (Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath ([System.Guid]::NewGuid().Guid))
$script:ProjectRoot = $Workspace.ProjectRoot
$null = Import-TestableAsset -RelativePath 'Templates/Modules/Destination/Destination.MSSQL.psm1' -AdditionalRelativePaths @(
    'Templates/Modules/Common/Framework.Common.psm1',
    'Templates/Modules/Common/Framework.Logging.psm1',
    'Templates/Modules/Common/Framework.Validation.psm1',
    'Templates/Modules/Credential/Credential.Manager.psm1'
)

Describe 'Destination.MSSQL module' {
    AfterAll {
        . (Join-Path -Path (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))) -ChildPath 'TestHelpers.ps1')
        Remove-TestModuleSafely -Module 'Destination.MSSQL'
        Clear-FrameworkTestEnvironment
    }

    InModuleScope 'Destination.MSSQL' {
        Context 'SQL identifier and literal helpers' {
            It 'trims identifiers and strips bracket characters' {
                Get-SafeSqlIdentifier -Name '  [dbo].[Users]  ' | Should -Be '[dbo.Users]'
            }

            It 'throws when the identifier is empty' {
                { Get-SafeSqlIdentifier -Name '   ' } | Should -Throw '*must not be empty*'
            }

            It 'escapes apostrophes in SQL literals' {
                Get-SqlLiteral -Value "O'Brien" | Should -Be "N'O''Brien'"
            }

            It 'throws when the literal is empty' {
                { Get-SqlLiteral -Value '   ' } | Should -Throw '*must not be empty*'
            }
        }

        Context 'SQL connection helpers' {
            It 'returns the provided connection string unchanged' {
                Get-SqlConnectionString -Config @{ ConnectionString = 'Server=override;Database=Demo;' } | Should -Be 'Server=override;Database=Demo;'
            }

            It 'builds an integrated-security connection string by default' {
                Mock -ModuleName 'Destination.MSSQL' Get-AuthenticationMode { 'WindowsAuthentication' }

                Get-SqlConnectionString -Config @{ Server = 'sql01'; Database = 'FNMS' } |
                    Should -Be 'Server=sql01;Database=FNMS;Integrated Security=True'
            }

            It 'builds a credential-based connection string when credential manager is enabled' {
                Mock -ModuleName 'Destination.MSSQL' Get-AuthenticationMode { 'CredentialManager' }
                Mock -ModuleName 'Destination.MSSQL' Get-SqlConnectionCredential { [pscustomobject]@{ UserName = 'etl'; Password = 's3cr3t' } }

                Get-SqlConnectionString -Config @{ Server = 'sql01'; Database = 'FNMS'; CredentialTarget = 'Target/One' } |
                    Should -Be 'Server=sql01;Database=FNMS;Persist Security Info=False'
            }

            It 'returns null when no credential-manager mode is active' {
                Mock -ModuleName 'Destination.MSSQL' Get-AuthenticationMode { 'WindowsAuthentication' }

                Get-SqlConnectionCredential -Config @{ AuthenticationMode = 'WindowsAuthentication' } | Should -BeNullOrEmpty
            }

            It 'throws when credential-manager mode is active without a target' {
                Mock -ModuleName 'Destination.MSSQL' Get-AuthenticationMode { 'CredentialManager' }

                { Get-SqlConnectionCredential -Config @{ AuthenticationMode = 'CredentialManager' } } |
                    Should -Throw '*CredentialTarget for AuthenticationMode=CredentialManager*'
            }
        }

        Context 'SQL connection construction' {
            It 'creates a SqlConnection from an explicit connection string' {
                $Connection = New-SqlConnection -Config @{ ConnectionString = 'Server=override;Database=Demo;' }
                try {
                    $Connection | Should -BeOfType ([System.Data.SqlClient.SqlConnection])
                    $Connection.ConnectionString | Should -Be 'Server=override;Database=Demo;'
                }
                finally {
                    $Connection.Dispose()
                }
            }

            It 'creates a SqlConnection using integrated security when not in credential mode' {
                Mock -ModuleName 'Destination.MSSQL' Get-AuthenticationMode { 'WindowsAuthentication' }

                $Connection = New-SqlConnection -Config @{ Server = 'sql01'; Database = 'FNMS' }
                try {
                    $Connection | Should -BeOfType ([System.Data.SqlClient.SqlConnection])
                    $Connection.ConnectionString | Should -Be 'Server=sql01;Database=FNMS;Integrated Security=True'
                }
                finally {
                    $Connection.Dispose()
                }
            }

            It 'creates a SqlConnection with SqlCredential in credential-manager mode' {
                Mock -ModuleName 'Destination.MSSQL' Get-AuthenticationMode { 'CredentialManager' }
                Mock -ModuleName 'Destination.MSSQL' Get-SqlConnectionCredential { [pscustomobject]@{ UserName = 'etl'; Password = 's3cr3t' } }

                $Connection = New-SqlConnection -Config @{ Server = 'sql01'; Database = 'FNMS'; CredentialTarget = 'Target/One' }
                try {
                    $Connection | Should -BeOfType ([System.Data.SqlClient.SqlConnection])
                    $Connection.ConnectionString | Should -Match 'Data Source=sql01'
                    $Connection.ConnectionString | Should -Match 'Initial Catalog=FNMS'
                    $Connection.ConnectionString | Should -Match 'Persist Security Info=False'
                    $Connection.ConnectionString | Should -Not -Match 'Password='
                    $Connection.Credential | Should -Not -BeNullOrEmpty
                    $Connection.Credential.UserId | Should -Be 'etl'
                }
                finally {
                    $Connection.Dispose()
                }
            }
        }

        Context 'Value helpers' {
        It 'recognizes boolean-like values' {
            Test-IsBooleanValue -Value $true | Should -BeTrue
            Test-IsBooleanValue -Value ' YES ' | Should -BeTrue
            Test-IsBooleanValue -Value 2 | Should -BeFalse
        }

        It 'recognizes integral values' {
            Test-IsInt64Value -Value 42 | Should -BeTrue
            Test-IsInt64Value -Value ' 42 ' | Should -BeTrue
            Test-IsInt64Value -Value '4.2' | Should -BeFalse
        }

        It 'recognizes decimal values' {
            Test-IsDecimalValue -Value 42.5 | Should -BeTrue
            Test-IsDecimalValue -Value ' 42.5 ' | Should -BeTrue
            Test-IsDecimalValue -Value ' ' | Should -BeFalse
        }

        It 'recognizes date/time values' {
            Test-IsDateTimeValue -Value ([datetime]'2026-04-20') | Should -BeTrue
            Test-IsDateTimeValue -Value '2026-04-20' | Should -BeTrue
            Test-IsDateTimeValue -Value 'not a date' | Should -BeFalse
        }
    }

    Context 'Conversion and property helpers' {
        It 'converts date and decimal values while preserving typed inputs' {
            Convert-ToDateTimeValue -Value ([datetime]'2026-04-20') | Should -Be ([datetime]'2026-04-20')
            Convert-ToDateTimeValue -Value '2026-04-20' | Should -Be ([datetime]'2026-04-20')
            ((Convert-ToDateTimeValue -Value '   ') -eq [DBNull]::Value) | Should -BeTrue

            Convert-ToDecimalValue -Value ([decimal]42.5) | Should -Be ([decimal]42.5)
            Convert-ToDecimalValue -Value 42.5 | Should -Be ([decimal]42.5)
            ((Convert-ToDecimalValue -Value '   ') -eq [DBNull]::Value) | Should -BeTrue
        }

        It 'initializes conversion tracking with zero counts' {
            $Tracking = Initialize-ConversionTracking -PropertyNames @('Name', 'Mail')
            $Tracking['Name'] | Should -Be 0
            $Tracking['Mail'] | Should -Be 0
        }

        It 'collects property names from rows and DataRow input' {
            $ObjectRowsForNames = @(
                [pscustomobject]@{ Name = 'Alice'; Mail = 'alice@example.org' },
                $null,
                [pscustomobject]@{ Mail = 'bob@example.org'; Department = 'IT' }
            )
            ((Get-PropertyNamesFromRows -InputRows $ObjectRowsForNames -SeedNames @('Seed', 'Name')) -join ',') | Should -Be 'Seed,Name,Mail,Department'

            $Table = New-Object System.Data.DataTable
            [void]$Table.Columns.Add('Alpha', [string])
            [void]$Table.Columns.Add('Beta', [string])
            $DataRow = $Table.NewRow()
            $DataRow['Alpha'] = 'A'
            $DataRow['Beta'] = 'B'
            [void]$Table.Rows.Add($DataRow)

            ((Get-PropertyNames -FirstRow $DataRow) -join ',') | Should -Be 'Alpha,Beta'
        }
    }
}
}
