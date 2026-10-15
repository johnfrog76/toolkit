<#
.SYNOPSIS
    Write a work-review scaffold for a date range from local history.
.DESCRIPTION
    Walks the hub's card folders -- archive/, current/ and the hub-root growth
    folder, whose name hub.json declares --
    for markdown committed between StartDate and EndDate, reads each file's
    title, sprint and checklist progress, and writes
    <promptsRoot>/reviews/<slug-set>/<year>/<start>_<end>/review.md.

    Nothing leaves the machine: this is git history and files on disk, and the
    output is a scaffold, not prose. Turning it into prose is a separate pass --
    agentic/generate-review.prompt.md is the instruction for that.

    The JSON on stdout is what the agent's POST /api/review/generate returns, so
    this script never prints anything else on the success path.
.PARAMETER StartDate
    Start of the review period (YYYY-MM-DD).
.PARAMETER EndDate
    End of the review period (YYYY-MM-DD).
.PARAMETER Slugs
    Comma-joined org slugs to include. Omit for the active Space alone. The output
    folder is the SORTED set joined by '+', so "second,first" and "first,second"
    write to the same place.
.PARAMETER Help
    Show usage information.
.EXAMPLE
    {cliPrefix}NewWorkReview -StartDate <yyyy-mm-dd> -EndDate <yyyy-mm-dd>
.EXAMPLE
    {cliPrefix}NewWorkReview -StartDate <yyyy-mm-dd> -EndDate <yyyy-mm-dd> -Slugs "first,second"
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$StartDate,

    [Parameter(Mandatory = $false)]
    [string]$EndDate,

    [Parameter(Mandatory = $false)]
    [string]$Slugs,

    [switch]$Help
)

if (-not (Get-Command Get-CliPrefix -ErrorAction SilentlyContinue)) {
    function Get-CliPrefix {
        if ($global:P20Config -and $global:P20Config.CommandPrefix) { return $global:P20Config.CommandPrefix }
        return ''
    }
}

function Show-Help {
    $p = Get-CliPrefix
    Write-Host ""
    Write-Host "  $($p)NewWorkReview - write a review scaffold from local history" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  USAGE:" -ForegroundColor Yellow
    Write-Host "    $($p)NewWorkReview -StartDate 2026-01-01 -EndDate 2026-04-18"
    Write-Host "    $($p)NewWorkReview -StartDate 2026-01-01 -EndDate 2026-04-18 -Slugs 'first,second'"
    Write-Host ""
    Write-Host "  PARAMETERS:" -ForegroundColor Yellow
    Write-Host "    -StartDate   start of the period (YYYY-MM-DD)"
    Write-Host "    -EndDate     end of the period   (YYYY-MM-DD)"
    Write-Host "    -Slugs       comma-joined org slugs; omit for the active Space"
    Write-Host ""
    Write-Host "  OUTPUT:" -ForegroundColor Yellow
    Write-Host "    reviews/<slug-set>/<year>/<start>_<end>/$($script:Consts.reviews.fileName), and JSON on stdout:"
    Write-Host "    { review, file_path, files_scanned, files_included }"
    Write-Host ""
    return
}

if ($Help) { Show-Help; return }
if (-not $StartDate -or -not $EndDate) {
    Write-Host "ERROR: -StartDate and -EndDate are required." -ForegroundColor Red
    Show-Help
    return
}

# -- Validate dates ----------------------------------------------------------

$datePattern = '^\d{4}-\d{2}-\d{2}$'
if ($StartDate -notmatch $datePattern -or $EndDate -notmatch $datePattern) {
    @{ error = "Dates must be YYYY-MM-DD format" } | ConvertTo-Json
    return
}
if ($StartDate -gt $EndDate) {
    @{ error = "StartDate must be before or equal to EndDate" } | ConvertTo-Json
    return
}

# -- Resolve paths -----------------------------------------------------------
# The hub root comes from Get-P20PromptsRoot and from nothing else -- env first,
# then config. The $cfg block below is still needed for the ORG list and the
# active org's folder, which this script also runs without a module to read.

