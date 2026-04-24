<#
.SYNOPSIS
ETL destination adapter for MSSQL.

.DESCRIPTION
Loads data into MSSQL from a collection of PowerShell
objects provided by the ETL pipeline.

This module implements the Invoke-Load entry point used by
the ETL runtime.

.VERSION
1.0.0

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
$Script:CultureDE = [System.Globalization.CultureInfo]::GetCultureInfo('de-DE')
$Script:CultureEN = [System.Globalization.CultureInfo]::GetCultureInfo('en-US')
$Script:InvariantCulture = [System.Globalization.CultureInfo]::InvariantCulture
$Script:DecimalStyles = [System.Globalization.NumberStyles]::Number
$Script:IntegerStyles = [System.Globalization.NumberStyles]::Integer
$Script:DateTimeStyles = [System.Globalization.DateTimeStyles]::AllowWhiteSpaces
$Script:DatePatterns = @(
    'yyyy-MM-dd',
    'yyyy-MM-dd HH:mm:ss',
    'yyyy-MM-dd HH:mm:ss.fff',
    'yyyy-MM-ddTHH:mm:ss',
    'yyyy-MM-ddTHH:mm:ss.fff',
    'yyyy-MM-ddTHH:mm:ssK',
    'yyyy-MM-ddTHH:mm:ss.fffK',
    'dd.MM.yyyy',
    'd.M.yyyy',
    'dd.MM.yyyy HH:mm:ss',
    'd.M.yyyy H:mm:ss',
    'dd.MM.yyyy HH:mm',
    'd.M.yyyy H:mm',
    'MM/dd/yyyy',
    'M/d/yyyy',
    'MM/dd/yyyy HH:mm:ss',
    'M/d/yyyy H:mm:ss',
    'MM/dd/yyyy HH:mm',
    'M/d/yyyy H:mm'
)

function Write-ModuleLog {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory)][string] $Message,
        [ValidateSet('INFO', 'WARN', 'ERROR', 'DEBUG')]
        [string] $Level = 'INFO'
    )

    Write-EtlModuleLog -Context $Script:ModuleContext -Message $Message -Level $Level
}

function Test-LoadConfiguration {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory)][hashtable] $Config
    )

    try {
        if (-not $Config.Server -and -not $Config.ConnectionString) {
            throw "Missing destination config value: Server or ConnectionString"
        }

        if (-not $Config.Database -and -not $Config.ConnectionString) {
            throw "Missing destination config value: Database or ConnectionString"
        }

        if (-not $Config.TableName) {
            throw "Missing destination config value: TableName"
        }

        if ($Config.AuthenticationMode -eq 'CredentialManager' -and -not $Config.CredentialTarget) {
            throw "Missing destination config value: CredentialTarget when AuthenticationMode is CredentialManager"
        }

        Write-ModuleLog "Destination MSSQL configuration validated successfully." -Level "DEBUG"
        return $true
    }
    catch {
        Write-ModuleLog "Destination MSSQL configuration validation failed: $($_.Exception.Message)" -Level "ERROR"
        return $false
    }
}

function Get-AuthenticationMode {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory)][hashtable] $Config
    )

    Get-EtlAuthenticationMode -Config $Config
}

function Get-SafeSqlIdentifier {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory)][string] $Name
    )

    $CleanName = $Name.Trim()
    if ([string]::IsNullOrWhiteSpace($CleanName)) {
        throw "SQL identifier must not be empty."
    }

    $CleanName = $CleanName -replace '\[', ''
    $CleanName = $CleanName -replace '\]', ''

    return "[{0}]" -f $CleanName
}

function Get-SqlLiteral {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory)][string] $Value
    )

    $CleanValue = $Value.Trim()
    if ([string]::IsNullOrWhiteSpace($CleanValue)) {
        throw "SQL literal must not be empty."
    }

    return "N'{0}'" -f ($CleanValue -replace "'", "''")
}

function Get-SqlConnectionCredential {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory)][hashtable] $Config
    )

    $AuthenticationMode = Get-AuthenticationMode -Config $Config
    if ($AuthenticationMode -ne 'CredentialManager') {
        return $null
    }

    if ([string]::IsNullOrWhiteSpace([string]$Config.CredentialTarget)) {
        throw "Missing destination config value: CredentialTarget for AuthenticationMode=CredentialManager"
    }

    Import-EtlCredentialSupport -ModuleRoot $PSScriptRoot
    return Get-StoredCredential -Target ([string]$Config.CredentialTarget)
}

function Get-SqlConnectionString {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory)][hashtable] $Config
    )

    if ($Config.ConnectionString) {
        return [string]$Config.ConnectionString
    }

    $AuthenticationMode = Get-AuthenticationMode -Config $Config

    if ($AuthenticationMode -eq 'CredentialManager') {
        return "Server={0};Database={1};Persist Security Info=False" -f $Config.Server, $Config.Database
    }

    return "Server={0};Database={1};Integrated Security=True" -f $Config.Server, $Config.Database
}

function ConvertTo-SecurePasswordForSql {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [AllowNull()] $Password
    )

    if ($Password -is [System.Security.SecureString]) {
        return $Password
    }

    $SecurePassword = New-Object System.Security.SecureString
    $PasswordText = if ($null -eq $Password) { '' } else { [string]$Password }
    if (-not [string]::IsNullOrEmpty($PasswordText)) {
        foreach ($Character in $PasswordText.ToCharArray()) {
            $SecurePassword.AppendChar($Character)
        }
    }

    $SecurePassword.MakeReadOnly()
    return $SecurePassword
}

function New-SqlConnection {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory)][hashtable] $Config
    )

    if ($Config.ConnectionString) {
        return [System.Data.SqlClient.SqlConnection]::new([string]$Config.ConnectionString)
    }

    $AuthenticationMode = Get-AuthenticationMode -Config $Config
    if ($AuthenticationMode -eq 'CredentialManager') {
        $Credential = Get-SqlConnectionCredential -Config $Config
        $CredentialUserName = if ($Credential -is [System.Management.Automation.PSCredential]) {
            [string]$Credential.UserName
        }
        elseif ($Credential.PSObject.Properties['UserName']) {
            [string]$Credential.UserName
        }
        else {
            throw 'Credential target did not provide a usable SQL username.'
        }
        if ([string]::IsNullOrWhiteSpace($CredentialUserName)) {
            throw 'Credential target returned an empty SQL username.'
        }

        $CredentialPasswordValue = if ($Credential -is [System.Management.Automation.PSCredential]) {
            $Credential.Password
        }
        elseif ($Credential.PSObject.Properties['Password']) {
            $Credential.Password
        }
        else {
            throw 'Credential target did not provide a usable SQL password.'
        }

        $ConnectionBuilder = New-Object System.Data.SqlClient.SqlConnectionStringBuilder
        $ConnectionBuilder['Data Source'] = [string]$Config.Server
        $ConnectionBuilder['Initial Catalog'] = [string]$Config.Database
        $ConnectionBuilder['Integrated Security'] = $false
        $ConnectionBuilder['Persist Security Info'] = $false

        $SecurePassword = ConvertTo-SecurePasswordForSql -Password $CredentialPasswordValue
        $SqlCredential = New-Object System.Data.SqlClient.SqlCredential($CredentialUserName, $SecurePassword)
        return [System.Data.SqlClient.SqlConnection]::new($ConnectionBuilder.ConnectionString, $SqlCredential)
    }

    return [System.Data.SqlClient.SqlConnection]::new((Get-SqlConnectionString -Config $Config))
}

