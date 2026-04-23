<#
.SYNOPSIS
ETL source adapter for XLSX.

.DESCRIPTION
Extracts data from XLSX workbooks and returns it as a structured
collection of PowerShell objects for further processing in the
ETL pipeline.

This module implements the Invoke-Extract entry point used by
the ETL runtime.

.VERSION
23.0.0

.AUTHOR
ETL Framework

.OUTPUTS
System.Object[]

.NOTES
- Entry point: Invoke-Extract
- Must return a collection of objects
- Used by Run-ETL.ps1 during extract phase
- Uses ExcelDataReader runtime dependency from RUN\Modules\Dependencies\ExcelDataReader

.DEPENDENCIES
- ExcelDataReader.dll
#>

$CommonModulePath = Join-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -ChildPath 'Common\Framework.Common.psm1'
if (-not (Test-Path -Path $CommonModulePath -PathType Leaf)) {
    throw "Common runtime module not found: $CommonModulePath"
}

Import-Module -Name $CommonModulePath -Force -ErrorAction Stop
$Script:ModuleContext = New-EtlModuleContext -ModulePath $MyInvocation.MyCommand.Path -ModuleRoot $PSScriptRoot

function Write-ModuleLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $Message,
        [ValidateSet('INFO','WARN','ERROR','DEBUG')][string] $Level = 'INFO'
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
        if (-not $Config.Path) { throw "Missing source config value: Path" }

        foreach ($NumericSetting in @(
            @{ Name = 'HeaderRowNumber'; Minimum = 1; Default = 1 },
            @{ Name = 'DataStartRowNumber'; Minimum = 1; Default = 2 },
            @{ Name = 'FirstDataColumn'; Minimum = 1; Default = 1 }
        )) {
            if ($Config.ContainsKey($NumericSetting.Name) -and -not [string]::IsNullOrWhiteSpace([string]$Config[$NumericSetting.Name])) {
                $ParsedValue = 0
                if (-not [int]::TryParse([string]$Config[$NumericSetting.Name], [ref]$ParsedValue) -or $ParsedValue -lt $NumericSetting.Minimum) {
                    throw "Invalid source config value: $($NumericSetting.Name) must be an integer >= $($NumericSetting.Minimum)."
                }
            }
        }

        Write-ModuleLog "Source XLSX configuration validated successfully." -Level 'DEBUG'
        return $true
    }
    catch {
        Write-ModuleLog "Source XLSX configuration validation failed: $($_.Exception.Message)" -Level 'ERROR'
        return $false
    }
}

function Convert-ExcelCellValueToText {
    [CmdletBinding()]
    param([Parameter()][AllowNull()] $Value)
    if ($null -eq $Value) { return $null }
    if ($Value -is [datetime]) { return ([datetime]$Value).ToString('yyyy-MM-dd HH:mm:ss', [System.Globalization.CultureInfo]::InvariantCulture) }
    if ($Value -is [bool]) { if ($Value) { return 'TRUE' } else { return 'FALSE' } }
    return [string]$Value
}

function Get-NormalizedHeaderName {
    [CmdletBinding()]
    param(
        [Parameter()][AllowNull()] $Value,
        [Parameter(Mandatory)][int] $ColumnNumber,
        [Parameter(Mandatory)][hashtable] $SeenHeaderNames
    )
    $HeaderName = Convert-ExcelCellValueToText -Value $Value
    if ([string]::IsNullOrWhiteSpace($HeaderName)) { $HeaderName = "Column$ColumnNumber" }
    $HeaderName = $HeaderName.Trim()
    if ($SeenHeaderNames.ContainsKey($HeaderName)) {
        $SeenHeaderNames[$HeaderName]++
        return ("{0}_{1}" -f $HeaderName, $SeenHeaderNames[$HeaderName])
    }
    $SeenHeaderNames[$HeaderName] = 1
    return $HeaderName
}

