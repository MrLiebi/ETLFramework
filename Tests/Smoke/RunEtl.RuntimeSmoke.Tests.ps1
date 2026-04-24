Set-StrictMode -Version Latest

Describe 'Run-ETL runtime smoke tests' {
    function Resolve-PowerShellHostPath {
        [CmdletBinding()]
        param()

        $Candidates = New-Object System.Collections.Generic.List[string]
        if ($env:OS -eq 'Windows_NT') {
            [void]$Candidates.Add('powershell.exe')
        }
        [void]$Candidates.Add('pwsh')
        [void]$Candidates.Add('powershell')

        foreach ($Candidate in $Candidates) {
            $Command = Get-Command -Name $Candidate -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($null -ne $Command) {
                if ($Command.PSObject.Properties['Path'] -and -not [string]::IsNullOrWhiteSpace([string]$Command.Path)) {
                    return [string]$Command.Path
                }
                return [string]$Command.Name
            }
        }

        throw 'No compatible PowerShell host found. Install Windows PowerShell 5.1 or PowerShell 7 (pwsh).'
    }

    BeforeAll {
        $script:FrameworkRoot = Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent
        $script:RuntimeTemplatePath = Join-Path -Path $script:FrameworkRoot -ChildPath 'Templates/Runtime/Run-ETL.ps1'
        $script:CommonModuleTemplatePath = Join-Path -Path $script:FrameworkRoot -ChildPath 'Templates/Modules/Common'
        $script:CredentialModuleTemplatePath = Join-Path -Path $script:FrameworkRoot -ChildPath 'Templates/Modules/Credential/Credential.Manager.psm1'
        $script:PowerShellHostPath = Resolve-PowerShellHostPath
    }

    It 'executes a minimal runtime pipeline successfully and writes output' {
        $ProjectRoot = Join-Path -Path $TestDrive -ChildPath 'RuntimeSmokeSuccess'
        $RunRoot = Join-Path -Path $ProjectRoot -ChildPath 'RUN'
        $LogRoot = Join-Path -Path $ProjectRoot -ChildPath 'LOG'
        $SourceRoot = Join-Path -Path $RunRoot -ChildPath 'Modules/Source'
        $DestinationRoot = Join-Path -Path $RunRoot -ChildPath 'Modules/Destination'
        $CommonRoot = Join-Path -Path $RunRoot -ChildPath 'Modules/Common'
        $CredentialRoot = Join-Path -Path $RunRoot -ChildPath 'Modules/Credential'
        $OutputPath = Join-Path -Path $ProjectRoot -ChildPath 'OUTPUT/out.json'

        foreach ($Directory in @($RunRoot, $LogRoot, $SourceRoot, $DestinationRoot, $CommonRoot, $CredentialRoot, (Split-Path -Path $OutputPath -Parent))) {
            New-Item -Path $Directory -ItemType Directory -Force | Out-Null
        }

        Copy-Item -Path $script:RuntimeTemplatePath -Destination (Join-Path -Path $RunRoot -ChildPath 'Run-ETL.ps1') -Force
        Copy-Item -Path (Join-Path -Path $script:CommonModuleTemplatePath -ChildPath 'Framework.Common.psm1') -Destination (Join-Path -Path $CommonRoot -ChildPath 'Framework.Common.psm1') -Force
        Copy-Item -Path (Join-Path -Path $script:CommonModuleTemplatePath -ChildPath 'Framework.Logging.psm1') -Destination (Join-Path -Path $CommonRoot -ChildPath 'Framework.Logging.psm1') -Force
        Copy-Item -Path (Join-Path -Path $script:CommonModuleTemplatePath -ChildPath 'Framework.Validation.psm1') -Destination (Join-Path -Path $CommonRoot -ChildPath 'Framework.Validation.psm1') -Force
        Copy-Item -Path $script:CredentialModuleTemplatePath -Destination (Join-Path -Path $CredentialRoot -ChildPath 'Credential.Manager.psm1') -Force

        @'
function Invoke-Extract {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][hashtable] $Config,
        [Parameter(Mandatory = $true)][string[]] $Properties
    )

    [PSCustomObject]@{
        Id = 1
        Name = 'Alice'
    }
}

Export-ModuleMember -Function Invoke-Extract
'@ | Set-Content -Path (Join-Path -Path $SourceRoot -ChildPath 'Source.Mock.psm1') -Encoding UTF8

        @'
function Invoke-Load {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)][object] $Data,
        [Parameter(Mandatory = $true)][hashtable] $Config
    )

    begin {
        $Rows = New-Object System.Collections.Generic.List[object]
        $TargetPath = [string]$Config.Path
        if ([string]::IsNullOrWhiteSpace($TargetPath)) {
            throw 'Destination config Path is required for mock destination.'
        }
    }
    process {
        if ($null -ne $Data) {
            [void]$Rows.Add($Data)
        }
    }
    end {
        $Directory = Split-Path -Path $TargetPath -Parent
        if (-not (Test-Path -Path $Directory -PathType Container)) {
            New-Item -Path $Directory -ItemType Directory -Force | Out-Null
        }

        $Rows.ToArray() | ConvertTo-Json -Depth 10 | Set-Content -Path $TargetPath -Encoding UTF8
    }
}