function Assert-NonInteractiveSqlConnectionAllowed {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory)][hashtable] $Config
    )

    $IsPesterSession = [bool](Get-Module -Name 'Pester' -ErrorAction SilentlyContinue)
    $IsNonInteractiveTest = ($env:ETL_TEST_NONINTERACTIVE -eq '1') -or $IsPesterSession
    if (-not $IsNonInteractiveTest -or $env:ETL_ALLOW_DB_CONNECTIONS -eq '1') {
        return
    }

    $ServerName = [string]$Config.Server
    if ([string]::IsNullOrWhiteSpace($ServerName)) {
        return
    }

    $NormalizedServer = $ServerName.Trim().ToLowerInvariant()
    $AllowedServers = @('localhost', '.', '(local)', '127.0.0.1', '::1')
    if ($AllowedServers -contains $NormalizedServer) {
        return
    }

    throw "Non-interactive test mode blocked MSSQL destination connection to server [$ServerName]. Set ETL_ALLOW_DB_CONNECTIONS=1 to override."
}


function Get-PropertyNames {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory)][object] $FirstRow
    )

    if ($FirstRow -is [System.Data.DataRow]) {
        return @($FirstRow.Table.Columns | ForEach-Object { $_.ColumnName })
    }

    return @($FirstRow.PSObject.Properties.Name)
}

function Get-PropertyNamesFromRows {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory)][System.Collections.IEnumerable] $InputRows,
        [string[]] $SeedNames = @()
    )

    $ResolvedNames = New-Object 'System.Collections.Generic.List[string]'
    foreach ($SeedName in @($SeedNames)) {
        if (-not [string]::IsNullOrWhiteSpace([string]$SeedName) -and -not $ResolvedNames.Contains([string]$SeedName)) {
            [void]$ResolvedNames.Add([string]$SeedName)
        }
    }

    foreach ($CurrentRow in $InputRows) {
        if ($null -eq $CurrentRow) { continue }

        $RowPropertyNames = if ($CurrentRow -is [System.Data.DataRow]) {
            @($CurrentRow.Table.Columns | ForEach-Object { $_.ColumnName })
        }
        else {
            @($CurrentRow.PSObject.Properties.Name)
        }

        foreach ($PropertyName in $RowPropertyNames) {
            if ([string]::IsNullOrWhiteSpace([string]$PropertyName)) { continue }
            if (-not $ResolvedNames.Contains([string]$PropertyName)) {
                [void]$ResolvedNames.Add([string]$PropertyName)
            }
        }
    }

    return @($ResolvedNames)
}

function Try-ParseDecimalUsingCulture {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory)][string] $Text,
        [Parameter(Mandatory)][System.Globalization.CultureInfo] $Culture,
        [Parameter(Mandatory)][ref] $Result
    )

    try {
        return [decimal]::TryParse($Text, $Script:DecimalStyles, $Culture, $Result)
    }
    catch {
        return $false
    }
}

function Try-ParseDateTimeUsingCulture {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory)][string] $Text,
        [Parameter(Mandatory)][System.Globalization.CultureInfo] $Culture,
        [Parameter(Mandatory)][ref] $Result
    )

    try {
        if ([datetime]::TryParseExact($Text, $Script:DatePatterns, $Culture, $Script:DateTimeStyles, $Result)) {
            return $true
        }

        return [datetime]::TryParse($Text, $Culture, $Script:DateTimeStyles, $Result)
    }
    catch {
        return $false
    }
}

function Test-IsBooleanValue {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory)][object] $Value
    )

    if ($Value -is [bool]) {
        return $true
    }

    if ($Value -is [string]) {
        return ([string]$Value).Trim() -in @('True','False','true','false','1','0','yes','no','y','n','YES','NO','Y','N')
    }

    return $false
}

function Test-IsInt64Value {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory)][object] $Value
    )

    if ($Value -is [int16] -or $Value -is [int32] -or $Value -is [int64]) {
        return $true
    }

    if ($Value -isnot [string]) {
        return $false
    }

    $Parsed = 0L
    return [int64]::TryParse(([string]$Value).Trim(), $Script:IntegerStyles, $Script:InvariantCulture, [ref]$Parsed)
}

function Test-IsDecimalValue {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory)][object] $Value
    )

    if ($Value -is [decimal] -or $Value -is [double] -or $Value -is [float]) {
        return $true
    }

    if ($Value -isnot [string]) {
        return $false
    }

    $Text = ([string]$Value).Trim()
    if ([string]::IsNullOrWhiteSpace($Text)) {
        return $false
    }

    [decimal]$Parsed = 0
    foreach ($Culture in @($Script:CultureDE, $Script:CultureEN, $Script:InvariantCulture)) {
        if (Try-ParseDecimalUsingCulture -Text $Text -Culture $Culture -Result ([ref]$Parsed)) {
            return $true
        }
    }

    $Normalized = $Text.Replace(' ', '')
    if ($Normalized -match '^-?\d{1,3}(\.\d{3})*,\d+$') {
        $Candidate = $Normalized.Replace('.', '').Replace(',', '.')
        return (Try-ParseDecimalUsingCulture -Text $Candidate -Culture $Script:InvariantCulture -Result ([ref]$Parsed))
    }

    if ($Normalized -match '^-?\d{1,3}(,\d{3})*\.\d+$') {
        $Candidate = $Normalized.Replace(',', '')
        return (Try-ParseDecimalUsingCulture -Text $Candidate -Culture $Script:InvariantCulture -Result ([ref]$Parsed))
    }

    return $false
}

function Test-IsDateTimeValue {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory)][object] $Value
    )

    if ($Value -is [datetime]) {
        return $true
    }

    if ($Value -isnot [string]) {
        return $false
    }

    $Text = ([string]$Value).Trim()
    if ([string]::IsNullOrWhiteSpace($Text)) {
        return $false
    }

    [datetime]$Parsed = [datetime]::MinValue
    foreach ($Culture in @($Script:CultureDE, $Script:CultureEN, $Script:InvariantCulture)) {
        if (Try-ParseDateTimeUsingCulture -Text $Text -Culture $Culture -Result ([ref]$Parsed)) {
            return $true
        }
    }

    return $false
}

function Convert-ToDateTimeValue {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory)][object] $Value
    )

    if ($Value -is [datetime]) {
        return $Value
    }

    if ($Value -isnot [string]) {
        return [DBNull]::Value
    }

    $Text = ([string]$Value).Trim()
    if ([string]::IsNullOrWhiteSpace($Text)) {
        return [DBNull]::Value
    }

    [datetime]$Parsed = [datetime]::MinValue
    foreach ($Culture in @($Script:CultureDE, $Script:CultureEN, $Script:InvariantCulture)) {
        if (Try-ParseDateTimeUsingCulture -Text $Text -Culture $Culture -Result ([ref]$Parsed)) {
            return $Parsed
        }
    }

    return [DBNull]::Value
}

