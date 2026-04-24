<#
    Helper functions for orchestrating New-ETLProject.ps1.
#>

function Write-Ui {
    [CmdletBinding()]
    param(
        [AllowEmptyString()][string] $Message,
        [string] $ForegroundColor
    )

    Write-Information -MessageData $Message -InformationAction Continue
}

function Invoke-NewEtlProjectWizard {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $ScriptPath,
        [Parameter(Mandatory)][string] $ScriptDirectory,
        [string] $DefaultBaseDirectory = 'C:\ProgramData\SoftwareOne\01_Import',
        [bool]   $LogFileAppend = $true,

        [ValidateSet('4.7','4.7.1','4.7.2','4.8','4.8.1')]
        [string] $RequiredDotNetVersion = '4.7',

        [bool]   $RequireDotNet = $true,
        [bool]   $AllowDotNetInstall = $true,
        [string] $DotNetOfflineInstallerPath = ''
    )

    $TemplatePath = Join-Path -Path $ScriptDirectory -ChildPath 'Templates'
    $RuntimeTemplatePath = Join-Path -Path $TemplatePath -ChildPath 'Runtime'
    $ModulesTemplateRootPath = Join-Path -Path $TemplatePath -ChildPath 'Modules'
    $CommonTemplatePath = Join-Path -Path $ModulesTemplateRootPath -ChildPath 'Common'
    $CredentialTemplateRootPath = Join-Path -Path $ModulesTemplateRootPath -ChildPath 'Credential'
    $SourceTemplateRootPath = Join-Path -Path $ModulesTemplateRootPath -ChildPath 'Source'
    $DestinationTemplateRootPath = Join-Path -Path $ModulesTemplateRootPath -ChildPath 'Destination'
    $AdapterTemplateRootPath = Join-Path -Path $ModulesTemplateRootPath -ChildPath 'Adapter'
    $ModuleDependenciesTemplateRootPath = Join-Path -Path $ModulesTemplateRootPath -ChildPath 'Dependencies'
    $ExcelDataReaderTemplateRootPath = Join-Path -Path $ModuleDependenciesTemplateRootPath -ChildPath 'ExcelDataReader'
    $TaskTemplateRootPath = Join-Path -Path $TemplatePath -ChildPath 'Task'
    $ScriptName = (Get-Item -Path $ScriptPath).BaseName
    $BuildDate = (Get-Item -Path $ScriptPath).LastWriteTime.ToString('yyyy-MM-dd')
    $LogDirectory = Join-Path -Path $ScriptDirectory -ChildPath 'Log'
    $LogFile = Join-Path -Path $LogDirectory -ChildPath ("{0}_{1}.log" -f $ScriptName, (Get-Date -Format 'yyyyMMdd_HHmmss'))
    $LogFileRetentionDays = 30

    $Script:LogContext = Initialize-WizardLogContext -LogDirectory $LogDirectory -LogFile $LogFile -LogLevel 'INFO' -RetentionDays $LogFileRetentionDays -Append $LogFileAppend -CleanupKey ('ProjectWizard::{0}' -f $ScriptName)

    try {
        Clear-Host
        Write-Ui "==============================================" -ForegroundColor Magenta
        Write-Ui "      ETL SOLUTION WIZARD v23.1.0             " -ForegroundColor Magenta
        Write-Ui "==============================================" -ForegroundColor Magenta

        Write-Log "--- SCRIPT STARTED ---" -Level 'INFO'
        Write-Log "Name: $ScriptName | BuildDate: $BuildDate" -Level 'INFO'
        Write-Log "TemplatePath: $TemplatePath" -Level 'INFO'

        if (-not (Test-PathExists -Path $TemplatePath -PathType Container -Description 'Template root directory')) {
            throw 'Template root directory validation failed.'
        }

        if (-not (Test-PathExists -Path $RuntimeTemplatePath -PathType Container -Description 'Runtime template directory')) {
            throw 'Runtime template directory validation failed.'
        }

        if (-not (Test-PathExists -Path $CommonTemplatePath -PathType Container -Description 'Common module template directory')) {
            throw 'Common module template directory validation failed.'
        }

        if (-not (Test-PathExists -Path $CredentialTemplateRootPath -PathType Container -Description 'Credential template directory')) {
            throw 'Credential template directory validation failed.'
        }

        if (-not (Test-PathExists -Path $SourceTemplateRootPath -PathType Container -Description 'Source template directory')) {
            throw 'Source template directory validation failed.'
        }

        if (-not (Test-PathExists -Path $DestinationTemplateRootPath -PathType Container -Description 'Destination template directory')) {
            throw 'Destination template directory validation failed.'
        }

        if (-not (Test-PathExists -Path $AdapterTemplateRootPath -PathType Container -Description 'Adapter template directory')) {
            throw 'Adapter template directory validation failed.'
        }

        if (-not (Test-PathExists -Path $ModuleDependenciesTemplateRootPath -PathType Container -Description 'Module dependencies template directory')) {
            throw 'Module dependencies template directory validation failed.'
        }

        if (-not (Test-PathExists -Path $TaskTemplateRootPath -PathType Container -Description 'Task template directory')) {
            throw 'Task template directory validation failed.'
        }

        if ($RequireDotNet) {
            $PreReqResult = Invoke-WizardPrerequisiteWorkflow -MinimumVersion $RequiredDotNetVersion -FrameworkRoot $ScriptDirectory -AllowInstallIfMissing:$AllowDotNetInstall -OfflineInstallerPath $DotNetOfflineInstallerPath
            if (-not $PreReqResult.RequirementMet) {
                if ($PreReqResult.UserDeclinedInstall) {
                    throw ".NET Framework prerequisite installation was declined. Required version: $RequiredDotNetVersion"
                }

                throw ".NET Framework prerequisite check failed. Required version: $RequiredDotNetVersion"
            }
        }
        else {
            Write-Log '.NET Framework prerequisite check skipped by configuration.' -Level 'WARN'
        }

        $ProjectNameInput = Read-InputValue -Prompt 'Project Name' -Default 'MyETL'
        $ProjectName = Get-SafePathSegment -Value $ProjectNameInput -Fallback 'MyETL'
        if ($ProjectName -ne $ProjectNameInput) {
            Write-Log "Project name normalized from [$ProjectNameInput] to [$ProjectName]." -Level 'WARN'
        }

        $BaseDirectoryInput = Read-InputValue -Prompt 'Base Directory' -Default $DefaultBaseDirectory
        Test-InvalidPathChars -Value $BaseDirectoryInput -Description 'Base directory'
        $BaseDirectory = Resolve-NormalizedPath -Path $BaseDirectoryInput
        Test-DirectoryWritable -Path $BaseDirectory -Description 'Base directory'
        Write-Log "Resolved base directory: $BaseDirectory" -Level 'INFO'

        $TargetDir = Resolve-NormalizedPath -Path $ProjectName -BasePath $BaseDirectory

        if (Test-Path -Path $TargetDir) {
            Write-Log "Target directory already exists: $TargetDir" -Level 'WARN'
            $Overwrite = Read-BooleanChoice -Prompt 'Target directory already exists. Continue and overwrite files?' -Default $false
            if (-not $Overwrite) {
                Write-Log 'User aborted project creation.' -Level 'WARN'
                return 0
            }

            Clear-GeneratedProjectArtifacts -ProjectRoot $TargetDir
            Write-Log 'Existing generated runtime and task artifacts were removed before regeneration.' -Level 'WARN'
        }
        else {
            New-Item -Path $TargetDir -ItemType Directory -Force | Out-Null
            Write-Log "Created target root directory: $TargetDir" -Level 'INFO'
        }

        $RunDir = Resolve-NormalizedPath -Path 'RUN' -BasePath $TargetDir
        $LogDir = Resolve-NormalizedPath -Path 'LOG' -BasePath $TargetDir
        $InputDir = Resolve-NormalizedPath -Path 'INPUT' -BasePath $TargetDir
        $OutputDir = Resolve-NormalizedPath -Path 'OUTPUT' -BasePath $TargetDir
        $InputBackupDir = Resolve-NormalizedPath -Path 'INPUT\_Backup' -BasePath $TargetDir
        $TaskDir = Resolve-NormalizedPath -Path 'TASK' -BasePath $TargetDir
        $ModuleRootDir = Resolve-NormalizedPath -Path 'Modules' -BasePath $RunDir
        $ModuleSourceDir = Resolve-NormalizedPath -Path 'Source' -BasePath $ModuleRootDir
        $ModuleDestDir = Resolve-NormalizedPath -Path 'Destination' -BasePath $ModuleRootDir
        $ModuleCredentialDir = Resolve-NormalizedPath -Path 'Credential' -BasePath $ModuleRootDir
        $ModuleCommonDir = Resolve-NormalizedPath -Path 'Common' -BasePath $ModuleRootDir
        $ModuleAdapterDir = Resolve-NormalizedPath -Path 'Adapter' -BasePath $ModuleRootDir
        $CustomScriptDir = Resolve-NormalizedPath -Path 'PS' -BasePath $TargetDir
        $AdapterTemplateFile = Resolve-NormalizedPath -Path 'Adapter.BAS.xml' -BasePath $AdapterTemplateRootPath
        $ModuleDependenciesDir = Resolve-NormalizedPath -Path 'Dependencies' -BasePath $ModuleRootDir
        $ModuleExcelReaderDir = Resolve-NormalizedPath -Path 'ExcelDataReader' -BasePath $ModuleDependenciesDir

        Write-Log "Resolved target directory: $TargetDir" -Level 'INFO'
        Write-Log "Resolved run directory: $RunDir" -Level 'INFO'
        Write-Log "Resolved input directory: $InputDir" -Level 'INFO'
        Write-Log "Resolved output directory: $OutputDir" -Level 'INFO'
        Write-Log "Resolved input backup directory: $InputBackupDir" -Level 'INFO'
        Write-Log "Resolved task directory: $TaskDir" -Level 'INFO'
        Write-Log "Resolved custom script directory: $CustomScriptDir" -Level 'INFO'

        $AvailableSourceTypes = @(Get-AvailableSourceTypes -SourceTemplateRootPath $SourceTemplateRootPath)
        if (-not $AvailableSourceTypes -or $AvailableSourceTypes.Count -eq 0) {
            throw "No source adapter templates found under: $SourceTemplateRootPath"
        }

        $AvailableDestinationTypes = @(Get-AvailableDestinationTypes -DestinationTemplateRootPath $DestinationTemplateRootPath)
        if (-not $AvailableDestinationTypes -or $AvailableDestinationTypes.Count -eq 0) {
            throw "No destination adapter templates found under: $DestinationTemplateRootPath"
        }

        Write-Log ("Discovered source adapter templates: {0}" -f ($AvailableSourceTypes -join ', ')) -Level 'INFO'
        Write-Log ("Discovered destination adapter templates: {0}" -f ($AvailableDestinationTypes -join ', ')) -Level 'INFO'

        $StepCount = Read-PositiveInteger -Prompt 'How many ETL steps should be created?' -Default 1
        $LogLevel = Read-Choice -Title 'SELECT LOG LEVEL' -Options @('INFO', 'DEBUG')
        $RetentionDays = [string](Read-PositiveInteger -Prompt 'Log retention days' -Default 30)

        $Pipelines = New-Object System.Collections.Generic.List[hashtable]
        $RequiredSourceTypes = New-Object System.Collections.Generic.List[string]
        $RequiredDestinationTypes = New-Object System.Collections.Generic.List[string]
        $CredentialSetups = New-Object System.Collections.Generic.List[object]
        $NeedInputFolder = $false
        $NeedOutputFolder = $false
        $NeedExcelDataReaderRuntime = $false
        $NeedAdapterRuntime = $false
        $NeedInputBackupFolder = $false
        $NeedCustomScriptFolder = $false

        for ($i = 1; $i -le $StepCount; $i++) {
            $StepId = "{0:D2}" -f $i

            Write-Ui ''
            Write-Ui '==============================================' -ForegroundColor Yellow
            Write-Ui ("Configure Step [{0}]" -f $StepId) -ForegroundColor Yellow
            Write-Ui '==============================================' -ForegroundColor Yellow

            $StepName = Read-InputValue -Prompt ("Step Name for [{0}]" -f $StepId) -Default ("Step-{0}" -f $StepId)

            $SourceType = Read-Choice -Title ("SELECT SOURCE FOR STEP [{0}]" -f $StepId) -Options $AvailableSourceTypes
            $SourceData = Get-SourceConfigFromWizard -SourceType $SourceType -ProjectName $ProjectName -StepId $StepId

            $DestinationType = Read-Choice -Title ("SELECT DESTINATION FOR STEP [{0}]" -f $StepId) -Options $AvailableDestinationTypes
            $DestinationData = Get-DestinationConfigFromWizard -DestinationType $DestinationType -ProjectName $ProjectName -StepId $StepId

            if ($RequiredSourceTypes -notcontains $SourceType) { [void]$RequiredSourceTypes.Add($SourceType) }
            if ($RequiredDestinationTypes -notcontains $DestinationType) { [void]$RequiredDestinationTypes.Add($DestinationType) }

            if ($SourceType -eq 'XLSX') { $NeedExcelDataReaderRuntime = $true }
            if ($SourceData.CreateInput) { $NeedInputFolder = $true }
            if ($SourceData.CreateInput -and $SourceType -in @('CSV','XLSX','XML','JSON')) { $NeedInputBackupFolder = $true }
            if ($DestinationData.CreateOutput) { $NeedOutputFolder = $true }

            if ($SourceType -eq 'CustomScript') {
                $ProjectScriptPath = Copy-CustomSourceScriptToProject -SourcePath ([string]$SourceData.Config.ScriptPath) -ProjectScriptDirectory $CustomScriptDir -StepId $StepId -StepName $StepName
                $RelativeScriptPath = $ProjectScriptPath.Substring($TargetDir.Length).TrimStart('\')
                $SourceData.Config['ScriptPath'] = $RelativeScriptPath
                $NeedCustomScriptFolder = $true
            }

            if ($SourceData.CredentialSetup) { [void]$CredentialSetups.Add($SourceData.CredentialSetup) }
            if ($DestinationData.CredentialSetup) { [void]$CredentialSetups.Add($DestinationData.CredentialSetup) }

            $Pipelines.Add([ordered]@{
                StepId = $StepId
                Name = $StepName
                StepEnabled = $true
                Source = [ordered]@{ Type = $SourceType; Config = $SourceData.Config }
                Destination = [ordered]@{ Type = $DestinationType; Config = $DestinationData.Config }
                Properties = @($SourceData.Properties)
            })
        }

        foreach ($Directory in @($RunDir, $LogDir, $TaskDir, $ModuleCommonDir, $ModuleSourceDir, $ModuleDestDir, $ModuleCredentialDir)) {
            New-Item -Path $Directory -ItemType Directory -Force | Out-Null
            Write-Log "Directory ensured: $Directory" -Level 'INFO'
        }

        if ($NeedInputFolder) { New-Item -Path $InputDir -ItemType Directory -Force | Out-Null; Write-Log "Directory ensured: $InputDir" -Level 'INFO' }
        if ($NeedInputBackupFolder) { New-Item -Path $InputBackupDir -ItemType Directory -Force | Out-Null; Write-Log "Directory ensured: $InputBackupDir" -Level 'INFO' }
        if ($NeedOutputFolder) { New-Item -Path $OutputDir -ItemType Directory -Force | Out-Null; Write-Log "Directory ensured: $OutputDir" -Level 'INFO' }
        if ($NeedCustomScriptFolder) { New-Item -Path $CustomScriptDir -ItemType Directory -Force | Out-Null; Write-Log "Directory ensured: $CustomScriptDir" -Level 'INFO' }

        if ($NeedExcelDataReaderRuntime) {
            foreach ($Directory in @($ModuleDependenciesDir, $ModuleExcelReaderDir)) {
                New-Item -Path $Directory -ItemType Directory -Force | Out-Null
                Write-Log "Directory ensured: $Directory" -Level 'INFO'
            }

            Copy-TemplateDirectory -SourcePath $ExcelDataReaderTemplateRootPath -DestinationPath $ModuleExcelReaderDir -Description 'ExcelDataReader runtime directory'
            Get-ChildItem -Path $ModuleExcelReaderDir -File -ErrorAction SilentlyContinue | ForEach-Object {
                try { Unblock-File -Path $_.FullName -ErrorAction Stop }
                catch { Write-Warning ("Failed to unblock dependency file: {0} | {1}" -f $_.FullName, $_.Exception.Message) }
            }
        }

        $RunTemplatePath = Join-Path -Path $RuntimeTemplatePath -ChildPath 'Run-ETL.ps1'
        $CommonTemplateFilePath = Join-Path -Path $CommonTemplatePath -ChildPath 'Framework.Common.psm1'
        $LoggingTemplateFilePath = Join-Path -Path $CommonTemplatePath -ChildPath 'Framework.Logging.psm1'
        $ValidationTemplateFilePath = Join-Path -Path $CommonTemplatePath -ChildPath 'Framework.Validation.psm1'
        $AdapterFlexeraTemplatePath = Join-Path -Path $AdapterTemplateRootPath -ChildPath 'Adapter.Flexera.psm1'
        $CredentialTemplatePath = Join-Path -Path $CredentialTemplateRootPath -ChildPath 'Credential.Manager.psm1'
        $TaskTemplatePath = Join-Path -Path $TaskTemplateRootPath -ChildPath 'Register-Task.ps1'

        Copy-TemplateFile -SourcePath $RunTemplatePath -DestinationPath (Join-Path -Path $RunDir -ChildPath 'Run-ETL.ps1') -Description 'Run controller script'
        Copy-TemplateFile -SourcePath $AdapterFlexeraTemplatePath -DestinationPath (Join-Path -Path $ModuleAdapterDir -ChildPath 'Adapter.Flexera.psm1') -Description 'Flexera adapter module'
        Copy-TemplateFile -SourcePath $CommonTemplateFilePath -DestinationPath (Join-Path -Path $ModuleCommonDir -ChildPath 'Framework.Common.psm1') -Description 'Common runtime module'
        Copy-TemplateFile -SourcePath $LoggingTemplateFilePath -DestinationPath (Join-Path -Path $ModuleCommonDir -ChildPath 'Framework.Logging.psm1') -Description 'Logging runtime module'
        Copy-TemplateFile -SourcePath $ValidationTemplateFilePath -DestinationPath (Join-Path -Path $ModuleCommonDir -ChildPath 'Framework.Validation.psm1') -Description 'Validation runtime module'
        Copy-TemplateFile -SourcePath $CredentialTemplatePath -DestinationPath (Join-Path -Path $ModuleCredentialDir -ChildPath 'Credential.Manager.psm1') -Description 'Credential support module'

        foreach ($SourceType in $RequiredSourceTypes) {
            $SourceTemplatePath = Join-Path -Path $SourceTemplateRootPath -ChildPath ("Source.{0}.psm1" -f $SourceType)
            $SourceTargetPath = Join-Path -Path $ModuleSourceDir -ChildPath ("Source.{0}.psm1" -f $SourceType)
            Copy-TemplateFile -SourcePath $SourceTemplatePath -DestinationPath $SourceTargetPath -Description ("Source adapter module [{0}]" -f $SourceType)
        }

        foreach ($DestinationType in $RequiredDestinationTypes) {
            $DestinationTemplatePath = Join-Path -Path $DestinationTemplateRootPath -ChildPath ("Destination.{0}.psm1" -f $DestinationType)
            $DestinationTargetPath = Join-Path -Path $ModuleDestDir -ChildPath ("Destination.{0}.psm1" -f $DestinationType)
            Copy-TemplateFile -SourcePath $DestinationTemplatePath -DestinationPath $DestinationTargetPath -Description ("Destination adapter module [{0}]" -f $DestinationType)
        }

        foreach ($CredentialSetup in $CredentialSetups.ToArray()) { Initialize-ProjectCredential -Target $CredentialSetup.Target -Credential $CredentialSetup.Credential }

        $Adapter = Read-AdapterConfiguration -ProjectName $ProjectName
        $AdapterFilePath = $null
        if ($Adapter.AdapterEnabled) {
            $NeedAdapterRuntime = $true
            $AdapterFilePath = New-AdapterXmlFile -Adapter $Adapter -AdapterDirectory $ModuleAdapterDir -TemplatePath $AdapterTemplateFile
        }

        $ConfigContent = New-ConfigContent -Pipelines $Pipelines.ToArray() -LogLevel $LogLevel -RetentionDays $RetentionDays -Adapter $Adapter.Config
        $ConfigPath = Join-Path -Path $RunDir -ChildPath 'config.psd1'
        Set-Content -Path $ConfigPath -Value $ConfigContent -Encoding UTF8
        Write-Log "ETL configuration file created: $ConfigPath" -Level 'INFO'

        $Schedule = Read-ScheduleConfiguration -ProjectName $ProjectName
        $TaskFilePath = $null
        $RegisterTaskScriptPath = $null
        if ($Schedule.Enabled) {
            $RunScriptPath = Join-Path -Path $RunDir -ChildPath 'Run-ETL.ps1'
            $TaskFilePath = New-TaskSchedulerDefinitionFile -TaskDirectory $TaskDir -RunScriptPath $RunScriptPath -WorkingDirectory $RunDir -Schedule $Schedule
            if ($TaskFilePath) {
                $RegisterTaskScriptPath = New-TaskRegistrationScriptFile -Schedule $Schedule -TaskDirectory $TaskDir -TaskTemplatePath $TaskTemplatePath
            }
        }
        else {
            Write-Log 'Task creation skipped by user.' -Level 'WARN'
        }

        Write-Ui ''
        Write-Ui 'Project created successfully.' -ForegroundColor Green
        Write-Ui ("Project Path : {0}" -f $TargetDir) -ForegroundColor Gray
        Write-Ui ("Config Path  : {0}" -f $ConfigPath) -ForegroundColor Gray
        Write-Ui ("ETL Steps    : {0}" -f $Pipelines.Count) -ForegroundColor Gray
        foreach ($Pipeline in $Pipelines.ToArray()) {
            Write-Ui ("  [{0}] {1}: {2} -> {3}" -f $Pipeline.StepId, $Pipeline.Name, $Pipeline.Source.Type, $Pipeline.Destination.Type) -ForegroundColor Gray
        }
        if ($NeedInputFolder) { Write-Ui ("[+] Created INPUT directory: {0}" -f $InputDir) -ForegroundColor Gray }
        if ($NeedOutputFolder) { Write-Ui ("[+] Created OUTPUT directory: {0}" -f $OutputDir) -ForegroundColor Gray }
        if ($NeedExcelDataReaderRuntime) { Write-Ui ("[+] Copied ExcelDataReader runtime to: {0}" -f $ModuleExcelReaderDir) -ForegroundColor Gray }
        if ($NeedCustomScriptFolder) { Write-Ui ("[+] Created PS directory for custom source scripts: {0}" -f $CustomScriptDir) -ForegroundColor Gray }
        if ($NeedAdapterRuntime -and $AdapterFilePath) {
            Write-Ui ("[+] Created Adapter directory: {0}" -f $ModuleAdapterDir) -ForegroundColor Gray
            Write-Ui ("[+] Created Adapter XML: {0}" -f $AdapterFilePath) -ForegroundColor Gray
            Write-Ui '    Edit the dummy adapter XML before productive use.' -ForegroundColor Yellow
        }
        Write-Ui ("[+] Created TASK directory: {0}" -f $TaskDir) -ForegroundColor Gray
        if ($TaskFilePath) { Write-Ui ("[+] Created Task XML: {0}" -f $TaskFilePath) -ForegroundColor Gray }
        if ($RegisterTaskScriptPath) {
            Write-Ui ("[+] Created Task registration script: {0}" -f $RegisterTaskScriptPath) -ForegroundColor Gray
            Write-Ui ("    Run elevated: powershell.exe -ExecutionPolicy Bypass -File `"{0}`"" -f $RegisterTaskScriptPath) -ForegroundColor Yellow
            Write-Ui '    The script will securely prompt for the RunAs password when -RunAsPassword is omitted.' -ForegroundColor Yellow
        }
        Write-Ui ''
        Write-Ui (".NET Requirement: {0} | Check Enabled: {1}" -f $RequiredDotNetVersion, $RequireDotNet) -ForegroundColor Gray
        Write-Ui ("Execute: cd '{0}'; .\Run-ETL.ps1" -f $RunDir) -ForegroundColor White

        Write-Log '--- SCRIPT COMPLETED SUCCESSFULLY ---' -Level 'INFO'
        return 0
    }
    catch {
        Write-WizardException -Context $Script:LogContext -ErrorRecord $_ -Prefix 'FATAL SCRIPT ERROR:'
        return 1
    }
    finally {
        Write-Log '--- SCRIPT EXECUTION ENDED ---' -Level 'INFO'
    }
}
