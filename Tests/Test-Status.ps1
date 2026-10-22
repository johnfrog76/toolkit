<#
.SYNOPSIS
    Status detection parity tests for Get-PromptStatus.ps1.
.DESCRIPTION
    Get-PromptFileStatus is the PowerShell implementation of the state gate:
    "PR URL: line present -> Code Review; commit hash present -> In Progress; else Active."
    The fixtures below were inherited from the package this was carved from, which
    had a second implementation of the same state machine. That service is not part
    of Toolkit and nothing here depends on it. This suite runs the
    PowerShell function against the identical fixture files so any regex drift between
    the two implementations fails a test rather than silently diverging.

    Run:  pwsh -File toolkit/Tests/Test-Status.ps1
    Or:   {cliPrefix}TestToolkit -Status
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$scriptDir   = Split-Path -Parent $MyInvocation.MyCommand.Path
# Package root is the parent of Tests/, from this file's own location.
$pkgRoot     = Split-Path $scriptDir -Parent

$targetScript = Join-Path $pkgRoot 'Scripts/Get-PromptStatus.ps1'
if (-not (Test-Path $targetScript)) {
    Write-Error "Get-PromptStatus.ps1 not found at $targetScript"
    return
}

$fixtureDir = Join-Path $scriptDir 'fixtures/parsers'

# The state machine's strings live in consts.json now, and the function reads
# them through this one reader -- lifting the function out of the file does not
# lift its dependency, so the suite loads it exactly as the script does.
. (Join-Path $pkgRoot 'Scripts/Get-Consts.ps1')

# -- The rule is its own file now: dot-source it, as the verbs do ---
. (Join-Path $pkgRoot 'Scripts/Get-PromptFileStatus.ps1')
# The Status script's own text is still read below, for the File: line it prints.
$sourceText = Get-Content -Path $targetScript -Raw

if (-not (Get-Command Get-PromptFileStatus -ErrorAction SilentlyContinue)) {
    Write-Error "Get-PromptFileStatus did not load correctly"
    return
}

# Byte-level writes for a card or session the verb under test reads or has just
# written. A host cmdlet (Set-Content / Add-Content -Encoding UTF8) opens the file
# with its own encoding detection and, on Windows PowerShell 5.1, throws "Stream was
# not readable" when something still holds it; the tool itself writes cards as
# BOM-less UTF-8 (AGENTS.md, "One byte contract for a card").
function Write-FixtureText {
    param([string]$Path, [string]$Text)
    [System.IO.File]::WriteAllText($Path, $Text + [Environment]::NewLine, (New-Object System.Text.UTF8Encoding $false))
}
function Add-FixtureText {
    param([string]$Path, [string]$Text)
    [System.IO.File]::AppendAllText($Path, $Text, (New-Object System.Text.UTF8Encoding $false))
}

# -- Scratch runner writer -----------------------------------------------------
# Several cases write a run.ps1 into a scratch hub, start a child on it, and write
# it again for the next case. On Windows PowerShell 5.1 a scanner can still hold the
# file the child just read ("being used by another process", "Stream was not
# readable"), and the rewrite is the operation that fails. The write retries
# briefly and rethrows on the last try; the same shape as Test-ModuleCommands.
function Write-ScratchRunner {
    param([string]$Path, [string]$Value, [switch]$NoBom)
    for ($try = 1; $try -le 10; $try++) {
        try {
            # Both branches write bytes: Set-Content -Encoding UTF8 opens the file
            # through the host's own encoding path and, under Windows PowerShell
            # 5.1, throws "Stream was not readable" when something still holds the
            # runner the child just read -- an ArgumentException the retry below
            # cannot wait out. The default branch keeps the BOM Set-Content wrote
            # on 5.1, so a runner carrying non-ASCII still reads as UTF-8 there.
            $enc = New-Object System.Text.UTF8Encoding($(-not $NoBom))
            [System.IO.File]::WriteAllText($Path, $Value + $(if ($NoBom) { '' } else { [Environment]::NewLine }), $enc)
            return
        }
        catch {
            if ($try -eq 10) { throw }
            Start-Sleep -Milliseconds 300
        }
    }
}
# -- Test harness --------------------------------------------------------------

$script:passed = 0
$script:failed = 0
$script:errors = @()

function Assert-Status {
    param([string]$TestName, [string]$Expected, [string]$Got)
    if ($Got -eq $Expected) {
        $script:passed++
        Write-Host "  PASS  $TestName" -ForegroundColor Green
    }
    else {
        $script:failed++
        $msg = "  FAIL  $TestName  (expected '$Expected', got '$Got')"
        $script:errors += $msg
        Write-Host $msg -ForegroundColor Red
    }
}

Write-Host ""
Write-Host "===================================================" -ForegroundColor Cyan
Write-Host "  Prompt Status Detection Tests" -ForegroundColor Cyan
Write-Host "===================================================" -ForegroundColor Cyan
Write-Host ""

# -- Fixture-based tests ------------------------------------------------------

$activeContent      = Get-Content (Join-Path $fixtureDir 'active.md')      -Raw
$inProgressContent  = Get-Content (Join-Path $fixtureDir 'in-progress.md') -Raw
$codeReviewContent  = Get-Content (Join-Path $fixtureDir 'code-review.md') -Raw
$multiRoundContent  = Get-Content (Join-Path $fixtureDir 'pr-multi-round.md') -Raw
$headingOnlyContent = Get-Content (Join-Path $fixtureDir 'review-heading-no-url.md') -Raw
$startedContent     = Get-Content (Join-Path $fixtureDir 'started-line.md') -Raw
$reviewLineContent  = Get-Content (Join-Path $fixtureDir 'review-line.md') -Raw

Assert-Status "active.md            -> Active"      'Active'      (Get-PromptFileStatus $activeContent)
Assert-Status "in-progress.md       -> In Progress" 'In Progress' (Get-PromptFileStatus $inProgressContent)
Assert-Status "code-review.md       -> Code Review" 'Code Review' (Get-PromptFileStatus $codeReviewContent)
Assert-Status "pr-multi-round.md    -> Code Review" 'Code Review' (Get-PromptFileStatus $multiRoundContent)
# The PR URL LINE is the gate, not review comments. Tests/test_parsers.py asserts the
# SAME file: the agent once read it as Code Review.
Assert-Status "review-heading-no-url.md -> In Progress (the line is the gate, not the heading)" 'In Progress' (Get-PromptFileStatus $headingOnlyContent)
# A person's tokens: Started is In Progress with nothing committed; Review is
# Code Review with no pull request, and outranks the commit bullet as PR URL does.
Assert-Status "started-line.md      -> In Progress (a person said so, nothing committed)" 'In Progress' (Get-PromptFileStatus $startedContent)
Assert-Status "review-line.md       -> Code Review (a person said look at this, no PR)" 'Code Review' (Get-PromptFileStatus $reviewLineContent)

