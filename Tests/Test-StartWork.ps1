<#
.SYNOPSIS
    Team Agile's hand-off block -- StartWork typed in a fresh shell, the block
    byte for byte, and every refusal.

.DESCRIPTION
    Tests/fixtures/start-work/ is the block's executable form:

        space.json          a GitHub Space whose howIWork answer is agents
        Task23A3-...md      a card with commit bullets, a PR URL: line and
                            footer stamps -- all of which must travel
        issue.json          gh issue view --json for an issue no card carries
        expected-card.md    the block StartWork 23A3 prints, up to and
                            including the prompt's heading
        expected-issue.md   the same for StartWork 41

    The prompt section is the SHIPPED agentic/build.prompt.md, which the
    shipped startWork.prompts rows name: each expected block is its golden,
    LF, then that file's own text -- so the golden and the prompt cannot drift.

    1. Off      with features.solitaireAgile unset there is no StartWork and
                nothing for the bridge to call; on, both.
    2. The card the block, byte for byte; the same card in CRLF gives the
                same block; the id in any case; an id is never a substring;
                nothing written to the hub.
    3. Section one  the Space's agentic/how-we-work.md (HowWeWork's), when it
                has one, replaces the derived sentence and the heading names
                its path; a note at the folder's root is read when that one
                is not there, and loses to it when both are.
    4. The issue    a number no card carries reads the Space's issue (gh
                stubbed): the block byte for byte, one read.
    5. The prompt   -Prompt overrides the row; a kind with no row and a row
                whose file is missing are refusals naming the key.
    6. Refusals     each exit 2, one Error block, nothing written: no id, an id
                that matches nothing, an archived card, a closed issue, a pull
                request, an Azure DevOps Space, an undeclared -Space, a partial
                name for a non-interactive caller.
    7. -Launch      from a scratch clone whose origin is the Space's address,
                with a stub claude first on PATH: -WhatIf prints the worktree
                add, the exact claude command and the log, and leaves nothing;
                the model from each place a size is read (the **Assigned:**
                line, the Tags, an issue's label, the issue behind a numbered
                card); never a launch on the owner's seat -- fable on a card and on an issue
                refused, and no size refused, as are me, a size with no model,
                -Clip with -Launch, -WhatIf alone, no git repository, another
                repository's origin, a failed worktree add and no claude. Off Windows the launch itself: read
                through a pipe it returns while the stub session lives on, the
                worktree is under .claude/worktrees/, the log at the root, and
                the log's first message is the block StartWork prints, whole.
                Windows walks the launch from VERIFY.md, Gate 12.

    Run:  pwsh -File Tests/Test-StartWork.ps1
#>
param([switch]$Help)

if ($Help) { Get-Help $MyInvocation.MyCommand.Path -Detailed; return }

$ErrorActionPreference = 'Stop'
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$pkgRoot = Split-Path -Parent $scriptDir

$script:passed = 0
$script:failed = 0
$script:errors = @()

function Assert-True {
    param([string]$Name, [bool]$Condition, [string]$Detail = '')
    if ($Condition) {
        $script:passed++
        Write-Host "  PASS  $Name" -ForegroundColor Green
    }
    else {
        $script:failed++
        $msg = "  FAIL  $Name"
        if ($Detail) { $msg += " -- $Detail" }
        Write-Host $msg -ForegroundColor Red
        $script:errors += $msg
    }
}

Write-Host ""
Write-Host "  StartWork -- the hand-off block" -ForegroundColor Cyan
Write-Host "  -----------------------------------------------------" -ForegroundColor DarkGray
Write-Host ""

$fixtureDir = Join-Path $scriptDir 'fixtures/start-work'
$cardName = 'Task23A3-route-the-remaining-raw-git-calls.prompt.md'
$utf8 = New-Object System.Text.UTF8Encoding($false)
function Read-Fixture {
    # A fixture's text, LF: .gitattributes checks them out LF, and a checkout
    # that predates the line must not fail the comparison on its endings.
    param([string]$Name)
    return [System.IO.File]::ReadAllText((Join-Path $fixtureDir $Name)).Replace("`r`n", "`n")
}
# The prompt is the shipped file itself, read the way the verb reads it.
$promptText = [System.IO.File]::ReadAllText((Join-Path $pkgRoot 'agentic/build.prompt.md')).Replace("`r`n", "`n").TrimEnd([char]10)
$wantCard = (Read-Fixture 'expected-card.md').TrimEnd([char]10) + "`n" + $promptText
$wantIssue = (Read-Fixture 'expected-issue.md').TrimEnd([char]10) + "`n" + $promptText
$spaceFixture = (Read-Fixture 'space.json') | ConvertFrom-Json

