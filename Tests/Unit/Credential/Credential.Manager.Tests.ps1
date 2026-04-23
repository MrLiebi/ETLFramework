Set-StrictMode -Version Latest
. (Join-Path -Path (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))) -ChildPath 'TestHelpers.ps1')

if (-not ('EtlCredentialNative' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

public static class EtlCredentialNative
{
    public const int CRED_TYPE_GENERIC = 1;
    public const int CRED_PERSIST_LOCAL_MACHINE = 2;

    public static int ReadCallCount = 0;
    public static int WriteCallCount = 0;
    public static int DeleteCallCount = 0;
    public static bool NextReadResult = true;
    public static bool NextWriteResult = true;
    public static bool NextDeleteResult = true;
    public static string NextUserName = "svc-etl";
    public static string NextPassword = "P@ssw0rd!";
    public static string NextComment = "ETL Framework Credential";
    public static string LastReadTarget = null;
    public static string LastWriteTarget = null;
    public static string LastDeleteTarget = null;

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

    public static void Reset()
    {
        ReadCallCount = 0;
        WriteCallCount = 0;
        DeleteCallCount = 0;
        NextReadResult = true;
        NextWriteResult = true;
        NextDeleteResult = true;
        NextUserName = "svc-etl";
        NextPassword = "P@ssw0rd!";
        NextComment = "ETL Framework Credential";
        LastReadTarget = null;
        LastWriteTarget = null;
        LastDeleteTarget = null;
    }

    private static IntPtr AllocateString(string value)
    {
        if (string.IsNullOrEmpty(value))
        {
            return IntPtr.Zero;
        }

        return Marshal.StringToCoTaskMemUni(value);
    }

    public static bool CredRead(string target, int type, int reservedFlag, out IntPtr credentialPtr)
    {
        ReadCallCount++;
        LastReadTarget = target;
        credentialPtr = IntPtr.Zero;

        if (!NextReadResult)
        {
            return false;
        }

        CREDENTIAL credential = new CREDENTIAL();
        credential.Flags = 0;
        credential.Type = type;
        credential.TargetName = target;
        credential.Comment = NextComment;
        credential.LastWritten = new System.Runtime.InteropServices.ComTypes.FILETIME();
        credential.CredentialBlob = AllocateString(NextPassword);
        credential.CredentialBlobSize = string.IsNullOrEmpty(NextPassword) ? 0 : NextPassword.Length * 2;
        credential.Persist = CRED_PERSIST_LOCAL_MACHINE;
        credential.AttributeCount = 0;
        credential.Attributes = IntPtr.Zero;
        credential.TargetAlias = null;
        credential.UserName = NextUserName;

        credentialPtr = Marshal.AllocHGlobal(Marshal.SizeOf(typeof(CREDENTIAL)));
        Marshal.StructureToPtr(credential, credentialPtr, false);
        return true;
    }

    public static bool CredWrite(ref CREDENTIAL userCredential, int flags)
    {
        WriteCallCount++;
        LastWriteTarget = userCredential.TargetName;
        return NextWriteResult;
    }

    public static void CredFree(IntPtr cred)
    {
        if (cred == IntPtr.Zero)
        {
            return;
        }

        try
        {
            CREDENTIAL credential = (CREDENTIAL)Marshal.PtrToStructure(cred, typeof(CREDENTIAL));
            if (credential.CredentialBlob != IntPtr.Zero)
            {
                Marshal.ZeroFreeCoTaskMemUnicode(credential.CredentialBlob);
            }
        }
        finally
        {
            Marshal.FreeHGlobal(cred);
        }
    }

    public static bool CredDelete(string target, int type, int flags)
    {
        DeleteCallCount++;
        LastDeleteTarget = target;
        return NextDeleteResult;
    }
}
'@ -Language CSharp -ErrorAction Stop
}

Describe 'Credential.Manager module' {
    BeforeAll {
        $script:OriginalEnv = @{}
        $script:CredentialProjectRoot = Join-Path -Path $TestDrive -ChildPath 'CredentialProject'
        $script:CredentialLogRoot = Join-Path -Path $script:CredentialProjectRoot -ChildPath 'LOG'
        New-Item -Path $script:CredentialLogRoot -ItemType Directory -Force | Out-Null

        foreach ($Name in @('ETL_PROJECT_ROOT','ETL_LOG_ROOT','ETL_RUN_ID','ETL_LOG_LEVEL','ETL_MODULE_LOGS','ETL_LOG_RETENTION_DAYS')) {
            $script:OriginalEnv[$Name] = [System.Environment]::GetEnvironmentVariable($Name)
        }

        $env:ETL_PROJECT_ROOT = $script:CredentialProjectRoot
        $env:ETL_LOG_ROOT = $script:CredentialLogRoot
        $env:ETL_RUN_ID = 'CRED_TEST_0001'
        $env:ETL_LOG_LEVEL = 'DEBUG'
        $env:ETL_MODULE_LOGS = 'true'
        $env:ETL_LOG_RETENTION_DAYS = '30'

        $script:Module = Import-TestableAsset -RelativePath 'Templates/Modules/Credential/Credential.Manager.psm1' -ModuleName 'Credential.Manager.Tests'
    }

    BeforeEach {
        [EtlCredentialNative]::Reset()
    }

    AfterAll {
        if ($script:Module) {
            Remove-TestModuleSafely -Module $script:Module
        }

        foreach ($Name in $script:OriginalEnv.Keys) {
            if ($null -eq $script:OriginalEnv[$Name]) {
                Remove-Item -Path ("Env:{0}" -f $Name) -ErrorAction SilentlyContinue
            }
            else {
                [System.Environment]::SetEnvironmentVariable($Name, $script:OriginalEnv[$Name])
            }
        }
    }

    Context 'module bootstrap' {
        It 'initializes the module log context from the environment' {
            $Context = & $script:Module { $script:CredentialLogContext }

            $Context.ModuleLogDirectory | Should -Be $script:CredentialLogRoot
            $Context.ModuleLogLevel | Should -Be 'DEBUG'
            $Context.ModuleRunId | Should -Be 'CRED_TEST_0001'
        }
    }

    Context 'Get-StoredCredential' {
        It 'returns a PSCredential for a stored credential target' {
            $Result = Get-StoredCredential -Target 'Target/One'

            $Result.UserName | Should -Be 'svc-etl'
            $Result.GetNetworkCredential().Password | Should -Be 'P@ssw0rd!'
            [EtlCredentialNative]::ReadCallCount | Should -Be 1
            [EtlCredentialNative]::LastReadTarget | Should -Be 'Target/One'
        }

        It 'returns a network credential when requested' {
            $Result = Get-StoredCredential -Target 'Target/Two' -AsNetworkCredential

            $Result.UserName | Should -Be 'svc-etl'
            $Result.Password | Should -Be 'P@ssw0rd!'
        }

        It 'throws when a stored credential cannot be read' {
            [EtlCredentialNative]::NextReadResult = $false

            { Get-StoredCredential -Target 'Missing/Target' } | Should -Throw '*Credential target not found or unreadable*'
        }
    }

    Context 'Set-StoredCredential' {
        It 'stores a credential in the interop layer' {
            $SecurePassword = New-Object System.Security.SecureString
            foreach ($Character in 'secret'.ToCharArray()) { $SecurePassword.AppendChar($Character) }
            $SecurePassword.MakeReadOnly()

            $Credential = [PSCredential]::new('svc-user', $SecurePassword)
            Set-StoredCredential -Target 'Target/Store' -Credential $Credential -Comment 'ETL Framework Credential' -Confirm:$false

            [EtlCredentialNative]::WriteCallCount | Should -Be 1
            [EtlCredentialNative]::LastWriteTarget | Should -Be 'Target/Store'
        }

        It 'throws when storing a credential fails' {
            [EtlCredentialNative]::NextWriteResult = $false

            $SecurePassword = New-Object System.Security.SecureString
            foreach ($Character in 'secret'.ToCharArray()) { $SecurePassword.AppendChar($Character) }
            $SecurePassword.MakeReadOnly()

            $Credential = [PSCredential]::new('svc-user', $SecurePassword)
            { Set-StoredCredential -Target 'Target/Fail' -Credential $Credential -Confirm:$false } | Should -Throw '*Failed to store credential target*'
        }
    }

    Context 'Test-StoredCredential' {
        It 'reports stored credential existence via Test-StoredCredential' {
            Test-StoredCredential -Target 'Target/Test' | Should -BeTrue
        }

        It 'returns false when the stored credential cannot be read' {
            [EtlCredentialNative]::NextReadResult = $false

            Test-StoredCredential -Target 'Missing/Target' | Should -BeFalse
        }
    }

    Context 'Remove-StoredCredential' {
        It 'deletes a stored credential target' {
            Remove-StoredCredential -Target 'Target/Delete' -Confirm:$false

            [EtlCredentialNative]::DeleteCallCount | Should -Be 1
            [EtlCredentialNative]::LastDeleteTarget | Should -Be 'Target/Delete'
        }

        It 'throws when deleting a stored credential fails' {
            [EtlCredentialNative]::NextDeleteResult = $false

            { Remove-StoredCredential -Target 'Target/Delete' -Confirm:$false } | Should -Throw '*Failed to delete credential target*'
        }
    }
}
