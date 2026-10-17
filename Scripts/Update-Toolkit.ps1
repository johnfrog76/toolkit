<#
.SYNOPSIS
    Bring this machine's copy of the Toolkit up to date -- and, with -Sync, the
    prompt store after it.

.DESCRIPTION
    A machine used to update the Toolkit by remembering three things: git pull in
    whatever folder the checkout is in, re-import the module in the open shell,
    and re-run InstallAutoload if the alias set moved. The third is the one that
    gets forgotten, and it fails quietly: a verb that works after an explicit
    import and is "not recognized" in a profile-less shell.

    This verb does the first two and NOTICES the third:

      1. Pulls the Toolkit's own repository -- the one this script was loaded
         from, resolved from $PSScriptRoot, never the current directory and never
         promptsRoot. FAST-FORWARD ONLY. It is software: it is never
         auto-committed, never rebased, never pushed.
      2. Re-imports the module, so the running shell has the pulled code.
      3. Says what else the pull touched that needs a hand: the autoload shim
         (InstallAutoload -Force), the web UI's lockfile (npm ci), the agent's
         requirements (pip install).

    It refuses rather than guesses. A working tree with uncommitted changes, a
    detached HEAD, a branch with no upstream, and local commits that have
    diverged from the remote are each a stated refusal (exit 2) that changes
    nothing -- a developer's checkout is not something a convenience verb
    rewrites.

    -Sync runs Sync afterwards: software first, then data. It is a switch HERE,
    and not an -All on Sync, because Sync is the DATA verb -- it auto-commits,
    rebases and pushes the hub -- and the rules for the software are the
    opposite. The two stay two verbs; this one can call the other, in that order,
    after the re-import, so the sync runs the code that was just pulled. If the
    update is refused, the sync does not run: a refusal is a stop.

    Needs git and nothing else, so it works at every tier.

.PARAMETER Sync
    After a successful update (or when already up to date), sync the prompt store.

.PARAMETER WhatIf
    Fetch, and report what a pull would bring. Change nothing.

.EXAMPLE
    {cliPrefix}Update
.EXAMPLE
    {cliPrefix}Update -Sync
.EXAMPLE
    {cliPrefix}Update -WhatIf

.NOTES
    PowerShell 5.1 compatible (ASCII dashes only).
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [switch]$Sync,
    [switch]$Help
)

# The prefix is config, never a literal. Run without the module (a test, a
# person running the .ps1) there may be no config at all, and then there is no
# prefix to print -- which is honest: the bare verb name is still right.
. (Join-Path $PSScriptRoot 'Initialize-CliFallbacks.ps1')
. (Join-Path $PSScriptRoot 'Invoke-TrackerRead.ps1')

function Write-UpdateRefusal {
    param([string]$Message, [string]$Hint)
    Write-Host ""
    Write-Host "Error: $Message" -ForegroundColor Red
    if ($Hint) { Write-Host "Hint:  $Hint" -ForegroundColor Yellow }
    Write-Host ""
}

if ($Help) {
    Write-Host @"

$(Get-CliPrefix)Update - bring this machine's Toolkit up to date

USAGE:
    $(Get-CliPrefix)Update              Pull the Toolkit (fast-forward only), re-import it, say what else moved
    $(Get-CliPrefix)Update -Sync        ...then sync the prompt store: software first, then data
    $(Get-CliPrefix)Update -WhatIf      Fetch and report; change nothing

It never commits, rebases or pushes the Toolkit. Uncommitted changes, a detached
HEAD, no upstream, or diverged local commits are each a refusal that changes nothing.

"@
    return
}

$pkgRoot = Split-Path -Parent $PSScriptRoot
$prefix = Get-CliPrefix

function Invoke-ToolkitGit {
    # Always FROM the package, never the current directory. Output is returned
    # as strings; the caller reads $LASTEXITCODE.
    param([string[]]$GitArgs)
    return @((Invoke-P20TrackerRead 'git' (@('-C', $pkgRoot) + @($GitArgs))).Lines)
}

if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    Write-UpdateRefusal -Message 'git is not installed, so the Toolkit cannot be updated from here.' -Hint 'Install git, or replace the folder with a fresh download.'
    exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
}