function Read-WorksheetObjects {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] $Reader,
        [Parameter(Mandatory)][int] $HeaderRowNumber,
        [Parameter(Mandatory)][int] $DataStartRowNumber,
        [Parameter(Mandatory)][int] $FirstDataColumn
    )

    $HeadersByIndex = @{}
    $SeenHeaderNames = @{}

    while ($Reader.Read()) {
        $RowNumber = [int]$Reader.Depth + 1
        $FieldCount = [int]$Reader.FieldCount

        if ($RowNumber -eq $HeaderRowNumber) {
            for ($ColumnIndex = $FirstDataColumn; $ColumnIndex -le $FieldCount; $ColumnIndex++) {
                $HeaderValue = $Reader.GetValue($ColumnIndex - 1)
                $HeadersByIndex[$ColumnIndex] = Get-NormalizedHeaderName -Value $HeaderValue -ColumnNumber $ColumnIndex -SeenHeaderNames $SeenHeaderNames
            }
            continue
        }

        if ($RowNumber -lt $DataStartRowNumber) { continue }
        if ($HeadersByIndex.Count -eq 0) { throw "No usable headers found in row '$HeaderRowNumber'." }

        $RowObject = [ordered]@{}
        foreach ($HeaderKey in ($HeadersByIndex.Keys | Sort-Object)) { $RowObject[$HeadersByIndex[$HeaderKey]] = $null }

        $HasValue = $false
        foreach ($ColumnIndex in ($HeadersByIndex.Keys | Sort-Object)) {
            $CellValue = $null
            if ($ColumnIndex -le $FieldCount) { $CellValue = Convert-ExcelCellValueToText -Value ($Reader.GetValue($ColumnIndex - 1)) }
            if (-not [string]::IsNullOrWhiteSpace([string]$CellValue)) { $HasValue = $true }
            $RowObject[$HeadersByIndex[$ColumnIndex]] = $CellValue
        }

        if ($HasValue) { [pscustomobject]$RowObject }
    }

}


function Resolve-SourceWorkbookFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $ResolvedPath,
        [string] $FilePattern = '*.xls*'
    )

    if (Test-Path -Path $ResolvedPath -PathType Leaf) {
        return (Get-Item -Path $ResolvedPath -ErrorAction Stop).FullName
    }

    if (-not (Test-Path -Path $ResolvedPath -PathType Container)) {
        throw "Configured XLSX path not found: $ResolvedPath"
    }

    $Files = @(
        Get-ChildItem -Path $ResolvedPath -File -Filter $FilePattern -ErrorAction Stop |
        Sort-Object Name
    )

    if ($Files.Count -eq 0) {
        throw "No Excel files found in folder: $ResolvedPath (Pattern: $FilePattern)"
    }

    if ($Files.Count -gt 1) {
        $CandidateNames = ($Files | Select-Object -First 10 -ExpandProperty Name) -join ', '
        throw "File pattern resolution for XLSX requires exactly one matching file in '$ResolvedPath'. Pattern '$FilePattern' matched $($Files.Count) files: $CandidateNames"
    }

    return $Files[0].FullName
}

