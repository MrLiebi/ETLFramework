<#
    Logging facade for wizard helper scripts.
#>

function Write-WizardFacadeLog {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)][string] $Message,
        [ValidateSet('DEBUG','INFO','WARN','ERROR')][string] $Level = 'INFO'
    )

    Write-WizardLog -Context $Script:LogContext -Message $Message -Level $Level
}

Set-Alias -Name Write-Log -Value Write-WizardFacadeLog -Scope Script
