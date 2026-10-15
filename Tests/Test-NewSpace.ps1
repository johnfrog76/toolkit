<#
.SYNOPSIS
    NewSpace -- add a Space, typed.
.DESCRIPTION
    Typed as the VERB in a fresh child shell against a scratch package and hub
    (AGENTS.md: a suite that runs a script directly does not test the verb).
    Holds: the three forms -- -Repo (a GitHub Space named from the repository),
    <slug> -Address (Azure DevOps, the next step named), <slug> alone (your own
    cards, local); every key written through Config into hub.json; the folder
    made, or an existing one ADOPTED untouched with its cards counted; no switch,
    and the last line the SwitchSpace that does; -WhatIf writing nothing; every
    refusal exit 2, one sentence, nothing written; gh asked and never required
    (absent: added and "not checked"; a repository it cannot see: "not visible to this login"); -Discover marking the repositories that are
    already Spaces; -Discover -Owner -- an organisation's repositories, the
    ones shared with you, the owners offered, a read-only repository marked, an
    owner gh cannot see refused, and no & in any gh argument; -Discover -Repo -- one
    typed repository read before it is added, and one gh cannot see said as such;
    a list read past 200 to the ceiling, a page at a time, and said past it; and the proposals
    over the shared table
    (Tests/fixtures/spaces/proposals.json, which the web's mirror asserts too).
    gh is ALWAYS a stand-in here -- a function, or off the PATH -- never the real one.
    And the other end of a Space's life: RetireSpace (status archive, through
    Config, still declared) and RemoveSpace (un-declared through Config; the folder
    and every card in it left exactly as they were, and the NewSpace line that adopts
    them back), with their -WhatIf, the -Force rule and their refusals.
#>
$ErrorActionPreference = 'Stop'
$pkgRoot = Split-Path $PSScriptRoot -Parent
$script:passed = 0
$script:failed = 0

