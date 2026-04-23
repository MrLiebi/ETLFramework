Set-StrictMode -Version Latest
. (Join-Path -Path (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))) -ChildPath 'TestHelpers.ps1')

Describe 'Source.XML module' {
    BeforeAll {
        $Workspace = Set-FrameworkTestEnvironment -ProjectRoot (Join-Path -Path $TestDrive -ChildPath 'XmlProject')
        $script:ProjectRoot = $Workspace.ProjectRoot
        $script:Module = Import-TestableAsset -RelativePath 'Templates/Modules/Source/Source.XML.psm1'
    }

    AfterAll {
        Remove-TestModuleSafely -Module $script:Module
        Clear-FrameworkTestEnvironment
    }

    Context 'Invoke-Extract integration' {
        It 'extracts XML rows and filters top-level properties' {
            $XmlPath = Join-Path -Path $env:ETL_PROJECT_ROOT -ChildPath 'DATA\accounts.xml'
            New-Item -Path (Split-Path -Path $XmlPath -Parent) -ItemType Directory -Force | Out-Null
            @'
<rows>
  <row>
    <Name>Alice</Name>
    <Active>true</Active>
  </row>
  <row>
    <Name>Bob</Name>
    <Active>false</Active>
  </row>
</rows>
'@ | Set-Content -Path $XmlPath -Encoding UTF8

            $Rows = @(Invoke-Extract -Config @{ Path = '.\DATA\accounts.xml'; RecordXPath = '/rows/row' } -Properties @('Name', 'Active'))

            $Rows.Count | Should -Be 2
            $Rows[0].Name | Should -Be 'Alice'
            $Rows[0].Active | Should -Be 'true'
            $Rows[1].Name | Should -Be 'Bob'
            $env:ETL_LAST_SOURCE_TYPE | Should -Be 'XML'
        }

        It 'fails when a folder pattern matches more than one file' {
            $Folder = Join-Path -Path $env:ETL_PROJECT_ROOT -ChildPath 'DATA\Many'
            New-Item -Path $Folder -ItemType Directory -Force | Out-Null
            '<rows><row><Name>A</Name></row></rows>' | Set-Content -Path (Join-Path $Folder 'a.xml') -Encoding UTF8
            '<rows><row><Name>B</Name></row></rows>' | Set-Content -Path (Join-Path $Folder 'b.xml') -Encoding UTF8

            {
                @(Invoke-Extract -Config @{ Path = '.\DATA\Many'; FilePattern = '*.xml'; RecordXPath = '/rows/row' } -Properties @('*'))
            } | Should -Throw '*exactly one matching file*'
        }
    }
}
