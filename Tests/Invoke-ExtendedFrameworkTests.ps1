# Central test runner (PSScriptAnalyzer + Pester). Comments use American English spelling.

[CmdletBinding()]
param(
    [string]$FrameworkRoot,
    [string]$OutputRoot,
    [switch]$SkipScriptAnalyzer,
    [switch]$SkipPester,
    [switch]$PassThru,
    [switch]$SkipCodeCoverage
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
# Ensure the suite remains non-interactive in CI/headless runs.
$ConfirmPreference = 'None'

$ScriptPath = if ($PSCommandPath) {
    $PSCommandPath
}
elseif ($MyInvocation.MyCommand.Path) {
    $MyInvocation.MyCommand.Path
}
else {
    $null
}

$ScriptRoot = if ($PSScriptRoot -and -not [string]::IsNullOrWhiteSpace($PSScriptRoot)) {
    $PSScriptRoot
}
elseif ($ScriptPath) {
    Split-Path -Path $ScriptPath -Parent
}
else {
    throw 'Cannot resolve script root. Start the script from a file or provide explicit paths.'
}

. (Join-Path -Path $ScriptRoot -ChildPath 'TestHelpers.ps1')
Set-EtlFrameworkTestHostDefaults -Full

if (-not $FrameworkRoot -or [string]::IsNullOrWhiteSpace($FrameworkRoot)) {
    $FrameworkRoot = Split-Path -Path $ScriptRoot -Parent
}

if (-not $OutputRoot -or [string]::IsNullOrWhiteSpace($OutputRoot)) {
    $OutputRoot = Join-Path -Path $ScriptRoot -ChildPath 'TestResults'
}

$null = New-Item -Path $OutputRoot -ItemType Directory -Force
$PesterResultPath = Join-Path -Path $OutputRoot -ChildPath 'pester-results.xml'
$CoverageResultPath = Join-Path -Path $OutputRoot -ChildPath 'coverage.xml'
$ScriptAnalyzerResultPath = Join-Path -Path $OutputRoot -ChildPath 'psscriptanalyzer-results.json'
$ScriptAnalyzerSettingsPath = Join-Path -Path $ScriptRoot -ChildPath 'PSScriptAnalyzerSettings.psd1'
$TestRoot = $ScriptRoot

function Assert-ModuleAvailable {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Name,
        [string]$MinimumVersion
    )

    $Available = Get-Module -ListAvailable -Name $Name | Sort-Object Version -Descending | Select-Object -First 1
    if (-not $Available) {
        throw "Required PowerShell module not found: $Name. Install it first, e.g. Install-Module $Name -Scope CurrentUser"
    }

    if ($MinimumVersion -and $Available.Version -lt [version]$MinimumVersion) {
        throw "Module $Name version $($Available.Version) is too old. Minimum version: $MinimumVersion"
    }
}

$SourceFiles = @(Get-ScriptAnalyzerTargetFiles -FrameworkRoot $FrameworkRoot)

$Summary = [ordered]@{
    FrameworkRoot  = $FrameworkRoot
    OutputRoot     = $OutputRoot
    SourceFiles    = @($SourceFiles).Count
    ScriptAnalyzer = [ordered]@{
        Executed = $false
        Findings = 0
        Result   = 'Skipped'
        File     = $ScriptAnalyzerResultPath
    }
    Pester = [ordered]@{
        Executed     = $false
        Passed       = 0
        Failed       = 0
        Skipped      = 0
        Result       = 'Skipped'
        ResultFile   = $PesterResultPath
        CoverageFile = $CoverageResultPath
    }
}

if (-not $SkipScriptAnalyzer) {
    Assert-ModuleAvailable -Name 'PSScriptAnalyzer' -MinimumVersion '1.22.0'
    Import-Module PSScriptAnalyzer -ErrorAction Stop

    $Summary.ScriptAnalyzer.Executed = $true
    $AnalyzerFindings = if (@($SourceFiles).Count -gt 0) {
        Invoke-ScriptAnalyzerCompat -Path $SourceFiles -SettingsPath $ScriptAnalyzerSettingsPath |
            Sort-ScriptAnalyzerFindings
    }
    else {
        @()
    }

    $AnalyzerFindings | ConvertTo-Json -Depth 10 | Set-Content -Path $ScriptAnalyzerResultPath -Encoding UTF8
    $Summary.ScriptAnalyzer.Findings = @($AnalyzerFindings).Count
    $Summary.ScriptAnalyzer.Result = if ($Summary.ScriptAnalyzer.Findings -eq 0) { 'Passed' } else { 'Failed' }
}

if (-not $SkipPester) {
    Assert-ModuleAvailable -Name 'Pester' -MinimumVersion '5.5.0'
    Import-Module Pester -MinimumVersion 5.5.0 -ErrorAction Stop

    $Summary.Pester.Executed = $true

    $PesterConfiguration = [PesterConfiguration]::Default
    $PesterConfiguration.Run.Path = $TestRoot
    $PesterConfiguration.Run.PassThru = $true
    $PesterConfiguration.Output.Verbosity = 'Detailed'
    $PesterConfiguration.Filter.ExcludeTag = @('AnalyzerStandalone')
    $PesterConfiguration.TestResult.Enabled = $true
    $PesterConfiguration.TestResult.OutputPath = $PesterResultPath
    $PesterConfiguration.TestResult.OutputFormat = 'NUnitXml'

    if (-not $SkipCodeCoverage) {
        $PesterConfiguration.CodeCoverage.Enabled = $true
        $PesterConfiguration.CodeCoverage.Path = $SourceFiles
        $PesterConfiguration.CodeCoverage.OutputPath = $CoverageResultPath
        $PesterConfiguration.CodeCoverage.OutputFormat = 'JaCoCo'
    }

    $PesterResult = Invoke-Pester -Configuration $PesterConfiguration
    $Summary.Pester.Passed = $PesterResult.PassedCount
    $Summary.Pester.Failed = $PesterResult.FailedCount
    $Summary.Pester.Skipped = $PesterResult.SkippedCount
    $Summary.Pester.Result = if ($PesterResult.FailedCount -eq 0) { 'Passed' } else { 'Failed' }
}

$HasFailures = ($Summary.ScriptAnalyzer.Result -eq 'Failed') -or ($Summary.Pester.Result -eq 'Failed')

if ($PassThru) {
    [PSCustomObject]$Summary
}
else {
    [PSCustomObject]$Summary | Format-List | Out-Host
}

if ($HasFailures) {
    exit 1
}
