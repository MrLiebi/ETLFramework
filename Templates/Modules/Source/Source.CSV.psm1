<#
.SYNOPSIS
ETL source adapter for CSV.

.DESCRIPTION
Extracts data from CSV and returns it as a structured
collection of PowerShell objects for further processing in the
ETL pipeline.

.VERSION
22.0.0
#>

$CommonModulePath = Join-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -ChildPath 'Common\Framework.Common.psm1'
if (-not (Test-Path -Path $CommonModulePath -PathType Leaf)) {
    throw "Common runtime module manifest not found: $CommonModulePath"
}

Import-Module -Name $CommonModulePath -Force -ErrorAction Stop
$Script:ModuleContext = New-EtlModuleContext -ModulePath $MyInvocation.MyCommand.Path -ModuleRoot $PSScriptRoot

function Write-ModuleLog {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory)][string] $Message,
        [ValidateSet('INFO', 'WARN', 'ERROR', 'DEBUG')][string] $Level = 'INFO'
    )
    Write-EtlModuleLog -Context $Script:ModuleContext -Message $Message -Level $Level
}

function Resolve-AbsolutePath {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param([Parameter(Mandatory)][string] $Path)
    Resolve-EtlProjectPath -Path $Path -ModuleRoot $PSScriptRoot
}

function Test-ExtractConfiguration {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param([Parameter(Mandatory)][hashtable] $Config)

    try {
        if (-not $Config.Path) { throw 'Missing source config value: Path' }
        Write-ModuleLog 'Source CSV configuration validated successfully.' -Level 'DEBUG'
        return $true
    }
    catch {
        Write-ModuleLog "Source CSV configuration validation failed: $($_.Exception.Message)" -Level 'ERROR'
        return $false
    }
}

function Resolve-TextEncoding {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param([Parameter(Mandatory)][string] $EncodingName)

    switch ($EncodingName.ToLowerInvariant()) {
        'utf8'              { return [System.Text.UTF8Encoding]::new($false) }
        'utf-8'             { return [System.Text.UTF8Encoding]::new($false) }
        'utf8bom'           { return [System.Text.UTF8Encoding]::new($true) }
        'utf-8-bom'         { return [System.Text.UTF8Encoding]::new($true) }
        'unicode'           { return [System.Text.Encoding]::Unicode }
        'utf16'             { return [System.Text.Encoding]::Unicode }
        'utf-16'            { return [System.Text.Encoding]::Unicode }
        'bigendianunicode'  { return [System.Text.Encoding]::BigEndianUnicode }
        'utf16be'           { return [System.Text.Encoding]::BigEndianUnicode }
        'utf-16be'          { return [System.Text.Encoding]::BigEndianUnicode }
        'ascii'             { return [System.Text.Encoding]::ASCII }
        'ansi'              { return [System.Text.Encoding]::GetEncoding(1252) }
        'windows-1252'      { return [System.Text.Encoding]::GetEncoding(1252) }
        '1252'              { return [System.Text.Encoding]::GetEncoding(1252) }
        'latin1'            { return [System.Text.Encoding]::GetEncoding('iso-8859-1') }
        'iso-8859-1'        { return [System.Text.Encoding]::GetEncoding('iso-8859-1') }
        default             { return [System.Text.Encoding]::GetEncoding($EncodingName) }
    }
}

