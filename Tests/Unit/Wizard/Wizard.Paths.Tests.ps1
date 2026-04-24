Set-StrictMode -Version Latest
. (Join-Path -Path (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))) -ChildPath 'TestHelpers.ps1')

Describe 'Wizard.Paths helpers' {
    BeforeAll {
        $script:Module = Import-TestableAsset -RelativePath 'Wizard/Helpers/Wizard.Paths.ps1' -ModuleName 'Wizard.Paths.Tests'
    }

    AfterAll {
        Remove-TestModuleSafely -Module $script:Module
    }



        Context 'Test-PathExists' {
            It 'returns true when the expected path exists' {
                $ExistingFile = Join-Path -Path $TestDrive -ChildPath 'existing.txt'
                'ok' | Set-Content -Path $ExistingFile -Encoding UTF8
                Test-PathExists -Path $ExistingFile -PathType Leaf -Description 'Existing file' | Should -BeTrue
            }

            It 'returns false when the expected path is missing' {
                Test-PathExists -Path (Join-Path -Path $TestDrive -ChildPath 'missing.txt') -PathType Leaf -Description 'Missing file' | Should -BeFalse
            }
        }

        Context 'Resolve-NormalizedPath' {
            It 'resolves a relative path against a base path' {
                $BasePath = [System.IO.Path]::GetFullPath((Join-Path -Path $TestDrive -ChildPath 'Work/ETL'))
                Resolve-NormalizedPath -Path '.\data\input.csv' -BasePath $BasePath |
                    Should -Be (Join-Path -Path $BasePath -ChildPath 'data/input.csv')
            }

            It 'returns a fully qualified rooted path unchanged' {
                $RootedPath = [System.IO.Path]::GetFullPath((Join-Path -Path $TestDrive -ChildPath 'Work/ETL/data/input.csv'))
                Resolve-NormalizedPath -Path $RootedPath -BasePath (Join-Path -Path $TestDrive -ChildPath 'Ignored') |
                    Should -Be $RootedPath
            }
        }

        Context 'Get-SafePathSegment' {
            It 'replaces invalid filename characters and trims dots' {
                Get-SafePathSegment -Value 'Report: Q1/2026.' -Fallback 'Fallback' | Should -Be 'Report_ Q1_2026'
            }

            It 'falls back when nothing remains after sanitization' {
                Get-SafePathSegment -Value '...' -Fallback 'DefaultName' | Should -Be 'DefaultName'
            }
        }

        Context 'Test-InvalidPathChars' {
            It 'throws for invalid path characters' {
                { Test-InvalidPathChars -Value 'C:\Temp\*.csv' -Description 'Source path' } |
                    Should -Throw '*invalid path character*'
            }
        }
        Context 'Test-DirectoryWritable' {
            It 'creates the directory when needed and validates writability' {
                $Path = Join-Path -Path $TestDrive -ChildPath 'WritableFolder'
                { Test-DirectoryWritable -Path $Path -Description 'Output directory' } | Should -Not -Throw
                Test-Path -Path $Path -PathType Container | Should -BeTrue
            }
        }
}
