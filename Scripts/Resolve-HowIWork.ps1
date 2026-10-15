<#
.SYNOPSIS
    How do you want to work in this Space? -- the answer, and whether it is asked.
.DESCRIPTION
    docs/CONFIGURATION.md, "spaces[].howIWork -- how you work in this Space": the answer is a fact
    about the SPACE, derived from its tracker, and asked only where the tracker
    cannot tell.

        tracker 'ado'     'team'   -- derived, locked: their board holds the rituals
        tracker 'none'    'alone'  -- derived, locked: your own cards
        tracker 'github'  spaces[].howIWork when it is 'alone' or 'agents'
                          ('chosen'), else 'alone' ('default') -- asked

    The tracker is the one the address names (Resolve-Tracker.ps1), so a GitHub
    Space that is 'local' is still asked. 'team' is never stored: it is what an
    Azure DevOps address means, and a stored value on a Space whose tracker
    decides is ignored, never an error.

    The gate (Invoke-P20HowIWorkGate): Team Agile's switch, features.solitaireAgile,
    stays the person's; the module is on only where the switch is on AND the
    active Space's answer is 'agents'. Applied once, in Get-P20Features, so every
    reader -- the module loader, Menu, the inventory, the bridge's table -- sees
    the same answer.

    Pure functions over values, in a file of their own like Resolve-Tracker.ps1
    and Test-AdoEnabled.ps1: they read no state. The agent's copy is
    agent/core/config.py how_i_work() and apply_how_i_work(); ONE table,
    Tests/fixtures/how-i-work/table.json, holds the two together.

    PowerShell 5.1 clean: no ternary, no null-coalescing, ASCII only.
#>

if (-not (Get-Command Resolve-P20Tracker -ErrorAction SilentlyContinue)) {
    . (Join-Path $PSScriptRoot 'Resolve-Tracker.ps1')
}

function Get-P20HowIWorkStored {
    <# The answers a Space may store -- the schema's allowed values. 'team' is derived, never stored. #>
    return @('alone', 'agents')
}

function Resolve-P20HowIWork {
    param(
        # The Space's address, spaces[].org: a URL, or '' / $null for own cards.
        [AllowEmptyString()][AllowNull()][string]$OrgUrl,
        # spaces[].howIWork as configured, or '' / $null when nobody has answered.
        [AllowEmptyString()][AllowNull()][string]$Stored
    )
    $tracker = Resolve-P20Tracker -OrgUrl $OrgUrl
    if ($tracker -eq 'ado') {
        return [PSCustomObject]@{ answer = 'team'; source = 'derived'; tracker = $tracker; locked = $true }
    }
    if ($tracker -ne 'github') {
        return [PSCustomObject]@{ answer = 'alone'; source = 'derived'; tracker = $tracker; locked = $true }
    }
    $said = "$Stored".Trim().ToLowerInvariant()
    if ((Get-P20HowIWorkStored) -contains $said) {
        return [PSCustomObject]@{ answer = $said; source = 'chosen'; tracker = $tracker; locked = $false }
    }
    return [PSCustomObject]@{ answer = 'alone'; source = 'default'; tracker = $tracker; locked = $false }
}

function Get-P20HowIWorkGatedFeature {
    <# The one module the answer gates: Team Agile, whose answer is 'agents'. #>
    return 'solitaireAgile'
}

function Invoke-P20HowIWorkGate {
    <#
      The resolved features map with the Space's answer applied: the gated flag
      stays true only where the answer is 'agents'. The map is changed in place
      and returned. A flag that is absent stays absent -- the switch was never
      set, and the inventory says so.
    #>
    param($Features, [AllowEmptyString()][AllowNull()][string]$Answer)
    $flag = Get-P20HowIWorkGatedFeature
    if ($Features -and $Features.ContainsKey($flag) -and $Features[$flag] -and $Answer -ne 'agents') {
        $Features[$flag] = $false
    }
    return $Features
}