function Get-DetectedFileEncoding {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param([Parameter(Mandatory)][string] $Path)

    $ProbeLength = 4096
    $Buffer = New-Object byte[] $ProbeLength
    $FileStream = [System.IO.File]::Open($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
    try {
        $BytesRead = $FileStream.Read($Buffer, 0, $Buffer.Length)
    }
    finally {
        $FileStream.Dispose()
    }

    $Bytes = if ($BytesRead -gt 0) { $Buffer[0..($BytesRead - 1)] } else { @() }

    if ($BytesRead -ge 3 -and $Bytes[0] -eq 0xEF -and $Bytes[1] -eq 0xBB -and $Bytes[2] -eq 0xBF) {
        return [PSCustomObject]@{ Encoding = [System.Text.UTF8Encoding]::new($true); Name = 'utf-8-bom'; Source = 'BOM' }
    }
    if ($BytesRead -ge 2 -and $Bytes[0] -eq 0xFF -and $Bytes[1] -eq 0xFE) {
        return [PSCustomObject]@{ Encoding = [System.Text.Encoding]::Unicode; Name = 'utf-16-le'; Source = 'BOM' }
    }
    if ($BytesRead -ge 2 -and $Bytes[0] -eq 0xFE -and $Bytes[1] -eq 0xFF) {
        return [PSCustomObject]@{ Encoding = [System.Text.Encoding]::BigEndianUnicode; Name = 'utf-16-be'; Source = 'BOM' }
    }

    try {
        $Utf8Strict = [System.Text.UTF8Encoding]::new($false, $true)
        [void]$Utf8Strict.GetString([byte[]]$Bytes)
        return [PSCustomObject]@{ Encoding = [System.Text.UTF8Encoding]::new($false); Name = 'utf-8'; Source = 'Heuristic' }
    }
    catch {
        return [PSCustomObject]@{ Encoding = [System.Text.Encoding]::GetEncoding(1252); Name = 'windows-1252'; Source = 'Fallback' }
    }
}

function Resolve-SourceCsvFile {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param([Parameter(Mandatory)][string] $ResolvedPath, [string] $FilePattern = '*.csv')

    if (Test-Path -Path $ResolvedPath -PathType Leaf) { return (Get-Item -Path $ResolvedPath -ErrorAction Stop).FullName }
    if (-not (Test-Path -Path $ResolvedPath -PathType Container)) { throw "Configured CSV path not found: $ResolvedPath" }

    $Files = @(Get-ChildItem -Path $ResolvedPath -File -Filter $FilePattern -ErrorAction Stop | Sort-Object Name)
    if ($Files.Count -eq 0) { throw "No CSV files found in folder: $ResolvedPath (Pattern: $FilePattern)" }
    if ($Files.Count -gt 1) {
        $CandidateNames = ($Files | Select-Object -First 10 -ExpandProperty Name) -join ', '
        throw "File pattern resolution for CSV requires exactly one matching file in '$ResolvedPath'. Pattern '$FilePattern' matched $($Files.Count) files: $CandidateNames"
    }

    return $Files[0].FullName
}

function ConvertTo-FilteredRow {
    [CmdletBinding(SupportsShouldProcess = $true)]
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

function Test-RowHasData {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param([Parameter(Mandatory)][psobject] $Row)

    foreach ($Value in $Row.PSObject.Properties.Value) {
        if ($null -eq $Value) { continue }
        if ($Value -isnot [string]) { return $true }
        if (-not [string]::IsNullOrWhiteSpace([string]$Value)) { return $true }
    }
    return $false
}

function New-CsvTextFieldParser {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory)][string] $Path,
        [Parameter(Mandatory)][System.Text.Encoding] $Encoding,
        [Parameter(Mandatory)][string] $Delimiter
    )

    Add-Type -AssemblyName Microsoft.VisualBasic -ErrorAction Stop
    $Parser = New-Object Microsoft.VisualBasic.FileIO.TextFieldParser($Path, $Encoding)
    $Parser.TextFieldType = [Microsoft.VisualBasic.FileIO.FieldType]::Delimited
    $Parser.SetDelimiters(@($Delimiter))
    $Parser.HasFieldsEnclosedInQuotes = $true
    $Parser.TrimWhiteSpace = $false
    return $Parser
}

function Get-CsvHeaders {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param([Parameter(Mandatory)] $Parser)

    $Headers = $Parser.ReadFields()
    if ($null -eq $Headers -or $Headers.Count -eq 0) {
        throw 'CSV file is empty or missing a header row.'
    }

    $Seen = @{}
    $Normalized = New-Object System.Collections.Generic.List[string]
    for ($i = 0; $i -lt $Headers.Count; $i++) {
        $Header = [string]$Headers[$i]
        if ([string]::IsNullOrWhiteSpace($Header)) { $Header = 'Column{0}' -f ($i + 1) }
        $Header = $Header.Trim()
        if ($Seen.ContainsKey($Header)) {
            $Seen[$Header]++
            $Header = '{0}_{1}' -f $Header, $Seen[$Header]
        } else {
            $Seen[$Header] = 1
        }
        [void]$Normalized.Add($Header)
    }

    return @($Normalized.ToArray())
}

function Convert-CsvFieldsToObject {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory)][string[]] $Headers,
        [Parameter(Mandatory)][object] $Fields
    )

    if ($null -eq $Fields) {
        $Fields = @()
    }
    elseif ($Fields -is [string]) {
        $Fields = @($Fields)
    }
    else {
        $Fields = @($Fields)
    }

    $Row = [ordered]@{}
    for ($i = 0; $i -lt $Headers.Count; $i++) {
        $Row[$Headers[$i]] = if ($i -lt $Fields.Count) { $Fields[$i] } else { $null }
    }
    return [pscustomobject]$Row
}

