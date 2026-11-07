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
function Test-P20UrlInOrg {
    <#
        Whether a URL lies under the organisation address a Space declares: the
        whole authority and path prefix, ignoring case. The test for a URL read
        from a card, before a credential or a command goes anywhere near it.
    #>
    param(
        [AllowEmptyString()][string]$Url,
        [AllowEmptyString()][string]$Org
    )
    $root = "$Org".TrimEnd('/')
    if (-not $root) { return $false }
    return "$Url".StartsWith("$root/", [System.StringComparison]::OrdinalIgnoreCase)
}

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
 Whether a pull request URL (or, with -Kind issue, a work item link) read from a
 card is on the Space's tracker. The one
 test a verb makes before it asks that address anything or sends a credential:
 the card is text, so its line names a pull request and never says where to go.

   a GitHub Space        a GitHub pull request in one of the Space's repositories,
                         or under its owner when it declares none
   an Azure DevOps Space an Azure DevOps pull request under its organisation
   a Space with no       a GitHub pull request, by its line: there is no tracker
   tracker               to hold it to, and nothing of the Space's goes there
#>
function Test-P20UrlOnTracker {
    param(
        [AllowEmptyString()][AllowNull()][string]$Url,
        [AllowEmptyString()][AllowNull()][string]$OrgUrl,
        $Projects,
        # 'pull' for a pull request line, 'issue' for a card's link to its work
        # item: the same rule, and an issue is never read from a Space with no
        # tracker, because there is nothing there to close.
        [ValidateSet('pull', 'issue')][string]$Kind = 'pull'
    )
    $segment = if ($Kind -eq 'issue') { 'issues' } else { 'pull' }
    $github = [regex]::Match("$Url", '(?i)^https://github\.com/([^/\s]+)/([^/\s]+)/' + $segment + '/\d+(?:[/?#]\S*)?$')
    $tracker = Resolve-P20Tracker -OrgUrl $OrgUrl
    if ($tracker -eq 'none') { return ($Kind -eq 'pull' -and $github.Success) }
    if ($tracker -eq 'ado') {
        # A work item link is read by its number wherever the organisation put it,
        # as Land always has; only the organisation is held.
        if ($Kind -eq 'issue') { return (Test-P20UrlInOrg -Url $Url -Org $OrgUrl) }
        return (("$Url" -match '(?i)/pullrequest/\d+') -and (Test-P20UrlInOrg -Url $Url -Org $OrgUrl))
    }
    if (-not $github.Success) { return $false }
    $repos = @(Get-P20TrackerRepos -OrgUrl $OrgUrl -Projects $Projects)
    if ($repos.Count -gt 0) { return ($repos -contains "$($github.Groups[1].Value)/$($github.Groups[2].Value)") }
    return ($github.Groups[1].Value -ieq (Get-P20TrackerOwner -OrgUrl $OrgUrl))
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
