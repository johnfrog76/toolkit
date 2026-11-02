<#
.SYNOPSIS
    Scans current/ and prints a list of active prompts with status and last-modified date.
.DESCRIPTION
    For each file in current/, extracts the title from the H1 heading,
    counts checklist progress (checked vs total checkboxes), and shows
    the last git-committed or filesystem-modified date.
.EXAMPLE
    {cliPrefix}Status
.EXAMPLE
    {cliPrefix}Status -Board
.EXAMPLE
    {cliPrefix}Status -Help
#>
[CmdletBinding()]
param(
    # OPT-IN, READ-ONLY: also ask the board for each linked card's work item state
    # and show it beside the card's own. Plain Status never contacts ADO, and this
    # never writes anywhere -- the file stays the source of truth (docs/CLI.md,
    # "The two can disagree, and nothing notices").
    [Parameter(Mandatory = $false)]
    [switch]$Board,

    [Parameter(Mandatory = $false)]
    [switch]$Help
)

. (Join-Path $PSScriptRoot 'Initialize-CliFallbacks.ps1')


$cfg = $global:P20Config
$promptsRoot = $cfg.PromptsRoot
# Test-P20HubRoot and the one "hub not found" sentence live here, and this file
# is dot-sourced rather than reached through the module because this script also
# runs with no module in the session (a test sandbox, `pwsh -File`).
. (Join-Path $PSScriptRoot 'Resolve-HubConfig.ps1')
# The state machine's vocabulary and its two patterns are a CONTRACT, not this
# script's private business: agent/core/parsers.py holds the same derivation and
# the web sorts and colours by the same four strings. They come from
# consts.json, through the one reader both a module session and a bare
# `pwsh -File` can reach.
. (Join-Path $PSScriptRoot 'Get-Consts.ps1')
. (Join-Path $PSScriptRoot 'ConvertTo-LocalDay.ps1')
. (Join-Path $PSScriptRoot 'Invoke-TrackerRead.ps1')
. (Join-Path $PSScriptRoot 'Get-InPlayLine.ps1')
$script:Consts = Get-P20Consts
if (-not (Test-P20HubRoot $promptsRoot)) {
    Write-CliError -Message (Get-P20HubMissingMessage $promptsRoot)
    exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
}

function Show-Help {
    Write-Host @"

Get-P20PromptStatus - Show active prompts in current/

USAGE:
    $(Get-CliPrefix)Status          # Print status table
    $(Get-CliPrefix)Status -Board   # ...and the board's state for each linked card (read-only)
    $(Get-CliPrefix)Status -Help    # Show this help

OUTPUT COLUMNS:
    File          Filename (truncated if long)
    Title         H1 heading from the prompt file
    Sprint        Sprint path from footer (last segment only)
    Progress      Checked / total checkboxes (or -- if none)
    Modified      Last modified date (git commit date, or filesystem fallback)
    Status        Active | In Progress | Code Review
    Board         With -Board: the work item's System.State, for a card linked to one

With limits.inPlay set ({cliPrefix}Config -Set limits.inPlay=5), the list opens with one line: "in play: 4" at or
under the number, "in play: 7 of 5" past it. The count is every card in current/ -- Active, In Progress and Code
Review -- and never the backlog/. It is a line the product says, not a gate: nothing refuses and nothing is hidden.
Unset, there is no line.

After the cards in play, the backlog/ -- cards planned, not yet in play -- is
folded to one line: how many, and their names. Move <id> -To Active, a card's
first ThreadHash or its NewPR pulls it into current/.

-Board asks Azure DevOps once per linked card and writes nothing -- not to the
board, not to a card. It flags only definite mismatches, with "(differs)": a card
in archive/ whose item is still open, or a card in current/ whose item is Closed,
Done, Removed or Resolved. Status lists current/ only, so only the second can be
seen here. Every other pairing is shown, not judged. A card with no
work item (K7M2) has no Board cell. With Azure DevOps off for this Space, or az
missing or signed out, -Board refuses and plain Status still works.
"@
    return
}

if ($Help) { Show-Help; return }

. (Join-Path $PSScriptRoot 'Get-PromptFileStatus.ps1')

