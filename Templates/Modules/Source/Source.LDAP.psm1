<#
.SYNOPSIS
ETL source adapter for LDAP.

.DESCRIPTION
Extracts data from LDAP and returns it as a structured
collection of PowerShell objects for further processing in the
ETL pipeline.

This module implements the Invoke-Extract entry point used by
the ETL runtime.

.VERSION
22.0.0

.AUTHOR
ETL Framework

.OUTPUTS
System.Object[]

.NOTES
- Entry point: Invoke-Extract
- Must return a collection of objects
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

try {
    Add-Type -AssemblyName "System.DirectoryServices.Protocols" -ErrorAction Stop
}
catch {
    $CandidateAssemblyPaths = @(
        'C:\Windows\Microsoft.NET\Framework64\v4.0.30319\System.DirectoryServices.Protocols.dll',
        'C:\Windows\Microsoft.NET\Framework\v4.0.30319\System.DirectoryServices.Protocols.dll'
    )

    $Loaded = $false
    foreach ($CandidateAssemblyPath in $CandidateAssemblyPaths) {
        if (-not (Test-Path -Path $CandidateAssemblyPath -PathType Leaf)) { continue }
        try {
            Add-Type -Path $CandidateAssemblyPath -ErrorAction Stop
            $Loaded = $true
            break
        }
        catch {
            Write-ModuleLog "Optional LDAP assembly probe failed: $($_.Exception.Message)" -Level "DEBUG"
        }
    }

    if (-not $Loaded) {
        throw "Failed to load System.DirectoryServices.Protocols. Is .NET Framework installed?"
    }
}


function Test-ExtractConfiguration {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][hashtable] $Config
    )

    try {
        if (-not $Config.Server) {
            throw "Missing source config value: Server"
        }

        if (-not $Config.SearchBase) {
            throw "Missing source config value: SearchBase"
        }

        if (-not $Config.Filter) {
            throw "Missing source config value: Filter"
        }

        if ($Config.AuthenticationMode -eq 'CredentialManager' -and -not $Config.CredentialTarget) {
            throw "Missing source config value: CredentialTarget when AuthenticationMode is CredentialManager"
        }

        Write-ModuleLog "Source LDAP configuration validated successfully." -Level "DEBUG"
        return $true
    }
    catch {
        Write-ModuleLog "Source LDAP configuration validation failed: $($_.Exception.Message)" -Level "ERROR"
        return $false
    }
}

function Get-ValidatedLdapProperties {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string[]] $Properties
    )

    $Validated = @(
        $Properties |
            Where-Object { $null -ne $_ } |
            ForEach-Object { [string]$_ } |
            ForEach-Object { $_.Trim() } |
            Where-Object { $_ -ne '' }
    )

    if (-not $Validated -or $Validated.Count -eq 0) {
        return @('*')
    }

    if ($Validated -contains '*') {
        return @('*')
    }

    return $Validated
}

function Convert-ADFileTime {
    [CmdletBinding()]
    param(
        [AllowNull()][object] $Value
    )

    if ($null -eq $Value) {
        return $null
    }

    try {
        $Ticks = [int64]$Value

        if ($Ticks -le 0 -or $Ticks -eq [int64]::MaxValue) {
            return $null
        }

        return [datetime]::FromFileTimeUtc($Ticks).ToString("yyyy-MM-dd HH:mm:ss")
    }
    catch {
        return $null
    }
}

