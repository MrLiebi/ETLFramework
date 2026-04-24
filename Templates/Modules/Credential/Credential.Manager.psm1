<#
.SYNOPSIS
Credential management module for the ETL framework.

.DESCRIPTION
Provides functions to securely store, retrieve, and delete credentials
using the Windows Credential Manager.

Used by adapters requiring authentication (e.g. MSSQL, LDAP).

.VERSION
1.0.0

.AUTHOR
ETL Framework

.NOTES
- Uses Windows Credential Manager
- Credentials stored per user context
- Accessed via Get-StoredCredential

.DEPENDENCIES
- Windows Credential Manager
- Advapi32.dll
#>

$CommonModulePath = Join-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -ChildPath 'Common\Framework.Common.psm1'
if (Test-Path -Path $CommonModulePath -PathType Leaf) {
    Import-Module -Name $CommonModulePath -Force -ErrorAction Stop
}

$Script:CredentialInteropLoaded = $false
$Script:CredentialLogContext = @{
    ModuleName = 'Credential.Manager'
    ModuleRole = '00'
    ModuleRoot = $PSScriptRoot
    ModuleRunId = if ($env:ETL_RUN_ID) { $env:ETL_RUN_ID } else { Get-Date -Format 'yyyyMMdd_HHmmss' }
    ModuleLogDirectory = if ($env:ETL_LOG_ROOT) { $env:ETL_LOG_ROOT } else { Join-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -ChildPath 'LOG' }
    ModuleRetentionDays = if ($env:ETL_LOG_RETENTION_DAYS) { [int]$env:ETL_LOG_RETENTION_DAYS } else { 30 }
    ModuleLogLevel = if ($env:ETL_LOG_LEVEL) { $env:ETL_LOG_LEVEL.ToUpperInvariant() } else { 'INFO' }
    ModuleLogFileNameBase = '00_Credential.Manager'
    CleanupKey = 'Module::Credential.Manager'
}

function Write-CredentialManagerLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $Message,
        [ValidateSet('INFO','WARN','ERROR','DEBUG')][string] $Level = 'INFO'
    )

    if (Get-Command -Name Write-EtlModuleLog -ErrorAction SilentlyContinue) {
        Write-EtlModuleLog -Context $Script:CredentialLogContext -Message $Message -Level $Level
    }
}

function Initialize-CredentialInterop {
    [CmdletBinding()]
    param()

    if ($Script:CredentialInteropLoaded) {
        return
    }

    if ('EtlCredentialNative' -as [type]) {
        $Script:CredentialInteropLoaded = $true
        Write-CredentialManagerLog 'Reusing previously loaded Credential Manager interop type.' -Level 'DEBUG'
        return
    }

    Write-CredentialManagerLog 'Initializing Windows Credential Manager interop.' -Level 'DEBUG'

    $TypeDefinition = @"
using System;
using System.Runtime.InteropServices;

public static class EtlCredentialNative
{
    public const int CRED_TYPE_GENERIC = 1;
    public const int CRED_PERSIST_LOCAL_MACHINE = 2;

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    public struct CREDENTIAL
    {
        public int Flags;
        public int Type;
        public string TargetName;
        public string Comment;
        public System.Runtime.InteropServices.ComTypes.FILETIME LastWritten;
        public int CredentialBlobSize;
        public IntPtr CredentialBlob;
        public int Persist;
        public int AttributeCount;
        public IntPtr Attributes;
        public string TargetAlias;
        public string UserName;
    }

    [DllImport("Advapi32.dll", EntryPoint = "CredReadW", CharSet = CharSet.Unicode, SetLastError = true)]
    public static extern bool CredRead(string target, int type, int reservedFlag, out IntPtr credentialPtr);

    [DllImport("Advapi32.dll", EntryPoint = "CredWriteW", CharSet = CharSet.Unicode, SetLastError = true)]
    public static extern bool CredWrite(ref CREDENTIAL userCredential, int flags);

    [DllImport("Advapi32.dll", EntryPoint = "CredFree", SetLastError = true)]
    public static extern void CredFree([In] IntPtr cred);

    [DllImport("Advapi32.dll", EntryPoint = "CredDeleteW", CharSet = CharSet.Unicode, SetLastError = true)]
    public static extern bool CredDelete(string target, int type, int flags);
}
"@

    Add-Type -TypeDefinition $TypeDefinition -Language CSharp -ErrorAction Stop
    $Script:CredentialInteropLoaded = $true
    Write-CredentialManagerLog 'Credential Manager interop initialized successfully.' -Level 'DEBUG'
}

