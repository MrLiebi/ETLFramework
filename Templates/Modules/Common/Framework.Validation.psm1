<#
.SYNOPSIS
Shared validation and normalization helpers for the ETL framework.

.VERSION
22.0.0
#>

function Get-ValidatedPropertySelection {
    [CmdletBinding()]
    param(
        [Parameter()][AllowEmptyCollection()][string[]] $Properties
    )

    $Validated = @(
        $Properties |
            Where-Object { $null -ne $_ } |
            ForEach-Object { [string]$_ } |
            ForEach-Object { $_.Trim() } |
            Where-Object { $_ -ne '' }
    )

    if (-not $Validated -or $Validated.Count -eq 0) {
        return @('*')
    }

    return $Validated
}

function Get-EtlAuthenticationMode {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][hashtable] $Config,
        [Parameter()][string] $Default = 'Integrated'
    )

    if ([string]::IsNullOrWhiteSpace([string]$Config.AuthenticationMode)) {
        return $Default
    }

    return [string]$Config.AuthenticationMode
}

Export-ModuleMember -Function Get-ValidatedPropertySelection, Get-EtlAuthenticationMode
