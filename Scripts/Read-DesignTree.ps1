#
# The ONE reader of a design tree in this half -- the four folders, a file's
# identity, and the state a design is in (L2; docs/hub/design.md, "The file" and
# "State -- derived, never stored").
#
# NOT a runnable verb: this file is DOT-SOURCED -- by Set-DesignStamp.ps1 (the
# stamping pass reads a file's id through it), by Get-OptionalSurfaces.ps1 (the
# "Design lifecycle" row counts unstamped files through it), by MoveDesign when
# it is built (L3: the verb refuses by the same state rule), and by
# Tests/Test-Design.ps1. The agent's agent/ado/design.py is the other
# implementation of the same rule, and Tests/fixtures/design/states.json holds
# the two to one table.
#
# THE RULE, in one sentence: a design is one id, a note and at most one spec,
# and its state is read from WHERE the files are -- never stored:
#
#   note in design/          spec none            Design
#   note in design/          spec in spec/        Spec
#   note in design/archive/  spec in spec/archive Complete
#   note in design/archive/  spec none            Archived
#   note in design/          spec in spec/archive Complete  (the spec's folder wins; mismatch)
#   note in design/archive/  spec in spec/        Spec      (the same, the other way round; mismatch)
#   note none                spec anywhere        Spec / Complete by the spec's folder
#
# Two stamps are facts and not states: `**Closed:**` on a file that entered an
# archive folder, and `**Outcome:** shipped|dropped` on a note archived WITHOUT
# a spec. Both are read from consts.json, never typed here.
#
# PowerShell 5.1 clean: no ternary, no null-coalescing, ASCII hyphens only.
#

if (-not (Get-Command Get-P20Consts -ErrorAction SilentlyContinue)) {
    . (Join-Path $PSScriptRoot 'Get-Consts.ps1')
}

function Get-P20FrontEnd {
    <#
      The index of the closing --- of a frontmatter block that opens on line 0,
      or -1 when the file has no (closed) block. Lines are split on LF with any
      CR trimmed, so both endings read the same.
    #>
    param([string[]]$Lines)
    if ($Lines.Count -lt 2 -or $Lines[0].TrimEnd("`r").Trim() -ne '---') { return -1 }
    for ($i = 1; $i -lt $Lines.Count; $i++) {
        if ($Lines[$i].TrimEnd("`r").Trim() -eq '---') { return $i }
    }
    return -1
}

function Get-P20FrontValue {
    <#
      One frontmatter key's value -- $null when the file has no block or the
      block has no such line. Quotes around the value are stripped, the way
      the agent's parse_doc strips them.
    #>
    param([string]$Text, [string]$Key)
    $lines = $Text -split "`n"
    $end = Get-P20FrontEnd -Lines $lines
    if ($end -lt 0) { return $null }
    $rx = '^' + [regex]::Escape($Key) + ':\s*(.*)$'
    for ($i = 1; $i -lt $end; $i++) {
        $m = [regex]::Match($lines[$i].TrimEnd("`r"), $rx)
        if ($m.Success) { return $m.Groups[1].Value.Trim().Trim('"').Trim("'") }
    }
    return $null
}

function Get-P20FileId {
    <#
      The id a file's frontmatter carries -- $null when it carries none. The
      key is the contract's (consts.json design.idKey).
    #>
    param([string]$Text)
    return (Get-P20FrontValue -Text $Text -Key ([string](Get-P20Consts).design.idKey))
}

function Get-P20DesignTitle {
    # The first `# ` heading after the frontmatter; the file's name when there is none.
    param([string]$Text, [string]$Name)
    $lines = $Text -split "`n"
    $start = (Get-P20FrontEnd -Lines $lines) + 1
    for ($i = $start; $i -lt $lines.Count; $i++) {
        $line = $lines[$i].TrimEnd("`r")
        if ($line.StartsWith('# ')) { return $line.Substring(2).Trim() }
    }
    return $Name
}

function Get-P20StampValue {
    # The text after a `**Stamp:**` line, '' when the file has none.
    param([string]$Text, [string]$Stamp)
    $m = [regex]::Match($Text, '(?m)^' + [regex]::Escape($Stamp) + '\s*(.*?)\s*$')
    if ($m.Success) { return $m.Groups[1].Value.Trim() }
    return ''
}

