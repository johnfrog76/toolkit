<#
.SYNOPSIS
    Tests for Sync-Prompts.ps1 — where the storeSync switch comes from, and that
    auto-commit-before-sync runs through the real pre-commit hook (no
    --no-verify), so a guard failure must abort sync with the working tree left
    unchanged rather than silently committing anyway.
.DESCRIPTION
    Two halves, and only the second one depends on the package shipping hooks.

    REMOTE — a bare repo, a clone that is the hub, and a second clone standing
    in for the other machine. The hub's own hub.json declares
    "storeSync": "git" and NO config.local.json names it, so what is proved is
    the resolution as well as the behaviour: Sync commits, rebases in the other
    machine's commit and pushes its own. A second run with a config.local.json
    that says "none" proves the machine still has the last word. These run
    everywhere; they need git and a child pwsh, not hooks.

    HOOKS — an isolated temp git repo with core.hooksPath pointed at a copy of
    the repo's tracked hooks/ folder, $global:P20Config stubbed at it, and
    Sync-Prompts.ps1 run in-process. Covered: the normal auto-commit path; both
    guard-failure paths (missing .gitignore, over the staged-file limit); and
    that a guard-failure abort restores the index, re-staging work staged before
    sync ran (modifications and deletions) without re-staging the files that
    tripped the guard. This package ships no hooks/, so these SKIP here — and a
    skip is not a pass.

    Run:  pwsh -File Tests/Test-Sync.ps1
    Or:   tkTestToolkit -Sync
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
# Package root is the parent of Tests/, from this file's own location:
# works wherever the package sits and needs no repo around it.
$pkgRoot  = Split-Path $scriptDir -Parent

$syncScript = Join-Path $pkgRoot 'Scripts/Sync-Prompts.ps1'
if (-not (Test-Path $syncScript)) {
    Write-Error "Sync-Prompts.ps1 not found at $syncScript"
    return
}

# The hook half only. This package does not ship tracked git hooks --
# ConfigureGit is not part of its command surface -- so hook interaction is
# untestable here, and its absence is a skip rather than a failure: a suite that
# cries wolf on a correctly-configured package is one people stop running.
#
# It is a skip of THOSE CASES, not of the file: the remote half below needs no
# hooks, and skipping it with them left the suite reporting 0/0 and proving
# nothing about the verb at all.
$realHooksDir   = Join-Path $pkgRoot 'hooks'
$script:hasHooks = Test-Path (Join-Path $realHooksDir 'pre-commit')

# ── Test harness ──────────────────────────────────────────────────────────────

$script:passed = 0
$script:failed = 0
$script:errors = @()

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

function Assert-True {
    param([string]$TestName, [bool]$Condition)
    if ($Condition) {
        $script:passed++
        Write-Host "  PASS  $TestName" -ForegroundColor Green
    }
    else {
        $script:failed++
        $msg = "  FAIL  $TestName"
        $script:errors += $msg
        Write-Host $msg -ForegroundColor Red
    }
}

function Assert-Contains {
    param([string]$TestName, [string]$Haystack, [string]$Needle)
    if ($Haystack -like "*$Needle*") {
        $script:passed++
        Write-Host "  PASS  $TestName" -ForegroundColor Green
    }
    else {
        $script:failed++
        $msg = "  FAIL  $TestName — '$Needle' not found in output"
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
        $msg = "  FAIL  $TestName — expected [$Expected] got [$Actual]"
        $script:errors += $msg
        Write-Host $msg -ForegroundColor Red
    }
}

# ── Sandbox setup ─────────────────────────────────────────────────────────────
#
# A sandbox is a temp dir wired as a real git repo, with core.hooksPath
# pointed at a copy of the real hooks/ folder so pre-commit genuinely runs —
# not a fake/stubbed hook. current/ exists so Get-PromptFolders resolves
# (Sync-Prompts.ps1 recreates it post-pull if git dropped it).
# No remote is configured; these tests stop before the pull/push step by
# construction (a guard failure returns early; a clean commit with no remote
# fails the pull with a controlled, asserted error rather than hanging).

