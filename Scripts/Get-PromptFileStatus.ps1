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

function Get-P20ModelObject {
    <#
      A model that did work, as the standup holds one:
      [pscustomobject]@{ id; sessionId; name; family; known }, or $null when the
      id is not a model at all. name, family and known are Get-P20ModelInfo's
      answer for the id, so the id is looked up and never parsed: an id with no
      row is known $false, its name the id as written and its family $null,
      whatever words it holds. A row the map keeps that `current` no longer names
      is still known. sessionId is the session the model was seen in, $null when
      there is none. An empty or missing id, and an id of consts.json
      models.notModels (<synthetic>), is $null: no object.
      agent/core/models.py's model_object is the same rule, and
      Tests/fixtures/rituals/standup-sessions.json's lookup rows hold the two to
      one table.
    #>
    param(
        [AllowEmptyString()][AllowNull()][string]$Id,
        [AllowEmptyString()][AllowNull()][string]$SessionId,
        # The package root the map's path is relative to; the one consts.json sits in by default.
        [string]$PackageRoot
    )
    $mid = "$Id"
    if (-not $mid) { return $null }
    if (@((Get-P20Consts).models.notModels) -ccontains $mid) { return $null }
    $infoArgs = @{ Id = $mid }
    if ($PackageRoot) { $infoArgs.PackageRoot = $PackageRoot }
    $info = Get-P20ModelInfo @infoArgs
    $sid = $null
    if ("$SessionId") { $sid = "$SessionId" }
    return [pscustomobject]@{ id = $mid; sessionId = $sid; name = $info.name; family = $info.family; known = $info.known }
}

# -- Who worked a card: the one reader over its sources --------------------------
# Resolve-P20CardAgent and its pieces. agent/core/parsers.py's resolve_card_agent,
# commit_co_authors and git_messages, and agent/core/models.py's
# model_by_co_author, are the same rules; Tests/fixtures/parsers/agent-source.json
# holds the two halves to one table (docs/hub/cards.md, "How a card's agent is
# worked out"). Every piece is pure but Get-P20ModelMap, which reads one file.

function Get-P20ModelMap {
    <#
      The model map (consts.json models.file) read ONCE, for a caller that asks
      about many ids or trailers: an ordered, case-sensitive dictionary of id ->
      its row, in the file's order. A missing or unreadable file reads as an empty
      map, never a throw -- every id is then unknown and no trailer names a model.
      Pass the answer to Resolve-P20CardAgent and Get-P20ModelByCoAuthor as -Models.
    #>
    param(
        # The package root the map's path is relative to; the one consts.json sits in by default.
        [string]$PackageRoot
    )
    $map = New-Object System.Collections.Specialized.OrderedDictionary
    try {
        if (-not $PackageRoot) { $PackageRoot = Split-Path (Get-P20ConstsPath) -Parent }
        $path = Join-Path $PackageRoot ([string](Get-P20Consts).models.file)
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return $map }
        $rows = (Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json).models
        if ($null -ne $rows) {
            foreach ($p in @($rows.PSObject.Properties)) { $map[[string]$p.Name] = $p.Value }
        }
    } catch {
        return (New-Object System.Collections.Specialized.OrderedDictionary)
    }
    return $map
}

function Get-P20ModelCurrent {
    <#
      The model map's top-level `current` block -- a worker size (a family alias:
      sonnet, opus) -> the model id it resolves to today -- as a hashtable; absent,
      missing or unreadable reads as empty, never a throw. Resolve-P20CardAgent's
      assigned source reads it. read_model_current in the agent.
    #>
    param([string]$PackageRoot)
    $cur = @{}
    try {
        if (-not $PackageRoot) { $PackageRoot = Split-Path (Get-P20ConstsPath) -Parent }
        $path = Join-Path $PackageRoot ([string](Get-P20Consts).models.file)
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return $cur }
        $block = (Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json).current
        if ($null -ne $block) { foreach ($p in @($block.PSObject.Properties)) { $cur[[string]$p.Name] = [string]$p.Value } }
    } catch {
        return @{}
    }
    return $cur
}

