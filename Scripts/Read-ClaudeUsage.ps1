#
# What Claude Code spent on this machine on one local day, read from Claude
# Code's own session files. The reader behind `Burn -Log`.
#
# NOT a runnable verb: this file is DOT-SOURCED, by Scripts/Write-BurnLog.ps1
# (the verb) and by Scripts/Get-OptionalSurfaces.ps1 (the "Claude Code usage"
# row, which asks only whether the folder is there). One answer to "where are
# the session files", reached the same way from both.
#
# READ-ONLY over Claude Code's folder. Every file is opened for reading with
# every share flag, so a session that is writing its transcript right now is
# neither blocked nor touched; nothing here creates, renames or stamps a file
# there. Tests/Test-Burn.ps1 holds that with a before-and-after snapshot.
#
# THE FILES (docs/hub/usage.md, "Where the numbers come from"):
#
#   <projects>/<project folder>/<session id>.jsonl
#   <projects>/<project folder>/<session id>/subagents/agent-*.jsonl
#
# A subagent's lines carry the PARENT's sessionId, so they count to the parent
# session. Anything that is not a .jsonl in one of those two places is ignored.
#
# ONE API RESPONSE IS SEVERAL LINES -- one per content block -- and they repeat
# its usage. So a message is counted ONCE, by message.id (requestId when there
# is none), and each of its numbers is the LARGEST any of its lines carries: a
# streamed response's early lines carry a partial output count, and a replayed
# copy of a transcript can carry zeros. A message belongs to the local day of
# its EARLIEST line, so a session that runs past midnight splits by message.
#
# PowerShell 5.1 clean: no ternary, no null-coalescing, ASCII only.
#

if (-not (Get-Command Get-P20Consts -ErrorAction SilentlyContinue)) {
    . (Join-Path $PSScriptRoot 'Get-Consts.ps1')
}

function Get-P20ClaudeProjectsRoot {
    <#
      Where Claude Code keeps its session files on this machine: the projects
      folder of its configuration directory. CLAUDE_CONFIG_DIR is Claude Code's
      own variable for moving that directory, so it is honoured first -- a
      person who moved it is read where they moved it, and a suite points the
      verb at a fixture the same way. Otherwise ~/.claude/projects.
      Returns the path whether or not it exists; Test-Path is the caller's.
    #>
    $configDir = [System.Environment]::GetEnvironmentVariable('CLAUDE_CONFIG_DIR')
    if ($configDir -and $configDir.Trim()) {
        return (Join-Path $configDir.Trim() 'projects')
    }
    $home_ = [System.Environment]::GetFolderPath('UserProfile')
    if (-not $home_) { $home_ = $HOME }
    return (Join-Path (Join-Path $home_ '.claude') 'projects')
}

function Get-P20ClaudePriceTable {
    <#
      The one price table: Config/claude-prices.json, list prices in USD per
      million tokens. Read here and nowhere else, so a cost in the record is
      always the table's arithmetic and never a number typed beside it.
    #>
    param([Parameter(Mandatory = $true)][string]$PackageRoot)
    $path = Join-Path (Join-Path $PackageRoot 'Config') 'claude-prices.json'
    return ([System.IO.File]::ReadAllText($path) | ConvertFrom-Json)
}

function Find-P20ClaudePrice {
    <#
      The price row for one model id: the exact id, else the longest table id
      the model starts with followed by a hyphen (a dated snapshot of a priced
      model). $null when the table has no row -- the model is then counted and
      named as unpriced, never guessed.
    #>
    param($Table, [string]$Model)
    $best = $null
    $bestLen = -1
    foreach ($p in @($Table.models.PSObject.Properties)) {
        $id = [string]$p.Name
        if ($Model -eq $id) { return $p.Value }
        if ($Model.StartsWith($id + '-', [System.StringComparison]::Ordinal) -and $id.Length -gt $bestLen) { $best = $p.Value; $bestLen = $id.Length }
    }
    return $best
}

function Get-P20PriceNotes {
    <#
      What a price row says about its own price, for the models counted: one
      @{ model; note } per model whose row carries a note (that it is priced at
      its lower rate card, say), sorted by model id. Empty when none does. The
      record and the Burn read both carry it, so a cost is never shown without
      what it assumed.
    #>
    param($Table, [string[]]$Models)
    $out = @()
    foreach ($model in @($Models | Where-Object { $_ } | Sort-Object { $_ } -CaseSensitive -Unique)) {
        $price = Find-P20ClaudePrice -Table $Table -Model $model
        if ($null -ne $price -and $price.PSObject.Properties['note'] -and [string]$price.note) {
            $out += [ordered]@{ model = $model; note = [string]$price.note }
        }
    }
    return $out
}

