<#
.SYNOPSIS
ETL destination adapter for CSV.

.DESCRIPTION
Loads data into CSV from a collection of PowerShell
objects provided by the ETL pipeline.

This module implements the Invoke-Load entry point used by
the ETL runtime.

.VERSION
1.0

.AUTHOR
ETL Framework

.INPUTS
System.Object[]

.NOTES
- Entry point: Invoke-Load
- Accepts objects from extract phase
- Responsible for persistence of data
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
        [ValidateSet('INFO', 'WARN', 'ERROR', 'DEBUG')]
        [string] $Level = 'INFO'
    )

    Write-EtlModuleLog -Context $Script:ModuleContext -Message $Message -Level $Level
}

function Resolve-AbsolutePath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $Path
    )

    Resolve-EtlProjectPath -Path $Path -ModuleRoot $PSScriptRoot
}

function Test-LoadConfiguration {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][hashtable] $Config
    )

    try {
        if (-not $Config.Path) {
            throw "Missing destination config value: Path"
        }

        Write-ModuleLog "Destination CSV configuration validated successfully." -Level "DEBUG"
        return $true
    }
    catch {
        Write-ModuleLog "Destination CSV configuration validation failed: $($_.Exception.Message)" -Level "ERROR"
        return $false
    }
}

function Ensure-Directory {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $FilePath
    )

    $Directory = Split-Path -Path $FilePath -Parent

    if ([string]::IsNullOrWhiteSpace($Directory)) {
        return
    }

    if (-not (Test-Path -Path $Directory -PathType Container)) {
        New-Item -Path $Directory -ItemType Directory -Force | Out-Null
        Write-ModuleLog "Created output directory: $Directory" -Level "INFO"
    }
}

function Get-FileEncoding {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $EncodingName
    )

    switch ($EncodingName.ToUpperInvariant()) {
        'ASCII'   { return [System.Text.Encoding]::ASCII }
        'UTF8'    { return [System.Text.UTF8Encoding]::new($false) }
        'UTF8BOM' { return [System.Text.UTF8Encoding]::new($true) }
        'UTF7'    { return [System.Text.Encoding]::UTF7 }
        'UTF32'   { return [System.Text.Encoding]::UTF32 }
        'UNICODE' { return [System.Text.Encoding]::Unicode }
        'DEFAULT' { return [System.Text.Encoding]::Default }
        default { throw "Unsupported CSV encoding: $EncodingName" }
    }
}

function Get-PropertyNames {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object] $Row
    )

    if ($Row -is [System.Data.DataRow]) {
        return @($Row.Table.Columns | ForEach-Object { $_.ColumnName })
    }

    return @($Row.PSObject.Properties.Name)
}

function Get-ExistingCsvHeader {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $Path,
        [Parameter(Mandatory)][string] $Delimiter
    )

    if (-not (Test-Path -Path $Path -PathType Leaf)) {
        return @()
    }

    $FirstLine = Get-Content -Path $Path -TotalCount 1 -ErrorAction Stop
    if ([string]::IsNullOrWhiteSpace($FirstLine)) {
        return @()
    }

    $NormalizedFirstLine = $FirstLine.TrimStart([char]0xFEFF)
    $ParsedHeader = @((@($NormalizedFirstLine, $NormalizedFirstLine) | ConvertFrom-Csv -Delimiter $Delimiter))
    if ($ParsedHeader.Count -eq 0) {
        return @()
    }

    return @($ParsedHeader[0].PSObject.Properties.Name)
}

function Test-CsvHeaderCompatibility {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string[]] $ExistingHeader,
        [Parameter(Mandatory)][string[]] $PropertyNames,
        [Parameter(Mandatory)][string] $Path
    )

    if ($ExistingHeader.Count -ne $PropertyNames.Count) {
        throw "Append mode detected schema mismatch for target CSV [$Path]. Existing header column count [$($ExistingHeader.Count)] differs from incoming column count [$($PropertyNames.Count)]."
    }

    for ($i = 0; $i -lt $PropertyNames.Count; $i++) {
        if ([string]$ExistingHeader[$i] -cne [string]$PropertyNames[$i]) {
            throw "Append mode detected schema mismatch for target CSV [$Path] at column index [$($i + 1)]. Existing header [$($ExistingHeader[$i])] differs from incoming header [$($PropertyNames[$i])]."
        }
    }
}

