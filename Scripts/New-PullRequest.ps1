<#
.SYNOPSIS
    Workflow command: creates an ADO PR and updates all tracking artifacts.

.DESCRIPTION
    Full ship-it workflow -- run from the repo directory:
      1. Create PR with Described Changes from the prompt file as description
      2. Move ADO work item to Code Review state
      3. Post described changes as ADO work item comment
      4. Write PR URL into the prompt file (triggers Code Review status in {cliPrefix}Status)

    Auto-detects everything from the current git branch + matching prompt file in current/.

.PARAMETER File
    Path to the prompt file. Default: auto-detected from current/ by matching branch name.

.PARAMETER TargetBranch
    Target branch name. Default: master.

.PARAMETER Draft
    Create as a draft PR.

.PARAMETER AutoComplete
    Set auto-complete on the PR after creation (squash merge, delete source branch).

.PARAMETER SkipWorkItem
    Skip ADO work item update (state change + comment). Just create the PR.

.PARAMETER Repository
    ADO repository name. Default: auto-detected from git remote.

.PARAMETER Project
    ADO project name. Default: auto-detected from git remote.

.PARAMETER Help
    Show usage information.

.EXAMPLE
    {cliPrefix}NewPR
    {cliPrefix}NewPR -Draft
    {cliPrefix}NewPR -AutoComplete
    {cliPrefix}NewPR -File .\current\223086-....prompt.md

.NOTES
    Depends on: az cli (for access token), git, ADO REST API v7.1
    Config: reads org/promptsRoot from $global:P20Config
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    # A card: its path, its filename, or its ID (119, K7M2) -- resolved by the one
    # rule every verb uses, Resolve-P20CardArgument.
    [Parameter()]
    [string]$File,

    [Parameter()]
    [string]$TargetBranch = 'master',

    [Parameter()]
    [switch]$Draft,

    [Parameter()]
    [switch]$AutoComplete,

    [Parameter()]
    [switch]$SkipWorkItem,

    [Parameter()]
    [string]$Repository,

    [Parameter()]
    [string]$Project,

    [Parameter()]
    [switch]$Help
)

# The "PR URL:" line this script writes is the state gate Get-PromptStatus.ps1
# and agent/core/parsers.py read back. One place: consts.json.
. (Join-Path $PSScriptRoot 'Get-Consts.ps1')
$script:Consts = Get-P20Consts

# Get-CliPrefix normally comes from the module. These scripts are also invoked
# directly -- by tests, by a user running the .ps1, by anything that wants -Help
# without importing first -- so a missing helper must not be fatal.
if (-not (Get-Command Get-CliPrefix -ErrorAction SilentlyContinue)) {
    function Get-CliPrefix {
        if ($global:P20Config -and $global:P20Config.CommandPrefix) { return $global:P20Config.CommandPrefix }
        return ''
    }
}


# -- Help ---------------------------------------------------------------------
function Show-Help {
    Write-Host @"

New-P20PullRequest - Ship-it workflow: PR + ADO card + prompt file

USAGE:
    $(Get-CliPrefix)NewPR [-Draft] [-AutoComplete] [-SkipWorkItem] [-File <path>]

WORKFLOW:
    1. Create PR     -- title from prompt heading, described changes as description
    2. ADO card      -- move work item to Code Review state
    3. ADO comment   -- post described changes + PR link
    4. Prompt file   -- write PR URL (triggers Code Review in $(Get-CliPrefix)Status)

PARAMETERS:
    -File <string>         The card: a path, a filename, or its ID (119, K7M2). Default: the card
                           current/ holds for this branch.
    -TargetBranch <string> Target branch. Default: master.
    -Draft                 Create as draft PR.
    -AutoComplete          Squash merge + delete source branch on completion.
    -SkipWorkItem          Skip ADO card state change and comment.
    -Repository <string>   ADO repo name. Default: auto-detected from git remote.
    -Project <string>      ADO project name. Default: auto-detected from git remote.
    -WhatIf                Resolve everything and say what would be done; call nothing.
    -Help                  Show this help message.

EXAMPLES:
    $(Get-CliPrefix)NewPR                          # auto-detect everything from branch + prompt
    $(Get-CliPrefix)NewPR -Draft                   # create as draft
    $(Get-CliPrefix)NewPR -AutoComplete            # auto-complete on approval
    $(Get-CliPrefix)NewPR -SkipWorkItem            # PR only, no ADO card update
    $(Get-CliPrefix)NewPR -File .\current\223086-ms-teams-....prompt.md
    $(Get-CliPrefix)NewPR -File 119 -Draft -WhatIf   # the card by ID; show, do not act

NOTES:
    - From the code repository, on the work branch, everything is inferred:
      branch -> card -> work item ID, title, described changes.
    - Named by -File from anywhere else (the web UI runs verbs in the Toolkit's own
      folder), the CARD answers instead: its ADO Link names the project and its
      ## Branch section the source branch. The Toolkit's own checkout is never
      read as a card's code repository.
    - A project or repository that cannot be told is a refusal, never a guess.
    - Ctrl-click the PR URL in the prompt file to open in browser for PoP.

"@ -ForegroundColor Cyan
    exit 0
}

if ($Help) { Show-Help }

# The one byte contract for a card this script writes into.
. (Join-Path $PSScriptRoot 'Write-CardText.ps1')

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

# -- Config -------------------------------------------------------------------
$cfg = $global:P20Config
if (-not $cfg) {
    Write-CliError -Message "Toolkit config not loaded. Is utilities.psm1 imported?"
    exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
}