function New-SyncSandbox {
    param([switch]$SkipGitignore)

    $base = Join-Path ([System.IO.Path]::GetTempPath()) ("test-sync-" + [System.Guid]::NewGuid().Guid.Substring(0, 8))
    New-Item -ItemType Directory -Path $base -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $base 'current') -Force | Out-Null

    $sandboxHooks = Join-Path $base 'hooks'
    New-Item -ItemType Directory -Path $sandboxHooks -Force | Out-Null
    Copy-Item -Path (Join-Path $realHooksDir 'pre-commit') -Destination $sandboxHooks -Force

    Push-Location $base
    try {
        git init --quiet 2>&1 | Out-Null
        git checkout -B main --quiet 2>&1 | Out-Null
        git config user.email 'test@example.com' 2>&1 | Out-Null
        git config user.name 'Sync Test' 2>&1 | Out-Null
        git config commit.gpgsign false 2>&1 | Out-Null
        git config core.hooksPath 'hooks' 2>&1 | Out-Null

        # The baseline commit always includes .gitignore, so it lands even in
        # the -SkipGitignore case -- otherwise the hook blocks the sandbox's own
        # setup commit and the test runs against a repo with zero commits, where
        # "no commit was created" passes trivially and proves nothing. Instead we
        # build a real repo first, then remove .gitignore below, which is the
        # scenario being modelled: an established repo whose .gitignore goes
        # missing.
        #
        # Scoped like the real repo's .gitignore (toolkit/*.log) -- a bare
        # "*.log" would also exclude the sandbox's own usage.log fixture,
        # which these tests stage deliberately.
        Set-Content -Path (Join-Path $base '.gitignore') -Value "toolkit/*.log`n" -Encoding UTF8
        Set-Content -Path (Join-Path $base '.gitkeep') -Value '' -Encoding UTF8
        git add -A 2>&1 | Out-Null
        git commit -m 'init' --quiet 2>&1 | Out-Null

        if ($SkipGitignore) {
            # Committed above, now deleted and the deletion committed with
            # --no-verify (the documented bypass) so the repo has real history
            # and a genuinely absent .gitignore before the test begins.
            Remove-Item -Path (Join-Path $base '.gitignore') -Force
            git add -A 2>&1 | Out-Null
            git commit -m 'remove gitignore' --quiet --no-verify 2>&1 | Out-Null
        }
    }
    finally {
        Pop-Location
    }

    $global:P20Config = @{ PromptsRoot = $base }
    return $base
}

function Remove-SyncSandbox {
    param([string]$Path)
    if ($Path -and (Test-Path $Path)) {
        Remove-Item -Path $Path -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Get-CommitSubjects {
    param([string]$Sandbox)
    Push-Location $Sandbox
    try {
        return @(git log --format='%s')
    }
    finally { Pop-Location }
}

function Get-SandboxStatus {
    param([string]$Sandbox)
    Push-Location $Sandbox
    try {
        return (git status --porcelain 2>&1 | Out-String)
    }
    finally { Pop-Location }
}

function Get-StagedPaths {
    param([string]$Sandbox)
    Push-Location $Sandbox
    try {
        return @(git diff --cached --name-only 2>$null)
    }
    finally { Pop-Location }
}

function Invoke-Sync {
    # Runs the script and captures all streams as a single string.
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'Sandbox', Justification = 'The callers name the sandbox for the reader; Sync-Prompts finds it through $global:P20Config.PromptsRoot, which New-SyncSandbox sets.')]
    param([string]$Sandbox)
    $prevErr = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $out = & $syncScript *>&1 | Out-String
    }
    finally {
        $ErrorActionPreference = $prevErr
    }
    return $out
}

Write-Host ""
Write-Host "═══════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "  Sync Script Tests (storeSync resolution, hook interaction)" -ForegroundColor Cyan
Write-Host "═══════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host ""

