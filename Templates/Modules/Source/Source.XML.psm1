<#
.SYNOPSIS
ETL source adapter for XML files.

.DESCRIPTION
Extracts data from XML files and returns flattened PowerShell objects for
further ETL processing. Supports direct file selection or folder + pattern
resolution and registers the selected source file for post-import actions.

.VERSION
23.1.0
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
        if (-not $Config.Path) { throw 'Missing source config value: Path' }
        Write-ModuleLog 'Source XML configuration validated successfully.' -Level 'DEBUG'
        return $true
    }
    catch {
        Write-ModuleLog "Source XML configuration validation failed: $($_.Exception.Message)" -Level 'ERROR'
        return $false
    }
}

function Resolve-SourceXmlFile {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string] $ResolvedPath, [string] $FilePattern = '*.xml')

    if (Test-Path -Path $ResolvedPath -PathType Leaf) { return (Get-Item -Path $ResolvedPath -ErrorAction Stop).FullName }
    if (-not (Test-Path -Path $ResolvedPath -PathType Container)) { throw "Configured XML path not found: $ResolvedPath" }

    $Files = @(Get-ChildItem -Path $ResolvedPath -File -Filter $FilePattern -ErrorAction Stop | Sort-Object Name)
    if ($Files.Count -eq 0) { throw "No XML files found in folder: $ResolvedPath (Pattern: $FilePattern)" }
    if ($Files.Count -gt 1) {
        $CandidateNames = ($Files | Select-Object -First 10 -ExpandProperty Name) -join ', '
        throw "File pattern resolution for XML requires exactly one matching file in '$ResolvedPath'. Pattern '$FilePattern' matched $($Files.Count) files: $CandidateNames"
    }

    return $Files[0].FullName
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

function Add-FlattenedXmlValue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][System.Collections.IDictionary] $Target,
        [Parameter(Mandatory)][string] $Key,
        [AllowNull()] $Value
    )

    if ([string]::IsNullOrWhiteSpace($Key)) { return }
    if ($null -eq $Value) { return }

    $Text = [string]$Value
    if ([string]::IsNullOrWhiteSpace($Text)) { return }

    if ($Target.Contains($Key) -and -not [string]::IsNullOrWhiteSpace([string]$Target[$Key])) {
        $Target[$Key] = '{0}; {1}' -f $Target[$Key], $Text
    }
    else {
        $Target[$Key] = $Text
    }
}

function Get-XmlNodeLocalName {
    [CmdletBinding()]
    param([Parameter(Mandatory)][System.Xml.XmlNode] $Node)

    if (-not [string]::IsNullOrWhiteSpace([string]$Node.LocalName) -and $Node.LocalName -ne '#text' -and $Node.LocalName -ne '#cdata-section') {
        return [string]$Node.LocalName
    }

    return [string]$Node.Name
}

function Test-XmlNodeIsSimpleLeaf {
    [CmdletBinding()]
    param([Parameter(Mandatory)][System.Xml.XmlNode] $Node)

    $ElementChildren = @($Node.ChildNodes | Where-Object { $_.NodeType -eq [System.Xml.XmlNodeType]::Element })
    return ($ElementChildren.Count -eq 0)
}

function Flatten-XmlNode {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][System.Xml.XmlNode] $Node,
        [Parameter(Mandatory)][System.Collections.IDictionary] $Target,
        [string] $Prefix = ''
    )

    foreach ($Attribute in @($Node.Attributes)) {
        $AttributeName = if ([string]::IsNullOrWhiteSpace($Prefix)) { "@$($Attribute.LocalName)" } else { "$Prefix.@$($Attribute.LocalName)" }
        Add-FlattenedXmlValue -Target $Target -Key $AttributeName -Value $Attribute.Value
    }

    $ElementChildren = @($Node.ChildNodes | Where-Object { $_.NodeType -eq [System.Xml.XmlNodeType]::Element })
    if ($ElementChildren.Count -eq 0) {
        $InnerText = [string]$Node.InnerText
        if (-not [string]::IsNullOrWhiteSpace($InnerText)) {
            $LeafKey = if ([string]::IsNullOrWhiteSpace($Prefix)) { 'Value' } else { $Prefix }
            Add-FlattenedXmlValue -Target $Target -Key $LeafKey -Value $InnerText.Trim()
        }
        return
    }

    $GroupedChildren = $ElementChildren | Group-Object { Get-XmlNodeLocalName -Node $_ }
    foreach ($Group in $GroupedChildren) {
        $ChildName = [string]$Group.Name
        $ChildNodes = @($Group.Group)
        $BaseKey = if ([string]::IsNullOrWhiteSpace($Prefix)) { $ChildName } else { "$Prefix.$ChildName" }

        if ($ChildNodes.Count -gt 1 -and (@($ChildNodes | Where-Object { -not (Test-XmlNodeIsSimpleLeaf -Node $_) }).Count -eq 0)) {
            $JoinedText = @(
                $ChildNodes |
                    ForEach-Object { ([string]$_.InnerText).Trim() } |
                    Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
            ) -join '; '

            Add-FlattenedXmlValue -Target $Target -Key $BaseKey -Value $JoinedText

            foreach ($ChildNode in $ChildNodes) {
                foreach ($Attribute in @($ChildNode.Attributes)) {
                    $AttributeKey = "$BaseKey.@$($Attribute.LocalName)"
                    Add-FlattenedXmlValue -Target $Target -Key $AttributeKey -Value $Attribute.Value
                }
            }

            continue
        }

        if ($ChildNodes.Count -eq 1) {
            Flatten-XmlNode -Node $ChildNodes[0] -Target $Target -Prefix $BaseKey
            continue
        }

        for ($Index = 0; $Index -lt $ChildNodes.Count; $Index++) {
            Flatten-XmlNode -Node $ChildNodes[$Index] -Target $Target -Prefix ("{0}[{1}]" -f $BaseKey, $Index)
        }
    }
}

