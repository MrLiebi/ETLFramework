Set-StrictMode -Version Latest
. (Join-Path -Path (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))) -ChildPath 'TestHelpers.ps1')

$Workspace = Set-FrameworkTestEnvironment -ProjectRoot (Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath ([System.Guid]::NewGuid().Guid))
$script:ProjectRoot = $Workspace.ProjectRoot
$null = Import-TestableAsset -RelativePath 'Templates/Modules/Source/Source.XLSX.psm1'

Describe 'Source.XLSX module' {
    AfterAll {
        . (Join-Path -Path (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))) -ChildPath 'TestHelpers.ps1')
        Remove-TestModuleSafely -Module 'Source.XLSX'
        Clear-FrameworkTestEnvironment
    }

    InModuleScope 'Source.XLSX' {
        Context 'Invoke-Extract configuration gate' {
            It 'throws when Path is missing' {
                { Invoke-Extract -Config @{} -Properties @('*') } |
                    Should -Throw '*Source XLSX configuration validation failed*'
            }

            It 'throws when numeric row settings are invalid' {
                $Bad = @{
                    Path               = '.\DATA\book.xlsx'
                    HeaderRowNumber    = '0'
                    DataStartRowNumber = '2'
                    FirstDataColumn    = '1'
                }
                { Invoke-Extract -Config $Bad -Properties @('*') } |
                    Should -Throw '*Source XLSX configuration validation failed*'
            }
        }

        Context 'Helper functions' {
            It 'converts excel cell values to normalized text' {
                Convert-ExcelCellValueToText -Value $null | Should -BeNullOrEmpty
                Convert-ExcelCellValueToText -Value $true | Should -Be 'TRUE'
                Convert-ExcelCellValueToText -Value ([datetime]'2026-04-24 12:30:00') | Should -Be '2026-04-24 12:30:00'
                Convert-ExcelCellValueToText -Value 42 | Should -Be '42'
            }

            It 'resolves relative source path through project path helper' {
                Mock -ModuleName 'Source.XLSX' Resolve-EtlProjectPath { '/tmp/project/DATA/book.xlsx' }
                Resolve-AbsolutePath -Path 'DATA/book.xlsx' | Should -Be '/tmp/project/DATA/book.xlsx'
            }

            It 'normalizes duplicate and empty header names' {
                $Seen = @{}
                Get-NormalizedHeaderName -Value 'Name' -ColumnNumber 1 -SeenHeaderNames $Seen | Should -Be 'Name'
                Get-NormalizedHeaderName -Value 'Name' -ColumnNumber 2 -SeenHeaderNames $Seen | Should -Be 'Name_2'
                Get-NormalizedHeaderName -Value '' -ColumnNumber 3 -SeenHeaderNames $Seen | Should -Be 'Column3'
            }

            It 'resolves workbook path from a direct file or a single-match folder pattern' {
                $Workbook = Join-Path -Path $TestDrive -ChildPath 'book.xlsx'
                Set-Content -Path $Workbook -Value 'x' -Encoding UTF8
                Resolve-SourceWorkbookFile -ResolvedPath $Workbook -FilePattern '*.xlsx' | Should -Be $Workbook

                $Folder = Join-Path -Path $TestDrive -ChildPath 'folder'
                New-Item -Path $Folder -ItemType Directory -Force | Out-Null
                $SingleWorkbook = Join-Path -Path $Folder -ChildPath 'single.xlsx'
                Set-Content -Path $SingleWorkbook -Value 'x' -Encoding UTF8
                Resolve-SourceWorkbookFile -ResolvedPath $Folder -FilePattern '*.xlsx' | Should -Be $SingleWorkbook
            }

            It 'throws when workbook folder has no files or multiple matches' {
                $EmptyFolder = Join-Path -Path $TestDrive -ChildPath 'empty'
                New-Item -Path $EmptyFolder -ItemType Directory -Force | Out-Null
                { Resolve-SourceWorkbookFile -ResolvedPath $EmptyFolder -FilePattern '*.xlsx' } | Should -Throw '*No Excel files found*'

                $ManyFolder = Join-Path -Path $TestDrive -ChildPath 'many'
                New-Item -Path $ManyFolder -ItemType Directory -Force | Out-Null
                Set-Content -Path (Join-Path -Path $ManyFolder -ChildPath 'a.xlsx') -Value 'a' -Encoding UTF8
                Set-Content -Path (Join-Path -Path $ManyFolder -ChildPath 'b.xlsx') -Value 'b' -Encoding UTF8
                { Resolve-SourceWorkbookFile -ResolvedPath $ManyFolder -FilePattern '*.xlsx' } | Should -Throw '*requires exactly one matching file*'
            }

            It 'throws when resolved workbook path does not exist as file or folder' {
                $MissingPath = Join-Path -Path $TestDrive -ChildPath 'missing/path'
                { Resolve-SourceWorkbookFile -ResolvedPath $MissingPath -FilePattern '*.xlsx' } | Should -Throw '*path not found*'
            }
        }
    }
}
