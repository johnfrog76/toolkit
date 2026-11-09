<#
.SYNOPSIS
    The Backlog's rows: the one reader in the CLI's half. Dot-source it.
.DESCRIPTION
    Not a command -- no alias, no menu row, no help entry of its own. The verb is
    Backlog (Scripts/Get-Backlog.ps1); this is the rule it prints.

    A milestone is a group when a card in the Space's backlog/ names it, and every
    member of a group is a row in its place -- a card in current/ too, marked InPlay
    -- so the ranks read 1, 2, 3. A card in play with no milestone, or in a milestone
    with no waiting card, is no row. Groups go milestone by milestone: milestones with a file -- milestones/<slug>.md whose # heading names
    the title exactly -- by the file's **Created:** day (a file with none after the
    dated ones), ties by title; then milestones with no file, by title. Inside a
    milestone, its order's ranked ids, then its unranked ones (Get-P20MilestoneOrder).
    Then the backlog/ cards with no milestone: oldest **Created:** first, no date last, ties
    by id. Rank is the card's place among the ranked ids, 1-based -- the count
    Plan -Rank uses -- and empty when unranked. Age is the whole days since
    **Created:**, 0 for a future day, empty for none. -Milestone, -Tag and -Type
    filter, AND, ignoring case (-Type ignoring spaces too); a filtered row keeps
    its rank. docs/hub/milestones.md, "The Backlog: the order as a table".

    agent/core/parsers.py backlog_rows() is the same rule, and
    Tests/fixtures/parsers/backlog-order.json holds the two to one table.

.NOTES
    PowerShell 5.1 compatible (ASCII dashes only).
#>

if (-not (Get-Command Get-P20Consts -ErrorAction SilentlyContinue)) {
    . (Join-Path $PSScriptRoot 'Get-Consts.ps1')
}
if (-not (Get-Command Get-P20MilestoneOrder -ErrorAction SilentlyContinue)) {
    . (Join-Path $PSScriptRoot 'Get-MilestoneOrder.ps1')
}
if (-not (Get-Command Read-CardText -ErrorAction SilentlyContinue)) {
    . (Join-Path $PSScriptRoot 'Write-CardText.ps1')
}

function Get-P20CardHeading {
    # A card's # heading, whole and trimmed, a leading emoji dropped; '' for none.
    # agent/core/parsers.py card_heading(). The range is U+2600 to U+1FFFF: the BMP
    # part, or a surrogate pair whose high half is D800-D83F.
    param([AllowEmptyString()][AllowNull()][string]$Content)
    $m = [regex]::Match("$Content", '(?m)^#\s+(.+)')
    if (-not $m.Success) { return '' }
    return ($m.Groups[1].Value.Trim() -replace '^(?:[\u2600-\uD7FF\uE000-\uFFFF]|[\uD800-\uD83F][\uDC00-\uDFFF])\s*', '')
}

function Split-P20CardHeading {
    # 'Bug 141: Recipe search' -> @{ Type = 'Bug'; Name = 'Recipe search' }, against
    # the configured type names, longest first. A heading that names no known type
    # has none, and its whole text is its name. agent/core/parsers.py _split_heading.
    param([AllowEmptyString()][string]$Heading, [string[]]$TypeNames)
    $shape = [string](Get-P20Consts).regex.cardId
    foreach ($t in @($TypeNames | Where-Object { $_ } | Sort-Object -Property @{ Expression = { $_.Length }; Descending = $true })) {
        $m = [regex]::Match($Heading, '^(?i)' + [regex]::Escape($t) + '\s+(?:' + $shape + '|[A-Za-z0-9]+)\s*:\s*(.*)$')
        if ($m.Success) { return @{ Type = $t; Name = $m.Groups[1].Value.Trim() } }
    }
    return @{ Type = ''; Name = $Heading }
}

function Get-P20CardCreated {
    # The yyyy-MM-dd a card's (or a milestone file's) first **Created:** line starts
    # with; '' for none or a placeholder. agent/core/parsers.py card_created().
    param([AllowEmptyString()][AllowNull()][string]$Content)
    $value = (Get-P20CardLineValue -Content $Content -Stamp ([string](Get-P20Consts).stamps.created)).Value
    $m = [regex]::Match($value, '^\d{4}-\d{2}-\d{2}')
    if ($m.Success) { return $m.Value }
    return ''
}

