<#
.SYNOPSIS
    Burn -Log -- write the day's Claude Code usage on this machine into the hub, once a day.
.DESCRIPTION
    Reads Claude Code's own session files on this machine (Scripts/Read-ClaudeUsage.ps1:
    CLAUDE_CONFIG_DIR's projects folder, else ~/.claude/projects) and writes ONE record
    for one local day and this machine: <hub>/usage/<yyyy-mm-dd>-<machine>.json, through
    Write-CardText -New (UTF-8, no BOM, LF). Run again the same day, it REPLACES that
    record -- never a second file, never an append -- and over the same session files
    it writes the same bytes. The record carries tokens by model and by session, and a
    cost DERIVED from Config/claude-prices.json, labelled so; never a path, a user
    name, or a plan's allocation. docs/hub/usage.md is its shape.

    Read-only over Claude Code's folder. A machine without one writes nothing and
    says so, exit 0. Without -Log the verb refuses, once (exit 2): reading the day
    back is a later verb.
.PARAMETER Log
    Write the record. The one thing the verb does today.
.PARAMETER Date
    The local day to log, yyyy-mm-dd. Default: today.
.NOTES
    PowerShell 5.1 compatible (ASCII only).
#>
[CmdletBinding()]
param(
    [switch]$Log,
    [string]$Date,
    [switch]$Help
)

$ErrorActionPreference = 'Stop'
$scriptsDir = $PSScriptRoot
$packageRoot = Split-Path $scriptsDir -Parent

. (Join-Path $scriptsDir 'Initialize-CliFallbacks.ps1')
$prefix = Get-CliPrefix

if ($Help) {
    Write-Host ""
    Write-Host "  ${prefix}Burn -- the day's Claude Code usage, logged into the hub" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "    ${prefix}Burn -Log [-Date <yyyy-mm-dd>]"
    Write-Host ""
    Write-Host "  Reads Claude Code's session files on this machine (read-only) and writes"
    Write-Host "  usage/<date>-<machine>.json in the hub: tokens by model and session, cost derived."
    Write-Host ""
    exit 0
}

foreach ($helper in @('Resolve-HubConfig.ps1', 'Get-Consts.ps1', 'Write-ConfigJson.ps1', 'Read-ClaudeUsage.ps1')) {
    . (Join-Path $scriptsDir $helper)
}

if (-not $Log) {
    Write-CliError -Message "${prefix}Burn needs -Log: writing the day's record is the one thing it does yet." `
        -Hint "${prefix}Burn -Log, or ${prefix}Burn -Log -Date <yyyy-mm-dd> for a past day."
    exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
}

$inv = [System.Globalization.CultureInfo]::InvariantCulture
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
if (@($record.unpriced).Count -gt 0) {
    Write-Host "      Not in Config/claude-prices.json, so counted without a cost: $(@($record.unpriced) -join ', ')" -ForegroundColor Yellow
}
if ($read.Skipped -gt 0) {
    Write-Host "      $($read.Skipped) line(s) could not be read and were skipped." -ForegroundColor DarkGray
}
Write-Host ""
exit 0
