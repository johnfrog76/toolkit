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
    Path to the prompt file (positional). If omitted, resolved from the current
    git branch, the same way NewPR resolves it.
.PARAMETER Hash
    Thread one explicit commit instead of scanning the branch. The alternative
    when the current location is not a git repository.
.EXAMPLE
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

# Get-CliPrefix normally comes from the module. These scripts are also invoked
# directly -- by tests, by a user running the .ps1, by anything that wants -Help
# without importing first -- so a missing helper must not be fatal.
if (-not (Get-Command Get-CliPrefix -ErrorAction SilentlyContinue)) {
    function Get-CliPrefix {
        if ($global:P20Config -and $global:P20Config.CommandPrefix) { return $global:P20Config.CommandPrefix }
        return ''
    }
}

# Write-CliError normally comes from the module too, and it is what makes a
# refusal ONE block: the wrapper sees the stated exit code and adds nothing.
# See AGENTS.md, "The refusal contract".
if (-not (Get-Command Write-CliError -ErrorAction SilentlyContinue)) {
    function Write-CliError {
        param([string]$Message, [string]$Hint)
        $global:P20StatedError = $Message
        Write-Host "Error: $Message" -ForegroundColor Red
        if ($Hint) { Write-Host "Hint:  $Hint" -ForegroundColor Yellow }
    }
}


if ($Help) {
    Write-Host ""
    Write-Host "  $(Get-CliPrefix)ThreadHash [file]            Thread this branch's commits into the card" -ForegroundColor Cyan
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
$gitTop = git rev-parse --show-toplevel 2>$null
if ($LASTEXITCODE -eq 0 -and $gitTop) { $codeRepoRoot = "$gitTop".Trim() }

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
    $remoteUrl = git -C $RepoRoot remote get-url origin 2>$null
    if ($LASTEXITCODE -eq 0 -and $remoteUrl) {
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
    $originHead = git -C $RepoRoot symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>$null
    if ($LASTEXITCODE -eq 0 -and $originHead) {
        return ("$originHead".Trim() -replace '^origin/', '')
    }

    # Last resort: whichever conventional name this repo actually has.
    foreach ($name in @('main', 'master')) {
        git -C $RepoRoot rev-parse --verify --quiet "refs/heads/$name" 2>$null | Out-Null
        if ($LASTEXITCODE -eq 0) { return $name }
    }
    return $null
}

# -- The bullets this run wants to add -----------------------------------------
$wanted = @()   # ordered list of "- <hash> <subject>" lines
$firstHash = $null

if ($Hash) {
    $subject = ''
    if ($codeRepoRoot) {
        $subject = git -C $codeRepoRoot log -1 --format=%s $Hash 2>$null
        if ($LASTEXITCODE -ne 0) { $subject = '' }
    }
    $subject = "$subject".Trim()
    if ($subject) { $wanted = @("- $Hash $subject") } else { $wanted = @("- $Hash") }
    $firstHash = $Hash
}
else {
    $currentBranch = "$(git -C $codeRepoRoot rev-parse --abbrev-ref HEAD 2>$null)".Trim()
    $baseBranch = Resolve-P20BaseBranch -RepoRoot $codeRepoRoot

    $lines = @()
    if ($baseBranch -and $baseBranch -ne $currentBranch) {
        # --abbrev=7 rather than git's default "auto": Status only reads a
        # bullet whose hash is 7+ hex characters.
        $lines = @(git -C $codeRepoRoot log --reverse --abbrev=7 "--format=- %h %s" "$baseBranch..HEAD" 2>$null)
        if ($LASTEXITCODE -ne 0) { $lines = @() }
    }
    if ($lines.Count -eq 0) {
        # On the default branch, or no base to measure against: the branch is
        # not the unit of work here, so record HEAD and say so.
        $head = @(git -C $codeRepoRoot log -1 --reverse --abbrev=7 "--format=- %h %s" 2>$null)
        if ($LASTEXITCODE -eq 0) { $lines = $head }
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
    $branchForCard = ''
    if ($codeRepoRoot) {
        $branchForCard = "$(git -C $codeRepoRoot rev-parse --abbrev-ref HEAD 2>$null)".Trim()
    }
    $found = Resolve-P20CardForBranch -Branch $branchForCard -CurrentDir $currentDir -Detailed
    $File = $found.Path
    if (-not $File -and $found.Candidates.Count -gt 1) {
        # Ambiguity is never guessed at (docs/CLI.md, Errors).
        Write-CliError -Message "Branch '$branchForCard' matches $($found.Candidates.Count) prompt files." `
            -Hint "Pass the card explicitly: $(Get-CliPrefix)ThreadHash <file> -- one of $($found.Candidates -join ', ')"
        exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
    }
    if (-not $File) {
        Write-CliError -Message "No prompt file matches branch '$branchForCard'." `
            -Hint "Looked in $currentDir. Pass the card explicitly: $(Get-CliPrefix)ThreadHash <file>."
        exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
    }
    Write-Host "  Card: $(Split-Path $File -Leaf)" -ForegroundColor DarkGray
}

if (-not (Test-Path $File)) {
    # Try relative to promptsRoot
    $resolved = Join-Path $promptsRoot $File
    if (Test-Path $resolved) { $File = $resolved }
    else {
        Write-CliError -Message "File not found: $File" `
            -Hint "Pass a path to a card under the hub's current/ folder."
        exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
    }
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