if (-not $script:hasHooks) {
    Write-Host "  SKIP  hook-interaction tests -- no hooks/pre-commit in this package" -ForegroundColor Yellow
    Write-Host ""
}
else {

# ── Test 1: Clean dirty tree commits normally, hook passes ───────────────────

Write-Host "── Normal dirty tree — hook passes, commit succeeds ───" -ForegroundColor Cyan

$sandbox = New-SyncSandbox
try {
    Set-Content -Path (Join-Path $sandbox 'usage.log') -Value 'noop' -Encoding UTF8
    # No .gitignore match needed — usage.log is small and .gitignore is present.
    $beforeCommits = (Get-CommitSubjects $sandbox).Count

    $output = Invoke-Sync $sandbox
    $afterCommits = Get-CommitSubjects $sandbox

    Assert-Equal "One auto-commit created" 1 ($afterCommits.Count - $beforeCommits)
    Assert-Contains "Commit subject is auto-commit before sync" $afterCommits[0] 'auto-commit before sync'
    Assert-Contains "Output confirms commit before pull" $output 'Committed pending changes before pull'
}
finally { Remove-SyncSandbox $sandbox }

Write-Host ""

# ── Test 2: Missing .gitignore blocks auto-commit, tree left dirty ───────────

Write-Host "── Missing .gitignore — hook blocks, sync aborts clean ─" -ForegroundColor Cyan

$sandbox = New-SyncSandbox -SkipGitignore
try {
    Set-Content -Path (Join-Path $sandbox 'usage.log') -Value 'noop' -Encoding UTF8
    $beforeCommits = (Get-CommitSubjects $sandbox).Count

    $output = Invoke-Sync $sandbox
    $afterCommits = (Get-CommitSubjects $sandbox).Count
    $status = Get-SandboxStatus $sandbox

    Assert-True "Sandbox has real history to abort against" ($beforeCommits -gt 0)
    Assert-Equal "No commit created" 0 ($afterCommits - $beforeCommits)
    Assert-Contains "Output warns sync was aborted" $output 'aborting sync'
    Assert-Contains "Hook error surfaces in output" $output '.gitignore is missing'
    Assert-True "usage.log left dirty (unstaged), not committed" ($status -like '*usage.log*')
}
finally { Remove-SyncSandbox $sandbox }

Write-Host ""

# ── Test 3: Oversized dirty tree blocks auto-commit, working tree untouched ──

Write-Host "── Over guard limit — hook blocks, working tree intact ─" -ForegroundColor Cyan

$sandbox = New-SyncSandbox
try {
    $bulkDir = Join-Path $sandbox 'bulk'
    New-Item -ItemType Directory -Path $bulkDir -Force | Out-Null
    # 3001 files trips the hook's 3000-file guard without the multi-minute
    # per-file overhead seen creating ~3000 files on this filesystem — the
    # hook's own logic (git diff --cached --name-only | wc -l) is exercised
    # for real; only the fixture generation is kept cheap.
    1..3001 | ForEach-Object {
        [System.IO.File]::WriteAllText((Join-Path $bulkDir "f$_.txt"), '')
    }
    $beforeCommits = (Get-CommitSubjects $sandbox).Count

    $output = Invoke-Sync $sandbox
    $afterCommits = (Get-CommitSubjects $sandbox).Count
    $status = Get-SandboxStatus $sandbox

    Assert-Equal "No commit created" 0 ($afterCommits - $beforeCommits)
    Assert-Contains "Output warns sync was aborted" $output 'aborting sync'
    Assert-Contains "Hook error names the guard limit" $output 'guard limit'
    Assert-True "bulk/ files left dirty, not committed" ($status -like '*bulk*')
}
finally { Remove-SyncSandbox $sandbox }

Write-Host ""

# ── Test 4: Guard failure preserves work staged before sync ──────────────────
#
# The recovery path does `git add -A` then, on hook failure, `git reset` --
# which unstages everything, including whatever the user had staged deliberately
# before running Sync. It must restore that exact staging, and nothing more:
# the whole point of the abort is to leave the repo as it was found.

Write-Host "── Pre-staged work survives a guard-failure abort ─────" -ForegroundColor Cyan

$sandbox = New-SyncSandbox
try {
    # A modification and a deletion, both staged on purpose before sync runs.
    Set-Content -Path (Join-Path $sandbox 'staged.txt') -Value 'v1' -Encoding UTF8
    Set-Content -Path (Join-Path $sandbox 'doomed.txt') -Value 'bye' -Encoding UTF8
    Push-Location $sandbox
    try {
        git add -A 2>&1 | Out-Null
        git commit -m 'add fixtures' --quiet 2>&1 | Out-Null
        Set-Content -Path (Join-Path $sandbox 'staged.txt') -Value 'v2' -Encoding UTF8
        git add staged.txt 2>&1 | Out-Null
        git rm --quiet doomed.txt 2>&1 | Out-Null
    }
    finally { Pop-Location }

    $stagedBefore = Get-StagedPaths $sandbox

    # Trip the guard so the recovery path runs, with an unstaged file alongside
    # so the dirty check fires on more than the pre-staged set.
    $bulkDir = Join-Path $sandbox 'bulk'
    New-Item -ItemType Directory -Path $bulkDir -Force | Out-Null
    1..3001 | ForEach-Object {
        [System.IO.File]::WriteAllText((Join-Path $bulkDir "f$_.txt"), '')
    }

    $beforeCommits = (Get-CommitSubjects $sandbox).Count
    $output = Invoke-Sync $sandbox
    $afterCommits = (Get-CommitSubjects $sandbox).Count
    $stagedAfter = Get-StagedPaths $sandbox

    Assert-True "Fixture staging captured before sync" ($stagedBefore.Count -eq 2)
    Assert-Equal "No commit created" 0 ($afterCommits - $beforeCommits)
    Assert-Equal "Same number of files staged after abort" $stagedBefore.Count $stagedAfter.Count
    Assert-True "Staged modification restored" ($stagedAfter -contains 'staged.txt')
    Assert-True "Staged deletion restored" ($stagedAfter -contains 'doomed.txt')
    Assert-True "Runaway bulk/ files NOT left staged" (-not ($stagedAfter -like 'bulk/*'))
    Assert-Contains "Output reports the restore" $output 'previously staged file'
}
finally { Remove-SyncSandbox $sandbox }

Write-Host ""

}  # end of the hook-dependent half