$org = $cfg.Org

# -- Which card, which checkout ----------------------------------------------
# The card is the authoritative answer and is asked FIRST. A -File that is not a path
# on disk is resolved as a card by the one rule every verb uses, so `NewPR 119`
# finds demo/current/US-119-... -- it used to bind 119 to -File, fail Test-Path
# and stop, which was the only thing keeping the browser's Create PR from acting
# on the wrong repository.
. (Join-Path $PSScriptRoot 'Resolve-CardName.ps1')
if ($File -and -not (Test-Path -LiteralPath $File)) {
    $cardFolders = Get-PromptFolders
    $cardHit = Resolve-P20CardArgument -Argument $File -Folder $cardFolders.Current `
        -WorkItemTypes (Get-P20WorkItemTypes -Config $cfg)
    if ($cardHit.IsId) {
        $cardMatches = @($cardHit.Match | Where-Object { $_.Name -like '*.prompt.md' })
        if ($cardMatches.Count -eq 1) { $File = $cardMatches[0].FullName }
        elseif ($cardMatches.Count -gt 1) {
            Write-CliError -Message "'$File' matches $($cardMatches.Count) cards in current/: $(($cardMatches | ForEach-Object { $_.Name }) -join ', ')" `
                -Hint 'Name the card by its filename.'
            exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
        }
        else {
            Write-CliError -Message "No card with id '$File' in current/." `
                -Hint "Scaffold it first ($(Get-CliPrefix)NewPrompt $File), or pass the card's path."
            exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
        }
    }
}

# Is the process standing in a CODE checkout? The Toolkit's own checkout never is
# one -- it is where the bridge runs every verb, so from the browser the cwd's
# branch and remote are toolkit's, never the card's. Asked of git in its own
# terms (--absolute-git-dir, resolved identically on both sides), not by
# comparing path strings.
$toolkitRoot = Split-Path -Parent $PSScriptRoot
$cwdGitDir = "$(git rev-parse --absolute-git-dir 2>$null)".Trim()
$cwdIsRepo = ($LASTEXITCODE -eq 0 -and $cwdGitDir)
$toolkitGitDir = "$(git -C $toolkitRoot rev-parse --absolute-git-dir 2>$null)".Trim()
$cwdIsToolkit = ($cwdIsRepo -and $toolkitGitDir -and ($cwdGitDir -eq $toolkitGitDir))
$cwdIsCode = ($cwdIsRepo -and -not $cwdIsToolkit)

# The card's own branch -- the first line of its ## Branch section that is not a
# comment or a placeholder. What the browser has instead of a checkout.
$cardBranch = ''
if ($File -and (Test-Path -LiteralPath $File)) {
    $cardText = [System.IO.File]::ReadAllText((Resolve-Path -LiteralPath $File).Path) -replace "`r`n", "`n"
    $branchSection = [regex]::Match($cardText, '(?ms)^##\s+Branch\s*$\n(.*?)(?=^##\s|\z)')
    if ($branchSection.Success) {
        foreach ($line in ($branchSection.Groups[1].Value -split "`n")) {
            $t = $line.Trim()
            if (-not $t -or $t.StartsWith('<!--') -or $t.StartsWith('(') -or $t -match '^\{.*\}$') { continue }
            $cardBranch = $t -replace '^`|`$', ''
            break
        }
    }
}

# -- The source branch ---------------------------------------------------------
# Standing in a code checkout: its branch, as it always was. Anywhere else, with a
# card named: the card's ## Branch. Neither: there is nothing honest to use.
$currentBranch = ''
if ($cwdIsCode) {
    $currentBranch = "$(git rev-parse --abbrev-ref HEAD 2>$null)".Trim()
}
elseif ($cardBranch) {
    $currentBranch = $cardBranch
    Write-Host "[*] Not in the card's code repository -- the branch is the card's own: $cardBranch" -ForegroundColor DarkGray
}
if (-not $currentBranch) {
    $why = 'Not in a git repository, and no card was named.'
    if ($cwdIsToolkit) { $why = "This is the Toolkit's own checkout, not a card's code repository, and no card with a branch was named." }
    elseif ($File) { $why = "Not in a code repository, and the card names no branch under ## Branch." }
    Write-CliError -Message $why -Hint "Run $(Get-CliPrefix)NewPR from the code repository on the work branch, or name the card: $(Get-CliPrefix)NewPR -File <id>."
    exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
}

# -- Auto-detect project/repo -------------------------------------------------
$allProjects = @($cfg.Projects | ForEach-Object { @{ Name = $_.name; Repo = $_.repo; DefaultBranch = [string]$_.defaultBranch } })

