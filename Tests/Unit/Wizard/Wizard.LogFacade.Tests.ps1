Set-StrictMode -Version Latest
. (Join-Path -Path (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))) -ChildPath 'TestHelpers.ps1')

Describe 'Wizard.LogFacade helper' {
    BeforeAll {
        $script:Module = Import-TestableAsset -RelativePath 'Wizard/Helpers/Wizard.LogFacade.ps1' -ModuleName 'Wizard.LogFacade.Tests'
        & $script:Module { $script:LogContext = [PSCustomObject]@{ LogFile = 'wizard.log' } }
    }

    AfterAll {
        Remove-TestModuleSafely -Module $script:Module
    }

    It 'forwards log messages to Write-WizardLog with the shared wizard context' {
        Mock -ModuleName $script:Module.Name Write-WizardLog {}

        Write-WizardFacadeLog -Message 'delegated' -Level 'WARN'

        Should -Invoke Write-WizardLog -ModuleName $script:Module.Name -Times 1 -ParameterFilter {
            $Context.LogFile -eq 'wizard.log' -and $Message -eq 'delegated' -and $Level -eq 'WARN'
        }
    }
}