function Invoke-Extract {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][hashtable] $Config,
        [Parameter()][string[]] $Properties
    )

    try {
        if (-not (Test-ExtractConfiguration -Config $Config)) { throw 'Source XLSX configuration validation failed.' }

        Import-ExcelDataReaderAssemblies -ModuleRoot $PSScriptRoot
        $ResolvedPath       = Resolve-AbsolutePath -Path ([string]$Config.Path)
        $FilePattern        = if ($Config.ContainsKey('FilePattern') -and -not [string]::IsNullOrWhiteSpace([string]$Config.FilePattern)) { [string]$Config.FilePattern } else { '*.xls*' }
        $WorkbookPath       = Resolve-SourceWorkbookFile -ResolvedPath $ResolvedPath -FilePattern $FilePattern
        $env:ETL_LAST_SOURCE_FILE = $WorkbookPath
        $env:ETL_LAST_SOURCE_TYPE = 'XLSX'

        $WorksheetName      = if ($Config.ContainsKey('WorksheetName') -and -not [string]::IsNullOrWhiteSpace([string]$Config.WorksheetName)) { [string]$Config.WorksheetName } else { '' }
        $HeaderRowNumber    = if ($Config.ContainsKey('HeaderRowNumber')) { [int]$Config.HeaderRowNumber } else { 1 }
        $DataStartRowNumber = if ($Config.ContainsKey('DataStartRowNumber')) { [int]$Config.DataStartRowNumber } else { 2 }
        $FirstDataColumn    = if ($Config.ContainsKey('FirstDataColumn')) { [int]$Config.FirstDataColumn } else { 1 }
        $SelectedProperties = Get-ValidatedPropertySelection -Properties $Properties
        Write-ModuleLog ("Requested property selection: {0}" -f ($SelectedProperties -join ', ')) -Level 'INFO'

        Write-ModuleLog ("Selected XLSX source file: {0}" -f $WorkbookPath) -Level 'INFO'
        Write-ModuleLog 'Registered selected XLSX source file for post-import actions.' -Level 'DEBUG'
        if (-not [string]::IsNullOrWhiteSpace($WorksheetName)) {
            Write-ModuleLog ("WorksheetName: {0}" -f $WorksheetName) -Level 'INFO'
        }
        else {
            Write-ModuleLog 'WorksheetName not specified. First worksheet will be used.' -Level 'INFO'
        }

        $Stream = [System.IO.File]::Open($WorkbookPath, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
        try {
            $Reader = [ExcelDataReader.ExcelReaderFactory]::CreateReader($Stream)
            try {
                $WorksheetMatched = $false
                $RowsEmitted = 0
                $PreviewLogged = $false
                do {
                    $CurrentWorksheetName = [string]$Reader.Name
                    if ([string]::IsNullOrWhiteSpace($WorksheetName) -or $CurrentWorksheetName -eq $WorksheetName) {
                        $WorksheetMatched = $true
                        foreach ($Row in (Read-WorksheetObjects -Reader $Reader -HeaderRowNumber $HeaderRowNumber -DataStartRowNumber $DataStartRowNumber -FirstDataColumn $FirstDataColumn)) {
                            $OutputRow = $Row
                            if ($SelectedProperties.Count -gt 0 -and -not ($SelectedProperties.Count -eq 1 -and $SelectedProperties[0] -eq '*')) {
                                $Projected = [ordered]@{}
                                foreach ($PropertyName in $SelectedProperties) {
                                    $Property = $Row.PSObject.Properties[$PropertyName]
                                    if ($null -ne $Property) { $Projected[$PropertyName] = $Property.Value } else { $Projected[$PropertyName] = $null }
                                }
                                $OutputRow = [pscustomobject]$Projected
                            }

                            if (-not $PreviewLogged) {
                                Write-ModuleLog ("First XLSX row preview: {0}" -f (Get-EtlObjectPreview -InputObject $OutputRow)) -Level 'INFO'
                                $PreviewLogged = $true
                            }

                            $RowsEmitted++
                            $OutputRow
                        }
                        break
                    }
                } while ($Reader.NextResult())

                if (-not $WorksheetMatched) { throw "Worksheet '$WorksheetName' not found." }
                if ($RowsEmitted -eq 0) {
                    Write-ModuleLog 'XLSX extraction returned zero rows. Downstream destination will receive no rows.' -Level 'WARN'
                }
                Write-ModuleLog ("XLSX extraction completed successfully. Total objects processed: {0}" -f $RowsEmitted) -Level 'INFO'
            }
            finally {
                if ($Reader) { $Reader.Dispose() }
            }
        }
        finally {
            if ($Stream) { $Stream.Dispose() }
        }
    }
    catch {
        Write-EtlExceptionDetails -Context $Script:ModuleContext -ErrorRecord $_ -Prefix 'XLSX extract failed:'
        throw
    }
}

Export-ModuleMember -Function Invoke-Extract