function Assert-True($label, $cond, $detail = '') {
    if ($cond) { $script:passed++; Write-Host "  PASS  $label" -ForegroundColor Green }
    else { $script:failed++; Write-Host "  FAIL  $label$(if ($detail) { " -- $($detail.ToString().Trim())" })" -ForegroundColor Red }
}
function Assert-Equal($label, $expected, $actual, $detail = '') {
    if ("$expected" -eq "$actual") { $script:passed++; Write-Host "  PASS  $label" -ForegroundColor Green }
    else { $script:failed++; Write-Host "  FAIL  $label -- expected '$expected', got '$actual'$(if ($detail) { "`n        $($detail.ToString().Trim())" })" -ForegroundColor Red }
}

$root = Join-Path ([System.IO.Path]::GetTempPath()) ("p20-newspace-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
$pkgDir = Join-Path $root 'pkg'
$hubDir = Join-Path $root 'hub'
$logDir = Join-Path $root 'log'
$utf8 = New-Object System.Text.UTF8Encoding($false)

function New-SpaceSandbox {
    if (Test-Path $root) { Remove-Item $root -Recurse -Force }
    New-Item -ItemType Directory -Path $pkgDir, $hubDir, $logDir -Force | Out-Null
    foreach ($file in @('utilities.psm1', 'config.default.json', 'consts.json')) { Copy-Item (Join-Path $pkgRoot $file) $pkgDir -Force }
    foreach ($folder in @('Scripts', 'Config', 'Prompt20Toolkit', 'templates')) { Copy-Item (Join-Path $pkgRoot $folder) $pkgDir -Recurse -Force }
    $hubJson = @'
{
  "hub": 1,
  "spaces": [
    { "slug": "demo", "name": "Demo", "status": "local", "promptsFolder": "demo" },
    { "slug": "toolkit", "name": "Toolkit", "status": "active", "promptsFolder": "toolkit", "org": "https://github.com/johnfrog76/toolkit" },
    { "slug": "elsewhere", "name": "Elsewhere", "status": "local", "promptsFolder": "shared" }
  ]
}
'@
    [System.IO.File]::WriteAllText((Join-Path $hubDir 'hub.json'), $hubJson, $utf8)
    foreach ($f in @('demo', 'toolkit', 'shared')) { New-Item -ItemType Directory -Path (Join-Path $hubDir "$f/current") -Force | Out-Null }
    $local = [ordered]@{ quietStart = $true; promptsRoot = $hubDir; activeSpace = 'demo' }
    [System.IO.File]::WriteAllText((Join-Path $pkgDir 'config.local.json'), ($local | ConvertTo-Json -Depth 4), $utf8)
}

# gh off the PATH for every child, and -- when signed in -- a function standing in.
$ghAbsent = @'
$sep = [System.IO.Path]::PathSeparator
$env:PATH = (@($env:PATH -split [regex]::Escape([string]$sep)) | Where-Object { $_ -and -not (Test-Path (Join-Path $_ 'gh')) -and -not (Test-Path (Join-Path $_ 'gh.exe')) }) -join $sep
'@
$ghSignedIn = @'
function global:gh {
    $a = @($args)
    $global:GhCalls += @($a -join ' ')
    $global:LASTEXITCODE = 0
    if ($a[0] -eq 'auth') { return 'Logged in to github.com as tester' }
    if ($a[0] -eq 'api' -and $a[1] -eq 'user/orgs') {
        if ($env:P20_TEST_ONE_ORG) { return '[{"login":"acme"}]' }
        return '[{"login":"acme"},{"login":"widgets"}]'
    }
    if ($a[0] -eq 'api' -and $a[1] -eq 'user/repos' -and $env:P20_TEST_MANY) {
        # A long list shared with you, served a page of 100 at a time as GitHub does.
        $total = [int]$env:P20_TEST_MANY
        $page = 1
        foreach ($x in $a) { if ([string]$x -like 'page=*') { $page = [int]([string]$x).Substring(5) } }
        $from = ($page - 1) * 100 + 1
        $to = [Math]::Min($total, $page * 100)
        if ($from -gt $to) { return '[]' }
        return '[' + ((($from..$to) | ForEach-Object { '{"name":"shared-' + $_ + '","owner":{"login":"friend"},"visibility":"private","archived":false,"permissions":{"push":true,"pull":true}}' }) -join ',') + ']'
    }
    if ($a[0] -eq 'api' -and $a[1] -eq 'user/repos') {
        return '[{"name":"upstream","owner":{"login":"someone"},"visibility":"public","archived":false,"description":"Theirs","permissions":{"admin":false,"maintain":false,"push":false,"triage":false,"pull":true}},{"name":"shared-work","owner":{"login":"friend"},"visibility":"private","archived":true,"description":"","permissions":{"admin":false,"push":true,"pull":true}}]'
    }
    if ($a[0] -eq 'api') { return 'tester' }
    if ($a[0] -eq 'repo' -and $a[1] -eq 'view') {
        if ($a[2] -eq 'tester/stderr-215') { $global:LASTEXITCODE = 1; Write-Error "GraphQL: Could not resolve to a Repository with the name 'tester/stderr-215'. (repository)"; return }
        if ($a[2] -eq 'tester/ghost') { $global:LASTEXITCODE = 1; return 'GraphQL: Could not resolve to a Repository with the name tester/ghost.' }
        if ($a[2] -eq 'tester/unseen') { $global:LASTEXITCODE = 1; return 'GraphQL: Could not resolve to a Repository with the name tester/unseen.' }
        if ($a[2] -eq 'tester/juggling-engine') { return '{"visibility":"PUBLIC"}' }
        if ($a[2] -eq 'someone/upstream') { return '{"visibility":"PUBLIC","isArchived":false,"viewerPermission":"READ"}' }
        return '{"visibility":"PRIVATE"}'
    }
    if ($a[0] -eq 'repo' -and $a[1] -eq 'list' -and $a[2] -eq 'nobody') {
        # On the error stream, as the real gh writes it to stderr.
        $global:LASTEXITCODE = 1; Write-Error "GraphQL: Could not resolve to a RepositoryOwner with the login of 'nobody'."; return
    }
    if ($a[0] -eq 'repo' -and $a[1] -eq 'list' -and $a[2] -eq 'big') {
        # An owner with P20_TEST_MANY repositories, of which gh returns --limit.
        $lim = [int]$a[[array]::IndexOf($a, '--limit') + 1]
        $n = [Math]::Min([int]$env:P20_TEST_MANY, $lim)
        return '[' + (((1..$n) | ForEach-Object { '{"name":"r' + $_ + '","owner":{"login":"big"},"visibility":"PUBLIC","isArchived":false,"viewerPermission":"WRITE","description":""}' }) -join ',') + ']'
    }
    if ($a[0] -eq 'repo' -and $a[1] -eq 'list' -and $a[2] -eq 'acme') {
        return '[{"name":"site","owner":{"login":"acme"},"visibility":"PUBLIC","isArchived":false,"viewerPermission":"READ","description":""},{"name":"api","owner":{"login":"acme"},"visibility":"PRIVATE","isArchived":false,"viewerPermission":"WRITE","description":""}]'
    }
    if ($a[0] -eq 'repo' -and $a[1] -eq 'list') {
        return '[{"name":"juggling-engine","owner":{"login":"tester"},"visibility":"PUBLIC","description":"Balls in the air"},{"name":"toolkit","owner":{"login":"johnfrog76"},"visibility":"PRIVATE","description":""}]'
    }
    $global:LASTEXITCODE = 9
    return "unexpected gh call: $($a -join ' ')"
}
'@

function New-ChildPreamble([bool]$SignedIn) {
    $pkg = $pkgDir -replace "'", "''"; $hub = $hubDir -replace "'", "''"; $log = $logDir -replace "'", "''"
    $text = $ghAbsent + "`n" + @"
`$env:PSModulePath = '$pkg'
`$env:PROMPTS_ROOT = '$hub'
`$env:P20_USAGE_LOG_DIR = '$log'
Get-ChildItem Env: | Where-Object { `$_.Name -like 'TEAMS_WEBHOOK_*' } | ForEach-Object { Remove-Item "Env:\`$(`$_.Name)" -ErrorAction SilentlyContinue }
Import-Module '$pkg/Prompt20Toolkit/Prompt20Toolkit.psd1' -Force 3>`$null 6>`$null
"@
    if ($SignedIn) { $text += "`n" + $ghSignedIn }
    return $text
}

function Invoke-NewSpace {
    param([string]$Snippet, [switch]$NoGh, [string]$Exe = 'pwsh')
    $runner = Join-Path $root ("run-" + [guid]::NewGuid().ToString('N').Substring(0, 8) + ".ps1")
    [System.IO.File]::WriteAllText($runner, ((New-ChildPreamble (-not $NoGh)) + "`n" + $Snippet + "`n`"EXIT=`$LASTEXITCODE`"`n"), $utf8)
    $out = & $Exe -NoProfile -File $runner 2>&1
    Remove-Item $runner -Force -ErrorAction SilentlyContinue
    return (($out | ForEach-Object { $_.ToString() }) -join "`n")
}
function Get-Json([string]$text) {
    $line = ($text -split "`n" | Where-Object { $_.Trim().StartsWith('{') } | Select-Object -Last 1)
    if (-not $line) { return $null }
    return ($line | ConvertFrom-Json)
}
function Get-HubSpace([string]$slug) {
    $hub = Get-Content (Join-Path $hubDir 'hub.json') -Raw | ConvertFrom-Json
    return @($hub.spaces | Where-Object { $_.slug -eq $slug }) | Select-Object -First 1
}
function Get-Snapshot {
    $files = @(Get-ChildItem -LiteralPath $hubDir -Recurse -Force | Sort-Object FullName | ForEach-Object {
        if ($_.PSIsContainer) { "$($_.FullName)|dir" } else { "$($_.FullName)|$([System.IO.File]::ReadAllText($_.FullName))" }
    })
    $files += [System.IO.File]::ReadAllText((Join-Path $pkgDir 'config.local.json'))
    return ($files -join "`n")
}

