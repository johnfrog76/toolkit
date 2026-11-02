<#
.SYNOPSIS
    A milestone's order: the one reader, and the line edits its one writer makes.
    Dot-source it.
.DESCRIPTION
    Not a command -- no alias, no menu row, no help entry of its own.

    A milestone's MEMBERSHIP is on each card, its **Milestone:** line. Its ORDER is
    one small file per milestone, `<Space>/milestones/<slug>.md` (consts.json
    folders.milestones; docs/hub/milestones.md):

        # M2 -- 1.2.0
        **Theme:** (not set)
        **Created:** YYYY-MM-DD

        ## Order

        - K7M2
        - 141 a note a person may keep after the id

    The line order IS the rank. Anything outside `## Order` is free text and is
    never rewritten.

    The reader, Get-P20MilestoneOrder, is a pure function over the file's text and
    the Space's open cards. The ranked list is the file's ids that a card carrying
    that **Milestone:** line still answers, in file order; then the members the
    file does not list, by **Created:** oldest first (unranked, never dropped). An
    id with no card, or whose card names another milestone, is skipped and counted
    as stale -- a reader never deletes it. agent/core/parsers.py milestone_order()
    is the same rule, and Tests/fixtures/parsers/milestone-order.json holds the two
    to one table.

    Edit-P20MilestoneOrderText is the text edit Plan makes -- add an id, remove
    it, move it. Plan (Scripts/Plan-Card.ps1) is the only caller: it is the one
    writer of a milestone's order.

.NOTES
    PowerShell 5.1 compatible (ASCII dashes only).
#>

if (-not (Get-Command Get-P20Consts -ErrorAction SilentlyContinue)) {
    . (Join-Path $PSScriptRoot 'Get-Consts.ps1')
}
if (-not (Get-Command Get-P20CardMilestone -ErrorAction SilentlyContinue)) {
    . (Join-Path $PSScriptRoot 'Get-PromptFileStatus.ps1')
}
if (-not (Get-Command Get-P20CardId -ErrorAction SilentlyContinue)) {
    . (Join-Path $PSScriptRoot 'Resolve-CardName.ps1')
}

function ConvertTo-P20MilestoneSlug {
    # The title slugged the way a card's slug is: lowercased, every run of anything
    # but a-z and 0-9 one hyphen, trimmed, at most 60 characters. 'M2 -- 1.2.0' is
    # 'm2-1-2-0'. agent/core/parsers.py milestone_slug(); the same table.
    param([AllowEmptyString()][AllowNull()][string]$Title)
    $slug = ("$Title".ToLowerInvariant() -replace '[^a-z0-9]+', '-').Trim('-')
    if ($slug.Length -gt 60) { $slug = $slug.Substring(0, 60).TrimEnd('-') }
    return $slug
}

function Split-P20MilestoneOrderLines {
    # The file as lines (LF and CRLF both read), the index of its `## Order` heading
    # (-1 for none), the end of that section (exclusive), and its bullets in file
    # order: @{ Index; Id }. A bullet's id is its first word.
    param([AllowEmptyString()][AllowNull()][string]$Text)
    $lines = New-Object System.Collections.Generic.List[string]
    if ("$Text" -ne '') {
        foreach ($l in ("$Text" -replace "`r`n", "`n").Split("`n")) { [void]$lines.Add($l) }
    }
    $start = -1
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match '^##[ \t]+Order[ \t]*$') { $start = $i; break }
    }
    $end = $lines.Count
    $bullets = @()
    if ($start -ge 0) {
        for ($i = $start + 1; $i -lt $lines.Count; $i++) {
            if ($lines[$i] -match '^#{1,6}[ \t]') { $end = $i; break }
            $m = [regex]::Match($lines[$i], '^[ \t]*[-*+][ \t]+(\S+)')
            if ($m.Success) { $bullets += @{ Index = $i; Id = $m.Groups[1].Value } }
        }
    }
    return @{ Lines = $lines; Start = $start; End = $end; Bullets = $bullets }
}