Export-ModuleMember -Function Invoke-Load
'@ | Set-Content -Path (Join-Path -Path $DestinationRoot -ChildPath 'Destination.Mock.psm1') -Encoding UTF8

        @"
@{
    Logging = @{
        Level = 'INFO'
        RetentionDays = 30
        ModuleLogs = `$true
    }
    Pipelines = @(
        @{
            StepId = '01'
            Name = 'SmokeSuccess'
            StepEnabled = `$true
            Source = @{
                Type = 'Mock'
                Config = @{}
            }
            Destination = @{
                Type = 'Mock'
                Config = @{
                    Path = '$($OutputPath -replace '\\', '\\')'
                }
            }
            Properties = @('Id', 'Name')
        }
    )
    Adapter = @{
        AdapterEnabled = `$false
    }
}
"@ | Set-Content -Path (Join-Path -Path $RunRoot -ChildPath 'config.psd1') -Encoding UTF8

        Push-Location -Path $RunRoot
        try {
            $CommandResult = & $script:PowerShellHostPath -NoProfile -File (Join-Path -Path $RunRoot -ChildPath 'Run-ETL.ps1') -ConfigPath '.\config.psd1' 2>&1
        }
        finally {
            Pop-Location
        }
        $ExitCode = $LASTEXITCODE

        $ExitCode | Should -Be 0
        Test-Path -Path $OutputPath -PathType Leaf | Should -BeTrue
        ((Get-Content -Path $OutputPath -Raw) -replace '\s+', '') | Should -Match '"Name":"Alice"'
        Test-Path -Path (Join-Path -Path $LogRoot -ChildPath '*.log') | Should -BeTrue
    }

    It 'returns a non-zero exit code when adapter modules are missing' {
        $ProjectRoot = Join-Path -Path $TestDrive -ChildPath 'RuntimeSmokeFailure'
        $RunRoot = Join-Path -Path $ProjectRoot -ChildPath 'RUN'
        $LogRoot = Join-Path -Path $ProjectRoot -ChildPath 'LOG'
        $CommonRoot = Join-Path -Path $RunRoot -ChildPath 'Modules/Common'
        $CredentialRoot = Join-Path -Path $RunRoot -ChildPath 'Modules/Credential'

        foreach ($Directory in @($RunRoot, $LogRoot, $CommonRoot, $CredentialRoot)) {
            New-Item -Path $Directory -ItemType Directory -Force | Out-Null
        }

        Copy-Item -Path $script:RuntimeTemplatePath -Destination (Join-Path -Path $RunRoot -ChildPath 'Run-ETL.ps1') -Force
        Copy-Item -Path (Join-Path -Path $script:CommonModuleTemplatePath -ChildPath 'Framework.Common.psm1') -Destination (Join-Path -Path $CommonRoot -ChildPath 'Framework.Common.psm1') -Force
        Copy-Item -Path (Join-Path -Path $script:CommonModuleTemplatePath -ChildPath 'Framework.Logging.psm1') -Destination (Join-Path -Path $CommonRoot -ChildPath 'Framework.Logging.psm1') -Force
        Copy-Item -Path (Join-Path -Path $script:CommonModuleTemplatePath -ChildPath 'Framework.Validation.psm1') -Destination (Join-Path -Path $CommonRoot -ChildPath 'Framework.Validation.psm1') -Force
        Copy-Item -Path $script:CredentialModuleTemplatePath -Destination (Join-Path -Path $CredentialRoot -ChildPath 'Credential.Manager.psm1') -Force

        @'
@{
    Logging = @{
        Level = 'INFO'
        RetentionDays = 30
        ModuleLogs = $true
    }
    Pipelines = @(
        @{
            StepId = '01'
            Name = 'SmokeFailure'
            StepEnabled = $true
            Source = @{
                Type = 'DoesNotExist'
                Config = @{}
            }
            Destination = @{
                Type = 'DoesNotExist'
                Config = @{}
            }
            Properties = @('*')
        }
    )
    Adapter = @{
        AdapterEnabled = $false
    }
}
'@ | Set-Content -Path (Join-Path -Path $RunRoot -ChildPath 'config.psd1') -Encoding UTF8

        Push-Location -Path $RunRoot
        try {
            $CommandResult = & $script:PowerShellHostPath -NoProfile -File (Join-Path -Path $RunRoot -ChildPath 'Run-ETL.ps1') -ConfigPath '.\config.psd1' 2>&1
        }
        finally {
            Pop-Location
        }
        $ExitCode = $LASTEXITCODE

        $ExitCode | Should -Not -Be 0
        ($CommandResult | Out-String) | Should -Match 'Adapter module import failed'
        Test-Path -Path (Join-Path -Path $LogRoot -ChildPath '*.log') | Should -BeTrue
    }
}
