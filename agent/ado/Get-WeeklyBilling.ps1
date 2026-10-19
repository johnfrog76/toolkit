<#
.SYNOPSIS
    Builds a week's billing log from the active Space's cards.
.DESCRIPTION
    Reads the cards in current/ and archive/ of the folder it is given, and
    puts each on every working day from its **Created:** to its **Closed:**
    (or to today while it is open), for the current week, the previous one
    (-LastWeek) or -Since/-Until. Git, where the hub has it, adds the days a
    card was touched and the day it went into review. Outputs one line per
    card per day, with a status word. Output is ASCII-safe and
    copy-pasteable into billing systems.
.NOTES
    Module-private copy: this script belongs to the agent, not to the prompt
    store, and is invoked by path from agent/ado/reporting.py. It is not a CLI
    command and has no alias.
.EXAMPLE
    pwsh -NoProfile -File agent/ado/Get-WeeklyBilling.ps1 -PromptsRoot <hub> -PromptsFolder <folder> -AsJson
.EXAMPLE
    pwsh -NoProfile -File agent/ado/Get-WeeklyBilling.ps1 -PromptsRoot <hub> -PromptsFolder . -LastWeek -AsJson
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [switch]$LastWeek,

    [Parameter(Mandatory = $false)]
    [switch]$Help,

    [Parameter(Mandatory = $false)]
    [Alias('OutputJson')]
    [switch]$AsJson,

    [Parameter(Mandatory = $false)]
    [switch]$Compact,

    [Parameter(Mandatory = $false)]
    [string]$PromptsRoot,

    # The active Space's folder inside the hub, as the CALLER resolved it; '.' (or
    # an empty value) for a Space whose cards sit at the hub root. Required: see
    # below.
    [Parameter(Mandatory = $false)]
    [string]$PromptsFolder,

    [Parameter(Mandatory = $false)]
    [string]$Since,

    [Parameter(Mandatory = $false)]
    [string]$Until
)

function Show-Help {
    Write-Host @"

Get-WeeklyBilling - Build a week's billing log from the cards

USAGE (module-private; invoked by path, not as a CLI command):
    pwsh -NoProfile -File <pkg>/agent/ado/Get-WeeklyBilling.ps1 -PromptsRoot <hub> -PromptsFolder <folder>
    ... -LastWeek    # Previous Monday--Friday
    ... -Since <yyyy-MM-dd> -Until <yyyy-MM-dd>   # Any window; both, or neither
    ... -Compact     # Compact: each day as one line per status group
    ... -AsJson      # Machine-readable; this is what the agent calls

OUTPUT (Normal):
    One line per card per working day it was open.
    Format: {Type} {ID}: {truncated title} ({status})

OUTPUT (Compact):
    Each day, one line per status group (not one summary for the week).
    Format: - {Status}: {Type} {ID}, {Type} {ID}, ...

STATUS VOCABULARY:
    active                 Currently working on it
    code review            PR is open
    resolved               Done, merged or closed
    resolved duplicate     Closed as duplicate
    resolved by design     Closed -- behavior is intentional
    resolved cannot reproduce  Could not repro
    abandoned              Won't fix, descoped, or reassigned
"@
    return
}

if ($Help) { Show-Help; return }

# The CALLER resolves the hub and the active Space; this script resolves neither.
# It used to work the Space out a second time from the package's config files,
# and where the two answers differed -- an activeSpace the shipped list did not
# know, which the agent reads as its first Space and this script read as the hub
# root; or a Space chosen for the agent alone -- Daily billed a different folder
# from the one the rest of the page showed. The agent passes both, always.
if (-not $PSBoundParameters.ContainsKey('PromptsFolder')) {
    [Console]::Error.WriteLine("-PromptsFolder is required: the active Space's folder inside the hub, or . for a Space whose cards sit at the hub root.")
    exit 2
}
# '.' is the hub root. An empty argument is the same answer, but Windows
# PowerShell 5.1 drops one from a child's command line, so the agent sends '.'.
$folderPrefix = if ($PromptsFolder -eq '.') { '' } else { $PromptsFolder }
$pfx = if ($folderPrefix) { "$folderPrefix/" } else { '' }

