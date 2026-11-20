#
# The weekly burndown: the plan's usage as typed readings, and how far each
# bucket is ahead of or behind an even week (docs/hub/usage.md, "The weekly
# burndown").
#
# NOT a runnable verb: this file is DOT-SOURCED, by Scripts/Write-BurnLog.ps1
# (Burn, Burn -Reading) and by Scripts/Get-ConfigSchema.ps1 (Config -Set
# burn.cacheHours is validated by the reader Burn uses, so a value -Set accepts
# is a value Burn reads).
#
# THE READINGS ARE TYPED. Nothing on this machine holds the plan's percentages:
# Claude Code's session files hold tokens, and a percentage worked out from
# tokens or cost would be a made-up number. So a reading is what the person read
# off Claude's usage page, recorded with the time it was taken, and nothing here
# estimates one.
#
# THE RECORD: <usage>/<readings>/<yyyy-mm-dd>-<machine>.json -- one file per
# week per machine, <yyyy-mm-dd> the local date the week starts on, <readings>
# consts.json usage.readingsFolder. A subfolder, so the day-record reader (which
# reads usage/*.json, not below) never meets one. Per machine, so two machines
# never write one synced file; the week's readings are every machine's files
# merged by time.
#
# THE RULE (Get-P20Burndown; Tests/fixtures/usage/burndown.json is its table):
#   - a reading counts when its time is at or after the week's start, before the
#     reset and at or before now;
#   - per bucket, the latest such reading that names it (a tie goes to the
#     machine that sorts last);
#   - pace = round-half-up(elapsed / week length x 100), the elapsed time
#     measured AT THE READING, in real time (UTC instants);
#   - gap = percent - pace, whole points: more than zero is ahead, less is behind;
#   - cachedAt = the latest reading used, renewsAt = cachedAt + burn.cacheHours,
#     due = now at or past renewsAt. A fact, not a warning.
#
# PowerShell 5.1 clean: no ternary, no null-coalescing, ASCII only.
#

if (-not (Get-Command Get-P20Consts -ErrorAction SilentlyContinue)) {
    . (Join-Path $PSScriptRoot 'Get-Consts.ps1')
}
# ConvertTo-P20UtcInstant, the one reader of a usage file's instants.
if (-not (Get-Command ConvertTo-P20UtcInstant -ErrorAction SilentlyContinue)) {
    . (Join-Path $PSScriptRoot 'Read-ClaudeUsage.ps1')
}

function Get-P20BurnCacheHours {
    <#
      burn.cacheHours: how long a reading is taken as current, a whole number
      of hours from 1 to 168 (a week). Returns @{ Ok; Hours; Reason }. Empty
      (no line anywhere) reads as 4, the shipped default.
    #>
    param([AllowEmptyString()][AllowNull()][string]$Value)
    $raw = ([string]$Value).Trim()
    if (-not $raw) { return @{ Ok = $true; Hours = 4; Reason = '' } }
    $n = 0
    if ($raw -notmatch '^\d+$' -or -not [int]::TryParse($raw, [ref]$n) -or $n -lt 1 -or $n -gt 168) {
        return @{ Ok = $false; Hours = 0; Reason = "burn.cacheHours is a whole number of hours from 1 to 168 -- got '$raw'." }
    }
    return @{ Ok = $true; Hours = $n; Reason = '' }
}

function Get-P20BurnBuckets {
    <#
      burn.buckets as rows of @{ key; label }, in config order. A row with no
      key is dropped; a row with no label is labelled by its key.
    #>
    param($Value)
    $rows = @()
    foreach ($b in @($Value)) {
        if ($null -eq $b) { continue }
        $key = ''
        $label = ''
        if ($b -is [System.Collections.IDictionary]) { $key = [string]$b['key']; $label = [string]$b['label'] }
        else {
            if ($b.PSObject.Properties['key']) { $key = [string]$b.key }
            if ($b.PSObject.Properties['label']) { $label = [string]$b.label }
        }
        $key = $key.Trim()
        if (-not $key) { continue }
        if (-not $label.Trim()) { $label = $key }
        $rows += [ordered]@{ key = $key; label = $label.Trim() }
    }
    return $rows
}

