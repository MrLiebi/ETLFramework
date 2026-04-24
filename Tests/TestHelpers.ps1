# Shared helpers for framework tests. Comments use American English spelling.

Set-StrictMode -Version Latest

function Get-FrameworkRoot {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [string]$StartPath = $PSScriptRoot
    )

    $Current = (Resolve-Path -LiteralPath $StartPath).Path
    while ($true) {
        if ((Test-Path -LiteralPath (Join-Path -Path $Current -ChildPath 'Templates') -PathType Container) -and
            (Test-Path -LiteralPath (Join-Path -Path $Current -ChildPath 'Wizard') -PathType Container)) {
            return $Current
        }

        $Parent = Split-Path -Path $Current -Parent
        if ([string]::IsNullOrWhiteSpace($Parent) -or $Parent -eq $Current) {
            break
        }

        $Current = $Parent
    }

    throw "Framework root could not be resolved from start path: $StartPath"
}

function Get-RelativeFrameworkPath {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory)][string]$FrameworkRoot,
        [Parameter(Mandatory)][string]$Path
    )

    $ResolvedRoot = [System.IO.Path]::GetFullPath($FrameworkRoot)
    $ResolvedPath = [System.IO.Path]::GetFullPath($Path)

    if ($ResolvedPath.StartsWith($ResolvedRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
        return ($ResolvedPath.Substring($ResolvedRoot.Length).TrimStart('\', '/')).Replace('\', '/')
    }

    return $ResolvedPath
}

function Get-FrameworkSourceFiles {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [string]$FrameworkRoot = (Get-FrameworkRoot)
    )

    Get-ChildItem -Path $FrameworkRoot -Recurse -File -Include *.ps1, *.psm1 |
        Where-Object {
            $_.FullName -notmatch '[\\/](Tests|\.git)[\\/]' -and
            $_.FullName -notmatch '[\\/]Templates[\\/]Modules[\\/]Dependencies[\\/]' -and
            $_.FullName -notmatch '[\\/]\.github[\\/]'
        } |
        Sort-Object -Property FullName
}

function Get-FrameworkManifestTrackedFiles {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [string]$FrameworkRoot = (Get-FrameworkRoot)
    )

    Get-ChildItem -Path $FrameworkRoot -Recurse -File -Include *.ps1, *.psm1, *.exe |
        Where-Object {
            $_.FullName -notmatch '[\\/](Tests|\.git)[\\/]' -and
            $_.FullName -notmatch '[\\/]Templates[\\/]Modules[\\/]Dependencies[\\/]' -and
            $_.FullName -notmatch '[\\/]\.github[\\/]'
        } |
        Sort-Object -Property FullName
}

function Get-ScriptAnalyzerTargetFiles {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [string]$FrameworkRoot = (Get-FrameworkRoot)
    )

    @(Get-FrameworkSourceFiles -FrameworkRoot $FrameworkRoot | Select-Object -ExpandProperty FullName)
}

function Disable-EtlFrameworkWizardAutomationForInteractivePromptTests {
    [CmdletBinding()]
    param()

    Remove-Item Env:ETL_FRAMEWORK_TEST_AUTOMATION -ErrorAction SilentlyContinue
    Remove-Item Env:ETL_TEST_NONINTERACTIVE -ErrorAction SilentlyContinue
}

function Enable-EtlFrameworkWizardAutomationAfterInteractivePromptTests {
    [CmdletBinding()]
    param()

    Set-EtlFrameworkTestHostDefaults -Full
}

function Set-EtlFrameworkTestHostDefaults {
    [CmdletBinding()]
    param(
        [switch]$Full
    )

    $env:ETL_FRAMEWORK_TEST_AUTOMATION = '1'
    $env:ETL_TASK_RUNAS_PASSWORD = 'etl-test-task-password'

    if (-not $Full) {
        return
    }

    $env:ETL_TEST_NONINTERACTIVE = '1'
    if (-not $env:ETL_TEST_CREDENTIAL_USERNAME) { $env:ETL_TEST_CREDENTIAL_USERNAME = 'etl-test-user' }
    if (-not $env:ETL_TEST_CREDENTIAL_PASSWORD) { $env:ETL_TEST_CREDENTIAL_PASSWORD = 'etl-test-password' }
}

