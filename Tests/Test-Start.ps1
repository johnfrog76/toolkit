<#
.SYNOPSIS
    The Start verb: a first run, end to end, against a scratch copy of the package.

.DESCRIPTION
    Every case runs the REAL module from a snapshot of this working tree that has
    no config.local.json -- a fresh clone -- and types the verb the way a person
    does. It has to: the three defects the first real run found were all in the
    hand-offs a stubbed test cannot see -- the module's fallback hub read as "you
    already have one", Config refusing an org the hub had not declared YET, and a
    helper function that stopped existing after the re-import.

    Nothing here touches the machine's own config or hub: the package is a copy,
    the hub is a temp folder, PROMPTS_ROOT is cleared and the usage log is scratch.

    Run:  pwsh -File Tests/Test-Start.ps1
    Or:   {cliPrefix}TestToolkit -Start

.NOTES
    PowerShell 5.1 compatible (ASCII dashes only).
#>

$pkgRoot = Split-Path -Parent $PSScriptRoot

$script:passed = 0
$script:failed = 0
$script:errors = @()

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

Write-Host ""
Write-Host "=======================================================" -ForegroundColor Cyan
Write-Host "  Start verb -- the first run" -ForegroundColor Cyan
Write-Host "=======================================================" -ForegroundColor Cyan
Write-Host ""

# ---- the sample hub itself ---------------------------------------------------
$samples = Join-Path (Join-Path $pkgRoot 'samples') 'hub'
$manifest = Get-Content (Join-Path $samples 'hub.json') -Raw | ConvertFrom-Json
$demo = @($manifest.spaces | Where-Object { $_.slug -eq 'demo' })[0]
Assert-True 'the sample hub declares the demo org' ($null -ne $demo)
Assert-True "and it is 'local': a first run never contacts Azure DevOps" ($demo.status -eq 'local') "status is '$($demo.status)'"
Assert-True 'with no organisation address to contact' ([string]::IsNullOrEmpty($demo.org))
Assert-True "the sample hub is a plain folder: storeSync 'none'" ($manifest.storeSync -eq 'none')
$sampleCards = @(Get-ChildItem (Join-Path $samples 'demo/current') -Filter '*.prompt.md')
Assert-True 'it has cards in progress' ($sampleCards.Count -ge 3) "$($sampleCards.Count) found"
# The board is the first thing a new user looks at, so the sample hub has a card
# in EVERY lane -- and one card with no work item, which is what the + makes.
$sampleTexts = @($sampleCards | ForEach-Object { Get-Content $_.FullName -Raw })
Assert-True 'a card in Code Review: one has a pull request' (@($sampleTexts | Where-Object { $_ -match '(?m)^PR URL:\s*https://' }).Count -ge 1)
Assert-True 'a card In Progress: one has a commit and no pull request' (@($sampleTexts | Where-Object { $_ -match '(?m)^\s*-\s+[0-9a-f]{7,}\s' -and $_ -notmatch '(?m)^PR URL:\s*https://' }).Count -ge 1)
Assert-True 'a card that is Active: neither' (@($sampleTexts | Where-Object { $_ -notmatch '(?m)^\s*-\s+[0-9a-f]{7,}\s' -and $_ -notmatch '(?m)^PR URL:\s*https://' }).Count -ge 1)
Assert-True 'a Spike with an id of its own, and no work item' (@($sampleCards | Where-Object { $_.Name -cmatch '^Spike-[A-Z0-9]{4}-' }).Count -ge 1 -and (@($sampleTexts | Where-Object { $_ -match '(?m)^# Spike ' -and $_ -match 'not linked' }).Count -ge 1))
Assert-True 'a Welcome card in To do: no work item, no commit, and its tour is checkboxes' (@($sampleCards | Where-Object { $_.Name -ceq 'TaskW3KC-welcome-to-the-toolkit.prompt.md' -and ($t = Get-Content $_.FullName -Raw) -match '(?m)^# Task W3KC: Welcome to the Toolkit' -and $t -match 'not linked' -and $t -notmatch '(?m)^\s*-\s+[0-9a-f]{7,}\s' -and $t -notmatch '(?m)^PR URL:' -and ([regex]::Matches($t, '(?m)^- \[ \] ')).Count -ge 5 }).Count -eq 1)
# Every sample card IS a card: its filename carries an id by the one rule,
# Resolve-CardName.ps1. The Welcome card was typed by hand as W3LC -- L is a look-alike
# the short id's alphabet leaves out -- so the first card a new user met had no id, and
# nothing here asked. Both card folders of every sample Space are read.
. (Join-Path (Split-Path -Parent $samples | Split-Path -Parent) 'Scripts/Resolve-CardName.ps1')
$sampleTypes = Get-P20WorkItemTypes -Config (Get-Content (Join-Path (Split-Path -Parent $samples | Split-Path -Parent) 'config.default.json') -Raw | ConvertFrom-Json)
$samplePattern = Get-P20CardIdPattern -WorkItemTypes $sampleTypes
$allSampleCards = @(Get-ChildItem $samples -Recurse -Filter '*.prompt.md' | Where-Object { $_.Directory.Name -in @('current', 'archive') -and $_.Directory.Parent.Name -in @('demo', 'github-demo', 'azure-demo') })
$noId = @($allSampleCards | Where-Object { -not (Get-P20CardId -Name $_.Name -Pattern $samplePattern) } | ForEach-Object { $_.Name })
Assert-True 'every sample card carries an id by the one rule' ($allSampleCards.Count -ge 10 -and $noId.Count -eq 0) "$($allSampleCards.Count) cards; no id: $($noId -join ', ')"
Assert-True 'and finished ones, stamped closed' (@(Get-ChildItem (Join-Path $samples 'demo/archive') -Filter '*.prompt.md' | Where-Object { (Get-Content $_.FullName -Raw) -match '\*\*Closed:\*\* \d{4}-\d{2}-\d{2}' }).Count -ge 2)
# The GitHub demo: the same product tracked on a public repo, and LOCAL until
# the connect wizard turns it on -- a cold machine with no gh never reads it as
# unreachable. Its cards link to the issues samples/seed-recipe-box.ps1 creates.
$ghDemo = @($manifest.spaces | Where-Object { $_.slug -eq 'github-demo' })[0]
Assert-True 'the sample hub declares the GitHub demo, marked as a sample' ($null -ne $ghDemo -and $ghDemo.example -eq $true)
Assert-True "it ships 'local', so nothing is contacted before Connect" ($ghDemo.status -eq 'local') "status is '$($ghDemo.status)'"
Assert-True 'and its address is the public demo repo, repo-grained' ($ghDemo.org -eq 'https://github.com/johnfrog76/recipe-box-demo') "$($ghDemo.org)"
$ghCards = @(Get-ChildItem (Join-Path $samples 'github-demo/current') -Filter '*.prompt.md')

