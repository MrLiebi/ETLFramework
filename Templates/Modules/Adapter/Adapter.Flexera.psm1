<#
.SYNOPSIS
Flexera Business Adapter module for the ETL framework.

.VERSION
23.0.0
#>

function Resolve-AdapterConfigPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][hashtable] $Config,
        [Parameter(Mandatory)][string] $RuntimeRoot,
        [Parameter(Mandatory)][scriptblock] $WriteLog,
        [Parameter(Mandatory)][scriptblock] $ResolveNormalizedPath
    )

    if (-not $Config.ContainsKey('Adapter') -or -not $Config.Adapter) { return $null }
    $AdapterSection = $Config.Adapter

    $AdapterEnabledValue = $null
    if ($AdapterSection -is [hashtable] -or $AdapterSection -is [System.Collections.Specialized.OrderedDictionary]) {
        if ($AdapterSection.Contains('AdapterEnabled')) {
            $AdapterEnabledValue = $AdapterSection['AdapterEnabled']
        }
        elseif ($AdapterSection.Contains('Enabled')) {
            $AdapterEnabledValue = $AdapterSection['Enabled']
        }
    }
    elseif ($AdapterSection.PSObject.Properties['AdapterEnabled']) {
        $AdapterEnabledValue = $AdapterSection.AdapterEnabled
    }
    elseif ($AdapterSection.PSObject.Properties['Enabled']) {
        $AdapterEnabledValue = $AdapterSection.Enabled
    }

    $AdapterEnabledText = [string]$AdapterEnabledValue
    if ($AdapterEnabledText -notmatch '^(?i:true|1|yes|y)$') {
        return $null
    }

    if ([string]::IsNullOrWhiteSpace([string]$AdapterSection.ConfigFile)) { throw 'Adapter.ConfigFile must be set when adapter execution is enabled.' }

    $AdapterConfigFileName = [System.IO.Path]::GetFileName([string]$AdapterSection.ConfigFile)
    if ([string]::IsNullOrWhiteSpace($AdapterConfigFileName)) { throw 'Adapter.ConfigFile must contain a valid file name.' }
    if ($AdapterConfigFileName -ne ([string]$AdapterSection.ConfigFile).Trim()) {
        & $WriteLog ("Adapter.ConfigFile contains path information. Only the file name is supported. Using sanitized value: {0}" -f $AdapterConfigFileName) 'WARN'
    }

    $AdapterConfigPath = Join-Path -Path $RuntimeRoot -ChildPath (Join-Path -Path 'Modules\Adapter' -ChildPath $AdapterConfigFileName)
    return & $ResolveNormalizedPath $AdapterConfigPath
}

function Resolve-MgsbiExecutablePath {
    [CmdletBinding()]
    param()

    $RegistryPath = 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\SharedDlls'
    if (-not (Test-Path -Path $RegistryPath)) { throw "Registry path for MGSBI lookup not found: $RegistryPath" }

    $RegistryProperties = (Get-ItemProperty -Path $RegistryPath -ErrorAction Stop).PSObject.Properties | Where-Object { $_.Name -notmatch '^PS(.*)$' }
    $CandidatePaths = New-Object System.Collections.Generic.List[string]
    foreach ($Property in $RegistryProperties) {
        foreach ($Candidate in @([string]$Property.Name, [string]$Property.Value)) {
            if (-not [string]::IsNullOrWhiteSpace($Candidate) -and $Candidate -match '(?i)mgsbi\.exe') { [void]$CandidatePaths.Add($Candidate) }
        }
    }

    $ResolvedPath = $CandidatePaths | Where-Object { $_ -match '(?i)mgsbi\.exe' -and (Test-Path -LiteralPath $_ -PathType Leaf) } | Select-Object -First 1
    if (-not $ResolvedPath) { throw 'MGSBI.exe could not be resolved from the SharedDlls registry key.' }
    return $ResolvedPath
}

