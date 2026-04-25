Set-StrictMode -Version Latest
. (Join-Path -Path (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))) -ChildPath 'TestHelpers.ps1')

Describe 'Destination.CSV module' {
    BeforeAll {
        $script:ProjectRoot = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath ([System.Guid]::NewGuid().Guid)
        $Workspace = Set-FrameworkTestEnvironment -ProjectRoot (Join-Path -Path $script:ProjectRoot -ChildPath 'CsvDestinationProject')
        $script:ProjectRoot = $Workspace.ProjectRoot
        $script:Module = Import-TestableAsset -RelativePath 'Templates/Modules/Destination/Destination.CSV.psm1'
    }

    AfterAll {
        Remove-TestModuleSafely -Module $script:Module
        Clear-FrameworkTestEnvironment

        [System.GC]::Collect()
        [System.GC]::WaitForPendingFinalizers()
        Start-Sleep -Milliseconds 400

        if (Test-Path -LiteralPath $script:ProjectRoot) {
            $ErrorActionPreference = 'Continue'

            for ($Attempt = 1; $Attempt -le 8; $Attempt++) {
                try {
                    Remove-Item -LiteralPath $script:ProjectRoot -Recurse -Force -ErrorAction Stop
                    break
                }
                catch {
                    if ($Attempt -eq 8) {
                        throw
                    }

                    [System.GC]::Collect()
                    [System.GC]::WaitForPendingFinalizers()
                    Start-Sleep -Milliseconds (250 * $Attempt)
                }
            }
        }
    }

    Context 'Invoke-Load integration' {
        It 'creates a CSV file and writes incoming pipeline data' {
            $Target = Join-Path -Path $env:ETL_PROJECT_ROOT -ChildPath 'OUT\users.csv'
            $Data = @(
                [PSCustomObject]@{ Name = 'Alice'; Mail = 'alice@example.org' },
                [PSCustomObject]@{ Name = 'Bob'; Mail = 'bob@example.org' }
            )

            $Data | Invoke-Load -Config @{ Path = '.\OUT\users.csv'; Delimiter = ';'; Encoding = 'UTF8'; Force = $true; BatchSize = 1 }

            Test-Path -Path $Target -PathType Leaf | Should -BeTrue
            $Lines = @(Get-Content -Path $Target)
            $Lines[0] | Should -Be '"Name";"Mail"'
            $Lines[1] | Should -Match 'Alice'
            $Lines[2] | Should -Match 'Bob'
        }

        It 'accepts simulated LDAP output rows and writes them unchanged to CSV' {
            $Target = Join-Path -Path $env:ETL_PROJECT_ROOT -ChildPath 'OUT\ldap-users.csv'
            $LdapRows = @(
                [PSCustomObject]@{
                    distinguishedName = 'CN=Alice Smith,OU=Users,DC=example,DC=org'
                    mail              = 'alice@example.org'
                    samAccountName    = 'asmith'
                    whenChanged       = '2026-04-25 12:15:00'
                },
                [PSCustomObject]@{
                    distinguishedName = 'CN=Bob Jones,OU=Users,DC=example,DC=org'
                    mail              = 'bob@example.org'
                    samAccountName    = 'bjones'
                    whenChanged       = '2026-04-24 09:00:00'
                }
            )

            $LdapRows | Invoke-Load -Config @{ Path = '.\OUT\ldap-users.csv'; Delimiter = ';'; Encoding = 'UTF8'; Force = $true; BatchSize = 2 }

            Test-Path -Path $Target -PathType Leaf | Should -BeTrue
            $CsvContent = Get-Content -Path $Target -Raw
            $CsvContent | Should -Match 'distinguishedName'
            $CsvContent | Should -Match 'alice@example.org'
            $CsvContent | Should -Match 'CN=Bob Jones,OU=Users,DC=example,DC=org'
        }

        It 'supports append mode with matching schema' {
            $Target = Join-Path -Path $env:ETL_PROJECT_ROOT -ChildPath 'OUT\append-users.csv'
            New-Item -Path (Split-Path -Path $Target -Parent) -ItemType Directory -Force | Out-Null
            @(
                '"Name";"Mail"',
                '"Alice";"alice@example.org"'
            ) | Set-Content -Path $Target -Encoding UTF8

            [PSCustomObject]@{ Name = 'Bob'; Mail = 'bob@example.org' } |
                Invoke-Load -Config @{ Path = '.\OUT\append-users.csv'; Delimiter = ';'; Encoding = 'UTF8'; Append = $true; BatchSize = 1 }

            $Lines = @(Get-Content -Path $Target)
            $Lines.Count | Should -Be 3
            $Lines[2] | Should -Match 'Bob'
        }

        It 'rejects append mode when the schema differs' {
            $Target = Join-Path -Path $env:ETL_PROJECT_ROOT -ChildPath 'OUT\schema-mismatch.csv'
            New-Item -Path (Split-Path -Path $Target -Parent) -ItemType Directory -Force | Out-Null
            @(
                '"Name";"Mail"',
                '"Alice";"alice@example.org"'
            ) | Set-Content -Path $Target -Encoding UTF8

            {
                [PSCustomObject]@{ Name = 'Bob'; Department = 'HR' } |
                    Invoke-Load -Config @{ Path = '.\OUT\schema-mismatch.csv'; Delimiter = ';'; Encoding = 'UTF8'; Append = $true; BatchSize = 1 }
            } | Should -Throw '*schema mismatch*'

        }
    }
}
