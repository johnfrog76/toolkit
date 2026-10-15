<#
.SYNOPSIS
    Team Agile's triage -- the grouping rule over the shared table, the
    golden texts byte for byte, and Triage and Route typed in a fresh shell.

.DESCRIPTION
    1. The table     Tests/fixtures/rituals/triage.json, every case: the groups
                     in order (no milestone first, then most open, a tie by
                     title), each group's counts, context line and issue
                     numbers, each issue's worker, size, severity and
                     deep-water mark, the sizes -- the same table
                     Tests/test_triage.py asserts against the agent.
    2. The goldens   the rendered text against triage-<name>.txt, byte for byte
                     (LF); every case rendered again from its own JSON round trip.
    3. Off           with features.solitaireAgile unset there is no Triage and
                     no Route, and nothing for the bridge to call.
    4. Triage typed  in a fresh shell -- the package's own manifest imported by
                     path, gh stubbed as a function answering the mixed case:
                     the text the rule renders, -AsJson, an Azure DevOps Space's
                     Tracker line (exit 0), an undeclared -Space refused.
    5. Route typed   the exact gh argv each switch writes, in order, and with
                     all four at once; -WhatIf writes nothing; the deep-water
                     hint names the two moves; every refusal exits 2 with one
                     Error block and no gh write; the hub untouched.

    Run:  pwsh -File Tests/Test-Triage.ps1
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
Write-Host "  Triage -- Team Agile's first write" -ForegroundColor Cyan
Write-Host "  -----------------------------------------------------" -ForegroundColor DarkGray
Write-Host ""

. (Join-Path $pkgRoot 'Scripts/Get-Consts.ps1')
. (Join-Path $pkgRoot 'Scripts/Triage-Rules.ps1')
$row = (Get-P20TriageRow -PackageRoot $pkgRoot).Row

$fixtureDir = Join-Path $scriptDir 'fixtures/rituals'
$fixture = [System.IO.File]::ReadAllText((Join-Path $fixtureDir 'triage.json')) | ConvertFrom-Json
$cases = @($fixture.cases)
Assert-True 'the table is read: four cases' ($cases.Count -eq 4) "$($cases.Count) cases"
Assert-True 'ceremonies.json declares triage''s three questions' ((@($row.slots) -join ',') -eq 'milestone,severity,size')
Assert-True 'and its severities and the deep-water label' ((@($row.severities) -join ',') -eq 'sev1,sev2,sev3' -and [string]$row.deepWaterLabel -eq 'deep-water')