function ConvertFrom-P20BurnReading {
    <#
      What -Reading typed: "general=43,premium=54", as one string or as the
      array PowerShell binds the unquoted comma form to. Each piece is a bucket
      key (any case) from -Buckets and a whole percent from 0 to 100; one
      bucket or several, each once. Returns @{ Ok; Values (ordered key ->
      int, in the order typed); Reason }.
    #>
    param([AllowEmptyCollection()][string[]]$Text, [Parameter(Mandatory = $true)][AllowEmptyCollection()]$Buckets)
    $known = @(@($Buckets) | ForEach-Object { [string]$_.key })
    $shape = "bucket=percent, like $(@($known | ForEach-Object { "$_=<n>" }) -join ',')"
    $pieces = @()
    foreach ($t in @($Text)) { foreach ($p in ([string]$t -split ',')) { if ($p.Trim()) { $pieces += $p.Trim() } } }
    if ($pieces.Count -eq 0) {
        return @{ Ok = $false; Values = $null; Reason = "-Reading takes $shape." }
    }
    $values = [ordered]@{}
    foreach ($p in $pieces) {
        $m = [regex]::Match($p, '^([^=\s]+)\s*=\s*(\S+)$')
        if (-not $m.Success) { return @{ Ok = $false; Values = $null; Reason = "'$p' is not bucket=percent: -Reading takes $shape." } }
        $typedKey = $m.Groups[1].Value
        $key = $null
        foreach ($k in $known) { if ($k -ieq $typedKey) { $key = $k } }
        if (-not $key) {
            return @{ Ok = $false; Values = $null; Reason = "'$typedKey' is not one of the plan's buckets (burn.buckets): $($known -join ', ')." }
        }
        if ($values.Contains($key)) { return @{ Ok = $false; Values = $null; Reason = "$key is typed twice: one percent per bucket." } }
        $n = 0
        $num = $m.Groups[2].Value.TrimEnd('%')
        if ($num -notmatch '^\d{1,3}$' -or -not [int]::TryParse($num, [ref]$n) -or $n -gt 100) {
            return @{ Ok = $false; Values = $null; Reason = "$key=$($m.Groups[2].Value) is not a reading: a whole percent from 0 to 100, as Claude's usage page shows it." }
        }
        $values[$key] = $n
    }
    return @{ Ok = $true; Values = $values; Reason = '' }
}

function Get-P20BurnReadingsDir {
    # <usage>/<readings>: the folder name is the contract's (consts.json usage.readingsFolder).
    param([Parameter(Mandatory = $true)][string]$UsageDir)
    return (Join-Path $UsageDir ([string](Get-P20Consts).usage.readingsFolder))
}

function Get-P20BurnStamp {
    # An instant as every usage file writes one: UTC, milliseconds, Z.
    param([Parameter(Mandatory = $true)]$Instant)
    $dto = [DateTimeOffset]$Instant
    return $dto.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ss.fffZ', [System.Globalization.CultureInfo]::InvariantCulture)
}

function ConvertTo-P20BurnEntries {
    <#
      One record's entries as @(@{ At (UTC DateTimeOffset); Machine; Buckets
      (ordered key -> int) }). An entry with no readable time, or a bucket value
      that is not a whole percent from 0 to 100, is dropped and counted.
    #>
    param($Record, [string]$Machine)
    $out = @()
    $bad = 0
    foreach ($e in @($Record.entries)) {
        if ($null -eq $e) { continue }
        $at = ConvertTo-P20UtcInstant $e.at
        if ($null -eq $at -or $null -eq $e.buckets) { $bad++; continue }
        $b = [ordered]@{}
        foreach ($p in $e.buckets.PSObject.Properties) {
            $n = 0
            if ([string]$p.Value -match '^\d{1,3}$' -and [int]::TryParse([string]$p.Value, [ref]$n) -and $n -le 100) { $b[$p.Name] = $n }
        }
        if ($b.Count -eq 0) { $bad++; continue }
        $who = $Machine
        if ($e.PSObject.Properties['machine'] -and $e.machine) { $who = [string]$e.machine }
        $out += @{ At = $at; Machine = $who; Buckets = $b }
    }
    return @{ Entries = $out; Skipped = $bad }
}

