<#
.SYNOPSIS
    Tests for Scripts/Update-Toolkit.ps1 -- the Update verb.

.DESCRIPTION
    The verb pulls the Toolkit's OWN repository, which it finds from where the
    script file sits. So each case builds a scratch "package": a bare remote, a
    publisher clone that pushes new commits to it, and a consumer clone with a
    copy of the real script dropped into its Scripts/ folder (untracked, so it is
    not itself a "local change"). No network, and the real checkout is never
    touched.

    What matters most about this verb is what it REFUSES to do -- it is software,
    so it is never auto-committed, rebased or pushed, and a developer's checkout
    is not something a convenience verb rewrites. Most cases are refusals, and
    each checks that HEAD did not move.

    Run:  pwsh -File Tests/Test-Update.ps1
    Or:   {cliPrefix}TestToolkit -Update

.NOTES
    PowerShell 5.1 compatible (ASCII dashes only).
#>

$pkgRoot = Split-Path -Parent $PSScriptRoot
$targetScript = Join-Path (Join-Path $pkgRoot 'Scripts') 'Update-Toolkit.ps1'
# Update-Toolkit.ps1 dot-sources this, so a sandbox standing in for a package
# has to carry it: a copy-install has the whole Scripts/ folder, and a sandbox
# with only the one file under test is a package no user ever has.
# Every script Update-Toolkit.ps1 dot-sources. Resolve-Python.ps1 was missing
# from this list, so the sandbox's Update fell back to `python3` -- wrong on the
# Windows, right by coincidence on macOS.
$helperScripts = @('Test-GitRoot.ps1', 'Resolve-Python.ps1', 'Initialize-CliFallbacks.ps1', 'Invoke-TrackerRead.ps1')

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
    Assert-True $TestName ($Expected -eq $Actual) "expected [$Expected] got [$Actual]"
}

Write-Host ""
Write-Host "=======================================================" -ForegroundColor Cyan
Write-Host "  Update verb" -ForegroundColor Cyan
Write-Host "=======================================================" -ForegroundColor Cyan
Write-Host ""

if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    Write-Host "  SKIP  git is not installed -- every case here needs a repository" -ForegroundColor DarkYellow
    # A stated skip still reports, as 0/0: the runner counts a suite with NO
    # Results line as one that threw, and reads 0/0 as a skip.
    Write-Host "  Results: 0/0 passed" -ForegroundColor DarkYellow
    exit 0
}

$base = Join-Path ([System.IO.Path]::GetTempPath()) ("p20-update-" + [System.Guid]::NewGuid().Guid.Substring(0, 8))
New-Item -ItemType Directory -Path $base -Force | Out-Null
$origin = Join-Path $base 'origin.git'
$publisher = Join-Path $base 'publisher'

function Invoke-Git {
    param([string]$Repo, [string[]]$GitArgs)
    return @(& git -C $Repo -c user.name=Test -c user.email=test@example.com -c commit.gpgsign=false -c core.autocrlf=false @GitArgs 2>&1 | ForEach-Object { "$_" })
}

function Write-RepoFile {
    param([string]$Repo, [string]$Rel, [string]$Text)
    $full = Join-Path $Repo $Rel
    New-Item -ItemType Directory -Path (Split-Path $full -Parent) -Force | Out-Null
    [System.IO.File]::WriteAllText($full, $Text, (New-Object System.Text.UTF8Encoding($false)))
}

function Publish-Commit {
    param([string]$Rel, [string]$Text, [string]$Message)
    Write-RepoFile $publisher $Rel $Text
    [void](Invoke-Git $publisher @('add', '-A'))
    [void](Invoke-Git $publisher @('commit', '-q', '-m', $Message))
    [void](Invoke-Git $publisher @('push', '-q', 'origin', 'main'))
}