# -- -Board: can the board be asked at all? ------------------------------------
# Refused HERE, before a card is read, as a stated refusal (exit 2): the SWITCH is
# refused and plain Status is untouched. The answer names what is missing.
if ($Board) {
    . (Join-Path $PSScriptRoot 'Test-AdoEnabled.ps1')
    . (Join-Path $PSScriptRoot 'Resolve-Tracker.ps1')
    . (Join-Path $PSScriptRoot 'Get-WorkItemRecord.ps1')
    . (Join-Path $PSScriptRoot 'Resolve-CardName.ps1')
    . (Join-Path $PSScriptRoot 'Invoke-TrackerRead.ps1')
    $adoFlag = $null
    if (Get-Command Get-P20Features -ErrorAction SilentlyContinue) {
        $features = Get-P20Features
        if ($features -and $features.ContainsKey('ado')) { $adoFlag = $features['ado'] }
    }
    $boardRefusal = $null
    $boardHint = $null
    $boardTracker = Resolve-P20Tracker -OrgUrl $cfg.Org
    # A GitHub board is named first: Azure DevOps reads off there BECAUSE the
    # tracker is GitHub, and the sentence should say that, not "off".
    if ($boardTracker -eq 'github') {
        $boardRefusal = "This Space's board is GitHub, and -Board reads Azure DevOps work items."
        $boardHint = 'Plain Status shows the cards; GitHub issues are not joined.'
    }
    elseif (-not (Test-P20AdoEnabled -OrgStatus $cfg.OrgStatus -Flag $adoFlag -Tracker $boardTracker)) {
        $boardRefusal = 'Azure DevOps is off for this Space, so there is no board to read.'
        $boardHint = "Switch to a Space whose status is active, or set features.ado: $(Get-CliPrefix)Config -Set features.ado=true"
    }
    elseif (-not $cfg.Org) {
        $boardRefusal = 'This Space has no board address (org), so there is no board to read.'
        $boardHint = "Set it in hub.json, or switch Space: $(Get-CliPrefix)Config -Set activeSpace=<slug>"
    }
    elseif (-not (Get-Command az -ErrorAction SilentlyContinue)) {
        $boardRefusal = 'az (the Azure CLI) is not installed, so the board cannot be read.'
        $boardHint = 'Install it from https://aka.ms/installazurecli, then az login.'
    }
    else {
        if ((Invoke-P20TrackerRead 'az' @('account', 'show', '--output', 'none')).Code -ne 0) {
            $boardRefusal = 'az is not signed in, so the board cannot be read.'
            $boardHint = 'Run: az login'
        }
    }
    if ($boardRefusal) {
        Write-CliError -Message "-Board: $boardRefusal" -Hint $boardHint
        exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
    }
    $boardIdPattern = Get-P20CardIdPattern -WorkItemTypes (Get-P20WorkItemTypes -Config $cfg)
}

$folders = Get-PromptFolders
$currentDir = $folders.Current

# -- The backlog: planned, not in play -----------------------------------------
# Listed AFTER the cards in play, folded to a count and the names -- the ledger is
# still the cards in play, and a planned card is a footnote to it until Move
# -To Active, its first ThreadHash or its NewPR pulls it into current/.
. (Join-Path $PSScriptRoot 'Move-CardFolder.ps1')
$backlogDir = Get-P20BacklogFolder -Folders $folders
$backlogNames = @()
if ($backlogDir -and (Test-Path -LiteralPath $backlogDir)) {
    $backlogList = New-Object 'System.Collections.Generic.List[string]'
    foreach ($b in @(Get-ChildItem -LiteralPath $backlogDir -File | Where-Object { $_.Name -notlike '.*' })) { $backlogList.Add($b.Name) }
    # Ordinal, for the same reason the ledger's sort is: one order on every host.
    $backlogList.Sort([System.StringComparer]::Ordinal)
    $backlogNames = $backlogList.ToArray()
}
$writeBacklog = {
    if ($backlogNames.Count -eq 0) { return }
    Write-Host "$($script:Consts.status.backlog) ($($backlogNames.Count)), planned -- not in play:" -ForegroundColor Cyan
    Write-Host "  $($backlogNames -join ', ')" -ForegroundColor DarkGray
    Write-Host "  $(Get-CliPrefix)Move <id> -To Active pulls one into play; so does its first commit (ThreadHash) or PR (NewPR)." -ForegroundColor DarkGray
    Write-Host ""
}

# -- The WIP line: opens the list when limits.inPlay is set -------------------------
# Said, never enforced (Scripts/Get-InPlayLine.ps1). Past the number it is amber.
$inPlayLimit = $null
if ($cfg) { $inPlayLimit = $cfg.InPlayLimit }   # the config is a hashtable: a missing key reads $null
$writeInPlay = {
    param([int]$Count)
    $inPlay = Get-P20InPlayLine -Count $Count -Limit $inPlayLimit
    if (-not $inPlay.Line) { return }
    $colour = 'Cyan'
    if ($inPlay.Past) { $colour = 'Yellow' }
    Write-Host "`n$($inPlay.Line)" -ForegroundColor $colour
}