# The work item types are read from the package's two config files -- the one
# thing this script still takes from them -- merged below, config.local.json last.
# agent/ado -> agent -> package root.
$pkgRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$cfgDefault = Join-Path $pkgRoot 'config.default.json'
$cfgLocal = Join-Path $pkgRoot 'config.local.json'
$defaults = $null; $local = $null
# -Encoding UTF8: Windows PowerShell 5.1 reads the machine's code page by default,
# and the shipped file is UTF-8 with no BOM -- a type's label is free text.
if (Test-Path $cfgDefault) { $defaults = Get-Content -LiteralPath $cfgDefault -Raw -Encoding UTF8 | ConvertFrom-Json }
if (-not (Get-Command Read-P20LocalConfigJson -ErrorAction SilentlyContinue)) { . (Join-Path $pkgRoot 'Scripts/Write-ConfigParseWarning.ps1') }
$local = Read-P20LocalConfigJson -Path $cfgLocal
if (-not $PromptsRoot -or -not (Test-Path $PromptsRoot)) {
    # Stated on stderr and exit 2: the agent puts the sentence in the response's
    # `error`, and Daily shows it. It used to `return` with exit 0, so a missing
    # hub and a quiet week were the same answer.
    [Console]::Error.WriteLine("-PromptsRoot is missing or does not exist: '$PromptsRoot'")
    exit 2
}
# The LONG path. A Windows 8.3 short name (`C:\Users\<name>~1.<domain>\...`) passes
# Test-Path and fails Push-Location -- which then failed quietly, exited 0 and
# reported an empty week as if nothing had been done. Get-Item is the one call
# that expands it; then the hub is entered once, here, so a hub that cannot be
# entered is a stated failure and never a quiet one.
#
$promptsRoot = (Get-Item -LiteralPath $PromptsRoot).FullName
try {
    Push-Location -LiteralPath $promptsRoot -ErrorAction Stop
    Pop-Location
}
catch {
    [Console]::Error.WriteLine("Cannot enter the hub at '$promptsRoot': $($_.Exception.Message)")
    exit 2
}
if (($Since -and -not $Until) -or ($Until -and -not $Since)) {
    # Half a window used to be ignored in silence and the current week billed.
    [Console]::Error.WriteLine("-Since and -Until go together: pass both (YYYY-MM-DD), or neither for this week.")
    exit 2
}

# -- Determine week boundary -------------------------------------------------

$today = (Get-Date).Date
$dayOfWeek = [int]$today.DayOfWeek
# Monday = 1 in .NET DayOfWeek (Sunday = 0)
if ($dayOfWeek -eq 0) { $daysBack = 6 } else { $daysBack = $dayOfWeek - 1 }
$thisMonday = $today.AddDays(-$daysBack)

if ($Since -and $Until) {
    $startDate = [datetime]::Parse($Since)
    $endDate = [datetime]::Parse($Until)
}
elseif ($LastWeek) {
    $startDate = $thisMonday.AddDays(-7)
    $endDate = $thisMonday.AddDays(-1)  # Friday
}
else {
    $startDate = $thisMonday
    $endDate = $today
}

$sinceStr = $startDate.ToString('yyyy-MM-dd')
# IMPORTANT: git interprets bare dates using the current wall-clock time,
# NOT midnight. Append explicit times for deterministic results.
# ONE clock for the day and the window: the AUTHOR's instant, read as the local
# day. git's --since/--until filter on the COMMITTER's date, which Sync's
# `pull --rebase` resets to the moment of the sync -- so a Friday commit synced
# on Monday was outside this week's window. The window git applies is widened
# by a week, and each commit is kept or dropped below by its own local day
$gitUntilStr = $endDate.AddDays(7).ToString('yyyy-MM-dd') + 'T23:59:59'
$endDayStr = $endDate.ToString('yyyy-MM-dd')
$clockScript = Join-Path (Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) 'Scripts') 'ConvertTo-LocalDay.ps1'
if (-not (Test-Path -LiteralPath $clockScript)) {
    # As loud as the other two below: without it no commit has a day at all.
    [Console]::Error.WriteLine("Get-WeeklyBilling: ConvertTo-LocalDay.ps1 is missing from $(Split-Path $clockScript -Parent) -- this package is incomplete.")
    exit 1
}
. $clockScript

# -- Collect git log ----------------------------------------------------------

# Widen the git log window: go back further to catch items that started before
# this week but should carry forward into it.
$lookbackStr = $startDate.AddDays(-14).ToString('yyyy-MM-dd') + 'T00:00:00'

Push-Location -LiteralPath $promptsRoot -ErrorAction Stop
try {
    # Include commit subject (%s) in output to avoid per-commit git log -1 calls later.
    # --relative: git names a path from the REPOSITORY's root, and every pattern
    # below is anchored at the hub's. A hub kept in a subfolder of a repository
    # matched nothing and lost every day git knows. (`git grep` and `git ls-tree`
    # already answer relative to the working directory.)
    # The active org's own folders and nothing else. The hub ROOT's current/ and
    # archive/ used to be searched too, for a layout from before orgs had folders;
    # a card at the root then lent its git days to any org card of the same name.
    $pathArgs = @("${pfx}current/", "${pfx}archive/")
    $logLines = git log --relative --name-status --format="COMMIT:%H %at%nSUBJECT:%s" --since="$lookbackStr" --until="$gitUntilStr" -- @pathArgs 2>$null
}
finally {
    Pop-Location
}

# NO early return when git has nothing to say. This script used to BE
# `git log`, so a hub that is not a repository -- a first-class case by this
# tool's own design, and what a first run has just made -- had no billing at all.
# The cards decide now (see "The cards themselves decide", below); git enriches.
$script:BillingHasGit = [bool]$logLines

# -- Build work days list -----------------------------------------------------

$workDays = @()
$d = $startDate
while ($d -le $endDate) {
    if ($d.DayOfWeek -ne 'Saturday' -and $d.DayOfWeek -ne 'Sunday') {
        $workDays += $d.ToString('yyyy-MM-dd')
    }
    $d = $d.AddDays(1)
}