$cfg = $global:P20Config
# When running as a subprocess (no module loaded), load config from files
if (-not $cfg) {
    $repoRoot = Split-Path -Parent $PSScriptRoot
    $cfgDefault = Join-Path $repoRoot 'config.default.json'
    $cfgLocal = Join-Path $repoRoot 'config.local.json'
    $defaults = $null; $local = $null
    # The container's keys in both spellings (ConvertTo-P20SpaceKeys, stage 2).
    . (Join-Path $PSScriptRoot 'Resolve-HubConfig.ps1')
    if (Test-Path $cfgDefault) { $defaults = ConvertTo-P20SpaceKeys (Get-Content $cfgDefault -Raw | ConvertFrom-Json) }
    if (-not (Get-Command Read-P20LocalConfigJson -ErrorAction SilentlyContinue)) { . (Join-Path $PSScriptRoot 'Write-ConfigParseWarning.ps1') }
    $local = ConvertTo-P20SpaceKeys (Read-P20LocalConfigJson -Path $cfgLocal)
    $spaces = if ($defaults.spaces) { @($defaults.spaces) } else { @() }
    # The environment's stand-in first, as the module and the agent read it.
    $activeSlug = Get-P20ActiveSpaceOverride
    if (-not $activeSlug) { $activeSlug = if ($local.activeSpace) { $local.activeSpace } elseif ($defaults.activeSpace) { $defaults.activeSpace } else { '' } }
    $activeSlug = Resolve-P20RenamedSlug -Slug ([string]$activeSlug) -Slugs @($spaces | ForEach-Object { [string]$_.slug })
    $activeSpace = $spaces | Where-Object { $_.slug -eq $activeSlug } | Select-Object -First 1
    $cfg = [PSCustomObject]@{
        PromptsFolder = if ($activeSpace) { $activeSpace.promptsFolder } else { '' }
        PromptsRoot   = if ($local.promptsRoot) { $local.promptsRoot } elseif ($defaults.promptsRoot) { $defaults.promptsRoot } else { '' }
        Spaces          = $spaces
    }
}

# If Orgs not present on cfg (e.g. set from module), load from config files
if (-not ($cfg | Get-Member -Name 'Orgs' -MemberType Properties -ErrorAction SilentlyContinue) -or $null -eq $cfg.Spaces) {
    $repoRoot2 = Split-Path -Parent $PSScriptRoot
    $cfgDefault2 = Join-Path $repoRoot2 'config.default.json'
    $defaults2 = $null
    . (Join-Path $PSScriptRoot 'Resolve-HubConfig.ps1')
    if (Test-Path $cfgDefault2) { $defaults2 = ConvertTo-P20SpaceKeys (Get-Content $cfgDefault2 -Raw | ConvertFrom-Json) }
    $cfg | Add-Member -NotePropertyName 'Orgs' -NotePropertyValue (@($defaults2.spaces)) -Force
}
# Dot-sourced HERE rather than below, because the root has to be resolved before
# anything is joined onto it.
. (Join-Path $PSScriptRoot 'Resolve-HubConfig.ps1')
# reviews/<slug-set>/<year>/<start>_<end>/<fileName> is a layout agent/ado/reporting.py
# reads back. The file name and the slug-set separator come from consts.json.
. (Join-Path $PSScriptRoot 'Get-Consts.ps1')
. (Join-Path $PSScriptRoot 'Write-CardText.ps1')
. (Join-Path $PSScriptRoot 'Invoke-TrackerRead.ps1')
$script:Consts = Get-P20Consts
$promptsRoot = Get-P20PromptsRoot -PackageRoot (Split-Path -Parent $PSScriptRoot)
if (-not $promptsRoot -or -not (Test-Path $promptsRoot)) {
    @{ error = "PromptsRoot not configured" } | ConvertTo-Json
    return
}

# Hub-root folder NAMES are the hub's, not this script's: hub.json's "folders"
# block can rename either of these. Resolve-HubConfig.ps1 is the single reader of
# that, dot-sourced because this script also runs with no module in session.
#
# Two names, two jobs. $reviewsFolder is where the review is WRITTEN.
# $growthFolder is a folder the scan READS, and its name is therefore also a
# pathspec the git log is walked with -- but never a grouping key: see
# Get-ItemKind below. Resolve-HubConfig.ps1 is dot-sourced above, with the root.
$hubFolders = Get-P20HubFolderNames -PromptsRoot $promptsRoot
$reviewsFolder = $hubFolders['reviews']
$growthFolder = $hubFolders['growth']