if (-not (Test-Path $currentDir)) {
    & $writeInPlay 0
    if ($backlogNames.Count -gt 0) {
        Write-Host "`nNo active prompts in current/." -ForegroundColor Yellow
        Write-Host ""
        & $writeBacklog
        return
    }
    Write-Warning "prompt folder not found at $currentDir"
    return
}

# Not sorted here -- there is exactly one ordering point, below, and a first
# sort whose result the second one discards was the whole bug.
$files = Get-ChildItem -Path $currentDir -File |
Where-Object { $_.Name -notlike '.*' }
if ($files.Count -eq 0) {
    & $writeInPlay 0
    Write-Host "No active prompts in current/." -ForegroundColor Yellow
    if ($backlogNames.Count -gt 0) { Write-Host ""; & $writeBacklog }
    return
}

# -- The day each card last changed: ONE git log for current/ ------------------
# Not one `git log -1` per card: git log is newest first, so the first time a
# file is named is its last change, and one call answers every card. The agent's
# twin is agent/core/git_history.py (folder_changes), and
# Tests/fixtures/status-modified/ holds the two halves to one day per card.
#
# The hub need not be a git repository: outside one the log exits 128 and there
# is no map, so every card reads its filesystem date below -- one failed process,
# where there used to be a probe, and before that one 128 per card (the LAST of
# which was what the command left behind; see the reset after the loop).
#
# Each commit opens with a marker line, '@@<epoch>' (%at, read as the LOCAL day,
# the same rule as the agent): a card's file name cannot take that shape, and
# no NUL has to travel through a Windows PowerShell 5.1 pipe.
#
# A name outside ASCII comes back in git's own quoted spelling --
# "caf\303\251.md", octal UTF-8 bytes -- and is unquoted here. That keeps the
# whole read ASCII, so it does not depend on the console code page a native
# command's output is decoded with (an OEM page on Windows would turn a raw
# UTF-8 name into another name, and the card would silently read its mtime).
# The agent decodes UTF-8 itself and asks for the raw name; the fixture's
# non-ASCII row holds the two to one answer. The map is ordinal, as the
# agent's dict is: two names that differ only in case are two cards.
$unquoteGitPath = {
    param([string]$Name)
    if ($Name.Length -lt 2 -or -not ($Name.StartsWith('"') -and $Name.EndsWith('"'))) { return $Name }
    $inner = $Name.Substring(1, $Name.Length - 2)
    $bytes = New-Object 'System.Collections.Generic.List[byte]'
    $utf8 = New-Object System.Text.UTF8Encoding($false)
    $escapes = @{ 'a' = 7; 'b' = 8; 't' = 9; 'n' = 10; 'v' = 11; 'f' = 12; 'r' = 13; '"' = 34; '\' = 92 }
    $i = 0
    while ($i -lt $inner.Length) {
        $c = $inner[$i]
        if ($c -eq '\' -and ($i + 3) -lt $inner.Length -and $inner.Substring($i + 1, 3) -match '^[0-7]{3}$') {
            $bytes.Add([Convert]::ToByte($inner.Substring($i + 1, 3), 8)); $i += 4; continue
        }
        if ($c -eq '\' -and ($i + 1) -lt $inner.Length -and $escapes.ContainsKey([string]$inner[$i + 1])) {
            $bytes.Add([byte]$escapes[[string]$inner[$i + 1]]); $i += 2; continue
        }
        $bytes.AddRange([byte[]]$utf8.GetBytes([string]$c)); $i++
    }
    return $utf8.GetString($bytes.ToArray())
}
$cardDays = New-Object 'System.Collections.Generic.Dictionary[string,string]' ([System.StringComparer]::Ordinal)
Push-Location $currentDir
try {
    $gitLog = Invoke-P20TrackerRead 'git' @('-c', 'core.quotepath=on', 'log', '--format=@@%at', '--name-only', '--relative', '--', '.')
    if ($gitLog.Code -eq 0) {
        $logDay = $null
        foreach ($logLine in $gitLog.Out) {
            $logLine = "$logLine".Trim()
            if (-not $logLine) { continue }
            if ($logLine -match '^@@(\d+)$') { $logDay = ConvertTo-P20LocalDay $Matches[1]; continue }
            $logLine = & $unquoteGitPath $logLine
            # A file directly in current/ only, and its FIRST naming is its last change.
            if ($logDay -and $logLine -notmatch '/' -and -not $cardDays.ContainsKey($logLine)) {
                $cardDays[$logLine] = $logDay
            }
        }
    }
}
catch { $cardDays.Clear() }
finally { Pop-Location }

$rows = @()
foreach ($file in $files) {
    $content = Get-Content $file.FullName -Raw -ErrorAction SilentlyContinue
    if (-not $content) { $content = '' }

    # Title from first H1
    $title = ''
    if ($content -match '(?m)^#\s+(.+)') {
        $title = $Matches[1].Trim()
        # Strip leading emoji or work item type prefixes for brevity
        $title = $title -replace '^[\p{So}\p{Sk}]\s*', ''
        if ($title.Length -gt 60) { $title = $title.Substring(0, 57) + '...' }
    }

    # Checklist progress
    $checked = ([regex]::Matches($content, '(?m)^\s*-\s*\[x\]')).Count
    $total = ([regex]::Matches($content, '(?m)^\s*-\s*\[[x ]\]')).Count
    if ($total -gt 0) {
        $progress = "$checked/$total"
    }
    else {
        $progress = '--'
    }

    # ADO Link from footer (the one reader, Get-PromptFileStatus.ps1)
    $adoUrl = Get-P20CardAdoUrl $content

    # PR URL from PR Review Comments section
    $prUrl = ''
    # The TOKEN is the contract; capturing the URL after it is this script's own.
    if ($content -match ('(?m)^' + [regex]::Escape($script:Consts.tokens.prUrl) + '\s*(https://\S+)')) {
        $prUrl = $Matches[1].Trim()
    }

    # Sprint from footer - take last path segment (e.g. "Search Coach\Sprint 4" -> "Sprint 4")
    $sprint = '--'
    if ($content -match '(?m)^\*\*Sprint:\*\*\s*(.+)') {
        $sprintRaw = $Matches[1].Trim()
        $segments = $sprintRaw -split '[/\\]'
        $sprint = $segments[-1].Trim()
        if ($sprint.Length -gt 20) { $sprint = $sprint.Substring(0, 18) + '..' }
    }

    # Last modified -- the folder's git log, else the filesystem: a hub that is
    # not a repository, or a card the log never named (new, not yet committed).
    if ($cardDays.ContainsKey($file.Name)) {
        $modified = $cardDays[$file.Name]
    }
    else {
        $modified = $file.LastWriteTime.ToString('yyyy-MM-dd')
    }

    $status = Get-PromptFileStatus $content

    # -Board: the work item's state, for a card linked to one. A card with no work
    # item (a lettered id, or no https ADO Link) has no row on the board and no
    # Board cell. Once per card, read-only. Flags only the one definite mismatch
    # Status can see -- a card still in current/ whose item is closed.
    $boardState = $null
    $boardDiffers = $false
    if ($Board) {
        $cardId = Get-P20CardId -Name $file.Name -Pattern $boardIdPattern
        if ((Test-P20IsWorkItemId $cardId) -and $adoUrl) {
            $record = Get-P20WorkItemRecord -Id $cardId -Org $cfg.Org
            if ($record.Ok -and $record.State) {
                $boardState = $record.State
                $boardDiffers = Get-P20BoardMismatch -Folder $script:Consts.folders.current -State $record.State
            }
            else { $boardState = '(unavailable)' }
        }
    }

    $rows += [PSCustomObject]@{
        File     = $file.Name
        # The store is its own repo and is never the terminal's working
        # directory -- you run this from the app repo you are coding in. A bare
        # file name is therefore not openable from anywhere: a terminal
        # resolves it against the cwd and finds nothing. Print the full path so
        # ctrl+click lands in the editor.
        Path     = $file.FullName
        Title    = $title
        Sprint   = $sprint
        Progress = $progress
        Modified = $modified
        AdoUrl   = $adoUrl
        PrUrl    = $prUrl
        Status   = $status
        Board    = $boardState
        Differs  = $boardDiffers
    }
}

# A card with no git history is a HANDLED case, not a failure: git's exit code
# has been read and answered, and what this command leaves behind must describe
# THIS command. Reset unconditionally -- the one log above is a native call,
# and on a hub that is not a repository it leaves 128 by itself.
$global:LASTEXITCODE = 0

# ONE sort, by (state, file name), and neither half may depend on the host.
#
# Two host differences meet here, and each on its own made the printed order --
# the numbering a user reads to pick a card -- a fact about which shell they
# opened:
#
#   * Sort-Object is NOT stable on Windows PowerShell 5.1 and IS on 7. With
#     every card Active the state keys all tie, so 5.1 rotated the list: the
#     same hub printed 114, 137, 141, Task139, US-119, US-142 in pwsh and
#     Task139, US-119, US-142, 114, 137, 141 in powershell.exe. Reduced:
#     `1..6 | % { [pscustomobject]@{K=1} } | Sort-Object { $_.K }` gives
#     4 5 6 1 2 3 on 5.1. -Stable is not an option; it does not exist there.
#   * Sort-Object compares strings with the CURRENT CULTURE, and 5.1 resolves
#     that through .NET Framework's NLS tables while 7 uses ICU. A tie-break on
#     a culture-aware comparison would have swapped one host difference for a
#     quieter one.
#
# So: an explicit comparison, ordinal on the file name, over a List<object> --
# Sort-Object cannot be given a comparer on 5.1. The agent's GET /status sorts
# by the same pair with Python's ordinal string order, so the CLI and the web
# number the same hub the same way (Tests/Test-Status.ps1 and
# Tests/test_parsers.py pin both sides).
#
# Why file name: docs/CLI.md ("The workflow") fixes the order of the STATE checks and says
# nothing about the order of cards within a state, so the file name is the only
# key the reader can predict -- and it is what the listing prints.
$statusOrder = @{
    $script:Consts.status.active     = 0
    $script:Consts.status.inProgress = 1
    $script:Consts.status.codeReview = 2
}
$ordered = New-Object 'System.Collections.Generic.List[object]'
foreach ($r in $rows) { $ordered.Add($r) }
$ordered.Sort([System.Comparison[object]] {
        param($a, $b)
        $ra = 99; if ($statusOrder.ContainsKey($a.Status)) { $ra = $statusOrder[$a.Status] }
        $rb = 99; if ($statusOrder.ContainsKey($b.Status)) { $rb = $statusOrder[$b.Status] }
        if ($ra -ne $rb) { return $ra.CompareTo($rb) }
        return [string]::CompareOrdinal($a.File, $b.File)
    })
# .ToArray(), not @($ordered): wrapping a List[object] in the array
# subexpression operator throws "Argument types do not match" here.
$rows = $ordered.ToArray()

& $writeInPlay $rows.Count
Write-Host "`nActive prompts ($($rows.Count)):" -ForegroundColor Cyan
Write-Host ""
$i = 0
foreach ($row in $rows) {
    $i++
    Write-Host "  $i. $($row.Title)" -ForegroundColor White
    Write-Host "     File:     $($row.Path)" -ForegroundColor DarkGray
    $statusLine = "     Sprint:   $($row.Sprint)   Progress: $($row.Progress)   Modified: $($row.Modified)   Status: $($row.Status)"
    $lineColour = 'DarkGray'
    if ($Board -and $row.Board) {
        $statusLine += "   Board: $($row.Board)"
        if ($row.Differs) { $statusLine += ' (differs)'; $lineColour = 'Yellow' }
    }
    Write-Host $statusLine -ForegroundColor $lineColour
    if ($row.AdoUrl) {
        Write-Host "     ADO:      $($row.AdoUrl)" -ForegroundColor DarkGray
    }
    if ($row.PrUrl) {
        Write-Host "     PR:       $($row.PrUrl)" -ForegroundColor DarkGray
    }
    Write-Host ""
}

& $writeBacklog

# -Board's one-line summary. It says what was NOT read, too: Status lists current/
# only, so the other definite mismatch -- an archived card whose item is still
# open -- cannot be seen from here.
if ($Board) {
    $checked = @($rows | Where-Object { $_.Board -and $_.Board -ne '(unavailable)' }).Count
    $differs = @($rows | Where-Object { $_.Differs }).Count
    $unavailable = @($rows | Where-Object { $_.Board -eq '(unavailable)' }).Count
    $summary = "Board: $differs of $checked linked card(s) differ from the board (only current/ is read; nothing was written)."
    if ($unavailable -gt 0) { $summary += " $unavailable could not be read." }
    Write-Host $summary -ForegroundColor $(if ($differs -gt 0) { 'Yellow' } else { 'DarkGray' })
    Write-Host ""
}