# WHICH tracker ships this PR follows the board's address
# (D-G4). On a GitHub board the repo comes
# from the cwd's github remote when standing in a code checkout, else from the
# one board rule (Resolve-P20TrackerRepo); the OWNER plays the project's role
# in every message below. The ADO sniffing blocks are gated off this path.
. (Join-Path $PSScriptRoot 'Resolve-Tracker.ps1')
$trackerKind = Resolve-P20Tracker -OrgUrl $org
# Which space, which tracker, before anything is opened against it.
#
Write-P20TrackerHeader -Name $cfg.ActiveOrgName -OrgUrl $org
$ghRepoFull = ''
if ($trackerKind -eq 'github') {
    $ghOwner = Get-P20TrackerOwner -OrgUrl $org
    if (-not $Repository -and $cwdIsCode) {
        $ghRemote = "$(git remote get-url origin 2>$null)".Trim()
        if ($LASTEXITCODE -eq 0 -and $ghRemote -match 'github\.com[:/]([^/]+)/([^/]+?)(?:\.git)?$') {
            $ghOwner = $Matches[1]
            $Repository = $Matches[2]
        }
    }
    if (-not $Repository) {
        $repoAnswer = Resolve-P20TrackerRepo -OrgUrl $org -Projects $cfg.Projects -CliPrefix (Get-CliPrefix)
        if (-not $repoAnswer.Repo) {
            # No guess, for a write -- the ADO rule, kept.
            Write-CliError -Message "$($repoAnswer.Reason) Nothing is guessed for a pull request." -Hint $repoAnswer.Hint
            exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
        }
        $ghOwner = $repoAnswer.Repo.Split('/')[0]
        $Repository = $repoAnswer.Repo.Split('/')[1]
    }
    if (-not $Project) { $Project = $ghOwner }
    $ghRepoFull = "$ghOwner/$Repository"
}

# When -File is passed, the prompt's ADO Link is the authoritative signal for
# which project we're shipping to -- the shell's cwd (and thus its git remote)
# may be a different repo entirely, e.g. the prompts orchestration repo.
if ($trackerKind -ne 'github' -and $File -and (Test-Path -LiteralPath $File) -and
    (-not $PSBoundParameters.ContainsKey('Project') -or -not $PSBoundParameters.ContainsKey('Repository'))) {
    $adoLinkLine = Select-String -Path $File -Pattern 'ADO Link.*dev\.azure\.com/[^/]+/([^/]+)/_workitems' | Select-Object -First 1
    if ($adoLinkLine) {
        $linkProject = [Uri]::UnescapeDataString($adoLinkLine.Matches[0].Groups[1].Value)
        $linkEntries = @($allProjects | Where-Object { $_.Name -eq $linkProject })
        if ($linkEntries.Count -gt 0) {
            if (-not $PSBoundParameters.ContainsKey('Project')) { $Project = $linkProject }
            # The ADO Link only encodes the project. Only let it decide the repo
            # when the project has exactly one configured repo; otherwise leave
            # Repository unset so the cwd git-remote fallback disambiguates.
            if (-not $PSBoundParameters.ContainsKey('Repository') -and $linkEntries.Count -eq 1) {
                $Repository = $linkEntries[0].Repo
            }
        } else {
            Write-CliError -Message "Prompt file's ADO Link points at project '$linkProject', which is not in the active Space's config." -Hint "Check $(Get-CliPrefix)SwitchOrg Status."
        exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
        }
    }
}

# Fall back to the git remote of the process cwd -- only when the cwd IS a code
# checkout. The Toolkit's own remote says nothing about a card.
$remoteUrl = ''
if ($trackerKind -ne 'github' -and $cwdIsCode -and (-not $Project -or -not $Repository)) {
    $remoteUrl = git remote get-url origin 2>&1
    if ($LASTEXITCODE -eq 0) {
        $remoteUrl = "$remoteUrl".Trim()
        # HTTPS clone URL shape: dev.azure.com/org/project/_git/repo
        # SSH clone URL shape:   ssh.dev.azure.com:v3/org/project/repo
        if ($remoteUrl -match 'dev\.azure\.com/[^/]+/([^/]+)/_git/([^/]+)' -or
            $remoteUrl -match 'ssh\.dev\.azure\.com[:/]v3/[^/]+/([^/]+)/([^/]+?)(?:\.git)?$') {
            $detectedProject = [Uri]::UnescapeDataString($Matches[1])
            $detectedRepo = [Uri]::UnescapeDataString($Matches[2])
            if (-not $Project) { $Project = $detectedProject }
            if (-not $Repository) { $Repository = $detectedRepo }
        }
    }
}