# -- The one id rule ------------------------------------------------------------
# Both passes below -- the history's view and the cards themselves -- read an id
# through Scripts/Resolve-CardName.ps1 (docs/hub/cards.md, "The filename"), so they cannot
# disagree about what a card is.
$pkgScripts = Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) 'Scripts'
foreach ($needed in @('Get-Consts.ps1', 'Resolve-CardName.ps1', 'Get-PromptFileStatus.ps1')) {
    # LOUDLY. Without the id rule every file reads as "not a card" and the week
    # comes out empty -- a timesheet that says nothing was done is the worst
    # possible way for a broken install to show itself.
    if (-not (Test-Path -LiteralPath (Join-Path $pkgScripts $needed))) {
        [Console]::Error.WriteLine("Get-WeeklyBilling: $needed is missing from $pkgScripts -- this package is incomplete.")
        exit 1
    }
}
. (Join-Path $pkgScripts 'Get-Consts.ps1')
. (Join-Path $pkgScripts 'Resolve-CardName.ps1')
# The one reader of **Billable:** (Test-P20CardBillable), shared with the standup.
. (Join-Path $pkgScripts 'Get-PromptFileStatus.ps1')
# The CONFIGURED types, the machine's own included: a team that files `Chore-Q4TN-...`
# said so in config, and a card the id rule cannot read is a card that is never billed.
# Both files are merged key by key; config.local.json wins, as it does everywhere else.
$typeTable = New-Object psobject
foreach ($source in @($defaults, $local)) {
    if ($source -and $source.workItemTypes) {
        foreach ($prop in $source.workItemTypes.PSObject.Properties) {
            $typeTable | Add-Member -NotePropertyName $prop.Name -NotePropertyValue $prop.Value -Force
        }
    }
}
$cardPattern = Get-P20CardIdPattern -WorkItemTypes (Get-P20WorkItemTypes -Config ([pscustomobject]@{ WorkItemTypes = $typeTable }))

# -- Parse commits into item timeline ----------------------------------------

# itemInfo: card id (a string: 141 or K7M2) -> { type, title, fileName, firstSeen, resolvedDate, status, commitDays }
$itemInfo = @{}

# Queued (hash, path) pairs for the post-loop batch PR-URL check (git grep).
$pendingPrChecks = [System.Collections.Generic.List[pscustomobject]]::new()

$currentCommitDate = $null
$currentCommitHash = $null
$currentSubject = $null
$currentCommitArchived = @{}  # track files archived via D+M overwrite in current commit

# Commits the TOOLKIT makes for mechanical reasons are not work. Sync refreshes
# every card's package links after a pull and commits "sync: refresh package
# links after a move"; Backfill-CardStamps.ps1's changes are committed as
# "backfill: ...". Both touch cards nobody worked on -- dozens at a time, archived
# ones included -- and each touched card used to be billed, and an
# archived one was then carried forward as "code review" for up to fourteen
# workdays.
# Matched on the subject the tool itself writes. "auto-commit before sync" is NOT
# here on purpose: that commit carries the engineer's own uncommitted work.
$mechanicalSubject = '^(sync: refresh package links|backfill:)'
$skipCommit = $false
# The org's folder as a literal in the patterns below (a folder name may hold a dot).
$rxPfx = [regex]::Escape($pfx)

