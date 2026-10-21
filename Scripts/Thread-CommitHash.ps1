<#
.SYNOPSIS
    Threads the commits of the CURRENT repository into a card's Git section.
.DESCRIPTION
    Run it from the repo you are committing to -- not from the hub.

    Every commit on the current branch that is not yet on the project's
    defaultBranch is recorded as its own `- <short-hash> <subject>` bullet under
    `Commits:`, in the order it was made, skipping any hash the card already
    carries. One run after the last commit records the whole branch, and a
    second run adds nothing.

    It also replaces [commit] placeholders in take/modify replies, removes the
    `- (pending)` placeholder once a real commit is written, and writes the card
    through Write-CardText so the file keeps its own line endings and no BOM.

    It used to read `git log -1` inside promptsRoot -- the HUB -- so it
    recorded the hub's own last commit, reported success, and left the card
    reading In Progress on a commit from another repository.
.PARAMETER File
    The card: its id, its filename, a partial name, or a path (positional).
    If omitted, resolved from the current
    git branch, the same way NewPR resolves it.
.PARAMETER Hash
    Thread one explicit commit instead of scanning the branch. The alternative
    when the current location is not a git repository.
.EXAMPLE
    {cliPrefix}ThreadHash 178497
    {cliPrefix}ThreadHash current/178497-teams-search-coach.prompt.md
    {cliPrefix}ThreadHash -Hash abc1234
#>
[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [string]$File,

    [string]$Hash,

    [switch]$Help
)

. (Join-Path $PSScriptRoot 'Initialize-CliFallbacks.ps1')


if ($Help) {
    Write-Host ""
    Write-Host "  $(Get-CliPrefix)ThreadHash [<id|file>]       Thread this branch's commits into the card" -ForegroundColor Cyan
    Write-Host "  $(Get-CliPrefix)ThreadHash -Hash abc1234     Thread one explicit hash" -ForegroundColor Cyan
    Write-Host "  $(Get-CliPrefix)ThreadHash -Help             Show this help" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  Run it from the repository you committed to. Every commit on the" -ForegroundColor Gray
    Write-Host "  current branch that is not yet on the project's default branch is" -ForegroundColor Gray
    Write-Host "  recorded once, with its subject; re-running adds nothing." -ForegroundColor Gray
    Write-Host ""
    return
}

$cfg = $global:P20Config
$promptsRoot = $cfg.PromptsRoot
# Test-P20HubRoot and the one "hub not found" sentence live here, and this file
# is dot-sourced rather than reached through the module because this script also
# runs with no module in the session (a test sandbox, `pwsh -File`).
. (Join-Path $PSScriptRoot 'Resolve-HubConfig.ps1')
. (Join-Path $PSScriptRoot 'Write-CardText.ps1')
. (Join-Path $PSScriptRoot 'Resolve-CardForBranch.ps1')
. (Join-Path $PSScriptRoot 'Resolve-CardName.ps1')
. (Join-Path $PSScriptRoot 'Move-CardFolder.ps1')
. (Join-Path $PSScriptRoot 'Invoke-TrackerRead.ps1')
# The bullet shape this writes is what Get-PromptStatus.ps1 and
# agent/core/parsers.py both read to call a card In Progress -- one pattern, in
# consts.json, compiled by each half.
. (Join-Path $PSScriptRoot 'Get-Consts.ps1')
$script:Consts = Get-P20Consts

function Get-P20BulletHash {
    # The hash out of a bullet the CONTRACT pattern matched. Matching and
    # extracting are one step so no second copy of the shape can exist here.
    param([string]$Line)
    $m = [regex]::Match($Line, $script:Consts.regex.commitBullet)
    if (-not $m.Success) { return '' }
    return (($m.Value -replace '^\s*-\s+', '') -replace '`', '').Trim().ToLower()
}
if (-not (Test-P20HubRoot $promptsRoot)) {
    Write-CliError -Message (Get-P20HubMissingMessage $promptsRoot)
    exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
}

# -- Where the hashes come from ------------------------------------------------
#
# The CURRENT LOCATION, always. The hub is a separate tree -- it need not be a
# git repository at all, and where it is one its history is the record of
# archived cards, not of the work. Reading it is how three BowlingApp commits
# were reported as one hub commit, three times, with exit 0.
$codeRepoRoot = $null
$topRead = Invoke-P20TrackerRead 'git' @('rev-parse', '--show-toplevel')
$gitTop = $topRead.Out
if ($topRead.Code -eq 0 -and $gitTop) { $codeRepoRoot = "$gitTop".Trim() }