# No guess. This used to default to the FIRST configured project and its repo --
# for a write that cannot be undone from this product -- and from the browser it
# picked an unrelated project with a warning, stopped only by an argument binding
# error.
# A read may guess; this refuses.
if (-not $Project -or -not $Repository) {
    if (-not $Project -and $allProjects.Count -eq 0) {
        Write-CliError -Message "Could not detect project/repo and none configured." -Hint "Pass -Project and -Repository, or add projects to the Space in hub.json."
        exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
    }
    if ($Project -and -not $Repository) {
        $match = @($allProjects | Where-Object { $_.Name -eq $Project })
        if ($match.Count -eq 1) { $Repository = $match[0].Repo }
    }
    if (-not $Project -or -not $Repository) {
        $what = if (-not $Project) { 'which Azure DevOps project' } else { "which repository in '$Project'" }
        $from = if ($remoteUrl) { "the card's ADO Link and this checkout's remote ($remoteUrl) do not say" } else { "the card's ADO Link does not say, and this is not the card's code checkout" }
        Write-CliError -Message "Could not tell $what this pull request is for: $from." `
            -Hint "Pass -Project and -Repository, or run $(Get-CliPrefix)NewPR from the code repository. Nothing is guessed for a write."
        exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
    }
}

# -- Resolve target branch: explicit -TargetBranch wins, else the matching
# project's configured defaultBranch, else the 'master' fallback (defaults
# over flags). Matched by repo
# name since one ADO project can contain multiple repos with different
# default branches.
if (-not $PSBoundParameters.ContainsKey('TargetBranch')) {
    $matchingProject = $allProjects | Where-Object { $_.Repo -eq $Repository } | Select-Object -First 1
    if ($matchingProject -and $matchingProject.DefaultBranch) {
        $TargetBranch = $matchingProject.DefaultBranch
    }
}

if ($currentBranch -eq $TargetBranch) {
    Write-CliError -Message "Current branch '$currentBranch' is the same as target '$TargetBranch'." -Hint "Check out the work branch, or pass -TargetBranch."
    exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
}

Write-Host "[*] Repo: $Project / $Repository" -ForegroundColor DarkGray
Write-Host "[*] Branch: $currentBranch -> $TargetBranch" -ForegroundColor DarkGray

# -- Find prompt file ---------------------------------------------------------
$folders = Get-PromptFolders
$currentDir = $folders.Current
$promptFile = $null

if ($File) {
    if (Test-Path -LiteralPath $File) {
        $promptFile = (Resolve-Path -LiteralPath $File).Path
    } else {
        Write-CliError -Message "Specified file not found: $File"
        exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
    }
} else {
    # One rule, in one file, because ThreadHash asks the same question --
    # Scripts/Resolve-CardForBranch.ps1. It used to live here and ThreadHash
    # answered a different question ("the most recently modified card"), which
    # is how a commit landed on the wrong card.
    #
    . (Join-Path $PSScriptRoot 'Resolve-CardForBranch.ps1')
    $found = Resolve-P20CardForBranch -Branch $currentBranch -CurrentDir $currentDir -Detailed
    $promptFile = $found.Path
    if (-not $promptFile -and $found.Candidates.Count -gt 1) {
        # Ambiguity is never guessed at (docs/CLI.md, Errors).
        Write-CliError -Message "Branch '$currentBranch' matches $($found.Candidates.Count) prompt files." `
            -Hint "Name the card with -File: $($found.Candidates -join ', ')"
        exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
    }
}

if (-not $promptFile) {
    Write-CliError -Message "No prompt file matches branch '$currentBranch'." -Hint "Looked in $currentDir. Use -File to name the card."
    exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
}

Write-Host "[*] Prompt: $(Split-Path $promptFile -Leaf)" -ForegroundColor DarkGray

# -- Parse prompt file --------------------------------------------------------
$promptContent = Get-Content -Path $promptFile -Raw

# Title: first heading line. Tolerant of "# Bug 232127: ...", "# User Story 452: ...",
# or a plain "# <title>". (?m) so ^/$ match per-line in the raw multi-line content.
$prTitle = $null
# The id in the heading has the shape of ANY card id -- a work item number or the
# four-character id of a card with no work item -- and the type is whatever
# workItemTypes names, not the four this line used to list.
. (Join-Path $PSScriptRoot 'Resolve-CardName.ps1')
$p20Types = Get-P20WorkItemTypes -Config $global:P20Config
$p20TypeNames = @($p20Types.Keys | ForEach-Object { [regex]::Escape([string]$_) }) + 'US'
$p20TitlePattern = '(?m)^#\s+(?i:' + ($p20TypeNames -join '|') + ')\s+(?:' + (Get-P20CardIdShape) + '):\s*(.+)$'
if ($promptContent -match $p20TitlePattern) {
    $prTitle = $Matches[1].Trim().TrimEnd('.')
} elseif ($promptContent -match '(?m)^#\s+(.+)$') {
    $prTitle = $Matches[1].Trim()
}
if (-not $prTitle) {
    $prTitle = git log -1 --format='%s' 2>&1
    $prTitle = "$prTitle".Trim()
    Write-Host "[!] No title heading found in prompt -- using commit message instead." -ForegroundColor Yellow
    Write-ToolkitLog -Type WARN -Source "$(Get-CliPrefix)NewPR" -Detail "title fallback to commit message"
}

# Work item ID: from the ADO Link line (tolerate **bold** markdown around the label) or
# the filename prefix (digits, optionally after a US-/Bug-/Task- prefix).
$workItemId = $null
if ($promptContent -match '(?m)^\s*\*{0,2}ADO Link:\*{0,2}\s*(https://\S+)') {
    $adoUrl = $Matches[1]
    if ($adoUrl -match '/edit/(\d+)' -or $adoUrl -match '/(\d+)/?$') {
        $workItemId = [int]$Matches[1]
    }
}
if (-not $workItemId) {
    # The one id rule. Only a NUMBER is a work item: a card with no work item has
    # no board to move, and takes the "ADO card will NOT be moved" path below.
    $p20FileId = Get-P20CardId -Name (Split-Path $promptFile -Leaf) -Pattern (Get-P20CardIdPattern -WorkItemTypes $p20Types)
    if (Test-P20IsWorkItemId $p20FileId) { $workItemId = [int]$p20FileId }
}
if (-not $workItemId) {
    Write-Host "[!] No work item ID found in prompt -- ADO card will NOT be moved to Code Review and no comment will be posted." -ForegroundColor Yellow
    Write-ToolkitLog -Type WARN -Source "$(Get-CliPrefix)NewPR" -Detail "no work item ID parsed; ADO tracking skipped"
}

