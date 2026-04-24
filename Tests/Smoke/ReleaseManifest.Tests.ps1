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
        $script:ReleaseManifest.Latest.Version | Should -Match '^\d+\.\d+(\.\d+)?$'
        $script:ReleaseManifest.Latest.Tag | Should -Match '^v\d+\.\d+(\.\d+)?$'
        [string]::IsNullOrWhiteSpace([string]$script:ReleaseManifest.Latest.ReleaseCommit) | Should -BeFalse
        $script:ReleaseManifest.Latest.ReleaseUrl | Should -Match '^https://github\.com/.+/releases/tag/v\d+\.\d+(\.\d+)?$'
        [string]::IsNullOrWhiteSpace([string]$script:ReleaseManifest.Latest.Notes) | Should -BeFalse
    }

    It 'keeps tag and version aligned' {
        $ExpectedTag = 'v{0}' -f $script:ReleaseManifest.Latest.Version
        $script:ReleaseManifest.Latest.Tag | Should -Be $ExpectedTag
    }

    It 'tracks bundled .NET installer metadata' {
        $script:ReleaseManifest.ContainsKey('BundledInstallers') | Should -BeTrue
        $script:ReleaseManifest.BundledInstallers.ContainsKey('DotNetFramework481') | Should -BeTrue
        $script:ReleaseManifest.BundledInstallers.DotNetFramework481.Path | Should -Be 'Templates/Installers/DotNet/NDP481-x86-x64-AllOS-ENU.exe'
        $script:ReleaseManifest.BundledInstallers.DotNetFramework481.Sha256 | Should -Match '^[0-9a-f]{64}$'
    }
}
