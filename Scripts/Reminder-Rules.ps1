<#
.SYNOPSIS
    The Organize add-on's reminder rules, in one file. Dot-source it.

.DESCRIPTION
    Not a command. Everything the CLI works OUT about a reminder lives here, so
    the two verbs (NewReminder, Reminders) and the suite read one answer:

      Get-P20ReminderBucket    overdue / today / upcoming, derived against the
                               local clock at read time and NEVER stored -- a
                               file that stored it would be wrong by morning.
                               The agent's GET /api/reminders implements the
                               same rule; Tests/fixtures/reminders/buckets.json
                               holds the two to one table.
      Get-P20SnoozeDue         what -Snooze 1h|tomorrow|nextweek means.
      ConvertTo-P20DueValue    what -Due accepts, normalised to the one stored shape.
      Read-P20Reminder         a reminder file's fields, read the way the agent reads them.

    Times are LOCAL with no offset -- the simplest honest answer for one
    engineer's hub, and a known limit for a hub synced across two zones
    (docs/hub/reminders.md). A due DATE with no time is due at the end of its day.

    Every contract literal -- the **Due:** stamp, its pattern, the bucket and
    snooze words -- comes from consts.json through Get-P20Consts.

.NOTES
    PowerShell 5.1 compatible (ASCII dashes only).
#>

if (-not (Get-Command Get-P20Consts -ErrorAction SilentlyContinue)) {
    . (Join-Path $PSScriptRoot 'Get-Consts.ps1')
}

function script:ConvertFrom-P20LocalStamp {
    # 'yyyy-MM-dd' or 'yyyy-MM-ddTHH:mm' -> [datetime], or $null.
    param([string]$Text)
    if (-not $Text) { return $null }
    $formats = [string[]]@('yyyy-MM-ddTHH:mm', 'yyyy-MM-dd')
    $parsed = [datetime]::MinValue
    if ([datetime]::TryParseExact($Text.Trim(), $formats, [System.Globalization.CultureInfo]::InvariantCulture,
            [System.Globalization.DateTimeStyles]::None, [ref]$parsed)) {
        return $parsed
    }
    return $null
}

function Get-P20ReminderBucket {
    <#
        overdue | today | upcoming for a stored due value against -Now.
        No due -> upcoming. A date alone -> due at the end of that day.
        A time -> overdue only once the minute has passed.
    #>
    param(
        [AllowNull()][AllowEmptyString()][string]$Due,
        [Parameter(Mandatory = $true)][datetime]$Now
    )
    $words = @((Get-P20Consts).reminders.buckets)   # overdue, today, upcoming
    if (-not $Due) { return $words[2] }
    $at = ConvertFrom-P20LocalStamp $Due
    if ($null -eq $at) { return $words[2] }
    $today = $Now.Date
    if ($Due.Trim() -notmatch 'T') {
        if ($at.Date -lt $today) { return $words[0] }
        if ($at.Date -eq $today) { return $words[1] }
        return $words[2]
    }
    $nowMinute = $Now.Date.AddHours($Now.Hour).AddMinutes($Now.Minute)
    if ($at -lt $nowMinute) { return $words[0] }
    if ($at.Date -eq $today) { return $words[1] }
    return $words[2]
}

function Get-P20SnoozeDue {
    <#
        The new **Due:** value for a snooze word, as 'yyyy-MM-ddTHH:mm'.
          1h        an hour from NOW (not from the old due time)
          tomorrow  tomorrow at 09:00
          nextweek  the next Monday at 09:00 -- never today, even on a Monday
        Returns $null for a word the contract does not list.
    #>
    param(
        [Parameter(Mandatory = $true)][string]$Word,
        [Parameter(Mandatory = $true)][datetime]$Now
    )
    $words = @((Get-P20Consts).reminders.snooze)    # 1h, tomorrow, nextweek
    $w = $Word.Trim().ToLowerInvariant()
    if ($words -notcontains $w) { return $null }
    $minute = $Now.Date.AddHours($Now.Hour).AddMinutes($Now.Minute)
    $at = $null
    if ($w -eq $words[0]) { $at = $minute.AddHours(1) }
    elseif ($w -eq $words[1]) { $at = $Now.Date.AddDays(1).AddHours(9) }
    else {
        $ahead = (([int][DayOfWeek]::Monday - [int]$Now.DayOfWeek) + 7) % 7
        if ($ahead -eq 0) { $ahead = 7 }
        $at = $Now.Date.AddDays($ahead).AddHours(9)
    }
    return $at.ToString('yyyy-MM-ddTHH:mm', [System.Globalization.CultureInfo]::InvariantCulture)
}

