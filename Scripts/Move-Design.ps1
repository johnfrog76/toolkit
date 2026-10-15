<#
.SYNOPSIS
    MoveDesign -- move a design along its road (the Studio, core).

.DESCRIPTION
    The design lifecycle's one verb (L3). A design is one id, a note and at
    most one spec, and its state is read from WHERE the files are
    (docs/hub/design.md, "State -- derived, never stored") -- so moving it is moving its
    files, and this is the one thing that does:

      -To Spec      scaffolds spec/<stem>.spec.md from templates/Spec.template.md
                    with the note's id, description and thread. The note stays.
      -To Archive   moves the note to design/archive/, stamps **Closed:** and
                    **Outcome:** shipped -- or dropped with -Dropped, which
                    needs -Reason: an idea that never made it is only worth
                    keeping with why.
      -To Complete  moves the spec to spec/archive/ and the note to
                    design/archive/ in one go, stamps **Closed:** on both and
                    writes `> Docs: <path>` into the spec. -Doc is the gate:
                    a spec is not complete until the durable part has a home.

    Every move appends one dated, self-contained line to the NOTE's `## Journey`
    (D-DL18): what date, what repository, what file path -- the path after the
    move included -- so the note tells its own story pasted into a phone.

    WHERE. By default the git root of the CURRENT directory, named on the
    first line of output, which must hold design/. In a repo it STAGES (git mv,
    git add) and never commits: a product's history is the engineer's. -Hub
    works on the hub's folders instead, and -Hub -Space <slug> on that Space's
    own design/ and spec/; in the hub it follows storeSync the way Archive does.
    Never both, never guessed.

    It never overwrites, in either folder. Edits go through Write-CardText (the
    file keeps its endings); the scaffolded spec is created with -New. -WhatIf
    prints every move and stamp and touches nothing. Every refusal is one
    sentence and exit 2 (AGENTS.md, "The refusal contract").

.PARAMETER Name
    The design: a note's or spec's file name (with or without .md), the stem
    both share, or its id -- any unique prefix of four or more characters.

.PARAMETER To
    Spec, Archive or Complete.

.PARAMETER Dropped
    With -To Archive: the idea never made it. Needs -Reason.

.PARAMETER Reason
    Appended to the journey line of any move; required with -Dropped.

.PARAMETER Doc
    With -To Complete: where the durable part landed, a path in the same tree.

.PARAMETER Hub
    Work on the hub's folders instead of the current repository.

.PARAMETER Space
    With -Hub: that declared Space's own design/ and spec/ inside the hub.

.PARAMETER WhatIf
    Print every move and stamp; write nothing.

.EXAMPLE
    {cliPrefix}MoveDesign board-ideas -To Spec
.EXAMPLE
    {cliPrefix}MoveDesign a-second-room -To Archive -Dropped -Reason "The Lounge already does this."
.EXAMPLE
    {cliPrefix}MoveDesign ee925272 -To Complete -Doc docs/hub/design.md
.EXAMPLE
    {cliPrefix}MoveDesign board-ideas -To Archive -Hub -WhatIf

.NOTES
    PowerShell 5.1 compatible (ASCII dashes only).
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $false, Position = 0)]
    [string]$Name,
    [Parameter(Mandatory = $false)]
    [ValidateSet('Spec', 'Archive', 'Complete', '')]
    [string]$To = '',
    [Parameter(Mandatory = $false)]
    [switch]$Dropped,
    [Parameter(Mandatory = $false)]
    [string]$Reason = '',
    [Parameter(Mandatory = $false)]
    [string]$Doc = '',
    [Parameter(Mandatory = $false)]
    [switch]$Hub,
    [Parameter(Mandatory = $false)]
    [string]$Space = '',
    [Parameter(Mandatory = $false)]
    [switch]$WhatIf,
    [Parameter(Mandatory = $false)]
    [switch]$Help
)

$repoRoot = Split-Path -Parent $PSScriptRoot

if (-not (Get-Command Get-CliPrefix -ErrorAction SilentlyContinue)) {
    function Get-CliPrefix {
        if ($global:P20Config -and $global:P20Config.CommandPrefix) { return $global:P20Config.CommandPrefix }
        return ''
    }
}
# Write-CliError normally comes from the module; it is what makes a refusal ONE
# block. See AGENTS.md, "The refusal contract".
if (-not (Get-Command Write-CliError -ErrorAction SilentlyContinue)) {
    function Write-CliError {
        param([string]$Message, [string]$Hint)
        $global:P20StatedError = $Message
        Write-Host "Error: $Message" -ForegroundColor Red
        if ($Hint) { Write-Host "Hint:  $Hint" -ForegroundColor Yellow }
    }
}