# Described Changes: capture the section body up to the next H2, allowing a heading suffix
# (e.g. "## Described Changes (as built)") and a leading non-bullet paragraph; keep the bullets.
#
# Wrapped bullets are folded back into one line. A bullet that soft-wraps in the editor
# continues on a line with no leading dash, and keeping only dash-led lines silently
# discarded the rest -- the truncation then landed mid-sentence in the PR description AND
# in the work item comment, the two places other people read this. Found on card 113,
# where "...asserting all eleven buttons" lost "end disabled."
#
# A function, not inline, so the parser can be tested without running the script.
function Get-DescribedChanges {
    param([string]$Content)

    if ($Content -match '(?ms)^## Described Changes[^\r\n]*\r?\n(.*?)(?=^## |\z)') {
        $body = $Matches[1]
    }
    else {
        return $null
    }

    $bullets = @()
    foreach ($line in ($body -split '\r?\n')) {
        if ($line -match '^\s*-\s+\S') {
            $bullets += $line.Trim()
        }
        elseif ($line.Trim() -and $bullets.Count -gt 0) {
            # A continuation of the bullet above. Anything before the first bullet
            # is a lead-in paragraph and is deliberately not carried.
            $bullets[$bullets.Count - 1] = $bullets[$bullets.Count - 1] + ' ' + $line.Trim()
        }
    }

    if ($bullets.Count -eq 0) { return $null }
    return (($bullets -join "`n").Trim())
}

$describedChanges = Get-DescribedChanges $promptContent

# Check for PR URL already present
if ($promptContent -match $script:Consts.regex.prUrlLine) {
    Write-CliError -Message "Prompt file already has a PR URL. Is this branch already in review?" -Hint "Remove the existing PR URL line if you want to create a new PR."
    exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
}

Write-Host ""
Write-Host "[*] Title: $prTitle" -ForegroundColor White
if ($workItemId) { Write-Host "[*] Work Item: $workItemId" -ForegroundColor White }
if ($describedChanges) {
    Write-Host "[*] Described Changes:" -ForegroundColor White
    $describedChanges -split "`n" | ForEach-Object { Write-Host "    $_" -ForegroundColor Gray }
} else {
    Write-Host "[!] No described changes found in prompt -- PR description and ADO comment will be empty." -ForegroundColor Yellow
    Write-ToolkitLog -Type WARN -Source "$(Get-CliPrefix)NewPR" -Detail "no described changes parsed"
}
Write-Host ""

# On stage: a pull request on a public repository is read by strangers.
# One line, said before -WhatIf stops, so the dry run shows it too.
if ($trackerKind -eq 'github') {
    . (Join-Path $PSScriptRoot 'Get-RepoVisibility.ps1')
    Write-P20PublicLine -Repo $ghRepoFull
}

# -WhatIf: everything above is resolved and said; nothing below is called -- no
# token, no pull request, no work item change, no write to the card.
if (-not $PSCmdlet.ShouldProcess("$Project/$Repository", "Open a pull request $currentBranch -> $TargetBranch for $(Split-Path $promptFile -Leaf)")) {
    Write-Host "[=] -WhatIf: no pull request was opened, no work item moved, nothing written." -ForegroundColor Cyan
    exit 0
}

$ErrorActionPreference = 'Stop'