foreach ($line in $logLines) {
    if ($line -match '^COMMIT:(\w+)\s+(\d+)\s*$') {
        $currentCommitHash = $Matches[1]
        $currentCommitDate = ConvertTo-P20LocalDay $Matches[2]
        $currentSubject = $null
        $currentCommitArchived = @{}
        # Authored after the week (git's window runs a week longer; see above).
        $skipCommit = (-not $currentCommitDate) -or ($currentCommitDate -gt $endDayStr)
        continue
    }

    if ($line -match '^SUBJECT:(.*)') {
        $currentSubject = $Matches[1]
        $skipCommit = $skipCommit -or ($currentSubject -match $mechanicalSubject)
        continue
    }

    if (-not $currentCommitDate) { continue }
    if ($skipCommit) { continue }

    # Parse git status lines: M, A, D, R### (rename)
    $isArchive = $false
    $isReopen = $false
    $isAddToCurrent = $false
    $fileName = $null

    if ($line -match "^R\d*\s+${rxPfx}current/(.+?\.prompt\.md)\s+${rxPfx}archive/(.+?\.prompt\.md)") {
        $fileName = $Matches[2]   # destination (archive/) name carries round suffix for multi-round archives
        $isArchive = $true
    }
    elseif ($line -match "^R\d*\s+${rxPfx}archive/(.+?\.prompt\.md)\s+${rxPfx}current/") {
        $fileName = $Matches[1]
        $isReopen = $true
    }
    elseif ($line -match "^A\s+${rxPfx}archive/(.+?\.prompt\.md)") {
        # File added directly to archive (never committed in current/) -- treat as resolved
        $fileName = $Matches[1]
        $isArchive = $true
    }
    elseif ($line -match "^A\s+${rxPfx}current/(.+?\.prompt\.md)") {
        # Fresh file written to current/ by the new-prompt verb. This is either the
        # initial creation or a reopen of a previously archived card -- in both
        # cases the item is live in current/ on this date. Flag it so a same-day
        # archive event (processed later, git log being newest-first) cannot
        # overwrite the active status or pin a stale ResolvedDate. Unlike the
        # `R archive/ -> current/` rename reopen, there is no archive source to
        # rename from, so this is the only signal that the card came back.
        $fileName = $Matches[1]
        $isAddToCurrent = $true
    }
    elseif ($line -match "^[MA]\s+${rxPfx}(?:current|archive)/(.+?\.prompt\.md)") {
        $fileName = $Matches[1]
        # Skip M archive/ lines when the same file was already handled as an
        # archive event (D current/ + M archive/ overwrite) in this commit.
        if ($line -match "^[MA]\s+${rxPfx}archive/" -and $currentCommitArchived[$fileName]) {
            continue
        }
    }
    elseif ($line -match "^D\s+${rxPfx}current/(.+?\.prompt\.md)") {
        # Deleted from current/ without a rename to archive/ in the same commit.
        # Check if the file existed in archive/ at this commit (not on disk today),
        # so a plain delete (e.g., cleanup) isn't confused with an archive event.
        $fileName = $Matches[1]
        Push-Location -LiteralPath $promptsRoot -ErrorAction Stop
        try {
            $archiveAtCommit = git ls-tree "$currentCommitHash" "${pfx}archive/$fileName" 2>$null
        }
        finally { Pop-Location }
        if ($archiveAtCommit) {
            $isArchive = $true
            $currentCommitArchived[$fileName] = $true
        }
    }
    else {
        continue
    }

    # Extract work item ID
    $workItemId = Get-P20CardId -Name $fileName -Pattern $cardPattern
    if (-not $workItemId) { continue }   # not a card

    # D current/ that is NOT an archive = file was deleted (cleanup, not resolved).
    # Mark item so older events from a previous lifecycle are ignored.
    if ($line -match '^D\s+' -and -not $isArchive -and -not $isReopen) {
        if ($itemInfo.ContainsKey($workItemId)) {
            $itemInfo[$workItemId].DeletionSeen = $true
        }
        continue
    }

    # Skip events older than a known deletion (they belong to a previous lifecycle)
    if ($itemInfo.ContainsKey($workItemId) -and $itemInfo[$workItemId].DeletionSeen) {
        continue
    }

    # Initialize item if first time seeing it
    if (-not $itemInfo.ContainsKey($workItemId)) {
        # Git's view carries days only. A card's type and title come from the card
        # itself, in the pass below ("The cards themselves decide").
        $itemInfo[$workItemId] = @{
            FileName         = $fileName
            FirstSeen        = $currentCommitDate
            ResolvedDate     = $null
            ResolvedStateSet = $false
            DeletionSeen     = $false
            CommitDays       = @{}
            ReopenDays       = @{}
        }
    }

    # Git log is newest-first, so update FirstSeen to the earliest commit date
    if ($currentCommitDate -lt $itemInfo[$workItemId].FirstSeen) {
        $itemInfo[$workItemId].FirstSeen = $currentCommitDate
    }

    # Track commit days and events - queue for batch PR-URL detection below.
    # Archive/reopen events set their own status; only plain M/A commits need the check.
    if (-not $itemInfo[$workItemId].CommitDays.ContainsKey($currentCommitDate)) {
        $itemInfo[$workItemId].CommitDays[$currentCommitDate] = 'active'  # placeholder
        if (-not $isArchive -and -not $isReopen) {
            # THIS commit's own path, not the item's newest name: after a
            # re-archive the item is X-r2 and `current/X-r2...` never existed, so
            # git grep found nothing and every review day read "active".
            #
            $pendingPrChecks.Add([pscustomobject]@{
                ItemId   = $workItemId
                Date     = $currentCommitDate
                Hash     = $currentCommitHash
                FileName = $fileName
            })
        }
    }

    if ($isArchive) {
        $resolveStatus = 'resolved'
        # Use commit subject from the enriched git log format (no extra git call needed)
        if ($currentSubject -match 'duplicate') { $resolveStatus = 'resolved duplicate' }
        elseif ($currentSubject -match 'by design|by-design') { $resolveStatus = 'resolved by design' }
        elseif ($currentSubject -match 'cannot reproduce|unable to reproduce|can''t reproduce') { $resolveStatus = 'resolved cannot reproduce' }
        elseif ($currentSubject -match 'abandon') { $resolveStatus = 'abandoned' }
        # Git log is newest-first: only the first (most recent) archive/reopen
        # event should determine ResolvedDate. Older events must not overwrite.
        if (-not $itemInfo[$workItemId].ResolvedStateSet) {
            $itemInfo[$workItemId].ResolvedDate = $currentCommitDate
            $itemInfo[$workItemId].ResolvedStateSet = $true
        }
        # Archive overrides content-based status, unless a newer reopen on the
        # same date already marked it (accidental archive -> restore same day).
        if (-not $itemInfo[$workItemId].ReopenDays.ContainsKey($currentCommitDate)) {
            $itemInfo[$workItemId].CommitDays[$currentCommitDate] = $resolveStatus
        }
    }
    elseif ($isReopen -or $isAddToCurrent) {
        # Reopen, either via `R archive/ -> current/` rename or a fresh
        # `A current/` add (new prompt). Git log is newest-first, so if this
        # is the most recent resolved-state event the item is currently live and
        # not resolved; ResolvedStateSet then blocks any older archive from
        # pinning a stale ResolvedDate.
        if (-not $itemInfo[$workItemId].ResolvedStateSet) {
            $itemInfo[$workItemId].ResolvedDate = $null
            $itemInfo[$workItemId].ResolvedStateSet = $true
        }
        # Mark this date so an older same-day archive commit won't override.
        # Don't overwrite CommitDays - the per-commit content detection (queued
        # above) from a newer sync commit on the same day is more accurate.
        $itemInfo[$workItemId].ReopenDays[$currentCommitDate] = $true
    }
}

