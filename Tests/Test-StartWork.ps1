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
    3. Section one  the Space's how-we-work.md, when it has one, replaces the
                derived sentence and the heading names its path.
    4. The issue    a number no card carries reads the Space's issue (gh
                stubbed): the block byte for byte, one read.
    5. The prompt   -Prompt overrides the row; a kind with no row and a row
                whose file is missing are refusals naming the key.
    6. Refusals     each exit 2, one Error block, nothing written: no id, an id
                that matches nothing, an archived card, a closed issue, a pull
                request, an Azure DevOps Space, an undeclared -Space, a partial
                name for a non-interactive caller.

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
    param([string]$Snippet, [bool]$On = $true, [string]$Prompts = '{}', [switch]$Quiet)
    $features = '{}'
    if ($On) { $features = '{ "solitaireAgile": true }' }
    [System.IO.File]::WriteAllText((Join-Path $pkg 'config.local.json'),
        "{ `"promptsRoot`": `"$($hub -replace '\\', '/')`", `"activeSpace`": `"widgets`", `"quietStart`": true, `"features`": $features, `"startWork`": { `"prompts`": $Prompts } }", $utf8)
    if (Test-Path -LiteralPath $ghLog) { Remove-Item -LiteralPath $ghLog -Force }
    $q = { param($p) $p -replace "'", "''" }
    $quietLine = ''
    if ($Quiet) { $quietLine = "`$env:TOOLKIT_QUIET_STARTUP = '1'`n" }
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
    $out = (& pwsh -NoProfile -NonInteractive -File $runner 2>&1 | ForEach-Object { "$_" }) -join "`n"
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
    return [pscustomobject]@{ All = $out; Inner = $inner; Exit = $code; Calls = $calls }
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
    $note = Join-Path $hub 'widgets/how-we-work.md'
    [System.IO.File]::WriteAllText($note, "We work in small pull requests.`r`nOne card, one branch.`r`n", $utf8)
    $n = Invoke-Verb 'tkStartWork 23A3'
    Assert-True 'a how-we-work.md: the heading names its path' ($n.Inner -match '(?m)^## How we work in Widgets \(widgets/how-we-work\.md\)$') $n.Inner
    Assert-True 'and its text stands in for the derived sentence, LF' ($n.Inner.Contains("(widgets/how-we-work.md)`nWe work in small pull requests.`nOne card, one branch.`n`n## The work:") -and $n.Inner -notmatch 'You work with agents here') $n.Inner
    Remove-Item -LiteralPath $note -Force

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
    Assert-True 'StartWork -Help renders the usage' ($usage.Inner -match [regex]::Escape('StartWork <id> [-Clip] [-Prompt <path>] [-Space <slug>]')) $usage.Inner
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