# Path -> KIND. The review groups, labels and orders its sections by kind --
# 'archive', 'current', 'growth' -- and a kind is a display contract, not a
# folder name. Renaming growth/ in hub.json must move the scan without producing
# a group nothing has a label for, which is what keying on the raw first path
# segment would have done.
function Get-ItemKind {
    param([string]$Segment)
    if ($Segment -eq $growthFolder) { return 'growth' }
    return $Segment
}

# -- Which cards belong to a window: the card's own dates, not git's ------------
# A card used to be in a review if a COMMIT touched it inside the
# window. That is not the same as having worked on it. One reorganisation commit
# (moving a Space's cards into its own folder) touched every card, so a
# review of that Space for one month selected all of them -- dozens closed
# the month before -- and an eleven-day review counted every card. A link
# refresh or a stamp backfill does the same to every month it lands in. And a hub that is not a git
# repository had no reviews at all.
#
# A card carries **Created:** and **Closed:** (consts.json, `stamps`), and
# Scripts/Backfill-CardStamps.ps1 gave them to the cards that predate them. So:
#
#   a card is in a window when it was OPEN at some point in it --
#   Created on or before the end, and not Closed before the start.
#
# Only a card with no Created stamp falls back to git ("touched in the window"),
# so nothing a hub's history could find is lost. On the real hub the two agree
# exactly for a full year, in an active Space and an archived one; they differ where git
# is wrong.
function Get-P20StampDate {
    param([string]$Content, [string]$Stamp)
    if ($Content -match ('(?m)^' + [regex]::Escape($Stamp) + '\s*(\d{4}-\d{2}-\d{2})')) { return $Matches[1] }
    return $null
}

function Test-P20CardInWindow {
    <#
        $true / $false from the card's own dates, or $null when it has no
        Created stamp and the caller must ask git instead. ISO dates compare
        correctly as strings.
    #>
    param([string]$Created, [string]$Closed, [string]$Start, [string]$End)
    if (-not $Created) { return $null }
    if ($Created -gt $End) { return $false }
    if ($Closed -and ($Closed -lt $Start)) { return $false }
    return $true
}

# -- Resolve slug list --------------------------------------------------------
# If -Slugs not supplied, fall back to single active org (backward compat).