# -- 1. The table, 2. the goldens -------------------------------------------------
foreach ($case in $cases) {
    $name = [string]$case.name
    $exp = $case.expected
    Write-Host ""
    Write-Host "-- $name --" -ForegroundColor Cyan
    $t = Invoke-P20TriageFill -Labels @($fixture.labels) -Issues @($case.issues) -Tracker $case.tracker -Space ([string]$case.space) -PackageRoot $pkgRoot

    $wantGroups = @($exp.groups)
    $gotGroups = @($t.groups)
    $wantOrder = (@($wantGroups | ForEach-Object { [string]$_.milestone })) -join '|'
    $gotOrder = (@($gotGroups | ForEach-Object { [string]$_.milestone })) -join '|'
    Assert-True "${name}: the groups, in order: [$wantOrder]" ($gotGroups.Count -eq $wantGroups.Count -and $gotOrder -ceq $wantOrder) "got [$gotOrder]"
    $groupsMatch = $true
    $detail = ''
    for ($i = 0; $i -lt [Math]::Min($gotGroups.Count, $wantGroups.Count); $i++) {
        $g = $gotGroups[$i]
        $w = $wantGroups[$i]
        $gotNums = (@($g.issues | ForEach-Object { [int]$_.number })) -join ','
        $wantNums = (@($w.issues | ForEach-Object { [int]$_ })) -join ','
        if ($g.open -ne [int]$w.open -or $g.routed -ne [int]$w.routed -or $g.unrouted -ne [int]$w.unrouted -or $g.context -cne [string]$w.context -or $gotNums -ne $wantNums) {
            $groupsMatch = $false
            $detail += "[$($w.milestone): got $($g.open)/$($g.routed)/$($g.unrouted) '$($g.context)' $gotNums] "
        }
    }
    Assert-True "${name}: each group's counts, context line and issue numbers" $groupsMatch $detail

    $issuesMatch = $true
    $detail = ''
    $seen = 0
    foreach ($g in $gotGroups) {
        foreach ($iss in @($g.issues)) {
            $seen++
            $w = $exp.issues.([string]$iss.number)
            if ($null -eq $w -or $iss.worker -cne [string]$w.worker -or $iss.size -cne [string]$w.size -or $iss.severity -cne [string]$w.severity -or [bool]$iss.deepWater -ne [bool]$w.deepWater) {
                $issuesMatch = $false
                $detail += "[#$($iss.number): $($iss.worker)/$($iss.size)/$($iss.severity)/$($iss.deepWater)] "
            }
        }
    }
    $wantSeen = @($exp.issues.PSObject.Properties).Count
    Assert-True "${name}: each issue's worker, size, severity and deep-water ($wantSeen issues)" ($issuesMatch -and $seen -eq $wantSeen) "$detail seen $seen"
    Assert-True "${name}: the sizes are the repo's worker labels" (((@($t.sizes | ForEach-Object { $_.label })) -join ',') -ceq ((@($exp.sizes)) -join ','))

    $text = Format-P20TriageText -Triage $t -PackageRoot $pkgRoot
    $golden = [System.IO.File]::ReadAllText((Join-Path $fixtureDir ([string]$exp.text)))
    Assert-True "${name}: the text is $($exp.text), byte for byte" ($text -ceq $golden) ("`n--- got ---`n$text--- want ---`n$golden")
    $back = ($t | ConvertTo-Json -Depth 8) | ConvertFrom-Json
    $again = Format-P20TriageText -Triage $back -PackageRoot $pkgRoot
    Assert-True "${name}: the JSON round trip renders the same text" ($again -ceq $text) $again
}

