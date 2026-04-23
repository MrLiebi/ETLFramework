<#
    Logging facade for wizard helper scripts.
#>

function Write-Log {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)][string] $Message,
        [ValidateSet('DEBUG','INFO','WARN','ERROR')][string] $Level = 'INFO'
    )

    Write-WizardLog -Context $Script:LogContext -Message $Message -Level $Level
}
