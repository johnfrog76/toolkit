<#
.SYNOPSIS
    StartWork -- one markdown block a cold agent can start the work from (the Team Agile add-on).

.DESCRIPTION
    The third move of the loop (docs/modules/solitaire-agile.md, "StartWork: the
    hand-off block"). Triage the backlog, make the issues, then start the work:
    this verb assembles everything the agent needs from three things that
    already exist, and writes none of them.

        # Start work: <Kind> <id> -- <title>

        ## How we work in <Space> (<source>)
        <one derived sentence from spaces[].howIWork, or the Space's how-we-work.md>

        ## The work: <Kind> <id> (<hub-relative path, or the issue's URL>)
        <the card's text, whole -- or the issue's title, labels, milestone and body>

        ## The prompt (<package-relative path>)
        <the chosen agentic prompt's text, whole>

    Plain markdown on stdout, LF-joined, nothing before and nothing after it,
    so `| pbcopy` and `> file` carry exactly the block. The four heading shapes
    are the contract's (consts.json startWork.text); which prompt a kind gets
    is configuration (config.default.json startWork.prompts).

    THE INPUT is resolved the one way every verb resolves one
    (Resolve-P20CardArgument): a card in current/ -- an id matches that id and
    never a substring. Then, for a work-item number no card in current/
    carries, the Space's GitHub issue of that number. Refused, each a stated
    refusal: an Azure DevOps Space (its board holds the rituals), an archived
    card or a closed issue (the work is done), a card in backlog/ (planned, not
    in play: Move <id> -To Active is the decision), an id that matches nothing, a
    partial name for a non-interactive caller, a kind with no prompt row, a
    prompt file that is not there.

    THE CARD'S BYTES travel: it is read whole, as Status reads it, never from a
    parsed model, so its commit bullets, its PR URL: line and its footer stamps
    reach the agent. The one transform is the terminator rule: CRLF reads as
    LF, so a Windows card and a Mac card give the same block.

    Writes nothing: not the hub, not the tracker.

    -LAUNCH (D-AR12) is the secondary action: the same block, handed to a
    session that starts the work where it gets done. Refused, each a stated
    refusal, unless the repository you stand in has the Space's GitHub address
    as its origin, claude is on the PATH, and the item has a crew size this
    launch has a model for: sonnet or opus. fable -- the owner's own seat --
    and an item with no size are refused with the hint to route it. Then it
    adds a detached worktree of that repository under its .claude/worktrees/,
    writes the block to <repo>/startwork-<ref>-<stamp>.block.log, and starts
    `claude --print --model <size> --output-format stream-json --verbose` in
    the worktree with that file as its stdin (claude --print reads its prompt
    there; a prompt of many lines does not cross a joined command line whole),
    through Start-Detached.ps1's Start-DetachedProcess -- the one launcher
    that keeps the caller's pipes from crossing, so
    `pwsh -c 'StartWork <id> -Launch' | cat` returns at once -- with its output
    to <repo>/startwork-<ref>-<stamp>.log (and .err.log), all three under the
    *.log ignore pattern. Prints the PID, the worktree and the log,
    and returns without waiting. -WhatIf runs every check and prints the
    commands it would run, and adds and starts nothing. The size is read the
    way the rituals read it: a card's **Assigned:** line, else a size in its
    Tags, else -- for a card whose id is an issue number -- the issue's labels;
    an issue's labels.

.PARAMETER Id
    The card's id (or its filename), or a GitHub issue number.
.PARAMETER Clip
    Put the block on the clipboard and say so in one line, instead of printing it.
.PARAMETER Prompt
    A prompt file to carry instead of the kind's row, for this call: absolute,
    or relative to the current folder, else to the package.
.PARAMETER Space
    A declared Space's slug, to read instead of the one you are in.
.PARAMETER Launch
    Start a session on the block in a new worktree of the Space's repository,
    with the model the item's size names; print its PID and log, and return.
.PARAMETER WhatIf
    With -Launch: run every check, print the commands, start nothing.

.EXAMPLE
    {cliPrefix}StartWork 23A3
.EXAMPLE
    {cliPrefix}StartWork 23A3 -Clip
.EXAMPLE
    {cliPrefix}StartWork 4 -Prompt agentic/new-issue.prompt.md
.EXAMPLE
    {cliPrefix}StartWork 23A3 -Launch -WhatIf

.NOTES
    PowerShell 5.1 compatible (ASCII dashes only).
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $false, Position = 0)]
    [string]$Id,
    [Parameter(Mandatory = $false)]
    [switch]$Clip,
    [Parameter(Mandatory = $false)]
    [string]$Prompt,
    [Parameter(Mandatory = $false)]
    [string]$Space,
    [Parameter(Mandatory = $false)]
    [switch]$Launch,
    [Parameter(Mandatory = $false)]
    [switch]$WhatIf,
    [Parameter(Mandatory = $false)]
    [switch]$Help
)