# -- A GitHub board: gh does steps 1-3, then falls through to the SHARED
# step 4 (the PR URL written through the one card writer). The ADO flow sits
# in the else below, untouched and unindented on purpose -- phase 8 moves it
# wholesale, and re-indenting 200 lines today would bury this diff.
if ($trackerKind -eq 'github') {
    # The BASE: when -TargetBranch was not passed and no configured project
    # answered, ask the REPO itself -- the address already names the source
    # of truth, and the 'master' fallback predates GitHub spaces
    # (found by the first
    # dogfood PR: toolkit's default is main, like most of the world's).
    if (-not $PSBoundParameters.ContainsKey('TargetBranch') -and $TargetBranch -eq 'master') {
        $repoDefault = [string](gh repo view $ghRepoFull --json defaultBranchRef -q '.defaultBranchRef.name' 2>$null)
        if ($LASTEXITCODE -eq 0 -and $repoDefault) { $TargetBranch = $repoDefault.Trim() }
    }

    # Is the branch on GitHub? From the web UI there is no checkout to push
    # from -- asked first, so the refusal says what to do (the ADO rule, kept).
    $null = gh api "repos/$ghRepoFull/branches/$([Uri]::EscapeDataString($currentBranch))" 2>$null
    if ($LASTEXITCODE -ne 0) {
        Write-CliError -Message "Branch '$currentBranch' is not on GitHub ($ghRepoFull), so there is nothing to open a pull request from." `
            -Hint "Push it from the code repository: git push -u origin $currentBranch -- then run $(Get-CliPrefix)NewPR again."
        exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
    }

    Write-Host "[1/4] Creating PR..." -ForegroundColor Cyan
    $prBodyText = ''
    if ($describedChanges) { $prBodyText = $describedChanges }
    if ($workItemId) {
        # A PLAIN reference, never "Closes #n": closing the issue is
        # CloseItem's job, and an auto-close on merge would reconcile the
        # two ledgers behind the person's back.
        $prBodyText = ("$prBodyText`n`nIssue: #$workItemId").Trim()
    }
    $ghCreateArgs = @('pr', 'create', '--repo', $ghRepoFull, '--head', $currentBranch,
        '--base', $TargetBranch, '--title', $prTitle, '--body', $prBodyText)
    if ($Draft) { $ghCreateArgs += '--draft' }
    $createOut = @(gh @ghCreateArgs 2>&1)
    if ($LASTEXITCODE -ne 0) {
        $said = ($createOut -join ' ').Trim()
        if ($said -match 'already exists') {
            Write-CliError -Message "A PR already exists for branch '$currentBranch' targeting '$TargetBranch'." -Hint $said
        }
        else {
            Write-CliError -Message "Create PR failed -- $said" -Hint "Check gh auth status, or $(Get-CliPrefix)Log -Errors."
        }
        exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
    }
    $prUrl = ($createOut | Where-Object { $_ -match '^https://github\.com/' } | Select-Object -Last 1).Trim()
    $prId = if ($prUrl -match '/pull/(\d+)') { [int]$Matches[1] } else { 0 }
    Write-Host "[+] PR #$prId created" -ForegroundColor Green
    if ($Draft) { Write-Host "    (draft)" -ForegroundColor DarkGray }

    if ($AutoComplete -and $prUrl) {
        gh pr merge --auto --squash --delete-branch $prUrl *> $null
        if ($LASTEXITCODE -eq 0) { Write-Host "[+] Auto-merge enabled (squash, delete branch)" -ForegroundColor Green }
        else {
            Write-Host "[~] PR created but auto-merge could not be enabled -- the repo may not allow it." -ForegroundColor Yellow
            Write-ToolkitLog -Type WARN -Source "$(Get-CliPrefix)NewPR" -Detail "gh auto-merge failed"
        }
    }

    # Steps 2-3, GitHub-shaped: no Code Review state exists to move an issue
    # to -- the card's own lane comes from the PR URL: line, as ever -- so the
    # issue's ledger entry is the COMMENT, in markdown, which GitHub renders.
    if (-not $SkipWorkItem -and $workItemId) {
        Write-Host "[2/4] No issue state to move on GitHub -- the card's lane comes from the PR URL line" -ForegroundColor DarkGray
        Write-Host "[3/4] Posting the PR and described changes to issue #$workItemId..." -ForegroundColor Cyan
        $ghCommentLines = @("PR created: $prUrl")
        if ($describedChanges) {
            $ghCommentLines += ''
            $ghCommentLines += '**Described Changes:**'
            $ghCommentLines += $describedChanges
        }
        gh issue comment $workItemId --repo $ghRepoFull --body ($ghCommentLines -join "`n") *> $null
        if ($LASTEXITCODE -eq 0) { Write-Host "[+] Comment posted to the issue" -ForegroundColor Green }
        else {
            Write-Host "[~] Failed to comment on issue #$workItemId -- the PR exists; add the link on GitHub." -ForegroundColor Yellow
            Write-ToolkitLog -Type WARN -Source "$(Get-CliPrefix)NewPR" -Detail "gh issue comment failed"
        }
    }
    elseif (-not $workItemId) {
        Write-Host "[2/4] No issue number found -- skipping the issue comment" -ForegroundColor Yellow
        Write-Host "[3/4] Skipped" -ForegroundColor DarkGray
    }
    else {
        Write-Host "[2/4] Skipped (--SkipWorkItem)" -ForegroundColor DarkGray
        Write-Host "[3/4] Skipped (--SkipWorkItem)" -ForegroundColor DarkGray
    }
}
else {

# -- Auth ---------------------------------------------------------------------
try {
    . (Join-Path $PSScriptRoot 'Get-AdoToken.ps1')
    $tokenRead = Get-P20AdoToken -Tenant $global:P20Config.Tenant
    if (-not $tokenRead.Ok) {
        Write-CliError -Message $tokenRead.Message -Hint $tokenRead.Hint
        exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
    }
    $token = $tokenRead.Token
    $headers = Get-P20AdoHeaders -Token $token
    $patchHeaders = Get-P20AdoHeaders -Token $token -ContentType 'application/json-patch+json'
} catch {
    Write-CliError -Message "Auth failed -- $($_.Exception.Message)"
    exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
}

# -- Is the branch on Azure DevOps? --------------------------------------------
# From the web UI there is no checkout to push from: the branch comes off the
# card, and a branch that was never pushed made ADO answer a bare "400 (Bad
# Request)" (found from the browser). Asked first, so the
# refusal says what to do. A lookup that itself fails does not block: the
# create below still runs and states whatever ADO says.
$encodedProject = [Uri]::EscapeDataString($Project)
try {
    $refsUri = "$org/$encodedProject/_apis/git/repositories/$Repository/refs?filter=heads/$([Uri]::EscapeDataString($currentBranch))&api-version=7.1"
    $refs = Invoke-RestMethod -Uri $refsUri -Headers $headers -Method Get
    $exact = @($refs.value | Where-Object { $_.name -eq "refs/heads/$currentBranch" })
    if ($exact.Count -eq 0) {
        Write-CliError -Message "Branch '$currentBranch' is not on Azure DevOps ($Project/$Repository), so there is nothing to open a pull request from." `
            -Hint "Push it from the code repository: git push -u origin $currentBranch -- then run $(Get-CliPrefix)NewPR again."
        exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
    }
}
catch {
    Write-Host "[*] Could not check the branch on Azure DevOps first ($($_.Exception.Message)); trying the create." -ForegroundColor DarkGray
}

# == STEP 1: Create PR ========================================================
Write-Host "[1/4] Creating PR..." -ForegroundColor Cyan

$prBody = @{
    sourceRefName = "refs/heads/$currentBranch"
    targetRefName = "refs/heads/$TargetBranch"
    title         = $prTitle
    isDraft       = [bool]$Draft
}

if ($describedChanges) {
    $prBody.description = $describedChanges
}

if ($workItemId) {
    $prBody.workItemRefs = @(@{ id = "$workItemId" })
}

$jsonBody = $prBody | ConvertTo-Json -Depth 3

try {
    $uri = "$org/$encodedProject/_apis/git/repositories/$Repository/pullrequests?api-version=7.1"
    $pr = Invoke-RestMethod -Uri $uri -Headers $headers -Method Post -Body $jsonBody
} catch {
    # ONE block: this used to print a red [!] line and then an Error: under it.
    $statusCode = $_.Exception.Response.StatusCode
    $msg = $_.Exception.Message
    # ADO puts the reason in the response body; the exception only says
    # "400 (Bad Request)". Surface ADO's own sentence when there is one.
    if ($_.ErrorDetails -and $_.ErrorDetails.Message) {
        try { $adoSaid = ($_.ErrorDetails.Message | ConvertFrom-Json).message; if ($adoSaid) { $msg = $adoSaid } } catch { $null = $_ }
    }
    if ($statusCode -eq 409) {
        Write-CliError -Message "A PR already exists for branch '$currentBranch' targeting '$TargetBranch'." -Hint "Fetch it with $(Get-CliPrefix)GetPRComments -BranchName $currentBranch."
    } elseif ($statusCode -eq 404) {
        Write-CliError -Message "Repository '$Repository' not found in project '$Project'." -Hint "Pass -Project and -Repository, or check the Space's projects in hub.json."
    } elseif ($msg -match 'refused|8888|proxy') {
        Write-CliError -Message "Create PR failed -- $msg" -Hint "A debugging proxy may be stale: [System.Net.Http.HttpClient]::DefaultProxy = New-Object System.Net.WebProxy"
    } else {
        Write-CliError -Message "Create PR failed -- $msg" -Hint "Check $(Get-CliPrefix)Log -Errors."
    }
    exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
}

$prId = $pr.pullRequestId
$prUrl = "$org/$encodedProject/_git/$Repository/pullrequest/$prId"

Write-Host "[+] PR #$prId created" -ForegroundColor Green
if ($Draft) { Write-Host "    (draft)" -ForegroundColor DarkGray }

# -- Auto-complete ------------------------------------------------------------
if ($AutoComplete -and $prId) {
    try {
        $acBody = @{
            autoCompleteSetBy = @{ id = $pr.createdBy.id }
            completionOptions = @{
                mergeStrategy      = 'squash'
                deleteSourceBranch = $true
            }
        } | ConvertTo-Json -Depth 3

        $acUri = "$org/$encodedProject/_apis/git/repositories/$Repository/pullrequests/$($prId)?api-version=7.1"
        Invoke-RestMethod -Uri $acUri -Headers $headers -Method Patch -Body $acBody | Out-Null
        Write-Host "[+] Auto-complete enabled (squash, delete branch)" -ForegroundColor Green
    } catch {
        Write-Host "[~] PR created but auto-complete failed -- $($_.Exception.Message)" -ForegroundColor Yellow
        Write-ToolkitLog -Type WARN -Source "$(Get-CliPrefix)NewPR" -Detail "auto-complete: $($_.Exception.Message)"
    }
}

# == STEP 2: Move ADO card to Code Review =====================================
if (-not $SkipWorkItem -and $workItemId) {
    Write-Host "[2/4] Moving work item $workItemId to Code Review..." -ForegroundColor Cyan

    try {
        $wiUri = "$org/_apis/wit/workitems/$($workItemId)?api-version=7.1"
        $wi = Invoke-RestMethod -Uri $wiUri -Headers @{ Authorization = "Bearer $token" } -Method Get
        $currentState = $wi.fields.'System.State'

        if ($currentState -eq 'Code Review' -or $currentState -eq 'Resolved' -or $currentState -eq 'Closed') {
            Write-Host "[~] Work item already in '$currentState' -- skipping state change" -ForegroundColor Yellow
        } else {
            # Not every work item type has a "Code Review" state (e.g. Bug in some
            # orgs goes Active -> Resolved directly) -- check before attempting so
            # the common case doesn't warn on every single PR.
            # Falls through to
            # attempting the move if the states query itself fails, so a
            # transient lookup failure doesn't silently skip a valid transition.
            $wiType = $wi.fields.'System.WorkItemType'
            $wiProject = [Uri]::EscapeDataString([string]$wi.fields.'System.TeamProject')
            $codeReviewIsValid = $true
            try {
                $statesUri = "$org/$wiProject/_apis/wit/workitemtypes/$([Uri]::EscapeDataString($wiType))/states?api-version=7.1"
                $states = Invoke-RestMethod -Uri $statesUri -Headers @{ Authorization = "Bearer $token" } -Method Get
                $codeReviewIsValid = [bool]($states.value | Where-Object { $_.name -eq 'Code Review' })
            } catch {
                # Couldn't determine valid states -- fall back to attempting.
                $null = $_
            }

            if (-not $codeReviewIsValid) {
                Write-Host "[~] '$wiType' has no 'Code Review' state in this project -- skipping state change" -ForegroundColor DarkGray
            } else {
                # System.Reason must travel in the SAME patch as System.State or the
                # transition 400s even when "Code Review" is valid for the type.
                # Close-WorkItem.ps1 has always done this; this script did not, and
                # the failure looked like an invalid state rather than a malformed
                # request. Documented in agentic/pr-ship.prompt.md before it was fixed.
                $statePatch = @(
                    @{ op = "add"; path = "/fields/System.State";  value = "Code Review" }
                    @{ op = "add"; path = "/fields/System.Reason"; value = "Work started" }
                ) | ConvertTo-Json -Depth 3

                Invoke-RestMethod -Uri $wiUri -Headers $patchHeaders -Method Patch -Body $statePatch | Out-Null
                Write-Host "[+] Work item moved to Code Review" -ForegroundColor Green
            }
        }
    } catch {
        $msg = $_.Exception.Message
        Write-Host "[~] Failed to update work item state -- $msg" -ForegroundColor Yellow
        if ($msg -match 'refused|8888|proxy') {
            Write-Host "    Hint: Fiddler proxy may be stale. Run:" -ForegroundColor DarkGray
            Write-Host "    [System.Net.Http.HttpClient]::DefaultProxy = New-Object System.Net.WebProxy" -ForegroundColor DarkGray
        } elseif ($msg -match '400') {
            Write-Host "    Hint: Work item may not support 'Code Review' state. Move it manually in ADO." -ForegroundColor DarkGray
        }
        Write-ToolkitLog -Type WARN -Source "$(Get-CliPrefix)NewPR" -Detail "work item state: $msg"
    }
} elseif (-not $workItemId) {
    Write-Host "[2/4] No work item ID found -- skipping ADO card update" -ForegroundColor Yellow
} else {
    Write-Host "[2/4] Skipped (--SkipWorkItem)" -ForegroundColor DarkGray
}

# == STEP 3: Post ADO comment with described changes ==========================
if (-not $SkipWorkItem -and $workItemId) {
    Write-Host "[3/4] Posting described changes to work item..." -ForegroundColor Cyan

    try {
        $wiProject = if ($wi) { $wi.fields.'System.TeamProject' } else { $Project }
        $encodedWiProject = [Uri]::EscapeDataString($wiProject)

        $commentLines = @()
        $commentLines += "PR created: <a href=`"$prUrl`">#$prId</a>"
        if ($describedChanges) {
            $commentLines += ""
            $commentLines += "<b>Described Changes:</b>"
            # Convert markdown bullets to HTML
            $describedChanges -split "`n" | ForEach-Object {
                $line = $_.Trim()
                if ($line -match '^- (.+)$') {
                    $commentLines += "- $($Matches[1])"
                }
            }
        }
        $commentText = $commentLines -join "<br/>"

        $commentUri = "$org/$encodedWiProject/_apis/wit/workItems/$workItemId/comments?api-version=7.1-preview"
        $commentBody = @{ text = $commentText } | ConvertTo-Json -Depth 3
        Invoke-RestMethod -Uri $commentUri -Headers $headers -Method Post -Body $commentBody | Out-Null
        Write-Host "[+] Comment posted to work item" -ForegroundColor Green
    } catch {
        $msg = $_.Exception.Message
        Write-Host "[~] Failed to post comment -- $msg" -ForegroundColor Yellow
        if ($msg -match 'refused|8888|proxy') {
            Write-Host "    Hint: Fiddler proxy may be stale. Clear with [System.Net.Http.HttpClient]::DefaultProxy = New-Object System.Net.WebProxy" -ForegroundColor DarkGray
        }
        Write-ToolkitLog -Type WARN -Source "$(Get-CliPrefix)NewPR" -Detail "comment: $msg"
    }
} elseif (-not $workItemId) {
    Write-Host "[3/4] No work item ID -- skipping comment" -ForegroundColor Yellow
} else {
    Write-Host "[3/4] Skipped (--SkipWorkItem)" -ForegroundColor DarkGray
}

}
# -- end of the ADO else; both trackers land here with $prId and $prUrl set --