if ($Help) {
    $p = Get-CliPrefix
    Write-Host ""
    Write-Host "  ${p}MoveDesign -- move a design along its road" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  Usage:" -ForegroundColor Yellow
    Write-Host "    ${p}MoveDesign <name|id> -To Spec|Archive|Complete [-Dropped] [-Reason <text>] [-Doc <path>] [-Hub] [-Space <slug>] [-WhatIf]"
    Write-Host ""
    Write-Host "  Spec scaffolds the spec beside the note; Archive moves the note to design/archive/ (shipped,"
    Write-Host "  or dropped with -Dropped -Reason); Complete archives the spec and the note together and"
    Write-Host "  needs -Doc <path>. Every move writes one line into the note's ## Journey. In a repo it"
    Write-Host "  stages and never commits; -Hub works on the hub's folders and follows storeSync."
    Write-Host ""
    return
}

. (Join-Path $PSScriptRoot 'Resolve-HubConfig.ps1')
. (Join-Path $PSScriptRoot 'Write-CardText.ps1')
. (Join-Path $PSScriptRoot 'Add-ClosedStamp.ps1')
. (Join-Path $PSScriptRoot 'Read-DesignTree.ps1')
$consts = Get-P20Consts
$states = @($consts.design.states)          # Design, Spec, Complete, Archived
$stateDesign = [string]$states[0]; $stateSpec = [string]$states[1]; $stateComplete = [string]$states[2]
$outcomes = @($consts.design.outcomes)       # shipped, dropped
$archiveName = [string]$consts.folders.archive
$outcomeStamp = [string]$consts.stamps.outcome
$createdStamp = [string]$consts.stamps.created
$docsLine = [string]$consts.design.docsLine
$threadLineWord = [string]$consts.studio.threadLine
$prefix = Get-CliPrefix