function ConvertTo-SecureStringFromPlainText {
    [CmdletBinding()]
    param(
        [AllowNull()][string] $Text
    )

    $SecureString = New-Object System.Security.SecureString

    if (-not [string]::IsNullOrEmpty($Text)) {
        foreach ($Character in $Text.ToCharArray()) {
            $SecureString.AppendChar($Character)
        }
    }

    $SecureString.MakeReadOnly()
    return $SecureString
}

function Get-StoredCredential {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $Target,
        [switch] $AsNetworkCredential
    )

    Initialize-CredentialInterop

    $CredentialPtr = [IntPtr]::Zero

    try {
        Write-CredentialManagerLog "Reading stored credential target: [$Target]" -Level 'DEBUG'
        $ReadSucceeded = [EtlCredentialNative]::CredRead(
            $Target,
            [EtlCredentialNative]::CRED_TYPE_GENERIC,
            0,
            [ref]$CredentialPtr
        )

        if (-not $ReadSucceeded) {
            $Win32Error = [Runtime.InteropServices.Marshal]::GetLastWin32Error()
            throw "Credential target not found or unreadable: [$Target] | Win32Error=$Win32Error"
        }

        $NativeCredential = [Runtime.InteropServices.Marshal]::PtrToStructure(
            $CredentialPtr,
            [type][EtlCredentialNative+CREDENTIAL]
        )

        $UserName = $NativeCredential.UserName
        $Password = ''

        if ($NativeCredential.CredentialBlob -ne [IntPtr]::Zero -and $NativeCredential.CredentialBlobSize -gt 0) {
            $Password = [Runtime.InteropServices.Marshal]::PtrToStringUni(
                $NativeCredential.CredentialBlob,
                [int]($NativeCredential.CredentialBlobSize / 2)
            )
        }

        $SecurePassword = ConvertTo-SecureStringFromPlainText -Text $Password
        $PsCredential   = New-Object System.Management.Automation.PSCredential($UserName, $SecurePassword)

        if ($AsNetworkCredential) {
            Write-CredentialManagerLog "Credential target read successfully as network credential: [$Target]" -Level 'INFO'
            return $PsCredential.GetNetworkCredential()
        }

        Write-CredentialManagerLog "Credential target read successfully: [$Target]" -Level 'INFO'
        return $PsCredential
    }
    catch {
        Write-CredentialManagerLog "Credential target read failed: [$Target] | $($_.Exception.Message)" -Level 'ERROR'
        throw
    }
    finally {
        if ($CredentialPtr -ne [IntPtr]::Zero) {
            [EtlCredentialNative]::CredFree($CredentialPtr)
        }
    }
}

function ConvertTo-PlainTextFromSecureString {
    [CmdletBinding()]
    param(
        [AllowNull()][System.Security.SecureString] $SecureString
    )

    if ($null -eq $SecureString -or $SecureString.Length -eq 0) {
        return ''
    }

    $Pointer = [Runtime.InteropServices.Marshal]::SecureStringToGlobalAllocUnicode($SecureString)
    try {
        return [Runtime.InteropServices.Marshal]::PtrToStringUni($Pointer)
    }
    finally {
        if ($Pointer -ne [IntPtr]::Zero) {
            [Runtime.InteropServices.Marshal]::ZeroFreeGlobalAllocUnicode($Pointer)
        }
    }
}

