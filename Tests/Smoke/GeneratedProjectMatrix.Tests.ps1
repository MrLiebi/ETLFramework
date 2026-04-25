Set-StrictMode -Version Latest

Describe 'Generated project matrix smoke tests' {
    BeforeAll {
        $script:FrameworkRoot = Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent
        $script:MatrixScriptPath = Join-Path -Path $script:FrameworkRoot -ChildPath 'Tests/Invoke-GeneratedProjectMatrix.ps1'
    }

    It 'runs the default scenario matrix successfully' {
        $OutputRoot = Join-Path -Path $TestDrive -ChildPath 'MatrixDefault'
        $Summary = & $script:MatrixScriptPath -FrameworkRoot $script:FrameworkRoot -OutputRoot $OutputRoot -PassThru

        $Summary.Total | Should -Be 4
        $Summary.Failed | Should -Be 0
        $Summary.Passed | Should -Be 4
        @($Summary.Results.Name) | Should -Contain 'csv_basic'
        @($Summary.Results.Name) | Should -Contain 'json_rootpath'
        @($Summary.Results.Name) | Should -Contain 'xml_delete_after_import'
        @($Summary.Results.Name) | Should -Contain 'missing_adapter_failure'
    }

    It 'runs only selected scenarios when Scenario is provided' {
        $OutputRoot = Join-Path -Path $TestDrive -ChildPath 'MatrixSubset'
        $Summary = & $script:MatrixScriptPath -FrameworkRoot $script:FrameworkRoot -OutputRoot $OutputRoot -Scenario @('csv_basic', 'missing_adapter_failure') -PassThru

        $Summary.Total | Should -Be 2
        $Summary.Failed | Should -Be 0
        @($Summary.Results.Name) | Should -Contain 'csv_basic'
        @($Summary.Results.Name) | Should -Contain 'missing_adapter_failure'
        @($Summary.Results | Where-Object { $_.Name -eq 'missing_adapter_failure' }).Count | Should -Be 1
        (@($Summary.Results | Where-Object { $_.Name -eq 'missing_adapter_failure' })[0].ExitCode) | Should -Not -Be 0
    }

    It 'fails fast for unknown scenario names' {
        $OutputRoot = Join-Path -Path $TestDrive -ChildPath 'MatrixUnknown'
        {
            & $script:MatrixScriptPath -FrameworkRoot $script:FrameworkRoot -OutputRoot $OutputRoot -Scenario @('does_not_exist') -PassThru
        } | Should -Throw '*Unknown scenario*'
    }
}