# -- The folder states, read first: one shared table ---------------------------
# Tests/fixtures/parsers/states.json -- Tests/test_parsers.py asserts the SAME
# rows against card_status, so the two halves cannot read a folder differently.
$stateTable = Get-Content (Join-Path $fixtureDir 'states.json') -Raw -Encoding UTF8 | ConvertFrom-Json
foreach ($row in @($stateTable.rows)) {
    Assert-Status "states.json: $($row.name)" ([string]$row.status) (Get-PromptFileStatus -Content ([string]$row.content) -Folder ([string]$row.folder))
}

# -- Edge case: empty file is Active ------------------------------------------

Assert-Status "empty content        -> Active"      'Active'      (Get-PromptFileStatus '')

# -- Edge case: commit hashes without PR URL stay In Progress -----------------
# The regex allows an optional backtick wrapper (``abc1234``) or a bare hash.

$commitOnly = "# Task`nCommits:`n- abc1234 fix`n"
Assert-Status "commits, no PR URL   -> In Progress" 'In Progress' (Get-PromptFileStatus $commitOnly)

# -- Edge case: PR URL without https:// does NOT flip to Code Review -----------
# GetPRComments always writes a full https:// URL; a bare "PR URL:" with no
# scheme is not a valid token and must not trigger Code Review.
# (No commit hashes either, so the result is Active, not In Progress.)

$bareUrl = "# Task`nPR URL: /pullrequest/99`n"
Assert-Status "PR URL without https -> Active"      'Active'      (Get-PromptFileStatus $bareUrl)

# -- Edge case: Code Review wins over commits (both present) -------------------

$both = "# Task`n- `"abc1234`" fix`nPR URL: https://dev.azure.com/org/proj/_git/repo/pullrequest/1`n"
Assert-Status "PR URL + commits     -> Code Review" 'Code Review' (Get-PromptFileStatus $both)

Write-Host ""

# -- The File: line is openable -----------------------------------------------
# Status printed $file.Name -- a bare file name. The prompt store is its own
# repo and is never the terminal's working directory (you run this from the app
# repo you are coding in), so a terminal resolved that name against the wrong
# directory and ctrl+click found nothing. Reported from VS Code.
#
# Checked against the source text: the display is inline script, not an
# extractable function, and the alternative -- running Status for real -- needs
# a configured store this suite deliberately does not assume.

function Assert-True {
    param([string]$TestName, [bool]$Condition, [string]$Detail = '')
    if ($Condition) {
        $script:passed++
        Write-Host "  PASS  $TestName" -ForegroundColor Green
    }
    else {
        $script:failed++
        $msg = "  FAIL  $TestName" + $(if ($Detail) { " -- $Detail" } else { '' })
        $script:errors += $msg
        Write-Host $msg -ForegroundColor Red
    }
}

Assert-True "the row carries a full path taken from FullName" `
    ($sourceText -match '(?m)^\s*Path\s*=\s*\$file\.FullName\s*$') `
    'Status needs $file.FullName on the row, not just $file.Name'

$fileLine = [regex]::Match($sourceText, '(?m)^\s*Write-Host\s+"\s*File:\s*\$\(\$row\.(\w+)\)')
Assert-True "the File: line renders that path" `
    ($fileLine.Success -and $fileLine.Groups[1].Value -eq 'Path') `
    "it renders `$row.$($fileLine.Groups[1].Value) -- a bare name is not openable from another directory"

Write-Host ""

# -- The order the cards are listed in ----------------------------------------
# The numbering (1., 2., ...) is what a user reads to pick a card, and it used
# to change with the shell. Windows PowerShell 5.1's Sort-Object is not stable
# and PowerShell 7's is, so with every card in one state the keys tied and 5.1
# rotated the list: 114, 137, 141, Task139, US-119, US-142 in pwsh became
# Task139, US-119, US-142, 114, 137, 141 in powershell.exe against the same hub.
#
#
# The names below are the ones that reproduced it. This case runs the real
# script, so it fails on either host if the ordering stops being explicit --
# a source-text assertion would not, since the old code also "had a sort".
# agent/core/parsers.py's status_sort_key is the same pair, ordinal, and
# Tests/test_parsers.py pins the agent's half against this same expectation.

Write-Host "-- Listing order ---------------------------------------" -ForegroundColor Cyan

