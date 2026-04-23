Set-StrictMode -Version Latest
. (Join-Path -Path (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))) -ChildPath 'TestHelpers.ps1')

Describe 'Wizard.Credentials helpers' {
    BeforeAll {
        Disable-EtlFrameworkWizardAutomationForInteractivePromptTests
        $script:Module = Import-TestableAsset -RelativePath 'Wizard/Helpers/Wizard.Credentials.ps1' -ModuleName 'Wizard.Credentials.Tests' -AdditionalRelativePaths @(
            'Wizard/Helpers/Wizard.Paths.ps1'
        )
    }

    AfterAll {
        Remove-TestModuleSafely -Module $script:Module
        Enable-EtlFrameworkWizardAutomationAfterInteractivePromptTests
    }

    Context 'Read-CredentialTargetConfiguration' {
        It 'returns integrated authentication without credential details' {
            Mock -ModuleName $script:Module.Name Read-Choice { 'Integrated' }

            $Result = Read-CredentialTargetConfiguration -RoleLabel 'Source' -TypeLabel 'LDAP' -ProjectName 'Demo' -StepId '01'

            $Result.AuthenticationMode | Should -Be 'Integrated'
            $Result.CredentialTarget | Should -BeNullOrEmpty
            $Result.CreateCredential | Should -BeFalse
        }

        It 'returns a credential manager configuration including the entered password' {
            $SecurePassword = New-Object System.Security.SecureString
            foreach ($Character in 'P@ssw0rd!'.ToCharArray()) { $SecurePassword.AppendChar($Character) }
            $SecurePassword.MakeReadOnly()
            $script:InputAnswers = [System.Collections.Generic.Queue[string]]::new()
            [void]$script:InputAnswers.Enqueue('ETL-Demo-02-Source')
            [void]$script:InputAnswers.Enqueue('svc-etl')

            Mock -ModuleName $script:Module.Name Read-Choice { 'CredentialManager' }
            Mock -ModuleName $script:Module.Name Read-BooleanChoice { $true }
            Mock -ModuleName $script:Module.Name Read-InputValue { $script:InputAnswers.Dequeue() }
            Mock -ModuleName $script:Module.Name Read-Host { $SecurePassword } -ParameterFilter { $AsSecureString }

            $Result = Read-CredentialTargetConfiguration -RoleLabel 'Source' -TypeLabel 'MSSQL' -ProjectName 'Demo' -StepId '02'

            $Result.AuthenticationMode | Should -Be 'CredentialManager'
            $Result.CredentialTarget | Should -Be 'ETL-Demo-02-Source'
            $Result.UserName | Should -Be 'svc-etl'
            $Result.Password | Should -BeOfType System.Security.SecureString
            $Bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($Result.Password)
            try {
                [Runtime.InteropServices.Marshal]::PtrToStringBSTR($Bstr) | Should -Be 'P@ssw0rd!'
            }
            finally {
                [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($Bstr)
            }
        }
    }

    Context 'Initialize-ProjectCredential' {
        It 'imports the credential manager template and stores the credential' {
            $CredentialTemplateRootPath = Join-Path -Path $TestDrive -ChildPath 'Credential'
            New-Item -Path $CredentialTemplateRootPath -ItemType Directory -Force | Out-Null
            New-Item -Path (Join-Path -Path $CredentialTemplateRootPath -ChildPath 'Credential.Manager.psm1') -ItemType File -Force | Out-Null
            & $script:Module { param($Path) $script:CredentialTemplateRootPath = $Path } $CredentialTemplateRootPath

            Mock -ModuleName $script:Module.Name Test-PathExists { $true }
            Mock -ModuleName $script:Module.Name Get-Module { @() }
            Mock -ModuleName $script:Module.Name Import-Module {}
            Mock -ModuleName $script:Module.Name Set-StoredCredential {}

            $SecurePassword = New-Object System.Security.SecureString
            foreach ($Character in 'secret'.ToCharArray()) { $SecurePassword.AppendChar($Character) }
            $SecurePassword.MakeReadOnly()

            $Credential = [PSCredential]::new('svc-user', $SecurePassword)

            Initialize-ProjectCredential -Target 'ETL-Target' -Credential $Credential

            Should -Invoke Import-Module -ModuleName $script:Module.Name -Times 1
            Should -Invoke Set-StoredCredential -ModuleName $script:Module.Name -Times 1 -ParameterFilter {
                $Target -eq 'ETL-Target' -and $Credential -is [PSCredential] -and $Credential.UserName -eq 'svc-user' -and $Credential.GetNetworkCredential().Password -eq 'secret'
            }
        }
    }
}