function Convert-ToDecimalValue {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory)][object] $Value
    )

    if ($Value -is [decimal]) {
        return $Value
    }

    if ($Value -is [double] -or $Value -is [float]) {
        return [decimal]$Value
    }

    if ($Value -isnot [string]) {
        return [DBNull]::Value
    }

    $Text = ([string]$Value).Trim()
    if ([string]::IsNullOrWhiteSpace($Text)) {
        return [DBNull]::Value
    }

    [decimal]$Parsed = 0
    foreach ($Culture in @($Script:CultureDE, $Script:CultureEN, $Script:InvariantCulture)) {
        if (Try-ParseDecimalUsingCulture -Text $Text -Culture $Culture -Result ([ref]$Parsed)) {
            return $Parsed
        }
    }

    $Normalized = $Text.Replace(' ', '')
    if ($Normalized -match '^-?\d{1,3}(\.\d{3})*,\d+$') {
        $Candidate = $Normalized.Replace('.', '').Replace(',', '.')
        if (Try-ParseDecimalUsingCulture -Text $Candidate -Culture $Script:InvariantCulture -Result ([ref]$Parsed)) {
            return $Parsed
        }
    }

    if ($Normalized -match '^-?\d{1,3}(,\d{3})*\.\d+$') {
        $Candidate = $Normalized.Replace(',', '')
        if (Try-ParseDecimalUsingCulture -Text $Candidate -Culture $Script:InvariantCulture -Result ([ref]$Parsed)) {
            return $Parsed
        }
    }

    return [DBNull]::Value
}

function Initialize-ConversionTracking {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory)][string[]] $PropertyNames
    )

    $Tracking = @{}
    foreach ($PropertyName in $PropertyNames) {
        $Tracking[$PropertyName] = 0
    }

    return $Tracking
}

function Add-ConversionFailure {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory)][hashtable] $Tracking,
        [Parameter(Mandatory)][string] $ColumnName,
        [Parameter(Mandatory)][hashtable] $Config
    )

    if (-not $Tracking.ContainsKey($ColumnName)) {
        $Tracking[$ColumnName] = 0
    }

    $Tracking[$ColumnName] = [int]$Tracking[$ColumnName] + 1

    $FailOnConversionError = if ($null -ne $Config.FailOnConversionError) { [System.Convert]::ToBoolean($Config.FailOnConversionError) } else { $false }
    $MaxErrors = if ($Config.MaxConversionErrorsPerColumn) { [int]$Config.MaxConversionErrorsPerColumn } else { 10 }

    if ($FailOnConversionError -and $Tracking[$ColumnName] -gt $MaxErrors) {
        throw "Maximum conversion errors exceeded for column [$ColumnName]. Current count: $($Tracking[$ColumnName]) | MaxConversionErrorsPerColumn: $MaxErrors"
    }
}

function Write-ConversionSummary {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory)][hashtable] $Tracking,
        [Parameter(Mandatory)][hashtable] $Config
    )

    $AnyFailures = $false
    foreach ($Entry in ($Tracking.GetEnumerator() | Sort-Object Name)) {
        if ([int]$Entry.Value -gt 0) {
            $AnyFailures = $true
            $Level = if ($null -ne $Config.FailOnConversionError -and [System.Convert]::ToBoolean($Config.FailOnConversionError)) { 'INFO' } else { 'WARN' }
            Write-ModuleLog ("Column [{0}] : {1} conversion failures" -f $Entry.Key, $Entry.Value) -Level $Level
        }
    }

    if (-not $AnyFailures) {
        Write-ModuleLog "No conversion failures detected." -Level "INFO"
    }
}

function Resolve-NetType {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory)][string] $NetTypeName
    )

    switch ($NetTypeName.Trim()) {
        'System.String'  { return [string] }
        'System.Boolean' { return [bool] }
        'System.Int64'   { return [int64] }
        'System.Decimal' { return [decimal] }
        'System.DateTime' { return [datetime] }
        default {
            $Resolved = [Type]::GetType($NetTypeName, $false)
            if ($null -eq $Resolved) {
                throw "Unsupported NetType [$NetTypeName] in explicit column definition."
            }
            return $Resolved
        }
    }
}

function Get-ColumnMetadataFromExplicitConfig {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory)][hashtable] $ColumnsConfig,
        [Parameter(Mandatory)][string[]] $PropertyNames
    )

    $ColumnMetadata = @{}

    foreach ($PropertyName in $PropertyNames) {
        $ColumnDefinition = $ColumnsConfig[$PropertyName]
        if ($null -eq $ColumnDefinition) {
            throw "Explicit Columns config is missing an entry for source column [$PropertyName]."
        }

        $SqlType = [string]$ColumnDefinition.SqlType
        $NetTypeName = [string]$ColumnDefinition.NetType

        if ([string]::IsNullOrWhiteSpace($SqlType)) {
            throw "Explicit Columns config for [$PropertyName] is missing SqlType."
        }

        if ([string]::IsNullOrWhiteSpace($NetTypeName)) {
            throw "Explicit Columns config for [$PropertyName] is missing NetType."
        }

        $ColumnMetadata[$PropertyName] = [PSCustomObject]@{
            Name    = $PropertyName
            SqlName = Get-SafeSqlIdentifier -Name $PropertyName
            SqlType = $SqlType
            NetType = Resolve-NetType -NetTypeName $NetTypeName
        }
    }

    return $ColumnMetadata
}

function Get-ColumnMetadataFromPropertyNames {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory)][string[]] $PropertyNames
    )

    $ColumnMetadata = @{}
    foreach ($PropertyName in $PropertyNames) {
        $ColumnMetadata[$PropertyName] = [PSCustomObject]@{
            Name    = $PropertyName
            SqlName = Get-SafeSqlIdentifier -Name $PropertyName
            SqlType = 'NVARCHAR(MAX)'
            NetType = [string]
        }
    }

    return $ColumnMetadata
}

