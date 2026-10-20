<#
.SYNOPSIS
    consts.json parses on the 5.1 floor, this half reads it, and no script
    retypes a literal that lives in it.
.DESCRIPTION
    consts.json at the package root holds the literals that cross a HALF
    boundary -- the strings and patterns the CLI, the agent and the web UI must
    agree on to the character. Three suites guard it, one per side: this file,
    Tests/test_consts.py and web/src/shell/consts.test.ts. Together they are the
    parity check: each half states the value it resolved for every key, so a
    value that stops agreeing fails somewhere rather than drifting.

    The EXPECTED table below is deliberately hand-written rather than read from
    the file. A test that reads the same file it is testing asserts only that
    JSON parsing works; the point is that changing the contract makes a person
    say so out loud, in three languages.

    Run:  pwsh -File Tests/Test-Consts.ps1
    Or:   {cliPrefix}TestToolkit -Consts
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$pkgRoot = Split-Path $scriptDir -Parent
$constsPath = Join-Path $pkgRoot 'consts.json'
$readerPath = Join-Path $pkgRoot 'Scripts/Get-Consts.ps1'

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

Write-Host ""
Write-Host "═══════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "  consts.json -- the contract file" -ForegroundColor Cyan
Write-Host "═══════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host ""

# ── The values, as this half must resolve them ────────────────────────────────
# MUST match Tests/test_consts.py's EXPECTED and web/src/shell/consts.test.ts.

