
Set-StrictMode -Version Latest
. (Join-Path -Path (Split-Path -Parent (Split-Path -Parent $PSCommandPath)) -ChildPath 'TestHelpers.ps1')

Describe 'PSScriptAnalyzer smoke test' -Tag 'AnalyzerStandalone' {
    It 'returns no findings for the framework using the supplied ruleset' {
        if (-not (Get-Module -ListAvailable -Name PSScriptAnalyzer)) {
            Set-ItResult -Skipped -Because 'PSScriptAnalyzer is not installed on this system.'
            return
        }

        Import-Module PSScriptAnalyzer -ErrorAction Stop
        $FrameworkRoot = Get-FrameworkRoot -StartPath $PSScriptRoot
        $SettingsPath = Join-Path -Path (Split-Path -Parent $PSCommandPath) -ChildPath '..\PSScriptAnalyzerSettings.psd1'
        $SettingsPath = [System.IO.Path]::GetFullPath($SettingsPath)
        $Targets = @(Get-ScriptAnalyzerTargetFiles -FrameworkRoot $FrameworkRoot)
        $Findings = if ($Targets.Count -gt 0) {
            @(Invoke-ScriptAnalyzerCompat -Path $Targets -SettingsPath $SettingsPath)
        }
        else {
            @()
        }

        $Findings | Should -BeNullOrEmpty
    }
}