function ConvertTo-P20ModelMap {
    <# -Models as a dictionary: $null reads the shipped map (Get-P20ModelMap), a dictionary is kept, an object (a JSON block) becomes one. #>
    param($Models)
    if ($null -eq $Models) { return (Get-P20ModelMap) }
    if ($Models -is [System.Collections.IDictionary]) { return $Models }
    $map = New-Object System.Collections.Specialized.OrderedDictionary
    foreach ($p in @($Models.PSObject.Properties)) { $map[[string]$p.Name] = $p.Value }
    return $map
}

function Get-P20CommitCoAuthors {
    <#
      The names a commit message's Co-Authored-By trailers carry, trimmed, in the
      order they are written: one per line that matches consts.json
      regex.coAuthorTrailer (the key in any case -- `Co-Authored-By`,
      `Co-authored-by` -- and the name before an <email>). A person's name is a
      name too; whether it names a model is Get-P20ModelByCoAuthor's question.
      commit_co_authors in the agent.
    #>
    param([AllowEmptyString()][AllowNull()][string]$Message)
    $names = New-Object 'System.Collections.Generic.List[string]'
    foreach ($m in [regex]::Matches("$Message", [string](Get-P20Consts).regex.coAuthorTrailer)) {
        $name = $m.Groups[1].Value.Trim()
        if ($name) { $names.Add($name) }
    }
    return , ([string[]]$names.ToArray())
}