$orderHub = Join-Path ([System.IO.Path]::GetTempPath()) "p20-status-order-$([guid]::NewGuid())"
try {
    $orderCurrent = Join-Path $orderHub 'test/current'
    New-Item -ItemType Directory -Path $orderCurrent -Force | Out-Null

    # Six Active cards, deliberately in an order no sort would produce.
    foreach ($n in @('US-142-foxtrot', '141-charlie', 'Task139-delta', '114-alpha', 'US-119-echo', '137-bravo')) {
        Write-FixtureText (Join-Path $orderCurrent "$n.prompt.md") "# $n"
    }
    # And two that are not Active, named to sort FIRST if state were ignored.
    Write-FixtureText (Join-Path $orderCurrent '001-in-progress.prompt.md') "# 001-in-progress`n`n- abc1234 did the thing"
    Write-FixtureText (Join-Path $orderCurrent '002-code-review.prompt.md') "# 002-code-review`n`nPR URL: https://dev.azure.com/o/p/_git/r/pullrequest/1"

    $runner = Join-Path $orderHub 'run.ps1'
    $statusPath = $targetScript -replace "'", "''"
    $hubPath = $orderHub -replace "'", "''"
    $body = @"
`$global:P20Config = @{ PromptsRoot = '$hubPath'; CommandPrefix = 'zz' }
function global:Get-PromptFolders { return @{ Current = (Join-Path '$hubPath' 'test/current') } }
& '$statusPath'
"@
    Write-ScratchRunner -Path $runner -Value $body
    $orderOut = & pwsh -NoProfile -File $runner 2>&1 | Out-String

    $listed = @([regex]::Matches($orderOut, '(?m)^\s*File:\s+(.+?)\s*$') |
        ForEach-Object { Split-Path $_.Groups[1].Value -Leaf })

    $expected = @(
        '114-alpha.prompt.md', '137-bravo.prompt.md', '141-charlie.prompt.md',
        'Task139-delta.prompt.md', 'US-119-echo.prompt.md', 'US-142-foxtrot.prompt.md',
        '001-in-progress.prompt.md', '002-code-review.prompt.md'
    )

    Assert-True "Status lists every card in current/" ($listed.Count -eq $expected.Count) `
        "listed $($listed.Count): $($listed -join ', ')"
    Assert-True "cards in one state are ordered by file name, not by the host" `
        ((($listed | Select-Object -First 6) -join ',') -eq (($expected | Select-Object -First 6) -join ',')) `
        "got: $($listed -join ', ')"
    Assert-True "state still comes before name (In Progress after Active)" `
        ($listed.Count -eq 8 -and $listed[6] -eq '001-in-progress.prompt.md') `
        "got: $($listed -join ', ')"
    Assert-True "Code Review sorts last" `
        ($listed.Count -eq 8 -and $listed[7] -eq '002-code-review.prompt.md') `
        "got: $($listed -join ', ')"
    Assert-True "the whole order is the one the agent produces" `
        (($listed -join ',') -eq ($expected -join ',')) "got: $($listed -join ', ')"
}
catch {
    Assert-True 'the cases ran to the end without a terminating error' $false $_.Exception.Message
}
finally {
    Remove-Item -Path $orderHub -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host ""

# -- Offline NewPrompt: a card without ADO ------------------------------------
# The README states in bold that a Tier-2 machine still produces and maintains
# prompt files, and every documented way to produce one once went
# through ADO. `NewPrompt -Title` is the other half. It belongs in this suite
# because the thing worth proving is that the state machine above reads what it
# writes -- a scaffolder whose output Status cannot classify is not a card.

Write-Host "-- NewPrompt -Title (offline) --------------------------" -ForegroundColor Cyan

$newPromptScript = Join-Path $pkgRoot 'Scripts/New-PromptFromWorkItem.ps1'
$scratchHub = Join-Path ([System.IO.Path]::GetTempPath()) "p20-newprompt-$([guid]::NewGuid())"

function Invoke-OfflineNewPrompt {
    # A child pwsh with PATH emptied after the shims are defined, so `az` is
    # genuinely unreachable: a test that proves "no ADO call" on a machine that
    # has az signed in proves nothing.
    param([string]$ArgLine)
    $runner = Join-Path $scratchHub 'run.ps1'
    $invokePath = $newPromptScript -replace "'", "''"
    $body = @"
`$global:P20Config = @{
    PromptsRoot   = '$($scratchHub -replace "'", "''")'
    PromptsFolder = 'test'
    CommandPrefix = 'zz'
    BranchUser    = 'someone'
    Org           = ''
}
function global:Resolve-P20Identity { throw 'the offline path must not resolve an identity' }
`$env:PATH = ''
& '$invokePath' $ArgLine
exit `$LASTEXITCODE
"@
    Write-ScratchRunner -Path $runner -Value $body
    $out = & pwsh -NoProfile -File $runner 2>&1 | Out-String
    return [pscustomobject]@{ Output = $out; ExitCode = $LASTEXITCODE }
}

