<#
.SYNOPSIS
    The standup's reminder to attend (Team Agile V1, D-TA15). Dot-source it.

.DESCRIPTION
    Not a command. Get-Standup.ps1 dot-sources it for two things:

      Invoke-P20StandupRemind   Standup -Remind <HH:mm> [-Days ...]: ONE Organize
                                reminder with source `standup`, due the first day
                                in the cadence whose time is still ahead. An open
                                one already there has its due and ref REWRITTEN
                                (Reminders <id> -Due -Ref) rather than a second added.
      Invoke-P20StandupAttend   attending: the open standup reminder is archived
                                (Reminders <id> -Archive) and the next written
                                (NewReminder), due the next day in the cadence after
                                today -- once a day, because a reminder already due
                                after today means today's was attended.

    A reminder has ONE writer: Organize's verbs. Nothing here writes a file; it
    reads reminders/current/ and calls New-P20Reminder and Get-P20Reminders, the
    functions the organize module defines when features.organize is on. Organize
    grows no recurrence: the cadence -- `HH:mm <days>` -- is the reminder's own
    **Ref:** line, and the ritual re-arms its own reminder each time it is attended.

    The rule (the Get-P20Standup*Days/Time/Due functions and the attend plan) is
    implemented twice, here and in agent/solitaire/remind.py, and held to one
    table: Tests/fixtures/rituals/remind.json.

    Times are LOCAL with no offset, as every reminder's are.

.NOTES
    PowerShell 5.1 compatible (ASCII dashes only).
#>

if (-not (Get-Command Get-P20Consts -ErrorAction SilentlyContinue)) {
    . (Join-Path $PSScriptRoot 'Get-Consts.ps1')
}
. (Join-Path $PSScriptRoot 'Resolve-HubConfig.ps1')
. (Join-Path $PSScriptRoot 'Resolve-CardName.ps1')
. (Join-Path $PSScriptRoot 'Reminder-Rules.ps1')

# -- The rule (pure) -------------------------------------------------------------

function Get-P20StandupDayIndex {
    # 'Mon' / 'monday' (any case) -> 0; Sunday -> 6; not a day -> -1.
    param([string]$Token)
    $t = $Token.Trim().ToLowerInvariant()
    $names = @((Get-P20Consts).rituals.weekdays)
    $full = [System.Globalization.CultureInfo]::InvariantCulture.DateTimeFormat.DayNames   # Sunday first
    for ($i = 0; $i -lt $names.Count; $i++) {
        if ($t -eq ([string]$names[$i]).ToLowerInvariant()) { return $i }
        if ($t -eq ([string]$full[($i + 1) % 7]).ToLowerInvariant()) { return $i }
    }
    return -1
}

function ConvertTo-P20StandupDays {
    <#
        'Mon-Fri', 'mon,wed,fri', 'Monday,Tue-Thu' -> the day indexes, Monday = 0,
        sorted; $null when any part is not a day or a range runs backwards.
    #>
    param([AllowNull()][AllowEmptyString()][string]$Text)
    if (-not $Text -or -not $Text.Trim()) { return $null }
    $on = New-Object bool[] 7
    foreach ($token in $Text.Split(',')) {
        if (-not $token.Trim()) { return $null }
        $ends = $token.Split('-')
        if ($ends.Count -gt 2) { return $null }
        $idx = @()
        foreach ($e in $ends) {
            $i = Get-P20StandupDayIndex -Token $e
            if ($i -lt 0) { return $null }
            $idx += $i
        }
        if ($idx.Count -eq 1) { $on[$idx[0]] = $true }
        else {
            if ($idx[0] -gt $idx[1]) { return $null }
            for ($k = $idx[0]; $k -le $idx[1]; $k++) { $on[$k] = $true }
        }
    }
    $out = @()
    for ($k = 0; $k -lt 7; $k++) { if ($on[$k]) { $out += $k } }
    return , ([int[]]$out)
}