# -- Batch PR-URL detection (replaces N git-show calls with 2 git-grep calls a batch) --
# git grep searches across multiple commit hashes in one process invocation.
# Output format: "<hash>:<path>" for each file that matches.
if ($pendingPrChecks.Count -gt 0) {
    # In BATCHES, each under a character budget. One call carried every hash and
    # every path, and Windows refuses a command line past 32,767 characters --
    # behind `2>$null`, so a long week would have lost every review day without
    # a word. A batch holds whole hashes with only THEIR paths, so the
    # answer does not depend on where a batch ends. P20_BILLING_GREP_BUDGET
    # exists for the suite, which shrinks it to one hash a batch and asserts the
    # same week comes back.
    $budget = 16000
    if ($env:P20_BILLING_GREP_BUDGET -match '^\d+$') { $budget = [int]$env:P20_BILLING_GREP_BUDGET }
    $batches = @()
    $batchHashes = @(); $batchPaths = @{}; $batchLen = 0
    foreach ($group in @($pendingPrChecks | Group-Object -Property Hash)) {
        $paths = @($group.Group | ForEach-Object {
            $fn = $_.FileName
            "${pfx}current/$fn"; "${pfx}archive/$fn"
        } | Sort-Object -Unique)
        $len = $group.Name.Length + 1 + (($paths | ForEach-Object { $_.Length + 1 } | Measure-Object -Sum).Sum)
        if ($batchHashes.Count -gt 0 -and ($batchLen + $len) -gt $budget) {
            $batches += , @{ Hashes = $batchHashes; Paths = @($batchPaths.Keys) }
            $batchHashes = @(); $batchPaths = @{}; $batchLen = 0
        }
        $batchHashes += $group.Name
        foreach ($pth in $paths) { $batchPaths[$pth] = $true }
        $batchLen += $len
    }
    if ($batchHashes.Count -gt 0) { $batches += , @{ Hashes = $batchHashes; Paths = @($batchPaths.Keys) } }

    $grepLines = @()
    Push-Location -LiteralPath $promptsRoot -ErrorAction Stop
    try {
        foreach ($b in $batches) {
            $hs = $b.Hashes; $ps = $b.Paths
            $grepLines += @(git grep -l "^PR URL:[[:space:]]*https://" @hs -- @ps 2>$null)
            $grepLines += @(git grep -l "Merged PR"           @hs -- @ps 2>$null)
        }
    }
    finally { Pop-Location }

    $prUrlHits = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($gl in $grepLines) { if ($gl) { $prUrlHits.Add($gl) | Out-Null } }

    foreach ($chk in $pendingPrChecks) {
        # Skip if a later pass (archive/reopen) already set a definitive status.
        if ($itemInfo[$chk.ItemId].CommitDays[$chk.Date] -ne 'active') { continue }
        $fn   = $chk.FileName
        $hash = $chk.Hash
        $hit  = $prUrlHits.Contains("${hash}:${pfx}current/$fn")  -or
                $prUrlHits.Contains("${hash}:${pfx}archive/$fn")
        if ($hit) { $itemInfo[$chk.ItemId].CommitDays[$chk.Date] = 'code review' }
    }
}

# -- The cards themselves decide ------------------------------------------------
# Everything above is git's VIEW: which files commits touched, and when. It is
# kept, as enrichment -- but it no longer decides what is billed.
#
#   - The item list is the CARD FILES in current/ and archive/, read by the one id
#     rule (Scripts/Resolve-CardName.ps1). A file that is not a card is never
#     billed; a card with a lettered id (K7M2) is; a hub with no git is billed.
#   - A card is open from **Created:** to **Closed:**, and a card in current/ is
#     open to today. File LOCATION is the final authority.
#   - Git adds the days a card was actually touched and the day it entered code
#     review -- kept only INSIDE the card's own interval, so a mechanical commit, a
#     folder move or a rewritten history cannot bill a card on a day it was not open.
#   - **Billable:** no takes a card off the timesheet. No line means billable.
$billingConsts = Get-P20Consts
$createdRx = '(?m)^' + [regex]::Escape($billingConsts.stamps.created) + '\s*(\d{4}-\d{2}-\d{2})'
$closedRx = '(?m)^' + [regex]::Escape($billingConsts.stamps.closed) + '\s*(\d{4}-\d{2}-\d{2})'
$prUrlRx = $billingConsts.regex.prUrlLine
# A person's own tokens: the day a card was moved by hand -- Move -To InProgress
# writes **Started:**, -To CodeReview writes **Review:** -- read the way git's
# days are, so the rule "the cards decide" is true of a person's lines too.
#
$startedRx = $billingConsts.regex.startedLine + '\s*(\d{4}-\d{2}-\d{2})'
$reviewRx = $billingConsts.regex.reviewLine + '\s*(\d{4}-\d{2}-\d{2})'