function Get-ColumnMetadata {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory)][object[]] $Data,
        [Parameter(Mandatory)][string[]] $PropertyNames,
        [Parameter(Mandatory)][hashtable] $Config
    )

    if (($Config.Columns -is [hashtable] -or $Config.Columns -is [System.Collections.Specialized.OrderedDictionary]) -and $Config.Columns.Count -gt 0) {
        Write-ModuleLog "Using explicit column mapping from configuration. Automatic type inference is disabled for this step." -Level "INFO"
        return (Get-ColumnMetadataFromExplicitConfig -ColumnsConfig $Config.Columns -PropertyNames $PropertyNames)
    }

    $InferenceSampleSize = if ($Config.InferenceSampleSize) { [int]$Config.InferenceSampleSize } else { 1000 }
    if ($InferenceSampleSize -lt 1) {
        $InferenceSampleSize = 1000
    }

    $DecimalPrecision = if ($Config.DecimalPrecision) { [int]$Config.DecimalPrecision } else { 19 }
    $DecimalScale = if ($Config.DecimalScale) { [int]$Config.DecimalScale } else { 6 }

    $ColumnMetadata = @{}
    foreach ($PropertyName in $PropertyNames) {
        $Samples = New-Object System.Collections.Generic.List[object]
        $SampleCount = 0
        foreach ($Item in $Data) {
            if ($SampleCount -ge $InferenceSampleSize) {
                break
            }

            $Value = $null
            if ($Item -is [System.Data.DataRow]) {
                if ($Item.Table.Columns.Contains($PropertyName)) {
                    $Value = $Item[$PropertyName]
                }
            }
            else {
                $Property = $Item.PSObject.Properties[$PropertyName]
                if ($null -ne $Property) {
                    $Value = $Property.Value
                }
            }

            if ($null -eq $Value -or [string]::IsNullOrWhiteSpace([string]$Value)) {
                continue
            }

            [void]$Samples.Add($Value)
            $SampleCount++
        }

        $SqlType = 'NVARCHAR(MAX)'
        $NetType = [string]

        if ($Samples.Count -gt 0) {
            $IsBool = $true
            $IsInt = $true
            $IsDate = $true
            $IsDecimal = $true

            foreach ($Sample in $Samples) {
                if ($IsBool -and -not (Test-IsBooleanValue -Value $Sample)) { $IsBool = $false }
                if ($IsInt -and -not (Test-IsInt64Value -Value $Sample)) { $IsInt = $false }
                if ($IsDate -and -not (Test-IsDateTimeValue -Value $Sample)) { $IsDate = $false }
                if ($IsDecimal -and -not (Test-IsDecimalValue -Value $Sample)) { $IsDecimal = $false }
            }

            if ($IsBool) {
                $SqlType = 'BIT'
                $NetType = [bool]
            }
            elseif ($IsInt) {
                $SqlType = 'BIGINT'
                $NetType = [int64]
            }
            elseif ($IsDate) {
                $SqlType = 'DATETIME2'
                $NetType = [datetime]
            }
            elseif ($IsDecimal) {
                $SqlType = 'DECIMAL({0},{1})' -f $DecimalPrecision, $DecimalScale
                $NetType = [decimal]
            }
        }

        $ColumnMetadata[$PropertyName] = [PSCustomObject]@{
            Name    = $PropertyName
            SqlName = Get-SafeSqlIdentifier -Name $PropertyName
            SqlType = $SqlType
            NetType = $NetType
        }

        Write-ModuleLog "Column [$PropertyName] mapped to SQL type [$SqlType]." -Level "INFO"
    }

    return $ColumnMetadata
}

function Convert-ToTypedValue {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [AllowNull()][object] $Value,
        [Parameter(Mandatory)][type] $TargetType,
        [Parameter(Mandatory)][string] $ColumnName,
        [Parameter(Mandatory)][hashtable] $ConversionTracking,
        [Parameter(Mandatory)][hashtable] $Config
    )

    if ($null -eq $Value) {
        return [DBNull]::Value
    }

    if ($Value -is [DBNull]) {
        return [DBNull]::Value
    }

    if ($Value -is [string] -and [string]::IsNullOrWhiteSpace([string]$Value)) {
        return [DBNull]::Value
    }

    try {
        if ($TargetType -eq [datetime]) {
            $Converted = Convert-ToDateTimeValue -Value $Value
            if ($Converted -eq [DBNull]::Value) { Add-ConversionFailure -Tracking $ConversionTracking -ColumnName $ColumnName -Config $Config }
            return $Converted
        }

        if ($TargetType -eq [bool]) {
            if ($Value -is [bool]) { return $Value }
            $Text = ([string]$Value).Trim()
            switch ($Text.ToLowerInvariant()) {
                '1'     { return $true }
                '0'     { return $false }
                'true'  { return $true }
                'false' { return $false }
                'yes'   { return $true }
                'no'    { return $false }
                'y'     { return $true }
                'n'     { return $false }
                default {
                    Add-ConversionFailure -Tracking $ConversionTracking -ColumnName $ColumnName -Config $Config
                    return [DBNull]::Value
                }
            }
        }

        if ($TargetType -eq [int64]) {
            $Parsed = 0L
            if ([int64]::TryParse(([string]$Value).Trim(), $Script:IntegerStyles, $Script:InvariantCulture, [ref]$Parsed)) {
                return $Parsed
            }

            Add-ConversionFailure -Tracking $ConversionTracking -ColumnName $ColumnName -Config $Config
            return [DBNull]::Value
        }

        if ($TargetType -eq [decimal]) {
            $Converted = Convert-ToDecimalValue -Value $Value
            if ($Converted -eq [DBNull]::Value) { Add-ConversionFailure -Tracking $ConversionTracking -ColumnName $ColumnName -Config $Config }
            return $Converted
        }

        if ($TargetType -eq [string]) {
            return [string]$Value
        }

        $Converted = $Value -as $TargetType
        if ($null -eq $Converted) {
            Add-ConversionFailure -Tracking $ConversionTracking -ColumnName $ColumnName -Config $Config
            return [DBNull]::Value
        }

        return $Converted
    }
    catch {
        Add-ConversionFailure -Tracking $ConversionTracking -ColumnName $ColumnName -Config $Config
        return [DBNull]::Value
    }
}

function New-DataTable {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory)][System.Collections.IDictionary] $ColumnMetadata
    )

    $DataTable = New-Object System.Data.DataTable
    foreach ($Column in $ColumnMetadata.Values) {
        [void]$DataTable.Columns.Add($Column.Name, $Column.NetType)
    }

    Write-ModuleLog ("Destination batch table created locally with [{0}] columns." -f $DataTable.Columns.Count) -Level 'DEBUG'
    return ,$DataTable
}

function Add-RowToDataTable {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory)][System.Data.DataTable] $DataTable,
        [Parameter(Mandatory)][object] $Row,
        [Parameter(Mandatory)][System.Collections.IDictionary] $ColumnMetadata,
        [Parameter(Mandatory)][hashtable] $ConversionTracking,
        [Parameter(Mandatory)][hashtable] $Config
    )

    $DataRow = $DataTable.NewRow()

    foreach ($Column in $ColumnMetadata.Values) {
        $RawValue = $null
        if ($Row -is [System.Data.DataRow]) {
            if ($Row.Table.Columns.Contains($Column.Name)) {
                $RawValue = $Row[$Column.Name]
            }
        }
        else {
            $Property = $Row.PSObject.Properties[$Column.Name]
            if ($null -ne $Property) {
                $RawValue = $Property.Value
            }
        }

        $TypedValue = Convert-ToTypedValue -Value $RawValue -TargetType $Column.NetType -ColumnName $Column.Name -ConversionTracking $ConversionTracking -Config $Config
        $DataRow[$Column.Name] = $TypedValue
    }

    [void]$DataTable.Rows.Add($DataRow)
}