. (Join-Path $PSScriptRoot 'Test-GitRoot.ps1')

# The ROOT, not "inside one". --is-inside-work-tree searches upward, so a
# Toolkit copy under any other repository answered yes and everything below ran
# against THAT repository -- including the fast-forward.
#
if (-not (Test-P20GitRoot -Path $pkgRoot)) {
    $enclosing = Get-P20EnclosingRepoHint -Path $pkgRoot -Subject 'Toolkit'
    Write-UpdateRefusal -Message "The Toolkit at '$pkgRoot' is not a git checkout, so there is nothing to pull." `
        -Hint $(if ($enclosing) { $enclosing } else { 'It was installed as a copy. Clone the repository to get updates.' })
    exit 2  # stated refusal
}

# Every git READ is checked. An unchecked rev-parse puts git's stderr into the
# message as if it were a branch name: "Branch 'fatal: ambiguous argument
# 'HEAD'...' has no upstream to pull from."
$branch = (Invoke-ToolkitGit @('rev-parse', '--abbrev-ref', 'HEAD') | Select-Object -First 1)
if ($LASTEXITCODE -ne 0 -or -not $branch) {
    Write-UpdateRefusal -Message "The Toolkit checkout at '$pkgRoot' has no branch to read." `
        -Hint 'A repository with no commits yet cannot be updated. Commit or clone first.'
    exit 2  # stated refusal
}
if ($branch -eq 'HEAD') {
    Write-UpdateRefusal -Message 'The Toolkit checkout is on a detached HEAD.' -Hint "Check out a branch first: git -C `"$pkgRoot`" switch main"
    exit 2  # stated refusal
}

$upstream = (Invoke-ToolkitGit @('rev-parse', '--abbrev-ref', '--symbolic-full-name', '@{u}') | Select-Object -First 1)
if ($LASTEXITCODE -ne 0 -or -not $upstream) {
    Write-UpdateRefusal -Message "Branch '$branch' has no upstream to pull from." -Hint "Set one: git -C `"$pkgRoot`" branch --set-upstream-to origin/$branch"
    exit 2  # stated refusal
}

# Tracked files only: an untracked scratch file is not a reason to refuse, and a
# fast-forward cannot clobber one without git refusing on its own.
$dirty = @(Invoke-ToolkitGit @('status', '--porcelain', '--untracked-files=no') | Where-Object { $_ })
if ($dirty.Count -gt 0) {
    Write-UpdateRefusal -Message "The Toolkit checkout has $($dirty.Count) uncommitted change(s); nothing was pulled." `
        -Hint "Commit or stash them first. First: $(($dirty | Select-Object -First 1).Trim())"
    exit 2  # stated refusal
}

Write-Host ""
Write-Host "Toolkit: $pkgRoot  ($branch <- $upstream)" -ForegroundColor Cyan

$fetchOut = Invoke-ToolkitGit @('fetch', '--quiet')
if ($LASTEXITCODE -ne 0) {
    Write-UpdateRefusal -Message 'Could not reach the remote to fetch.' -Hint (($fetchOut | Select-Object -Last 1))
    exit 2  # stated refusal
}

$countLine = (Invoke-ToolkitGit @('rev-list', '--left-right', '--count', "HEAD...$upstream") | Select-Object -First 1)
if ($LASTEXITCODE -ne 0 -or $countLine -notmatch '^\s*\d+\s+\d+\s*$') {
    Write-UpdateRefusal -Message 'Could not compare this checkout with its upstream.' `
        -Hint "git -C `"$pkgRoot`" rev-list --left-right --count HEAD...$upstream said: $countLine"
    exit 2  # stated refusal
}
$counts = $countLine.Trim() -split '\s+'
$ahead = [int]$counts[0]
$behind = [int]$counts[1]
$oldHead = (Invoke-ToolkitGit @('rev-parse', '--short', 'HEAD') | Select-Object -First 1)

if ($ahead -gt 0 -and $behind -gt 0) {
    Write-UpdateRefusal -Message "Local and remote have diverged ($ahead local commit(s), $behind on the remote); nothing was pulled." `
        -Hint 'This verb only fast-forwards. Rebase or merge by hand.'
    exit 2  # stated refusal
}

