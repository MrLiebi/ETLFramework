<#
    Helper functions for .NET Framework and runtime prerequisites within the ETL wizard.
#>

function Get-WizardDotNetReleaseMap {
    [CmdletBinding()]
    param()

    [ordered]@{
        '4.7'   = 460798
        '4.7.1' = 461308
        '4.7.2' = 461808
        '4.8'   = 528040
        '4.8.1' = 533320
    }
}

function Get-WizardSupportedDotNetVersions {
    [CmdletBinding()]
    param()

    @(
        [string[]](Get-WizardDotNetReleaseMap).Keys |
            Sort-Object {
                [version]($_ -replace '[^0-9\.]', '')
            } -Descending
    )
}

function Get-WizardDotNetFrameworkStatus {
    [CmdletBinding()]
    param(
        [string] $MinimumVersion = '4.8.1'
    )

    if ((Get-WizardSupportedDotNetVersions) -notcontains $MinimumVersion) {
        throw "Unsupported .NET Framework minimum version: $MinimumVersion"
    }

    $RegistryPath = 'HKLM:\SOFTWARE\Microsoft\NET Framework Setup\NDP\v4\Full'
    $MinimumReleaseMap = Get-WizardDotNetReleaseMap
    $MinimumRelease = [int]$MinimumReleaseMap[$MinimumVersion]

    if (-not (Test-Path -Path $RegistryPath)) {
        return [pscustomobject]@{
            Installed = $false
            Release = $null
            DetectedVersion = 'Not detected'
            MinimumVersion = $MinimumVersion
            MinimumRelease = $MinimumRelease
            RequirementMet = $false
        }
    }

    $Release = (Get-ItemProperty -Path $RegistryPath -Name Release -ErrorAction Stop).Release
    $DetectedVersion = switch ($true) {
        { $Release -ge 533320 } { '4.8.1 or later'; break }
        { $Release -ge 528040 } { '4.8'; break }
        { $Release -ge 461808 } { '4.7.2'; break }
        { $Release -ge 461308 } { '4.7.1'; break }
        { $Release -ge 460798 } { '4.7'; break }
        default                 { 'below 4.7' }
    }

    [pscustomobject]@{
        Installed = $true
        Release = $Release
        DetectedVersion = $DetectedVersion
        MinimumVersion = $MinimumVersion
        MinimumRelease = $MinimumRelease
        RequirementMet = ($Release -ge $MinimumRelease)
    }
}

function Test-WizardIsAdministrator {
    [CmdletBinding()]
    param()

    $Identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $Principal = New-Object Security.Principal.WindowsPrincipal($Identity)
    return $Principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Install-WizardDotNetFrameworkOffline {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $InstallerPath
    )

    if (-not (Test-Path -Path $InstallerPath -PathType Leaf)) {
        throw "Offline installer not found: $InstallerPath"
    }

    Write-Log "Starting .NET Framework installer: $InstallerPath" -Level 'INFO'
    $Process = Start-Process -FilePath $InstallerPath -ArgumentList '/quiet /norestart' -Wait -PassThru -WindowStyle Hidden
    Write-Log ".NET Framework installer finished with exit code: $($Process.ExitCode)" -Level 'INFO'

    switch ($Process.ExitCode) {
        0 { return $true }
        3010 {
            Write-Log 'Installer requests reboot (exit code 3010).' -Level 'WARN'
            return $true
        }
        default {
            throw ".NET Framework installer failed with exit code $($Process.ExitCode)"
        }
    }
}

function Resolve-WizardBundledDotNetInstallerPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $FrameworkRoot,
        [string] $MinimumVersion = '4.8.1'
    )

    if ((Get-WizardSupportedDotNetVersions) -notcontains $MinimumVersion) {
        throw "Unsupported .NET Framework minimum version: $MinimumVersion"
    }

    $BundledInstallerMap = [ordered]@{
        '4.8.1' = 'Templates\Installers\DotNet\NDP481-x86-x64-AllOS-ENU.exe'
    }

    $SelectedRelativePath = $null
    if ($BundledInstallerMap.Contains($MinimumVersion)) {
        $SelectedRelativePath = [string]$BundledInstallerMap[$MinimumVersion]
    }
    else {
        $SelectedRelativePath = [string]$BundledInstallerMap['4.8.1']
    }

    $SelectedPath = Join-Path -Path $FrameworkRoot -ChildPath $SelectedRelativePath
    if (Test-Path -Path $SelectedPath -PathType Leaf) {
        return $SelectedPath
    }

    return ''
}

function Get-WizardBundledDotNetInstallerMetadata {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $FrameworkRoot,
        [string] $MinimumVersion = '4.8.1'
    )

    $InstallerPath = Resolve-WizardBundledDotNetInstallerPath -FrameworkRoot $FrameworkRoot -MinimumVersion $MinimumVersion
    if ([string]::IsNullOrWhiteSpace($InstallerPath) -or -not (Test-Path -Path $InstallerPath -PathType Leaf)) {
        return [pscustomobject]@{
            InstallerPath = ''
            Present = $false
            SizeBytes = 0
        }
    }

    $InstallerItem = Get-Item -Path $InstallerPath -ErrorAction Stop
    [pscustomobject]@{
        InstallerPath = $InstallerItem.FullName
        Present = $true
        SizeBytes = [int64]$InstallerItem.Length
    }
}