function Get-NormalizedSqlTypeName {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory)][string] $SqlType
    )

    return (($SqlType -replace '\s+', '')).ToUpperInvariant()
}

function Get-ExistingTargetTableDefinition {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory)][System.Data.SqlClient.SqlConnection] $Connection,
        [Parameter(Mandatory)][string] $SchemaName,
        [Parameter(Mandatory)][string] $TableName
    )

    $Command = $Connection.CreateCommand()
    $Command.CommandTimeout = 120
    $Command.CommandText = @"
SELECT
    c.name AS ColumnName,
    t.name AS SqlTypeName,
    c.max_length AS MaxLength,
    c.precision AS [Precision],
    c.scale AS [Scale]
FROM sys.tables AS st
INNER JOIN sys.schemas AS ss ON ss.schema_id = st.schema_id
INNER JOIN sys.columns AS c ON c.object_id = st.object_id
INNER JOIN sys.types AS t ON t.user_type_id = c.user_type_id
WHERE ss.name = @SchemaName
  AND st.name = @TableName
ORDER BY c.column_id;
"@
    [void]$Command.Parameters.Add('@SchemaName', [System.Data.SqlDbType]::NVarChar, 128)
    [void]$Command.Parameters.Add('@TableName', [System.Data.SqlDbType]::NVarChar, 128)
    $Command.Parameters['@SchemaName'].Value = $SchemaName
    $Command.Parameters['@TableName'].Value = $TableName

    $Adapter = New-Object System.Data.SqlClient.SqlDataAdapter($Command)
    $DataTable = New-Object System.Data.DataTable
    [void]$Adapter.Fill($DataTable)

    if ($DataTable.Rows.Count -eq 0) {
        return $null
    }

    $Columns = @{}
    foreach ($Row in $DataTable.Rows) {
        $BaseType = ([string]$Row.SqlTypeName).Trim().ToUpperInvariant()
        $NormalizedType = switch ($BaseType) {
            'NVARCHAR' {
                if ([int]$Row.MaxLength -eq -1) { 'NVARCHAR(MAX)' } else { 'NVARCHAR({0})' -f ([int]$Row.MaxLength / 2) }
            }
            'VARCHAR' {
                if ([int]$Row.MaxLength -eq -1) { 'VARCHAR(MAX)' } else { 'VARCHAR({0})' -f [int]$Row.MaxLength }
            }
            'NCHAR' { 'NCHAR({0})' -f ([int]$Row.MaxLength / 2) }
            'CHAR' { 'CHAR({0})' -f [int]$Row.MaxLength }
            'DECIMAL' { 'DECIMAL({0},{1})' -f [int]$Row.Precision, [int]$Row.Scale }
            'NUMERIC' { 'NUMERIC({0},{1})' -f [int]$Row.Precision, [int]$Row.Scale }
            default { $BaseType }
        }

        $Columns[[string]$Row.ColumnName] = [PSCustomObject]@{
            Name           = [string]$Row.ColumnName
            SqlType        = $NormalizedType
            SqlTypeBase    = $BaseType
            MaxLength      = [int]$Row.MaxLength
            Precision      = [int]$Row.Precision
            Scale          = [int]$Row.Scale
            NormalizedType = Get-NormalizedSqlTypeName -SqlType $NormalizedType
        }
    }

    return [PSCustomObject]@{
        SchemaName = $SchemaName
        TableName  = $TableName
        Columns    = $Columns
    }
}

function Assert-ExistingTargetTableCompatible {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory)][System.Data.SqlClient.SqlConnection] $Connection,
        [Parameter(Mandatory)][string] $SchemaName,
        [Parameter(Mandatory)][string] $TableName,
        [Parameter(Mandatory)][System.Collections.IDictionary] $ColumnMetadata
    )

    $ExistingDefinition = Get-ExistingTargetTableDefinition -Connection $Connection -SchemaName $SchemaName -TableName $TableName
    if ($null -eq $ExistingDefinition) {
        throw "DropCreate is disabled, but target table [$SchemaName.$TableName] does not exist."
    }

    foreach ($Column in $ColumnMetadata.Values) {
        if (-not $ExistingDefinition.Columns.ContainsKey($Column.Name)) {
            throw "DropCreate is disabled, but target table [$SchemaName.$TableName] is missing required column [$($Column.Name)]."
        }

        $ExistingColumn = $ExistingDefinition.Columns[$Column.Name]
        $ExpectedType = Get-NormalizedSqlTypeName -SqlType ([string]$Column.SqlType)
        if ($ExistingColumn.NormalizedType -ne $ExpectedType) {
            throw "DropCreate is disabled, but target table [$SchemaName.$TableName] column [$($Column.Name)] has incompatible type [$($ExistingColumn.SqlType)]. Expected [$($Column.SqlType)]."
        }
    }

    Write-ModuleLog "Existing target table validation completed successfully: [$SchemaName.$TableName]" -Level 'INFO'
}


function New-TargetTable {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory)][System.Data.SqlClient.SqlConnection] $Connection,
        [Parameter(Mandatory)][string] $QualifiedTableName,
        [Parameter(Mandatory)][string] $SchemaName,
        [Parameter(Mandatory)][string] $TableName,
        [Parameter(Mandatory)][System.Collections.IDictionary] $ColumnMetadata,
        [Parameter(Mandatory)][bool] $DropCreate,
        [System.Data.SqlClient.SqlTransaction] $Transaction
    )

    if (-not $DropCreate) {
        Assert-ExistingTargetTableCompatible -Connection $Connection -SchemaName $SchemaName -TableName $TableName -ColumnMetadata $ColumnMetadata
        Write-ModuleLog "DropCreate disabled. Existing target table will be reused after successful schema validation." -Level "INFO"
        return
    }

    $ColumnDefinitions = foreach ($Column in $ColumnMetadata.Values) {
        "{0} {1}" -f $Column.SqlName, $Column.SqlType
    }

    $QualifiedTableLiteral = Get-SqlLiteral -Value $QualifiedTableName
    $Sql = @"
IF OBJECT_ID($QualifiedTableLiteral, 'U') IS NOT NULL
    DROP TABLE $QualifiedTableName;

CREATE TABLE $QualifiedTableName (
    ImportDate DATETIME2 NOT NULL DEFAULT SYSDATETIME(),
    $($ColumnDefinitions -join ",`r`n    ")
);
"@

    $Command = $Connection.CreateCommand()
    $Command.CommandText = $Sql
    $Command.CommandTimeout = 120
    if ($Transaction) {
        $Command.Transaction = $Transaction
    }

    [void]$Command.ExecuteNonQuery()
    Write-ModuleLog "Target table prepared successfully: [$QualifiedTableName]" -Level "INFO"
}


