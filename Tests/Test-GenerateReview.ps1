<#
.SYNOPSIS
    Generate-Review.ps1 -- the review scaffold, against a scratch hub.
.DESCRIPTION
    Carried over from the package this was carved out of, and rewritten on the
    way: the original asserted against that repository's own git history, by
    work-item id and by calendar date. It passed there and could not run
    anywhere else, which for a suite that ships with a forkable tool is the same
    as not existing.

    So this builds its own hub -- a throwaway git repository with commits made
    at chosen dates -- and asserts against that. Every clause the original had
    survives; what is gone is the dependence on one person's history.

    The clause worth keeping in mind is the first one. git reads a bare
    --after=<date> as "after <date> at the current wall-clock time", so
    a scan run in the morning silently returned different files from the same
    scan run in the evening. The script pins T00:00:00 / T23:59:59 for that
    reason and this asserts it is still pinned.

    Run:  pwsh -File Tests/Test-GenerateReview.ps1
#>
[CmdletBinding()]
param([switch]$Help)

if ($Help) {
    Write-Host ""
    Write-Host "  Test-GenerateReview -- the review scaffold, against a scratch hub" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  Bare-date regression   explicit T times, not wall clock"
    Write-Host "  Date scanning          in-range files in, out-of-range files out"
    Write-Host "  Output                 JSON shape, markdown sections, the file on disk"
    Write-Host "  Multi-org              -Slugs writes a sorted '+'-joined folder"
    Write-Host "  Edge cases             reversed dates, bad format, empty range"
    Write-Host ""
    return
}

$ErrorActionPreference = 'Stop'

$testDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$pkgRoot = Split-Path $testDir -Parent
$reviewScript = Join-Path $pkgRoot 'Scripts/Generate-Review.ps1'

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
        Write-Host "  FAIL  $Name" -ForegroundColor Red
        if ($Detail) { Write-Host "        $Detail" -ForegroundColor DarkYellow }
        $script:errors += "$Name -- $Detail"
    }
}

function Assert-Contains {
    param([string]$Name, [string]$Haystack, [string]$Needle)
    Assert-True $Name ($Haystack -match [regex]::Escape($Needle)) "'$Needle' not in output"
}

function Assert-NotContains {
    param([string]$Name, [string]$Haystack, [string]$Needle)
    Assert-True $Name ($Haystack -notmatch [regex]::Escape($Needle)) "'$Needle' should not be in output"
}

# -- A scratch hub -------------------------------------------------------------
# A hub, not a repository of this package: no toolkit inside it, two org folders
# and a hub-root growth/. Commits are dated, because dates are what the script
# reads.
$hub = Join-Path ([System.IO.Path]::GetTempPath()) "p20-generate-review-$PID"

function New-Card {
    param([string]$RelPath, [string]$Title, [string]$Sprint, [string]$Body = '')
    $full = Join-Path $hub $RelPath
    New-Item -ItemType Directory -Path (Split-Path $full -Parent) -Force | Out-Null
    $text = "---`ntitle: $Title`nsprint: $Sprint`n---`n`n# $Title`n`n$Body`n"
    [System.IO.File]::WriteAllText($full, $text, [System.Text.UTF8Encoding]::new($false))
}

function Invoke-DatedCommit {
    param([string]$Message, [string]$Stamp)
    $env:GIT_AUTHOR_DATE = $Stamp
    $env:GIT_COMMITTER_DATE = $Stamp
    git add -A 2>&1 | Out-Null
    git -c user.name='Fixture' -c user.email='fixture@example.com' commit -m $Message 2>&1 | Out-Null
    $env:GIT_AUTHOR_DATE = $null
    $env:GIT_COMMITTER_DATE = $null
}

New-Item -ItemType Directory -Path $hub -Force | Out-Null
$savedConfig = $global:P20Config
$savedRoot = $env:PROMPTS_ROOT
$savedReviewsDir = $env:PROMPTS_REVIEWS_DIR