# Every current sample card ships wearing a cover, and the file the line names is there.
$coverLines = @()
foreach ($c in @($sampleCards) + @($ghCards)) {
    $m = [regex]::Match((Get-Content -LiteralPath $c.FullName -Raw), '(?m)^\*\*Cover:\*\* (\S+)')
    if ($m.Success) { $coverLines += (Join-Path $c.Directory.FullName $m.Groups[1].Value) }
}
Assert-True 'every current sample card wears a cover' ((@($sampleCards).Count + @($ghCards).Count) -eq $coverLines.Count) "$(@($sampleCards).Count + @($ghCards).Count) cards, $($coverLines.Count) cover lines"
Assert-True 'and each cover file ships beside the cards' (@($coverLines | Where-Object { -not (Test-Path -LiteralPath $_) }).Count -eq 0)
Assert-True 'it has cards, each linked to an issue of that repo' ($ghCards.Count -ge 3 -and @($ghCards | Where-Object { (Get-Content $_.FullName -Raw) -match '(?m)^\*\*ADO Link:\*\* https://github\.com/johnfrog76/recipe-box-demo/issues/\d+' }).Count -eq $ghCards.Count) "$($ghCards.Count) found"
$seed = Get-Content (Join-Path (Join-Path $pkgRoot 'samples') 'recipe-box.seed.json') -Raw | ConvertFrom-Json
$seedNumbers = @($seed.issues | ForEach-Object { [int]$_.number })
$linked = @(Get-ChildItem (Join-Path $samples 'github-demo') -Recurse -Filter '*.prompt.md' | ForEach-Object { if ((Get-Content $_.FullName -Raw) -match '/recipe-box/issues/(\d+)') { [int]$Matches[1] } })
Assert-True 'and every issue a card links to is one the seed creates' (@($linked | Where-Object { $seedNumbers -notcontains $_ }).Count -eq 0) (($linked -join ',') + ' vs ' + ($seedNumbers -join ','))
# The Azure demo: config.default.json's 'azure-demo' ('test' before the rename), renamed from Example and made
# honest -- local, no address, so nothing reads it as unreachable -- with cards in
# the sample hub so switching to it is not an empty folder and a warning (B).
$shippedCfg = Get-Content (Join-Path $pkgRoot 'config.default.json') -Raw | ConvertFrom-Json
$azure = @($shippedCfg.spaces | Where-Object { $_.slug -eq 'azure-demo' })[0]
Assert-True 'the shipped Azure demo is named so, and is a sample' ($null -ne $azure -and $azure.name -eq 'Azure demo' -and $azure.example -eq $true) "$($azure.name)"
Assert-True "it ships 'local' with no address -- ready for yours, contacting nothing" ($azure.status -eq 'local' -and [string]::IsNullOrEmpty([string]$azure.org)) "status '$($azure.status)', org '$($azure.org)'"
Assert-True 'and the sample hub carries its cards' (@(Get-ChildItem (Join-Path $samples 'azure-demo/current') -Filter '*.prompt.md').Count -ge 1)
$sampleText = (Get-ChildItem $samples -Recurse -File | ForEach-Object { Get-Content $_.FullName -Raw }) -join "`n"
Assert-True 'nothing in it is a real address or a real organisation' ($sampleText -notmatch '@(?!example\.)[a-z0-9-]+\.(com|org|net)\b' -and $sampleText -notmatch 'dev\.azure\.com/(?!YOUR-ADO-ORG)[A-Za-z]')

