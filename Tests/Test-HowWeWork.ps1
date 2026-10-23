<#
.SYNOPSIS
    HowWeWork -- a Space worked with agents gets its how-we-work note, typed.
.DESCRIPTION
    Typed as the VERB in a fresh child shell against a scratch copy of the
    package and of samples/hub (AGENTS.md: a suite that runs a script directly
    does not test the verb; samples/hub is never used in place). Holds:

    1. Registration  the command table the bridge reads, -Help from config,
                     the autoload manifest.
    2. The template  agentic/how-we-work.template.md names roles and loops and
                     never a model, a machine or a plan; its two slots are there.
    3. Alone, team   a GitHub Space nobody has answered (alone, default), a
                     Space with no tracker (alone, derived) and an Azure DevOps
                     Space (team, derived) each say so, exit 0, write nothing.
    4. -WhatIf       on a Space answered agents: the path and the text, exit 0,
                     nothing written.
    5. The write     once: <space folder>/agentic/how-we-work.md, UTF-8 with no
                     BOM, LF, the Space's name and tracker filled, no slot left,
                     no model, machine or plan named; the AGENTS.md line printed.
    6. Never over it the second run refuses, exit 2, naming the path, and a
                     file a person edited keeps every byte.
    7. StartWork     quotes the written note under "How we work in".
    8. Refusals      no slug and an unknown slug: exit 2, nothing written.

    Run:  pwsh -File Tests/Test-HowWeWork.ps1
#>
param([switch]$Help)

if ($Help) { Get-Help $MyInvocation.MyCommand.Path -Detailed; return }

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

$root = Join-Path ([System.IO.Path]::GetTempPath()) ("p20-howwework-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
$pkgDir = Join-Path $root 'pkg'
$hubDir = Join-Path $root 'hub'
$logDir = Join-Path $root 'log'
$utf8 = New-Object System.Text.UTF8Encoding($false)
$notePath = Join-Path $hubDir 'github-demo/agentic/how-we-work.md'

# What the note may never name (the card's rule: roles and loops, never models,
# machines or plans). Whole words, case ignored.
$forbidden = '\b(fable|opus|sonnet|haiku|gpt|claude|anthropic|openai|gemini|copilot|mac|macs|macbook|mini|laptop|desktop|pc|pcs|windows|linux|machine|machines|plan|plans|subscription|budget|quota|weekly|pro|max|enterprise)\b'

function Invoke-HowWeWork {
    param([string]$Snippet, [switch]$Quiet)
    $pkg = $pkgDir -replace "'", "''"; $log = $logDir -replace "'", "''"
    $quietLine = ''
    if ($Quiet) { $quietLine = "`$env:TOOLKIT_QUIET_STARTUP = '1'" }
    $text = @"
`$env:PSModulePath = '$pkg'
`$env:PROMPTS_ROOT = ''
`$env:P20_USAGE_LOG_DIR = '$log'
Remove-Item Env:P20_ACTIVE_SPACE -ErrorAction SilentlyContinue
Get-ChildItem Env: | Where-Object { `$_.Name -like 'TEAMS_WEBHOOK_*' } | ForEach-Object { Remove-Item "Env:\`$(`$_.Name)" -ErrorAction SilentlyContinue }
$quietLine
Import-Module '$pkg/Prompt20Toolkit/Prompt20Toolkit.psd1' -Force 3>`$null 6>`$null
$Snippet
"EXIT=`$LASTEXITCODE"
"@
    $runner = Join-Path $root ("run-" + [guid]::NewGuid().ToString('N').Substring(0, 8) + ".ps1")
    [System.IO.File]::WriteAllText($runner, $text, $utf8)
    $out = & pwsh -NoProfile -NonInteractive -File $runner 2>&1
    Remove-Item $runner -Force -ErrorAction SilentlyContinue
    $all = (($out | ForEach-Object { $_.ToString() }) -join "`n")
    $code = ''
    $m = [regex]::Matches($all, 'EXIT=(\d*)')
    if ($m.Count) { $code = $m[$m.Count - 1].Groups[1].Value }
    return [pscustomobject]@{ All = $all; Exit = $code }
}
function Get-Snapshot {
    return ((@(Get-ChildItem -LiteralPath $hubDir -Recurse -Force | Sort-Object FullName | ForEach-Object {
                    if ($_.PSIsContainer) { "$($_.FullName)|dir" } else { "$($_.FullName)|$([System.IO.File]::ReadAllText($_.FullName))" }
                })) -join "`n")
}
function Set-Answer([string]$Value) {
    # The Space's answer, straight into the scratch hub.json (Config's own suite
    # holds the writer; here the answer is only the input).
    $path = Join-Path $hubDir 'hub.json'
    $hub = Get-Content -Raw -LiteralPath $path | ConvertFrom-Json
    foreach ($s in @($hub.spaces)) {
        if ($s.slug -eq 'github-demo') {
            if ($s.PSObject.Properties['howIWork']) { $s.howIWork = $Value } else { $s | Add-Member -NotePropertyName howIWork -NotePropertyValue $Value }
        }
    }
    [System.IO.File]::WriteAllText($path, ($hub | ConvertTo-Json -Depth 10), $utf8)
}