# ── Test 5: The hub declares storeSync, and Sync pulls and pushes ────────────
#
# The only case here that runs the real module rather than a stubbed
# $global:P20Config, because the thing under test is where the switch comes
# from: hub.json says "git", no config.local.json says anything, and Sync has
# to agree. A bare repo plus two clones makes the pull and the push observable
# rather than inferred -- the other clone stands in for the other machine.

Write-Host "── The hub declares storeSync — real remote ───────────" -ForegroundColor Cyan

function New-RemoteSandbox {
    <# base/remote.git (bare), base/hub (the store), base/other (the other
       machine), base/pkg (enough of the package to import). #>
    param([string]$HubJson)

    $base = Join-Path ([System.IO.Path]::GetTempPath()) ("test-sync-remote-" + [System.Guid]::NewGuid().Guid.Substring(0, 8))
    New-Item -ItemType Directory -Path $base -Force | Out-Null
    $remote = Join-Path $base 'remote.git'
    $hub    = Join-Path $base 'hub'
    $other  = Join-Path $base 'other'
    $pkg    = Join-Path $base 'pkg'

    git init --bare --quiet --initial-branch=main $remote 2>&1 | Out-Null
    # Cloning an empty bare repository prints 'You appear to have cloned an empty
    # repository' on stderr, which 5.1 turns into a terminating error under Stop;
    # --quiet does not silence it. A function-local Continue reads it as text.
    $prevErr = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try { git clone --quiet $remote $hub 2>&1 | Out-Null }
    finally { $ErrorActionPreference = $prevErr }
    Set-RepoIdentity $hub

    # The hub's own declaration, and the card folders the active Space reads.
    Set-Content -Path (Join-Path $hub 'hub.json') -Value $HubJson -Encoding UTF8
    Set-Content -Path (Join-Path $hub '.gitignore') -Value "*.tmp`n" -Encoding UTF8
    New-Item -ItemType Directory -Path (Join-Path $hub 'test/current') -Force | Out-Null
    Set-Content -Path (Join-Path $hub 'test/current/.gitkeep') -Value '' -Encoding UTF8
    Push-Location $hub
    try {
        git checkout -B main --quiet 2>&1 | Out-Null
        git add -A 2>&1 | Out-Null
        git commit -m 'hub' --quiet 2>&1 | Out-Null
        git push --quiet --set-upstream origin main 2>&1 | Out-Null
    }
    finally { Pop-Location }

    git clone --quiet $remote $other 2>&1 | Out-Null
    Set-RepoIdentity $other

    # Enough of the package to import: the module, its Scripts/ and the shipped
    # config. config.local.json is written per case by Invoke-SyncInModule.
    New-Item -ItemType Directory -Path $pkg -Force | Out-Null
    Copy-Item (Join-Path $pkgRoot 'utilities.psm1')      (Join-Path $pkg 'utilities.psm1')
    Copy-Item (Join-Path $pkgRoot 'Scripts')             (Join-Path $pkg 'Scripts') -Recurse
    Copy-Item (Join-Path $pkgRoot 'config.default.json') (Join-Path $pkg 'config.default.json')
    # consts.json travels with the module: utilities.psm1 dot-sources Scripts/Get-Consts.ps1
    # at import and the contract file has no default, so a package without it is not a package.
    Copy-Item (Join-Path $pkgRoot 'consts.json') (Join-Path $pkg 'consts.json')

    return @{ Base = $base; Remote = $remote; Hub = $hub; Other = $other; Pkg = $pkg }
}