$expected = [ordered]@{
    # The package's own repository: the agent's fallback for a Space that is
    # this package itself when a copy has no git origin to read.
    'repository.url'          = 'https://github.com/johnfrog76/toolkit'
    'stamps.closed'           = '**Closed:**'
    'stamps.created'          = '**Created:**'
    'stamps.billable'         = '**Billable:**'
    'stamps.started'          = '**Started:**'
    'stamps.outcome'          = '**Outcome:**'
    'stamps.review'           = '**Review:**'
    'tokens.prUrl'            = 'PR URL:'
    'tokens.prReviewHeading'  = '## PR Review Comments'
    'tokens.previousRound'    = '> Previous round:'
    # The design a card names:
    # NewPrompt -Design writes the first; the corpus wrote the second by hand.
    'tokens.design'           = '> Design:'
    'tokens.spec'             = '> Spec:'
    'regex.prUrlLine'        = '(?m)^PR URL:\s*https://'
    'regex.prReviewHeading'   = '(?m)^##\s+PR Review Comments'
    'regex.commitBullet'      = '(?m)^\s*-\s+`?([0-9a-f]{7,})`?'
    'regex.startedLine'       = '(?m)^\*\*Started:\*\*'
    'regex.reviewLine'        = '(?m)^\*\*Review:\*\*'
    'regex.sessionName'       = '^(?:([a-z0-9]+(?:-[a-z0-9]+)*)-)?(\d{4}-\d{2}-\d{2})\.md$'
    'regex.cardId'            = '(?:\d+|(?=[A-Z0-9]{0,3}[0-9])(?=[A-Z0-9]{0,3}[A-Z])[ACDEFGHJKMNPQRTUVWXY234679]{4})'
    'status.active'           = 'Active'
    'status.inProgress'       = 'In Progress'
    'status.codeReview'       = 'Code Review'
    'status.done'             = 'Done'
    'folders.current'         = 'current'
    'folders.archive'         = 'archive'
    'reviews.fileName'        = 'review.md'
    'reviews.slugSetSeparator' = '+'
    # A list travels as its elements joined with a comma, so the table stays flat.
    'features.spaceScoped'      = 'sprintAwareness,trainingHoursPerQuarter'
    'env.activeSpace'         = 'P20_ACTIVE_SPACE'
    'env.features'            = 'P20_FEATURES'
    'env.agentPort'           = 'P20_AGENT_PORT'
    'env.teamsWebhookPrefix'  = 'TEAMS_WEBHOOK_'
    'env.testRunMarker'       = 'P20_TEST_RUN'
    'agent.bindHost'          = '127.0.0.1'
    'stamps.sent'             = 'Sent to'
    'stamps.due'              = '**Due:**'
    'stamps.source'           = '**Source:**'
    'stamps.ref'              = '**Ref:**'
    # A card's pictures: the two
    # footer lines Cover writes and both readers parse, the Space's folder they
    # point into, and what Cover accepts. A list travels comma-joined.
    'stamps.cover'            = '**Cover:**'
    'stamps.before'           = '**Before:**'
    'folders.assets'          = 'assets'
    'assets.coverExtensions'  = 'png,jpg,jpeg,webp,gif'
    'assets.coverMaxBytes'    = '5242880'
    'regex.dueLine'           = '(?m)^\*\*Due:\*\*[ \t]*(\d{4}-\d{2}-\d{2})(?:T(\d{2}:\d{2}))?'
    'reminders.buckets'       = 'overdue,today,upcoming'
    'reminders.snooze'        = '1h,tomorrow,nextweek'
    # The three halves a test run covers: Test and the CLI runner write
    # them into test-summary.<machine>.json; the agent serves them.
    'tests.halves'            = 'agent,cli,web'
    'tests.legacyHalf'        = 'cli'
    # The Docs tab's two roots: the agent's path rule and the web's link
    # resolver read them; the CLI states them so the contract is three-sided.
    'docs.readme'             = 'README.md'
    'docs.root'               = 'docs'
    'docs.segment'            = '^[A-Za-z0-9_][A-Za-z0-9._-]*$'
    # A shipped Space's old slug -> its new one. A map travels as its
    # old=new pairs joined with a comma, so the table stays flat.
    'spaces.renamed'          = 'test=azure-demo'
    # Whether a GitHub Space's repository is public: the three words the
    # agent serves and Env, SwitchSpace Status and the writing verbs print, and
    # the one line a write to a public repository carries.
    'visibility.public'       = 'public'
    'visibility.private'      = 'private'
    'visibility.unknown'      = 'unknown'
    'visibility.publicLine'   = 'This repository is public'
    # The Studio's design notes (S2b): NewDesign names its files by noteName and
    # Promote writes threadLine; the agent reads both, the web opens noteName.
    'studio.noteName'         = '^[A-Za-z0-9][A-Za-z0-9._-]*\.md$'
    'studio.threadLine'       = '> GitHub:'
    'studio.promoteLabel'     = 'design'
    # The Studio's Prompts card: the agent's read the web asks.
    'studio.promptsRoute'     = '/api/studio/prompts'
    'studio.threadRegex'      = '(?m)^>\s*GitHub:\s*(https://github\.com/([^/\s]+)/([^/\s]+)/issues/(\d+))\s*$'
    # The design lifecycle's identity (L1): the frontmatter key, the id's shape and
    # the state and outcome words. NewDesign and StampDesign write them; lists
    # travel comma-joined.
    'design.idKey'            = 'id'
    'design.idRegex'          = '^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
    'design.states'           = 'Design,Spec,Complete,Archived'
    'design.outcomes'         = 'shipped,dropped'
    'design.docsLine'         = '> Docs:'
    'design.docsRegex'        = '(?m)^>\s*Docs:\s*(\S.*?)\s*$'
    'design.cardLineRegex'    = '(?m)^>[ \t]*(Design|Spec):[ \t]*(?:\[([^\]\r\n]*)\]\(([^)\r\n]*)\))?[ \t]*([^\r\n]*?)[ \t]*\r?$'
    # Solitaire Agile's Ritual Engine: the standup the CLI's Standup and
    # the agent's GET /api/ritual/standup both render, word for word. text is a
    # map and travels as its key=value pairs joined with a comma, so the table
    # stays flat; Tests/fixtures/rituals/ holds the goldens the words make.
    'rituals.route'             = '/api/ritual/standup'
    'rituals.triageRoute'       = '/api/ritual/triage'
    'rituals.ceremoniesFile'    = 'Config/ceremonies.json'
    'rituals.vocabularyFile'    = 'Config/standup-vocabulary.json'
    'rituals.workerLabelPrefix' = 'Routed to'
    'rituals.walkLabel'         = 'verify-close'
    'rituals.labelWidth'        = '9'
    # The reminder to attend: an Organize reminder with this source and
    # title, its cadence written in these day names; the routes are the agent's.
    'rituals.attendRoute'       = '/api/ritual/standup/attend'
    'rituals.remindRoute'       = '/api/ritual/standup/remind'
    'rituals.remindSource'      = 'standup'
    'rituals.remindTitle'       = 'Standup'
    'rituals.remindDays'        = 'Mon-Fri'
    'rituals.weekdays'          = 'Mon,Tue,Wed,Thu,Fri,Sat,Sun'
    # The work grain (D-TA20): the three grains, the counts as the voice
    # says them, and the four patterns the grouping reads.
    'rituals.grains'             = 'detail,work,brief'
    'rituals.numberWords'        = 'zero,one,two,three,four,five,six,seven,eight,nine,ten,eleven,twelve'
    'rituals.workHeadRegex'      = '^(?:[A-Za-z]+:\s+)?(.+?)(?:\s+--\s+|:\s+|$)'
    'rituals.workThreadRegex'    = '(?m)^>\s*GitHub:\s*<?(?:https://github\.com/[^/\s>]+/[^/\s>]+/issues/|#)(\d+)'
    'rituals.workDesignRegex'    = 'design/([A-Za-z0-9][A-Za-z0-9_-]*)\.md'
    'rituals.workSmallWordRegex' = '^[a-z]{1,3}$'
    # The also-ons fold (D-SA9): the most groups a folded sentence names.
    'rituals.proseFoldNames'     = '4'
    # The dress (D-SA11): the guard's checks, in the order they run, and
    # the four patterns it reads a model's sentence with.
    'rituals.dressGuards'        = 'empty,ref-added,ref-dropped,number,count-dropped,kind,name-dropped,name'
    'rituals.dressRefRegex'      = '#\d+|(?<![\w#])(?=[A-Z0-9]{0,3}[0-9])(?=[A-Z0-9]{0,3}[A-Z])[ACDEFGHJKMNPQRTUVWXY234679]{4}(?!\w)'
    'rituals.dressNumberRegex'   = '(?<![\w#])\d+(?!\w)'
    'rituals.dressNameRegex'     = '(?<![\w''-])[A-Z][A-Za-z0-9''-]*'
    'rituals.dressPronounRegex'  = '^I(?:''[a-z]+)?$'
    # What moved: a slot item's motion, and the hash its card's bullet threads.
    'rituals.motions'            = 'closed,started,inProgress'
    # StartWork's hand-off block (D-AR5): the head line and the three section
    # headings the CLI types and the web's copy box finds; Tests/fixtures/start-work/
    # holds the block they make.
    'startWork.text'            = 'head=# Start work: {kind} {id} -- {title},howWeWork=## How we work in {space} ({source}),work=## The work: {kind} {id} ({source}),prompt=## The prompt ({source})'
    'rituals.text'              = 'title=Standup -- {date},dateFormat=dddd d MMMM yyyy,queueHeading=Waiting on you,queueEmpty=Nothing is waiting on you.,walk=Walk,tracker=Tracker,yesterday=Yesterday,today=Today,blockers=Blockers,mug=Mug,yesterdayEmpty=nothing closed,todayEmpty=nothing in flight,blockersEmpty=no blockers,blockerSuffix= (verify-close),noWorkers=No worker labels in this Space.,adoTracker=Azure DevOps is the human team''s board, and its standup is the one the team holds; Team Agile reads a GitHub Space''s issues and cards, or a local Space''s cards.,check=Check,checkCardArchived={item} -- the card is archived, but the issue is still open.,checkIssueClosed={item} -- the issue is closed, but the card is not archived.,briefWalkOne=walk,briefWalkMany=walks,briefDecideOne=decision,briefDecideMany=decisions,briefLookOne=look,briefLookMany=looks,briefAllPc=all on the PC,briefWhoPc=the PC,briefWhoYou=you,briefClosed={n} closed yesterday,briefClosedNone=nothing yesterday,briefOpen={n} open,briefOpenNone=nothing open,briefInFlight=none in flight,briefBlocker={n} blocker,briefBlockers={n} blockers,briefWorkerNone=nothing today,briefInFlightUnknown=In flight is not yet known: every routed issue reads as open.,briefNext=Next: the {kind} -- {n} on {who}.,briefNextNone=Next: nothing is waiting on you.,workYesterday={name}, {n} closed,workToday={name}, {n},workBlockers={name}, {n} to walk,workWalk={name}, {n} to walk,workGroup={name}, {n},proseSentence={lead} {body}.,proseYesterday=Yesterday I closed,proseYesterdayAlso=I also closed,proseToday=Today I''m on,proseTodayAlso=I''m also on,proseBlockers=Blocked on,proseBlockersAlso=Also blocked on,proseBlockersNone=Nothing blocked.,proseWalk=Waiting on you to walk,proseWalkAlso=Also to walk,proseDecide=Waiting on you to decide,proseDecideAlso=Also to decide,proseLook=Waiting on you to look at,proseLookAlso=Also to look at,proseOne={n} in {name}: {item},proseTodayOne={name}: {item},proseMany={n} in {name} ({refs}),proseBare={item},proseItem={ref}, {clause},proseRefSeparator=, ,proseTodayFold={n} more: {names},proseTodayFoldCount={n} more designs,proseNameSeparator=, ,proseNameLast= and ,itemMotion={ref} ({motion}) {title},motionStarted=started,commitOne={n} commit,commitMany={n} commits,countsTotal=Since {date}: {counts}.,countsNone=nothing moved,countsSeparator=, ,countsClosed={n} closed,countsStarted={n} started,countsInProgress={n} in progress'
}

