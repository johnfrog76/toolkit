<#
.SYNOPSIS
    Holds the counts docs/TESTING.md writes in several places to the one paste block.
.DESCRIPTION
    tkTest prints a paste block of three figures (Get-P20PasteLines in
    Scripts/TestAll-Rules.ps1): the CLI's per-suite line and `N suites, M assertions`,
    then `pytest: ...` and `web: ...`. The seat pastes it into docs/TESTING.md under
    "The counts, after a merge". The same figures are written in more places, and a paste
    used to refresh some and not the rest. The paste block is the source; this reads the
    other places back against it, from the text alone -- no run, no machine-local file --
    so it holds on every machine and in CI.

      1. the `tkTestToolkit` table row's per-suite list == the paste block's per-suite line
      2. the command block's `tkTestToolkit # N suites, M assertions` == the paste's total
      3. the command block's pytest totals == the paste block's `pytest:` line
      4. the command block's web totals == the paste block's `web:` line

    A paste line that says "not run" (a half the run lacked) is not a count and is a
    finding of its own: it is information for the person pasting, never a figure to keep.

    Returns an array of findings (empty when everything agrees); each names the stale line,
    and for the table row the first suite whose number differs.
#>
function Get-P20TestingDocDrift {
    [CmdletBinding()]
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Text)

    $findings = @()
    $paste = [regex]::Match($Text, '(?s)\*\*The counts, after a merge\.\*\*.*?```text\r?\n(.*?)\r?\n```')
    if (-not $paste.Success) { return @('the paste block under "The counts, after a merge" was not found') }
    $lines = @($paste.Groups[1].Value -split "\r?\n" | ForEach-Object { $_.Trim() } | Where-Object { $_ })

    $pasteSuites = @()
    $pasteTotal = $null; $pastePytest = $null; $pasteWeb = $null
    foreach ($l in $lines) {
        if ($l -match '^(\d+ suites, \d+ assertions)$') { $pasteTotal = $Matches[1]; continue }
        if ($l -match '^pytest: (.+)$') { $pastePytest = $Matches[1]; continue }
        if ($l -match '^web: (.+)$') { $pasteWeb = $Matches[1]; continue }
        foreach ($pm in [regex]::Matches($l, '(?<=^|,\s)([A-Z][A-Za-z]+) (\d+)(?=,|$)')) { $pasteSuites += , @($pm.Groups[1].Value, $pm.Groups[2].Value) }
    }

    # 1. the table row's list
    $row = @($Text -split "\r?\n" | Where-Object { $_ -match '^\|\s*`tkTestToolkit`\s*\|' })
    if ($row.Count -ne 1) { $findings += "the tkTestToolkit table row was not found exactly once ($($row.Count))" }
    else {
        $rm = [regex]::Match($row[0], 'per suite: (.*?)\.(?: |$)')
        if (-not $rm.Success) { $findings += 'the tkTestToolkit table row has no "per suite: ..." list' }
        else {
            $rowSuites = @([regex]::Matches($rm.Groups[1].Value, '([A-Z][A-Za-z]+) (\d+)') | ForEach-Object { , @($_.Groups[1].Value, $_.Groups[2].Value) })
            $n = [Math]::Max($rowSuites.Count, $pasteSuites.Count)
            for ($i = 0; $i -lt $n; $i++) {
                $r = '(none)'; if ($i -lt $rowSuites.Count) { $r = "$($rowSuites[$i][0]) $($rowSuites[$i][1])" }
                $p = '(none)'; if ($i -lt $pasteSuites.Count) { $p = "$($pasteSuites[$i][0]) $($pasteSuites[$i][1])" }
                if ($r -ne $p) {
                    $findings += "the tkTestToolkit table row is stale against the paste block: first difference is suite $($i + 1), row says '$r', paste says '$p'"
                    break
                }
            }
        }
    }

    # 2. the command block's CLI line
    $cmdTotal = [regex]::Match($Text, 'tkTestToolkit\s+#\s*(\d+ suites, \d+ assertions)')
    if (-not $pasteTotal) { $findings += 'the paste block has no "N suites, M assertions" line' }
    elseif (-not $cmdTotal.Success) { $findings += 'the command block has no "tkTestToolkit # N suites, M assertions" line' }
    elseif ($cmdTotal.Groups[1].Value -ne $pasteTotal) { $findings += "the command block's tkTestToolkit line is stale: it says '$($cmdTotal.Groups[1].Value)', the paste block says '$pasteTotal'" }

    # 3. pytest
    $cmdPytest = [regex]::Match($Text, 'pytest Tests/\s+#\s*(.+?)\s+--')
    if (-not $pastePytest) { $findings += 'the paste block has no "pytest: ..." line' }
    elseif ($pastePytest -notmatch '^\d+ passed(, \d+ skipped)?(, \d+ subtests)?$') { $findings += "the paste block's pytest line is not a count ('$pastePytest'): paste from a tkTest run that ran the agent half" }
    elseif (-not $cmdPytest.Success) { $findings += 'the command block has no pytest totals line' }
    elseif ($cmdPytest.Groups[1].Value -ne $pastePytest) { $findings += "the command block's pytest line is stale: it says '$($cmdPytest.Groups[1].Value)', the paste block says '$pastePytest'" }

    # 4. web
    $cmdWeb = [regex]::Match($Text, 'npm test\s+#\s*(?:.*?then\s+)?(\d+ suites, \d+ tests)')
    if (-not $pasteWeb) { $findings += 'the paste block has no "web: ..." line' }
    elseif ($pasteWeb -notmatch '^\d+ suites, \d+ tests$') { $findings += "the paste block's web line is not a count ('$pasteWeb'): paste from a tkTest run that ran the web half" }
    elseif (-not $cmdWeb.Success) { $findings += 'the command block has no web totals line' }
    elseif ($cmdWeb.Groups[1].Value -ne $pasteWeb) { $findings += "the command block's web line is stale: it says '$($cmdWeb.Groups[1].Value)', the paste block says '$pasteWeb'" }

    return $findings
}
