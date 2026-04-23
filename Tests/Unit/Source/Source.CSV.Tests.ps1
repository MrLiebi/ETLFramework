Set-StrictMode -Version Latest
. (Join-Path -Path (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))) -ChildPath 'TestHelpers.ps1')

Describe 'Source.CSV module' {
    BeforeAll {
        $Workspace = Set-FrameworkTestEnvironment -ProjectRoot (Join-Path -Path $TestDrive -ChildPath 'CsvProject')
        $script:ProjectRoot = $Workspace.ProjectRoot
        $script:Module = Import-TestableAsset -RelativePath 'Templates/Modules/Source/Source.CSV.psm1'
    }

    AfterAll {
        Remove-TestModuleSafely -Module $script:Module
        Clear-FrameworkTestEnvironment
    }

    Context 'Invoke-Extract integration' {
        It 'reads CSV rows, skips blank lines, and filters properties' {
            $CsvPath = Join-Path -Path $env:ETL_PROJECT_ROOT -ChildPath 'DATA\users.csv'
            New-Item -Path (Split-Path -Path $CsvPath -Parent) -ItemType Directory -Force | Out-Null
            @(
                'Name;Mail;Department',
                'Alice;alice@example.org;IT',
                ';;',
                'Bob;bob@example.org;HR'
            ) | Set-Content -Path $CsvPath -Encoding UTF8

            $Rows = @(Invoke-Extract -Config @{ Path = '.\DATA\users.csv'; Delimiter = ';'; Encoding = 'utf8' } -Properties @('Name', 'Mail'))

            $Rows.Count | Should -Be 2
            $Rows[0].Name | Should -Be 'Alice'
            @($Rows[0].PSObject.Properties.Name) | Should -Be @('Name', 'Mail')
            $Rows[1].Name | Should -Be 'Bob'
            $env:ETL_LAST_SOURCE_FILE | Should -Match 'users\.csv$'
        }

        It 'resolves a single file from a folder pattern' {
            $DataDir = Join-Path -Path $env:ETL_PROJECT_ROOT -ChildPath 'DATA'
            New-Item -Path $DataDir -ItemType Directory -Force | Out-Null
            @(
                'Name;Mail',
                'Alice;alice@example.org'
            ) | Set-Content -Path (Join-Path $DataDir 'input.csv') -Encoding UTF8

            $Rows = @(Invoke-Extract -Config @{ Path = '.\DATA'; FilePattern = 'input.csv'; Delimiter = ';'; Encoding = 'utf8' } -Properties @('*'))
            $Rows.Count | Should -Be 1
            $Rows[0].Name | Should -Be 'Alice'
        }
    }
}