function Invoke-SqlBulkLoad {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory)][System.Data.SqlClient.SqlConnection] $Connection,
        [Parameter(Mandatory)][string] $QualifiedTableName,
        [Parameter(Mandatory)][System.Data.DataTable] $DataTable,
        [Parameter(Mandatory)][System.Collections.IDictionary] $ColumnMetadata,
        [Parameter(Mandatory)][int] $BulkCopyTimeout,
        [System.Data.SqlClient.SqlTransaction] $Transaction
    )

    if ($DataTable.Rows.Count -eq 0) {
        return
    }

    $BulkCopy = $null
    try {
        if ($Transaction) {
            $BulkCopy = New-Object System.Data.SqlClient.SqlBulkCopy($Connection, [System.Data.SqlClient.SqlBulkCopyOptions]::Default, $Transaction)
        }
        else {
            $BulkCopy = New-Object System.Data.SqlClient.SqlBulkCopy($Connection)
        }

        $BulkCopy.DestinationTableName = $QualifiedTableName
        $BulkCopy.BulkCopyTimeout = $BulkCopyTimeout

        foreach ($Column in $ColumnMetadata.Values) {
            [void]$BulkCopy.ColumnMappings.Add($Column.Name, $Column.Name)
        }

        Write-ModuleLog "Starting SQL bulk copy for [$($DataTable.Rows.Count)] rows into [$QualifiedTableName]..." -Level "INFO"
        $BulkCopy.WriteToServer($DataTable)
        Write-ModuleLog "SQL bulk copy completed successfully for [$($DataTable.Rows.Count)] rows into [$QualifiedTableName]." -Level "INFO"
    }
    finally {
        if ($BulkCopy) {
            $BulkCopy.Close()
            $BulkCopy.Dispose()
        }
    }
}


function Initialize-StreamingLoadState {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory)][hashtable] $Config
    )

    $SchemaName = if ($Config.Schema) { [string]$Config.Schema } else { 'dbo' }
    $TableName = [string]$Config.TableName
    $BatchSize = if ($Config.BatchSize) { [int]$Config.BatchSize } else { 5000 }
    $InferenceSampleSize = if ($Config.InferenceSampleSize) { [int]$Config.InferenceSampleSize } else { 1000 }
    $BulkCopyTimeout = if ($Config.BulkCopyTimeout) { [int]$Config.BulkCopyTimeout } else { 600 }
    $DropCreate = if ($null -ne $Config.DropCreate) { [System.Convert]::ToBoolean($Config.DropCreate) } else { $true }

    if ($BatchSize -lt 1) { $BatchSize = 5000 }
    if ($InferenceSampleSize -lt 1) { $InferenceSampleSize = 1000 }

    $QualifiedTableName = "{0}.{1}" -f (Get-SafeSqlIdentifier -Name $SchemaName), (Get-SafeSqlIdentifier -Name $TableName)
    $RunIdentifier = if (-not [string]::IsNullOrWhiteSpace($env:ETL_RUN_ID)) { [string]$env:ETL_RUN_ID } else { (Get-Date -Format 'yyyyMMdd_HHmmss') }
    $StageToken = (($RunIdentifier -replace '[^A-Za-z0-9_]', '_') + '_' + ([guid]::NewGuid().ToString('N').Substring(0,8)))
    $StagingTableName = "__ETL_STAGE_{0}_{1}" -f (($TableName -replace '[^A-Za-z0-9_]', '_')), $StageToken
    $QualifiedStagingTableName = "{0}.{1}" -f (Get-SafeSqlIdentifier -Name $SchemaName), (Get-SafeSqlIdentifier -Name $StagingTableName)

    return @{
        SchemaName                = $SchemaName
        TableName                 = $TableName
        QualifiedTableName        = $QualifiedTableName
        BatchSize                 = $BatchSize
        InferenceSampleSize       = $InferenceSampleSize
        BulkCopyTimeout           = $BulkCopyTimeout
        DropCreate                = $DropCreate
        UseStagingTable           = $DropCreate
        StagingTableName          = $StagingTableName
        QualifiedStagingTableName = $QualifiedStagingTableName
        ActiveLoadTableName       = if ($DropCreate) { $QualifiedStagingTableName } else { $QualifiedTableName }
        SampleBuffer              = New-Object 'System.Collections.Generic.List[object]'
        BatchTable                = $null
        ColumnMetadata            = $null
        PropertyNames             = @($Config._PipelineProperties)
        ConversionTracking        = $null
        Connection                = $null
        Transaction               = $null
        RowsReceived              = 0
        RowsLoaded                = 0
        BatchesWritten            = 0
        StagingSwapCompleted      = $false
    }
}

function Start-SqlTransactionIfNeeded {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory)][System.Collections.IDictionary] $State
    )

    if ($null -ne $State.Transaction -or $null -eq $State.Connection -or $State.UseStagingTable) {
        return
    }

    $State.Transaction = $State.Connection.BeginTransaction()
    Write-ModuleLog "SQL transaction started for target [$($State.QualifiedTableName)]." -Level "INFO"
}

function Complete-StagingSwap {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory)][System.Collections.IDictionary] $State
    )

    if (-not $State.UseStagingTable -or $State.StagingSwapCompleted) {
        return
    }

    $Transaction = $State.Connection.BeginTransaction()
    try {
        $SwapCommand = $State.Connection.CreateCommand()
        $SwapCommand.Transaction = $Transaction
        $SwapCommand.CommandTimeout = 120
        $SwapCommand.CommandText = @"
IF OBJECT_ID($(Get-SqlLiteral -Value $State.QualifiedTableName), 'U') IS NOT NULL
    DROP TABLE $($State.QualifiedTableName);

EXEC sp_rename $(Get-SqlLiteral -Value ($State.SchemaName + '.' + $State.StagingTableName)), $(Get-SqlLiteral -Value $State.TableName);
"@
        [void]$SwapCommand.ExecuteNonQuery()
        $Transaction.Commit()
        $State.StagingSwapCompleted = $true
        Write-ModuleLog "Staging table promoted successfully to final target [$($State.QualifiedTableName)]." -Level "INFO"
    }
    catch {
        try { $Transaction.Rollback() } catch { Write-ModuleLog "Rollback failed after staging swap error: $($_.Exception.Message)" -Level 'WARN' }
        throw
    }
}

function Remove-StagingTableIfPresent {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory)][System.Collections.IDictionary] $State
    )

    if (-not $State.UseStagingTable -or $State.StagingSwapCompleted -or $null -eq $State.Connection) {
        return
    }

    try {
        $DropCommand = $State.Connection.CreateCommand()
        $DropCommand.CommandTimeout = 120
        $DropCommand.CommandText = @"
IF OBJECT_ID($(Get-SqlLiteral -Value $State.QualifiedStagingTableName), 'U') IS NOT NULL
    DROP TABLE $($State.QualifiedStagingTableName);
"@
        [void]$DropCommand.ExecuteNonQuery()
        Write-ModuleLog "Removed staging table after failed or aborted load: [$($State.QualifiedStagingTableName)]" -Level "WARN"
    }
    catch {
        Write-ModuleLog "Failed to remove staging table [$($State.QualifiedStagingTableName)]: $($_.Exception.Message)" -Level "WARN"
    }
}