$selectedSlugs = @()
if ($Slugs -and $Slugs.Trim() -ne '') {
    $selectedSlugs = @($Slugs -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' } | Sort-Object)
}
else {
    # Single active org -- identical to prior behaviour
    $singleSlug = if ($cfg -and $cfg.PromptsFolder) { $cfg.PromptsFolder } else { 'default' }
    $selectedSlugs = @($singleSlug)
}

# Build the output slug-set string (sorted asc, joined by the contract's separator)
$slugSetStr = ($selectedSlugs | Sort-Object) -join $script:Consts.reviews.slugSetSeparator

Push-Location $promptsRoot
try {
    # -- Per-slug scan loop --------------------------------------------------
    # For each selected slug run the scan (including the legacy-path fallback)
    # and accumulate paths.  Dedup across slugs with a HashSet.

    # IMPORTANT: git interprets bare dates using the current wall-clock time,
    # NOT midnight. Use explicit T00:00:00 / T23:59:59 for deterministic results.
    $afterDate = ([datetime]::Parse($StartDate)).AddDays(-1).ToString("yyyy-MM-dd") + "T23:59:59"
    $beforeDate = ([datetime]::Parse($EndDate)).AddDays(1).ToString("yyyy-MM-dd") + "T00:00:00"

    $allPaths = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $stampSelected = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

    foreach ($slug in $selectedSlugs) {
        # Look up the org config to get its promptsFolder
        $spaceEntry = $null
        if ($cfg.Spaces) {
            $spaceEntry = @($cfg.Spaces) | Where-Object { $_.slug -eq $slug } | Select-Object -First 1
        }
        $folderPrefix = if ($spaceEntry -and $spaceEntry.promptsFolder) { $spaceEntry.promptsFolder } else { $slug }

        # The hub's folders, and only the hub's. A card lives under the org's
        # promptsFolder; growth/ is a hub-root sibling and belongs to the
        # engineer rather than to any one org, which is why it is scanned
        # unprefixed as well.
        $baseFolders = @("archive/", "current/", "$growthFolder/")
        $scanFolders = if ($folderPrefix) {
            # Both the prefixed and the bare path, once per slug. A hub whose
            # history predates the per-org folders still has cards at the root,
            # and a past range must stay reproducible after the move -- the bare
            # paths are what keeps git's rename history reachable.
            ($baseFolders | ForEach-Object { "$folderPrefix/$_" }) + $baseFolders
        }
        else { $baseFolders }

        # Through the tracker-read helper: under Windows PowerShell 5.1 a native
        # call redirected 2>&1 throws on its first stderr line when the CALLER's
        # preference is 'Stop', and a hub that is not a repository answers on stderr.
        $gitRun = Invoke-P20TrackerRead 'git' (@('log', '--name-only', '--format=', "--after=$afterDate", "--before=$beforeDate", '--') + @($scanFolders))
        $gitOutput = $gitRun.Lines

        # On a hub that is not a repository git answers with an error line, not
        # with paths; nothing in it ends .md, so the filter below leaves nothing.
        # A dotfile is not a work item: an editor's stray ".US-316614-...prompt.md"
        # sat in a real archive/ and was listed as completed work.
        $gitPaths = @($gitOutput | Where-Object { $_ -and "$_".Trim() -match '\.md$' -and "$_".Trim() -notmatch '(^|/)README\.md$' -and "$_".Trim() -notmatch '(^|/)\.[^/]+$' } |
            ForEach-Object { "$_".Trim().Replace('\', '/') })

        # The org's cards, from DISK, judged by their own dates.
        $verdicts = @{}
        if ($folderPrefix) {
            foreach ($kindFolder in @('archive', 'current')) {
                $cardDir = Join-Path (Join-Path $promptsRoot $folderPrefix) $kindFolder
                if (-not (Test-Path $cardDir)) { continue }
                foreach ($cardFile in (Get-ChildItem -Path $cardDir -Filter '*.md' -File -ErrorAction SilentlyContinue)) {
                    if ($cardFile.Name -eq 'README.md') { continue }
                    $cardRel = "$folderPrefix/$kindFolder/$($cardFile.Name)"
                    $cardText = Get-Content $cardFile.FullName -Raw -Encoding UTF8
                    if ($null -eq $cardText) { $cardText = '' }
                    $verdicts[$cardRel] = Test-P20CardInWindow `
                        -Created (Get-P20StampDate $cardText $script:Consts.stamps.created) `
                        -Closed (Get-P20StampDate $cardText $script:Consts.stamps.closed) `
                        -Start $StartDate -End $EndDate
                }
            }
        }
        foreach ($cardRel in @($verdicts.Keys)) {
            if ($verdicts[$cardRel] -eq $true) { [void]$allPaths.Add($cardRel); [void]$stampSelected.Add($cardRel) }
        }
        # Everything git found that a stamp did not already decide: a card with no
        # Created stamp, the growth folder, and pre-move history at the hub root.
        # A stamped card git "touched" but whose dates put it outside the window
        # stays out -- that is the whole point.
        foreach ($p in $gitPaths) {
            if ($verdicts.ContainsKey($p) -and ($null -ne $verdicts[$p])) { continue }
            [void]$allPaths.Add($p)
        }
    }

    $paths = @($allPaths | Sort-Object)

    if ($paths.Count -eq 0) {
        @{ error = "No work artifacts found between $StartDate and $EndDate" } | ConvertTo-Json
        return
    }

    # -- Extract metadata from each file -------------------------------------
    # Use the first selected slug's folderPrefix for path normalization/grouping.
    # For multi-slug we use the primary slug (first sorted); each item's source
    # org can be inferred from path prefix but label-grouping by folder type
    # (archive/current/spec/growth) is sufficient for the scaffold.

    $items = @()
    $seenPaths = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

    foreach ($rel in $paths) {
        # Try each selected slug's folder prefix to resolve the file
        $resolvedFull = $null
        $resolvedRel  = $rel

        # First: check if the path already has a known slug prefix
        $matchedPrefix = ''
        foreach ($slug in $selectedSlugs) {
            $spaceEntry = $null
            if ($cfg.Spaces) {
                $spaceEntry = @($cfg.Spaces) | Where-Object { $_.slug -eq $slug } | Select-Object -First 1
            }
            $fp = if ($spaceEntry -and $spaceEntry.promptsFolder) { $spaceEntry.promptsFolder } else { $slug }
            if ($fp -and $rel.StartsWith("$fp/")) {
                $matchedPrefix = $fp
                break
            }
        }

        if ($matchedPrefix) {
            # Path already has the slug prefix
            $candidate = Join-Path $promptsRoot $rel
            if (Test-Path $candidate) {
                $resolvedFull = $candidate
                $resolvedRel  = $rel
            }
        }

        if (-not $resolvedFull) {
            # Try to resolve relative to root (legacy/bare paths)
            $candidate = Join-Path $promptsRoot $rel
            if (Test-Path $candidate) {
                $resolvedFull = $candidate
                $resolvedRel  = $rel
            }
            else {
                # growth files may have been moved without git mv
                $basename = [System.IO.Path]::GetFileName($rel)
                $resolved = $false
                foreach ($sub in @("$growthFolder/archive/", "$growthFolder/current/")) {
                    $c2 = Join-Path $promptsRoot "$sub$basename"
                    if (Test-Path $c2) {
                        $resolvedFull = $c2
                        $resolvedRel  = "$sub$basename"
                        $resolved = $true
                        break
                    }
                }
                if (-not $resolved) { continue }
            }
        }

        if (-not $seenPaths.Add($resolvedRel)) { continue }
        $content = Get-Content $resolvedFull -Raw -Encoding UTF8

        # Parse YAML frontmatter
        $fm = @{}
        if ($content -match '(?s)^---\r?\n(.+?)\r?\n---') {
            foreach ($line in ($Matches[1] -split '\r?\n')) {
                if ($line -match '^(\w[\w\s]*?):\s*(.+)$') {
                    $fm[$Matches[1].Trim()] = $Matches[2].Trim().Trim('"').Trim("'")
                }
            }
        }

        # Determine folder type -- strip any org prefix to get the bare folder
        $relForFolder = $resolvedRel
        foreach ($slug in $selectedSlugs) {
            $spaceEntry = $null
            if ($cfg.Spaces) {
                $spaceEntry = @($cfg.Spaces) | Where-Object { $_.slug -eq $slug } | Select-Object -First 1
            }
            $fp = if ($spaceEntry -and $spaceEntry.promptsFolder) { $spaceEntry.promptsFolder } else { $slug }
            if ($fp -and $relForFolder.StartsWith("$fp/")) {
                $relForFolder = $relForFolder.Substring($fp.Length + 1)
                break
            }
        }
        $folder = Get-ItemKind (($relForFolder -split '/')[0])

        # A stamped card is Completed or Active AS OF THE END OF THE WINDOW, not as
        # of today. A card open all through May and archived in June sits in
        # archive/ now, and a May review written in September used to call it
        # completed work. For a window that runs to today the two are the same.
        $created = Get-P20StampDate $content $script:Consts.stamps.created
        $closed = Get-P20StampDate $content $script:Consts.stamps.closed
        if ($created -and ($folder -eq 'archive' -or $folder -eq 'current')) {
            if ($closed -and ($closed -le $EndDate)) { $folder = 'archive' } else { $folder = 'current' }
        }
        $openedInWindow = [bool]($created -and ($created -ge $StartDate) -and ($created -le $EndDate))
        $closedInWindow = [bool]($closed -and ($closed -ge $StartDate) -and ($closed -le $EndDate))

        $title = $fm["title"]
        if (-not $title) {
            if ($content -match '(?m)^##\s+Title\s*\r?\n+([^\r\n#][^\r\n]+)') { $title = $Matches[1] }
            elseif ($content -match '(?m)^#\s+(.+)') { $title = $Matches[1] }
            else { $title = [System.IO.Path]::GetFileNameWithoutExtension($rel) }
        }
        $title = $title.Trim().TrimEnd("`r")

        $checked = ([regex]::Matches($content, '\[x\]')).Count
        $total = ([regex]::Matches($content, '\[[ x]\]')).Count
        $progress = if ($total -gt 0) { "$checked/$total" } else { "--" }

        # Source-org attribution: a slug-prefixed path belongs to that org. A
        # bare path is not attributed -- it is either pre-move history or a
        # hub-root folder like the growth one, which belongs to no org, and guessing
        # would put one engagement's label on another's work.
        $itemOrg = ''
        foreach ($s in $selectedSlugs) {
            $oe = if ($cfg.Spaces) { @($cfg.Spaces) | Where-Object { $_.slug -eq $s } | Select-Object -First 1 } else { $null }
            $pf = if ($oe -and $oe.promptsFolder) { $oe.promptsFolder } else { $s }
            if ($pf -and $resolvedRel.StartsWith("$pf/")) { $itemOrg = $s; break }
        }
        $items += [PSCustomObject]@{
            File     = $rel
            Folder   = $folder
            Title    = $title
            Sprint   = if ($fm["sprint"]) { $fm["sprint"] } else { "--" }
            Progress = $progress
            Org      = $itemOrg
            Opened   = $(if ($openedInWindow) { $created } else { '' })
            Closed   = $(if ($closedInWindow) { $closed } else { '' })
        }
    }

    if ($items.Count -eq 0) {
        @{ error = "No readable files found in date range" } | ConvertTo-Json
        return
    }

    # -- Build review markdown -----------------------------------------------

    $startDisplay = ([datetime]::Parse($StartDate)).ToString("MMMM d, yyyy")
    $endDisplay = ([datetime]::Parse($EndDate)).ToString("MMMM d, yyyy")
    $startShort = ([datetime]::Parse($StartDate)).ToString("MMMM d")
    $endShort = ([datetime]::Parse($EndDate)).ToString("MMMM d, yyyy")

    # Emoji by code point, never as a literal: a PS 5.1 shell on a Windows-1252
    # code page mangles a pasted emoji inside a double-quoted string.
    $folderLabel = @{
        "archive" = "$([char]::ConvertFromUtf32(0x2705)) Completed Work"
        "current" = "$([char]::ConvertFromUtf32(0x1F6A7)) Active Work"
        "growth"  = "$([char]::ConvertFromUtf32(0x1F331)) Professional Development"
    }
    $folderOrder = @("archive", "current", "growth")

    $sprints = @($items | Where-Object { $_.Sprint -ne "--" } |
        Select-Object -ExpandProperty Sprint -Unique)

    $grouped = $items | Group-Object Folder

    $today = (Get-Date).ToString("yyyy-MM-dd")

    # Build normalized orgs YAML list: [globex] or [demo, globex]
    $orgsYaml = "[" + ($selectedSlugs -join ", ") + "]"

    $sb = [System.Text.StringBuilder]::new()
    [void]$sb.AppendLine("---")
    [void]$sb.AppendLine("orgs: $orgsYaml")
    [void]$sb.AppendLine("period: ${StartDate}_${EndDate}")
    [void]$sb.AppendLine("generated: $today")
    [void]$sb.AppendLine("generator: scaffold")
    [void]$sb.AppendLine("---")
    [void]$sb.AppendLine()
    [void]$sb.AppendLine("# $([char]::ConvertFromUtf32(0x1F4CB)) Review -- $startShort - $endShort")
    [void]$sb.AppendLine()
    [void]$sb.AppendLine("**Period:** $startDisplay - $endDisplay")
    if ($sprints.Count -gt 0) {
        [void]$sb.AppendLine("**Sprints:** $($sprints -join ', ')")
    }
    [void]$sb.AppendLine()
    [void]$sb.AppendLine("---")
    [void]$sb.AppendLine()

    # By the Numbers
    $completed = @($items | Where-Object { $_.Folder -eq "archive" }).Count
    $active = @($items | Where-Object { $_.Folder -eq "current" }).Count
    $growth = @($items | Where-Object { $_.Folder -eq "growth" }).Count

    [void]$sb.AppendLine("## $([char]::ConvertFromUtf32(0x1F4CA)) By the Numbers")
    [void]$sb.AppendLine()
    [void]$sb.AppendLine("| Metric | Count |")
    [void]$sb.AppendLine("|--------|-------|")
    [void]$sb.AppendLine("| $([char]::ConvertFromUtf32(0x1F4E6)) Total work items | $($items.Count) |")
    if ($completed -gt 0) { [void]$sb.AppendLine("| $([char]::ConvertFromUtf32(0x2705)) Completed (archived) | $completed |") }
    if ($active -gt 0) { [void]$sb.AppendLine("| $([char]::ConvertFromUtf32(0x1F6A7)) Active | $active |") }
    if ($growth -gt 0) { [void]$sb.AppendLine("| $([char]::ConvertFromUtf32(0x1F331)) Growth / development | $growth |") }
    if ($sprints.Count -gt 0) { [void]$sb.AppendLine("| $([char]::ConvertFromUtf32(0x1F3C3)) Sprints covered | $($sprints.Count) |") }
    [void]$sb.AppendLine()
    [void]$sb.AppendLine("---")
    [void]$sb.AppendLine()

    # Sections by folder (in preferred order)
    foreach ($folderName in $folderOrder) {
        $group = $grouped | Where-Object { $_.Name -eq $folderName }
        if (-not $group) { continue }

        $label = $folderLabel[$folderName]
        if (-not $label) { $label = $folderName }
        [void]$sb.AppendLine("## $label")
        [void]$sb.AppendLine()

        $bySprint = $group.Group | Group-Object Sprint
        foreach ($sg in $bySprint) {
            if ($sg.Name -ne "--") {
                [void]$sb.AppendLine("### $($sg.Name)")
                [void]$sb.AppendLine()
            }
            foreach ($item in $sg.Group) {
                $badge = if ($item.Progress -ne "--") { " ``$($item.Progress)``" } else { "" }
                # Multi-org reviews label each bullet with its source org (D1);
                # single-org output stays unchanged for back-compat.
                $orgTag = if ($selectedSlugs.Count -gt 1 -and $item.Org) { "**[$($item.Org)]** " } else { "" }
                # What happened to the card INSIDE this window, when its stamps say so.
                # MM-dd, because the heading above already carries the year.
                $when = @()
                if ($item.Opened) { $when += "opened $($item.Opened.Substring(5))" }
                if ($item.Closed) { $when += "closed $($item.Closed.Substring(5))" }
                $whenText = if ($when.Count -gt 0) { " -- $($when -join ', ')" } else { "" }
                [void]$sb.AppendLine("- $orgTag**$($item.Title)**$badge$whenText")
            }
            [void]$sb.AppendLine()
        }
    }

    [void]$sb.AppendLine("---")
    [void]$sb.AppendLine()
    [void]$sb.AppendLine("*$([char]::ConvertFromUtf32(0x1F916)) A scaffold, from local history. Edit it, then run ``$(Get-CliPrefix)PublishWorkReview`` to commit.*")

    $reviewMd = $sb.ToString().TrimEnd()

    # -- Write output file ---------------------------------------------------

    $year = $StartDate.Substring(0, 4)
    $folderRange = "${StartDate}_${EndDate}"
    # Reviews write under $promptsRoot/reviews. PROMPTS_REVIEWS_DIR redirects
    # the physical write elsewhere, which is how the suite runs this against a
    # scratch hub without touching a real one; unset, nothing changes.
    $reviewsRoot = if ($env:PROMPTS_REVIEWS_DIR) { $env:PROMPTS_REVIEWS_DIR } else { Join-Path $promptsRoot $reviewsFolder }
    $outDir = Join-Path $reviewsRoot "$slugSetStr/$year/$folderRange"
    if (-not (Test-Path $outDir)) {
        New-Item -ItemType Directory -Path $outDir -Force | Out-Null
    }
    $outFile = Join-Path $outDir $script:Consts.reviews.fileName
    # The one byte contract (Write-CardText -New): UTF-8, no BOM, LF. Under
    # Windows PowerShell 5.1 Set-Content -Encoding UTF8 wrote a BOM ahead of the
    # first heading.
    Write-CardText -Path $outFile -Content ($reviewMd + "`n") -New

    # file_path stays the logical repo-relative path (reviews/...); only the
    # physical write location changes when PROMPTS_REVIEWS_DIR is set.
    $relPath = "$reviewsFolder/$slugSetStr/$year/$folderRange/$($script:Consts.reviews.fileName)"

    # -- Output JSON ---------------------------------------------------------

    @{
        review         = $reviewMd
        file_path      = $relPath
        files_scanned  = $paths.Count
        files_included = $items.Count
        # How the window was filled, counted over the items that are IN the
        # review: by their own dates, and by git for what has no stamp (unstamped
        # files, the growth folder). 0 by git on a hub that is not a repository.
        selected_by_stamps = @($items | Where-Object { $stampSelected.Contains($_.File) }).Count
        selected_by_git    = @($items | Where-Object { -not $stampSelected.Contains($_.File) }).Count
    } | ConvertTo-Json -Depth 5

}
finally {
    Pop-Location
}
