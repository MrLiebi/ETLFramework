<#
    Helper functions for New-ETLProject.ps1.
    File: Wizard.ProjectFiles.ps1
#>

function Copy-TemplateFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $SourcePath,
        [Parameter(Mandatory)][string] $DestinationPath,
        [Parameter(Mandatory)][string] $Description
    )

    if (-not (Test-PathExists -Path $SourcePath -PathType Leaf -Description $Description)) {
        throw "$Description missing: $SourcePath"
    }

    $DestinationDirectory = if (Test-Path -Path $DestinationPath -PathType Container) {
        $DestinationPath
    }
    else {
        Split-Path -Path $DestinationPath -Parent
    }

    if (-not [string]::IsNullOrWhiteSpace($DestinationDirectory) -and -not (Test-Path -Path $DestinationDirectory -PathType Container)) {
        New-Item -Path $DestinationDirectory -ItemType Directory -Force | Out-Null
    }

    Copy-Item -Path $SourcePath -Destination $DestinationPath -Force
    Write-Log "$Description copied to: $DestinationPath" -Level "INFO"
}

function Copy-TemplateDirectory {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $SourcePath,
        [Parameter(Mandatory)][string] $DestinationPath,
        [Parameter(Mandatory)][string] $Description
    )

    if (-not (Test-PathExists -Path $SourcePath -PathType Container -Description $Description)) {
        throw "$Description missing: $SourcePath"
    }

    if (-not (Test-Path -Path $DestinationPath -PathType Container)) {
        New-Item -Path $DestinationPath -ItemType Directory -Force | Out-Null
    }

    Copy-Item -Path (Join-Path -Path $SourcePath -ChildPath '*') -Destination $DestinationPath -Recurse -Force
    Write-Log "$Description copied to: $DestinationPath" -Level "INFO"
}

function Copy-CustomSourceScriptToProject {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $SourcePath,
        [Parameter(Mandatory)][string] $ProjectScriptDirectory,
        [Parameter(Mandatory)][string] $StepId,
        [Parameter(Mandatory)][string] $StepName
    )

    $ResolvedSourcePath = Resolve-NormalizedPath -Path $SourcePath
    if (-not (Test-Path -Path $ResolvedSourcePath -PathType Leaf)) {
        throw "Custom source script not found: $ResolvedSourcePath"
    }
    if ([System.IO.Path]::GetExtension($ResolvedSourcePath) -ine '.ps1') {
        throw "Custom source script must be a .ps1 file: $ResolvedSourcePath"
    }

    if (-not (Test-Path -Path $ProjectScriptDirectory -PathType Container)) {
        New-Item -Path $ProjectScriptDirectory -ItemType Directory -Force | Out-Null
    }

    $SafeStepName = Get-SafePathSegment -Value $StepName -Fallback ("Step_{0}" -f $StepId)
    $TargetFileName = "Step_{0}_{1}_{2}" -f $StepId, $SafeStepName, [System.IO.Path]::GetFileName($ResolvedSourcePath)
    $TargetPath = Join-Path -Path $ProjectScriptDirectory -ChildPath $TargetFileName
    Copy-Item -Path $ResolvedSourcePath -Destination $TargetPath -Force
    Write-Log "Custom source script copied to project: $TargetPath" -Level 'INFO'
    return $TargetPath
}

function Assert-NoUnresolvedTemplateTokens {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $Content,
        [Parameter(Mandatory)][string] $Description
    )

    $TemplateMatches = [regex]::Matches($Content, '__[A-Z0-9_]+__')
    if ($TemplateMatches.Count -gt 0) {
        $TokenList = ($TemplateMatches | ForEach-Object { $_.Value } | Select-Object -Unique) -join ', '
        throw "Generated $Description still contains unresolved template tokens: $TokenList"
    }
}

function Get-AvailableAdapterTypes {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $TemplateRootPath,
        [Parameter(Mandatory)][ValidateSet('Source','Destination')] [string] $AdapterRole
    )

    if (-not (Test-PathExists -Path $TemplateRootPath -PathType Container -Description ("{0} template directory" -f $AdapterRole))) {
        throw ("{0} template directory missing: {1}" -f $AdapterRole, $TemplateRootPath)
    }

    $Pattern = '^{0}\.(?<Type>.+)\.psm1$' -f [regex]::Escape($AdapterRole)
    $Types = @(
        Get-ChildItem -Path $TemplateRootPath -Filter ("{0}.*.psm1" -f $AdapterRole) -File -ErrorAction Stop |
            ForEach-Object {
                $Match = [regex]::Match($_.Name, $Pattern)
                if ($Match.Success) {
                    [string]$Match.Groups['Type'].Value
                }
            } |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
            Sort-Object -Unique
    )

    if (-not $Types -or $Types.Count -eq 0) {
        throw ("No {0} adapter templates found in: {1}" -f $AdapterRole, $TemplateRootPath)
    }

    Write-Log ("Discovered available {0} adapter types: {1}" -f $AdapterRole.ToLowerInvariant(), ($Types -join ', ')) -Level 'INFO'
    return $Types
}

function Get-AvailableSourceTypes {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $SourceTemplateRootPath
    )

    return @(Get-AvailableAdapterTypes -TemplateRootPath $SourceTemplateRootPath -AdapterRole 'Source')
}

function Get-AvailableDestinationTypes {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $DestinationTemplateRootPath
    )

    return @(Get-AvailableAdapterTypes -TemplateRootPath $DestinationTemplateRootPath -AdapterRole 'Destination')
}

# Backward-compatible aliases for callers that include the Adapter token in the function name.
function Get-AvailableSourceAdapterTypes {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $SourceTemplateRootPath
    )

    return @(Get-AvailableSourceTypes -SourceTemplateRootPath $SourceTemplateRootPath)
}

function Get-AvailableDestinationAdapterTypes {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $DestinationTemplateRootPath
    )

    return @(Get-AvailableDestinationTypes -DestinationTemplateRootPath $DestinationTemplateRootPath)
}



function Clear-GeneratedProjectArtifacts {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $ProjectRoot
    )

    foreach ($RelativePath in @('RUN', 'TASK', 'PS')) {
        $TargetPath = Join-Path -Path $ProjectRoot -ChildPath $RelativePath
        if (Test-Path -LiteralPath $TargetPath) {
            Remove-Item -LiteralPath $TargetPath -Recurse -Force -ErrorAction Stop
            Write-Log "Removed existing generated project artifact: $TargetPath" -Level 'WARN'
        }
    }
}
