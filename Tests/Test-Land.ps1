<#
.SYNOPSIS
    Land -- the merge recorded, the issue closed, the card archived, typed as
    the VERB in a fresh shell.
.DESCRIPTION
    Typed as the verb in a fresh child shell against a scratch package and hub
    (AGENTS.md: a suite that runs a script directly does not test the verb).
    `gh`, `az` and Invoke-RestMethod are stubbed as functions that write down
    every call and keep the tracker's state in files under the scratch root --
    an issue closed by one run reads closed to the next -- so nothing reaches a
    real tracker and no issue is ever closed.

    Holds: a merged GitHub pull request lands the card in order -- one bullet
    `- <hash> #<n> squash-merged to <base> <date>` in the Git section, the
    issue closed through CloseItem with a comment naming the commit and
    -Comment, the card in archive/ with its Closed stamp; a re-run asks the
    tracker, writes nothing, posts no second comment, makes no -r1 round and
    says so; an open and a closed-unmerged pull request are each exit 2 naming
    the state, with the card and the tracker untouched; a merged Azure DevOps
    pull request lands through az and the work item REST calls CloseItem
    makes; a -Title card (with -Pr) and a Space with no tracker record and
    archive with the issue step skipped and said; -WhatIf prints the three
    writes and makes none; a card a person archived by hand is landed where it
    is; an id is never a partial name.
#>
$ErrorActionPreference = 'Stop'
$pkgRoot = Split-Path $PSScriptRoot -Parent
$script:passed = 0
$script:failed = 0

function Assert-True($label, $cond, $detail = '') {
    if ($cond) { $script:passed++; Write-Host "  PASS  $label" -ForegroundColor Green }
    else { $script:failed++; Write-Host "  FAIL  $label$(if ($detail) { " -- $($detail.ToString().Trim())" })" -ForegroundColor Red }
}