function Set-StoredCredential {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)][string] $Target,
        [Parameter(Mandatory)][PSCredential] $Credential,
        [string] $Comment = 'ETL Framework Credential',
        [ValidateSet('LocalMachine')]
        [string] $Persistence = 'LocalMachine'
    )

    Initialize-CredentialInterop

    if (-not $PSCmdlet.ShouldProcess($Target, 'Store credential in Windows Credential Manager')) {
        return
    }

    Write-CredentialManagerLog "Storing credential target: [$Target]" -Level 'INFO'

    $PersistValue = [EtlCredentialNative]::CRED_PERSIST_LOCAL_MACHINE
    $PasswordPlainText = ConvertTo-PlainTextFromSecureString -SecureString $Credential.Password
    $PasswordBytes = [System.Text.Encoding]::Unicode.GetBytes($PasswordPlainText)
    $PasswordPtr = [IntPtr]::Zero

    try {
        $PasswordPtr = [Runtime.InteropServices.Marshal]::StringToCoTaskMemUni($PasswordPlainText)

        $StoredCredential = New-Object EtlCredentialNative+CREDENTIAL
        $StoredCredential.Flags = 0
        $StoredCredential.Type = [EtlCredentialNative]::CRED_TYPE_GENERIC
        $StoredCredential.TargetName = $Target
        $StoredCredential.Comment = $Comment
        $StoredCredential.CredentialBlobSize = $PasswordBytes.Length
        $StoredCredential.CredentialBlob = $PasswordPtr
        $StoredCredential.Persist = $PersistValue
        $StoredCredential.AttributeCount = 0
        $StoredCredential.Attributes = [IntPtr]::Zero
        $StoredCredential.TargetAlias = $null
        $StoredCredential.UserName = $Credential.UserName

        $WriteSucceeded = [EtlCredentialNative]::CredWrite([ref]$StoredCredential, 0)

        if (-not $WriteSucceeded) {
            $Win32Error = [Runtime.InteropServices.Marshal]::GetLastWin32Error()
            throw "Failed to store credential target [$Target]. Win32Error=$Win32Error"
        }

        Write-CredentialManagerLog "Credential target stored successfully: [$Target]" -Level 'INFO'
    }
    catch {
        Write-CredentialManagerLog "Credential target store failed: [$Target] | $($_.Exception.Message)" -Level 'ERROR'
        throw
    }
    finally {
        if ($PasswordPtr -ne [IntPtr]::Zero) {
            [Runtime.InteropServices.Marshal]::ZeroFreeCoTaskMemUnicode($PasswordPtr)
        }

        $PasswordPlainText = $null
    }
}

function Test-StoredCredential {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $Target
    )

    try {
        $null = Get-StoredCredential -Target $Target
        return $true
    }
    catch {
        return $false
    }
}

function Remove-StoredCredential {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)][string] $Target
    )

    Initialize-CredentialInterop

    if (-not $PSCmdlet.ShouldProcess($Target, 'Delete stored credential')) {
        return
    }

    Write-CredentialManagerLog "Deleting credential target: [$Target]" -Level 'INFO'

    $Deleted = [EtlCredentialNative]::CredDelete(
        $Target,
        [EtlCredentialNative]::CRED_TYPE_GENERIC,
        0
    )

    if (-not $Deleted) {
        $Win32Error = [Runtime.InteropServices.Marshal]::GetLastWin32Error()
        throw "Failed to delete credential target [$Target]. Win32Error=$Win32Error"
    }

    Write-CredentialManagerLog "Credential target deleted successfully: [$Target]" -Level 'INFO'
}


Export-ModuleMember -Function Get-StoredCredential, Set-StoredCredential, Test-StoredCredential, Remove-StoredCredential