function Format-P20StandupDays {
    # A run of three or more days is a range (Mon-Fri); anything else a list.
    param([int[]]$Days)
    $names = @((Get-P20Consts).rituals.weekdays)
    $d = @($Days | Sort-Object -Unique)
    if ($d.Count -ge 3 -and (($d[$d.Count - 1] - $d[0] + 1) -eq $d.Count)) {
        return "$($names[$d[0]])-$($names[$d[$d.Count - 1]])"
    }
    return (@($d | ForEach-Object { [string]$names[$_] }) -join ',')
}

function ConvertTo-P20StandupTime {
    # '9:00' / '09:00' -> '09:00'; anything else $null.
    param([AllowNull()][AllowEmptyString()][string]$Text)
    if (-not $Text) { return $null }
    $m = [regex]::Match($Text.Trim(), '^(\d{1,2}):(\d{2})$')
    if (-not $m.Success) { return $null }
    $h = [int]$m.Groups[1].Value
    $mi = [int]$m.Groups[2].Value
    if ($h -gt 23 -or $mi -gt 59) { return $null }
    return ('{0:D2}:{1:D2}' -f $h, $mi)
}

function ConvertFrom-P20StandupCadence {
    # A Ref line's 'HH:mm <days>' -> @{ Time; Days }, or $null if it is not one.
    param([AllowNull()][AllowEmptyString()][string]$Ref)
    if (-not $Ref) { return $null }
    $m = [regex]::Match($Ref.Trim(), '^(\S+)\s+(\S+)$')
    if (-not $m.Success) { return $null }
    $time = ConvertTo-P20StandupTime -Text $m.Groups[1].Value
    $days = ConvertTo-P20StandupDays -Text $m.Groups[2].Value
    if ($null -eq $time -or $null -eq $days) { return $null }
    return @{ Time = $time; Days = $days }
}

function Get-P20StandupDayAt {
    # $Day's date at 'HH:mm'.
    param([datetime]$Day, [string]$Time)
    $hm = $Time.Split(':')
    return $Day.Date.AddHours([int]$hm[0]).AddMinutes([int]$hm[1])
}

function Get-P20StandupFirstDue {
    # The first day in the cadence whose time is still AHEAD of -Now, today included.
    param([datetime]$Now, [string]$Time, [int[]]$Days)
    for ($k = 0; $k -le 7; $k++) {
        $day = $Now.Date.AddDays($k)
        if ($Days -notcontains (([int]$day.DayOfWeek + 6) % 7)) { continue }
        $at = Get-P20StandupDayAt -Day $day -Time $Time
        if ($k -eq 0 -and $at -le $Now) { continue }
        return $at.ToString('yyyy-MM-ddTHH:mm', [System.Globalization.CultureInfo]::InvariantCulture)
    }
    return $null
}

function Get-P20StandupNextDue {
    # The next day in the cadence AFTER -Now's day, at the cadence's time.
    param([datetime]$Now, [string]$Time, [int[]]$Days)
    for ($k = 1; $k -le 7; $k++) {
        $day = $Now.Date.AddDays($k)
        if ($Days -notcontains (([int]$day.DayOfWeek + 6) % 7)) { continue }
        return (Get-P20StandupDayAt -Day $day -Time $Time).ToString('yyyy-MM-ddTHH:mm', [System.Globalization.CultureInfo]::InvariantCulture)
    }
    return $null
}