function ConvertTo-P20BacklogCard {
    <#
      One open card as the Backlog reads it: @{ Id; Title; Type; Milestone; Tags;
      Created; Folder; File }, or $null for a file with no id. agent/core/parsers.py
      backlog_card().
    #>
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string]$Folder,
        [AllowEmptyString()][AllowNull()][string]$Content,
        [string[]]$TypeNames,
        [Parameter(Mandatory = $true)][string]$Pattern
    )
    $id = Get-P20CardId -Name $Name -Pattern $Pattern
    if (-not $id) { return $null }
    $heading = Get-P20CardHeading $Content
    $split = @{ Type = ''; Name = '' }
    if ($heading) { $split = Split-P20CardHeading -Heading $heading -TypeNames $TypeNames }
    return @{
        Id        = [string]$id
        Title     = [string]$split.Name
        Type      = [string]$split.Type
        Milestone = [string](Get-P20CardMilestone $Content)
        Tags      = @(Get-P20CardTags $Content)
        Created   = [string](Get-P20CardCreated $Content)
        Folder    = $Folder
        File      = $Name
    }
}

function Get-P20BacklogAge {
    # Whole days from Created to Today, 0 for a future day; $null for no date or an
    # impossible one.
    param([string]$Created, [string]$Today)
    if (-not $Created) { return $null }
    $inv = [System.Globalization.CultureInfo]::InvariantCulture
    $c = [datetime]::MinValue
    $t = [datetime]::MinValue
    if (-not [datetime]::TryParseExact($Created, 'yyyy-MM-dd', $inv, [System.Globalization.DateTimeStyles]::None, [ref]$c)) { return $null }
    if (-not [datetime]::TryParseExact($Today, 'yyyy-MM-dd', $inv, [System.Globalization.DateTimeStyles]::None, [ref]$t)) { return $null }
    return [int][Math]::Max(0, ($t - $c).Days)
}

function Get-P20BacklogRows {
    <#
      The rows. -Cards are the Space's open cards (ConvertTo-P20BacklogCard, from
      current/ and backlog/); -MilestoneFiles maps a file's name in milestones/ to its
      text; -Today is yyyy-MM-dd. Returns @{ Rank; Id; Title; Type; Milestone; Tags;
      Age; Created; File; InPlay } in order, Rank and Age $null when there is none.
    #>
    param(
        [object[]]$Cards = @(),
        [hashtable]$MilestoneFiles = @{},
        [Parameter(Mandatory = $true)][string]$Today,
        [string]$Milestone = '',
        [string]$Tag = '',
        [string]$Type = ''
    )
    $backlogName = [string](Get-P20Consts).folders.backlog
    $waiting = @($Cards | Where-Object { $_ -and [string]$_.Folder -eq $backlogName })
    # Every open card by id: a group's rows are its members, in play or waiting.
    $byId = @{}
    foreach ($c in @($Cards | Where-Object { $_ })) { $byId[[string]$c.Id] = $c }
    $titles = New-Object System.Collections.Generic.List[string]
    foreach ($c in $waiting) {
        $t = [string]$c.Milestone
        if ($t -and -not $titles.Contains($t)) { [void]$titles.Add($t) }
    }

    $groups = New-Object System.Collections.Generic.List[object]
    foreach ($t in $titles) {
        $file = "$(ConvertTo-P20MilestoneSlug $t).md"
        $text = ''
        $exists = $false
        if ($MilestoneFiles.ContainsKey($file) -and ((Get-P20MilestoneTitle ([string]$MilestoneFiles[$file])) -ceq $t)) {
            $text = [string]$MilestoneFiles[$file]
            $exists = $true
        }
        $created = ''
        if ($exists) { $created = Get-P20CardCreated $text }
        [void]$groups.Add(@{ Title = $t; Text = $text; Exists = $exists; Created = $created })
    }
    $groups.Sort([System.Comparison[object]] {
            param($a, $b)
            if ($a.Exists -ne $b.Exists) { if ($a.Exists) { return -1 } else { return 1 } }
            if ($a.Exists) {
                if (($a.Created -eq '') -ne ($b.Created -eq '')) { if ($a.Created -eq '') { return 1 } else { return -1 } }
                $byDate = [string]::CompareOrdinal($a.Created, $b.Created)
                if ($byDate -ne 0) { return $byDate }
            }
            return [string]::CompareOrdinal($a.Title, $b.Title)
        })

    $orderCards = @($Cards | Where-Object { $_ } | ForEach-Object { @{ Id = [string]$_.Id; Milestone = [string]$_.Milestone; Created = [string]$_.Created } })
    $rows = New-Object System.Collections.Generic.List[object]
    $add = {
        param($c, $rank)
        [void]$rows.Add(@{
                Rank      = $rank
                Id        = [string]$c.Id
                Title     = [string]$c.Title
                Type      = [string]$c.Type
                Milestone = [string]$c.Milestone
                Tags      = @($c.Tags)
                Age       = (Get-P20BacklogAge -Created ([string]$c.Created) -Today $Today)
                Created   = [string]$c.Created
                File      = [string]$c.File
                InPlay    = ([string]$c.Folder -ne $backlogName)
            })
    }
    foreach ($g in $groups) {
        $order = Get-P20MilestoneOrder -Text $g.Text -Title $g.Title -Cards $orderCards
        $ranked = @($order.Ranked)
        for ($i = 0; $i -lt $ranked.Count; $i++) {
            if ($byId.ContainsKey([string]$ranked[$i])) { & $add $byId[[string]$ranked[$i]] ($i + 1) }
        }
        foreach ($id in @($order.Unranked)) {
            if ($byId.ContainsKey([string]$id)) { & $add $byId[[string]$id] $null }
        }
    }
    $loose = New-Object System.Collections.Generic.List[object]
    foreach ($c in $waiting) { if (-not [string]$c.Milestone) { [void]$loose.Add($c) } }
    $loose.Sort([System.Comparison[object]] {
            param($a, $b)
            $ca = [string]$a.Created; $cb = [string]$b.Created
            if (($ca -eq '') -ne ($cb -eq '')) { if ($ca -eq '') { return 1 } else { return -1 } }
            $byDate = [string]::CompareOrdinal($ca, $cb)
            if ($byDate -ne 0) { return $byDate }
            return [string]::CompareOrdinal([string]$a.Id, [string]$b.Id)
        })
    foreach ($c in $loose) { & $add $c $null }

    $fold = { param([string]$v, [bool]$spaces) $v = "$v".ToLowerInvariant(); if ($spaces) { $v = $v -replace '\s+', '' }; $v }
    $out = $rows.ToArray()
    if ($Milestone) {
        $want = & $fold $Milestone $false
        $out = @($out | Where-Object { (& $fold $_.Milestone $false) -ceq $want })
    }
    if ($Tag) {
        $want = & $fold $Tag $false
        $out = @($out | Where-Object { @($_.Tags | Where-Object { (& $fold $_ $false) -ceq $want }).Count -gt 0 })
    }
    if ($Type) {
        $want = & $fold $Type $true
        $out = @($out | Where-Object { $_.Type -and (& $fold $_.Type $true) -ceq $want })
    }
    return , $out
}

