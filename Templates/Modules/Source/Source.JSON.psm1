<#
.SYNOPSIS
ETL source adapter for JSON and JSONL files.

.DESCRIPTION
Extracts data from JSON or JSONL files and returns flattened PowerShell
objects for further ETL processing. Supports direct file selection or folder
+ pattern resolution and registers the selected source file for post-import
actions.

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
        Write-ModuleLog 'Source JSON configuration validated successfully.' -Level 'DEBUG'
        return $true
    }
    catch {
        Write-ModuleLog "Source JSON configuration validation failed: $($_.Exception.Message)" -Level 'ERROR'
        return $false
    }
}

function Resolve-SourceJsonFile {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string] $ResolvedPath, [string] $FilePattern = '*.json*')

    if (Test-Path -Path $ResolvedPath -PathType Leaf) { return (Get-Item -Path $ResolvedPath -ErrorAction Stop).FullName }
    if (-not (Test-Path -Path $ResolvedPath -PathType Container)) { throw "Configured JSON path not found: $ResolvedPath" }

    $Files = @(Get-ChildItem -Path $ResolvedPath -File -Filter $FilePattern -ErrorAction Stop | Sort-Object Name)
    if ($Files.Count -eq 0) { throw "No JSON/JSONL files found in folder: $ResolvedPath (Pattern: $FilePattern)" }
    if ($Files.Count -gt 1) {
        $CandidateNames = ($Files | Select-Object -First 10 -ExpandProperty Name) -join ', '
        throw "File pattern resolution for JSON requires exactly one matching file in '$ResolvedPath'. Pattern '$FilePattern' matched $($Files.Count) files: $CandidateNames"
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

function Read-TextFileWithBomDetection {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string] $Path)

    $StreamReader = [System.IO.StreamReader]::new($Path, $true)
    try {
        return $StreamReader.ReadToEnd()
    }
    finally {
        $StreamReader.Dispose()
    }
}

function Get-JsonFormat {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $Path,
        [string] $ConfiguredFormat = 'Auto'
    )

    $FormatText = if ([string]::IsNullOrWhiteSpace($ConfiguredFormat)) { 'Auto' } else { $ConfiguredFormat.Trim() }

    switch -Regex ($FormatText) {
        '^(?i:jsonl|ndjson)$' { return 'JsonL' }
        '^(?i:json)$'         { return 'Json' }
    }

    $Extension = [System.IO.Path]::GetExtension($Path)
    if ($Extension -match '^(?i:\.jsonl|\.ndjson)$') {
        return 'JsonL'
    }

    return 'Json'
}

function Resolve-JsonRootValue {
    [CmdletBinding()]
    param(
        [AllowNull()] $InputObject,
        [string] $RootPath
    )

    if ([string]::IsNullOrWhiteSpace($RootPath)) {
        return $InputObject
    }

    $Current = $InputObject
    foreach ($Segment in @($RootPath -split '\.' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })) {
        if ($null -eq $Current) {
            return $null
        }

        if ($Current -is [System.Collections.IDictionary]) {
            if (-not $Current.Contains($Segment)) { return $null }
            $Current = $Current[$Segment]
            continue
        }

        $Property = $Current.PSObject.Properties[$Segment]
        if ($null -eq $Property) {
            return $null
        }

        $Current = $Property.Value
    }

    return $Current
}

function Test-IsJsonScalar {
    [CmdletBinding()]
    param([AllowNull()] $Value)

    if ($null -eq $Value) { return $true }
    return (
        $Value -is [string] -or
        $Value -is [char] -or
        $Value -is [bool] -or
        $Value -is [byte] -or
        $Value -is [sbyte] -or
        $Value -is [int16] -or
        $Value -is [int32] -or
        $Value -is [int64] -or
        $Value -is [uint16] -or
        $Value -is [uint32] -or
        $Value -is [uint64] -or
        $Value -is [single] -or
        $Value -is [double] -or
        $Value -is [decimal] -or
        $Value -is [datetime]
    )
}

function Add-FlattenedJsonValue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][System.Collections.IDictionary] $Target,
        [Parameter(Mandatory)][string] $Key,
        [AllowNull()] $Value
    )

    if ([string]::IsNullOrWhiteSpace($Key)) { return }

    if ($Target.Contains($Key)) {
        if ($null -eq $Value) { return }
        $Existing = [string]$Target[$Key]
        $Incoming = [string]$Value
        if ([string]::IsNullOrWhiteSpace($Incoming)) { return }

        if ([string]::IsNullOrWhiteSpace($Existing)) {
            $Target[$Key] = $Incoming
        }
        else {
            $Target[$Key] = '{0}; {1}' -f $Existing, $Incoming
        }

        return
    }

    $Target[$Key] = $Value
}

