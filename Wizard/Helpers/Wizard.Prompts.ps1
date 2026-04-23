<#
    Helper functions for New-ETLProject.ps1.
    File: Wizard.Prompts.ps1
#>

function Write-Ui {
    [CmdletBinding()]
    param(
        [AllowEmptyString()][string] $Message,
        [string] $ForegroundColor
    )

    Write-Information -MessageData $Message -InformationAction Continue
}

function Test-NonInteractiveMode {
    [CmdletBinding()]
    param()

    # ETL_TEST_NONINTERACTIVE: production / explicit CI wizard runs.
    # ETL_FRAMEWORK_TEST_AUTOMATION: set by Tests/TestHelpers.ps1 so Pester runs never block on Read-Host
    # after per-fixture env cleanup (Clear-FrameworkTestEnvironment used to drop only ETL_TEST_*).
    return ($env:ETL_TEST_NONINTERACTIVE -eq '1' -or $env:ETL_FRAMEWORK_TEST_AUTOMATION -eq '1')
}

function Read-Choice {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $Title,
        [Parameter(Mandatory)][string[]] $Options
    )

    Write-Ui ""
    Write-Ui "--- $Title ---" -ForegroundColor Cyan

    for ($i = 0; $i -lt $Options.Count; $i++) {
        Write-Ui ("{0}. {1}" -f ($i + 1), $Options[$i])
    }

    if (Test-NonInteractiveMode) {
        return $Options[0]
    }

    do {
        $Selection = Read-Host ("Select (1-{0})" -f $Options.Count)
    } until ($Selection -match '^\d+$' -and [int]$Selection -ge 1 -and [int]$Selection -le $Options.Count)

    return $Options[[int]$Selection - 1]
}

function Read-InputValue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $Prompt,
        [string] $Default = $null,
        [switch] $AllowEmpty
    )

    if (Test-NonInteractiveMode) {
        if ($null -ne $Default) { return [string]$Default }
        if ($AllowEmpty) { return '' }
        return 'non-interactive-value'
    }

    if ($null -ne $Default) {
        $Value = Read-Host "$Prompt [$Default]"
        if ([string]::IsNullOrWhiteSpace($Value)) {
            return $Default
        }
        return $Value.Trim()
    }

    do {
        $Value = Read-Host $Prompt
    } until ($AllowEmpty -or -not [string]::IsNullOrWhiteSpace($Value))

    return $Value.Trim()
}

function Read-BooleanChoice {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $Prompt,
        [bool] $Default = $true
    )

    $DefaultText = if ($Default) { 'Y' } else { 'N' }

    if (Test-NonInteractiveMode) {
        return $Default
    }

    do {
        $Value = Read-Host "$Prompt [Y/N] (Default: $DefaultText)"
        if ([string]::IsNullOrWhiteSpace($Value)) {
            return $Default
        }

        switch ($Value.Trim().ToUpperInvariant()) {
            'Y' { return $true }
            'N' { return $false }
        }
    } until ($false)
}

function Read-PositiveInteger {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $Prompt,
        [int] $Default = 1
    )

    if (Test-NonInteractiveMode) {
        return $Default
    }

    do {
        $Value = Read-Host "$Prompt [$Default]"
        if ([string]::IsNullOrWhiteSpace($Value)) {
            return $Default
        }
    } until ($Value -match '^\d+$' -and [int]$Value -gt 0)

    return [int]$Value
}

function Read-NonNegativeInteger {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $Prompt,
        [int] $Default = 0
    )

    if (Test-NonInteractiveMode) {
        return $Default
    }

    do {
        $Value = Read-Host "$Prompt [$Default]"
        if ([string]::IsNullOrWhiteSpace($Value)) {
            return $Default
        }
    } until ($Value -match '^\d+$' -and [int]$Value -ge 0)

    return [int]$Value
}

function Read-ValidatedDateValue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $Prompt,
        [Parameter(Mandatory)][string] $Default,
        [string] $Format = 'yyyy-MM-dd'
    )

    do {
        $Value = Read-InputValue -Prompt $Prompt -Default $Default
        $ParsedValue = [datetime]::MinValue
    } until ([datetime]::TryParseExact($Value, $Format, [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::None, [ref]$ParsedValue))

    return $ParsedValue.ToString($Format, [System.Globalization.CultureInfo]::InvariantCulture)
}

function Read-ValidatedTimeValue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $Prompt,
        [Parameter(Mandatory)][string] $Default,
        [string] $Format = 'HH:mm:ss'
    )

    do {
        $Value = Read-InputValue -Prompt $Prompt -Default $Default
        $ParsedValue = [datetime]::MinValue
    } until ([datetime]::TryParseExact($Value, $Format, [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::None, [ref]$ParsedValue))

    return $ParsedValue.ToString($Format, [System.Globalization.CultureInfo]::InvariantCulture)
}

function Get-ValidatedDaysOfWeek {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string[]] $DaysOfWeek
    )

    $AllowedDays = [System.Collections.Specialized.OrderedDictionary]::new()
    foreach ($DayName in @('Monday','Tuesday','Wednesday','Thursday','Friday','Saturday','Sunday')) {
        $AllowedDays[$DayName.ToUpperInvariant()] = $DayName
    }

    $NormalizedDays = New-Object System.Collections.Generic.List[string]
    foreach ($Day in @($DaysOfWeek)) {
        $Candidate = [string]$Day
        if ([string]::IsNullOrWhiteSpace($Candidate)) {
            continue
        }

        $LookupKey = $Candidate.Trim().ToUpperInvariant()
        if (-not $AllowedDays.Contains($LookupKey)) {
            throw "Unsupported day of week in schedule configuration: $Candidate"
        }

        $NormalizedName = [string]$AllowedDays[$LookupKey]
        if (-not $NormalizedDays.Contains($NormalizedName)) {
            [void]$NormalizedDays.Add($NormalizedName)
        }
    }

    if ($NormalizedDays.Count -eq 0) {
        throw 'At least one valid day of week must be provided for weekly schedules.'
    }

    return @($NormalizedDays.ToArray())
}

