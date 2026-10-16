<#
.SYNOPSIS
    View and filter the toolkit diagnostic log (usage.*.log).
.DESCRIPTION
    Reads all toolkit/usage.*.log files (one per machine) and displays
    entries merged and sorted by timestamp with color-coded output.
    Supports filtering by type, date range, command name, and live tailing.
.EXAMPLE
    {cliPrefix}Log                          # Last 20 entries (all machines)
    {cliPrefix}Log -Errors                  # ERR entries only
    {cliPrefix}Log -Today                   # All entries from today
    {cliPrefix}Log -Days 7                  # Last 7 days
    {cliPrefix}Log -Command {cliPrefix}Sync          # Entries for a specific command
    {cliPrefix}Log -Type WARN               # Entries of a specific type
    {cliPrefix}Log -Clear                   # Archive all log files, start fresh
    {cliPrefix}Log -Tail                    # Live tail this machine's log (Ctrl+C to stop)
    {cliPrefix}Log -Help                    # Show usage
#>
[CmdletBinding()]
param(
    [switch]$Errors,
    [switch]$Today,
    [int]$Days,
    [string]$Command,
    [ValidateSet('CMD', 'ERR', 'WARN', 'INFO')]
    [string]$Type,
    [switch]$Clear,
    [switch]$Tail,
    [switch]$Ack,
    [switch]$Help,
    [int]$Count = 20
)

. (Join-Path $PSScriptRoot 'Initialize-CliFallbacks.ps1')


$toolkitRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)

# Where the usage logs live. The package root, unless P20_USAGE_LOG_DIR names
# somewhere else -- the one override both halves read, so a test run logs to
# scratch instead of into the engineer's own history (docs/CLI.md, "The log").
# config.local.json and the -Clear archives stay with the package either way:
# this variable moves the log, not the toolkit.
$logRoot = $toolkitRoot
if ($env:P20_USAGE_LOG_DIR -and $env:P20_USAGE_LOG_DIR.Trim()) { $logRoot = $env:P20_USAGE_LOG_DIR.Trim() }

# -- Ack: dismiss error indicator ----------------------------------------------
if ($Ack) {
    $localCfgPath = Join-Path $toolkitRoot 'config.local.json'
    # Config's own writer for the file: no BOM, LF, atomic, the same on both hosts.
    # Resolve-HubConfig.ps1 gives it the long form of a short (8.3) folder name.
    if (-not (Get-Command ConvertTo-P20LongPath -ErrorAction SilentlyContinue)) { . (Join-Path $PSScriptRoot 'Resolve-HubConfig.ps1') }
    if (-not (Get-Command Write-ConfigJson -ErrorAction SilentlyContinue)) { . (Join-Path $PSScriptRoot 'Write-ConfigJson.ps1') }
    # Read so it can be written back as it was: PowerShell 7 would otherwise turn an
    # ISO-8601-looking string (menuResetTimestamp) into a [datetime], and the writer
    # would put it back in another format. 5.1 never does.
    $ackJsonArgs = @{}
    if ((Get-Command ConvertFrom-Json).Parameters.ContainsKey('DateKind')) { $ackJsonArgs['DateKind'] = 'String' }
    if (Test-Path $localCfgPath) {
        # A file that will not parse is left exactly as it is: writing the ack into
        # what was read (nothing) would replace the person's settings.
        try { $localCfg = Get-Content $localCfgPath -Raw -Encoding UTF8 | ConvertFrom-Json @ackJsonArgs }
        catch {
            if (-not (Get-Command Write-P20ConfigParseWarning -ErrorAction SilentlyContinue)) { . (Join-Path $PSScriptRoot 'Write-ConfigParseWarning.ps1') }
            $null = Write-P20ConfigParseWarning -Path $localCfgPath -Message $_.Exception.Message
            $ackWhy = 'config.local.json will not parse, so the errors were not acknowledged.'
            $ackHint = 'Fix the file by hand (or delete it); it was not changed.'
            if (Get-Command Write-CliError -ErrorAction SilentlyContinue) { Write-CliError -Message $ackWhy -Hint $ackHint }
            else { Write-Host "Error: $ackWhy" -ForegroundColor Red; Write-Host "Hint:  $ackHint" -ForegroundColor Yellow }
            exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
        }
    }
    else {
        $localCfg = [PSCustomObject]@{}
    }
    $localCfg | Add-Member -NotePropertyName 'errorsAckedAt' -NotePropertyValue (Get-Date -Format 'yyyy-MM-ddTHH:mm:ss') -Force
    Write-ConfigJson -Path $localCfgPath -Value $localCfg
    Write-Host "  Errors acknowledged - indicator dismissed until new errors occur." -ForegroundColor Green
    return
}