function Get-XmlAttributeValue {
    [CmdletBinding()]
    param([Parameter(Mandatory)] $XmlNode, [Parameter(Mandatory)][string] $AttributeName)

    if ($null -eq $XmlNode) { return $null }

    if (-not ($XmlNode -is [System.Xml.XmlNode])) {
        $DirectProperty = $XmlNode.PSObject.Properties[$AttributeName]
        if ($DirectProperty) { return [string]$DirectProperty.Value }
    }

    $AttributeCollection = $XmlNode.Attributes
    if ($null -ne $AttributeCollection) {
        try {
            $Attribute = $AttributeCollection[$AttributeName]
            if ($Attribute) { return [string]$Attribute.Value }
        }
        catch {
            Write-Verbose ("Failed to resolve XML attribute '{0}': {1}" -f $AttributeName, $_.Exception.Message)
        }
    }

    return $null
}

function Get-AdapterImportDefinitions {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $ConfigFile,
        [Parameter(Mandatory)][scriptblock] $WriteLog,
        [Parameter(Mandatory)][scriptblock] $ResolveNormalizedPath
    )

    $NormalizedConfigFile = & $ResolveNormalizedPath $ConfigFile
    if (-not (Test-Path -LiteralPath $NormalizedConfigFile -PathType Leaf)) { throw "Adapter config file not found: $NormalizedConfigFile" }

    [xml]$AdapterXml = Get-Content -LiteralPath $NormalizedConfigFile -Raw -Encoding UTF8
    $Imports = @($AdapterXml.SelectNodes('//*[local-name()="Imports"]/*[local-name()="Import"]'))
    if (-not $Imports -or $Imports.Count -eq 0) { throw "No <Import> entries found in adapter XML: $NormalizedConfigFile" }

    $ImportDefinitions = foreach ($ImportNode in $Imports) {
        $ImportName = Get-XmlAttributeValue -XmlNode $ImportNode -AttributeName 'Name'
        $ImportType = Get-XmlAttributeValue -XmlNode $ImportNode -AttributeName 'Type'
        $HasRunnableName = -not [string]::IsNullOrWhiteSpace([string]$ImportName)
        $HasRunnableType = -not [string]::IsNullOrWhiteSpace([string]$ImportType)
        [PSCustomObject]@{
            Node = $ImportNode
            Name = [string]$ImportName
            Type = [string]$ImportType
            HasRunnableName = $HasRunnableName
            HasRunnableType = $HasRunnableType
            IsRunnable = $HasRunnableName -and $HasRunnableType
        }
    }

    foreach ($ImportDefinition in $ImportDefinitions) {
        if ($ImportDefinition.IsRunnable) {
            $State = 'runnable'
        }
        elseif (-not $ImportDefinition.HasRunnableName -and -not $ImportDefinition.HasRunnableType) {
            $State = 'skipped-missing-name-and-type'
        }
        elseif (-not $ImportDefinition.HasRunnableName) {
            $State = 'skipped-missing-name'
        }
        else {
            $State = 'skipped-missing-type'
        }

        $DisplayName = if ([string]::IsNullOrWhiteSpace($ImportDefinition.Name)) { '<missing-name>' } else { $ImportDefinition.Name }
        $DisplayType = if ([string]::IsNullOrWhiteSpace($ImportDefinition.Type)) { '<unknown-type>' } else { $ImportDefinition.Type }
        & $WriteLog ("Discovered adapter import: Name='{0}', Type='{1}', State='{2}'" -f $DisplayName, $DisplayType, $State) 'INFO'
    }

    return [PSCustomObject]@{ Xml = $AdapterXml; ConfigFile = $NormalizedConfigFile; Imports = $ImportDefinitions; RunnableImports = @($ImportDefinitions | Where-Object { $_.IsRunnable }) }
}