function Convert-XmlNodeToObject {
    [CmdletBinding()]
    param([Parameter(Mandatory)][System.Xml.XmlNode] $Node)

    $Flattened = [ordered]@{}
    Flatten-XmlNode -Node $Node -Target $Flattened
    return [PSCustomObject]$Flattened
}

function Invoke-Extract {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][hashtable] $Config,
        [Parameter(Mandatory = $true)][string[]] $Properties
    )

    if (-not (Test-ExtractConfiguration -Config $Config)) {
        throw 'Source XML configuration is invalid.'
    }

    try {
        $ResolvedPath       = Resolve-AbsolutePath -Path ([string]$Config.Path)
        $FilePattern        = if ($Config.FilePattern) { [string]$Config.FilePattern } else { '*.xml' }
        $RecordXPath        = if ($Config.RecordXPath) { [string]$Config.RecordXPath } else { '/*/*' }
        $SelectedProperties = Get-ValidatedPropertySelection -Properties $Properties

        $XmlFile = Resolve-SourceXmlFile -ResolvedPath $ResolvedPath -FilePattern $FilePattern
        $env:ETL_LAST_SOURCE_FILE = $XmlFile
        $env:ETL_LAST_SOURCE_TYPE = 'XML'
        Write-ModuleLog "Selected XML source file: $XmlFile" -Level 'INFO'
        Write-ModuleLog 'Registered selected XML source file for post-import actions.' -Level 'DEBUG'

        $XmlDocument = New-Object System.Xml.XmlDocument
        $XmlDocument.PreserveWhitespace = $false
        $XmlDocument.Load($XmlFile)

        $Nodes = @($XmlDocument.SelectNodes($RecordXPath))
        if ($Nodes.Count -eq 0) {
            throw "No XML records matched XPath: $RecordXPath"
        }

        Write-ModuleLog ("XML records matched via XPath [{0}]: {1}" -f $RecordXPath, $Nodes.Count) -Level 'INFO'
        Write-ModuleLog ("Requested property selection: {0}" -f ($SelectedProperties -join ', ')) -Level 'INFO'

        $EmittedRows = 0
        $PreviewLogged = $false

        foreach ($Node in $Nodes) {
            $Row = Convert-XmlNodeToObject -Node $Node
            $FilteredRow = ConvertTo-FilteredRow -Row $Row -SelectedProperties $SelectedProperties

            if (-not $PreviewLogged) {
                Write-ModuleLog ("First XML row preview: {0}" -f (Get-EtlObjectPreview -InputObject $FilteredRow)) -Level 'INFO'
                $PreviewLogged = $true
            }

            $EmittedRows++
            $FilteredRow
        }

        if ($EmittedRows -eq 0) {
            Write-ModuleLog 'XML extract emitted zero rows. Downstream destination will receive no rows.' -Level 'WARN'
        }
        else {
            Write-ModuleLog ("XML extract completed successfully. Rows emitted: {0}" -f $EmittedRows) -Level 'INFO'
        }
    }
    catch {
        Write-EtlExceptionDetails -Context $Script:ModuleContext -ErrorRecord $_ -Prefix 'XML extract failed:'
        throw
    }
}

Export-ModuleMember -Function Invoke-Extract
