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
    }
}
