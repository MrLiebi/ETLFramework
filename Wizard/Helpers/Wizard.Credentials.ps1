<#
    Helper functions for New-ETLProject.ps1.
    File: Wizard.Credentials.ps1
#>

function Convert-EtlWizardPlainPasswordToSecureString {
    [CmdletBinding()]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingConvertToSecureStringWithPlainText', 'ConvertTo-SecureString', Justification = 'Non-interactive wizard/tests use ETL_TEST_CREDENTIAL_PASSWORD.')]
    param(
        [Parameter(Mandatory)][string] $PlainText
    )

    return ConvertTo-SecureString -String $PlainText -AsPlainText -Force
}

function Read-CredentialTargetConfiguration {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $RoleLabel,
        [Parameter(Mandatory)][string] $TypeLabel,
        [Parameter(Mandatory)][string] $ProjectName,
        [Parameter(Mandatory)][string] $StepId
    )

    $AuthenticationMode = Read-Choice -Title ("SELECT AUTHENTICATION MODE FOR {0} [{1}] STEP [{2}]" -f $RoleLabel.ToUpperInvariant(), $TypeLabel, $StepId) -Options @('Integrated', 'CredentialManager')

    $Result = [ordered]@{
        AuthenticationMode = $AuthenticationMode
        CredentialTarget   = $null
        CreateCredential   = $false
        UserName           = $null
        Password           = $null
    }

    if ($AuthenticationMode -eq 'CredentialManager') {
        $DefaultTarget = "ETL-{0}-{1}-{2}" -f $ProjectName, $StepId, $RoleLabel
        $Result['CredentialTarget'] = Read-InputValue -Prompt '  > Credential Target Name' -Default $DefaultTarget
        $Result['CreateCredential'] = Read-BooleanChoice -Prompt '  > Create credential entry now?' -Default $true

        if ($Result['CreateCredential']) {
            if ($env:ETL_TEST_NONINTERACTIVE -eq '1') {
                $Result['UserName'] = if (-not [string]::IsNullOrWhiteSpace($env:ETL_TEST_CREDENTIAL_USERNAME)) { $env:ETL_TEST_CREDENTIAL_USERNAME } else { 'etl-test-user' }
                $PasswordPlainText = if (-not [string]::IsNullOrWhiteSpace($env:ETL_TEST_CREDENTIAL_PASSWORD)) { $env:ETL_TEST_CREDENTIAL_PASSWORD } else { 'etl-test-password' }
                $Result['Password'] = Convert-EtlWizardPlainPasswordToSecureString -PlainText $PasswordPlainText
            }
            else {
                $Result['UserName'] = Read-InputValue -Prompt '  > User Name'
                $Result['Password'] = Read-Host '  > Password' -AsSecureString
            }
        }
    }

    return [PSCustomObject]$Result
}

function Initialize-ProjectCredential {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $Target,
        [Parameter(Mandatory)][PSCredential] $Credential
    )

    if ([string]::IsNullOrWhiteSpace($Target)) {
        throw "Credential setup target is empty."
    }

    if ($null -eq $Credential) {
        throw "Credential setup is missing for target [$Target]."
    }

    $CredentialModulePath = Join-Path -Path $CredentialTemplateRootPath -ChildPath 'Credential.Manager.psm1'
    if (-not (Test-PathExists -Path $CredentialModulePath -PathType Leaf -Description 'Credential manager template')) {
        throw "Credential manager template missing: $CredentialModulePath"
    }

    $LoadedCredentialModule = Get-Module | Where-Object { $_.Path -eq $CredentialModulePath } | Select-Object -First 1
    if (-not $LoadedCredentialModule) {
        Import-Module $CredentialModulePath -ErrorAction Stop
    }

    # Keep wizard runs and automated tests non-interactive.
    Set-StoredCredential -Target $Target -Credential $Credential -Comment 'ETL Framework Wizard Credential' -Confirm:$false
    Write-Log "Credential target initialized: $Target" -Level "INFO"
}

