Set-StrictMode -Version Latest
. (Join-Path -Path (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))) -ChildPath 'TestHelpers.ps1')
$script:Module = $null

Describe 'Wizard.PreReqs helpers' {
    BeforeAll {
        $script:Module = Import-TestableAsset -RelativePath 'Wizard/Helpers/Wizard.PreReqs.ps1' -ModuleName 'Wizard.PreReqs.Tests'
    }

    AfterAll {
        if ($script:Module) {
            Remove-TestModuleSafely -Module $script:Module
        }
    }

    It 'returns a not-detected status when the registry key is missing' {
        Mock -ModuleName $script:Module.Name Test-Path { $false }

        $Status = Get-WizardDotNetFrameworkStatus -MinimumVersion '4.8'

        $Status.Installed | Should -BeFalse
        $Status.RequirementMet | Should -BeFalse
        $Status.MinimumRelease | Should -Be 528040
    }

    It 'maps a detected release value to a matching framework version' {
        Mock -ModuleName $script:Module.Name Test-Path { $true }
        Mock -ModuleName $script:Module.Name Get-ItemProperty { [pscustomobject]@{ Release = 528040 } }

        $Status = Get-WizardDotNetFrameworkStatus -MinimumVersion '4.7'

        $Status.Installed | Should -BeTrue
        $Status.DetectedVersion | Should -Be '4.8'
        $Status.RequirementMet | Should -BeTrue
    }

    It 'creates dependency summary entries for required and optional libraries' {
        $Entries = @(Get-WizardDependencySummaryEntries -DependencyStatus ([pscustomobject]@{
            Present = $true
            DllPath = 'ExcelDataReader.dll'
            CodePagesPresent = $false
            CodePagesDllPath = 'System.Text.Encoding.CodePages.dll'
            SystemMemoryPresent = $true
            SystemMemoryPath = 'System.Memory.dll'
            SystemBuffersPresent = $true
            SystemBuffersPath = 'System.Buffers.dll'
            UnsafePresent = $false
            UnsafeDllPath = 'System.Runtime.CompilerServices.Unsafe.dll'
        }))

        $Entries.Count | Should -Be 5
        ($Entries | Where-Object Name -EQ 'ExcelDataReader').Optional | Should -BeFalse
        ($Entries | Where-Object Name -EQ 'System.Text.Encoding.CodePages').Optional | Should -BeTrue
    }

    It 'returns sorted supported .NET versions in descending order' {
        $Versions = @(Get-WizardSupportedDotNetVersions)
        $Versions | Should -Be @('4.8.1','4.8','4.7.2','4.7.1','4.7')
    }

    It 'returns bundled installer metadata when installer exists' {
        Mock -ModuleName $script:Module.Name Resolve-WizardBundledDotNetInstallerPath { 'C:\Framework\Templates\Installers\DotNet\NDP481-x86-x64-AllOS-ENU.exe' }
        Mock -ModuleName $script:Module.Name Test-Path { $true }
        Mock -ModuleName $script:Module.Name Get-Item {
            [pscustomobject]@{
                FullName = 'C:\Framework\Templates\Installers\DotNet\NDP481-x86-x64-AllOS-ENU.exe'
                Length = 77594584
            }
        }

        $Metadata = Get-WizardBundledDotNetInstallerMetadata -FrameworkRoot 'C:\Framework' -MinimumVersion '4.8.1'
        $Metadata.Present | Should -BeTrue
        $Metadata.SizeBytes | Should -Be 77594584
        $Metadata.InstallerPath | Should -Be 'C:\Framework\Templates\Installers\DotNet\NDP481-x86-x64-AllOS-ENU.exe'
    }

    It 'returns an unmet status when the prerequisite is missing and installation is disabled' {
        Mock -ModuleName $script:Module.Name Test-WizardExcelDataReaderTemplateDependency { [pscustomobject]@{ Present = $true; DllPath='x'; CodePagesPresent=$true; CodePagesDllPath='y'; SystemMemoryPresent=$true; SystemMemoryPath='z'; SystemBuffersPresent=$true; SystemBuffersPath='b'; UnsafePresent=$true; UnsafeDllPath='u' } }
        Mock -ModuleName $script:Module.Name Write-WizardDependencySummary {}
        Mock -ModuleName $script:Module.Name Get-WizardDotNetFrameworkStatus { [pscustomobject]@{ Installed = $false; Release = $null; DetectedVersion = 'Not detected'; MinimumVersion = '4.8'; MinimumRelease = 528040; RequirementMet = $false } }

        $Result = Invoke-WizardPrerequisiteWorkflow -MinimumVersion '4.8' -FrameworkRoot 'C:\Framework' -AllowInstallIfMissing:$false

        $Result.RequirementMet | Should -BeFalse
        $Result.InstallAttempted | Should -BeFalse
        $Result.UserDeclinedInstall | Should -BeFalse
    }

    It 'returns a declined status when the user skips installation' {
        Mock -ModuleName $script:Module.Name Test-WizardExcelDataReaderTemplateDependency { [pscustomobject]@{ Present = $true; DllPath='x'; CodePagesPresent=$true; CodePagesDllPath='y'; SystemMemoryPresent=$true; SystemMemoryPath='z'; SystemBuffersPresent=$true; SystemBuffersPath='b'; UnsafePresent=$true; UnsafeDllPath='u' } }
        Mock -ModuleName $script:Module.Name Write-WizardDependencySummary {}
        Mock -ModuleName $script:Module.Name Get-WizardDotNetFrameworkStatus { [pscustomobject]@{ Installed = $false; Release = $null; DetectedVersion = 'Not detected'; MinimumVersion = '4.8'; MinimumRelease = 528040; RequirementMet = $false } }
        Mock -ModuleName $script:Module.Name Read-BooleanChoice { $false }

        $Result = Invoke-WizardPrerequisiteWorkflow -MinimumVersion '4.8' -FrameworkRoot 'C:\Framework' -AllowInstallIfMissing:$true

        $Result.RequirementMet | Should -BeFalse
        $Result.UserDeclinedInstall | Should -BeTrue
    }

    It 'installs the prerequisite when the user agrees and the installer path is provided' {
        Mock -ModuleName $script:Module.Name Test-WizardExcelDataReaderTemplateDependency { [pscustomobject]@{ Present = $true; DllPath='x'; CodePagesPresent=$true; CodePagesDllPath='y'; SystemMemoryPresent=$true; SystemMemoryPath='z'; SystemBuffersPresent=$true; SystemBuffersPath='b'; UnsafePresent=$true; UnsafeDllPath='u' } }
        Mock -ModuleName $script:Module.Name Write-WizardDependencySummary {}
        $global:WizardPreReqsStatusCallCount = 0
        Mock -ModuleName $script:Module.Name Get-WizardDotNetFrameworkStatus {
            $global:WizardPreReqsStatusCallCount++
            if ($global:WizardPreReqsStatusCallCount -eq 1) { return [pscustomobject]@{ Installed = $false; Release = $null; DetectedVersion = 'Not detected'; MinimumVersion = '4.8'; MinimumRelease = 528040; RequirementMet = $false } }
            return [pscustomobject]@{ Installed = $true; Release = 528040; DetectedVersion = '4.8'; MinimumVersion = '4.8'; MinimumRelease = 528040; RequirementMet = $true }
        }
        Mock -ModuleName $script:Module.Name Read-BooleanChoice { $true }
        Mock -ModuleName $script:Module.Name Test-WizardIsAdministrator { $true }
        Mock -ModuleName $script:Module.Name Install-WizardDotNetFrameworkOffline { $true }
        Mock -ModuleName $script:Module.Name Start-Sleep {}

        $Result = Invoke-WizardPrerequisiteWorkflow -MinimumVersion '4.8' -FrameworkRoot 'C:\Framework' -AllowInstallIfMissing:$true -OfflineInstallerPath 'C:\Installers\dotnet.exe'

        $Result.RequirementMet | Should -BeTrue
        $Result.InstallAttempted | Should -BeTrue
        Assert-MockCalled -CommandName Install-WizardDotNetFrameworkOffline -ModuleName $script:Module.Name -Times 1 -Exactly
        Remove-Variable -Name WizardPreReqsStatusCallCount -Scope Global -ErrorAction SilentlyContinue
    }

    It 'prefers bundled installer when explicit path is missing' {
        Mock -ModuleName $script:Module.Name Test-WizardExcelDataReaderTemplateDependency { [pscustomobject]@{ Present = $true; DllPath='x'; CodePagesPresent=$true; CodePagesDllPath='y'; SystemMemoryPresent=$true; SystemMemoryPath='z'; SystemBuffersPresent=$true; SystemBuffersPath='b'; UnsafePresent=$true; UnsafeDllPath='u' } }
        Mock -ModuleName $script:Module.Name Write-WizardDependencySummary {}
        $global:WizardPreReqsStatusCallCount = 0
        Mock -ModuleName $script:Module.Name Get-WizardDotNetFrameworkStatus {
            $global:WizardPreReqsStatusCallCount++
            if ($global:WizardPreReqsStatusCallCount -eq 1) { return [pscustomobject]@{ Installed = $false; Release = $null; DetectedVersion = 'Not detected'; MinimumVersion = '4.8.1'; MinimumRelease = 533320; RequirementMet = $false } }
            return [pscustomobject]@{ Installed = $true; Release = 533320; DetectedVersion = '4.8.1'; MinimumVersion = '4.8.1'; MinimumRelease = 533320; RequirementMet = $true }
        }
        Mock -ModuleName $script:Module.Name Read-BooleanChoice { $true }
        Mock -ModuleName $script:Module.Name Test-WizardIsAdministrator { $true }
        Mock -ModuleName $script:Module.Name Resolve-WizardBundledDotNetInstallerPath { 'C:\Framework\Templates\Installers\DotNet\NDP481-x86-x64-AllOS-ENU.exe' }
        Mock -ModuleName $script:Module.Name Read-InputValue { throw 'Read-InputValue should not be called when bundled installer exists.' }
        Mock -ModuleName $script:Module.Name Install-WizardDotNetFrameworkOffline { $true }
        Mock -ModuleName $script:Module.Name Start-Sleep {}

        $Result = Invoke-WizardPrerequisiteWorkflow -MinimumVersion '4.8.1' -FrameworkRoot 'C:\Framework' -AllowInstallIfMissing:$true

        $Result.RequirementMet | Should -BeTrue
        $Result.InstallAttempted | Should -BeTrue
        Assert-MockCalled -CommandName Resolve-WizardBundledDotNetInstallerPath -ModuleName $script:Module.Name -Times 1 -Exactly
        Assert-MockCalled -CommandName Install-WizardDotNetFrameworkOffline -ModuleName $script:Module.Name -Times 1 -Exactly -ParameterFilter {
            $InstallerPath -eq 'C:\Framework\Templates\Installers\DotNet\NDP481-x86-x64-AllOS-ENU.exe'
        }
        Remove-Variable -Name WizardPreReqsStatusCallCount -Scope Global -ErrorAction SilentlyContinue
    }
}
