<#
.SYNOPSIS
    The state of a card, read from its text. The CLI's half of the one rule.
.DESCRIPTION
    There is no status field. A card's state is derived from WHERE the file is
    and then what it says, in this order, and the first that holds wins:

        the file is in backlog/                   -> Backlog   (-Folder)
        the file is in archive/                   -> Done      (-Folder)
        a PR URL: line, or a **Review:** line     -> Code Review
        a commit bullet, or a **Started:** line   -> In Progress
        otherwise                                 -> Active

    The two folder states are read FIRST and whatever the text says: a card in
    backlog/ is planned, not in play, and one in archive/ is done. A caller that
    passes no -Folder is asking about a card in current/ -- every caller did
    before backlog/ existed, so the text rule reads exactly as it always did.
    Tests/fixtures/parsers/states.json is the table both halves assert.

    The rule exists once per half on purpose -- this file and
    agent/core/parsers.py -- and the two are held together by shared fixtures
    in Tests/fixtures/parsers/, asserted from both suites. Patterns and state
    names come from consts.json, read INSIDE the function, so a caller that
    dot-sources this file has no enclosing scope to depend on.

    It is a file of its own so that Status, Move and Tests/Test-Status.ps1 all
    reach the same function by dot-sourcing it; it used to live inside
    Get-PromptStatus.ps1 and the suite lifted it out with a regex.
#>

if (-not (Get-Command Get-P20Consts -ErrorAction SilentlyContinue)) {
    . (Join-Path $PSScriptRoot 'Get-Consts.ps1')
}

function Get-PromptFileStatus {
    param(
        [string]$Content,
        # The folder the card is in: its name (backlog, archive, current) or its
        # path -- the last segment is what is read. Empty means current/.
        [string]$Folder = ''
    )
    # PR URL: line is the state gate between In Progress and Code Review.
    # {cliPrefix}GetPRComments writes it whenever a PR exists -- the URL's presence is the
    # gate, not the presence of reviewer comments (it is written even with none).
    #
    # Patterns and state names from consts.json -- agent/core/parsers.py compiles
    # the same two strings. Read INSIDE the function rather than from a script
    # variable, because Tests/Test-Status.ps1 lifts this function out of the file
    # and runs it on its own: a dependency on enclosing scope would make the
    # suite green by exercising something the command does not do.
    # Two writers per lane: git's token, or a person's. A card with
    # no pull request enters Code Review on a `**Review:**` line ("look at this
    # thing"), and a card with nothing checked in enters In Progress on a
    # `**Started:**` line. Both are written by {cliPrefix}Move, or by hand -- the
    # rule does not care who wrote the line (docs/hub/cards.md).
    $c = Get-P20Consts
    if ($Folder) {
        $leaf = Split-Path -Leaf ($Folder.TrimEnd('/', '\'))
        if ($leaf -eq [string]$c.folders.backlog) { return $c.status.backlog }
        if ($leaf -eq [string]$c.folders.archive) { return $c.status.done }
    }
    if ($Content -match $c.regex.prUrlLine) { return $c.status.codeReview }
    if ($Content -match $c.regex.reviewLine) { return $c.status.codeReview }
    if ($Content -match $c.regex.commitBullet) { return $c.status.inProgress }
    if ($Content -match $c.regex.startedLine) { return $c.status.inProgress }
    return $c.status.active
}

function Test-P20CardBillable {
    <#
      False when the card says `**Billable:** no` (stamps.billable); no line means
      billable, so no existing card needed migrating. The CLI's one reader of the
      stamp: Daily (agent/ado/Get-WeeklyBilling.ps1) and the standup
      (Get-P20StandupCards) both read through it. agent/core/parsers.py's
      card_billable is the same rule.
    #>
    param([AllowEmptyString()][AllowNull()][string]$Content)
    $stamp = [string](Get-P20Consts).stamps.billable
    return -not ([regex]::IsMatch("$Content", '(?mi)^' + [regex]::Escape($stamp) + '\s*no\b'))
}