Write-Host "-- It parses, on the 5.1 floor ------------------------" -ForegroundColor Cyan

Assert-True "consts.json is at the package root" (Test-Path $constsPath)
Assert-True "Scripts/Get-Consts.ps1 is beside it" (Test-Path $readerPath)

# ConvertFrom-Json WITHOUT -AsHashtable: Windows PowerShell 5.1 has no such
# switch, and this file must be readable there.
$raw = Get-Content -Path $constsPath -Raw -Encoding UTF8 | ConvertFrom-Json
Assert-True "it parses with plain ConvertFrom-Json" ($null -ne $raw)

. $readerPath
$c = Get-P20Consts
Assert-True "the reader returns the same tree" ($c.stamps.closed -eq $raw.stamps.closed)
Assert-True "a second call is the cached object" ([object]::ReferenceEquals($c, (Get-P20Consts)))

Write-Host ""
Write-Host "-- Every key resolves to the agreed value -------------" -ForegroundColor Cyan

foreach ($entry in $expected.GetEnumerator()) {
    $parts = $entry.Key.Split('.')
    $actual = $c.($parts[0]).($parts[1])
    if ($actual -is [array]) { $actual = ($actual -join ',') }
    elseif ($actual -is [System.Management.Automation.PSCustomObject]) { $actual = (@($actual.PSObject.Properties | ForEach-Object { "$($_.Name)=$($_.Value)" }) -join ',') }
    Assert-Equal $entry.Key $entry.Value $actual
}