function Get-P20MilestoneOrderIds {
    # The ids in a milestone file's `## Order`, in file order, each once.
    param([AllowEmptyString()][AllowNull()][string]$Text)
    $seen = @{}
    $ids = @()
    foreach ($b in (Split-P20MilestoneOrderLines $Text).Bullets) {
        if ($seen.ContainsKey($b.Id)) { continue }
        $seen[$b.Id] = $true
        $ids += $b.Id
    }
    return , $ids
}

function Get-P20MilestoneTitle {
    # The title a milestone file names: its first `# ` heading, trimmed; '' for none.
    param([AllowEmptyString()][AllowNull()][string]$Text)
    $m = [regex]::Match("$Text", '(?m)^#[ \t]+([^\r\n]*?)[ \t]*\r?$')
    if ($m.Success) { return $m.Groups[1].Value }
    return ''
}

function Get-P20MilestoneOrder {
    <#
      The one reader. -Text is the milestone file ('' when there is none), -Title
      the milestone, -Cards the Space's open cards as @{ Id; Milestone; Created }.
      Returns @{ Ranked; Unranked; Stale }: the ranked ids in file order, the
      unranked members by Created (oldest first, a card with no date last, ties by
      id, ordinal), and how many of the file's ids answered no member.
    #>
    param(
        [AllowEmptyString()][AllowNull()][string]$Text,
        [AllowEmptyString()][string]$Title,
        [object[]]$Cards = @()
    )
    $members = @{}
    foreach ($card in @($Cards)) {
        if (-not $card) { continue }
        if ([string]$card.Milestone -ceq $Title -and $Title -ne '') { $members[[string]$card.Id] = $card }
    }
    $ranked = @()
    $stale = 0
    $placed = @{}
    foreach ($id in (Get-P20MilestoneOrderIds $Text)) {
        if ($members.ContainsKey($id)) { $ranked += $id; $placed[$id] = $true }
        else { $stale++ }
    }
    $rest = New-Object System.Collections.Generic.List[object]
    foreach ($id in $members.Keys) {
        if (-not $placed.ContainsKey($id)) { [void]$rest.Add($members[$id]) }
    }
    $rest.Sort([System.Comparison[object]] {
            param($a, $b)
            $ca = [string]$a.Created; $cb = [string]$b.Created
            if (($ca -eq '') -ne ($cb -eq '')) { if ($ca -eq '') { return 1 } else { return -1 } }
            $byDate = [string]::CompareOrdinal($ca, $cb)
            if ($byDate -ne 0) { return $byDate }
            return [string]::CompareOrdinal([string]$a.Id, [string]$b.Id)
        })
    $unranked = @($rest | ForEach-Object { [string]$_.Id })
    return @{ Ranked = $ranked; Unranked = $unranked; Stale = $stale }
}

function Get-P20MilestoneFolder {
    # A Space's milestones/ folder, beside current/, backlog/ and archive/.
    param([Parameter(Mandatory = $true)][string]$SpaceDir)
    return (Join-Path $SpaceDir ([string](Get-P20Consts).folders.milestones))
}

function Get-P20SpaceOpenCards {
    # The Space's open cards -- current/ and backlog/ -- as @{ Id; Milestone; Created; Name }.
    param(
        [Parameter(Mandatory = $true)][string]$SpaceDir,
        $WorkItemTypes = $null
    )
    $c = Get-P20Consts
    # The house prefixes (Task, US-, Feat-) from config, else the shipped ones.
    if ($null -eq $WorkItemTypes) { $WorkItemTypes = Get-P20WorkItemTypes -Config $global:P20Config }
    $pattern = Get-P20CardIdPattern -WorkItemTypes $WorkItemTypes
    $cards = @()
    foreach ($name in @([string]$c.folders.current, [string]$c.folders.backlog)) {
        $dir = Join-Path $SpaceDir $name
        if (-not (Test-Path -LiteralPath $dir)) { continue }
        foreach ($f in @(Get-ChildItem -LiteralPath $dir -File -Filter '*.md' -ErrorAction SilentlyContinue)) {
            $id = Get-P20CardId -Name $f.Name -Pattern $pattern
            if (-not $id) { continue }
            $text = [System.IO.File]::ReadAllText($f.FullName)
            $created = ''
            $cm = [regex]::Match((Get-P20CardLineValue -Content $text -Stamp ([string]$c.stamps.created)).Value, '^\d{4}-\d{2}-\d{2}')
            if ($cm.Success) { $created = $cm.Value }
            $cards += @{ Id = [string]$id; Milestone = (Get-P20CardMilestone $text); Created = $created; Name = $f.Name }
        }
    }
    return $cards
}

