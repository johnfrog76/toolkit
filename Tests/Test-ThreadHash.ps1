<#
.SYNOPSIS
    Tests for Thread-CommitHash.ps1 -- which repository the hashes come from,
    one bullet per commit with its subject, idempotence, and the byte contract.
.DESCRIPTION
    Every case builds TWO trees, because the bug this suite exists for was that
    they were confused for one another: a scratch HUB (its own git repo, with
    its own commits) and a scratch CODE repo (three commits on a branch off
    main). ThreadHash is run from the code repo and must record the code repo's
    hashes -- the hub's HEAD must never appear in a card.

    Run:  pwsh -File Tests/Test-ThreadHash.ps1
    Or:   {cliPrefix}TestToolkit -ThreadHash
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$pkgRoot = Split-Path $scriptDir -Parent
$threadScript = Join-Path $pkgRoot 'Scripts/Thread-CommitHash.ps1'
if (-not (Test-Path $threadScript)) {
    Write-Error "Thread-CommitHash.ps1 not found at $threadScript"
    return
}

# ── Test harness ──────────────────────────────────────────────────────────────

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
    if ($Expected -eq $Actual) {
        $script:passed++
        Write-Host "  PASS  $TestName" -ForegroundColor Green
    }
    else {
        $script:failed++
        $msg = "  FAIL  $TestName -- expected [$Expected] got [$Actual]"
        $script:errors += $msg
        Write-Host $msg -ForegroundColor Red
    }
}

# ── Sandbox ───────────────────────────────────────────────────────────────────

function Initialize-Repo {
    param([string]$Path, [string]$UserName)
    New-Item -ItemType Directory -Path $Path -Force | Out-Null
    Push-Location $Path
    try {
        git init --quiet 2>&1 | Out-Null
        git checkout -B main --quiet 2>&1 | Out-Null
        git config user.email 'test@example.com' 2>&1 | Out-Null
        git config user.name $UserName 2>&1 | Out-Null
        git config commit.gpgsign false 2>&1 | Out-Null
        git config core.autocrlf false 2>&1 | Out-Null
    }
    finally { Pop-Location }
}

function Add-Commit {
    param([string]$Repo, [string]$FileName, [string]$Message)
    Set-Content -Path (Join-Path $Repo $FileName) -Value "$Message`n" -Encoding UTF8
    Push-Location $Repo
    try {
        git add . 2>&1 | Out-Null
        git commit -m $Message --quiet 2>&1 | Out-Null
        return "$(git rev-parse --short=7 HEAD)".Trim()
    }
    finally { Pop-Location }
}

$script:cardBody = @'
# Bug 137: Something is wrong

## Git

<!-- One commit PER LINE as a bullet: "- {short-hash} {message}". -->

Commits:

- (pending)

## Summary

Nothing yet.
'@

function New-ThreadSandbox {
    <#
        Returns @{ Hub; Code; Card; HubHead; CodeHashes }.
        The hub is a git repo with its own commits -- that is the trap.
    #>
    param([switch]$Crlf, [string]$Branch = 'user/137-something-is-wrong')

    $base = Join-Path ([System.IO.Path]::GetTempPath()) ("test-threadhash-" + [System.Guid]::NewGuid().Guid.Substring(0, 8))
    $hub = Join-Path $base 'hub'
    $code = Join-Path $base 'BowlingApp'

    Initialize-Repo -Path $hub -UserName 'Hub Test'
    New-Item -ItemType Directory -Path (Join-Path $hub 'current') -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $hub 'archive') -Force | Out-Null

    $body = $script:cardBody -replace "`r`n", "`n"
    if ($Crlf) { $body = $body -replace "`n", "`r`n" }
    $card = Join-Path (Join-Path $hub 'current') '137-something-is-wrong.prompt.md'
    [System.IO.File]::WriteAllText($card, $body, (New-Object System.Text.UTF8Encoding($false)))

    $hubHead = Add-Commit -Repo $hub -FileName 'ledger.md' -Message 'Archive Bug 114'

    Initialize-Repo -Path $code -UserName 'Code Test'
    Add-Commit -Repo $code -FileName 'README.md' -Message 'initial' | Out-Null
    Push-Location $code
    try { git checkout -b $Branch --quiet 2>&1 | Out-Null } finally { Pop-Location }
    $h1 = Add-Commit -Repo $code -FileName 'one.txt' -Message 'first real change'
    $h2 = Add-Commit -Repo $code -FileName 'two.txt' -Message 'second real change'
    $h3 = Add-Commit -Repo $code -FileName 'three.txt' -Message 'third real change'

    $global:P20Config = @{ PromptsRoot = $hub; StoreSync = 'git'; CommandPrefix = 'tk'; Projects = @() }

    return @{
        Base       = $base
        Hub        = $hub
        Code       = $code
        Card       = $card
        HubHead    = $hubHead
        CodeHashes = @($h1, $h2, $h3)
    }
}

