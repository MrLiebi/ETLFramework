<#
    Bootstrap loader for ETL Project Wizard helper functions.

    Comments and user-visible wizard text use American English spelling.
#>

$WizardRoot = Split-Path -Path $MyInvocation.MyCommand.Path -Parent
$HelperFiles = @(
    (Join-Path -Path $WizardRoot -ChildPath 'Helpers/Wizard.LogFacade.ps1')
    (Join-Path -Path $WizardRoot -ChildPath 'Helpers/Wizard.EntryPoint.ps1')
    (Join-Path -Path $WizardRoot -ChildPath 'Helpers/Wizard.Paths.ps1')
    (Join-Path -Path $WizardRoot -ChildPath 'Helpers/Wizard.Prompts.ps1')
    (Join-Path -Path $WizardRoot -ChildPath 'Helpers/Wizard.PreReqs.ps1')
    (Join-Path -Path $WizardRoot -ChildPath 'Helpers/Wizard.CustomScript.ps1')
    (Join-Path -Path $WizardRoot -ChildPath 'Helpers/Wizard.FileSources.ps1')
    (Join-Path -Path $WizardRoot -ChildPath 'Helpers/Wizard.Config.ps1')
    (Join-Path -Path $WizardRoot -ChildPath 'Helpers/Wizard.ProjectFiles.ps1')
    (Join-Path -Path $WizardRoot -ChildPath 'Helpers/Wizard.Credentials.ps1')
    (Join-Path -Path $WizardRoot -ChildPath 'Helpers/Wizard.Sources.ps1')
    (Join-Path -Path $WizardRoot -ChildPath 'Helpers/Wizard.Destinations.ps1')
    (Join-Path -Path $WizardRoot -ChildPath 'Helpers/Wizard.Adapter.ps1')
    (Join-Path -Path $WizardRoot -ChildPath 'Helpers/Wizard.Schedule.ps1')
    (Join-Path -Path $WizardRoot -ChildPath 'Helpers/Wizard.ProjectWizard.ps1')
)

foreach ($HelperFile in $HelperFiles) {
    if (-not (Test-Path -Path $HelperFile -PathType Leaf)) {
        throw "Wizard helper file not found: $HelperFile"
    }

    . $HelperFile
}