# -- What was asked ------------------------------------------------------------------
if ([string]::IsNullOrWhiteSpace($Name)) {
    Write-CliError -Message 'MoveDesign needs the design to move: a note or spec name, the stem, or its id.' `
        -Hint "${prefix}MoveDesign <name|id> -To Spec|Archive|Complete"
    exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
}
if (-not $To) {
    Write-CliError -Message 'MoveDesign needs -To: Spec, Archive or Complete.' `
        -Hint "${prefix}MoveDesign $Name -To Spec"
    exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
}
if ($Dropped -and $To -ne 'Archive') {
    Write-CliError -Message '-Dropped belongs to -To Archive: an idea that never made it is archived, not graduated or completed.'
    exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
}
if ($Dropped -and [string]::IsNullOrWhiteSpace($Reason)) {
    Write-CliError -Message 'A dropped idea is only worth keeping with why: -Dropped needs -Reason <text>.' `
        -Hint "${prefix}MoveDesign $Name -To Archive -Dropped -Reason `"...`""
    exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
}
if ($Space -and -not $Hub) {
    Write-CliError -Message '-Space is the hub''s: it names a Space folder inside the hub, so it goes with -Hub.' `
        -Hint "${prefix}MoveDesign $Name -To $To -Hub -Space $Space"
    exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
}

# -- Where: the repository we stand in, or the hub -----------------------------------
$base = ''; $designDir = ''; $specDir = ''; $where = ''; $repoName = ''; $inRepo = $false
if ($Hub) {
    $promptsRoot = Get-P20PromptsRoot -PackageRoot $repoRoot
    if (-not (Test-P20HubRoot $promptsRoot)) {
        Write-CliError -Message (Get-P20HubMissingMessage $promptsRoot)
        exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
    }
    $promptsRoot = ConvertTo-P20LongPath -Path (Resolve-Path -LiteralPath $promptsRoot).Path
    Write-Host "Hub: $promptsRoot"
    $base = $promptsRoot
    $where = 'the hub'
    $repoName = 'the hub'
    if ($Space) {
        $declared = @()
        if ($global:P20Config -and $global:P20Config.Spaces) { $declared = @($global:P20Config.Spaces) }
        $match = $declared | Where-Object { [string]$_.slug -eq $Space } | Select-Object -First 1
        if (-not $match) {
            Write-CliError -Message "No Space '$Space' is declared, so the hub has no folder of its own for it." `
                -Hint "${prefix}Env lists the Spaces; -Hub without -Space works on the hub's root design/ and spec/."
            exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
        }
        $folder = [string]$match.promptsFolder
        if (-not $folder) { $folder = [string]$match.slug }
        $base = Join-Path $promptsRoot $folder
        $designDir = Join-Path $base 'design'
        $specDir = Join-Path $base 'spec'
        $where = "the hub's $folder/"
        $repoName = "the hub ($folder)"
    }
    else {
        $designDir = Get-P20HubFolder -Name 'design' -PromptsRoot $promptsRoot -PackageRoot $repoRoot
        $specDir = Get-P20HubFolder -Name 'spec' -PromptsRoot $promptsRoot -PackageRoot $repoRoot
    }
}
else {
    $top = ''
    try { $top = "$(git rev-parse --show-toplevel 2>$null)".Trim() } catch { $top = '' }
    if (-not $top) {
        Write-CliError -Message "$((Get-Location).Path) is not inside a git repository." `
            -Hint "Run it from the repository whose design/ holds the design, or use -Hub for the hub's."
        exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
    }
    $top = ConvertTo-P20LongPath -Path (Resolve-Path -LiteralPath $top).Path
    Write-Host "Git root: $top"
    if (-not (Test-Path -LiteralPath (Join-Path $top 'design') -PathType Container)) {
        Write-CliError -Message "$top has no design/ folder." `
            -Hint "A product keeps its designs in design/ with spec/ beside it; use -Hub for the hub's."
        exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
    }
    $base = $top; $inRepo = $true
    $designDir = Join-Path $top 'design'
    $specDir = Join-Path $top 'spec'
    $where = 'this repository'
    # The name a journey line calls this repository by: owner/repo from the
    # origin remote when there is one, else the folder's name.
    $repoName = Split-Path -Leaf $top
    try {
        $origin = "$(git remote get-url origin 2>$null)".Trim()
        $m = [regex]::Match($origin, '[:/]([^/:]+)/([^/]+?)(?:\.git)?/?$')
        if ($m.Success) { $repoName = "$($m.Groups[1].Value)/$($m.Groups[2].Value)" }
    } catch { $null = $_ }
}

# -- The design --------------------------------------------------------------------
$tree = Read-P20DesignTree -DesignDir $designDir -SpecDir $specDir -Base $base
$designs = @($tree.Designs)
$wanted = $Name.Trim()
$wantedLower = $wanted.ToLowerInvariant()
$stemOf = {
    param([string]$FileName)
    $s = $FileName
    if ($s.ToLowerInvariant().EndsWith('.md')) { $s = $s.Substring(0, $s.Length - 3) }
    if ($s.ToLowerInvariant().EndsWith('.spec')) { $s = $s.Substring(0, $s.Length - 5) }
    return $s
}
# The one rule for what a person meant (Read-DesignTree.ps1), shared with NewPrompt -Design.
$found = @(Select-P20Design -Designs $designs -Name $wanted)
if ($found.Count -gt 1) {
    $list = ($found | ForEach-Object { "$($_.Short) $($_.Title)" }) -join '; '
    Write-CliError -Message "'$Name' names $($found.Count) designs in ${where}: $list." `
        -Hint 'Give more of the id, or the file name.'
    exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
}
if ($found.Count -eq 0) {
    $unshown = @($tree.NotShown | Where-Object {
        $leaf = Split-Path -Leaf $_.Path
        ($leaf.ToLowerInvariant() -eq $wantedLower) -or ((& $stemOf $leaf).ToLowerInvariant() -eq (& $stemOf $wanted).ToLowerInvariant())
    })
    if ($unshown.Count -gt 0) {
        $u = $unshown[0]
        if ($u.Reason -eq 'no id') {
            Write-CliError -Message "$($u.Path) is not a design yet: it carries no id." `
                -Hint "${prefix}StampDesign$(if ($Hub) { ' -Hub' }) gives it one; then move it."
        }
        else {
            Write-CliError -Message "$($u.Path) is not shown as a design: $($u.Reason)." `
                -Hint 'Give one of the files a fresh id, then move it.'
        }
        exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
    }
    Write-CliError -Message "No design named '$Name' in $where." `
        -Hint "A design is a note in design/ or a spec in spec/ (or their archives); name its file, its stem, or its id."
    exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
}
$design = $found[0]
$title = $design.Title
$note = $design.Note
$spec = $design.Spec
$today = Get-Date -Format 'yyyy-MM-dd'