# The org-scoped flags: the module's state and the standalone reader's default
# both come from the file, not from a copy.
Assert-True "features.spaceScoped is a list" ($c.features.spaceScoped -is [array])
. (Join-Path $pkgRoot 'Scripts/Resolve-HubConfig.ps1')
$hubDir = Join-Path ([System.IO.Path]::GetTempPath()) ("p20-consts-hub-" + [System.Guid]::NewGuid().Guid.Substring(0, 8))
New-Item -ItemType Directory -Path $hubDir -Force | Out-Null
try {
    Set-Content (Join-Path $hubDir 'hub.json') '{"orgs":[{"slug":"x","promptsFolder":"x","features":{"sprintAwareness":true,"growth":true}}]}'
    $manifest = Read-P20HubManifest -Root $hubDir -WarningAction SilentlyContinue
    $kept = @($manifest.Spaces[0].features.PSObject.Properties.Name)
    Assert-Equal "Read-P20HubManifest keeps exactly the contract's org-scoped flags by default" 'sprintAwareness' ($kept -join ',')
}
catch {
    Assert-True 'the cases ran to the end without a terminating error' $false $_.Exception.Message
}
finally { Remove-Item $hubDir -Recurse -Force -ErrorAction SilentlyContinue }

# A key added to the file without a line above is a key nobody agreed to.
$found = @()
# A top-level key that is a value rather than a group: `version`, and nothing else.
$scalars = @()
foreach ($group in $c.PSObject.Properties) {
    if ($group.Name -eq '_README') { continue }
    if ($group.Value -isnot [System.Management.Automation.PSCustomObject]) {
        $scalars += $group.Name
        continue
    }
    foreach ($key in $group.Value.PSObject.Properties) {
        if ($key.Name -eq '_') { continue }
        $found += "$($group.Name).$($key.Name)"
    }
}
$missing = @($found | Where-Object { -not $expected.Contains($_) })
Assert-True "no key in consts.json is unaccounted for here" ($missing.Count -eq 0) ($missing -join ', ')
Assert-Equal "and none is listed that the file does not have" 0 (@($expected.Keys | Where-Object { $found -notcontains $_ }).Count)
Assert-Equal "the one top-level value is the version" 'version' ($scalars -join ',')

