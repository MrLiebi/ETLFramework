<#
.SYNOPSIS
ETL source adapter for MSSQL.

.DESCRIPTION
Extracts data from MSSQL and returns it as a structured
collection of PowerShell objects for further processing in the
ETL pipeline.

This module implements the Invoke-Extract entry point used by
the ETL runtime.

.VERSION
23.1.0

.AUTHOR
ETL Framework

.OUTPUTS
System.Object[]

.NOTES
- Entry point: Invoke-Extract
- Must return objects via pipeline
- Used by Run-ETL.ps1 during extract phase
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

function Test-ExtractConfiguration {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][hashtable] $Config
    )

    try {
        if (-not $Config.ConnectionString -and -not $Config.Server) {
            throw "Missing source config value: ConnectionString or Server"
        }

        if (-not $Config.ConnectionString -and -not $Config.Database) {
            throw "Missing source config value: Database when ConnectionString is not used"
        }

        if (-not $Config.Query) {
            throw "Missing source config value: Query"
        }

        if ($Config.AuthenticationMode -eq 'CredentialManager' -and -not $Config.CredentialTarget) {
            throw "Missing source config value: CredentialTarget when AuthenticationMode is CredentialManager"
        }

        Write-ModuleLog "Source MSSQL configuration validated successfully." -Level "DEBUG"
        return $true
    }
    catch {
        Write-ModuleLog "Source MSSQL configuration validation failed: $($_.Exception.Message)" -Level "ERROR"
        return $false
    }
}

function Get-AuthenticationMode {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][hashtable] $Config
    )

    Get-EtlAuthenticationMode -Config $Config
}

function Get-SqlConnectionCredential {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][hashtable] $Config
    )

    $AuthenticationMode = Get-AuthenticationMode -Config $Config

    if ($AuthenticationMode -ne 'CredentialManager') {
        return $null
    }

    if ([string]::IsNullOrWhiteSpace([string]$Config.CredentialTarget)) {
        throw "Missing source config value: CredentialTarget for AuthenticationMode=CredentialManager"
    }

    Import-EtlCredentialSupport -ModuleRoot $PSScriptRoot
    return Get-StoredCredential -Target ([string]$Config.CredentialTarget)
}

function Get-SqlConnectionString {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][hashtable] $Config
    )

    if ($Config.ConnectionString) {
        return [string]$Config.ConnectionString
    }

    $AuthenticationMode = Get-AuthenticationMode -Config $Config

    if ($AuthenticationMode -eq 'CredentialManager') {
        return "Server={0};Database={1};Persist Security Info=False;" -f $Config.Server, $Config.Database
    }

    return "Server={0};Database={1};Integrated Security=True;" -f $Config.Server, $Config.Database
}

function ConvertTo-SecurePasswordForSql {
    [CmdletBinding()]
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
    [CmdletBinding()]
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
    [CmdletBinding()]
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

    throw "Non-interactive test mode blocked MSSQL source connection to server [$ServerName]. Set ETL_ALLOW_DB_CONNECTIONS=1 to override."
}