function Get-P20StandupAttendPlan {
    <#
        What attending does to the open standup reminders (each @{ Id; Due; Ref }):
          absent      there is none
          none        one is due AFTER today -- today's was attended already
          unreadable  no Ref is a cadence: left alone
          rearm       archive every one, write ONE next (Next, Ref)
    #>
    param([object[]]$Open, [datetime]$Now)
    $plan = @{ Action = 'absent'; Archive = @(); Next = ''; Ref = '' }
    $list = @($Open | Where-Object { $null -ne $_ })
    if ($list.Count -eq 0) { return $plan }
    foreach ($r in $list) {
        $due = [string]$r.Due
        if ($due.Length -ge 10) {
            $day = [datetime]::MinValue
            if ([datetime]::TryParseExact($due.Substring(0, 10), 'yyyy-MM-dd', [System.Globalization.CultureInfo]::InvariantCulture,
                    [System.Globalization.DateTimeStyles]::None, [ref]$day) -and $day.Date -gt $Now.Date) {
                $plan.Action = 'none'
                return $plan
            }
        }
    }
    $cadence = $null
    foreach ($r in $list) {
        $cadence = ConvertFrom-P20StandupCadence -Ref ([string]$r.Ref)
        if ($cadence) { break }
    }
    if (-not $cadence) {
        $plan.Action = 'unreadable'
        return $plan
    }
    $plan.Action = 'rearm'
    $plan.Archive = @($list | ForEach-Object { [string]$_.Id })
    $plan.Next = Get-P20StandupNextDue -Now $Now -Time $cadence.Time -Days $cadence.Days
    $plan.Ref = "$($cadence.Time) $(Format-P20StandupDays -Days $cadence.Days)"
    return $plan
}

# -- The hub (reads only) and Organize's verbs (the writes) ------------------------

function Test-P20StandupOrganizeOn {
    # features.organize, read through the module's one accessor. No accessor (a
    # script run bare, outside the module) reads as off.
    if (-not (Get-Command Get-P20Features -ErrorAction SilentlyContinue)) { return $false }
    $f = Get-P20Features
    return [bool]($f -and $f['organize'])
}

function Test-P20StandupOrganizeVerbs {
    # The two verbs the organize module defines when its flag is on.
    return [bool]((Get-Command New-P20Reminder -ErrorAction SilentlyContinue) -and
        (Get-Command Get-P20Reminders -ErrorAction SilentlyContinue))
}

function Get-P20StandupReminders {
    # The open reminders whose source is the standup's, soonest due first.
    param([string]$PackageRoot)
    $c = Get-P20Consts
    $promptsRoot = Get-P20PromptsRoot -PackageRoot $PackageRoot
    if (-not (Test-P20HubRoot $promptsRoot)) { return @() }
    $dir = Join-Path (Get-P20HubFolder -Name 'reminders' -PromptsRoot $promptsRoot -PackageRoot $PackageRoot) $c.folders.current
    if (-not (Test-Path -LiteralPath $dir)) { return @() }
    $source = [string]$c.rituals.remindSource
    $found = @(Get-ChildItem -LiteralPath $dir -Filter '*.md' -File | ForEach-Object { Read-P20Reminder -File $_ } |
            Where-Object { $_.Id -and $_.Source -eq $source })
    return @($found | Sort-Object @{ Expression = { if ($_.Due) { $_.Due } else { '9999' } } })
}

function Invoke-P20StandupVerb {
    <#
        Run one Organize verb by its function name. '' when it succeeded, else
        the sentence it stated (or the exit code). -Quiet swallows what it prints.
        Never throws: a non-interactive caller's stated refusal is re-raised by
        the guard, and caught here.
    #>
    param([string]$Name, [hashtable]$Parameters, [switch]$Quiet)
    $global:LASTEXITCODE = 0
    $global:P20StatedError = $null
    try {
        if ($Quiet) { & $Name @Parameters 6>$null | Out-Null }
        else { & $Name @Parameters | Out-Null }
    }
    catch {
        $why = [string]$_.Exception.Message
        if (-not $why) { $why = "$Name failed." }
        return $why
    }
    if ($LASTEXITCODE) {
        $why = [string]$global:P20StatedError
        if (-not $why) { $why = "$Name exited $LASTEXITCODE." }
        return $why
    }
    return ''
}