function Test-WizardExcelDataReaderTemplateDependency {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $FrameworkRoot
    )

    $DependencyDir = Join-Path -Path $FrameworkRoot -ChildPath 'Templates\Modules\Dependencies\ExcelDataReader'
    $PrimaryDllPath = Join-Path -Path $DependencyDir -ChildPath 'ExcelDataReader.dll'
    $CodePagesDllPath = Join-Path -Path $DependencyDir -ChildPath 'System.Text.Encoding.CodePages.dll'
    $SystemMemoryPath = Join-Path -Path $DependencyDir -ChildPath 'System.Memory.dll'
    $SystemBuffersPath = Join-Path -Path $DependencyDir -ChildPath 'System.Buffers.dll'
    $UnsafeDllPath = Join-Path -Path $DependencyDir -ChildPath 'System.Runtime.CompilerServices.Unsafe.dll'

    [pscustomobject]@{
        DependencyDirectory = $DependencyDir
        DllPath = $PrimaryDllPath
        Present = (Test-Path -Path $PrimaryDllPath -PathType Leaf)
        CodePagesDllPath = $CodePagesDllPath
        CodePagesPresent = (Test-Path -Path $CodePagesDllPath -PathType Leaf)
        SystemMemoryPath = $SystemMemoryPath
        SystemMemoryPresent = (Test-Path -Path $SystemMemoryPath -PathType Leaf)
        SystemBuffersPath = $SystemBuffersPath
        SystemBuffersPresent = (Test-Path -Path $SystemBuffersPath -PathType Leaf)
        UnsafeDllPath = $UnsafeDllPath
        UnsafePresent = (Test-Path -Path $UnsafeDllPath -PathType Leaf)
    }
}

function Get-WizardDependencySummaryEntries {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] $DependencyStatus
    )

    @(
        [pscustomobject]@{ Name = 'ExcelDataReader'; Present = $DependencyStatus.Present; Path = $DependencyStatus.DllPath; Optional = $false }
        [pscustomobject]@{ Name = 'System.Text.Encoding.CodePages'; Present = $DependencyStatus.CodePagesPresent; Path = $DependencyStatus.CodePagesDllPath; Optional = $true }
        [pscustomobject]@{ Name = 'System.Memory'; Present = $DependencyStatus.SystemMemoryPresent; Path = $DependencyStatus.SystemMemoryPath; Optional = $true }
        [pscustomobject]@{ Name = 'System.Buffers'; Present = $DependencyStatus.SystemBuffersPresent; Path = $DependencyStatus.SystemBuffersPath; Optional = $true }
        [pscustomobject]@{ Name = 'System.Runtime.CompilerServices.Unsafe'; Present = $DependencyStatus.UnsafePresent; Path = $DependencyStatus.UnsafeDllPath; Optional = $true }
    )
}

function Write-WizardDependencySummary {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] $DependencyStatus
    )

    foreach ($Entry in @(Get-WizardDependencySummaryEntries -DependencyStatus $DependencyStatus)) {
        if ($Entry.Present) {
            Write-Log ("Dependency detected: {0} | {1}" -f $Entry.Name, $Entry.Path) -Level 'INFO'
        }
        elseif ($Entry.Optional) {
            Write-Log ("Optional dependency not found: {0} | {1}" -f $Entry.Name, $Entry.Path) -Level 'WARN'
        }
        else {
            Write-Log ("Required dependency not found: {0} | {1}" -f $Entry.Name, $Entry.Path) -Level 'ERROR'
        }
    }
}

function Test-DotNetFrameworkPrerequisite {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $MinimumVersion,
        [switch] $FailIfMissing
    )

    if ((Get-WizardSupportedDotNetVersions) -notcontains $MinimumVersion) {
        throw "Unsupported .NET Framework minimum version: $MinimumVersion"
    }

    try {
        $Status = Get-WizardDotNetFrameworkStatus -MinimumVersion $MinimumVersion
        if ($Status.Installed) {
            Write-Log ".NET Framework Release value detected: $($Status.Release)" -Level 'INFO'
            Write-Log ".NET Framework version interpreted as: $($Status.DetectedVersion)" -Level 'INFO'
        }
        else {
            Write-Log '.NET Framework 4.x registry entry not found.' -Level 'WARN'
        }

        if ($Status.RequirementMet) {
            Write-Log ".NET Framework prerequisite satisfied. Required: $MinimumVersion, Detected Release: $($Status.Release)" -Level 'INFO'
            return $true
        }

        $WarnMessage = ".NET Framework prerequisite NOT satisfied. Required: $($Status.MinimumVersion) (Release >= $($Status.MinimumRelease)), Detected Release: $($Status.Release)"
        if ($FailIfMissing) {
            Write-Log $WarnMessage -Level 'ERROR'
        }
        else {
            Write-Log $WarnMessage -Level 'WARN'
        }

        return $false
    }
    catch {
        $Message = "Failed to verify .NET Framework prerequisite: $($_.Exception.Message)"
        if ($FailIfMissing) {
            Write-Log $Message -Level 'ERROR'
        }
        else {
            Write-Log $Message -Level 'WARN'
        }

        return $false
    }
}

