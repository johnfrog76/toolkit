# PSScriptAnalyzer, for the CLI half: utilities.psm1, Prompt20Toolkit/, Scripts/, Tests/,
# Config/'s module wrappers and the agent's two PowerShell files -- every .ps1, .psm1 and
# .psd1 in the repository outside the vendored and generated folders Tests/ScanExclusions.ps1
# names. The command is in docs/CONTRIBUTING.md, "Lint"; the bar is zero at Warning and Error.
#
# PSScriptAnalyzer's defaults, less the rules below. Each one is set aside because the house
# does the thing on purpose, and says where. A rule that finds real defects stays on, and a
# line it is wrong about carries a SuppressMessageAttribute with a Justification instead.
@{
    ExcludeRules = @(
        # A CLI that colours its output. Every verb writes to the console for a person, in
        # colour (-ForegroundColor), and the suites print their own pass/fail lines the same
        # way; Write-Output would put the text in the pipeline a caller captures.
        'PSAvoidUsingWriteHost'

        # The verbs ARE global functions. `function global:` is how utilities.psm1 and the
        # Config/*.commands.ps1 wrappers register a verb so the alias resolves from any scope,
        # and AGENTS.md, "Traps worth knowing", is why module state is reached through them.
        'PSAvoidGlobalFunctions'

        # $global:P20Config (the merged configuration every script reads), $global:P20Env,
        # $global:P20StatedError (the refusal contract's stated sentence) and the module roots
        # are shared on purpose between the module and the scripts it launches -- the one
        # shape AGENTS.md's scope trap says a $script: name cannot carry.
        'PSAvoidGlobalVars'

        # The noun is the thing the command returns or acts on, and the verb surface already
        # carries plurals people type and config.default.json names: Get-P20MyWorkItems,
        # Get-P20PRComments, Sync-P20Prompts, Get-P20ModuleCommands. Renaming them would change
        # the public surface; the helpers follow the same reading (Get-P20WorkItemTypes returns
        # the types, Assert-Contains says what it asserts).
        'PSUseSingularNouns'

        # The house's -WhatIf is a declared [switch], forwarded through $PSBoundParameters
        # from the wrapper to the script and checked there (AGENTS.md, "The refusal contract":
        # a switch goes in the script's param(), the wrapper's and the verb's usage). The two
        # ShouldProcess rules would add -Confirm and a $WhatIfPreference that reaches every
        # cmdlet the script calls; many of the names they catch are pure constructors
        # (New-P20Counts, Set-Stub in a suite) that change nothing outside themselves.
        'PSUseShouldProcessForStateChangingFunctions'
        'PSUseSupportsShouldProcess'

        # The suites' assertion helpers are called positionally by design -- Assert-True
        # '<what>' <condition>, Assert-Equal '<what>' <want> <got> -- which is most of what
        # this rule (Information) finds; Join-Path a b reads the same way everywhere else.
        'PSAvoidUsingPositionalParameters'
    )

    Rules = @{
        # Every .ps1 runs under Windows PowerShell 5.1 and PowerShell 7 (Tests/Test-PS51Compat.ps1);
        # this says the same thing about syntax from the analyzer's side.
        PSUseCompatibleSyntax = @{
            Enable         = $true
            TargetVersions = @('5.1', '7.0')
        }
    }
}