$repoRoot = Split-Path -Parent $PSScriptRoot

. (Join-Path $PSScriptRoot 'Initialize-CliFallbacks.ps1')

if ($Help) {
    $p = Get-CliPrefix
    Write-Host ""
    Write-Host "  ${p}StartWork -- one block a cold agent can start the work from" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  Usage:" -ForegroundColor Yellow
    Write-Host "    ${p}StartWork <id> [-Clip] [-Prompt <path>] [-Space <slug>] [-Launch] [-WhatIf]"
    Write-Host ""
    Write-Host "  How we work in this Space, the card (or the issue) and the prompt, each heading naming its file. Writes nothing."
    Write-Host "  -Launch starts a session on the block in a worktree of the Space's repository, the model from the item's size; -WhatIf prints it."
    Write-Host ""
    return
}

. (Join-Path $PSScriptRoot 'Resolve-HubConfig.ps1')
. (Join-Path $PSScriptRoot 'Get-Consts.ps1')
. (Join-Path $PSScriptRoot 'Resolve-CardName.ps1')
. (Join-Path $PSScriptRoot 'Resolve-Tracker.ps1')
. (Join-Path $PSScriptRoot 'Resolve-HowIWork.ps1')
. (Join-Path $PSScriptRoot 'Resolve-AgenticPrompt.ps1')
. (Join-Path $PSScriptRoot 'Invoke-TrackerRead.ps1')
. (Join-Path $PSScriptRoot 'Ritual-Common.ps1')
# The card's title, read from its heading by the standup's own rule (one rule, not two).
. (Join-Path $PSScriptRoot 'Standup-Rules.ps1')

$p = Get-CliPrefix
$c = Get-P20Consts
$t = $c.startWork.text
$cfg = $global:P20Config

function Format-P20StartWorkText {
    # One heading template with its {name} slots filled. Pure.
    param([string]$Template, [hashtable]$Values)
    $out = $Template
    foreach ($k in $Values.Keys) { $out = $out.Replace('{' + $k + '}', [string]$Values[$k]) }
    return $out
}

function ConvertTo-P20BlockText {
    # A file's text as the block carries it: CRLF read as LF (the terminator
    # rule), and no trailing blank lines -- the block joins its parts itself.
    param([AllowEmptyString()][AllowNull()][string]$Text)
    return ([string]$Text).Replace("`r`n", "`n").TrimEnd([char]10)
}

function Get-P20RelativeTo {
    # A path under Root as Root-relative with forward slashes; anything else as given.
    param([string]$Path, [string]$Root)
    $full = ($Path -replace '\\', '/')
    $base = (([string]$Root) -replace '\\', '/').TrimEnd('/')
    if ($base -and $full.StartsWith($base + '/', [System.StringComparison]::OrdinalIgnoreCase)) { return $full.Substring($base.Length + 1) }
    return $full
}

function Get-P20StartWorkPrompts {
    # startWork.prompts, the shipped rows with this machine's over them, row by
    # row: Config -Set startWork.prompts.Bug=... writes one row to
    # config.local.json and the others stay the team's.
    param([string]$PackageRoot)
    $rows = [ordered]@{}
    foreach ($name in @('config.default.json', 'config.local.json')) {
        $path = Join-Path $PackageRoot $name
        if (-not (Test-Path -LiteralPath $path)) { continue }
        try { $json = [System.IO.File]::ReadAllText($path) | ConvertFrom-Json }
        catch {
            # A config.local.json that will not parse is said, never silently skipped.
            if ($name -eq 'config.local.json') { $null = Write-P20ConfigParseWarning -Path $path -Message $_.Exception.Message }
            continue
        }
        if (-not $json -or -not $json.PSObject.Properties['startWork'] -or -not $json.startWork) { continue }
        $table = $json.startWork.prompts
        if (-not $table) { continue }
        foreach ($prop in $table.PSObject.Properties) {
            if ($prop.Name.StartsWith('_')) { continue }
            $rows[$prop.Name] = [string]$prop.Value
        }
    }
    return $rows
}