function Set-FrameworkTestEnvironment {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [string]$ProjectRoot = (Join-Path -Path $TestDrive -ChildPath 'Project'),
        [string]$RunId = 'TEST_RUN_0001'
    )

    $LogRoot = Join-Path -Path $ProjectRoot -ChildPath 'LOG'
    New-Item -Path $ProjectRoot -ItemType Directory -Force | Out-Null
    New-Item -Path $LogRoot -ItemType Directory -Force | Out-Null

    $env:ETL_PROJECT_ROOT = $ProjectRoot
    $env:ETL_LOG_ROOT = $LogRoot
    $env:ETL_RUN_ID = $RunId
    $env:ETL_LOG_LEVEL = 'DEBUG'
    $env:ETL_MODULE_LOGS = 'true'
    $env:ETL_LOG_RETENTION_DAYS = '30'
    Set-EtlFrameworkTestHostDefaults -Full

    [PSCustomObject]@{
        ProjectRoot = $ProjectRoot
        LogRoot     = $LogRoot
        RunId       = $RunId
    }
}

function Clear-FrameworkTestEnvironment {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param()

    foreach ($Name in @(
        'ETL_PROJECT_ROOT',
        'ETL_LOG_ROOT',
        'ETL_RUN_ID',
        'ETL_LOG_LEVEL',
        'ETL_MODULE_LOGS',
        'ETL_LOG_RETENTION_DAYS',
        'ETL_STEP_ID',
        'ETL_LAST_SOURCE_FILE',
        'ETL_LAST_SOURCE_TYPE'
    )) {
        Remove-Item -Path ("Env:{0}" -f $Name) -ErrorAction SilentlyContinue
    }

    # Restore wizard + task defaults so later tests never block on Read-Host / Register-Task password prompts.
    Set-EtlFrameworkTestHostDefaults -Full
}

function Import-TestableAsset {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory)][string]$RelativePath,
        [string]$ModuleName,
        [string[]]$AdditionalRelativePaths = @()
    )

    $FrameworkRoot = Get-FrameworkRoot
    $FullPath = Join-Path -Path $FrameworkRoot -ChildPath $RelativePath
    if (-not (Test-Path -LiteralPath $FullPath -PathType Leaf)) {
        throw "Asset not found: $FullPath"
    }

    $DependencyPaths = @(
        $AdditionalRelativePaths |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
            ForEach-Object { Join-Path -Path $FrameworkRoot -ChildPath $_ }
    )

    foreach ($DependencyPath in $DependencyPaths) {
        if (-not (Test-Path -LiteralPath $DependencyPath -PathType Leaf)) {
            throw "Dependent asset not found: $DependencyPath"
        }
    }

    if ($FullPath -like '*.psm1') {
        return Import-Module -Name $FullPath -Force -PassThru
    }

    if ($FullPath -like '*.ps1') {
        if ([string]::IsNullOrWhiteSpace($ModuleName)) {
            $ModuleName = ([System.IO.Path]::GetFileNameWithoutExtension($FullPath) -replace '[^A-Za-z0-9_.-]', '_') + '.DynamicTests'
        }

        $DynamicModule = New-Module -Name $ModuleName -ScriptBlock {
            param($ScriptPath, $DependencyPaths)

            function Write-Log {
                [CmdletBinding(SupportsShouldProcess = $true)]
                param(
                    [Parameter(Mandatory)][string]$Message,
                    [string]$Level = 'INFO'
                )
            }

            function Write-WizardLog {
                [CmdletBinding(SupportsShouldProcess = $true)]
                param(
                    [Parameter(Mandatory)]$Context,
                    [Parameter(Mandatory)][string]$Message,
                    [ValidateSet('DEBUG','INFO','WARN','ERROR')][string]$Level = 'INFO'
                )
            }

            function Read-Choice {
                [CmdletBinding(SupportsShouldProcess = $true)]
                param(
                    [Parameter(Mandatory)][string]$Title,
                    [Parameter(Mandatory)][string[]]$Options
                )
                return $Options[0]
            }

            function Read-BooleanChoice {
                [CmdletBinding(SupportsShouldProcess = $true)]
                param(
                    [Parameter(Mandatory)][string]$Prompt,
                    [bool]$Default = $false
                )
                return $Default
            }

            function Read-InputValue {
                [CmdletBinding(SupportsShouldProcess = $true)]
                param(
                    [Parameter(Mandatory)][string]$Prompt,
                    [string]$Default = '',
                    [switch]$AllowEmpty
                )
                return $Default
            }


            function Initialize-WizardLogContext {
                [CmdletBinding(SupportsShouldProcess = $true)]
                param(
                    [Parameter(Mandatory)][string]$LogDirectory,
                    [Parameter(Mandatory)][string]$LogFile,
                    [string]$LogLevel = 'INFO',
                    [int]$RetentionDays = 30,
                    [bool]$Append = $true,
                    [string]$CleanupKey
                )
                return [PSCustomObject]@{ LogDirectory = $LogDirectory; LogFile = $LogFile; LogLevel = $LogLevel; CleanupKey = $CleanupKey }
            }

            function Write-WizardException {
                [CmdletBinding(SupportsShouldProcess = $true)]
                param(
                    [Parameter(Mandatory)]$Context,
                    [Parameter(Mandatory)]$ErrorRecord,
                    [string]$Prefix = 'ERROR:'
                )
            }

            function Set-StoredCredential {
                [CmdletBinding(SupportsShouldProcess = $true)]
                param(
                    [Parameter(Mandatory)][string]$Target,
                    [Parameter(Mandatory)][PSCredential]$Credential,
                    [string]$Comment
                )
            }

            function Get-StoredCredential {
                [CmdletBinding(SupportsShouldProcess = $true)]
                param(
                    [Parameter(Mandatory)][string]$Target,
                    [switch]$AsNetworkCredential
                )
                return [PSCustomObject]@{ UserName = 'etl'; Password = 's3cr3t' }
            }

            function Invoke-NewEtlProjectWizard {
                [CmdletBinding(SupportsShouldProcess = $true)]
                param(
                    [Parameter(Mandatory)][string]$ScriptPath,
                    [Parameter(Mandatory)][string]$ScriptDirectory,
                    [string]$DefaultBaseDirectory = '',
                    [bool]$LogFileAppend = $true,
                    [string]$RequiredDotNetVersion = '4.8.1',
                    [bool]$RequireDotNet = $true,
                    [bool]$AllowDotNetInstall = $true,
                    [string]$DotNetOfflineInstallerPath = ''
                )
                return 0
            }

            $Script:DotNetReleaseMap = @{
                '4.7'   = 460798
                '4.7.1' = 461308
                '4.7.2' = 461808
                '4.8'   = 528040
                '4.8.1' = 533320
            }

            foreach ($DependencyPath in @($DependencyPaths)) {
                . $DependencyPath
            }

            . $ScriptPath
            Export-ModuleMember -Function * -Alias *
        } -ArgumentList $FullPath, $DependencyPaths

        return Import-Module -ModuleInfo $DynamicModule -Force -PassThru
    }

    throw "Unsupported asset type: $FullPath"
}

