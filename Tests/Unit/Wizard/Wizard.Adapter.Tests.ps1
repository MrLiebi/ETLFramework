
Set-StrictMode -Version Latest
. (Join-Path -Path (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))) -ChildPath 'TestHelpers.ps1')

Describe 'Wizard.Adapter helpers' {
    BeforeAll {
        $script:Module = Import-TestableAsset -RelativePath 'Wizard/Helpers/Wizard.Adapter.ps1' -ModuleName 'Wizard.Adapter.Tests' -AdditionalRelativePaths @(
            'Wizard/Helpers/Wizard.Config.ps1',
            'Wizard/Helpers/Wizard.Paths.ps1'
        )
    }

    AfterAll {
        Remove-TestModuleSafely -Module $script:Module
    }



        Context 'Read-AdapterConfiguration' {
            It 'returns a disabled adapter configuration when scaffolding is skipped' {
                Mock -ModuleName $script:Module.Name Read-BooleanChoice { $false }

                $Result = Read-AdapterConfiguration -ProjectName 'DemoProject'

                $Result.AdapterEnabled | Should -BeFalse
                $Result.XmlFileName | Should -Be 'Adapter.BAS.xml'
                $Result.Config.AdapterEnabled | Should -BeFalse
            }

            It 'builds an enabled adapter configuration with connection string defaults' {
                $script:InputAnswers = [System.Collections.Generic.Queue[string]]::new()
                foreach ($Answer in @('Import-Demo', 'FNMSStage', 'sql01')) { [void]$script:InputAnswers.Enqueue($Answer) }

                Mock -ModuleName $script:Module.Name Read-BooleanChoice { $true }
                Mock -ModuleName $script:Module.Name Read-InputValue { $script:InputAnswers.Dequeue() }

                $Result = Read-AdapterConfiguration -ProjectName 'DemoProject'

                $Result.AdapterEnabled | Should -BeTrue
                $Result.AdapterName | Should -Be 'Import-Demo'
                $Result.ConnectionString | Should -Match 'Initial Catalog=FNMSStage'
                $Result.ConnectionString | Should -Match 'Data Source=sql01'
                $Result.Config.ConfigFile | Should -Be 'Adapter.BAS.xml'
            }
        }

        Context 'New-AdapterXmlContent' {
            It 'replaces template tokens and escapes XML-sensitive values' {
                $TemplatePath = Join-Path -Path $TestDrive -ChildPath 'Adapter.BAS.xml'
                @'
<Adapter>
  <Name>__ADAPTER_NAME__</Name>
  <ConnectionString>__CONNECTION_STRING__</ConnectionString>
</Adapter>
'@ | Set-Content -Path $TemplatePath -Encoding UTF8

                $Content = New-AdapterXmlContent -TemplatePath $TemplatePath -ImportName 'A&B <Demo>' -ConnectionString 'Server=SQL01;Pwd="abc&123"'
                $Content | Should -Match '&lt;Demo&gt;'
                $Content | Should -Match 'A&amp;B'
                $Content | Should -Match 'abc&amp;123'
            }
        }

        Context 'New-AdapterXmlFile' {
            It 'creates the adapter XML file when adapter scaffolding is enabled' {
                $TemplatePath = Join-Path -Path $TestDrive -ChildPath 'AdapterTemplate.xml'
                $AdapterDirectory = Join-Path -Path $TestDrive -ChildPath 'Adapter'
                '<Adapter><Name>__ADAPTER_NAME__</Name><ConnectionString>__CONNECTION_STRING__</ConnectionString></Adapter>' |
                    Set-Content -Path $TemplatePath -Encoding UTF8

                $Adapter = [PSCustomObject]@{
                    AdapterEnabled   = $true
                    AdapterName      = 'DemoAdapter'
                    ConnectionString = 'Server=localhost;Database=FNMSStaging'
                    XmlFileName      = 'Adapter.BAS.xml'
                }

                $AdapterFile = New-AdapterXmlFile -Adapter $Adapter -AdapterDirectory $AdapterDirectory -TemplatePath $TemplatePath
                Test-Path -Path $AdapterFile -PathType Leaf | Should -BeTrue
                (Get-Content -Path $AdapterFile -Raw) | Should -Match 'DemoAdapter'
            }

            It 'returns null when adapter generation is disabled' {
                $Result = New-AdapterXmlFile -Adapter ([PSCustomObject]@{ AdapterEnabled = $false; XmlFileName = 'Adapter.BAS.xml' }) -AdapterDirectory $TestDrive -TemplatePath (Join-Path -Path $TestDrive -ChildPath 'unused.xml')
                $Result | Should -BeNullOrEmpty
            }
        }
}
