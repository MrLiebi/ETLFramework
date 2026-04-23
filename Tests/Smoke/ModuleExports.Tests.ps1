
Set-StrictMode -Version Latest
. (Join-Path -Path (Split-Path -Parent (Split-Path -Parent $PSCommandPath)) -ChildPath 'TestHelpers.ps1')

BeforeAll {
    $null = Set-FrameworkTestEnvironment
}

AfterAll {
    Clear-FrameworkTestEnvironment
}

BeforeDiscovery {
    $script:ModuleExpectations = @(
        @{ RelativePath = 'Wizard/Modules/Wizard.Logging.psm1';                   ExportedCommands = @('Initialize-WizardLogContext', 'Write-WizardLog', 'Write-WizardException') },
        @{ RelativePath = 'Templates/Modules/Adapter/Adapter.Flexera.psm1';       ExportedCommands = @('Resolve-AdapterConfigPath', 'Resolve-MgsbiExecutablePath', 'Get-XmlAttributeValue', 'Get-AdapterImportDefinitions', 'Invoke-FlexeraBusinessAdapter') },
        @{ RelativePath = 'Templates/Modules/Common/Framework.Common.psm1';       ExportedCommands = @('Get-EtlProjectRootPath', 'Resolve-EtlProjectPath', 'Get-EtlObjectPreview', 'Write-EtlModuleLog', 'Import-EtlCredentialSupport') },
        @{ RelativePath = 'Templates/Modules/Common/Framework.Logging.psm1';      ExportedCommands = @('Test-EtlLogLevelEnabled', 'Write-EtlMessageStream', 'Invoke-EtlLogRetentionCleanup', 'Initialize-EtlScriptLogContext', 'Write-EtlScriptLog', 'Write-EtlScriptException') },
        @{ RelativePath = 'Templates/Modules/Common/Framework.Validation.psm1';   ExportedCommands = @('Get-ValidatedPropertySelection', 'Get-EtlAuthenticationMode') },
        @{ RelativePath = 'Templates/Modules/Credential/Credential.Manager.psm1'; ExportedCommands = @('Get-StoredCredential', 'Set-StoredCredential', 'Test-StoredCredential', 'Remove-StoredCredential') },
        @{ RelativePath = 'Templates/Modules/Destination/Destination.CSV.psm1';   ExportedCommands = @('Invoke-Load') },
        @{ RelativePath = 'Templates/Modules/Destination/Destination.MSSQL.psm1'; ExportedCommands = @('Invoke-Load') },
        @{ RelativePath = 'Templates/Modules/Source/Source.CSV.psm1';             ExportedCommands = @('Invoke-Extract') },
        @{ RelativePath = 'Templates/Modules/Source/Source.CustomScript.psm1';    ExportedCommands = @('Invoke-Extract') },
        @{ RelativePath = 'Templates/Modules/Source/Source.JSON.psm1';            ExportedCommands = @('Invoke-Extract') },
        @{ RelativePath = 'Templates/Modules/Source/Source.LDAP.psm1';            ExportedCommands = @('Invoke-Extract') },
        @{ RelativePath = 'Templates/Modules/Source/Source.MSSQL.psm1';           ExportedCommands = @('Invoke-Extract') },
        @{ RelativePath = 'Templates/Modules/Source/Source.XLSX.psm1';            ExportedCommands = @('Invoke-Extract') },
        @{ RelativePath = 'Templates/Modules/Source/Source.XML.psm1';             ExportedCommands = @('Invoke-Extract') }
    )
}

Describe 'Module export smoke tests' {
    It '<RelativePath> imports and exports the expected commands' -ForEach $script:ModuleExpectations {
        $Module = Import-TestableAsset -RelativePath $RelativePath
        try {
            foreach ($CommandName in $ExportedCommands) {
                $Module.ExportedCommands.Keys | Should -Contain $CommandName
            }
        }
        finally {
            Remove-TestModuleSafely -Module $Module
        }
    }
}