# ---- a fresh clone ------------------------------------------------------------
$base = Join-Path ([System.IO.Path]::GetTempPath()) ("p20-start-" + [System.Guid]::NewGuid().Guid.Substring(0, 8))
$pkg = Join-Path $base 'pkg'
New-Item -ItemType Directory -Path $pkg -Force | Out-Null
$files = @()
if (Get-Command git -ErrorAction SilentlyContinue) { $files = @(& git -C $pkgRoot ls-files --cached --others --exclude-standard 2>$null) }
if ($files.Count -eq 0) {
    $files = @(Get-ChildItem $pkgRoot -Recurse -File | Where-Object { $_.FullName -notmatch '[\\/](node_modules|\.git|dist|__pycache__)[\\/]' } |
        ForEach-Object { $_.FullName.Substring($pkgRoot.Length + 1) })
}
foreach ($rel in $files) {
    if ($rel -match '^(web|agent|issues|docs)/' -or $rel -eq 'config.local.json') { continue }  # the CLI half is all this needs
    $src = Join-Path $pkgRoot $rel
    if (-not (Test-Path $src -PathType Leaf)) { continue }
    $dst = Join-Path $pkg $rel
    New-Item -ItemType Directory -Path (Split-Path $dst -Parent) -Force | Out-Null
    Copy-Item $src $dst
}
$prefix = (Get-Content (Join-Path $pkgRoot 'config.default.json') -Raw | ConvertFrom-Json).commandPrefix
$logDir = Join-Path $base 'log'
New-Item -ItemType Directory -Path $logDir -Force | Out-Null

function Invoke-Start {
    # A new shell per case, as a person's would be: no profile, this package only.
    param([string]$Arguments, [string]$After = '')
    $command = "`$env:PSModulePath = '$pkg'; `$env:PROMPTS_ROOT = ''; `$env:P20_USAGE_LOG_DIR = '$logDir'; " +
        "Import-Module '$pkg/Prompt20Toolkit/Prompt20Toolkit.psd1' -Force 3>`$null 6>`$null; ${prefix}Start $Arguments; `$code = `$LASTEXITCODE; $After; exit `$code"
    Push-Location $base
    try { $out = (& pwsh -NoProfile -NonInteractive -Command $command 2>&1 | ForEach-Object { "$_" }) -join "`n" }
    finally { Pop-Location }
    return [pscustomobject]@{ Output = $out; ExitCode = $LASTEXITCODE }
}

$hub = Join-Path $base 'my-hub'
$localConfig = Join-Path $pkg 'config.local.json'