if (-not $codeRepoRoot -and -not $Hash) {
    Write-CliError -Message "Not in a git repository: $((Get-Location).Path)" `
        -Hint "Run $(Get-CliPrefix)ThreadHash from the repository you committed to, or pass -Hash <hash> to thread one explicitly."
    exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
}

# -- Which branch is the work measured against ---------------------------------
#
# The project's configured defaultBranch, matched by repo name exactly as NewPR
# matches it. A repo that is in no configured project (a scratch clone, a
# personal sibling) falls back to what git itself knows.
function Resolve-P20BaseBranch {
    param([string]$RepoRoot)

    $repoName = $null
    $remoteRead = Invoke-P20TrackerRead 'git' @('-C', $RepoRoot, 'remote', 'get-url', 'origin')
    $remoteUrl = $remoteRead.Out
    if ($remoteRead.Code -eq 0 -and $remoteUrl) {
        $remoteUrl = "$remoteUrl".Trim()
        if ($remoteUrl -match 'dev\.azure\.com/[^/]+/([^/]+)/_git/([^/]+)' -or
            $remoteUrl -match 'ssh\.dev\.azure\.com[:/]v3/[^/]+/([^/]+)/([^/]+?)(?:\.git)?$') {
            $repoName = [Uri]::UnescapeDataString($Matches[2])
        }
    }
    if (-not $repoName) { $repoName = Split-Path $RepoRoot -Leaf }

    if ($global:P20Config -and $global:P20Config.Projects) {
        foreach ($p in $global:P20Config.Projects) {
            if ($p.repo -eq $repoName -and $p.defaultBranch) { return [string]$p.defaultBranch }
        }
    }

    # What the remote says its default is.
    $headRead = Invoke-P20TrackerRead 'git' @('-C', $RepoRoot, 'symbolic-ref', '--quiet', '--short', 'refs/remotes/origin/HEAD')
    $originHead = $headRead.Out
    if ($headRead.Code -eq 0 -and $originHead) {
        return ("$originHead".Trim() -replace '^origin/', '')
    }

    # Last resort: whichever conventional name this repo actually has.
    foreach ($name in @('main', 'master')) {
        $verify = Invoke-P20TrackerRead 'git' @('-C', $RepoRoot, 'rev-parse', '--verify', '--quiet', "refs/heads/$name")
        if ($verify.Code -eq 0) { return $name }
    }
    return $null
}

# -- The bullets this run wants to add -----------------------------------------
$wanted = @()   # ordered list of "- <hash> <subject>" lines
$firstHash = $null

if ($Hash) {
    $subject = ''
    if ($codeRepoRoot) {
        $subjectRead = Invoke-P20TrackerRead 'git' @('-C', $codeRepoRoot, 'log', '-1', '--format=%s', $Hash)
        $subject = $subjectRead.Out
        if ($subjectRead.Code -ne 0) { $subject = '' }
    }
    $subject = "$subject".Trim()
    if ($subject) { $wanted = @("- $Hash $subject") } else { $wanted = @("- $Hash") }
    $firstHash = $Hash
}
else {
    $currentBranch = "$((Invoke-P20TrackerRead 'git' @('-C', $codeRepoRoot, 'rev-parse', '--abbrev-ref', 'HEAD')).Out)".Trim()
    $baseBranch = Resolve-P20BaseBranch -RepoRoot $codeRepoRoot

    $lines = @()
    if ($baseBranch -and $baseBranch -ne $currentBranch) {
        # --abbrev=7 rather than git's default "auto": Status only reads a
        # bullet whose hash is 7+ hex characters.
        $logRead = Invoke-P20TrackerRead 'git' @('-C', $codeRepoRoot, 'log', '--reverse', '--abbrev=7', '--format=- %h %s', "$baseBranch..HEAD")
        $lines = @($logRead.Out)
        if ($logRead.Code -ne 0) { $lines = @() }
    }
    if ($lines.Count -eq 0) {
        # On the default branch, or no base to measure against: the branch is
        # not the unit of work here, so record HEAD and say so.
        $headLog = Invoke-P20TrackerRead 'git' @('-C', $codeRepoRoot, 'log', '-1', '--reverse', '--abbrev=7', '--format=- %h %s')
        if ($headLog.Code -eq 0) { $lines = @($headLog.Out) }
    }
    $wanted = @($lines | Where-Object { $_ -and $_.Trim() } | ForEach-Object { $_.TrimEnd() })
    if ($wanted.Count -eq 0) {
        Write-CliError -Message "No commits found in $codeRepoRoot." `
            -Hint "Commit first, or pass -Hash <hash> to thread one explicitly."
        exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
    }
    $firstHash = Get-P20BulletHash $wanted[0]
}

