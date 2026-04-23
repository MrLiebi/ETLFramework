<#
    Helper functions for bootstrapping New-ETLProject.ps1.
#>

function Get-NewEtlProjectBootstrapContext {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory)][string] $ScriptPath
    )

    $ScriptDirectory = Split-Path -Path $ScriptPath -Parent
    [pscustomobject]@{
        ScriptPath = $ScriptPath
        ScriptDirectory = $ScriptDirectory
        WizardLoggingModulePath = Join-Path -Path $ScriptDirectory -ChildPath 'Wizard\Modules\Wizard.Logging.psm1'
        WizardBootstrapPath = Join-Path -Path $ScriptDirectory -ChildPath 'Wizard\Bootstrap.ps1'
    }
}

function Assert-NewEtlProjectBootstrapAssets {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory)] $Context
    )

    if (-not (Test-Path -Path $Context.WizardLoggingModulePath -PathType Leaf)) {
        throw "Wizard logging module not found: $($Context.WizardLoggingModulePath)"
    }

    if (-not (Test-Path -Path $Context.WizardBootstrapPath -PathType Leaf)) {
        throw "Wizard bootstrap helper not found: $($Context.WizardBootstrapPath)"
    }
}

function Import-NewEtlProjectRuntime {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory)] $Context
    )

    Import-Module -Name $Context.WizardLoggingModulePath -Force -ErrorAction Stop
}

function Start-NewEtlProjectWizard {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory)] $Context,
        [string] $DefaultBaseDirectory = 'C:\ProgramData\SoftwareOne\01_Import',
        [bool]   $LogFileAppend = $true,

        [ValidateSet('4.7','4.7.1','4.7.2','4.8','4.8.1')]
        [string] $RequiredDotNetVersion = '4.7',

        [bool]   $RequireDotNet = $true,
        [bool]   $AllowDotNetInstall = $true,
        [string] $DotNetOfflineInstallerPath = ''
    )

    Invoke-NewEtlProjectWizard -ScriptPath $Context.ScriptPath -ScriptDirectory $Context.ScriptDirectory -DefaultBaseDirectory $DefaultBaseDirectory -LogFileAppend $LogFileAppend -RequiredDotNetVersion $RequiredDotNetVersion -RequireDotNet $RequireDotNet -AllowDotNetInstall $AllowDotNetInstall -DotNetOfflineInstallerPath $DotNetOfflineInstallerPath
}
