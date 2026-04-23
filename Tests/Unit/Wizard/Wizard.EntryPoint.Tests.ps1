Set-StrictMode -Version Latest
. (Join-Path -Path (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))) -ChildPath 'TestHelpers.ps1')
$script:Module = $null

Describe 'Wizard.EntryPoint helpers' {
    BeforeAll {
        $script:Module = Import-TestableAsset -RelativePath 'Wizard/Helpers/Wizard.EntryPoint.ps1' -ModuleName 'Wizard.EntryPoint.Tests'
    }

    AfterAll {
        if ($script:Module) {
            Remove-TestModuleSafely -Module $script:Module
        }
    }

    It 'builds the bootstrap context for New-ETLProject.ps1' {
        $Path = 'C:\Framework\New-ETLProject.ps1'
        $Context = Get-NewEtlProjectBootstrapContext -ScriptPath $Path

        $Context.ScriptPath | Should -Be $Path
        $Context.ScriptDirectory | Should -Be 'C:\Framework'
        $Context.WizardLoggingModulePath | Should -Be 'C:\Framework\Wizard\Modules\Wizard.Logging.psm1'
        $Context.WizardBootstrapPath | Should -Be 'C:\Framework\Wizard\Bootstrap.ps1'
    }

    It 'throws when a required bootstrap asset is missing' {
        Mock -ModuleName $script:Module.Name Test-Path {
            param($Path, $PathType)
            if ($Path -like '*Wizard.Logging.psm1') { return $false }
            return $true
        }

        $Context = [pscustomobject]@{
            WizardLoggingModulePath = 'C:\Framework\Wizard\Modules\Wizard.Logging.psm1'
            WizardBootstrapPath = 'C:\Framework\Wizard\Bootstrap.ps1'
        }

        { Assert-NewEtlProjectBootstrapAssets -Context $Context } | Should -Throw '*Wizard logging module not found*'
    }

    It 'delegates wizard startup to Invoke-NewEtlProjectWizard' {
        Mock -ModuleName $script:Module.Name Invoke-NewEtlProjectWizard { 7 }
        $Context = [pscustomobject]@{ ScriptPath = 'C:\Framework\New-ETLProject.ps1'; ScriptDirectory = 'C:\Framework' }

        $ExitCode = Start-NewEtlProjectWizard -Context $Context -DefaultBaseDirectory 'C:\Base' -LogFileAppend:$false -RequiredDotNetVersion '4.8' -RequireDotNet:$false -AllowDotNetInstall:$false -DotNetOfflineInstallerPath 'C:\Installers\dotnet.exe'

        $ExitCode | Should -Be 7
        Assert-MockCalled -CommandName Invoke-NewEtlProjectWizard -ModuleName $script:Module.Name -Times 1 -Exactly
    }
}
