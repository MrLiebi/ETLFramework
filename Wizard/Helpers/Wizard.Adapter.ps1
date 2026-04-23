<#
    Helper functions for New-ETLProject.ps1.
    File: Wizard.Adapter.ps1
#>

function Write-Ui {
    [CmdletBinding()]
    param(
        [AllowEmptyString()][string] $Message,
        [string] $ForegroundColor
    )

    Write-Information -MessageData $Message -InformationAction Continue
}

function Read-AdapterConfiguration {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $ProjectName
    )

    Write-Ui ''
    Write-Ui 'WARNING: Flexera Business Adapter generation is an optional wizard step.' -ForegroundColor Yellow
    Write-Ui 'Choose [No] to skip adapter scaffolding for this project.' -ForegroundColor Yellow
    Write-Ui ''

    $CreateAdapter = Read-BooleanChoice -Prompt 'Create Flexera Business Adapter scaffold for this project?' -Default $false
    if (-not $CreateAdapter) {
        Write-Log 'Adapter XML generation skipped by user.' -Level 'WARN'
        Write-Ui '[!] Adapter generation skipped by user.' -ForegroundColor Yellow
        return [PSCustomObject]@{
            AdapterEnabled   = $false
            AdapterName      = $null
            DatabaseName     = $null
            DatabaseServer   = $null
            ConnectionString = $null
            XmlFileName      = 'Adapter.BAS.xml'
            Config           = [ordered]@{
                AdapterEnabled = $false
            }
        }
    }

    Write-Ui ''
    Write-Ui '--- FLEXERA BUSINESS ADAPTER ---' -ForegroundColor Cyan
    Write-Ui 'A blueprint XML from the framework will be copied into the project and must be edited later in Adapter Studio.' -ForegroundColor Yellow

    $AdapterName = Read-InputValue -Prompt '  > Adapter Import Name' -Default $ProjectName
    $DatabaseName = Read-InputValue -Prompt '  > Adapter Database Name' -Default 'FNMSStaging'
    $DatabaseServer = Read-InputValue -Prompt '  > Adapter Database Server' -Default 'localhost'
    $XmlFileName = 'Adapter.BAS.xml'
    $ConnectionString = 'Integrated Security=SSPI;Persist Security Info=False;Initial Catalog={0};Data Source={1}' -f $DatabaseName, $DatabaseServer

    return [PSCustomObject]@{
        AdapterEnabled   = $true
        AdapterName      = $AdapterName
        DatabaseName     = $DatabaseName
        DatabaseServer   = $DatabaseServer
        ConnectionString = $ConnectionString
        XmlFileName      = $XmlFileName
        Config           = [ordered]@{
            AdapterEnabled = $true
            ConfigFile = $XmlFileName
        }
    }
}

function New-AdapterXmlContent {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory)][string] $TemplatePath,
        [Parameter(Mandatory)][string] $ImportName,
        [Parameter(Mandatory)][string] $ConnectionString
    )

    if (-not (Test-PathExists -Path $TemplatePath -PathType Leaf -Description 'Flexera adapter blueprint XML')) {
        throw "Flexera adapter blueprint XML missing: $TemplatePath"
    }

    $ImportNameEscaped = ConvertTo-XmlEscapedValue -Value $ImportName
    $ConnectionStringEscaped = ConvertTo-XmlEscapedValue -Value $ConnectionString
    $TemplateContent = Get-Content -Path $TemplatePath -Raw -Encoding UTF8

    $TemplateContent = $TemplateContent.Replace('__ADAPTER_NAME__', $ImportNameEscaped)
    $TemplateContent = $TemplateContent.Replace('__CONNECTION_STRING__', $ConnectionStringEscaped)

    return $TemplateContent
}

function New-AdapterXmlFile {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory)][pscustomobject] $Adapter,
        [Parameter(Mandatory)][string] $AdapterDirectory,
        [Parameter(Mandatory)][string] $TemplatePath
    )

    if (-not $Adapter.AdapterEnabled) {
        return $null
    }

    if (-not (Test-Path -Path $AdapterDirectory -PathType Container)) {
        New-Item -Path $AdapterDirectory -ItemType Directory -Force | Out-Null
        Write-Log "Directory ensured: $AdapterDirectory" -Level 'INFO'
    }

    $AdapterFilePath = Join-Path -Path $AdapterDirectory -ChildPath $Adapter.XmlFileName
    $AdapterXmlContent = New-AdapterXmlContent -TemplatePath $TemplatePath -ImportName $Adapter.AdapterName -ConnectionString $Adapter.ConnectionString
    Set-Content -Path $AdapterFilePath -Value $AdapterXmlContent -Encoding UTF8
    Write-Log "Adapter XML created from framework blueprint: $AdapterFilePath" -Level 'INFO'
    return $AdapterFilePath
}

