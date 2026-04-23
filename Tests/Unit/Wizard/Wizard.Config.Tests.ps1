Set-StrictMode -Version Latest
. (Join-Path -Path (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))) -ChildPath 'TestHelpers.ps1')

Describe 'Wizard.Config helpers' {
    BeforeAll {
        $script:Module = Import-TestableAsset -RelativePath 'Wizard/Helpers/Wizard.Config.ps1' -ModuleName 'Wizard.Config.Tests'
    }

    AfterAll {
        Remove-TestModuleSafely -Module $script:Module
    }

        Context 'ConvertTo-QuotedPsd1Value' {
            It 'quotes strings and escapes apostrophes' {
                ConvertTo-QuotedPsd1Value -Value "O'Reilly" | Should -Be "'O''Reilly'"
            }

            It 'renders booleans as PowerShell literals' {
                ConvertTo-QuotedPsd1Value -Value $true | Should -Be '$true'
                ConvertTo-QuotedPsd1Value -Value $false | Should -Be '$false'
            }

            It 'renders null as an empty quoted string' {
                ConvertTo-QuotedPsd1Value -Value $null | Should -Be "''"
            }
        }

        Context 'ConvertTo-XmlEscapedValue' {
            It 'escapes XML control characters' {
                ConvertTo-XmlEscapedValue -Value '<tag a="1">&</tag>' |
                    Should -Be '&lt;tag a=&quot;1&quot;&gt;&amp;&lt;/tag&gt;'
            }
        }

        Context 'Convert-HashtableToPsd1Block' {
            It 'renders nested hashtables and arrays' {
                $Text = Convert-HashtableToPsd1Block -Hashtable @{
                    Name = 'Pipeline'
                    Source = @{ Type = 'CSV'; Path = '.\\input.csv' }
                    Properties = @('Name', 'Mail')
                }

                $Text | Should -Match 'Name = ''Pipeline'''
                $Text | Should -Match 'Source ='
                $Text | Should -Match 'Type = ''CSV'''
                $Text | Should -Match 'Properties = @\('
            }
        }

        Context 'New-ConfigContent' {
            It 'creates a full ETL config including logging and adapter sections' {
                $Content = New-ConfigContent -Pipelines @(
                    [PSCustomObject]@{
                        StepId = 'S1'
                        Name = 'Import Users'
                        StepEnabled = $true
                        Source = @{ Type = 'JSON'; Path = '.\\DATA\\users.json' }
                        Destination = @{ Type = 'CSV'; Path = '.\\OUT\\users.csv' }
                        Properties = @('Name', 'Mail')
                    }
                ) -LogLevel 'DEBUG' -RetentionDays '14' -Adapter @{ AdapterEnabled = $true; ConfigFile = 'Adapter.BAS.xml' }

                $Content | Should -Match 'Pipelines = @\('
                $Content | Should -Match "StepId = 'S1'"
                $Content | Should -Match 'StepEnabled = \$true'
                $Content | Should -Match "Level = 'DEBUG'"
                $Content | Should -Match 'RetentionDays = 14'
                $Content | Should -Match 'ModuleLogs = \$true'
                $Content | Should -Match 'AdapterEnabled = \$true'
                $Content | Should -Match 'Adapter ='
                $Content | Should -Match "ConfigFile = 'Adapter.BAS.xml'"
            }
        }
}
