Set-StrictMode -Version Latest
. (Join-Path -Path (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))) -ChildPath 'TestHelpers.ps1')
$script:Module = $null

Describe 'Wizard.Bootstrap loader' {
    BeforeAll {
        $script:Module = Import-TestableAsset -RelativePath 'Wizard/Bootstrap.ps1' -ModuleName 'Wizard.Bootstrap.Tests'
    }

    AfterAll {
        if ($script:Module) {
            Remove-TestModuleSafely -Module $script:Module
        }
    }

    It 'loads and exposes core helper commands from the bootstrap file' {
        Get-Command -Module $script:Module.Name -Name New-ConfigContent -ErrorAction Stop | Should -Not -BeNullOrEmpty
        Get-Command -Module $script:Module.Name -Name Get-SafePathSegment -ErrorAction Stop | Should -Not -BeNullOrEmpty
        Get-Command -Module $script:Module.Name -Name New-TaskSchedulerXmlContent -ErrorAction Stop | Should -Not -BeNullOrEmpty
    }
}