$root = Join-Path ([System.IO.Path]::GetTempPath()) ("p20-land-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
$pkgDir = Join-Path $root 'pkg'
$hubDir = Join-Path $root 'hub'
$logDir = Join-Path $root 'log'
$stateDir = Join-Path $root 'tracker'
$callLog = Join-Path $root 'calls.log'
$utf8 = New-Object System.Text.UTF8Encoding($false)

function New-LandSandbox {
    New-Item -ItemType Directory -Path $pkgDir, $hubDir, $logDir, $stateDir -Force | Out-Null
    foreach ($file in @('utilities.psm1', 'config.default.json', 'consts.json')) { Copy-Item (Join-Path $pkgRoot $file) $pkgDir -Force }
    Copy-Item (Join-Path $pkgRoot 'Scripts') $pkgDir -Recurse -Force
    Copy-Item (Join-Path $pkgRoot 'Config')  $pkgDir -Recurse -Force
    $hubJson = @'
{
  "hub": 1,
  "spaces": [
    { "slug": "widgets", "name": "Widgets", "status": "active", "promptsFolder": "widgets", "org": "https://github.com/acme/widgets" },
    { "slug": "board",   "name": "Board",   "status": "active", "promptsFolder": "board",   "org": "https://dev.azure.com/acme-org" },
    { "slug": "solo",    "name": "Solo",    "status": "local",  "promptsFolder": "solo",    "org": "" }
  ]
}
'@
    [System.IO.File]::WriteAllText((Join-Path $hubDir 'hub.json'), $hubJson, $utf8)
    foreach ($f in @('widgets', 'board', 'solo')) { New-Item -ItemType Directory -Path (Join-Path $hubDir "$f/current") -Force | Out-Null }
}

function Set-ActiveSpace([string]$slug) {
    $local = [ordered]@{ quietStart = $true; promptsRoot = $hubDir; activeSpace = $slug }
    [System.IO.File]::WriteAllText((Join-Path $pkgDir 'config.local.json'), ($local | ConvertTo-Json -Depth 4), $utf8)
}

# A card the way the templates write one: a Git section with one branch
# commit under Commits:, a PR URL line when it has one, and the footer.
function New-Card {
    param([string]$Space, [string]$FileName, [string]$Heading, [string]$PrUrl = '',
        [string]$Link = '(not linked -- created offline with -Title)', [switch]$Crlf, [string]$Folder = 'current')
    $text = "# $Heading`n`n## Branch`nyou/x`n`n## Git`n<!-- One commit PER LINE -->`nCommits:`n- f776d39 the work itself`n`n## Summary`nDone.`n"
    if ($PrUrl) { $text += "`nPR URL: $PrUrl`n" }
    $text += "`n---`n`n**Sprint:** (not linked)`n**ADO Link:** $Link`n**Created:** 2026-10-01`n"
    if ($Crlf) { $text = $text -replace "`n", "`r`n" }
    $dir = Join-Path $hubDir "$Space/$Folder"
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    $path = Join-Path $dir $FileName
    [System.IO.File]::WriteAllText($path, $text, $utf8)
    return $path
}

# The child: the package alone on PSModulePath, no webhook in reach, and the
# trackers replaced by functions that WRITE DOWN what they were asked. The
# pull request's state is P20_TEST_PR_STATE; an issue or work item is closed
# once a run has closed it -- a file under the scratch root -- so a re-run
# reads what the first run did.
function New-ChildPreamble {
    $pkg = $pkgDir -replace "'", "''"; $hub = $hubDir -replace "'", "''"; $log = $logDir -replace "'", "''"
    $calls = $callLog -replace "'", "''"; $state = $stateDir -replace "'", "''"
    return @"
`$env:PSModulePath = '$pkg'
`$env:PROMPTS_ROOT = '$hub'
`$env:P20_USAGE_LOG_DIR = '$log'
Get-ChildItem Env: | Where-Object { `$_.Name -like 'TEAMS_WEBHOOK_*' } | ForEach-Object { Remove-Item "Env:\`$(`$_.Name)" -ErrorAction SilentlyContinue }
function global:gh {
    Add-Content -Path '$calls' -Value ("gh " + ((`$args | ForEach-Object { ("`$_" -replace "``r?``n", '\n') }) -join ' '))
    `$global:LASTEXITCODE = 0
    if (`$args[0] -eq 'pr' -and `$args[1] -eq 'view') {
        `$s = if (`$env:P20_TEST_PR_STATE) { `$env:P20_TEST_PR_STATE } else { 'MERGED' }
        if (`$s -eq 'MERGED') { return '{"state":"MERGED","mergeCommit":{"oid":"c84c6e3f00dbeef1234567890abcdef12345678"},"mergedAt":"2026-10-30T12:00:00Z","baseRefName":"main"}' }
        return ('{"state":"' + `$s + '","mergeCommit":null,"mergedAt":null,"baseRefName":"main"}')
    }
    if (`$args[0] -eq 'issue' -and `$args[1] -eq 'view') {
        `$n = "`$(`$args[2])"
        `$st = if (Test-Path (Join-Path '$state' "issue-`$n-closed")) { 'CLOSED' } else { 'OPEN' }
        return ('{"title":"Issue ' + `$n + '","state":"' + `$st + '","url":"https://github.com/acme/widgets/issues/' + `$n + '"}')
    }
    if (`$args[0] -eq 'issue' -and `$args[1] -eq 'close') { New-Item -ItemType File -Force -Path (Join-Path '$state' "issue-`$(`$args[2])-closed") | Out-Null; return }
    if (`$args[0] -eq 'api') { return '{"visibility":"private"}' }
}
function global:az {
    Add-Content -Path '$calls' -Value ("az " + (`$args -join ' '))
    `$global:LASTEXITCODE = 0
    if (`$args[0] -eq 'account' -and `$args[1] -eq 'get-access-token') { return 'stub-token' }
    if (`$args[0] -eq 'repos' -and `$args[1] -eq 'pr' -and `$args[2] -eq 'show') {
        `$s = if (`$env:P20_TEST_ADO_STATUS) { `$env:P20_TEST_ADO_STATUS } else { 'completed' }
        return ('{"pullRequestId":901,"status":"' + `$s + '","lastMergeCommit":{"commitId":"0a1b2c3d4e5f60718293a4b5c6d7e8f901234567"},"closedDate":"2026-10-29T12:00:00Z","targetRefName":"refs/heads/main"}')
    }
    if (`$args[0] -eq 'boards' -and `$args[1] -eq 'work-item' -and `$args[2] -eq 'show') {
        `$st = if (Test-Path (Join-Path '$state' 'wi-closed')) { 'Closed' } else { 'Active' }
        return ('{"id":4242,"fields":{"System.State":"' + `$st + '","System.Title":"A scratch item"}}')
    }
}
function global:Invoke-RestMethod {
    param(`$Uri, `$Headers, `$Method, `$Body)
    `$line = "REST `$Method `$Uri"
    if (`$Body) { `$line += " " + (`$Body -replace '\s+', ' ') }
    Add-Content -Path '$calls' -Value `$line
    if ("`$Method" -eq 'Get') {
        `$st = if (Test-Path (Join-Path '$state' 'wi-closed')) { 'Closed' } else { 'Active' }
        return [pscustomobject]@{ fields = [pscustomobject]@{ 'System.State' = `$st; 'System.Title' = 'A scratch item'; 'System.WorkItemType' = 'Task'; 'System.TeamProject' = 'Acme Project' } }
    }
    if ("`$Method" -eq 'Patch') { New-Item -ItemType File -Force -Path (Join-Path '$state' 'wi-closed') | Out-Null }
    return [pscustomobject]@{ id = 4242 }
}
Import-Module '$pkg/utilities.psm1' -Force -DisableNameChecking *>`$null
"@
}

function Invoke-Land {
    param([string]$Snippet, [string]$PrState = '', [string]$AdoStatus = '')
    if (Test-Path $callLog) { Remove-Item $callLog -Force }
    $runner = Join-Path $root ("run-" + [guid]::NewGuid().ToString('N').Substring(0, 8) + ".ps1")
    $pre = New-ChildPreamble
    if ($PrState) { $pre = "`$env:P20_TEST_PR_STATE = '$PrState'`n" + $pre }
    if ($AdoStatus) { $pre = "`$env:P20_TEST_ADO_STATUS = '$AdoStatus'`n" + $pre }
    [System.IO.File]::WriteAllText($runner, ($pre + "`n" + $Snippet + "`n; `"EXIT=`$LASTEXITCODE`"`n"), $utf8)
    $out = & pwsh -NoProfile -File $runner 2>&1
    $text = (($out | ForEach-Object { $_.ToString() }) -join "`n")
    $calls = if (Test-Path $callLog) { @(Get-Content $callLog) } else { @() }
    return [pscustomobject]@{ Text = $text; Calls = $calls }
}

function Get-Bytes64([string]$Path) { [System.Convert]::ToBase64String([System.IO.File]::ReadAllBytes($Path)) }
function Get-FolderNames([string]$Path) { if (Test-Path $Path) { @(Get-ChildItem -LiteralPath $Path -File | ForEach-Object { $_.Name } | Sort-Object) } else { @() } }

Write-Host ""
Write-Host "  Land -- record, close, archive, typed" -ForegroundColor Cyan
Write-Host "  -------------------------------------" -ForegroundColor DarkGray
Write-Host ""

try {
    New-LandSandbox

    # -- GitHub, merged: the full path ------------------------------------------
    Set-ActiveSpace 'widgets'
    $name146 = 'Task146-a-card-whose-pr-merged.prompt.md'
    New-Card -Space 'widgets' -FileName $name146 -Heading 'Task 146: A card whose PR merged' `
        -PrUrl 'https://github.com/acme/widgets/pull/175' -Link 'https://github.com/acme/widgets/issues/146' -Crlf | Out-Null
    $archived146 = Join-Path $hubDir "widgets/archive/$name146"

    $r = Invoke-Land "tkLand 146 -Comment 'Thanks for the review.'"
    Assert-True 'merged on GitHub: exit 0' ($r.Text -match 'EXIT=0') $r.Text
    Assert-True 'the pull request is asked about by its number, its repo and the fields that say merged' (@($r.Calls) -contains 'gh pr view 175 --repo acme/widgets --json state,mergeCommit,mergedAt,baseRefName') ($r.Calls -join ' | ')
    Assert-True 'no gh argument carries a query string (& is cmd''s on Windows)' (-not (@($r.Calls) -match '^gh .*&')) ($r.Calls -join ' | ')
    Assert-True 'the card is no longer in current/' (-not (Test-Path (Join-Path $hubDir "widgets/current/$name146")))
    Assert-True 'the card is in archive/ under its own name -- no round suffix' (Test-Path $archived146) ((Get-FolderNames (Join-Path $hubDir 'widgets/archive')) -join ', ')
    $landed = if (Test-Path $archived146) { [System.IO.File]::ReadAllText($archived146) } else { '' }
    Assert-True 'the merge is ONE bullet, in the house shape' (([regex]::Matches($landed, '(?m)^- c84c6e3 #175 squash-merged to main 2026-10-30\r?$')).Count -eq 1) $landed
    Assert-True 'under Commits:, after the branch''s own commit' ($landed -match "Commits:\r\n- f776d39 the work itself\r\n- c84c6e3 #175 squash-merged to main 2026-10-30\r\n") $landed
    Assert-True 'the bullet is in the archived file: recorded BEFORE the archive' ($landed -match 'c84c6e3 #175')
    Assert-True 'Archive stamped it Closed' ($landed -match '(?m)^\*\*Closed:\*\*') $landed
    Assert-True 'a CRLF card stays CRLF, with no bare LF line' (-not ($landed -replace "`r`n", '' -match "`n"))
    $bytes = [System.IO.File]::ReadAllBytes($archived146)
    Assert-True 'and it is written with no BOM' (-not ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF))
    $closeCalls = @($r.Calls | Where-Object { $_ -match '^gh issue close' })
    Assert-True 'the issue behind the card is closed once, through CloseItem''s gh issue close' ($closeCalls.Count -eq 1 -and $closeCalls[0] -match '^gh issue close 146 --repo acme/widgets --reason completed --comment ') ($r.Calls -join ' | ')
    Assert-True 'the comment names the commit and the pull request' ($closeCalls.Count -eq 1 -and $closeCalls[0] -match 'Landed in c84c6e3' -and $closeCalls[0] -match '\[pull request 175\]\(https://github\.com/acme/widgets/pull/175\)') ($closeCalls -join ' | ')
    Assert-True 'and carries -Comment after it' ($closeCalls.Count -eq 1 -and $closeCalls[0] -match '2026-10-30\. Thanks for the review\.$') ($closeCalls -join ' | ')
    $iPr = [array]::IndexOf(@($r.Calls), 'gh pr view 175 --repo acme/widgets --json state,mergeCommit,mergedAt,baseRefName')
    $iClose = [array]::IndexOf(@($r.Calls), $closeCalls[0])
    Assert-True 'the merged check comes before the close' ($iPr -ge 0 -and $iClose -gt $iPr) ($r.Calls -join ' | ')
    Assert-True 'the output walks the three steps in order' ($r.Text -match '(?s)\[1/3\] Recorded.*\[2/3\] Closing issue #146.*\[3/3\] Archiving') $r.Text
    Assert-True 'and says it landed' ($r.Text -match 'Landed Task146') $r.Text

    # -- A re-run changes nothing --------------------------------------------
    $before = Get-Bytes64 $archived146
    $namesBefore = Get-FolderNames (Join-Path $hubDir 'widgets/archive')
    $r = Invoke-Land 'tkLand 146'
    Assert-True 're-run: exit 0' ($r.Text -match 'EXIT=0') $r.Text
    Assert-True 're-run: the card is found in archive/ and not written' ((Get-Bytes64 $archived146) -eq $before)
    Assert-True 're-run: no -r1 round, nothing new in archive/' (((Get-FolderNames (Join-Path $hubDir 'widgets/archive')) -join ',') -eq ($namesBefore -join ',')) ((Get-FolderNames (Join-Path $hubDir 'widgets/archive')) -join ', ')
    Assert-True 're-run: no close and no second comment' (-not (@($r.Calls) -match '^gh issue (close|comment)')) ($r.Calls -join ' | ')
    Assert-True 're-run: each step says it was skipped' ($r.Text -match '\[1/3\] Skipped: .*already carries c84c6e3' -and $r.Text -match '\[2/3\] Skipped: issue #146 is already closed' -and $r.Text -match '\[3/3\] Skipped: .*already in archive/') $r.Text
    Assert-True 're-run: and says nothing changed' ($r.Text -match 'already landed' -and $r.Text -match 'Nothing changed') $r.Text

    # -- An id is not a substring ---------------------------------------------
    # (The import itself asks who is signed in -- gh auth status, gh api user --
    # as every shell does; a refusal asks nothing about a pull request or issue.)
    $r = Invoke-Land 'tkLand 46'
    Assert-True '"46" is not Task146: exit 2, and the tracker is not asked' ($r.Text -match "No card with id '46'" -and $r.Text -match 'EXIT=2' -and -not (@($r.Calls) -match '^gh (pr|issue) ')) ($r.Text + ' || ' + ($r.Calls -join ' | '))

    # -- Open: refused, nothing written -----------------------------------------
    $p147 = New-Card -Space 'widgets' -FileName 'Task147-still-in-review.prompt.md' -Heading 'Task 147: Still in review' -PrUrl 'https://github.com/acme/widgets/pull/176'
    $b147 = Get-Bytes64 $p147
    $r = Invoke-Land 'tkLand 147' -PrState 'OPEN'
    Assert-True 'an open pull request is a stated refusal (exit 2) naming its state' ($r.Text -match 'is open, not merged' -and $r.Text -match 'EXIT=2') $r.Text
    Assert-True 'said once, not wrapped in a generic error' (-not ($r.Text -match 'exit code 2')) $r.Text
    Assert-True 'the card is not written and stays in current/' ((Test-Path $p147) -and (Get-Bytes64 $p147) -eq $b147)
    Assert-True 'and no issue is touched' (-not (@($r.Calls) -match '^gh issue')) ($r.Calls -join ' | ')

    # -- Closed without merging: refused ----------------------------------------
    $r = Invoke-Land 'tkLand 147' -PrState 'CLOSED'
    Assert-True 'a pull request closed unmerged is refused (exit 2) and says so' ($r.Text -match 'is closed without merging, not merged' -and $r.Text -match 'EXIT=2') $r.Text
    Assert-True 'the card is not written, and no issue is touched' ((Get-Bytes64 $p147) -eq $b147 -and -not (@($r.Calls) -match '^gh issue')) ($r.Calls -join ' | ')

    # -- No PR URL and no -Pr ---------------------------------------------------
    New-Card -Space 'widgets' -FileName 'Task149-no-pull-request-yet.prompt.md' -Heading 'Task 149: No pull request yet' | Out-Null
    $r = Invoke-Land 'tkLand 149'
    Assert-True 'a card with no PR URL: and no -Pr is refused (exit 2), naming -Pr, asking nothing' ($r.Text -match 'has no PR URL' -and $r.Text -match '-Pr <n>' -and $r.Text -match 'EXIT=2' -and -not (@($r.Calls) -match '^gh (pr|issue) ')) ($r.Text + ' || ' + ($r.Calls -join ' | '))

    # -- -WhatIf: the three writes, none made -----------------------------------
    $p148 = New-Card -Space 'widgets' -FileName 'Task148-ready-to-land.prompt.md' -Heading 'Task 148: Ready to land' -PrUrl 'https://github.com/acme/widgets/pull/180'
    $b148 = Get-Bytes64 $p148
    $r = Invoke-Land 'tkLand 148 -WhatIf'
    Assert-True '-WhatIf: exit 0' ($r.Text -match 'EXIT=0') $r.Text
    Assert-True '-WhatIf prints the bullet it would add' ($r.Text -match 'Would add to Task148-ready-to-land\.prompt\.md: - c84c6e3 #180 squash-merged to main 2026-10-30') $r.Text
    Assert-True '-WhatIf prints the close and its comment' ($r.Text -match 'Would close issue #148 with the comment: Landed in c84c6e3') $r.Text
    Assert-True '-WhatIf prints the archive' ($r.Text -match 'Would archive Task148-ready-to-land\.prompt\.md') $r.Text
    Assert-True '-WhatIf writes nothing: the card is unchanged in current/' ((Test-Path $p148) -and (Get-Bytes64 $p148) -eq $b148)
    Assert-True '-WhatIf closes nothing and comments nothing' (-not (@($r.Calls) -match '^gh issue (close|comment)')) ($r.Calls -join ' | ')

    # -- A -Title card: the issue step skipped, with -Pr ------------------------
    $nameK = 'TaskK7M2-a-card-of-my-own.prompt.md'
    New-Card -Space 'widgets' -FileName $nameK -Heading 'Task K7M2: A card of my own' | Out-Null
    $r = Invoke-Land 'tkLand K7M2 -Pr 177'
    Assert-True 'a -Title card with -Pr: exit 0' ($r.Text -match 'EXIT=0') $r.Text
    Assert-True '-Pr is asked about on the Space''s repo' (@($r.Calls) -contains 'gh pr view 177 --repo acme/widgets --json state,mergeCommit,mergedAt,baseRefName') ($r.Calls -join ' | ')
    Assert-True 'the issue step is skipped, and said' ($r.Text -match '\[2/3\] Skipped: .*has no issue behind it') $r.Text
    Assert-True 'and no issue is asked about or closed' (-not (@($r.Calls) -match '^gh issue')) ($r.Calls -join ' | ')
    $kArch = Join-Path $hubDir "widgets/archive/$nameK"
    Assert-True 'the merge is recorded and the card archived' ((Test-Path $kArch) -and ([System.IO.File]::ReadAllText($kArch) -match '(?m)^- c84c6e3 #177 squash-merged to main 2026-10-30$')) $(if (Test-Path $kArch) { [System.IO.File]::ReadAllText($kArch) })

    # -- A card archived by hand: landed where it is ------------------------------
    $name150 = 'Task150-archived-by-hand.prompt.md'
    $p150 = New-Card -Space 'widgets' -FileName $name150 -Heading 'Task 150: Archived by hand' -PrUrl 'https://github.com/acme/widgets/pull/181' -Folder 'archive'
    $r = Invoke-Land 'tkLand 150'
    Assert-True 'a card already in archive/: exit 0' ($r.Text -match 'EXIT=0') $r.Text
    Assert-True 'the merge is written into the archived card' ([System.IO.File]::ReadAllText($p150) -match '(?m)^- c84c6e3 #181 squash-merged to main 2026-10-30$') ([System.IO.File]::ReadAllText($p150))
    Assert-True 'its issue is still closed (it was open)' (@($r.Calls | Where-Object { $_ -match '^gh issue close 150 ' }).Count -eq 1) ($r.Calls -join ' | ')
    Assert-True 'and Archive is not run again: no round, one file' (((Get-FolderNames (Join-Path $hubDir 'widgets/archive')) -match '^Task150').Count -eq 1 -and -not (Test-Path (Join-Path $hubDir 'widgets/current/Task150-archived-by-hand.prompt.md'))) ((Get-FolderNames (Join-Path $hubDir 'widgets/archive')) -join ', ')
    Assert-True 'and the archive step says it was skipped' ($r.Text -match '\[3/3\] Skipped: .*already in archive/') $r.Text

    # -- A Space with no tracker: the PR from its URL, the issue skipped ----------
    Set-ActiveSpace 'solo'
    $nameS = 'TaskH7KP-solo-work.prompt.md'
    New-Card -Space 'solo' -FileName $nameS -Heading 'Task H7KP: Solo work' -PrUrl 'https://github.com/acme/widgets/pull/178' | Out-Null
    $r = Invoke-Land 'tkLand H7KP'
    Assert-True 'no tracker on the Space: exit 0, the PR read from the card''s own URL' ($r.Text -match 'EXIT=0' -and (@($r.Calls) -contains 'gh pr view 178 --repo acme/widgets --json state,mergeCommit,mergedAt,baseRefName')) $r.Text
    Assert-True 'the issue step is skipped, and said' ($r.Text -match '\[2/3\] Skipped: this Space has no tracker') $r.Text
    Assert-True 'and the card is recorded and archived' ((Test-Path (Join-Path $hubDir "solo/archive/$nameS")) -and ([System.IO.File]::ReadAllText((Join-Path $hubDir "solo/archive/$nameS")) -match '- c84c6e3 #178 squash-merged to main 2026-10-30')) $r.Text

    # -- Azure DevOps, merged ---------------------------------------------------
    Set-ActiveSpace 'board'
    $nameA = '4242-a-board-bug.prompt.md'
    New-Card -Space 'board' -FileName $nameA -Heading 'Bug 4242: A board bug' `
        -PrUrl 'https://dev.azure.com/acme-org/Acme%20Project/_git/widgets/pullrequest/901' `
        -Link 'https://dev.azure.com/acme-org/Acme%20Project/_workitems/edit/4242' | Out-Null
    $r = Invoke-Land 'tkLand 4242'
    Assert-True 'merged on Azure DevOps: exit 0' ($r.Text -match 'EXIT=0') $r.Text
    Assert-True 'the pull request is read through az repos pr show, in the PR''s own org' (@($r.Calls) -contains 'az repos pr show --id 901 --org https://dev.azure.com/acme-org --output json') ($r.Calls -join ' | ')
    $patch = @($r.Calls | Where-Object { $_ -match '^REST Patch https://dev\.azure\.com/acme-org/_apis/wit/workitems/4242' })
    Assert-True 'the work item is closed through CloseItem''s PATCH' ($patch.Count -eq 1 -and $patch[0] -match 'Closed') ($r.Calls -join ' | ')
    $post = @($r.Calls | Where-Object { $_ -match '^REST Post .*/workItems/4242/comments' })
    Assert-True 'and the comment names the commit' ($post.Count -eq 1 -and $post[0] -match 'Landed in 0a1b2c3') ($r.Calls -join ' | ')
    $aArch = Join-Path $hubDir "board/archive/$nameA"
    Assert-True 'the bullet is recorded and the card archived' ((Test-Path $aArch) -and ([System.IO.File]::ReadAllText($aArch) -match '(?m)^- 0a1b2c3 #901 squash-merged to main 2026-10-29$')) $(if (Test-Path $aArch) { [System.IO.File]::ReadAllText($aArch) })

    $r = Invoke-Land 'tkLand 4242'
    Assert-True 'ADO re-run: exit 0, no PATCH, no comment' ($r.Text -match 'EXIT=0' -and -not (@($r.Calls) -match '^REST (Patch|Post)')) ($r.Text + ' || ' + ($r.Calls -join ' | '))
    Assert-True 'ADO re-run: the work item reads closed and is skipped' ($r.Text -match '\[2/3\] Skipped: work item 4242 is already Closed') $r.Text

    $nameB = '4243-abandoned.prompt.md'
    $pB = New-Card -Space 'board' -FileName $nameB -Heading 'Bug 4243: Abandoned' -PrUrl 'https://dev.azure.com/acme-org/Acme%20Project/_git/widgets/pullrequest/902'
    $bB = Get-Bytes64 $pB
    $r = Invoke-Land 'tkLand 4243' -AdoStatus 'abandoned'
    Assert-True 'an abandoned Azure DevOps pull request is refused (exit 2), named, nothing written' ($r.Text -match 'is abandoned, not merged' -and $r.Text -match 'EXIT=2' -and (Get-Bytes64 $pB) -eq $bB -and -not (@($r.Calls) -match '^REST ')) $r.Text

    # -- The help --------------------------------------------------------------
    $r = Invoke-Land 'tkLand -Help'
    Assert-True '-Help names -Pr, -Comment and -WhatIf' ($r.Text -match '-Pr <n>' -and $r.Text -match '-Comment' -and $r.Text -match '-WhatIf') $r.Text
}
catch {
    Assert-True 'the cases ran to the end without a terminating error' $false $_.Exception.Message
}
finally {
    if (Test-Path $root) { Remove-Item $root -Recurse -Force -ErrorAction SilentlyContinue }
}

Write-Host ""
$total = $script:passed + $script:failed
Write-Host "  Results: $($script:passed)/$total passed" -ForegroundColor $(if ($script:failed -eq 0) { 'Green' } else { 'Red' })
Write-Host ""
if ($script:failed -gt 0) { exit 1 }
exit 0
