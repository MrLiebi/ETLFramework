<#
    Helper functions for New-ETLProject.ps1.
    File: Wizard.Config.ps1
#>

function ConvertTo-QuotedPsd1Value {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param([AllowNull()][object] $Value)

    if ($null -eq $Value) { return "''" }
    if ($Value -is [bool]) { return $(if ($Value) { '$true' } else { '$false' }) }
    if ($Value -is [System.Management.Automation.SwitchParameter]) {
        return $(if ([bool]$Value) { '$true' } else { '$false' })
    }

    $StringValue = [string]$Value
    $EscapedValue = $StringValue -replace "'", "''"
    return "'$EscapedValue'"
}

function ConvertTo-XmlEscapedValue {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param([AllowNull()][string] $Value)

    if ($null -eq $Value) { return '' }
    return [System.Security.SecurityElement]::Escape($Value)
}

function Convert-HashtableToPsd1Block {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory)][hashtable] $Hashtable,
        [int] $IndentLevel = 0
    )

    $Indent = (' ' * $IndentLevel)
    $Lines = New-Object System.Collections.Generic.List[string]
    $Lines.Add("$Indent@{")

    foreach ($Key in $Hashtable.Keys) {
        $Value = $Hashtable[$Key]
        $ChildIndent = (' ' * ($IndentLevel + 4))

        if ($Value -is [hashtable] -or $Value -is [System.Collections.Specialized.OrderedDictionary]) {
            $Lines.Add("$ChildIndent$Key =")
            $Lines.Add((Convert-HashtableToPsd1Block -Hashtable ([hashtable]$Value) -IndentLevel ($IndentLevel + 4)))
        }
        elseif ($Value -is [array]) {
            $Lines.Add("$ChildIndent$Key = @(")
            foreach ($Item in $Value) {
                if ($Item -is [hashtable] -or $Item -is [System.Collections.Specialized.OrderedDictionary]) {
                    $Lines.Add((Convert-HashtableToPsd1Block -Hashtable ([hashtable]$Item) -IndentLevel ($IndentLevel + 8)))
                }
                else {
                    $RenderedItem = "{0}{1}" -f (' ' * ($IndentLevel + 8)), (ConvertTo-QuotedPsd1Value -Value $Item)
                    $Lines.Add($RenderedItem)
                }
            }
            $Lines.Add("{0})" -f (' ' * ($IndentLevel + 4)))
        }
        else {
            $Lines.Add("$ChildIndent$Key = $(ConvertTo-QuotedPsd1Value -Value $Value)")
        }
    }

    $Lines.Add("$Indent}")
    return ($Lines -join "`r`n")
}

function New-ConfigContent {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory)][array] $Pipelines,
        [Parameter(Mandatory)][string] $LogLevel,
        [Parameter(Mandatory)][string] $RetentionDays,
        [Parameter()][hashtable] $Adapter = $null
    )

    $PipelineBlocks = New-Object System.Collections.Generic.List[string]

    foreach ($Pipeline in $Pipelines) {
        $PropertyLines = (($Pipeline.Properties | ForEach-Object {
            "                {0}" -f (ConvertTo-QuotedPsd1Value -Value $_)
        }) -join "`r`n")

        $PipelineBlock = @"
        @{
            StepId = $(ConvertTo-QuotedPsd1Value -Value $Pipeline.StepId)
            Name = $(ConvertTo-QuotedPsd1Value -Value $Pipeline.Name)
            StepEnabled = $(if ($null -ne $Pipeline.StepEnabled) { if (([string]$Pipeline.StepEnabled).Trim() -match '^(?i:true|1|yes|y)$') { '$true' } else { '$false' } } else { '$true' })
            Source =
$(Convert-HashtableToPsd1Block -Hashtable $Pipeline.Source -IndentLevel 12)
            Destination =
$(Convert-HashtableToPsd1Block -Hashtable $Pipeline.Destination -IndentLevel 12)
            Properties = @(
$PropertyLines
            )
        }
"@
        [void]$PipelineBlocks.Add($PipelineBlock)
    }

    $AdapterBlock = ''
    if ($null -ne $Adapter -and $Adapter.Count -gt 0) {
        $AdapterBlock = @"

    Adapter =
$(Convert-HashtableToPsd1Block -Hashtable $Adapter -IndentLevel 4)
"@
    }

    return @"
@{
    Pipelines = @(
$($PipelineBlocks -join ",`r`n")
    )
$AdapterBlock

    Logging = @{
        Level = '$(($LogLevel -replace "'", "''"))'
        RetentionDays = $(if ([string]::IsNullOrWhiteSpace($RetentionDays)) { 30 } elseif ($RetentionDays -match '^\d+$') { [int]$RetentionDays } else { ConvertTo-QuotedPsd1Value -Value $RetentionDays })
        ModuleLogs = $(ConvertTo-QuotedPsd1Value -Value $true)
    }
}
"@
}