# -- A weekend is billed on the Monday after ----------------------------------
# Only weekdays render, so a Saturday **Closed:** used to vanish: active Thursday
# and Friday, then gone. Time is submitted on Friday before 5pm --
# The owner's rule: "Friday before 5pm, so following week" -- so a weekend event
# cannot go on the week already sent. Every day a card contributes is folded
# before any window check: Saturday and Sunday become the Monday after.
function ConvertTo-BillingDay {
    param([string]$Day)
    if (-not $Day) { return $Day }
    $dt = [datetime]::ParseExact($Day, 'yyyy-MM-dd', [System.Globalization.CultureInfo]::InvariantCulture)
    if ($dt.DayOfWeek -eq 'Saturday') { return $dt.AddDays(2).ToString('yyyy-MM-dd') }
    if ($dt.DayOfWeek -eq 'Sunday') { return $dt.AddDays(1).ToString('yyyy-MM-dd') }
    return $Day
}
# When a weekend day folds onto one that already has a word, the further one wins.
$foldRank = @{ 'active' = 1; 'code review' = 2 }
function Get-FoldRank { param([string]$Status) if ($foldRank.ContainsKey($Status)) { return $foldRank[$Status] } if ($Status) { return 3 } return 0 }

$gitByFile = @{}
foreach ($g in $itemInfo.Values) { if ($g.FileName) { $gitByFile[$g.FileName] = $g } }
$itemInfo = @{}
$script:BillingNonBillable = 0
$script:BillingUnstamped = 0
$todayStr = (Get-Date).ToString('yyyy-MM-dd')

foreach ($where in @('current', 'archive')) {
    $dir = Join-Path $promptsRoot "${pfx}$where"
    if (-not (Test-Path -LiteralPath $dir)) { continue }
    foreach ($f in (Get-ChildItem -LiteralPath $dir -Filter '*.prompt.md' -File -ErrorAction SilentlyContinue)) {
        $cardId = Get-P20CardId -Name $f.Name -Pattern $cardPattern
        if (-not $cardId) { continue }   # not a card
        $text = [System.IO.File]::ReadAllText($f.FullName)
        $git = $gitByFile[$f.Name]

        $created = if ($text -match $createdRx) { $Matches[1] } elseif ($git) { $git.FirstSeen } else { $null }
        $closed = $null
        if ($where -eq 'archive') {
            $closed = if ($text -match $closedRx) { $Matches[1] } elseif ($git -and $git.ResolvedDate) { $git.ResolvedDate } else { $null }
        }
        $created = ConvertTo-BillingDay $created
        $closed = ConvertTo-BillingDay $closed
        # No date anywhere: it cannot be placed on a calendar. Counted, never guessed.
        if (-not $created -or ($where -eq 'archive' -and -not $closed)) { $script:BillingUnstamped++; continue }
        # Outside the window altogether: closed before it, or opened after it.
        if ($closed -and $closed -lt $sinceStr) { continue }
        if ($created -gt $endDate.ToString('yyyy-MM-dd')) { continue }
        if (-not (Test-P20CardBillable $text)) { $script:BillingNonBillable++; continue }

        # Type and title from the H1 -- the record of a card's type (spec 5.0).
        $heading = if ($text -match '(?m)^#\s+(.+)$') { $Matches[1].Trim() } else { $f.BaseName }
        $heading = $heading -replace '^[^\p{L}\p{N}]+', ''
        $type = 'Bug'; $title = $heading
        if ($heading -match '^(?i)(User Story|Task|Feature|Bug|Spike|[A-Za-z]+)\s+\S+\s*:\s*(.+)$') {
            # Both captures are read BEFORE anything else matches: a second -match
            # replaces $Matches, which is how every User Story lost its title.
            $type = $Matches[1]; $title = $Matches[2]
            if ($type -ieq 'User Story') { $type = 'US' }
        }
        $title = ($title -replace '\[.*?\]\s*:?\s*', '').Trim()
        if ($title.Length -gt 70) { $title = $title.Substring(0, 67).TrimEnd() + ' ...' }

        # Git's days, kept only inside the card's own interval.
        $days = @{}
        if ($git) {
            foreach ($rawDay in $git.CommitDays.Keys) {
                $cd = ConvertTo-BillingDay $rawDay
                if ($cd -lt $created) { continue }
                if ($closed -and $cd -gt $closed) { continue }
                $st = $git.CommitDays[$rawDay]
                if (-not $days.ContainsKey($cd) -or (Get-FoldRank $st) -gt (Get-FoldRank $days[$cd])) { $days[$cd] = $st }
            }
        }
        # The person's own lines, inside the card's interval like git's days.
        if ($text -match $startedRx) {
            $startedOn = ConvertTo-BillingDay $Matches[1]
            if ($startedOn -ge $created -and (-not $closed -or $startedOn -le $closed) -and -not $days.ContainsKey($startedOn)) { $days[$startedOn] = 'active' }
        }
        $reviewOn = $null
        if ($text -match $reviewRx) {
            $reviewOn = ConvertTo-BillingDay $Matches[1]
            if ($reviewOn -ge $created -and (-not $closed -or $reviewOn -le $closed)) {
                if (-not $days.ContainsKey($reviewOn) -or $days[$reviewOn] -eq 'active') { $days[$reviewOn] = 'code review' }
            }
            else { $reviewOn = $null }
        }
        if ($closed) {
            # The closing day is "resolved" -- git's more specific word if it has one.
            if (-not $days.ContainsKey($closed) -or $days[$closed] -notmatch '^(resolved|abandoned)') { $days[$closed] = 'resolved' }
        }
        elseif (($text -match $prUrlRx) -and -not $reviewOn -and -not ($days.Values | Where-Object { $_ -eq 'code review' })) {
            # In review, and neither git nor the card can say since when: today is the one day known.
            $days[(ConvertTo-BillingDay $todayStr)] = 'code review'
        }

        # One card, one line. A re-archived round (-r2) shares its id with the card
        # it came back as; the interval that reaches furthest into the window wins.
        if ($itemInfo.ContainsKey($cardId) -and $itemInfo[$cardId].FirstSeen -gt $created) { continue }
        $itemInfo[$cardId] = @{
            Type = $type; Title = $title; FileName = $f.Name
            FirstSeen = $created; ResolvedDate = $closed; CommitDays = $days
        }
    }
}