Push-Location $hub
try {
    git init -q -b main 2>&1 | Out-Null
    git config core.autocrlf false 2>&1 | Out-Null

    # Well outside the window under test.
    New-Card 'first/archive/101-old-thing.prompt.md' 'An older closed card' 'Sprint 1' '- [x] done'
    Invoke-DatedCommit 'seed' '2026-01-05T09:00:00'

    # Inside the window.
    New-Card 'first/archive/201-retry-on-upload.prompt.md' 'Add retry to upload' 'Sprint 12' "- [x] a`n- [x] b"
    New-Card 'first/archive/202-timeout-large-files.prompt.md' 'Timeout on large files' 'Sprint 12' '- [x] a'
    Invoke-DatedCommit 'closed two cards' '2026-05-11T10:00:00'

    New-Card 'first/current/203-paginate-results.prompt.md' 'Paginate the results list' 'Sprint 13' "- [x] a`n- [ ] b`n- [ ] c"
    New-Card 'growth/current/training-2026-05-01-consensus.prompt.md' 'Consensus and partitioning' '--' ''
    # A README in a scanned folder must NOT become a review line item.
    [System.IO.File]::WriteAllText((Join-Path $hub 'growth/README.md'), "# Growth`n", [System.Text.UTF8Encoding]::new($false))
    Invoke-DatedCommit 'active work and a training' '2026-05-12T08:04:00'

    # A second org, so -Slugs has something to combine.
    New-Card 'second/archive/301-other-engagement.prompt.md' 'Other engagement card' 'Sprint 4' '- [x] a'
    Invoke-DatedCommit 'second org' '2026-05-12T11:00:00'

    $global:P20Config = [PSCustomObject]@{
        PromptsRoot   = $hub
        PromptsFolder = 'first'
        Spaces          = @(
            [PSCustomObject]@{ slug = 'first';  promptsFolder = 'first' },
            [PSCustomObject]@{ slug = 'second'; promptsFolder = 'second' }
        )
    }
    $env:PROMPTS_ROOT = $hub
    $env:PROMPTS_REVIEWS_DIR = $null

    Write-Host ""
    Write-Host "  Generate-Review" -ForegroundColor Cyan
    Write-Host "  ------------------------------------------------" -ForegroundColor DarkGray

    # -- 1. The bare-date regression ------------------------------------------
    Write-Host ""
    Write-Host "  Bare-date regression" -ForegroundColor Magenta

    $scriptText = Get-Content $reviewScript -Raw
    Assert-Contains 'the scan pins an explicit end-of-day time' $scriptText 'T23:59:59'
    Assert-Contains 'the scan pins an explicit start-of-day time' $scriptText 'T00:00:00'

    # And it is not only in the source: the same range must answer the same way
    # whatever time of day the suite runs.
    $earlyRun = & $reviewScript -StartDate '2026-05-11' -EndDate '2026-05-13' | ConvertFrom-Json
    Assert-True 'a dated range answers the same regardless of wall clock' `
        ($earlyRun.files_included -gt 0) "files_included=$($earlyRun.files_included)"

    # -- 2. What the scan picks up --------------------------------------------
    Write-Host ""
    Write-Host "  Date scanning" -ForegroundColor Magenta

    Assert-True 'the run returns JSON' ($null -ne $earlyRun)
    Assert-True 'JSON carries review' ($null -ne $earlyRun.review)
    Assert-True 'JSON carries file_path' ($null -ne $earlyRun.file_path)
    Assert-True 'files_scanned is greater than zero' ($earlyRun.files_scanned -gt 0)
    Assert-True 'files_included is greater than zero' ($earlyRun.files_included -gt 0)

    $md = $earlyRun.review
    Assert-Contains 'an in-range archived card is in the review' $md 'Add retry to upload'
    Assert-Contains 'an in-range active card is in the review' $md 'Paginate the results list'
    Assert-NotContains 'a card committed before the window is not' $md 'An older closed card'
    Assert-NotContains 'a README in a scanned folder is not a line item' $md 'growth/README.md'
    Assert-NotContains "another org's card is not in a single-org review" $md 'Other engagement card'

    # -- 3. The shape of the scaffold -----------------------------------------
    Write-Host ""
    Write-Host "  The scaffold" -ForegroundColor Magenta

    Assert-Contains 'the review has a heading' $md 'Review'
    Assert-Contains 'the review counts the work' $md 'By the Numbers'
    Assert-Contains 'archived cards land under Completed Work' $md 'Completed Work'
    Assert-Contains 'current cards land under Active Work' $md 'Active Work'
    Assert-Contains 'growth items land under Professional Development' $md 'Professional Development'
    Assert-Contains 'sprint headings group the bullets' $md 'Sprint 12'
    Assert-Contains 'checklist progress rides along with the title' $md '1/3'
    Assert-Contains 'frontmatter names the orgs as a list' $md 'orgs: [first]'
    Assert-Contains 'frontmatter says what wrote it' $md 'generator: scaffold'
    Assert-NotContains 'and not the old scalar org: field' ($md -replace '(?s)^---.*?---', '') 'org: '

    # -- 4. The file on disk ---------------------------------------------------
    Write-Host ""
    Write-Host "  The file" -ForegroundColor Magenta

    Assert-Contains 'file_path is scoped to the active Space' $earlyRun.file_path 'reviews/first/'
    Assert-Contains 'file_path carries the date range' $earlyRun.file_path '2026-05-11_2026-05-13'
    $onDisk = Join-Path $hub $earlyRun.file_path
    Assert-True 'the review is written where file_path says' (Test-Path $onDisk) $onDisk
    if (Test-Path $onDisk) {
        # Normalised: a review written into a hub on Windows is CRLF, and the
        # assertions below are about its text, not about its line endings.
        $diskText = (Get-Content $onDisk -Raw) -replace "`r`n", "`n"
        Assert-True 'the written review has content' ($diskText.Length -gt 100)
        Assert-Contains 'the written review carries the period' $diskText 'May 11'
    }

    # PROMPTS_REVIEWS_DIR moves the physical write and leaves file_path logical,
    # which is what lets a suite run this without touching a real hub.
    $altDir = Join-Path $hub '.scratch-reviews'
    $env:PROMPTS_REVIEWS_DIR = $altDir
    $redirected = & $reviewScript -StartDate '2026-05-11' -EndDate '2026-05-13' | ConvertFrom-Json
    $env:PROMPTS_REVIEWS_DIR = $null
    Assert-Contains 'a redirected write still reports the logical path' $redirected.file_path 'reviews/first/'
    Assert-True 'a redirected write lands in the override directory' `
        (Test-Path (Join-Path $altDir 'first/2026/2026-05-11_2026-05-13/review.md'))

    # -- 5. Edge cases ---------------------------------------------------------
    Write-Host ""
    Write-Host "  Edge cases" -ForegroundColor Magenta

    $reversed = & $reviewScript -StartDate '2026-05-13' -EndDate '2026-05-01' | ConvertFrom-Json
    Assert-True 'reversed dates are refused, in JSON' ($null -ne $reversed.error) $reversed.error

    $badFormat = & $reviewScript -StartDate 'May 1' -EndDate 'May 13' | ConvertFrom-Json
    Assert-True 'a non-ISO date is refused, in JSON' ($null -ne $badFormat.error) $badFormat.error

    $empty = & $reviewScript -StartDate '2020-01-01' -EndDate '2020-01-31' | ConvertFrom-Json
    Assert-True 'a range with no work says so rather than writing an empty file' `
        ($null -ne $empty.error) $empty.error

    # -- 6. Multi-org ----------------------------------------------------------
    Write-Host ""
    Write-Host "  Multi-org" -ForegroundColor Magenta

    $multi = & $reviewScript -StartDate '2026-05-11' -EndDate '2026-05-13' -Slugs 'second,first' | ConvertFrom-Json
    Assert-True 'a two-org run produces a review' ($null -eq $multi.error) $multi.error
    Assert-Contains 'the folder is the SORTED slug set, joined by +' $multi.file_path 'first+second'
    Assert-Contains 'the folder still carries the date range' $multi.file_path '2026-05-11_2026-05-13'
    Assert-Contains "a two-org review includes the second org's card" $multi.review 'Other engagement card'
    Assert-Contains 'frontmatter lists both orgs, sorted' $multi.review 'orgs: [first, second]'
    Assert-Contains 'bullets are labelled with their source org' $multi.review '**[second]**'
    Assert-True 'the combined review is written to the combined folder' `
        (Test-Path (Join-Path $hub 'reviews/first+second/2026/2026-05-11_2026-05-13/review.md'))

    $singleViaSlugs = & $reviewScript -StartDate '2026-05-11' -EndDate '2026-05-13' -Slugs 'first' | ConvertFrom-Json
    Assert-Contains 'one slug via -Slugs writes the plain org folder' $singleViaSlugs.file_path 'reviews/first/'
    Assert-NotContains 'and a one-org review does not label its bullets' $singleViaSlugs.review '**[first]**'

    # -- 6b. The preview the web UI renders before committing --------------------
    Write-Host ""
    Write-Host "  Publish preview" -ForegroundColor Magenta

    # Everything generated above is uncommitted, and reviews/ is a brand new
    # folder. That is the normal case for a first review and it is where this
    # broke: `git status --porcelain` reports a new folder as ONE entry ending
    # in '/', reading a folder gives no content, and the route that renders
    # this answered 500. --untracked-files=all is the fix.
    $publishScript = Join-Path $pkgRoot 'Scripts/Update-Review.ps1'
    $previewJson = (& $publishScript -Preview | Out-String) | ConvertFrom-Json

    $previewFiles = @($previewJson.files)
    Assert-True 'the preview lists the pending review as a FILE, not its folder' `
        (($previewFiles.Count -gt 0) -and ($previewFiles[0].file -match 'review\.md$')) `
        (($previewFiles | ForEach-Object { $_.file }) -join ', ')
    Assert-True 'and every entry carries its content' `
        (@($previewFiles | Where-Object { $null -eq $_.content }).Count -eq 0) `
        'an entry with no content is what a folder produces'
    Assert-True 'the content is the review that was just written' `
        ($previewFiles[0].content -match 'By the Numbers') 'the preview is what the web UI renders'

    # -- 8. The growth folder's NAME comes from the hub -------------------------
    # hub.json's "folders" block renames the hub-root siblings, and once
    # this script followed the declaration for the folder it WROTE to
    # and spelled growth/ four times in the folder it READ from. A hub that
    # renamed it therefore got a review with no Professional Development section
    # and no error -- the folder was simply never scanned.
    #
    # A second hub, because the one above is already built and committed.
    Write-Host ""
    Write-Host "  A renamed growth folder" -ForegroundColor Magenta

    $renamedHub = Join-Path ([System.IO.Path]::GetTempPath()) "p20-review-renamed-$PID"
    $savedCfg2 = $global:P20Config
    Remove-Item -Recurse -Force $renamedHub -ErrorAction SilentlyContinue
    New-Item -ItemType Directory -Path $renamedHub -Force | Out-Null
    Push-Location $renamedHub
    try {
        git init -q -b main 2>&1 | Out-Null
        git config core.autocrlf false 2>&1 | Out-Null
        # Everything the default-named hub has, under a different name.
        [System.IO.File]::WriteAllText((Join-Path $renamedHub 'hub.json'),
            '{ "folders": { "growth": "development" } }', [System.Text.UTF8Encoding]::new($false))
        foreach ($card in @(
                @{ Path = 'first/archive/401-shipped.prompt.md'; Title = 'A shipped card'; Sprint = 'Sprint 20' },
                @{ Path = 'development/current/training-2026-05-12-raft.prompt.md'; Title = 'Raft in anger'; Sprint = '--' }
            )) {
            $full = Join-Path $renamedHub $card.Path
            New-Item -ItemType Directory -Path (Split-Path $full -Parent) -Force | Out-Null
            $text = "---`ntitle: $($card.Title)`nsprint: $($card.Sprint)`n---`n`n# $($card.Title)`n`n- [x] a`n"
            [System.IO.File]::WriteAllText($full, $text, [System.Text.UTF8Encoding]::new($false))
        }
        Invoke-DatedCommit 'a card and a training' '2026-05-12T09:00:00'

        $global:P20Config = [PSCustomObject]@{
            PromptsRoot   = $renamedHub
            PromptsFolder = 'first'
            Spaces          = @([PSCustomObject]@{ slug = 'first'; promptsFolder = 'first' })
        }
        $env:PROMPTS_ROOT = $renamedHub

        $renamedRun = & $reviewScript -StartDate '2026-05-11' -EndDate '2026-05-13' | ConvertFrom-Json
        $md2 = $renamedRun.review

        Assert-Contains 'the renamed hub-root folder is scanned at all' $md2 'Raft in anger'
        Assert-Contains 'its items still land under Professional Development' $md2 'Professional Development'
        Assert-Contains 'and are still counted as growth' $md2 'Growth / development |'
        Assert-Contains "the org's own folders are unaffected" $md2 'A shipped card'
        # The section is keyed by KIND, so the folder name must not leak into
        # the document as a heading nothing has a label for.
        Assert-NotContains 'the folder name is not a section heading' $md2 '## development'
    }
    finally {
        Pop-Location
        $global:P20Config = $savedCfg2
        $env:PROMPTS_ROOT = $hub
        Remove-Item -Recurse -Force $renamedHub -ErrorAction SilentlyContinue
    }

    # -- 7. The wrapper forwards what the script accepts ------------------------
    Write-Host ""
    Write-Host "  The wrapper" -ForegroundColor Magenta

    # @PSBoundParameters forwards only declared parameters, so a flag the
    # wrapper does not declare is rejected before the script ever runs. The web
    # UI calls the wrapper, never the script.
    $wrapperText = Get-Content (Join-Path $pkgRoot 'Config/growth.commands.ps1') -Raw
    Assert-Contains 'the NewWorkReview wrapper declares -Slugs' $wrapperText '[string]$Slugs'
    Assert-Contains 'the NewWorkReview wrapper declares -StartDate' $wrapperText '[string]$StartDate'
    Assert-Contains 'the NewWorkReview wrapper declares -EndDate' $wrapperText '[string]$EndDate'
}
catch {
    Assert-True 'the cases ran to the end without a terminating error' $false $_.Exception.Message
}
finally {
    Pop-Location
    $global:P20Config = $savedConfig
    $env:PROMPTS_ROOT = $savedRoot
    $env:PROMPTS_REVIEWS_DIR = $savedReviewsDir
    if (Test-Path $hub) { Remove-Item -Recurse -Force $hub -ErrorAction SilentlyContinue }
}