function Get-P20CardKind {
    # A card's type from its FILENAME, by the workItemTypes table the filename
    # writer used: the longest prefix that matches, else the type whose prefix
    # is empty (a bare id is a Bug in the shipped table).
    param([string]$Name, [string]$CardId, [hashtable]$Types)
    $best = ''
    $bestLen = -1
    $bare = ''
    foreach ($typeName in @($Types.Keys | Sort-Object)) {
        $prefix = [string]$Types[$typeName].FilePrefix
        if (-not $prefix) { if (-not $bare) { $bare = $typeName }; continue }
        if ($Name.StartsWith($prefix + $CardId, [System.StringComparison]::OrdinalIgnoreCase) -and $prefix.Length -gt $bestLen) {
            $best = $typeName
            $bestLen = $prefix.Length
        }
    }
    if ($best) { return $best }
    return $bare
}

# -- The hub, the Space, its tracker -------------------------------------------
$hubRoot = ''
if ($cfg) { $hubRoot = [string]$cfg.PromptsRoot }
if (-not (Test-P20HubRoot $hubRoot)) {
    Write-CliError -Message (Get-P20HubMissingMessage $hubRoot)
    exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
}

# A name that is not $space: PowerShell variables are case-insensitive, so it
# would be the -Space PARAMETER and coerce the object to [string].
$resolvedSpace = Resolve-P20RitualSpace -Space $Space -Config $cfg
$slug = [string]$resolvedSpace.slug
$org = [string]$resolvedSpace.org
$spaceName = [string]$resolvedSpace.spaceName
if (-not $spaceName) { $spaceName = $slug }
$folderName = [string]$resolvedSpace.promptsFolder
$tracker = Resolve-P20Tracker -OrgUrl $org

if ($tracker -eq 'ado') {
    Write-CliError -Message "$spaceName is an Azure DevOps Space; StartWork hands off a card or an issue on a GitHub or local Space." `
        -Hint "Their board holds the rituals there. The card is still yours to open: '${p}Status' lists it."
    exit 2  # stated refusal
}

if ($Launch -and $Clip) {
    Write-CliError -Message '-Clip and -Launch are two ways to hand the block on; pass one.' `
        -Hint "'${p}StartWork <id> -Clip' copies it; '${p}StartWork <id> -Launch' starts a session on it."
    exit 2  # stated refusal
}
if ($WhatIf -and -not $Launch) {
    Write-CliError -Message '-WhatIf previews -Launch; StartWork alone writes nothing to preview.' `
        -Hint "'${p}StartWork <id> -Launch -WhatIf' prints the commands a launch would run."
    exit 2  # stated refusal
}

$wanted = ([string]$Id).Trim()
if (-not $wanted) {
    Write-CliError -Message 'StartWork needs a card id or an issue number.' `
        -Hint "'${p}StartWork <id>'. '${p}Status' lists the cards; '${p}Triage' the open issues."
    exit 2  # stated refusal
}

$spaceRoot = $hubRoot
if ($folderName) { $spaceRoot = Join-Path $hubRoot $folderName }
$currentDir = Join-Path $spaceRoot ([string]$c.folders.current)
$archiveDir = Join-Path $spaceRoot ([string]$c.folders.archive)
$types = Get-P20WorkItemTypes -Config $cfg
$pattern = Get-P20CardIdPattern -WorkItemTypes $types