function ConvertTo-P20DueValue {
    <#
        What -Due accepts, as the one stored shape, or $null if it is none of them:
          yyyy-MM-dd               a day
          yyyy-MM-ddTHH:mm         a moment (a space instead of the T is accepted)
          1h | tomorrow | nextweek the snooze words, from -Now
    #>
    param(
        [Parameter(Mandatory = $true)][string]$Text,
        [Parameter(Mandatory = $true)][datetime]$Now
    )
    $t = $Text.Trim()
    $snoozed = Get-P20SnoozeDue -Word $t -Now $Now
    if ($snoozed) { return $snoozed }
    $t = $t -replace '^(\d{4}-\d{2}-\d{2}) (\d{2}:\d{2})$', '$1T$2'
    if ($t -notmatch '^\d{4}-\d{2}-\d{2}(T\d{2}:\d{2})?$') { return $null }
    if ($null -eq (ConvertFrom-P20LocalStamp $t)) { return $null }
    return $t
}

function Read-P20Reminder {
    <#
        @{ Id; File; Path; Title; Due; Source; Ref; Created; Closed } from one
        reminder file. The id is the filename's, read by the ONE id rule.
    #>
    param([Parameter(Mandatory = $true)][System.IO.FileInfo]$File)
    $c = Get-P20Consts
    $text = [System.IO.File]::ReadAllText($File.FullName) -replace "`r`n", "`n"
    $title = $File.BaseName
    $h1 = [regex]::Match($text, '(?m)^#\s+(.+)$')
    if ($h1.Success) { $title = $h1.Groups[1].Value.Trim() }
    $read = {
        param($stamp)
        $m = [regex]::Match($text, '(?m)^' + [regex]::Escape($stamp) + '[ \t]*(.*)$')
        if ($m.Success) { return $m.Groups[1].Value.Trim() }
        return ''
    }
    $due = ''
    $dm = [regex]::Match($text, $c.regex.dueLine)
    if ($dm.Success) {
        $due = $dm.Groups[1].Value
        if ($dm.Groups[2].Success -and $dm.Groups[2].Value) { $due = "$due" + 'T' + $dm.Groups[2].Value }
    }
    $id = $null
    if (Get-Command Get-P20CardId -ErrorAction SilentlyContinue) {
        $id = Get-P20CardId -Name $File.Name -Pattern (Get-P20CardIdPattern -WorkItemTypes @{})
    }
    return @{
        Id      = $id
        File    = $File.Name
        Path    = $File.FullName
        Title   = $title
        Due     = $due
        Source  = (& $read $c.stamps.source)
        Ref     = (& $read $c.stamps.ref)
        Created = (& $read $c.stamps.created)
        Closed  = (& $read $c.stamps.closed)
    }
}

function Set-P20ReminderTitle {
    <#
        Rewrites a reminder's title -- its first `# ` heading -- and nothing
        else. The filename's slug is NOT renamed: the id is the identity, and the
        slug is a label written once. Keeps the file's line terminator and goes
        through Write-CardText. Returns $false, writing nothing, when the title
        is already that.
    #>
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Title
    )
    if (-not (Get-Command Write-CardText -ErrorAction SilentlyContinue)) {
        . (Join-Path $PSScriptRoot 'Write-CardText.ps1')
    }
    $raw = [System.IO.File]::ReadAllText($Path)
    $eol = "`n"
    if ($raw.Contains("`r`n")) { $eol = "`r`n" }
    $lines = @(($raw -replace "`r`n", "`n").Split("`n"))
    $wanted = "# $Title"
    $at = -1
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match '^#\s+') { $at = $i; break }
    }
    if ($at -ge 0) {
        if ($lines[$at] -ceq $wanted) { return $false }
        $lines[$at] = $wanted
    }
    else {
        # A file with no heading read its title from the filename; give it one.
        $lines = @($wanted, '') + $lines
    }
    Write-CardText -Path $Path -Content ($lines -join $eol)
    return $true
}

function ConvertTo-P20ReminderSlug {
    # The filename's words: lowercase kebab, ASCII, at most 50 characters.
    param([Parameter(Mandatory = $true)][string]$Title)
    $s = $Title.ToLowerInvariant() -replace '[^a-z0-9]+', '-'
    $s = $s.Trim('-')
    if ($s.Length -gt 50) { $s = $s.Substring(0, 50).TrimEnd('-') }
    if (-not $s) { $s = 'reminder' }
    return $s
}