function Resolve-P20DesignState {
    <#
      The state rule over one design. -Note and -Spec say where each file is:
      'live' (design/ or spec/), 'archive' (the archive folder), or 'none'.
      -NoteText and -SpecText are the files' text, for the two stamps.

      Returns State, Outcome ('' unless an archived note without a spec says
      shipped or dropped), Mismatch (the two files disagree about where the
      design is -- the spec's folder wins), and Closed (the archived file's
      date: the spec's when the spec is archived, else the note's).
    #>
    param(
        [ValidateSet('live', 'archive', 'none')][string]$Note = 'none',
        [ValidateSet('live', 'archive', 'none')][string]$Spec = 'none',
        [string]$NoteText = '',
        [string]$SpecText = ''
    )
    $consts = Get-P20Consts
    $states = @($consts.design.states)     # Design, Spec, Complete, Archived
    $closedStamp = [string]$consts.stamps.closed
    $outcomeStamp = [string]$consts.stamps.outcome
    $outcomes = @($consts.design.outcomes)

    $state = $states[0]
    $mismatch = $false
    if ($Spec -eq 'archive') {
        $state = $states[2]
        if ($Note -eq 'live') { $mismatch = $true }
    }
    elseif ($Spec -eq 'live') {
        $state = $states[1]
        if ($Note -eq 'archive') { $mismatch = $true }
    }
    elseif ($Note -eq 'archive') {
        $state = $states[3]
    }

    $outcome = ''
    if ($state -eq $states[3]) {
        $word = (Get-P20StampValue -Text $NoteText -Stamp $outcomeStamp).ToLowerInvariant()
        if ($outcomes -contains $word) { $outcome = $word }
    }

    # Closed is a fact about a design that has REACHED an archive state: the
    # spec's date for Complete, the note's for Archived. A note archived before
    # its spec is still a Spec, and a Spec has no Closed date.
    $closed = ''
    if ($state -eq $states[2]) { $closed = Get-P20StampValue -Text $SpecText -Stamp $closedStamp }
    elseif ($state -eq $states[3]) { $closed = Get-P20StampValue -Text $NoteText -Stamp $closedStamp }
    if ($closed) {
        $m = [regex]::Match($closed, '^\d{4}-\d{2}-\d{2}')
        if ($m.Success) { $closed = $m.Value } else { $closed = '' }
    }

    return [PSCustomObject]@{
        State    = $state
        Outcome  = $outcome
        Mismatch = $mismatch
        Closed   = $closed
    }
}