Write-Host ""
Write-Host "-- One version, and the two files that carry a copy ---" -ForegroundColor Cyan

# The product's version is typed once, here. The module manifest and the web
# package must carry their own literal (a data file and a package file cannot
# read another file), so each is held to the contract by name: a partial bump
# fails here, naming the file that was left behind.
# MUST match Tests/test_consts.py's and web/src/shell/consts.test.ts's.
$expectedVersion = '1.1.0'
Assert-Equal 'version' $expectedVersion ([string]$c.version)
Assert-True 'the version is three dotted numbers' ([string]$c.version -match '^\d+\.\d+\.\d+$') "got '$($c.version)'"

$manifestFile = Join-Path $pkgRoot 'Prompt20Toolkit/Prompt20Toolkit.psd1'
$manifestVersion = [string](Import-PowerShellDataFile -Path $manifestFile).ModuleVersion
Assert-True 'Prompt20Toolkit/Prompt20Toolkit.psd1 ModuleVersion is consts.json version' `
    ($manifestVersion -eq [string]$c.version) "Prompt20Toolkit/Prompt20Toolkit.psd1 says '$manifestVersion', consts.json says '$($c.version)'"

$packageFile = Join-Path $pkgRoot 'web/package.json'
$packageVersion = [string]((Get-Content -Path $packageFile -Raw -Encoding UTF8 | ConvertFrom-Json).version)
Assert-True 'web/package.json version is consts.json version' `
    ($packageVersion -eq [string]$c.version) "web/package.json says '$packageVersion', consts.json says '$($c.version)'"

