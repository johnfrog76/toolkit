<#
.SYNOPSIS
    PublishPR -- the ship flow's second stage: the card's draft pull request on
    Azure DevOps flipped to ready, typed as the VERB in a fresh shell.
.DESCRIPTION
    Typed as the verb in a fresh child shell against a scratch package and hub
    (AGENTS.md: a suite that runs a script directly does not test the verb), the
    same sandbox Test-EditItem.ps1 builds. `az`, `gh` and Invoke-RestMethod are
    replaced in the child by functions that WRITE DOWN every call and change
    nothing -- the REST stub is Test-ExitCodes.ps1's shape -- so no pull request
    anywhere is touched. Holds:

      - -WhatIf prints the exact PATCH and its body, asks az for no token, makes
        no REST call, and leaves the card's bytes as they were.
      - The success path: one token from az, one GET, one PATCH with
        {"isDraft":false} to the address the card's PR URL: line names, and one
        line under that line -- `PR published: <url>` -- in the card's own line
        endings, with no BOM. Run again, the line is not written twice.
      - The refusals, each exit 2 in one block and with nothing written: a card
        with no PR URL: line, a pull request Azure DevOps says is already ready,
        a GitHub pull request (the hint is `gh pr ready <url>`), and an id that is
        not a card.
#>
$ErrorActionPreference = 'Stop'
$pkgRoot = Split-Path $PSScriptRoot -Parent
$script:passed = 0
$script:failed = 0

function Assert-True($label, $cond, $detail = '') {
    if ($cond) { $script:passed++; Write-Host "  PASS  $label" -ForegroundColor Green }
    else { $script:failed++; Write-Host "  FAIL  $label$(if ($detail) { " -- $($detail.ToString().Trim())" })" -ForegroundColor Red }
}

# The namespace under test, read from config rather than typed (Test-ExitCodes.ps1).
. (Join-Path (Join-Path $pkgRoot 'Scripts') 'Resolve-CliPrefix.ps1')
$cfgPrefix = Resolve-P20ConfigPrefix -PackageRoot $pkgRoot

