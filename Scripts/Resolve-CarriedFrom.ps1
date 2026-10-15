#
# Which session a meeting record carries forward from -- and whether its
# "## Carried from <date>" heading still names that session.
#
# NOT a runnable verb: this file is DOT-SOURCED by Scripts/New-Meeting.ps1 and
# Scripts/Get-MeetingAgenda.ps1, the two CLI readers of the heading. The agent's
# reader is carried_from_check in agent/communication/manager.py; the rule both
# implement is docs/hub/manager.md, "Which session a record carries from", and
# one shared table holds them to it (Tests/fixtures/carried-from/table.json,
# asserted from Tests/Test-MeetingAgenda.ps1 and Tests/test_manager.py).
#
# The heading is filled ONCE, when a session is created. A session added later
# for an earlier date, or a heading edited by hand, leaves it naming a session
# that is no longer the latest earlier one in the series. The readers SAY SO;
# none of them rewrites the heading -- it is the record, and a hand edit may
# have been on purpose.
#
#     . (Join-Path $PSScriptRoot 'Resolve-CarriedFrom.ps1')
#     $check = Get-P20CarriedFromCheck -Path $file -Folders @($currentDir, $archiveDir)
#     $note  = Format-P20CarriedFromNote $check
#
# The record-name rule is the contract's (consts.json regex.sessionName), so this
# file needs Scripts/Get-Consts.ps1 dot-sourced first, as both callers already do.
#
# PowerShell 5.1 compatible (ASCII only, no ternary, no -AsHashtable).
#

function Get-P20SessionNameParts {
    # (series, date) from a record's file name by the contract's rule; $null for
    # a file that is not a record. The 1:1 -- the default series -- is '1on1'.
    param([string]$Name)
    $m = [regex]::Match($Name, (Get-P20Consts).regex.sessionName)
    if (-not $m.Success) { return $null }
    $series = '1on1'
    if ($m.Groups[1].Success -and $m.Groups[1].Value) { $series = $m.Groups[1].Value }
    return @{ Series = $series; Date = $m.Groups[2].Value; Name = $Name }
}

function New-P20SessionFileName {
    # The inverse of Get-P20SessionNameParts: a record's file name from its series
    # and date, by the same rule -- the default series by date alone, any other
    # series in front of the date (docs/hub/manager.md, "Where it lives"). The ONE
    # builder: New-Meeting names the record it creates with it, and
    # Get-MeetingAgenda -Plan names the prior record it reads with it.
    param([string]$Series, [string]$Date)
    if (-not $Series -or $Series -eq '1on1') { return "$Date.md" }
    return "$Series-$Date.md"
}

function Get-P20CarriedFromHeading {
    # The text after "## Carried from" -- a date, "(none)", or whatever a hand
    # wrote there -- or $null when the session has no such heading. Matched
    # ignoring case, as the agent's reader matches it; a line may end CRLF.
    param([string[]]$Lines)
    foreach ($line in $Lines) {
        $t = $line.Trim()
        if ($t -match '^## carried from(\s|$)') { return $t.Substring('## Carried from'.Length).Trim() }
    }
    return $null
}

function Resolve-P20CarriedFrom {
    # The rule, over names only: no disk. $Names is every file name in the
    # meeting folder's current/ and archive/ together -- which folder a record is
    # in does not change which session it follows.
    #
    # Returns @{ Verdict; Named; Expected }:
    #   ok       the heading names the latest earlier record in the series
    #            ("(none)" when there is none)
    #   stale    the heading names an earlier record, or "(none)", and a later
    #            earlier record exists -- created out of order, or edited
    #   missing  the heading names no earlier record in this series: a date with
    #            no file, a date in another series, a date not before this one,
    #            or text that is not a date
    #   absent   the session has no "## Carried from" heading at all
    # Expected is the latest earlier record's date, or "(none)".
    param(
        [string]$SessionName,
        # Untyped on purpose: a [string] parameter turns $null into '', and
        # "no heading" and "an empty heading" are different answers.
        [AllowNull()]$Heading,
        [string[]]$Names
    )
    $self = Get-P20SessionNameParts $SessionName
    $earlier = @()
    if ($self) {
        foreach ($n in $Names) {
            $r = Get-P20SessionNameParts $n
            if ($r -and $r.Series -eq $self.Series -and $r.Date -lt $self.Date) { $earlier += $r.Date }
        }
    }
    $earlier = @($earlier | Sort-Object -Unique)
    $expected = '(none)'
    if ($earlier.Count -gt 0) { $expected = $earlier[$earlier.Count - 1] }

    $named = ''
    if ($null -ne $Heading) { $named = ([string]$Heading).Trim() }

    $verdict = 'ok'
    if ($null -eq $Heading) { $verdict = 'absent' }
    elseif ($named -eq $expected) { $verdict = 'ok' }
    elseif ($named -eq '(none)' -or $earlier -contains $named) { $verdict = 'stale' }
    else { $verdict = 'missing' }

    return @{ Verdict = $verdict; Named = $named; Expected = $expected }
}

function Get-P20CarriedFromCheck {
    # The rule over one session file on disk. $Folders are the series' folders
    # (current/ and archive/); a folder that is not there holds nothing. $Also
    # names a record about to be written, so a creator asks BEFORE it writes and
    # never reads the folder back over the file it has just created.
    param([string]$Path, [string[]]$Folders, [string[]]$Also = @())
    $names = @($Also)
    foreach ($dir in $Folders) {
        if (-not (Test-Path $dir)) { continue }
        foreach ($f in (Get-ChildItem -Path $dir -Filter '*.md' -File)) { $names += $f.Name }
    }
    $lines = @(Get-Content -Path $Path -Encoding UTF8)
    return (Resolve-P20CarriedFrom -SessionName (Split-Path $Path -Leaf) -Heading (Get-P20CarriedFromHeading $lines) -Names $names)
}

function Format-P20CarriedFromNote {
    # The one sentence a reader prints when the check is not ok; '' when it is.
    # It names both dates and says the file was left alone.
    param([hashtable]$Check)
    if (-not $Check -or $Check.Verdict -eq 'ok') { return '' }
    $latest = "the latest earlier session in this series is $($Check.Expected)"
    if ($Check.Expected -eq '(none)') { $latest = 'there is no earlier session in this series' }
    $tail = 'The heading is not rewritten; edit it by hand if it should change.'
    if ($Check.Verdict -eq 'absent') { return "This session has no '## Carried from' heading, and $latest. $tail" }
    if ($Check.Verdict -eq 'stale') { return "Carried from $($Check.Named), but $latest. $tail" }
    return "Carried from $($Check.Named), which is not an earlier session in this series; $latest. $tail"
}

function Get-P20NextSessionPath {
    # The record that comes straight after $Date in $Series, in either folder,
    # or $null. A session created for an earlier date sits in front of it, and
    # that later record's heading is the one that may now be stale.
    param([string]$Series, [string]$Date, [string[]]$Folders)
    $best = $null
    $bestDate = $null
    foreach ($dir in $Folders) {
        if (-not (Test-Path $dir)) { continue }
        foreach ($f in (Get-ChildItem -Path $dir -Filter '*.md' -File)) {
            $r = Get-P20SessionNameParts $f.Name
            if (-not $r -or $r.Series -ne $Series -or $r.Date -le $Date) { continue }
            if (-not $bestDate -or $r.Date -lt $bestDate) { $bestDate = $r.Date; $best = $f.FullName }
        }
    }
    return $best
}
