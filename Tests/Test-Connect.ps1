<#
.SYNOPSIS
    Connect -- the connect wizard's verb: four steps, each named as whose it is
    (W2, D-W12 to D-W17).
.DESCRIPTION
    Typed as the VERB in a fresh child shell against a scratch package and hub
    (AGENTS.md: a suite that runs a script directly does not test the verb).
    Holds: the report with no step; the address written through Config and
    implying active (D-W14); the grain said for each tracker (D-W17); -Projects
    for an Azure DevOps Space and refused on GitHub; -Repo for a GitHub Space
    and refused on ADO; -Sprint; discovery refused without an address; an
    unknown Space refused by name; and graduation (D-W15): the Example becomes
    a Space of your slug, its folder moved, made active. The tracker CLIs are
    stubbed absent, so the sign-in step reads "not installed" and names the
    command -- a live sign-in is a manual walk (VERIFY.md).
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

$root = Join-Path ([System.IO.Path]::GetTempPath()) ("p20-connect-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
$pkgDir = Join-Path $root 'pkg'
$hubDir = Join-Path $root 'hub'
$logDir = Join-Path $root 'log'

function New-ConnectSandbox {
    New-Item -ItemType Directory -Path $pkgDir, $hubDir, $logDir -Force | Out-Null
    foreach ($file in @('utilities.psm1', 'config.default.json', 'consts.json')) { Copy-Item (Join-Path $pkgRoot $file) $pkgDir -Force }
    Copy-Item (Join-Path $pkgRoot 'Scripts') $pkgDir -Recurse -Force
    Copy-Item (Join-Path $pkgRoot 'Config')  $pkgDir -Recurse -Force
    $hubJson = @'
{
  "hub": 1,
  "spaces": [
    { "slug": "acme", "name": "Acme", "status": "local", "promptsFolder": "acme" },
    { "slug": "shop",  "name": "Shop", "status": "local", "promptsFolder": "shop" },
    { "slug": "ready", "name": "Ready", "status": "local", "promptsFolder": "ready", "org": "https://github.com/johnfrog76/recipe-box-demo" }
  ]
}
'@
    [System.IO.File]::WriteAllText((Join-Path $hubDir 'hub.json'), $hubJson, (New-Object System.Text.UTF8Encoding($false)))
    foreach ($f in @('acme', 'shop', 'azure-demo')) { New-Item -ItemType Directory -Path (Join-Path $hubDir "$f/current") -Force | Out-Null }
    [System.IO.File]::WriteAllText((Join-Path $hubDir 'azure-demo/current/Task7-a-card-that-travels.prompt.md'), "# Task 7: a card that travels`n", (New-Object System.Text.UTF8Encoding($false)))
    $local = [ordered]@{ quietStart = $true; promptsRoot = $hubDir; activeSpace = 'acme' }
    [System.IO.File]::WriteAllText((Join-Path $pkgDir 'config.local.json'), ($local | ConvertTo-Json -Depth 4), (New-Object System.Text.UTF8Encoding($false)))
}

function New-ChildPreamble {
    $pkg = $pkgDir -replace "'", "''"; $hub = $hubDir -replace "'", "''"; $log = $logDir -replace "'", "''"
    return @"
`$env:PSModulePath = '$pkg'
`$env:PROMPTS_ROOT = '$hub'
`$env:P20_USAGE_LOG_DIR = '$log'
Get-ChildItem Env: | Where-Object { `$_.Name -like 'TEAMS_WEBHOOK_*' } | ForEach-Object { Remove-Item "Env:\`$(`$_.Name)" -ErrorAction SilentlyContinue }
# Neither tracker CLI exists in this sandbox: the sign-in step must SAY the command, never run it.
function global:az { `$global:LASTEXITCODE = 127 }
function global:gh { `$global:LASTEXITCODE = 127 }
Import-Module '$pkg/utilities.psm1' -Force -DisableNameChecking *>`$null
"@
}

function Invoke-Connect {
    param([string]$Snippet, [string]$Exe = 'pwsh')
    $runner = Join-Path $root ("run-" + [guid]::NewGuid().ToString('N').Substring(0, 8) + ".ps1")
    [System.IO.File]::WriteAllText($runner, ((New-ChildPreamble) + "`n" + $Snippet + "`n; `"EXIT=`$LASTEXITCODE`"`n"), (New-Object System.Text.UTF8Encoding($false)))
    $out = & $Exe -NoProfile -File $runner 2>&1
    return (($out | ForEach-Object { $_.ToString() }) -join "`n")
}
function Get-Json([string]$text) {
    $line = ($text -split "`n" | Where-Object { $_.Trim().StartsWith('{') } | Select-Object -Last 1)
    if (-not $line) { return $null }
    return ($line | ConvertFrom-Json)
}
function Get-Hub { return (Get-Content (Join-Path $hubDir 'hub.json') -Raw | ConvertFrom-Json) }
function Get-HubSpace([string]$slug) { return @((Get-Hub).spaces | Where-Object { $_.slug -eq $slug }) | Select-Object -First 1 }