$root = Join-Path ([System.IO.Path]::GetTempPath()) ("p20-publishpr-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
$pkgDir = Join-Path $root 'pkg'
$hubDir = Join-Path $root 'hub'
$logDir = Join-Path $root 'log'
$callLog = Join-Path $root 'calls.log'

$adoPrUrl = 'https://dev.azure.com/acme-org/Acme%20Project/_git/widget-api/pullrequest/77'
$adoApi = 'https://dev.azure.com/acme-org/Acme%20Project/_apis/git/repositories/widget-api/pullrequests/77?api-version=7.1'
$ghPrUrl = 'https://github.com/acme/widgets/pull/12'

function New-PublishSandbox {
    New-Item -ItemType Directory -Path $pkgDir, $hubDir, $logDir -Force | Out-Null
    foreach ($file in @('utilities.psm1', 'config.default.json', 'consts.json')) { Copy-Item (Join-Path $pkgRoot $file) $pkgDir -Force }
    Copy-Item (Join-Path $pkgRoot 'Scripts') $pkgDir -Recurse -Force
    Copy-Item (Join-Path $pkgRoot 'Config')  $pkgDir -Recurse -Force
    $hubJson = @'
{
  "hub": 1,
  "spaces": [
    { "slug": "board",   "name": "Board",   "status": "active", "promptsFolder": "board",   "org": "https://dev.azure.com/acme-org" },
    { "slug": "widgets", "name": "Widgets", "status": "active", "promptsFolder": "widgets", "org": "https://github.com/acme/widgets" }
  ]
}
'@
    [System.IO.File]::WriteAllText((Join-Path $hubDir 'hub.json'), $hubJson, (New-Object System.Text.UTF8Encoding($false)))
    foreach ($f in @('board', 'widgets')) { New-Item -ItemType Directory -Path (Join-Path $hubDir "$f/current") -Force | Out-Null }
}

# A card the way NewPR leaves one: the PR URL: line above ## Work Item Info.
function New-ShippedCard {
    param([string]$Space, [string]$FileName, [string]$Heading, [string]$PrUrl, [switch]$Crlf)
    $prBlock = ''
    if ($PrUrl) { $prBlock = "PR URL: $PrUrl`n`n" }
    $text = "# $Heading`n`n## Branch`nyou/x`n`n## Git`nCommits:`n- a41c2e9 the change`n`n$prBlock## Work Item Info`nPriority: 2`n`n---`n`n**Created:** 2026-10-01`n"
    if ($Crlf) { $text = $text -replace "`n", "`r`n" }
    $path = Join-Path $hubDir "$Space/current/$FileName"
    [System.IO.File]::WriteAllText($path, $text, (New-Object System.Text.UTF8Encoding($false)))
    return $path
}

function Set-ActiveSpace([string]$slug) {
    $local = [ordered]@{ quietStart = $true; promptsRoot = $hubDir; activeSpace = $slug }
    [System.IO.File]::WriteAllText((Join-Path $pkgDir 'config.local.json'), ($local | ConvertTo-Json -Depth 4), (New-Object System.Text.UTF8Encoding($false)))
}

function Get-Bytes([string]$path) { return [System.Convert]::ToBase64String([System.IO.File]::ReadAllBytes($path)) }

# The child: the package alone on PSModulePath, no webhook in reach, and az, gh and
# Invoke-RestMethod replaced by functions that record the call and change nothing.
# The REST GET answers an active draft, or -- with P20_TEST_PR_READY set -- a pull
# request that is already ready.
function New-ChildPreamble {
    $pkg = $pkgDir -replace "'", "''"; $hub = $hubDir -replace "'", "''"; $log = $logDir -replace "'", "''"; $calls = $callLog -replace "'", "''"
    return @"
`$env:PSModulePath = '$pkg'
`$env:PROMPTS_ROOT = '$hub'
`$env:P20_USAGE_LOG_DIR = '$log'
Get-ChildItem Env: | Where-Object { `$_.Name -like 'TEAMS_WEBHOOK_*' } | ForEach-Object { Remove-Item "Env:\`$(`$_.Name)" -ErrorAction SilentlyContinue }
function global:az {
    Add-Content -Path '$calls' -Value ("az " + (`$args -join ' '))
    `$global:LASTEXITCODE = 0
    if (`$args[0] -eq 'account' -and `$args[1] -eq 'get-access-token') { return 'stub-token' }
}
function global:gh {
    Add-Content -Path '$calls' -Value ("gh " + (`$args -join ' '))
    `$global:LASTEXITCODE = 0
}
function global:Invoke-RestMethod {
    param(`$Uri, `$Headers, `$Method, `$Body)
    `$line = "REST `$Method `$Uri"
    if (`$Body) { `$line += " `$Body" }
    Add-Content -Path '$calls' -Value `$line
    if ("`$Method" -eq 'Get') { return [pscustomobject]@{ pullRequestId = 77; status = 'active'; isDraft = (-not `$env:P20_TEST_PR_READY) } }
    return [pscustomobject]@{ pullRequestId = 77; status = 'active'; isDraft = `$false }
}
Import-Module '$pkg/utilities.psm1' -Force -DisableNameChecking *>`$null
# Tier 1: the tracker "answers" -- the stubs above are what it answers with.
`$global:P20Env = [pscustomobject]@{ Tier = 1 }
"@
}

function Invoke-Publish {
    param([string]$Snippet, [switch]$Ready)
    if (Test-Path $callLog) { Remove-Item $callLog -Force }
    $runner = Join-Path $root ("run-" + [guid]::NewGuid().ToString('N').Substring(0, 8) + ".ps1")
    $pre = New-ChildPreamble
    if ($Ready) { $pre = "`$env:P20_TEST_PR_READY = '1'`n" + $pre }
    [System.IO.File]::WriteAllText($runner, ($pre + "`n" + $Snippet + "`n; `"EXIT=`$LASTEXITCODE`"`n"), (New-Object System.Text.UTF8Encoding($false)))
    $out = & pwsh -NoProfile -File $runner 2>&1
    $text = (($out | ForEach-Object { $_.ToString() }) -join "`n")
    $calls = if (Test-Path $callLog) { @(Get-Content $callLog) } else { @() }
    return [pscustomobject]@{ Text = $text; Calls = $calls }
}

function Get-TokenCalls($calls) { return @($calls | Where-Object { $_ -match '^az account get-access-token' }) }
function Get-RestCalls($calls) { return @($calls | Where-Object { $_ -match '^REST ' }) }

Write-Host ""
Write-Host "  PublishPR -- the draft published, typed" -ForegroundColor Cyan
Write-Host "  ---------------------------------------" -ForegroundColor DarkGray
Write-Host ""

try {
    New-PublishSandbox
    Set-ActiveSpace 'board'
    $shipped = New-ShippedCard -Space 'board' -FileName 'Task4242-ship-the-widget.prompt.md' -Heading 'Task 4242: Ship the widget' -PrUrl $adoPrUrl -Crlf
    $noPr = New-ShippedCard -Space 'board' -FileName 'TaskM3PX-not-shipped-yet.prompt.md' -Heading 'Task M3PX: Not shipped yet'

    # -- -WhatIf: the exact call, nothing sent ----------------------------------
    $before = Get-Bytes $shipped
    $r = Invoke-Publish "${cfgPrefix}PublishPR 4242 -WhatIf"
    Assert-True '-WhatIf prints the exact PATCH address' ($r.Text.Contains("PATCH $adoApi")) $r.Text
    Assert-True '-WhatIf prints the body' ($r.Text.Contains('{"isDraft":false}')) $r.Text
    Assert-True '-WhatIf asks az for no token' ((Get-TokenCalls $r.Calls).Count -eq 0) ($r.Calls -join ' | ')
    Assert-True '-WhatIf makes no REST call' ((Get-RestCalls $r.Calls).Count -eq 0) ($r.Calls -join ' | ')
    Assert-True '-WhatIf writes nothing into the card' ((Get-Bytes $shipped) -eq $before)
    Assert-True '-WhatIf exits 0' ($r.Text -match 'EXIT=0') $r.Text

    # -- Success: one PATCH, one line -------------------------------------------
    $r = Invoke-Publish "${cfgPrefix}PublishPR 4242"
    $rest = Get-RestCalls $r.Calls
    $patches = @($rest | Where-Object { $_ -match '^REST Patch ' })
    $tokens = @(Get-TokenCalls $r.Calls)
    Assert-True 'one token from az, for the Azure DevOps resource' ($tokens.Count -eq 1 -and $tokens[0] -match '--resource 499b84ac-1321-427f-aa17-267ca6975798') ($r.Calls -join ' | ')
    Assert-True 'it reads the pull request first' ($rest.Count -ge 1 -and $rest[0] -eq "REST Get $adoApi") ($rest -join ' | ')
    Assert-True 'and PATCHes it once, with isDraft false, at the card''s address' ($patches.Count -eq 1 -and $patches[0] -eq "REST Patch $adoApi {`"isDraft`":false}") ($rest -join ' | ')
    Assert-True 'it says Published: <url>' ($r.Text.Contains("Published: $adoPrUrl")) $r.Text
    $after = [System.IO.File]::ReadAllText($shipped)
    $lineCount = ([regex]::Matches($after, '(?m)^PR published: ' + [regex]::Escape($adoPrUrl) + '\r?$')).Count
    Assert-True 'the card carries the line once' ($lineCount -eq 1) $after
    Assert-True 'directly under the PR URL: line' ($after.Contains("PR URL: $adoPrUrl`r`nPR published: $adoPrUrl`r`n")) $after
    Assert-True 'a CRLF card stays CRLF: no bare LF anywhere' (-not ($after -match '(?<!\r)\n')) $after
    $raw = [System.IO.File]::ReadAllBytes($shipped)
    Assert-True 'and it is written with no BOM' (-not ($raw.Length -ge 3 -and $raw[0] -eq 0xEF -and $raw[1] -eq 0xBB -and $raw[2] -eq 0xBF))
    Assert-True 'success exits 0' ($r.Text -match 'EXIT=0') $r.Text

    # -- Again: the line is not written twice -----------------------------------
    $once = Get-Bytes $shipped
    $r = Invoke-Publish "${cfgPrefix}PublishPR 4242"
    Assert-True 'run again, the card is not written a second time' ((Get-Bytes $shipped) -eq $once) ([System.IO.File]::ReadAllText($shipped))
    Assert-True 'and it says so' ($r.Text -match 'not written again') $r.Text

    # -- Refusal: already ready ---------------------------------------------------
    $r = Invoke-Publish "${cfgPrefix}PublishPR 4242" -Ready
    Assert-True 'a pull request already ready is refused (exit 2)' ($r.Text -match 'already ready' -and $r.Text -match 'EXIT=2') $r.Text
    Assert-True 'and nothing is PATCHed' (@(Get-RestCalls $r.Calls | Where-Object { $_ -match '^REST Patch ' }).Count -eq 0) ($r.Calls -join ' | ')
    Assert-True 'and the card is not written' ((Get-Bytes $shipped) -eq $once)
    Assert-True 'and the refusal is said once, not wrapped in a generic error' ((@([regex]::Matches($r.Text, '(?m)^Error: ')).Count -eq 1) -and -not ($r.Text -match 'exit code 2')) $r.Text

    # -- Refusal: no PR URL: line -------------------------------------------------
    $noPrBytes = Get-Bytes $noPr
    $r = Invoke-Publish "${cfgPrefix}PublishPR M3PX"
    Assert-True 'a card with no PR URL: line is refused (exit 2)' ($r.Text -match 'has no PR URL: line' -and $r.Text -match 'EXIT=2') $r.Text
    Assert-True 'and its hint is NewPR -Draft' ($r.Text -match "Hint:.*${cfgPrefix}NewPR <id> -Draft") $r.Text
    Assert-True 'and no token is asked for and no REST call made' ((Get-TokenCalls $r.Calls).Count -eq 0 -and (Get-RestCalls $r.Calls).Count -eq 0) ($r.Calls -join ' | ')
    Assert-True 'and the card is not written' ((Get-Bytes $noPr) -eq $noPrBytes)

    # -- Refusal: an id that is not a card ----------------------------------------
    $r = Invoke-Publish "${cfgPrefix}PublishPR X9X9"
    Assert-True 'an id that is not a card is refused (exit 2)' ($r.Text -match "No card with id 'X9X9'" -and $r.Text -match 'EXIT=2' -and (Get-RestCalls $r.Calls).Count -eq 0) $r.Text

    # -- Refusal: a GitHub pull request ---------------------------------------------
    Set-ActiveSpace 'widgets'
    $gh = New-ShippedCard -Space 'widgets' -FileName 'TaskG7HB-a-github-card.prompt.md' -Heading 'Task G7HB: A GitHub card' -PrUrl $ghPrUrl
    $ghBytes = Get-Bytes $gh
    $r = Invoke-Publish "${cfgPrefix}PublishPR G7HB"
    Assert-True 'a GitHub pull request is refused (exit 2)' ($r.Text -match 'is a GitHub pull request' -and $r.Text -match 'EXIT=2') $r.Text
    Assert-True 'and the hint is gh pr ready <url>' ($r.Text.Contains("gh pr ready $ghPrUrl")) $r.Text
    Assert-True 'and nothing is called on either tracker' ((Get-RestCalls $r.Calls).Count -eq 0 -and -not (@($r.Calls) -match '^gh pr ')) ($r.Calls -join ' | ')
    Assert-True 'and the card is not written' ((Get-Bytes $gh) -eq $ghBytes)

    # -- The help -----------------------------------------------------------------
    $r = Invoke-Publish "${cfgPrefix}PublishPR -Help"
    Assert-True '-Help names -Card and -WhatIf' ($r.Text -match '-Card' -and $r.Text -match '-WhatIf' -and $r.Text -match "${cfgPrefix}PublishPR") $r.Text
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