# The manifest's generator writes the version FROM the contract: a literal in it
# would be a fourth copy, and the next regeneration would undo a bump.
$generatorText = Get-Content -Path (Join-Path $pkgRoot 'Prompt20Toolkit/Update-ToolkitManifest.ps1') -Raw -Encoding UTF8
Assert-True 'Update-ToolkitManifest.ps1 types no version of its own' `
    ($generatorText -notmatch "ModuleVersion\s*=\s*'\d") 'the generator carries a version literal; it must write consts.json version'

Write-Host ""
Write-Host "-- The patterns work in .NET too ----------------------" -ForegroundColor Cyan

# They travel as strings and each half compiles its own; these are .NET's.
Assert-True "prUrlLine matches a card with a PR" ("# Card`nPR URL: https://dev.azure.com/x" -match $c.regex.prUrlLine)
Assert-True "prUrlLine does not match a non-URL" (-not ("# Card`nPR URL: not-a-url" -match $c.regex.prUrlLine))
Assert-True "commitBullet matches a real bullet" ("Commits:`n- 80e2168 add grid" -match $c.regex.commitBullet)
Assert-True "commitBullet does not match the placeholder" (-not ("Commits:`n- (pending)" -match $c.regex.commitBullet))
$bulletHashes = @([regex]::Matches("- 80e2168 a`n- ``abcdef1234`` b`n- (pending)", $c.regex.commitBullet) | ForEach-Object { $_.Groups[1].Value })
Assert-Equal "commitBullet captures the hash in group 1" '80e2168,abcdef1234' ($bulletHashes -join ',')
$idWhole = '^(?:' + $c.regex.cardId + ')$'
Assert-True "cardId matches a work item number" ('141' -cmatch $idWhole)
Assert-True "cardId matches the id of a card with no work item" ('K7M2' -cmatch $idWhole)
Assert-True "cardId is case-sensitive: a lowercase slug word is not an id" (-not ('k7m2' -cmatch $idWhole))
Assert-True "cardId needs a digit: TASK is a type prefix, not an id" (-not ('TASK' -cmatch $idWhole))
Assert-True "cardId has no look-alike characters: K7M0 is not an id" (-not ('K7M0' -cmatch $idWhole))

# The generator lives in one half (only the CLI makes an id); the SHAPE is the
# contract. 500 of them, and every one must be an id all three halves agree on.
. (Join-Path (Join-Path $pkgRoot 'Scripts') 'Resolve-CardName.ps1')
$generated = @(1..500 | ForEach-Object { New-P20CardId })
Assert-Equal "New-P20CardId: 500 asked for, 500 made" 500 @($generated | Where-Object { $_ }).Count
Assert-Equal "every generated id matches regex.cardId" 0 @($generated | Where-Object { $_ -cnotmatch $idWhole }).Count
Assert-Equal "none is all digits -- none can be mistaken for a work item number" 0 @($generated | Where-Object { $_ -match '^\d+$' }).Count
Assert-Equal "none is all letters -- none can be mistaken for a type prefix" 0 @($generated | Where-Object { $_ -cmatch '^[A-Z]+$' }).Count
Assert-True "500 draws are not all the same id" (@($generated | Sort-Object -Unique).Count -gt 450)
$idDir = Join-Path ([System.IO.Path]::GetTempPath()) ("p20-ids-" + [System.Guid]::NewGuid().Guid.Substring(0, 8))
New-Item -ItemType Directory -Path $idDir -Force | Out-Null
try {
    Write-FixtureText (Join-Path $idDir 'TaskK7M2-taken.prompt.md') '# x'
    $script:draws = 0
    $forced = New-P20CardId -Folders @($idDir) -WorkItemTypes (Get-P20WorkItemTypes -Config $null) -Generator { $script:draws++; if ($script:draws -lt 3) { 'k7m2'.ToUpper() } else { 'Q4TN' } }
    Assert-Equal "an id already on a card is drawn again, ignoring case" 'Q4TN' $forced
    $never = New-P20CardId -Folders @($idDir) -WorkItemTypes (Get-P20WorkItemTypes -Config $null) -MaxTries 5 -Generator { 'K7M2' }
    Assert-True "and when every draw is taken it gives up with `$null rather than reusing one" ($null -eq $never)
}
catch {
    Assert-True 'the cases ran to the end without a terminating error' $false $_.Exception.Message
}
finally { Remove-Item $idDir -Recurse -Force -ErrorAction SilentlyContinue }
Assert-True "prReviewHeading matches a round heading" ("## PR Review Comments -- Round 2 (PR 35)" -match $c.regex.prReviewHeading)
# The design line a card carries: .NET reads the same four groups the
# agent and the web do, CRLF included.
$dm = [regex]::Match("# T`r`n> Design: [Board ideas](../../design/board-ideas.md) ee925272-9564-4816-8944-e6b39c86339c`r`n", $c.design.cardLineRegex)
Assert-True "cardLineRegex reads a Design line's word, title, link and id in .NET" ($dm.Success -and $dm.Groups[1].Value -ceq 'Design' -and $dm.Groups[2].Value -eq 'Board ideas' -and $dm.Groups[3].Value -eq '../../design/board-ideas.md' -and $dm.Groups[4].Value -eq 'ee925272-9564-4816-8944-e6b39c86339c')
Assert-True "and a hand-written Spec line's words" ([regex]::Match('> Spec: [P.spec.md](../spec/P.spec.md) (D4)', $c.design.cardLineRegex).Groups[4].Value -eq '(D4)')