function ConvertTo-P20UsageProjectName {
    <#
      A project by its LAST path segment and nothing more -- the record never
      carries a path, and a project folder's own name spells the home path out.
      The leaf of the line's cwd when there is one (so my-web-app stays
      whole); else the last dash-separated segment of the folder name. A cwd, or
      a folder, that IS a home directory is '~', never the user's name.
    #>
    param([string]$Cwd, [string]$FolderName)
    $homeRx = '^(?:/Users/[^/]+|/home/[^/]+|/root|[A-Za-z]:[\\/]+Users[\\/]+[^\\/]+)[\\/]*$'
    if ($Cwd -and $Cwd.Trim()) {
        $c = $Cwd.Trim()
        $userHome = [System.Environment]::GetFolderPath('UserProfile')
        if ($c -match $homeRx -or ($userHome -and $c.TrimEnd('\', '/') -eq $userHome.TrimEnd('\', '/'))) { return '~' }
        $leaf = ($c.TrimEnd('\', '/') -split '[\\/]')[-1]
        if ($leaf -and $leaf -notmatch '^[A-Za-z]:$') { return $leaf }
    }
    $segments = @(([string]$FolderName).Split('-') | Where-Object { $_ })
    if ($segments.Count -eq 0) { return '~' }
    # -Users-alex, -home-alex, C--Users-alex: the home folder itself.
    $rest = $segments
    if ($segments[0] -match '^[A-Za-z]$') { $rest = @($segments | Select-Object -Skip 1) }
    if ($rest.Count -le 2 -and $rest.Count -ge 1 -and @('Users', 'home') -contains $rest[0]) { return '~' }
    return $segments[-1]
}

function ConvertTo-P20UtcInstant {
    <#
      A line's timestamp as a UTC DateTimeOffset, or $null. ConvertFrom-Json on
      PowerShell 7 may hand an ISO string back as a DateTime already; 5.1 and
      -DateKind String hand back the string.
    #>
    param($Value)
    if ($null -eq $Value) { return $null }
    if ($Value -is [DateTime]) {
        $dt = [DateTime]$Value
        if ($dt.Kind -eq [DateTimeKind]::Unspecified) { $dt = [DateTime]::SpecifyKind($dt, [DateTimeKind]::Utc) }
        return ([DateTimeOffset]$dt.ToUniversalTime())
    }
    if ($Value -is [DateTimeOffset]) { return ([DateTimeOffset]$Value).ToUniversalTime() }
    $parsed = [DateTimeOffset]::MinValue
    $ok = [DateTimeOffset]::TryParse([string]$Value, [System.Globalization.CultureInfo]::InvariantCulture,
        [System.Globalization.DateTimeStyles]::AssumeUniversal, [ref]$parsed)
    if (-not $ok) { return $null }
    return $parsed.ToUniversalTime()
}

function Get-P20ClaudeSessionFiles {
    <#
      The .jsonl files a day can be in: every session file and every subagent
      transcript under the projects folder whose last write is on or after the
      day's start (a cheap filter -- a file untouched since before the day
      cannot hold a line from it). Sorted, so a run reads them in one order.
    #>
    param([string]$ProjectsRoot, [DateTime]$SinceUtc)
    $files = @()
    foreach ($project in @(Get-ChildItem -LiteralPath $ProjectsRoot -Directory -ErrorAction SilentlyContinue)) {
        foreach ($f in @(Get-ChildItem -LiteralPath $project.FullName -Filter '*.jsonl' -File -ErrorAction SilentlyContinue)) {
            if ($f.LastWriteTimeUtc -ge $SinceUtc) { $files += [pscustomobject]@{ Path = $f.FullName; Project = $project.Name; Session = $f.BaseName } }
        }
        foreach ($sessionDir in @(Get-ChildItem -LiteralPath $project.FullName -Directory -ErrorAction SilentlyContinue)) {
            $sub = Join-Path $sessionDir.FullName 'subagents'
            if (-not (Test-Path -LiteralPath $sub -PathType Container)) { continue }
            foreach ($f in @(Get-ChildItem -LiteralPath $sub -Filter '*.jsonl' -File -ErrorAction SilentlyContinue)) {
                if ($f.LastWriteTimeUtc -ge $SinceUtc) { $files += [pscustomobject]@{ Path = $f.FullName; Project = $project.Name; Session = $sessionDir.Name } }
            }
        }
    }
    return @($files | Sort-Object Path)
}

function New-P20UsageBucket {
    return @{ input = [long]0; output = [long]0; thinking = [long]0; cacheWrite5m = [long]0; cacheWrite1h = [long]0; cacheRead = [long]0; messages = [long]0 }
}

function Add-P20UsageToBucket {
    param($Bucket, $Message)
    foreach ($k in @('input', 'output', 'thinking', 'cacheWrite5m', 'cacheWrite1h', 'cacheRead')) { $Bucket[$k] += [long]$Message[$k] }
    $Bucket.messages += 1
}

function Get-P20BucketCost {
    <#
      The derived cost of a bucket of ONE model's tokens, in USD, unrounded
      [decimal]; $null when the model has no price row. Thinking is inside
      output already, so it is not priced twice.
    #>
    param($Bucket, $Price, $Table)
    if ($null -eq $Price) { return $null }
    $m = [decimal]1000000
    $in = [decimal]$Price.input
    $cost = ([decimal]$Bucket.input * $in) +
        ([decimal]$Bucket.output * [decimal]$Price.output) +
        ([decimal]$Bucket.cacheRead * [decimal]$Price.cacheRead) +
        ([decimal]$Bucket.cacheWrite5m * $in * [decimal]$Table.cacheWrite5mMultiplier) +
        ([decimal]$Bucket.cacheWrite1h * $in * [decimal]$Table.cacheWrite1hMultiplier)
    return ($cost / $m)
}

function ConvertTo-P20UsdValue {
    # Six places, no trailing zeros: the same text on every host.
    param($Value)
    if ($null -eq $Value) { return $null }
    $inv = [System.Globalization.CultureInfo]::InvariantCulture
    $r = [decimal]::Round([decimal]$Value, 6)
    return [decimal]::Parse($r.ToString('0.######', $inv), $inv)
}

function ConvertTo-P20UsageFields {
    param($Bucket, $Cost)
    return [ordered]@{
        input          = [long]$Bucket.input
        output         = [long]$Bucket.output
        thinking       = [long]$Bucket.thinking
        cacheWrite5m   = [long]$Bucket.cacheWrite5m
        cacheWrite1h   = [long]$Bucket.cacheWrite1h
        cacheRead      = [long]$Bucket.cacheRead
        messages       = [long]$Bucket.messages
        costUsdDerived = (ConvertTo-P20UsdValue $Cost)
    }
}

function Read-P20ClaudeMessages {
    <#
      Every API response in the session files a window can be in, counted once:
      @{ Messages = @(<one hashtable per response>); Files; Skipped }. A response
      is its message.id (requestId as fallback); each number is the largest any
      of its lines carries; 'at' is its EARLIEST line, as a UTC DateTimeOffset.
      -SinceUtc is the window's start: a file last written before it is not
      opened. The caller filters the responses by 'at'.
    #>
    param(
        [Parameter(Mandatory = $true)][string]$ProjectsRoot,
        [Parameter(Mandatory = $true)][DateTime]$SinceUtc
    )
    $jsonArgs = @{}
    if ((Get-Command ConvertFrom-Json).Parameters.ContainsKey('DateKind')) { $jsonArgs['DateKind'] = 'String' }

    $messages = @{}
    $skipped = 0
    $files = @(Get-P20ClaudeSessionFiles -ProjectsRoot $ProjectsRoot -SinceUtc $SinceUtc)
    foreach ($file in $files) {
        $stream = $null
        $reader = $null
        try {
            $share = [System.IO.FileShare]::ReadWrite -bor [System.IO.FileShare]::Delete
            $stream = New-Object System.IO.FileStream($file.Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, $share)
            $reader = New-Object System.IO.StreamReader($stream, (New-Object System.Text.UTF8Encoding($false)))
            $lineNo = 0
            while ($null -ne ($line = $reader.ReadLine())) {
                $lineNo++
                # Cheap first: only an assistant line carries usage.
                if (-not $line.Contains('"assistant"') -or -not $line.Contains('"usage"')) { continue }
                $o = $null
                try { $o = $line | ConvertFrom-Json @jsonArgs -ErrorAction Stop }
                catch { $skipped++; continue }
                if ($null -eq $o -or [string]$o.type -ne 'assistant') { continue }
                $m = $o.message
                if ($null -eq $m -or $null -eq $m.usage) { continue }
                $model = [string]$m.model
                if (-not $model -or $model -eq '<synthetic>') { continue }
                $at = ConvertTo-P20UtcInstant $o.timestamp
                if ($null -eq $at) { $skipped++; continue }

                $key = [string]$m.id
                if (-not $key) { $key = [string]$o.requestId }
                if (-not $key) { $key = "$($file.Path)#$lineNo" }
                $session = [string]$o.sessionId
                if (-not $session) { $session = $file.Session }

                $u = $m.usage
                $w5 = [long]0; $w1 = [long]0
                if ($null -ne $u.cache_creation) {
                    $w5 = [long]$u.cache_creation.ephemeral_5m_input_tokens
                    $w1 = [long]$u.cache_creation.ephemeral_1h_input_tokens
                }
                else { $w5 = [long]$u.cache_creation_input_tokens }
                $thinking = [long]0
                if ($null -ne $u.output_tokens_details) { $thinking = [long]$u.output_tokens_details.thinking_tokens }
                $line_ = @{
                    input = [long]$u.input_tokens; output = [long]$u.output_tokens; thinking = $thinking
                    cacheWrite5m = $w5; cacheWrite1h = $w1; cacheRead = [long]$u.cache_read_input_tokens
                }

                if (-not $messages.ContainsKey($key)) {
                    $line_['at'] = $at; $line_['model'] = $model; $line_['session'] = $session
                    $line_['cwd'] = [string]$o.cwd; $line_['folder'] = $file.Project
                    $messages[$key] = $line_
                    continue
                }
                $seen = $messages[$key]
                foreach ($k in @('input', 'output', 'thinking', 'cacheWrite5m', 'cacheWrite1h', 'cacheRead')) {
                    if ($line_[$k] -gt $seen[$k]) { $seen[$k] = $line_[$k] }
                }
                if ($at -lt $seen.at) {
                    $seen.at = $at; $seen.session = $session; $seen.folder = $file.Project
                    if ($o.cwd) { $seen.cwd = [string]$o.cwd }
                }
                elseif (-not $seen.cwd -and $o.cwd) { $seen.cwd = [string]$o.cwd }
            }
        }
        catch { $skipped++ }
        finally {
            if ($reader) { $reader.Dispose() }
            elseif ($stream) { $stream.Dispose() }
        }
    }
    return @{ Messages = @($messages.Values); Files = $files.Count; Skipped = $skipped }
}

function Read-P20ClaudeUsageDay {
    <#
      One local day's usage on this machine, as the record docs/hub/usage.md
      describes (an [ordered] tree; the caller serialises it). -Day is the
      local calendar day. Returns @{ Record; Files; Skipped }: the record, how
      many files were read, and how many lines could not be read as JSON.
    #>
    param(
        [Parameter(Mandatory = $true)][string]$ProjectsRoot,
        [Parameter(Mandatory = $true)][DateTime]$Day,
        [Parameter(Mandatory = $true)]$PriceTable,
        [string]$Machine = ''
    )
    $dayStart = [DateTime]::SpecifyKind($Day.Date, [DateTimeKind]::Local)
    $dayKey = $dayStart.ToString('yyyy-MM-dd', [System.Globalization.CultureInfo]::InvariantCulture)
    $read = Read-P20ClaudeMessages -ProjectsRoot $ProjectsRoot -SinceUtc $dayStart.ToUniversalTime()
    $skipped = $read.Skipped

    # The day's messages: by the local day of each message's earliest line.
    $inv = [System.Globalization.CultureInfo]::InvariantCulture
    $dayMessages = @($read.Messages | Where-Object { $_.at.ToLocalTime().ToString('yyyy-MM-dd', $inv) -eq $dayKey } |
            Sort-Object @{ Expression = { $_.at.UtcTicks } }, @{ Expression = { $_.session } }, @{ Expression = { $_.model } })

    $total = New-P20UsageBucket
    $byModel = @{}
    $bySession = @{}
    foreach ($msg in $dayMessages) {
        Add-P20UsageToBucket $total $msg
        if (-not $byModel.ContainsKey($msg.model)) { $byModel[$msg.model] = New-P20UsageBucket }
        Add-P20UsageToBucket $byModel[$msg.model] $msg
        if (-not $bySession.ContainsKey($msg.session)) {
            # The project is named from the session's earliest line of the day.
            $bySession[$msg.session] = @{
                Bucket = (New-P20UsageBucket); Models = @{}
                Project = (ConvertTo-P20UsageProjectName -Cwd $msg.cwd -FolderName $msg.folder)
                First = $msg.at; Last = $msg.at
            }
        }
        $s = $bySession[$msg.session]
        Add-P20UsageToBucket $s.Bucket $msg
        if (-not $s.Models.ContainsKey($msg.model)) { $s.Models[$msg.model] = New-P20UsageBucket }
        Add-P20UsageToBucket $s.Models[$msg.model] $msg
        if ($msg.at -gt $s.Last) { $s.Last = $msg.at }
        if ($msg.at -lt $s.First) { $s.First = $msg.at }
    }

    $unpriced = @()
    $modelRows = @()
    $totalCost = [decimal]0
    foreach ($model in @($byModel.Keys | Sort-Object { $_ } -CaseSensitive)) {
        $price = Find-P20ClaudePrice -Table $PriceTable -Model $model
        if ($null -eq $price) { $unpriced += $model }
        $cost = Get-P20BucketCost -Bucket $byModel[$model] -Price $price -Table $PriceTable
        if ($null -ne $cost) { $totalCost += $cost }
        $row = [ordered]@{ model = $model }
        foreach ($e in (ConvertTo-P20UsageFields $byModel[$model] $cost).GetEnumerator()) { $row[$e.Key] = $e.Value }
        $modelRows += $row
    }

    # A day with messages and not one priced model has no cost to state.
    if ($byModel.Count -gt 0 -and $unpriced.Count -eq $byModel.Count) { $totalCost = $null }

    $stamp = 'yyyy-MM-ddTHH:mm:ss.fffZ'
    $sessionRows = @()
    $sessionOrder = @($bySession.Keys | Sort-Object @{ Expression = { $bySession[$_].First.UtcTicks } }, @{ Expression = { $_ } })
    foreach ($id in $sessionOrder) {
        $s = $bySession[$id]
        # The priced models' cost; $null when none of the session's models is priced.
        $cost = $null
        foreach ($model in @($s.Models.Keys)) {
            $c = Get-P20BucketCost -Bucket $s.Models[$model] -Price (Find-P20ClaudePrice -Table $PriceTable -Model $model) -Table $PriceTable
            if ($null -ne $c) {
                if ($null -eq $cost) { $cost = [decimal]0 }
                $cost += $c
            }
        }
        $row = [ordered]@{
            session = $id
            project = $s.Project
            models  = @($s.Models.Keys | Sort-Object { $_ } -CaseSensitive)
        }
        foreach ($e in (ConvertTo-P20UsageFields $s.Bucket $cost).GetEnumerator()) { $row[$e.Key] = $e.Value }
        $row['firstAt'] = $s.First.UtcDateTime.ToString($stamp, $inv)
        $row['lastAt'] = $s.Last.UtcDateTime.ToString($stamp, $inv)
        $sessionRows += $row
    }

    $tz = [TimeZoneInfo]::Local
    $offset = $tz.GetUtcOffset($dayStart)
    $sign = '+'
    if ($offset -lt [TimeSpan]::Zero) { $sign = '-' }
    $offsetText = $sign + [Math]::Abs($offset.Hours).ToString('00') + ':' + [Math]::Abs($offset.Minutes).ToString('00')

    $record = [ordered]@{
        usage     = 1
        date      = $dayKey
        machine   = $Machine
        timezone  = [string]$tz.Id
        utcOffset = $offsetText
        source    = 'claude-code-session-files'
        totals    = (ConvertTo-P20UsageFields $total $totalCost)
        byModel   = $modelRows
        bySession = $sessionRows
        unpriced  = $unpriced
        cost      = [ordered]@{
            derived        = $true
            currency       = [string]$PriceTable.currency
            priceTableAsOf = [string]$PriceTable.asOf
            note           = [string]$PriceTable.note
            priceNotes     = @(Get-P20PriceNotes -Table $PriceTable -Models @($byModel.Keys))
        }
    }
    return @{ Record = $record; Files = $read.Files; Skipped = $skipped }
}

function Get-P20UsageMachineName {
    # The machine as the usage log names it, short (before any dot) and safe in
    # a file name.
    $name = ([string][System.Environment]::MachineName).Split('.')[0]
    $name = $name -replace '[^A-Za-z0-9_-]', '-'
    if (-not $name) { $name = 'machine' }
    return $name
}

# -- The current burn: today and this week (Burn with no switch) ----------------
#
# THE WEEK starts Friday 05:00 local, when the plan's allocation resets
# (docs/hub/usage.md, "Today and this week"). Two readings meet in it:
#
#   - THIS machine is read from its session files, by each response's own time,
#     so its lines split at Friday 05:00 exactly.
#   - ANOTHER machine is read from the day records it logged into the hub's
#     usage/, and a day record cannot be split: it counts toward the week it
#     STARTS in. A record starts at 00:00 on its date, so one dated Friday counts
#     toward the week that ENDS that Friday at 05:00, not the one that begins
#     then. Its date is read on this machine's calendar.
#
# This machine's own records in usage/ are never read here: its session files
# are, and reading both would count it twice.

function Get-P20BurnWindows {
    <#
      The two windows at -Now (a local time): Today from local midnight, This
      week from the latest Friday 05:00 at or before -Now. NextBoundary is the
      sooner of the next midnight and the next week start -- the instant the
      answer stops being right, which the agent's cache honours.
    #>
    param([Parameter(Mandatory = $true)][DateTime]$Now)
    # The allocation resets Friday 05:00 local. Here and nowhere else.
    $weekDay = [DayOfWeek]::Friday
    $weekHour = 5
    $local = $Now
    if ($local.Kind -eq [DateTimeKind]::Utc) { $local = $local.ToLocalTime() }
    $local = [DateTime]::SpecifyKind($local, [DateTimeKind]::Local)
    $todayStart = $local.Date
    $back = ((([int]$todayStart.DayOfWeek) - [int]$weekDay) + 7) % 7
    $weekStart = $todayStart.AddDays(-$back).AddHours($weekHour)
    if ($weekStart -gt $local) { $weekStart = $weekStart.AddDays(-7) }
    $nextMidnight = $todayStart.AddDays(1)
    $nextWeek = $weekStart.AddDays(7)
    $next = $nextMidnight
    if ($nextWeek -lt $next) { $next = $nextWeek }
    $inv = [System.Globalization.CultureInfo]::InvariantCulture
    return @{
        Now          = $local
        TodayStart   = $todayStart
        TodayKey     = $todayStart.ToString('yyyy-MM-dd', $inv)
        WeekStart    = $weekStart
        WeekEnd      = $nextWeek
        NextBoundary = $next
    }
}

function Test-P20RecordInWeek {
    <#
      Whether a day record dated -DayKey (yyyy-mm-dd) counts toward the week
      starting -WeekStart: the week it STARTS in, a record starting at 00:00 on
      its date. A record dated the Friday a week starts on starts five hours
      before it, so it is the week before's.
    #>
    param([Parameter(Mandatory = $true)][string]$DayKey, [Parameter(Mandatory = $true)][DateTime]$WeekStart)
    $parsed = [DateTime]::MinValue
    if (-not [DateTime]::TryParseExact($DayKey, 'yyyy-MM-dd', [System.Globalization.CultureInfo]::InvariantCulture,
            [System.Globalization.DateTimeStyles]::None, [ref]$parsed)) { return $false }
    $starts = [DateTime]::SpecifyKind($parsed.Date, [DateTimeKind]::Local)
    return ($starts -ge $WeekStart -and $starts -lt $WeekStart.AddDays(7))
}

function Read-P20OtherMachineRecords {
    <#
      The day records in the hub's usage/ folder that ANOTHER machine logged:
      @{ Records = @(@{ Machine; Date; ByModel }); Skipped }. A file that is not
      a record (unreadable, or no date) is skipped and counted; this machine's
      own records are left out.
    #>
    param([string]$UsageDir, [Parameter(Mandatory = $true)][string]$Machine)
    $records = @()
    $skipped = 0
    # A bare yyyy-mm-dd must stay a string: PowerShell 7 would read it as a date.
    $jsonArgs = @{}
    if ((Get-Command ConvertFrom-Json).Parameters.ContainsKey('DateKind')) { $jsonArgs['DateKind'] = 'String' }
    if (-not $UsageDir -or -not (Test-Path -LiteralPath $UsageDir -PathType Container)) { return @{ Records = @(); Skipped = 0 } }
    foreach ($f in @(Get-ChildItem -LiteralPath $UsageDir -Filter '*.json' -File -ErrorAction SilentlyContinue | Sort-Object Name)) {
        $r = $null
        try { $r = [System.IO.File]::ReadAllText($f.FullName) | ConvertFrom-Json @jsonArgs -ErrorAction Stop }
        catch { $skipped++; continue }
        if ($null -eq $r -or -not $r.PSObject.Properties['date']) { $skipped++; continue }
        $date = $r.date
        if ($date -is [DateTime]) { $date = ([DateTime]$date).ToString('yyyy-MM-dd', [System.Globalization.CultureInfo]::InvariantCulture) }
        $date = [string]$date
        if ($date -notmatch '^\d{4}-\d{2}-\d{2}$') { $skipped++; continue }
        $who = [string]$r.machine
        if (-not $who) { $who = $f.BaseName.Substring([Math]::Min(11, $f.BaseName.Length)) }
        if ($who -ieq $Machine) { continue }
        $records += @{ Machine = $who; Date = $date; ByModel = @($r.byModel) }
    }
    return @{ Records = $records; Skipped = $skipped }
}

function ConvertTo-P20BurnWindow {
    <#
      One window's block: its totals, its models, the unpriced ones, and which
      machine said what. -Mine is this machine's responses in the window;
      -Others the other machines' records that count toward it.
    #>
    param($Mine, $Others, [string]$Machine, [bool]$HasSessionFiles, $PriceTable, [DateTime]$From, [DateTime]$To)
    $inv = [System.Globalization.CultureInfo]::InvariantCulture
    $stamp = 'yyyy-MM-ddTHH:mm:ss.fffZ'
    $byModel = @{}
    # machine -> @{ Source; Days; Models = @{ model -> bucket } }
    $machines = [ordered]@{}
    if ($HasSessionFiles) { $machines[$Machine] = @{ Source = 'session-files'; Days = @(); Models = @{} } }
    foreach ($msg in @($Mine)) {
        if (-not $byModel.ContainsKey($msg.model)) { $byModel[$msg.model] = New-P20UsageBucket }
        Add-P20UsageToBucket $byModel[$msg.model] $msg
        $mm = $machines[$Machine].Models
        if (-not $mm.ContainsKey($msg.model)) { $mm[$msg.model] = New-P20UsageBucket }
        Add-P20UsageToBucket $mm[$msg.model] $msg
    }
    foreach ($rec in @($Others | Sort-Object @{ Expression = { $_.Machine } }, @{ Expression = { $_.Date } })) {
        if (-not $machines.Contains($rec.Machine)) { $machines[$rec.Machine] = @{ Source = 'usage-records'; Days = @(); Models = @{} } }
        $entry = $machines[$rec.Machine]
        $entry.Days += $rec.Date
        foreach ($row in @($rec.ByModel)) {
            if ($null -eq $row -or -not [string]$row.model) { continue }
            $model = [string]$row.model
            foreach ($target in @($byModel, $entry.Models)) {
                if (-not $target.ContainsKey($model)) { $target[$model] = New-P20UsageBucket }
                $b = $target[$model]
                foreach ($k in @('input', 'output', 'thinking', 'cacheWrite5m', 'cacheWrite1h', 'cacheRead', 'messages')) {
                    if ($row.PSObject.Properties[$k]) { $b[$k] += [long]$row.$k }
                }
            }
        }
    }

    $total = New-P20UsageBucket
    $totalCost = [decimal]0
    $unpriced = @()
    $modelRows = @()
    foreach ($model in @($byModel.Keys | Sort-Object { $_ } -CaseSensitive)) {
        $b = $byModel[$model]
        foreach ($k in @('input', 'output', 'thinking', 'cacheWrite5m', 'cacheWrite1h', 'cacheRead', 'messages')) { $total[$k] += $b[$k] }
        $price = Find-P20ClaudePrice -Table $PriceTable -Model $model
        if ($null -eq $price) { $unpriced += $model }
        $cost = Get-P20BucketCost -Bucket $b -Price $price -Table $PriceTable
        if ($null -ne $cost) { $totalCost += $cost }
        $row = [ordered]@{ model = $model }
        foreach ($e in (ConvertTo-P20UsageFields $b $cost).GetEnumerator()) { $row[$e.Key] = $e.Value }
        $modelRows += $row
    }
    if ($byModel.Count -gt 0 -and $unpriced.Count -eq $byModel.Count) { $totalCost = $null }

    $machineRows = @()
    foreach ($name in @($machines.Keys)) {
        $entry = $machines[$name]
        $m = New-P20UsageBucket
        $cost = $null
        foreach ($model in @($entry.Models.Keys)) {
            $b = $entry.Models[$model]
            foreach ($k in @('input', 'output', 'thinking', 'cacheWrite5m', 'cacheWrite1h', 'cacheRead', 'messages')) { $m[$k] += $b[$k] }
            $c = Get-P20BucketCost -Bucket $b -Price (Find-P20ClaudePrice -Table $PriceTable -Model $model) -Table $PriceTable
            if ($null -ne $c) {
                if ($null -eq $cost) { $cost = [decimal]0 }
                $cost += $c
            }
        }
        $machineRows += [ordered]@{
            machine        = [string]$name
            source         = $entry.Source
            days           = @($entry.Days | Sort-Object)
            messages       = [long]$m.messages
            costUsdDerived = (ConvertTo-P20UsdValue $cost)
        }
    }

    return [ordered]@{
        from     = $From.ToUniversalTime().ToString($stamp, $inv)
        to       = $To.ToUniversalTime().ToString($stamp, $inv)
        totals   = (ConvertTo-P20UsageFields $total $totalCost)
        byModel  = $modelRows
        unpriced = $unpriced
        machines = $machineRows
    }
}

function Read-P20BurnSummary {
    <#
      The current burn at -Now: Today and This week, this machine's session
      files plus the other machines' day records in -UsageDir (docs/hub/usage.md,
      "Today and this week"). -ProjectsRoot may not exist: this machine then
      adds nothing and the answer says so. Returns @{ Summary; Files; Skipped }.
    #>
    param(
        [string]$ProjectsRoot,
        [string]$UsageDir,
        [Parameter(Mandatory = $true)][DateTime]$Now,
        [Parameter(Mandatory = $true)]$PriceTable,
        [Parameter(Mandatory = $true)][string]$Machine
    )
    $inv = [System.Globalization.CultureInfo]::InvariantCulture
    $stamp = 'yyyy-MM-ddTHH:mm:ss.fffZ'
    $w = Get-P20BurnWindows -Now $Now
    $hasFiles = [bool]($ProjectsRoot -and (Test-Path -LiteralPath $ProjectsRoot -PathType Container))
    $since = $w.TodayStart
    if ($w.WeekStart -lt $since) { $since = $w.WeekStart }
    $mine = @()
    $files = 0
    $skippedLines = 0
    if ($hasFiles) {
        $read = Read-P20ClaudeMessages -ProjectsRoot $ProjectsRoot -SinceUtc $since.ToUniversalTime()
        $mine = @($read.Messages)
        $files = $read.Files
        $skippedLines = $read.Skipped
    }
    $nowUtc = ([DateTimeOffset]$w.Now).ToUniversalTime()
    $todayUtc = ([DateTimeOffset]$w.TodayStart).ToUniversalTime()
    $weekUtc = ([DateTimeOffset]$w.WeekStart).ToUniversalTime()
    $mineToday = @($mine | Where-Object { $_.at -ge $todayUtc -and $_.at -le $nowUtc })
    $mineWeek = @($mine | Where-Object { $_.at -ge $weekUtc -and $_.at -le $nowUtc })

    $others = Read-P20OtherMachineRecords -UsageDir $UsageDir -Machine $Machine
    $othersToday = @($others.Records | Where-Object { $_.Date -eq $w.TodayKey })
    $othersWeek = @($others.Records | Where-Object { Test-P20RecordInWeek -DayKey $_.Date -WeekStart $w.WeekStart })

    $today = ConvertTo-P20BurnWindow -Mine $mineToday -Others $othersToday -Machine $Machine -HasSessionFiles $hasFiles `
        -PriceTable $PriceTable -From $w.TodayStart -To $w.Now
    $week = ConvertTo-P20BurnWindow -Mine $mineWeek -Others $othersWeek -Machine $Machine -HasSessionFiles $hasFiles `
        -PriceTable $PriceTable -From $w.WeekStart -To $w.Now
    $models = @(@($today.byModel) + @($week.byModel) | ForEach-Object { $_.model })

    $tz = [TimeZoneInfo]::Local
    $offset = $tz.GetUtcOffset($w.Now)
    $sign = '+'
    if ($offset -lt [TimeSpan]::Zero) { $sign = '-' }
    $summary = [ordered]@{
        burn           = 1
        machine        = $Machine
        timezone       = [string]$tz.Id
        utcOffset      = ($sign + [Math]::Abs($offset.Hours).ToString('00') + ':' + [Math]::Abs($offset.Minutes).ToString('00'))
        asOf           = $w.Now.ToUniversalTime().ToString($stamp, $inv)
        nextBoundaryAt = $w.NextBoundary.ToUniversalTime().ToString($stamp, $inv)
        weekStarts     = 'Friday 05:00 local'
        sessionFiles   = $hasFiles
        hub            = [bool]($UsageDir -and (Test-Path -LiteralPath $UsageDir -PathType Container))
        today          = $today
        week           = $week
        cost           = [ordered]@{
            derived        = $true
            currency       = [string]$PriceTable.currency
            priceTableAsOf = [string]$PriceTable.asOf
            note           = [string]$PriceTable.note
            priceNotes     = @(Get-P20PriceNotes -Table $PriceTable -Models $models)
        }
        skipped        = [ordered]@{ lines = [long]$skippedLines; records = [long]$others.Skipped }
    }
    return @{ Summary = $summary; Files = $files; Skipped = $skippedLines }
}