$rel = { param([string]$Path) return ($Path -replace '\\', '/') }
$full = { param([string]$RelPath) return (Join-Path $base ($RelPath -replace '/', [IO.Path]::DirectorySeparatorChar)) }
$reasonTail = ''
if (-not [string]::IsNullOrWhiteSpace($Reason)) {
    $reasonTail = ' ' + $Reason.Trim()
    if (-not $reasonTail.EndsWith('.')) { $reasonTail += '.' }
}

# -- The journey: one dated, self-contained line per move (D-DL18) -----------------
function Add-P20JourneyLine {
    param([string]$Path, [string]$NoteRel, [string]$Line, [string]$Thread)
    $raw = [System.IO.File]::ReadAllText($Path)
    $text = $raw -replace "`r`n", "`n"
    if ($text.Length -gt 0 -and $text[0] -eq [char]0xFEFF) { $text = $text.Substring(1) }
    $lines = [System.Collections.Generic.List[string]]::new()
    foreach ($l in ($text -split "`n")) { $lines.Add($l) }
    # Trailing empty element from a final newline: keep the file's shape.
    $heading = -1
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match '^##\s+Journey\s*$') { $heading = $i; break }
    }
    if ($heading -lt 0) {
        # The first line is the design's birth, dated from **Created:** when the
        # note has one -- added by the first move, so a note tells the whole road.
        $created = $today
        $cm = [regex]::Match($text, '(?m)^' + [regex]::Escape($createdStamp) + '\s*(\d{4}-\d{2}-\d{2})')
        if ($cm.Success) { $created = $cm.Groups[1].Value }
        $first = "- $created $stateDesign`: written as $NoteRel in $repoName."
        if ($Thread) { $first += " Thread: $Thread" }
        $section = @('## Journey', '', $first, $Line, '')
        # Above the note's footer: its **Created:** line, or -- a note that never
        # had one -- the first stamp the move itself wrote (**Closed:**, **Outcome:**).
        $at = -1
        $footer = @($createdStamp, [string]$consts.stamps.closed, $outcomeStamp)
        for ($i = 0; $i -lt $lines.Count; $i++) {
            $hit = $false
            foreach ($f in $footer) { if ($lines[$i].StartsWith($f)) { $hit = $true } }
            if ($hit) { $at = $i; break }
        }
        if ($at -ge 0) {
            if ($at -gt 0 -and $lines[$at - 1].Trim() -ne '') { $section = @('') + $section }
            $lines.InsertRange($at, [string[]]$section)
        }
        else {
            while ($lines.Count -gt 0 -and $lines[$lines.Count - 1].Trim() -eq '') { $lines.RemoveAt($lines.Count - 1) }
            $lines.AddRange([string[]](@('') + $section[0..($section.Count - 2)]))
            $lines.Add('')
        }
    }
    else {
        # Append after the section's last bullet, before the next heading.
        $last = $heading
        for ($i = $heading + 1; $i -lt $lines.Count; $i++) {
            if ($lines[$i] -match '^##\s') { break }
            if ($lines[$i] -match '^\s*-\s') { $last = $i }
        }
        if ($last -eq $heading) {
            $lines.InsertRange($heading + 1, [string[]]@('', $Line))
        }
        else {
            $lines.Insert($last + 1, $Line)
        }
    }
    Write-CardText -Path $Path -Content ($lines -join "`n")
}

function Add-P20OutcomeLine {
    param([string]$Path, [string]$Word)
    $content = [System.IO.File]::ReadAllText($Path)
    if ($content -match ('(?m)^' + [regex]::Escape($outcomeStamp))) { return }
    $eol = "`n"
    if ($content -match "`r`n") { $eol = "`r`n" }
    if ($content -and -not $content.EndsWith("`n")) { $content += $eol }
    $content += "$outcomeStamp $Word$eol"
    Write-CardText -Path $Path -Content $content
}