# -- 9. A window is filled by the cards' own dates, not by git ---------------------
# A card used to be in a review if a COMMIT touched it inside the
# window. On a real hub one reorganisation commit touched every card in a Space, so a
# review of one month selected all of them -- dozens closed the month before.
#Every case above uses cards
# with NO stamps, so it still goes through git: that is the no-regression half.
# This block is the other half -- a hub of stamped cards -- run twice: as a git
# repository whose history is deliberately misleading, and with no git at all.

function New-StampedCard {
    param([string]$Root, [string]$RelPath, [string]$Title, [string]$Created, [string]$Closed)
    $full = Join-Path $Root $RelPath
    New-Item -ItemType Directory -Path (Split-Path $full -Parent) -Force | Out-Null
    $text = "# $Title`n`n- [x] done`n`n**Created:** $Created`n"
    if ($Closed) { $text += "**Closed:** $Closed`n" }
    [System.IO.File]::WriteAllText($full, $text, [System.Text.UTF8Encoding]::new($false))
}

function New-StampedHub {
    param([string]$Root)
    New-Item -ItemType Directory -Path $Root -Force | Out-Null
    New-StampedCard $Root 'first/archive/401-shipped-in-april.prompt.md' 'Shipped in April' '2026-04-02' '2026-04-20'
    New-StampedCard $Root 'first/archive/402-worked-in-may.prompt.md' 'Worked and shipped in May' '2026-05-04' '2026-05-15'
    New-StampedCard $Root 'first/archive/403-open-through-may.prompt.md' 'Open all through May' '2026-04-28' '2026-06-03'
    New-StampedCard $Root 'first/current/404-started-in-june.prompt.md' 'Started in June' '2026-06-10' ''
    [System.IO.File]::WriteAllText((Join-Path $Root 'first/archive/.405-editor-stray.prompt.md'), "# A stray dotfile`n", [System.Text.UTF8Encoding]::new($false))
}

