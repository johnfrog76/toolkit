<#
.SYNOPSIS
    Seed the public GitHub repo the GitHub demo Space reads: files, labels,
    milestones and a dozen issues, all through gh. Run ONCE, by the repo's owner.

.DESCRIPTION
    The GitHub demo Space (`github-demo` in samples/hub/hub.json) points at
    a small public repo, johnfrog76/recipe-box-demo, so that a new user who has run
    `gh auth login` sees Issues, Board, Stats and Design read something real.
    This script puts that something there, from samples/recipe-box.seed.json:

      1. the repo itself, only with -CreateRepo (public, with the JSON's description);
      2. the files (README, a design note, a spec, a docs page) -- each only if absent;
      3. the house labels -- created, or brought in line with the JSON (gh label create --force);
      4. the milestones -- each only if no milestone has that title;
      5. the issues, IN ORDER -- each only if no issue has that title -- then closed
         or pinned as the JSON says;
      6. the milestones the JSON marks closed are closed last, once their issues are.

    It is safe to run again: everything that exists is left alone, by title or path.
    It never deletes, never edits an issue's text, and never touches another repo.

    NOT part of the toolkit and not a verb: nothing runs it but a person, and no
    suite calls it. The toolkit itself never writes to GitHub on a person's behalf
    for setup -- this is the owner's one-time job.

    The sample cards in samples/hub/github-demo/ link to issue numbers (5, 6, 9 in
    current/, 4 in archive/). On a fresh repo each issue lands on the `number` the
    JSON gives it; if one lands elsewhere, the script says which, so the cards can
    be corrected.

.PARAMETER Repo
    owner/name. Default: the JSON's `repo`.

.PARAMETER CreateRepo
    Create the repo (public) when it does not exist. Without it, a missing repo is
    a stated refusal.

.PARAMETER SeedFile
    The JSON. Default: recipe-box.seed.json beside this script.

.PARAMETER WhatIf
    Say what would be created; create nothing. gh is still asked what exists.

.EXAMPLE
    ./samples/seed-recipe-box.ps1 -WhatIf
.EXAMPLE
    ./samples/seed-recipe-box.ps1 -CreateRepo

.NOTES
    PowerShell 5.1 compatible: ASCII only, no ternary, no null-coalescing.
    Exit 0 done, 2 a stated refusal (the toolkit's refusal contract).
#>
[CmdletBinding()]
param(
    [string]$Repo,
    [switch]$CreateRepo,
    [string]$SeedFile,
    [switch]$WhatIf
)

$ErrorActionPreference = 'Stop'

function Write-SeedRefusal {
    param([string]$Message, [string]$Hint)
    Write-Host ""
    Write-Host "Error: $Message" -ForegroundColor Red
    if ($Hint) { Write-Host "Hint:  $Hint" -ForegroundColor Yellow }
    Write-Host ""
}

function Invoke-Gh {
    # One gh call. Returns @{ Ok; Out; Err }. gh writes its errors to stderr and
    # sets a non-zero exit; neither is allowed to throw here -- the caller decides.
    param([string[]]$Arguments)
    $errFile = [System.IO.Path]::GetTempFileName()
    $prev = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        $out = & gh @Arguments 2> $errFile
        $code = $LASTEXITCODE
        $err = ''
        if (Test-Path -LiteralPath $errFile) { $err = [System.IO.File]::ReadAllText($errFile) }
        return @{ Ok = ($code -eq 0); Out = (($out | Out-String).Trim()); Err = $err.Trim() }
    }
    finally {
        $ErrorActionPreference = $prev
        Remove-Item -LiteralPath $errFile -Force -ErrorAction SilentlyContinue
    }
}

function Write-Step {
    param([string]$Verb, [string]$What, [string]$Color = 'Green')
    Write-Host ("  {0,-9} {1}" -f $Verb, $What) -ForegroundColor $Color
}

$utf8NoBom = New-Object System.Text.UTF8Encoding($false)

# ---- the seed ------------------------------------------------------------------
if (-not $SeedFile) { $SeedFile = Join-Path $PSScriptRoot 'recipe-box.seed.json' }
if (-not (Test-Path -LiteralPath $SeedFile -PathType Leaf)) {
    Write-SeedRefusal -Message "The seed file is not there: $SeedFile" -Hint 'It ships beside this script as recipe-box.seed.json.'
    exit 2
}
try { $seed = [System.IO.File]::ReadAllText($SeedFile, $utf8NoBom) | ConvertFrom-Json }
catch {
    Write-SeedRefusal -Message "The seed file is not JSON: $SeedFile" -Hint $_.Exception.Message
    exit 2
}
if (-not $Repo) { $Repo = [string]$seed.repo }
if ($Repo -notmatch '^[^/\s]+/[^/\s]+$') {
    Write-SeedRefusal -Message "'$Repo' is not owner/name." -Hint 'For example: -Repo johnfrog76/recipe-box-demo'
    exit 2
}

# ---- gh, signed in -------------------------------------------------------------
if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
    Write-SeedRefusal -Message 'gh is not installed.' -Hint 'Install the GitHub CLI, run gh auth login, then run this again.'
    exit 2
}
$auth = Invoke-Gh @('auth', 'status')
if (-not $auth.Ok) {
    Write-SeedRefusal -Message 'gh is not signed in.' -Hint 'Run gh auth login yourself, then run this again.'
    exit 2
}