function Set-RepoIdentity {
    param([string]$Repo)
    Push-Location $Repo
    try {
        git config user.email 'test@example.com' 2>&1 | Out-Null
        git config user.name 'Sync Test' 2>&1 | Out-Null
        git config commit.gpgsign false 2>&1 | Out-Null
        git config core.autocrlf false 2>&1 | Out-Null
    }
    finally { Pop-Location }
}

function Invoke-SyncInModule {
    <# Import the sandboxed module in a fresh child pwsh -- so StoreSync is
       resolved for real, from config + hub.json + whatever local config this
       case writes -- and run Sync-Prompts.ps1 against it. #>
    param($Sandbox, [string]$LocalJson, [string]$CallerPreference = 'SilentlyContinue')

    # The previous case's child pwsh, or a scanner reading what it just wrote, can still
    # hold the file for a moment; retry the write rather than ending the run on it.
    $localPath = Join-Path $Sandbox.Pkg 'config.local.json'
    for ($attempt = 1; $attempt -le 20; $attempt++) {
        try { Set-Content -Path $localPath -Value $LocalJson -Encoding UTF8; break }
        catch {
            if ($attempt -eq 20) { throw }
            Start-Sleep -Milliseconds 250
        }
    }
    $modulePath = Join-Path $Sandbox.Pkg 'utilities.psm1'
    $syncPath   = Join-Path $Sandbox.Pkg 'Scripts/Sync-Prompts.ps1'
    $command = @"
`$ErrorActionPreference = 'SilentlyContinue'
Remove-Item Env:PROMPTS_ROOT -ErrorAction SilentlyContinue
Import-Module '$modulePath' -Force -DisableNameChecking *>`$null
Write-Host "RESOLVED-STORESYNC=`$(`$global:P20Config.StoreSync)"
`$ErrorActionPreference = '$CallerPreference'
& '$syncPath' *>&1 | ForEach-Object { Write-Host `$_ }
"@
    return (pwsh -NoProfile -Command $command 2>&1 | Out-String)
}