$changed = @()
if ($behind -eq 0) {
    $note = ''
    if ($ahead -gt 0) { $note = " ($ahead local commit(s) not pushed)" }
    Write-Host "  Already up to date at $oldHead.$note" -ForegroundColor Green
}
else {
    $changed = @(Invoke-ToolkitGit @('diff', '--name-only', "HEAD..$upstream") | Where-Object { $_ })

    # Which Python, answered here -- before the fast-forward re-imports the module,
    # so the answer is held in variables, which survive a re-import (AGENTS.md, "A
    # function defined in a script does not survive the module being
    # re-imported"). A fallback says it is a guess, and why: it fell back silently
    # in Test-Update's sandbox, which never copied Resolve-Python.ps1 in -- wrong on
    # Windows, and invisible on macOS, where `python3` is also the right word.
    #
    $pythonWord = 'python3'
    $pythonWhy = ''
    if (@($changed | Where-Object { $_ -like 'agent/requirements*.txt' }).Count -gt 0) {
        # Scripts/Resolve-Python.ps1 is the one implementation of "which Python".
        $resolverScript = Join-Path $PSScriptRoot 'Resolve-Python.ps1'
        $resolvedPython = $null
        if (-not (Test-Path -LiteralPath $resolverScript)) {
            $pythonWhy = "Scripts/Resolve-Python.ps1 is missing from this package"
        }
        else {
            . $resolverScript
            try { $resolvedPython = Resolve-P20Python -Windows (($PSVersionTable.PSEdition -eq 'Desktop') -or $IsWindows) }
            catch { $pythonWhy = "the resolver failed: $($_.Exception.Message)" }
        }
        if ($resolvedPython -and $resolvedPython.Display) { $pythonWord = $resolvedPython.Display }
        elseif (-not $pythonWhy) { $pythonWhy = 'no Python interpreter answered on this PATH' }
    }
    Write-Host "  $behind new commit(s), $($changed.Count) file(s):" -ForegroundColor White
    foreach ($line in (Invoke-ToolkitGit @('log', '--format=    %h %s', "HEAD..$upstream") | Select-Object -First 8)) { Write-Host $line -ForegroundColor Gray }
    if ($behind -gt 8) { Write-Host "    ... and $($behind - 8) more" -ForegroundColor DarkGray }

    if ($PSCmdlet.ShouldProcess($pkgRoot, "fast-forward $branch to $upstream")) {
        $pullOut = Invoke-ToolkitGit @('merge', '--ff-only', '--quiet', $upstream)
        if ($LASTEXITCODE -ne 0) {
            Write-UpdateRefusal -Message 'The fast-forward failed; nothing was changed.' -Hint (($pullOut | Select-Object -Last 1))
            exit 2  # stated refusal
        }
        $newHead = (Invoke-ToolkitGit @('rev-parse', '--short', 'HEAD') | Select-Object -First 1)
        Write-Host "  Updated $oldHead -> $newHead." -ForegroundColor Green

        # The running shell has the OLD module. Re-import it so this shell -- and
        # the sync below -- run the code that was just pulled.
        $manifest = Join-Path (Join-Path $pkgRoot 'Prompt20Toolkit') 'Prompt20Toolkit.psd1'
        if ((Get-Module | Where-Object { $_.Path -like "$pkgRoot*" }) -and (Test-Path $manifest)) {
            try {
                Import-Module $manifest -Force -Global -WarningAction SilentlyContinue -ErrorAction Stop 3>$null
                Write-Host "  Re-imported into this shell. Other open shells still have the old version." -ForegroundColor Gray
            }
            catch {
                Write-Host "  Could not re-import into this shell ($($_.Exception.Message)). Open a new one." -ForegroundColor Yellow
            }
        }
    }
    else {
        Write-Host "  (-WhatIf: nothing was pulled)" -ForegroundColor Yellow
    }
}

