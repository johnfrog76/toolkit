[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [ValidateSet("UserStory", "Task", "Bug", "Feature")]
    [string]$Type = "UserStory",

    [Parameter(Mandatory = $false)]
    [string]$Title,

    [Parameter(Mandatory = $false)]
    [string]$Description,

    [Parameter(Mandatory = $false)]
    [string]$Project,

    [Parameter(Mandatory = $false)]
    [int]$Parent = 0,

    [Parameter(Mandatory = $false)]
    [string]$Sprint,

    [Parameter(Mandatory = $false)]
    [string]$AssignTo,

    [Parameter(Mandatory = $false)]
    [int]$Priority = 0,

    [Parameter(Mandatory = $false)]
    [int]$Points = 0,

    [Parameter(Mandatory = $false)]
    [string]$AcceptanceCriteria,

    [Parameter(Mandatory = $false)]
    [string]$ReproSteps,

    [Parameter(Mandatory = $false)]
    [string]$Tags,

    [Parameter(Mandatory = $false)]
    [string]$FromDesign,

    # Publish a card made with no tracker (docs/CLI.md, "Cards and prompt files"):
    # its id, or its file name, by the one card rule.
    [Parameter(Mandatory = $false)]
    [string]$FromCard,

    [Parameter(Mandatory = $false)]
    [switch]$ReadOnly,

    # The house's dry-run word (Cover, CloseItem, MoveDesign): the same dry run
    # as -ReadOnly, which NewItem has always had.
    [Parameter(Mandatory = $false)]
    [switch]$WhatIf,

    [Parameter(Mandatory = $false)]
    [switch]$Help
)

# Get-CliPrefix normally comes from the module. These scripts are also invoked
# directly -- by tests, by a user running the .ps1, by anything that wants -Help
# without importing first -- so a missing helper must not be fatal.
if (-not (Get-Command Get-CliPrefix -ErrorAction SilentlyContinue)) {
    function Get-CliPrefix {
        if ($global:P20Config -and $global:P20Config.CommandPrefix) { return $global:P20Config.CommandPrefix }
        return ''
    }
}


$typeMap = @{
    "UserStory" = "User Story"
    "Task"      = "Task"
    "Bug"       = "Bug"
    "Feature"   = "Feature"
}