function Convert-LdapValue {
    [CmdletBinding()]
    param(
        [AllowNull()][object] $Value,
        [Parameter(Mandatory)][string] $AttributeName
    )

    if ($null -eq $Value) {
        return $null
    }

    if ($AttributeName -in @("objectGuid", "guid")) {
        try {
            if ($Value -is [byte[]]) {
                return ([guid]$Value).ToString()
            }

            return ([string]$Value).Trim()
        }
        catch {
            return ([string]$Value).Trim()
        }
    }

    if ($AttributeName -eq "objectSid") {
        try {
            if ($Value -is [byte[]]) {
                return (New-Object System.Security.Principal.SecurityIdentifier($Value, 0)).Value
            }

            return ([string]$Value).Trim()
        }
        catch {
            return ([string]$Value).Trim()
        }
    }

    if ($AttributeName -in @(
        'lastLogonTimestamp',
        'lastLogon',
        'pwdLastSet',
        'accountExpires',
        'badPasswordTime',
        'lastLogoff',
        'lockoutTime',
        'creationTime'
    )) {
        $ConvertedTime = Convert-ADFileTime -Value $Value
        if ($null -ne $ConvertedTime) {
            return $ConvertedTime
        }
    }

    if ($Value -is [byte[]]) {
        try {
            return [System.Text.Encoding]::UTF8.GetString($Value).TrimEnd([char]0)
        }
        catch {
            return [System.BitConverter]::ToString($Value)
        }
    }

    return ([string]$Value).Trim()
}

function Get-AuthenticationMode {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][hashtable] $Config
    )

    Get-EtlAuthenticationMode -Config $Config
}

function Assert-NonInteractiveLdapConnectionAllowed {
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
    $AllowedServers = @('localhost', '127.0.0.1', '::1')
    if ($AllowedServers -contains $NormalizedServer) {
        return
    }

    throw "Non-interactive test mode blocked LDAP connection to server [$ServerName]. Set ETL_ALLOW_DB_CONNECTIONS=1 to override."
}

function Connect-LdapServer {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][hashtable] $Config,
        [int] $TimeoutSeconds = 120
    )

    Assert-NonInteractiveLdapConnectionAllowed -Config $Config
    $Server = [string]$Config.Server
    Write-ModuleLog "Connecting to LDAP server: $Server" -Level "DEBUG"

    $Identifier = New-Object System.DirectoryServices.Protocols.LdapDirectoryIdentifier($Server)
    $Ldap = New-Object System.DirectoryServices.Protocols.LdapConnection($Identifier)
    $Ldap.AuthType = [System.DirectoryServices.Protocols.AuthType]::Negotiate
    $Ldap.Timeout  = New-TimeSpan -Seconds $TimeoutSeconds
    $Ldap.SessionOptions.ReferralChasing = [System.DirectoryServices.Protocols.ReferralChasingOptions]::External
    $Ldap.SessionOptions.ProtocolVersion = 3

    $AuthenticationMode = Get-AuthenticationMode -Config $Config

    if ($AuthenticationMode -eq 'CredentialManager') {
        if ([string]::IsNullOrWhiteSpace([string]$Config.CredentialTarget)) {
            throw "Missing source config value: CredentialTarget when AuthenticationMode is CredentialManager"
        }

        Import-EtlCredentialSupport -ModuleRoot $PSScriptRoot
        $Credential = Get-StoredCredential -Target ([string]$Config.CredentialTarget) -AsNetworkCredential
        $Ldap.Credential = $Credential
        Write-ModuleLog "LDAP authentication mode: CredentialManager" -Level "DEBUG"
    }
    else {
        Write-ModuleLog "LDAP authentication mode: Integrated" -Level "DEBUG"
    }

    try {
        $Ldap.Bind()
        Write-ModuleLog "LDAP bind successful for server: $Server" -Level "INFO"
    }
    catch {
        throw "LDAP bind failed for $Server : $($_.Exception.Message)"
    }

    return $Ldap
}

function Resolve-LdapAttributeName {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] $Entry,
        [Parameter(Mandatory)][string] $RequestedName
    )

    foreach ($ExistingName in $Entry.Attributes.AttributeNames) {
        if ([string]::Equals([string]$ExistingName, $RequestedName, [System.StringComparison]::OrdinalIgnoreCase)) {
            return [string]$ExistingName
        }
    }

    return $null
}

function Get-EntryMetaValue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] $Entry,
        [Parameter(Mandatory)][string] $RequestedName
    )

    if ([string]::Equals($RequestedName, 'distinguishedName', [System.StringComparison]::OrdinalIgnoreCase)) {
        try { return $Entry.DistinguishedName } catch { return $null }
    }

    return $null
}

