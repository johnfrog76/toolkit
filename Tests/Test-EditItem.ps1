<#
.SYNOPSIS
    EditItem -- the pin: -Pin and -Unpin are the tracker's own pin,
    `gh issue pin` / `gh issue unpin`, typed as the VERB in a fresh shell.
.DESCRIPTION
    Typed as the verb in a fresh child shell against a scratch package and hub
    (AGENTS.md: a suite that runs a script directly does not test the verb).
    `gh` and `az` are stubbed as functions that record every call, so nothing
    reaches a real tracker: a pin is never sent. Holds: -Pin and -Unpin call
    gh with the issue and the Space's repo; -WhatIf prints the transition and
    never calls pin; GitHub refusing a fourth pin is said in the product's own
    sentence; -Pin with -Unpin is refused; and on an Azure DevOps Space both
    switches are a stated refusal (exit 2) before az is asked anything.

    And NewItem -FromCard, the
    other verb that turns a card and a tracker item into one record, typed the
    same way: the issue is the card's name and Summary, its body ends with
    "Toolkit card: <id>", the URL lands in the card's **ADO Link:** line and
    nothing else in the card moves (a CRLF card stays CRLF); -WhatIf prints the
    whole issue and creates nothing; a card already linked, an id that is not a
    card, an Azure DevOps Space and a Space with no tracker are each refused
    with exit 2 and no issue asked for.

    And NewItem -Parent on a GitHub Space (Team Agile's Split): the parent is
    read before anything is created; the new issue's id is read and it is added
    as a sub-issue of the parent through the REST route; where GitHub refuses
    that route, a task-list line is appended to the parent's body instead and
    the output says so; -WhatIf prints the calls and makes none of the writes;
    a parent that does not exist is refused with exit 2 and nothing created.
#>
$ErrorActionPreference = 'Stop'
$pkgRoot = Split-Path $PSScriptRoot -Parent
$script:passed = 0
$script:failed = 0

function Assert-True($label, $cond, $detail = '') {
    if ($cond) { $script:passed++; Write-Host "  PASS  $label" -ForegroundColor Green }
    else { $script:failed++; Write-Host "  FAIL  $label$(if ($detail) { " -- $($detail.ToString().Trim())" })" -ForegroundColor Red }
}

$root = Join-Path ([System.IO.Path]::GetTempPath()) ("p20-edititem-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
$pkgDir = Join-Path $root 'pkg'
$hubDir = Join-Path $root 'hub'
$logDir = Join-Path $root 'log'
$callLog = Join-Path $root 'calls.log'

function New-EditSandbox {
    New-Item -ItemType Directory -Path $pkgDir, $hubDir, $logDir -Force | Out-Null
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
    [System.IO.File]::WriteAllText((Join-Path $hubDir 'hub.json'), $hubJson, (New-Object System.Text.UTF8Encoding($false)))
    foreach ($f in @('widgets', 'board', 'solo')) { New-Item -ItemType Directory -Path (Join-Path $hubDir "$f/current") -Force | Out-Null }
}

# A card made with no tracker, the way NewPrompt -Title writes one: a Summary,
# and an ADO Link line that says it is not linked.
function New-OfflineCard {
    param([string]$Space, [string]$FileName, [string]$Heading, [string]$Summary, [switch]$Crlf, [string]$Link = '(not linked -- created offline with -Title)')
    $text = "# $Heading`n`n## Branch`nyou/x`n`n## Summary`n$Summary`n`n## Question`nWhat?`n`n---`n`n**Sprint:** (not linked)`n**ADO Link:** $Link`n**Created:** 2026-10-01`n"
    if ($Crlf) { $text = $text -replace "`n", "`r`n" }
    $path = Join-Path $hubDir "$Space/current/$FileName"
    [System.IO.File]::WriteAllText($path, $text, (New-Object System.Text.UTF8Encoding($false)))
    return $path
}

function Set-ActiveSpace([string]$slug) {
    $local = [ordered]@{ quietStart = $true; promptsRoot = $hubDir; activeSpace = $slug }
    [System.IO.File]::WriteAllText((Join-Path $pkgDir 'config.local.json'), ($local | ConvertTo-Json -Depth 4), (New-Object System.Text.UTF8Encoding($false)))
}

# The child: the package alone on PSModulePath, no webhook in reach, and both
# tracker CLIs replaced by functions that WRITE DOWN what they were asked and
# change nothing. `gh issue pin` answers GitHub's fourth-pin refusal when
# P20_TEST_PINS_FULL is set.
function New-ChildPreamble {
    $pkg = $pkgDir -replace "'", "''"; $hub = $hubDir -replace "'", "''"; $log = $logDir -replace "'", "''"; $calls = $callLog -replace "'", "''"
    return @"
`$env:PSModulePath = '$pkg'
`$env:PROMPTS_ROOT = '$hub'
`$env:P20_USAGE_LOG_DIR = '$log'
Get-ChildItem Env: | Where-Object { `$_.Name -like 'TEAMS_WEBHOOK_*' } | ForEach-Object { Remove-Item "Env:\`$(`$_.Name)" -ErrorAction SilentlyContinue }
function global:gh {
    # One line per call: a multi-line --body is written with its newlines as \n.
    Add-Content -Path '$calls' -Value ("gh " + ((`$args | ForEach-Object { ("`$_" -replace "``r?``n", '\n') }) -join ' '))
    if (`$args[0] -eq 'issue' -and `$args[1] -eq 'create') { `$global:LASTEXITCODE = 0; return 'https://github.com/acme/widgets/issues/41' }
    if (`$args[0] -eq 'issue' -and `$args[1] -eq 'view' -and "`$(`$args[2])" -eq '99') { `$global:LASTEXITCODE = 1; return 'GraphQL: Could not resolve to an issue or pull request with the number of 99. (repository.issue)' }
    if (`$args[0] -eq 'issue' -and `$args[1] -eq 'view' -and (`$args -contains 'body')) { `$global:LASTEXITCODE = 0; return '{"body":"The parent body."}' }
    if (`$args[0] -eq 'issue' -and `$args[1] -eq 'view') { `$global:LASTEXITCODE = 0; return '{"title":"A thing worth pinning","state":"OPEN","url":"https://github.com/acme/widgets/issues/12"}' }
    if (`$args[0] -eq 'api' -and "`$(`$args[1])" -eq 'repos/acme/widgets/issues/41') { `$global:LASTEXITCODE = 0; return '{"id":9001,"number":41}' }
    if (`$args[0] -eq 'api' -and "`$(`$args[3])" -like '*/sub_issues' -and `$env:P20_TEST_SUBISSUES_REFUSED) { `$global:LASTEXITCODE = 1; return 'gh: Not Found (HTTP 404)' }
    if (`$args[0] -eq 'issue' -and `$args[1] -eq 'pin' -and `$env:P20_TEST_PINS_FULL) { `$global:LASTEXITCODE = 1; return 'GraphQL: Issue pin limit reached for this repository (pinIssue)' }
    `$global:LASTEXITCODE = 0
}
function global:az {
    Add-Content -Path '$calls' -Value ("az " + (`$args -join ' '))
    `$global:LASTEXITCODE = 0
}
Import-Module '$pkg/utilities.psm1' -Force -DisableNameChecking *>`$null
# Tier 1: the tracker "answers" -- the stubs above are what it answers with.
`$global:P20Env = [pscustomobject]@{ Tier = 1; Tracker = 'github' }
"@
}

function Invoke-Edit {
    param([string]$Snippet, [switch]$PinsFull, [switch]$SubIssuesRefused)
    if (Test-Path $callLog) { Remove-Item $callLog -Force }
    $runner = Join-Path $root ("run-" + [guid]::NewGuid().ToString('N').Substring(0, 8) + ".ps1")
    $pre = New-ChildPreamble
    if ($PinsFull) { $pre = "`$env:P20_TEST_PINS_FULL = '1'`n" + $pre }
    if ($SubIssuesRefused) { $pre = "`$env:P20_TEST_SUBISSUES_REFUSED = '1'`n" + $pre }
    [System.IO.File]::WriteAllText($runner, ($pre + "`n" + $Snippet + "`n; `"EXIT=`$LASTEXITCODE`"`n"), (New-Object System.Text.UTF8Encoding($false)))
    $out = & pwsh -NoProfile -File $runner 2>&1
    $text = (($out | ForEach-Object { $_.ToString() }) -join "`n")
    $calls = if (Test-Path $callLog) { @(Get-Content $callLog) } else { @() }
    return [pscustomobject]@{ Text = $text; Calls = $calls }
}

Write-Host ""
Write-Host "  EditItem -- the pin, typed" -ForegroundColor Cyan
Write-Host "  --------------------------" -ForegroundColor DarkGray
Write-Host ""

try {
    New-EditSandbox

    # -- A GitHub Space ---------------------------------------------------------
    Set-ActiveSpace 'widgets'

    $r = Invoke-Edit 'tkEditItem 12 -Pin'
    Assert-True '-Pin runs gh issue pin with the issue and the Space''s repo' (@($r.Calls) -contains 'gh issue pin 12 --repo acme/widgets') ($r.Calls -join ' | ')
    Assert-True '-Pin alone runs no gh issue edit' (-not (@($r.Calls) -match '^gh issue edit')) ($r.Calls -join ' | ')
    Assert-True '-Pin exits 0' ($r.Text -match 'EXIT=0') $r.Text

    $r = Invoke-Edit 'tkEditItem 12 -Unpin'
    Assert-True '-Unpin runs gh issue unpin' (@($r.Calls) -contains 'gh issue unpin 12 --repo acme/widgets') ($r.Calls -join ' | ')
    Assert-True '-Unpin exits 0' ($r.Text -match 'EXIT=0') $r.Text

    $r = Invoke-Edit 'tkEditItem 12 -Pin -AddTag sev2'
    Assert-True 'a pin beside an edit runs both: the edit, then the pin' ((@($r.Calls) -match '^gh issue edit 12 --repo acme/widgets --add-label sev2').Count -eq 1 -and (@($r.Calls) -contains 'gh issue pin 12 --repo acme/widgets')) ($r.Calls -join ' | ')

    $r = Invoke-Edit 'tkEditItem 12 -Pin -WhatIf'
    Assert-True '-WhatIf prints the transition' ($r.Text -match 'WHATIF' -and $r.Text -match 'pinned on GitHub') $r.Text
    Assert-True '-WhatIf never calls pin' (-not (@($r.Calls) -match '^gh issue (pin|unpin)')) ($r.Calls -join ' | ')
    Assert-True '-WhatIf exits 0' ($r.Text -match 'EXIT=0') $r.Text

    $r = Invoke-Edit 'tkEditItem 12 -Unpin -WhatIf'
    Assert-True '-Unpin -WhatIf says unpinned and calls nothing' ($r.Text -match 'unpinned' -and -not (@($r.Calls) -match '^gh issue unpin')) $r.Text

    $r = Invoke-Edit 'tkEditItem 12 -Pin' -PinsFull
    Assert-True 'a fourth pin is said in the product''s own sentence' ($r.Text -match 'GitHub pins three issues per repository; unpin one first') $r.Text
    Assert-True 'and is a stated refusal (exit 2)' ($r.Text -match 'EXIT=2') $r.Text
    Assert-True 'and the refusal is said once, not wrapped in a generic error' (-not ($r.Text -match 'exit code 2')) $r.Text

    $r = Invoke-Edit 'tkEditItem 12 -Pin -Unpin'
    # The wrapper's tier gate has already asked who is signed in (gh auth status, gh api user;
    # az account show on a board) -- every tracker verb does. A refusal asks nothing about the ITEM.
    Assert-True '-Pin with -Unpin is refused (exit 2) and asks gh nothing about the issue' ($r.Text -match 'opposite' -and $r.Text -match 'EXIT=2' -and -not (@($r.Calls) -match '^gh issue ')) ($r.Text + " || calls: " + ($r.Calls -join " | "))

    # -- An Azure DevOps Space --------------------------------------------------
    Set-ActiveSpace 'board'

    $r = Invoke-Edit 'tkEditItem 42 -Pin'
    Assert-True 'on Azure DevOps -Pin is refused with the reason' ($r.Text -match 'has no pin' -and $r.Text -match 'EXIT=2') $r.Text
    Assert-True 'and az is asked nothing about the work item' (-not (@($r.Calls) -match '^az (boards|rest|devops) ')) ($r.Calls -join ' | ')

    $r = Invoke-Edit 'tkEditItem 42 -Unpin -WhatIf'
    Assert-True 'on Azure DevOps -Unpin is refused too, -WhatIf or not' ($r.Text -match 'has no pin' -and $r.Text -match 'EXIT=2' -and -not (@($r.Calls) -match '^(az (boards|rest|devops)|gh issue) ')) ($r.Text + " || calls: " + ($r.Calls -join " | "))

    # -- The help --------------------------------------------------------------
    $r = Invoke-Edit 'tkEditItem -Help'
    Assert-True '-Help names -Pin and -Unpin' ($r.Text -match '-Pin' -and $r.Text -match '-Unpin') $r.Text

    # -- NewItem -FromCard: a card made with no tracker becomes its issue --
    Write-Host ""
    Write-Host "  NewItem -FromCard -- publish a card, typed" -ForegroundColor Cyan
    Set-ActiveSpace 'widgets'
    $spike = New-OfflineCard -Space 'widgets' -FileName 'Spike-K7M2-import-a-recipe-from-a-photo.prompt.md' `
        -Heading 'Spike K7M2: Import a recipe from a photo' -Summary "Half the recipes people own are on paper.`n<!-- a template comment -->`nURL import does nothing for them." -Crlf
    $before = [System.IO.File]::ReadAllBytes($spike)

    $r = Invoke-Edit 'tkNewItem -FromCard K7M2 -WhatIf'
    Assert-True '-WhatIf prints the whole issue, ending with the line that names the card' ($r.Text -match 'DRY RUN' -and $r.Text -match 'Toolkit card: K7M2' -and $r.Text -match 'Import a recipe from a photo') $r.Text
    Assert-True '-WhatIf creates no issue' (-not (@($r.Calls) -match '^gh issue create')) ($r.Calls -join ' | ')
    Assert-True '-WhatIf writes nothing into the card' ([System.Convert]::ToBase64String([System.IO.File]::ReadAllBytes($spike)) -eq [System.Convert]::ToBase64String($before))
    Assert-True '-WhatIf exits 0' ($r.Text -match 'EXIT=0') $r.Text
    $r = Invoke-Edit 'tkNewItem -FromCard K7M2 -ReadOnly'
    Assert-True '-ReadOnly is the same dry run' ($r.Text -match 'DRY RUN' -and -not (@($r.Calls) -match '^gh issue create')) $r.Text

    $r = Invoke-Edit 'tkNewItem -FromCard K7M2'
    $creates = @($r.Calls | Where-Object { $_ -match '^gh issue create' })
    Assert-True '-FromCard creates one issue on the Space''s repo' ($creates.Count -eq 1 -and $creates[0] -match '--repo acme/widgets') ($r.Calls -join ' | ')
    Assert-True 'titled by the card''s name, not its heading' ($creates.Count -eq 1 -and $creates[0] -match '--title Import a recipe from a photo --body') ($creates -join ' | ')
    $bodyMatch = [regex]::Match([string]($creates | Select-Object -First 1), '--body (.*) --assignee')
    $body = $bodyMatch.Groups[1].Value
    Assert-True 'the body is the card''s Summary, its template comment dropped' ($body.StartsWith('Half the recipes people own are on paper.') -and $body -notmatch 'template comment') $body
    Assert-True 'and it ENDS with "Toolkit card: K7M2"' ($body.EndsWith('\n\nToolkit card: K7M2')) $body
    Assert-True 'a Spike files as a plain issue: no kind label' (-not ($creates[0] -match '--label')) ($creates -join ' | ')
    $after = [System.IO.File]::ReadAllText($spike)
    Assert-True 'the issue''s URL is written into the card''s ADO Link line' ($after -match '(?m)^\*\*ADO Link:\*\* https://github\.com/acme/widgets/issues/41\r?$') $after
    $expected = ([System.Text.Encoding]::UTF8.GetString($before)) -replace '\*\*ADO Link:\*\* \(not linked -- created offline with -Title\)', '**ADO Link:** https://github.com/acme/widgets/issues/41'
    Assert-True 'and nothing else in the card moved: a CRLF card stays CRLF, line for line' ($after -ceq $expected) $after
    $rawAfter = [System.IO.File]::ReadAllBytes($spike)
    Assert-True 'and it is written with no BOM' (-not ($rawAfter.Length -ge 3 -and $rawAfter[0] -eq 0xEF -and $rawAfter[1] -eq 0xBB -and $rawAfter[2] -eq 0xBF))
    Assert-True 'it says the card is linked and keeps its id' ($r.Text -match 'card K7M2 is linked, and keeps its id') $r.Text
    Assert-True '-FromCard exits 0' ($r.Text -match 'EXIT=0') $r.Text
    $linkedBytes = [System.IO.File]::ReadAllBytes($spike)

    $r = Invoke-Edit 'tkNewItem -FromCard K7M2'
    Assert-True 'run again it refuses: the card is already linked' ($r.Text -match 'already linked' -and $r.Text -match 'EXIT=2') $r.Text
    Assert-True 'and asks for no issue' (-not (@($r.Calls) -match '^gh issue create')) ($r.Calls -join ' | ')
    Assert-True 'and the refusal is said once, not wrapped in a generic error' (-not ($r.Text -match 'exit code 2')) $r.Text
    Assert-True 'and the card is not written' ([System.Convert]::ToBase64String([System.IO.File]::ReadAllBytes($spike)) -eq [System.Convert]::ToBase64String($linkedBytes))

    New-OfflineCard -Space 'widgets' -FileName 'Q4TN-tags-overlap-in-search.prompt.md' -Heading 'Bug Q4TN: Tags overlap in search' -Summary '(TBD)' | Out-Null
    $r = Invoke-Edit 'tkNewItem -FromCard Q4TN'
    $creates = @($r.Calls | Where-Object { $_ -match '^gh issue create' })
    Assert-True 'a Bug card folds to the bug label' ($creates.Count -eq 1 -and $creates[0] -match '--label bug') ($r.Calls -join ' | ')
    Assert-True 'a Summary still (TBD) leaves the one line that names the card' ($creates.Count -eq 1 -and $creates[0] -match '--body Toolkit card: Q4TN --assignee') ($creates -join ' | ')

    $r = Invoke-Edit 'tkNewItem -FromCard X9X9'
    Assert-True 'an id that is not a card is refused (exit 2) and asks for no issue' ($r.Text -match "No card with id 'X9X9'" -and $r.Text -match 'EXIT=2' -and -not (@($r.Calls) -match '^gh issue create')) $r.Text

    $r = Invoke-Edit 'tkNewItem -FromCard K7M2 -Title Other'
    Assert-True '-Title beside -FromCard is refused: the card names the issue' ($r.Text -match '-Title has nothing to do' -and $r.Text -match 'EXIT=2') $r.Text

    Set-ActiveSpace 'board'
    New-OfflineCard -Space 'board' -FileName 'TaskW3KC-a-board-card.prompt.md' -Heading 'Task W3KC: A board card' -Summary 'x' | Out-Null
    $r = Invoke-Edit 'tkNewItem -FromCard W3KC'
    Assert-True 'on Azure DevOps -FromCard is refused with the reason (exit 2)' ($r.Text -match 'tracker is not GitHub' -and $r.Text -match 'EXIT=2') $r.Text
    Assert-True 'and nothing is created on either tracker' (-not (@($r.Calls) -match '^(gh issue create|az boards work-item create)')) ($r.Calls -join ' | ')

    Set-ActiveSpace 'solo'
    $solo = New-OfflineCard -Space 'solo' -FileName 'TaskH7KP-a-card-of-my-own.prompt.md' -Heading 'Task H7KP: A card of my own' -Summary 'x'
    $soloBytes = [System.IO.File]::ReadAllBytes($solo)
    $r = Invoke-Edit 'tkNewItem -FromCard H7KP'
    Assert-True 'a Space with no tracker is refused in its own sentence, not a tier' ($r.Text -match 'no tracker to publish card H7KP on' -and $r.Text -match 'EXIT=2' -and -not ($r.Text -match 'Tier 1')) $r.Text
    Assert-True 'and the card is not written' ([System.Convert]::ToBase64String([System.IO.File]::ReadAllBytes($solo)) -eq [System.Convert]::ToBase64String($soloBytes))

    $r = Invoke-Edit 'tkNewItem -Help'
    Assert-True 'NewItem -Help names -FromCard and -WhatIf' ($r.Text -match '-FromCard' -and $r.Text -match '-WhatIf') $r.Text
    Assert-True 'NewItem -Help says -Parent is a sub-issue on GitHub' ($r.Text -match 'sub-issue') $r.Text

    # -- NewItem -Parent on GitHub: Team Agile's Split ---------------------------
    Write-Host ""
    Write-Host "  NewItem -Parent -- a sub-issue, typed" -ForegroundColor Cyan
    Set-ActiveSpace 'widgets'
    $subCall = 'gh api --method POST repos/acme/widgets/issues/12/sub_issues -F sub_issue_id=9001'

    $r = Invoke-Edit "tkNewItem -Title 'The read half' -Parent 12 -WhatIf"
    Assert-True '-Parent -WhatIf names the parent and prints the sub-issue call' ($r.Text -match 'DRY RUN' -and $r.Text -match 'Parent:\s+#12 A thing worth pinning' -and $r.Text -match 'issues/12/sub_issues -F sub_issue_id=') $r.Text
    Assert-True 'and the task-list fallback it would use' ($r.Text -match 'gh issue edit 12 --repo acme/widgets --body') $r.Text
    Assert-True 'and reads the parent first, so a wrong number is refused in the dry run too' (@($r.Calls) -contains 'gh issue view 12 --repo acme/widgets --json number,title,url') ($r.Calls -join ' | ')
    Assert-True 'and sends nothing: no create, no sub-issue, no body edit' (-not (@($r.Calls) -match '^gh issue (create|edit)|sub_issues')) ($r.Calls -join ' | ')
    Assert-True 'and exits 0' ($r.Text -match 'EXIT=0') $r.Text

    $r = Invoke-Edit "tkNewItem -Title 'The read half' -Parent 12"
    $calls = @($r.Calls)
    $creates = @($calls | Where-Object { $_ -match '^gh issue create' })
    Assert-True '-Parent creates one issue on the Space''s repo' ($creates.Count -eq 1 -and $creates[0] -match '--repo acme/widgets') ($calls -join ' | ')
    Assert-True 'reads the new issue''s id' ($calls -contains 'gh api repos/acme/widgets/issues/41') ($calls -join ' | ')
    Assert-True 'and adds it as a sub-issue of the parent, by id, through the REST route' ($calls -contains $subCall) ($calls -join ' | ')
    $createAt = [array]::IndexOf([string[]]$calls, [string]$creates[0])
    $subAt = [array]::IndexOf([string[]]$calls, $subCall)
    Assert-True 'after the create, never before it' ($createAt -ge 0 -and $subAt -gt $createAt) ($calls -join ' | ')
    Assert-True 'and no query string reaches gh: no & in any argument' (-not (@($calls) -match '&')) ($calls -join ' | ')
    Assert-True 'a sub-issue that lands leaves the parent''s body alone' (-not (@($calls) -match '^gh issue edit')) ($calls -join ' | ')
    Assert-True 'it says the link, with the parent''s URL' ($r.Text -match 'Linked: #41 is a sub-issue of #12 -- https://github\.com/acme/widgets/issues/12') $r.Text
    Assert-True 'and exits 0' ($r.Text -match 'EXIT=0') $r.Text

    $r = Invoke-Edit "tkNewItem -Title 'The read half' -Parent 12" -SubIssuesRefused
    $calls = @($r.Calls)
    Assert-True 'where GitHub refuses the sub-issue, the route was still asked first' ($calls -contains $subCall) ($calls -join ' | ')
    Assert-True 'then the parent''s body is read as it is now' ($calls -contains 'gh issue view 12 --repo acme/widgets --json body') ($calls -join ' | ')
    Assert-True 'and written back with one task-list line appended' ($calls -contains 'gh issue edit 12 --repo acme/widgets --body The parent body.\n\n- [ ] #41') ($calls -join ' | ')
    Assert-True 'the output says the sub-issue was refused and the task-list line used' ($r.Text -match 'refused the sub-issue link' -and $r.Text -match 'HTTP 404' -and $r.Text -match "Linked: '- \[ \] #41' added to #12's body") $r.Text
    Assert-True 'and exits 0' ($r.Text -match 'EXIT=0') $r.Text

    $r = Invoke-Edit "tkNewItem -Title 'The read half' -Parent 99"
    Assert-True 'a parent that does not exist is refused (exit 2)' ($r.Text -match 'No issue #99 on acme/widgets to be the parent' -and $r.Text -match 'EXIT=2') $r.Text
    Assert-True 'and nothing is created' (-not (@($r.Calls) -match '^gh issue create|sub_issues')) ($r.Calls -join ' | ')
    Assert-True 'and the refusal is said once, not wrapped in a generic error' (-not ($r.Text -match 'exit code 2')) $r.Text

    $r = Invoke-Edit "tkNewItem -Title 'The read half' -Priority 2"
    Assert-True '-Priority is still refused by name on GitHub (exit 2), and -Parent is no longer in that sentence' ($r.Text -match '-Priority has no GitHub shape' -and $r.Text -notmatch 'parent link' -and $r.Text -match 'EXIT=2') $r.Text
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