# == STEP 4: Write PR URL into prompt file ====================================
Write-Host "[4/4] Writing PR URL to prompt file..." -ForegroundColor Cyan

try {
    $lines = Get-Content -Path $promptFile
    $insertIndex = -1

    # Insert after the last Git commit line, before ## Work Item Info
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match '^## Work Item Info') {
            $insertIndex = $i
            break
        }
    }

    if ($insertIndex -gt 0) {
        $prUrlLine = "$($script:Consts.tokens.prUrl) $prUrl"
        $newLines = @()
        $newLines += $lines[0..($insertIndex - 1)]
        $newLines += $prUrlLine
        $newLines += ""
        $newLines += $lines[$insertIndex..($lines.Count - 1)]
        # Through the one card writer: no BOM under 5.1, and the file's own line
        # endings kept -- Set-Content wrote the platform's, and a BOM.
        Write-CardText -Path $promptFile -Content (($newLines -join "`n") + "`n")
        Write-Host "[+] PR URL written to prompt file" -ForegroundColor Green
    } else {
        Write-Host "[~] Could not find insertion point -- appending to end" -ForegroundColor Yellow
                Write-CardText -Path $promptFile -Content ((Get-Content -Path $promptFile -Raw).TrimEnd("`r", "`n") + "`n`n$($script:Consts.tokens.prUrl) $prUrl`n")
    }
} catch {
    Write-Host "[~] Failed to update prompt file -- $($_.Exception.Message)" -ForegroundColor Yellow
    Write-Host "    Manually add: $($script:Consts.tokens.prUrl) $prUrl" -ForegroundColor Gray
    Write-ToolkitLog -Type WARN -Source "$(Get-CliPrefix)NewPR" -Detail "prompt file: $($_.Exception.Message)"
}

# -- Summary ------------------------------------------------------------------
Write-Host ""
Write-Host "[+] Done. PR #$prId is live." -ForegroundColor Green
Write-Host "    $prUrl" -ForegroundColor Cyan
Write-Host ""

Write-Output $prId
