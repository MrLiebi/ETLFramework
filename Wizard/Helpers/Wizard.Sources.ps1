<#
    Helper functions for New-ETLProject.ps1.
    File: Wizard.Sources.ps1
#>

function Get-SourceConfigFromWizard {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $SourceType,
        [Parameter(Mandatory)][string] $ProjectName,
        [Parameter(Mandatory)][string] $StepId
    )

    $SourceConfig = [ordered]@{}
    $Properties   = @('*')
    $CreateInput  = $false
    $CredentialSetup = $null

    switch ($SourceType) {
        'LDAP' {
            $SourceConfig['Server']         = Read-InputValue -Prompt '  > Domain Controller (FQDN)' -Default 'my.domain.com'
            $SourceConfig['SearchBase']     = Read-InputValue -Prompt '  > SearchBase' -Default 'dc=my,dc=domain,dc=com'
            $SourceConfig['Filter']         = Read-InputValue -Prompt '  > LDAP Filter' -Default '(&(objectClass=user)(objectCategory=person))'
            $SourceConfig['PageSize']       = '1000'
            $SourceConfig['TimeoutSeconds'] = '120'

            $AuthConfig = Read-CredentialTargetConfiguration -RoleLabel 'Source' -TypeLabel 'LDAP' -ProjectName $ProjectName -StepId $StepId
            $SourceConfig['AuthenticationMode'] = $AuthConfig.AuthenticationMode

            if ($AuthConfig.CredentialTarget) {
                $SourceConfig['CredentialTarget'] = $AuthConfig.CredentialTarget
            }

            if ($AuthConfig.CreateCredential) {
                $CredentialSetup = [PSCustomObject]@{
                    Target   = $AuthConfig.CredentialTarget
                    UserName = $AuthConfig.UserName
                    Password = $AuthConfig.Password
                }
            }

            $PropertyString = Read-InputValue -Prompt '  > Attributes (comma-separated)' -Default 'sAMAccountName, mail, sn, givenName'
            $Properties = @($PropertyString -split ',' | ForEach-Object { $_.Trim() } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
        }

        'MSSQL' {
            $SourceConfig['Server']         = Read-InputValue -Prompt '  > SQL Server' -Default 'localhost'
            $SourceConfig['Database']       = Read-InputValue -Prompt '  > Database' -Default 'FNMSCompliance'
            $SourceConfig['Query']          = Read-InputValue -Prompt '  > SQL Select Query' -Default 'SELECT * FROM [dbo].[ComplianceComputer]'
            $SourceConfig['CommandTimeout'] = '600'

            $AuthConfig = Read-CredentialTargetConfiguration -RoleLabel 'Source' -TypeLabel 'MSSQL' -ProjectName $ProjectName -StepId $StepId
            $SourceConfig['AuthenticationMode'] = $AuthConfig.AuthenticationMode

            if ($AuthConfig.CredentialTarget) {
                $SourceConfig['CredentialTarget'] = $AuthConfig.CredentialTarget
            }

            if ($AuthConfig.CreateCredential) {
                $CredentialSetup = [PSCustomObject]@{
                    Target   = $AuthConfig.CredentialTarget
                    UserName = $AuthConfig.UserName
                    Password = $AuthConfig.Password
                }
            }

            $PropertyString = Read-InputValue -Prompt '  > Columns used (comma-separated, * for all)' -Default '*'
            if ($PropertyString -eq '*') {
                $Properties = @('*')
            }
            else {
                $Properties = @($PropertyString -split ',' | ForEach-Object { $_.Trim() } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
            }
        }

        'CSV' {
            $CsvFileInput = Read-FileSourceConfiguration -SourceType 'CSV' -SpecificFileDefault ("step_{0}_{1}.csv" -f $StepId, $ProjectName)
            $SourceConfig['Path']            = [string]$CsvFileInput.Path
            if (-not [string]::IsNullOrWhiteSpace([string]$CsvFileInput.FilePattern)) {
                $SourceConfig['FilePattern'] = [string]$CsvFileInput.FilePattern
            }
            $SourceConfig['Delimiter']          = Read-InputValue -Prompt '  > Delimiter' -Default ';'
            $SourceConfig['Encoding']           = Read-InputValue -Prompt '  > Encoding (auto, utf8, windows-1252, ...)' -Default 'auto'
            $FileHandlingConfig                 = Read-FileSourcePostImportConfiguration -SourceType 'CSV'
            $SourceConfig['BackupAfterImport']  = $FileHandlingConfig.BackupAfterImport
            $SourceConfig['BackupPath']         = [string]$FileHandlingConfig.BackupPath
            $SourceConfig['DeleteAfterImport']  = $FileHandlingConfig.DeleteAfterImport
            $CreateInput = $true

            $PropertyString = Read-InputValue -Prompt '  > Columns to import (comma-separated, empty for ALL)' -Default '' -AllowEmpty
            if ([string]::IsNullOrWhiteSpace($PropertyString)) {
                $Properties = @('*')
            }
            else {
                $Properties = @($PropertyString -split ',' | ForEach-Object { $_.Trim() } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
            }
        }

        'XLSX' {
            $XlsxFileInput = Read-FileSourceConfiguration -SourceType 'XLSX' -SpecificFileDefault ("step_{0}_{1}.xlsx" -f $StepId, $ProjectName)
            $SourceConfig['Path']               = [string]$XlsxFileInput.Path
            if (-not [string]::IsNullOrWhiteSpace([string]$XlsxFileInput.FilePattern)) {
                $SourceConfig['FilePattern']    = [string]$XlsxFileInput.FilePattern
            }
            $SourceConfig['WorksheetName']      = Read-InputValue -Prompt '  > Worksheet Name' -Default 'Sheet1'
            $SourceConfig['HeaderRowNumber']    = [string](Read-PositiveInteger -Prompt '  > Header Row Number' -Default 1)
            $SourceConfig['DataStartRowNumber'] = [string](Read-PositiveInteger -Prompt '  > Data Start Row Number' -Default 2)
            $SourceConfig['FirstDataColumn']    = [string](Read-PositiveInteger -Prompt '  > First Data Column' -Default 1)
            $FileHandlingConfig                 = Read-FileSourcePostImportConfiguration -SourceType 'XLSX'
            $SourceConfig['BackupAfterImport']  = $FileHandlingConfig.BackupAfterImport
            $SourceConfig['BackupPath']         = [string]$FileHandlingConfig.BackupPath
            $SourceConfig['DeleteAfterImport']  = $FileHandlingConfig.DeleteAfterImport
            $CreateInput = $true

            $PropertyString = Read-InputValue -Prompt '  > Columns to import (comma-separated, empty for ALL)' -Default '' -AllowEmpty
            if ([string]::IsNullOrWhiteSpace($PropertyString)) {
                $Properties = @('*')
            }
            else {
                $Properties = @($PropertyString -split ',' | ForEach-Object { $_.Trim() } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
            }
        }


        'XML' {
            $XmlFileInput = Read-FileSourceConfiguration -SourceType 'XML' -SpecificFileDefault ("step_{0}_{1}.xml" -f $StepId, $ProjectName)
            $SourceConfig['Path']               = [string]$XmlFileInput.Path
            if (-not [string]::IsNullOrWhiteSpace([string]$XmlFileInput.FilePattern)) {
                $SourceConfig['FilePattern']    = [string]$XmlFileInput.FilePattern
            }
            $SourceConfig['RecordXPath']        = Read-InputValue -Prompt '  > Record XPath' -Default '/*/*'
            $FileHandlingConfig                 = Read-FileSourcePostImportConfiguration -SourceType 'XML'
            $SourceConfig['BackupAfterImport']  = $FileHandlingConfig.BackupAfterImport
            $SourceConfig['BackupPath']         = [string]$FileHandlingConfig.BackupPath
            $SourceConfig['DeleteAfterImport']  = $FileHandlingConfig.DeleteAfterImport
            $CreateInput = $true

            $PropertyString = Read-InputValue -Prompt '  > Properties to import (comma-separated, empty for ALL)' -Default '' -AllowEmpty
            if ([string]::IsNullOrWhiteSpace($PropertyString)) {
                $Properties = @('*')
            }
            else {
                $Properties = @($PropertyString -split ',' | ForEach-Object { $_.Trim() } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
            }
        }

        'JSON' {
            $JsonFileInput = Read-FileSourceConfiguration -SourceType 'JSON' -SpecificFileDefault ("step_{0}_{1}.json" -f $StepId, $ProjectName)
            $SourceConfig['Path']               = [string]$JsonFileInput.Path
            if (-not [string]::IsNullOrWhiteSpace([string]$JsonFileInput.FilePattern)) {
                $SourceConfig['FilePattern']    = [string]$JsonFileInput.FilePattern
            }
            $SourceConfig['Format']             = Read-Choice -Title ("SELECT JSON INPUT FORMAT FOR STEP [{0}]" -f $StepId) -Options @('Auto', 'Json', 'JsonL')
            $SourceConfig['RootPath']           = Read-InputValue -Prompt '  > JSON root path (dot notation, empty = root)' -Default '' -AllowEmpty
            $FileHandlingConfig                 = Read-FileSourcePostImportConfiguration -SourceType 'JSON'
            $SourceConfig['BackupAfterImport']  = $FileHandlingConfig.BackupAfterImport
            $SourceConfig['BackupPath']         = [string]$FileHandlingConfig.BackupPath
            $SourceConfig['DeleteAfterImport']  = $FileHandlingConfig.DeleteAfterImport
            $CreateInput = $true

            $PropertyString = Read-InputValue -Prompt '  > Properties to import (comma-separated, empty for ALL)' -Default '' -AllowEmpty
            if ([string]::IsNullOrWhiteSpace($PropertyString)) {
                $Properties = @('*')
            }
            else {
                $Properties = @($PropertyString -split ',' | ForEach-Object { $_.Trim() } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
            }
        }

        'CustomScript' {
            if (-not (Show-CustomScriptContractAndConfirm -StepId $StepId)) {
                throw "Custom Script contract was not accepted for step [$StepId]."
            }

            $ScriptLocation = Read-InputValue -Prompt '  > Custom script location (.ps1)'
            $ResolvedScriptLocation = Resolve-NormalizedPath -Path $ScriptLocation
            if (-not (Test-Path -Path $ResolvedScriptLocation -PathType Leaf)) {
                throw "Custom source script file not found: $ResolvedScriptLocation"
            }
            if ([System.IO.Path]::GetExtension($ResolvedScriptLocation) -ine '.ps1') {
                throw "Custom source script must be a .ps1 file: $ResolvedScriptLocation"
            }

            $SourceConfig['ScriptPath'] = [string]$ResolvedScriptLocation
            $SourceConfig['Parameters'] = [hashtable](Invoke-CustomScriptParameterWizard -ScriptPath $ResolvedScriptLocation -StepId $StepId)

            $PropertyString = Read-InputValue -Prompt '  > Properties to forward (comma-separated, * for all)' -Default '*'
            if ($PropertyString -eq '*') {
                $Properties = @('*')
            }
            else {
                $Properties = @($PropertyString -split ',' | ForEach-Object { $_.Trim() } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
            }
        }
    }

    if (-not $Properties -or $Properties.Count -eq 0) {
        $Properties = @('*')
    }

    return [PSCustomObject]@{
        Config          = $SourceConfig
        Properties      = $Properties
        CreateInput     = $CreateInput
        CredentialSetup = $CredentialSetup
    }
}