function New-Consumer {
    # A fresh clone with the REAL script dropped in, untracked.
    param([string]$Name)
    $path = Join-Path $base $Name
    & git clone -q $origin $path 2>&1 | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $path 'Scripts') -Force | Out-Null
    Copy-Item $targetScript (Join-Path (Join-Path $path 'Scripts') 'Update-Toolkit.ps1')
    foreach ($h in $helperScripts) {
        Copy-Item (Join-Path (Join-Path $pkgRoot 'Scripts') $h) (Join-Path (Join-Path $path 'Scripts') $h) -Force
    }
    return $path
}

function Invoke-Update {
    param([string]$Consumer, [string[]]$ScriptArgs = @())
    $scriptPath = Join-Path (Join-Path $Consumer 'Scripts') 'Update-Toolkit.ps1'
    # From a DIFFERENT directory on purpose: the verb must find its repository
    # from where the script sits, never from the current directory.
    Push-Location $base
    try { $out = & pwsh -NoProfile -File $scriptPath @ScriptArgs 2>&1 | Out-String }
    finally { Pop-Location }
    return [pscustomobject]@{ Output = $out; ExitCode = $LASTEXITCODE }
}

function Get-Head { param([string]$Repo) return (Invoke-Git $Repo @('rev-parse', 'HEAD') | Select-Object -First 1) }