# -- The scratch package and hub -------------------------------------------------
$scratch = Join-Path ([System.IO.Path]::GetTempPath()) ("p20-triage-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
$pkg = Join-Path $scratch 'pkg'
$hub = Join-Path $scratch 'hub'
$logDir = Join-Path $scratch 'log'
$ghLog = Join-Path $scratch 'gh-calls.log'
$utf8 = New-Object System.Text.UTF8Encoding($false)
$sep = [char]0x1F

function Invoke-Verb {
    # A fresh shell per call: gh replaced by a function that logs every call
    # (args joined with U+001F, one line each) and answers from the scratch
    # files, then the package's own manifest and nothing else (AGENTS.md, "One
    # toolkit per shell"). P20_TEST_GH_EDIT_FAILS makes every issue edit fail;
    # P20_TEST_GH_PUBLIC makes the repository answer PUBLIC, PRIVATE otherwise.
    param([string]$Snippet, [bool]$On = $true, [switch]$EditFails, [switch]$Public)
    $features = '{}'
    if ($On) { $features = '{ "solitaireAgile": true }' }
    [System.IO.File]::WriteAllText((Join-Path $pkg 'config.local.json'),
        "{ `"promptsRoot`": `"$($hub -replace '\\', '/')`", `"activeSpace`": `"widgets`", `"quietStart`": true, `"features`": $features }", $utf8)
    if (Test-Path -LiteralPath $ghLog) { Remove-Item -LiteralPath $ghLog -Force }
    $q = { param($p) $p -replace "'", "''" }
    $fails = ''
    if ($EditFails) { $fails = "`$env:P20_TEST_GH_EDIT_FAILS = '1'`n" }
    if ($Public) { $fails += "`$env:P20_TEST_GH_PUBLIC = '1'`n" }
    $body = $fails + @"
`$env:PSModulePath = '$(& $q $pkg)'
`$env:PROMPTS_ROOT = ''
`$env:P20_USAGE_LOG_DIR = '$(& $q $logDir)'
Get-ChildItem Env: | Where-Object { `$_.Name -like 'TEAMS_WEBHOOK_*' } | ForEach-Object { Remove-Item "Env:\`$(`$_.Name)" -ErrorAction SilentlyContinue }
function global:gh {
    [System.IO.File]::AppendAllText('$(& $q $ghLog)', ((@(`$args | ForEach-Object { [string]`$_ })) -join [char]0x1F) + "``n")
    if (`$args[0] -eq 'issue' -and `$args[1] -eq 'edit' -and `$env:P20_TEST_GH_EDIT_FAILS) { `$global:LASTEXITCODE = 1; Write-Error 'GraphQL: Could not resolve to an issue'; return }
    `$global:LASTEXITCODE = 0
    if (`$args[0] -eq 'label' -and `$args[1] -eq 'list') { return (Get-Content -Raw -LiteralPath '$(& $q (Join-Path $scratch 'labels.json'))') }
    if (`$args[0] -eq 'issue' -and `$args[1] -eq 'list') { return (Get-Content -Raw -LiteralPath '$(& $q (Join-Path $scratch 'issues.json'))') }
    if (`$args[0] -eq 'api' -and `$args.Count -eq 2 -and `$args[1] -eq 'repos/acme/widgets') { if (`$env:P20_TEST_GH_PUBLIC) { return '{"visibility":"PUBLIC"}' }; return '{"visibility":"PRIVATE"}' }
    if (`$args[0] -eq 'api') { return (Get-Content -Raw -LiteralPath '$(& $q (Join-Path $scratch 'milestones.json'))') }
    return ''
}
Import-Module '$(& $q $pkg)/Prompt20Toolkit/Prompt20Toolkit.psd1' -Force 3>`$null 6>`$null
'<<<'
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
    # The module's own startup probe (Get-Environment.ps1: gh auth status, gh api user,
    # gh api users/<owner>) is not the verb's: the log holds the VERB's reads and writes.
    $sep = [string][char]0x1F
    $calls = @($calls | Where-Object { -not ($_.StartsWith('auth') -or $_.StartsWith("api${sep}user")) })
    return [pscustomobject]@{ All = $out; Inner = $inner; Exit = $code; Calls = $calls }
}

function Get-Edits {
    # The issue edits a run made, each as one space-joined line.
    param($Run)
    return @($Run.Calls | Where-Object { $_.StartsWith("issue${sep}edit${sep}") } | ForEach-Object { $_.Replace([string]$sep, ' ') })
}

function Test-OneRefusal {
    # A stated refusal: exit 2, ONE Error block, no generic 'exit code' block, no gh write.
    param($Run)
    return ($Run.Exit -eq '2' -and (@([regex]::Matches($Run.All, '(?m)^Error: ')).Count -eq 1) -and $Run.All -notmatch 'exit code' -and (Get-Edits $Run).Count -eq 0)
}

function Get-HubSnapshot {
    return ((@(Get-ChildItem -LiteralPath $hub -Recurse -Force -File | ForEach-Object { $_.FullName + '|' + $_.Length + '|' + $_.LastWriteTimeUtc.Ticks })) -join "`n")
}

