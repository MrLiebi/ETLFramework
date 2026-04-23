
@{
    Severity = @(
        'Error',
        'Warning'
    )

    ExcludeRules = @(
        'PSAlignAssignmentStatement',
        'PSAvoidTrailingWhitespace',
        'PSPlaceOpenBrace',
        'PSPlaceCloseBrace',
        'PSUseConsistentIndentation',
        'PSUseConsistentWhitespace',
        'PSUseConsistentLineEndings',
        'PSUseConsistentSyntax',
        'PSAvoidUsingWriteHost',
        'PSAvoidUsingEmptyCatchBlock',
        'PSReviewUnusedParameter',
        'PSUseDeclaredVarsMoreThanAssignments',
        'PSUseSingularNouns',
        'PSUseApprovedVerbs',
        'PSUseShouldProcessForStateChangingFunctions',
        'PSShouldProcess'
    )

    Rules = @{
        PSAvoidUsingPlainTextForPassword = @{ Enable = $true }
        PSAvoidUsingConvertToSecureStringWithPlainText = @{ Enable = $true }
        PSAvoidUsingInvokeExpression = @{ Enable = $true }
        PSAvoidUsingCmdletAliases = @{ Enable = $true }
        PSUseApprovedVerbs = @{ Enable = $true }
    }
}