function Invoke-SyncWrapperInModule {
    <# Same shape as Invoke-SyncInModule, but through the VERB
       (Sync-P20Prompts), not the raw script -- so a failed pull or push is
       read by Invoke-ToolkitScript, the one place the double-block bug (KVK7)
       could reappear: a script that exits non-zero without having called
       Write-CliError gets the wrapper's own generic "Error: exit code <n>"
       block printed on top of whatever the script already said. Also prints
       the process's own exit code, which the raw-script helper above has no
       reason to read. #>
    param($Sandbox, [string]$LocalJson)

    $localPath = Join-Path $Sandbox.Pkg 'config.local.json'
    for ($attempt = 1; $attempt -le 20; $attempt++) {
        try { Set-Content -Path $localPath -Value $LocalJson -Encoding UTF8; break }
        catch {
            if ($attempt -eq 20) { throw }
            Start-Sleep -Milliseconds 250
        }
    }
    $modulePath = Join-Path $Sandbox.Pkg 'utilities.psm1'
    $command = @"
`$ErrorActionPreference = 'SilentlyContinue'
Remove-Item Env:PROMPTS_ROOT -ErrorAction SilentlyContinue
Import-Module '$modulePath' -Force -DisableNameChecking *>`$null
Sync-P20Prompts *>&1 | ForEach-Object { Write-Host `$_ }
Write-Host "SYNC-EXITCODE=`$LASTEXITCODE"
"@
    return (pwsh -NoProfile -Command $command 2>&1 | Out-String)
}

function Get-RemoteSubjects {
    param([string]$Remote)
    Push-Location $Remote
    try { return @(git log main --format='%s' 2>$null) }
    finally { Pop-Location }
}

# The manifest is written in the OLD spelling on purpose: Sync migrates it to
# `spaces` once (stage 2) and commits, and what it declared must survive.
$hubJson = '{ "hub": 1, "storeSync": "git", "orgs": [ { "slug": "test", "name": "Test", "status": "local", "promptsFolder": "test" } ] }'
$rs = New-RemoteSandbox -HubJson $hubJson
try {
    # The other machine pushes something.
    Set-Content -Path (Join-Path $rs.Other 'from-the-other-machine.md') -Value 'hello' -Encoding UTF8
    Push-Location $rs.Other
    try {
        git add -A 2>&1 | Out-Null
        git commit -m 'card written on the other machine' --quiet 2>&1 | Out-Null
        git push --quiet 2>&1 | Out-Null
    }
    finally { Pop-Location }

    # This machine has an uncommitted card of its own.
    Write-FixtureText (Join-Path $rs.Hub 'test/current/local-card.md') '# local'

    $output = Invoke-SyncInModule -Sandbox $rs -LocalJson "{ `"promptsRoot`": `"$($rs.Hub -replace '\\', '/')`" }"

    Assert-Contains "storeSync resolves to git from hub.json alone" $output 'RESOLVED-STORESYNC=git'
    Assert-Contains "Sync runs rather than refusing" $output 'Syncing prompts repo'
    Assert-Contains "and says it finished" $output 'Sync complete'
    Assert-True "the other machine's commit was pulled in" (Test-Path (Join-Path $rs.Hub 'from-the-other-machine.md'))
    $remoteSubjects = Get-RemoteSubjects $rs.Remote
    Assert-True "this machine's auto-commit reached the remote" (@($remoteSubjects | Where-Object { $_ -like '*auto-commit before sync*' }).Count -eq 1)
    Assert-True "and it carried the card with it" ((git -C $rs.Remote show 'main:test/current/local-card.md' 2>$null) -join '' -like '*# local*')

    $manifestAfter = Get-Content (Join-Path $rs.Hub 'hub.json') -Raw | ConvertFrom-Json
    Assert-True "hub.json now says spaces" ($null -ne $manifestAfter.PSObject.Properties['spaces'])
    Assert-True "and no longer orgs" ($null -eq $manifestAfter.PSObject.Properties['orgs'])
    Assert-Equal "with the Space it declared intact" 'test' (@($manifestAfter.spaces)[0].slug)
    Assert-Equal "and the hub's storeSync intact" 'git' $manifestAfter.storeSync
    Assert-True "the new spelling reached the remote as its own commit" (@($remoteSubjects | Where-Object { $_ -like '*hub.json says spaces*' }).Count -eq 1)
    Assert-Contains "and Sync said so" $output 'hub.json now says spaces'

    # A caller holding 'Stop', a hub with nothing to commit: the status read is a
    # native call and must not throw before Sync can report. (On 5.1 this is the
    # throw; pwsh 7 reads it as text, so the 5.1 run in CI is what proves it.)
    $output = Invoke-SyncInModule -Sandbox $rs -LocalJson "{ `"promptsRoot`": `"$($rs.Hub -replace '\\', '/')`" }" -CallerPreference 'Stop'

    Assert-Contains "a Stop caller with a clean hub still syncs to the end" $output 'Sync complete'
    Assert-True "and nothing was committed, because there was nothing to commit" ($output -notmatch 'Committed pending changes')
    Assert-True "and no error escaped the status read" ($output -notmatch 'NativeCommandError|Error:|Exception')

    # Same hub, same declaration -- and a machine that must never push says so.
    $output = Invoke-SyncInModule -Sandbox $rs -LocalJson "{ `"promptsRoot`": `"$($rs.Hub -replace '\\', '/')`", `"storeSync`": `"none`" }"

    Assert-Contains "a local override beats the hub" $output 'RESOLVED-STORESYNC=none'
    Assert-Contains "and Sync refuses" $output 'Nothing to sync'
    Assert-Contains "naming the hub's hub.json as where the switch lives" $output "hub's hub.json"
    Assert-Contains "and config.local.json as the per-machine override" $output 'config.local.json'
}
catch {
    Assert-True "the cases ran to the end without a terminating error -- $($_.Exception.Message)" $false
}
finally { Remove-SyncSandbox $rs.Base }

Write-Host ""

# ── Test 6: A failed pull states the refusal once (KVK7) ─────────────────────
#
# Through the WRAPPER (Sync-P20Prompts), not the raw script -- Test 5 above
# never exercises Invoke-ToolkitScript, so it could not have caught this. The
# old code left `git pull --rebase`'s failing exit code (128) as the script's
# own exit code with no Write-CliError call, so the guard read it as "a
# failure that said nothing" and printed its own generic "Error: exit code
# 128" block on top of Sync's Write-Warning -- two messages where AGENTS.md's
# refusal contract wants one. The fix calls Write-CliError and exits 2, so the
# guard logs the stated reason and prints nothing more.

Write-Host "── A failed pull states the refusal once ──────────────" -ForegroundColor Cyan

$hubJson6 = '{ "hub": 1, "storeSync": "git", "spaces": [ { "slug": "test", "name": "Test", "status": "local", "promptsFolder": "test" } ] }'
$rs6 = New-RemoteSandbox -HubJson $hubJson6
try {
    # Point origin at a path that is not a git repository at all, so
    # `git pull --rebase` fails fast (fatal, exit 128) with no network and no
    # race to arrange -- the repro's own wording: "whose remote cannot be
    # reached".
    Push-Location $rs6.Hub
    try { git remote set-url origin (Join-Path $rs6.Base 'does-not-exist.git') 2>&1 | Out-Null }
    finally { Pop-Location }

    $output = Invoke-SyncWrapperInModule -Sandbox $rs6 -LocalJson "{ `"promptsRoot`": `"$($rs6.Hub -replace '\\', '/')`" }"

    Assert-Contains "Sync names the failed pull" $output "git pull --rebase failed in"
    Assert-Contains "and says nothing was synced" $output 'nothing was synced'
    Assert-Contains "and hints at the next step" $output 'Resolve the conflict in a terminal'
    Assert-Contains "exits 2, the stated-refusal code" $output 'SYNC-EXITCODE=2'
    Assert-True "exactly one Error: block" (@([regex]::Matches($output, 'Error:')).Count -eq 1)
    Assert-True "no generic exit-code block on top" ($output -notmatch 'Error: exit code \d+')
    Assert-True "and no Log -Errors hint from the generic block" ($output -notmatch 'Log -Errors')
}
catch {
    Assert-True "the cases ran to the end without a terminating error -- $($_.Exception.Message)" $false
}
finally { Remove-SyncSandbox $rs6.Base }

