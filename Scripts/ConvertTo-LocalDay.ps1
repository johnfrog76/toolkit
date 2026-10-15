<#
.SYNOPSIS
    The one way the CLI turns a git timestamp into a day.

.DESCRIPTION
    A day in this product is the engineer's LOCAL day. git's `%ai`/`%ad` carry
    the AUTHOR's own zone, so `--date=short` or `%ai`'s first ten characters are
    whatever day it was where the commit was made; and `--since`/`--until`
    filter on the COMMITTER's date, which `Sync`'s `pull --rebase` resets to the
    moment of the sync. So every git reader asks for `%at` -- seconds since the
    epoch, zone-free -- and converts here, on the reader's clock.

    The agent's twin is agent/core/clock.py; Tests/fixtures/clock/local-days.json
    holds the two to one answer. Dot-sourceable, 5.1-safe: no module state.
#>

function ConvertTo-P20LocalDay {
    <#
        Seconds since the epoch -> 'yyyy-MM-dd' on the local clock, or in
        -TimeZone when a test pins one. $null for anything that is not a number.
    #>
    param(
        [Parameter(Position = 0)][AllowNull()][AllowEmptyString()][string]$Epoch,
        [System.TimeZoneInfo]$TimeZone
    )
    $seconds = 0L
    if (-not $Epoch -or -not [long]::TryParse($Epoch.Trim(), [ref]$seconds)) { return $null }
    $instant = [DateTimeOffset]::FromUnixTimeSeconds($seconds)
    if ($TimeZone) { return [System.TimeZoneInfo]::ConvertTime($instant, $TimeZone).ToString('yyyy-MM-dd') }
    return $instant.ToLocalTime().ToString('yyyy-MM-dd')
}

function ConvertTo-P20LocalStamp {
    <#
        Seconds since the epoch -> 'yyyy-MM-dd HH:mm' on the local clock (or
        -TimeZone). The agent's twin is local_stamp in agent/core/clock.py.
    #>
    param(
        [Parameter(Position = 0)][AllowNull()][AllowEmptyString()][string]$Epoch,
        [System.TimeZoneInfo]$TimeZone
    )
    $seconds = 0L
    if (-not $Epoch -or -not [long]::TryParse($Epoch.Trim(), [ref]$seconds)) { return $null }
    $instant = [DateTimeOffset]::FromUnixTimeSeconds($seconds)
    if ($TimeZone) { return [System.TimeZoneInfo]::ConvertTime($instant, $TimeZone).ToString('yyyy-MM-dd HH:mm') }
    return $instant.ToLocalTime().ToString('yyyy-MM-dd HH:mm')
}
