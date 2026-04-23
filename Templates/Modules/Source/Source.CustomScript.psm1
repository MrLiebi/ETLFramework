<#
.SYNOPSIS
ETL source adapter for project-provided custom PowerShell scripts.

.DESCRIPTION
Executes a project-local custom script and validates that the script
returns structured object data for further ETL processing.

.VERSION
23.0.0
#>

$CommonModulePath = Join-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -ChildPath 'Common\Framework.Common.psm1'
if (-not (Test-Path -Path $CommonModulePath -PathType Leaf)) {
    throw "Common runtime module manifest not found: $CommonModulePath"
}

Import-Module -Name $CommonModulePath -Force -ErrorAction Stop
$Script:ModuleContext = New-EtlModuleContext -ModulePath $MyInvocation.MyCommand.Path -ModuleRoot $PSScriptRoot

function Write-ModuleLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $Message,
        [ValidateSet('INFO', 'WARN', 'ERROR', 'DEBUG')][string] $Level = 'INFO'
    )
    Write-EtlModuleLog -Context $Script:ModuleContext -Message $Message -Level $Level
}

function Resolve-AbsolutePath {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string] $Path)
    Resolve-EtlProjectPath -Path $Path -ModuleRoot $PSScriptRoot
}

function Test-ExtractConfiguration {
    [CmdletBinding()]
    param([Parameter(Mandatory)][hashtable] $Config)

    try {
        if (-not $Config.ContainsKey('ScriptPath') -or [string]::IsNullOrWhiteSpace([string]$Config.ScriptPath)) {
            throw 'Missing source config value: ScriptPath'
        }

        if ($Config.ContainsKey('Parameters') -and $null -ne $Config.Parameters -and $Config.Parameters -isnot [hashtable]) {
            throw 'Source CustomScript config value Parameters must be a hashtable when specified.'
        }

        Write-ModuleLog 'Source CustomScript configuration validated successfully.' -Level 'DEBUG'
        return $true
    }
    catch {
        Write-ModuleLog "Source CustomScript configuration validation failed: $($_.Exception.Message)" -Level 'ERROR'
        return $false
    }
}

function ConvertTo-FilteredRow {
    [CmdletBinding()]
    param([Parameter(Mandatory)][psobject] $Row, [Parameter(Mandatory)][string[]] $SelectedProperties)

    if ($SelectedProperties -contains '*') {
        $Result = [ordered]@{}
        foreach ($Property in $Row.PSObject.Properties) { $Result[$Property.Name] = $Property.Value }
        return [PSCustomObject]$Result
    }

    $Filtered = [ordered]@{}
    foreach ($Property in $SelectedProperties) {
        $Filtered[$Property] = if ($Row.PSObject.Properties.Name -contains $Property) { $Row.$Property } else { $null }
    }
    return [PSCustomObject]$Filtered
}

function ConvertTo-ValidCustomScriptObject {
    [CmdletBinding()]
    param([Parameter(Mandatory)] $InputObject)

    if ($null -eq $InputObject) {
        return $null
    }

    if ($InputObject -is [hashtable] -or $InputObject -is [System.Collections.Specialized.OrderedDictionary]) {
        return [PSCustomObject]$InputObject
    }

    if ($InputObject -is [string]) {
        throw 'Custom script returned a string via pipeline output. Use Write-Host/Write-Verbose for diagnostics and return PSCustomObject data only.'
    }

    if ($InputObject -is [ValueType]) {
        throw ("Custom script returned a scalar value type via pipeline output: {0}" -f $InputObject.GetType().FullName)
    }

    $Properties = @($InputObject.PSObject.Properties)
    if ($Properties.Count -eq 0) {
        throw ("Custom script returned an unsupported output type without properties: {0}" -f $InputObject.GetType().FullName)
    }

    $Result = [ordered]@{}
    foreach ($Property in $Properties) {
        $Result[$Property.Name] = $Property.Value
    }
    return [PSCustomObject]$Result
}

function Invoke-Extract {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][hashtable] $Config,
        [Parameter(Mandatory = $true)][string[]] $Properties
    )

    if (-not (Test-ExtractConfiguration -Config $Config)) {
        throw 'Source CustomScript configuration is invalid.'
    }

    try {
        $ResolvedScriptPath = Resolve-AbsolutePath -Path ([string]$Config.ScriptPath)
        if (-not (Test-Path -Path $ResolvedScriptPath -PathType Leaf)) {
            throw "Configured custom source script not found: $ResolvedScriptPath"
        }

        $SelectedProperties = Get-ValidatedPropertySelection -Properties $Properties
        $ScriptParameters = if ($Config.ContainsKey('Parameters') -and $null -ne $Config.Parameters) { [hashtable]$Config.Parameters } else { @{} }

        Write-ModuleLog "Executing CustomScript source: $ResolvedScriptPath" -Level 'INFO'
        Write-ModuleLog ("CustomScript parameter count: {0}" -f $ScriptParameters.Count) -Level 'INFO'
        Write-ModuleLog ("Requested property selection: {0}" -f ($SelectedProperties -join ', ')) -Level 'INFO'

        $EmittedRows = 0
        $PreviewLogged = $false

        & $ResolvedScriptPath @ScriptParameters | ForEach-Object {
            $Item = $_
            $ObjectRow = ConvertTo-ValidCustomScriptObject -InputObject $Item
            if ($null -eq $ObjectRow) { continue }

            $FilteredRow = ConvertTo-FilteredRow -Row $ObjectRow -SelectedProperties $SelectedProperties
            if (-not $PreviewLogged) {
                Write-ModuleLog ("First CustomScript row preview: {0}" -f (Get-EtlObjectPreview -InputObject $FilteredRow)) -Level 'INFO'
                $PreviewLogged = $true
            }

            $EmittedRows++
            $FilteredRow
        }

        Write-ModuleLog ("CustomScript raw result count: {0}" -f $EmittedRows) -Level 'INFO'

        if ($EmittedRows -eq 0) {
            Write-ModuleLog 'CustomScript extract emitted zero rows. Downstream destination will receive no rows.' -Level 'WARN'
        }
        else {
            Write-ModuleLog ("CustomScript extract completed successfully. Rows emitted: {0}" -f $EmittedRows) -Level 'INFO'
        }
    }
    catch {
        Write-EtlExceptionDetails -Context $Script:ModuleContext -ErrorRecord $_ -Prefix 'CustomScript extract failed:'
        throw
    }
}

Export-ModuleMember -Function Invoke-Extract
