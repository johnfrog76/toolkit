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
    with -Log (whose day is -Date).
.NOTES
    PowerShell 5.1 compatible (ASCII only).
#>
[CmdletBinding()]
param(
    [switch]$Log,
    [string]$Date,
    [switch]$AsJson,
    [string]$At,
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
    Write-Host "    ${prefix}Burn -Log [-Date <yyyy-mm-dd>]"
    Write-Host ""
    Write-Host "  Alone: today and this week (from burn.weekStarts, Friday 05:00 by default),"
    Write-Host "  this machine's session files"
    Write-Host "  plus the other machines' records in the hub. -Log writes"
    Write-Host "  usage/<date>-<machine>.json in the hub: tokens by model and session, cost derived."
    Write-Host ""
    exit 0
}

foreach ($helper in @('Resolve-HubConfig.ps1', 'Get-Consts.ps1', 'Write-ConfigJson.ps1', 'Read-ClaudeUsage.ps1')) {
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
    $projectsRoot = Get-P20ClaudeProjectsRoot
    $machine = Get-P20UsageMachineName
    $promptsRoot = Get-P20PromptsRoot -PackageRoot $packageRoot
    $usageDir = ''
    if (Test-P20HubRoot $promptsRoot) { $usageDir = Get-P20HubFolder -Name 'usage' -PromptsRoot $promptsRoot -PackageRoot $packageRoot }
    $read = Read-P20BurnSummary -ProjectsRoot $projectsRoot -UsageDir $usageDir -Now $now -WeekStart $weekStart `
        -PriceTable (Get-P20ClaudePriceTable -PackageRoot $packageRoot) -Machine $machine
    $sum = $read.Summary
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