$savedConfig9 = $global:P20Config
$savedRoot9 = $env:PROMPTS_ROOT
$savedReviews9 = $env:PROMPTS_REVIEWS_DIR
$gitHub9 = Join-Path ([System.IO.Path]::GetTempPath()) "p20-review-stamps-git-$PID"
$plainHub9 = Join-Path ([System.IO.Path]::GetTempPath()) "p20-review-stamps-plain-$PID"
try {
    Write-Host ""
    Write-Host "  A window is filled by the cards' own dates" -ForegroundColor Cyan
    Write-Host "  ------------------------------------------------" -ForegroundColor DarkGray

    # (a) A repository whose history LIES: every card is committed for the first
    # time inside the window -- the shape a reorganisation or a backfill leaves.
    New-StampedHub $gitHub9
    Push-Location $gitHub9
    git init -q -b main 2>&1 | Out-Null
    git config core.autocrlf false 2>&1 | Out-Null
    Invoke-DatedCommit 'reorganise: every card touched in one commit' '2026-05-25T09:00:00'
    Pop-Location

    $global:P20Config = [PSCustomObject]@{
        PromptsRoot = $gitHub9; PromptsFolder = 'first'
        Spaces = @([PSCustomObject]@{ slug = 'first'; promptsFolder = 'first' })
    }
    $env:PROMPTS_ROOT = $gitHub9
    $env:PROMPTS_REVIEWS_DIR = Join-Path $gitHub9 '_out'
    $may = & $reviewScript -StartDate '2026-05-01' -EndDate '2026-05-31' | ConvertFrom-Json
    Assert-True 'a May review of stamped cards is produced' ($null -eq $may.error) $may.error
    Assert-NotContains 'a card closed in April is NOT in May, though a May commit touched it' $may.review 'Shipped in April'
    Assert-Contains 'a card worked and shipped in May is' $may.review 'Worked and shipped in May'
    Assert-Contains 'a card open all through May is, though it shipped in June' $may.review 'Open all through May'
    Assert-NotContains 'a card started in June is not, though a May commit touched it' $may.review 'Started in June'
    Assert-NotContains 'a stray dotfile is not a work item' $may.review 'A stray dotfile'
    Assert-True 'both May cards were selected by their stamps' ($may.selected_by_stamps -eq 2) "by stamps: $($may.selected_by_stamps)"
    Assert-True 'and none by git' ($may.selected_by_git -eq 0) "by git: $($may.selected_by_git)"

    # Completed / Active as of the END of the window, not as of today.
    $activeSection = ($may.review -split '## ') | Where-Object { $_ -match '^\S+ Active Work' }
    $doneSection = ($may.review -split '## ') | Where-Object { $_ -match '^\S+ Completed Work' }
    Assert-True 'a card that shipped in June is ACTIVE in a May review' ("$activeSection" -match 'Open all through May') "$activeSection"
    Assert-True 'a card that shipped in May is COMPLETED in it' ("$doneSection" -match 'Worked and shipped in May') "$doneSection"
    Assert-Contains 'the bullet says what happened inside the window' $may.review 'opened 05-04, closed 05-15'
    Assert-True 'and says nothing about dates outside it' (($may.review -split "`n" | Where-Object { $_ -match 'Open all through May' }) -notmatch 'opened|closed')

    $year = & $reviewScript -StartDate '2026-01-01' -EndDate '2026-12-31' | ConvertFrom-Json
    Assert-True 'a full-year review has all four cards' ($year.selected_by_stamps -eq 4) "by stamps: $($year.selected_by_stamps)"

    # (b) The same hub with NO git at all. There used to be no review here.
    New-StampedHub $plainHub9
    $global:P20Config = [PSCustomObject]@{
        PromptsRoot = $plainHub9; PromptsFolder = 'first'
        Spaces = @([PSCustomObject]@{ slug = 'first'; promptsFolder = 'first' })
    }
    $env:PROMPTS_ROOT = $plainHub9
    $env:PROMPTS_REVIEWS_DIR = Join-Path $plainHub9 '_out'
    $plainMay = & $reviewScript -StartDate '2026-05-01' -EndDate '2026-05-31' | ConvertFrom-Json
    Assert-True 'a hub that is not a git repository gets a review' ($null -eq $plainMay.error) $plainMay.error
    Assert-True 'with the same two cards' ($plainMay.selected_by_stamps -eq 2 -and $plainMay.review -match 'Worked and shipped in May' -and $plainMay.review -notmatch 'Shipped in April') $plainMay.review
    Assert-True 'and the same bullets, word for word' `
        (((($may.review -split "`n") | Where-Object { $_ -match '^- \*\*' }) -join '|') -eq ((($plainMay.review -split "`n") | Where-Object { $_ -match '^- \*\*' }) -join '|'))
}
catch {
    Assert-True 'the cases ran to the end without a terminating error' $false $_.Exception.Message
}
finally {
    if ((Get-Location).Path -like "$gitHub9*") { Pop-Location }
    $global:P20Config = $savedConfig9
    $env:PROMPTS_ROOT = $savedRoot9
    $env:PROMPTS_REVIEWS_DIR = $savedReviews9
    foreach ($h in @($gitHub9, $plainHub9)) { if (Test-Path $h) { Remove-Item -Recurse -Force $h -ErrorAction SilentlyContinue } }
}

Write-Host ""
$total = $script:passed + $script:failed
Write-Host "  Results: $script:passed/$total passed" -ForegroundColor $(if ($script:failed -eq 0) { 'Green' } else { 'Red' })
if ($script:failed -gt 0) {
    Write-Host ""
    foreach ($e in $script:errors) { Write-Host "  $e" -ForegroundColor Red }
}
Write-Host ""

if (Get-Command Write-P20TestResult -ErrorAction SilentlyContinue) {
    Write-P20TestResult -Suite 'GenerateReview' -Result $(if ($script:failed -eq 0) { 'pass' } else { 'fail' }) `
        -Passed $script:passed -Total $total
}

if ($script:failed -gt 0) { exit 1 }
exit 0
