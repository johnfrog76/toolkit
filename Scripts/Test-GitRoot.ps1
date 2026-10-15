<#
.SYNOPSIS
    Is this folder the ROOT of a git work tree -- not merely somewhere inside one?
.DESCRIPTION
    `git rev-parse --is-inside-work-tree` answers the wrong question. Git
    searches UPWARD, so a plain folder sitting anywhere under another repository
    answers "yes", and every git command a verb runs afterwards operates on THAT
    repository. A Toolkit copy inside a monorepo reads as a checkout; a hub
    inside a dotfiles repo reads as a prompt store. `Update` would then
    fast-forward the enclosing repository and `Sync` would `git add -A`, commit
    and PUSH it -- an irreversible, outward-facing write, earned by nothing more
    than where a folder happens to sit.

    So the question a WRITER must ask is "is this folder the top level", and git
    answers it directly -- `rev-parse --show-prefix` is empty exactly at the root.
    Nothing here compares two paths; .NOTES says why that matters.

    A READER asks something different, and the difference matters. Backfill
    reads commit dates for cards and deliberately supports a hub that is a
    subfolder of its own repository -- there the history is genuinely about the
    cards. What disqualifies a folder there is not being a subfolder, it is the
    repository knowing nothing about it: a stray `git init` above the folder
    with none of its files tracked has no dates to give. `Test-P20GitTracksPath`
    is that question, and it is why this file exports two.

.NOTES
    ASK GIT, do not compare paths. `rev-parse --show-prefix` prints the path from
    the repository root down to the folder you asked about, and prints NOTHING
    when that folder IS the root. So the question is answered by git, in git's own
    terms, and every way two strings naming one folder can differ stops mattering:
    a symlinked path, the Windows 8.3 short form, case, separators, a trailing
    slash.

    The first version of this file did compare -- `--show-toplevel` against a
    normalised copy of the folder -- and it was wrong on macOS within a day. Git
    resolves symlinks and `(Get-Item).FullName` does not, and on macOS every temp
    folder is reached through one (`/var` -> `/private/var`), so a real checkout
    read as "not a git checkout" and four suites went red.
    The comparison also needed to know whether the filesystem was case-sensitive,
    which meant reading one of the platform variables PowerShell 7 adds and 5.1
    does not have -- below the floor this package supports, and flagged by the
    Compat suite. Both problems belonged to the comparison, and neither exists
    once git is the one answering.
#>

function Get-P20GitToplevel {
    <#
      The root of the work tree the folder belongs to, or '' when it belongs to
      none. Never throws, and never lets git's stderr become the answer: a
      non-zero exit is '' and nothing else.
    #>
    param([Parameter(Mandatory)][string]$Path)

    if (-not (Get-Command git -ErrorAction SilentlyContinue)) { return '' }
    if (-not (Test-Path -LiteralPath $Path)) { return '' }

    $previous = $global:LASTEXITCODE
    $out = @(& git -C $Path rev-parse --show-toplevel 2>$null | ForEach-Object { "$_" })
    $ok = ($LASTEXITCODE -eq 0)
    $global:LASTEXITCODE = $previous
    if (-not $ok) { return '' }
    $top = ($out | Where-Object { $_ } | Select-Object -First 1)
    if (-not $top) { return '' }
    return "$top".Trim()
}

function Test-P20GitRoot {
    <#
      Is $Path itself the top level of a work tree? The question every WRITER
      asks before it runs git: Update before it pulls, Sync before it commits
      and pushes.

      Answered by `rev-parse --show-prefix`, which is empty exactly at the root.
      No path comparison happens here on purpose -- see .NOTES.
    #>
    param([Parameter(Mandatory)][string]$Path)

    if (-not (Get-Command git -ErrorAction SilentlyContinue)) { return $false }
    if (-not (Test-Path -LiteralPath $Path)) { return $false }

    $previous = $global:LASTEXITCODE
    # Taken whole and joined: a native command piped into something that stops
    # early never exits, and $LASTEXITCODE then reports the PREVIOUS command's
    # result (the trap Test-P20GitTracksPath's comment records).
    $out = @(& git -C $Path rev-parse --show-prefix 2>$null)
    $ok = ($LASTEXITCODE -eq 0)
    $global:LASTEXITCODE = $previous
    if (-not $ok) { return $false }
    # Empty output IS the answer: no prefix means nothing between the root and
    # here. git prints a trailing slash for any real subdirectory.
    return ([string]::IsNullOrWhiteSpace(($out -join '')))
}

function Get-P20EnclosingRepoHint {
    <#
      The hint for a refusal, naming the repository that was found instead --
      the whole point being that the user can see WHY a plain folder looked like
      a checkout. Empty when the folder is in no repository at all, so the
      caller keeps whatever hint it already had.
    #>
    param(
        [Parameter(Mandatory)][string]$Path,
        # What this folder was supposed to be, for the sentence: 'Toolkit', 'hub'.
        [string]$Subject = 'folder'
    )

    $top = Get-P20GitToplevel -Path $Path
    if (-not $top) { return '' }
    if (Test-P20GitRoot -Path $Path) { return '' }
    return "'$Path' is inside the repository at '$top', which is not this $Subject. Git searches upward, so a folder under someone else's repository is not a checkout of its own."
}

function Test-P20GitTracksPath {
    <#
      Does the repository actually track anything in this folder? The question a
      READER asks, where a subfolder of a repository is legitimate and an
      unrelated repository above it is not.

      A stray `git init` two folders up leaves every file here untracked, so
      there is no history to read and the honest answer is the same refusal a
      non-git folder gets. A hub that IS a tracked subfolder answers true and
      keeps working, which is the behaviour Backfill documents and relies on.
    #>
    param([Parameter(Mandatory)][string]$Path)

    if (-not (Get-P20GitToplevel -Path $Path)) { return $false }

    $previous = $global:LASTEXITCODE
    # -- ends the option list; '.' is relative to -C, so this asks only about
    # this folder and below, never the whole repository.
    #
    # The output is taken WHOLE and filtered afterwards. Piping a native command
    # into `Select-Object -First` short-circuits the pipeline, so git never exits
    # normally and $LASTEXITCODE keeps whatever it held BEFORE the call -- the
    # check then reports "git failed" on the strength of some earlier command's
    # exit code. That read as "not a git repository" for a perfectly good hub,
    # and only when something non-zero had run first, which is why it survived
    # every isolated probe and why adding a debug line made it pass.
    $out = @(& git -C $Path ls-files -- . 2>$null)
    $ok = ($LASTEXITCODE -eq 0)
    $global:LASTEXITCODE = $previous
    return ($ok -and (@($out | Where-Object { $_ }).Count -gt 0))
}