function Remove-TestModuleSafely {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory)][object]$Module
    )

    $ModuleName = if ($Module -is [string]) { $Module } else { $Module.Name }
    if (-not [string]::IsNullOrWhiteSpace($ModuleName)) {
        Remove-Module -Name $ModuleName -Force -ErrorAction SilentlyContinue
    }
}


function Sort-ScriptAnalyzerFindings {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(ValueFromPipeline)][object[]]$InputObject
    )

    begin {
        $Items = New-Object System.Collections.Generic.List[object]
    }

    process {
        foreach ($Item in @($InputObject)) {
            if ($null -ne $Item) {
                [void]$Items.Add($Item)
            }
        }
    }

    end {
        $SortProperties = @(
            @{ Expression = {
                if ($_.PSObject.Properties['Severity']) { [string]$_.PSObject.Properties['Severity'].Value } else { '' }
            } }
            @{ Expression = {
                if ($_.PSObject.Properties['ScriptName']) {
                    [string]$_.PSObject.Properties['ScriptName'].Value
                }
                elseif ($_.PSObject.Properties['Extent'] -and $null -ne $_.PSObject.Properties['Extent'].Value) {
                    [string]$_.PSObject.Properties['Extent'].Value.File
                }
                else {
                    ''
                }
            } }
            @{ Expression = {
                if ($_.PSObject.Properties['Line']) {
                    [int]$_.PSObject.Properties['Line'].Value
                }
                elseif ($_.PSObject.Properties['LineNumber']) {
                    [int]$_.PSObject.Properties['LineNumber'].Value
                }
                elseif ($_.PSObject.Properties['StartLineNumber']) {
                    [int]$_.PSObject.Properties['StartLineNumber'].Value
                }
                elseif ($_.PSObject.Properties['Extent'] -and $null -ne $_.PSObject.Properties['Extent'].Value) {
                    [int]$_.PSObject.Properties['Extent'].Value.StartLineNumber
                }
                else {
                    0
                }
            } }
        )

        @($Items.ToArray()) | Sort-Object -Property $SortProperties
    }
}

function Invoke-ScriptAnalyzerCompat {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory)][string[]]$Path,
        [Parameter(Mandatory)][string]$SettingsPath
    )

    $ResolvedPaths = @(
        $Path |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
            ForEach-Object { [System.IO.Path]::GetFullPath($_) } |
            Sort-Object -Unique
    )

    if (@($ResolvedPaths).Count -eq 0) {
        return @()
    }

    $AllFindings = New-Object System.Collections.Generic.List[object]
    foreach ($CurrentPath in $ResolvedPaths) {
        foreach ($Finding in @(Invoke-ScriptAnalyzer -Path $CurrentPath -Settings $SettingsPath)) {
            [void]$AllFindings.Add($Finding)
        }
    }

    return @($AllFindings.ToArray())
}

Set-EtlFrameworkTestHostDefaults
