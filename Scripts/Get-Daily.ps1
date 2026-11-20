<#
.SYNOPSIS
    Daily -- print a week's timesheet from the active Space's cards.
.DESCRIPTION
    The terminal's Daily: the same week the web UI's Daily page shows, built by
    the same script (agent/ado/Get-WeeklyBilling.ps1) from the same hub and the
    same Space folder the agent passes it. This week by default; -LastWeek for
    the week before; -Since and -Until for any window, both yyyy-MM-dd.

    What it prints is the `raw` the page's Copy All copies -- or, with -Compact,
    the `compact` its Short lines copy -- on the output stream, so it can be piped
    (`Daily | Set-Clipboard`). What was left off the week (cards marked not
    billable, cards with no date) is said after it, on the host only.

    The window is checked first, by the one rule the billing script also runs
    (Scripts/Resolve-BillingWindow.ps1), so a refusal is said once, in the same
    words the page shows. Read-only: nothing in the hub is written, and the
    clipboard is not touched.
.PARAMETER LastWeek
    The previous Monday to Friday.
.PARAMETER Since
    The window's first day, yyyy-MM-dd. Only with -Until.
.PARAMETER Until
    The window's last day, yyyy-MM-dd. Only with -Since.
.PARAMETER Compact
    Each day as one line per status group -- the page's Short lines.
.EXAMPLE
    {cliPrefix}Daily
    {cliPrefix}Daily -LastWeek
    {cliPrefix}Daily -Since <yyyy-MM-dd> -Until <yyyy-MM-dd>
.NOTES
    PowerShell 5.1 compatible (ASCII only).
#>
[CmdletBinding()]
param(
    [switch]$LastWeek,
    [string]$Since,
    [string]$Until,
    [switch]$Compact,
    [switch]$Help
)

. (Join-Path $PSScriptRoot 'Initialize-CliFallbacks.ps1')
$prefix = Get-CliPrefix

if ($Help) {
    Write-Host ""
    Write-Host "  ${prefix}Daily                                          This week, from the cards" -ForegroundColor Cyan
    Write-Host "  ${prefix}Daily -LastWeek                                The week before" -ForegroundColor Cyan
    Write-Host "  ${prefix}Daily -Since <yyyy-MM-dd> -Until <yyyy-MM-dd>  Any window" -ForegroundColor Cyan
    Write-Host "  ${prefix}Daily -Compact                                 One line per status group a day" -ForegroundColor Cyan
    Write-Host "  ${prefix}Daily -Help                                    Show this help" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  The same week the web UI's Daily page shows, as the text its Copy All" -ForegroundColor Gray
    Write-Host "  copies. Each card is on every working day from its Created line to its" -ForegroundColor Gray
    Write-Host "  Closed line, plus the days git saw it worked. Nothing is written." -ForegroundColor Gray
    Write-Host ""
    return
}

$cfg = $global:P20Config
$promptsRoot = [string]$cfg.PromptsRoot
. (Join-Path $PSScriptRoot 'Resolve-HubConfig.ps1')
if (-not (Test-P20HubRoot $promptsRoot)) {
    Write-CliError -Message (Get-P20HubMissingMessage $promptsRoot)
    exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
}

. (Join-Path $PSScriptRoot 'Resolve-BillingWindow.ps1')
$window = Resolve-P20BillingWindow -Since $Since -Until $Until
if ($window.Error) {
    Write-CliError -Message $window.Error `
        -Hint "'${prefix}Daily -Since 2026-01-05 -Until 2026-01-09' is a window; '${prefix}Daily -LastWeek' is the week before."
    exit 2  # stated refusal
}

# The Space folder, as the agent passes it: '.' for a Space at the hub root,
# because the script refuses without one and 5.1 drops an empty argument.
$folder = [string]$cfg.PromptsFolder
if (-not $folder) { $folder = '.' }
$billingScript = Join-Path (Join-Path (Join-Path (Split-Path $PSScriptRoot -Parent) 'agent') 'ado') 'Get-WeeklyBilling.ps1'
if (-not (Test-Path -LiteralPath $billingScript)) {
    Write-CliError -Message "The billing script is missing: $billingScript" `
        -Hint "This package is incomplete. '${prefix}Update' restores it."
    exit 2  # stated refusal
}

$params = @{ PromptsRoot = $promptsRoot; PromptsFolder = $folder; AsJson = $true }
if ($window.HasWindow) {
    $params.Since = $Since
    $params.Until = $Until
}
elseif ($LastWeek) {
    $params.LastWeek = $true
}

# In this session, with -AsJson: the script's text mode writes to the host and
# the clipboard, and its JSON is what the page reads. Its exit code is not read:
# the git calls inside it leave $LASTEXITCODE at whatever git said, so the
# answer is whether it printed a week.
$ErrorActionPreference = 'Continue'
$json = (& $billingScript @params | Out-String).Trim()
$data = $null
if ($json) {
    try { $data = $json | ConvertFrom-Json } catch { $data = $null }
}
if ($null -eq $data -or $null -eq $data.raw) {
    Write-CliError -Message "The week could not be built: the billing script answered no week." `
        -Hint "Its own reason, if it gave one, is above. '${prefix}Log -Errors' has the details."
    exit 2  # stated refusal
}

$text = [string]$data.raw
if ($Compact -and [string]$data.compact) { $text = [string]$data.compact }
Write-Output $text

# What is NOT on the week, and why: a timesheet is filled in from this.
$left = @()
$off = [int]$data.nonBillable
if ($off -gt 0) { $left += $(if ($off -eq 1) { '1 card marked not billable' } else { "$off cards marked not billable" }) }
$blank = [int]$data.unstamped
if ($blank -gt 0) { $left += $(if ($blank -eq 1) { '1 card with no date' } else { "$blank cards with no date" }) }
if ($left.Count -gt 0) {
    Write-Host ""
    Write-Host "  Left off: $($left -join '; ')." -ForegroundColor Gray
}
exit 0