function Add-P20DocsLine {
    # `> Docs: <path>` under the spec's title, a blank line either side -- the
    # place the thread line sits; left alone when the spec already has one.
    param([string]$Path, [string]$DocPath)
    $current = ([System.IO.File]::ReadAllText($Path)) -replace "`r`n", "`n"
    if ($current -match ('(?m)^' + [regex]::Escape($docsLine))) { return }
    $lines = [System.Collections.Generic.List[string]]::new()
    foreach ($l in ($current -split "`n")) { $lines.Add($l) }
    $at = -1
    $inFront = ($lines.Count -gt 0 -and $lines[0].Trim() -eq '---')
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($inFront) { if ($i -gt 0 -and $lines[$i].Trim() -eq '---') { $inFront = $false }; continue }
        if ($lines[$i] -match '^# ') { $at = $i; break }
    }
    $insert = @('', "$docsLine $DocPath")
    if ($at + 1 -lt $lines.Count -and $lines[$at + 1].Trim() -ne '') { $insert += '' }
    $lines.InsertRange($at + 1, [string[]]$insert)
    Write-CardText -Path $Path -Content ($lines -join "`n")
}

function Add-P20BlankBeforeStamp {
    # A spec ends in prose, so the **Closed:** stamp a completion appends wants a
    # blank line before it. A file whose last line is already a stamp
    # (a note's footer) is left alone: the stamps stack, as they do on a card.
    param([string]$Path)
    $current = [System.IO.File]::ReadAllText($Path)
    $eol = "`n"
    if ($current -match "`r`n") { $eol = "`r`n" }
    $trimmed = $current.TrimEnd("`r", "`n")
    if ($trimmed -eq '') { return }
    $last = ($trimmed -split "`n")[-1].Trim()
    if ($last.StartsWith('**')) { return }
    if ($current.EndsWith($eol + $eol)) { return }
    Write-CardText -Path $Path -Content ($trimmed + $eol + $eol)
}

# -- Staging: a repo stages and never commits; the hub follows storeSync -----------
$staged = @()
function Move-P20DesignFile {
    param([string]$FromRel, [string]$ToRel)
    $from = & $full $FromRel
    $to = & $full $ToRel
    $toDir = Split-Path -Parent $to
    if (-not (Test-Path -LiteralPath $toDir -PathType Container)) { New-Item -ItemType Directory -Path $toDir -Force | Out-Null }
    $tracked = $false
    if ($inRepo) {
        Push-Location $base
        try { git ls-files --error-unmatch -- $FromRel 2>$null | Out-Null; $tracked = ($LASTEXITCODE -eq 0) }
        finally { Pop-Location }
    }
    if ($tracked) {
        Push-Location $base
        try { git mv -- $FromRel $ToRel 2>&1 | Out-Null } finally { Pop-Location }
        if (-not (Test-Path -LiteralPath $to)) { Move-Item -LiteralPath $from -Destination $to }
    }
    else {
        Move-Item -LiteralPath $from -Destination $to
    }
    $script:staged += $FromRel
    $script:staged += $ToRel
}

