
Set-StrictMode -Version Latest
. (Join-Path -Path (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))) -ChildPath 'TestHelpers.ps1')

Describe 'Wizard.Logging module' {
    BeforeAll {
        $script:Module = Import-TestableAsset -RelativePath 'Wizard/Modules/Wizard.Logging.psm1'
    }

    AfterAll {
        Remove-TestModuleSafely -Module $script:Module
    }

        Context 'Initialize-WizardLogContext' {
            It 'creates the log directory and cleans outdated files once' {
                $LogDirectory = Join-Path -Path $TestDrive -ChildPath 'WizardLog'
                New-Item -Path $LogDirectory -ItemType Directory -Force | Out-Null
                $OldLog = Join-Path -Path $LogDirectory -ChildPath 'old.log'
                $NewLog = Join-Path -Path $LogDirectory -ChildPath 'new.log'
                Set-Content -Path $OldLog -Value 'old' -Encoding UTF8
                Set-Content -Path $NewLog -Value 'new' -Encoding UTF8
                (Get-Item $OldLog).LastWriteTime = (Get-Date).AddDays(-40)
                (Get-Item $NewLog).LastWriteTime = (Get-Date).AddDays(-2)

                $Context = Initialize-WizardLogContext -LogDirectory $LogDirectory -LogFile (Join-Path -Path $LogDirectory -ChildPath 'wizard.log') -RetentionDays 30

                Test-Path -Path $OldLog | Should -BeFalse
                Test-Path -Path $NewLog | Should -BeTrue
                $Context.CleanupDone | Should -BeTrue
            }
        }

        Context 'Write-WizardLog and Write-WizardException' {
            It 'writes log lines and respects the configured log level' {
                $LogDirectory = Join-Path -Path $TestDrive -ChildPath 'WizardLogLevel'
                $LogFile = Join-Path -Path $LogDirectory -ChildPath 'wizard.log'
                $Context = Initialize-WizardLogContext -LogDirectory $LogDirectory -LogFile $LogFile -LogLevel 'WARN'

                Write-WizardLog -Context $Context -Message 'Debug suppressed' -Level 'DEBUG'
                Write-WizardLog -Context $Context -Message 'Visible warning' -Level 'WARN'

                $Content = @(Get-Content -Path $LogFile)
                $Content.Count | Should -Be 1
                $Content[0] | Should -Match '\[WARN\] Visible warning$'
            }

            It 'logs exception details with the supplied prefix' {
                $LogDirectory = Join-Path -Path $TestDrive -ChildPath 'WizardException'
                $LogFile = Join-Path -Path $LogDirectory -ChildPath 'wizard.log'
                $Context = Initialize-WizardLogContext -LogDirectory $LogDirectory -LogFile $LogFile -LogLevel 'ERROR'

                try {
                    throw 'Boom'
                }
                catch {
                    Write-WizardException -Context $Context -ErrorRecord $_ -Prefix 'Wizard failed:'
                }

                (Get-Content -Path $LogFile -Raw) | Should -Match 'Wizard failed: Boom'
            }
        }
}