try {
    & git init -q --bare -b main $origin 2>&1 | Out-Null
    & git clone -q $origin $publisher 2>&1 | Out-Null
    [void](Invoke-Git $publisher @('checkout', '-q', '-b', 'main'))
    Publish-Commit 'utilities.psm1' "# v1`n" 'first'

    # -- Already up to date ----------------------------------------------------
    Write-Host "-- Already up to date ---------------------------------" -ForegroundColor Cyan
    $c = New-Consumer 'c-current'
    $r = Invoke-Update $c
    Assert-Equal 'exits 0' 0 $r.ExitCode
    Assert-True 'says it is up to date' ($r.Output -match 'Already up to date') $r.Output
    Assert-True 'names the package it looked at, not the current directory' ($r.Output -match [regex]::Escape((Split-Path $c -Leaf))) $r.Output

    # -- Behind: -WhatIf, then the real thing -----------------------------------
    Write-Host ""
    Write-Host "-- Behind the remote ----------------------------------" -ForegroundColor Cyan
    $c = New-Consumer 'c-behind'
    $before = Get-Head $c
    Publish-Commit 'Prompt20Toolkit/Prompt20Toolkit.psd1' "@{ v = 2 }`n" 'the alias set moved'
    Publish-Commit 'web/package-lock.json' "{ `"v`": 2 }`n" 'a web dependency moved'
    Publish-Commit 'agent/requirements.txt' "fastapi`n" 'an agent requirement moved'

    $preview = Invoke-Update $c @('-WhatIf')
    Assert-Equal '-WhatIf exits 0' 0 $preview.ExitCode
    Assert-True '-WhatIf says how far behind it is' ($preview.Output -match '3 new commit') $preview.Output
    Assert-True '-WhatIf names the commits' ($preview.Output -match 'the alias set moved') $preview.Output
    Assert-Equal '-WhatIf pulls nothing' $before (Get-Head $c)
    Assert-True '-WhatIf still says what would need a hand' ($preview.Output -match 'InstallAutoload -Force') $preview.Output

    $r = Invoke-Update $c
    Assert-Equal 'the update exits 0' 0 $r.ExitCode
    Assert-Equal 'HEAD is now the remote HEAD' (Get-Head $publisher) (Get-Head $c)
    Assert-True 'it says what it moved from and to' ($r.Output -match 'Updated \w+ -> \w+') $r.Output
    Assert-True 'a changed autoload shim is NOTICED, with the verb that fixes it' ($r.Output -match 'autoload shim changed\s+->\s+\S*InstallAutoload -Force') $r.Output
    Assert-True 'a changed lockfile names npm ci' ($r.Output -match 'npm ci') $r.Output
    Assert-True 'changed requirements name pip install' ($r.Output -match 'pip install -r agent/requirements-dev.txt') $r.Output
    # The command named is the interpreter that runs HERE, not the literal
    # `python3` -- which on Windows is the Store stub.
    . (Join-Path $pkgRoot 'Scripts/Resolve-Python.ps1')
    $expectedPython = Resolve-P20Python
    if ($expectedPython) {
        # The detail is the advice LINE, not the whole run: the line says which
        # interpreter it named and, when it fell back, why.
        $adviceLine = (@($r.Output -split "`r?`n" | Where-Object { $_ -match 'pip install' }) -join ' | ').Trim()
        Assert-True "the advice names the resolved interpreter ($($expectedPython.Display))" ($r.Output -match ('->  ' + [regex]::Escape($expectedPython.Display) + ' -m pip install')) $adviceLine
        Assert-True "and it is not a fallback guess" ($r.Output -notmatch 'python3 is a guess') $adviceLine
    }
    Assert-True 'it fast-forwarded: no merge commit was made' (-not (Invoke-Git $c @('log', '--merges', '--oneline')))
    Assert-True 'and nothing was pushed: the remote is where the publisher left it' ((Invoke-Git $origin @('rev-parse', 'main') | Select-Object -First 1) -eq (Get-Head $publisher))

    $again = Invoke-Update $c
    Assert-True 'a second run has nothing to do' ($again.Output -match 'Already up to date') $again.Output
    Assert-True 'and asks for nothing' ($again.Output -notmatch 'Also needed') $again.Output

    # -- Refusals: each one changes nothing --------------------------------------
    Write-Host ""
    Write-Host "-- It refuses rather than guesses ---------------------" -ForegroundColor Cyan

    $c = New-Consumer 'c-dirty'
    $before = Get-Head $c
    Publish-Commit 'utilities.psm1' "# v2`n" 'second'
    Write-RepoFile $c 'utilities.psm1' "# my local edit`n"
    $r = Invoke-Update $c @('-Sync')
    Assert-Equal 'uncommitted changes: a stated refusal (exit 2)' 2 $r.ExitCode
    Assert-True 'it says why' ($r.Output -match 'uncommitted change') $r.Output
    Assert-Equal 'HEAD did not move' $before (Get-Head $c)
    Assert-True 'the local edit is untouched' ((Get-Content (Join-Path $c 'utilities.psm1') -Raw) -match 'my local edit')
    Assert-True 'and a refused update does NOT go on to sync' ($r.Output -notmatch 'Prompt store:') $r.Output

    $c = New-Consumer 'c-untracked'
    Write-RepoFile $c 'scratch-notes.txt' "mine`n"
    $r = Invoke-Update $c
    Assert-Equal 'an UNTRACKED file is not a reason to refuse' 0 $r.ExitCode

    $c = New-Consumer 'c-diverged'
    Write-RepoFile $c 'local-only.txt' "a local commit`n"
    [void](Invoke-Git $c @('add', 'local-only.txt'))
    [void](Invoke-Git $c @('commit', '-q', '-m', 'local work'))
    $before = Get-Head $c
    Publish-Commit 'utilities.psm1' "# v3`n" 'third'
    $r = Invoke-Update $c
    Assert-Equal 'diverged history: a stated refusal (exit 2)' 2 $r.ExitCode
    Assert-True 'it says it only fast-forwards' ($r.Output -match 'diverged' -and $r.Output -match 'fast-forward') $r.Output
    Assert-Equal 'HEAD did not move -- no rebase, no merge' $before (Get-Head $c)

    $c = New-Consumer 'c-ahead'
    Write-RepoFile $c 'local-only.txt' "a local commit`n"
    [void](Invoke-Git $c @('add', 'local-only.txt'))
    [void](Invoke-Git $c @('commit', '-q', '-m', 'local work'))
    $r = Invoke-Update $c
    Assert-Equal 'local commits with nothing to pull: fine (exit 0)' 0 $r.ExitCode
    Assert-True 'and it mentions them rather than pushing them' ($r.Output -match '1 local commit\(s\) not pushed') $r.Output

    $c = New-Consumer 'c-detached'
    [void](Invoke-Git $c @('checkout', '-q', '--detach'))
    $r = Invoke-Update $c
    Assert-Equal 'a detached HEAD: a stated refusal (exit 2)' 2 $r.ExitCode
    Assert-True 'it says so' ($r.Output -match 'detached HEAD') $r.Output

    $c = New-Consumer 'c-noupstream'
    [void](Invoke-Git $c @('checkout', '-q', '-b', 'feature/x'))
    $r = Invoke-Update $c
    Assert-Equal 'a branch with no upstream: a stated refusal (exit 2)' 2 $r.ExitCode
    Assert-True 'it names the branch' ($r.Output -match "feature/x") $r.Output

    $plain = Join-Path $base 'c-copy'
    New-Item -ItemType Directory -Path (Join-Path $plain 'Scripts') -Force | Out-Null
    Copy-Item $targetScript (Join-Path (Join-Path $plain 'Scripts') 'Update-Toolkit.ps1')
    foreach ($h in $helperScripts) {
        Copy-Item (Join-Path (Join-Path $pkgRoot 'Scripts') $h) (Join-Path (Join-Path $plain 'Scripts') $h) -Force
    }
    $r = Invoke-Update $plain
    Assert-Equal 'a Toolkit installed as a COPY: a stated refusal (exit 2)' 2 $r.ExitCode
    Assert-True 'it says there is nothing to pull' ($r.Output -match 'not a git checkout') $r.Output

    # -- A Demo copied out before the covers shipped ----------------------
    # Update SAYS, once, and writes nothing: the verb that dresses them is Cover -Samples.
    Write-Host ""
    Write-Host "-- An older Demo: Update says, and writes nothing -----" -ForegroundColor Cyan
    $coverHelpers = @('Get-SampleCoverGaps.ps1', 'Add-CardImage.ps1', 'Invoke-TrackerRead.ps1', 'Get-Consts.ps1', 'Resolve-CardName.ps1', 'Set-CardLine.ps1', 'Write-CardText.ps1')
    function New-CoverConsumer {
        param([string]$Name)
        $path = New-Consumer $Name
        foreach ($h in $coverHelpers) {
            Copy-Item (Join-Path (Join-Path $pkgRoot 'Scripts') $h) (Join-Path (Join-Path $path 'Scripts') $h) -Force
        }
        Copy-Item (Join-Path $pkgRoot 'consts.json') (Join-Path $path 'consts.json') -Force
        Copy-Item (Join-Path $pkgRoot 'samples') (Join-Path $path 'samples') -Recurse -Force
        return $path
    }
    function New-OlderHub {
        param([string]$Path, [switch]$KeepCovers)
        Copy-Item (Join-Path $pkgRoot 'samples/hub') $Path -Recurse
        if ($KeepCovers) { return }
        foreach ($d in @(Get-ChildItem $Path -Directory)) {
            $a = Join-Path $d.FullName 'assets'
            if (Test-Path $a) { Remove-Item $a -Recurse -Force }
        }
        foreach ($f in @(Get-ChildItem $Path -Recurse -Filter '*.md')) {
            $t = [System.IO.File]::ReadAllText($f.FullName)
            $n = [regex]::Replace($t, '(?m)^\*\*Cover:\*\*[^\r\n]*\r?\n', '')
            if ($n -ne $t) { [System.IO.File]::WriteAllText($f.FullName, $n, (New-Object System.Text.UTF8Encoding($false))) }
        }
    }
    function Get-HubSnapshot {
        param([string]$Path)
        return ((@(Get-ChildItem $Path -Recurse -File | ForEach-Object { $_.FullName + '|' + $_.Length + '|' + [System.IO.File]::ReadAllText($_.FullName).GetHashCode() } | Sort-Object)) -join "`n")
    }
    $savedRoot = $env:PROMPTS_ROOT
    try {
        $c = New-CoverConsumer 'c-covers'
        $oldHub = Join-Path $base 'hub-old'
        New-OlderHub $oldHub
        [System.IO.File]::WriteAllText((Join-Path $oldHub 'demo/current/Task9ABC-mine.prompt.md'), "# Task 9ABC: mine`n", (New-Object System.Text.UTF8Encoding($false)))
        $snap = Get-HubSnapshot $oldHub
        $env:PROMPTS_ROOT = $oldHub
        $r = Invoke-Update $c
        Assert-Equal 'an older Demo: Update still exits 0' 0 $r.ExitCode
        Assert-True 'it names the count and the verb, in the Also-needed block' ($r.Output -match '10 sample cards in this hub have no cover\s+->\s+\S*Cover -Samples') $r.Output
        Assert-Equal 'and says it once' 1 ([regex]::Matches($r.Output, 'Cover -Samples')).Count
        Assert-Equal 'and writes nothing into the hub' $snap (Get-HubSnapshot $oldHub)

        $r = Invoke-Update $c @('-WhatIf')
        Assert-True 'the hint is the same under -WhatIf' ($r.Output -match '10 sample cards in this hub have no cover') $r.Output

        # One card dressed by hand: the count drops by one, and singular reads right at one.
        $env:PROMPTS_ROOT = (Join-Path $base 'hub-one')
        New-Item -ItemType Directory -Path (Join-Path $env:PROMPTS_ROOT 'demo/current') -Force | Out-Null
        Copy-Item (Join-Path $oldHub 'demo/current/214-search-returns-duplicates-when-tags-overlap.prompt.md') (Join-Path $env:PROMPTS_ROOT 'demo/current') -Force
        $r = Invoke-Update $c
        Assert-True 'one card: "1 sample card in this hub has no cover"' ($r.Output -match '1 sample card in this hub has no cover') $r.Output

        $dressedHub = Join-Path $base 'hub-dressed'
        New-OlderHub $dressedHub -KeepCovers
        $snap = Get-HubSnapshot $dressedHub
        $env:PROMPTS_ROOT = $dressedHub
        $r = Invoke-Update $c
        Assert-Equal 'a Demo already wearing covers: exits 0' 0 $r.ExitCode
        Assert-True 'and no hint' ($r.Output -notmatch 'Cover -Samples' -and $r.Output -notmatch 'Also needed') $r.Output
        Assert-Equal 'and no writes' $snap (Get-HubSnapshot $dressedHub)

        $env:PROMPTS_ROOT = (Join-Path $base 'no-such-hub')
        $r = Invoke-Update $c
        Assert-True 'no hub to look in: nothing said, and Update still succeeds' ($r.ExitCode -eq 0 -and $r.Output -notmatch 'Cover -Samples') $r.Output
    }
    finally { $env:PROMPTS_ROOT = $savedRoot }

    # -- -Sync ---------------------------------------------------------------
    Write-Host ""
    Write-Host "-- -Sync: software first, then data -------------------" -ForegroundColor Cyan
    $c = New-Consumer 'c-sync'
    $r = Invoke-Update $c @('-Sync', '-WhatIf')
    Assert-Equal '-Sync -WhatIf exits 0' 0 $r.ExitCode
    Assert-True '-WhatIf does not sync the prompt store either' ($r.Output -match 'prompt store was not synced') $r.Output
    # The scratch package has no module, so the Sync VERB is not loaded. That is
    # the point of this case: -Sync goes through the verb, never around it.
    $r = Invoke-Update $c @('-Sync')
    Assert-Equal '-Sync without the Sync verb loaded is a stated refusal' 2 $r.ExitCode
    Assert-True 'and says the Toolkit itself IS updated' ($r.Output -match 'Toolkit is updated') $r.Output

    # -- -Sync, end to end, with the REAL module ---------------------------------
    # Everything above runs the script in a package that has no module, so none
    # of it could see the hand-off to Sync. The first real `Update -Sync` died in
    # it: Sync was called by its FUNCTION name, the wrapper resolved no prefix,
    # and a good update ended in a binder error. So: commit a snapshot of THIS
    # working tree into a scratch repository, clone it, import the module from
    # the clone, and type the verb the way a person does.
    Write-Host ""
    Write-Host "-- -Sync with the real module, from a clone -----------" -ForegroundColor Cyan
    $snapshot = Join-Path $base 'snapshot'
    $snapOrigin = Join-Path $base 'snapshot-origin.git'
    New-Item -ItemType Directory -Path $snapshot -Force | Out-Null
    foreach ($rel in @(& git -C $pkgRoot ls-files --cached --others --exclude-standard)) {
        $src = Join-Path $pkgRoot $rel
        if (-not (Test-Path $src -PathType Leaf)) { continue }
        $dst = Join-Path $snapshot $rel
        New-Item -ItemType Directory -Path (Split-Path $dst -Parent) -Force | Out-Null
        Copy-Item $src $dst
    }
    & git init -q -b main $snapshot 2>&1 | Out-Null
    [void](Invoke-Git $snapshot @('add', '-A'))
    [void](Invoke-Git $snapshot @('commit', '-q', '-m', 'a snapshot of the working tree'))
    & git clone -q --bare $snapshot $snapOrigin 2>&1 | Out-Null
    $real = Join-Path $base 'c-real'
    & git clone -q $snapOrigin $real 2>&1 | Out-Null

    # A hub that is a plain folder: storeSync is 'none' by default, so Sync has
    # nothing to do and SAYS so -- which is all this case needs it to do.
    $plainHub = Join-Path $base 'plain-hub'
    New-Item -ItemType Directory -Path (Join-Path $plainHub 'test/current') -Force | Out-Null
    $shippedPrefix = (Get-Content (Join-Path $pkgRoot 'config.default.json') -Raw | ConvertFrom-Json).commandPrefix
    $verb = $shippedPrefix + 'Update'
    $logDir = Join-Path $base 'log'
    New-Item -ItemType Directory -Path $logDir -Force | Out-Null
    $command = "`$env:PSModulePath = '$real'; `$env:PROMPTS_ROOT = '$plainHub'; `$env:P20_USAGE_LOG_DIR = '$logDir'; " +
        "Import-Module '$real/Prompt20Toolkit/Prompt20Toolkit.psd1' -Force 3>`$null; $verb -Sync; exit `$LASTEXITCODE"
    Push-Location $base
    try { $realOut = & pwsh -NoProfile -Command $command 2>&1 | Out-String }
    finally { Pop-Location }
    $realExit = $LASTEXITCODE
    Assert-True 'the update half ran against the CLONE, not this checkout' ($realOut -match [regex]::Escape('c-real')) $realOut
    Assert-True 'it reached the prompt store' ($realOut -match 'Prompt store:') $realOut
    Assert-True 'and Sync ran as the verb, and answered' ($realOut -match 'Nothing to sync') $realOut
    Assert-True 'with no binder error in the hand-off' ($realOut -notmatch 'Cannot bind') $realOut
    Assert-Equal 'and the whole thing exits 0' 0 $realExit

    # -- -Help -------------------------------------------------------------------
    $r = Invoke-Update $c @('-Help')
    Assert-True '-Help describes -Sync and -WhatIf' ($r.Output -match '-Sync' -and $r.Output -match '-WhatIf') $r.Output
    Assert-True '-Help says what it never does' ($r.Output -match 'never commits, rebases or pushes') $r.Output
}
catch {
    Assert-True 'the cases ran to the end without a terminating error' $false $_.Exception.Message
}
finally {
    Remove-Item -Path $base -Recurse -Force -ErrorAction SilentlyContinue
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