function Open-StreamingLoadIfNeeded {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory)][System.Collections.IDictionary] $State,
        [Parameter(Mandatory)][hashtable] $Config
    )

    if ($null -ne $State.Connection) {
        return
    }

    $State.Connection = New-SqlConnection -Config $Config
    $State.Connection.Open()

    Write-ModuleLog "SQL connection opened successfully." -Level "INFO"
    if ($State.UseStagingTable) {
        New-TargetTable -Connection $State.Connection -QualifiedTableName $State.ActiveLoadTableName -SchemaName $State.SchemaName -TableName $State.StagingTableName -ColumnMetadata $State.ColumnMetadata -DropCreate $true -Transaction $null
        Write-ModuleLog "DropCreate enabled. Data will be loaded into a staging table and promoted only after a successful run." -Level "INFO"
    }
    else {
        Assert-ExistingTargetTableCompatible -Connection $State.Connection -SchemaName $State.SchemaName -TableName $State.TableName -ColumnMetadata $State.ColumnMetadata
        Start-SqlTransactionIfNeeded -State $State
        Write-ModuleLog "DropCreate disabled. Existing target table will be loaded inside a single SQL transaction." -Level "INFO"
    }

    $BatchTable = New-DataTable -ColumnMetadata $State.ColumnMetadata
    if ($null -eq $BatchTable) {
        throw "Failed to initialize destination batch table after opening SQL connection."
    }
    if ($BatchTable -isnot [System.Data.DataTable]) {
        throw "Destination batch table initialization returned unexpected type: [$($BatchTable.GetType().FullName)]"
    }
    $State['BatchTable'] = $BatchTable
    Write-ModuleLog ("Destination batch table initialized with [{0}] columns." -f $State.BatchTable.Columns.Count) -Level "INFO"
}

function Finalize-MetadataIfNeeded {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory)][System.Collections.IDictionary] $State,
        [Parameter(Mandatory)][hashtable] $Config
    )

    if ($null -ne $State.ColumnMetadata) {
        return
    }

    if ($State.SampleBuffer.Count -eq 0) {
        return
    }

    $State.PropertyNames = Get-PropertyNamesFromRows -InputRows $State.SampleBuffer.ToArray() -SeedNames @($State.PropertyNames)
    Write-ModuleLog ("Destination MSSQL inferred input columns: {0}" -f ($State.PropertyNames -join ', ')) -Level "INFO"
    Write-ModuleLog ("Destination MSSQL first buffered row preview: {0}" -f (Get-EtlObjectPreview -InputObject $State.SampleBuffer[0])) -Level "INFO"
    $State.ColumnMetadata = Get-ColumnMetadata -Data $State.SampleBuffer.ToArray() -PropertyNames $State.PropertyNames -Config $Config
    $State.ConversionTracking = Initialize-ConversionTracking -PropertyNames $State.PropertyNames
    Write-ModuleLog ("Destination MSSQL column metadata: {0}" -f (($State.ColumnMetadata.Values | ForEach-Object { "{0}:{1}" -f $_.Name, $_.SqlType }) -join ', ')) -Level "INFO"
    Open-StreamingLoadIfNeeded -State $State -Config $Config
    if ($null -eq $State.BatchTable) {
        throw "Destination batch table is null after metadata initialization. RowsReceived=$($State.RowsReceived) SampleBuffer=$($State.SampleBuffer.Count) Columns=$($State.PropertyNames -join ', ')"
    }

    foreach ($BufferedRow in $State.SampleBuffer.ToArray()) {
        if ($null -eq $State.BatchTable) {
            throw "Destination batch table is null while replaying buffered sample rows."
        }
        Add-RowToDataTable -DataTable $State.BatchTable -Row $BufferedRow -ColumnMetadata $State.ColumnMetadata -ConversionTracking $State.ConversionTracking -Config $Config
        if ($State.BatchTable.Rows.Count -ge $State.BatchSize) {
            Invoke-SqlBulkLoad -Connection $State.Connection -QualifiedTableName $State.ActiveLoadTableName -DataTable $State.BatchTable -ColumnMetadata $State.ColumnMetadata -BulkCopyTimeout $State.BulkCopyTimeout -Transaction $State.Transaction
            $State.RowsLoaded += $State.BatchTable.Rows.Count
            $State.BatchesWritten++
            Write-ModuleLog ("MSSQL destination flushed batch [{0}] during buffered replay. Rows loaded total: [{1}]" -f $State.BatchesWritten, $State.RowsLoaded) -Level "INFO"
            $State.BatchTable.Clear()
        }
    }

    $State.SampleBuffer.Clear()
}