function Invoke-WizardPrerequisiteWorkflow {
    [CmdletBinding()]
    param(
        [string] $MinimumVersion = '4.8.1',

        [Parameter(Mandatory)][string] $FrameworkRoot,

        [bool] $AllowInstallIfMissing = $true,

        [string] $OfflineInstallerPath = ''
    )

    if ((Get-WizardSupportedDotNetVersions) -notcontains $MinimumVersion) {
        throw "Unsupported .NET Framework minimum version: $MinimumVersion"
    }

    Write-Log ("Required .NET Framework version: {0}" -f $MinimumVersion) -Level 'INFO'

    $ExcelDependencyStatus = Test-WizardExcelDataReaderTemplateDependency -FrameworkRoot $FrameworkRoot
    Write-WizardDependencySummary -DependencyStatus $ExcelDependencyStatus

    $Status = Get-WizardDotNetFrameworkStatus -MinimumVersion $MinimumVersion
    if ($Status.Installed) {
        Write-Log ("Detected Release value: {0}" -f $Status.Release) -Level 'INFO'
        Write-Log ("Detected version: {0}" -f $Status.DetectedVersion) -Level 'INFO'
    }
    else {
        Write-Log '.NET Framework 4.x registry entry not found.' -Level 'WARN'
    }

    if ($Status.RequirementMet) {
        Write-Log 'Prerequisite check completed successfully.' -Level 'INFO'
        return [pscustomobject]@{
            RequirementMet = $true
            Status = $Status
            InstallAttempted = $false
            UserDeclinedInstall = $false
        }
    }

    Write-Log ("Prerequisite not satisfied. Required: {0} (Release >= {1})." -f $Status.MinimumVersion, $Status.MinimumRelease) -Level 'WARN'

    if (-not $AllowInstallIfMissing) {
        return [pscustomobject]@{
            RequirementMet = $false
            Status = $Status
            InstallAttempted = $false
            UserDeclinedInstall = $false
        }
    }

    $InstallNow = Read-BooleanChoice -Prompt ("Required .NET Framework {0} is missing. Install now from an offline installer?" -f $MinimumVersion) -Default $false
    if (-not $InstallNow) {
        Write-Log 'User declined .NET Framework installation.' -Level 'WARN'
        return [pscustomobject]@{
            RequirementMet = $false
            Status = $Status
            InstallAttempted = $false
            UserDeclinedInstall = $true
        }
    }

    if (-not (Test-WizardIsAdministrator)) {
        throw 'Administrative privileges are required to install .NET Framework.'
    }

    if ([string]::IsNullOrWhiteSpace($OfflineInstallerPath)) {
        $OfflineInstallerPath = Resolve-WizardBundledDotNetInstallerPath -FrameworkRoot $FrameworkRoot -MinimumVersion $MinimumVersion
        if (-not [string]::IsNullOrWhiteSpace($OfflineInstallerPath)) {
            Write-Log ("Using bundled .NET offline installer: {0}" -f $OfflineInstallerPath) -Level 'INFO'
        }
    }

    if ([string]::IsNullOrWhiteSpace($OfflineInstallerPath)) {
        $OfflineInstallerPath = Read-InputValue -Prompt ("Path to offline installer for .NET Framework {0}" -f $MinimumVersion) -Default '' -AllowEmpty
    }

    if ([string]::IsNullOrWhiteSpace($OfflineInstallerPath)) {
        throw ("Please provide the path to an offline installer for at least .NET Framework {0}." -f $MinimumVersion)
    }

    [void](Install-WizardDotNetFrameworkOffline -InstallerPath $OfflineInstallerPath)
    Start-Sleep -Seconds 5

    $Status = Get-WizardDotNetFrameworkStatus -MinimumVersion $MinimumVersion
    Write-Log ("Post-install detected Release value: {0}" -f $Status.Release) -Level 'INFO'
    Write-Log ("Post-install detected version: {0}" -f $Status.DetectedVersion) -Level 'INFO'

    if (-not $Status.RequirementMet) {
        throw 'Prerequisite installation completed, but the required .NET Framework version is still not available.'
    }

    Write-Log 'Prerequisite check completed successfully.' -Level 'INFO'
    [pscustomobject]@{
        RequirementMet = $true
        Status = $Status
        InstallAttempted = $true
        UserDeclinedInstall = $false
    }
}