try {
    Write-Host ""
    Write-Host "-- -WhatIf -----------------------------------------------" -ForegroundColor Cyan
    $r = Invoke-Start "-Path '$hub' -NoWeb -WhatIf"
    Assert-True '-WhatIf exits 0' ($r.ExitCode -eq 0) $r.Output
    Assert-True 'a fresh clone is NOT told it already has a hub' ($r.Output -notmatch 'already has a hub') $r.Output
    Assert-True 'it says where the hub would go' ($r.Output -match [regex]::Escape($hub)) $r.Output
    Assert-True 'and copies nothing' (-not (Test-Path $hub))
    Assert-True 'and writes no configuration' (-not (Test-Path $localConfig))

    Write-Host ""
    Write-Host "-- the first run -----------------------------------------" -ForegroundColor Cyan
    $dayBefore = (Get-Date).ToString('yyyy-MM-dd')
    $r = Invoke-Start "-Path '$hub' -NoWeb" "'SEES ' + `$global:P20Config.PromptsRoot + ' | ' + `$global:P20Config.ActiveSpace + ' | ' + `$global:P20Config.OrgStatus"
    Assert-True 'it exits 0' ($r.ExitCode -eq 0) $r.Output
    Assert-True 'the sample hub is copied out, whole' ((Test-Path (Join-Path $hub 'hub.json')) -and (Test-Path (Join-Path $hub 'demo/current')) -and (Test-Path (Join-Path $hub 'README.md')))
    Assert-True 'not nested a level down' (-not (Test-Path (Join-Path $hub 'hub/hub.json')))
    # The Studio is dressed out of the box: the four design folders travel with the sample hub, and every
    # design file in them carries the id the lifecycle reads, so StampDesign has nothing to do and nothing is 'not shown'.
    $designFolders = @('design', 'design/archive', 'spec', 'spec/archive')
    $designFiles = @($designFolders | ForEach-Object { Get-ChildItem -LiteralPath (Join-Path $hub $_) -Filter '*.md' -File -ErrorAction SilentlyContinue })
    Assert-True 'the four design folders are copied out, each with a design in it' (@($designFolders | Where-Object { @(Get-ChildItem -LiteralPath (Join-Path $hub $_) -Filter '*.md' -File -ErrorAction SilentlyContinue).Count -ge 1 }).Count -eq 4)
    Assert-True 'every design file carries an id: first in its frontmatter' ($designFiles.Count -ge 6 -and @($designFiles | Where-Object { (Get-Content -LiteralPath $_.FullName -Raw) -notmatch '(?s)\A---\r?\nid: [0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\r?\n' }).Count -eq 0) "$($designFiles.Count) files"
    Assert-True 'the completed spec names a document that is in the copied hub (docs/)' ((Get-Content -LiteralPath (Get-ChildItem (Join-Path $hub 'spec/archive') -Filter '*.spec.md' | Select-Object -First 1).FullName -Raw) -match '(?m)^> Docs: (docs/\S+\.md)\s*$' -and (Test-Path -LiteralPath (Join-Path $hub $Matches[1]) -PathType Leaf))
    $written = if (Test-Path $localConfig) { Get-Content $localConfig -Raw | ConvertFrom-Json } else { $null }
    Assert-True 'this machine points at it' ($written -and $written.promptsRoot -eq $hub) "promptsRoot: $($written.promptsRoot)"
    Assert-True 'with the sample org active -- an org only the hub declares' ($written -and $written.activeSpace -eq 'demo') $r.Output
    Assert-True 'and the four modules on, so there is a whole product to look at' ($written -and $written.features.growth -eq $true -and $written.features.communication -eq $true -and $written.features.deck -eq $true -and $written.features.organize -eq $true)
    Assert-True 'and the first-run banner on, which only its own Dismiss turns off' ($written -and $written.firstRun.welcome -eq $true)
    Assert-True 'config.local.json stays a sparse patch' ($written -and @($written.PSObject.Properties.Name).Count -le 4) (@($written.PSObject.Properties.Name) -join ',')
    Assert-True 'the SAME shell sees the new hub afterwards' ($r.Output -match ('SEES ' + [regex]::Escape($hub) + ' \| demo \| local')) $r.Output
    Assert-True 'a newcomer is told nothing about our rename: no "is activeSpace now" note on the first run' ($r.Output -notmatch 'is activeSpace now|Both are accepted') $r.Output
    Assert-True 'nothing it defined went missing in the re-import' ($r.Output -notmatch 'is not recognized') $r.Output
    Assert-True 'it says where your real organisation is added' ($r.Output -match 'Settings') $r.Output
    # The closing line is built from the same table that writes the flags, so it
    # cannot name three modules while turning on four.
    #
    Assert-True 'the closing line names every module it turned on, Organize included' `
        ($r.Output -match 'Growth, Meetings, Decks and Organize modules on') $r.Output
    # The day-1 reminder: stamped due TODAY on the copy, a day and not a moment, and the package's file
    # still has no Due line. Either side of midnight is today for a run that straddles it.
    $dayOneRel = 'reminders/current/D1WK-welcome-to-your-first-day.md'
    $dayOneText = if (Test-Path (Join-Path $hub $dayOneRel)) { Get-Content (Join-Path $hub $dayOneRel) -Raw } else { '' }
    $dayAfter = (Get-Date).ToString('yyyy-MM-dd')
    Assert-True 'the day-1 reminder in the copy is due today, as a day' ($dayOneText -match "(?m)^\*\*Due:\*\* ($dayBefore|$dayAfter)\r?$") $dayOneText
    Assert-True "and the package's own copy of it has no Due line" ((Get-Content (Join-Path $pkg "samples/hub/$dayOneRel") -Raw) -notmatch '\*\*Due:\*\*')
    Assert-True "the package's own tree is untouched but for the gitignored config" (-not (Test-Path (Join-Path $pkg 'samples/hub/.touched')) -and (Test-Path (Join-Path $pkg 'samples/hub/hub.json')))
    # A card's picture is named by a path relative to the card (../assets/<key>/cover.png),
    # so it must survive the copy. Read with
    # the package's own reader, the one the agent's card_image() is held to.
    . (Join-Path $pkg 'Scripts/Add-CardImage.ps1')
    $pictureStamps = @((Get-P20Consts).stamps.cover, (Get-P20Consts).stamps.before)
    $named = 0
    $unresolved = @()
    foreach ($sampleCard in @(Get-ChildItem $hub -Recurse -Filter '*.prompt.md' -File)) {
        $pictureCardText = [System.IO.File]::ReadAllText($sampleCard.FullName)
        foreach ($stamp in $pictureStamps) {
            if (-not (Get-P20CardImageLine -Text $pictureCardText -Stamp $stamp)) { continue }
            $named++
            if (-not (Resolve-P20CardImage -CardPath $sampleCard.FullName -Stamp $stamp -Text $pictureCardText)) { $unresolved += "$($sampleCard.Name) $stamp" }
        }
    }
    Assert-True "every picture a sample card names resolves in the COPIED hub ($named named)" ($unresolved.Count -eq 0) ($unresolved -join '; ')

    Write-Host ""
    Write-Host "-- the cards are readable by the rest of the CLI -----------" -ForegroundColor Cyan
    $command = "`$env:PSModulePath = '$pkg'; `$env:PROMPTS_ROOT = ''; `$env:P20_USAGE_LOG_DIR = '$logDir'; Import-Module '$pkg/Prompt20Toolkit/Prompt20Toolkit.psd1' -Force 3>`$null 6>`$null; ${prefix}Status"
    $status = (& pwsh -NoProfile -NonInteractive -Command $command 2>&1 | ForEach-Object { "$_" }) -join "`n"
    # The sample hub's Demo is a shipped sample, marked the way config.default.json's Example is,
    # and the CLI's hub merge keeps the mark: isDemoDismissed hides whichever of the two you are not in.
    $command = "`$env:PSModulePath = '$pkg'; `$env:PROMPTS_ROOT = ''; `$env:P20_USAGE_LOG_DIR = '$logDir'; Import-Module '$pkg/Prompt20Toolkit/Prompt20Toolkit.psd1' -Force 3>`$null 6>`$null; 'EXAMPLES ' + ((@(`$global:P20Config.Spaces | Where-Object { `$_.example -eq `$true } | ForEach-Object { `$_.slug }) | Sort-Object) -join ',')"
    $examples = (& pwsh -NoProfile -NonInteractive -Command $command 2>&1 | ForEach-Object { "$_" }) -join "`n"
    Assert-True 'every shipped sample -- Demo, the GitHub demo and the Azure demo -- carries example: true after the merge' ($examples -match 'EXAMPLES azure-demo,demo,github-demo') $examples
    Assert-True 'Status lists the sample cards' ($status -match "Active prompts \($($sampleCards.Count)\)") $status
    Assert-True 'and derives state from the file: a card with commits is In Progress' ($status -match 'In Progress') $status

    Write-Host ""
    Write-Host "-- a second run keeps what is there -----------------------" -ForegroundColor Cyan
    $other = Join-Path $base 'other-hub'
    $r = Invoke-Start "-Path '$other' -NoWeb"
    Assert-True 'it exits 0' ($r.ExitCode -eq 0) $r.Output
    Assert-True 'it says this machine already has a hub, and which' ($r.Output -match 'already has a hub' -and $r.Output -match [regex]::Escape($hub)) $r.Output
    Assert-True 'and copies nothing anywhere' (-not (Test-Path $other))

    Write-Host ""
    Write-Host "-- refusals change nothing --------------------------------" -ForegroundColor Cyan
    Remove-Item $localConfig -Force
    $before = @(Get-ChildItem $hub -Recurse -File).Count
    $r = Invoke-Start "-Path '$hub' -NoWeb"
    Assert-True 'a folder with anything in it is refused (exit 2)' ($r.ExitCode -eq 2) "exit $($r.ExitCode)"
    Assert-True 'it says how many things are there, and how to USE the folder instead' ($r.Output -match 'already has \d+ item' -and $r.Output -match 'Config -Set promptsRoot=') $r.Output
    Assert-True 'nothing in it was overwritten or added' (@(Get-ChildItem $hub -Recurse -File).Count -eq $before)
    Assert-True 'and no configuration was written' (-not (Test-Path $localConfig))

    $r = Invoke-Start "-Path '$(Join-Path $pkg 'hub-in-here')' -NoWeb"
    Assert-True "a hub inside the Toolkit's own folder is refused (exit 2)" ($r.ExitCode -eq 2) "exit $($r.ExitCode)"
    Assert-True 'because Update refuses a dirty tree -- and it says so' ($r.Output -match 'dirty') $r.Output
    Assert-True 'nothing was created there' (-not (Test-Path (Join-Path $pkg 'hub-in-here')))

    # A SIBLING whose name merely starts with the package folder's name is not
    # "inside" it -- the house layout (~/Repos/toolkit beside ~/Repos/toolkit-hub)
    # hits exactly this.
    Remove-Item $localConfig -Force -ErrorAction SilentlyContinue
    $siblingHub = "$pkg-hub"
    $r = Invoke-Start "-Path '$siblingHub' -NoWeb"
    Assert-True "a sibling named '<package>-hub' is accepted, not refused as inside the package" ($r.ExitCode -eq 0) "exit $($r.ExitCode): $($r.Output)"
    Assert-True 'and the hub really was copied there' (Test-Path (Join-Path $siblingHub 'hub.json'))

    # The previous Start's shell may still hold config.local.json for a moment under 5.1 (an
    # antivirus scan, a child winding down): retry the write, and if it never lands say so as a
    # FAIL rather than let the exception end the try block and drop every case below it.
    $goneJson = '{ "promptsRoot": "' + ((Join-Path $base 'gone') -replace '\\', '/') + '" }'
    $wrote = $false
    for ($attempt = 0; $attempt -lt 20 -and -not $wrote; $attempt++) {
        try { [System.IO.File]::WriteAllText($localConfig, $goneJson); $wrote = $true }
        catch { Start-Sleep -Milliseconds 500 }
    }
    Assert-True 'the missing-hub case could write its config.local.json' $wrote 'config.local.json stayed locked for 10 seconds'
    $r = Invoke-Start "-Path '$other' -NoWeb"
    Assert-True 'a configured hub that has gone missing is a refusal, not a first run (exit 2)' ($r.ExitCode -eq 2) "exit $($r.ExitCode): $($r.Output)"
    Assert-True 'and nothing is copied to paper over it' (-not (Test-Path $other))

    Write-Host ""
    Write-Host "-- help --------------------------------------------------" -ForegroundColor Cyan
    Remove-Item $localConfig -Force
    $r = Invoke-Start '-Help'
    Assert-True '-Help names the verb with the prefix and changes nothing' ($r.Output -match "${prefix}Start" -and -not (Test-Path $localConfig)) $r.Output
}
catch {
    # A terminating error in the cases above ends the try block; without this the cases below it
    # vanish and the count shrinks with nothing said.
    Assert-True 'the cases ran to the end without a terminating error' $false $_.Exception.Message
}
finally {
    Remove-Item $base -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host ""
Write-Host "=======================================================" -ForegroundColor Cyan
$total = $script:passed + $script:failed
Write-Host "  Results: $($script:passed)/$total passed" -ForegroundColor $(if ($script:failed -eq 0) { 'Green' } else { 'Red' })
if ($script:errors.Count -gt 0) {
    Write-Host ""
    Write-Host "  Failures:" -ForegroundColor Red
    foreach ($e in $script:errors) { Write-Host $e -ForegroundColor Red }
}
Write-Host "=======================================================" -ForegroundColor Cyan
Write-Host ""

if ($script:failed -gt 0) { exit 1 }