function Invoke-Extract {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable] $Config,

        [Parameter(Mandatory = $true)]
        [string[]] $Properties
    )

    if (-not (Test-ExtractConfiguration -Config $Config)) {
        throw "Source MSSQL configuration is invalid."
    }

    $Connection = $null
    $Reader = $null
    $Command = $null

    try {
        Assert-NonInteractiveSqlConnectionAllowed -Config $Config
        $SelectedProperties = Get-ValidatedPropertySelection -Properties $Properties

        Write-ModuleLog "Opening MSSQL source connection..." -Level "INFO"
        Write-ModuleLog "MSSQL source mode: $(if ($Config.ConnectionString) { 'ConnectionString' } else { 'Server/Database' })" -Level "DEBUG"
        Write-ModuleLog "MSSQL authentication mode: $(Get-AuthenticationMode -Config $Config)" -Level "DEBUG"
        Write-ModuleLog "Property selection mode: $(if ($SelectedProperties -and $SelectedProperties -notcontains '*') { 'Explicit' } else { 'All columns' })" -Level "DEBUG"

        $Connection = New-SqlConnection -Config $Config
        $Command = $Connection.CreateCommand()
        $Command.CommandText = [string]$Config.Query
        $Command.CommandTimeout = if ($Config.CommandTimeout) { [int]$Config.CommandTimeout } else { 600 }

        Write-ModuleLog "MSSQL source command timeout: $($Command.CommandTimeout) seconds" -Level "DEBUG"
        Write-ModuleLog "Configured query length: $($Command.CommandText.Length) characters" -Level "DEBUG"
        $QueryPreview = ($Command.CommandText -replace '\s+', ' ')
        if ($QueryPreview.Length -gt 160) { $QueryPreview = $QueryPreview.Substring(0,160) + '...' }
        Write-ModuleLog ("MSSQL query preview: {0}" -f $QueryPreview) -Level "INFO"

        $Connection.Open()
        Write-ModuleLog "MSSQL source connection opened successfully." -Level "INFO"

        $Reader = $Command.ExecuteReader()

        $AvailableColumns = for ($i = 0; $i -lt $Reader.FieldCount; $i++) { $Reader.GetName($i) }
        $ColumnOrdinalMap = @{}
        for ($i = 0; $i -lt $Reader.FieldCount; $i++) { $ColumnOrdinalMap[$Reader.GetName($i)] = $i }
        $ColumnsToRead = New-Object System.Collections.Generic.List[string]

        if ($SelectedProperties -contains '*') {
            foreach ($ColumnName in $AvailableColumns) {
                [void]$ColumnsToRead.Add($ColumnName)
            }
        }
        else {
            foreach ($Property in $SelectedProperties) {
                if ($AvailableColumns -contains $Property) {
                    [void]$ColumnsToRead.Add($Property)
                }
                else {
                    Write-ModuleLog "Requested SQL result column '$Property' not found. Column will be returned as null." -Level "WARN"
                    [void]$ColumnsToRead.Add($Property)
                }
            }
        }

        Write-ModuleLog "MSSQL extract streaming initialized. Reader columns: $($AvailableColumns.Count) | Selected columns: $($ColumnsToRead.Count)" -Level "INFO"

        $RowsRead = 0
        $PreviewLogged = $false
        while ($Reader.Read()) {
            $RowsRead++
            $Object = [ordered]@{}

            foreach ($ColumnName in $ColumnsToRead) {
                $Ordinal = if ($ColumnOrdinalMap.ContainsKey($ColumnName)) { [int]$ColumnOrdinalMap[$ColumnName] } else { -1 }
                if ($Ordinal -lt 0 -or $Reader.IsDBNull($Ordinal)) {
                    $Object[$ColumnName] = $null
                }
                else {
                    $Object[$ColumnName] = $Reader.GetValue($Ordinal)
                }
            }

            $OutputObject = [PSCustomObject]$Object
            if (-not $PreviewLogged) {
                Write-ModuleLog ("First MSSQL source row preview: {0}" -f (Get-EtlObjectPreview -InputObject $OutputObject)) -Level "INFO"
                $PreviewLogged = $true
            }
            $OutputObject
        }

        if ($RowsRead -eq 0) {
            Write-ModuleLog "Query returned zero rows. Streaming extract returned an empty result set." -Level "WARN"
        }
        else {
            Write-ModuleLog "MSSQL extract completed successfully. Rows streamed: $RowsRead" -Level "INFO"
        }
    }
    catch {
        Write-EtlExceptionDetails -Context $Script:ModuleContext -ErrorRecord $_ -Prefix 'MSSQL extract failed:'
        throw
    }
    finally {
        if ($Reader) {
            $Reader.Close()
            $Reader.Dispose()
        }

        if ($Command) {
            $Command.Dispose()
        }

        if ($Connection) {
            $Connection.Close()
            $Connection.Dispose()
            Write-ModuleLog "MSSQL source connection disposed." -Level "DEBUG"
        }
    }
}

Export-ModuleMember -Function Invoke-Extract