function Invoke-Extract {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true)][hashtable] $Config,
        [Parameter(Mandatory = $true)][string[]] $Properties
    )

    if (-not (Test-ExtractConfiguration -Config $Config)) {
        throw 'Source CSV configuration is invalid.'
    }

    $Parser = $null
    try {
        $ResolvedPath       = Resolve-AbsolutePath -Path ([string]$Config.Path)
        $Delimiter          = if ($Config.Delimiter) { [string]$Config.Delimiter } else { ';' }
        $EncodingName       = if ($Config.Encoding) { [string]$Config.Encoding } else { 'auto' }
        $FilePattern        = if ($Config.FilePattern) { [string]$Config.FilePattern } else { '*.csv' }
        $SelectedProperties = Get-ValidatedPropertySelection -Properties $Properties

        $CsvFile = Resolve-SourceCsvFile -ResolvedPath $ResolvedPath -FilePattern $FilePattern
        $env:ETL_LAST_SOURCE_FILE = $CsvFile
        $env:ETL_LAST_SOURCE_TYPE = 'CSV'
        Write-ModuleLog "Selected CSV source file: $CsvFile" -Level 'INFO'
        Write-ModuleLog 'Registered selected CSV source file for post-import actions.' -Level 'DEBUG'

        if ([string]::IsNullOrWhiteSpace($EncodingName) -or $EncodingName.ToLowerInvariant() -in @('auto', 'default')) {
            $EncodingInfo = Get-DetectedFileEncoding -Path $CsvFile
            $TextEncoding = $EncodingInfo.Encoding
            Write-ModuleLog "Detected CSV encoding '$($EncodingInfo.Name)' via $($EncodingInfo.Source)." -Level 'INFO'
        } else {
            $TextEncoding = Resolve-TextEncoding -EncodingName $EncodingName
            Write-ModuleLog "Using configured CSV encoding '$($TextEncoding.WebName)'." -Level 'INFO'
        }

        Write-ModuleLog "Reading CSV file with delimiter '$Delimiter' using record-aware streaming mode." -Level 'INFO'
        Write-ModuleLog "Requested property selection: $($SelectedProperties -join ', ')" -Level 'INFO'

        $Parser = New-CsvTextFieldParser -Path $CsvFile -Encoding $TextEncoding -Delimiter $Delimiter
        $Headers = Get-CsvHeaders -Parser $Parser
        Write-ModuleLog ("CSV header preview: {0}" -f (($Headers | Select-Object -First 10) -join ', ')) -Level 'INFO'

        $RowsProcessed = 0
        $RowsEmitted = 0
        $PreviewLogged = $false

        while (-not $Parser.EndOfData) {
            $Fields = $Parser.ReadFields()
            $RowsProcessed++

            if ($null -eq $Fields) {
                Write-ModuleLog "Skipping null CSV row at data row index [$RowsProcessed]." -Level 'DEBUG'
                continue
            }

            if ($Fields -is [string]) {
                if ([string]::IsNullOrWhiteSpace($Fields)) {
                    Write-ModuleLog "Skipping empty CSV row at data row index [$RowsProcessed]." -Level 'DEBUG'
                    continue
                }

                $Fields = @($Fields)
            }
            else {
                $Fields = @($Fields)
            }

            $Row = Convert-CsvFieldsToObject -Headers $Headers -Fields $Fields
            if (-not (Test-RowHasData -Row $Row)) {
                Write-ModuleLog "Skipping blank CSV row after normalization at data row index [$RowsProcessed]." -Level 'DEBUG'
                continue
            }

            $FilteredRow = ConvertTo-FilteredRow -Row $Row -SelectedProperties $SelectedProperties
            if (-not $PreviewLogged) {
                Write-ModuleLog ("First CSV row preview: {0}" -f (Get-EtlObjectPreview -InputObject $FilteredRow)) -Level 'INFO'
                $PreviewLogged = $true
            }

            $RowsEmitted++
            $FilteredRow
        }

        if ($RowsEmitted -eq 0) {
            Write-ModuleLog 'CSV extract emitted zero rows. Downstream destination will receive no rows.' -Level 'WARN'
        }
        Write-ModuleLog "CSV extract completed successfully. Data rows processed: $RowsProcessed | Rows emitted: $RowsEmitted" -Level 'INFO'
    }
    catch {
        Write-EtlExceptionDetails -Context $Script:ModuleContext -ErrorRecord $_ -Prefix 'CSV extract failed:'
        throw
    }
    finally {
        if ($Parser) { $Parser.Close(); $Parser.Dispose() }
    }
}

Export-ModuleMember -Function Invoke-Extract