Write-Host ""
Write-Host "  HowWeWork -- the orchestrating answer's note, typed" -ForegroundColor Cyan
Write-Host "  ---------------------------------------------------" -ForegroundColor DarkGray
Write-Host ""

try {
    New-Item -ItemType Directory -Path $pkgDir, $logDir -Force | Out-Null
    foreach ($file in @('utilities.psm1', 'config.default.json', 'consts.json')) { Copy-Item (Join-Path $pkgRoot $file) $pkgDir -Force }
    foreach ($folder in @('Scripts', 'Config', 'Prompt20Toolkit', 'templates', 'agentic')) { Copy-Item (Join-Path $pkgRoot $folder) $pkgDir -Recurse -Force }
    # samples/hub, COPIED out: the GitHub demo Space is where the acceptance is shown.
    Copy-Item (Join-Path $pkgRoot 'samples/hub') $hubDir -Recurse -Force
    # An Azure DevOps Space beside the samples' (the shipped Azure demo has no address, so it reads alone).
    $hubJsonPath = Join-Path $hubDir 'hub.json'
    $hubJson = Get-Content -Raw -LiteralPath $hubJsonPath | ConvertFrom-Json
    $hubJson.spaces = @($hubJson.spaces) + @([pscustomobject]@{ slug = 'board'; name = 'Board'; status = 'active'; promptsFolder = 'board'; org = 'https://dev.azure.com/acme-org' })
    [System.IO.File]::WriteAllText($hubJsonPath, ($hubJson | ConvertTo-Json -Depth 10), $utf8)
    New-Item -ItemType Directory -Path (Join-Path $hubDir 'board/current') -Force | Out-Null
    $local = [ordered]@{ quietStart = $true; promptsRoot = ($hubDir -replace '\\', '/'); activeSpace = 'github-demo'; features = [ordered]@{ solitaireAgile = $true } }
    [System.IO.File]::WriteAllText((Join-Path $pkgDir 'config.local.json'), ($local | ConvertTo-Json -Depth 4), $utf8)

    # -- 1. Registration ----------------------------------------------------------------
    Write-Host "-- Registration ----------------------------------------" -ForegroundColor Cyan
    $reg = Invoke-HowWeWork "'MAP=' + (Get-P20CommandMap); tkHowWeWork -Help"
    Assert-True 'HowWeWork is in the command table the bridge reads' ($reg.All -match '"HowWeWork":\s*"New-P20HowWeWork"') $reg.All
    Assert-True '-Help prints the usage from config' ($reg.All -match 'tkHowWeWork <slug> \[-WhatIf\] \[-Help\]') $reg.All
    $manifest = Get-Content (Join-Path $pkgRoot 'Prompt20Toolkit/Prompt20Toolkit.psd1') -Raw
    Assert-True 'the autoload manifest names tkHowWeWork (core, like the Studio''s verbs)' ($manifest -match "'tkHowWeWork',")

    # -- 2. The template ------------------------------------------------------------------
    Write-Host ""
    Write-Host "-- The template: roles and loops ------------------------" -ForegroundColor Cyan
    $template = [System.IO.File]::ReadAllText((Join-Path $pkgRoot 'agentic/how-we-work.template.md'))
    $hits = @([regex]::Matches($template, $forbidden, 'IgnoreCase') | ForEach-Object { $_.Value })
    Assert-True 'the template names no model, machine or plan' ($hits.Count -eq 0) ("found: " + ($hits -join ', '))
    Assert-True 'it carries the two slots, {space} and {tracker}' ($template.Contains('{space}') -and $template.Contains('{tracker}'))
    foreach ($part in @('## The seats', '## The loop', '## The hand-off rule', '## The relay rule', '## The stand-in rule', 'A seat is not a model')) {
        Assert-True "it has $part" ($template.Contains($part))
    }
    Assert-True 'it is not a shipped prompt (no .prompt.md), so the Prompts index does not list it' (-not (Test-Path (Join-Path $pkgRoot 'agentic/how-we-work.prompt.md')))

    # -- 3. Alone and team write nothing --------------------------------------------------
    Write-Host ""
    Write-Host "-- Alone and team: nothing to write ---------------------" -ForegroundColor Cyan
    $before = Get-Snapshot
    $a = Invoke-HowWeWork 'tkHowWeWork github-demo'
    Assert-True 'a GitHub Space nobody answered is alone: said, exit 0' ($a.Exit -eq '0' -and $a.All -match 'worked alone \(default\)' -and $a.All -match 'Nothing written') $a.All
    Assert-True 'and the line that answers it is named' ($a.All -match 'tkConfig -Set spaces\.github-demo\.howIWork=agents -Hub') $a.All
    $d = Invoke-HowWeWork 'tkHowWeWork demo'
    Assert-True 'a Space with no tracker is alone, derived: exit 0' ($d.Exit -eq '0' -and $d.All -match 'worked alone \(derived\)') $d.All
    $t = Invoke-HowWeWork 'tkHowWeWork board'
    Assert-True 'an Azure DevOps Space is on a team, derived: exit 0' ($t.Exit -eq '0' -and $t.All -match 'worked on a team \(derived\)') $t.All
    Set-Answer 'alone'
    $before = Get-Snapshot
    $c = Invoke-HowWeWork 'tkHowWeWork github-demo'
    Assert-True 'a GitHub Space answered alone: chosen, nothing written' ($c.Exit -eq '0' -and $c.All -match 'worked alone \(chosen\)') $c.All
    Assert-Equal 'alone and team wrote nothing' $before (Get-Snapshot)
    Assert-True 'no note on the GitHub demo Space' (-not (Test-Path -LiteralPath $notePath))

    # -- 4. -WhatIf --------------------------------------------------------------------------
    Write-Host ""
    Write-Host "-- -WhatIf --------------------------------------------" -ForegroundColor Cyan
    Set-Answer 'agents'
    $before = Get-Snapshot
    $w = Invoke-HowWeWork 'tkHowWeWork github-demo -WhatIf'
    Assert-True '-WhatIf names the path it would write, exit 0' ($w.Exit -eq '0' -and $w.All.Contains("[WhatIf] would write $notePath")) $w.All
    Assert-True 'and prints the text, the Space''s name filled' ($w.All -match '(?m)^# How we work in GitHub demo$') $w.All
    Assert-Equal '-WhatIf writes nothing' $before (Get-Snapshot)
    Assert-True '-WhatIf leaves no file' (-not (Test-Path -LiteralPath $notePath))

    # -- 5. The write -------------------------------------------------------------------------
    Write-Host ""
    Write-Host "-- The write ------------------------------------------" -ForegroundColor Cyan
    $r = Invoke-HowWeWork 'tkHowWeWork github-demo'
    Assert-True 'the orchestrating answer writes the note, exit 0' ($r.Exit -eq '0' -and (Test-Path -LiteralPath $notePath)) $r.All
    Assert-True 'and prints the line to paste into the repository''s AGENTS.md' ($r.All.Contains("How we work here: $notePath")) $r.All
    $bytes = [System.IO.File]::ReadAllBytes($notePath)
    Assert-True 'UTF-8 with no BOM' (-not ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF))
    $written = [System.IO.File]::ReadAllText($notePath)
    Assert-True 'LF, no CR (Write-CardText -New)' (-not $written.Contains("`r"))
    Assert-True 'the Space''s name in the title' ($written -match '(?m)^# How we work in GitHub demo$') $written
    Assert-True 'the Space''s tracker filled in' ($written.Contains('GitHub, `johnfrog76/recipe-box-demo`')) $written
    Assert-True 'no slot left unfilled' (-not ($written.Contains('{space}') -or $written.Contains('{tracker}')))
    $hits = @([regex]::Matches($written, $forbidden, 'IgnoreCase') | ForEach-Object { $_.Value })
    Assert-True 'the written note names no model, machine or plan' ($hits.Count -eq 0) ("found: " + ($hits -join ', '))

    # -- 6. Never over it ---------------------------------------------------------------------
    Write-Host ""
    Write-Host "-- Never over a file that is there --------------------" -ForegroundColor Cyan
    $edited = $written + "`nOur own line: reviews happen before lunch.`n"
    [System.IO.File]::WriteAllText($notePath, $edited, $utf8)
    $before = Get-Snapshot
    $again = Invoke-HowWeWork 'tkHowWeWork github-demo'
    Assert-True 'the second run refuses, exit 2, naming the path' ($again.Exit -eq '2' -and $again.All.Contains("$notePath is already there")) $again.All
    Assert-True 'one Error block, no generic exit-code block' ((@([regex]::Matches($again.All, '(?m)^Error: ')).Count -eq 1) -and $again.All -notmatch 'exit code') $again.All
    Assert-Equal 'the edited note keeps every byte' $edited ([System.IO.File]::ReadAllText($notePath))
    $wi = Invoke-HowWeWork 'tkHowWeWork github-demo -WhatIf'
    Assert-True '-WhatIf over an existing note is the same refusal' ($wi.Exit -eq '2' -and $wi.All.Contains('is already there')) $wi.All
    Assert-Equal 'and the hub is untouched' $before (Get-Snapshot)
    $q = Invoke-HowWeWork 'tkHowWeWork github-demo' -Quiet
    Assert-True 'a non-interactive caller (the bridge) gets the same refusal' ($q.All -match 'is already there') $q.All

    # -- 7. StartWork quotes it ----------------------------------------------------------------
    Write-Host ""
    Write-Host "-- StartWork quotes it --------------------------------" -ForegroundColor Cyan
    $s = Invoke-HowWeWork 'tkStartWork 6'
    Assert-True 'StartWork <id> on the Space quotes the note under How we work in' ($s.Exit -eq '0' -and $s.All -match '(?m)^## How we work in GitHub demo \(github-demo/agentic/how-we-work\.md\)$') $s.All
    Assert-True 'with its text, the person''s edit included' ($s.All.Contains('Our own line: reviews happen before lunch.') -and $s.All -notmatch 'You work with agents here') $s.All

    # -- 8. Refusals ----------------------------------------------------------------------------
    Write-Host ""
    Write-Host "-- Refusals -------------------------------------------" -ForegroundColor Cyan
    $before = Get-Snapshot
    $none = Invoke-HowWeWork 'tkHowWeWork'
    Assert-True 'no slug: exit 2, the Spaces named' ($none.Exit -eq '2' -and $none.All -match 'Say which Space' -and $none.All -match 'github-demo') $none.All
    $ghost = Invoke-HowWeWork 'tkHowWeWork nowhere'
    Assert-True 'an unknown slug: exit 2' ($ghost.Exit -eq '2' -and $ghost.All -match "'nowhere' is not a Space") $ghost.All
    Assert-Equal 'the refusals wrote nothing' $before (Get-Snapshot)
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