function Get-LdapEntrySnapshot {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] $Entry
    )

    $Dn = $null
    try { $Dn = $Entry.DistinguishedName } catch { $Dn = '<unknown>' }

    $AttributeNames = @()
    try {
        $AttributeNames = @($Entry.Attributes.AttributeNames | ForEach-Object { [string]$_ } | Sort-Object)
    }
    catch { Write-ModuleLog "LDAP snapshot capture skipped: $($_.Exception.Message)" -Level "DEBUG" }

    [PSCustomObject]@{
        DistinguishedName = $Dn
        AttributeCount    = $AttributeNames.Count
        AttributeNames    = $AttributeNames
    }
}

function Get-LdapEntryByDn {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][System.DirectoryServices.Protocols.LdapConnection] $LdapConn,
        [Parameter(Mandatory)][string] $EntryDn,
        [Parameter(Mandatory)][string[]] $Properties,
        [Parameter(Mandatory)][int] $TimeoutSeconds
    )

    $Request = New-Object System.DirectoryServices.Protocols.SearchRequest(
        $EntryDn,
        '(objectClass=*)',
        [System.DirectoryServices.Protocols.SearchScope]::Base,
        $Properties
    )

    $Request.SizeLimit = 1
    $Request.TimeLimit = New-TimeSpan -Seconds $TimeoutSeconds

    $Response = $LdapConn.SendRequest($Request)
    if ($Response.Entries.Count -gt 0) {
        return $Response.Entries[0]
    }

    return $null
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
        throw "Source LDAP configuration is invalid."
    }

    $SearchBase         = $Config.SearchBase
    $Filter             = $Config.Filter
    $PageSize           = if ($Config.PageSize) { [int]$Config.PageSize } else { 1000 }
    $TimeoutSeconds     = if ($Config.TimeoutSeconds) { [int]$Config.TimeoutSeconds } else { 120 }
    $SelectedProperties = Get-ValidatedLdapProperties -Properties $Properties

    $LdapConn = Connect-LdapServer -Config $Config -TimeoutSeconds $TimeoutSeconds
    $Cookie   = [byte[]]@()
    $Scope    = [System.DirectoryServices.Protocols.SearchScope]::Subtree
    $Total    = 0
    $ReloadFallbackCount = 0
    $PreviewLogged = $false

    Write-ModuleLog "Starting LDAP paged search with PageSize=$PageSize and TimeoutSeconds=$TimeoutSeconds" -Level "INFO"
    Write-ModuleLog "LDAP SearchBase: $SearchBase" -Level "DEBUG"
    Write-ModuleLog "LDAP Filter: $Filter" -Level "DEBUG"
    Write-ModuleLog ("LDAP authentication mode: {0}" -f (Get-AuthenticationMode -Config $Config)) -Level "DEBUG"
    Write-ModuleLog ("Requested LDAP properties: {0}" -f ($SelectedProperties -join ', ')) -Level "DEBUG"

    try {
        do {
            $SearchRequest = New-Object System.DirectoryServices.Protocols.SearchRequest(
                $SearchBase,
                $Filter,
                $Scope,
                $SelectedProperties
            )

            $SearchRequest.SizeLimit = 0
            $SearchRequest.TimeLimit = New-TimeSpan -Seconds $TimeoutSeconds

            $PageRequestControl = New-Object System.DirectoryServices.Protocols.PageResultRequestControl($PageSize)
            $PageRequestControl.Cookie = $Cookie
            [void]$SearchRequest.Controls.Add($PageRequestControl)

            $Response = $null

            try {
                $Response = $LdapConn.SendRequest($SearchRequest)
            }
            catch {
                Write-ModuleLog "LDAP search request failed: $($_.Exception.Message)" -Level "ERROR"
                throw
            }

            $PageCount = $Response.Entries.Count
            $Total += $PageCount
            Write-ModuleLog ("LDAP page returned [{0}] entries. Total so far: [{1}]" -f $PageCount, $Total) -Level "INFO"

            foreach ($Entry in $Response.Entries) {
                $EntryData      = [ordered]@{}
                $EffectiveEntry = $Entry
                $Snapshot       = Get-LdapEntrySnapshot -Entry $Entry
                $EntryDn        = $Snapshot.DistinguishedName

                if ($SelectedProperties -notcontains '*' -and $Snapshot.AttributeCount -eq 0 -and -not [string]::IsNullOrWhiteSpace($EntryDn)) {
                    try {
                        $ReloadedEntry = Get-LdapEntryByDn -LdapConn $LdapConn -EntryDn $EntryDn -Properties $SelectedProperties -TimeoutSeconds $TimeoutSeconds
                        if ($null -ne $ReloadedEntry) {
                            $EffectiveEntry = $ReloadedEntry
                            $ReloadFallbackCount++
                            Write-ModuleLog ("Applied LDAP base-reload fallback for entry: {0}" -f $EntryDn) -Level "DEBUG"
                        }
                        else {
                            Write-ModuleLog ("LDAP base-reload fallback returned no entry for: {0}" -f $EntryDn) -Level "WARN"
                        }
                    }
                    catch {
                        Write-ModuleLog ("LDAP base-reload fallback failed for entry '{0}': {1}" -f $EntryDn, $_.Exception.Message) -Level "WARN"
                    }
                }

                foreach ($Attribute in $SelectedProperties) {
                    try {
                        $MetaValue = Get-EntryMetaValue -Entry $EffectiveEntry -RequestedName $Attribute
                        if ($null -ne $MetaValue) {
                            $EntryData[$Attribute] = $MetaValue
                            continue
                        }

                        $ResolvedAttributeName = Resolve-LdapAttributeName -Entry $EffectiveEntry -RequestedName $Attribute
                        if ($ResolvedAttributeName) {
                            $AttributeValues = $EffectiveEntry.Attributes[$ResolvedAttributeName]
                            $ConvertedValues = New-Object System.Collections.Generic.List[string]

                            foreach ($Item in $AttributeValues) {
                                $Converted = Convert-LdapValue -Value $Item -AttributeName $ResolvedAttributeName
                                if ($null -ne $Converted -and $Converted -ne '') {
                                    [void]$ConvertedValues.Add([string]$Converted)
                                }
                            }

                            if ($ConvertedValues.Count -gt 1) {
                                $EntryData[$Attribute] = $ConvertedValues -join '; '
                            }
                            elseif ($ConvertedValues.Count -eq 1) {
                                $EntryData[$Attribute] = $ConvertedValues[0]
                            }
                            else {
                                $EntryData[$Attribute] = $null
                            }
                        }
                        else {
                            $EntryData[$Attribute] = $null
                        }
                    }
                    catch {
                        throw "LDAP attribute conversion failed. DN='$EntryDn' Attribute='$Attribute' Message='$($_.Exception.Message)'"
                    }
                }

                $OutputObject = [PSCustomObject]$EntryData
                if (-not $PreviewLogged) {
                    Write-ModuleLog ("First LDAP object preview: {0}" -f (Get-EtlObjectPreview -InputObject $OutputObject)) -Level "INFO"
                    $PreviewLogged = $true
                }
                $OutputObject
            }

            $PageResponseControl = $Response.Controls | Where-Object {
                $_ -is [System.DirectoryServices.Protocols.PageResultResponseControl]
            }

            if ($PageResponseControl) {
                $Cookie = $PageResponseControl.Cookie
            }
            else {
                $Cookie = $null
            }

        } while ($null -ne $Cookie -and $Cookie.Length -gt 0)

        if ($Total -eq 0) {
            Write-ModuleLog "LDAP extraction returned zero objects. Downstream destination will receive no rows." -Level "WARN"
        }
        Write-ModuleLog ("LDAP extraction completed successfully. Total objects processed: {0}" -f $Total) -Level "INFO"
        Write-ModuleLog ("LDAP reload fallback applied to {0} entries." -f $ReloadFallbackCount) -Level "DEBUG"
    }
    catch {
        Write-EtlExceptionDetails -Context $Script:ModuleContext -ErrorRecord $_ -Prefix 'LDAP extraction failed:'
        throw
    }
    finally {
        if ($LdapConn) {
            $LdapConn.Dispose()
            Write-ModuleLog "LDAP connection disposed." -Level "DEBUG"
        }
    }
}

Export-ModuleMember -Function Invoke-Extract
