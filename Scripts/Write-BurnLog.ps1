<#
.SYNOPSIS
    Burn -- the current Claude Code burn, today and this week; Burn -Log writes the day's record into the hub.
.DESCRIPTION
    With no switch: the current burn, TODAY (from local midnight) and THIS WEEK (from
    the latest burn.weekStarts -- Friday 05:00 local by default -- when the
    allocation resets) -- this machine's
    Claude Code session files, read live, plus the day records the OTHER machines
    logged into the hub's usage/ folder. This machine's own records are not read:
    its session files are. A day record counts toward the week it starts in (00:00
    on its date), so with the default one dated Friday is the week before's. Blocks: tokens by model,
    and a cost DERIVED from Config/claude-prices.json, labelled so; never the plan's
    allocation. -AsJson prints the same answer as one JSON object -- what the agent's
    GET /api/usage/burn serves. docs/hub/usage.md, "Today and this week".

    With -Log: reads the session files (Scripts/Read-ClaudeUsage.ps1:
    CLAUDE_CONFIG_DIR's projects folder, else ~/.claude/projects) and writes ONE record
    for one local day and this machine: <hub>/usage/<yyyy-mm-dd>-<machine>.json, through
    Write-CardText -New (UTF-8, no BOM, LF). Run again the same day, it REPLACES that
    record -- never a second file, never an append -- and over the same session files
    it writes the same bytes. The record carries tokens by model and by session, and a
    cost DERIVED from Config/claude-prices.json, labelled so; never a path, a user
    name, or a plan's allocation. docs/hub/usage.md is its shape.

    With -Reading: records the plan's weekly usage as Claude's usage page shows
    it -- whole percents by bucket (burn.buckets), typed, never estimated -- and
    appends it to this machine's record for the week:
    <hub>/usage/readings/<week's start date>-<machine>.json. Bare Burn opens with
    the weekly burndown drawn from every machine's readings: each bucket's latest
    reading, and its gap from an even pace at the reading's time.
    Scripts/Read-BurnReadings.ps1 is the rule; docs/hub/usage.md, "The weekly
    burndown".

    Read-only over Claude Code's folder. A machine without one writes nothing and
    says so, exit 0; read with no switch, it adds nothing and says so.
.PARAMETER Log
    Write the day's record into the hub.
.PARAMETER Date
    The local day -Log writes, yyyy-mm-dd. Default: today. Only with -Log.
.PARAMETER AsJson
    The current burn as one JSON object. Not with -Log.
.PARAMETER At
    Read the burn as it stood at a past local time, yyyy-mm-dd HH:mm, instead of now:
    the windows are the ones that held then, and nothing after it is counted. Not
    with -Log (whose day is -Date). With -Reading, when the reading was taken.
.PARAMETER Reading
    A plan reading, bucket=percent, one bucket or several: general=43,premium=54.
    Not with -Log, -Date or -AsJson.
.NOTES
    PowerShell 5.1 compatible (ASCII only).
#>
[CmdletBinding()]
param(
    [switch]$Log,
    [string]$Date,
    [switch]$AsJson,
    [string]$At,
    [string[]]$Reading,
    [switch]$Help
)

$ErrorActionPreference = 'Stop'
$scriptsDir = $PSScriptRoot
$packageRoot = Split-Path $scriptsDir -Parent

. (Join-Path $scriptsDir 'Initialize-CliFallbacks.ps1')
$prefix = Get-CliPrefix

if ($Help) {
    Write-Host ""
    Write-Host "  ${prefix}Burn -- Claude Code usage: the current burn, and the day's record" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "    ${prefix}Burn [-AsJson] [-At <yyyy-mm-dd HH:mm>]"
    Write-Host "    ${prefix}Burn -Reading general=43,premium=54 [-At <yyyy-mm-dd HH:mm>]"
    Write-Host "    ${prefix}Burn -Log [-Date <yyyy-mm-dd>]"
    Write-Host ""
    Write-Host "  Alone: today and this week (from burn.weekStarts, Friday 05:00 by default),"
    Write-Host "  this machine's session files"
    Write-Host "  plus the other machines' records in the hub. -Log writes"
    Write-Host "  usage/<date>-<machine>.json in the hub: tokens by model and session, cost derived."
    Write-Host "  -Reading records the plan's weekly usage as Claude's usage page shows it;"
    Write-Host "  Burn alone opens with the weekly burndown drawn from those readings."
    Write-Host ""
    exit 0
}

foreach ($helper in @('Resolve-HubConfig.ps1', 'Get-Consts.ps1', 'Write-ConfigJson.ps1', 'Read-ClaudeUsage.ps1', 'Read-BurnReadings.ps1')) {
    . (Join-Path $scriptsDir $helper)
}

$inv = [System.Globalization.CultureInfo]::InvariantCulture

if ($Log -and $AsJson) {
    Write-CliError -Message "-AsJson is the current burn's, not -Log's: -Log writes the record and says where." `
        -Hint "${prefix}Burn -AsJson for today and this week, or ${prefix}Burn -Log to write the day's record."
    exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
}
if ($Log -and $PSBoundParameters.ContainsKey('At')) {
    Write-CliError -Message "-At is the current burn's, not -Log's: -Log's day is -Date." `
        -Hint "${prefix}Burn -At <yyyy-mm-dd HH:mm> for the burn as it stood then, or ${prefix}Burn -Log -Date <yyyy-mm-dd>."
    exit 2  # stated refusal
}
$hasReading = $PSBoundParameters.ContainsKey('Reading')
if ($hasReading -and $Log) {
    Write-CliError -Message "-Reading records the plan's usage; -Log writes the day's token record. One at a time." `
        -Hint "${prefix}Burn -Reading general=<n>,premium=<n>, then ${prefix}Burn -Log."
    exit 2  # stated refusal
}
if ($hasReading -and $AsJson) {
    Write-CliError -Message "-AsJson is the current burn's, not -Reading's: -Reading records a reading and prints the burndown." `
        -Hint "${prefix}Burn -Reading general=<n>,premium=<n>, then ${prefix}Burn -AsJson."
    exit 2  # stated refusal
}
if (-not $Log -and $PSBoundParameters.ContainsKey('Date')) {
    Write-CliError -Message "-Date names the day -Log writes; ${prefix}Burn alone reads today and this week." `
        -Hint "${prefix}Burn -Log -Date $([string]$Date), or ${prefix}Burn for today and this week."
    exit 2  # stated refusal
}

if (-not $Log) {
    # -- The current burn: today and this week ---------------------------------
    $now = Get-Date
    if ($PSBoundParameters.ContainsKey('At')) {
        $typedAt = ([string]$At).Trim()
        $parsedAt = [DateTime]::MinValue
        $okAt = [DateTime]::TryParseExact($typedAt, [string[]]@('yyyy-MM-dd HH:mm', 'yyyy-MM-ddTHH:mm'), $inv,
            [System.Globalization.DateTimeStyles]::None, [ref]$parsedAt)
        if (-not $okAt) {
            Write-CliError -Message "'$typedAt' is not a time: -At takes yyyy-mm-dd HH:mm, local." -Hint "${prefix}Burn -At '$($now.ToString('yyyy-MM-dd HH:mm', $inv))'"
            exit 2  # stated refusal
        }
        if ($parsedAt -gt $now) {
            Write-CliError -Message "$typedAt has not happened yet: -At reads the burn as it stood at a past time." -Hint "${prefix}Burn reads it now."
            exit 2  # stated refusal
        }
        $now = [DateTime]::SpecifyKind($parsedAt, [DateTimeKind]::Local)
    }
    # When the week starts: burn.weekStarts, read through its one parser.
    $weekText = ''
    if ($global:P20Config -and $global:P20Config.BurnWeekStarts) { $weekText = [string]$global:P20Config.BurnWeekStarts }
    $weekStart = ConvertFrom-P20WeekStart -Text $weekText
    if (-not $weekStart.Ok) {
        Write-CliError -Message $weekStart.Reason `
            -Hint "${prefix}Config -Set burn.weekStarts=`"Friday 05:00`" -- the key is read from config.local.json, then config.default.json."
        exit 2  # stated refusal
    }
    # The burndown's settings: how long a reading is current, and the plan's buckets.
    $cacheText = ''
    if ($global:P20Config -and $null -ne $global:P20Config.BurnCacheHours) { $cacheText = [string]$global:P20Config.BurnCacheHours }
    $cache = Get-P20BurnCacheHours -Value $cacheText
    if (-not $cache.Ok) {
        Write-CliError -Message $cache.Reason `
            -Hint "${prefix}Config -Set burn.cacheHours=4 -- the key is read from config.local.json, then config.default.json."
        exit 2  # stated refusal
    }
    $buckets = @()
    $product = ''
    if ($global:P20Config) {
        $buckets = @(Get-P20BurnBuckets -Value @($global:P20Config.BurnBuckets))
        $product = [string]$global:P20Config.BurnProduct
    }
    $machine = Get-P20UsageMachineName
    $promptsRoot = Get-P20PromptsRoot -PackageRoot $packageRoot
    $usageDir = ''
    if (Test-P20HubRoot $promptsRoot) { $usageDir = Get-P20HubFolder -Name 'usage' -PromptsRoot $promptsRoot -PackageRoot $packageRoot }
    $readingsDir = ''
    if ($usageDir) { $readingsDir = Get-P20BurnReadingsDir -UsageDir $usageDir }
    $windows = Get-P20BurnWindows -Now $now -WeekStart $weekStart
    $weekKey = $windows.WeekStart.ToString('yyyy-MM-dd', $inv)

    $writeBurndown = {
        param($Block)
        $local = { param($s) ([DateTimeOffset]::Parse($s, $inv)).LocalDateTime }
        $resets = & $local $Block.resetsAt
        $left = $resets - $now
        if ($left -lt [TimeSpan]::Zero) { $left = [TimeSpan]::Zero }
        $leftText = "$([int][Math]::Floor($left.TotalDays))d $($left.Hours)h left"
        $title = 'Weekly burndown'
        if ($Block.product) { $title += ", $($Block.product) plan" }
        Write-Host ""
        Write-Host ("  {0} -- resets {1} ({2})" -f $title, $resets.ToString('ddd d MMM HH:mm', $inv), $leftText) -ForegroundColor Cyan
        $width = 0
        foreach ($b in @($Block.buckets)) { if ($b.label.Length -gt $width) { $width = $b.label.Length } }
        foreach ($b in @($Block.buckets)) {
            $name = $b.label.PadRight($width)
            if ($null -eq $b.percent) {
                Write-Host ("      {0}   no reading this week" -f $name)
                continue
            }
            $filled = [int][Math]::Floor(([int]$b.percent) / 5.0 + 0.5)
            $bar = ('#' * $filled) + ('.' * (20 - $filled))
            $pace = 'on pace'
            if ($b.gap -gt 0) { $pace = "ahead of pace by $($b.gap)" }
            elseif ($b.gap -lt 0) { $pace = "behind pace by $(-[int]$b.gap)" }
            Write-Host ("      {0}   {1}  {2,3}%   {3} (pace {4}% at {5})" -f $name, $bar, $b.percent, $pace, $b.pace, (& $local $b.readingAt).ToString('ddd HH:mm', $inv))
        }
        if ($null -eq $Block.cachedAt) {
            $example = @(@($Block.buckets) | ForEach-Object { "$($_.key)=<n>" }) -join ','
            Write-Host "      No reading this week. Record one from Claude's usage page: ${prefix}Burn -Reading $example" -ForegroundColor DarkGray
        }
        else {
            $cachedAt = & $local $Block.cachedAt
            $renewsAt = & $local $Block.renewsAt
            $renewWord = 'renews'
            if ($Block.due) { $renewWord = 'renewal due since' }
            Write-Host ("      *cached as of {0} - {1} {2} (burn.cacheHours {3})" -f $cachedAt.ToString('ddd d MMM HH:mm', $inv), $renewWord, $renewsAt.ToString('ddd d MMM HH:mm', $inv), $Block.cacheHours) -ForegroundColor DarkGray
        }
        Write-Host "      Typed readings, never estimated; pace is an even line from 0% at the week's start to 100% at the reset." -ForegroundColor DarkGray
    }

    if ($hasReading) {
        # -- A plan reading: recorded, then the burndown ------------------------
        if ($buckets.Count -eq 0) {
            Write-CliError -Message "The plan has no buckets to read (burn.buckets is empty)." `
                -Hint "burn.buckets in config.default.json names them: [{ `"key`": `"general`", `"label`": `"General`" }, ...]."
            exit 2  # stated refusal
        }
        $parsedReading = ConvertFrom-P20BurnReading -Text $Reading -Buckets $buckets
        if (-not $parsedReading.Ok) {
            $example = @($buckets | ForEach-Object { "$($_.key)=<n>" }) -join ','
            Write-CliError -Message $parsedReading.Reason -Hint "${prefix}Burn -Reading $example -- whole percents, one bucket or several."
            exit 2  # stated refusal
        }
        if (-not $usageDir) {
            Write-CliError -Message (Get-P20HubMissingMessage $promptsRoot)
            exit 2  # stated refusal
        }
        $added = Add-P20BurnReading -ReadingsDir $readingsDir -WeekKey $weekKey -Machine $machine -At ([DateTimeOffset]$now) `
            -Values $parsedReading.Values -WeekStart ([DateTimeOffset]$windows.WeekStart) -WeekStartsText $weekStart.Text -Product $product
        if (-not $added.Ok) {
            Write-CliError -Message $added.Reason -Hint "Move the file aside; the next reading starts the week's record again."
            exit 2  # stated refusal
        }
        $typed = @($parsedReading.Values.Keys | ForEach-Object { "$_=$($parsedReading.Values[$_])" }) -join ','
        if (Get-Command Write-ToolkitLog -ErrorAction SilentlyContinue) {
            Write-ToolkitLog -Type CMD -Source "${prefix}Burn" -Detail "-Reading $typed at $($now.ToString('yyyy-MM-dd HH:mm', $inv))"
        }
        $verbWord = 'Added a reading to'
        if ($added.Created) { $verbWord = 'Started' }
        Write-Host ""
        Write-Host "  [+] Recorded $typed at $($now.ToString('ddd d MMM HH:mm', $inv)) on $machine" -ForegroundColor Green
        Write-Host "      $verbWord the week's record ($($added.Count) reading(s) from this machine): $($added.Path)"
        $readBack = Read-P20BurnReadings -ReadingsDir $readingsDir -WeekKey $weekKey
        $block = Get-P20Burndown -WeekStart ([DateTimeOffset]$windows.WeekStart) -WeekEnd ([DateTimeOffset]$windows.WeekEnd) -Now ([DateTimeOffset]$now) `
            -CacheHours $cache.Hours -Buckets $buckets -Entries $readBack.Entries -Product $product
        & $writeBurndown $block
        Write-Host ""
        exit 0
    }

    $projectsRoot = Get-P20ClaudeProjectsRoot
    $read = Read-P20BurnSummary -ProjectsRoot $projectsRoot -UsageDir $usageDir -Now $now -WeekStart $weekStart `
        -PriceTable (Get-P20ClaudePriceTable -PackageRoot $packageRoot) -Machine $machine
    $sum = $read.Summary
    $weekReadings = Read-P20BurnReadings -ReadingsDir $readingsDir -WeekKey $weekKey
    $burndown = Get-P20Burndown -WeekStart ([DateTimeOffset]$windows.WeekStart) -WeekEnd ([DateTimeOffset]$windows.WeekEnd) -Now ([DateTimeOffset]$now) `
        -CacheHours $cache.Hours -Buckets $buckets -Entries $weekReadings.Entries -Product $product
    $sum['burndown'] = $burndown
    $sum.skipped['readings'] = [long]$weekReadings.Skipped
    $burnCost = { param($v) if ($null -eq $v) { 'no priced model' } else { '$' + ([decimal]$v).ToString('0.00', $inv) + ' derived' } }
    if (Get-Command Write-ToolkitLog -ErrorAction SilentlyContinue) {
        Write-ToolkitLog -Type CMD -Source "${prefix}Burn" -Detail ("today $($sum.today.totals.messages) messages, $(& $burnCost $sum.today.totals.costUsdDerived); week $($sum.week.totals.messages) messages, $(& $burnCost $sum.week.totals.costUsdDerived)" + $(if ($AsJson) { ' (-AsJson)' } else { '' }))
    }
    if ($AsJson) {
        Write-Output (ConvertTo-P20ConfigJson $sum)
        exit 0
    }

    $writeBlock = {
        param($Title, $Block)
        $t = $Block.totals
        Write-Host ""
        Write-Host ("  {0}  {1} messages, {2}" -f $Title, $t.messages, (& $burnCost $t.costUsdDerived)) -ForegroundColor Cyan
        if (@($Block.byModel).Count -eq 0) { Write-Host "      nothing counted" -ForegroundColor DarkGray }
        foreach ($m in @($Block.byModel)) {
            $c = 'unpriced'
            if ($null -ne $m.costUsdDerived) { $c = '$' + ([decimal]$m.costUsdDerived).ToString('0.00', $inv) }
            Write-Host ("      {0,-22} {1,6} msgs  in {2,10}  out {3,10}  cache write {4,11}  cache read {5,13}  {6}" -f `
                    $m.model, $m.messages, $m.input, $m.output, ($m.cacheWrite5m + $m.cacheWrite1h), $m.cacheRead, $c)
        }
        $parts = @()
        foreach ($row in @($Block.machines)) {
            if ($row.source -eq 'session-files') { $parts += "$($row.machine) (session files)" }
            else { $parts += "$($row.machine) ($(@($row.days).Count) day record(s): $(@($row.days) -join ', '))" }
        }
        if ($parts.Count -gt 0) { Write-Host "      from $($parts -join '; ')" -ForegroundColor DarkGray }
    }

    $todayStart = [DateTime]::Parse($sum.today.from, $inv).ToLocalTime()
    $weekFrom = [DateTime]::Parse($sum.week.from, $inv).ToLocalTime()
    Write-Host ""
    $asOfText = ''
    if ($PSBoundParameters.ContainsKey('At')) { $asOfText = ' as of ' + $now.ToString('yyyy-MM-dd HH:mm', $inv) }
    if ($buckets.Count -gt 0) { & $writeBurndown $burndown }
    Write-Host ""
    Write-Host "  Claude Code burn on $machine$asOfText -- cost derived from list prices as of $($sum.cost.priceTableAsOf), not the plan's allocation" -ForegroundColor Cyan
    & $writeBlock ("Today, " + $todayStart.ToString('ddd d MMM', $inv)) $sum.today
    & $writeBlock ("This week, from " + $weekFrom.ToString('ddd d MMM HH:mm', $inv) + " (the week starts $($weekStart.Text), burn.weekStarts)") $sum.week
    Write-Host ""
    if (-not $sum.sessionFiles) { Write-Host "  No Claude Code session files on this machine ($projectsRoot is not there): it adds nothing." -ForegroundColor DarkGray }
    if (-not $sum.hub) { Write-Host "  No hub usage/ folder: no other machine's records were read." -ForegroundColor DarkGray }
    foreach ($n in @($sum.cost.priceNotes)) { Write-Host "  $($n.model) is $($n.note)." -ForegroundColor DarkGray }
    $unpriced = @(@($sum.today.unpriced) + @($sum.week.unpriced) | Sort-Object -Unique)
    if ($unpriced.Count -gt 0) { Write-Host "  Not in Config/claude-prices.json, so counted without a cost: $($unpriced -join ', ')" -ForegroundColor Yellow }
    if ($sum.skipped.lines -gt 0) { Write-Host "  $($sum.skipped.lines) line(s) could not be read and were skipped." -ForegroundColor DarkGray }
    if ($weekReadings.Skipped -gt 0) { Write-Host "  $($weekReadings.Skipped) reading(s) or file(s) in usage/$((Get-P20Consts).usage.readingsFolder)/ could not be read and were skipped." -ForegroundColor DarkGray }
    if ($sum.skipped.records -gt 0) { Write-Host "  $($sum.skipped.records) file(s) in usage/ could not be read as a record and were skipped." -ForegroundColor DarkGray }
    Write-Host "  Another machine's day record counts toward the week it starts in; ${prefix}Burn -Log writes this machine's." -ForegroundColor DarkGray
    Write-Host ""
    exit 0
}

$today = (Get-Date).Date
$day = $today
if ($PSBoundParameters.ContainsKey('Date')) {
    $typed = ([string]$Date).Trim()
    $parsed = [DateTime]::MinValue
    if ($typed -notmatch '^\d{4}-\d{2}-\d{2}$' -or
        -not [DateTime]::TryParseExact($typed, 'yyyy-MM-dd', $inv, [System.Globalization.DateTimeStyles]::None, [ref]$parsed)) {
        Write-CliError -Message "'$typed' is not a day: -Date takes yyyy-mm-dd." -Hint "${prefix}Burn -Log -Date $($today.ToString('yyyy-MM-dd', $inv))"
        exit 2  # stated refusal
    }
    if ($parsed.Date -gt $today) {
        Write-CliError -Message "$typed has not happened yet: there is nothing to log." -Hint "${prefix}Burn -Log logs today; -Date names a past day."
        exit 2  # stated refusal
    }
    $day = $parsed.Date
}
$dayKey = $day.ToString('yyyy-MM-dd', $inv)

$projectsRoot = Get-P20ClaudeProjectsRoot
if (-not (Test-Path -LiteralPath $projectsRoot -PathType Container)) {
    Write-Host ""
    Write-Host "  No Claude Code session files on this machine ($projectsRoot is not there). Nothing written." -ForegroundColor DarkGray
    Write-Host ""
    exit 0
}

$promptsRoot = Get-P20PromptsRoot -PackageRoot $packageRoot
if (-not (Test-P20HubRoot $promptsRoot)) {
    Write-CliError -Message (Get-P20HubMissingMessage $promptsRoot)
    exit 2  # stated refusal
}

$machine = Get-P20UsageMachineName
$read = Read-P20ClaudeUsageDay -ProjectsRoot $projectsRoot -Day $day -PriceTable (Get-P20ClaudePriceTable -PackageRoot $packageRoot) -Machine $machine
$record = $read.Record

$usageDir = Get-P20HubFolder -Name 'usage' -PromptsRoot $promptsRoot -PackageRoot $packageRoot
if (-not (Test-Path -LiteralPath $usageDir)) { New-Item -ItemType Directory -Path $usageDir -Force | Out-Null }
$recordPath = Join-Path $usageDir "$dayKey-$machine.json"
$replaced = Test-Path -LiteralPath $recordPath
Write-CardText -Path $recordPath -Content ((ConvertTo-P20ConfigJson $record) + "`n") -New

$t = $record.totals
$costText = 'no priced model'
if ($null -ne $t.costUsdDerived) { $costText = '$' + ([decimal]$t.costUsdDerived).ToString('0.00', $inv) + ' derived' }
if (Get-Command Write-ToolkitLog -ErrorAction SilentlyContinue) {
    Write-ToolkitLog -Type CMD -Source "${prefix}Burn" -Detail "-Log $dayKey -> $($t.messages) messages, $costText"
}

$verb = 'Wrote'
if ($replaced) { $verb = 'Replaced' }
Write-Host ""
Write-Host "  [+] $verb the Claude Code usage for $dayKey on $machine" -ForegroundColor Green
Write-Host "      $recordPath"
Write-Host "      $($t.messages) messages in $(@($record.bySession).Count) sessions, from $($read.Files) session files -- $costText (list prices as of $($record.cost.priceTableAsOf), not the plan's allocation)"
foreach ($m in @($record.byModel)) {
    $c = 'unpriced'
    if ($null -ne $m.costUsdDerived) { $c = '$' + ([decimal]$m.costUsdDerived).ToString('0.00', $inv) }
    Write-Host ("      {0,-22} {1,6} msgs  in {2,10}  out {3,10}  cache write {4,11}  cache read {5,13}  {6}" -f `
            $m.model, $m.messages, $m.input, $m.output, ($m.cacheWrite5m + $m.cacheWrite1h), $m.cacheRead, $c)
}
foreach ($n in @($record.cost.priceNotes)) { Write-Host "      $($n.model) is $($n.note)." -ForegroundColor DarkGray }
if (@($record.unpriced).Count -gt 0) {
    Write-Host "      Not in Config/claude-prices.json, so counted without a cost: $(@($record.unpriced) -join ', ')" -ForegroundColor Yellow
}
if ($read.Skipped -gt 0) {
    Write-Host "      $($read.Skipped) line(s) could not be read and were skipped." -ForegroundColor DarkGray
}
Write-Host ""
exit 0