Write-Host ""
Write-Host "  Connect -- the wizard's verb, typed" -ForegroundColor Cyan
Write-Host "  ----------------------------------" -ForegroundColor DarkGray
Write-Host ""

try {
    New-ConnectSandbox

    # -- The report, before anything -------------------------------------------
    $r = Get-Json (Invoke-Connect 'tkConnect acme -AsJson')
    Assert-True 'the verb answers JSON for a Space with no address' ($null -ne $r)
    Assert-Equal 'no address: the grain is your cards alone' 'your cards alone -- no tracker' $r.grain
    Assert-Equal 'and the tracker is none' 'none' $r.tracker
    Assert-True 'step 1 is not done' (-not $r.steps.address.done)
    Assert-True 'and the Space is the active one' ([bool]$r.active)
    $text = Invoke-Connect 'tkConnect acme'
    Assert-True 'the text report says the grain and how to connect' ($text -match 'your cards alone' -and $text -match 'tkConnect acme -Address')

    # -- Unknown Space ---------------------------------------------------------
    $u = Invoke-Connect 'tkConnect nowhere'
    Assert-True 'an unknown Space is refused by name, with the Spaces it knows' ($u -match "No Space 'nowhere'" -and $u -match 'acme' -and $u -match 'EXIT=2') $u

    # -- 1. The address, written through Config; an address implies active (D-W14)
    $a = Get-Json (Invoke-Connect "tkConnect acme -Address https://dev.azure.com/acme-org -AsJson")
    Assert-Equal 'the address is written' 'https://dev.azure.com/acme-org' (Get-HubSpace 'acme').org
    Assert-Equal 'and the Space is active now -- no status step' 'active' (Get-HubSpace 'acme').status
    Assert-Equal 'the tracker is Azure DevOps' 'ado' $a.tracker
    Assert-Equal 'and the grain is an organisation (D-W17)' 'an Azure DevOps organisation, projects inside it' $a.grain
    Assert-Equal 'step 2 names the tool' 'az' $a.steps.signIn.tool
    Assert-True 'step 2 says the command and is not done (the sandbox az answers nothing)' ($a.steps.signIn.command -eq 'az login' -and -not $a.steps.signIn.done)
    # A Space that SHIPS with an address and stays local -- the GitHub demo --
    # has the address and not the step: saving the same address connects it.
    $rd = Get-Json (Invoke-Connect 'tkConnect ready -AsJson')
    Assert-Equal 'a local Space with an address is still GitHub' 'github' $rd.tracker
    Assert-True 'but step 1 is not done while it is local' (-not $rd.steps.address.done)
    $rdText = Invoke-Connect 'tkConnect ready'
    Assert-True 'and the text says it is local until connected, with the line that connects it' ($rdText -match 'local until you connect it' -and $rdText -match 'tkConnect ready -Address https://github.com/johnfrog76/recipe-box-demo') $rdText
    $rc = Get-Json (Invoke-Connect 'tkConnect ready -Address https://github.com/johnfrog76/recipe-box-demo -AsJson')
    Assert-Equal 'saving the same address makes it active' 'active' (Get-HubSpace 'ready').status
    Assert-True 'and step 1 is done' ([bool]$rc.steps.address.done)
    $bad = Invoke-Connect "tkConnect acme -Address not-an-address"
    Assert-True 'a non-address is refused with the two shapes' ($bad -match 'not an address' -and $bad -match 'dev.azure.com' -and $bad -match 'EXIT=2') $bad

    # -- 3. Projects on an ADO Space; refused on GitHub -------------------------
    $p = Get-Json (Invoke-Connect "tkConnect acme -Projects 'Alpha/alpha-repo; Beta' -AsJson")
    Assert-Equal 'projects are written through Config' 2 @((Get-HubSpace 'acme').projects).Count
    Assert-Equal 'with their repo' 'alpha-repo' @((Get-HubSpace 'acme').projects)[0].repo
    Assert-True 'and the report says step 3 is done' ([bool]$p.steps.projects.done)
    $d = Invoke-Connect 'tkConnect shop -Discover'
    Assert-True 'discovery without an address is refused, naming step 1' ($d -match 'no address yet' -and $d -match 'tkConnect shop -Address' -and $d -match 'EXIT=2') $d
    $g = Get-Json (Invoke-Connect "tkConnect shop -Address https://github.com/johnfrog76 -AsJson")
    Assert-Equal 'an owner address is GitHub' 'github' $g.tracker
    Assert-True 'and the grain says pick the one repo' ($g.grain -match 'pick the one repo')
    $pg = Invoke-Connect "tkConnect shop -Projects 'x/y'"
    Assert-True 'a projects list on a GitHub Space is refused, pointing at -Repo' ($pg -match 'one repo, not a list' -and $pg -match '-Repo' -and $pg -match 'EXIT=2') $pg
    $rp = Get-Json (Invoke-Connect "tkConnect shop -Repo johnfrog76/toolkit -AsJson")
    Assert-Equal '-Repo writes the address repo-grained' 'https://github.com/johnfrog76/toolkit' (Get-HubSpace 'shop').org
    Assert-Equal 'and the grain is one GitHub repo' 'one GitHub repo' $rp.grain
    Assert-Equal 'step 2 names gh' 'gh auth login' $rp.steps.signIn.command
    $ra = Invoke-Connect "tkConnect acme -Repo a/b"
    Assert-True '-Repo on an ADO Space is refused, pointing at -Projects' ($ra -match 'Azure DevOps organisation' -and $ra -match '-Projects' -and $ra -match 'EXIT=2') $ra
    $dg = Invoke-Connect 'tkConnect shop -Discover'
    Assert-True 'discovery before the sign-in is refused, naming the command you run yourself' ($dg -match 'signed in to gh' -and $dg -match 'gh auth login' -and $dg -match 'EXIT=2') $dg

    # -- discovery reads gh's JSON list through a variable, so 5.1 does not see one object
    $ghList = @'
function global:gh {
    $a = @($args)
    $global:LASTEXITCODE = 0
    if ($a[0] -eq 'auth') { return 'Logged in to github.com as tester' }
    if ($a[0] -eq 'api') { return 'tester' }
    if ($a[0] -eq 'repo' -and $a[1] -eq 'list') {
        if ($env:P20_TEST_ONE_REPO) { return '[{"name":"alpha","defaultBranchRef":{"name":"main"}}]' }
        return '[{"name":"alpha","defaultBranchRef":{"name":"main"}},{"name":"beta","defaultBranchRef":{"name":"trunk"}}]'
    }
    $global:LASTEXITCODE = 9
    return 'unexpected gh call'
}
'@
    $two = Get-Json (Invoke-Connect ($ghList + "`ntkConnect shop -Address https://github.com/johnfrog76 -Discover -AsJson"))
    $twoRows = @($two.steps.projects.available)
    Assert-Equal '#172: a two-repo list from gh is two items, not one holding the list' 2 $twoRows.Count
    Assert-Equal 'the first is alpha' 'alpha' $twoRows[0].name
    Assert-Equal 'the second is beta, with its own default branch' 'trunk' $twoRows[1].defaultBranch
    $oneRows = @((Get-Json (Invoke-Connect ("`$env:P20_TEST_ONE_REPO = '1'`n" + $ghList + "`ntkConnect shop -Address https://github.com/johnfrog76 -Discover -AsJson"))).steps.projects.available)
    Assert-Equal '#172: a one-repo list is still one item' 1 $oneRows.Count

    # -- gh and az answering on the ERROR stream with a non-zero code. Under Windows
    # PowerShell 5.1 and 'Stop' a redirected native stderr threw before the exit code was read,
    # so each site printed the tool's own sentence through the generic block instead of the
    # verb's refusal. One row per site, run under both hosts.
    $ghFail = @'
function global:gh {
    $a = @($args)
    $global:LASTEXITCODE = 0
    if ($a[0] -eq 'auth' -and $env:P20_TEST_SIGNED_OUT) { $global:LASTEXITCODE = 1; Write-Error 'You are not logged into any GitHub hosts.'; return }
    if ($a[0] -eq 'auth') { return 'Logged in to github.com as tester' }
    if ($a[0] -eq 'api') { return 'tester' }
    if ($a[0] -eq 'repo' -and $a[1] -eq 'list') { $global:LASTEXITCODE = 1; Write-Error 'GraphQL: Could not resolve to a RepositoryOwner with the login of nobody.'; return }
    $global:LASTEXITCODE = 9
}
function global:az {
    $a = @($args)
    $global:LASTEXITCODE = 0
    if ($a[0] -eq 'account' -and $env:P20_TEST_SIGNED_OUT) { $global:LASTEXITCODE = 1; Write-Error 'ERROR: Please run az login to setup account.'; return }
    if ($a[0] -eq 'account') { return '{"user":{"name":"me@example.com"}}' }
    if ($a[0] -eq 'devops' -and $env:P20_TEST_REPOS_FAIL) { return '{"value":[{"name":"Alpha"}]}' }
    if ($a[0] -eq 'repos') { $global:LASTEXITCODE = 1; Write-Error 'ERROR: repos unreachable.'; return }
    if ($a[0] -eq 'devops') { $global:LASTEXITCODE = 1; Write-Error 'ERROR: TF400813: The user is not authorized to access this resource.'; return }
    $global:LASTEXITCODE = 9
}
'@
    foreach ($exe in @('pwsh', 'powershell.exe')) {
        if (-not (Get-Command $exe -ErrorAction SilentlyContinue)) { continue }
        $tag = "#215, $exe"
        $gl = Invoke-Connect ($ghFail + "`ntkConnect shop -Address https://github.com/nobody -Discover") -Exe $exe
        Assert-True "${tag}: gh repo list on stderr is the stated refusal, exit 2, one Error:" ($gl -match "gh could not list nobody's repos" -and $gl -match 'EXIT=2' -and @([regex]::Matches($gl, 'Error:')).Count -eq 1 -and $gl -notmatch 'GraphQL') $gl
        $al = Invoke-Connect ($ghFail + "`ntkConnect acme -Address https://dev.azure.com/acme-org -Discover") -Exe $exe
        Assert-True "${tag}: az devops project list on stderr is the stated refusal, exit 2" ($al -match 'az could not list the projects' -and $al -match 'EXIT=2' -and @([regex]::Matches($al, 'Error:')).Count -eq 1 -and $al -notmatch 'TF400813') $al
        $ar = Get-Json (Invoke-Connect ("`$env:P20_TEST_REPOS_FAIL = '1'`n" + $ghFail + "`ntkConnect acme -Address https://dev.azure.com/acme-org -Discover -AsJson") -Exe $exe)
        Assert-True "${tag}: az repos list on stderr leaves that project with no repos, exit 0" ($null -ne $ar -and @($ar.steps.projects.available).Count -eq 1 -and @($ar.steps.projects.available)[0].name -eq 'Alpha') ($ar | Out-String)
        $sg = Invoke-Connect ("`$env:P20_TEST_SIGNED_OUT = '1'`n" + $ghFail + "`ntkConnect shop -Address https://github.com/nobody -Discover") -Exe $exe
        Assert-True "${tag}: a signed-out gh says to run gh auth login, exit 2" ($sg -match 'signed in to gh' -and $sg -match 'gh auth login' -and $sg -match 'EXIT=2' -and $sg -notmatch 'not logged into') $sg
        $sa = Invoke-Connect ("`$env:P20_TEST_SIGNED_OUT = '1'`n" + $ghFail + "`ntkConnect acme -Address https://dev.azure.com/acme-org -Discover") -Exe $exe
        Assert-True "${tag}: a signed-out az says to run az login, exit 2" ($sa -match 'signed in to az' -and $sa -match 'az login' -and $sa -match 'EXIT=2' -and $sa -notmatch 'Please run') $sa
        $si = Invoke-Connect ($ghFail + "`ntkConnect shop -AsJson") -Exe $exe
        $sj = Get-Json $si
        Assert-True "${tag}: signed in, the report names the identity" ($null -ne $sj -and $sj.steps.signIn.identity -eq 'tester') $si
    }

    # -- The helper itself: code and lines, stderr kept as text, $LASTEXITCODE preserved
    $helperPath = (Join-Path $pkgRoot 'Scripts/Invoke-TrackerRead.ps1') -replace "'", "''"
    $helperCases = @'
. '__HELPER__'
$ErrorActionPreference = 'Stop'
function global:tool215 {
    $a = @($args)
    $global:LASTEXITCODE = 0
    if ($a[0] -eq 'ok') { return 'one', 'two' }
    if ($a[0] -eq 'fail') { $global:LASTEXITCODE = 3; Write-Error 'it said no'; return }
    if ($a[0] -eq 'mixed') { 'data'; Write-Error 'warning text'; return }
}
$ok = Invoke-P20TrackerRead 'tool215' @('ok')
"OK code=$($ok.Code) lines=$($ok.Lines -join '|') out=$($ok.Out -join '|') err=$($ok.Err.Count) last=$LASTEXITCODE"
$bad = Invoke-P20TrackerRead 'tool215' @('fail')
"FAIL code=$($bad.Code) lines=$($bad.Lines -join '|') err=$($bad.Err -join '|') out=$($bad.Out.Count) last=$LASTEXITCODE"
$mix = Invoke-P20TrackerRead 'tool215' @('mixed')
"MIX out=$($mix.Out -join '|') err=$($mix.Err -join '|')"
"PREF=$ErrorActionPreference"
'@.Replace('__HELPER__', $helperPath)
    foreach ($exe in @('pwsh', 'powershell.exe')) {
        if (-not (Get-Command $exe -ErrorAction SilentlyContinue)) { continue }
        $hp = Join-Path $root ("helper-215-" + [guid]::NewGuid().ToString('N').Substring(0, 8) + ".ps1")
        [System.IO.File]::WriteAllText($hp, $helperCases, (New-Object System.Text.UTF8Encoding($false)))
        $ho = (& $exe -NoProfile -File $hp 2>&1 | ForEach-Object { $_.ToString() }) -join "`n"
        Assert-True "#215 helper, ${exe}: exit 0 keeps stdout as lines, no stderr" ($ho -match 'OK code=0 lines=one\|two out=one\|two err=0 last=0') $ho
        Assert-True "#215 helper, ${exe}: a non-zero exit keeps stderr as text, the code and `$LASTEXITCODE" ($ho -match 'FAIL code=3 lines=it said no err=it said no out=0 last=3') $ho
        Assert-True "#215 helper, ${exe}: stdout and stderr are told apart" ($ho -match 'MIX out=data err=warning text') $ho
        Assert-True "#215 helper, ${exe}: the caller's ErrorActionPreference is still Stop after the call" ($ho -match 'PREF=Stop') $ho
    }

    # -- 4. Sprint awareness ---------------------------------------------------
    $s = Get-Json (Invoke-Connect 'tkConnect acme -Sprint true -AsJson')
    Assert-Equal 'sprint awareness is written on the Space' 'True' ([string](Get-HubSpace 'acme').features.sprintAwareness)
    Assert-True 'and the report says so' ([bool]$s.steps.sprint.on)
    $sb = Invoke-Connect 'tkConnect acme -Sprint maybe'
    Assert-True 'a non-boolean sprint is refused' ($sb -match 'true or false' -and $sb -match 'EXIT=2') $sb

    # -- WhatIf writes nothing -------------------------------------------------
    $before = Get-Content (Join-Path $hubDir 'hub.json') -Raw
    $w = Invoke-Connect 'tkConnect shop -Sprint true -WhatIf'
    Assert-True '-WhatIf says the Config line it would run' ($w -match '\[WhatIf\] tkConfig -Set spaces.shop.features.sprintAwareness=true -Hub') $w
    Assert-Equal 'and changes nothing' $before (Get-Content (Join-Path $hubDir 'hub.json') -Raw)

    # -- the Azure demo's old slug is accepted, and the new one is said --
    $old = Invoke-Connect 'tkConnect test'
    Assert-True '#116: Connect test reports the Azure demo, naming its new slug' ($old -match "it is 'azure-demo' now" -and $old -notmatch "No Space 'test'" -and $old -notmatch 'EXIT=[1-9]') $old

    # -- Graduation (D-W15): the Example becomes yours -------------------------
    $ng = Invoke-Connect 'tkConnect acme -As mine'
    Assert-True 'only a shipped demo Space graduates' ($ng -match 'not one of the shipped demo Spaces' -and $ng -match 'EXIT=2') $ng
    $gr = Get-Json (Invoke-Connect "tkConnect azure-demo -Address https://dev.azure.com/mine-org -As mine -AsJson")
    Assert-True 'the new Space is declared in hub.json' ($null -ne (Get-HubSpace 'mine'))
    Assert-Equal 'with the address' 'https://dev.azure.com/mine-org' (Get-HubSpace 'mine').org
    Assert-Equal 'active' 'active' (Get-HubSpace 'mine').status
    Assert-True 'the folder moved, card and all' (Test-Path (Join-Path $hubDir 'mine/current/Task7-a-card-that-travels.prompt.md'))
    Assert-True 'and the old folder is gone' (-not (Test-Path (Join-Path $hubDir 'azure-demo')))
    $localAfter = Get-Content (Join-Path $pkgDir 'config.local.json') -Raw | ConvertFrom-Json
    Assert-Equal 'it is the active Space now' 'mine' $localAfter.activeSpace
    Assert-Equal 'and the samples are dismissed' 'True' ([string]$localAfter.isDemoDismissed)
    Assert-Equal 'the report is about the new Space' 'mine' $gr.slug
    Assert-True 'and says it graduated' ($gr.did -contains 'graduate')
    $st = Invoke-Connect 'tkStatus'
    Assert-True 'Status still works, on the graduated Space' ($st -notmatch 'EXIT=[1-9]') $st
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