# -- The item: a card in current/, else the issue of that number ---------------
$item = $null
$resolved = Resolve-P20CardArgument -Argument $wanted -Folder $currentDir -WorkItemTypes $types
$found = @($resolved.Match | Where-Object { $_.Name -like '*.md' })
if ($found.Count -gt 1) {
    Write-Host "Matches for '$wanted':" -ForegroundColor Yellow
    $found | ForEach-Object { Write-Host "  $($_.Name)" }
    Write-CliError -Message "'$wanted' matches $($found.Count) cards in current/." -Hint 'Pass the full filename of the one you mean.'
    exit 2  # stated refusal
}
if ($found.Count -eq 1 -and $resolved.Fuzzy) {
    # A partial name is a convenience in a terminal, and the target is named
    # before the block. A caller that cannot read that line (the bridge) is
    # refused rather than handed a card nobody named.
    if ($env:TOOLKIT_QUIET_STARTUP) {
        Write-CliError -Message "'$wanted' is not a card in current/; it matches '$($found[0].Name)' only by partial name." `
            -Hint "Pass the card's id or its full filename."
        exit 2  # stated refusal
    }
    Write-Host "Matched '$wanted' -> $($found[0].Name)" -ForegroundColor Cyan
}

if ($found.Count -eq 1) {
    $file = $found[0]
    $cardId = Get-P20CardId -Name $file.Name -Pattern $pattern
    $content = [System.IO.File]::ReadAllText($file.FullName)
    $typeName = ''
    if ($cardId) { $typeName = Get-P20CardKind -Name $file.Name -CardId $cardId -Types $types }
    if (-not $cardId) { $cardId = $file.Name }
    $item = @{
        Kind    = $typeName
        Key     = ($typeName -replace '\s', '')
        Ref     = $cardId
        Title   = (Get-P20StandupCardTitle -Content $content -File $file.Name -Id $cardId)
        Source  = (Get-P20RelativeTo -Path $file.FullName -Root $hubRoot)
        Text    = (ConvertTo-P20BlockText $content)
    }
}
else {
    # Nothing in current/. A planned card is in backlog/, and starting it is a
    # decision a person makes -- Move <id> -To Active -- not one StartWork makes
    # for them. An id, or a whole file name; never a partial one.
    $backlogDir = Join-Path $spaceRoot ([string]$c.folders.backlog)
    $plannedHit = Resolve-P20CardArgument -Argument $wanted -Folder $backlogDir -WorkItemTypes $types
    $planned = @($plannedHit.Match | Where-Object { $_.Name -like '*.md' })
    if ($planned.Count -gt 0 -and -not $plannedHit.Fuzzy) {
        $plannedId = Get-P20CardId -Name $planned[0].Name -Pattern $pattern
        if (-not $plannedId) { $plannedId = $wanted }
        Write-CliError -Message "Card $plannedId is in the backlog: $(Get-P20RelativeTo -Path $planned[0].FullName -Root $hubRoot) is planned, not in play." `
            -Hint "Starting it is the decision: '${p}Move $plannedId -To Active' pulls it into play, then '${p}StartWork $plannedId'."
        exit 2  # stated refusal
    }
    # An archived card is Done -- said as such, not as "no card".
    if ($resolved.IsId) {
        $archivedHit = Resolve-P20CardArgument -Argument $wanted -Folder $archiveDir -WorkItemTypes $types
        $archived = @($archivedHit.Match | Where-Object { $_.Name -like '*.md' })
        if ($archived.Count -gt 0) {
            Write-CliError -Message "Card $wanted is archived: $(Get-P20RelativeTo -Path $archived[0].FullName -Root $hubRoot) is Done." `
                -Hint "To work it again, '${p}NewPrompt' scaffolds a fresh card and Archive keeps every round."
            exit 2  # stated refusal
        }
    }
    $number = $wanted.TrimStart('#')
    if (-not ($resolved.IsId -or $wanted.StartsWith('#')) -or -not (Test-P20IsWorkItemId $number)) {
        if ($resolved.IsId) {
            Write-CliError -Message "No card with id '$wanted' in current/." `
                -Hint "'$wanted' has the shape of an ID, and an ID is not a partial name. Run '${p}Status' to see the cards."
        }
        else {
            Write-CliError -Message "No card matching '$wanted' in current/." -Hint "Run '${p}Status' to see the cards."
        }
        exit 2  # stated refusal
    }
    # A number no card carries: the Space's GitHub issue of that number.
    $why = ''
    if ($tracker -ne 'github') { $why = "$spaceName has no tracker to ask." }
    elseif ($resolvedSpace.status -eq 'local' -or $resolvedSpace.status -eq 'archive') { $why = "$spaceName is $($resolvedSpace.status), so its tracker is not asked." }
    if ($why) {
        Write-CliError -Message "No card with id '$number' in current/, and $why" -Hint "Run '${p}Status' to see the cards."
        exit 2  # stated refusal
    }
    $target = Resolve-P20TrackerRepo -OrgUrl $org -Projects $resolvedSpace.projects -CliPrefix $p
    if (-not $target.Repo) {
        Write-CliError -Message "No card with id '$number' in current/. $($target.Reason)" -Hint $target.Hint
        exit 2  # stated refusal
    }
    $repo = $target.Repo
    if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
        Write-CliError -Message "No card with id '$number' in current/, and gh is not installed, so issue #$number on $repo was not asked." `
            -Hint 'Install the GitHub CLI and sign in (gh auth login), or pass a card id.'
        exit 2  # stated refusal
    }
    $read = Invoke-P20TrackerRead 'gh' @('issue', 'view', $number, '--repo', $repo, '--json', 'number,title,state,labels,milestone,body,url')
    $raw = (@($read.Out) -join "`n").Trim()
    $issue = $null
    if ($read.Code -eq 0 -and $raw) {
        try { $issue = $raw | ConvertFrom-Json } catch { $issue = $null }
    }
    if (-not $issue) {
        $err = @($read.Err | ForEach-Object { ([string]$_).Trim() } | Where-Object { $_ }) | Select-Object -First 1
        $msg = "No card with id '$number' in current/, and issue #$number could not be read from $repo"
        if ($err) { $msg += ": $err" } else { $msg += '.' }
        Write-CliError -Message $msg -Hint "Check the number ('${p}Triage' lists the open issues) and that gh is signed in (gh auth status)."
        exit 2  # stated refusal
    }
    # gh issue view answers for a pull request's number too; a PR is not work to start.
    if ([string]$issue.url -match '/pull/\d+') {
        Write-CliError -Message "#$number on $repo is a pull request, not an issue." `
            -Hint "Pass an issue number or a card id. '${p}Triage' lists the open issues."
        exit 2  # stated refusal
    }
    if ("$($issue.state)".ToUpperInvariant() -eq 'CLOSED') {
        Write-CliError -Message "Issue #$number on $repo is closed: the work is done." -Hint "'${p}Triage' lists the open issues."
        exit 2  # stated refusal
    }
    # As a card renders "from the tracker": the title as its heading, Tags: the
    # labels, **Sprint:** the milestone, then the body.
    $labelWords = @($issue.labels | Where-Object { $_ } | ForEach-Object { [string]$_.name })
    $tags = '(None)'
    if ($labelWords.Count -gt 0) { $tags = $labelWords -join '; ' }
    $milestone = '(Not assigned to sprint)'
    if ($issue.milestone -and $issue.milestone.title) { $milestone = [string]$issue.milestone.title }
    $body = ConvertTo-P20BlockText ([string]$issue.body)
    if (-not $body.Trim()) { $body = '(No description provided)' }
    # The two lines are the card template's own words (templates/*.template.md).
    $issueText = @("# Issue #${number}: $($issue.title)", '', "Tags: $tags", "**Sprint:** $milestone", '', $body) -join "`n"
    $item = @{
        Kind   = 'Issue'
        Key    = 'issue'
        Ref    = "#$number"
        Title  = [string]$issue.title
        Source = [string]$issue.url
        Text   = $issueText
    }
}

# -- Section one: how we work in this Space ------------------------------------
# The Space's own note once it has one (HowWeWork writes it, at
# startWork.howWeWorkNote under the Space's folder; this verb only reads it),
# else ONE derived sentence from the howIWork table (D-AR3). A note a person put
# at the Space's folder root, where this verb looked before HowWeWork existed,
# is still read when the written one is not there. The heading names whichever
# was read, so the agent always knows where to re-read.
$notePath = Join-Path $spaceRoot ([string]$c.startWork.howWeWorkNote)
$rootNote = Join-Path $spaceRoot (Split-Path -Leaf ([string]$c.startWork.howWeWorkNote))
if (-not (Test-Path -LiteralPath $notePath -PathType Leaf) -and (Test-Path -LiteralPath $rootNote -PathType Leaf)) { $notePath = $rootNote }
if (Test-Path -LiteralPath $notePath -PathType Leaf) {
    $howSource = Get-P20RelativeTo -Path $notePath -Root $hubRoot
    $howText = ConvertTo-P20BlockText ([System.IO.File]::ReadAllText($notePath))
}
else {
    $storedAnswer = ''
    $entry = $null
    if ($cfg -and $cfg.Spaces) { $entry = @($cfg.Spaces | Where-Object { $_ -and [string]$_.slug -eq $slug }) | Select-Object -First 1 }
    if ($entry -and $entry.PSObject.Properties['howIWork']) { $storedAnswer = [string]$entry.howIWork }
    $how = Resolve-P20HowIWork -OrgUrl $org -Stored $storedAnswer
    $howSource = "hub.json: spaces[$slug].howIWork = $($how.answer)"
    $howText = Get-P20HowIWorkSentence -Answer $how.answer
}

# -- Section three: the prompt -------------------------------------------------
$promptPath = ''
if ($Prompt) {
    $given = $Prompt.Trim()
    $candidates = @()
    if ([System.IO.Path]::IsPathRooted($given)) { $candidates += $given }
    else { $candidates += (Join-Path (Get-Location).Path $given); $candidates += (Join-Path $repoRoot $given) }
    foreach ($cand in $candidates) {
        if (Test-Path -LiteralPath $cand -PathType Leaf) { $promptPath = (Get-Item -LiteralPath $cand).FullName; break }
    }
    if (-not $promptPath) {
        Write-CliError -Message "-Prompt names '$given', which is not a file." `
            -Hint 'A path relative to this folder or to the Toolkit package, or an absolute one. Leave -Prompt out for the kind''s own prompt.'
        exit 2  # stated refusal
    }
}
else {
    $key = "startWork.prompts.$($item.Key)"
    $rows = Get-P20StartWorkPrompts -PackageRoot $repoRoot
    $row = ''
    if ($item.Key -and $rows.Contains($item.Key)) { $row = ([string]$rows[$item.Key]).Trim() }
    $kindWords = $item.Kind
    if (-not $kindWords) { $kindWords = 'card of no known type' }
    if (-not $row) {
        Write-CliError -Message "No prompt is configured for a $kindWords ($key)." `
            -Hint "Set one: '${p}Config -Set $key=agentic/<name>.prompt.md'. Or pass -Prompt <path> for this call."
        exit 2  # stated refusal
    }
    $leaf = $row -replace '\\', '/'
    if ([System.IO.Path]::IsPathRooted($row)) { $promptPath = $row }
    elseif ($leaf.StartsWith('agentic/', [System.StringComparison]::OrdinalIgnoreCase) -and $leaf.IndexOf('/', 8) -lt 0) {
        # A shipped prompt: the one lookup, so a tuned copy in agenticExtensionPath wins here as everywhere.
        $promptPath = [string](Resolve-P20AgenticPrompt -Name $leaf.Substring(8) -PackageRoot $repoRoot).Path
    }
    else { $promptPath = Join-Path $repoRoot $row }
    if (-not (Test-Path -LiteralPath $promptPath -PathType Leaf)) {
        Write-CliError -Message "$key names '$row', which is not there." `
            -Hint "Point it at a prompt that exists: '${p}Config -Set $key=agentic/<name>.prompt.md'. Or pass -Prompt <path> for this call."
        exit 2  # stated refusal
    }
}
$promptSource = Get-P20RelativeTo -Path $promptPath -Root $repoRoot
if ($promptSource -eq ($promptPath -replace '\\', '/')) { $promptSource = Get-P20RelativeTo -Path $promptPath -Root $hubRoot }
$promptText = ConvertTo-P20BlockText ([System.IO.File]::ReadAllText($promptPath))

# -- The block -----------------------------------------------------------------
$sections = @(
    (Format-P20StartWorkText $t.head @{ kind = $item.Kind; id = $item.Ref; title = $item.Title }),
    ((Format-P20StartWorkText $t.howWeWork @{ space = $spaceName; source = $howSource }) + "`n" + $howText),
    ((Format-P20StartWorkText $t.work @{ kind = $item.Kind; id = $item.Ref; source = $item.Source }) + "`n" + $item.Text),
    ((Format-P20StartWorkText $t.prompt @{ source = $promptSource }) + "`n" + $promptText)
)
$block = $sections -join "`n`n"

# -- -Launch: the same block, handed to a session (D-AR12) ---------------------
if ($Launch) {
    # The one launcher (AGENTS.md: a long-lived child on Windows inherits every
    # pipe its launcher holds unless it starts through this file).
    . (Join-Path $PSScriptRoot 'Start-Detached.ps1')
    $ownerSeat = [string]$c.rituals.suggestOwnerSeat
    $meWord = [string]$c.rituals.assignMe
    # The crew sizes a launch has a model for: the size label IS the model's
    # name on the claude command line. One half types these, so they live here.
    $launchModels = [ordered]@{ sonnet = 'sonnet'; opus = 'opus' }
    $sizeWords = @($launchModels.Keys) -join ' or '
    $routeHint = "Route it to a crew size first: '${p}Route $wanted -Assign sonnet' (or opus)."
    $selfHint = "Work it yourself from the block ('${p}StartWork $wanted'), or route it to a crew size: '${p}Route $wanted -Assign sonnet' (or opus)."

    # 1. The repository you stand in is the Space's: its origin is the address.
    $spaceRepo = ''
    if ($tracker -eq 'github') {
        $repoTarget = Resolve-P20TrackerRepo -OrgUrl $org -Projects $resolvedSpace.projects -CliPrefix $p
        $spaceRepo = [string]$repoTarget.Repo
    }
    if (-not $spaceRepo) {
        Write-CliError -Message "$spaceName has no GitHub repository address, so -Launch has nowhere to start the session." `
            -Hint "A launch starts in a worktree of the Space's own repository: '${p}Config -Set spaces.$slug.org=https://github.com/<owner>/<repo>'. The block works without it: '${p}StartWork $wanted'."
        exit 2  # stated refusal
    }
    $topRead = Invoke-P20TrackerRead 'git' @('rev-parse', '--show-toplevel')
    $repoTop = ''
    if ($topRead.Code -eq 0) { $repoTop = [string](@($topRead.Out | Where-Object { "$_".Trim() }) | Select-Object -First 1) }
    $repoTop = $repoTop.Trim()
    if (-not $repoTop) {
        Write-CliError -Message "This folder is not in a git repository, and -Launch starts from a clone of $spaceRepo." `
            -Hint "cd into your clone of https://github.com/$spaceRepo and run '${p}StartWork $wanted -Launch' there."
        exit 2  # stated refusal
    }
    $repoTop = [System.IO.Path]::GetFullPath($repoTop)
    $originRead = Invoke-P20TrackerRead 'git' @('-C', $repoTop, 'remote', 'get-url', 'origin')
    $originUrl = ''
    if ($originRead.Code -eq 0) { $originUrl = ([string](@($originRead.Out) | Select-Object -First 1)).Trim() }
    # https://github.com/o/r(.git), git@github.com:o/r(.git), ssh://git@github.com/o/r -- the owner/repo after the host.
    $originRepo = ''
    $om = [regex]::Match($originUrl, '(?i)github\.com[:/]+([^/\s]+)/([^/\s]+?)(?:\.git)?/?$')
    if ($om.Success) { $originRepo = $om.Groups[1].Value + '/' + $om.Groups[2].Value }
    if (-not $originRepo -or $originRepo -ine $spaceRepo) {
        $originWords = 'no origin'
        if ($originUrl) { $originWords = "origin $originUrl" }
        Write-CliError -Message "The repository you stand in ($repoTop) has $originWords, not $spaceName's address (https://github.com/$spaceRepo)." `
            -Hint "cd into your clone of https://github.com/$spaceRepo and run '${p}StartWork $wanted -Launch' there."
        exit 2  # stated refusal
    }

    # 2. claude on the PATH -- the optional surface named by consts.json startWork.launchEnvFlag (D-AR13).
    $claude = Resolve-LaunchExecutable -Name 'claude'
    if (-not $claude) {
        $launchFlag = $c.startWork.launchEnvFlag
        Write-CliError -Message 'claude is not on the PATH, so there is no session to start.' `
            -Hint "Install Claude Code and open a new shell ('${p}Env' names it: $launchFlag). The block works without it: '${p}StartWork $wanted', and paste it."
        exit 2  # stated refusal
    }

    # 3. The size: who the rituals say has it, read the rituals' way -- an
    # issue's labels; a card's **Assigned:** line, else a size in its Tags, else
    # (a card whose id is an issue number, which Route sizes on the tracker)
    # that issue's labels.
    $size = ''
    $sizeFrom = ''
    $knownSizes = @($launchModels.Keys) + @($ownerSeat)
    if ($item.Kind -eq 'Issue') {
        foreach ($labelName in @(Get-P20IssueLabelNames $issue)) {
            $hit = @($knownSizes | Where-Object { $_ -ieq [string]$labelName }) | Select-Object -First 1
            if ($hit) { $size = [string]$hit; $sizeFrom = "a label on issue $($item.Ref)"; break }
        }
    }
    else {
        $assigned = Get-P20CardAssigned $content
        if ($assigned) { $size = $assigned; $sizeFrom = 'its **Assigned:** line' }
        if (-not $size) {
            foreach ($tag in @(Get-P20CardTags $content)) {
                $hit = @($knownSizes | Where-Object { $_ -ieq [string]$tag }) | Select-Object -First 1
                if ($hit) { $size = [string]$hit; $sizeFrom = 'its Tags'; break }
            }
        }
        if (-not $size -and (Test-P20IsWorkItemId ([string]$item.Ref)) -and $resolvedSpace.status -eq 'active' -and (Get-Command gh -ErrorAction SilentlyContinue)) {
            $labelRead = Invoke-P20TrackerRead 'gh' @('issue', 'view', [string]$item.Ref, '--repo', $spaceRepo, '--json', 'labels')
            $labelIssue = $null
            if ($labelRead.Code -eq 0) {
                try { $labelIssue = ((@($labelRead.Out) -join "`n") | ConvertFrom-Json) } catch { $labelIssue = $null }
            }
            if ($labelIssue) {
                foreach ($labelName in @(Get-P20IssueLabelNames $labelIssue)) {
                    $hit = @($knownSizes | Where-Object { $_ -ieq [string]$labelName }) | Select-Object -First 1
                    if ($hit) { $size = [string]$hit; $sizeFrom = "a label on issue #$($item.Ref)"; break }
                }
            }
        }
    }
    $what = "$($item.Kind) $($item.Ref)"
    if (-not $size) {
        Write-CliError -Message "$what has no size, so there is no crew to launch (a launch takes $sizeWords)." -Hint $routeHint
        exit 2  # stated refusal
    }
    if ($size -ieq $ownerSeat) {
        Write-CliError -Message "$what is sized $ownerSeat ($sizeFrom): the owner's own seat, never a crew builder." -Hint $selfHint
        exit 2  # stated refusal
    }
    if ($size -ieq $meWord) {
        Write-CliError -Message "$what is assigned to you ($sizeFrom says $meWord), not to a crew size." -Hint $selfHint
        exit 2  # stated refusal
    }
    $model = ''
    foreach ($k in $launchModels.Keys) { if ($k -ieq $size) { $model = [string]$launchModels[$k] } }
    if (-not $model) {
        Write-CliError -Message "$what is sized $size ($sizeFrom), and a launch has a model only for $sizeWords." -Hint $routeHint
        exit 2  # stated refusal
    }

    # 4. Where: a detached worktree under the repository's .claude/worktrees/;
    # the block, the log and the stderr log at the repository root, all three
    # *.log, which is ignored. The block is the session's STDIN -- claude
    # --print reads its prompt there -- because a prompt of many lines does
    # not cross a joined command line whole on any host.
    $refWord = (([string]$item.Ref).TrimStart('#').ToLowerInvariant() -replace '[^a-z0-9]+', '-').Trim('-')
    $runName = "startwork-$refWord-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
    $worktree = Join-Path (Join-Path (Join-Path $repoTop '.claude') 'worktrees') $runName
    $blockPath = Join-Path $repoTop "$runName.block.log"
    $logPath = Join-Path $repoTop "$runName.log"
    $errPath = Join-Path $repoTop "$runName.err.log"
    $claudeArgs = @('--print', '--model', $model, '--output-format', 'stream-json', '--verbose')
    $blockLines = @($block -split "`n").Count
    $shownCommand = "claude $($claudeArgs -join ' ') < `"$blockPath`""

    if ($WhatIf) {
        Write-Output "  [WhatIf] $what is sized $size ($sizeFrom): model $model."
        Write-Output "  [WhatIf] Would run: git -C `"$repoTop`" worktree add --detach `"$worktree`""
        Write-Output "  [WhatIf] Would write the block ($blockLines lines, as '${p}StartWork $wanted' prints it) to $blockPath"
        Write-Output "  [WhatIf] Would start, in that worktree: $shownCommand"
        Write-Output "  [WhatIf] Its output would go to $logPath (stderr: $errPath)."
        Write-Output '  [WhatIf] Nothing was added or started.'
        exit 0
    }

    $add = Invoke-P20TrackerRead 'git' @('-C', $repoTop, 'worktree', 'add', '--detach', $worktree)
    if ($add.Code -ne 0) {
        $why = @($add.Err | ForEach-Object { ([string]$_).Trim() } | Where-Object { $_ }) | Select-Object -First 1
        if (-not $why) { $why = "git exited $($add.Code)" }
        Write-CliError -Message "git worktree add failed in ${repoTop}: $why" `
            -Hint 'Nothing was started. git worktree list shows what is there; a repository with no commit yet has nothing to check out.'
        exit 2  # stated refusal
    }

    # The child's environment is this one's, without a Teams webhook: a session
    # never sends (AGENTS.md, "The webhook variables").
    $childEnv = @{}
    $hookPrefix = [string]$c.env.teamsWebhookPrefix
    foreach ($var in @(Get-ChildItem Env: -ErrorAction SilentlyContinue | Where-Object { $hookPrefix -and $_.Name.StartsWith($hookPrefix) })) { $childEnv[$var.Name] = $null }
    try {
        # UTF-8 with no BOM, LF: the bytes StartWork prints.
        [System.IO.File]::WriteAllText($blockPath, $block, (New-Object System.Text.UTF8Encoding($false)))
        $proc = Start-DetachedProcess -FilePath $claude -ArgumentList $claudeArgs -WorkingDirectory $worktree `
            -StdOutLog $logPath -StdErrLog $errPath -Environment $childEnv -StdInFile $blockPath
    }
    catch {
        Write-CliError -Message "claude did not start: $($_.Exception.Message)" `
            -Hint "The worktree is at $worktree; 'git worktree remove `"$worktree`"' takes it away."
        exit 2  # stated refusal
    }
    Write-Output "Launched $what on ${model}: PID $($proc.Id)."
    Write-Output "  worktree: $worktree"
    Write-Output "  log:      $logPath"
    exit 0
}

if ($Clip) {
    try { Set-Clipboard -Value $block -ErrorAction Stop }
    catch {
        Write-CliError -Message "The clipboard did not take the block ($($_.Exception.Message))." `
            -Hint "Leave -Clip off and pipe it: '${p}StartWork $wanted | pbcopy' (clip on Windows)."
        exit 2  # stated refusal
    }
    $lineCount = @($block -split "`n").Count
    Write-Host "Copied the hand-off block for $($item.Kind) $($item.Ref) to the clipboard ($lineCount lines)." -ForegroundColor Green
    exit 0
}

Write-Output $block
exit 0