# -- Build daily output with carry-forward ------------------------------------

# Filter out items whose files were deleted (not on disk in current/ or archive/)
Push-Location -LiteralPath $promptsRoot -ErrorAction Stop
try {
    $deletedIds = @()
    foreach ($entry in $itemInfo.GetEnumerator()) {
        $fn = $entry.Value.FileName
        if (-not (Test-Path "${pfx}current/$fn") -and -not (Test-Path "${pfx}archive/$fn")) {
            $deletedIds += $entry.Key
        }
        # Safety net: a file live in current/ cannot be resolved. The parse loop
        # already clears ResolvedDate for add-based reopens (see $isAddToCurrent),
        # but guard the invariant here so any stale ResolvedDate can't drop a live
        # item from carry-forward (line ~463). Truly resolved items live in
        # archive/, never current/, so this cannot re-activate a closed item.
        elseif ($entry.Value.ResolvedDate -and (Test-Path "${pfx}current/$fn")) {
            $entry.Value.ResolvedDate = $null
        }
    }
    foreach ($did in $deletedIds) { $itemInfo.Remove($did) }
}
finally { Pop-Location }

# For each work day, an item appears if:
#   1. It had a commit that day (use that day's status), OR
#   2. It was first seen on or before this day AND not yet resolved (carry forward)

$dailyActivity = @{}

foreach ($dayStr in $workDays) {
    $dailyActivity[$dayStr] = @{}

    foreach ($entry in $itemInfo.GetEnumerator()) {
        $id = $entry.Key
        $info = $entry.Value
        $firstSeen = $info.FirstSeen
        $resolvedDate = $info.ResolvedDate

        # Was there a commit on this specific day?
        if ($info.CommitDays.ContainsKey($dayStr)) {
            $dailyActivity[$dayStr][$id] = @{
                Type   = $info.Type
                Title  = $info.Title
                Status = $info.CommitDays[$dayStr]
            }
            continue
        }

        # Carry-forward: item is in flight (first seen <= today, not resolved yet or resolved later)
        if ($firstSeen -le $dayStr) {
            # Skip if resolved before this day
            if ($resolvedDate -and $resolvedDate -lt $dayStr) { continue }
            # For items first seen before this week AND resolved before this week,
            # require week activity to avoid showing stale ancient items.
            # Items resolved THIS week are always relevant - carry them forward.
            if ($firstSeen -lt $sinceStr -and $resolvedDate -and $resolvedDate -lt $sinceStr) {
                $hasWeekActivity = $false
                foreach ($cd in $info.CommitDays.Keys) {
                    if ($cd -ge $sinceStr -and $cd -le $dayStr) { $hasWeekActivity = $true; break }
                }
                if (-not $hasWeekActivity) { continue }
            }

            # Carry-forward: use status from the most recent commit day
            $carryStatus = 'active'
            $latestDay = $null
            foreach ($cd in $info.CommitDays.Keys) {
                if ($cd -le $dayStr -and (-not $latestDay -or $cd -gt $latestDay)) {
                    $latestDay = $cd
                }
            }
            if ($latestDay) { $carryStatus = $info.CommitDays[$latestDay] }

            $dailyActivity[$dayStr][$id] = @{
                Type   = $info.Type
                Title  = $info.Title
                Status = $carryStatus
            }
        }
    }
}

# -- ASCII-safe output --------------------------------------------------------

function ConvertTo-Ascii {
    param([string]$Text)
    $Text = $Text -replace '[\u2018\u2019\u0060\u00B4]', "'"    # smart single quotes
    $Text = $Text -replace '[\u201C\u201D]', '"'                  # smart double quotes
    $Text = $Text -replace '[\u2013\u2014]', '--'                 # en/em dash
    $Text = $Text -replace '\u2026', '...'                        # ellipsis
    $Text = $Text -replace '[\u00C6\u00E6]', 'ae'                # ligatures
    $Text = $Text -replace '[\u00D4\u00F4]', 'o'                 # circumflex o
    $Text = $Text -replace '[^\x20-\x7E]', ''                    # strip remaining non-ASCII
    return $Text
}