function Remove-ThreadSandbox {
    param($Sandbox)
    if ($Sandbox -and $Sandbox.Base -and (Test-Path $Sandbox.Base)) {
        Remove-Item -Path $Sandbox.Base -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# Stub Get-PromptFolders the way utilities.psm1 wires it for a real run.
function Get-PromptFolders {
    $root = $global:P20Config.PromptsRoot
    return @{ Current = (Join-Path $root 'current'); Archive = (Join-Path $root 'archive') }
}

function Invoke-ThreadHash {
    <#
        Runs the script from $From and returns @{ Text; Exit }.
    #>
    param([string]$From, [hashtable]$BoundArgs = @{})
    $prevErr = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    Push-Location $From
    try {
        $global:LASTEXITCODE = 0
        $out = & $threadScript @BoundArgs *>&1 | Out-String
        $code = $LASTEXITCODE
    }
    finally {
        Pop-Location
        $ErrorActionPreference = $prevErr
    }
    return @{ Text = $out; Exit = $code }
}

function Get-CardText {
    param([string]$Path)
    return [System.IO.File]::ReadAllText($Path)
}

# ══════════════════════════════════════════════════════════════════════════════

Write-Host ""
Write-Host "═══════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "  ThreadHash Tests" -ForegroundColor Cyan
Write-Host "═══════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host ""

# -- The hashes come from the code repo, not the hub ---------------------------

Write-Host "-- The repo the command is run in ---------------------" -ForegroundColor Cyan

$sb = New-ThreadSandbox
try {
    $r = Invoke-ThreadHash -From $sb.Code -BoundArgs @{ File = $sb.Card }
    $text = Get-CardText $sb.Card

    Assert-Equal "a run from the code repo exits 0" 0 $r.Exit
    foreach ($h in $sb.CodeHashes) {
        Assert-True "the card carries $h" ($text -match [regex]::Escape($h)) $text
    }
    Assert-True "the hub's own HEAD never appears" ($text -notmatch [regex]::Escape($sb.HubHead)) $sb.HubHead
    Assert-True "each commit carries its subject" ($text -match 'first real change' -and $text -match 'second real change' -and $text -match 'third real change') $text
    Assert-True "the commits are in the order they were made" `
        ($text.IndexOf($sb.CodeHashes[0]) -lt $text.IndexOf($sb.CodeHashes[1]) -and
         $text.IndexOf($sb.CodeHashes[1]) -lt $text.IndexOf($sb.CodeHashes[2]))
    Assert-True "the (pending) placeholder is gone" ($text -notmatch '\(pending\)') $text
    Assert-True "the base branch's own commit is not threaded" ($text -notmatch 'initial') $text

    $bullets = @([regex]::Matches($text, '(?m)^-\s+[0-9a-f]{7,}\s'))
    Assert-Equal "exactly three commit bullets" 3 $bullets.Count

    # Status's contract: a bullet whose hash is 7+ hex reads In Progress.
    Assert-True "the card now reads In Progress to Status" ($text -match '(?m)^\s*-\s+`?[0-9a-f]{7,}`?')
}
catch {
    Assert-True 'the cases ran to the end without a terminating error' $false $_.Exception.Message
}
finally { Remove-ThreadSandbox $sb }

Write-Host ""

# -- Re-running adds nothing ---------------------------------------------------

Write-Host "-- Idempotence ----------------------------------------" -ForegroundColor Cyan

$sb = New-ThreadSandbox
try {
    Invoke-ThreadHash -From $sb.Code -BoundArgs @{ File = $sb.Card } | Out-Null
    $first = Get-CardText $sb.Card
    $r = Invoke-ThreadHash -From $sb.Code -BoundArgs @{ File = $sb.Card }
    $second = Get-CardText $sb.Card

    Assert-Equal "the second run exits 0" 0 $r.Exit
    Assert-True "the second run changed nothing" ($first -eq $second)
    Assert-True "the second run says so" ($r.Text -match 'nothing to add') $r.Text
    $bullets = @([regex]::Matches($second, '(?m)^-\s+[0-9a-f]{7,}\s'))
    Assert-Equal "still exactly three commit bullets" 3 $bullets.Count

    # A fourth commit after the first run is picked up, and only it.
    $h4 = Add-Commit -Repo $sb.Code -FileName 'four.txt' -Message 'fourth real change'
    Invoke-ThreadHash -From $sb.Code -BoundArgs @{ File = $sb.Card } | Out-Null
    $third = Get-CardText $sb.Card
    Assert-True "a later commit is threaded on the next run" ($third -match [regex]::Escape($h4))
    $bullets = @([regex]::Matches($third, '(?m)^-\s+[0-9a-f]{7,}\s'))
    Assert-Equal "four bullets after a fourth commit" 4 $bullets.Count
}
catch {
    Assert-True 'the cases ran to the end without a terminating error' $false $_.Exception.Message
}
finally { Remove-ThreadSandbox $sb }

Write-Host ""

# -- Outside a git repository it refuses ---------------------------------------

Write-Host "-- Not a git repository -------------------------------" -ForegroundColor Cyan

$sb = New-ThreadSandbox
try {
    $outside = Join-Path $sb.Base 'not-a-repo'
    New-Item -ItemType Directory -Path $outside -Force | Out-Null

    $r = Invoke-ThreadHash -From $outside -BoundArgs @{ File = $sb.Card }
    $text = Get-CardText $sb.Card

    Assert-Equal "a non-repo location is a stated refusal (exit 2)" 2 $r.Exit
    Assert-True "the refusal says it is not a git repository" ($r.Text -match 'Not in a git repository') $r.Text
    Assert-True "the refusal names -Hash as the alternative" ($r.Text -match '-Hash') $r.Text
    Assert-True "the card was not written" ($text -match '\(pending\)') $text
    Assert-True "the hub's HEAD was not threaded" ($text -notmatch [regex]::Escape($sb.HubHead)) $sb.HubHead

    # -Hash is the stated way out, and it works from the same location.
    $r2 = Invoke-ThreadHash -From $outside -BoundArgs @{ File = $sb.Card; Hash = 'abc1234' }
    $text2 = Get-CardText $sb.Card
    Assert-Equal "-Hash from a non-repo exits 0" 0 $r2.Exit
    Assert-True "-Hash threaded the explicit hash" ($text2 -match '(?m)^- abc1234\s*$') $text2
    Assert-True "-Hash removed the placeholder" ($text2 -notmatch '\(pending\)') $text2
}
catch {
    Assert-True 'the cases ran to the end without a terminating error' $false $_.Exception.Message
}
finally { Remove-ThreadSandbox $sb }

Write-Host ""

# -- The byte contract ---------------------------------------------------------

Write-Host "-- The bytes the card keeps ---------------------------" -ForegroundColor Cyan

$sb = New-ThreadSandbox -Crlf
try {
    Invoke-ThreadHash -From $sb.Code -BoundArgs @{ File = $sb.Card } | Out-Null
    $bytes = [System.IO.File]::ReadAllBytes($sb.Card)
    $text = [System.Text.Encoding]::UTF8.GetString($bytes)

    Assert-True "a CRLF card has no BOM after the edit" `
        (-not ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF))
    $lone = [regex]::Matches($text, "(?<!`r)`n")
    Assert-Equal "a CRLF card has no lone LF left in it" 0 $lone.Count
    Assert-True "the inserted bullets are CRLF too" ($text -match "`r`n- $($sb.CodeHashes[0]) first real change`r`n")
}
catch {
    Assert-True 'the cases ran to the end without a terminating error' $false $_.Exception.Message
}
finally { Remove-ThreadSandbox $sb }

$sb = New-ThreadSandbox
try {
    Invoke-ThreadHash -From $sb.Code -BoundArgs @{ File = $sb.Card } | Out-Null
    $bytes = [System.IO.File]::ReadAllBytes($sb.Card)
    $text = [System.Text.Encoding]::UTF8.GetString($bytes)

    Assert-True "an LF card has no BOM after the edit" `
        (-not ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF))
    Assert-True "an LF card stays LF" ($text -notmatch "`r")
}
catch {
    Assert-True 'the cases ran to the end without a terminating error' $false $_.Exception.Message
}
finally { Remove-ThreadSandbox $sb }

Write-Host ""

# -- The card is resolved from the branch, not from mtime ----------------------

Write-Host "-- Which card, with no -File --------------------------" -ForegroundColor Cyan

$sb = New-ThreadSandbox
try {
    # A decoy card touched AFTER the real one: "most recently modified" would
    # pick this, and used to.
    $decoy = Join-Path (Join-Path $sb.Hub 'current') '999-a-different-card.prompt.md'
    [System.IO.File]::WriteAllText($decoy, ($script:cardBody -replace "`r`n", "`n"), (New-Object System.Text.UTF8Encoding($false)))

    $r = Invoke-ThreadHash -From $sb.Code
    $real = Get-CardText $sb.Card
    $other = Get-CardText $decoy

    Assert-Equal "resolving from the branch exits 0" 0 $r.Exit
    Assert-True "the branch's own card got the commits" ($real -match [regex]::Escape($sb.CodeHashes[0])) $real
    Assert-True "the more recently written card was left alone" ($other -match '\(pending\)') $other

    # A branch that matches no card is a stated refusal, not a guess.
    Push-Location $sb.Code
    try { git checkout -b user/555-no-such-card --quiet 2>&1 | Out-Null } finally { Pop-Location }
    $r2 = Invoke-ThreadHash -From $sb.Code
    Assert-Equal "a branch with no card refuses (exit 2)" 2 $r2.Exit
    Assert-True "the refusal names the branch" ($r2.Text -match 'user/555-no-such-card') $r2.Text
}
catch {
    Assert-True 'the cases ran to the end without a terminating error' $false $_.Exception.Message
}
finally { Remove-ThreadSandbox $sb }

Write-Host ""

# -- The branch resolver reads ids with the ONE rule ---------------------------
# It used to match `^$id-` against the filename, which can only ever find a
# bare-bug card: a Task or a Story starts with its type, so it was never found
# from its branch.
# And an id need not be a number (docs/hub/cards.md, "The filename").

Write-Host "-- A prefixed card, and a lettered id, from a branch ---" -ForegroundColor Cyan

. (Join-Path (Join-Path $pkgRoot 'Scripts') 'Resolve-CardForBranch.ps1')
$resolverDir = Join-Path ([System.IO.Path]::GetTempPath()) ("p20-resolver-" + [System.Guid]::NewGuid().Guid.Substring(0, 8))
New-Item -ItemType Directory -Path $resolverDir -Force | Out-Null
try {
    foreach ($name in @('Task139-extract-scoring-rules.prompt.md', 'US-144-paginate-the-list.prompt.md',
            '114-a-bare-bug.prompt.md', 'TaskK7M2-wallet-ticket-from-a-qr-code.prompt.md', 'Q4TN-a-bug-with-no-work-item.prompt.md')) {
        [System.IO.File]::WriteAllText((Join-Path $resolverDir $name), "# card`n", (New-Object System.Text.UTF8Encoding($false)))
    }
    $leaf = { param($p) if ($p) { Split-Path $p -Leaf } else { '(none)' } }
    Assert-Equal 'a Task branch finds its Task card, by id, through its type prefix' 'Task139-extract-scoring-rules.prompt.md' (& $leaf (Resolve-P20CardForBranch -Branch 'user/139-a-different-slug' -CurrentDir $resolverDir))
    Assert-Equal 'a story branch (three segments) finds its US- card' 'US-144-paginate-the-list.prompt.md' (& $leaf (Resolve-P20CardForBranch -Branch 'user/144/paginate' -CurrentDir $resolverDir))
    Assert-Equal 'a bare-bug branch still finds its card' '114-a-bare-bug.prompt.md' (& $leaf (Resolve-P20CardForBranch -Branch 'user/114-a-bare-bug' -CurrentDir $resolverDir))
    Assert-Equal 'a lettered id finds its card through a prefix' 'TaskK7M2-wallet-ticket-from-a-qr-code.prompt.md' (& $leaf (Resolve-P20CardForBranch -Branch 'user/K7M2-wallet-ticket' -CurrentDir $resolverDir))
    Assert-Equal 'a lettered id finds a bare card' 'Q4TN-a-bug-with-no-work-item.prompt.md' (& $leaf (Resolve-P20CardForBranch -Branch 'user/Q4TN-a-bug' -CurrentDir $resolverDir))
    Assert-Equal 'an id is not a substring: 39 does not find Task139' '(none)' (& $leaf (Resolve-P20CardForBranch -Branch 'user/39-something' -CurrentDir $resolverDir))
    Assert-Equal 'a lowercase branch word is not an id' '(none)' (& $leaf (Resolve-P20CardForBranch -Branch 'user/cat7-fix-the-thing' -CurrentDir $resolverDir))

    # Ambiguity is never guessed at: two cards are prefixes of the branch and
    # neither is its exact name. It used to return the first of them.
    #
    foreach ($name in @('212-a-fix.prompt.md', '212-a-fix-for.prompt.md')) {
        [System.IO.File]::WriteAllText((Join-Path $resolverDir $name), "# card`n", (New-Object System.Text.UTF8Encoding($false)))
    }
    Assert-Equal 'two prefix matches and no exact one is NOT a card' '(none)' (& $leaf (Resolve-P20CardForBranch -Branch 'user/212-a-fix-for-the-thing' -CurrentDir $resolverDir))
    $detail = Resolve-P20CardForBranch -Branch 'user/212-a-fix-for-the-thing' -CurrentDir $resolverDir -Detailed
    Assert-Equal '-Detailed names both candidates' 2 @($detail.Candidates).Count
    Assert-True '-Detailed has no path for an ambiguous branch' ($null -eq $detail.Path)
    Assert-Equal 'an exact name still wins over the other prefix match' '212-a-fix.prompt.md' (& $leaf (Resolve-P20CardForBranch -Branch 'user/212-a-fix' -CurrentDir $resolverDir))
    $one = Resolve-P20CardForBranch -Branch 'user/114-a-bare-bug' -CurrentDir $resolverDir -Detailed
    Assert-Equal '-Detailed on an unambiguous branch carries the path' '114-a-bare-bug.prompt.md' (Split-Path $one.Path -Leaf)
}
catch {
    Assert-True 'the cases ran to the end without a terminating error' $false $_.Exception.Message
}
finally { Remove-Item $resolverDir -Recurse -Force -ErrorAction SilentlyContinue }

Write-Host ""

# -- A card with no Git section --------------------------------------------

Write-Host "-- A card with no '## Git' section --------------------" -ForegroundColor Cyan

$sb = New-ThreadSandbox
try {
    [System.IO.File]::WriteAllText($sb.Card, "# Bug 137: Something is wrong`n`n## Summary`n`nNothing.`n", (New-Object System.Text.UTF8Encoding($false)))
    $r = Invoke-ThreadHash -From $sb.Code -BoundArgs @{ File = $sb.Card }

    Assert-Equal "a card with no Git section refuses (exit 2)" 2 $r.Exit
    Assert-True "the refusal names the section" ($r.Text -match '## Git') $r.Text
}
catch {
    Assert-True 'the cases ran to the end without a terminating error' $false $_.Exception.Message
}
finally { Remove-ThreadSandbox $sb }

Write-Host ""

# -- A planned card is pulled into play by its first thread --------------------
# A card in backlog/ never carries a commit bullet: the first ThreadHash MOVES
# the file to current/ as it writes, so the flow a person types is unchanged and
# the card arrives in play with its commits on it (Scripts/Move-CardFolder.ps1).

Write-Host "-- A planned card, pulled by its first thread ----------" -ForegroundColor Cyan

$sb = New-ThreadSandbox
try {
    $backlogDir = Join-Path $sb.Hub 'backlog'
    New-Item -ItemType Directory -Path $backlogDir -Force | Out-Null
    $planned = Join-Path $backlogDir (Split-Path $sb.Card -Leaf)
    Move-Item -LiteralPath $sb.Card -Destination $planned

    # From the branch, with no card named: backlog/ is searched beside current/.
    $r = Invoke-ThreadHash -From $sb.Code
    Assert-Equal "ThreadHash with no card, on the branch of a planned card, exits 0" 0 $r.Exit
    Assert-True "the card left backlog/" (-not (Test-Path -LiteralPath $planned))
    Assert-True "and is in current/, with every commit on it" ((Test-Path -LiteralPath $sb.Card) -and ((Get-CardText $sb.Card) -match [regex]::Escape($sb.CodeHashes[2])))
    Assert-True "the pull is said" ($r.Text -match 'pulled from backlog/ into current/') $r.Text

    # By id, and a refusal before the write leaves the planned card where it is.
    Move-Item -LiteralPath $sb.Card -Destination $planned
    [System.IO.File]::WriteAllText($planned, "# Bug 137: Something is wrong`n`n## Summary`n`nNothing.`n", (New-Object System.Text.UTF8Encoding($false)))
    $r = Invoke-ThreadHash -From $sb.Code -BoundArgs @{ File = '137' }
    Assert-Equal "a planned card ThreadHash cannot thread is refused (exit 2)" 2 $r.Exit
    Assert-True "and stays in backlog/: nothing moved, nothing written" ((Test-Path -LiteralPath $planned) -and -not (Test-Path -LiteralPath $sb.Card))
}
catch {
    Assert-True 'the cases ran to the end without a terminating error' $false $_.Exception.Message
}
finally { Remove-ThreadSandbox $sb }

Write-Host ""

# -- The configured defaultBranch is what the branch is measured against -------

Write-Host "-- defaultBranch comes from config --------------------" -ForegroundColor Cyan

$sb = New-ThreadSandbox
try {
    # A project whose defaultBranch is the scratch repo's folder name's match.
    $global:P20Config.Projects = @(
        [pscustomobject]@{ name = 'BowlingApp'; repo = 'BowlingApp'; defaultBranch = 'main' }
    )
    $r = Invoke-ThreadHash -From $sb.Code -BoundArgs @{ File = $sb.Card }
    $text = Get-CardText $sb.Card

    Assert-Equal "a configured project exits 0" 0 $r.Exit
    $bullets = @([regex]::Matches($text, '(?m)^-\s+[0-9a-f]{7,}\s'))
    Assert-Equal "three bullets against the configured default branch" 3 $bullets.Count
    Assert-True "the base branch's commit is still excluded" ($text -notmatch 'initial') $text
}
catch {
    Assert-True 'the cases ran to the end without a terminating error' $false $_.Exception.Message
}
finally { Remove-ThreadSandbox $sb }

Write-Host ""

# -- [commit] placeholders -----------------------------------------------------

Write-Host "-- [commit] placeholders in replies -------------------" -ForegroundColor Cyan

$sb = New-ThreadSandbox
try {
    $body = (Get-CardText $sb.Card) + "`n## PR Review Comments`n`nFixed in [commit].`n"
    [System.IO.File]::WriteAllText($sb.Card, $body, (New-Object System.Text.UTF8Encoding($false)))

    $r = Invoke-ThreadHash -From $sb.Code -BoundArgs @{ File = $sb.Card }
    $text = Get-CardText $sb.Card

    Assert-Equal "a card with placeholders exits 0" 0 $r.Exit
    Assert-True "the placeholder took the first hash threaded" ($text -match "Fixed in $($sb.CodeHashes[0])\.") $text
    Assert-True "no [commit] token is left" ($text -notmatch '\[commit\]') $text
    Assert-True "the run reports the replacement" ($r.Text -match 'placeholder') $r.Text
}
catch {
    Assert-True 'the cases ran to the end without a terminating error' $false $_.Exception.Message
}
finally { Remove-ThreadSandbox $sb }

Write-Host ""

# -- The card is an id, typed as a verb -----------------------------------------

Write-Host "-- ThreadHash <id>, typed as a verb -------------------" -ForegroundColor Cyan

$sb = New-ThreadSandbox
try {
    $prefix = (Get-Content (Join-Path $pkgRoot 'config.default.json') -Raw | ConvertFrom-Json).commandPrefix
    $logDir = Join-Path $sb.Base 'log'
    New-Item -ItemType Directory -Path $logDir -Force | Out-Null
    $preamble = "`$env:PSModulePath = '$pkgRoot'; `$env:PROMPTS_ROOT = '$($sb.Hub)'; `$env:P20_USAGE_LOG_DIR = '$logDir'; " +
        "Import-Module '$pkgRoot/Prompt20Toolkit/Prompt20Toolkit.psd1' -Force 3>`$null 6>`$null; Set-Location '$($sb.Code)'; "
    function Invoke-ThreadVerb {
        param([string]$Commands)
        return (& pwsh -NoProfile -NonInteractive -Command ($preamble + $Commands) 2>&1 | ForEach-Object { "$_" }) -join "`n"
    }

    # The verb looks in its own Space's folders, so the card is made by the verb --
    # and a new card is PLANNED: it lands in backlog/.
    $null = Invoke-ThreadVerb "${prefix}NewPrompt -Title 'Thread by id' -Type Task -Id K7M2 | Out-Null"
    $card = @(Get-ChildItem $sb.Hub -Recurse -Filter 'TaskK7M2-*.prompt.md')
    Assert-Equal 'the verb made the card to thread into' 1 $card.Count
    Assert-Equal 'in backlog/: planned, not in play' 'backlog' (Split-Path $card[0].DirectoryName -Leaf)
    $cardPath = $card[0].FullName
    $before = Get-CardText $cardPath
    $out = Invoke-ThreadVerb "${prefix}ThreadHash W3X7 -Hash $($sb.CodeHashes[0]); 'ID-NONE-EXIT=' + `$LASTEXITCODE"
    Assert-True 'an id that matches nothing is refused naming the id, exit 2' ($out -match "No card with id 'W3X7'" -and $out -match 'ID-NONE-EXIT=2') $out
    Assert-Equal 'and the refusal wrote nothing' $before (Get-CardText $cardPath)

    # The id form finds the planned card, and its first thread PULLS it into current/.
    $out = Invoke-ThreadVerb "${prefix}ThreadHash k7m2 -Hash $($sb.CodeHashes[0]); 'ID-EXIT=' + `$LASTEXITCODE"
    Assert-True 'the id form exits 0' ($out -match 'ID-EXIT=0') $out
    $card = @(Get-ChildItem $sb.Hub -Recurse -Filter 'TaskK7M2-*.prompt.md')
    Assert-True 'the first thread pulled the card from backlog/ into current/' ($card.Count -eq 1 -and (Split-Path $card[0].DirectoryName -Leaf) -eq 'current' -and $out -match 'pulled from backlog/ into current/') $out
    $cardPath = $card[0].FullName
    Assert-True 'the id form threads the hash' ((Get-CardText $cardPath) -match "(?m)^- $($sb.CodeHashes[0])\b") $out

    $out = Invoke-ThreadVerb "${prefix}ThreadHash thread-by -Hash $($sb.CodeHashes[1]); 'PART-EXIT=' + `$LASTEXITCODE"
    Assert-True 'the partial-name form exits 0' ($out -match 'PART-EXIT=0') $out
    Assert-True 'and names the card it chose' ($out -match "Matched 'thread-by' -> $([regex]::Escape($card[0].Name))") $out
    Assert-True 'and threads the hash' ((Get-CardText $cardPath) -match "(?m)^- $($sb.CodeHashes[1])\b") $out

    $out = Invoke-ThreadVerb "${prefix}ThreadHash '$cardPath' -Hash $($sb.CodeHashes[2]); 'PATH-EXIT=' + `$LASTEXITCODE"
    Assert-True 'a full path still works' ($out -match 'PATH-EXIT=0' -and (Get-CardText $cardPath) -match "(?m)^- $($sb.CodeHashes[2])\b") $out
}
catch {
    Assert-True 'the cases ran to the end without a terminating error' $false $_.Exception.Message
}
finally { Remove-ThreadSandbox $sb }

Write-Host ""

# -- Help ----------------------------------------------------------------------

Write-Host "-- Help -----------------------------------------------" -ForegroundColor Cyan

$sb = New-ThreadSandbox
try {
    $r = Invoke-ThreadHash -From $sb.Base -BoundArgs @{ Help = $true }
    Assert-Equal "-Help exits 0 outside any repo" 0 $r.Exit
    Assert-True "-Help names the -Hash form" ($r.Text -match '-Hash') $r.Text
    Assert-True "-Help says where to run it" ($r.Text -match 'repository you committed to') $r.Text
}
catch {
    Assert-True 'the cases ran to the end without a terminating error' $false $_.Exception.Message
}
finally { Remove-ThreadSandbox $sb }

Write-Host ""
Write-Host "═══════════════════════════════════════════════════════" -ForegroundColor Cyan
$total = $script:passed + $script:failed
Write-Host "  Results: $($script:passed)/$total passed" -ForegroundColor $(if ($script:failed -eq 0) { 'Green' } else { 'Red' })
if ($script:errors.Count -gt 0) {
    Write-Host ""
    Write-Host "  Failures:" -ForegroundColor Red
    foreach ($e in $script:errors) { Write-Host $e -ForegroundColor Red }
}
Write-Host "═══════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host ""

if ($script:failed -gt 0) { exit 1 }
exit 0