Write-Host ""
Write-Host "  NewSpace -- add a Space, typed" -ForegroundColor Cyan
Write-Host "  ------------------------------" -ForegroundColor DarkGray
Write-Host ""

try {
    New-SpaceSandbox

    # -- Registration ------------------------------------------------------------------
    $map = Invoke-NewSpace "'MAP=' + (Get-P20CommandMap); tkNewSpace -Help"
    Assert-True 'NewSpace is in the command table the bridge reads' ($map -match '"NewSpace":\s*"New-P20Space"') $map
    Assert-True '-Help prints the usage from config' ($map -match 'NewSpace \[<slug>\] \[-Repo <owner/name>\]') $map
    $manifest = Get-Content (Join-Path $pkgRoot 'Prompt20Toolkit/Prompt20Toolkit.psd1') -Raw
    Assert-True 'the autoload manifest names tkNewSpace' ($manifest -match "'tkNewSpace',")

    # -- The proposals, over the shared table ---------------------------------------------------
    # FIRST, while the scratch hub declares nothing: -WhatIf proposes a slug and then refuses one
    # that is already a Space, so run after the sections below (which declare juggling-engine and
    # a Space at tester/Notes_App) two rows came back as refusals. Found at the merge.
    $table = Get-Content (Join-Path $pkgRoot 'Tests/fixtures/spaces/proposals.json') -Raw | ConvertFrom-Json
    $snippet = (@($table.rows) | ForEach-Object { "'ROW=$($_.repo)'; tkNewSpace -Repo 'tester/$($_.repo)' -WhatIf -AsJson; 'X=' + `$LASTEXITCODE" }) -join "`n"
    $p = Invoke-NewSpace $snippet
    $chunks = @($p -split 'ROW=' | Select-Object -Skip 1)
    Assert-Equal 'every row of the table ran' @($table.rows).Count $chunks.Count
    for ($i = 0; $i -lt [Math]::Min($chunks.Count, @($table.rows).Count); $i++) {
        $row = @($table.rows)[$i]
        if ($row.valid) {
            $pj = Get-Json $chunks[$i]
            Assert-Equal "proposes $($row.repo) -> $($row.slug) / $($row.name)" "$($row.slug)|$($row.name)" "$($pj.slug)|$($pj.name)" $chunks[$i]
        }
        else {
            Assert-True "refuses $($row.repo): '$($row.slug)' is not a slug" ($chunks[$i] -match 'X=2' -and $chunks[$i] -match 'does not make a slug') $chunks[$i]
        }
    }

    # -- -Repo: a GitHub Space, named from the repository --------------------------------
    $r = Invoke-NewSpace 'tkNewSpace -Repo tester/juggling-engine'
    $s = Get-HubSpace 'juggling-engine'
    Assert-True '-Repo declares the Space in hub.json' ($null -ne $s) $r
    Assert-Equal 'its name is the repository title-cased, dashes as spaces' 'Juggling Engine' $s.name
    Assert-Equal 'it is active' 'active' $s.status
    Assert-Equal 'its address is the repository' 'https://github.com/tester/juggling-engine' $s.org
    Assert-Equal 'its folder is its slug' 'juggling-engine' $s.promptsFolder
    Assert-True 'the cards folder is made, current/ and archive/' ((Test-Path (Join-Path $hubDir 'juggling-engine/current')) -and (Test-Path (Join-Path $hubDir 'juggling-engine/archive')))
    Assert-True 'gh signed in: the repository is checked and PUBLIC said' ($r -match 'PUBLIC') $r
    Assert-True 'the write went through Config (its own change lines)' ($r -match 'spaces\.juggling-engine\.org') $r
    $lines = @($r -split "`n" | Where-Object { $_.Trim() -and $_ -notmatch '^EXIT=' })
    Assert-Equal 'the last line is the SwitchSpace that goes into it' 'tkSwitchSpace juggling-engine' $lines[-1].Trim()
    $localAfter = Get-Content (Join-Path $pkgDir 'config.local.json') -Raw | ConvertFrom-Json
    Assert-Equal 'and it did not switch' 'demo' $localAfter.activeSpace
    $j = Get-Json (Invoke-NewSpace "tkNewSpace jug -Repo https://github.com/tester/Notes_App.git -Name 'My notes' -AsJson")
    Assert-Equal 'a pasted address reads as owner/name' 'tester/Notes_App' $j.repo
    Assert-Equal '<slug> and -Name are kept as given' 'jug|My notes' "$($j.slug)|$($j.name)"
    Assert-Equal '-AsJson says the visibility' 'PRIVATE' $j.visibility

    # -- <slug> -Address: Azure DevOps ---------------------------------------------------
    $a = Invoke-NewSpace 'tkNewSpace acme -Address https://dev.azure.com/acme'
    $s = Get-HubSpace 'acme'
    Assert-Equal '-Address declares an Azure DevOps Space' 'https://dev.azure.com/acme|active|Acme' "$($s.org)|$($s.status)|$($s.name)"
    Assert-True 'and names the next step, Connect -Discover' ($a -match 'tkConnect acme -Discover' -and $a -match 'EXIT=0') $a

    # -- <slug> alone: your own cards -------------------------------------------------------
    $o = Get-Json (Invoke-NewSpace 'tkNewSpace side-notes -AsJson')
    Assert-Equal 'a slug alone is local, no tracker' 'local|none|Side Notes' "$($o.status)|$($o.tracker)|$($o.name)"
    Assert-True 'with no address' (-not (Get-HubSpace 'side-notes').org)

    # -- Adoption ----------------------------------------------------------------------------
    New-Item -ItemType Directory -Path (Join-Path $hubDir 'old-work/current'), (Join-Path $hubDir 'old-work/archive') -Force | Out-Null
    [System.IO.File]::WriteAllText((Join-Path $hubDir 'old-work/current/Task7-a-card.prompt.md'), "# Task 7`r`n", $utf8)
    [System.IO.File]::WriteAllText((Join-Path $hubDir 'old-work/current/8-another.prompt.md'), "# 8`n", $utf8)
    [System.IO.File]::WriteAllText((Join-Path $hubDir 'old-work/archive/Task3-done.prompt.md'), "# 3`n", $utf8)
    $beforeCards = (Get-ChildItem (Join-Path $hubDir 'old-work') -Recurse -File | ForEach-Object { "$($_.Name)=$([System.IO.File]::ReadAllText($_.FullName))" }) -join '|'
    $ad = Invoke-NewSpace 'tkNewSpace old-work'
    Assert-True 'an existing folder is adopted, its cards counted' ($ad -match 'adopted as it is: 3 cards \(2 current, 1 archive\)') $ad
    $afterCards = (Get-ChildItem (Join-Path $hubDir 'old-work') -Recurse -File | ForEach-Object { "$($_.Name)=$([System.IO.File]::ReadAllText($_.FullName))" }) -join '|'
    Assert-Equal 'and nothing in it is touched' $beforeCards $afterCards

    # -- -WhatIf -----------------------------------------------------------------------------
    $before = Get-Snapshot
    $w = Invoke-NewSpace 'tkNewSpace -Repo tester/fresh-thing -WhatIf'
    Assert-True '-WhatIf names every key it would write through Config' (
        $w -match '\[WhatIf\] tkConfig -Set spaces\.fresh-thing\.name=Fresh Thing -Hub' -and
        $w -match '\[WhatIf\] tkConfig -Set spaces\.fresh-thing\.status=active -Hub' -and
        $w -match '\[WhatIf\] tkConfig -Set spaces\.fresh-thing\.org=https://github\.com/tester/fresh-thing -Hub') $w
    Assert-True 'and the folder it would make' ($w -match '\[WhatIf\] make .*fresh-thing') $w
    Assert-Equal '-WhatIf writes nothing' $before (Get-Snapshot)

    # -- Refusals: exit 2, one sentence, nothing written -------------------------------------
    $refusals = @(
        @{ Label = 'no arguments names the three forms'; Snippet = 'tkNewSpace'; Want = 'for your own cards' },
        @{ Label = 'a slug already declared'; Snippet = 'tkNewSpace demo'; Want = "already a Space 'demo'" },
        @{ Label = 'a slug that is not a slug'; Snippet = 'tkNewSpace Bad_Slug'; Want = "'Bad_Slug' is not a slug" },
        @{ Label = '-Repo that is not owner/name'; Snippet = 'tkNewSpace -Repo not-a-repo'; Want = 'is not owner/name' },
        @{ Label = '-Repo and -Address together'; Snippet = 'tkNewSpace x -Repo a/b -Address https://dev.azure.com/a'; Want = 'not both' },
        @{ Label = 'a repository that is already a Space, named'; Snippet = 'tkNewSpace -Repo johnfrog76/TOOLKIT'; Want = 'already a Space: Toolkit \(toolkit\)' },
        @{ Label = 'an address with no slug'; Snippet = 'tkNewSpace -Address https://dev.azure.com/acme2'; Want = 'needs a slug' },
        @{ Label = 'a folder another Space keeps'; Snippet = 'tkNewSpace shared'; Want = "already Elsewhere \(elsewhere\)'s cards" },
        @{ Label = "the hub's own folder name"; Snippet = 'tkNewSpace growth'; Want = "the hub's own folder" },
        @{ Label = "the Azure demo's old slug"; Snippet = 'tkNewSpace test'; Want = 'already a Space' }
    )
    foreach ($case in $refusals) {
        $before = Get-Snapshot
        $out = Invoke-NewSpace $case.Snippet
        $errors = @([regex]::Matches($out, 'Error:')).Count
        Assert-True "refused: $($case.Label)" ($out -match 'EXIT=2' -and $errors -eq 1 -and $out -match $case.Want) $out
        Assert-Equal "  and nothing written ($($case.Label))" $before (Get-Snapshot)
    }

    # -- gh: asked, never required -----------------------------------------------------------
    $ng = Invoke-NewSpace 'tkNewSpace -Repo tester/no-gh-here' -NoGh
    Assert-True 'without gh the Space is added and the repository said not checked' ($ng -match 'EXIT=0' -and $ng -match 'not checked: gh is not installed') $ng
    Assert-Equal '  and it is active all the same' 'active' (Get-HubSpace 'no-gh-here').status
    $gf = Get-Json (Invoke-NewSpace 'tkNewSpace -Repo tester/ghost -AsJson')
    Assert-True 'a check gh cannot answer adds the Space anyway and says why' ((-not $gf.checked) -and $gf.note -match 'Could not resolve' -and $null -ne (Get-HubSpace 'ghost'))

    # -- -Discover ---------------------------------------------------------------------------
    $d = Get-Json (Invoke-NewSpace 'tkNewSpace -Discover -AsJson')
    Assert-True '-Discover lists your repositories' ($d.available -and @($d.repos).Count -eq 2)
    $held = @($d.repos | Where-Object { $_.repo -eq 'johnfrog76/toolkit' })[0]
    Assert-Equal 'and marks the one that is already a Space' 'toolkit' $held.space
    $mine = @($d.repos | Where-Object { $_.repo -eq 'tester/juggling-engine' })[0]
    Assert-Equal 'with the line that adds each' 'tkNewSpace -Repo tester/juggling-engine' $mine.command
    $dn = Invoke-NewSpace 'tkNewSpace -Discover' -NoGh
    Assert-True '-Discover without gh says what is unavailable and why' ($dn -match 'EXIT=2' -and $dn -match 'gh, the GitHub CLI, is not installed') $dn
    $dj = Get-Json (Invoke-NewSpace 'tkNewSpace -Discover -AsJson' -NoGh)
    Assert-True '  and -AsJson answers available false, for the dialog' ((-not $dj.available) -and $dj.reason -match 'not installed')

    # -- RetireSpace and RemoveSpace: the other end of a Space's life -----------------
    Write-Host ""
    Write-Host "  RetireSpace and RemoveSpace" -ForegroundColor Cyan
    $reg = Invoke-NewSpace "'MAP=' + (Get-P20CommandMap); tkRetireSpace -Help; tkRemoveSpace -Help"
    Assert-True 'RetireSpace and RemoveSpace are in the command table the bridge reads' ($reg -match '"RetireSpace":\s*"Invoke-P20RetireSpace"' -and $reg -match '"RemoveSpace":\s*"Remove-P20Space"') $reg
    Assert-True '-Help prints each usage from config' ($reg -match 'RetireSpace <slug> \[-WhatIf\]' -and $reg -match 'RemoveSpace <slug> \[-Force\] \[-WhatIf\]') $reg
    Assert-True 'the autoload manifest names both' ($manifest -match "'tkRetireSpace'," -and $manifest -match "'tkRemoveSpace',")

    # Retire: status archive, through Config; the Space stays declared, its folder untouched.
    $before = Get-Snapshot
    $rw = Invoke-NewSpace 'tkRetireSpace acme -WhatIf'
    Assert-True 'RetireSpace -WhatIf names the Config line and the folder that stays' ($rw -match '\[WhatIf\] tkConfig -Set spaces\.acme\.status=archive -Hub' -and $rw -match 'folder stays as it is') $rw
    Assert-Equal '  and writes nothing' $before (Get-Snapshot)
    $rt = Invoke-NewSpace 'tkRetireSpace acme'
    Assert-True 'RetireSpace exits 0, through Config' ($rt -match 'EXIT=0' -and $rt -match 'spaces\.acme\.status\s+active -> archive') $rt
    Assert-Equal '  the Space is archived in hub.json' 'archive' (Get-HubSpace 'acme').status
    Assert-Equal '  and still declared, with its address' 'https://dev.azure.com/acme' (Get-HubSpace 'acme').org
    Assert-True '  and the line that brings it back is named' ($rt -match 'tkConfig -Set spaces\.acme\.status=active -Hub') $rt
    $before = Get-Snapshot
    $ra = Invoke-NewSpace 'tkRetireSpace acme'
    Assert-True 'a Space already retired is said, exit 0' ($ra -match 'already retired' -and $ra -match 'EXIT=0') $ra
    Assert-Equal '  and nothing is written' $before (Get-Snapshot)
    $rl = Invoke-NewSpace 'tkConfig -Set spaces.side-notes.status=active -Local | Out-Null; tkRetireSpace side-notes'
    $localNow = Get-Content (Join-Path $pkgDir 'config.local.json') -Raw | ConvertFrom-Json
    Assert-True "a status this machine overrides is unset with it, so the retire holds here" (
        $rl -match 'EXIT=0' -and (Get-HubSpace 'side-notes').status -eq 'archive' -and
        -not ($localNow.spaces.'side-notes' -and $localNow.spaces.'side-notes'.PSObject.Properties['status'])) $rl

    # Remove: the entry leaves hub.json; the folder stays exactly as it is.
    $before = Get-Snapshot
    $mw = Invoke-NewSpace 'tkRemoveSpace old-work -WhatIf'
    Assert-True 'RemoveSpace -WhatIf names the key that would go and the folder that would stay' (
        $mw -match '\[WhatIf\] tkConfig -Unset spaces\.old-work -Hub' -and $mw -match 'folder stays as it is: .*old-work -- 3 cards \(2 current, 1 archive\)') $mw
    Assert-True '  and that cards in current/ ask first' ($mw -match '2 cards in current/') $mw
    Assert-Equal '  and writes nothing' $before (Get-Snapshot)
    $mq = Invoke-NewSpace "`$env:TOOLKIT_QUIET_STARTUP = '1'; try { tkRemoveSpace old-work } catch { }"
    Assert-True 'cards in current/ and a caller that cannot answer: refused without -Force, one sentence' (
        $mq -match 'needs a yes this caller cannot give' -and @([regex]::Matches($mq, 'Error:')).Count -eq 1 -and $mq -match '-Force') $mq
    Assert-Equal '  and nothing is written' $before (Get-Snapshot)
    $mf = Invoke-NewSpace 'tkRemoveSpace old-work -Force'
    Assert-True 'RemoveSpace -Force exits 0, through Config' ($mf -match 'EXIT=0' -and $mf -match 'spaces\.old-work\s+declared') $mf
    Assert-True '  the Space leaves hub.json' ($null -eq (Get-HubSpace 'old-work'))
    $afterRemove = (Get-ChildItem (Join-Path $hubDir 'old-work') -Recurse -File | ForEach-Object { "$($_.Name)=$([System.IO.File]::ReadAllText($_.FullName))" }) -join '|'
    Assert-Equal '  REMOVING NEVER DELETES A CARD: the folder and every card in it as they were' $beforeCards $afterRemove
    Assert-True '  the output says where the folder is and how many cards it holds' ($mf -match 'Its folder stays, untouched: .*old-work -- 3 cards') $mf
    Assert-True '  and names the line that brings them back' ($mf -match 'tkNewSpace old-work') $mf
    $back = Invoke-NewSpace 'tkNewSpace old-work'
    Assert-True 'adding a Space with the same folder brings the cards back' ($back -match 'adopted as it is: 3 cards \(2 current, 1 archive\)') $back
    $ml = Invoke-NewSpace 'tkConfig -Set spaces.jug.tenant=contoso -Local | Out-Null; tkRemoveSpace jug'
    $localNow = Get-Content (Join-Path $pkgDir 'config.local.json') -Raw | ConvertFrom-Json
    Assert-True "this machine's patch for the slug goes with it" (
        $ml -match 'EXIT=0' -and $null -eq (Get-HubSpace 'jug') -and -not ($localNow.spaces -and $localNow.spaces.PSObject.Properties['jug'])) $ml

    $lifeRefusals = @(
        @{ Label = 'RetireSpace with no slug'; Snippet = 'tkRetireSpace'; Want = 'Say which Space to retire' },
        @{ Label = 'RetireSpace of a slug nobody declared'; Snippet = 'tkRetireSpace nope'; Want = "'nope' is not a Space" },
        @{ Label = 'RemoveSpace with no slug'; Snippet = 'tkRemoveSpace'; Want = 'Say which Space to remove' },
        @{ Label = 'RemoveSpace of a slug nobody declared'; Snippet = 'tkRemoveSpace nope'; Want = "'nope' is not a Space" },
        @{ Label = 'RemoveSpace of the Space you are in'; Snippet = 'tkRemoveSpace demo'; Want = 'the Space you are in; switch' },
        @{ Label = 'RemoveSpace of a Space config.default.json ships'; Snippet = 'tkRemoveSpace azure-demo'; Want = 'ships in config\.default\.json' }
    )
    foreach ($case in $lifeRefusals) {
        $before = Get-Snapshot
        $out = Invoke-NewSpace $case.Snippet
        $errors = @([regex]::Matches($out, 'Error:')).Count
        Assert-True "refused: $($case.Label)" ($out -match 'EXIT=2' -and $errors -eq 1 -and $out -match $case.Want) $out
        Assert-Equal "  and nothing written ($($case.Label))" $before (Get-Snapshot)
    }

    # -- -Discover -Owner: beyond the repositories you own ------------------------------
    $ow = @($d.owners)
    Assert-Equal '-Discover offers the owners: you, your organisations, then collaborator' 'tester:user|acme:organization|widgets:organization|collaborator:collaborator' (($ow | ForEach-Object { "$($_.value):$($_.kind)" }) -join '|')
    Assert-Equal '  and says whose list it is' 'tester' $d.owner
    # 5.1 reads a JSON list as ONE object: a two-org and a one-org answer, item by item.
    $one = Get-Json (Invoke-NewSpace "`$env:P20_TEST_ONE_ORG = '1'; tkNewSpace -Discover -AsJson")
    Assert-Equal '  a one-organisation answer is one owner, not a list held in one' 'tester|acme|collaborator' ((@($one.owners) | ForEach-Object { $_.value }) -join '|')
    $og = Invoke-NewSpace "tkNewSpace -Discover -Owner acme -AsJson; 'CALLS=' + (`$global:GhCalls -join '|')"
    $oj = Get-Json $og
    Assert-Equal '-Owner acme lists the organisation''s repositories, two items' 'acme/api|acme/site' ((@($oj.repos) | ForEach-Object { $_.repo }) -join '|') $og
    Assert-Equal '  and names the owner it listed' 'acme' $oj.owner
    $site = @($oj.repos | Where-Object { $_.repo -eq 'acme/site' })[0]
    $api = @($oj.repos | Where-Object { $_.repo -eq 'acme/api' })[0]
    Assert-Equal '  a repository you can only read is marked read-only, Public said' 'READ|True|PUBLIC' "$($site.viewerPermission)|$($site.readOnly)|$($site.visibility)"
    Assert-Equal '  one you can write is not' 'WRITE|False' "$($api.viewerPermission)|$($api.readOnly)"
    Assert-True '  through gh repo list <owner>' ($og -match 'CALLS=.*repo list acme --json') $og
    $cg = Invoke-NewSpace "tkNewSpace -Discover -Owner collaborator -AsJson; 'CALLS=' + (`$global:GhCalls -join '|')"
    $cj = Get-Json $cg
    $up = @($cj.repos | Where-Object { $_.repo -eq 'someone/upstream' })[0]
    $sw = @($cj.repos | Where-Object { $_.repo -eq 'friend/shared-work' })[0]
    Assert-Equal '-Owner collaborator lists the repositories shared with you, two items' 2 @($cj.repos).Count $cg
    Assert-Equal '  GitHub''s REST shape read the same way: pull only is read-only, Public' 'READ|True|PUBLIC|False' "$($up.viewerPermission)|$($up.readOnly)|$($up.visibility)|$($up.isArchived)"
    Assert-Equal '  push is write, archived carried' 'WRITE|False|PRIVATE|True' "$($sw.viewerPermission)|$($sw.readOnly)|$($sw.visibility)|$($sw.isArchived)"
    Assert-True '  the affiliation travels as an -f field' ($cg -match 'api user/repos -X GET -f affiliation=collaborator -f per_page=100') $cg
    $calls = @($cg -split "`n" | Where-Object { $_ -like 'CALLS=*' }) + @($og -split "`n" | Where-Object { $_ -like 'CALLS=*' })
    Assert-True '  and no & reaches a gh argument (cmd.exe would split it)' ($calls.Count -eq 2 -and -not (($calls -join '') -match '&')) ($calls -join "`n")
    $ot = Invoke-NewSpace 'tkNewSpace -Discover -Owner acme'
    Assert-True '-Discover -Owner in the terminal marks READ-ONLY and names the owners' ($ot -match 'acme/site\s+public\s+READ-ONLY tkNewSpace -Repo acme/site' -and $ot -match 'Owners: tester \(yours\), acme, widgets, collaborator') $ot
    Assert-True '  and a repository you can write carries no mark' ($ot -match 'acme/api\s+private\s+tkNewSpace -Repo acme/api') $ot
    $rv = Get-Json (Invoke-NewSpace 'tkNewSpace -Repo someone/upstream -WhatIf -AsJson')
    Assert-Equal '-Repo reads the permission with the visibility: someone else''s public repository' 'PUBLIC|READ|True' "$($rv.visibility)|$($rv.viewerPermission)|$($rv.readOnly)"
    $rt = Invoke-NewSpace 'tkNewSpace -Repo someone/upstream -WhatIf'
    Assert-True '  and the terminal says PUBLIC READ-ONLY' ($rt -match 'github\.com/someone/upstream -- PUBLIC READ-ONLY') $rt
    $ownerRefusals = @(
        @{ Label = 'an owner gh cannot see'; Snippet = 'tkNewSpace -Discover -Owner nobody'; Want = "The repositories of 'nobody' cannot be listed: gh answered 'GraphQL: Could not resolve" },
        @{ Label = 'an owner that is not a name'; Snippet = "tkNewSpace -Discover -Owner 'a&b'"; Want = "'a&b' is not an owner" },
        @{ Label = '-Owner without -Discover'; Snippet = 'tkNewSpace -Owner acme'; Want = 'it does not add a Space' }
    )
    foreach ($case in $ownerRefusals) {
        $before = Get-Snapshot
        $out = Invoke-NewSpace $case.Snippet
        $errors = @([regex]::Matches($out, 'Error:')).Count
        $hints = @([regex]::Matches($out, 'Hint:')).Count
        Assert-True "refused: $($case.Label), exit 2, one Error: and one Hint:" ($out -match 'EXIT=2' -and $errors -eq 1 -and $hints -eq 1 -and $out.Contains($case.Want)) $out
        Assert-Equal "  and nothing written ($($case.Label))" $before (Get-Snapshot)
    }
    $nj = Get-Json (Invoke-NewSpace 'tkNewSpace -Discover -Owner nobody -AsJson')
    Assert-True '  -AsJson: an owner gh cannot see is available false, with the owners still offered' ((-not $nj.available) -and $nj.reason -match "'nobody' cannot be listed" -and @($nj.owners).Count -eq 4)

    # -- -Discover -Repo: one typed repository's visibility, read before it is added -------
    $dr = Invoke-NewSpace "tkNewSpace -Discover -Repo tester/juggling-engine -AsJson; 'CALLS=' + (`$global:GhCalls -join '|')"
    $drj = Get-Json $dr
    $drRow = @($drj.repos)[0]
    Assert-Equal '-Discover -Repo is one row, its visibility read first' '1|tester/juggling-engine|PUBLIC|juggling-engine|Juggling Engine' "$(@($drj.repos).Count)|$($drRow.repo)|$($drRow.visibility)|$($drRow.proposedSlug)|$($drRow.proposedName)" $dr
    Assert-True '  through gh repo view, the one read the Add makes, and no owners list asked' ($dr -match 'CALLS=.*repo view tester/juggling-engine --json name,owner,visibility' -and $dr -notmatch 'user/orgs') $dr
    Assert-Equal '  with the line that adds it and no note' 'tkNewSpace -Repo tester/juggling-engine|' "$($drRow.command)|$($drRow.note)"
    $dg = Get-Json (Invoke-NewSpace 'tkNewSpace -Discover -Repo tester/unseen -AsJson')
    $dgRow = @($dg.repos)[0]
    Assert-True 'a repository gh cannot see is a row all the same: visibility UNKNOWN, "not visible to this login" with gh''s line' (
        $dg.available -and $dgRow.visibility -eq 'UNKNOWN' -and $dgRow.note -match '^not visible to this login: gh answered' -and $dgRow.note -match 'Could not resolve' -and $dgRow.proposedSlug -eq 'unseen') ($dg | ConvertTo-Json -Depth 4)
    $dgt = Invoke-NewSpace 'tkNewSpace -Discover -Repo https://github.com/tester/unseen'
    Assert-True '  in the terminal: said plainly, still addable, exit 0' ($dgt -match 'EXIT=0' -and $dgt -match 'unknown\s+tkNewSpace -Repo tester/unseen' -and $dgt -match 'not visible to this login' -and $dgt -match 'can still be added' -and $dgt -notmatch 'Error:') $dgt
    $dh = Get-Json (Invoke-NewSpace 'tkNewSpace -Discover -Repo johnfrog76/toolkit -AsJson')
    Assert-Equal '  a repository that is already a Space is marked on its row' 'toolkit' @($dh.repos)[0].space
    $dng = Get-Json (Invoke-NewSpace 'tkNewSpace -Discover -Repo tester/x -AsJson' -NoGh)
    Assert-True '  without gh: available false, with the reason' ((-not $dng.available) -and $dng.reason -match 'tester/x cannot be read: gh, the GitHub CLI, is not installed')
    # The proposals over the shared table, as -Discover -Repo proposes them (the row the dialog
    # shows for a typed owner/name): the same slug and name for every row, valid or not.
    $tsnip = (@($table.rows) | ForEach-Object { "'ROW=$($_.repo)'; tkNewSpace -Discover -Repo 'tester/$($_.repo)' -AsJson" }) -join "`n"
    $tchunks = @((Invoke-NewSpace $tsnip) -split 'ROW=' | Select-Object -Skip 1)
    for ($i = 0; $i -lt [Math]::Min($tchunks.Count, @($table.rows).Count); $i++) {
        $row = @($table.rows)[$i]
        $tj = Get-Json $tchunks[$i]
        Assert-Equal "-Discover -Repo proposes $($row.repo) -> $($row.slug) / $($row.name)" "$($row.slug)|$($row.name)" "$(@($tj.repos)[0].proposedSlug)|$(@($tj.repos)[0].proposedName)" $tchunks[$i]
    }
    $gfn = Get-Json (Invoke-NewSpace 'tkNewSpace -Repo tester/unseen -WhatIf -AsJson')
    Assert-True 'the Add says a repository gh cannot see is not visible to this login, not "not checked"' ((-not $gfn.checked) -and $gfn.note -match '^not visible to this login: gh answered' -and $gfn.note -notmatch 'not checked')
    $discoverRefusals = @(
        @{ Label = '-Discover with -Repo and -Owner'; Snippet = 'tkNewSpace -Discover -Repo a/b -Owner acme'; Want = 'not both: give -Owner or -Repo' },
        @{ Label = '-Discover -Repo that is not owner/name'; Snippet = 'tkNewSpace -Discover -Repo not-a-repo'; Want = "'not-a-repo' is not owner/name" }
    )
    foreach ($case in $discoverRefusals) {
        $before = Get-Snapshot
        $out = Invoke-NewSpace $case.Snippet
        $errors = @([regex]::Matches($out, 'Error:')).Count
        Assert-True "refused: $($case.Label), exit 2, one Error:" ($out -match 'EXIT=2' -and $errors -eq 1 -and $out.Contains($case.Want)) $out
        Assert-Equal "  and nothing written ($($case.Label))" $before (Get-Snapshot)
    }

    # -- Paging: an owner's list read past 200, to the ceiling, and said past it ------------
    $p250 = Invoke-NewSpace "`$env:P20_TEST_MANY = '250'; tkNewSpace -Discover -Owner big -AsJson; 'CALLS=' + (`$global:GhCalls -join '|')"
    $p250j = Get-Json $p250
    Assert-Equal 'an owner of 250 repositories lists all 250, nothing said past it' '250|False|1000' "$(@($p250j.repos).Count)|$($p250j.more)|$($p250j.ceiling)" $p250
    Assert-True '  gh repo list asked for one past the ceiling' ($p250 -match 'CALLS=.*repo list big --json \S+ --limit 1001') $p250
    $p1200 = Get-Json (Invoke-NewSpace "`$env:P20_TEST_MANY = '1200'; tkNewSpace -Discover -Owner big -AsJson")
    Assert-Equal 'an owner of 1200 lists the first 1000 and says there are more' '1000|True' "$(@($p1200.repos).Count)|$($p1200.more)"
    $p1200t = Invoke-NewSpace "`$env:P20_TEST_MANY = '1200'; tkNewSpace -Discover -Owner big"
    Assert-True '  and the terminal says so, with the line for one past them' ($p1200t -match ': 1000 \(the first 1000\)' -and $p1200t -match 'The first 1000 are listed and there are more' -and $p1200t -match 'tkNewSpace -Discover -Repo <owner>/<name>') $p1200t
    $c250 = Invoke-NewSpace "`$env:P20_TEST_MANY = '250'; tkNewSpace -Discover -Owner collaborator -AsJson; 'CALLS=' + (`$global:GhCalls -join '|')"
    $c250j = Get-Json $c250
    $c250calls = @((@($c250 -split "`n" | Where-Object { $_ -like 'CALLS=*' })[0] -replace '^CALLS=', '') -split '\|' | Where-Object { $_ -like 'api user/repos*' })
    Assert-Equal '250 shared with you: every one, read a page of 100 at a time (three pages)' '250|False|3' "$(@($c250j.repos).Count)|$($c250j.more)|$($c250calls.Count)" $c250
    Assert-True '  each page an -f field, and no & in any gh argument' ($c250calls[2] -eq 'api user/repos -X GET -f affiliation=collaborator -f per_page=100 -f page=3' -and -not (($c250calls -join '') -match '&')) ($c250calls -join "`n")
    $c1250 = Invoke-NewSpace "`$env:P20_TEST_MANY = '1250'; tkNewSpace -Discover -Owner collaborator -AsJson; 'CALLS=' + (`$global:GhCalls -join '|')"
    $c1250j = Get-Json $c1250
    $c1250calls = @((@($c1250 -split "`n" | Where-Object { $_ -like 'CALLS=*' })[0] -replace '^CALLS=', '') -split '\|' | Where-Object { $_ -like 'api user/repos*' })
    Assert-Equal '1250 shared with you: the first 1000, more said, and reading stops one page past the ceiling' '1000|True|11' "$(@($c1250j.repos).Count)|$($c1250j.more)|$($c1250calls.Count)"

    # The same lists read by Windows PowerShell 5.1 itself, where it is on this machine:
    # the shape that broke is 5.1's, and a pwsh child cannot show it.
    if (Get-Command powershell.exe -ErrorAction SilentlyContinue) {
        $w1 = Get-Json (Invoke-NewSpace 'tkNewSpace -Discover -Owner acme -AsJson' -Exe 'powershell.exe')
        Assert-Equal '5.1: -Owner acme is two repositories, not one holding the list' 'acme/api|acme/site' ((@($w1.repos) | ForEach-Object { $_.repo }) -join '|')
        $w2 = Get-Json (Invoke-NewSpace 'tkNewSpace -Discover -Owner collaborator -AsJson' -Exe 'powershell.exe')
        Assert-Equal '5.1: -Owner collaborator is two repositories' 'friend/shared-work|someone/upstream' ((@($w2.repos) | ForEach-Object { $_.repo }) -join '|')
        $w3 = Get-Json (Invoke-NewSpace "`$env:P20_TEST_ONE_ORG = '1'; tkNewSpace -Discover -AsJson" -Exe 'powershell.exe')
        Assert-Equal '5.1: a one-organisation answer is one owner' 'tester|acme|collaborator' ((@($w3.owners) | ForEach-Object { $_.value }) -join '|')
        # A repository gh cannot see answers on the error stream with exit 1. Under 5.1 and
        # 'Stop' that threw gh's sentence through the generic error block; it is "not visible to
        # this login", exit 0.
        $before215 = Get-Snapshot
        $w4 = Invoke-NewSpace 'tkNewSpace -Repo tester/stderr-215 -WhatIf' -Exe 'powershell.exe'
        Assert-True '5.1: -Repo a repository gh cannot see on stderr is "not visible to this login", exit 0, no Error:' ($w4 -match 'EXIT=0' -and $w4 -match 'the repository was not visible to this login: gh answered' -and $w4 -match 'Could not resolve' -and $w4 -notmatch 'Error:') $w4
        Assert-Equal '5.1:   and nothing written' $before215 (Get-Snapshot)
        $w5 = Invoke-NewSpace 'tkNewSpace -Discover -Repo tester/stderr-215' -Exe 'powershell.exe'
        Assert-True '5.1: -Discover -Repo of a repository gh cannot see on stderr is a row, exit 0, no Error:' ($w5 -match 'EXIT=0' -and $w5 -match 'not visible to this login: gh answered' -and $w5 -notmatch 'Error:') $w5
        $w6 = Get-Json (Invoke-NewSpace "`$env:P20_TEST_MANY = '250'; tkNewSpace -Discover -Owner collaborator -AsJson" -Exe 'powershell.exe')
        Assert-Equal '5.1: 250 shared with you, three pages, every one' 250 @($w6.repos).Count
    }

}
catch {
    Assert-True 'the cases ran to the end without a terminating error' $false $_.Exception.Message
}
finally {
    Remove-Item $root -Recurse -Force -ErrorAction SilentlyContinue
}

$total = $script:passed + $script:failed
Write-Host ""
Write-Host "  Results: $script:passed/$total passed" -ForegroundColor $(if ($script:failed -eq 0) { 'Green' } else { 'Red' })
if ($script:failed -gt 0) { exit 1 }
exit 0
