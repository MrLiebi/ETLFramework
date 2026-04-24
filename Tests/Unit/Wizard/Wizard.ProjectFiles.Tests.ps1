Set-StrictMode -Version Latest
. (Join-Path -Path (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))) -ChildPath 'TestHelpers.ps1')

Describe 'Wizard.ProjectFiles helpers' {
    BeforeAll {
        . (Join-Path -Path (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))) -ChildPath 'TestHelpers.ps1')
        $script:Module = Import-TestableAsset -RelativePath 'Wizard/Helpers/Wizard.ProjectFiles.ps1' -ModuleName 'Wizard.ProjectFiles.Tests' -AdditionalRelativePaths @(
            'Wizard/Helpers/Wizard.Paths.ps1'
        )
    }

    AfterAll {
        Remove-TestModuleSafely -Module $script:Module
    }

    Context 'Copy-TemplateFile' {
        It 'copies a template file and creates the target directory when needed' {
            $SourcePath = Join-Path -Path $TestDrive -ChildPath 'template.txt'
            $DestinationPath = Join-Path -Path $TestDrive -ChildPath 'nested/out/template.txt'
            'demo-content' | Set-Content -Path $SourcePath -Encoding UTF8

            Copy-TemplateFile -SourcePath $SourcePath -DestinationPath $DestinationPath -Description 'Demo template'

            Test-Path -Path $DestinationPath -PathType Leaf | Should -BeTrue
            ((Get-Content -Path $DestinationPath -Raw).TrimEnd("`r", "`n")) | Should -Be 'demo-content'
        }
    }

    Context 'Copy-TemplateDirectory' {
        It 'copies a template directory recursively' {
            $SourcePath = Join-Path -Path $TestDrive -ChildPath 'src'
            $DestinationPath = Join-Path -Path $TestDrive -ChildPath 'dst'
            New-Item -Path (Join-Path -Path $SourcePath -ChildPath 'child') -ItemType Directory -Force | Out-Null
            'value' | Set-Content -Path (Join-Path -Path $SourcePath -ChildPath 'child/file.txt') -Encoding UTF8

            Copy-TemplateDirectory -SourcePath $SourcePath -DestinationPath $DestinationPath -Description 'Directory template'

            Test-Path -Path (Join-Path -Path $DestinationPath -ChildPath 'child/file.txt') -PathType Leaf | Should -BeTrue
        }
    }

    Context 'Copy-CustomSourceScriptToProject' {
        It 'copies a custom source script into the project using a sanitized step name' {
            $SourcePath = Join-Path -Path $TestDrive -ChildPath 'Get-Users.ps1'
            $ProjectScriptDirectory = Join-Path -Path $TestDrive -ChildPath 'PS'
            'Write-Output 1' | Set-Content -Path $SourcePath -Encoding UTF8

            $TargetPath = Copy-CustomSourceScriptToProject -SourcePath $SourcePath -ProjectScriptDirectory $ProjectScriptDirectory -StepId '07' -StepName 'Users: EU/West'

            Test-Path -Path $TargetPath -PathType Leaf | Should -BeTrue
            [System.IO.Path]::GetFileName($TargetPath) | Should -Match '^Step_07_Users_ EU_West_Get-Users\.ps1$'
        }
    }

    Context 'Assert-NoUnresolvedTemplateTokens' {
        It 'throws when unresolved template tokens remain in generated content' {
            { Assert-NoUnresolvedTemplateTokens -Content 'Value=__TOKEN__' -Description 'adapter XML' } |
                Should -Throw '*unresolved template tokens*'
        }
    }

    Context 'Clear-GeneratedProjectArtifacts' {
        It 'removes generated RUN, TASK and PS folders only' {
            $ProjectRoot = Join-Path -Path $TestDrive -ChildPath 'Project'
            foreach ($RelativePath in @('RUN', 'TASK', 'PS', 'LOG')) {
                New-Item -Path (Join-Path -Path $ProjectRoot -ChildPath $RelativePath) -ItemType Directory -Force | Out-Null
            }

            Clear-GeneratedProjectArtifacts -ProjectRoot $ProjectRoot

            Test-Path -Path (Join-Path -Path $ProjectRoot -ChildPath 'RUN') | Should -BeFalse
            Test-Path -Path (Join-Path -Path $ProjectRoot -ChildPath 'TASK') | Should -BeFalse
            Test-Path -Path (Join-Path -Path $ProjectRoot -ChildPath 'PS') | Should -BeFalse
            Test-Path -Path (Join-Path -Path $ProjectRoot -ChildPath 'LOG') | Should -BeTrue
        }
    }

    Context 'Get-AvailableAdapterTypes' {
        It 'discovers adapter types from module template file names' {
            $TemplateRoot = Join-Path -Path $TestDrive -ChildPath 'Templates'
            New-Item -Path $TemplateRoot -ItemType Directory -Force | Out-Null
            'source' | Set-Content -Path (Join-Path -Path $TemplateRoot -ChildPath 'Source.CSV.psm1') -Encoding UTF8
            'source' | Set-Content -Path (Join-Path -Path $TemplateRoot -ChildPath 'Source.JSON.psm1') -Encoding UTF8
            'ignore' | Set-Content -Path (Join-Path -Path $TemplateRoot -ChildPath 'Other.psm1') -Encoding UTF8

            $Types = Get-AvailableAdapterTypes -TemplateRootPath $TemplateRoot -AdapterRole 'Source'
            $Types | Should -Be @('CSV', 'JSON')
        }

        It 'throws when no matching module templates are present' {
            $TemplateRoot = Join-Path -Path $TestDrive -ChildPath 'EmptyTemplates'
            New-Item -Path $TemplateRoot -ItemType Directory -Force | Out-Null

            { Get-AvailableAdapterTypes -TemplateRootPath $TemplateRoot -AdapterRole 'Destination' } |
                Should -Throw '*No Destination adapter templates found*'
        }
    }
}
