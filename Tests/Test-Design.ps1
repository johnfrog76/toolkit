<#
.SYNOPSIS
    The design lifecycle's reader, this half (L2; docs/hub/design.md, "The file"
    and "State -- derived, never stored").
.DESCRIPTION
    Three things, none of them a verb -- the verb is L3's MoveDesign, and it will
    refuse by the rule pinned here:

      - the STATE RULE, Resolve-P20DesignState, over the ONE table both halves
        assert (Tests/fixtures/design/states.json; Tests/test_design.py is the
        agent's side of it) -- state, outcome, mismatch and Closed, row for row;
      - the TREE READER, Read-P20DesignTree, over a scratch tree: the four
        folders, grouping by id, a file with no id counted and not shown, two
        notes with one id a conflict, README.md skipped, CRLF read the same,
        the row's words (title, description, thread, Docs), road order, and
        the structure flags;
      - the SURFACES ROW, "Design lifecycle" in Get-P20OptionalSurfaces: `not
        configured` with no design/ or with nothing but a README in it, `on`
        when every file is stamped, `off` with the count when one is not --
        and its question.

    Run:  pwsh -File Tests/Test-Design.ps1
    Or:   {cliPrefix}TestToolkit -Design
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$pkgRoot = Split-Path $scriptDir -Parent

. (Join-Path $pkgRoot 'Scripts/Get-Consts.ps1')
. (Join-Path $pkgRoot 'Scripts/Resolve-HubConfig.ps1')
. (Join-Path $pkgRoot 'Scripts/Read-DesignTree.ps1')

# -- Test harness --------------------------------------------------------------

$script:passed = 0
$script:failed = 0
$script:errors = @()

function Assert-True {
    param([string]$TestName, [bool]$Condition, [string]$Detail = '')
    if ($Condition) {
        $script:passed++
        Write-Host "  PASS  $TestName" -ForegroundColor Green
    }
    else {
        $script:failed++
        $msg = "  FAIL  $TestName"
        if ($Detail) { $msg += " -- $Detail" }
        $script:errors += $msg
        Write-Host $msg -ForegroundColor Red
    }
}

function Assert-Equal {
    param([string]$TestName, $Expected, $Actual)
    if ("$Expected" -eq "$Actual") {
        $script:passed++
        Write-Host "  PASS  $TestName" -ForegroundColor Green
    }
    else {
        $script:failed++
        $msg = "  FAIL  $TestName -- expected '$Expected', got '$Actual'"
        $script:errors += $msg
        Write-Host $msg -ForegroundColor Red
    }
}

function Write-Lf {
    # UTF-8, no BOM, LF -- or CRLF when asked: the bytes a card has (AGENTS.md).
    param([string]$Path, [string]$Text, [switch]$Crlf)
    $dir = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $normal = $Text -replace "`r`n", "`n"
    if ($Crlf) { $normal = $normal -replace "`n", "`r`n" }
    [System.IO.File]::WriteAllText($Path, $normal, (New-Object System.Text.UTF8Encoding($false)))
}

$consts = Get-P20Consts
$closedStamp = [string]$consts.stamps.closed
$outcomeStamp = [string]$consts.stamps.outcome
$docsLine = [string]$consts.design.docsLine
$idKey = [string]$consts.design.idKey

$base = Join-Path ([System.IO.Path]::GetTempPath()) ("p20-design-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Path $base -Force | Out-Null

try {
    # -- 1. The state rule over the shared table -----------------------------
    Write-Host ""
    Write-Host "-- Resolve-P20DesignState: the shared table --------------" -ForegroundColor Cyan

    $table = Get-Content (Join-Path $pkgRoot 'Tests/fixtures/design/states.json') -Raw | ConvertFrom-Json
    Assert-True 'the table has rows' (@($table.rows).Count -ge 7)
    foreach ($row in $table.rows) {
        $note = 'none'; if ($row.note) { $note = [string]$row.note }
        $spec = 'none'; if ($row.spec) { $spec = [string]$row.spec }
        $noteText = "# N`n`n" + (@($row.noteLines) -join "`n") + "`n"
        $specText = "# S`n`n" + (@($row.specLines) -join "`n") + "`n"
        $r = Resolve-P20DesignState -Note $note -Spec $spec -NoteText $noteText -SpecText $specText
        $e = $row.expected
        $expectedOutcome = ''; if ($e.outcome) { $expectedOutcome = [string]$e.outcome }
        Assert-Equal "$($row.name): state" $e.state $r.State
        Assert-Equal "$($row.name): outcome" $expectedOutcome $r.Outcome
        Assert-Equal "$($row.name): mismatch" ([bool]$e.mismatch) $r.Mismatch
        Assert-Equal "$($row.name): closed" ([string]$e.closed) $r.Closed
    }

    # -- 2. The tree reader --------------------------------------------------
    Write-Host ""
    Write-Host "-- Read-P20DesignTree: a scratch tree ---------------------" -ForegroundColor Cyan

    $tree = Join-Path $base 'repo'
    $idPair = 'aaaaaaaa-0000-4000-8000-000000000001'
    $idAlone = 'aaaaaaaa-0000-4000-8000-000000000002'
    $idDropped = 'aaaaaaaa-0000-4000-8000-000000000003'
    $idTwice = 'aaaaaaaa-0000-4000-8000-000000000004'
    $idSpecOnly = 'aaaaaaaa-0000-4000-8000-000000000005'
    $idLeft = 'aaaaaaaa-0000-4000-8000-000000000006'
    Write-Lf (Join-Path $tree 'design/pair.md') "---`n${idKey}: $idPair`ndescription: `"The pair's one line`"`n---`n`n# Feature: the pair`n`n> GitHub: https://github.com/o/r/issues/7`n`nBody.`n"
    Write-Lf (Join-Path $tree 'spec/pair.spec.md') "---`n${idKey}: $idPair`ndescription: `"not the row's line`"`n---`n`n# Pair (spec)`n"
    Write-Lf (Join-Path $tree 'design/alone.md') "---`n${idKey}: $idAlone`n---`n`n# A note alone`n" -Crlf
    Write-Lf (Join-Path $tree 'design/archive/dropped.md') "---`n${idKey}: $idDropped`n---`n`n# An idea that never made it`n`n$closedStamp 2026-11-20`n$outcomeStamp dropped`n"
    Write-Lf (Join-Path $tree 'design/unstamped.md') "# No id here`n"
    Write-Lf (Join-Path $tree 'design/README.md') "# Not a design`n"
    Write-Lf (Join-Path $tree 'design/twice-a.md') "---`n${idKey}: $idTwice`n---`n`n# Twice A`n"
    Write-Lf (Join-Path $tree 'design/twice-b.md') "---`n${idKey}: $idTwice`n---`n`n# Twice B`n"
    Write-Lf (Join-Path $tree 'spec/archive/built.spec.md') "---`n${idKey}: $idSpecOnly`ndescription: 'Built and documented'`n---`n`n# Built (spec)`n`n$docsLine docs/hub/built.md`n`n$closedStamp 2026-10-01`n"
    Write-Lf (Join-Path $tree 'design/left.md') "---`n${idKey}: $idLeft`n---`n`n# Left behind`n"
    Write-Lf (Join-Path $tree 'spec/archive/left.spec.md') "---`n${idKey}: $idLeft`n---`n`n# Left (spec)`n`n$closedStamp 2026-10-02`n"

    $read = Read-P20DesignTree -DesignDir (Join-Path $tree 'design') -SpecDir (Join-Path $tree 'spec') -Base $tree
    Assert-True 'structure: design/ is there' ([bool]$read.Structure.design)
    Assert-True 'structure: spec/ is there' ([bool]$read.Structure.spec)
    $by = @{}
    foreach ($d in $read.Designs) { $by[$d.Id] = $d }
    Assert-Equal 'five designs are shown' 5 @($read.Designs).Count
    Assert-Equal 'the states come in road order' 'Design,Spec,Complete,Complete,Archived' (@($read.Designs | ForEach-Object { $_.State }) -join ',')
    Assert-Equal 'within a state, by title' 'Built (spec),Left behind' (@($read.Designs | Where-Object { $_.State -eq 'Complete' } | ForEach-Object { $_.Title }) -join ',')

    $pair = $by[$idPair]
    Assert-Equal 'the pair is a Spec' 'Spec' $pair.State
    Assert-Equal 'its title is the note''s heading' 'Feature: the pair' $pair.Title
    Assert-Equal 'its description is the note''s, not the spec''s' "The pair's one line" $pair.Description
    Assert-Equal 'its thread is read' 'https://github.com/o/r/issues/7' $pair.Thread
    Assert-Equal 'its note path is relative, forward slashes' 'design/pair.md' $pair.Note.Path
    Assert-Equal 'its spec path too' 'spec/pair.spec.md' $pair.Spec.Path
    Assert-Equal 'the short id is eight characters' 'aaaaaaaa' $pair.Short
    Assert-True 'nothing is closed on a Spec' ($pair.Closed -eq '')

    $alone = $by[$idAlone]
    Assert-Equal 'a CRLF note alone is a Design' 'Design' $alone.State
    Assert-Equal 'and its title reads without a CR' 'A note alone' $alone.Title
    Assert-True 'it has no spec' ($null -eq $alone.Spec)
    Assert-Equal 'a note with no > GitHub: line has no thread' '' $alone.Thread

    $dropped = $by[$idDropped]
    Assert-Equal 'an archived note alone is Archived' 'Archived' $dropped.State
    Assert-Equal 'with its outcome' 'dropped' $dropped.Outcome
    Assert-Equal 'and its Closed date' '2026-11-20' $dropped.Closed
    Assert-True 'its note is marked archived' ([bool]$dropped.Note.Archived)

    $built = $by[$idSpecOnly]
    Assert-Equal 'an archived spec with no note is Complete' 'Complete' $built.State
    Assert-Equal 'its words come from the spec' 'Built and documented' $built.Description
    Assert-Equal 'its Docs line is read' 'docs/hub/built.md' $built.Docs
    Assert-Equal 'its Closed date is the spec''s' '2026-10-01' $built.Closed
    Assert-True 'it has no note' ($null -eq $built.Note)

    $left = $by[$idLeft]
    Assert-Equal 'a note left behind: the spec''s folder wins' 'Complete' $left.State
    Assert-True 'and the row says the two disagree' ([bool]$left.Mismatch)
    Assert-True 'the pair does not disagree' (-not [bool]$pair.Mismatch)

    Assert-Equal 'three files are not shown' 3 @($read.NotShown).Count
    $noId = @($read.NotShown | Where-Object { $_.Reason -eq 'no id' })
    Assert-Equal 'one of them has no id' 1 $noId.Count
    Assert-Equal 'and it is named by path' 'design/unstamped.md' $noId[0].Path
    $twice = @($read.NotShown | Where-Object { $_.Path -like 'design/twice-*' })
    Assert-Equal 'two notes with one id are both counted' 2 $twice.Count
    Assert-Equal 'with the reason naming the id' '2 notes carry the id aaaaaaaa' $twice[0].Reason
    Assert-True 'README.md is not a design and is not counted' (-not ($read.NotShown | Where-Object { $_.Path -like '*README*' }))
    Assert-True 'and the conflicting id is not among the designs' (-not $by.ContainsKey($idTwice))

    $noSpec = Join-Path $base 'nospec'
    Write-Lf (Join-Path $noSpec 'design/only.md') "---`n${idKey}: $idAlone`n---`n`n# Only`n"
    $read2 = Read-P20DesignTree -DesignDir (Join-Path $noSpec 'design') -SpecDir (Join-Path $noSpec 'spec')
    Assert-True 'a tree with no spec/ says so' (-not [bool]$read2.Structure.spec)
    Assert-Equal 'and still lists its notes' 1 @($read2.Designs).Count
    $empty = Join-Path $base 'empty'
    New-Item -ItemType Directory -Path $empty -Force | Out-Null
    $read3 = Read-P20DesignTree -DesignDir (Join-Path $empty 'design') -SpecDir (Join-Path $empty 'spec')
    Assert-True 'no folders at all: no structure, nothing shown, nothing counted' ((-not [bool]$read3.Structure.design) -and (@($read3.Designs).Count -eq 0) -and (@($read3.NotShown).Count -eq 0))

    # A note the public export has been over: its > GitHub: header and its Journey
    # Thread: lines are gone (the public tracker starts fresh), and a note made by
    # NewDesign has none until MoveDesign threads it. Both read as a design with no
    # thread, and nothing else in the row changes.
    $createdStamp = [string]$consts.stamps.created
    $exported = Join-Path $base 'exported'
    $idExported = 'aaaaaaaa-0000-4000-8000-000000000007'
    $exportedNote = "---`n${idKey}: $idExported`ndescription: `"Exported, no thread`"`n---`n`n# Feature: exported`n`n> **The living card.** Its spec is spec/exported.spec.md.`n`n## Journey`n`n- 2026-10-04 Design: written as design/exported.md in the repository.`n- 2026-10-05 Spec: became spec/exported.spec.md in the repository.`n`n$createdStamp 2026-10-04`n"
    Write-Lf (Join-Path $exported 'design/exported.md') $exportedNote
    Write-Lf (Join-Path $exported 'spec/exported.spec.md') "---`n${idKey}: $idExported`n---`n`n# Exported (spec)`n"
    $readE = Read-P20DesignTree -DesignDir (Join-Path $exported 'design') -SpecDir (Join-Path $exported 'spec') -Base $exported
    Assert-Equal 'an exported note is still a design' 1 @($readE.Designs).Count
    $ex = $readE.Designs[0]
    Assert-Equal 'it is read as a Spec, with its id' "Spec $idExported" "$($ex.State) $($ex.Id)"
    Assert-Equal 'its title and description are read' 'Feature: exported|Exported, no thread' "$($ex.Title)|$($ex.Description)"
    Assert-Equal 'its thread is empty, not an error' '' $ex.Thread
    Assert-Equal 'and nothing is left out of the row' 0 @($readE.NotShown).Count

    # -- 3. The surfaces row -------------------------------------------------
    Write-Host ""
    Write-Host "-- Get-P20OptionalSurfaces: the Design lifecycle row -----" -ForegroundColor Cyan

    . (Join-Path $pkgRoot 'Scripts/Get-OptionalSurfaces.ps1')
    $states = Get-P20SurfaceStates
    $hasGit = [bool](Get-Command git -ErrorAction SilentlyContinue)

    function Get-DesignRow {
        param([string]$In)
        Push-Location $In
        try { return (Get-P20OptionalSurfaces -Prefix 'tk' -PackageRoot $pkgRoot | Where-Object { $_.key -eq 'design' }) }
        finally { Pop-Location }
    }

    $plain = Join-Path $base 'plain'
    New-Item -ItemType Directory -Path $plain -Force | Out-Null
    $row = Get-DesignRow -In $plain
    Assert-True 'the row is in the inventory' ($null -ne $row)
    Assert-Equal 'its title' 'Design lifecycle' $row.title
    Assert-Equal 'outside a repository it is not configured' $states.Unset $row.state
    Assert-True 'and it carries its question' ([bool]$row.question) "question: '$($row.question)'"
    Assert-True 'the config line names StampDesign' ($row.config -like '*StampDesign*')

    if ($hasGit) {
        $stamped = Join-Path $base 'stamped'
        New-Item -ItemType Directory -Path $stamped -Force | Out-Null
        Push-Location $stamped
        try { git init -q . 2>$null | Out-Null } finally { Pop-Location }
        Write-Lf (Join-Path $stamped 'design/one.md') "---`n${idKey}: $idAlone`n---`n`n# One`n"
        $row = Get-DesignRow -In $stamped
        Assert-Equal 'a repository whose files are all stamped is on' $states.On $row.state
        Assert-True 'and the note counts its designs' ($row.note -like '1 designs*') "note: '$($row.note)'"

        Write-Lf (Join-Path $stamped 'spec/archive/old.spec.md') "# Old, unstamped`n"
        $row = Get-DesignRow -In $stamped
        Assert-Equal 'one unstamped file and the row is off' $states.Off $row.state
        Assert-True 'with the count in the note' ($row.note -like '1 file not stamped*') "note: '$($row.note)'"
        Assert-Equal 'and the config line is the stamp' 'tkStampDesign' $row.config

        # The folders with nothing but a README in them: a product that has not written its
        # first note has not answered, so the row is not configured, not `on` with 0 designs.
        $readmeOnly = Join-Path $base 'readme-only'
        New-Item -ItemType Directory -Path $readmeOnly -Force | Out-Null
        Push-Location $readmeOnly
        try { git init -q . 2>$null | Out-Null } finally { Pop-Location }
        Write-Lf (Join-Path $readmeOnly 'design/README.md') "# Design notes`n"
        Write-Lf (Join-Path $readmeOnly 'spec/README.md') "# Specs`n"
        $row = Get-DesignRow -In $readmeOnly
        Assert-Equal 'a repository whose design/ holds only a README is not configured' $states.Unset $row.state
        Assert-True 'and the note says there is nothing yet' ($row.note -like 'no designs in this repository yet*') "note: '$($row.note)'"
        Assert-True 'with the config line that starts one' ($row.config -like '*StampDesign*') "config: '$($row.config)'"

        $nodesign = Join-Path $base 'nodesign'
        New-Item -ItemType Directory -Path $nodesign -Force | Out-Null
        Push-Location $nodesign
        try { git init -q . 2>$null | Out-Null } finally { Pop-Location }
        $row = Get-DesignRow -In $nodesign
        Assert-Equal 'a repository with no design/ is not configured' $states.Unset $row.state
    }
    else {
        Write-Host "  SKIP  the repository cases need git on the PATH" -ForegroundColor Yellow
    }
}
catch {
    Assert-True 'the cases ran to the end without a terminating error' $false $_.Exception.Message
}
finally {
    Remove-Item -LiteralPath $base -Recurse -Force -ErrorAction SilentlyContinue
}

# -- The design a CARD names (toolkit card C3) -------------------------------------
# Get-P20CardDesign over the ONE table the agent's card_design asserts too
# (Tests/fixtures/parsers/design-lines.json; Tests/test_parsers.py is its side).
# And the one rule for what a person typed, which MoveDesign and NewPrompt -Design ask.
Write-Host ""
Write-Host "-- A card's design line, by the shared table ----------" -ForegroundColor Cyan
try {
    $lineTable = Get-Content (Join-Path $pkgRoot 'Tests/fixtures/parsers/design-lines.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-True 'the table has its rows' (@($lineTable.rows).Count -ge 10)
    foreach ($row in @($lineTable.rows)) {
        $eol = "`n"
        if ($row.crlf) { $eol = "`r`n" }
        $text = (@($row.lines) -join $eol) + $eol
        $got = Get-P20CardDesign -Text $text
        if ($null -eq $row.expected) {
            Assert-True "$($row.name): names no design" ($null -eq $got) ($got | Out-String)
            continue
        }
        $e = $row.expected
        $same = $got -and ($got.Kind -ceq $e.kind) -and ($got.Title -ceq $e.title) -and ($got.Link -ceq $e.link) -and ($got.Id -ceq $e.id) -and ($got.Note -ceq $e.note)
        Assert-True "$($row.name)" $same ("got: " + ($got | Out-String).Trim())
    }
    $line = New-P20DesignLine -Title 'Board ideas: the [next] lane' -Link '../../design/board-ideas.md' -Id 'ee925272-9564-4816-8944-e6b39c86339c'
    Assert-Equal 'New-P20DesignLine writes the token, the title (a bracket made round), the link and the id' `
        '> Design: [Board ideas: the (next) lane](../../design/board-ideas.md) ee925272-9564-4816-8944-e6b39c86339c' $line
    $back = Get-P20CardDesign -Text $line
    Assert-True 'and the reader reads what the writer wrote' ($back -and $back.Id -eq 'ee925272-9564-4816-8944-e6b39c86339c' -and $back.Title -eq 'Board ideas: the (next) lane')

    $mk = {
        param([string]$Id, [string]$Note, [string]$Spec)
        $n = $null; $s = $null
        if ($Note) { $n = [pscustomobject]@{ Name = $Note } }
        if ($Spec) { $s = [pscustomobject]@{ Name = $Spec } }
        [pscustomobject]@{ Id = $Id; Note = $n; Spec = $s }
    }
    $pool = @(
        (& $mk 'ab12cd34-0000-4000-8000-000000000001' 'board-ideas.md' 'board-ideas.spec.md'),
        (& $mk 'ab12ef56-0000-4000-8000-000000000002' 'lanes.md' ''),
        (& $mk 'ee925272-9564-4816-8944-e6b39c86339c' '' 'stand-alone.spec.md'))
    Assert-Equal 'Select-P20Design: an id prefix of four names its design' 1 @(Select-P20Design -Designs $pool -Name 'ee92').Count
    Assert-Equal 'a prefix two ids share names both' 2 @(Select-P20Design -Designs $pool -Name 'ab12').Count
    Assert-Equal 'a stem names the design whose note or spec has it' 1 @(Select-P20Design -Designs $pool -Name 'board-ideas').Count
    Assert-Equal 'so does a spec''s file name, any case' 1 @(Select-P20Design -Designs $pool -Name 'Stand-Alone.Spec.md').Count
    Assert-Equal 'and a name nothing has names nothing' 0 @(Select-P20Design -Designs $pool -Name 'nothing').Count
}
catch {
    Assert-True 'the card-line cases ran to the end without a terminating error' $false $_.Exception.Message
}

Write-Host ""
Write-Host "=======================================================" -ForegroundColor Cyan
$total = $script:passed + $script:failed
Write-Host "  Results: $($script:passed)/$total passed" -ForegroundColor $(if ($script:failed -eq 0) { 'Green' } else { 'Red' })
if ($script:errors.Count -gt 0) {
    Write-Host ""
    Write-Host "  Failures:" -ForegroundColor Red
    foreach ($e in $script:errors) { Write-Host $e -ForegroundColor Red }
}
Write-Host "=======================================================" -ForegroundColor Cyan
Write-Host ""

if ($script:failed -gt 0) { exit 1 }
exit 0