Write-Host ""

# ── Test 7: A failed push states the refusal once (KVK7) ─────────────────────
#
# Same bug, the push side: `git push`'s own exit code, with no Write-CliError
# call, reached the guard as an unstated failure. Needs a remote that accepts
# a fetch (the pull step, with nothing to rebase) but rejects a push, so a
# read-only bare repo stands in for "push failed, pull already went through".
# chmod-based read-only is not reliable on Windows, so this half skips there --
# a skip is not a pass, and Test 6 above already proves the fix on every host.

Write-Host "── A failed push states the refusal once ──────────────" -ForegroundColor Cyan

$onWindowsForSync = ($PSVersionTable.PSEdition -eq 'Desktop') -or $IsWindows
if (-not (Get-Command chmod -ErrorAction SilentlyContinue) -or $onWindowsForSync) {
    Write-Host "  SKIP  failed-push case -- chmod read-only is not reliable on this host" -ForegroundColor Yellow
}
else {
    $hubJson7 = '{ "hub": 1, "storeSync": "git", "spaces": [ { "slug": "test", "name": "Test", "status": "local", "promptsFolder": "test" } ] }'
    $rs7 = New-RemoteSandbox -HubJson $hubJson7
    try {
        # A local change so pull --rebase has nothing to do (already up to
        # date) and the only thing left to fail is the push.
        Write-FixtureText (Join-Path $rs7.Hub 'test/current/local-card.md') '# local'
        Push-Location $rs7.Hub
        try {
            git add -A 2>&1 | Out-Null
            git commit -m 'local change before push' --quiet 2>&1 | Out-Null
        }
        finally { Pop-Location }

        & chmod -R a-w $rs7.Remote
        try {
            $output = Invoke-SyncWrapperInModule -Sandbox $rs7 -LocalJson "{ `"promptsRoot`": `"$($rs7.Hub -replace '\\', '/')`" }"
        }
        finally {
            & chmod -R u+w $rs7.Remote
        }

        Assert-Contains "the pull above went through" $output 'Syncing prompts repo'
        Assert-Contains "Sync names the failed push" $output "git push failed in"
        Assert-Contains "and says the pull went through but nothing was pushed" $output 'went through but nothing was pushed'
        Assert-Contains "and hints at checking the remote" $output 'Check the remote and your network'
        Assert-Contains "exits 2, the stated-refusal code" $output 'SYNC-EXITCODE=2'
        Assert-True "exactly one Error: block" (@([regex]::Matches($output, 'Error:')).Count -eq 1)
        Assert-True "no generic exit-code block on top" ($output -notmatch 'Error: exit code \d+')
        Assert-True "and no Log -Errors hint from the generic block" ($output -notmatch 'Log -Errors')
    }
    catch {
        Assert-True "the cases ran to the end without a terminating error -- $($_.Exception.Message)" $false
    }
    finally {
        & chmod -R u+w $rs7.Remote 2>$null
        Remove-SyncSandbox $rs7.Base
    }
}

Write-Host ""

# ── Summary ──────────────────────────────────────────────────────────────────

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