Write-Host ""
Write-Host "-- The state machine reads the contract ---------------" -ForegroundColor Cyan

# The state rule is its own file, dot-sourced here exactly as Status
# and Move dot-source it, so this asserts the shipped function rather than a copy.
. (Join-Path $pkgRoot 'Scripts/Get-PromptFileStatus.ps1')
Assert-True "Get-PromptFileStatus was found" ([bool](Get-Command Get-PromptFileStatus -ErrorAction SilentlyContinue))
Assert-Equal "a card with a PR URL reads codeReview" $c.status.codeReview (Get-PromptFileStatus -Content "PR URL: https://x")
Assert-Equal "a card with a commit bullet reads inProgress" $c.status.inProgress (Get-PromptFileStatus -Content "Commits:`n- 80e2168 add grid")
Assert-Equal "an empty card reads active" $c.status.active (Get-PromptFileStatus -Content "")
Assert-Equal "a person's Started line reads inProgress" $c.status.inProgress (Get-PromptFileStatus -Content "$($c.stamps.started) 2026-09-22")
Assert-Equal "a person's Review line reads codeReview, over a commit" $c.status.codeReview (Get-PromptFileStatus -Content "- 80e2168 x`n$($c.stamps.review) 2026-09-22")

Write-Host ""
Write-Host "-- A repository's visibility reads the contract -------" -ForegroundColor Cyan

# gh's word as the contract's, and one Space from its repositories' --
# the same table Tests/test_visibility.py holds the agent's copy to.
. (Join-Path $pkgRoot 'Scripts/Get-RepoVisibility.ps1')
foreach ($row in @(
        @('PUBLIC', 'public'), @('public', 'public'), @('PRIVATE', 'private'),
        @('INTERNAL', 'private'), @('', 'unknown'), @('something-new', 'unknown'))) {
    Assert-Equal "gh's '$($row[0])' reads as $($row[1])" $row[1] (ConvertTo-P20Visibility $row[0])
}
Assert-Equal 'a Space is public when any repository is' 'public' (Merge-P20Visibility -Words @('private', 'public'))
Assert-Equal 'and when one is unknown beside a public one' 'public' (Merge-P20Visibility -Words @('public', 'unknown'))
Assert-Equal 'private when all are' 'private' (Merge-P20Visibility -Words @('private', 'private'))
Assert-Equal 'unknown when one did not answer and none is public' 'unknown' (Merge-P20Visibility -Words @('private', 'unknown'))
Assert-Equal 'unknown for a Space that names none' 'unknown' (Merge-P20Visibility)
Assert-Equal 'an Azure DevOps Space has no visibility, and gh is not asked' '' (Get-P20SpaceVisibility -OrgUrl 'https://dev.azure.com/acme' -Projects @())
Assert-Equal 'nor a Space with no tracker' '' (Get-P20SpaceVisibility -OrgUrl '' -Projects @())
Assert-Equal 'a GitHub Space not asked (-NoAsk) is unknown, never a guess' 'unknown' (Get-P20SpaceVisibility -OrgUrl 'https://github.com/acme/widgets' -Projects @() -NoAsk)

Write-Host ""
Write-Host "-- No script retypes a contract literal ---------------" -ForegroundColor Cyan

