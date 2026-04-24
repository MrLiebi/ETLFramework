<#
    Helper functions for New-ETLProject.ps1.
    File: Wizard.Paths.ps1
#>

function Test-PathExists {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $Path,
        [Parameter(Mandatory)][ValidateSet('Leaf','Container')] [string] $PathType,
        [Parameter(Mandatory)][string] $Description
    )

    if (-not (Test-Path -Path $Path -PathType $PathType)) {
        Write-Log "$Description not found: $Path" -Level "ERROR"
        return $false
    }

    Write-Log "$Description validated: $Path" -Level "INFO"
    return $true
}

function Resolve-NormalizedPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $Path,
        [string] $BasePath = $null
    )

    if ([string]::IsNullOrWhiteSpace($Path)) {
        throw 'Path value is empty and cannot be normalized.'
    }

    $CandidatePath = $Path.Trim().Trim('"')

    if ([System.IO.Path]::IsPathRooted($CandidatePath)) {
        return [System.IO.Path]::GetFullPath($CandidatePath)
    }

    if ([string]::IsNullOrWhiteSpace($BasePath)) {
        return [System.IO.Path]::GetFullPath($CandidatePath)
    }

    return [System.IO.Path]::GetFullPath((Join-Path -Path $BasePath -ChildPath $CandidatePath))
}

function Get-SafePathSegment {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $Value,
        [string] $Fallback = 'Value'
    )

    $Result = $Value.Trim()
    $InvalidChars = [System.IO.Path]::GetInvalidFileNameChars() + [char[]]@(':','*','?','"','<','>','|')
    foreach ($InvalidChar in ($InvalidChars | Select-Object -Unique)) {
        $Result = $Result.Replace([string]$InvalidChar, '_')
    }

    $Result = $Result.Trim().Trim('.')
    if ([string]::IsNullOrWhiteSpace($Result)) {
        return $Fallback
    }

    return $Result
}

function Test-InvalidPathChars {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $Value,
        [Parameter(Mandatory)][string] $Description
    )

    $InvalidChars = [System.IO.Path]::GetInvalidPathChars() + [char[]]@('*','?','"','<','>','|')
    foreach ($InvalidChar in ($InvalidChars | Select-Object -Unique)) {
        if ($Value.Contains([string]$InvalidChar)) {
            throw "$Description contains invalid path character [$InvalidChar]: $Value"
        }
    }
}

function Test-DirectoryWritable {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $Path,
        [Parameter(Mandatory)][string] $Description
    )

    try {
        if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
            New-Item -Path $Path -ItemType Directory -Force | Out-Null
        }

        $ProbeFile = Join-Path -Path $Path -ChildPath (".etl_write_test_{0}.tmp" -f ([guid]::NewGuid().ToString('N')))
        Set-Content -Path $ProbeFile -Value 'probe' -Encoding UTF8 -Force
        Remove-Item -Path $ProbeFile -Force -ErrorAction Stop
        Write-Log "$Description validated and writable: $Path" -Level 'INFO'
    }
    catch {
        throw "$Description is not writable: $Path | $($_.Exception.Message)"
    }
}


