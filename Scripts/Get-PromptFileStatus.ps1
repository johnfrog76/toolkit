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
# Resolve-P20Tracker: which tracker a card's own ADO Link names (Get-P20CardMilestone).
if (-not (Get-Command Resolve-P20Tracker -ErrorAction SilentlyContinue)) {
    . (Join-Path $PSScriptRoot 'Resolve-Tracker.ps1')
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

function Get-P20CardAssigned {
    <#
      Who takes the card: the value of its first `**Assigned:**` line
      (stamps.assigned), trimmed -- `me`, or a size -- and '' when it has none
      (nobody). Route -Assign writes it on a card with no issue behind it
      (D-AR10). The CLI's one reader of the stamp; agent/core/parsers.py's
      card_assigned is the same rule, and Tests/fixtures/parsers/assigned-lines.json
      holds the two to one table.
    #>
    param([AllowEmptyString()][AllowNull()][string]$Content)
    $stamp = [string](Get-P20Consts).stamps.assigned
    $m = [regex]::Match("$Content", '(?m)^' + [regex]::Escape($stamp) + '[ \t]*([^\r\n]*?)[ \t]*\r?$')
    if ($m.Success) { return $m.Groups[1].Value }
    return ''
}

function Get-P20CardAgent {
    <#
      Who did the work, when an agent did: the value of the card's first
      `**Agent:**` line (stamps.agent), trimmed -- a model id, as written -- and
      '' when it has none (a person worked it alone). The line sits beside
      `**Assigned:**`: the person owns the card, the agent worked it. The value is
      never parsed here; Get-P20ModelInfo looks it up in the model map. The CLI's
      one reader of the stamp; agent/core/parsers.py's card_agent is the same
      rule, and Tests/fixtures/parsers/agent-lines.json holds the two to one table.
    #>
    param([AllowEmptyString()][AllowNull()][string]$Content)
    $stamp = [string](Get-P20Consts).stamps.agent
    $m = [regex]::Match("$Content", '(?m)^' + [regex]::Escape($stamp) + '[ \t]*([^\r\n]*?)[ \t]*\r?$')
    if ($m.Success) { return $m.Groups[1].Value }
    return ''
}

function Get-P20CardWorker {
    <#
      Who works the card, as a FAMILY-shaped string the standup, the suggestion
      and StartWork -Launch compare against sizes: when the card has an
      `**Agent:**` line, the model map's family for its id if the id is known,
      else the id as written; with no Agent line, exactly the `**Assigned:**`
      line's value, as those readers took it before (a size, me, or '').

      A BRIDGE: it stands in for the shared resolver of a card's agent
      (Resolve-P20CardAgent) until that lands, and that change
      removes it. Its three callers are Standup-Rules.ps1's card rows and
      Start-Work.ps1's -Launch size check; add none. agent/core/parsers.py's
      card_worker is the same rule, and Tests/fixtures/parsers/card-worker.json
      holds the two to one table.
    #>
    param(
        [Parameter(Position = 0)][AllowEmptyString()][AllowNull()][string]$Text,
        [string]$PackageRoot
    )
    $agentId = Get-P20CardAgent -Content $Text
    if (-not $agentId) { return (Get-P20CardAssigned -Content $Text) }
    $info = if ($PackageRoot) { Get-P20ModelInfo -Id $agentId -PackageRoot $PackageRoot } else { Get-P20ModelInfo -Id $agentId }
    if ($info.known -and $info.family) { return [string]$info.family }
    return $agentId
}

function Get-P20ModelInfo {
    <#
      What the model map (consts.json models.file, Config/models.json) says about
      a model id: [pscustomobject]@{ id; known; provider; family; name }. A known
      id takes its provider, family and display name from its row; an unknown one
      is reported, never guessed at -- known $false, name the id as written,
      provider and family $null. The id is never parsed for a family.
      agent/core/models.py's model_info is the same rule, and
      Tests/fixtures/parsers/models.json holds the two to one table.
    #>
    param(
        [AllowEmptyString()][AllowNull()][string]$Id,
        # The package root the map's path is relative to; the one consts.json sits in by default.
        [string]$PackageRoot
    )
    if (-not $PackageRoot) { $PackageRoot = Split-Path (Get-P20ConstsPath) -Parent }
    $mid = "$Id"
    $path = Join-Path $PackageRoot ([string](Get-P20Consts).models.file)
    # A map that is missing, unreadable or not JSON reads as EMPTY: every id is
    # unknown and reads as written, and nothing throws.
    $map = $null
    if (Test-Path -LiteralPath $path -PathType Leaf) {
        try {
            $raw = Get-Content -LiteralPath $path -Raw -Encoding UTF8 -ErrorAction Stop
            if ($raw) { $map = (ConvertFrom-Json -InputObject $raw -ErrorAction Stop).models }
        }
        catch { $map = $null }
    }
    if ($map -isnot [System.Management.Automation.PSCustomObject]) { $map = $null }
    $row = $null
    if ($mid -and $map) {
        $prop = $map.PSObject.Properties | Where-Object { $_.Name -ceq $mid } | Select-Object -First 1
        if ($prop) { $row = $prop.Value }
    }
    if ($null -eq $row) {
        return [pscustomobject]@{ id = $mid; known = $false; provider = $null; family = $null; name = $mid }
    }
    $name = [string]$row.name
    if (-not $name) { $name = $mid }
    return [pscustomobject]@{ id = $mid; known = $true; provider = [string]$row.provider; family = [string]$row.family; name = $name }
}

function Get-P20ModelForSize {
    <#
      The id a worker size (a family: sonnet, opus) resolves to when a card is
      routed to it: the model map's `current` entry (consts.json models.file),
      matched ignoring case, and '' for a size the map has no entry for or a map
      that is missing or broken. A size is a family alias, not an id, so this is
      the one place it becomes one. agent/core/models.py's current_model is the
      same rule, and Tests/fixtures/parsers/models.json holds the two to one table.
    #>
    param(
        [AllowEmptyString()][AllowNull()][string]$Size,
        # The package root the map's path is relative to; the one consts.json sits in by default.
        [string]$PackageRoot
    )
    if (-not $PackageRoot) { $PackageRoot = Split-Path (Get-P20ConstsPath) -Parent }
    $want = "$Size".Trim()
    if (-not $want) { return '' }
    $path = Join-Path $PackageRoot ([string](Get-P20Consts).models.file)
    $current = $null
    if (Test-Path -LiteralPath $path -PathType Leaf) {
        try {
            $raw = Get-Content -LiteralPath $path -Raw -Encoding UTF8 -ErrorAction Stop
            if ($raw) { $current = (ConvertFrom-Json -InputObject $raw -ErrorAction Stop).current }
        }
        catch { $current = $null }
    }
    if ($current -isnot [System.Management.Automation.PSCustomObject]) { return '' }
    foreach ($prop in $current.PSObject.Properties) {
        if ($prop.Name -ieq $want -and $prop.Value -is [string] -and $prop.Value) { return [string]$prop.Value }
    }
    return ''
}

function Get-P20CardLineValue {
    <#
      The value of a card's FIRST `<stamp> value` line, trimmed: @{ Present; Value }.
      Value is '' for a parenthesised template placeholder (`(not linked)`,
      `(none)`) as for an empty line; Present says whether the line is there at
      all. The milestone and sprint readers below share it, so the two lines are
      read by one rule.
    #>
    param([AllowEmptyString()][AllowNull()][string]$Content, [string]$Stamp)
    $m = [regex]::Match("$Content", '(?m)^' + [regex]::Escape($Stamp) + '[ \t]*([^\r\n]*?)[ \t]*\r?$')
    if (-not $m.Success) { return @{ Present = $false; Value = '' } }
    $value = $m.Groups[1].Value
    if ($value.StartsWith('(')) { $value = '' }
    return @{ Present = $true; Value = $value }
}

function Get-P20CardAdoUrl {
    <#
      The card's own `**ADO Link:**` address when it is an https:// one, else ''.
      What makes a card linked, and what Resolve-P20Tracker reads to say which
      tracker the card belongs to. agent/core/parsers.py's card_ado_url is the same.
    #>
    param([AllowEmptyString()][AllowNull()][string]$Content)
    if ([string]$Content -match '(?m)^\*\*ADO Link:\*\*\s*(https://\S+)') { return $Matches[1].Trim() }
    return ''
}

function Get-P20CardMilestone {
    <#
      The milestone a card names, WHOLE and trimmed -- never the board's shortened
      sprint column -- and '' for none or a template's parenthesised placeholder.
      A card's milestone and its sprint are two lines (stamps.milestone,
      stamps.sprint; docs/hub/cards.md, "Milestone and sprint: two lines"):

        - a `**Milestone:**` line            -> its value (a placeholder is none,
                                                and the sprint line is a sprint only)
        - no `**Milestone:**` line at all    -> the first `**Sprint:**` line's value,
                                                exactly as every card read before
                                                the two were separate
        - ...except on an Azure DevOps card  -> '' (its own ADO Link reads 'ado' by
                                                Resolve-P20Tracker): there the sprint
                                                line is the iteration path, never a
                                                milestone

      Files outlive their templates: a card written when one line held a sprint
      OR a milestone still reads as the milestone it named. D-AR11: the milestone
      is the destination. agent/core/parsers.py's card_milestone is the same rule;
      Tests/fixtures/parsers/card-milestone.json holds the two to one table.
    #>
    param([AllowEmptyString()][AllowNull()][string]$Content)
    $c = Get-P20Consts
    $own = Get-P20CardLineValue -Content $Content -Stamp ([string]$c.stamps.milestone)
    if ($own.Present) { return $own.Value }
    if ((Resolve-P20Tracker -OrgUrl (Get-P20CardAdoUrl $Content)) -eq 'ado') { return '' }
    return (Get-P20CardLineValue -Content $Content -Stamp ([string]$c.stamps.sprint)).Value
}