# Only the DISTINCTIVE literals are grep-able. 'Active', 'current' and 'archive'
# are ordinary English -- org statuses, folder words, prose -- so a text search
# for them would report noise rather than drift. Those keys are held by the
# parity assertions above instead, which is the stronger check: all three halves
# state the value they resolved.
#
# ALLOWLIST, and why each entry is on it:
#   Scripts/Get-Consts.ps1   the reader. It names keys, not values.
#   Tests/                   the tests, which must state the values to check them.
#   templates/               documents a person reads, not parsers (see consts.json).
# Comment lines are skipped everywhere rather than whole files being excused:
# explaining a literal is fine, comparing against one is not.
$guarded = [ordered]@{
    'stamps.closed'          = '**Closed:**'
    'stamps.created'         = '**Created:**'
    'tokens.prUrl'           = 'PR URL:'
    'tokens.prReviewHeading' = '## PR Review Comments'
    'tokens.previousRound'   = '> Previous round:'
    # Read-DesignTree.ps1 builds and reads the line from tokens.design and
    # design.cardLineRegex, and nothing types it.
    'tokens.design'          = '> Design:'
    'regex.commitBullet'     = '[0-9a-f]{7,}'
    'reviews.fileName'       = 'review.md'
    'env.agentPort'          = 'P20_AGENT_PORT'
    'env.activeSpace'        = 'P20_ACTIVE_SPACE'
    'env.features'           = 'P20_FEATURES'
    'stamps.due'             = '**Due:**'
    'stamps.cover'           = '**Cover:**'
    'stamps.before'          = '**Before:**'
    'stamps.outcome'         = '**Outcome:**'
    # The standup's distinctive words: Scripts/Standup-Rules.ps1 reads them
    # from rituals.text and rituals.workerLabelPrefix, and nothing types them.
    'rituals.text.queueHeading'  = 'Waiting on you'
    'rituals.text.todayEmpty'    = 'nothing in flight'
    'rituals.workerLabelPrefix'  = 'Routed to'
    # The work grain's phrases: Standup-Rules.ps1 reads them from rituals.text.
    'rituals.text.workBlockers'  = '{n} to walk'
    # The prose: Standup-Rules.ps1 reads its sentences from rituals.text.
    'rituals.text.proseBlockersNone' = 'Nothing blocked.'
    'rituals.text.proseYesterday'    = 'Yesterday I closed'
    # The line a write to a public repository carries: Get-RepoVisibility.ps1
    # prints it from visibility.publicLine, and nothing types it.
    'visibility.publicLine'      = 'This repository is public'
}
$allowed = @('Scripts/Get-Consts.ps1')

$scripts = @(Get-ChildItem -Path (Join-Path $pkgRoot 'Scripts') -Filter '*.ps1' -File) +
           @(Get-Item (Join-Path $pkgRoot 'utilities.psm1'))

foreach ($g in $guarded.GetEnumerator()) {
    $offenders = @()
    foreach ($file in $scripts) {
        $rel = 'Scripts/' + $file.Name
        if ($file.Name -eq 'utilities.psm1') { $rel = 'utilities.psm1' }
        if ($allowed -contains $rel) { continue }
        $n = 0
        $inBlockComment = $false
        foreach ($line in (Get-Content -Path $file.FullName -Encoding UTF8)) {
            $n++
            $code = $line.Trim()
            # Comment-based help (<# ... #>) is documentation, and a doc block is
            # where a literal SHOULD be spelled out: it is what a reader needs to
            # recognise the line in a card. Only code is guarded.
            if ($code.StartsWith('<#')) { $inBlockComment = $true }
            if ($inBlockComment) {
                if ($code.Contains('#>')) { $inBlockComment = $false }
                continue
            }
            if ($code.StartsWith('#')) { continue }
            if ($line.Contains($g.Value)) { $offenders += "${rel}:$n" }
        }
    }
    Assert-True "$($g.Key) is read, not retyped" ($offenders.Count -eq 0) ($offenders -join ', ')
}

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