function Flatten-JsonObject {
    [CmdletBinding()]
    param(
        [AllowNull()] $InputObject,
        [Parameter(Mandatory)][System.Collections.IDictionary] $Target,
        [string] $Prefix = ''
    )

    if (Test-IsJsonScalar -Value $InputObject) {
        if (-not [string]::IsNullOrWhiteSpace($Prefix)) {
            Add-FlattenedJsonValue -Target $Target -Key $Prefix -Value $InputObject
        }
        return
    }

    if ($InputObject -is [System.Collections.IEnumerable] -and $InputObject -isnot [string]) {
        $Items = @($InputObject)
        if ($Items.Count -eq 0) {
            if (-not [string]::IsNullOrWhiteSpace($Prefix)) {
                Add-FlattenedJsonValue -Target $Target -Key $Prefix -Value $null
            }
            return
        }

        if (@($Items | Where-Object { -not (Test-IsJsonScalar -Value $_) }).Count -eq 0) {
            $Joined = @($Items | ForEach-Object { [string]$_ }) -join '; '
            if (-not [string]::IsNullOrWhiteSpace($Prefix)) {
                Add-FlattenedJsonValue -Target $Target -Key $Prefix -Value $Joined
            }
            return
        }

        if (-not [string]::IsNullOrWhiteSpace($Prefix)) {
            Add-FlattenedJsonValue -Target $Target -Key $Prefix -Value ($Items | ConvertTo-Json -Compress -Depth 20)
        }

        return
    }

    $Properties = @($InputObject.PSObject.Properties)
    foreach ($Property in $Properties) {
        $ChildKey = if ([string]::IsNullOrWhiteSpace($Prefix)) { $Property.Name } else { "$Prefix.$($Property.Name)" }
        Flatten-JsonObject -InputObject $Property.Value -Target $Target -Prefix $ChildKey
    }
}

function ConvertTo-FlatJsonObject {
    [CmdletBinding()]
    param([AllowNull()] $InputObject)

    if ($null -eq $InputObject) {
        return [PSCustomObject]@{}
    }

    if (Test-IsJsonScalar -Value $InputObject) {
        return [PSCustomObject]@{ Value = $InputObject }
    }

    $Flattened = [ordered]@{}
    Flatten-JsonObject -InputObject $InputObject -Target $Flattened
    return [PSCustomObject]$Flattened
}

function Get-JsonRecords {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $JsonFile,
        [Parameter(Mandatory)][string] $Format,
        [string] $RootPath
    )

    if ($Format -eq 'JsonL') {
        $Records = New-Object System.Collections.Generic.List[object]
        $StreamReader = [System.IO.StreamReader]::new($JsonFile, $true)
        try {
            while (-not $StreamReader.EndOfStream) {
                $Line = $StreamReader.ReadLine()
                if ([string]::IsNullOrWhiteSpace($Line)) { continue }
                [void]$Records.Add(($Line | ConvertFrom-Json))
            }
        }
        finally {
            $StreamReader.Dispose()
        }

        return @($Records.ToArray())
    }

    $JsonText = Read-TextFileWithBomDetection -Path $JsonFile
    $Parsed = $JsonText | ConvertFrom-Json
    $RootValue = Resolve-JsonRootValue -InputObject $Parsed -RootPath $RootPath

    if ($null -eq $RootValue) {
        throw "Configured JSON root path did not resolve to any value: $RootPath"
    }

    if ($RootValue -is [System.Collections.IEnumerable] -and $RootValue -isnot [string] -and $RootValue -isnot [System.Collections.IDictionary]) {
        return @($RootValue)
    }

    return @($RootValue)
}

function Invoke-Extract {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][hashtable] $Config,
        [Parameter(Mandatory = $true)][string[]] $Properties
    )

    if (-not (Test-ExtractConfiguration -Config $Config)) {
        throw 'Source JSON configuration is invalid.'
    }

    try {
        $ResolvedPath       = Resolve-AbsolutePath -Path ([string]$Config.Path)
        $FilePattern        = if ($Config.FilePattern) { [string]$Config.FilePattern } else { '*.json*' }
        $ConfiguredFormat   = if ($Config.Format) { [string]$Config.Format } else { 'Auto' }
        $RootPath           = if ($Config.ContainsKey('RootPath')) { [string]$Config.RootPath } else { '' }
        $SelectedProperties = Get-ValidatedPropertySelection -Properties $Properties

        $JsonFile = Resolve-SourceJsonFile -ResolvedPath $ResolvedPath -FilePattern $FilePattern
        $env:ETL_LAST_SOURCE_FILE = $JsonFile
        $env:ETL_LAST_SOURCE_TYPE = 'JSON'
        Write-ModuleLog "Selected JSON source file: $JsonFile" -Level 'INFO'
        Write-ModuleLog 'Registered selected JSON source file for post-import actions.' -Level 'DEBUG'

        $Format = Get-JsonFormat -Path $JsonFile -ConfiguredFormat $ConfiguredFormat
        Write-ModuleLog ("Using JSON input mode: {0}" -f $Format) -Level 'INFO'
        if (-not [string]::IsNullOrWhiteSpace($RootPath) -and $Format -eq 'Json') {
            Write-ModuleLog ("Using JSON root path: {0}" -f $RootPath) -Level 'INFO'
        }

        $Records = @(Get-JsonRecords -JsonFile $JsonFile -Format $Format -RootPath $RootPath)
        $EmittedRows = 0
        $PreviewLogged = $false

        foreach ($Record in $Records) {
            $Row = ConvertTo-FlatJsonObject -InputObject $Record
            $FilteredRow = ConvertTo-FilteredRow -Row $Row -SelectedProperties $SelectedProperties

            if (-not $PreviewLogged) {
                Write-ModuleLog ("First JSON row preview: {0}" -f (Get-EtlObjectPreview -InputObject $FilteredRow)) -Level 'INFO'
                $PreviewLogged = $true
            }

            $EmittedRows++
            $FilteredRow
        }

        if ($EmittedRows -eq 0) {
            Write-ModuleLog 'JSON extract emitted zero rows. Downstream destination will receive no rows.' -Level 'WARN'
        }
        else {
            Write-ModuleLog ("JSON extract completed successfully. Rows emitted: {0}" -f $EmittedRows) -Level 'INFO'
        }
    }
    catch {
        Write-EtlExceptionDetails -Context $Script:ModuleContext -ErrorRecord $_ -Prefix 'JSON extract failed:'
        throw
    }
}

Export-ModuleMember -Function Invoke-Extract