Write-Host ""
Write-Host "Seeding $Repo$(if ($WhatIf) { ' (-WhatIf: nothing is created)' })" -ForegroundColor Cyan

# ---- 1. the repo -----------------------------------------------------------------
$view = Invoke-Gh @('repo', 'view', $Repo, '--json', 'name')
if (-not $view.Ok) {
    if (-not $CreateRepo) {
        Write-SeedRefusal -Message "gh cannot read $Repo -- it does not exist, or this login cannot see it." `
            -Hint 'Create it with -CreateRepo (public), or check gh auth status.'
        exit 2
    }
    if ($WhatIf) { Write-Step 'would' "create the public repo $Repo" 'Yellow' }
    else {
        $made = Invoke-Gh @('repo', 'create', $Repo, '--public', '--description', [string]$seed.description)
        if (-not $made.Ok) {
            Write-SeedRefusal -Message "gh could not create $Repo." -Hint $made.Err
            exit 2
        }
        Write-Step 'created' "the public repo $Repo"
    }
}
else { Write-Step 'exists' "the repo $Repo" 'Gray' }
$repoExists = $view.Ok -or (-not $WhatIf)

# ---- 2. the files ------------------------------------------------------------------
# Through the contents API, each only when absent. On an empty repo the first PUT
# is the first commit, which is why the files go before anything else.
foreach ($file in @($seed.files)) {
    $path = [string]$file.path
    $have = $null
    if ($repoExists) { $have = Invoke-Gh @('api', "repos/$Repo/contents/$path") }
    if ($have -and $have.Ok) { Write-Step 'exists' $path 'Gray'; continue }
    if ($WhatIf) { Write-Step 'would' "add $path" 'Yellow'; continue }
    $text = (@($file.lines) -join "`n")
    $b64 = [System.Convert]::ToBase64String($utf8NoBom.GetBytes($text))
    $put = Invoke-Gh @('api', '--method', 'PUT', "repos/$Repo/contents/$path", '-f', "message=$([string]$file.message)", '-f', "content=$b64")
    if (-not $put.Ok) {
        Write-SeedRefusal -Message "gh could not add $path." -Hint $put.Err
        exit 2
    }
    Write-Step 'added' $path
}

# ---- 3. the labels -----------------------------------------------------------------
foreach ($label in @($seed.labels)) {
    if ($WhatIf) { Write-Step 'would' "label $($label.name)" 'Yellow'; continue }
    $made = Invoke-Gh @('label', 'create', [string]$label.name, '--repo', $Repo, '--color', [string]$label.color, '--description', [string]$label.description, '--force')
    if (-not $made.Ok) {
        Write-SeedRefusal -Message "gh could not write the label $($label.name)." -Hint $made.Err
        exit 2
    }
    Write-Step 'label' ([string]$label.name)
}

# ---- 4. the milestones ---------------------------------------------------------------
$milestones = @{}
if ($repoExists) {
    $list = Invoke-Gh @('api', "repos/$Repo/milestones?state=all&per_page=100")
    if ($list.Ok -and $list.Out) {
        foreach ($m in @($list.Out | ConvertFrom-Json)) { $milestones[[string]$m.title] = $m }
    }
}
# A due date reaches GitHub as the ISO text the JSON holds. ConvertFrom-Json
# turns an ISO 8601 string into a [datetime] -- on 5.1 and on 7 alike -- and
# [string] on that renders the machine's culture, "9/15/2026 12:00:00 AM" or
# "09/15/2026 00:00:00", which GitHub answers with a 422. Found by the first
# seed run, 2026-10-01. GitHub also reads a milestone's due date in US Pacific
# time, so the JSON carries noon UTC: midnight UTC lands on the day before.
function ConvertTo-SeedDate {
    param([object]$Value)
    if ($Value -is [datetime]) { return $Value.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ') }
    return [string]$Value
}

foreach ($m in @($seed.milestones)) {
    $title = [string]$m.title
    if ($milestones.ContainsKey($title)) { Write-Step 'exists' "milestone $title" 'Gray'; continue }
    if ($WhatIf) { Write-Step 'would' "milestone $title" 'Yellow'; continue }
    $made = Invoke-Gh @('api', '--method', 'POST', "repos/$Repo/milestones", '-f', "title=$title", '-f', "description=$([string]$m.description)", '-f', "due_on=$(ConvertTo-SeedDate $m.due_on)")
    if (-not $made.Ok) {
        Write-SeedRefusal -Message "gh could not create the milestone $title." -Hint $made.Err
        exit 2
    }
    $milestones[$title] = ($made.Out | ConvertFrom-Json)
    Write-Step 'milestone' $title
}

# ---- 5. the issues, in order -------------------------------------------------------------
$existing = @{}
if ($repoExists) {
    $list = Invoke-Gh @('issue', 'list', '--repo', $Repo, '--state', 'all', '--limit', '500', '--json', 'number,title')
    if ($list.Ok -and $list.Out) {
        foreach ($i in @($list.Out | ConvertFrom-Json)) { $existing[[string]$i.title] = [int]$i.number }
    }
}
$moved = @()
foreach ($issue in @($seed.issues)) {
    $title = [string]$issue.title
    $number = 0
    if ($existing.ContainsKey($title)) {
        $number = $existing[$title]
        Write-Step 'exists' "#$number $title" 'Gray'
    }
    elseif ($WhatIf) {
        Write-Step 'would' "issue $title$(if ($issue.state -eq 'closed') { ' (then close it)' })$(if ($issue.pin) { ' (then pin it)' })" 'Yellow'
        continue
    }
    else {
        $bodyFile = [System.IO.Path]::GetTempFileName()
        try {
            [System.IO.File]::WriteAllText($bodyFile, ((@($issue.body) -join "`n") + "`n"), $utf8NoBom)
            $ghArgs = @('issue', 'create', '--repo', $Repo, '--title', $title, '--body-file', $bodyFile)
            foreach ($l in @($issue.labels)) { $ghArgs += @('--label', [string]$l) }
            if ($issue.milestone) { $ghArgs += @('--milestone', [string]$issue.milestone) }
            $made = Invoke-Gh $ghArgs
        }
        finally { Remove-Item -LiteralPath $bodyFile -Force -ErrorAction SilentlyContinue }
        if (-not $made.Ok) {
            Write-SeedRefusal -Message "gh could not create the issue '$title'." -Hint $made.Err
            exit 2
        }
        # gh prints the new issue's URL; its last segment is the number.
        $url = (($made.Out -split "`n") | Where-Object { $_ -match '/issues/\d+' } | Select-Object -Last 1)
        if ($url -match '/issues/(\d+)') { $number = [int]$Matches[1] }
        Write-Step 'issue' "#$number $title"
        if ($issue.state -eq 'closed') {
            $closed = Invoke-Gh @('issue', 'close', [string]$number, '--repo', $Repo, '--reason', 'completed')
            if ($closed.Ok) { Write-Step 'closed' "#$number" } else { Write-Step 'NOT' "closed #$number -- $($closed.Err)" 'Yellow' }
        }
        if ($issue.pin) {
            $pinned = Invoke-Gh @('issue', 'pin', [string]$number, '--repo', $Repo)
            if ($pinned.Ok) { Write-Step 'pinned' "#$number" } else { Write-Step 'NOT' "pinned #$number -- $($pinned.Err)" 'Yellow' }
        }
    }
    if ($issue.number -and $number -and ([int]$issue.number -ne $number)) { $moved += "#$($issue.number) -> #$number  $title" }
}

# ---- 6. close the milestones the JSON marks closed ---------------------------------------
foreach ($m in @($seed.milestones)) {
    if ([string]$m.state -ne 'closed') { continue }
    $title = [string]$m.title
    if ($WhatIf) { Write-Step 'would' "close milestone $title" 'Yellow'; continue }
    $have = $milestones[$title]
    if (-not $have -or [string]$have.state -eq 'closed') { continue }
    $patched = Invoke-Gh @('api', '--method', 'PATCH', "repos/$Repo/milestones/$($have.number)", '-f', 'state=closed')
    if ($patched.Ok) { Write-Step 'closed' "milestone $title" } else { Write-Step 'NOT' "closed milestone $title -- $($patched.Err)" 'Yellow' }
}

Write-Host ""
if ($moved.Count -gt 0) {
    Write-Host "  Some issues did not land on the number the sample cards link to:" -ForegroundColor Yellow
    foreach ($line in $moved) { Write-Host "    $line" -ForegroundColor Yellow }
    Write-Host "  Correct the ADO Link lines in samples/hub/github-demo/ to match." -ForegroundColor Yellow
}
else { Write-Host "  Done. The GitHub demo Space can read https://github.com/$Repo now: sign in with gh and connect it (Connect github-demo)." -ForegroundColor Green }
Write-Host ""
exit 0