function Show-Help {
    Write-Host ""
    Write-Host "  $(Get-CliPrefix)NewItem -- Create a work item (an issue, on a GitHub space)" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  Usage:" -ForegroundColor White
    Write-Host "    $(Get-CliPrefix)NewItem -Title <string> [-Type <type>] [-Project <name>] [options]" -ForegroundColor Gray
    Write-Host ""
    Write-Host "  Types (default: UserStory):" -ForegroundColor White
    Write-Host "    UserStory  Task  Bug  Feature" -ForegroundColor Gray
    Write-Host ""
    Write-Host "  Parameters:" -ForegroundColor White
    Write-Host "    -Title <string>               Work item title (required)" -ForegroundColor Gray
    Write-Host "    -Type <type>                  Work item type (default: UserStory)" -ForegroundColor Gray
    Write-Host "    -Project <name>               ADO project -- partial match ok; required when org has multiple projects" -ForegroundColor Gray
    Write-Host "    -Description <string>         Description text" -ForegroundColor Gray
    Write-Host "    -Parent <id>                  ADO ID of the parent work item (Feature, Epic, etc.); on a GitHub space," -ForegroundColor Gray
    Write-Host "                                  the parent issue's number: the new issue is added as its sub-issue" -ForegroundColor Gray
    Write-Host "                                  (a '- [ ] #<n>' line in its body, where GitHub refuses the sub-issue)" -ForegroundColor Gray
    Write-Host "    -Sprint <name>                Iteration name e.g. 'Sprint 72' (auto-expands to full iteration path)" -ForegroundColor Gray
    Write-Host "    -AssignTo <email>             Assign to this user (default: your config email)" -ForegroundColor Gray
    Write-Host "    -Priority <1-4>               Priority (1=Critical, 2=High, 3=Medium, 4=Low)" -ForegroundColor Gray
    Write-Host "    -Points <int>                 Story points (UserStory, Task)" -ForegroundColor Gray
    Write-Host "    -AcceptanceCriteria <string>  Acceptance criteria text (UserStory)" -ForegroundColor Gray
    Write-Host "    -ReproSteps <string>          Steps to reproduce (Bug)" -ForegroundColor Gray
    Write-Host "    -Tags <string>                Semicolon-separated tags (e.g. 'ux; accessibility')" -ForegroundColor Gray
    Write-Host "    -FromDesign <note>            Promote a hub design note (the Studio): an issue labelled design," -ForegroundColor Gray
    Write-Host "                                  its body the note, its URL written back as the note's > GitHub: line" -ForegroundColor Gray
    Write-Host "    -FromCard <id>                Publish a card made with no tracker: an issue from its title and Summary," -ForegroundColor Gray
    Write-Host "                                  its body ending 'Toolkit card: <id>', its URL written into the card's ADO Link" -ForegroundColor Gray
    Write-Host "    -ReadOnly                     Dry run -- print what would be created, no ADO call (on GitHub: the reads run," -ForegroundColor Gray
    Write-Host "                                  every write is printed, none is made)" -ForegroundColor Gray
    Write-Host "    -WhatIf                       The same dry run as -ReadOnly" -ForegroundColor Gray
    Write-Host "    -Help                         Show this help" -ForegroundColor Gray
    Write-Host ""
    Write-Host "  Examples:" -ForegroundColor White
    Write-Host '    $(Get-CliPrefix)NewItem -Title "Add dark mode toggle" -Sprint "Sprint 72"' -ForegroundColor DarkGray
    Write-Host '    $(Get-CliPrefix)NewItem -Type Bug -Title "Login fails on Edge" -Priority 1 -ReproSteps "1. Go to /login 2. Click Sign in"' -ForegroundColor DarkGray
    Write-Host '    $(Get-CliPrefix)NewItem -Type Task -Title "Update API docs" -Parent 195551 -Points 2 -Project "Search Coach"' -ForegroundColor DarkGray
    Write-Host '    $(Get-CliPrefix)NewItem -Type Feature -Title "Offline mode" -Description "Allow app to function offline" -Tags "offline; pwa"' -ForegroundColor DarkGray
    Write-Host '    $(Get-CliPrefix)NewItem -Title "Spike: auth approach" -ReadOnly' -ForegroundColor DarkGray
    Write-Host "    $(Get-CliPrefix)NewItem -Title `"Split: the read half`" -Parent 140 -WhatIf   # on a GitHub space: a sub-issue of the parent" -ForegroundColor DarkGray
    Write-Host "    $(Get-CliPrefix)NewItem -FromCard K7M2 -WhatIf" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  After creation, scaffold a local prompt file with:" -ForegroundColor DarkGray
    Write-Host "    $(Get-CliPrefix)NewPrompt <id>" -ForegroundColor DarkGray
    Write-Host ""
}

# Write-CliError normally comes from the module; it is what makes a refusal ONE
# block. See AGENTS.md, "The refusal contract".
if (-not (Get-Command Write-CliError -ErrorAction SilentlyContinue)) {
    function Write-CliError {
        param([string]$Message, [string]$Hint)
        $global:P20StatedError = $Message
        Write-Host "Error: $Message" -ForegroundColor Red
        if ($Hint) { Write-Host "Hint:  $Hint" -ForegroundColor Yellow }
    }
}

if ($Help) { Show-Help; return }
if ($WhatIf) { $ReadOnly = [switch]$true }

# -- Promote: a hub design note becomes its thread (Studio S2b) ----------------
# NewItem -FromDesign <note>: the same verb the Backlog uses, one click from the
# Studio's reading room (docs/modules/studio.md, "The verbs"). The issue's
# title is the note's, its body the note's text, and it is labelled design
# (consts.json studio.promoteLabel); once GitHub has made it, its URL is written
# back into the note as the > GitHub: line (studio.threadLine), through
# Write-CardText -- an EDIT, so the note keeps its own line endings. The
# Studio's verb is NewDesign; this switch is its door into the tracker. The
# Studio is core (D-S13), so there is no flag to ask.
$designPath = ''
$designFolderName = ''
if ($PSBoundParameters.ContainsKey('FromDesign')) {
    . (Join-Path $PSScriptRoot 'Resolve-HubConfig.ps1')
    . (Join-Path $PSScriptRoot 'Write-CardText.ps1')
    $studio = (Get-P20Consts).studio
    foreach ($taken in @('Title', 'Description', 'AcceptanceCriteria', 'ReproSteps')) {
        if ($PSBoundParameters.ContainsKey($taken)) {
            Write-CliError -Message "-FromDesign takes the issue's title and body from the note, so -$taken has nothing to do." `
                -Hint 'Edit the note, then promote it.'
            exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
        }
    }
    if ($FromDesign -notmatch $studio.noteName) {
        Write-CliError -Message "'$FromDesign' is not a design note's name." -Hint 'A note is one .md file in the hub''s design/, e.g. -FromDesign board-ideas.md.'
        exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
    }
    $packageRoot = Split-Path -Parent $PSScriptRoot
    $promptsRoot = Get-P20PromptsRoot -PackageRoot $packageRoot
    $designDir = Get-P20HubFolder -Name 'design' -PromptsRoot $promptsRoot -PackageRoot $packageRoot
    $designFolderName = [System.IO.Path]::GetFileName($designDir)
    $designPath = Join-Path $designDir $FromDesign
    if (-not (Test-Path -LiteralPath $designPath)) {
        Write-CliError -Message "No note $designFolderName/$FromDesign in the hub." -Hint "Write one with $(Get-CliPrefix)NewDesign -Title <text>."
        exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
    }
    $noteText = ([System.IO.File]::ReadAllText($designPath)) -replace "`r`n", "`n"
    if ($noteText -match $studio.threadRegex) {
        Write-CliError -Message "$designFolderName/$FromDesign already has its thread: $($Matches[1])" -Hint 'Comment there; a note is promoted once.'
        exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
    }
    # The frontmatter is the note's own index card, not the issue's body: the
    # description and the Space it is for are read off it and left behind.
    $noteLines = @($noteText -split "`n")
    $bodyStart = 0
    $noteSpace = ''
    if ($noteLines.Count -gt 0 -and $noteLines[0].Trim() -eq '---') {
        for ($i = 1; $i -lt $noteLines.Count; $i++) {
            if ($noteLines[$i].Trim() -eq '---') { $bodyStart = $i + 1; break }
            if ($noteLines[$i] -match '^space:\s*(.*)$') { $noteSpace = $Matches[1].Trim().Trim('"').Trim("'") }
        }
    }
    $titleIndex = -1
    for ($i = $bodyStart; $i -lt $noteLines.Count; $i++) {
        if ($noteLines[$i] -match '^# (.+)$') { $titleIndex = $i; $Title = $Matches[1].Trim(); break }
    }
    if ($titleIndex -lt 0) {
        Write-CliError -Message "$designFolderName/$FromDesign has no '# ' title line to name the issue with." -Hint 'Give the note a title, then promote it.'
        exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
    }
    $activeSpace = ''
    if ($global:P20Config -and $global:P20Config.ActiveSpace) { $activeSpace = [string]$global:P20Config.ActiveSpace }
    if ($noteSpace -and $activeSpace -and $noteSpace -ne $activeSpace) {
        Write-CliError -Message "$designFolderName/$FromDesign is for the Space '$noteSpace', and you are in '$activeSpace'." `
            -Hint "$(Get-CliPrefix)SwitchSpace $noteSpace, then promote it -- its thread belongs in that product's tracker."
        exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
    }
    $kept = @(for ($i = $bodyStart; $i -lt $noteLines.Count; $i++) { if ($i -ne $titleIndex) { $noteLines[$i] } })
    $Description = ($kept -join "`n").Trim()
    $labelList = @($studio.promoteLabel)
    if (-not [string]::IsNullOrWhiteSpace($Tags)) { $labelList += $Tags }
    $Tags = $labelList -join ';'
}

