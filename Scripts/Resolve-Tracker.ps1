<#
.SYNOPSIS
    WHICH tracker answers for a board -- derived from its address.
.DESCRIPTION
    D-G2 (docs/CONFIGURATION.md, "The org address also decides the TRACKER"): a board carries ONE address
    (spaces[].org), and the address decides the tracker. No tracker: key, no
    migration, nothing new to set -- the same derived-not-defaulted rule as
    Test-P20AdoEnabled, applied to WHICH instead of WHETHER.

        'none'    when the address is blank -- a local board
        'github'  when the address's host is github.com
        'ado'     for every other address -- which is exactly what every
                  address meant before this rule existed. A GitHub Enterprise
                  host lands here too; a third tracker
                  changes that on purpose, in the shared table first.

    A pure function over one value, in a file of its own, like
    Test-AdoEnabled.ps1 and Resolve-TierDecision.ps1: a module wrapper, a
    module-launched script and a test all reach the SAME rule, and it reads no
    state. The agent's copy is agent/core/config.py tracker(); ONE table,
    Tests/fixtures/tracker/table.json, holds the two together. WHETHER the
    tracker is contacted stays the tier's and Test-P20AdoEnabled's business;
    this only names which one would answer.
#>

function Resolve-P20Tracker {
    param(
        # The board's address, spaces[].org: a URL, or '' / $null for a local board.
        [AllowEmptyString()][AllowNull()][string]$OrgUrl
    )
    $url = "$OrgUrl".Trim().ToLowerInvariant()
    if ($url -eq '') { return 'none' }
    # The authority: strip scheme, then path, credentials and port.
    $authority = ($url -replace '^[a-z][a-z0-9+.-]*://', '').Split('/')[0]
    $authority = $authority.Split('@')[-1].Split(':')[0]
    if ($authority -eq 'github.com' -or $authority -eq 'www.github.com') { return 'github' }
    return 'ado'
}

<#
 The address's FIRST PATH SEGMENT: the GitHub owner, and the ADO organisation
 name -- the thing a probe asks after and a report prints. Case is preserved
 (it is a display name as much as an API argument). '' when the address has no
 path -- a blank address, or the legacy *.visualstudio.com shape whose org
 lives in the host.
#>
function Get-P20TrackerOwner {
    param(
        [AllowEmptyString()][AllowNull()][string]$OrgUrl
    )
    $url = "$OrgUrl".Trim()
    if ($url -eq '') { return '' }
    $rest = $url -replace '^[a-zA-Z][a-zA-Z0-9+.-]*://', ''
    $parts = $rest.Split('/')
    if ($parts.Count -lt 2) { return '' }
    return $parts[1]
}

<#
 WHICH repository a GitHub verb means -- the one rule, used by every verb that
 needs a repo (NewPrompt, CloseItem, NewPR ...), because GitHub's issue
 and PR numbers are per-REPO where ADO's are org-wide. A repo-grained address
 answers itself; otherwise the board's projects[] must name exactly ONE repo.
 With several the number is ambiguous -- a guess could act on the wrong
 repo's issue of that number -- so the answer is a stated reason instead, and the caller
 refuses with it. Returns a hashtable: @{ Repo = 'owner/name' }, or
 @{ Reason = ...; Hint = ... }.
#>
<#
 Every repository a GitHub READ may span -- 'owner/name' each. A repo-grained
 address names one; otherwise every projects[] entry with a repo. A read may
 fan out where a write must name ONE (Resolve-P20TrackerRepo below): listing
 PRs across the board's repos is the WIQL org-wide shape, and wrong-repo
 ambiguity cannot corrupt a read.
#>
function Get-P20TrackerRepos {
    param(
        [AllowEmptyString()][AllowNull()][string]$OrgUrl,
        $Projects
    )
    $owner = Get-P20TrackerOwner -OrgUrl $OrgUrl
    if (-not $owner) { return @() }
    $rest = ("$OrgUrl".Trim() -replace '^[a-zA-Z][a-zA-Z0-9+.-]*://', '').Split('/')
    if ($rest.Count -ge 3 -and $rest[2]) { return @("$owner/$($rest[2])") }
    return @($Projects | ForEach-Object { $_.repo } | Where-Object { $_ } | ForEach-Object { "$owner/$_" })
}

<#
 One header line, every tracker verb, before it acts: which space, which
 tracker. Found live: with the machine's active space quietly back on
 a real ADO org, `NewPrompt 55` -- meant for a GitHub issue -- fetched ADO work item
 55, a real work item assigned to someone else. An existing guard refused
 before anything was written, but the output never named the space; the
 near-miss was caught by recognising an email string, not by the product
 saying where it stood. An id is unambiguous WITHIN a space and ambiguous
 ACROSS tenants, and the active space decides silently -- this line is the
 cheap fix that comes first.
#>
function Write-P20TrackerHeader {
    param(
        # The active space's display name (config's spaces[].name, falling back
        # to the slug); '' prints as '(no space)' rather than a blank line.
        [AllowEmptyString()][AllowNull()][string]$Name,
        [AllowEmptyString()][AllowNull()][string]$OrgUrl
    )
    $tracker = Resolve-P20Tracker -OrgUrl $OrgUrl
    $label = 'local'
    if ($tracker -eq 'github') { $label = 'gh' }
    elseif ($tracker -eq 'ado') { $label = 'ado' }
    $display = "$Name"
    if (-not $display) { $display = '(no space)' }
    Write-Host "[*] In $display ($label)" -ForegroundColor DarkCyan
}

function Resolve-P20TrackerRepo {
    param(
        [AllowEmptyString()][AllowNull()][string]$OrgUrl,
        $Projects,
        [string]$CliPrefix = ''
    )
    $owner = Get-P20TrackerOwner -OrgUrl $OrgUrl
    $rest = ("$OrgUrl".Trim() -replace '^[a-zA-Z][a-zA-Z0-9+.-]*://', '').Split('/')
    if ($rest.Count -ge 3 -and $rest[2]) { return @{ Repo = "$owner/$($rest[2])" } }
    $repos = @($Projects | ForEach-Object { $_.repo } | Where-Object { $_ })
    if ($repos.Count -eq 1) { return @{ Repo = "$owner/$($repos[0])" } }
    if ($repos.Count -eq 0) {
        return @{
            Reason = 'This GitHub board names no repository.'
            Hint   = "Make the address repo-grained (${CliPrefix}Config -Set spaces.<slug>.org=https://github.com/$owner/<repo>) or add the repo to spaces.<slug>.projects."
        }
    }
    return @{
        Reason = "Issue numbers are per-repository, and this board has $($repos.Count): $($repos -join ', ')."
        Hint   = "Say which: make the address repo-grained (https://github.com/$owner/<repo>), or keep one repo in spaces.<slug>.projects."
    }
}

<#
 A git remote URL's GitHub repository, 'owner/name' -- https://github.com/o/r(.git),
 or the scp-like and ssh:// forms of the same address -- or '' for anything else.
 The one reading of "is this clone that repository", shared by StartWork -Launch
 and Resolve-P20SpaceCheckout (Resolve-SpaceCheckout.ps1).
#>
function Get-P20GitHubOriginRepo {
    param(
        [AllowEmptyString()][AllowNull()][string]$Url
    )
    $m = [regex]::Match("$Url".Trim(), '(?i)github\.com[:/]+([^/\s]+)/([^/\s]+?)(?:\.git)?/?$')
    if ($m.Success) { return $m.Groups[1].Value + '/' + $m.Groups[2].Value }
    return ''
}
