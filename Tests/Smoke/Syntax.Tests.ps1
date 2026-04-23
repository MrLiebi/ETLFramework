Set-StrictMode -Version Latest
. (Join-Path -Path (Split-Path -Parent (Split-Path -Parent $PSCommandPath)) -ChildPath 'TestHelpers.ps1')

BeforeAll {
    $script:FrameworkRoot = Get-FrameworkRoot -StartPath $PSScriptRoot
    $script:FrameworkFiles = @(Get-FrameworkSourceFiles -FrameworkRoot $script:FrameworkRoot | ForEach-Object {
        [PSCustomObject]@{
            FullName     = $_.FullName
            RelativePath = Get-RelativeFrameworkPath -FrameworkRoot $script:FrameworkRoot -Path $_.FullName
        }
    })
}

Describe 'PowerShell parser smoke tests' {
    It 'all framework scripts and modules parse without syntax errors' {
        $Failures = foreach ($FrameworkFile in $script:FrameworkFiles) {
            $Tokens = $null
            $ParseErrors = $null
            [void][System.Management.Automation.Language.Parser]::ParseFile($FrameworkFile.FullName, [ref]$Tokens, [ref]$ParseErrors)

            foreach ($ParseError in @($ParseErrors)) {
                [PSCustomObject]@{
                    RelativePath = $FrameworkFile.RelativePath
                    Line         = if ($ParseError.Extent) { $ParseError.Extent.StartLineNumber } else { $null }
                    Message      = $ParseError.Message
                }
            }
        }

        if ($Failures) {
            $Message = ($Failures | ForEach-Object {
                if ($_.Line) {
                    '[{0}:{1}] {2}' -f $_.RelativePath, $_.Line, $_.Message
                }
                else {
                    '[{0}] {1}' -f $_.RelativePath, $_.Message
                }
            }) -join [Environment]::NewLine

            throw "Parser errors detected:`n$Message"
        }
    }
}