try {
    New-Item -ItemType Directory -Path (Join-Path $scratchHub 'test/current') -Force | Out-Null
    # A new card is PLANNED: with no -Now it lands in the Space's backlog/.

    $r = Invoke-OfflineNewPrompt -ArgLine "-Title 'Timeout on large files' -Type Bug"
    Assert-True "offline -Title exits 0" ($r.ExitCode -eq 0) $r.Output
    Assert-True "offline -Title says no ADO call was made" ($r.Output -match 'No ADO call was made') $r.Output

    # A card with no work item gets a short lettered id, not "1" (see
    # docs/hub/cards.md, "The filename"): find the file by its shape.
    $bugFile = @(Get-ChildItem (Join-Path $scratchHub 'test/backlog') -Filter '*-timeout-on-large-files.prompt.md' |
        Where-Object { $_.Name -cmatch '^[A-Z0-9]{4}-timeout-on-large-files\.prompt\.md$' -and $_.Name -cmatch '^[A-Z0-9]*[A-Z]' })
    $bug = if ($bugFile.Count -eq 1) { $bugFile[0].FullName } else { Join-Path $scratchHub 'test/backlog/(none)' }
    $bugId = if ($bugFile.Count -eq 1) { $bugFile[0].Name.Substring(0, 4) } else { '' }
    Assert-True "a Bug files bare, house style: {id}-{slug}" (Test-Path $bug) $r.Output
    if (Test-Path $bug) {
        $text = Get-Content $bug -Raw
        Assert-Status "Status reads the scaffolded card as Backlog -- a new card is planned" 'Backlog' (Get-PromptFileStatus $text -Folder (Split-Path $bug -Parent))
        Assert-True "the header carries type, id and title" ($text -cmatch ('(?m)^# Bug ' + $bugId + ': Timeout on large files')) $text
        Assert-True "the ADO Link says it is not linked" ($text -match '(?m)^\*\*ADO Link:\*\* \(not linked') $text
        Assert-True "the Sprint says it is not linked" ($text -match '(?m)^\*\*Sprint:\*\* \(not linked\)') $text
        Assert-True "the Created stamp is written" ($text -match '(?m)^\*\*Created:\*\* \d{4}-\d{2}-\d{2}') $text
        Assert-True "the branch uses the configured branchUser, not the OS account" ($text -cmatch ('(?m)^someone/' + $bugId + '-timeout-on-large-files')) $text
        Assert-True "the card links the type's template" ($text -match 'Bug\.template\.md') $text
    }

    # A User Story takes the US- prefix and the three-segment branch, so the
    # offline path really is going through the same house-style table.
    $r = Invoke-OfflineNewPrompt -ArgLine "-Title 'Import flow' -Type UserStory -Id 144"
    $story = Join-Path $scratchHub 'test/backlog/US-144-import-flow.prompt.md'
    Assert-True "'UserStory' resolves to the 'User Story' shape" (Test-Path $story) $r.Output
    if (Test-Path $story) {
        Assert-True "a story branch carries the third segment" ((Get-Content $story -Raw) -match '(?m)^someone/144/import-flow') ''
    }

    # No -Id: a short lettered id that no card carries -- never "the next number",
    # which would sooner or later be a real work item's.
    $r = Invoke-OfflineNewPrompt -ArgLine "-Title 'Spike the cache layer'"
    $made = @(Get-ChildItem (Join-Path $scratchHub 'test/backlog') -Filter 'Task*-spike-the-cache-layer.prompt.md')
    Assert-True "no -Id takes a lettered id, not the next number" `
        ($made.Count -eq 1 -and $made[0].Name -cmatch '^Task[A-Z0-9]{4}-' -and $made[0].Name -notmatch '^Task\d+-') $r.Output

    # current/ is protected, offline too. The owner's rule is that the verb
    # RETURNS the card that is there -- exit 0, nothing written -- and the offline form
    # now follows it like the ADO form, by ID: it used to
    # refuse only an identical FILE NAME, so the same id under a new title wrote a
    # second card.
    $before = (Get-Item $story).LastWriteTimeUtc
    $r = Invoke-OfflineNewPrompt -ArgLine "-Title 'Import flow' -Type UserStory -Id 144"
    Assert-True "an existing card is returned, not overwritten" ($r.ExitCode -eq 0 -and $r.Output -match 'already in' -and $r.Output -match 'nothing was written') $r.Output
    Assert-True "and the file was not touched" ((Get-Item $story).LastWriteTimeUtc -eq $before) ''
    $r = Invoke-OfflineNewPrompt -ArgLine "-Title 'A different title for the same id' -Type UserStory -Id 144"
    Assert-True "the same id under ANOTHER title is returned too, not written beside it" `
        ($r.ExitCode -eq 0 -and @(Get-ChildItem (Join-Path $scratchHub 'test/backlog') -Filter 'US-144-*').Count -eq 1) $r.Output

    # -Now: in play at once, in current/ -- exactly what the verb did before backlog/ existed.
    $r = Invoke-OfflineNewPrompt -ArgLine "-Title 'Right now' -Type Task -Id 145 -Now"
    Assert-True "-Now writes the card to current/, not backlog/" ((Test-Path (Join-Path $scratchHub 'test/current/Task145-right-now.prompt.md')) -and -not (Test-Path (Join-Path $scratchHub 'test/backlog/Task145-right-now.prompt.md'))) $r.Output
    $r = Invoke-OfflineNewPrompt -ArgLine "-Title 'Right now, again' -Type Task -Id 145"
    Assert-True "an id already in current/ is returned by a call with no -Now too: both open folders are asked" ($r.ExitCode -eq 0 -and $r.Output -match 'already in test/current/' -and @(Get-ChildItem (Join-Path $scratchHub 'test') -Recurse -Filter 'Task145-*').Count -eq 1) $r.Output

    # Refusals, stated.

    $r = Invoke-OfflineNewPrompt -ArgLine "-Title 'Nope' -Type Epic"
    Assert-True "an unknown -Type is refused by name" ($r.ExitCode -ne 0 -and $r.Output -match "unknown work item type 'Epic'") $r.Output
    Assert-True "the refusal lists the types it knows" ($r.Output -match 'Known types:.*Task') $r.Output

    $r = Invoke-OfflineNewPrompt -ArgLine ""
    Assert-True "neither an id nor a title is a stated error" ($r.ExitCode -ne 0 -and $r.Output -match '-Title to scaffold a card offline') $r.Output
}
catch {
    Assert-True 'the cases ran to the end without a terminating error' $false $_.Exception.Message
}
finally {
    Remove-Item -Path $scratchHub -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host ""

# -- The exit code on a hub that is not a git repository ----------------------
# The README says a hub need not be a git repository, and the Modified column
# already fell back to the filesystem -- but the per-card `git log` exits 128
# outside a repository, and the LAST card's 128 was what the command left
# behind, so `tkStatus; if ($LASTEXITCODE) { ... }` saw a failure that did not
# happen.
#
# Both halves of the fix are asserted: exit 0, and the dates still printed.

Write-Host "-- A hub that is not a git repository -----------------" -ForegroundColor Cyan

$plainHub = Join-Path ([System.IO.Path]::GetTempPath()) "p20-status-nogit-$([guid]::NewGuid())"
try {
    New-Item -ItemType Directory -Path (Join-Path $plainHub 'test/current') -Force | Out-Null
    Write-FixtureText (Join-Path $plainHub 'test/current/1-first.prompt.md') "# First`n`nA card."
    Write-FixtureText (Join-Path $plainHub 'test/current/2-second.prompt.md') "# Second`n`n- 80e2168 threaded"

    $runner = Join-Path $plainHub 'run.ps1'
    $invokePath = $targetScript -replace "'", "''"
    $body = @"
`$global:P20Config = @{
    PromptsRoot   = '$($plainHub -replace "'", "''")'
    PromptsFolder = 'test'
    CommandPrefix = 'zz'
    StoreSync     = 'none'
}
function global:Get-PromptFolders {
    `$root = Join-Path `$global:P20Config.PromptsRoot `$global:P20Config.PromptsFolder
    @{ Current = (Join-Path `$root 'current'); Archive = (Join-Path `$root 'archive') }
}
& '$invokePath'
exit `$LASTEXITCODE
"@
    Write-ScratchRunner -Path $runner -Value $body
    $output = & pwsh -NoProfile -File $runner 2>&1 | Out-String
    $code = $LASTEXITCODE

    Assert-True "Status on a non-git hub exits 0" ($code -eq 0) "exit $code -- $output"
    Assert-True "Status still lists the cards" ($output -match '1-first' -and $output -match '2-second') $output
    Assert-True "the filesystem date is printed" ($output -match '\d{4}-\d{2}-\d{2}') $output
    Assert-True "no git error reaches the output" ($output -notmatch 'not a git repository') $output
}
catch {
    Assert-True 'the cases ran to the end without a terminating error' $false $_.Exception.Message
}
finally {
    Remove-Item -Path $plainHub -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host ""

# -- Modified: the shared table, and ONE git call ------------------------------
# A card's Modified day is derived, so it must keep reading what the files
# already say. It used to be one `git log -1 -- <card>` per card; it is one log
# for current/. Tests/fixtures/status-modified/history.json pins the day for
# every shape that matters -- renamed, moved between folders, changed since its
# last commit, never committed, a name outside ASCII, no repository at all --
# and Tests/test_status.py asserts the same table against the agent's route.
# Status lists current/ alone, so the rows under backlog/ are the agent's.

Write-Host "-- Modified: the shared table -------------------------" -ForegroundColor Cyan

. (Join-Path $pkgRoot 'Scripts/Invoke-TrackerRead.ps1')
$historyTable = Get-Content -Path (Join-Path $scriptDir 'fixtures/status-modified/history.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$noonUtc = {
    param([string]$Day)
    [DateTime]::SpecifyKind([DateTime]::ParseExact($Day, 'yyyy-MM-dd', [Globalization.CultureInfo]::InvariantCulture).AddHours(12), [DateTimeKind]::Utc)
}
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)

foreach ($scenario in $historyTable.scenarios) {
    $tableHub = Join-Path ([System.IO.Path]::GetTempPath()) "p20-status-modified-$([guid]::NewGuid())"
    try {
        $space = Join-Path $tableHub 'test'
        foreach ($d in 'current', 'backlog', 'archive') { New-Item -ItemType Directory -Path (Join-Path $space $d) -Force | Out-Null }
        $writeCard = {
            param([string]$Rel, [string]$Note)
            $path = Join-Path $space $Rel
            New-Item -ItemType Directory -Path (Split-Path $path -Parent) -Force | Out-Null
            [System.IO.File]::WriteAllText($path, "# $([System.IO.Path]::GetFileNameWithoutExtension($Rel))`n`n$Note`n", $utf8NoBom)
        }
        $gitIn = {
            param([string[]]$GitArgs)
            Push-Location $tableHub
            try {
                $r = Invoke-P20TrackerRead 'git' (@('-c', 'user.name=t', '-c', 'user.email=t@example.com', '-c', 'commit.gpgsign=false') + $GitArgs)
                if ($r.Code -ne 0) { throw "git $($GitArgs -join ' '): $($r.Lines -join ' ')" }
            }
            finally { Pop-Location }
        }
        $committed = @{}
        if ($scenario.repository) {
            & $gitIn -GitArgs @('init', '-q')
            foreach ($commit in $scenario.commits) {
                foreach ($rel in @($commit.write)) { if ($rel) { & $writeCard $rel "written $($commit.day)"; $committed[$rel] = $true } }
                if ($commit.move) {
                    foreach ($prop in $commit.move.PSObject.Properties) {
                        New-Item -ItemType Directory -Path (Split-Path (Join-Path $space $prop.Value) -Parent) -Force | Out-Null
                        & $gitIn -GitArgs @('mv', "test/$($prop.Name)", "test/$($prop.Value)")
                        $committed.Remove($prop.Name); $committed[$prop.Value] = $true
                    }
                }
                $epoch = [DateTimeOffset]::new((& $noonUtc $commit.day)).ToUnixTimeSeconds()
                $env:GIT_AUTHOR_DATE = "$epoch +0000"; $env:GIT_COMMITTER_DATE = "$epoch +0000"
                try { & $gitIn -GitArgs @('add', '-A'); & $gitIn -GitArgs @('commit', '-q', '-m', $commit.day) }
                finally { Remove-Item Env:GIT_AUTHOR_DATE, Env:GIT_COMMITTER_DATE -ErrorAction SilentlyContinue }
            }
            foreach ($rel in @($committed.Keys)) { [System.IO.File]::SetLastWriteTimeUtc((Join-Path $space $rel), (& $noonUtc $scenario.staleMtime)) }
        }
        foreach ($item in @($scenario.uncommitted)) {
            & $writeCard $item.write 'on disk'
            [System.IO.File]::SetLastWriteTimeUtc((Join-Path $space $item.write), (& $noonUtc $item.mtime))
        }

        # The script in a child, with a git that records every call and then runs the
        # real one. Its output is written to a UTF-8 file inside the child, so a name
        # outside ASCII never passes through a console code page on its way here.
        $gitCalls = Join-Path $tableHub 'git-calls.log'
        $outFile = Join-Path $tableHub 'status-out.txt'
        $runner = Join-Path $tableHub 'run.ps1'
        $q = { param([string]$s) $s -replace "'", "''" }
        $body = @"
