Set-StrictMode -Version Latest
. (Join-Path -Path (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))) -ChildPath 'TestHelpers.ps1')

Describe 'Wizard.FileSources helpers' {
    BeforeAll {
        $script:Module = Import-TestableAsset -RelativePath 'Wizard/Helpers/Wizard.FileSources.ps1' -ModuleName 'Wizard.FileSources.Tests' -AdditionalRelativePaths @(
            'Wizard/Helpers/Wizard.Prompts.ps1'
        )
    }

    AfterAll {
        Remove-TestModuleSafely -Module $script:Module
    }

    Context 'Get-NormalizedSourceFilePattern' {
        It 'adds or preserves expected file extensions for supported source types' {
            Get-NormalizedSourceFilePattern -RawPattern 'users' -SourceType 'CSV' | Should -Be 'users.csv'
            Get-NormalizedSourceFilePattern -RawPattern 'book' -SourceType 'XLSX' | Should -Be 'book.xls*'
            Get-NormalizedSourceFilePattern -RawPattern 'events.jsonl' -SourceType 'JSON' | Should -Be 'events.jsonl'
        }
    }

    Context 'Read-FileSourcePostImportConfiguration' {
        It 'normalizes backup settings and delete choice' {
            $script:BooleanAnswers = [System.Collections.Generic.Queue[object]]::new()
            [void]$script:BooleanAnswers.Enqueue($true)
            [void]$script:BooleanAnswers.Enqueue($false)

            Mock -ModuleName $script:Module.Name Read-BooleanChoice { $script:BooleanAnswers.Dequeue() }
            Mock -ModuleName $script:Module.Name Read-InputValue { ' INPUT\Archive\ ' }

            $Result = Read-FileSourcePostImportConfiguration -SourceType 'CSV'

            $Result.BackupAfterImport | Should -BeTrue
            $Result.BackupPath | Should -Be 'INPUT\Archive'
            $Result.DeleteAfterImport | Should -BeFalse
        }
    }

    Context 'Read-FileSourceConfiguration' {
        It 'returns a concrete file path when specific file mode is selected' {
            $script:InputAnswers = [System.Collections.Generic.Queue[string]]::new()
            [void]$script:InputAnswers.Enqueue('INPUT')
            [void]$script:InputAnswers.Enqueue('users.csv')

            Mock -ModuleName $script:Module.Name Read-Choice { 'Specific file' }
            Mock -ModuleName $script:Module.Name Read-InputValue { $script:InputAnswers.Dequeue() }

            $Result = Read-FileSourceConfiguration -SourceType 'CSV' -SpecificFileDefault 'default.csv'

            $Result.Path | Should -Be (Join-Path -Path 'INPUT' -ChildPath 'users.csv')
            $Result.FilePattern | Should -BeNullOrEmpty
        }

        It 'returns a directory and normalized pattern when file pattern mode is selected' {
            $script:InputAnswers = [System.Collections.Generic.Queue[string]]::new()
            [void]$script:InputAnswers.Enqueue('INPUT\JSON')
            [void]$script:InputAnswers.Enqueue('accounts')

            Mock -ModuleName $script:Module.Name Read-Choice { 'File pattern' }
            Mock -ModuleName $script:Module.Name Read-InputValue { $script:InputAnswers.Dequeue() }

            $Result = Read-FileSourceConfiguration -SourceType 'JSON' -SpecificFileDefault 'default.json'

            $Result.Path | Should -Be 'INPUT\JSON'
            $Result.FilePattern | Should -Be 'accounts.json*'
        }
    }
}