# -- Help ----------------------------------------------------------------------
if ($Help) {
    Write-Host ""
    Write-Host "  $(Get-CliPrefix)Log                          Last 20 entries (all types)" -ForegroundColor Cyan
    Write-Host "  $(Get-CliPrefix)Log -Errors                  ERR entries only" -ForegroundColor Cyan
    Write-Host "  $(Get-CliPrefix)Log -Today                   All entries from today" -ForegroundColor Cyan
    Write-Host "  $(Get-CliPrefix)Log -Days 7                  Last 7 days" -ForegroundColor Cyan
    Write-Host "  $(Get-CliPrefix)Log -Command $(Get-CliPrefix)Sync          Entries for a specific command" -ForegroundColor Cyan
    Write-Host "  $(Get-CliPrefix)Log -Type WARN               Entries of a specific type (CMD, ERR, WARN, INFO)" -ForegroundColor Cyan
    Write-Host "  $(Get-CliPrefix)Log -Clear                   Archive current log, start fresh" -ForegroundColor Cyan
    Write-Host "  $(Get-CliPrefix)Log -Tail                    Live tail (Ctrl+C to stop)" -ForegroundColor Cyan
    Write-Host "  $(Get-CliPrefix)Log -Ack                     Dismiss error indicator in $(Get-CliPrefix)Menu" -ForegroundColor Cyan
    Write-Host "  $(Get-CliPrefix)Log -Help                    Show this help message" -ForegroundColor Cyan
    Write-Host ""
    return
}

# -- Format helper -------------------------------------------------------------
function Format-LogLine {
    param(
        [string]$Line,
        [bool]$ShowMachine = $true
    )
    $parts = $Line -split "`t"
    if ($parts.Count -lt 5) { Write-Host "  $Line"; return }

    $time = ([datetime]$parts[0]).ToString('HH:mm:ss')
    $type = $parts[1].PadRight(4)
    $machine = $parts[2]
    $source = $parts[3].PadRight(20)
    $detail = $parts[4]

    $color = switch ($parts[1]) {
        'ERR' { 'Red' }
        'WARN' { 'Yellow' }
        'INFO' { 'DarkGray' }
        default { 'Gray' }
    }

    if ($ShowMachine) {
        $machineCol = $machine.PadRight(14)
        Write-Host "  $time  $type  $machineCol $source $detail" -ForegroundColor $color
    }
    else {
        Write-Host "  $time  $type  $source $detail" -ForegroundColor $color
    }
}

# -- Main ----------------------------------------------------------------------
$logFiles = Get-ChildItem -Path $logRoot -Filter 'usage.*.log' -ErrorAction SilentlyContinue
if (-not $logFiles) {
    Write-Host "  No usage log files found." -ForegroundColor Yellow
    return
}

# -Clear: archive all log files
if ($Clear) {
    $dateSuffix = Get-Date -Format 'yyyy-MM-dd-HHmmss'
    foreach ($lf in $logFiles) {
        $archiveName = "$($lf.BaseName).$dateSuffix.bak"
        $archivePath = Join-Path $logRoot $archiveName
        Move-Item -Path $lf.FullName -Destination $archivePath
    }
    Write-ToolkitLog -Type INFO -Source "$(Get-CliPrefix)Log" -Detail "log cleared - archived $($logFiles.Count) file(s)"
    Write-Host "  Archived $($logFiles.Count) log file(s) - fresh log started." -ForegroundColor Green
    return
}

# -Tail: live tail this machine's log only
if ($Tail) {
    $machine = [System.Environment]::MachineName
    $localLog = Join-Path $logRoot "usage.$machine.log"
    if (-not (Test-Path $localLog)) {
        Write-Host "  No log file for this machine ($machine) yet." -ForegroundColor Yellow
        return
    }
    Write-Host "  Tailing usage.$machine.log (Ctrl+C to stop)..." -ForegroundColor DarkGray
    Get-Content $localLog -Wait -Tail 10 -Encoding UTF8 | ForEach-Object {
        Format-LogLine $_
    }
    return
}

# Read all log files and merge
$lines = @()
foreach ($lf in $logFiles) {
    $lines += Get-Content $lf.FullName -Encoding UTF8
}
# Sort by timestamp (first field)
$lines = $lines | Sort-Object { ($_ -split "`t")[0] }

if ($Errors) {
    $lines = $lines | Where-Object { ($_ -split "`t")[1] -eq 'ERR' }
}
if ($Today) {
    $todayPrefix = (Get-Date -Format 'yyyy-MM-dd')
    $lines = $lines | Where-Object { $_.StartsWith($todayPrefix) }
}
if ($Days -gt 0) {
    $cutoff = (Get-Date).AddDays(-$Days).ToString('yyyy-MM-ddTHH:mm:ss')
    $lines = $lines | Where-Object { ($_ -split "`t")[0] -ge $cutoff }
}
if ($Command) {
    $lines = $lines | Where-Object { ($_ -split "`t")[3] -eq $Command }
}
if ($Type) {
    $lines = $lines | Where-Object { ($_ -split "`t")[1] -eq $Type }
}

# Show last $Count entries (or all if filtered)
if (-not $Errors -and -not $Today -and $Days -eq 0 -and -not $Command -and -not $Type) {
    $lines = $lines | Select-Object -Last $Count
}

if (-not $lines -or @($lines).Count -eq 0) {
    Write-Host "  No matching entries." -ForegroundColor DarkGray
    return
}

# Determine if all entries are from the same machine (omit machine column if so)
$machines = @($lines | ForEach-Object { ($_ -split "`t")[2] } | Sort-Object -Unique)
$showMachine = $machines.Count -gt 1

Write-Host ""
foreach ($line in $lines) {
    Format-LogLine $line $showMachine
}
Write-Host ""