function Read-P20DesignTree {
    <#
      One tree -- a design/ and a spec/ side by side, each with its archive/ --
      read into designs grouped by id, the files that are NOT shown (no id, or
      an id two notes or two specs share), and which of the two folders exist.

      Returns Structure (@{ design; spec }), Designs (one object per id, in
      road order then by title) and NotShown (@{ Path; Reason }). A file's
      Path is relative to -Base, forward slashes, when -Base is given.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'Base', Justification = 'Read inside the $rel scriptblock, which the rule does not follow.')]
    param(
        [Parameter(Mandatory = $true)][string]$DesignDir,
        [Parameter(Mandatory = $true)][string]$SpecDir,
        [string]$Base = ''
    )
    $consts = Get-P20Consts
    $archiveName = [string]$consts.folders.archive
    $states = @($consts.design.states)
    $threadRx = [regex]::new([string]$consts.studio.threadRegex)
    $docsRx = [regex]::new([string]$consts.design.docsRegex)

    $rel = {
        param([string]$Path)
        if (-not $Base) { return ($Path -replace '\\', '/') }
        $b = $Base.TrimEnd('\', '/')
        if ($Path.StartsWith($b, [System.StringComparison]::OrdinalIgnoreCase)) {
            return (($Path.Substring($b.Length).TrimStart('\', '/')) -replace '\\', '/')
        }
        return ($Path -replace '\\', '/')
    }

    $files = @()
    foreach ($spot in @(
            @{ Dir = $DesignDir; Kind = 'note'; Where = 'live' },
            @{ Dir = (Join-Path $DesignDir $archiveName); Kind = 'note'; Where = 'archive' },
            @{ Dir = $SpecDir; Kind = 'spec'; Where = 'live' },
            @{ Dir = (Join-Path $SpecDir $archiveName); Kind = 'spec'; Where = 'archive' })) {
        if (-not (Test-Path -LiteralPath $spot.Dir -PathType Container)) { continue }
        foreach ($f in @(Get-ChildItem -LiteralPath $spot.Dir -Filter '*.md' -File | Sort-Object Name)) {
            if ($f.Name -ieq 'README.md') { continue }
            $text = [System.IO.File]::ReadAllText($f.FullName)
            $files += [PSCustomObject]@{
                Path  = (& $rel $f.FullName)
                Full  = $f.FullName
                Name  = $f.Name
                Kind  = $spot.Kind
                Where = $spot.Where
                Text  = $text
                Id    = (Get-P20FileId -Text $text)
            }
        }
    }

    $notShown = @()
    $byId = [ordered]@{}
    foreach ($f in $files) {
        if (-not $f.Id) {
            $notShown += [PSCustomObject]@{ Path = $f.Path; Reason = 'no id' }
            continue
        }
        if (-not $byId.Contains($f.Id)) { $byId[$f.Id] = @() }
        $byId[$f.Id] += $f
    }

    $designs = @()
    foreach ($id in @($byId.Keys)) {
        $members = @($byId[$id])
        $notes = @($members | Where-Object { $_.Kind -eq 'note' })
        $specs = @($members | Where-Object { $_.Kind -eq 'spec' })
        $short = $id.Substring(0, [Math]::Min(8, $id.Length))
        $conflict = $false
        if ($notes.Count -gt 1) {
            $conflict = $true
            foreach ($n in $notes) { $notShown += [PSCustomObject]@{ Path = $n.Path; Reason = "$($notes.Count) notes carry the id $short" } }
        }
        if ($specs.Count -gt 1) {
            $conflict = $true
            foreach ($s in $specs) { $notShown += [PSCustomObject]@{ Path = $s.Path; Reason = "$($specs.Count) specs carry the id $short" } }
        }
        if ($conflict) { continue }

        $note = $null; $spec = $null
        if ($notes.Count -eq 1) { $note = $notes[0] }
        if ($specs.Count -eq 1) { $spec = $specs[0] }
        $noteWhere = 'none'; $specWhere = 'none'
        $noteText = ''; $specText = ''
        if ($note) { $noteWhere = $note.Where; $noteText = $note.Text }
        if ($spec) { $specWhere = $spec.Where; $specText = $spec.Text }
        $r = Resolve-P20DesignState -Note $noteWhere -Spec $specWhere -NoteText $noteText -SpecText $specText

        # The row's words come from the note when there is one (the design IS
        # the note; the spec is what it became), else from the spec.
        $lead = $note
        if (-not $lead) { $lead = $spec }
        $title = Get-P20DesignTitle -Text $lead.Text -Name $lead.Name
        $description = Get-P20FrontValue -Text $lead.Text -Key 'description'
        if ($null -eq $description) { $description = '' }
        $thread = ''
        foreach ($t in @($noteText, $specText)) {
            if ($thread) { break }
            $m = $threadRx.Match($t)
            if ($m.Success) { $thread = $m.Groups[1].Value }
        }
        $docs = ''
        if ($spec) {
            $m = $docsRx.Match($specText)
            if ($m.Success) { $docs = $m.Groups[1].Value }
        }

        $noteRow = $null; $specRow = $null
        if ($note) { $noteRow = [PSCustomObject]@{ Path = $note.Path; Name = $note.Name; Archived = ($note.Where -eq 'archive') } }
        if ($spec) { $specRow = [PSCustomObject]@{ Path = $spec.Path; Name = $spec.Name; Archived = ($spec.Where -eq 'archive') } }
        $designs += [PSCustomObject]@{
            Id          = $id
            Short       = $short
            State       = $r.State
            Outcome     = $r.Outcome
            Mismatch    = $r.Mismatch
            Closed      = $r.Closed
            Title       = $title
            Description = $description
            Thread      = $thread
            Docs        = $docs
            Note        = $noteRow
            Spec        = $specRow
        }
    }

    $order = @{}
    for ($i = 0; $i -lt $states.Count; $i++) { $order[[string]$states[$i]] = $i }
    $designs = @($designs | Sort-Object @{ Expression = { $order[[string]$_.State] } }, @{ Expression = { $_.Title.ToLowerInvariant() } })

    return [PSCustomObject]@{
        Structure = [PSCustomObject]@{
            design = [bool](Test-Path -LiteralPath $DesignDir -PathType Container)
            spec   = [bool](Test-Path -LiteralPath $SpecDir -PathType Container)
        }
        Designs  = $designs
        NotShown = @($notShown)
    }
}

function Get-P20DesignStem {
    # A design file's stem: board-ideas.md and board-ideas.spec.md are both 'board-ideas'.
    param([string]$FileName)
    $s = $FileName
    if ($s.ToLowerInvariant().EndsWith('.md')) { $s = $s.Substring(0, $s.Length - 3) }
    if ($s.ToLowerInvariant().EndsWith('.spec')) { $s = $s.Substring(0, $s.Length - 5) }
    return $s
}

function Select-P20Design {
    <#
      The designs a person meant by what they typed -- the ONE rule MoveDesign
      and NewPrompt -Design both ask (an id is accepted
      as any unique prefix of four or more). Something shaped like an id (four
      or more hex digits and hyphens) is matched as an id prefix first; else, or
      when no id starts with it, it is matched against each design's note and
      spec by file name and by stem, ignoring case. Returns every match: none
      and several are the caller's to refuse.
    #>
    param([object[]]$Designs = @(), [string]$Name)
    $wanted = "$Name".Trim()
    $wantedLower = $wanted.ToLowerInvariant()
    $found = @()
    if ($wantedLower -match '^[0-9a-f-]{4,}$') {
        $found = @($Designs | Where-Object { $_ -and $_.Id.ToLowerInvariant().StartsWith($wantedLower) })
    }
    if ($found.Count -eq 0) {
        $wantedStem = (Get-P20DesignStem -FileName $wanted).ToLowerInvariant()
        $found = @($Designs | Where-Object {
                $names = @()
                if ($_.Note) { $names += $_.Note.Name.ToLowerInvariant(); $names += (Get-P20DesignStem -FileName $_.Note.Name).ToLowerInvariant() }
                if ($_.Spec) { $names += $_.Spec.Name.ToLowerInvariant(); $names += (Get-P20DesignStem -FileName $_.Spec.Name).ToLowerInvariant() }
                ($names -contains $wantedLower) -or ($names -contains $wantedStem)
            })
    }
    return $found
}

# -- The design a CARD names (C3) ----------------------------------------
# A card carries one header line under its `> Template:` line naming the design
# it was worked against: `> Design: [<title>](<link>) <id>`, which NewPrompt
# -Design writes; and the corpus has a hand-written `> Spec: [<title>](<link>)
# <words>` on 16 cards, which is read as written and never rewritten. The token
# is consts.json tokens.design, the pattern design.cardLineRegex. The agent's
# card_design (agent/core/parsers.py) is the other reader, and the two are held
# to one table, Tests/fixtures/parsers/design-lines.json.

function Get-P20CardDesign {
    <#
      The design a card's text names, or $null: Kind (design or spec), Title,
      Link, Id (the design's id when the first word after the link is one, else
      '') and Note (the rest of those words). A card names ONE design: its first
      Design line, else its first Spec line. An empty line names nothing.
    #>
    param([AllowEmptyString()][string]$Text)
    $consts = Get-P20Consts
    $lineRx = [regex]::new([string]$consts.design.cardLineRegex)
    $idRx = [regex]::new([string]$consts.design.idRegex)
    $split = [regex]::new('[ \t]+')
    $found = @{}
    foreach ($m in $lineRx.Matches("$Text")) {
        $kind = $m.Groups[1].Value.ToLowerInvariant()
        if ($found.ContainsKey($kind)) { continue }
        $hasLink = ($m.Groups[2].Success -or $m.Groups[3].Success)
        $title = $m.Groups[2].Value.Trim()
        $link = $m.Groups[3].Value.Trim()
        $words = $m.Groups[4].Value.Trim()
        $parts = $split.Split($words, 2)
        $id = ''
        $note = $words
        if ($parts[0] -and $idRx.IsMatch($parts[0])) {
            $id = $parts[0]
            $note = ''
            if ($parts.Count -gt 1) { $note = $parts[1].Trim() }
        }
        if (-not $hasLink -and -not $id) { $title = $words; $note = '' }
        if (-not ($title -or $link -or $id -or $note)) { continue }
        $found[$kind] = [PSCustomObject]@{ Kind = $kind; Title = $title; Link = $link; Id = $id; Note = $note }
    }
    if ($found.ContainsKey('design')) { return $found['design'] }
    if ($found.ContainsKey('spec')) { return $found['spec'] }
    return $null
}

function New-P20DesignLine {
    <#
      The `> Design:` line NewPrompt -Design writes. The title is the design's
      own (its first heading); a square bracket in it would end the link, so it
      is written as a round one. The id is the design's whole id.
    #>
    param([string]$Title, [string]$Link, [string]$Id)
    $safe = ("$Title" -replace '\[', '(' -replace '\]', ')').Trim()
    return "$((Get-P20Consts).tokens.design) [$safe]($Link) $Id"
}