function Read-P20BurnReadings {
    <#
      Every machine's readings for the week whose local start date is -WeekKey
      (yyyy-mm-dd): the files <ReadingsDir>/<WeekKey>-*.json. Returns
      @{ Entries; Skipped } -- Skipped counts a file that is not a record and an
      entry that cannot be read.
    #>
    param([string]$ReadingsDir, [Parameter(Mandatory = $true)][string]$WeekKey)
    $entries = @()
    $skipped = 0
    if (-not $ReadingsDir -or -not (Test-Path -LiteralPath $ReadingsDir -PathType Container)) { return @{ Entries = @(); Skipped = 0 } }
    $jsonArgs = @{}
    if ((Get-Command ConvertFrom-Json).Parameters.ContainsKey('DateKind')) { $jsonArgs['DateKind'] = 'String' }
    foreach ($f in @(Get-ChildItem -LiteralPath $ReadingsDir -Filter "$WeekKey-*.json" -File -ErrorAction SilentlyContinue | Sort-Object Name)) {
        $r = $null
        try { $r = [System.IO.File]::ReadAllText($f.FullName, [System.Text.UTF8Encoding]::new($false)) | ConvertFrom-Json @jsonArgs -ErrorAction Stop }
        catch { $skipped++; continue }
        if ($null -eq $r -or -not $r.PSObject.Properties['entries']) { $skipped++; continue }
        $who = ''
        if ($r.PSObject.Properties['machine']) { $who = [string]$r.machine }
        if (-not $who) { $who = $f.BaseName.Substring([Math]::Min(11, $f.BaseName.Length)) }
        $read = ConvertTo-P20BurnEntries -Record $r -Machine $who
        $entries += @($read.Entries)
        $skipped += $read.Skipped
    }
    return @{ Entries = $entries; Skipped = $skipped }
}

function Get-P20Burndown {
    <#
      The burndown block at -Now: the rule in the header, over -Entries (any
      machine's, any week -- the ones outside the week or after -Now are not
      counted). -WeekStart and -WeekEnd are the week's instants. Returns the
      block Burn prints and Burn -AsJson carries as `burndown`.
    #>
    param(
        [Parameter(Mandatory = $true)]$WeekStart,
        [Parameter(Mandatory = $true)]$WeekEnd,
        [Parameter(Mandatory = $true)]$Now,
        [Parameter(Mandatory = $true)][int]$CacheHours,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()]$Buckets,
        [AllowEmptyCollection()]$Entries = @(),
        [string]$Product = ''
    )
    $from = ([DateTimeOffset]$WeekStart).ToUniversalTime()
    $to = ([DateTimeOffset]$WeekEnd).ToUniversalTime()
    $at = ([DateTimeOffset]$Now).ToUniversalTime()
    $length = ($to - $from).TotalMilliseconds
    $counted = @(@($Entries) | Where-Object { $_.At -ge $from -and $_.At -lt $to -and $_.At -le $at } |
            Sort-Object -Property @{ Expression = { $_.At.UtcTicks } }, @{ Expression = { [string]$_.Machine } })

    $rows = @()
    $latest = $null
    foreach ($b in @($Buckets)) {
        $hit = $null
        foreach ($e in $counted) { if ($e.Buckets.Contains($b.key)) { $hit = $e } }
        $row = [ordered]@{ key = $b.key; label = $b.label; percent = $null; readingAt = $null; machine = $null; pace = $null; gap = $null }
        if ($null -ne $hit) {
            $exact = 0.0
            if ($length -gt 0) { $exact = ($hit.At - $from).TotalMilliseconds / $length * 100 }
            $pace = [int][Math]::Floor($exact + 0.5)
            $percent = [int]$hit.Buckets[$b.key]
            $row.percent = $percent
            $row.readingAt = Get-P20BurnStamp $hit.At
            $row.machine = [string]$hit.Machine
            $row.pace = $pace
            $row.gap = $percent - $pace
            if ($null -eq $latest -or $hit.At -gt $latest) { $latest = $hit.At }
        }
        $rows += $row
    }
    $cachedAt = $null
    $renewsAt = $null
    $due = $false
    if ($null -ne $latest) {
        $renew = $latest.AddHours($CacheHours)
        $cachedAt = Get-P20BurnStamp $latest
        $renewsAt = Get-P20BurnStamp $renew
        $due = [bool]($at -ge $renew)
    }
    $points = @()
    foreach ($e in $counted) {
        $points += [ordered]@{ at = (Get-P20BurnStamp $e.At); machine = [string]$e.Machine; buckets = $e.Buckets }
    }
    return [ordered]@{
        product    = $Product
        source     = 'typed'
        weekFrom   = Get-P20BurnStamp $from
        resetsAt   = Get-P20BurnStamp $to
        cacheHours = $CacheHours
        cachedAt   = $cachedAt
        renewsAt   = $renewsAt
        due        = $due
        buckets    = $rows
        readings   = $points
    }
}