function Get-P20ModelByCoAuthor {
    <#
      The model id whose row's coAuthor is this trailer name -- both trimmed,
      compared ignoring case -- or $null. A lookup, never a parse: a name no row
      carries (a person, a model the map does not know) names no model, and a
      row with no coAuthor is never named by a trailer. -Models is the map
      (Get-P20ModelMap's answer, or a JSON block); $null reads the shipped one.
      models.model_by_co_author in the agent.
    #>
    param([AllowEmptyString()][AllowNull()][string]$Name, $Models)
    $want = "$Name".Trim()
    if (-not $want) { return $null }
    $map = ConvertTo-P20ModelMap $Models
    foreach ($k in @($map.Keys)) {
        $co = $map[$k].coAuthor
        if ($null -eq $co) { continue }
        if ([string]::Equals(([string]$co).Trim(), $want, [System.StringComparison]::OrdinalIgnoreCase)) { return [string]$k }
    }
    return $null
}

function ConvertFrom-P20GitMessages {
    <#
      The output of `git log --no-walk=unsorted --ignore-missing
      --format=%x00%H%x1f%B <hashes>` -> an ordered dictionary of short hash (its
      first seven characters, lower case) -> the commit's message, its trailing
      line endings removed. A record with no unit separator, or whose hash is not
      7 to 40 hex characters, is skipped; a commit given twice keeps the first.
      Pure: the caller runs git. git_messages in the agent.
    #>
    param([AllowEmptyString()][AllowNull()][string]$Raw)
    $map = New-Object System.Collections.Specialized.OrderedDictionary
    foreach ($rec in ("$Raw").Split([char]0)) {
        $cut = $rec.IndexOf([char]0x1f)
        if ($cut -lt 0) { continue }
        $hash = $rec.Substring(0, $cut).Trim().ToLowerInvariant()
        if ($hash -cnotmatch '^[0-9a-f]{7,40}$') { continue }
        $key = $hash.Substring(0, 7)
        if ($map.Contains($key)) { continue }
        $map[$key] = $rec.Substring($cut + 1).TrimEnd([char]13, [char]10)
    }
    return $map
}

function Resolve-P20CardAgent {
    <#
      Who worked a card, worked out every time it is read and never written into
      it: [pscustomobject]@{ id; family; source }. The sources are tried in
      -Order (default consts.json models.agentSources) and the first that answers
      wins:

        line     the card's **Agent:** line (Get-P20CardAgent): id as written;
                 family from the id's row, else the id as written
        assigned a card with NO Agent line whose **Assigned:** value
                 (Get-P20CardAssigned) names a worker -- a size, which Route
                 -Assign <size> writes on a card with no issue. Read tolerantly:
                 a key of the map's `current` block (ignoring case) is its model, id
                 current[size] and family that id's (else the id as written);
                 any other value is the worker as written, id $null and family
                 the value. Empty, rituals.assignMe (`me`, in any case) and an
                 `@<login>` do not answer
        trailer  only when -Messages is given: the card's own commit bullets
                 (regex.commitBullet, the squash-merged bullet among them --
                 distinct by their first seven characters, in bullet order)
                 looked up in -Messages; each commit votes once for every model
                 its Co-Authored-By trailers name (Get-P20ModelByCoAuthor), most
                 votes wins, a tie to the first seen in bullet then trailer
                 order; a name no row carries is ignored, a hash with no message
                 skipped
        label    not in the shipped order, read only where -Order names it:
                 -Label, the card's issue's worker label, trimmed: id $null,
                 family the label as written
        none     a person worked it alone: id and family $null

      An order that leaves none out still ends in it. -Messages is short hash ->
      message (ConvertFrom-P20GitMessages's answer; a longer key is cut to seven)
      or $null for not read; -Models the map (Get-P20ModelMap's answer, read once
      by the caller), $null for the shipped one. resolve_card_agent in the agent.
    #>
    param(
        [AllowEmptyString()][AllowNull()][string]$Content,
        [AllowEmptyString()][AllowNull()][string]$Label,
        $Messages,
        $Models,
        [string[]]$Order,
        # The map's `current` block (worker size -> model id). With -Models $null
        # it is read from the shipped map; with a -Models given and no -Current, empty.
        $Current
    )
    $c = Get-P20Consts
    if (-not $PSBoundParameters.ContainsKey('Order') -or $null -eq $Order) {
        $Order = @($c.models.agentSources | ForEach-Object { [string]$_ })
    }
    $map = ConvertTo-P20ModelMap $Models
    $curGiven = $Current
    if ($null -eq $curGiven -and $null -eq $Models) { $curGiven = Get-P20ModelCurrent }
    $cur = @{}
    if ($curGiven -is [System.Collections.IDictionary]) { foreach ($k in @($curGiven.Keys)) { $cur[[string]$k] = $curGiven[$k] } }
    elseif ($null -ne $curGiven) { foreach ($p in @($curGiven.PSObject.Properties)) { $cur[[string]$p.Name] = $p.Value } }
    foreach ($source in @($Order)) {
        if ($source -ceq 'line') {
            $id = Get-P20CardAgent -Content $Content
            if (-not $id) { continue }
            $family = $id
            foreach ($k in @($map.Keys)) {
                if ([string]$k -ceq $id) {
                    $f = $map[$k].family
                    if ($f) { $family = [string]$f }
                    break
                }
            }
            return [pscustomobject][ordered]@{ id = $id; family = $family; source = 'line' }
        }
        if ($source -ceq 'assigned') {
            # A size's model may later come from the map's own size lookup (Get-P20ModelForSize, models.current_model); the step stays here.
            if (Get-P20CardAgent -Content $Content) { continue }
            $size = Get-P20CardAssigned -Content $Content
            if (-not $size -or $size -ieq [string]$c.rituals.assignMe -or $size.StartsWith('@')) { continue }
            $id = $null
            # Matched ignoring case, as Get-P20ModelForSize matches a size.
            foreach ($k in @($cur.Keys)) { if ([string]$k -ieq $size) { $id = [string]$cur[$k]; break } }
            if (-not $id) { return [pscustomobject][ordered]@{ id = $null; family = $size; source = 'assigned' } }
            $family = $id
            foreach ($k in @($map.Keys)) {
                if ([string]$k -ceq $id) {
                    $f = $map[$k].family
                    if ($f) { $family = [string]$f }
                    break
                }
            }
            return [pscustomobject][ordered]@{ id = $id; family = $family; source = 'assigned' }
        }
        if ($source -ceq 'trailer') {
            if ($null -eq $Messages) { continue }
            $msgs = @{}
            $pairs = @()
            if ($Messages -is [System.Collections.IDictionary]) {
                foreach ($k in @($Messages.Keys)) { $pairs += , @([string]$k, $Messages[$k]) }
            } else {
                foreach ($p in @($Messages.PSObject.Properties)) { $pairs += , @([string]$p.Name, $p.Value) }
            }
            foreach ($pair in $pairs) {
                $key = $pair[0].Trim().ToLowerInvariant()
                if ($key.Length -gt 7) { $key = $key.Substring(0, 7) }
                if ($key -and -not $msgs.ContainsKey($key)) { $msgs[$key] = [string]$pair[1] }
            }
            $hashes = New-Object 'System.Collections.Generic.List[string]'
            foreach ($m in [regex]::Matches("$Content", [string]$c.regex.commitBullet)) {
                $key = $m.Groups[1].Value.ToLowerInvariant()
                if ($key.Length -gt 7) { $key = $key.Substring(0, 7) }
                if (-not $hashes.Contains($key)) { $hashes.Add($key) }
            }
            $votes = New-Object 'System.Collections.Generic.Dictionary[string,int]'
            $seen = New-Object 'System.Collections.Generic.List[string]'
            foreach ($h in $hashes) {
                if (-not $msgs.ContainsKey($h)) { continue }
                $named = New-Object 'System.Collections.Generic.List[string]'
                $names = Get-P20CommitCoAuthors -Message $msgs[$h]
                foreach ($name in $names) {
                    $mid = Get-P20ModelByCoAuthor -Name $name -Models $map
                    if ($mid -and -not $named.Contains($mid)) { $named.Add($mid) }
                }
                foreach ($mid in $named) {
                    if ($votes.ContainsKey($mid)) { $votes[$mid] = $votes[$mid] + 1 }
                    else { $votes[$mid] = 1; $seen.Add($mid) }
                }
            }
            if ($seen.Count -eq 0) { continue }
            $best = $seen[0]
            foreach ($mid in $seen) { if ($votes[$mid] -gt $votes[$best]) { $best = $mid } }
            $family = $best
            $f = $map[$best].family
            if ($f) { $family = [string]$f }
            return [pscustomobject][ordered]@{ id = $best; family = $family; source = 'trailer' }
        }
        if ($source -ceq 'label') {
            $l = "$Label".Trim()
            if (-not $l) { continue }
            return [pscustomobject][ordered]@{ id = $null; family = $l; source = 'label' }
        }
        if ($source -ceq 'none') { break }
    }
    return [pscustomobject][ordered]@{ id = $null; family = $null; source = 'none' }
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

function Test-P20CardMilestoneFromGitHub {
    <#
      Whether the title Get-P20CardMilestone reads is a GitHub issue's milestone
      rather than the card's own release. True only for a card with NO
      `**Milestone:**` line whose own ADO Link names a GitHub issue
      (Resolve-P20Tracker reads 'github') and whose `**Sprint:**` line names
      something: NewPrompt and StartWork copy the issue's milestone title onto
      that line. A `**Milestone:**` line is the card's own release, written by
      Plan, whatever the card is linked to. card_milestone_from_github in the
      agent; Tests/fixtures/parsers/card-milestone.json's github column.
    #>
    param([AllowEmptyString()][AllowNull()][string]$Content)
    $c = Get-P20Consts
    if ((Get-P20CardLineValue -Content $Content -Stamp ([string]$c.stamps.milestone)).Present) { return $false }
    if ((Resolve-P20Tracker -OrgUrl (Get-P20CardAdoUrl $Content)) -ne 'github') { return $false }
    return [bool](Get-P20CardLineValue -Content $Content -Stamp ([string]$c.stamps.sprint)).Value
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
