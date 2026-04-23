<#
    Helper functions for New-ETLProject.ps1.
    File: Wizard.CustomScript.ps1
#>

<#
    .SYNOPSIS
    Helper functions for Custom Script wizard handling in New-ETLProject.

    .DESCRIPTION
    Reads a PowerShell script statically via AST, detects declared parameters,
    identifies mandatory parameters, and interactively captures only the values
    that should be written into the ETL project configuration.
#>

function Write-Ui {
    [CmdletBinding()]
    param(
        [AllowEmptyString()][string] $Message,
        [string] $ForegroundColor
    )

    Write-Information -MessageData $Message -InformationAction Continue
}

function Get-CustomScriptDisplayDefaultValue {
    [CmdletBinding()]
    param(
        [Parameter()][System.Management.Automation.Language.ExpressionAst] $DefaultValueAst
    )

    if ($null -eq $DefaultValueAst) {
        return $null
    }

    try {
        $SafeValue = $DefaultValueAst.SafeGetValue()
        if ($null -eq $SafeValue) {
            return $null
        }

        if ($SafeValue -is [array]) {
            return (($SafeValue | ForEach-Object { [string]$_ }) -join ',')
        }

        if ($SafeValue -is [switch]) {
            return $SafeValue.IsPresent.ToString()
        }

        return [string]$SafeValue
    }
    catch {
        return [string]$DefaultValueAst.Extent.Text
    }
}

function Get-CustomScriptParameterMetadata {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $ScriptPath
    )

    if (-not (Test-Path -Path $ScriptPath -PathType Leaf)) {
        throw "Custom script file not found: $ScriptPath"
    }

    $Tokens = $null
    $ParseErrors = $null
    $Ast = [System.Management.Automation.Language.Parser]::ParseFile($ScriptPath, [ref]$Tokens, [ref]$ParseErrors)

    if ($ParseErrors -and $ParseErrors.Count -gt 0) {
        $Messages = @($ParseErrors | ForEach-Object { $_.Message }) -join '; '
        throw "Custom script parameter parsing failed: $Messages"
    }

    if ($null -eq $Ast.ParamBlock -or $null -eq $Ast.ParamBlock.Parameters) {
        return @()
    }

    $SupportedTypeNames = @('String','Int32','Int64','Boolean','String[]','SwitchParameter','SecureString')
    $Result = New-Object System.Collections.Generic.List[object]

    foreach ($ParameterAst in $Ast.ParamBlock.Parameters) {
        $ParameterName = [string]$ParameterAst.Name.VariablePath.UserPath
        $TypeName = if ($null -ne $ParameterAst.StaticType) {
            [string]$ParameterAst.StaticType.Name
        }
        else {
            'Object'
        }

        $IsMandatory = $false
        foreach ($AttributeAst in @($ParameterAst.Attributes)) {
            if ($AttributeAst.TypeName.FullName -eq 'Parameter') {
                foreach ($NamedArgument in @($AttributeAst.NamedArguments)) {
                    if ($NamedArgument.ArgumentName -eq 'Mandatory') {
                        try {
                            if ([bool]$NamedArgument.Argument.SafeGetValue()) {
                                $IsMandatory = $true
                            }
                        }
                        catch {
                            if ([string]$NamedArgument.Argument.Extent.Text -match '^(?i)\$true|true|1$') {
                                $IsMandatory = $true
                            }
                        }
                    }
                }
            }
        }

        $HasDefault = ($null -ne $ParameterAst.DefaultValue)
        $DefaultValue = Get-CustomScriptDisplayDefaultValue -DefaultValueAst $ParameterAst.DefaultValue
        $IsSupported = $SupportedTypeNames -contains $TypeName
        $IsSwitch = ($TypeName -eq 'SwitchParameter')

        [void]$Result.Add([PSCustomObject]@{
            Name         = $ParameterName
            TypeName     = $TypeName
            IsMandatory  = $IsMandatory
            HasDefault   = $HasDefault
            DefaultValue = $DefaultValue
            IsSupported  = $IsSupported
            IsSwitch     = $IsSwitch
        })
    }

    return @($Result.ToArray())
}

function Read-CustomScriptParameterValue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][pscustomobject] $ParameterMetadata,
        [switch] $Optional
    )

    $PromptLabel = if ($Optional) { 'optional' } else { 'mandatory' }

    if ($ParameterMetadata.IsSwitch -or $ParameterMetadata.TypeName -eq 'Boolean') {
        $DefaultBooleanValue = $false
        if ($ParameterMetadata.HasDefault -and -not [string]::IsNullOrWhiteSpace([string]$ParameterMetadata.DefaultValue)) {
            $DefaultBooleanValue = ([string]$ParameterMetadata.DefaultValue).Trim() -match '^(?i:true|1|yes|y|present)$'
        }

        $ParameterKind = if ($ParameterMetadata.IsSwitch) { 'switch' } else { 'boolean' }
        $BooleanValue = Read-BooleanChoice -Prompt ("  > Set {0} {1} parameter [{2}]" -f $PromptLabel, $ParameterKind, $ParameterMetadata.Name) -Default $DefaultBooleanValue
        return $BooleanValue
    }

    $Prompt = "  > Enter value for {0} parameter [{1}] ({2})" -f $PromptLabel, $ParameterMetadata.Name, $ParameterMetadata.TypeName
    if ($ParameterMetadata.HasDefault -and -not [string]::IsNullOrWhiteSpace([string]$ParameterMetadata.DefaultValue)) {
        return (Read-InputValue -Prompt $Prompt -Default ([string]$ParameterMetadata.DefaultValue) -AllowEmpty:$Optional)
    }

    return (Read-InputValue -Prompt $Prompt -AllowEmpty:$Optional)
}

