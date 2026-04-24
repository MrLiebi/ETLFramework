
@{
    'New-ETLProject.ps1' = @{ Coverage = @('Syntax', 'Analyzer'); Notes = 'Refactored wizard wrapper with minimal entry logic.' }
    'Templates/Runtime/Run-ETL.ps1' = @{ Coverage = @('Syntax', 'Analyzer', 'Smoke'); Notes = 'Runtime entry script; covered by non-interactive runtime smoke tests and not full integration tests.' }
    'Templates/Task/Register-Task.ps1' = @{ Coverage = @('Syntax', 'Analyzer'); Notes = 'Task registration; COM/admin rights.' }

    'Templates/Modules/Adapter/Adapter.Flexera.psm1' = @{ Coverage = @('Syntax', 'Analyzer', 'ModuleExports'); Notes = 'Adapter module with export/import smoke test.' }
    'Templates/Modules/Common/Framework.Common.psm1' = @{ Coverage = @('Syntax', 'Analyzer', 'ModuleExports', 'Unit'); Notes = 'Core runtime helpers with unit tests.' }
    'Templates/Modules/Common/Framework.Logging.psm1' = @{ Coverage = @('Syntax', 'Analyzer', 'ModuleExports', 'Unit'); Notes = 'Logging core module with unit tests.' }
    'Templates/Modules/Common/Framework.Validation.psm1' = @{ Coverage = @('Syntax', 'Analyzer', 'ModuleExports', 'Unit'); Notes = 'Validation helpers with unit tests.' }
    'Templates/Modules/Credential/Credential.Manager.psm1' = @{ Coverage = @('Syntax', 'Analyzer', 'ModuleExports', 'Unit'); Notes = 'Windows Credential Manager with interop-focused unit tests.' }
    'Templates/Modules/Destination/Destination.CSV.psm1' = @{ Coverage = @('Syntax', 'Analyzer', 'ModuleExports', 'Unit'); Notes = 'CSV destination with near-integration tests.' }
    'Templates/Modules/Destination/Destination.MSSQL.psm1' = @{ Coverage = @('Syntax', 'Analyzer', 'ModuleExports', 'Unit'); Notes = 'MSSQL destination with unit tests for helpers and configuration paths.' }
    'Templates/Modules/Source/Source.CSV.psm1' = @{ Coverage = @('Syntax', 'Analyzer', 'ModuleExports', 'Unit'); Notes = 'CSV source with near-integration tests.' }
    'Templates/Modules/Source/Source.CustomScript.psm1' = @{ Coverage = @('Syntax', 'Analyzer', 'ModuleExports', 'Unit'); Notes = 'Custom script source with unit/integration tests.' }
    'Templates/Modules/Source/Source.JSON.psm1' = @{ Coverage = @('Syntax', 'Analyzer', 'ModuleExports', 'Unit'); Notes = 'JSON/JSONL source with near-integration tests.' }
    'Templates/Modules/Source/Source.LDAP.psm1' = @{ Coverage = @('Syntax', 'Analyzer', 'ModuleExports', 'Unit'); Notes = 'LDAP source: configuration validation via unit tests without directory services.' }
    'Templates/Modules/Source/Source.MSSQL.psm1' = @{ Coverage = @('Syntax', 'Analyzer', 'ModuleExports', 'Unit'); Notes = 'MSSQL source with unit tests for configuration and connection helpers.' }
    'Templates/Modules/Source/Source.XLSX.psm1' = @{ Coverage = @('Syntax', 'Analyzer', 'ModuleExports', 'Unit'); Notes = 'XLSX source: configuration validation via unit tests without workbook runtime.' }
    'Templates/Modules/Source/Source.XML.psm1' = @{ Coverage = @('Syntax', 'Analyzer', 'ModuleExports', 'Unit'); Notes = 'XML source with flattening/extraction tests.' }
    'Templates/Installers/DotNet/NDP481-x86-x64-AllOS-ENU.exe' = @{ Coverage = @('Manifest'); Notes = 'Bundled offline .NET Framework 4.8.1 installer used by wizard prerequisite workflow.' }

    'Wizard/Bootstrap.ps1' = @{ Coverage = @('Syntax', 'Analyzer', 'Unit'); Notes = 'Bootstrap script loaded via dynamic loader test.' }
    'Wizard/Helpers/Wizard.Adapter.ps1' = @{ Coverage = @('Syntax', 'Analyzer', 'Unit'); Notes = 'Adapter helpers with template/file tests.' }
    'Wizard/Helpers/Wizard.Config.ps1' = @{ Coverage = @('Syntax', 'Analyzer', 'Unit'); Notes = 'Configuration helpers with unit tests.' }
    'Wizard/Helpers/Wizard.Credentials.ps1' = @{ Coverage = @('Syntax', 'Analyzer', 'Unit'); Notes = 'Credential helpers with mock-based unit tests.' }
    'Wizard/Helpers/Wizard.CustomScript.ps1' = @{ Coverage = @('Syntax', 'Analyzer', 'Unit'); Notes = 'Custom script helpers covered indirectly via source/wizard tests.' }
    'Wizard/Helpers/Wizard.Destinations.ps1' = @{ Coverage = @('Syntax', 'Analyzer', 'Unit'); Notes = 'Destination helpers with mock-based unit tests.' }
    'Wizard/Helpers/Wizard.EntryPoint.ps1' = @{ Coverage = @('Syntax', 'Analyzer', 'Unit'); Notes = 'Bootstrap/entry-point helpers for New-ETLProject.ps1.' }
    'Wizard/Helpers/Wizard.FileSources.ps1' = @{ Coverage = @('Syntax', 'Analyzer', 'Unit'); Notes = 'File source helpers with pattern/prompt tests.' }
    'Wizard/Helpers/Wizard.LogFacade.ps1' = @{ Coverage = @('Syntax', 'Analyzer', 'Unit'); Notes = 'Logging facade with delegation test.' }
    'Wizard/Helpers/Wizard.PreReqs.ps1' = @{ Coverage = @('Syntax', 'Analyzer', 'Unit'); Notes = '.NET/runtime prerequisite helpers; fully integrated into the wizard.' }
    'Wizard/Helpers/Wizard.Paths.ps1' = @{ Coverage = @('Syntax', 'Analyzer', 'Unit'); Notes = 'Path helpers with unit tests.' }
    'Wizard/Helpers/Wizard.ProjectFiles.ps1' = @{ Coverage = @('Syntax', 'Analyzer', 'Unit'); Notes = 'File/template helpers with filesystem tests.' }
    'Wizard/Helpers/Wizard.ProjectWizard.ps1' = @{ Coverage = @('Syntax', 'Analyzer', 'Unit'); Notes = 'Project wizard orchestration with harness/filesystem tests.' }
    'Wizard/Helpers/Wizard.Prompts.ps1' = @{ Coverage = @('Syntax', 'Analyzer', 'Unit'); Notes = 'Prompt helpers with mock-based input tests.' }
    'Wizard/Helpers/Wizard.Schedule.ps1' = @{ Coverage = @('Syntax', 'Analyzer', 'Unit'); Notes = 'Task schedule helpers with XML tests.' }
    'Wizard/Helpers/Wizard.Sources.ps1' = @{ Coverage = @('Syntax', 'Analyzer', 'Unit'); Notes = 'Source helpers with mock-based configuration tests.' }
    'Wizard/Modules/Wizard.Logging.psm1' = @{ Coverage = @('Syntax', 'Analyzer', 'ModuleExports', 'Unit'); Notes = 'Wizard logging module with unit tests.' }
}
