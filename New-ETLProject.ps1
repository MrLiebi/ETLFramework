<# 
    .SYNOPSIS
    Creates a new ETL project structure with multi-step pipeline support.

    .DESCRIPTION
    Thin entry-point wrapper that validates the wizard bootstrap assets, imports the wizard runtime,
    and starts the refactored project wizard orchestration.

    .AUTHOR
    Alexander Liebold

    .VERSION
22.0.0

    .NOTES
    User-visible text and comments follow American English spelling.
#>

[CmdletBinding()]
param(
    [string] $DefaultBaseDirectory = 'C:\ProgramData\SoftwareOne\01_Import',
    [bool]   $LogFileAppend = $true,

    [ValidateSet('4.7','4.7.1','4.7.2','4.8','4.8.1')]
    [string] $RequiredDotNetVersion = '4.7',

    [bool]   $RequireDotNet = $true,
    [bool]   $AllowDotNetInstall = $true,
    [string] $DotNetOfflineInstallerPath = ''
)

$ErrorActionPreference = 'Stop'
$ScriptPath = $MyInvocation.MyCommand.Path
$ScriptDirectory = Split-Path -Path $ScriptPath -Parent
$EntryPointHelperPath = Join-Path -Path $ScriptDirectory -ChildPath 'Wizard\Helpers\Wizard.EntryPoint.ps1'

if (-not (Test-Path -Path $EntryPointHelperPath -PathType Leaf)) {
    throw "Wizard entry-point helper not found: $EntryPointHelperPath"
}

. $EntryPointHelperPath

$BootstrapContext = Get-NewEtlProjectBootstrapContext -ScriptPath $ScriptPath
Assert-NewEtlProjectBootstrapAssets -Context $BootstrapContext
Import-NewEtlProjectRuntime -Context $BootstrapContext
. $BootstrapContext.WizardBootstrapPath

$ExitCode = Start-NewEtlProjectWizard -Context $BootstrapContext -DefaultBaseDirectory $DefaultBaseDirectory -LogFileAppend $LogFileAppend -RequiredDotNetVersion $RequiredDotNetVersion -RequireDotNet $RequireDotNet -AllowDotNetInstall $AllowDotNetInstall -DotNetOfflineInstallerPath $DotNetOfflineInstallerPath

exit $ExitCode