function Invoke-FlexeraBusinessAdapter {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][hashtable] $Config,
        [Parameter(Mandatory)][string] $RuntimeRoot,
        [Parameter(Mandatory)][string] $LogDirectory,
        [Parameter(Mandatory)][string] $RunId,
        [Parameter(Mandatory)][scriptblock] $WriteLog,
        [Parameter(Mandatory)][scriptblock] $ResolveNormalizedPath
    )

    $AdapterConfigPath = Resolve-AdapterConfigPath -Config $Config -RuntimeRoot $RuntimeRoot -WriteLog $WriteLog -ResolveNormalizedPath $ResolveNormalizedPath
    if ([string]::IsNullOrWhiteSpace($AdapterConfigPath)) {
        & $WriteLog 'Adapter execution skipped. No adapter configuration present.' 'INFO'
        return $true
    }

    & $WriteLog ("Resolved adapter config path: {0}" -f $AdapterConfigPath) 'INFO'
    $MgsbiPath = & $ResolveNormalizedPath (Resolve-MgsbiExecutablePath)
    & $WriteLog ("Resolved MGSBI executable: {0}" -f $MgsbiPath) 'INFO'

    $AdapterDefinition = Get-AdapterImportDefinitions -ConfigFile $AdapterConfigPath -WriteLog $WriteLog -ResolveNormalizedPath $ResolveNormalizedPath
    $ImportsToRun = @($AdapterDefinition.RunnableImports)
    if (-not $ImportsToRun -or $ImportsToRun.Count -eq 0) {
        $AvailableImports = @($AdapterDefinition.Imports | ForEach-Object { $_.Name } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
        $AvailableImportsText = if ($AvailableImports.Count -gt 0) { $AvailableImports -join ', ' } else { '<none>' }
        throw "Adapter XML contains no runnable imports to execute: $($AdapterDefinition.ConfigFile). Available imports: $AvailableImportsText"
    }

    foreach ($ImportDefinition in $ImportsToRun) {
        $ImportName = [string]$ImportDefinition.Name
        $SessionUid = [guid]::NewGuid().ToString()
        $SafeImportName = ($ImportName -replace '[^A-Za-z0-9._-]', '_')
        $AdapterLogFile = & $ResolveNormalizedPath (Join-Path -Path $LogDirectory -ChildPath ("{0}_04_Adapter.BAS_{1}.log" -f $RunId, $SafeImportName))
        $ArgumentString = '/Import="{0}" /ConfigFile="{1}" /SessionUID={2} /LogFile="{3}"' -f $ImportName, $AdapterDefinition.ConfigFile, $SessionUid, $AdapterLogFile

        & $WriteLog ("Starting Flexera Business Adapter import: {0}" -f $ImportName) 'INFO'
        & $WriteLog ("Adapter command line: {0} {1}" -f $MgsbiPath, $ArgumentString) 'INFO'
        & $WriteLog ("Adapter config file: {0}" -f $AdapterDefinition.ConfigFile) 'INFO'
        & $WriteLog ("Adapter log file: {0}" -f $AdapterLogFile) 'INFO'
        & $WriteLog ("Adapter session UID: {0}" -f $SessionUid) 'INFO'

        $Process = Start-Process -FilePath $MgsbiPath -ArgumentList $ArgumentString -Wait -PassThru -NoNewWindow
        & $WriteLog ("Flexera Business Adapter import [{0}] finished with exit code: {1}" -f $ImportName, $Process.ExitCode) 'INFO'
        if ($Process.ExitCode -ne 0) { throw "Flexera Business Adapter import [$ImportName] failed with exit code $($Process.ExitCode)." }
    }

    & $WriteLog 'Flexera Business Adapter execution completed successfully.' 'INFO'
    return $true
}

Export-ModuleMember -Function Resolve-AdapterConfigPath, Resolve-MgsbiExecutablePath, Get-XmlAttributeValue, Get-AdapterImportDefinitions, Invoke-FlexeraBusinessAdapter
