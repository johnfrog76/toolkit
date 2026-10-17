<#
.SYNOPSIS
    Quick cross-machine sync for the prompts repo: pull --rebase then push.
.DESCRIPTION
    Runs git pull --rebase then git push in the prompts repo root.
    If the rebase hits conflicts, it aborts and leaves the repo unchanged.

    Only runs when storeSync is 'git'. That switch lives in the hub's own
    hub.json -- whether the store is a git repository is a fact about the hub,
    so both machines read the same answer -- and config.local.json overrides it
    per machine, which is how a machine that must never push says so.
.EXAMPLE
    {cliPrefix}Sync
#>
[CmdletBinding()]
param()

# Its own preference, like every other script: left unset it is the caller's,
# and a caller holding 'Stop' would turn the first stderr line of a native
# call into a throw on Windows PowerShell 5.1.
$ErrorActionPreference = 'Stop'

# The tool maintains files in a directory and has no opinion about what keeps
# that directory safe. Sync exists only for stores that happen to be git; any
# other arrangement -- a synced folder, a share, a zip -- syncs itself or does
# not need to.
#
# storeSync resolves config.default.json -> the hub's hub.json -> this machine's
# config.local.json, so keeping one hub in sync across two machines needs no
# per-machine switch: the hub says it once.
#
# State derivation never reads git. REPORTING does: review generation walks
# git log, and cards written before created/closed stamps existed can only be
# dated from history. So 'none' costs nothing for the workflow and costs the
# past for reports over an existing corpus.
if ($global:P20Config.StoreSync -ne 'git') {
    Write-Host ""
    Write-Host "  Nothing to sync: storeSync is '$($global:P20Config.StoreSync)'." -ForegroundColor Gray
    Write-Host "  The prompt store is a directory; whatever keeps it safe is yours to choose." -ForegroundColor DarkGray
    Write-Host "  If the store is a git repo, set storeSync: git in the hub's hub.json," -ForegroundColor DarkGray
    Write-Host "  or override it per machine in config.local.json." -ForegroundColor DarkGray
    Write-Host ""
    exit 0
}

$promptsRoot = $global:P20Config.PromptsRoot
. (Join-Path $PSScriptRoot 'Initialize-CliFallbacks.ps1')

# Test-P20HubRoot and the one "hub not found" sentence live here, and this file
# is dot-sourced rather than reached through the module because this script also
# runs with no module in the session (a test sandbox, `pwsh -File`).
. (Join-Path $PSScriptRoot 'Resolve-HubConfig.ps1')

# Every git call here goes through this, except the pull and the push, which
# pass git's own output to the terminal as it arrives.
. (Join-Path $PSScriptRoot 'Invoke-TrackerRead.ps1')

# A card's links back into the package are relative paths, and a hub pulled onto
# a second machine is a hub whose clone sits somewhere else -- so the pull is
# exactly the moment those paths stop being right. Refreshing here is what makes
# a hub fix itself on the machine that pulled it, instead of leaving the
# engineer to count `../` by hand in every card written before the move.
#
. (Join-Path $PSScriptRoot 'Repair-CardLinks.ps1')

if (-not (Test-P20HubRoot $promptsRoot)) {
    Write-CliError -Message (Get-P20HubMissingMessage $promptsRoot)
    exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
}

# BEFORE anything is written. This verb runs `git add -A`, commits, rebases and
# PUSHES from the hub -- and `git add -A` from a subdirectory stages the whole
# repository, so a hub sitting under an unrelated repository would commit and
# push everything in it. `--is-inside-work-tree` said yes to exactly that,
# because git searches upward; the check is whether the hub IS the root.
#
#
# storeSync has already said 'git' by here, and that is exactly the case this
# guards: saying "my hub is a git repo" must not be taken as permission to
# write to whatever repository happens to enclose the folder.
. (Join-Path $PSScriptRoot 'Test-GitRoot.ps1')
if (-not (Test-P20GitRoot -Path $promptsRoot)) {
    $enclosing = Get-P20EnclosingRepoHint -Path $promptsRoot -Subject 'hub'
    Write-CliError -Message "The hub at '$promptsRoot' is not the root of a git repository, so nothing was synced." `
        -Hint $(if ($enclosing) { "$enclosing Nothing was committed, rebased or pushed." } else { "Run: git -C `"$promptsRoot`" init, or set storeSync to none." })
    exit 2  # stated refusal
}

