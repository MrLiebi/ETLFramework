Set-StrictMode -Version Latest
. (Join-Path -Path (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))) -ChildPath 'TestHelpers.ps1')

Describe 'Source.JSON module' {
    BeforeAll {
        $Workspace = Set-FrameworkTestEnvironment -ProjectRoot (Join-Path -Path $TestDrive -ChildPath 'JsonProject')
        $script:ProjectRoot = $Workspace.ProjectRoot
        $script:Module = Import-TestableAsset -RelativePath 'Templates/Modules/Source/Source.JSON.psm1'
    }

    AfterAll {
        Remove-TestModuleSafely -Module $script:Module
        Clear-FrameworkTestEnvironment
    }

    Context 'Invoke-Extract integration' {
        It 'extracts rows from a classic JSON array and applies property selection' {
            $JsonPath = Join-Path -Path $env:ETL_PROJECT_ROOT -ChildPath 'DATA\accounts.json'
            New-Item -Path (Split-Path -Path $JsonPath -Parent) -ItemType Directory -Force | Out-Null
            @'
{
  "rows": [
    { "Name": "Alice", "Active": true },
    { "Name": "Bob",   "Active": false }
  ]
}
'@ | Set-Content -Path $JsonPath -Encoding UTF8

            $Rows = @(Invoke-Extract -Config @{ Path = '.\DATA\accounts.json'; RootPath = 'rows' } -Properties @('Name', 'Active'))

            $Rows.Count | Should -Be 2
            $Rows[0].Name | Should -Be 'Alice'
            $Rows[0].Active | Should -BeTrue
            $Rows[1].Name | Should -Be 'Bob'
            $env:ETL_LAST_SOURCE_TYPE | Should -Be 'JSON'
        }

        It 'extracts rows from JSONL files' {
            $JsonPath = Join-Path -Path $env:ETL_PROJECT_ROOT -ChildPath 'DATA\accounts.jsonl'
            New-Item -Path (Split-Path -Path $JsonPath -Parent) -ItemType Directory -Force | Out-Null
            @'
{"Name":"Alice","Active":true}
{"Name":"Bob","Active":false}
'@ | Set-Content -Path $JsonPath -Encoding UTF8

            $Rows = @(Invoke-Extract -Config @{ Path = '.\DATA\accounts.jsonl'; Format = 'JsonL' } -Properties @('Name', 'Active'))
            $Rows.Count | Should -Be 2
            $Rows[1].Name | Should -Be 'Bob'
        }
    }
}