# -- Which card ----------------------------------------------------------------
if (-not $File) {
    $folders = Get-PromptFolders
    $currentDir = $folders.Current
    # backlog/ too: the first ThreadHash into a planned card is what pulls it into play.
    $cardDirs = @($currentDir, (Get-P20BacklogFolder -Folders $folders))
    $branchForCard = ''
    if ($codeRepoRoot) {
        $branchForCard = "$((Invoke-P20TrackerRead 'git' @('-C', $codeRepoRoot, 'rev-parse', '--abbrev-ref', 'HEAD')).Out)".Trim()
    }
    $found = Resolve-P20CardForBranch -Branch $branchForCard -CurrentDir $cardDirs -Detailed
    $File = $found.Path
    if (-not $File -and $found.Candidates.Count -gt 1) {
        # Ambiguity is never guessed at (docs/CLI.md, Errors).
        Write-CliError -Message "Branch '$branchForCard' matches $($found.Candidates.Count) prompt files." `
            -Hint "Pass the card explicitly: $(Get-CliPrefix)ThreadHash <file> -- one of $($found.Candidates -join ', ')"
        exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
    }
    if (-not $File) {
        Write-CliError -Message "No prompt file matches branch '$branchForCard'." `
            -Hint "Looked in $($cardDirs -join ' and '). Pass the card explicitly: $(Get-CliPrefix)ThreadHash <file>."
        exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
    }
    Write-Host "  Card: $(Split-Path $File -Leaf)" -ForegroundColor DarkGray
}

# A full path (or one relative to the hub or the current location) is used as
# typed. Anything else is what a person types for every other card verb: an id,
# a filename, or a partial name, turned into a card by the one shared rule,
# Resolve-P20CardArgument (AGENTS.md, "An id is not a substring").
$asPath = $null
if (Test-Path -LiteralPath $File -PathType Leaf) { $asPath = $File }
elseif (Test-Path -LiteralPath (Join-Path $promptsRoot $File) -PathType Leaf) { $asPath = Join-Path $promptsRoot $File }

