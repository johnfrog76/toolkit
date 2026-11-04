#
# burn.weekStarts -- when the Claude Code burn's week starts: "<Day> HH:mm",
# local time, "Friday 05:00" by default (config.default.json). The ONE reader of
# the value's shape: Get-P20BurnWindows (Scripts/Read-ClaudeUsage.ps1) takes the
# week from it, and Config -Set validates it through Test-P20ConfigValue
# (Scripts/Get-ConfigSchema.ps1), so a value -Set accepts is a value Burn reads.
#
# NOT a runnable verb: dot-sourced. PowerShell 5.1 clean, ASCII only.
#

function ConvertFrom-P20WeekStart {
    <#
      Reads "<Day> HH:mm": an English day name (any case) and a 24-hour time,
      one space or more between. Returns @{ Ok; Day ([DayOfWeek]); Hour;
      Minute; Text (the value as it reads back, "Monday 09:00"); Reason }.
    #>
    param([AllowEmptyString()][AllowNull()][string]$Text)
    $result = @{ Ok = $false; Day = [DayOfWeek]::Friday; Hour = 0; Minute = 0; Text = ''; Reason = '' }
    $raw = ([string]$Text).Trim()
    $m = [regex]::Match($raw, '^(?i)(monday|tuesday|wednesday|thursday|friday|saturday|sunday)\s+(\d{1,2}):(\d{2})$')
    if (-not $m.Success) {
        $result.Reason = "burn.weekStarts is a day and a 24-hour time, like 'Friday 05:00' -- got '$raw'."
        return $result
    }
    $hour = [int]$m.Groups[2].Value
    $minute = [int]$m.Groups[3].Value
    if ($hour -gt 23 -or $minute -gt 59) {
        $result.Reason = "burn.weekStarts is a day and a 24-hour time, like 'Friday 05:00' -- '$raw' is no time of day."
        return $result
    }
    $name = $m.Groups[1].Value.ToLowerInvariant()
    $name = $name.Substring(0, 1).ToUpperInvariant() + $name.Substring(1)
    $result.Ok = $true
    $result.Day = [DayOfWeek]$name
    $result.Hour = $hour
    $result.Minute = $minute
    $result.Text = $name + ' ' + $hour.ToString('00') + ':' + $minute.ToString('00')
    return $result
}