function Read-CustomScriptParameterConfiguration {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $ScriptPath,
        [Parameter(Mandatory)][string] $StepId
    )

    $Parameters = [ordered]@{}
    $Metadata = @(Get-CustomScriptParameterMetadata -ScriptPath $ScriptPath)

    if ($Metadata.Count -eq 0) {
        Write-Ui ''
        Write-Ui ("No script parameters were detected for custom script step [{0}]." -f $StepId) -ForegroundColor DarkGray
        return [hashtable]$Parameters
    }

    Write-Ui ''
    Write-Ui ("--- DETECTED CUSTOM SCRIPT PARAMETERS FOR STEP [{0}] ---" -f $StepId) -ForegroundColor Cyan
    foreach ($Item in $Metadata) {
        $MandatoryLabel = if ($Item.IsMandatory) { 'Yes' } else { 'No' }
        $SupportedLabel = if ($Item.IsSupported) { 'Yes' } else { 'No' }
        $DefaultLabel = if ($Item.HasDefault) { [string]$Item.DefaultValue } else { '<none>' }
        Write-Ui ("  - {0} | Type: {1} | Mandatory: {2} | Default: {3} | Supported: {4}" -f $Item.Name, $Item.TypeName, $MandatoryLabel, $DefaultLabel, $SupportedLabel) -ForegroundColor Gray
    }

    $MandatoryParameters = @($Metadata | Where-Object { $_.IsMandatory })
    $OptionalParameters  = @($Metadata | Where-Object { -not $_.IsMandatory })

    foreach ($Parameter in $MandatoryParameters) {
        if (-not $Parameter.IsSupported) {
            throw "Mandatory custom script parameter '$($Parameter.Name)' uses unsupported type '$($Parameter.TypeName)'. Supported types: String, Int32, Int64, Boolean, String[], SwitchParameter, SecureString."
        }

        $ParameterValue = Read-CustomScriptParameterValue -ParameterMetadata $Parameter
        $Parameters[[string]$Parameter.Name] = $ParameterValue
    }

    if ($OptionalParameters.Count -gt 0) {
        $UseOptionalParameters = Read-BooleanChoice -Prompt '  > Configure optional custom script parameters as well?' -Default $false
        if ($UseOptionalParameters) {
            foreach ($Parameter in $OptionalParameters) {
                if (-not $Parameter.IsSupported) {
                    Write-Warning ("Skipping unsupported optional custom script parameter '{0}' of type '{1}'." -f $Parameter.Name, $Parameter.TypeName)
                    continue
                }

                $UseThisParameter = Read-BooleanChoice -Prompt ("  > Set optional parameter [{0}]?" -f $Parameter.Name) -Default $false
                if (-not $UseThisParameter) {
                    continue
                }

                $ParameterValue = Read-CustomScriptParameterValue -ParameterMetadata $Parameter -Optional
                if ($null -eq $ParameterValue -or [string]::IsNullOrWhiteSpace([string]$ParameterValue)) {
                    continue
                }

                $Parameters[[string]$Parameter.Name] = $ParameterValue
            }
        }
    }

    return [hashtable]$Parameters
}

function Show-CustomScriptContractAndConfirm {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $StepId
    )

    Write-Ui ""
    Write-Ui "--- CUSTOM SCRIPT CONTRACT FOR STEP [$StepId] ---" -ForegroundColor Cyan
    Write-Ui "The selected source script must comply with the following contract:" -ForegroundColor Gray
    Write-Ui "  1. The script must return business data as object output (PSCustomObject or object array)." -ForegroundColor Gray
    Write-Ui "  2. The script must NOT write its data output to files." -ForegroundColor Gray
    Write-Ui "  3. Console output for diagnostics is allowed, but Write-Output text must not be mixed with data objects." -ForegroundColor Gray
    Write-Ui "  4. The script is executed directly by the framework and its returned objects are written to the configured destination." -ForegroundColor Gray
    Write-Ui "  5. Parameter values configured in the wizard are passed to the script as named parameters." -ForegroundColor Gray
    return (Read-BooleanChoice -Prompt 'Confirm Custom Script contract and continue?' -Default $true)
}

function Invoke-CustomScriptParameterWizard {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $ScriptPath,
        [Parameter(Mandatory)][string] $StepId
    )

    return (Read-CustomScriptParameterConfiguration -ScriptPath $ScriptPath -StepId $StepId)
}