# -ErrorAction Stop: a hub that cannot be entered (a short Windows path, an
# unmapped drive) is a failure, not a sync of the current directory.
Push-Location -LiteralPath $promptsRoot -ErrorAction Stop
try {
    Write-Host "Syncing prompts repo ($promptsRoot)..." -ForegroundColor Cyan

    # Auto-commit usage.log (and any other tracked changes) before rebase.
    # Without this, Write-ToolkitLog entries from previous commands leave the
    # working tree dirty, which causes git pull --rebase to fail (exit 128).
    # Runs through the normal pre-commit hook (no --no-verify) so a runaway
    # dirty tree (missing .gitignore, or a corrupted-file blowup past the
    # staged-file guard) stops sync here instead of auto-committing silently.
    $status = Invoke-P20TrackerRead 'git' @('status', '--porcelain')
    if ($status.Code -ne 0) {
        Write-CliError -Message "git status failed in '$promptsRoot', so nothing was synced." -Hint "git said: $(@($status.Lines)[0])"
        exit 2  # stated refusal
    }
    if (@($status.Out).Count -gt 0) {
        # Remember anything already staged before we widen with -A. On a hook
        # failure the recovery reset unstages everything, which would silently
        # flatten a deliberate partial-staging setup -- exactly the state the
        # user most wants preserved when a runaway tree trips the guard.
        $preStaged = @((Invoke-P20TrackerRead 'git' @('diff', '--cached', '--name-only')).Out)

        $null = Invoke-P20TrackerRead 'git' @('add', '-A')
        $commit = Invoke-P20TrackerRead 'git' @('commit', '-m', 'auto-commit before sync')
        if ($commit.Code -ne 0) {
            $null = Invoke-P20TrackerRead 'git' @('reset')
            if ($preStaged.Count -gt 0) {
                # Re-stage exactly what was staged before, nothing more. -- ends
                # the option list so paths that look like flags still resolve.
                $null = Invoke-P20TrackerRead 'git' (@('add', '--') + $preStaged)
                Write-Host "  Restored $($preStaged.Count) previously staged file(s)." -ForegroundColor DarkGray
            }
            Write-Warning "Pre-commit hook blocked auto-commit - aborting sync to leave repo unchanged."
            $commit.Lines | ForEach-Object { Write-Host $_ }
            return
        }
        Write-Host "  Committed pending changes before pull." -ForegroundColor DarkGray
    }

    # The pull and the push are the two raw calls: git prints its progress on
    # stderr as it goes and the person watching wants it as it arrives. 'Stop'
    # would make the first line a throw on 5.1, so each runs under 'Continue'
    # and the exit code is read right after.
    # Pull with rebase
    $ErrorActionPreference = 'Continue'
    git pull --rebase 2>&1 | ForEach-Object { Write-Host $_ }
    $pullCode = $LASTEXITCODE
    $ErrorActionPreference = 'Stop'
    if ($pullCode -ne 0) {
        Write-Warning "Rebase failed - aborting to leave repo unchanged."
        $null = Invoke-P20TrackerRead 'git' @('rebase', '--abort')
        return
    }

    # The hub's manifest in the product's spelling (stage 2): a hub.json
    # that still says `orgs` is rewritten to `spaces` once, here, on the
    # machine that pulled it, and committed -- so the other machine pulls the
    # new spelling with a toolkit that already reads it (step 1 shipped first).
    $manifestPath = Join-Path $promptsRoot (Get-P20HubManifestName)
    if (Update-P20SpaceKeysInFile -Path $manifestPath) {
        Write-Host "  hub.json now says spaces -- the Space rename." -ForegroundColor DarkGray
        $null = Invoke-P20TrackerRead 'git' @('add', '--', (Get-P20HubManifestName))
        $spell = Invoke-P20TrackerRead 'git' @('commit', '-m', 'sync: hub.json says spaces')
        $spellOut = ($spell.Lines -join "`n")
        if ($spell.Code -ne 0 -and $spellOut -notmatch 'nothing to commit|nothing added to commit|no changes added') {
            Write-Warning "Could not commit hub.json's new spelling; it is still on disk. git said: $($spellOut.Trim())"
        }
    }

    # Refresh every card's package links from where the hub and the package are
    # NOW -- before the push, so the machine that pulled the move is the machine
    # that publishes the repair. Idempotent and byte-preserving: a hub whose
    # links are already right produces no diff and nothing to commit.
    # EVERY org's folders, not only the active one's: an org nobody switches to
    # would otherwise keep stale links forever.
    $folders = Get-PromptFolders
    $relinked = 0
    $cardFolders = Get-P20CardFolders -Root $promptsRoot -Spaces $global:P20Config.Spaces `
        -CurrentName (Split-Path $folders.Current -Leaf) -ArchiveName (Split-Path $folders.Archive -Leaf) `
        -Also @($folders.Current, $folders.Archive)
    foreach ($folder in $cardFolders) {
        $relinked += Repair-P20FolderLinks -Folder $folder
    }
    if ($relinked -gt 0) {
        Write-Host "  Refreshed package links in $relinked card(s)." -ForegroundColor DarkGray
        $null = Invoke-P20TrackerRead 'git' @('add', '-A')
        $linkCommit = Invoke-P20TrackerRead 'git' @('commit', '-m', 'sync: refresh package links after a move')
        $commitOut = ($linkCommit.Lines -join "`n")
        # "nothing to commit" exits non-zero too: on a Windows hub with
        # core.autocrlf, git ignores a line-ending-only change, and a refresh
        # that changed no bytes git cares about is not a failed commit.
        if ($linkCommit.Code -ne 0 -and $commitOut -notmatch 'nothing to commit|nothing added to commit|no changes added') {
            Write-Warning "Could not commit the refreshed links; they are still on disk. git said: $($commitOut.Trim())"
        }
    }

    # Push
    $ErrorActionPreference = 'Continue'
    git push 2>&1 | ForEach-Object { Write-Host $_ }
    $pushCode = $LASTEXITCODE
    $ErrorActionPreference = 'Stop'
    if ($pushCode -ne 0) {
        Write-Warning "Push failed. Check remote status."
        return
    }

    # Ensure current/ directory exists (Git drops empty directories)
    $currentDir = $folders.Current
    if (-not (Test-Path $currentDir)) {
        New-Item -Path $currentDir -ItemType Directory -Force | Out-Null
        Write-Host "Recreated empty current/ directory." -ForegroundColor Yellow
    }

    Write-Host "Sync complete." -ForegroundColor Green
}
finally {
    Pop-Location
}