# -- Render -------------------------------------------------------------------

$sortedDates = $dailyActivity.Keys | Sort-Object

# "Nothing to bill" is one answer, not five empty days: the days exist whether or
# not any card was open on them, now that the week is built from the cards.
$anyBilled = @($dailyActivity.Values | Where-Object { $_.Count -gt 0 }).Count -gt 0
if ($sortedDates.Count -eq 0 -or -not $anyBilled) {
    if ($AsJson) {
        @{ days = @(); raw = 'No activity found.'; compact = ''; source = $(if ($script:BillingHasGit) { 'stamps+git' } else { 'stamps' }); nonBillable = [int]$script:BillingNonBillable; unstamped = [int]$script:BillingUnstamped } | ConvertTo-Json -Depth 5 -Compress
    }
    else {
        Write-Host "No billable activity found for the week of $sinceStr." -ForegroundColor Yellow
    }
    return
}

$statusOrder = @{ 'active' = 0; 'code review' = 1;
    'resolved' = 3; 'resolved duplicate' = 3;
    'resolved by design' = 3; 'resolved cannot reproduce' = 3;
    'abandoned' = 4
}

function ConvertTo-StatusLabel {
    param([string]$Status)
    return ($Status -split ' ' | ForEach-Object {
            $_.Substring(0, 1).ToUpper() + $_.Substring(1)
        }) -join ' '
}

# -- Build per-day (normal) output --------------------------------------------

$output = @()
$compactOutput = @()
$jsonDays = @()

foreach ($dateStr in $sortedDates) {
    $dt = [datetime]::Parse($dateStr)
    $dayLabel = "$($dt.ToString('M/d')) $($dt.DayOfWeek)"
    $output += $dayLabel

    $items = $dailyActivity[$dateStr]
    # An id is a STRING: a work item number sorts as a number, a lettered id
    # (K7M2) after them by name. `[int]$_.Key` threw a non-terminating error onto
    # stderr for every lettered card and the script carried on as if it had not.
    $sortedItems = $items.GetEnumerator() | Sort-Object {
        $s = $statusOrder[$_.Value.Status]; if ($null -eq $s) { 9 } else { $s }
    }, { if ("$($_.Key)" -match '^\d+$') { [long]$_.Key } else { [long]::MaxValue } }, { "$($_.Key)" }

    $dayRawLines = @($dayLabel)
    $dayJsonItems = @()

    foreach ($entry in $sortedItems) {
        $id = $entry.Key
        $info = $entry.Value
        $line = "  - $($info.Type) $id`: $(ConvertTo-Ascii $info.Title) ($($info.Status))"
        $output += $line
        $dayRawLines += "`t- $($info.Type) $id`: $(ConvertTo-Ascii $info.Title) ($($info.Status))"
        $dayJsonItems += @{ id = $id; type = $info.Type; title = (ConvertTo-Ascii $info.Title); status = $info.Status }
    }
    $output += ''

    # -- Build compact lines for this day (group items by status) --
    $dayStatusGroups = @{}
    foreach ($entry in $sortedItems) {
        $id = $entry.Key
        $info = $entry.Value
        $s = $info.Status
        if (-not $dayStatusGroups.ContainsKey($s)) { $dayStatusGroups[$s] = @() }
        $dayStatusGroups[$s] += "$($info.Type) $id"
    }
    $dayCompactLines = @($dayLabel)
    $sortedDayStatuses = $dayStatusGroups.Keys | Sort-Object {
        $s = $statusOrder[$_]; if ($null -eq $s) { 9 } else { $s }
    }
    foreach ($s in $sortedDayStatuses) {
        $members = $dayStatusGroups[$s] | Sort-Object
        $dayCompactLines += "- $(ConvertTo-StatusLabel $s): $($members -join ', ')"
    }
    $compactOutput += $dayCompactLines
    $compactOutput += ''
    $dayCompactRaw = ($dayCompactLines -join "`n")

    $jsonDays += @{
        date        = $dateStr
        day_name    = $dayLabel
        items       = $dayJsonItems
        raw         = ($dayRawLines -join "`n")
        compact_raw = $dayCompactRaw
    }
}

$normalResult = ($output -join "`n").TrimEnd()
$compactResult = ($compactOutput -join "`n").TrimEnd()

# -- Output -------------------------------------------------------------------

if ($AsJson) {
    @{ days = $jsonDays; raw = $normalResult; compact = $compactResult; source = $(if ($script:BillingHasGit) { 'stamps+git' } else { 'stamps' }); nonBillable = [int]$script:BillingNonBillable; unstamped = [int]$script:BillingUnstamped } | ConvertTo-Json -Depth 5 -Compress
    return
}

$result = if ($Compact) { $compactResult } else { $normalResult }

Write-Host $result

# Copy to clipboard
try {
    $result | Set-Clipboard
    Write-Host "`n[Copied to clipboard]" -ForegroundColor Green
}
catch {
    # Clipboard not available in all environments
    $null = $_
}