`$global:P20Config = @{ PromptsRoot = '$(& $q $tableHub)'; PromptsFolder = 'test'; CommandPrefix = 'zz'; StoreSync = 'none' }
function global:Get-PromptFolders {
    `$root = Join-Path `$global:P20Config.PromptsRoot 'test'
    @{ Current = (Join-Path `$root 'current'); Archive = (Join-Path `$root 'archive'); Backlog = (Join-Path `$root 'backlog') }
}
`$global:RealGit = (Get-Command git -CommandType Application | Select-Object -First 1).Source
function global:git { [System.IO.File]::AppendAllText('$(& $q $gitCalls)', "git `$(`$args -join ' ')``n"); & `$global:RealGit @args }
`$out = & '$(& $q $targetScript)' 6>&1 | Out-String
[System.IO.File]::WriteAllText('$(& $q $outFile)', `$out, (New-Object System.Text.UTF8Encoding(`$false)))
exit `$LASTEXITCODE
"@
        Write-ScratchRunner -Path $runner -Value $body
        $null = & pwsh -NoProfile -File $runner 2>&1
        $code = $LASTEXITCODE
        $output = ''
        if (Test-Path $outFile) { $output = [System.IO.File]::ReadAllText($outFile, $utf8NoBom) }

        $read = @{}
        $file = $null
        foreach ($line in ($output -split "`r?`n")) {
            if ($line -match '^\s*File:\s+(.+?)\s*$') { $file = Split-Path $Matches[1] -Leaf }
            elseif ($file -and $line -match 'Modified:\s+(\S+)') { $read[$file] = $Matches[1]; $file = $null }
        }
        $rows = @($scenario.expect | Where-Object { $_.card -like 'current/*' })
        $expectedNames = @($rows | ForEach-Object { Split-Path $_.card -Leaf } | Sort-Object)
        $listedNames = @($read.Keys | Sort-Object)

        Assert-True "$($scenario.name): Status exits 0" ($code -eq 0) "exit $code -- $output"
        Assert-True "$($scenario.name): every card in current/ is a row, and nothing else is listed (archive/, a subfolder)" `
            (($listedNames -join '|') -ceq ($expectedNames -join '|')) "listed: $($listedNames -join ', ')"
        foreach ($row in $rows) {
            $name = Split-Path $row.card -Leaf
            Assert-Status "$($scenario.name): $name -- $($row.why)" ([string]$row.day) ([string]$read[$name])
        }
        $calls = @()
        if (Test-Path $gitCalls) { $calls = @(Get-Content $gitCalls | Where-Object { $_ }) }
        Assert-True "$($scenario.name): ONE git call for $($rows.Count) cards, and no probe before it" `
            ($calls.Count -eq 1 -and $calls[0] -match ' log ' -and $calls[0] -notmatch 'rev-parse') ($calls -join ' / ')
    }
    catch {
        Assert-True "$($scenario.name): the cases ran to the end without a terminating error" $false $_.Exception.Message
    }
    finally {
        Remove-Item -Path $tableHub -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Write-Host ""

# -- Status -Board: the board's state beside the card's ----------------
# OPT-IN and READ-ONLY. Plain Status never contacts ADO; -Board asks `az boards
# work-item show` once per card linked to a work item and flags only the definite
# mismatch it can see -- a card still in current/ whose item is Closed, Done,
# Removed or Resolved. `az` is a STUB that records every call: a real one is
# never reached.

Write-Host "-- Status -Board --------------------------------------" -ForegroundColor Cyan

$boardHub = Join-Path ([System.IO.Path]::GetTempPath()) "p20-status-board-$([guid]::NewGuid())"
$boardCalls = Join-Path $boardHub 'az-calls.log'

function Invoke-BoardStatus {
    # A child pwsh running the script directly. -AzMode: stub (answers from a table by
    # work item id, records its calls), missing (no az on the machine), signedout.
    param([string]$ArgLine, [string]$OrgStatus = 'active', [string]$AzMode = 'stub', [string]$Org = 'https://dev.azure.com/acme-org')
    if (Test-Path $boardCalls) { Remove-Item $boardCalls -Force }
    $runner = Join-Path $boardHub 'run.ps1'
    $invokePath = $targetScript -replace "'", "''"
    $calls = $boardCalls -replace "'", "''"
    $azStub = switch ($AzMode) {
        'missing' { "`$env:PATH = ''" }
        'signedout' { "function global:az { Add-Content -Path '$calls' -Value ('az ' + (`$args -join ' ')); `$global:LASTEXITCODE = 1 }" }
        default {
            @"
function global:az {
    Add-Content -Path '$calls' -Value ('az ' + (`$args -join ' '))
    if (`$args[0] -eq 'account') { `$global:LASTEXITCODE = 0; return }
    `$id = `$args[4]
    `$states = @{ '141' = 'Active'; '142' = 'Closed'; '143' = 'Resolved'; '144' = 'Committed' }
    if (-not `$states.ContainsKey(`$id)) { `$global:LASTEXITCODE = 1; return }
    `$global:LASTEXITCODE = 0
    return ('{"id":' + `$id + ',"fields":{"System.State":"' + `$states[`$id] + '"}}')
}
"@
        }
    }
    $body = @"
`$global:P20Config = @{
    PromptsRoot   = '$($boardHub -replace "'", "''")'
    PromptsFolder = 'test'
    CommandPrefix = 'zz'
    StoreSync     = 'none'
    Org           = '$Org'
    OrgStatus     = '$OrgStatus'
}
function global:Get-PromptFolders {
    `$root = Join-Path `$global:P20Config.PromptsRoot `$global:P20Config.PromptsFolder
    @{ Current = (Join-Path `$root 'current'); Archive = (Join-Path `$root 'archive') }
}
$azStub
& '$invokePath' $ArgLine
exit `$LASTEXITCODE
"@
    Write-ScratchRunner -Path $runner -Value $body
    $out = & pwsh -NoProfile -File $runner 2>&1 | Out-String
    $azCalls = if (Test-Path $boardCalls) { @(Get-Content $boardCalls) } else { @() }
    return [pscustomobject]@{ Output = $out; ExitCode = $LASTEXITCODE; AzCalls = $azCalls }
}

try {
    $cur = Join-Path $boardHub 'test/current'
    New-Item -ItemType Directory -Path $cur -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $boardHub 'test/archive') -Force | Out-Null
    $link = '**ADO Link:** https://dev.azure.com/acme-org/Proj/_workitems/edit/'
    Write-FixtureText (Join-Path $cur '141-still-open.prompt.md') "# Bug 141: Still open`n`n---`n`n$($link)141"
    Write-FixtureText (Join-Path $cur 'Task142-already-closed.prompt.md') "# Task 142: Already closed`n`n---`n`n$($link)142"
    Write-FixtureText (Join-Path $cur 'Task143-resolved-too.prompt.md') "# Task 143: Resolved too`n`n---`n`n$($link)143"
    Write-FixtureText (Join-Path $cur 'Task144-lane-unknown.prompt.md') "# Task 144: Lane unknown`n`nPR URL: https://dev.azure.com/acme-org/Proj/_git/r/pullrequest/9`n`n---`n`n$($link)144"
    Write-FixtureText (Join-Path $cur 'K7M2-no-work-item.prompt.md') "# Task K7M2: No work item`n`n---`n`n**ADO Link:** (not linked -- created offline with -Title)"
    $before = @(Get-ChildItem $cur -File | Sort-Object Name | ForEach-Object { (Get-FileHash $_.FullName).Hash })

    $r = Invoke-BoardStatus '-Board'
    Assert-True "-Board exits 0" ($r.ExitCode -eq 0) $r.Output
    Assert-True "a current card with an OPEN item shows the board's state and no flag" `
        ($r.Output -match 'Board: Active\s*\r?\n' -and $r.Output -notmatch 'Board: Active \(differs\)') $r.Output
    Assert-True "a current card whose item is Closed is flagged, the row ending (differs)" ($r.Output -match 'Board: Closed \(differs\)\s*\r?\n') $r.Output
    Assert-True "Resolved counts as closed" ($r.Output -match 'Board: Resolved \(differs\)') $r.Output
    Assert-True "a state the product has no mapping for (Committed, beside a PR) is shown, not judged" `
        ($r.Output -match 'Board: Committed\s*\r?\n' -and $r.Output -notmatch 'Committed \(differs\)') $r.Output
    $localBlock = [regex]::Match($r.Output, '(?s)Task K7M2.*?(?=\r?\n\s*\d+\. |\r?\nBoard:|$)').Value
    Assert-True "a card with no work item (a lettered id) has no Board cell" ($localBlock -ne '' -and $localBlock -notmatch 'Board:') $r.Output
    Assert-True "az was asked once per linked card, and never for the local one" `
        (@($r.AzCalls | Where-Object { $_ -match '^az boards work-item show --id \d+ ' }).Count -eq 4 -and -not ($r.AzCalls -match 'K7M2')) ($r.AzCalls -join ' | ')
    Assert-True "the foot counts the mismatches and says what was not read" `
        ($r.Output -match 'Board: 2 of 4 linked card\(s\) differ from the board \(only current/ is read; nothing was written\)') $r.Output
    Assert-True "-Board only ever READS: no az call but account show and boards work-item show" `
        (@($r.AzCalls | Where-Object { $_ -notmatch '^az (account show|boards work-item show) ' }).Count -eq 0) ($r.AzCalls -join ' | ')
    $after = @(Get-ChildItem $cur -File | Sort-Object Name | ForEach-Object { (Get-FileHash $_.FullName).Hash })
    Assert-True "and no card was written" (($before -join ',') -eq ($after -join ',')) ''

    $r = Invoke-BoardStatus '-Board' -OrgStatus 'local'
    Assert-True "-Board with Azure DevOps off is refused (exit 2) naming what is missing" `
        ($r.ExitCode -eq 2 -and $r.Output -match 'Error: -Board: Azure DevOps is off for this Space' -and $r.Output -match 'Hint:') $r.Output
    Assert-True "and az is not asked anything, and no card is listed" ($r.AzCalls.Count -eq 0 -and $r.Output -notmatch 'Active prompts') ($r.AzCalls -join ' | ')

    $r = Invoke-BoardStatus '-Board' -AzMode 'missing'
    Assert-True "-Board with az missing is refused (exit 2) and says so" ($r.ExitCode -eq 2 -and $r.Output -match 'az \(the Azure CLI\) is not installed') $r.Output

    $r = Invoke-BoardStatus '-Board' -AzMode 'signedout'
    Assert-True "-Board with az signed out is refused (exit 2) and says so" ($r.ExitCode -eq 2 -and $r.Output -match 'az is not signed in' -and $r.Output -match 'az login') $r.Output

    $r = Invoke-BoardStatus '-Board' -Org 'https://github.com/acme/widgets'
    Assert-True "-Board on a GitHub board is refused (exit 2) rather than guessing" ($r.ExitCode -eq 2 -and $r.Output -match 'board is GitHub') $r.Output

    # Plain Status is untouched: ADO off, no az on the machine at all, and no refusal.
    $r = Invoke-BoardStatus '' -OrgStatus 'local' -AzMode 'missing'
    Assert-True "plain Status still works with ADO off and no az" ($r.ExitCode -eq 0 -and $r.Output -match '141-still-open' -and $r.Output -match 'K7M2') $r.Output
    Assert-True "and shows no Board column and no summary" ($r.Output -notmatch 'Board:') $r.Output
    $r = Invoke-BoardStatus ''
    Assert-True "plain Status with ADO on never calls az either" ($r.AzCalls.Count -eq 0 -and $r.Output -notmatch 'Board:') ($r.AzCalls -join ' | ')

    # One item the board cannot answer for: shown as unavailable, the rest still read.
    Write-FixtureText (Join-Path $cur 'Task999-gone.prompt.md') "# Task 999: Gone`n`n---`n`n$($link)999"
    $r = Invoke-BoardStatus '-Board'
    Assert-True "an item az cannot read is (unavailable), not a failure of the whole read" ($r.ExitCode -eq 0 -and $r.Output -match 'Board: \(unavailable\)' -and $r.Output -match 'Board: Closed \(differs\)') $r.Output
}
catch {
    Assert-True 'the cases ran to the end without a terminating error' $false $_.Exception.Message
}
finally {
    Remove-Item -Path $boardHub -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host ""

# -- The rule itself: a table, one row per pairing -------------------------------
# Only the two DEFINITE mismatches are flagged. Status reads current/ only, but the
# rule is stated whole, so the archive half is held here and not left to a reader.
. (Join-Path $pkgRoot 'Scripts/Get-WorkItemRecord.ps1')
$mismatchTable = @(
    @('current', 'Active', $false), @('current', 'New', $false), @('current', 'Committed', $false),
    @('current', 'Closed', $true), @('current', 'Done', $true), @('current', 'Removed', $true), @('current', 'Resolved', $true),
    @('archive', 'Closed', $false), @('archive', 'Done', $false), @('archive', 'Removed', $false), @('archive', 'Resolved', $false),
    @('archive', 'Active', $true), @('archive', 'Code Review', $true), @('archive', 'New', $true),
    @('current', '', $false), @('archive', '', $false), @('elsewhere', 'Closed', $false)
)
foreach ($row in $mismatchTable) {
    $got = Get-P20BoardMismatch -Folder $row[0] -State $row[1]
    Assert-True "$($row[0]) + item '$($row[1])' -> $(if ($row[2]) { 'differs' } else { 'not flagged' })" ($got -eq $row[2]) "got $got"
}

# -- Typed as the verb ----------------------------------------------------------
# -- The WIP line (limits.inPlay): a table, one row per input the rule tells apart ----
# A line the product says, never a gate. Scripts/Get-InPlayLine.ps1 is the rule; the
# web board's twin is Board.inPlay.test.tsx and the agent's is test_card_model.py.
. (Join-Path $pkgRoot 'Scripts/Get-InPlayLine.ps1')
Write-Host "In play line (limits.inPlay)" -ForegroundColor Cyan
$inPlayTable = @(
    @{ N = 'unset';                Count = 7; Limit = $null;  Line = '';                Past = $false },
    @{ N = 'zero is no limit';     Count = 7; Limit = 0;      Line = '';                Past = $false },
    @{ N = 'negative is no limit'; Count = 7; Limit = -3;     Line = '';                Past = $false },
    @{ N = 'not a number';         Count = 7; Limit = 'lots'; Line = '';                Past = $false },
    @{ N = 'under';                Count = 4; Limit = 5;      Line = 'in play: 4';      Past = $false },
    @{ N = 'at';                   Count = 5; Limit = 5;      Line = 'in play: 5';      Past = $false },
    @{ N = 'past';                 Count = 7; Limit = 5;      Line = 'in play: 7 of 5'; Past = $true },
    @{ N = 'past, limit as text';  Count = 7; Limit = '5';    Line = 'in play: 7 of 5'; Past = $true },
    @{ N = 'nothing in play';      Count = 0; Limit = 5;      Line = 'in play: 0';      Past = $false }
)
foreach ($row in $inPlayTable) {
    $got = Get-P20InPlayLine -Count $row.Count -Limit $row.Limit
    Assert-True "in play line: $($row.N)" ($got.Line -eq $row.Line -and $got.Past -eq $row.Past) "got '$($got.Line)' past=$($got.Past)"
}
Write-Host ""

# A suite that runs a script directly does not test the verb (AGENTS.md): a fresh
# shell, the package alone on PSModulePath, `az` stubbed, `tkStatus -Board` typed.
$verbRoot = Join-Path ([System.IO.Path]::GetTempPath()) "p20-status-verb-$([guid]::NewGuid().ToString('N').Substring(0, 8))"
try {
    $vPkg = Join-Path $verbRoot 'pkg'; $vHub = Join-Path $verbRoot 'hub'; $vLog = Join-Path $verbRoot 'log'
    New-Item -ItemType Directory -Path $vPkg, $vHub, $vLog -Force | Out-Null
    foreach ($file in @('utilities.psm1', 'config.default.json', 'consts.json')) { Copy-Item (Join-Path $pkgRoot $file) $vPkg -Force }
    Copy-Item (Join-Path $pkgRoot 'Scripts') $vPkg -Recurse -Force
    Copy-Item (Join-Path $pkgRoot 'Config') $vPkg -Recurse -Force
    $hubJson = '{ "hub": 1, "spaces": [ { "slug": "board", "name": "Board", "status": "active", "promptsFolder": "board", "org": "https://dev.azure.com/acme-org" }, { "slug": "mine", "name": "Mine", "status": "local", "promptsFolder": "mine" }, { "slug": "wip", "name": "Wip", "status": "local", "promptsFolder": "wip" } ] }'
    [System.IO.File]::WriteAllText((Join-Path $vHub 'hub.json'), $hubJson, (New-Object System.Text.UTF8Encoding($false)))
    foreach ($f in @('board', 'mine')) { New-Item -ItemType Directory -Path (Join-Path $vHub "$f/current") -Force | Out-Null }
    $card = "# Task 142: Already closed`n`n---`n`n**ADO Link:** https://dev.azure.com/acme-org/Proj/_workitems/edit/142"
    [System.IO.File]::WriteAllText((Join-Path $vHub 'board/current/Task142-already-closed.prompt.md'), $card, (New-Object System.Text.UTF8Encoding($false)))
    [System.IO.File]::WriteAllText((Join-Path $vHub 'mine/current/Task142-already-closed.prompt.md'), $card, (New-Object System.Text.UTF8Encoding($false)))

    # The WIP space: three cards in current/ (every lane counts), two in backlog/ (not counted).
    foreach ($f in @('wip/current', 'wip/backlog')) { New-Item -ItemType Directory -Path (Join-Path $vHub $f) -Force | Out-Null }
    foreach ($n in @('K7M2', 'P4R9', 'T6V3')) {
        [System.IO.File]::WriteAllText((Join-Path $vHub "wip/current/Task$n-in-play.prompt.md"), "# Task ${n}: In play`n", (New-Object System.Text.UTF8Encoding($false)))
    }
    foreach ($n in @('C3D4', 'E5F6')) {
        [System.IO.File]::WriteAllText((Join-Path $vHub "wip/backlog/Task$n-planned.prompt.md"), "# Task ${n}: Planned`n", (New-Object System.Text.UTF8Encoding($false)))
    }

    function Invoke-StatusVerb([string]$Space, [string]$Snippet, $Limit = $null) {
        $local = [ordered]@{ quietStart = $true; promptsRoot = $vHub; activeSpace = $Space }
        if ($null -ne $Limit) { $local['limits'] = [ordered]@{ inPlay = $Limit } }
        [System.IO.File]::WriteAllText((Join-Path $vPkg 'config.local.json'), ($local | ConvertTo-Json -Depth 4), (New-Object System.Text.UTF8Encoding($false)))
        $pkg = $vPkg -replace "'", "''"; $hub = $vHub -replace "'", "''"; $log = $vLog -replace "'", "''"
        $pre = @"
`$env:PSModulePath = '$pkg'
`$env:PROMPTS_ROOT = '$hub'
`$env:P20_USAGE_LOG_DIR = '$log'
Get-ChildItem Env: | Where-Object { `$_.Name -like 'TEAMS_WEBHOOK_*' } | ForEach-Object { Remove-Item "Env:\`$(`$_.Name)" -ErrorAction SilentlyContinue }
function global:az {
    if (`$args[0] -eq 'account') { `$global:LASTEXITCODE = 0; return }
    `$global:LASTEXITCODE = 0
    return '{"id":142,"fields":{"System.State":"Closed"}}'
}
Import-Module '$pkg/utilities.psm1' -Force -DisableNameChecking *>`$null
"@
        $runner = Join-Path $verbRoot ("run-" + [guid]::NewGuid().ToString('N').Substring(0, 8) + ".ps1")
        Write-ScratchRunner -Path $runner -Value ($pre + "`n" + $Snippet + "`n; `"EXIT=`$LASTEXITCODE`"`n") -NoBom
        $out = & pwsh -NoProfile -File $runner 2>&1
        return (($out | ForEach-Object { $_.ToString() }) -join "`n")
    }

    $text = Invoke-StatusVerb 'board' 'tkStatus -Board'
    Assert-True "typed as the verb, tkStatus -Board flags the closed item and exits 0" ($text -match 'Board: Closed \(differs\)' -and $text -match 'EXIT=0') $text
    $text = Invoke-StatusVerb 'mine' 'tkStatus -Board'
    Assert-True "typed as the verb in a local Space, -Board is ONE stated refusal (exit 2)" `
        ($text -match 'EXIT=2' -and $text -match 'Azure DevOps is off for this Space' -and $text -notmatch 'exit code 2') $text
    $text = Invoke-StatusVerb 'mine' 'tkStatus'
    Assert-True "typed as the verb, plain tkStatus in that Space still lists the card" ($text -match 'Already closed' -and $text -notmatch 'Board:' -and $text -match 'EXIT=0') $text
    # The WIP line, typed as the verb: three cards in current/, two in backlog/.
    $text = Invoke-StatusVerb 'wip' 'tkStatus'
    Assert-True "typed as the verb, with no limit set there is no in play line" ($text -notmatch '(?m)^in play:' -and $text -match 'EXIT=0') $text
    $text = Invoke-StatusVerb 'wip' 'tkStatus' 5
    Assert-True "typed as the verb, under the limit the list opens with the bare count (backlog not counted)" `
        ($text -match '(?s)in play: 3\s.*Active prompts \(3\)' -and $text -notmatch 'in play: 3 of' -and $text -match 'EXIT=0') $text
    $text = Invoke-StatusVerb 'wip' 'tkStatus' 3
    Assert-True "typed as the verb, at the limit it is still the bare count" ($text -match 'in play: 3\s' -and $text -notmatch 'in play: 3 of') $text
    $text = Invoke-StatusVerb 'wip' 'tkStatus' 2
    Assert-True "typed as the verb, past the limit it says 'of N' and still lists every card (no gate)" `
        ($text -match 'in play: 3 of 2' -and $text -match 'Active prompts \(3\)' -and $text -match 'EXIT=0') $text
    $text = Invoke-StatusVerb 'board' 'tkStatus -Help'
    Assert-True "-Help names -Board" ($text -match '-Board') $text
}
catch {
    Assert-True 'the cases ran to the end without a terminating error' $false $_.Exception.Message
}
finally {
    Remove-Item -Path $verbRoot -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host ""

# -- Summary ------------------------------------------------------------------

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