function Get-P20SpaceMilestoneOrders {
    <#
      Every milestone in a Space, read from disk: the titles its open cards name and
      the titles its milestone files carry, each as @{ Title; Slug; Path; Exists;
      Ranked; Unranked; Stale }. -TrackerKind 'ado' answers nothing: on an Azure
      DevOps Space the order is the board's, and ToolKit keeps none.
    #>
    param(
        [Parameter(Mandatory = $true)][string]$SpaceDir,
        $WorkItemTypes = $null,
        [string]$TrackerKind = '',
        [object[]]$Cards
    )
    if ($TrackerKind -eq 'ado') { return }
    if ($null -eq $Cards) { $Cards = @(Get-P20SpaceOpenCards -SpaceDir $SpaceDir -WorkItemTypes $WorkItemTypes) }
    $folder = Get-P20MilestoneFolder -SpaceDir $SpaceDir
    $titles = New-Object System.Collections.Generic.List[string]
    foreach ($card in @($Cards)) {
        $t = [string]$card.Milestone
        if ($t -and -not $titles.Contains($t)) { [void]$titles.Add($t) }
    }
    if (Test-Path -LiteralPath $folder) {
        foreach ($f in @(Get-ChildItem -LiteralPath $folder -File -Filter '*.md' | Sort-Object Name)) {
            $t = Get-P20MilestoneTitle ([System.IO.File]::ReadAllText($f.FullName))
            if ($t -and -not $titles.Contains($t)) { [void]$titles.Add($t) }
        }
    }
    $out = @()
    foreach ($t in $titles) {
        $slug = ConvertTo-P20MilestoneSlug $t
        $path = Join-Path $folder "$slug.md"
        $text = ''
        $exists = $false
        if ($slug -and (Test-Path -LiteralPath $path)) {
            $raw = [System.IO.File]::ReadAllText($path)
            # The file is this milestone's only when its heading names it.
            if ((Get-P20MilestoneTitle $raw) -ceq $t) { $text = $raw; $exists = $true }
        }
        $r = Get-P20MilestoneOrder -Text $text -Title $t -Cards $Cards
        $out += @{ Title = $t; Slug = $slug; Path = $path; Exists = $exists; Ranked = $r.Ranked; Unranked = $r.Unranked; Stale = $r.Stale }
    }
    return $out
}

function New-P20MilestoneOrderText {
    # A new milestone file: the title, a Theme placeholder a person fills in, the
    # day it was made, and an Order holding the one id.
    param([Parameter(Mandatory = $true)][string]$Title, [Parameter(Mandatory = $true)][string]$Id, [string]$Date)
    $c = Get-P20Consts
    if (-not $Date) { $Date = (Get-Date).ToString('yyyy-MM-dd') }
    return "# $Title`n`n**Theme:** (not set)`n$([string]$c.stamps.created) $Date`n`n## Order`n`n- $Id`n"
}