function Read-P20SpaceBacklog {
    <#
      The rows for a Space, read from disk: current/ and backlog/ as cards (through
      Read-CardText, so a BOM-less UTF-8 card reads right on 5.1), milestones/ as
      files. Read-only.
    #>
    param(
        [Parameter(Mandatory = $true)][string]$SpaceDir,
        [Parameter(Mandatory = $true)][string]$Today,
        $WorkItemTypes = $null,
        [string]$Milestone = '',
        [string]$Tag = '',
        [string]$Type = ''
    )
    $c = Get-P20Consts
    if ($null -eq $WorkItemTypes) { $WorkItemTypes = Get-P20WorkItemTypes -Config $global:P20Config }
    $pattern = Get-P20CardIdPattern -WorkItemTypes $WorkItemTypes
    $typeNames = @($WorkItemTypes.Keys | ForEach-Object { [string]$_ })
    $cards = @()
    foreach ($name in @([string]$c.folders.current, [string]$c.folders.backlog)) {
        $dir = Join-Path $SpaceDir $name
        if (-not (Test-Path -LiteralPath $dir)) { continue }
        foreach ($f in @(Get-ChildItem -LiteralPath $dir -File -Filter '*.md' -ErrorAction SilentlyContinue | Sort-Object Name)) {
            $card = ConvertTo-P20BacklogCard -Name $f.Name -Folder $name -Content (Read-CardText -Path $f.FullName) -TypeNames $typeNames -Pattern $pattern
            if ($card) { $cards += $card }
        }
    }
    $files = @{}
    $folder = Get-P20MilestoneFolder -SpaceDir $SpaceDir
    if (Test-Path -LiteralPath $folder) {
        foreach ($f in @(Get-ChildItem -LiteralPath $folder -File -Filter '*.md' -ErrorAction SilentlyContinue)) {
            $files[$f.Name] = Read-CardText -Path $f.FullName
        }
    }
    $rows = Get-P20BacklogRows -Cards $cards -MilestoneFiles $files -Today $Today -Milestone $Milestone -Tag $Tag -Type $Type
    return , $rows
}
