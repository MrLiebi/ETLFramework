Set-StrictMode -Version Latest

BeforeAll {
    $script:FrameworkRoot = Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent
    $script:ReleaseManifestPath = Join-Path -Path $script:FrameworkRoot -ChildPath 'ReleaseManifest.psd1'
    $script:ReleaseManifest = Import-PowerShellDataFile -Path $script:ReleaseManifestPath
}

Describe 'Release manifest traceability' {
    It 'contains latest release metadata fields' {
        Test-Path -Path $script:ReleaseManifestPath -PathType Leaf | Should -BeTrue
        $script:ReleaseManifest.ContainsKey('Latest') | Should -BeTrue
        $script:ReleaseManifest.Latest.Version | Should -Match '^\d+\.\d+\.\d+$'
        $script:ReleaseManifest.Latest.Tag | Should -Match '^v\d+\.\d+\.\d+$'
        $script:ReleaseManifest.Latest.ReleaseCommit | Should -Match '^[0-9a-f]{7,40}$'
        $script:ReleaseManifest.Latest.ReleaseUrl | Should -Match '^https://github\.com/.+/releases/tag/v\d+\.\d+\.\d+$'
        [string]::IsNullOrWhiteSpace([string]$script:ReleaseManifest.Latest.Notes) | Should -BeFalse
    }

    It 'keeps tag and version aligned' {
        $ExpectedTag = 'v{0}' -f $script:ReleaseManifest.Latest.Version
        $script:ReleaseManifest.Latest.Tag | Should -Be $ExpectedTag
    }
}
