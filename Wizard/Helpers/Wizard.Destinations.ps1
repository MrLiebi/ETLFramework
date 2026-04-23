<#
    Helper functions for New-ETLProject.ps1.
    File: Wizard.Destinations.ps1
#>

function Get-DestinationConfigFromWizard {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $DestinationType,
        [Parameter(Mandatory)][string] $ProjectName,
        [Parameter(Mandatory)][string] $StepId
    )

    $DestinationConfig = [ordered]@{}
    $CreateOutput      = $false
    $CredentialSetup   = $null

    switch ($DestinationType) {
        'MSSQL' {
            $DestinationConfig['Server']          = Read-InputValue -Prompt '  > SQL Server' -Default 'localhost'
            $DestinationConfig['Database']        = Read-InputValue -Prompt '  > Database' -Default 'FNMSStaging'
            $DestinationConfig['Schema']          = Read-InputValue -Prompt '  > Target Schema' -Default 'dbo'
            $DestinationConfig['TableName']       = Read-InputValue -Prompt '  > Target Table' -Default ("Step{0}" -f $StepId)
            $DestinationConfig['DropCreate']      = Read-BooleanChoice -Prompt '  > Recreate target table?' -Default $true
            $DestinationConfig['BulkCopyTimeout'] = '600'
            $DestinationConfig['BatchSize']       = '5000'
            $DestinationConfig['InferenceSampleSize'] = '1000'
            $DestinationConfig['DecimalPrecision'] = '19'
            $DestinationConfig['DecimalScale']     = '6'
            $DestinationConfig['FailOnConversionError'] = $false
            $DestinationConfig['MaxConversionErrorsPerColumn'] = '10'

            $AuthConfig = Read-CredentialTargetConfiguration -RoleLabel 'Destination' -TypeLabel 'MSSQL' -ProjectName $ProjectName -StepId $StepId
            $DestinationConfig['AuthenticationMode'] = $AuthConfig.AuthenticationMode

            if ($AuthConfig.CredentialTarget) {
                $DestinationConfig['CredentialTarget'] = $AuthConfig.CredentialTarget
            }

            if ($AuthConfig.CreateCredential) {
                $CredentialSetup = [PSCustomObject]@{
                    Target   = $AuthConfig.CredentialTarget
                    UserName = $AuthConfig.UserName
                    Password = $AuthConfig.Password
                }
            }
        }

        'CSV' {
            $CsvFileName = Read-InputValue -Prompt '  > Output CSV Filename (stored in OUTPUT folder)' -Default ("step_{0}_{1}.csv" -f $StepId, $ProjectName)
            $DestinationConfig['Path']      = "OUTPUT\$CsvFileName"
            $DestinationConfig['Delimiter'] = Read-InputValue -Prompt '  > Delimiter' -Default ';'
            $DestinationConfig['Encoding']  = Read-InputValue -Prompt '  > Encoding' -Default 'UTF8'
            $DestinationConfig['Append']    = Read-BooleanChoice -Prompt '  > Append to existing file?' -Default $false
            $DestinationConfig['Force']     = $true
            $DestinationConfig['BatchSize'] = '1000'
            $CreateOutput = $true
        }
    }

    return [PSCustomObject]@{
        Config          = $DestinationConfig
        CreateOutput    = $CreateOutput
        CredentialSetup = $CredentialSetup
    }
}
