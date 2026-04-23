# Installs Pester and PSScriptAnalyzer for framework tests. Comments use American English spelling.
[CmdletBinding()]
param(
    [switch]$Force,
    [string]$PesterVersion = '5.5.0',
    [string]$PSScriptAnalyzerVersion = '1.22.0'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not (Get-PSRepository -Name PSGallery -ErrorAction SilentlyContinue)) {
    throw 'PowerShell Gallery (PSGallery) is not registered on this system.'
}

Set-PSRepository -Name PSGallery -InstallationPolicy Trusted

$Modules = @(
    @{ Name = 'Pester'; Version = $PesterVersion },
    @{ Name = 'PSScriptAnalyzer'; Version = $PSScriptAnalyzerVersion }
)

foreach ($Module in $Modules) {
    $Installed = Get-Module -ListAvailable -Name $Module.Name | Sort-Object Version -Descending | Select-Object -First 1
    if (-not $Force -and $Installed -and $Installed.Version -ge [version]$Module.Version) {
        Write-Information -MessageData "Using existing module $($Module.Name) $($Installed.Version)" -InformationAction Continue
        continue
    }

    Install-Module -Name $Module.Name -Scope CurrentUser -Force:$Force -MinimumVersion $Module.Version -AllowClobber
}
