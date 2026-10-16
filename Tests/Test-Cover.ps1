<#
.SYNOPSIS
    Tests for the Cover verb and the one reader of a card's pictures.
.DESCRIPTION
    C1; the rule is docs/hub/cards.md, "A card's pictures". Three parts:

      - the reader, Resolve-P20CardImage, against the ONE table both halves
        assert (Tests/fixtures/parsers/covers.json; Tests/test_assets.py is the
        agent's side of it), and the card key as Resolve-CardName.ps1 reads it;
      - the verb AS A VERB -- the real module imported in a fresh shell, typed
        the way a person types it -- because a suite that runs a script directly
        does not test the verb:
        the copy and the line, every refusal exit 2 writing nothing, -WhatIf,
        -Remove, a second round taking cover-r2, a mock left alone, and
        NewPrompt -Cover / -Before at birth;
      - storeSync: git, where the picture and the card are one commit.

    Run:  pwsh -File Tests/Test-Cover.ps1
    Or:   {cliPrefix}TestToolkit -Cover
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$pkgRoot = Split-Path $scriptDir -Parent
$libScript = Join-Path $pkgRoot 'Scripts/Add-CardImage.ps1'
if (-not (Test-Path $libScript)) {
    Write-Error "Add-CardImage.ps1 not found at $libScript"
    return
}

# -- Test harness ---------------------------------------------------------------

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

function Assert-Equal {
    param([string]$TestName, $Expected, $Actual)
    if ($Expected -eq $Actual) {
        $script:passed++
        Write-Host "  PASS  $TestName" -ForegroundColor Green
    }
    else {
        $script:failed++
        $msg = "  FAIL  $TestName -- expected [$Expected] got [$Actual]"
        $script:errors += $msg
        Write-Host $msg -ForegroundColor Red
    }
}

. $libScript
$consts = Get-P20Consts
$coverStamp = [string]$consts.stamps.cover
$beforeStamp = [string]$consts.stamps.before
$created = [string]$consts.stamps.created
$utf8 = New-Object System.Text.UTF8Encoding($false)

# Eight bytes that open every PNG, and some padding: a file that is one on disk.
$pngBytes = [byte[]](0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A) + (New-Object byte[] 24)

$base = Join-Path ([System.IO.Path]::GetTempPath()) ("p20-cover-" + [System.Guid]::NewGuid().Guid.Substring(0, 8))
New-Item -ItemType Directory -Path $base -Force | Out-Null

function New-Png {
    param([string]$Path, [byte]$Mark = 0)
    $dir = Split-Path -Parent $Path
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $bytes = [byte[]]($pngBytes + @($Mark))
    [System.IO.File]::WriteAllBytes($Path, $bytes)
    return $Path
}

try {
    # -- The shared table -----------------------------------------------------------
    Write-Host "-- Resolve-P20CardImage: the shared table -------------" -ForegroundColor Cyan

    $table = Get-Content (Join-Path $pkgRoot 'Tests/fixtures/parsers/covers.json') -Raw | ConvertFrom-Json
    $rowN = 0
    foreach ($row in $table.rows) {
        $rowN++
        $scratch = Join-Path $base "row$rowN"
        $space = Join-Path $scratch 'space'
        $cardDir = Join-Path $space $row.folder
        New-Item -ItemType Directory -Path $cardDir -Force | Out-Null
        foreach ($rel in @($row.files)) {
            if (-not $rel) { continue }
            [void](New-Png -Path ([System.IO.Path]::GetFullPath((Join-Path $space $rel))))
        }
        $lines = @('# Spike K7M2: Can we import a recipe from a photo?', '', '## Summary', 'Paper recipes.', '', '---', '',
            '**Sprint:** RecipeBox\Sprint 9') + @($row.footer | Where-Object { $_ }) + @("$created 2026-09-18", '')
        $text = $lines -join "`n"
        if ($row.crlf) { $text = $text -replace "`n", "`r`n" }
        $cardPath = Join-Path $cardDir $table.cardName
        [System.IO.File]::WriteAllText($cardPath, $text, $utf8)

        $gotCover = Resolve-P20CardImage -CardPath $cardPath -Stamp $coverStamp
        $gotBefore = Resolve-P20CardImage -CardPath $cardPath -Stamp $beforeStamp
        Assert-Equal "$($row.name): cover" ([string]$row.cover) ([string]$gotCover)
        Assert-Equal "$($row.name): before" ([string]$row.before) ([string]$gotBefore)
    }
    Assert-True 'the table was read, every row' ($rowN -ge 10) "$rowN rows"

    Write-Host ""
    Write-Host "-- The card key, as Resolve-CardName.ps1 reads it -----" -ForegroundColor Cyan

    $types = Get-P20WorkItemTypes -Config $null
    $keys = [ordered]@{
        'US-467-prize-drawer.prompt.md'                          = 'US-467'
        'Task211-extract-unit-conversion.prompt.md'              = 'Task211'
        'Spike-K7M2-can-we-import-a-recipe-from-a-photo.prompt.md' = 'Spike-K7M2'
        '214-search-returns-duplicates.prompt.md'                = '214'
        'TaskN4WQ-a-card-with-its-own-id.prompt.md'              = 'TaskN4WQ'
        # W3LC is NOT an id: L is one of the look-alikes regex.cardId leaves out, so a file named
        # with it carries no id by the one rule and has no card key. The sample hub's Welcome card
        # was typed that way by hand until it was renamed.
        'TaskW3LC-an-id-with-a-look-alike.prompt.md'             = ''
        '0141-leading-zero.prompt.md'                            = '141'
        'notes-from-tuesday.prompt.md'                           = ''
    }
    foreach ($k in $keys.GetEnumerator()) {
        Assert-Equal "key of $($k.Key)" $k.Value ([string](Get-P20CardKey -Name $k.Key -WorkItemTypes $types))
    }

    Write-Host ""
    Write-Host "-- Test-P20CoverSource: what may be a cover -----------" -ForegroundColor Cyan

    $ok = New-Png (Join-Path $base 'src/snap.png')
    $txt = Join-Path $base 'src/notes.txt'
    [System.IO.File]::WriteAllText($txt, 'not a picture', $utf8)
    $big = Join-Path $base 'src/huge.png'
    [System.IO.File]::WriteAllBytes($big, (New-Object byte[] (6MB)))
    $r = Test-P20CoverSource -Path $ok
    Assert-True 'a png is a cover' ($r.Ok -and $r.Extension -eq 'png')
    $r = Test-P20CoverSource -Path (Join-Path $base 'src/nope.png')
    Assert-True 'a path that is not there is refused, in one sentence' (-not $r.Ok -and $r.Message -match 'is not a file\.$')
    $r = Test-P20CoverSource -Path (Join-Path $base 'src')
    Assert-True 'a folder is not a file' (-not $r.Ok -and $r.Message -match 'is not a file')
    $r = Test-P20CoverSource -Path $txt
    Assert-True 'a type not in the list is refused, naming the list' (-not $r.Ok -and $r.Message -match '\.txt' -and $r.Message -match 'png, jpg, jpeg, webp, gif') $r.Message
    $r = Test-P20CoverSource -Path $big
    Assert-True 'a 6 MB file is refused, naming the limit' (-not $r.Ok -and $r.Message -match '6 MB' -and $r.Message -match 'at most 5 MB') $r.Message

    Write-Host ""

    # -- Through the VERB -------------------------------------------------------------
    Write-Host "-- Cover, typed as a verb -----------------------------" -ForegroundColor Cyan

    $hub = Join-Path $base 'hub'
    $log = Join-Path $base 'log'
    New-Item -ItemType Directory -Path $hub, $log -Force | Out-Null
    $prefix = (Get-Content (Join-Path $pkgRoot 'config.default.json') -Raw | ConvertFrom-Json).commandPrefix
    $srcDir = Join-Path $base 'src'
    $preamble = "`$env:PSModulePath = '$pkgRoot'; `$env:PROMPTS_ROOT = '$hub'; `$env:P20_USAGE_LOG_DIR = '$log'; " +
        "Set-Location '$srcDir'; " +
        "Import-Module '$pkgRoot/Prompt20Toolkit/Prompt20Toolkit.psd1' -Force 3>`$null 6>`$null; "

    function Invoke-Verbs {
        param([string]$Commands)
        return (& pwsh -NoProfile -NonInteractive -Command ($preamble + $Commands) 2>&1 | ForEach-Object { "$_" }) -join "`n"
    }
    function Find-Card {
        param([string]$Filter, [string]$FolderName)
        return @(Get-ChildItem $hub -Recurse -Filter $Filter | Where-Object { $_.DirectoryName -match "[\\/]$FolderName`$" })
    }
    function Get-HubFiles {
        return @(Get-ChildItem $hub -Recurse -File | ForEach-Object { $_.FullName + '|' + $_.Length + '|' + $_.LastWriteTimeUtc.Ticks } | Sort-Object)
    }

    [void](New-Png (Join-Path $srcDir 'after.png') 2)
    [void](New-Png (Join-Path $srcDir 'before.png') 3)
    [System.IO.File]::WriteAllBytes((Join-Path $srcDir 'snap.jpg'), [byte[]](0xFF, 0xD8, 0xFF, 0xE0, 1, 2, 3))

    $out = Invoke-Verbs ("${prefix}NewPrompt -Title 'Import from a photo' -Type Spike -Id K7M2 | Out-Null; " +
        "${prefix}NewPrompt -Title 'Extract unit conversion' -Type Task -Id Q4R9 | Out-Null; " +
        "'HELP-BEGIN'; ${prefix}Cover -Help; 'HELP-END'")
    $usage = [regex]::Match($out, '(?s)HELP-BEGIN(.*)HELP-END').Groups[1].Value
    Assert-True '-Help names the verb with the registered prefix' ($usage -match [regex]::Escape("${prefix}Cover <id|file> <image>")) $usage
    $spike = Find-Card 'Spike-K7M2-*.prompt.md' 'current'
    Assert-Equal 'the card exists to be given a cover' 1 $spike.Count
    $spaceDir = Split-Path -Parent $spike[0].DirectoryName
    $assetsDir = Join-Path $spaceDir ([string]$consts.folders.assets)
    $keyDir = Join-Path $assetsDir 'Spike-K7M2'

    # A mock someone put in the folder by hand, the corpus's way: never touched.
    New-Item -ItemType Directory -Path $keyDir -Force | Out-Null
    $mock = Join-Path $keyDir 'add_prize_drawer.html'
    [System.IO.File]::WriteAllText($mock, '<p>a mock</p>', $utf8)
    $mockStamp = (Get-Item $mock).LastWriteTimeUtc

    $hubBefore = Get-HubFiles
    $original = [System.IO.File]::ReadAllText($spike[0].FullName)
    $out = Invoke-Verbs ("${prefix}Cover; 'BARE-EXIT=' + `$LASTEXITCODE; " +
        "${prefix}Cover K7M2; 'NOPIC-EXIT=' + `$LASTEXITCODE; " +
        "${prefix}Cover W3X7 ./after.png; 'UNKNOWN-EXIT=' + `$LASTEXITCODE; " +
        "${prefix}Cover K7M2 ./missing.png; 'NOTFILE-EXIT=' + `$LASTEXITCODE; " +
        "${prefix}Cover K7M2 ./notes.txt; 'TYPE-EXIT=' + `$LASTEXITCODE; " +
        "${prefix}Cover K7M2 ./huge.png; 'SIZE-EXIT=' + `$LASTEXITCODE; " +
        "${prefix}Cover K7M2 ./after.png -WhatIf; 'WHATIF-EXIT=' + `$LASTEXITCODE")
    Assert-True 'a bare call states the reason and exits 2' ($out -match 'no card given\.' -and $out -match 'BARE-EXIT=2') $out
    Assert-True 'a card with no picture named exits 2' ($out -match 'no picture given\.' -and $out -match 'NOPIC-EXIT=2') $out
    Assert-True 'an id nobody has is refused, not guessed at' ($out -match "No card with id 'W3X7'" -and $out -match 'UNKNOWN-EXIT=2') $out
    Assert-True 'a path that is not a file exits 2' ($out -match 'is not a file' -and $out -match 'NOTFILE-EXIT=2') $out
    Assert-True 'a type not in the list exits 2' ($out -match 'TYPE-EXIT=2') $out
    Assert-True 'a 6 MB picture exits 2, naming the limit' ($out -match 'at most 5 MB' -and $out -match 'SIZE-EXIT=2') $out
    Assert-True "each refusal says why once -- no wrapper 'exit code' block on top" ($out -notmatch 'exit code \d') $out
    Assert-True '-WhatIf exits 0 and says what it would do' ($out -match 'WHATIF-EXIT=0' -and $out -match 'What if: would copy') $out
    Assert-True 'and no refusal, nor -WhatIf, wrote anything in the hub' ((@(Get-HubFiles) -join "`n") -eq ($hubBefore -join "`n"))
    Assert-Equal 'the card is byte for byte what it was' $original ([System.IO.File]::ReadAllText($spike[0].FullName))

    $out = Invoke-Verbs "${prefix}Cover k7m2 ./after.png; 'COVER-EXIT=' + `$LASTEXITCODE"
    Assert-True "'Cover k7m2 ./after.png' exits 0, the id typed in any case" ($out -match 'COVER-EXIT=0') $out
    Assert-True 'and says where the picture went' ($out -match 'K7M2 has a cover -- assets/Spike-K7M2/cover\.png') $out
    $coverFile = Join-Path $keyDir 'cover.png'
    Assert-True 'the picture is copied into assets/<card key>/cover.png' ((Test-Path $coverFile) -and ([System.IO.File]::ReadAllBytes($coverFile)[-1] -eq 2))
    $text = [System.IO.File]::ReadAllText($spike[0].FullName)
    Assert-True 'the card carries ONE line, above Created' ($text -match ('(?m)^' + [regex]::Escape("$coverStamp ../assets/Spike-K7M2/cover.png") + '\n' + [regex]::Escape($created)) -and ([regex]::Matches($text, [regex]::Escape($coverStamp))).Count -eq 1) $text
    Assert-True 'and the card it CREATED is still LF' (-not $text.Contains("`r"))
    Assert-Equal 'the reader reads it back' 'Spike-K7M2/cover.png' ([string](Resolve-P20CardImage -CardPath $spike[0].FullName -Stamp $coverStamp))
    Assert-True 'one picture in the folder, beside the mock' (@(Get-ChildItem $keyDir -File | Where-Object { $_.Name -ne 'add_prize_drawer.html' }).Count -eq 1)
    $other = Find-Card 'TaskQ4R9-*.prompt.md' 'current'
    Assert-True 'the other card was not touched' ([System.IO.File]::ReadAllText($other[0].FullName) -notmatch [regex]::Escape($coverStamp))
    Assert-True 'and no image sits beside the cards in current/' (@(Get-ChildItem $spike[0].DirectoryName -File | Where-Object { $_.Extension -ne '.md' }).Count -eq 0)

    $out = Invoke-Verbs ("${prefix}Cover K7M2 ./snap.jpg; 'AGAIN-EXIT=' + `$LASTEXITCODE; " +
        "${prefix}Cover K7M2 ./before.png -Before; 'BEFORE-EXIT=' + `$LASTEXITCODE")
    Assert-True 'attaching again replaces the card''s own picture, and says so' ($out -match 'AGAIN-EXIT=0' -and $out -match 'Replaced K7M2''s cover \(cover\.png\)') $out
    Assert-True 'the old picture is gone, the new one is cover.jpg' (-not (Test-Path $coverFile) -and (Test-Path (Join-Path $keyDir 'cover.jpg')))
    $text = [System.IO.File]::ReadAllText($spike[0].FullName)
    Assert-True 'still one Cover line, now naming cover.jpg' (([regex]::Matches($text, [regex]::Escape($coverStamp))).Count -eq 1 -and $text -match [regex]::Escape("$coverStamp ../assets/Spike-K7M2/cover.jpg")) $text
    Assert-True '-Before writes before.png and its own line' ($out -match 'BEFORE-EXIT=0' -and (Test-Path (Join-Path $keyDir 'before.png')) -and $text -match [regex]::Escape("$beforeStamp ../assets/Spike-K7M2/before.png")) $out
    Assert-True 'the mock is untouched' ((Test-Path $mock) -and (Get-Item $mock).LastWriteTimeUtc -eq $mockStamp)

    Write-Host ""
    Write-Host "-- Rounds share a folder: a second round takes cover-r2" -ForegroundColor Cyan

    $out = Invoke-Verbs ("${prefix}Archive K7M2 | Out-Null; " +
        "${prefix}NewPrompt -Title 'Import from a photo' -Type Spike -Id K7M2 | Out-Null; " +
        "${prefix}Cover K7M2 ./after.png; 'ROUND-EXIT=' + `$LASTEXITCODE")
    $archived = Find-Card 'Spike-K7M2-*.prompt.md' 'archive'
    $round2 = Find-Card 'Spike-K7M2-*.prompt.md' 'current'
    Assert-Equal 'round one is in archive/' 1 $archived.Count
    Assert-Equal 'round two is in current/' 1 $round2.Count
    Assert-True "'Cover K7M2' finds the current round and exits 0" ($out -match 'ROUND-EXIT=0') $out
    Assert-True 'the second round takes cover-r2 -- cover.jpg is the archived round''s' ((Test-Path (Join-Path $keyDir 'cover-r2.png')) -and [System.IO.File]::ReadAllText($round2[0].FullName) -match [regex]::Escape("$coverStamp ../assets/Spike-K7M2/cover-r2.png")) $out
    Assert-Equal 'and the archived round still draws its own picture' 'Spike-K7M2/cover.jpg' ([string](Resolve-P20CardImage -CardPath $archived[0].FullName -Stamp $coverStamp))
    Assert-Equal 'its before too, from archive/' 'Spike-K7M2/before.png' ([string](Resolve-P20CardImage -CardPath $archived[0].FullName -Stamp $beforeStamp))

    $out = Invoke-Verbs ("${prefix}Cover K7M2 -Remove -WhatIf; 'RMWHATIF-EXIT=' + `$LASTEXITCODE; " +
        "${prefix}Cover K7M2 -Remove; 'REMOVE-EXIT=' + `$LASTEXITCODE; " +
        "${prefix}Cover K7M2 -Remove; 'REMOVE2-EXIT=' + `$LASTEXITCODE")
    Assert-True '-Remove -WhatIf exits 0 and says what it would remove' ($out -match 'RMWHATIF-EXIT=0' -and $out -match 'What if: would remove') $out
    Assert-True '-Remove deletes the round''s picture and its line' ($out -match 'REMOVE-EXIT=0' -and -not (Test-Path (Join-Path $keyDir 'cover-r2.png')) -and [System.IO.File]::ReadAllText($round2[0].FullName) -notmatch [regex]::Escape($coverStamp)) $out
    Assert-True 'a second -Remove has nothing to remove, exit 0' ($out -match 'REMOVE2-EXIT=0' -and $out -match 'has no cover -- nothing removed') $out
    Assert-True 'and the archived round''s pictures and the mock are still there' ((Test-Path (Join-Path $keyDir 'cover.jpg')) -and (Test-Path (Join-Path $keyDir 'before.png')) -and (Test-Path $mock))

    Write-Host ""
    Write-Host "-- NewPrompt -Cover / -Before: born with the picture --" -ForegroundColor Cyan

    $out = Invoke-Verbs ("${prefix}NewPrompt -Title 'Tags overlap in search' -Type Bug -Id 214 -Before ./before.png -Cover ./snap.jpg; 'BORN-EXIT=' + `$LASTEXITCODE; " +
        "${prefix}NewPrompt -Title 'Refused at birth' -Type Task -Id V9TA -Before ./notes.txt; 'BADBIRTH-EXIT=' + `$LASTEXITCODE")
    $born = Find-Card '214-*.prompt.md' 'current'
    Assert-True 'NewPrompt -Before -Cover makes the card and exits 0' ($out -match 'BORN-EXIT=0' -and $born.Count -eq 1) $out
    if ($born.Count -eq 1) {
        $bornText = [System.IO.File]::ReadAllText($born[0].FullName)
        Assert-Equal 'its cover resolves' '214/cover.jpg' ([string](Resolve-P20CardImage -CardPath $born[0].FullName -Stamp $coverStamp))
        Assert-Equal 'its before resolves' '214/before.png' ([string](Resolve-P20CardImage -CardPath $born[0].FullName -Stamp $beforeStamp))
        Assert-True 'both lines above Created, and the card is LF' ($bornText -match ('(?s)' + [regex]::Escape($beforeStamp) + '.*' + [regex]::Escape($coverStamp) + '[^\n]*\n' + [regex]::Escape($created)) -and -not $bornText.Contains("`r")) $bornText
    }
    Assert-True 'a refused picture at birth exits 2 and writes no card' ($out -match 'BADBIRTH-EXIT=2' -and $out -match '-Before:' -and (Find-Card 'TaskV9TA-*.prompt.md' 'current').Count -eq 0) $out

    Write-Host ""
    Write-Host "-- storeSync: git -- the picture and the card, one commit" -ForegroundColor Cyan

    $gitHub = Join-Path $base 'github'
    New-Item -ItemType Directory -Path (Join-Path $gitHub 'demo/current') -Force | Out-Null
    [System.IO.File]::WriteAllText((Join-Path $gitHub 'hub.json'),
        '{ "hub": 1, "storeSync": "git", "spaces": [ { "slug": "cover-test", "name": "Cover test", "status": "local", "promptsFolder": "demo" } ] }', $utf8)
    $cardText = "# Task 7: Paginate`n`n## Summary`nPages.`n`n---`n`n**Sprint:** --`n$created 2026-09-20`n"
    [System.IO.File]::WriteAllText((Join-Path $gitHub 'demo/current/Task7-paginate.prompt.md'), $cardText, $utf8)
    Push-Location $gitHub
    try {
        git init --quiet 2>&1 | Out-Null
        git config user.email 'test@example.invalid' 2>&1 | Out-Null
        git config user.name 'Cover test' 2>&1 | Out-Null
        git config core.autocrlf false 2>&1 | Out-Null
        git add -A 2>&1 | Out-Null
        git commit --quiet -m 'seed' 2>&1 | Out-Null
    }
    finally { Pop-Location }
    $gitPreamble = "`$env:PSModulePath = '$pkgRoot'; `$env:PROMPTS_ROOT = '$gitHub'; `$env:P20_ACTIVE_SPACE = 'cover-test'; `$env:P20_USAGE_LOG_DIR = '$log'; " +
        "Set-Location '$srcDir'; " +
        "Import-Module '$pkgRoot/Prompt20Toolkit/Prompt20Toolkit.psd1' -Force 3>`$null 6>`$null; "
    $out = (& pwsh -NoProfile -NonInteractive -Command ($gitPreamble + "${prefix}Cover 7 ./after.png; 'GIT-EXIT=' + `$LASTEXITCODE") 2>&1 | ForEach-Object { "$_" }) -join "`n"
    Assert-True "'Cover 7' on a git hub exits 0 and says Committed." ($out -match 'GIT-EXIT=0' -and $out -match 'Committed\.') $out
    $names = @(git -C $gitHub show --name-only --format= HEAD 2>$null)
    Assert-True 'one commit carries the picture and the card' (($names -contains 'demo/assets/Task7/cover.png') -and ($names -contains 'demo/current/Task7-paginate.prompt.md')) ($names -join ', ')
    $status = @(git -C $gitHub status --porcelain 2>$null)
    Assert-True 'and leaves nothing uncommitted' ($status.Count -eq 0) ($status -join '; ')

    # A pre-commit hook that refuses: the picture and the card are written, the
    # commit is not, and the verb says so as a stated refusal -- exit 2.
    $hook = Join-Path $gitHub '.git/hooks/pre-commit'
    [System.IO.File]::WriteAllText($hook, "#!/bin/sh`necho 'hook says no'`nexit 1`n")
    # git runs a hook only when the file is executable; Windows has no execute bit, Unix does.
    if (Get-Command chmod -ErrorAction SilentlyContinue) { & chmod '+x' $hook }
    $out = (& pwsh -NoProfile -NonInteractive -Command ($gitPreamble + "${prefix}Cover 7 ./before.png -Before; 'HOOK-EXIT=' + `$LASTEXITCODE") 2>&1 | ForEach-Object { "$_" }) -join "`n"
    Assert-True 'a refused commit exits 2' ($out -match 'HOOK-EXIT=2') $out
    Assert-True 'the refusal says the picture and the card are written but not committed' ($out -match 'written, but they are not committed') $out
    Assert-True 'the refusal carries git''s own sentence and a hint' ($out -match 'hook says no' -and $out -match 'Hint:') $out
    Assert-True 'the picture is on disk' (Test-Path (Join-Path $gitHub 'demo/assets/Task7/before.png'))
    Remove-Item $hook -Force

    # -- -Samples: a Demo copied out before the covers shipped ------------------
    Write-Host ""
    Write-Host "-- Cover -Samples: an older Demo ----------------------" -ForegroundColor Cyan

    function New-OldDemoHub {
        # The sample hub as it was before covers: no assets/, no **Cover:** line.
        param([string]$Path)
        Copy-Item (Join-Path $pkgRoot 'samples/hub') $Path -Recurse
        foreach ($d in @(Get-ChildItem $Path -Directory)) {
            $a = Join-Path $d.FullName 'assets'
            if (Test-Path $a) { Remove-Item $a -Recurse -Force }
        }
        foreach ($f in @(Get-ChildItem $Path -Recurse -Filter '*.md')) {
            $t = [System.IO.File]::ReadAllText($f.FullName)
            $n = [regex]::Replace($t, '(?m)^\*\*Cover:\*\*[^\r\n]*\r?\n', '')
            if ($n -ne $t) { [System.IO.File]::WriteAllText($f.FullName, $n, $utf8) }
        }
    }
    function Invoke-HubVerbs {
        param([string]$HubPath, [string]$Commands)
        $pre = "`$env:PSModulePath = '$pkgRoot'; `$env:PROMPTS_ROOT = '$HubPath'; `$env:P20_USAGE_LOG_DIR = '$log'; " +
            "Set-Location '$srcDir'; " +
            "Import-Module '$pkgRoot/Prompt20Toolkit/Prompt20Toolkit.psd1' -Force 3>`$null 6>`$null; "
        return (& pwsh -NoProfile -NonInteractive -Command ($pre + $Commands) 2>&1 | ForEach-Object { "$_" }) -join "`n"
    }
    function Get-Snapshot {
        param([string]$Path)
        return @(Get-ChildItem $Path -Recurse -File | ForEach-Object { $_.FullName + '|' + [System.IO.File]::ReadAllText($_.FullName).GetHashCode() + '|' + $_.Length } | Sort-Object)
    }

    $old = Join-Path $base 'old-hub'
    New-OldDemoHub $old
    $mine = Join-Path $old 'demo/current/Task9ABC-mine.prompt.md'
    [System.IO.File]::WriteAllText($mine, "# Task 9ABC: mine`n`n---`n`n$created 2026-10-07`n", $utf8)
    # A card of the sample's that the person gave a cover of their own: the line is theirs.
    $ownCardPath = Join-Path $old 'demo/current/Task211-extract-unit-conversion-into-a-pure-module.prompt.md'
    [System.IO.File]::AppendAllText($ownCardPath, "$coverStamp ../assets/Task211/mine.png`n", $utf8)
    $ownBefore = [System.IO.File]::ReadAllText($ownCardPath)
    # A Space that is not a sample's, holding a card with a sample's name.
    $notSample = Join-Path $old 'my-space/current'
    New-Item -ItemType Directory -Path $notSample -Force | Out-Null
    $lookalike = Join-Path $notSample 'US-209-paginate-the-recipe-list.prompt.md'
    [System.IO.File]::WriteAllText($lookalike, "# US 209: mine`n`n---`n`n$created 2026-10-07`n", $utf8)

    . (Join-Path $pkgRoot 'Scripts/Get-SampleCoverGaps.ps1')
    $gaps = @(Get-P20SampleCoverGaps -PromptsRoot $old -PackageRoot $pkgRoot)
    $sampleCards = @(Get-ChildItem (Join-Path $pkgRoot 'samples/hub') -Recurse -Filter '*.md' |
        Where-Object { [System.IO.File]::ReadAllText($_.FullName) -match "(?m)^\*\*Cover:\*\*" })
    Assert-Equal 'the gap list is every sample card with a cover, less the one that has its own' ($sampleCards.Count - 1) $gaps.Count
    Assert-True 'the gap list never names the card the person added, their own cover, or another Space' (
        -not (@($gaps | Where-Object { $_.Card.Name -like 'Task9ABC*' -or $_.Card.Name -like 'Task211*' -or $_.Space -eq 'my-space' }))) ''

    $before = Get-Snapshot $old
    $out = Invoke-HubVerbs $old "${prefix}Cover -Samples -WhatIf; 'CODE=' + `$LASTEXITCODE"
    Assert-True '-WhatIf exits 0 and says what it would dress' ($out -match 'CODE=0' -and $out -match 'What if: would dress demo/214' -and $out -match "would dress $($sampleCards.Count - 1) sample card") $out
    Assert-True '-WhatIf wrote nothing' (((Get-Snapshot $old) -join "`n") -eq ($before -join "`n"))
    Assert-True '-WhatIf made no assets folder' (-not (Test-Path (Join-Path $old 'demo/assets/214')))

    $out = Invoke-HubVerbs $old "${prefix}Cover -Samples; 'CODE=' + `$LASTEXITCODE"
    Assert-True 'Cover -Samples exits 0 and says how many it dressed' ($out -match 'CODE=0' -and $out -match "Dressed $($sampleCards.Count - 1) sample card") $out
    $demoCard = Get-ChildItem (Join-Path $old 'demo/current') -Filter '214-*.md'
    Assert-True 'a dressed card has the line' ([System.IO.File]::ReadAllText($demoCard.FullName) -match '(?m)^\*\*Cover:\*\* \.\./assets/214/cover\.webp\r?$')
    Assert-True 'and the picture is the package''s own, byte for byte' (
        [System.IO.File]::ReadAllBytes((Join-Path $old 'demo/assets/214/cover.webp')).Length -eq
        [System.IO.File]::ReadAllBytes((Join-Path $pkgRoot 'samples/hub/demo/assets/214/cover.webp')).Length)
    Assert-True 'the GitHub demo is dressed too' ((Test-Path (Join-Path $old 'github-demo/assets/Task6/cover.webp')))
    Assert-Equal 'a card the person added is untouched' ("# Task 9ABC: mine`n`n---`n`n$created 2026-10-07`n") ([System.IO.File]::ReadAllText($mine))
    Assert-Equal 'a sample card with its own cover is untouched' $ownBefore ([System.IO.File]::ReadAllText($ownCardPath))
    Assert-True 'and its package picture was not copied in' (-not (Test-Path (Join-Path $old 'demo/assets/Task211')))
    Assert-Equal 'a card of the same name in a Space that is not a sample is untouched' ("# US 209: mine`n`n---`n`n$created 2026-10-07`n") ([System.IO.File]::ReadAllText($lookalike))
    Assert-True 'and that Space got no assets folder' (-not (Test-Path (Join-Path $old 'my-space/assets')))

    $after = Get-Snapshot $old
    $out = Invoke-HubVerbs $old "${prefix}Cover -Samples; 'CODE=' + `$LASTEXITCODE"
    Assert-True 'a second run says there is nothing to do, and writes nothing' ($out -match 'CODE=0' -and $out -match 'nothing to do' -and ((Get-Snapshot $old) -join "`n") -eq ($after -join "`n")) $out

    $fresh = Join-Path $base 'fresh-hub'
    Copy-Item (Join-Path $pkgRoot 'samples/hub') $fresh -Recurse
    $before = Get-Snapshot $fresh
    $out = Invoke-HubVerbs $fresh "${prefix}Cover -Samples; 'CODE=' + `$LASTEXITCODE"
    Assert-True 'a Demo already wearing its covers: nothing to do, no writes' ($out -match 'CODE=0' -and $out -match 'nothing to do' -and ((Get-Snapshot $fresh) -join "`n") -eq ($before -join "`n")) $out

    $out = Invoke-HubVerbs $old "${prefix}Cover 214 ./after.png -Samples; 'CODE=' + `$LASTEXITCODE"
    Assert-True '-Samples with a card is a stated refusal (exit 2), said once' ($out -match 'CODE=2' -and $out -match '-Samples takes no card' -and (([regex]::Matches($out, 'Error:')).Count -eq 1)) $out
    $out = Invoke-HubVerbs $old "${prefix}Cover -Help"
    Assert-True '-Help names -Samples' ($out -match 'Cover -Samples') $out
}
catch {
    Assert-True 'the cases ran to the end without a terminating error' $false $_.Exception.Message
}
finally { Remove-Item $base -Recurse -Force -ErrorAction SilentlyContinue }

# -- Summary ----------------------------------------------------------------------

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
