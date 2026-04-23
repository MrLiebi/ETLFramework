<#
    Helper functions for New-ETLProject.ps1.
    File: Wizard.FileSources.ps1
#>

function Get-NormalizedSourceFilePattern {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $RawPattern,
        [Parameter(Mandatory)][ValidateSet('CSV','XLSX','XML','JSON')] [string] $SourceType
    )

    $Pattern = $RawPattern.Trim()
    if ([string]::IsNullOrWhiteSpace($Pattern)) {
        $Pattern = '*'
    }

    switch ($SourceType) {
        'CSV' {
            if ($Pattern -match '\.csv$' -or $Pattern -match '\\*\.csv$') {
                return $Pattern
            }
            return ("{0}.csv" -f $Pattern)
        }
        'XLSX' {
            if ($Pattern -match '\.xls\*$' -or $Pattern -match '\.xlsx$' -or $Pattern -match '\.xls$') {
                return $Pattern
            }
            return ("{0}.xls*" -f $Pattern)
        }
        'XML' {
            if ($Pattern -match '\.xml$') {
                return $Pattern
            }
            return ("{0}.xml" -f $Pattern)
        }
        'JSON' {
            if ($Pattern -match '\.json\*$' -or $Pattern -match '\.jsonl$' -or $Pattern -match '\.ndjson$' -or $Pattern -match '\.json$') {
                return $Pattern
            }
            return ("{0}.json*" -f $Pattern)
        }
    }
}

function Read-FileSourcePostImportConfiguration {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateSet('CSV','XLSX','XML','JSON')] [string] $SourceType
    )

    $EnableBackup = Read-BooleanChoice -Prompt '  > Backup source file after successful import?' -Default $true
    $BackupPath = 'INPUT\_Backup'
    if ($EnableBackup) {
        $BackupPathInput = Read-InputValue -Prompt '  > Backup target path' -Default $BackupPath -AllowEmpty
        $BackupPathInput = $BackupPathInput.Trim().Trim('"').Trim()
        if (-not [string]::IsNullOrWhiteSpace($BackupPathInput)) {
            $BackupPath = $BackupPathInput.TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar)
            if ([string]::IsNullOrWhiteSpace($BackupPath)) {
                $BackupPath = 'INPUT\_Backup'
            }
        }
    }

    $DeleteAfterImport = Read-BooleanChoice -Prompt '  > Delete source file after successful import?' -Default $false

    return [PSCustomObject]@{
        BackupAfterImport = $EnableBackup
        BackupPath        = $BackupPath
        DeleteAfterImport = $DeleteAfterImport
    }
}

function Read-FileSourceConfiguration {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateSet('CSV','XLSX','XML','JSON')] [string] $SourceType,
        [Parameter(Mandatory)][string] $SpecificFileDefault
    )

    $DefaultDirectoryPath = 'INPUT'
    $DirectoryPrompt = switch ($SourceType) {
        'CSV'  { '  > Source directory path for CSV files' }
        'XLSX' { '  > Source directory path for Excel files' }
        'XML'  { '  > Source directory path for XML files' }
        'JSON' { '  > Source directory path for JSON / JSONL files' }
    }

    $DirectoryPath = Read-InputValue -Prompt $DirectoryPrompt -Default $DefaultDirectoryPath
    $DirectoryPath = $DirectoryPath.Trim().Trim('"').Trim()
    if ([string]::IsNullOrWhiteSpace($DirectoryPath)) {
        $DirectoryPath = $DefaultDirectoryPath
    }
    $DirectoryPath = $DirectoryPath.TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar)
    if ([string]::IsNullOrWhiteSpace($DirectoryPath)) {
        $DirectoryPath = $DefaultDirectoryPath
    }

    $Selection = Read-Choice -Title ("SELECT FILE INPUT MODE FOR {0}" -f $SourceType) -Options @('Specific file', 'File pattern')

    if ($Selection -eq 'Specific file') {
        $SpecificFileName = Read-InputValue -Prompt ("  > {0} filename" -f $SourceType) -Default $SpecificFileDefault
        return [PSCustomObject]@{
            Path        = (Join-Path -Path $DirectoryPath -ChildPath $SpecificFileName)
            FilePattern = $null
        }
    }

    $PatternPrompt = switch ($SourceType) {
        'CSV'  { '  > File pattern (extension .csv is added automatically)' }
        'XLSX' { '  > File pattern (extension .xls* is added automatically)' }
        'XML'  { '  > File pattern (extension .xml is added automatically)' }
        'JSON' { '  > File pattern (extension .json* is added automatically)' }
    }

    $RawPattern = Read-InputValue -Prompt $PatternPrompt -Default '*'
    return [PSCustomObject]@{
        Path        = $DirectoryPath
        FilePattern = Get-NormalizedSourceFilePattern -RawPattern $RawPattern -SourceType $SourceType
    }
}

