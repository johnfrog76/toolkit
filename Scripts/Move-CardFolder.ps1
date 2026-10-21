<#
.SYNOPSIS
    A card's folder move: backlog/ <-> current/. Dot-source it.

.DESCRIPTION
    Not a command -- no alias, no menu row, no help entry of its own.

    A Space has three card folders (docs/hub/cards.md, "Where it lives"):
    current/ (in play), archive/ (done) and backlog/ (planned, not yet in
    play). The state is the FOLDER for two of them, so moving a card between
    backlog/ and current/ IS the transition, the way moving it to archive/ is
    Done. This file is the one place that move is made:

      - Move <id> -To Backlog and -To Active (Scripts/Move-CardLane.ps1), the
        explicit moves;
      - the pull on first write: ThreadHash, NewPR and Move -To InProgress /
        CodeReview, each of which calls Invoke-P20PullIntoPlay before it writes
        the line that would put the card in play -- so a backlog card never
        carries a commit bullet, a PR URL, **Started:** or **Review:**.

    A folder move is a RENAME, not a rewrite: Move-Item, and nothing goes
    through Write-CardText because the folder changed. The card's package links
    are refreshed afterwards (Repair-P20CardLinks), which writes nothing when
    the two folders sit at the same depth, as they do -- so the bytes that arrive
    are the bytes that left (AGENTS.md, "One byte contract for a card").

    Dot-sourced rather than reached through utilities.psm1: every caller also
    runs as a plain script with no module imported, which is how their suites
    drive them.

        . (Join-Path $PSScriptRoot 'Move-CardFolder.ps1')

.NOTES
    PowerShell 5.1 compatible (ASCII dashes only).
#>

if (-not (Get-Command Get-P20Consts -ErrorAction SilentlyContinue)) {
    . (Join-Path $PSScriptRoot 'Get-Consts.ps1')
}
# Always, not "if missing": its functions read script-scope patterns this
# dot-source defines, so a copy found elsewhere would read none of them.
. (Join-Path $PSScriptRoot 'Repair-CardLinks.ps1')

function Get-P20SiblingCardFolder {
    <#
        The Space's <Name> folder beside the folder a card is in: backlog/ beside
        current/, current/ beside backlog/. The same sibling hop
        Get-P20ArchiveFolderFor makes, so a caller holding one folder -- or a
        test's Get-PromptFolders stub that knows only two -- finds the third.
    #>
    param(
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Folder,
        [Parameter(Mandatory = $true)][string]$Name
    )
    if (-not $Folder) { return $null }
    $parent = Split-Path ($Folder.TrimEnd('/', '\')) -Parent
    if (-not $parent) { return $null }
    return (Join-Path $parent $Name)
}

function Get-P20BacklogFolder {
    <#
        The active Space's backlog/: Get-PromptFolders' Backlog, else the sibling
        of its Current (a stub that predates the third folder).
    #>
    param($Folders)
    if (-not $Folders) { return $null }
    if ($Folders.Backlog) { return [string]$Folders.Backlog }
    return (Get-P20SiblingCardFolder -Folder ([string]$Folders.Current) -Name ([string](Get-P20Consts).folders.backlog))
}

function Test-P20CardInBacklog {
    # Is the file at $Path in a backlog/ folder? The folder's NAME decides, as it
    # does for archive/ -- the state rule reads the same segment.
    param([AllowEmptyString()][string]$Path)
    if (-not $Path) { return $false }
    $dir = Split-Path $Path -Parent
    if (-not $dir) { return $false }
    return ((Split-Path $dir -Leaf) -eq [string](Get-P20Consts).folders.backlog)
}

function Get-P20InPlayMarkers {
    <#
        What in a card's text says it is in play: a commit bullet, a PR URL:
        line, a **Started:** line, a **Review:** line -- the four tokens the
        state rule reads, from consts.json. Empty means nothing is threaded,
        which is the one shape Move -To Backlog accepts.
    #>
    param([AllowEmptyString()][AllowNull()][string]$Content)
    $c = Get-P20Consts
    $found = @()
    $text = "$Content"
    if ($text -match $c.regex.commitBullet) { $found += 'a commit bullet' }
    if ($text -match $c.regex.prUrlLine) { $found += "a $($c.tokens.prUrl) line" }
    if ($text -match $c.regex.startedLine) { $found += "a $($c.stamps.started) line" }
    if ($text -match $c.regex.reviewLine) { $found += "a $($c.stamps.review) line" }
    return , $found
}

function Move-P20CardFile {
    <#
        Move the card at $Path into $Destination (a folder), by RENAME. Refuses,
        and moves nothing, when a file of that name is already there: nothing
        overwrites a card (AGENTS.md, "current/ is protected").

        Returns @{ Ok; Path; Message }. The caller states a refusal; this never
        writes to the console.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Inner helper; the verb owns the decision.')]
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Destination
    )
    $name = Split-Path $Path -Leaf
    $target = Join-Path $Destination $name
    if (Test-Path -LiteralPath $target) {
        return @{ Ok = $false; Path = $Path; Message = "$name is already in $(Split-Path $Destination -Leaf)/, and nothing overwrites a card." }
    }
    if (-not (Test-Path -LiteralPath $Destination)) {
        New-Item -ItemType Directory -Path $Destination -Force | Out-Null
    }
    Move-Item -LiteralPath $Path -Destination $target -ErrorAction Stop
    # The links are computed from the card's folder. backlog/ and current/ sit at
    # one depth, so this writes nothing -- and on a hub where they do not, it is
    # the one pass that knows how to say the hop.
    $null = Repair-P20CardLinks -Path $target
    return @{ Ok = $true; Path = $target; Message = '' }
}

function Invoke-P20PullIntoPlay {
    <#
        The pull on first write. A card in backlog/ is moved to current/ BEFORE
        the writer that would put it in play writes its line -- the first
        ThreadHash, NewPR, Move -To InProgress / CodeReview -- so the flow a
        person types is unchanged and the card arrives in play with its first
        token already on it. A card that is not in backlog/ comes back as it was.

        Returns @{ Ok; Path; Pulled; Message }: Path is where the card is now.
    #>
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [switch]$Quiet
    )
    if (-not (Test-P20CardInBacklog -Path $Path)) {
        return @{ Ok = $true; Path = $Path; Pulled = $false; Message = '' }
    }
    $c = Get-P20Consts
    $currentDir = Get-P20SiblingCardFolder -Folder (Split-Path $Path -Parent) -Name ([string]$c.folders.current)
    $moved = Move-P20CardFile -Path $Path -Destination $currentDir
    if (-not $moved.Ok) {
        return @{ Ok = $false; Path = $Path; Pulled = $false; Message = $moved.Message }
    }
    if (-not $Quiet) {
        Write-Host "[>] $(Split-Path $Path -Leaf) pulled from $($c.folders.backlog)/ into $($c.folders.current)/ -- it is in play now." -ForegroundColor Cyan
    }
    return @{ Ok = $true; Path = $moved.Path; Pulled = $true; Message = '' }
}
