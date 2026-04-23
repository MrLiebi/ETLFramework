Set-StrictMode -Version Latest
. (Join-Path -Path (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))) -ChildPath 'TestHelpers.ps1')

Describe 'Framework.Logging' {
    BeforeAll {
        $script:Module = Import-TestableAsset -RelativePath 'Templates/Modules/Common/Framework.Logging.psm1'
    }

    AfterAll {
        Remove-TestModuleSafely -Module $script:Module
        Clear-FrameworkTestEnvironment
    }

        Context 'Test-EtlLogLevelEnabled' {
            It 'allows messages at or above the configured level' {
                Test-EtlLogLevelEnabled -ConfiguredLevel 'INFO' -MessageLevel 'INFO' | Should -BeTrue
                Test-EtlLogLevelEnabled -ConfiguredLevel 'INFO' -MessageLevel 'ERROR' | Should -BeTrue
                Test-EtlLogLevelEnabled -ConfiguredLevel 'WARN' -MessageLevel 'INFO' | Should -BeFalse
            }
        }

        Context 'Initialize-EtlScriptLogContext' {
            It 'creates a reusable context with defaults' {
                $Context = Initialize-EtlScriptLogContext -LogDirectory 'C:\Temp\Logs' -LogFile 'C:\Temp\Logs\run.log'
                $Context.LogLevel | Should -Be 'INFO'
                $Context.RetentionDays | Should -Be 30
                $Context.HasWrittenFirstLog | Should -BeFalse
                $Context.CleanupKey | Should -Be 'Script'
            }
        }

        Context 'Write-EtlScriptLog' {
            It 'creates the log file and appends subsequent entries' {
                $Workspace = Set-FrameworkTestEnvironment
                $LogFile = Join-Path -Path $Workspace.LogRoot -ChildPath 'framework.log'
                $Context = Initialize-EtlScriptLogContext -LogDirectory $Workspace.LogRoot -LogFile $LogFile -Append:$true

                Write-EtlScriptLog -Context $Context -Message 'First message' -Level 'INFO'
                Write-EtlScriptLog -Context $Context -Message 'Second message' -Level 'ERROR'

                $Content = @(Get-Content -Path $LogFile)
                $Content.Count | Should -Be 2
                $Content[0] | Should -Match '\[INFO\] First message$'
                $Content[1] | Should -Match '\[ERROR\] Second message$'
            }

            It 'honors the ETL_LOG_LEVEL environment override' {
                $Workspace = Set-FrameworkTestEnvironment
                $LogFile = Join-Path -Path $Workspace.LogRoot -ChildPath 'level.log'
                $Context = Initialize-EtlScriptLogContext -LogDirectory $Workspace.LogRoot -LogFile $LogFile -LogLevel 'DEBUG'
                $env:ETL_LOG_LEVEL = 'ERROR'

                Write-EtlScriptLog -Context $Context -Message 'Suppressed message' -Level 'INFO'
                Write-EtlScriptLog -Context $Context -Message 'Visible message' -Level 'ERROR'

                $Content = @(Get-Content -Path $LogFile)
                $Content.Count | Should -Be 1
                $Content[0] | Should -Match 'Visible message$'
            }
        }

        Context 'Invoke-EtlLogRetentionCleanup' {
            It 'removes only outdated log files' {
                $Workspace = Set-FrameworkTestEnvironment
                $OldLog = Join-Path -Path $Workspace.LogRoot -ChildPath 'old.log'
                $NewLog = Join-Path -Path $Workspace.LogRoot -ChildPath 'new.log'
                $TextFile = Join-Path -Path $Workspace.LogRoot -ChildPath 'keep.txt'

                Set-Content -Path $OldLog -Value 'old' -Encoding UTF8
                Set-Content -Path $NewLog -Value 'new' -Encoding UTF8
                Set-Content -Path $TextFile -Value 'text' -Encoding UTF8

                (Get-Item $OldLog).LastWriteTime = (Get-Date).AddDays(-40)
                (Get-Item $NewLog).LastWriteTime = (Get-Date).AddDays(-2)
                (Get-Item $TextFile).LastWriteTime = (Get-Date).AddDays(-60)

                Invoke-EtlLogRetentionCleanup -LogDirectory $Workspace.LogRoot -RetentionDays 30 -CleanupKey 'RetentionTest'

                Test-Path -Path $OldLog | Should -BeFalse
                Test-Path -Path $NewLog | Should -BeTrue
                Test-Path -Path $TextFile | Should -BeTrue
            }
        }
}