function Edit-P20MilestoneOrderText {
    <#
      The edit Plan makes to a milestone file's `## Order`, as text in, text out --
      the caller writes it, and an unchanged result is not written.

        -Action Add     the id's bullet at the bottom of the order, if it is not there
        -Action Remove  every bullet naming the id
        -Action Move    the id (added first if missing) to -To: top, up, down or a
                        1-based position, counted among -Live -- the ids a member
                        still answers -- so a stale line is never a step

      A bullet moves whole, its note with it. Lines outside `## Order` and the
      lines between bullets are never touched. The file keeps its own terminator.
    #>
    param(
        [AllowEmptyString()][string]$Text,
        [Parameter(Mandatory = $true)][string]$Id,
        [Parameter(Mandatory = $true)][ValidateSet('Add', 'Remove', 'Move')][string]$Action,
        [string]$To = '',
        [string[]]$Live = @()
    )
    $eol = "`n"
    if ($Text.Contains("`r`n")) { $eol = "`r`n" }
    # A file that ends with a terminator keeps ending with one (and a new one does).
    $trail = ($Text -eq '') -or $Text.EndsWith("`n")
    $body = $Text -replace "`r`n", "`n"
    if ($body.EndsWith("`n")) { $body = $body.Substring(0, $body.Length - 1) }
    $s = Split-P20MilestoneOrderLines $body
    $lines = $s.Lines
    $changed = $false

    if ($Action -eq 'Remove') {
        $drop = @($s.Bullets | Where-Object { $_.Id -ceq $Id } | ForEach-Object { $_.Index } | Sort-Object -Descending)
        foreach ($i in $drop) { $lines.RemoveAt($i); $changed = $true }
    }
    else {
        if (@($s.Bullets | Where-Object { $_.Id -ceq $Id }).Count -eq 0) {
            if ($s.Start -lt 0) {
                if ($lines.Count -gt 0 -and $lines[$lines.Count - 1] -ne '') { $lines.Add('') }
                $lines.Add('## Order'); $lines.Add(''); $lines.Add("- $Id")
            }
            else {
                $at = $s.Start + 1
                if ($s.Bullets.Count -gt 0) { $at = $s.Bullets[$s.Bullets.Count - 1].Index + 1 }
                elseif ($at -lt $lines.Count -and $lines[$at] -eq '') { $at++ }
                $lines.Insert($at, "- $Id")
            }
            $changed = $true
            # Re-read: the bullets' indexes moved.
            $s = Split-P20MilestoneOrderLines ($lines -join "`n")
            $lines = $s.Lines
        }
        if ($Action -eq 'Move') {
            # Positions are counted among the live ids, the id itself always one of them.
            $liveSet = @{}
            foreach ($l in @($Live)) { $liveSet[[string]$l] = $true }
            $liveSet[$Id] = $true
            $seen = @{}
            $order = @()
            foreach ($b in $s.Bullets) {
                if ($liveSet.ContainsKey($b.Id) -and -not $seen.ContainsKey($b.Id)) { $seen[$b.Id] = $true; $order += $b }
            }
            $k = 0
            for ($i = 0; $i -lt $order.Count; $i++) { if ($order[$i].Id -ceq $Id) { $k = $i; break } }
            $n = $order.Count
            $t = $k
            $want = "$To".Trim().ToLowerInvariant()
            if ($want -eq 'top') { $t = 0 }
            elseif ($want -eq 'up') { $t = [Math]::Max(0, $k - 1) }
            elseif ($want -eq 'down') { $t = [Math]::Min($n - 1, $k + 1) }
            elseif ($want -match '^\d+$') { $t = [Math]::Min($n, [Math]::Max(1, [int]$want)) - 1 }
            if ($t -ne $k) {
                $from = $order[$k].Index
                $moving = $lines[$from]
                $anchorIndex = $order[$t].Index
                $lines.RemoveAt($from)
                if ($anchorIndex -gt $from) { $anchorIndex-- }
                # Up the list: before the anchor. Down the list: after it.
                if ($t -lt $k) { $lines.Insert($anchorIndex, $moving) } else { $lines.Insert($anchorIndex + 1, $moving) }
                $changed = $true
            }
        }
    }
    if (-not $changed) { return $Text }
    $out = ($lines -join $eol)
    if ($trail) { $out += $eol }
    return $out
}
