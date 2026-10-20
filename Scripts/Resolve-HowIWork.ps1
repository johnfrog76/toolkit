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

function Get-P20HowIWorkSentence {
    <#
      The answer said to an agent: section one of StartWork's hand-off block
      (D-AR3 of the agent-in-the-room spec), until the Space has a
      how-we-work.md of its own. One sentence per row of the table above --
      the answer, and the tracker it was derived from -- so the block always
      assembles. Only the CLI types it (the web shows the block verbatim), so
      it lives beside the table rather than in consts.json.
    #>
    param([AllowEmptyString()][AllowNull()][string]$Answer)
    switch ("$Answer") {
        'agents' { return 'You work with agents here: the repository''s GitHub issues are the backlog, a worker label on an issue (its size) says which agent takes it, and the item below is the record -- write what you find, what you decide and each commit into it as you go.' }
        'team' { return 'You work on a team in Azure DevOps here: their board and their people hold the rituals, and the item below is the record -- write what you find, what you decide and each commit into it as you go.' }
        default { return 'You work alone here: no rituals and no crew -- the item below is your own record; write what you find, what you decide and each commit into it as you go.' }
    }
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