function Get-P20CardSprint {
    <#
      The sprint a card names: its first `**Sprint:**` line's value, WHOLE and
      trimmed, '' for none or a placeholder. Read whatever the milestone line
      says -- on a card with no milestone line the same value is its milestone
      too (Get-P20CardMilestone). card_sprint in the agent; the same table.
    #>
    param([AllowEmptyString()][AllowNull()][string]$Content)
    return (Get-P20CardLineValue -Content $Content -Stamp ([string](Get-P20Consts).stamps.sprint)).Value
}

function Get-P20CardTags {
    <#
      The card's `Tags:` line, split on commas or semicolons (regex.tagSeparator --
      an Azure DevOps work item's tags arrive `a; b`) and trimmed, empties dropped; none
      for no line or a parenthesised placeholder. The suggestion reads a card's
      severity and size from it. card_tags in the agent; the same table.
      Returns an array -- callers wrap it in @().
    #>
    param([AllowEmptyString()][AllowNull()][string]$Content)
    $m = [regex]::Match("$Content", '(?m)^' + [regex]::Escape([string](Get-P20Consts).tokens.tags) + '[ \t]*([^\r\n]*?)[ \t]*\r?$')
    $value = ''
    if ($m.Success) { $value = $m.Groups[1].Value }
    if ($value.StartsWith('(')) { return @() }
    return @($value -split ([string](Get-P20Consts).regex.tagSeparator) | ForEach-Object { $_.Trim() } | Where-Object { $_ })
}