function Complete-P20Staging {
    param([string]$Summary)
    $paths = @($staged | Select-Object -Unique)
    if ($inRepo) {
        Push-Location $base
        try { foreach ($p in $paths) { git add -A -- $p 2>&1 | Out-Null } } finally { Pop-Location }
        Write-Host "Staged, not committed. Suggested:" -ForegroundColor DarkGray
        Write-Host "  git commit -m `"design: $Summary`"" -ForegroundColor DarkGray
        return
    }
    $storeSync = 'none'
    if ($global:P20Config -and $global:P20Config.StoreSync) { $storeSync = [string]$global:P20Config.StoreSync }
    if ($storeSync -ne 'git') {
        Write-Host "Moved. Store is not git (storeSync='$storeSync') -- nothing committed." -ForegroundColor DarkGray
        return
    }
    Push-Location $promptsRoot
    try {
        foreach ($p in $paths) {
            $abs = & $full $p
            $hubRel = $abs.Substring($promptsRoot.TrimEnd('\', '/').Length).TrimStart('\', '/') -replace '\\', '/'
            git add -A -- $hubRel 2>&1 | Out-Null
        }
        git commit -m "design: $Summary" 2>&1 | ForEach-Object { Write-Host $_ }
        if ($LASTEXITCODE -ne 0) { Write-Warning 'Commit failed. Files have been moved but not committed.' }
        else { Write-Host 'Committed.' -ForegroundColor Green }
    }
    finally { Pop-Location }
}

# One voice for what the verb does and what it would do: `Would move ...`
# under -WhatIf, `Move ...` when it is real.
function Say {
    param([string]$Verb, [string]$Rest)
    if ($WhatIf) { Write-Host "Would $Verb $Rest" }
    else { Write-Host ($Verb.Substring(0, 1).ToUpperInvariant() + $Verb.Substring(1) + ' ' + $Rest) }
}

# -- The move ------------------------------------------------------------------------
switch ($To) {
    'Spec' {
        if (-not $note) {
            Write-CliError -Message "'$title' ($($design.Short)) has no note to graduate: it is a spec standing alone."
            exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
        }
        if ($spec) {
            Write-CliError -Message "'$title' already carries its id in $($spec.Path): it is $($design.State)."
            exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
        }
        if ($note.Archived) {
            Write-CliError -Message "'$title' is $($design.State): a note in design/$archiveName/ does not graduate." `
                -Hint 'Move it back into design/ by hand first, if it is alive again.'
            exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
        }
        $stem = & $stemOf $note.Name
        $specRel = "$(& $rel ((Split-Path -Leaf $specDir)))/$stem.spec.md"
        $specPath = & $full $specRel
        if (Test-Path -LiteralPath $specPath) {
            Write-CliError -Message "$specRel already exists. Not overwriting it." `
                -Hint 'Give it the note''s id by hand if it is the spec, or move it aside.'
            exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
        }
        $templatePath = Join-Path (Join-Path $repoRoot 'templates') 'Spec.template.md'
        if (-not (Test-Path -LiteralPath $templatePath)) {
            Write-CliError -Message "The spec template is missing: $templatePath" -Hint 'The package is incomplete; update or re-clone it.'
            exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
        }
        $text = Get-Content -LiteralPath $templatePath -Raw -Encoding UTF8
        $desc = ([string]$design.Description).Replace('"', "'")
        # The thread line sits under the title with a blank line either side, the
        # place the note carries it; with no thread the slot goes, blank line and all.
        $text = $text -replace "`r`n", "`n"
        if ($design.Thread) { $text = $text.Replace("{THREAD}`n", "$threadLineWord $($design.Thread)`n") }
        else { $text = $text.Replace("{THREAD}`n`n", '').Replace("{THREAD}`n", '') }
        $text = $text.Replace('{ID}', $design.Id).Replace('{DESCRIPTION}', $desc).Replace('{TITLE}', $title)
        $line = "- $today $stateSpec`: became $specRel in $repoName.$reasonTail"
        Say 'scaffold' "$specRel from templates/Spec.template.md ($($design.Short))"
        Say 'append' "to $($note.Path): $line"
        if (-not $WhatIf) {
            # The spec folder appears with the first graduation, made here the way
            # Move-P20DesignFile makes an archive folder.
            $specDirNow = Split-Path -Parent $specPath
            if (-not (Test-Path -LiteralPath $specDirNow -PathType Container)) { New-Item -ItemType Directory -Path $specDirNow -Force | Out-Null }
            Write-CardText -Path $specPath -Content $text -New
            Add-P20JourneyLine -Path (& $full $note.Path) -NoteRel $note.Path -Line $line -Thread $design.Thread
            $staged += $specRel; $staged += $note.Path
            Complete-P20Staging -Summary "$title graduates to $specRel"
        }
    }
    'Archive' {
        if (-not $note) {
            Write-CliError -Message "'$title' ($($design.Short)) has no note to archive: it is a spec standing alone." `
                -Hint '-To Complete archives a spec, with -Doc <path>.'
            exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
        }
        if ($note.Archived) {
            Write-CliError -Message "'$title' is already in $($note.Path)."
            exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
        }
        if ($spec -and -not $spec.Archived) {
            Write-CliError -Message "'$title' is $stateSpec`: its spec $($spec.Path) is live, so the note does not archive alone." `
                -Hint "${prefix}MoveDesign $Name -To Complete -Doc <path> archives both."
            exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
        }
        $destRel = "$(& $rel ((Split-Path -Leaf $designDir)))/$archiveName/$($note.Name)"
        if (Test-Path -LiteralPath (& $full $destRel)) {
            Write-CliError -Message "$destRel already exists. Not overwriting it."
            exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
        }
        $word = [string]$outcomes[0]
        if ($Dropped) { $word = [string]$outcomes[1] }
        $label = $word.Substring(0, 1).ToUpperInvariant() + $word.Substring(1)
        if ($Dropped) { $line = "- $today $label`:$reasonTail This note is now $destRel in $repoName." }
        else { $line = "- $today $label`: shipped as written.$reasonTail This note is now $destRel in $repoName." }
        Say 'move' "$($note.Path) -> $destRel"
        Say 'stamp' "$destRel with $($consts.stamps.closed) $today and $outcomeStamp $word"
        Say 'append' "to $destRel`: $line"
        if (-not $WhatIf) {
            Move-P20DesignFile -FromRel $note.Path -ToRel $destRel
            $dest = & $full $destRel
            Add-ClosedDate -Path $dest
            Add-P20OutcomeLine -Path $dest -Word $word
            Add-P20JourneyLine -Path $dest -NoteRel $note.Path -Line $line -Thread $design.Thread
            Complete-P20Staging -Summary "$title archived ($word)"
        }
    }
    'Complete' {
        if (-not $spec -or $spec.Archived -or $design.State -ne $stateSpec) {
            Write-CliError -Message "'$title' is $($design.State), not $stateSpec`: only a design whose spec is live completes." `
                -Hint 'A note alone archives with -To Archive; a Complete design is already in both archives.'
            exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
        }
        if ([string]::IsNullOrWhiteSpace($Doc)) {
            Write-CliError -Message "'$title' is not complete until its durable part has a home: -Doc <path> names the document it landed in." `
                -Hint "${prefix}MoveDesign $Name -To Complete -Doc docs/<file>.md"
            exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
        }
        $docRel = (& $rel $Doc.Trim()).TrimStart('/')
        if (-not (Test-Path -LiteralPath (& $full $docRel) -PathType Leaf)) {
            Write-CliError -Message "-Doc $docRel does not exist in $where." `
                -Hint 'The docs land first; the spec completes after.'
            exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
        }
        $specDest = "$(& $rel ((Split-Path -Leaf $specDir)))/$archiveName/$($spec.Name)"
        if (Test-Path -LiteralPath (& $full $specDest)) {
            Write-CliError -Message "$specDest already exists. Not overwriting it."
            exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
        }
        $noteDest = ''
        if ($note -and -not $note.Archived) {
            $noteDest = "$(& $rel ((Split-Path -Leaf $designDir)))/$archiveName/$($note.Name)"
            if (Test-Path -LiteralPath (& $full $noteDest)) {
                Write-CliError -Message "$noteDest already exists. Not overwriting it."
                exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
            }
        }
        $notePathAfter = ''
        if ($noteDest) { $notePathAfter = $noteDest } elseif ($note) { $notePathAfter = $note.Path }
        $line = "- $today $stateComplete`: built. The docs are $docRel.$reasonTail"
        if ($notePathAfter) { $line += " This note is now $notePathAfter and the spec is $specDest, in $repoName." }
        else { $line += " The spec is now $specDest in $repoName." }
        Say 'move' "$($spec.Path) -> $specDest"
        if ($noteDest) { Say 'move' "$($note.Path) -> $noteDest" }
        Say 'write' "'$docsLine $docRel' into $specDest and stamp both with $($consts.stamps.closed) $today"
        if ($notePathAfter) { Say 'append' "to $notePathAfter`: $line" }
        if (-not $WhatIf) {
            Move-P20DesignFile -FromRel $spec.Path -ToRel $specDest
            Add-P20DocsLine -Path (& $full $specDest) -DocPath $docRel
            Add-P20BlankBeforeStamp -Path (& $full $specDest)
            Add-ClosedDate -Path (& $full $specDest)
            if ($noteDest) {
                Move-P20DesignFile -FromRel $note.Path -ToRel $noteDest
                Add-ClosedDate -Path (& $full $noteDest)
            }
            if ($notePathAfter) {
                $noteOrigRel = $note.Path
                Add-P20JourneyLine -Path (& $full $notePathAfter) -NoteRel $noteOrigRel -Line $line -Thread $design.Thread
                $staged += $notePathAfter
            }
            Complete-P20Staging -Summary "$title complete; docs in $docRel"
        }
    }
}

if ($WhatIf) { Write-Host 'Nothing was written (-WhatIf).' -ForegroundColor DarkGray }
else {
    Write-Host "Moved: '$title' -> $To." -ForegroundColor Green
    if (Get-Command Write-ToolkitLog -ErrorAction SilentlyContinue) {
        Write-ToolkitLog -Type CMD -Source "$($prefix)MoveDesign" -Detail "$($design.Short) -> $To"
    }
}
exit 0