# What the pull touched that needs a hand. Said, not done: the point of this
# verb is that the machine NOTICES. The words are the same under -WhatIf.
$next = @()
if (@($changed | Where-Object { $_ -like 'Prompt20Toolkit/*' }).Count -gt 0) {
    $next += "the autoload shim changed       ->  ${prefix}InstallAutoload -Force"
}
if ($changed -contains 'web/package-lock.json') {
    $next += "the web UI's dependencies moved ->  cd web; npm ci"
}
if (@($changed | Where-Object { $_ -like 'agent/requirements*.txt' }).Count -gt 0) {
    # Name the interpreter that WORKS here, the way Start-Agent does: on Windows
    # `python3` is the Store stub.
    # Resolved above, before the re-import; a fallback says it is a guess, and why.
    $pythonNote = if ($pythonWhy) { "   (python3 is a guess: $pythonWhy)" } else { '' }
    $next += "the agent's requirements moved  ->  $pythonWord -m pip install -r agent/requirements-dev.txt$pythonNote"
}
# The assistant's copy of AGENTS.md lives outside the tree, so no repo test can
# see it go stale -- this is where the machine notices. Asked every run, not only
# when AGENTS.md moved: a copy can already be behind before this pull.
#
$agentDocs = Join-Path $PSScriptRoot 'Update-AgentDocs.ps1'
if (Test-Path $agentDocs) {
    & $agentDocs -Check *> $null
    if ($LASTEXITCODE -eq 1) {
        $next += "the agent guidance is behind AGENTS.md ->  pwsh ./Scripts/Update-AgentDocs.ps1"
    }
    $global:LASTEXITCODE = 0
}
# A Demo copied out before the sample cards had covers stays bare after
# the pull. Said, never done: Cover -Samples is the one thing that writes, and a
# person runs it. Asked every run -- the pull that brought the pictures may be an
# earlier one. The hub is wherever PROMPTS_ROOT or the module's config says; with
# neither, there is no hub to look in and nothing to say. Never fatal: a notice
# must not turn a good update into a failure.
try {
    $hubRoot = $env:PROMPTS_ROOT
    if ($global:P20Config -and $global:P20Config.PromptsRoot) { $hubRoot = [string]$global:P20Config.PromptsRoot }
    $gapScript = Join-Path $PSScriptRoot 'Get-SampleCoverGaps.ps1'
    if ($hubRoot -and (Test-Path -LiteralPath $gapScript)) {
        . $gapScript
        $coverGaps = @(Get-P20SampleCoverGaps -PromptsRoot $hubRoot -PackageRoot $pkgRoot)
        if ($coverGaps.Count -gt 0) {
            $cardWord = 'sample cards in this hub have'
            if ($coverGaps.Count -eq 1) { $cardWord = 'sample card in this hub has' }
            $next += "$($coverGaps.Count) $cardWord no cover  ->  ${prefix}Cover -Samples"
        }
    }
}
catch { $null = $_ }
if ($next.Count -gt 0) {
    Write-Host ""
    Write-Host "  Also needed on this machine:" -ForegroundColor Yellow
    foreach ($n in $next) { Write-Host "    $n" -ForegroundColor Yellow }
}
Write-Host ""

$global:LASTEXITCODE = 0
if (-not $Sync) { exit 0 }
if ($WhatIfPreference) {
    Write-Host "  (-WhatIf: the prompt store was not synced)" -ForegroundColor Yellow
    Write-Host ""
    exit 0
}

# Software first, then data. Through the VERB, not the script, so it is the
# freshly imported code, its config and its refusal contract that run -- and
# through its ALIAS, the way a person types it. Every wrapper in the module works
# out its prefix from the name it was INVOKED by; called by its function name it
# resolves no prefix, and the first real `Update -Sync` died in the hand-off with
# "Cannot bind argument to parameter 'Prefix'" after a perfectly good update.
$syncCommand = $null
if ($prefix) { $syncCommand = Get-Command "${prefix}Sync" -ErrorAction SilentlyContinue }
if (-not $syncCommand) {
    Write-UpdateRefusal -Message 'The Toolkit is updated, but the Sync verb is not loaded in this shell.' -Hint "Run ${prefix}Sync in a new shell."
    exit 2  # stated refusal
}
Write-Host "Prompt store:" -ForegroundColor Cyan
& "${prefix}Sync"
exit $LASTEXITCODE