function Convert-ToOrderedCsvRow {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object] $Row,
        [Parameter(Mandatory)][string[]] $PropertyNames
    )

    $Ordered = [ordered]@{}
    foreach ($PropertyName in $PropertyNames) {
        $Value = $null

        if ($Row -is [System.Data.DataRow]) {
            if ($Row.Table.Columns.Contains($PropertyName)) {
                $Value = $Row[$PropertyName]
            }
        }
        else {
            $Property = $Row.PSObject.Properties[$PropertyName]
            if ($null -ne $Property) {
                $Value = $Property.Value
            }
        }

        $Ordered[$PropertyName] = $Value
    }

    return [PSCustomObject]$Ordered
}

function Write-CsvBatch {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][System.IO.StreamWriter] $Writer,
        [Parameter(Mandatory)][System.Collections.Generic.List[object]] $Batch,
        [Parameter(Mandatory)][string[]] $PropertyNames,
        [Parameter(Mandatory)][string] $Delimiter,
        [Parameter(Mandatory)][ref] $HeaderWritten,
        [Parameter(Mandatory)][ref] $RowsWritten
    )

    if ($Batch.Count -eq 0) {
        return
    }

    $PreparedRows = foreach ($Item in $Batch) {
        Convert-ToOrderedCsvRow -Row $Item -PropertyNames $PropertyNames
    }

    $Lines = @($PreparedRows | ConvertTo-Csv -Delimiter $Delimiter -NoTypeInformation)
    if ($Lines.Count -eq 0) {
        $Batch.Clear()
        return
    }

    $StartIndex = 0
    if ($HeaderWritten.Value) {
        $StartIndex = 1
    }

    for ($i = $StartIndex; $i -lt $Lines.Count; $i++) {
        $Writer.WriteLine($Lines[$i])
    }

    if (-not $HeaderWritten.Value) {
        $HeaderWritten.Value = $true
    }

    $RowsWritten.Value += $Batch.Count
    $Writer.Flush()
    $Batch.Clear()
}