$scratch = Join-Path ([System.IO.Path]::GetTempPath()) ("p20-startwork-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
$pkg = Join-Path $scratch 'pkg'
$hub = Join-Path $scratch 'hub'
$logDir = Join-Path $scratch 'log'
$ghLog = Join-Path $scratch 'gh-calls.log'
$current = Join-Path $hub 'widgets/current'
$archive = Join-Path $hub 'widgets/archive'

function Invoke-Verb {
    # A fresh shell per call: gh replaced by a function that logs every call and
    # answers issue view from the scratch files, then the package's own manifest
    # and nothing else (AGENTS.md, "One toolkit per shell"). -Quiet sets
    # TOOLKIT_QUIET_STARTUP, the mark of a non-interactive caller (the bridge).
    # -Prompts is this machine's startWork.prompts patch; '{}' leaves the shipped rows.
    # -PathPrefix puts a folder (the stub claude's) first on PATH; -PathOnly
    # replaces PATH outright (the no-claude case: git's folder and nothing else).
    param([string]$Snippet, [bool]$On = $true, [string]$Prompts = '{}', [switch]$Quiet, [string]$PathPrefix = '', [string]$PathOnly = '')
    $features = '{}'
    if ($On) { $features = '{ "solitaireAgile": true }' }
    [System.IO.File]::WriteAllText((Join-Path $pkg 'config.local.json'),
        "{ `"promptsRoot`": `"$($hub -replace '\\', '/')`", `"activeSpace`": `"widgets`", `"quietStart`": true, `"features`": $features, `"startWork`": { `"prompts`": $Prompts } }", $utf8)
    if (Test-Path -LiteralPath $ghLog) { Remove-Item -LiteralPath $ghLog -Force }
    $q = { param($p) $p -replace "'", "''" }
    $quietLine = ''
    if ($Quiet) { $quietLine = "`$env:TOOLKIT_QUIET_STARTUP = '1'`n" }
    if ($PathOnly) { $quietLine += "`$env:PATH = '$(& $q $PathOnly)'`n" }
    elseif ($PathPrefix) { $quietLine += "`$env:PATH = '$(& $q $PathPrefix)' + [System.IO.Path]::PathSeparator + `$env:PATH`n" }
    $body = @"
`$env:PSModulePath = '$(& $q $pkg)'
`$env:PROMPTS_ROOT = ''
`$env:P20_USAGE_LOG_DIR = '$(& $q $logDir)'
Get-ChildItem Env: | Where-Object { `$_.Name -like 'TEAMS_WEBHOOK_*' } | ForEach-Object { Remove-Item "Env:\`$(`$_.Name)" -ErrorAction SilentlyContinue }
function global:gh {
    [System.IO.File]::AppendAllText('$(& $q $ghLog)', ((@(`$args | ForEach-Object { [string]`$_ })) -join [char]0x1F) + "``n")
    `$global:LASTEXITCODE = 0
    if (`$args[0] -eq 'issue' -and `$args[1] -eq 'view') {
        `$file = Join-Path '$(& $q $scratch)' ('issue-' + `$args[2] + '.json')
        if (Test-Path -LiteralPath `$file) { return (Get-Content -Raw -LiteralPath `$file) }
        `$global:LASTEXITCODE = 1
        Write-Error ('GraphQL: Could not resolve to an issue or pull request with the number of ' + `$args[2] + '.')
        return
    }
    return ''
}
Import-Module '$(& $q $pkg)/Prompt20Toolkit/Prompt20Toolkit.psd1' -Force 3>`$null 6>`$null
$quietLine'<<<'
$Snippet
'>>>'
'EXIT=' + `$LASTEXITCODE
"@
    $runner = Join-Path $scratch ("run-" + [guid]::NewGuid().ToString('N').Substring(0, 8) + '.ps1')
    [System.IO.File]::WriteAllText($runner, $body, $utf8)
    # Read through a PIPE, as an agent's tool call reads it: a launched child that
    # held this pipe would hold this line until it exited (Seconds says so).
    $clock = [System.Diagnostics.Stopwatch]::StartNew()
    $out = (& pwsh -NoProfile -NonInteractive -File $runner 2>&1 | ForEach-Object { "$_" }) -join "`n"
    $clock.Stop()
    $inner = ''
    $m = [regex]::Match($out, '(?s)<<<\n(.*?)\n?>>>')
    if ($m.Success) { $inner = $m.Groups[1].Value }
    $code = ''
    $mc = [regex]::Match($out, 'EXIT=(\d*)')
    if ($mc.Success) { $code = $mc.Groups[1].Value }
    $calls = @()
    if (Test-Path -LiteralPath $ghLog) {
        $calls = @([System.IO.File]::ReadAllText($ghLog) -split "`n" | Where-Object { $_ })
    }
    # The module's own startup probe is not the verb's: keep the verb's reads.
    $sep = [string][char]0x1F
    $calls = @($calls | Where-Object { -not ($_.StartsWith('auth') -or $_.StartsWith("api${sep}user")) })
    return [pscustomobject]@{ All = $out; Inner = $inner; Exit = $code; Calls = $calls; Seconds = $clock.Elapsed.TotalSeconds }
}

function Test-OneRefusal {
    # A stated refusal: exit 2, ONE Error block, no generic 'exit code' block,
    # nothing on stdout that looks like a block.
    param($Run)
    return ($Run.Exit -eq '2' -and (@([regex]::Matches($Run.All, '(?m)^Error: ')).Count -eq 1) -and $Run.All -notmatch 'exit code' -and $Run.All -notmatch '(?m)^# Start work:')
}

function Get-HubSnapshot {
    return ((@(Get-ChildItem -LiteralPath $hub -Recurse -Force -File | ForEach-Object { $_.FullName + '|' + $_.Length + '|' + $_.LastWriteTimeUtc.Ticks })) -join "`n")
}

try {
    New-Item -ItemType Directory -Path $pkg, $logDir, $current, $archive, (Join-Path $hub 'board/current') -Force | Out-Null
    foreach ($item in @('utilities.psm1', 'config.default.json', 'consts.json')) { Copy-Item (Join-Path $pkgRoot $item) $pkg -Force }
    # agentic/ too: the shipped rows name agentic/build.prompt.md, and the block carries it.
    foreach ($folder in @('Scripts', 'Config', 'Prompt20Toolkit', 'templates', 'agentic')) { Copy-Item (Join-Path $pkgRoot $folder) $pkg -Recurse -Force }
    $spaceJson = ConvertTo-Json -InputObject ([ordered]@{
            slug = [string]$spaceFixture.slug; name = [string]$spaceFixture.name; status = [string]$spaceFixture.status
            promptsFolder = [string]$spaceFixture.promptsFolder; org = [string]$spaceFixture.org; howIWork = [string]$spaceFixture.howIWork
        }) -Compress
    [System.IO.File]::WriteAllText((Join-Path $hub 'hub.json'), @"
{
  "hub": 1,
  "spaces": [
    $spaceJson,
    { "slug": "board", "name": "Board", "status": "active", "promptsFolder": "board", "org": "https://dev.azure.com/acme-org" }
  ]
}
"@, $utf8)
    $cardLf = Read-Fixture $cardName
    [System.IO.File]::WriteAllText((Join-Path $current $cardName), $cardLf, $utf8)
    # A card whose id holds the other one as a substring, and an archived card.
    [System.IO.File]::WriteAllText((Join-Path $current 'Task139-write-the-docs.prompt.md'), "# Task 139: Write the docs`n", $utf8)
    [System.IO.File]::WriteAllText((Join-Path $current 'Meeting-K7M2-the-planning-meeting.prompt.md'), "# Meeting K7M2: The planning meeting`n", $utf8)
    [System.IO.File]::WriteAllText((Join-Path $archive 'Task4D9K-an-old-card.prompt.md'), "# Task 4D9K: An old card`n", $utf8)
    # A planned card: StartWork does not start it -- that is a person's decision.
    $backlogDir = Join-Path $hub 'widgets/backlog'
    New-Item -ItemType Directory -Path $backlogDir -Force | Out-Null
    [System.IO.File]::WriteAllText((Join-Path $backlogDir 'Task9QHT-a-planned-card.prompt.md'), "# Task 9QHT: A planned card`n", $utf8)
    [System.IO.File]::WriteAllText((Join-Path $scratch 'issue-41.json'), (Read-Fixture 'issue.json'), $utf8)
    [System.IO.File]::WriteAllText((Join-Path $scratch 'issue-43.json'), '{ "number": 43, "title": "Done already", "state": "CLOSED", "labels": [], "milestone": null, "body": "", "url": "https://github.com/acme/widgets/issues/43" }', $utf8)
    [System.IO.File]::WriteAllText((Join-Path $scratch 'issue-57.json'), '{ "number": 57, "title": "Route the git calls", "state": "OPEN", "labels": [], "milestone": null, "body": "", "url": "https://github.com/acme/widgets/pull/57" }', $utf8)

    # -- 1. Off means absent -----------------------------------------------------
    Write-Host "-- Off: no verb ----------------------------------------" -ForegroundColor Cyan
    $off = Invoke-Verb "'VERB=' + [bool](Get-Command tkStartWork -ErrorAction SilentlyContinue); 'MAP=' + (Get-P20CommandMap)" -On $false
    Assert-True 'with the flag off StartWork does not exist' ($off.Inner -match 'VERB=False') $off.All
    Assert-True 'and the bridge has nothing to call' ($off.Inner -notmatch '"StartWork"') $off.Inner
    $on = Invoke-Verb "'MAP=' + (Get-P20CommandMap); tkMenu -All"
    Assert-True 'with the flag on the bridge can call it' ($on.Inner -match '"StartWork"\s*:\s*"Get-P20StartWork"') $on.Inner
    Assert-True 'and Menu -All lists it' ($on.Inner -match '(?m)^\s+tkStartWork\s') $on.Inner

    # -- 2. The card, byte for byte ---------------------------------------------
    Write-Host ""
    Write-Host "-- The card, byte for byte -----------------------------" -ForegroundColor Cyan
    $before = Get-HubSnapshot
    $r = Invoke-Verb 'tkStartWork 23A3'
    Assert-True 'StartWork 23A3 exits 0 and prints expected-card.md, byte for byte' ($r.Exit -eq '0' -and $r.Inner -ceq $wantCard) ("`n--- got ---`n$($r.Inner)`n--- want ---`n$wantCard")
    Assert-True 'nothing before the block and nothing after it' ($r.Inner.StartsWith('# Start work: Task 23A3') -and $r.Inner.EndsWith($promptText))
    Assert-True 'the shipped rows carry agentic/build.prompt.md, whole' ($r.Inner.Contains("## The prompt (agentic/build.prompt.md)`n---`n") -and $r.Inner -notmatch '## The prompt \(agentic/pr-ship')
    Assert-True 'the card''s commit bullets, PR URL: and footer travel whole' ($r.Inner.Contains('- 80e2168 Route') -and $r.Inner.Contains('PR URL: https://github.com/acme/widgets/pull/57') -and $r.Inner.Contains('**Sprint:** Phase 6: the long milestone title that is longer than twenty characters'))
    Assert-True 'gh is not asked for a card' ($r.Calls.Count -eq 0) ($r.Calls -join ' / ')
    Assert-True 'and the hub is untouched' ((Get-HubSnapshot) -ceq $before)

    $lower = Invoke-Verb 'tkStartWork 23a3'
    Assert-True 'an id in any case is the same card' ($lower.Exit -eq '0' -and $lower.Inner -ceq $wantCard) $lower.All
    $named = Invoke-Verb "tkStartWork '$cardName'"
    Assert-True 'the full filename is the same card' ($named.Exit -eq '0' -and $named.Inner -ceq $wantCard) $named.All

    [System.IO.File]::WriteAllText((Join-Path $current $cardName), $cardLf.Replace("`n", "`r`n"), $utf8)
    $crlf = Invoke-Verb 'tkStartWork 23A3'
    Assert-True 'the same card in CRLF gives the same block' ($crlf.Exit -eq '0' -and $crlf.Inner -ceq $wantCard) ("`n--- got ---`n$($crlf.Inner)")
    [System.IO.File]::WriteAllText((Join-Path $current $cardName), $cardLf, $utf8)

    $sub = Invoke-Verb 'tkStartWork 39'
    Assert-True 'an id is not a substring: 39 never assembles Task139' ($sub.Exit -eq '2' -and $sub.All -notmatch 'Task 139' -and $sub.All -match "issue #39 could not be read") $sub.All

    # -- 3. Section one: the Space's note --------------------------------------
    Write-Host ""
    Write-Host "-- Section one: how we work ----------------------------" -ForegroundColor Cyan
    # The note HowWeWork writes: <space folder>/agentic/how-we-work.md (consts.json startWork.howWeWorkNote).
    New-Item -ItemType Directory -Path (Join-Path $hub 'widgets/agentic') -Force | Out-Null
    $note = Join-Path $hub 'widgets/agentic/how-we-work.md'
    [System.IO.File]::WriteAllText($note, "We work in small pull requests.`r`nOne card, one branch.`r`n", $utf8)
    $n = Invoke-Verb 'tkStartWork 23A3'
    Assert-True 'a how-we-work.md: the heading names its path' ($n.Inner -match '(?m)^## How we work in Widgets \(widgets/agentic/how-we-work\.md\)$') $n.Inner
    Assert-True 'and its text stands in for the derived sentence, LF' ($n.Inner.Contains("(widgets/agentic/how-we-work.md)`nWe work in small pull requests.`nOne card, one branch.`n`n## The work:") -and $n.Inner -notmatch 'You work with agents here') $n.Inner
    # A note at the Space's folder root -- where this verb looked before HowWeWork wrote one -- is still read
    # when the written one is not there, and the written one wins when both are.
    $rootNote = Join-Path $hub 'widgets/how-we-work.md'
    [System.IO.File]::WriteAllText($rootNote, "An older note at the root.`n", $utf8)
    $both = Invoke-Verb 'tkStartWork 23A3'
    Assert-True 'both there: the agentic/ note is the one quoted' ($both.Inner -match '(?m)^## How we work in Widgets \(widgets/agentic/how-we-work\.md\)$' -and $both.Inner -notmatch 'An older note') $both.Inner
    Remove-Item -LiteralPath $note -Force
    $old = Invoke-Verb 'tkStartWork 23A3'
    Assert-True 'the root note alone is still read, its path named' ($old.Inner -match '(?m)^## How we work in Widgets \(widgets/how-we-work\.md\)$' -and $old.Inner.Contains("(widgets/how-we-work.md)`nAn older note at the root.`n`n## The work:")) $old.Inner
    Remove-Item -LiteralPath $rootNote -Force

    # -- 4. The issue -------------------------------------------------------------
    Write-Host ""
    Write-Host "-- An issue no card carries ----------------------------" -ForegroundColor Cyan
    $i = Invoke-Verb 'tkStartWork 41'
    Assert-True 'StartWork 41 prints expected-issue.md, byte for byte' ($i.Exit -eq '0' -and $i.Inner -ceq $wantIssue) ("`n--- got ---`n$($i.Inner)`n--- want ---`n$wantIssue")
    $sep = [string][char]0x1F
    Assert-True 'one gh read: issue view on the Space''s repo' ($i.Calls.Count -eq 1 -and $i.Calls[0].StartsWith("issue${sep}view${sep}41${sep}--repo${sep}acme/widgets${sep}--json")) ($i.Calls -join ' / ')
    $hash = Invoke-Verb "tkStartWork '#41'"
    Assert-True 'a number with its # is the same issue' ($hash.Exit -eq '0' -and $hash.Inner -ceq $wantIssue) $hash.All

    # -- 5. The prompt --------------------------------------------------------------
    Write-Host ""
    Write-Host "-- The prompt ------------------------------------------" -ForegroundColor Cyan
    $alt = Join-Path $scratch 'other.prompt.md'
    [System.IO.File]::WriteAllText($alt, "# Other`r`n", $utf8)
    $o = Invoke-Verb "tkStartWork 23A3 -Prompt '$($alt -replace "'", "''")'"
    Assert-True '-Prompt carries another prompt for this call, LF' ($o.Exit -eq '0' -and $o.Inner.EndsWith("other.prompt.md)`n# Other")) $o.Inner
    # From a folder with no agentic/ of its own, so the path is read against the package.
    $o = Invoke-Verb "Set-Location '$($scratch -replace "'", "''")'; tkStartWork 23A3 -Prompt agentic/build.prompt.md"
    Assert-True '-Prompt relative to the package' ($o.Exit -eq '0' -and $o.Inner -ceq $wantCard) $o.All

    $refusals = [ordered]@{
        'a kind with no row names the key'      = @{ Snippet = 'tkStartWork K7M2'; Says = 'No prompt is configured for a Meeting (startWork.prompts.Meeting)'; Hint = 'Config -Set startWork.prompts.Meeting=' }
        'a row whose file is missing names it'  = @{ Snippet = 'tkStartWork 23A3'; Prompts = '{ "Task": "agentic/gone.prompt.md" }'; Says = "startWork.prompts.Task names 'agentic/gone.prompt.md', which is not there" }
        'a -Prompt that is not a file'          = @{ Snippet = 'tkStartWork 23A3 -Prompt nowhere.md'; Says = "-Prompt names 'nowhere.md', which is not a file" }
        # -- 6. The rest of the refusals --------------------------------------
        'no id'                                 = @{ Snippet = 'tkStartWork'; Says = 'StartWork needs a card id or an issue number' }
        'an id that matches nothing'            = @{ Snippet = 'tkStartWork 404'; Says = "No card with id '404' in current/, and issue #404 could not be read from acme/widgets" }
        'a card id that matches nothing'        = @{ Snippet = 'tkStartWork X9X9'; Says = "No card with id 'X9X9' in current/" }
        'a name that matches nothing'           = @{ Snippet = 'tkStartWork nothing-like-it'; Says = "No card matching 'nothing-like-it' in current/" }
        'an archived card is Done'              = @{ Snippet = 'tkStartWork 4D9K'; Says = 'Card 4D9K is archived: widgets/archive/Task4D9K-an-old-card.prompt.md is Done' }
        'a planned card is not started for you' = @{ Snippet = 'tkStartWork 9qht'; Says = 'Card 9QHT is in the backlog: widgets/backlog/Task9QHT-a-planned-card.prompt.md is planned, not in play'; Hint = 'tkMove 9QHT -To Active' }
        'a closed issue'                        = @{ Snippet = 'tkStartWork 43'; Says = 'Issue #43 on acme/widgets is closed' }
        'a pull request is not an issue'        = @{ Snippet = 'tkStartWork 57'; Says = '#57 on acme/widgets is a pull request, not an issue' }
        'an Azure DevOps Space'                 = @{ Snippet = 'tkStartWork 23A3 -Space board'; Says = 'Board is an Azure DevOps Space' }
        'an undeclared -Space'                  = @{ Snippet = 'tkStartWork 23A3 -Space nowhere'; Says = "No Space 'nowhere' is declared" }
    }
    $before = Get-HubSnapshot
    foreach ($k in $refusals.Keys) {
        $case = $refusals[$k]
        if ($case.Prompts) { $run = Invoke-Verb $case.Snippet -Prompts $case.Prompts } else { $run = Invoke-Verb $case.Snippet }
        $ok = (Test-OneRefusal $run) -and $run.All.Contains([string]$case.Says)
        if ($case.Hint) { $ok = $ok -and $run.All.Contains([string]$case.Hint) }
        Assert-True "refused, nothing written: $k" $ok $run.All
    }
    Assert-True 'the hub is untouched through every refusal' ((Get-HubSnapshot) -ceq $before)

    $partial = Invoke-Verb 'tkStartWork remaining-raw'
    Assert-True 'a partial name in a terminal names the card, then prints the block' ($partial.Exit -eq '0' -and $partial.Inner -match "Matched 'remaining-raw' -> $([regex]::Escape($cardName))" -and $partial.Inner.EndsWith($wantCard)) $partial.All
    $partialQuiet = Invoke-Verb 'try { tkStartWork remaining-raw } catch { $_.Exception.Message }' -Quiet
    Assert-True 'a partial name for a non-interactive caller is refused, naming the card' ($partialQuiet.All -match "'remaining-raw' is not a card in current/; it matches '$([regex]::Escape($cardName))' only by partial name" -and $partialQuiet.Inner -notmatch '(?m)^# Start work:') $partialQuiet.All

    $usage = Invoke-Verb 'tkStartWork -Help'
    Assert-True 'StartWork -Help renders the usage' ($usage.Inner -match [regex]::Escape('StartWork <id> [-Clip] [-Prompt <path>] [-Space <slug>] [-Launch] [-WhatIf]')) $usage.Inner

    # -- 7. -Launch: the same block, handed to a session (D-AR12) ---------------
    Write-Host ""
    Write-Host "-- -Launch: a session in a worktree --------------------" -ForegroundColor Cyan
    $onWindows = ($PSVersionTable.PSEdition -eq 'Desktop') -or $IsWindows
    function Invoke-Git {
        # A scratch repository's git, its stderr swallowed whatever the host
        # (5.1 under Stop turns a redirected native stderr into a throw).
        param([string[]]$GitArgs)
        $ErrorActionPreference = 'Continue'
        $null = (& git @GitArgs 2>&1)
        return $LASTEXITCODE
    }
    $esc = { param($s) $s -replace "'", "''" }
    # Three clones: the Space's (origin is its address, one commit), another
    # repository's, and the Space's with no commit -- worktree add fails there.
    # The empty one's origin is the ssh form of the same address.
    $clone = Join-Path $scratch 'widgets-clone'
    $otherClone = Join-Path $scratch 'other-clone'
    $emptyClone = Join-Path $scratch 'empty-clone'
    foreach ($dir in @($clone, $otherClone, $emptyClone)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        $null = Invoke-Git @('-C', $dir, 'init', '-q')
    }
    $null = Invoke-Git @('-C', $clone, 'remote', 'add', 'origin', 'https://github.com/acme/widgets.git')
    $null = Invoke-Git @('-C', $emptyClone, 'remote', 'add', 'origin', 'git@github.com:acme/widgets.git')
    $null = Invoke-Git @('-C', $otherClone, 'remote', 'add', 'origin', 'https://github.com/acme/other.git')
    [System.IO.File]::WriteAllText((Join-Path $clone 'README.md'), "widgets`n", $utf8)
    $null = Invoke-Git @('-C', $clone, 'add', 'README.md')
    $committed = Invoke-Git @('-C', $clone, '-c', 'user.name=StartWork Test', '-c', 'user.email=startwork@example.invalid', '-c', 'commit.gpgsign=false', 'commit', '-q', '-m', 'init')
    Assert-True 'the scratch clone has a commit to check out' ($committed -eq 0) "git commit exited $committed"

    # The stub session. On macOS and Linux a shell script: its prompt (its
    # stdin, as claude --print reads it) is the first thing it writes -- so the
    # log's first message is what it was handed -- its flags go to stderr, and then it lives on like a
    # real session. On Windows a process image named claude.exe, so every check
    # runs; the launch itself is a VERIFY.md row there.
    $bin = Join-Path $scratch 'bin'
    New-Item -ItemType Directory -Path $bin -Force | Out-Null
    if ($onWindows) {
        Copy-Item (Join-Path $env:SystemRoot 'System32\whoami.exe') (Join-Path $bin 'claude.exe')
    }
    else {
        $stubText = @'
#!/bin/sh
cat
echo "$1 $2 $3 $4 $5 $6" >&2
exec sleep 30
'@
        $stub = Join-Path $bin 'claude'
        [System.IO.File]::WriteAllText($stub, $stubText.Replace("`r`n", "`n"), $utf8)
        & chmod +x $stub
    }
    $inClone = "Set-Location '$(& $esc $clone)'; "

    # Cards and issues, one per way an item is sized.
    $launchCards = [ordered]@{
        'Task-K2N4-launch-me.prompt.md'             = "# Task K2N4: Launch me`n`n**Assigned:** sonnet`n"
        'Task-F3AE-the-owners-seat.prompt.md'       = "# Task F3AE: The owner's seat`n`n**Assigned:** fable`n"
        'Task-N7QX-nobody-has-it.prompt.md'         = "# Task N7QX: Nobody has it`n"
        'Task-P9TC-sized-in-its-tags.prompt.md'     = "# Task P9TC: Sized in its tags`n`nTags: cli, opus`n"
        'Task-M6YD-mine.prompt.md'                  = "# Task M6YD: Mine`n`n**Assigned:** me`n"
        'Task-H4KU-a-size-with-no-model.prompt.md'  = "# Task H4KU: A size with no model`n`n**Assigned:** haiku`n"
        'Task45-sized-on-the-tracker.prompt.md'     = "# Task 45: Sized on the tracker`n"
    }
    foreach ($k in $launchCards.Keys) { [System.IO.File]::WriteAllText((Join-Path $current ($k -replace '^Task-', 'Task')), $launchCards[$k], $utf8) }
    [System.IO.File]::WriteAllText((Join-Path $scratch 'issue-44.json'), '{ "number": 44, "title": "Sized opus", "state": "OPEN", "labels": [{ "name": "opus" }], "milestone": null, "body": "", "url": "https://github.com/acme/widgets/issues/44" }', $utf8)
    [System.IO.File]::WriteAllText((Join-Path $scratch 'issue-45.json'), '{ "number": 45, "labels": [{ "name": "bug" }, { "name": "sonnet" }] }', $utf8)
    [System.IO.File]::WriteAllText((Join-Path $scratch 'issue-46.json'), '{ "number": 46, "title": "Sized fable", "state": "OPEN", "labels": [{ "name": "Fable" }], "milestone": null, "body": "", "url": "https://github.com/acme/widgets/issues/46" }', $utf8)
    $worktreeShape = '[\\/]\.claude[\\/]worktrees[\\/]startwork-k2n4-\d{8}-\d{6}'
    function Get-LaunchLeftovers {
        # What a launch would leave in a clone: a worktree, a log.
        param([string]$Dir)
        $found = @()
        if (Test-Path -LiteralPath (Join-Path $Dir '.claude')) { $found += '.claude' }
        $found += @(Get-ChildItem -LiteralPath $Dir -Filter '*.log' -File -ErrorAction SilentlyContinue | ForEach-Object { $_.Name })
        return ($found -join ', ')
    }

    # -WhatIf: every check, the commands, nothing added or started.
    $w = Invoke-Verb ($inClone + 'tkStartWork K2N4 -Launch -WhatIf') -PathPrefix $bin
    Assert-True '-Launch -WhatIf exits 0 and names the size, where it read it and the model' ($w.Exit -eq '0' -and $w.Inner.Contains('[WhatIf] Task K2N4 is sized sonnet (its **Assigned:** line): model sonnet.')) $w.All
    Assert-True 'it prints the worktree add it would run, under the clone''s .claude/worktrees/' ($w.Inner -match ('worktree add --detach "[^"]*' + $worktreeShape + '"')) $w.Inner
    Assert-True 'it prints where the block would be written, at the repository root' ($w.Inner -match 'Would write the block \(\d+ lines, as ''tkStartWork K2N4'' prints it\) to [^\n]*[\\/]startwork-k2n4-\d{8}-\d{6}\.block\.log') $w.Inner
    Assert-True 'it prints the exact claude command, the block as its stdin' ($w.Inner -match 'Would start, in that worktree: claude --print --model sonnet --output-format stream-json --verbose < "[^"]*startwork-k2n4-\d{8}-\d{6}\.block\.log"') $w.Inner
    Assert-True 'and the log at the repository root' ($w.Inner -match 'output would go to [^\n]*[\\/]startwork-k2n4-\d{8}-\d{6}\.log') $w.Inner
    Assert-True '-WhatIf adds no worktree and writes no log' ((Get-LaunchLeftovers $clone) -eq '') (Get-LaunchLeftovers $clone)

    $tags = Invoke-Verb ($inClone + 'tkStartWork P9TC -Launch -WhatIf') -PathPrefix $bin
    Assert-True 'a size in the card''s Tags picks the model' ($tags.Exit -eq '0' -and $tags.Inner.Contains('Task P9TC is sized opus (its Tags): model opus.') -and $tags.Inner.Contains('--model opus')) $tags.All
    $iss = Invoke-Verb ($inClone + 'tkStartWork 44 -Launch -WhatIf') -PathPrefix $bin
    Assert-True 'an issue''s label picks the model' ($iss.Exit -eq '0' -and $iss.Inner.Contains('Issue #44 is sized opus (a label on issue #44): model opus.')) $iss.All
    $tracked = Invoke-Verb ($inClone + 'tkStartWork 45 -Launch -WhatIf') -PathPrefix $bin
    Assert-True 'a card whose id is an issue number reads the issue''s label' ($tracked.Exit -eq '0' -and $tracked.Inner.Contains('Task 45 is sized sonnet (a label on issue #45): model sonnet.')) $tracked.All
    Assert-True 'with one gh read of that issue''s labels' (@($tracked.Calls | Where-Object { $_.StartsWith("issue${sep}view${sep}45${sep}--repo${sep}acme/widgets${sep}--json${sep}labels") }).Count -eq 1) ($tracked.Calls -join ' / ')

    # Never a launch on the owner's seat, and never a crew on nobody's item.
    $launchRefusals = [ordered]@{
        'sized fable on the card: the owner''s own seat' = @{ Snippet = 'tkStartWork F3AE -Launch'; Says = "Task F3AE is sized fable (its **Assigned:** line): the owner's own seat, never a crew builder"; Hint = 'tkStartWork F3AE' }
        'sized fable on the issue: the owner''s own seat' = @{ Snippet = 'tkStartWork 46 -Launch'; Says = "Issue #46 is sized fable (a label on issue #46): the owner's own seat, never a crew builder" }
        'no size at all'                                 = @{ Snippet = 'tkStartWork N7QX -Launch'; Says = 'Task N7QX has no size, so there is no crew to launch (a launch takes sonnet or opus)'; Hint = 'tkRoute N7QX -Assign sonnet' }
        'assigned to you'                                = @{ Snippet = 'tkStartWork M6YD -Launch'; Says = 'Task M6YD is assigned to you (its **Assigned:** line says me), not to a crew size' }
        'a size with no model'                           = @{ Snippet = 'tkStartWork H4KU -Launch'; Says = 'Task H4KU is sized haiku (its **Assigned:** line), and a launch has a model only for sonnet or opus' }
        '-Clip with -Launch'                             = @{ Snippet = 'tkStartWork K2N4 -Launch -Clip'; Says = '-Clip and -Launch are two ways to hand the block on; pass one.' }
        '-WhatIf without -Launch'                        = @{ Snippet = 'tkStartWork K2N4 -WhatIf'; Says = '-WhatIf previews -Launch' }
    }
    $before = Get-HubSnapshot
    foreach ($k in $launchRefusals.Keys) {
        $case = $launchRefusals[$k]
        $run = Invoke-Verb ($inClone + $case.Snippet) -PathPrefix $bin
        $ok = (Test-OneRefusal $run) -and $run.All.Contains([string]$case.Says)
        if ($case.Hint) { $ok = $ok -and $run.All.Contains([string]$case.Hint) }
        Assert-True "-Launch refused, nothing started: $k" $ok $run.All
    }

    $run = Invoke-Verb ("Set-Location '$(& $esc $scratch)'; tkStartWork K2N4 -Launch") -PathPrefix $bin
    Assert-True '-Launch refused, nothing started: not in a git repository' ((Test-OneRefusal $run) -and $run.All.Contains('This folder is not in a git repository, and -Launch starts from a clone of acme/widgets')) $run.All
    $run = Invoke-Verb ("Set-Location '$(& $esc $otherClone)'; tkStartWork K2N4 -Launch") -PathPrefix $bin
    Assert-True '-Launch refused, nothing started: a repository whose origin is not the Space''s' ((Test-OneRefusal $run) -and $run.All.Contains("has origin https://github.com/acme/other.git, not Widgets's address (https://github.com/acme/widgets)")) $run.All
    $run = Invoke-Verb ("Set-Location '$(& $esc $emptyClone)'; tkStartWork K2N4 -Launch") -PathPrefix $bin
    Assert-True '-Launch refused, nothing started: worktree add failed (the ssh origin is the same address)' ((Test-OneRefusal $run) -and $run.All.Contains('git worktree add failed in')) $run.All
    Assert-True 'and the empty clone has no worktree and no log' ((Get-LaunchLeftovers $emptyClone) -eq '') (Get-LaunchLeftovers $emptyClone)

    $gitDir = Split-Path -Parent (Get-Command git -CommandType Application | Select-Object -First 1).Source
    if (@(Get-ChildItem -LiteralPath $gitDir -Filter 'claude*' -File -ErrorAction SilentlyContinue).Count -gt 0) {
        Write-Host "  SKIP  no claude on the PATH: git and claude share $gitDir here, so a PATH with git has claude" -ForegroundColor Yellow
    }
    else {
        $run = Invoke-Verb ($inClone + 'tkStartWork K2N4 -Launch') -PathOnly $gitDir
        Assert-True '-Launch refused, nothing started: claude is not on the PATH, and the hint names the surface' ((Test-OneRefusal $run) -and $run.All.Contains('claude is not on the PATH, so there is no session to start.') -and $run.All.Contains('startWorkLaunch')) $run.All
    }
    Assert-True 'the hub is untouched through every launch refusal' ((Get-HubSnapshot) -ceq $before)
    Assert-True 'and the clone has no worktree and no log' ((Get-LaunchLeftovers $clone) -eq '') (Get-LaunchLeftovers $clone)

    # The launch: through a pipe, back at once, the session alive, its first
    # message the block. The proof the Windows host repeats is VERIFY.md's.
    if ($onWindows) {
        Write-Host "  SKIP  the launch itself: Windows walks it from VERIFY.md, Gate 12 (StartWork -Launch rows)" -ForegroundColor Yellow
    }
    else {
        $plain = Invoke-Verb 'tkStartWork K2N4'
        $launched = Invoke-Verb ($inClone + 'tkStartWork K2N4 -Launch') -PathPrefix $bin
        $pidMatch = [regex]::Match($launched.Inner, 'Launched Task K2N4 on sonnet: PID (\d+)\.')
        $childPid = 0
        if ($pidMatch.Success) { $childPid = [int]$pidMatch.Groups[1].Value }
        try {
            Assert-True '-Launch exits 0 and prints the PID' ($launched.Exit -eq '0' -and $childPid -gt 0) $launched.All
            Assert-True ("through a pipe it returns while the session lives on ({0:N1}s; the stub lives 30s)" -f $launched.Seconds) ($launched.Seconds -lt 20) $launched.All
            Assert-True 'the session is still running after the verb returned' ($childPid -gt 0 -and $null -ne (Get-Process -Id $childPid -ErrorAction SilentlyContinue))
            $wtMatch = [regex]::Match($launched.Inner, '(?m)^\s+worktree:\s+(.+?)\s*$')
            $logMatch = [regex]::Match($launched.Inner, '(?m)^\s+log:\s+(.+?)\s*$')
            Assert-True 'it prints the worktree, under the clone''s .claude/worktrees/' ($wtMatch.Success -and $wtMatch.Groups[1].Value -match $worktreeShape -and (Test-Path -LiteralPath (Join-Path $wtMatch.Groups[1].Value 'README.md'))) $launched.Inner
            $logPath = ''
            if ($logMatch.Success) { $logPath = $logMatch.Groups[1].Value }
            Assert-True 'and the log, at the repository root' ($logPath -match '[\\/]widgets-clone[\\/]startwork-k2n4-\d{8}-\d{6}\.log$') $launched.Inner
            $logText = ''
            $deadline = (Get-Date).AddSeconds(10)
            while ((Get-Date) -lt $deadline) {
                if ($logPath -and (Test-Path -LiteralPath $logPath)) {
                    $logText = [System.IO.File]::ReadAllText($logPath)
                    if ($logText.Length -ge $plain.Inner.Length) { break }
                }
                Start-Sleep -Milliseconds 200
            }
            Assert-True 'the session''s first message is the block, whole -- the one StartWork prints' ($plain.Exit -eq '0' -and $logText -ceq $plain.Inner) ("log $($logText.Length) chars, block $($plain.Inner.Length)")
            $errText = ''
            if ($logPath) {
                $errPath = $logPath -replace '\.log$', '.err.log'
                $deadline = (Get-Date).AddSeconds(5)
                while ((Get-Date) -lt $deadline -and -not $errText) {
                    if (Test-Path -LiteralPath $errPath) { $errText = [System.IO.File]::ReadAllText($errPath).Trim() }
                    if (-not $errText) { Start-Sleep -Milliseconds 200 }
                }
            }
            Assert-True 'the model is the size''s, on the claude command line' ($errText -ceq '--print --model sonnet --output-format stream-json --verbose') $errText
        }
        finally {
            if ($childPid -gt 0) { Stop-Process -Id $childPid -Force -ErrorAction SilentlyContinue }
        }
    }
}
catch {
    Assert-True 'the cases ran to the end without a terminating error' $false $_.Exception.Message
}
finally {
    Remove-Item $scratch -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host ""
$total = $script:passed + $script:failed
Write-Host "  Results: $script:passed/$total passed" -ForegroundColor $(if ($script:failed -eq 0) { 'Green' } else { 'Red' })
if ($script:failed -gt 0) {
    Write-Host ""
    foreach ($e in $script:errors) { Write-Host $e -ForegroundColor Red }
}
Write-Host ""
if (Get-Command Write-P20TestResult -ErrorAction SilentlyContinue) {
    Write-P20TestResult -Suite 'StartWork' -Result $(if ($script:failed -eq 0) { 'pass' } else { 'fail' }) -Passed $script:passed -Total $total
}
if ($script:failed -gt 0) { exit 1 }
exit 0
