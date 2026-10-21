#
# Which card does this branch belong to?
#
# NOT a runnable verb: this file is DOT-SOURCED. `NewPR` has resolved the card
# from the branch name since it was written; `ThreadHash` used to pick "the most
# recently modified file in current/" instead, which is a different question and
# answered it wrong whenever two cards were open at once.
#
#
# Both verbs run in the code repo, on a branch named after the work item, so
# there is exactly one rule and it lives here.
#
# The rule, in the order it is tried:
#   1. The branch's last segment IS the card's base name --
#      `user/137-fix-the-thing` -> `137-fix-the-thing.prompt.md`, and a card
#      whose name is a PREFIX of that segment also matches (branch slugs are
#      often longer than the file's).
#   2. Failing that, the work item id out of the branch -- `user/144/slug` and
#      `user/223086-slug` both yield the id -- matched by the one id rule
#      (Resolve-CardName.ps1). Only accepted when exactly one card matches.
#
# Ambiguity is never guessed at. When several cards match and none exactly,
# the answer is NO card -- it used to be "the first one", which is how a hash
# could be threaded into the wrong card.
# A caller that wants
# to SAY how many matched asks with -Detailed and gets the candidates back, so
# the refusal names them; the plain call keeps returning a path or $null.
#
# PowerShell 5.1 clean: no ternary, no null-coalescing, ASCII hyphens only.
#

function Resolve-P20CardForBranch {
    <#
        Returns the full path of the card for $Branch in $CurrentDir, or $null.
        Never writes, never throws on a missing folder -- the caller states the
        refusal, because NewPR and ThreadHash word it differently.

        $CurrentDir takes one folder or several, searched together: NewPR and
        ThreadHash pass current/ AND backlog/, because their first write into a
        backlog card is what pulls it into play (Scripts/Move-CardFolder.ps1).
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'Detailed', Justification = 'Read inside the $answer scriptblock, which the rule does not follow.')]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Branch,
        [Parameter(Mandatory = $true)][AllowEmptyString()][AllowEmptyCollection()][AllowNull()][string[]]$CurrentDir,
        [switch]$Detailed
    )

    # -Detailed: @{ Path = <string or $null>; Candidates = @(<leaf names>) }.
    # Candidates holds more than one name only when the branch was ambiguous.
    $answer = { param($Path, $Names)
        if ($Detailed) { return @{ Path = $Path; Candidates = @($Names) } }
        return $Path
    }

    $dirs = @(@($CurrentDir) | Where-Object { $_ -and (Test-Path -LiteralPath $_) })
    if (-not $Branch -or $dirs.Count -eq 0) { return (& $answer $null @()) }
    $cardFiles = @(foreach ($d in $dirs) { Get-ChildItem -LiteralPath $d -Filter "*.prompt.md" -File -ErrorAction SilentlyContinue })

    # Match branch name to prompt filename
    # Branch: v-someone/223086-ms-teams-search-progress-...
    # File:   223086-ms-teams-search-progress-....prompt.md
    . (Join-Path $PSScriptRoot 'Resolve-CardName.ps1')
    $idShape = Get-P20CardIdShape
    # -cmatch: an id with letters is UPPERCASE, so a lowercase branch word ("cat7-fix") is not one.
    if ($Branch -cmatch ('/((?:' + $idShape + ')-.+)$')) {
        $branchSuffix = $Matches[1]
        $candidates = @($cardFiles |
            Where-Object { ($_.BaseName -replace '\.prompt$', '') -eq $branchSuffix -or
                           $branchSuffix.StartsWith(($_.BaseName -replace '\.prompt$', '')) })
        if ($candidates.Count -eq 1) {
            return (& $answer $candidates[0].FullName @($candidates[0].Name))
        }
        elseif ($candidates.Count -gt 1) {
            # An exact name wins over the prefix matches. Several prefix matches
            # and no exact one is ambiguity, and ambiguity is not a card.
            $exact = @($candidates | Where-Object { ($_.BaseName -replace '\.prompt$', '') -eq $branchSuffix })
            if ($exact.Count -eq 1) { return (& $answer $exact[0].FullName @($exact[0].Name)) }
            return (& $answer $null @($candidates | ForEach-Object { $_.Name }))
        }
    }

    # Fallback: extract work item ID from branch, match by ID prefix.
    # `user/144/slug` (the story shape) and `user/137-slug` both reach here.
    #
    # Matched by the ONE id rule. This used to be `$_.Name -match "^$id-"`, which
    # can only ever find a bare-bug card: `Task139-...` and `US-144-...` start
    # with their type, so a story or a task was never found from its branch.
    #
    $workItemId = $null
    if ($Branch -match '/(\d{4,})[-/]') { $workItemId = $Matches[1] }
    elseif ($Branch -cmatch ('/(' + $idShape + ')[-/]')) { $workItemId = $Matches[1] }
    if ($workItemId) {
        if (Test-P20IsWorkItemId $workItemId) { $workItemId = [string]([long]$workItemId) }
        $idPattern = Get-P20CardIdPattern -WorkItemTypes (Get-P20WorkItemTypes -Config $global:P20Config)
        $candidates = @($cardFiles |
            Where-Object { (Get-P20CardId -Name $_.Name -Pattern $idPattern) -eq $workItemId })
        if ($candidates.Count -eq 1) {
            return (& $answer $candidates[0].FullName @($candidates[0].Name))
        }
        if ($candidates.Count -gt 1) {
            return (& $answer $null @($candidates | ForEach-Object { $_.Name }))
        }
    }

    return (& $answer $null @())
}