if ($asPath) {
    $File = $asPath
}
else {
    $typed = $File
    $typedFolders = Get-PromptFolders
    $resolved = Resolve-P20CardArgument -Argument $typed -Folder @($typedFolders.Current, (Get-P20BacklogFolder -Folders $typedFolders)) `
        -WorkItemTypes (Get-P20WorkItemTypes -Config $cfg)
    $match = @($resolved.Match | Where-Object { $_.Name -like '*.md' })
    if ($match.Count -eq 0) {
        if ($resolved.IsId) {
            Write-CliError -Message "No card with id '$typed' in current/ or backlog/." `
                -Hint "'$typed' has the shape of an ID, and an ID is not a partial name. Run '$(Get-CliPrefix)Status' to see the cards."
        }
        else {
            Write-CliError -Message "No card matching '$typed' found in current/ or backlog/." `
                -Hint "Pass the card's ID, its filename, or a path. Run '$(Get-CliPrefix)Status' to see the cards."
        }
        exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
    }
    if ($match.Count -gt 1) {
        Write-Host "Matches for '$typed':" -ForegroundColor Yellow
        $match | ForEach-Object { Write-Host "  $($_.Name)" }
        Write-CliError -Message "'$typed' matches $($match.Count) files in current/ or backlog/." `
            -Hint "Be more specific, or pass the card's ID."
        exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
    }
    # A partial name is named before anything is written; with nobody to read it
    # (the bridge) it refuses rather than guessing.
    if ($resolved.Fuzzy) {
        if ($env:TOOLKIT_QUIET_STARTUP) {
            Write-CliError -Message "'$typed' is not a card in current/ or backlog/; it matches '$($match[0].Name)' only by partial name." `
                -Hint "Pass the card's ID or its full filename."
            exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
        }
        Write-Host "Matched '$typed' -> $($match[0].Name)" -ForegroundColor Cyan
    }
    $File = $match[0].FullName
}

# -- Edit the card -------------------------------------------------------------
#
# Read raw, work in LF, restore the terminator the file already had. Write-CardText
# without -New passes the content through byte for byte, which is what keeps a
# CRLF card CRLF (AGENTS.md, "One byte contract for a card"); this is the half
# that has to decide what "unchanged" means for a file it rewrote line by line.
$original = [System.IO.File]::ReadAllText($File)
$wasCrlf = $original -match "`r`n"
$content = $original -replace "`r`n", "`n"

# [commit] placeholders in PR replies take the first hash this run threads.
$replacements = ([regex]::Matches($content, '\[commit\]')).Count
if ($replacements -gt 0 -and $firstHash) {
    $content = $content -replace '\[commit\]', $firstHash
}

$lines = [System.Collections.Generic.List[string]]($content -split "`n")

# The Git section: `## Git` to the next `## ` heading, or end of file.
$gitStart = -1
for ($i = 0; $i -lt $lines.Count; $i++) {
    if ($lines[$i] -match '^##\s+Git\s*$') { $gitStart = $i; break }
}
if ($gitStart -lt 0) {
    Write-CliError -Message "No '## Git' section in $(Split-Path $File -Leaf)." `
        -Hint "Add a '## Git' heading with a 'Commits:' line, as the card templates have."
    exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
}
$gitEnd = $lines.Count
for ($i = $gitStart + 1; $i -lt $lines.Count; $i++) {
    if ($lines[$i] -match '^##\s+') { $gitEnd = $i; break }
}

# Hashes the card already carries -- the whole point of re-running being safe.
$existing = @{}
for ($i = $gitStart; $i -lt $gitEnd; $i++) {
    $h = Get-P20BulletHash $lines[$i]
    if ($h) { $existing[$h] = $true }
}

$toAdd = @()
foreach ($line in $wanted) {
    $h = Get-P20BulletHash $line
    $seen = $false
    foreach ($k in $existing.Keys) {
        if ($k.StartsWith($h) -or $h.StartsWith($k)) { $seen = $true; break }
    }
    if (-not $seen) {
        $toAdd += $line
        if ($h) { $existing[$h] = $true }
    }
}

$added = $toAdd.Count
if ($added -gt 0) {
    # Insert after the last existing commit bullet under Commits:, else right
    # after the Commits: line, else at the end of the Git section.
    $insertAt = -1
    for ($i = $gitStart; $i -lt $gitEnd; $i++) {
        if ($lines[$i] -match '^Commits:') { $insertAt = $i + 1; break }
    }
    if ($insertAt -lt 0) { $insertAt = $gitEnd }
    for ($i = $insertAt; $i -lt $gitEnd; $i++) {
        if (Get-P20BulletHash $lines[$i]) { $insertAt = $i + 1 }
        elseif ($lines[$i].Trim() -ne '') { break }
    }
    $lines.InsertRange($insertAt, [string[]]$toAdd)
    $gitEnd += $added

    # The placeholder has done its job the moment a real commit is recorded.
    for ($i = $gitEnd - 1; $i -ge $gitStart; $i--) {
        if ($lines[$i] -match '^\s*-\s+\(pending\)\s*$') { $lines.RemoveAt($i) }
    }
}

$content = ($lines -join "`n")
if ($wasCrlf) { $content = $content -replace "`n", "`r`n" }

if ($content -ne $original) {
    # The pull on first write: a planned card in backlog/ moves to current/
    # BEFORE its first commit bullet is written, so it arrives in play with the
    # commit on it and a backlog card never carries one (Scripts/Move-CardFolder.ps1).
    # After every refusal above, so a card this run cannot thread is not moved.
    $pull = Invoke-P20PullIntoPlay -Path $File
    if (-not $pull.Ok) {
        Write-CliError -Message "$($pull.Message) Nothing was threaded." `
            -Hint "Look in $((Get-P20Consts).folders.current)/ -- a person moves or deletes the file there, on purpose."
        exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
    }
    $File = $pull.Path
    Write-CardText -Path $File -Content $content
}

$leaf = Split-Path $File -Leaf
if ($added -gt 0) {
    Write-Host "  Threaded $added commit$(if ($added -ne 1) { 's' }) into $leaf" -ForegroundColor Green
    foreach ($line in $toAdd) { Write-Host "    $line" -ForegroundColor Gray }
}
else {
    Write-Host "  $leaf already carries every commit on this branch -- nothing to add." -ForegroundColor DarkGray
}
if ($replacements -gt 0 -and $firstHash) {
    Write-Host "  Replaced $replacements [commit] placeholder$(if ($replacements -ne 1) { 's' })" -ForegroundColor Gray
}
Write-Host ""
if (Get-Command Write-ToolkitLog -ErrorAction SilentlyContinue) {
    Write-ToolkitLog -Type CMD -Source "$(Get-CliPrefix)ThreadHash" -Detail "$added commit(s) threaded into $leaf"
}

# Explicit, because this script's first act is a `git rev-parse` that EXITS 128
# when the location is not a repository -- and with -Hash that is not a failure,
# it is the case -Hash exists for. Falling off the end would leave the probe's
# 128 in $LASTEXITCODE and the wrapper would explain a failure that did not
# happen (AGENTS.md, "The refusal contract": exit 0 is success, and nothing else is).
exit 0