function Invoke-Load {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [object] $Data,

        [Parameter(Mandatory = $true)]
        [hashtable] $Config
    )

    begin {
        if (-not (Test-LoadConfiguration -Config $Config)) {
            throw "Destination CSV configuration is invalid."
        }

        $ResolvedPath = Resolve-AbsolutePath -Path ([string]$Config.Path)
        $Delimiter    = if ($Config.Delimiter) { [string]$Config.Delimiter } else { ';' }
        $Encoding     = if ($Config.Encoding)  { Get-FileEncoding -EncodingName ([string]$Config.Encoding) } else { [System.Text.UTF8Encoding]::new($false) }
        $Append       = if ($null -ne $Config.Append) { [System.Convert]::ToBoolean($Config.Append) } else { $false }
        $Force        = if ($null -ne $Config.Force)  { [System.Convert]::ToBoolean($Config.Force) } else { $true }
        $BatchSize    = if ($Config.BatchSize) { [int]$Config.BatchSize } else { 1000 }

        if ($BatchSize -lt 1) {
            $BatchSize = 1000
        }

        Write-ModuleLog "Preparing CSV export to: $ResolvedPath" -Level "INFO"
        Write-ModuleLog "CSV delimiter resolved to: '$Delimiter'" -Level "DEBUG"
        Write-ModuleLog "CSV encoding resolved to: '$($Encoding.WebName)'" -Level "DEBUG"
        Write-ModuleLog "Append mode: $Append" -Level "DEBUG"
        Write-ModuleLog "Force overwrite mode: $Force" -Level "DEBUG"
        Write-ModuleLog "BatchSize resolved to: $BatchSize" -Level "INFO"

        Ensure-Directory -FilePath $ResolvedPath

        if ((Test-Path -Path $ResolvedPath -PathType Leaf) -and -not $Append -and -not $Force) {
            throw "Target CSV file already exists and neither Append nor Force is enabled: $ResolvedPath"
        }

        $FileMode = if ($Append) { [System.IO.FileMode]::Append } else { [System.IO.FileMode]::Create }
        $FileStream = [System.IO.File]::Open($ResolvedPath, $FileMode, [System.IO.FileAccess]::Write, [System.IO.FileShare]::Read)
        $Writer = [System.IO.StreamWriter]::new($FileStream, $Encoding)

        $ExistingHasContent = $false
        if ($Append -and (Test-Path -Path $ResolvedPath -PathType Leaf)) {
            $ExistingHasContent = ((Get-Item -Path $ResolvedPath -ErrorAction Stop).Length -gt 0)
        }

        $ExistingHeader = @()
        if ($Append -and $ExistingHasContent) {
            $ExistingHeader = Get-ExistingCsvHeader -Path $ResolvedPath -Delimiter $Delimiter
            Write-ModuleLog "Detected existing CSV header in append mode: $($ExistingHeader -join ', ')" -Level 'INFO'
        }

        $HeaderWritten = [ref]$ExistingHasContent
        $RowsWritten = [ref]0
        $RowsReceived = [ref]0
        $BatchesWritten = [ref]0
        $Buffer = New-Object 'System.Collections.Generic.List[object]'
        $PropertyNames = $null
        $PreviewLogged = $false
    }

    process {
        if ($null -eq $Data) {
            Write-ModuleLog 'Destination CSV received a null pipeline object. Entry skipped.' -Level 'DEBUG'
            return
        }

        $RowsReceived.Value++

        if ($null -eq $PropertyNames) {
            $PropertyNames = Get-PropertyNames -Row $Data
            Write-ModuleLog "CSV output columns resolved: $($PropertyNames -join ', ')" -Level "INFO"
            if ($Append -and $ExistingHasContent) {
                Test-CsvHeaderCompatibility -ExistingHeader $ExistingHeader -PropertyNames $PropertyNames -Path $ResolvedPath
                Write-ModuleLog 'Existing CSV header is compatible with incoming data schema.' -Level 'INFO'
            }
        }

        if (-not $PreviewLogged) {
            Write-ModuleLog ("First CSV destination row preview: {0}" -f (Get-EtlObjectPreview -InputObject $Data)) -Level "INFO"
            $PreviewLogged = $true
        }

        [void]$Buffer.Add($Data)

        if ($Buffer.Count -ge $BatchSize) {
            Write-CsvBatch -Writer $Writer -Batch $Buffer -PropertyNames $PropertyNames -Delimiter $Delimiter -HeaderWritten $HeaderWritten -RowsWritten $RowsWritten
            $BatchesWritten.Value++
            Write-ModuleLog ("CSV destination flushed batch [{0}] with total rows written [{1}]." -f $BatchesWritten.Value, $RowsWritten.Value) -Level 'INFO'
        }
    }

    end {
        try {
            if ($Buffer.Count -gt 0) {
                Write-CsvBatch -Writer $Writer -Batch $Buffer -PropertyNames $PropertyNames -Delimiter $Delimiter -HeaderWritten $HeaderWritten -RowsWritten $RowsWritten
                $BatchesWritten.Value++
                Write-ModuleLog ("CSV destination flushed final batch [{0}] with total rows written [{1}]." -f $BatchesWritten.Value, $RowsWritten.Value) -Level 'INFO'
            }

            if ($RowsWritten.Value -eq 0) {
                Write-ModuleLog "No input data received. CSV export completed without data rows." -Level "WARN"
            }
            else {
                Write-ModuleLog "CSV export completed successfully: $ResolvedPath ($($RowsWritten.Value) rows, $($BatchesWritten.Value) batches, $($RowsReceived.Value) rows received)." -Level "INFO"
            }
        }
        catch {
            Write-EtlExceptionDetails -Context $Script:ModuleContext -ErrorRecord $_ -Prefix 'CSV export failed:'
            throw
        }
        finally {
            if ($Writer) {
                $Writer.Dispose()
            }
            if ($FileStream) {
                $FileStream.Dispose()
            }
        }
    }
}

Export-ModuleMember -Function Invoke-Load