try {
    New-Item -ItemType Directory -Path $pkg, $logDir, (Join-Path $hub 'widgets/current') -Force | Out-Null
    foreach ($item in @('utilities.psm1', 'config.default.json', 'consts.json')) { Copy-Item (Join-Path $pkgRoot $item) $pkg -Force }
    foreach ($folder in @('Scripts', 'Config', 'Prompt20Toolkit', 'templates')) { Copy-Item (Join-Path $pkgRoot $folder) $pkg -Recurse -Force }
    [System.IO.File]::WriteAllText((Join-Path $hub 'hub.json'), @'
{
  "hub": 1,
  "spaces": [
    { "slug": "widgets", "name": "Widgets", "status": "active", "promptsFolder": "widgets", "org": "https://github.com/acme/widgets", "howIWork": "agents" },
    { "slug": "board",   "name": "Board",   "status": "active", "promptsFolder": "board",   "org": "https://dev.azure.com/acme-org" },
    { "slug": "sandbox", "name": "Sandbox", "status": "local",  "promptsFolder": "sandbox", "org": "https://github.com/acme/sandbox" }
  ]
}
'@, $utf8)

    # What the stub answers: the mixed case's labels and OPEN issues in gh's own
    # shape (labels as objects), and two open milestones.
    $mixed = @($cases | Where-Object { $_.name -eq 'mixed' })[0]
    $ghIssues = @(foreach ($iss in @($mixed.issues | Where-Object { $_.state -eq 'OPEN' })) {
            [ordered]@{
                number    = [int]$iss.number
                title     = [string]$iss.title
                state     = 'OPEN'
                labels    = [object[]]@(@($iss.labels) | ForEach-Object { [ordered]@{ name = [string]$_ } })
                milestone = $iss.milestone
                url       = [string]$iss.url
            }
        })
    $ghLabels = @($fixture.labels | ForEach-Object { [ordered]@{ name = [string]$_.name; description = [string]$_.description } })
    $ghMilestones = @(
        [ordered]@{ title = 'Phase 6: ledgers'; number = 6; state = 'open' },
        [ordered]@{ title = 'Going public'; number = 7; state = 'open' }
    )
    [System.IO.File]::WriteAllText((Join-Path $scratch 'labels.json'), (ConvertTo-Json -InputObject ([object[]]$ghLabels) -Depth 4), $utf8)
    [System.IO.File]::WriteAllText((Join-Path $scratch 'issues.json'), (ConvertTo-Json -InputObject ([object[]]$ghIssues) -Depth 5), $utf8)
    [System.IO.File]::WriteAllText((Join-Path $scratch 'milestones.json'), (ConvertTo-Json -InputObject ([object[]]$ghMilestones) -Depth 3), $utf8)

    # -- 3. Off means absent -----------------------------------------------------
    Write-Host ""
    Write-Host "-- Off: no verbs ---------------------------------------" -ForegroundColor Cyan
    $off = Invoke-Verb "'TRIAGE=' + [bool](Get-Command tkTriage -ErrorAction SilentlyContinue); 'ROUTE=' + [bool](Get-Command tkRoute -ErrorAction SilentlyContinue); 'MAP=' + (Get-P20CommandMap)" -On $false
    Assert-True 'with the flag off Triage and Route do not exist' ($off.Inner -match 'TRIAGE=False' -and $off.Inner -match 'ROUTE=False') $off.All
    Assert-True 'and the bridge has neither to call' ($off.Inner -notmatch '"Triage"' -and $off.Inner -notmatch '"Route"') $off.Inner

    $on = Invoke-Verb "'MAP=' + (Get-P20CommandMap); tkMenu -All"
    Assert-True 'with the flag on the bridge can call both' ($on.Inner -match '"Triage"' -and $on.Inner -match '"Route"') $on.Inner
    Assert-True 'and Menu -All lists both' ($on.Inner -match '(?m)^\s+tkTriage\s' -and $on.Inner -match '(?m)^\s+tkRoute\s') $on.Inner

    # -- 4. Triage, as typed --------------------------------------------------------
    Write-Host ""
    Write-Host "-- Triage, as typed -------------------------------------" -ForegroundColor Cyan
    $before = Get-HubSnapshot
    $r = Invoke-Verb 'tkTriage'
    $golden = [System.IO.File]::ReadAllText((Join-Path $fixtureDir 'triage-mixed.txt'))
    $want = $golden.Replace('Triage -- toolkit', 'Triage -- widgets').TrimEnd([char]10)
    Assert-True 'Triage exits 0 and prints the mixed golden, for this Space' ($r.Exit -eq '0' -and $r.Inner -ceq $want) ("`n--- got ---`n$($r.Inner)`n--- want ---`n$want")
    Assert-True 'it reads the labels, then the OPEN issues with their milestones' ($r.Calls.Count -eq 2 -and $r.Calls[0].StartsWith("label${sep}list${sep}--repo${sep}acme/widgets") -and $r.Calls[1] -match "state${sep}open" -and $r.Calls[1] -match 'milestone') ($r.Calls -join ' / ')
    Assert-True 'and writes nothing to the hub' ((Get-HubSnapshot) -ceq $before)

    $j = Invoke-Verb 'tkTriage -AsJson'
    $parsed = $null
    try { $parsed = $j.Inner | ConvertFrom-Json } catch { $parsed = $null }
    Assert-True '-AsJson prints the route''s shape' ($null -ne $parsed -and $parsed.ceremony -eq 'triage' -and $parsed.space -eq 'widgets' -and @($parsed.groups).Count -eq 4 -and [string]@($parsed.groups)[0].milestone -eq '') $j.All
    if ($parsed) {
        Assert-True '-AsJson''s text is the text the verb prints' (([string]$parsed.text).TrimEnd([char]10) -ceq $r.Inner)
        Assert-True '-AsJson names the sizes and the severities the page offers' ((@($parsed.sizes | ForEach-Object { $_.label }) -join ',') -eq 'fable,opus,sonnet' -and (@($parsed.severities) -join ',') -eq 'sev1,sev2,sev3')
    }

    $ado = Invoke-Verb 'tkTriage -Space board'
    Assert-True 'an Azure DevOps Space: a Tracker line, exit 0, gh never asked' ($ado.Exit -eq '0' -and $ado.Inner -match '(?m)^  Tracker {4}This Space''s tracker is not GitHub' -and $ado.Calls.Count -eq 0) $ado.All
    $bad = Invoke-Verb 'tkTriage -Space nowhere'
    Assert-True 'an undeclared -Space is a stated refusal' ($bad.Exit -eq '2' -and $bad.All -match "No Space 'nowhere' is declared" -and (@([regex]::Matches($bad.All, '(?m)^Error: ')).Count -eq 1)) $bad.All

    # -- 5. Route, as typed -----------------------------------------------------------
    Write-Host ""
    Write-Host "-- Route, as typed --------------------------------------" -ForegroundColor Cyan
    $base = 'issue edit 132 --repo acme/widgets'
    $r = Invoke-Verb 'tkRoute 132 -Size opus'
    Assert-True '-Size: adds the worker label and removes the other sizes, one write' ($r.Exit -eq '0' -and ((Get-Edits $r) -join '/') -ceq "$base --add-label opus --remove-label fable,sonnet") (((Get-Edits $r) -join ' / ') + "`n" + $r.All)
    Assert-True '-Size: the sizes are read from the repo''s labels first' ($r.Calls.Count -ge 1 -and $r.Calls[0].StartsWith("label${sep}list${sep}--repo${sep}acme/widgets")) ($r.Calls -join ' / ')
    Assert-True 'and the verb says what it wrote' ($r.Inner -match 'Routed #132 on acme/widgets: size opus\.') $r.Inner

    $r = Invoke-Verb "tkRoute '#132' -Size OPUS"
    Assert-True 'a size in any case, a number with its #: the label''s own spelling' (((Get-Edits $r) -join '/') -ceq "$base --add-label opus --remove-label fable,sonnet") (((Get-Edits $r) -join ' / ') + "`n" + $r.All)

    $r = Invoke-Verb "tkRoute 132 -Milestone 'phase 6: LEDGERS'"
    Assert-True '-Milestone: one write, the tracker''s spelling, one argv element' ($r.Exit -eq '0' -and @($r.Calls | Where-Object { $_ -ceq "issue${sep}edit${sep}132${sep}--repo${sep}acme/widgets${sep}--milestone${sep}Phase 6: ledgers" }).Count -eq 1 -and (Get-Edits $r).Count -eq 1) (($r.Calls -join ' / ') + "`n" + $r.All)
    Assert-True '-Milestone: the open milestones are read first' (@($r.Calls | Where-Object { $_ -ceq "api${sep}--method${sep}GET${sep}repos/acme/widgets/milestones${sep}-f${sep}state=open${sep}-F${sep}per_page=100" }).Count -eq 1) ($r.Calls -join ' / ')

    $r = Invoke-Verb 'tkRoute 132 -Severity SEV2'
    Assert-True '-Severity: adds that one and removes the other two, one write' ($r.Exit -eq '0' -and ((Get-Edits $r) -join '/') -ceq "$base --add-label sev2 --remove-label sev1,sev3") (((Get-Edits $r) -join ' / ') + "`n" + $r.All)
    # The one read every write makes is the repository's visibility,
    # after the reads and before the write; nothing else is read for a severity.
    Assert-True '-Severity reads nothing first' (@($r.Calls | Where-Object { $_ -cne "api${sep}repos/acme/widgets" }).Count -eq 1) ($r.Calls -join ' / ')
    Assert-True 'and the write asks the repository''s visibility once, after the reads' (@($r.Calls | Where-Object { $_ -ceq "api${sep}repos/acme/widgets" }).Count -eq 1) ($r.Calls -join ' / ')

    $r = Invoke-Verb 'tkRoute 132 -DeepWater'
    Assert-True '-DeepWater: adds the label, one write' ($r.Exit -eq '0' -and ((Get-Edits $r) -join '/') -ceq "$base --add-label deep-water") (((Get-Edits $r) -join ' / ') + "`n" + $r.All)
    Assert-True 'and prints the two moves: Fable or split' ($r.Inner -match 'two moves' -and $r.Inner -match 'tkRoute 132 -Size fable' -and $r.Inner -match 'split') $r.Inner
    Assert-True 'and the split names its verb: NewItem with the issue as the parent' ($r.Inner -match 'tkNewItem -Parent 132 -Title') $r.Inner

    $r = Invoke-Verb "tkRoute 132 -Size fable -Milestone 'Going public' -Severity sev1 -DeepWater"
    $wantAll = @(
        "$base --add-label fable --remove-label opus,sonnet",
        "$base --milestone Going public",
        "$base --add-label sev1 --remove-label sev2,sev3",
        "$base --add-label deep-water"
    ) -join '/'
    Assert-True 'all four at once: four writes, in the usage''s order' ($r.Exit -eq '0' -and ((Get-Edits $r) -join '/') -ceq $wantAll) (((Get-Edits $r) -join ' / ') + "`n" + $r.All)
    Assert-True 'with -Size fable the two moves are not offered again' ($r.Inner -notmatch 'two moves') $r.Inner

    # On stage: a private repository prints no line; a public one prints
    # it once, before the write, and in -WhatIf too. Nothing is asked.
    Assert-True 'a private repository: no public line' ($r.All -notmatch 'This repository is public') $r.All
    $pub = Invoke-Verb 'tkRoute 132 -Severity sev2' -Public
    Assert-True 'a public repository: the line, once, and the write still made' ($pub.Exit -eq '0' -and @([regex]::Matches($pub.All, 'This repository is public')).Count -eq 1 -and (Get-Edits $pub).Count -eq 1) $pub.All
    $pub = Invoke-Verb 'tkRoute 132 -Severity sev2 -WhatIf' -Public
    Assert-True '-WhatIf on a public repository shows the line and writes nothing' ($pub.Exit -eq '0' -and $pub.All -match 'This repository is public' -and (Get-Edits $pub).Count -eq 0) $pub.All

    $r = Invoke-Verb "tkRoute 132 -Size sonnet -Severity sev3 -WhatIf"
    Assert-True '-WhatIf: no write at all, exit 0' ($r.Exit -eq '0' -and (Get-Edits $r).Count -eq 0) (($r.Calls -join ' / ') + "`n" + $r.All)
    Assert-True '-WhatIf prints every gh write it would make' ($r.Inner -match [regex]::Escape("[WhatIf] gh $base --add-label sonnet --remove-label fable,opus") -and $r.Inner -match [regex]::Escape("[WhatIf] gh $base --add-label sev3 --remove-label sev1,sev2")) $r.Inner

    # The refusals: each exit 2, one Error block, no write.
    $refusals = [ordered]@{
        'no number'                         = @{ Snippet = 'tkRoute -Size opus'; Says = 'Route needs an issue number' }
        'a number that is not one'          = @{ Snippet = 'tkRoute abc -Size opus'; Says = "'abc' is not an issue number" }
        'no switch'                         = @{ Snippet = 'tkRoute 132'; Says = 'Nothing to route' }
        'a severity that is not one'        = @{ Snippet = 'tkRoute 132 -Severity sev9'; Says = "'sev9' is not a severity" }
        'a size that is not a worker label' = @{ Snippet = 'tkRoute 132 -Size haiku'; Says = "'haiku' is not a worker label on acme/widgets"; Hint = 'Sizes on acme/widgets: fable, opus, sonnet' }
        'an unknown milestone'              = @{ Snippet = "tkRoute 132 -Milestone 'Phase 9'"; Says = "No open milestone 'Phase 9'"; Hint = 'Open milestones on acme/widgets: Phase 6: ledgers; Going public' }
        'an undeclared -Space'              = @{ Snippet = 'tkRoute 132 -Size opus -Space nowhere'; Says = "No Space 'nowhere' is declared" }
        'an Azure DevOps Space'             = @{ Snippet = 'tkRoute 132 -Size opus -Space board'; Says = 'tracker is not GitHub' }
        'a local Space'                     = @{ Snippet = 'tkRoute 132 -Size opus -Space sandbox'; Says = 'This Space is local' }
    }
    foreach ($k in $refusals.Keys) {
        $case = $refusals[$k]
        $r = Invoke-Verb $case.Snippet
        $ok = (Test-OneRefusal $r) -and $r.All.Contains([string]$case.Says)
        if ($case.Hint) { $ok = $ok -and $r.All.Contains([string]$case.Hint) }
        Assert-True "refused, nothing written: $k" $ok (($r.Calls -join ' / ') + "`n" + $r.All)
    }
    $r = Invoke-Verb 'tkRoute 132 -Size opus -Severity sev2' -EditFails
    Assert-True 'a gh write that fails is a stated refusal naming it' ($r.Exit -eq '2' -and $r.All -match 'gh did not write the size opus on #132' -and (@([regex]::Matches($r.All, '(?m)^Error: ')).Count -eq 1) -and $r.All -notmatch 'exit code') $r.All
    Assert-True 'and the writes after it are not tried' ((Get-Edits $r).Count -eq 1) ($r.Calls -join ' / ')

    Assert-True 'Route wrote nothing to the hub through all of it' ((Get-HubSnapshot) -ceq $before)

    $usage = Invoke-Verb 'tkRoute -Help'
    Assert-True 'Route -Help renders the usage' ($usage.Inner -match [regex]::Escape('Route <n> [-Size <label>] [-Milestone <title>] [-Severity <sev>] [-DeepWater] [-Space <slug>] [-WhatIf]')) $usage.Inner
    $usage = Invoke-Verb 'tkTriage -Help'
    Assert-True 'Triage -Help renders the usage' ($usage.Inner -match [regex]::Escape('Triage [-Space <slug>] [-AsJson]')) $usage.Inner
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
    Write-P20TestResult -Suite 'Triage' -Result $(if ($script:failed -eq 0) { 'pass' } else { 'fail' }) -Passed $script:passed -Total $total
}
if ($script:failed -gt 0) { exit 1 }
exit 0