# -- Publish: a card made with no tracker becomes its issue (toolkit card C3) ----
# NewItem -FromCard <id> (docs/CLI.md, "Cards and prompt files"). The issue's
# title is the card's name (its heading after "<Type> <id>: "), its body the
# card's Summary, ended by one line naming the card -- "Toolkit card: K7M2" --
# so the issue says which record it came from. Once GitHub has made it, its URL
# is written into the card's **ADO Link:** line through Set-P20CardLine (an EDIT
# through Write-CardText: the card keeps its line endings, nothing else moves).
# That line is what makes a card `linked` and gives it its gh badge, by the rule
# that already exists (docs/hub/cards.md); the card keeps its id.
# Refused, each in one sentence: an id that is not a card, a card already
# linked, and a Space whose tracker is not GitHub (publishing to Azure DevOps is
# roadmap phase 6).
$cardPath = ''
$cardName = ''
$cardId = ''
$cardLinkStamp = '**ADO Link:**'   # the footer line both halves read a card's link from
$cardBodyLine = 'Toolkit card:'    # written into GitHub; nothing in the package reads it back
if ($PSBoundParameters.ContainsKey('FromCard')) {
    . (Join-Path $PSScriptRoot 'Resolve-HubConfig.ps1')
    . (Join-Path $PSScriptRoot 'Resolve-CardName.ps1')
    . (Join-Path $PSScriptRoot 'Set-CardLine.ps1')
    foreach ($taken in @('Title', 'Description', 'AcceptanceCriteria', 'ReproSteps', 'FromDesign')) {
        if ($PSBoundParameters.ContainsKey($taken)) {
            Write-CliError -Message "-FromCard takes the issue's title and body from the card, so -$taken has nothing to do." `
                -Hint 'Edit the card''s heading or its Summary, then publish it.'
            exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
        }
    }
    $cfgCard = $global:P20Config
    if (-not (Test-P20HubRoot $cfgCard.PromptsRoot)) {
        Write-CliError -Message (Get-P20HubMissingMessage $cfgCard.PromptsRoot)
        exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
    }
    $cardTypes = Get-P20WorkItemTypes -Config $cfgCard
    $cardFolders = Get-PromptFolders
    $found = @()
    $isId = $false
    foreach ($folder in @($cardFolders.Current, $cardFolders.Archive)) {
        $resolved = Resolve-P20CardArgument -Argument $FromCard -Folder $folder -WorkItemTypes $cardTypes
        $isId = $resolved.IsId
        $found = @($resolved.Match | Where-Object { $_.Name -like '*.md' })
        if ($found.Count -gt 0) { break }
    }
    if ($found.Count -eq 0) {
        $said = "No card matching '$FromCard' in current/ or archive/."
        if ($isId) { $said = "No card with id '$FromCard' in current/ or archive/." }
        Write-CliError -Message $said -Hint "Run '$(Get-CliPrefix)Status' to see the cards; -FromCard takes a card's id or its file name."
        exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
    }
    if ($found.Count -gt 1) {
        Write-CliError -Message "'$FromCard' matches $($found.Count) cards: $((@($found | ForEach-Object { $_.Name })) -join ', ')." `
            -Hint 'Pass the full file name of the one you mean.'
        exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
    }
    $cardPath = $found[0].FullName
    $cardName = $found[0].Name
    $cardId = Get-P20CardId -Name $cardName -Pattern (Get-P20CardIdPattern -WorkItemTypes $cardTypes)
    if (-not $cardId) {
        Write-CliError -Message "$cardName is not a card: its name carries no id." `
            -Hint 'A card is named [<type prefix>]<id>-<slug>.prompt.md (docs/hub/cards.md).'
        exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
    }
    $cardText = ([System.IO.File]::ReadAllText($cardPath)) -replace "`r`n", "`n"
    $linkMatch = [regex]::Match($cardText, '(?m)^' + [regex]::Escape($cardLinkStamp) + '\s*(https://\S+)')
    if ($linkMatch.Success) {
        Write-CliError -Message "Card $cardId is already linked: $($linkMatch.Groups[1].Value)" `
            -Hint 'A card is published once; its issue is where the conversation goes now.'
        exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
    }
    # The heading: "# <Type> <id>: <name>". The issue is titled by the name; the
    # type folds to the kind label the way -Type does, unless -Type was said.
    $cardLines = @($cardText -split "`n")
    $heading = ''
    foreach ($l in $cardLines) { if ($l -match '^#\s+(.+)$') { $heading = $Matches[1].Trim(); break } }
    # A large story's heading opens with an emoji (NewPrompt's broccoli); the
    # agent's reader drops a leading one too.
    $heading = ($heading -replace '^[^\x00-\x7F]+\s*', '')
    $cardTitle = $heading
    $cardType = ''
    foreach ($tn in @($cardTypes.Keys | Sort-Object -Property Length -Descending)) {
        $hm = [regex]::Match($heading, '^(?i:' + [regex]::Escape([string]$tn) + ')\s+\S+\s*:\s*(.+)$')
        if ($hm.Success) { $cardType = [string]$tn; $cardTitle = $hm.Groups[1].Value.Trim(); break }
    }
    if ([string]::IsNullOrWhiteSpace($cardTitle)) {
        Write-CliError -Message "$cardName has no '# ' heading to title the issue with." -Hint 'Give the card its heading, then publish it.'
        exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
    }
    if (-not $PSBoundParameters.ContainsKey('Type')) {
        # A Bug and a Feature fold to their labels; everything else is a plain issue.
        $Type = 'Task'
        if ($cardType -eq 'Bug') { $Type = 'Bug' }
        if ($cardType -eq 'Feature') { $Type = 'Feature' }
    }
    # The Summary: the text under "## Summary" up to the next heading or the
    # footer rule, its template comments dropped. A summary still "(TBD)" says
    # nothing, and the body is then the one line that names the card.
    $summary = @()
    $inSummary = $false
    foreach ($l in $cardLines) {
        if ($l -match '^##\s+Summary\s*$') { $inSummary = $true; continue }
        if ($inSummary -and ($l -match '^#{1,2}\s' -or $l.Trim() -eq '---')) { break }
        if ($inSummary) { $summary += $l }
    }
    $summaryText = (($summary -join "`n") -replace '(?s)<!--.*?-->', '').Trim()
    if ($summaryText -eq '(TBD)') { $summaryText = '' }
    $Title = $cardTitle
    $Description = "$cardBodyLine $cardId"
    if ($summaryText) { $Description = "$summaryText`n`n$cardBodyLine $cardId" }
}

# -- Validate required fields --------------------------------------------------
if ([string]::IsNullOrWhiteSpace($Title)) {
    Write-CliError -Message "-Title is required." -Hint "Use '$(Get-CliPrefix)NewItem -Help' for usage."
    exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
}

if ($Priority -ne 0 -and ($Priority -lt 1 -or $Priority -gt 4)) {
    Write-CliError -Message "-Priority must be between 1 and 4 (1=Critical, 4=Low)."
    exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
}

if ($Points -lt 0) {
    Write-CliError -Message "-Points must be a positive number."
    exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
}

# -- Config --------------------------------------------------------------------
$cfg = $global:P20Config
$org = $cfg.Org
$allProjects = @($cfg.Projects)

# -- The tracker seam (D-G4): the same verb, the space's own tool --------------
# On a GitHub space this creates an ISSUE: title, body, labels, milestone.
# The mapping is stated, not silent -- Type folds to the kind label the
# Backlog folds back ({cliPrefix} chips), Tags become labels (sev1..3 land
# here), Sprint is the milestone, AC and repro steps join the body as
# sections. What has no GitHub shape is refused by name, not dropped.
. (Join-Path $PSScriptRoot 'Resolve-Tracker.ps1')
if ($cardPath -and (Resolve-P20Tracker -OrgUrl $org) -ne 'github') {
    if ((Resolve-P20Tracker -OrgUrl $org) -eq 'none') {
        Write-CliError -Message "This Space has no tracker to publish card $cardId on." `
            -Hint "Connect a Space to GitHub ($(Get-CliPrefix)Connect <slug>), switch to it, then $(Get-CliPrefix)NewItem -FromCard $cardId."
    }
    else {
        Write-CliError -Message "-FromCard files the card as a GitHub issue, and this Space's tracker is not GitHub." `
            -Hint 'Publishing a card to Azure DevOps is not built.'
    }
    exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
}
if ($designPath -and (Resolve-P20Tracker -OrgUrl $org) -ne 'github') {
    # D-S9: a design's thread is a GitHub issue; an Azure DevOps Space is a
    # client's tenant, and a Spike's thinking stays on our side.
    Write-CliError -Message "-FromDesign opens the note's thread on GitHub, and this Space's tracker is not GitHub." `
        -Hint "$(Get-CliPrefix)SwitchSpace <a GitHub Space>, then promote it."
    exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
}
if ((Resolve-P20Tracker -OrgUrl $org) -eq 'github') {
    # -Parent has a GitHub shape -- a sub-issue, below -- so it is not in this list.
    $adoOnly = @()
    if ($Priority -gt 0) { $adoOnly += '-Priority' }
    if ($Points -gt 0)   { $adoOnly += '-Points' }
    if ($adoOnly.Count -gt 0) {
        Write-CliError -Message "$($adoOnly -join ', ') has no GitHub shape -- an issue has no priority or points." `
            -Hint 'Severity is a label: -Tags sev1 (or sev2, sev3). Drop the switch and create again.'
        exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
    }

    $repoAnswer = Resolve-P20TrackerRepo -OrgUrl $org -Projects $cfg.Projects -CliPrefix (Get-CliPrefix)
    if (-not [string]::IsNullOrWhiteSpace($Project)) {
        $candidates = @(Get-P20TrackerRepos -OrgUrl $org -Projects $cfg.Projects | Where-Object { $_ -like "*$Project*" })
        if ($candidates.Count -eq 1) { $repoAnswer = @{ Repo = $candidates[0] } }
        elseif ($candidates.Count -gt 1) {
            Write-CliError -Message "'$Project' matches more than one repository: $($candidates -join ', ')." -Hint 'Be more specific with -Project.'
            exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
        }
        elseif ($candidates.Count -eq 0 -and -not $repoAnswer.Repo) {
            Write-CliError -Message "No repository matching '$Project' on this space." -Hint $repoAnswer.Hint
            exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
        }
    }
    if (-not $repoAnswer.Repo) {
        Write-CliError -Message "$($repoAnswer.Reason) Nothing was created." -Hint $repoAnswer.Hint
        exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
    }
    $repoFull = $repoAnswer.Repo

    $kindLabel = switch ($Type) { 'Bug' { 'bug' } 'Feature' { 'enhancement' } default { '' } }
    # Only the ADO-flavored word earns the aside: the bridge always binds
    # -Type, so warning on 'Task' would print it on every plain issue.
    if ($Type -eq 'UserStory' -and $PSBoundParameters.ContainsKey('Type')) {
        Write-Host "[~] GitHub has no work item types -- 'UserStory' lands as a plain issue. Bug and Feature fold to labels." -ForegroundColor Yellow
    }
    $labels = @()
    if ($kindLabel) { $labels += $kindLabel }
    if (-not [string]::IsNullOrWhiteSpace($Tags)) { $labels += ($Tags -split ';' | ForEach-Object { $_.Trim() } | Where-Object { $_ }) }

    $bodyText = ''
    if (-not [string]::IsNullOrWhiteSpace($Description))        { $bodyText = $Description }
    if (-not [string]::IsNullOrWhiteSpace($AcceptanceCriteria)) { $bodyText = ($bodyText, "## Acceptance Criteria`n`n$AcceptanceCriteria" | Where-Object { $_ }) -join "`n`n" }
    if (-not [string]::IsNullOrWhiteSpace($ReproSteps))         { $bodyText = ($bodyText, "## Repro Steps`n`n$ReproSteps" | Where-Object { $_ }) -join "`n`n" }

    # Identity is the tracker's own: gh knows @me, and the ADO default (an
    # email from Resolve-P20Identity) is not a GitHub login. Unnamed = @me.
    $ghAssignee = if ([string]::IsNullOrWhiteSpace($AssignTo)) { '@me' } else { $AssignTo }

    # Through the one native-call helper: under Windows PowerShell 5.1 a
    # redirected stderr line can throw before the exit code is read.
    . (Join-Path $PSScriptRoot 'Invoke-TrackerRead.ps1')

    # -- The parent (Team Agile's Split) -------------------------------------
    # -Parent <n> on GitHub: the new issue becomes a SUB-ISSUE of #n -- GitHub's
    # own parent link, the REST route POST repos/<repo>/issues/<n>/sub_issues,
    # which takes the new issue's id (not its number), so the id is read first.
    # Where GitHub refuses that route on the repository, the fallback is the
    # older shape every GitHub renders: a "- [ ] #<new>" task-list line appended
    # to the parent's body. The output says which happened. The parent is READ
    # before anything is created, in the dry run too (Route's rule: the reads
    # run, so every refusal still happens) -- a wrong number must not leave an
    # orphan issue behind. Every argument travels as its own argv element; no
    # query string, so no `&` reaches gh.
    $parentUrl = ''
    $parentTitle = ''
    if ($Parent -gt 0) {
        $pv = Invoke-P20TrackerRead 'gh' @('issue', 'view', [string]$Parent, '--repo', $repoFull, '--json', 'number,title,url')
        if ($pv.Code -ne 0) {
            $why = @($pv.Lines | Where-Object { "$_".Trim() }) | Select-Object -First 1
            Write-CliError -Message "No issue #$Parent on $repoFull to be the parent: $why Nothing was created." `
                -Hint "-Parent takes the parent issue's number on $repoFull. Check it on github.com, or gh auth status."
            exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
        }
        try {
            $pj = (@($pv.Out) -join "`n") | ConvertFrom-Json
            if ($pj.url)   { $parentUrl = [string]$pj.url }
            if ($pj.title) { $parentTitle = [string]$pj.title }
        }
        catch { $parentUrl = '' }
        if (-not $parentUrl) { $parentUrl = "https://github.com/$repoFull/issues/$Parent" }
    }

    # On stage: a new issue in a public repository is read by strangers,
    # and GitHub keeps its first wording. One line before it, and in -ReadOnly.
    . (Join-Path $PSScriptRoot 'Get-RepoVisibility.ps1')
    Write-P20PublicLine -Repo $repoFull

    if ($ReadOnly) {
        Write-Host ""
        Write-Host "  [DRY RUN] Would create issue in ${repoFull}:" -ForegroundColor Yellow
        Write-Host "    Title:     $Title" -ForegroundColor Gray
        if ($bodyText)                                        { Write-Host "    Body:      $($bodyText -split "`n" | Select-Object -First 1) ..." -ForegroundColor Gray }
        if ($labels.Count -gt 0)                              { Write-Host "    Labels:    $($labels -join ', ')" -ForegroundColor Gray }
        if (-not [string]::IsNullOrWhiteSpace($Sprint))       { Write-Host "    Milestone: $Sprint" -ForegroundColor Gray }
        Write-Host "    Assignee:  $ghAssignee" -ForegroundColor Gray
        if ($Parent -gt 0) {
            # The exact calls, in order: <new> is the number GitHub gives the issue.
            Write-Host "    Parent:    #$Parent $parentTitle" -ForegroundColor Gray
            Write-Host "    Then:      gh api repos/$repoFull/issues/<new>   (the new issue's id)" -ForegroundColor Gray
            Write-Host "               gh api --method POST repos/$repoFull/issues/$Parent/sub_issues -F sub_issue_id=<id>" -ForegroundColor Gray
            Write-Host "    If GitHub refuses the sub-issue: gh issue edit $Parent --repo $repoFull --body <its body, then '- [ ] #<new>'>" -ForegroundColor Gray
        }
        if ($designPath) { Write-Host "    Then:      its URL written into $designFolderName/$FromDesign as the thread line" -ForegroundColor Gray }
        if ($cardPath) {
            # The whole body, not its first line: the line that names the card is its last.
            Write-Host "    Body, in full:" -ForegroundColor Gray
            foreach ($bl in ($bodyText -split "`n")) { Write-Host "      $bl" -ForegroundColor Gray }
            Write-Host "    Then:      its URL written into $cardName as its $cardLinkStamp line -- the card is linked, and keeps its id $cardId" -ForegroundColor Gray
        }
        Write-Host ""
        $dryWord = '-ReadOnly'
        if ($WhatIf) { $dryWord = '-WhatIf' }
        Write-Host "  Remove $dryWord to create on GitHub. Nothing was created or written." -ForegroundColor DarkGray
        Write-Host ""
        return
    }

    Write-Host "[*] Creating issue in $repoFull..." -ForegroundColor Cyan
    $ghArgs = @('issue', 'create', '--repo', $repoFull, '--title', $Title, '--body', $bodyText, '--assignee', $ghAssignee)
    foreach ($l in $labels) { $ghArgs += @('--label', $l) }
    if (-not [string]::IsNullOrWhiteSpace($Sprint)) { $ghArgs += @('--milestone', $Sprint) }
    $ghCall = Invoke-P20TrackerRead 'gh' $ghArgs
    $created = @($ghCall.Lines)
    if ($ghCall.Code -ne 0) {
        Write-CliError -Message "Failed to create the issue: $(@($created) -join ' ')" `
            -Hint "A label or milestone must already exist on $repoFull. Check gh auth status."
        exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
    }
    $issueUrl = @($created | Where-Object { "$_" -match '^https://' }) | Select-Object -First 1
    $newNumber = if ("$issueUrl" -match '/issues/(\d+)') { $Matches[1] } else { '' }
    Write-Host "[+] Created: issue #$newNumber -- $Title" -ForegroundColor Green
    Write-Host "    $issueUrl" -ForegroundColor Cyan
    if ($designPath -and $issueUrl) {
        # The thread line goes under the title, a blank line either side: the
        # place every design note and issue file in the corpus carries it.
        $current = ([System.IO.File]::ReadAllText($designPath)) -replace "`r`n", "`n"
        $lines = [System.Collections.Generic.List[string]]::new()
        foreach ($l in ($current -split "`n")) { $lines.Add($l) }
        $at = -1
        $inFront = ($lines.Count -gt 0 -and $lines[0].Trim() -eq '---')
        for ($i = 0; $i -lt $lines.Count; $i++) {
            if ($inFront) { if ($i -gt 0 -and $lines[$i].Trim() -eq '---') { $inFront = $false }; continue }
            if ($lines[$i] -match '^# ') { $at = $i; break }
        }
        $insert = @('', "$($studio.threadLine) $issueUrl")
        if ($at + 1 -lt $lines.Count -and $lines[$at + 1].Trim() -ne '') { $insert += '' }
        $lines.InsertRange($at + 1, [string[]]$insert)
        Write-CardText -Path $designPath -Content ($lines -join "`n")
        Write-Host "    Wrote the thread into $designFolderName/$FromDesign" -ForegroundColor Green
    }
    if ($cardPath -and $issueUrl) {
        [void](Set-P20CardLine -Path $cardPath -Stamp $cardLinkStamp -Value $issueUrl)
        Write-Host "    Wrote the issue into $cardName as its $cardLinkStamp line -- card $cardId is linked, and keeps its id." -ForegroundColor Green
    }
    elseif ($cardPath) {
        Write-Host "[!] GitHub answered without an issue URL, so $cardName was not written. Paste the URL into its $cardLinkStamp line." -ForegroundColor Yellow
    }
    if ($Parent -gt 0) {
        # The link, after the create: a sub-issue, else a task-list line in the
        # parent's body. The issue already exists, so a link that fails both
        # ways is a stated refusal that says so -- never a second create.
        $linked = ''
        $subWhy = ''
        $subId = ''
        if ($newNumber) {
            $idCall = Invoke-P20TrackerRead 'gh' @('api', "repos/$repoFull/issues/$newNumber")
            if ($idCall.Code -eq 0) {
                try { $subId = [string]((@($idCall.Out) -join "`n") | ConvertFrom-Json).id } catch { $subId = '' }
            }
            if ($subId -notmatch '^\d+$') {
                $subId = ''
                $subWhy = "GitHub did not give issue #$newNumber's id"
            }
        }
        else { $subWhy = 'GitHub answered without the new issue''s number' }
        if ($subId) {
            $subCall = Invoke-P20TrackerRead 'gh' @('api', '--method', 'POST', "repos/$repoFull/issues/$Parent/sub_issues", '-F', "sub_issue_id=$subId")
            if ($subCall.Code -eq 0) { $linked = 'sub-issue' }
            else { $subWhy = @($subCall.Lines | Where-Object { "$_".Trim() }) | Select-Object -First 1 }
        }
        if (-not $linked -and $newNumber) {
            # The fallback: the parent's body as it is NOW, with one task-list line
            # appended. A body that cannot be read is not rewritten -- an edit
            # from a guess would wipe the parent's text.
            $taskLine = "- [ ] #$newNumber"
            $bodyCall = Invoke-P20TrackerRead 'gh' @('issue', 'view', [string]$Parent, '--repo', $repoFull, '--json', 'body')
            $parentBody = $null
            if ($bodyCall.Code -eq 0) {
                try {
                    $bj = (@($bodyCall.Out) -join "`n") | ConvertFrom-Json
                    if (@($bj.PSObject.Properties.Name) -contains 'body') { $parentBody = "$($bj.body)" -replace "`r`n", "`n" }
                }
                catch { $parentBody = $null }
            }
            if ($null -ne $parentBody) {
                $kept = $parentBody.TrimEnd()
                $newBody = $taskLine
                if ($kept) { $newBody = "$kept`n`n$taskLine" }
                $editCall = Invoke-P20TrackerRead 'gh' @('issue', 'edit', [string]$Parent, '--repo', $repoFull, '--body', $newBody)
                if ($editCall.Code -eq 0) { $linked = 'task-list' }
                else { $subWhy = "$subWhy; and the body edit failed: $(@($editCall.Lines | Where-Object { "$_".Trim() }) | Select-Object -First 1)" }
            }
            else { $subWhy = "$subWhy; and #$Parent's body could not be read to add the task-list line" }
        }
        if ($linked -eq 'sub-issue') {
            Write-Host "[+] Linked: #$newNumber is a sub-issue of #$Parent -- $parentUrl" -ForegroundColor Green
        }
        elseif ($linked -eq 'task-list') {
            Write-Host "[~] GitHub refused the sub-issue link ($subWhy), so the parent link is a task-list line instead." -ForegroundColor Yellow
            Write-Host "[+] Linked: '- [ ] #$newNumber' added to #$Parent's body -- $parentUrl" -ForegroundColor Green
        }
        else {
            Write-CliError -Message "Created issue #$newNumber ($issueUrl), but it is not linked to #${Parent}: $subWhy" `
                -Hint "Do not create it again. On github.com, open #$Parent and add #$newNumber as a sub-issue."
            exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
        }
    }
    Write-Host ""
    if ($newNumber -and -not $cardPath) { Write-Host "    Next: $(Get-CliPrefix)NewPrompt $newNumber -- if this work has the weight for a card." -ForegroundColor DarkGray }
    Write-Host ""
    if (Get-Command Write-ToolkitLog -ErrorAction SilentlyContinue) {
        Write-ToolkitLog -Type CMD -Source "$(Get-CliPrefix)NewItem" -Detail "issue #$newNumber ($repoFull) -- $Title"
    }
    return
}

# -- Project resolution --------------------------------------------------------
$selectedProject = ""

if (-not [string]::IsNullOrWhiteSpace($Project)) {
    # Dedupe by name: config may list the same ADO project once per repo
    $matched = @($allProjects | Where-Object { $_.name -like "*$Project*" } | Sort-Object -Property name -Unique)
    if ($matched.Count -eq 0) {
        Write-CliError -Message "No project matching '$Project' in the active Space." -Hint "Available: $((@($allProjects | ForEach-Object { $_.name } | Sort-Object -Unique)) -join ', ')"
        exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
    }
    if ($matched.Count -gt 1) {
        Write-CliError -Message "'$Project' matches more than one project: $((@($matched | ForEach-Object { $_.name })) -join ', ')." -Hint "Be more specific with -Project."
        exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
    }
    $selectedProject = $matched[0].name
} elseif ($allProjects.Count -eq 1) {
    $selectedProject = $allProjects[0].name
    Write-Host "[*] Using project: $selectedProject" -ForegroundColor DarkGray
} else {
    Write-CliError -Message "The active Space has more than one project; which one is not said." -Hint "Pass -Project: $((@($allProjects | ForEach-Object { $_.name } | Sort-Object -Unique)) -join ', ')"
    exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
}

# -- Resolve type and defaults -------------------------------------------------
$adoType = $typeMap[$Type]

if ([string]::IsNullOrWhiteSpace($AssignTo)) {
    $AssignTo = Resolve-P20Identity
}

# Expand short sprint name to full iteration path ("Sprint 72" -> "ProjectName\Sprint 72")
$iterationPath = ""
if (-not [string]::IsNullOrWhiteSpace($Sprint)) {
    if ($Sprint -match '\\') {
        $iterationPath = $Sprint
    } else {
        $iterationPath = "$selectedProject\$Sprint"
    }
}

# Soft warnings for type-specific fields used on the wrong type
if ($Type -ne "UserStory" -and -not [string]::IsNullOrWhiteSpace($AcceptanceCriteria)) {
    Write-Host "[~] -AcceptanceCriteria is a User Story field -- setting anyway, but it may not surface on $adoType boards." -ForegroundColor Yellow
}
if ($Type -ne "Bug" -and -not [string]::IsNullOrWhiteSpace($ReproSteps)) {
    Write-Host "[~] -ReproSteps is a Bug field -- setting anyway, but it may not surface on $adoType boards." -ForegroundColor Yellow
}

# -- Dry run -------------------------------------------------------------------
if ($ReadOnly) {
    Write-Host ""
    Write-Host "  [DRY RUN] Would create:" -ForegroundColor Yellow
    Write-Host "    Type:    $adoType" -ForegroundColor Gray
    Write-Host "    Project: $selectedProject" -ForegroundColor Gray
    Write-Host "    Title:   $Title" -ForegroundColor Gray
    if (-not [string]::IsNullOrWhiteSpace($Description))        { Write-Host "    Desc:    $Description" -ForegroundColor Gray }
    if ($Parent -gt 0)                                           { Write-Host "    Parent:  $Parent" -ForegroundColor Gray }
    if (-not [string]::IsNullOrWhiteSpace($iterationPath))      { Write-Host "    Sprint:  $iterationPath" -ForegroundColor Gray }
    if (-not [string]::IsNullOrWhiteSpace($AssignTo))           { Write-Host "    Assign:  $AssignTo" -ForegroundColor Gray }
    if ($Priority -gt 0)                                         { Write-Host "    Priority:$Priority" -ForegroundColor Gray }
    if ($Points -gt 0)                                           { Write-Host "    Points:  $Points" -ForegroundColor Gray }
    if (-not [string]::IsNullOrWhiteSpace($AcceptanceCriteria)) { Write-Host "    AC:      $AcceptanceCriteria" -ForegroundColor Gray }
    if (-not [string]::IsNullOrWhiteSpace($ReproSteps))         { Write-Host "    Repro:   $ReproSteps" -ForegroundColor Gray }
    if (-not [string]::IsNullOrWhiteSpace($Tags))                { Write-Host "    Tags:    $Tags" -ForegroundColor Gray }
    Write-Host ""
    Write-Host "  Remove -ReadOnly to create in ADO." -ForegroundColor DarkGray
    Write-Host ""
    return
}

# -- Auth token ----------------------------------------------------------------
$tenantArg = if ($cfg.Tenant) { @('--tenant', $cfg.Tenant) } else { @() }
$tokenOutput = az account get-access-token @tenantArg --resource "499b84ac-1321-427f-aa17-267ca6975798" --query accessToken -o tsv 2>&1
$adoToken = ($tokenOutput | Where-Object { $_ -notmatch '^WARNING:' }) -join ''

if ([string]::IsNullOrWhiteSpace($adoToken)) {
    # A stated refusal, not a bare return: exit 0 here reported success to the
    # bridge and to any script checking $LASTEXITCODE.
    Write-CliError -Message "Failed to get ADO access token. Run 'az login' first." -Hint "az said: $tokenOutput"
    exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
}


$headers = @{
    Authorization  = "Bearer $adoToken"
    "Content-Type" = "application/json-patch+json"
}

# -- Build patch body ----------------------------------------------------------
$patches = @()
$patches += @{ op = "add"; path = "/fields/System.Title";       value = $Title }
$patches += @{ op = "add"; path = "/fields/System.AssignedTo";  value = $AssignTo }

if (-not [string]::IsNullOrWhiteSpace($Description)) {
    $patches += @{ op = "add"; path = "/fields/System.Description"; value = $Description }
}
if (-not [string]::IsNullOrWhiteSpace($iterationPath)) {
    $patches += @{ op = "add"; path = "/fields/System.IterationPath"; value = $iterationPath }
}
if ($Priority -gt 0) {
    $patches += @{ op = "add"; path = "/fields/Microsoft.VSTS.Common.Priority"; value = $Priority }
}
if ($Points -gt 0) {
    $patches += @{ op = "add"; path = "/fields/Microsoft.VSTS.Scheduling.StoryPoints"; value = $Points }
}
if (-not [string]::IsNullOrWhiteSpace($AcceptanceCriteria)) {
    $patches += @{ op = "add"; path = "/fields/Microsoft.VSTS.Common.AcceptanceCriteria"; value = $AcceptanceCriteria }
}
if (-not [string]::IsNullOrWhiteSpace($ReproSteps)) {
    $patches += @{ op = "add"; path = "/fields/Microsoft.VSTS.TCM.ReproSteps"; value = $ReproSteps }
}
if (-not [string]::IsNullOrWhiteSpace($Tags)) {
    $patches += @{ op = "add"; path = "/fields/System.Tags"; value = $Tags }
}
if ($Parent -gt 0) {
    $patches += @{
        op    = "add"
        path  = "/relations/-"
        value = @{
            rel = "System.LinkTypes.Hierarchy-Reverse"
            url = "$org/_apis/wit/workitems/$Parent"
        }
    }
}

$bodyParts = @($patches | ForEach-Object { $_ | ConvertTo-Json -Depth 4 -Compress })
$body = "[" + ($bodyParts -join ",") + "]"

# -- Create work item ----------------------------------------------------------
Write-Host "[*] Creating $adoType in '$selectedProject'..." -ForegroundColor Cyan

$projEncoded = [Uri]::EscapeDataString($selectedProject)
$createUri   = $org + '/' + $projEncoded + '/_apis/wit/workitems/$' + [Uri]::EscapeDataString($adoType) + '?api-version=7.1'

try {
    $result  = Invoke-RestMethod -Uri $createUri -Headers $headers -Method Post -Body $body
    $newId   = $result.id
    $newUrl  = "$org/$projEncoded/_workitems/edit/$newId"
    Write-Host "[+] Created: $adoType #$newId -- $($result.fields.'System.Title')" -ForegroundColor Green
    Write-Host "    $newUrl" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "    Next: $(Get-CliPrefix)NewPrompt $newId" -ForegroundColor DarkGray
    Write-Host ""
    if (Get-Command Write-ToolkitLog -ErrorAction SilentlyContinue) {
        Write-ToolkitLog -Type CMD -Source "$(Get-CliPrefix)NewItem" -Detail "$adoType #$newId -- $Title"
    }
}
catch {
    # A failure that exited 0 used to tell the bridge the item was created.
    # Write-CliError + exit 2 lets the wrapper log ERR with this sentence.
    $errMsg = $_.Exception.Message
    $detail = if ($_.ErrorDetails) { "ADO said: $($_.ErrorDetails.Message)" } else { "Nothing was created. Check $(Get-CliPrefix)Log -Errors." }
    Write-CliError -Message "Failed to create work item: $errMsg" -Hint $detail
    exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
}