function Add-P20BurnReading {
    <#
      Appends one reading to this machine's record for the week, creating it on
      the week's first reading. The file is read, the entry added, the entries
      sorted by time, and the whole written through Write-CardText -- -New on a
      create (LF), as an edit otherwise (the file keeps its terminator). A file
      that is there but not a record is refused rather than overwritten.
      Returns @{ Ok; Path; Created; Count; Reason }.
    #>
    param(
        [Parameter(Mandatory = $true)][string]$ReadingsDir,
        [Parameter(Mandatory = $true)][string]$WeekKey,
        [Parameter(Mandatory = $true)][string]$Machine,
        [Parameter(Mandatory = $true)]$At,
        [Parameter(Mandatory = $true)]$Values,
        [Parameter(Mandatory = $true)]$WeekStart,
        [Parameter(Mandatory = $true)][string]$WeekStartsText,
        [string]$Product = ''
    )
    $path = Join-Path $ReadingsDir "$WeekKey-$Machine.json"
    $created = -not (Test-Path -LiteralPath $path)
    $existing = @()
    if (-not $created) {
        $jsonArgs = @{}
        if ((Get-Command ConvertFrom-Json).Parameters.ContainsKey('DateKind')) { $jsonArgs['DateKind'] = 'String' }
        $r = $null
        try { $r = [System.IO.File]::ReadAllText($path, [System.Text.UTF8Encoding]::new($false)) | ConvertFrom-Json @jsonArgs -ErrorAction Stop } catch { $r = $null }
        if ($null -eq $r -or -not $r.PSObject.Properties['entries']) {
            return @{ Ok = $false; Path = $path; Created = $false; Count = 0; Reason = "$path is there and is not a readings record, so it is not overwritten." }
        }
        foreach ($e in @($r.entries)) {
            if ($null -eq $e) { continue }
            $t = ConvertTo-P20UtcInstant $e.at
            if ($null -eq $t) { continue }
            $b = [ordered]@{}
            if ($null -ne $e.buckets) { foreach ($p in $e.buckets.PSObject.Properties) { $b[$p.Name] = $p.Value } }
            $existing += @{ At = $t; Buckets = $b }
        }
    }
    $buckets = [ordered]@{}
    foreach ($k in $Values.Keys) { $buckets[$k] = [int]$Values[$k] }
    $all = @($existing) + @(@{ At = ([DateTimeOffset]$At).ToUniversalTime(); Buckets = $buckets })
    $all = @($all | Sort-Object -Property @{ Expression = { $_.At.UtcTicks } })
    $entries = @()
    foreach ($e in $all) { $entries += [ordered]@{ at = (Get-P20BurnStamp $e.At); buckets = $e.Buckets } }
    $record = [ordered]@{
        readings   = 1
        product    = $Product
        source     = 'typed'
        machine    = $Machine
        weekStart  = Get-P20BurnStamp $WeekStart
        weekStarts = ($WeekStartsText + ' local')
        entries    = $entries
    }
    if (-not (Test-Path -LiteralPath $ReadingsDir)) { New-Item -ItemType Directory -Path $ReadingsDir -Force | Out-Null }
    $text = (ConvertTo-P20ConfigJson $record) + "`n"
    if ($created) { Write-CardText -Path $path -Content $text -New }
    else { Write-CardText -Path $path -Content $text }
    return @{ Ok = $true; Path = $path; Created = $created; Count = $entries.Count; Reason = '' }
}