function Invoke-P20StandupRemind {
    <#
        Standup -Remind. Returns @{ Code; Message; Hint; Stated; Line }:
          Code 0  done -- Line is the one line to print
          Code 2  refused -- Message/Hint to state, or Stated = $true when the
                  Organize verb has already printed its own Error block
    #>
    param(
        [string]$Time,
        [string[]]$Days,
        [string]$PackageRoot,
        [string]$CliPrefix = '',
        [datetime]$Now = (Get-Date)
    )
    $c = Get-P20Consts
    $p = $CliPrefix
    if (-not (Test-P20StandupOrganizeOn)) {
        return @{ Code = 2; Message = 'The reminder to attend is an Organize reminder, and features.organize is off.'
            Hint = "${p}Config -Set features.organize=true turns Organize on (config.local.json, top level)." }
    }
    if (-not (Test-P20StandupOrganizeVerbs)) {
        return @{ Code = 2; Message = 'features.organize is on, but Organize''s verbs are not loaded in this shell.'
            Hint = 'Open a new shell, or Import-Module the toolkit again, so NewReminder and Reminders are defined.' }
    }
    $hhmm = ConvertTo-P20StandupTime -Text $Time
    if (-not $hhmm) {
        return @{ Code = 2; Message = "'$Time' is not a time of day."; Hint = '-Remind takes HH:mm on the 24-hour clock, like 09:00 or 17:30.' }
    }
    $dayText = [string]$c.rituals.remindDays
    if ($Days -and @($Days | Where-Object { $_ }).Count -gt 0) { $dayText = (@($Days) -join ',') }
    $dayIdx = ConvertTo-P20StandupDays -Text $dayText
    if ($null -eq $dayIdx) {
        return @{ Code = 2; Message = "'$dayText' is not a list of days."
            Hint = "-Days takes day names, comma-separated or as a range: $(@($c.rituals.weekdays) -join ','), or $([string]$c.rituals.remindDays)." }
    }
    $ref = "$hhmm $(Format-P20StandupDays -Days $dayIdx)"
    $due = Get-P20StandupFirstDue -Now $Now -Time $hhmm -Days $dayIdx

    $existing = @(Get-P20StandupReminders -PackageRoot $PackageRoot)
    if ($existing.Count -gt 0) {
        $why = Invoke-P20StandupVerb -Name 'Get-P20Reminders' -Parameters @{ Id = [string]$existing[0].Id; Due = $due; Ref = $ref }
    }
    else {
        $why = Invoke-P20StandupVerb -Name 'New-P20Reminder' -Parameters @{
            Title = [string]$c.rituals.remindTitle; Due = $due; Source = [string]$c.rituals.remindSource; Ref = $ref
        }
    }
    if ($why) { return @{ Code = 2; Message = $why; Stated = $true } }
    return @{ Code = 0; Line = "The standup reminds you at $ref; next due $due. Attending re-arms it." }
}

function Invoke-P20StandupAttend {
    <#
        Attending: the open standup reminder archived, the next written -- once a
        day. Returns '' when done or when there is nothing to do (Organize off,
        no standup reminder, today's already attended); else the one sentence why
        it was not re-armed. Never throws, never refuses.
    #>
    param([string]$PackageRoot, [datetime]$Now = (Get-Date))
    try {
        if (-not (Test-P20StandupOrganizeOn)) { return '' }
        $open = @(Get-P20StandupReminders -PackageRoot $PackageRoot)
        if ($open.Count -eq 0) { return '' }
        if (-not (Test-P20StandupOrganizeVerbs)) { return 'Organize''s verbs are not loaded in this shell.' }
        $plan = Get-P20StandupAttendPlan -Open $open -Now $Now
        if ($plan.Action -eq 'unreadable') { return "its ref '$($open[0].Ref)' is not a cadence (HH:mm days)." }
        if ($plan.Action -ne 'rearm') { return '' }
        $c = Get-P20Consts
        foreach ($id in $plan.Archive) {
            $why = Invoke-P20StandupVerb -Name 'Get-P20Reminders' -Parameters @{ Id = $id; Archive = $true } -Quiet
            if ($why) { return $why }
        }
        return (Invoke-P20StandupVerb -Name 'New-P20Reminder' -Quiet -Parameters @{
                Title = [string]$c.rituals.remindTitle; Due = $plan.Next; Source = [string]$c.rituals.remindSource; Ref = $plan.Ref
            })
    }
    catch {
        return [string]$_.Exception.Message
    }
}