function Invoke-Load {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [object] $Data,

        [Parameter(Mandatory = $true)]
        [hashtable] $Config
    )

    begin {
        if (-not (Test-LoadConfiguration -Config $Config)) {
            throw "Destination MSSQL configuration is invalid."
        }

        Assert-NonInteractiveSqlConnectionAllowed -Config $Config
        $State = Initialize-StreamingLoadState -Config $Config
        Write-ModuleLog "Preparing MSSQL load for target [$($State.QualifiedTableName)]" -Level "INFO"
        Write-ModuleLog "Target schema resolved to [$($State.SchemaName)]" -Level "DEBUG"
        Write-ModuleLog "Target table resolved to [$($State.TableName)]" -Level "DEBUG"
        Write-ModuleLog "MSSQL authentication mode: $(Get-AuthenticationMode -Config $Config)" -Level "DEBUG"
        Write-ModuleLog "DropCreate mode: [$($State.DropCreate)]" -Level "DEBUG"
        Write-ModuleLog "BatchSize resolved to [$($State.BatchSize)] rows" -Level "INFO"
        Write-ModuleLog "InferenceSampleSize resolved to [$($State.InferenceSampleSize)] rows" -Level "INFO"
        Write-ModuleLog ("FailOnConversionError: [{0}] | MaxConversionErrorsPerColumn: [{1}]" -f $(if ($null -ne $Config.FailOnConversionError) { [System.Convert]::ToBoolean($Config.FailOnConversionError) } else { $false }), $(if ($Config.MaxConversionErrorsPerColumn) { [int]$Config.MaxConversionErrorsPerColumn } else { 10 })) -Level "INFO"
    }

    process {
        if ($null -eq $Data) {
            return
        }

        $State.RowsReceived++

        if ($State.RowsReceived -eq 1) {
            Write-ModuleLog ("First destination input row preview: {0}" -f (Get-EtlObjectPreview -InputObject $Data)) -Level "INFO"
        }

        if ($null -eq $State.ColumnMetadata) {
            [void]$State.SampleBuffer.Add($Data)
            if ($State.SampleBuffer.Count -eq 1) {
                Write-ModuleLog "MSSQL destination started buffering input rows for metadata inference." -Level "INFO"
            }
            if ($State.SampleBuffer.Count -ge $State.InferenceSampleSize) {
                Write-ModuleLog ("MSSQL destination reached inference sample size [{0}]. Finalizing metadata." -f $State.SampleBuffer.Count) -Level "INFO"
                Write-ModuleLog ("Finalizing MSSQL destination metadata with RowsReceived=[{0}] and SampleBuffer=[{1}]" -f $State.RowsReceived, $State.SampleBuffer.Count) -Level "INFO"
            Finalize-MetadataIfNeeded -State $State -Config $Config
            }
            return
        }

        if ($null -eq $State.BatchTable) {
            throw "Destination batch table is null before processing streaming input row. RowsReceived=$($State.RowsReceived)"
        }
        Add-RowToDataTable -DataTable $State.BatchTable -Row $Data -ColumnMetadata $State.ColumnMetadata -ConversionTracking $State.ConversionTracking -Config $Config
        if ($State.BatchTable.Rows.Count -ge $State.BatchSize) {
            Invoke-SqlBulkLoad -Connection $State.Connection -QualifiedTableName $State.ActiveLoadTableName -DataTable $State.BatchTable -ColumnMetadata $State.ColumnMetadata -BulkCopyTimeout $State.BulkCopyTimeout -Transaction $State.Transaction
            $State.RowsLoaded += $State.BatchTable.Rows.Count
            $State.BatchesWritten++
            Write-ModuleLog ("MSSQL destination flushed batch [{0}] from streaming input. Rows loaded total: [{1}]" -f $State.BatchesWritten, $State.RowsLoaded) -Level "INFO"
            $State.BatchTable.Clear()
        }
    }

    end {
        try {
            if ($State.RowsReceived -eq 0) {
                if (($Config.Columns -is [hashtable] -or $Config.Columns -is [System.Collections.Specialized.OrderedDictionary]) -and $Config.Columns.Count -gt 0) {
                    if (-not $State.PropertyNames -or $State.PropertyNames.Count -eq 0) {
                        $State.PropertyNames = @($Config.Columns.Keys)
                    }
                    $State.ColumnMetadata = Get-ColumnMetadataFromExplicitConfig -ColumnsConfig $Config.Columns -PropertyNames $State.PropertyNames
                    $State.ConversionTracking = Initialize-ConversionTracking -PropertyNames $State.PropertyNames
                    Write-ModuleLog 'No input data received. Preparing empty target table from explicit MSSQL column configuration.' -Level 'WARN'
                    Open-StreamingLoadIfNeeded -State $State -Config $Config
                    if ($State.UseStagingTable) {
                        Complete-StagingSwap -State $State
                    }
                    elseif ($State.Transaction) {
                        $State.Transaction.Commit()
                        Write-ModuleLog "SQL transaction committed successfully for target [$($State.QualifiedTableName)]." -Level 'INFO'
                    }
                    Write-ConversionSummary -Tracking $State.ConversionTracking -Config $Config
                    Write-ModuleLog 'MSSQL load completed with zero rows. Target table was prepared from explicit column configuration.' -Level 'WARN'
                    return
                }

                if ($State.PropertyNames -and $State.PropertyNames.Count -gt 0) {
                    $State.ColumnMetadata = Get-ColumnMetadataFromPropertyNames -PropertyNames $State.PropertyNames
                    $State.ConversionTracking = Initialize-ConversionTracking -PropertyNames $State.PropertyNames
                    Write-ModuleLog 'No input data received. Preparing empty target table from configured pipeline properties using fallback type NVARCHAR(MAX).' -Level 'WARN'
                    Open-StreamingLoadIfNeeded -State $State -Config $Config
                    if ($State.UseStagingTable) {
                        Complete-StagingSwap -State $State
                    }
                    elseif ($State.Transaction) {
                        $State.Transaction.Commit()
                        Write-ModuleLog "SQL transaction committed successfully for target [$($State.QualifiedTableName)]." -Level 'INFO'
                    }
                    Write-ConversionSummary -Tracking $State.ConversionTracking -Config $Config
                    Write-ModuleLog 'MSSQL load completed with zero rows. Target table was prepared from pipeline properties using fallback type NVARCHAR(MAX).' -Level 'WARN'
                    return
                }

                Write-ModuleLog 'No input data received. Load step skipped because no rows and no explicit/pipeline column definition were available.' -Level 'WARN'
                return
            }

            Write-ModuleLog ("Finalizing MSSQL destination metadata with RowsReceived=[{0}] and SampleBuffer=[{1}]" -f $State.RowsReceived, $State.SampleBuffer.Count) -Level "INFO"
            Finalize-MetadataIfNeeded -State $State -Config $Config

            if ($State.BatchTable -and $State.BatchTable.Rows.Count -gt 0) {
                Invoke-SqlBulkLoad -Connection $State.Connection -QualifiedTableName $State.ActiveLoadTableName -DataTable $State.BatchTable -ColumnMetadata $State.ColumnMetadata -BulkCopyTimeout $State.BulkCopyTimeout -Transaction $State.Transaction
                $State.RowsLoaded += $State.BatchTable.Rows.Count
                $State.BatchesWritten++
                Write-ModuleLog ("MSSQL destination flushed final batch [{0}]. Rows loaded total: [{1}]" -f $State.BatchesWritten, $State.RowsLoaded) -Level "INFO"
                $State.BatchTable.Clear()
            }

            if ($State.UseStagingTable) {
                Complete-StagingSwap -State $State
            }
            elseif ($State.Transaction) {
                $State.Transaction.Commit()
                Write-ModuleLog "SQL transaction committed successfully for target [$($State.QualifiedTableName)]." -Level "INFO"
            }

            Write-ConversionSummary -Tracking $State.ConversionTracking -Config $Config
            Write-ModuleLog "MSSQL load completed successfully. Rows received: [$($State.RowsReceived)] | Rows loaded: [$($State.RowsLoaded)] | Bulk batches: [$($State.BatchesWritten)] | Active target: [$($State.ActiveLoadTableName)]" -Level "INFO"
        }
        catch {
            if ($State.Transaction) {
                try {
                    $State.Transaction.Rollback()
                    Write-ModuleLog "SQL transaction rolled back for target [$($State.QualifiedTableName)]." -Level "WARN"
                }
                catch {
                    Write-ModuleLog "Failed to roll back SQL transaction: $($_.Exception.Message)" -Level "WARN"
                }
            }

            Write-ModuleLog ("Destination MSSQL state snapshot: RowsReceived=[{0}] | RowsLoaded=[{1}] | SampleBuffer=[{2}] | BatchTableNull=[{3}] | ColumnMetadataNull=[{4}] | ActiveTarget=[{5}]" -f $State.RowsReceived, $State.RowsLoaded, $State.SampleBuffer.Count, ($null -eq $State.BatchTable), ($null -eq $State.ColumnMetadata), $State.ActiveLoadTableName) -Level 'ERROR'
            Write-EtlExceptionDetails -Context $Script:ModuleContext -ErrorRecord $_ -Prefix 'SQL load failed:'
            throw
        }
        finally {
            Remove-StagingTableIfPresent -State $State

            if ($State.Transaction) {
                $State.Transaction.Dispose()
            }

            if ($State.Connection) {
                $State.Connection.Close()
                $State.Connection.Dispose()
                Write-ModuleLog "SQL destination connection disposed." -Level "DEBUG"
            }
        }
    }
}

Export-ModuleMember -Function Invoke-Load
