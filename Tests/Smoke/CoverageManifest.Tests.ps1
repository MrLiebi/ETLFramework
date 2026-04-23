
Set-StrictMode -Version Latest
. (Join-Path -Path (Split-Path -Parent (Split-Path -Parent $PSCommandPath)) -ChildPath 'TestHelpers.ps1')

BeforeAll {
    $script:FrameworkRoot = Get-FrameworkRoot -StartPath $PSScriptRoot
    $script:ManifestPath = Join-Path -Path (Split-Path -Parent $PSCommandPath) -ChildPath '..\CoverageManifest.psd1'
    $script:ManifestPath = [System.IO.Path]::GetFullPath($script:ManifestPath)
    $script:CoverageManifest = Import-PowerShellDataFile -Path $script:ManifestPath
    $script:FrameworkRelativePaths = @(
        Get-FrameworkSourceFiles -FrameworkRoot $script:FrameworkRoot |
            ForEach-Object { Get-RelativeFrameworkPath -FrameworkRoot $script:FrameworkRoot -Path $_.FullName }
    )
}

Describe 'Tester completeness manifest' {
    It 'covers every framework script and module exactly once' {
        $Differences = @(Compare-Object -ReferenceObject @($script:CoverageManifest.Keys | Sort-Object) -DifferenceObject @($script:FrameworkRelativePaths | Sort-Object))
        $Differences | Should -BeNullOrEmpty
    }

    It 'contains no stale entries' {
        foreach ($RelativePath in $script:CoverageManifest.Keys) {
            $script:FrameworkRelativePaths | Should -Contain $RelativePath
        }
    }

    It 'stores coverage metadata for every tracked file' {
        foreach ($RelativePath in $script:CoverageManifest.Keys) {
            $Entry = $script:CoverageManifest[$RelativePath]
            @($Entry.Coverage).Count | Should -BeGreaterThan 0
            [string]::IsNullOrWhiteSpace([string]$Entry.Notes) | Should -BeFalse
        }
    }

    It 'keeps targeted unit coverage on high-value framework components' {
        foreach ($RelativePath in @(
            'Templates/Modules/Common/Framework.Common.psm1',
            'Templates/Modules/Common/Framework.Logging.psm1',
            'Templates/Modules/Common/Framework.Validation.psm1',
            'Templates/Modules/Destination/Destination.CSV.psm1',
            'Templates/Modules/Source/Source.CSV.psm1',
            'Templates/Modules/Source/Source.CustomScript.psm1',
            'Templates/Modules/Source/Source.JSON.psm1',
            'Templates/Modules/Source/Source.XML.psm1',
            'Templates/Modules/Source/Source.LDAP.psm1',
            'Templates/Modules/Source/Source.XLSX.psm1',
            'Wizard/Helpers/Wizard.Config.ps1',
            'Wizard/Helpers/Wizard.Paths.ps1',
            'Wizard/Helpers/Wizard.Adapter.ps1',
            'Wizard/Helpers/Wizard.Schedule.ps1',
            'Wizard/Modules/Wizard.Logging.psm1'
        )) {
            @($script:CoverageManifest[$RelativePath].Coverage) | Should -Contain 'Unit'
        }
    }
}
