<#
.SYNOPSIS
    Detects environment capabilities and resolves a tier (1=Full, 2=Local, 3=Minimal).
.DESCRIPTION
    Runs detection checks (git, az CLI, ADO reachability, repo presence),
    resolves a capability tier, and populates $global:P20Env.
    With -Startup, prints a one-liner on Tier 2/3 and stays silent on Tier 1.
.EXAMPLE
    {cliPrefix}Env             # Full environment report
    {cliPrefix}Env -Startup    # Silent on Tier 1, one-liner on Tier 2/3
#>
[CmdletBinding()]
param(
    [switch]$Startup,
    [switch]$Quiet,
    [switch]$Help
)

# Get-CliPrefix normally comes from the module. These scripts are also invoked
# directly -- by tests, by a user running the .ps1, by anything that wants -Help
# without importing first -- so a missing helper must not be fatal.
if (-not (Get-Command Get-CliPrefix -ErrorAction SilentlyContinue)) {
    function Get-CliPrefix {
        if ($global:P20Config -and $global:P20Config.CommandPrefix) { return $global:P20Config.CommandPrefix }
        return ''
    }
}


if ($Help) {
    Write-Host ""
    Write-Host "  $(Get-CliPrefix)Env            Full environment report with tier detection" -ForegroundColor Cyan
    Write-Host "  $(Get-CliPrefix)Env -Startup   Silent on Tier 1, one-liner on Tier 2/3" -ForegroundColor Cyan
    Write-Host "  $(Get-CliPrefix)Env -Help      Show this help" -ForegroundColor Cyan
    Write-Host ""
    return
}

$cfg = $global:P20Config

# -- Detection checks ----------------------------------------------------------
$machine = [System.Environment]::MachineName
$os = if ($IsWindows -or ($PSVersionTable.PSEdition -eq 'Desktop')) { 'Windows' }
elseif ($PSVersionTable.PSEdition -ne 'Desktop' -and $IsMacOS) { 'macOS' }
else { 'Linux' }

$gitInstalled = [bool](Get-Command git -ErrorAction SilentlyContinue)
$repoFound = [bool]($cfg.PromptsRoot -and (Test-Path $cfg.PromptsRoot))

# WHICH tracker the board's address names (D-G2): the probes, the tier's inputs and the report's rows all follow it. An
# ADO board (and a local one, whose rows keep their exact words) walks the az
# path below, byte for byte what it always was; a GitHub board probes gh.
. (Join-Path $PSScriptRoot 'Resolve-Tracker.ps1')
. (Join-Path $PSScriptRoot 'Invoke-TrackerRead.ps1')
$trackerKind = Resolve-P20Tracker -OrgUrl $cfg.Org
$trackerName = if ($trackerKind -eq 'github') { 'GitHub' } else { 'Azure DevOps' }

$azCliInstalled = $false
$azAuthenticated = $false
$adoReachable = $false
$azIdentity = ''

$ghCliInstalled = $false
$ghAuthenticated = $false
$ghReachable = $false
$ghIdentity = ''
$trackerOwner = Get-P20TrackerOwner -OrgUrl $cfg.Org

if ($trackerKind -eq 'github') {
    $ghCliInstalled = [bool](Get-Command gh -ErrorAction SilentlyContinue)
    if ($ghCliInstalled) {
        $ghAuthenticated = ((Invoke-P20TrackerRead 'gh' @('auth', 'status')).Code -eq 0)
        if ($ghAuthenticated) {
            $userRead = Invoke-P20TrackerRead 'gh' @('api', 'user', '-q', '.login')
            $ghIdentity = [string]($userRead.Out -join '')
            if ($userRead.Code -ne 0) { $ghIdentity = '' }
            if ($cfg.OrgStatus -ne 'local' -and $cfg.OrgStatus -ne 'archive' -and $trackerOwner) {
                # Probe via the same path real GitHub calls use -- the gh CLI --
                # so reachability reflects actual access, the az probe's rule.
                $ownerRead = Invoke-P20TrackerRead 'gh' @('api', "users/$trackerOwner", '-q', '.login')
                $ghReachable = ($ownerRead.Code -eq 0 -and [bool](($ownerRead.Out -join '').Trim()))
            }
        }
    }
}
else {
    $azCliInstalled = [bool](Get-Command az -ErrorAction SilentlyContinue)
}

if ($azCliInstalled) {
    $acctRead = Invoke-P20TrackerRead 'az' @('account', 'show', '--output', 'json')
    $azAcct = $acctRead.Out
    $azAuthenticated = ($acctRead.Code -eq 0 -and [bool](($azAcct -join '').Trim()))

    # The account is already in hand; reporting a bare boolean where the docs
    # promised an identity was the whole of that drift. Setup computes the same
    # thing from the same call.
    if ($azAuthenticated) {
        try {
            $acct = ($azAcct | Out-String) | ConvertFrom-Json
            if ($acct.user -and $acct.user.name) { $azIdentity = [string]$acct.user.name }
        }
        catch { $azIdentity = '' }
    }

    if ($azAuthenticated -and $cfg.Org) {
        if ($cfg.OrgStatus -eq 'local' -or $cfg.OrgStatus -eq 'archive') {
            # Config wins: declared-local or rolled-off org is never probed (docs/CLI.md, "Tiers: what works without ADO").
            $adoReachable = $false
        }
        else {
            # Probe via the same path real ADO calls use - the `az devops` CLI -
            # so reachability reflects actual access, not mere org reachability.
            # (A raw connectionData/token probe can 302 even when the CLI works.)
            $projRead = Invoke-P20TrackerRead 'az' @('devops', 'project', 'list', '--org', $cfg.Org, '--query', 'value[0].name', '-o', 'tsv')
            $adoReachable = ($projRead.Code -eq 0 -and [bool](($projRead.Out -join '').Trim()))
        }
    }
}

# -- Tier resolution -----------------------------------------------------------
# Delegates to the canonical decision. Its two tracker inputs were always "the
# tracker's tool is signed in" and "the tracker answered" -- named after the
# only tracker there was -- so a GitHub board hands it gh's answers.
$toolAuthenticated = if ($trackerKind -eq 'github') { $ghAuthenticated } else { $azAuthenticated }
$trackerReachable = if ($trackerKind -eq 'github') { $ghReachable } else { $adoReachable }
$tier = & "$PSScriptRoot\Resolve-TierDecision.ps1" `
    -RepoFound:$repoFound -GitInstalled:$gitInstalled `
    -AzAuthenticated:$toolAuthenticated -AdoReachable:$trackerReachable `
    -Status $cfg.OrgStatus

# Why Tier 2, in words: an archived org, a local one and an active one that
# could not be reached all used to read 'Local (Tier 2)', and the first two are
# a machine doing what it was told.
$orgWord = if ($cfg.ActiveSpace) { "'$($cfg.ActiveSpace)'" } else { 'the active Space' }
$toolWord = if ($trackerKind -eq 'github') { 'gh' } else { 'az' }
$toolInstalled = if ($trackerKind -eq 'github') { $ghCliInstalled } else { $azCliInstalled }
$tierWhy = ''
if ($tier -eq 2) {
    if ($cfg.OrgStatus -eq 'archive') { $tierWhy = "$orgWord is archived; $trackerName is not contacted" }
    elseif ($cfg.OrgStatus -eq 'local') { $tierWhy = "$orgWord works from its cards; Azure DevOps is not contacted" }
    elseif (-not $toolInstalled) { $tierWhy = "$orgWord is active but $toolWord is not installed" }
    elseif (-not $toolAuthenticated) { $tierWhy = "$orgWord is active but $toolWord is not signed in" }
    else { $tierWhy = "$orgWord is active but $trackerName did not answer" }
}
$tierLabel = switch ($tier) {
    1 { 'Full (Tier 1)' }
    2 { "Working from your cards (Tier 2) -- $tierWhy" }
    3 { 'Minimal (Tier 3)' }
}

# -- Populate global -----------------------------------------------------------
$global:P20Env = @{
    Machine          = $machine
    OS               = $os
    Tier             = $tier
    TierLabel        = $tierLabel
    OrgStatus        = $cfg.OrgStatus
    GitInstalled     = $gitInstalled
    RepoFound        = $repoFound
    AzCliInstalled   = $azCliInstalled
    AzAuthenticated  = $azAuthenticated
    AzIdentity       = $azIdentity
    AdoReachable     = $adoReachable
    Tracker          = $trackerKind
    GhCliInstalled   = $ghCliInstalled
    GhAuthenticated  = $ghAuthenticated
    GhIdentity       = $ghIdentity
    TrackerReachable = $trackerReachable
    ActiveSpace        = $cfg.ActiveSpace
}

# -- Startup mode: one-liner on Tier 2/3, silent on Tier 1 --------------------
if ($Startup) {
    # -Quiet: populate $global:P20Env and log, but emit no banner. Used when the
    # module is imported by a non-interactive caller (e.g. the agent) that parses
    # stdout as JSON -- a Write-Host banner here would corrupt that output.
    if ($tier -eq 2) {
        # Yellow only when something WANTED did not happen: an active org that
        # could not be reached. A local or archived org opens every shell with
        # nothing missing, so nothing is said.
        if (-not $Quiet -and $cfg.OrgStatus -ne 'local' -and $cfg.OrgStatus -ne 'archive') {
            $bannerWord = if ($trackerKind -eq 'github') { 'GitHub' } else { 'ADO' }
            Write-Host "  [*] $tierWhy -- $bannerWord commands unavailable  ($(Get-CliPrefix)Env for details)" -ForegroundColor Yellow
        }
        Write-ToolkitLog -Type INFO -Source "$(Get-CliPrefix)Env" -Detail "$machine -- Tier 2 ($tierWhy)"
    }
    elseif ($tier -eq 3) {
        if (-not $Quiet) { Write-Host "  [!] Minimal mode -- repo not found or git missing  ($(Get-CliPrefix)Env for details)" -ForegroundColor Red }
        Write-ToolkitLog -Type INFO -Source "$(Get-CliPrefix)Env" -Detail "$machine -- Tier 3 (minimal mode)"
    }
    return
}

# -- Full report ---------------------------------------------------------------
function Write-Check {
    param([bool]$Ok, [string]$Label, [string]$Detail, [switch]$Note)
    $icon = if ($Ok) { '[ok]' } else { '[X]' }
    $color = if ($Ok) { 'Green' } else { 'Red' }
    # A note is a fact, not a verdict: nothing is wrong and nothing is passing.
    if ($Note) { $icon = '[--]'; $color = 'Yellow' }
    Write-Host "  $icon  $($Label.PadRight(18)) $Detail" -ForegroundColor $color
}

# Which build this is: consts.json's version, the one place it is typed, so the
# line here, /api/env and the System page cannot say three different things.
if (-not (Get-Command Get-P20Consts -ErrorAction SilentlyContinue)) {
    . (Join-Path $PSScriptRoot 'Get-Consts.ps1')
}
Write-Host ""
Write-Host "  Environment" -ForegroundColor Cyan
Write-Host ""
Write-Host "  Version:    $([string](Get-P20Consts).version)" -ForegroundColor White
Write-Host "  Machine:    $machine" -ForegroundColor White
Write-Host "  OS:         $os" -ForegroundColor White
Write-Host "  Tier:       $tierLabel" -ForegroundColor White
# The active org, because every query, prompt path and dashboard is scoped by
# it and "which org am I in" is the question this report is opened to answer.
$orgName = ''
if ($cfg.Spaces) {
    $match = $cfg.Spaces | Where-Object { $_.slug -eq $cfg.ActiveSpace } | Select-Object -First 1
    if ($match -and $match.name) { $orgName = " ($($match.name))" }
}
$orgLine = if ($cfg.ActiveSpace) { "$($cfg.ActiveSpace)$orgName" } else { '(none configured)' }
Write-Host "  Org:        $orgLine" -ForegroundColor White
# On stage: a GitHub Space says whether its repository is public --
# public, private or unknown (consts.json `visibility`), gh asked only when the
# tracker answered the probe above, never at startup. An Azure DevOps Space, or
# one with no tracker, has no visibility and no line.
if ($trackerKind -eq 'github') {
    . (Join-Path $PSScriptRoot 'Get-RepoVisibility.ps1')
    $spaceVisibility = Get-P20SpaceVisibility -OrgUrl $cfg.Org -Projects $cfg.Projects -NoAsk:(-not $ghReachable)
    $visibilityColor = 'White'
    if ($spaceVisibility -eq [string](Get-P20Consts).visibility.public) { $visibilityColor = 'Yellow' }
    Write-Host "  Visibility: $spaceVisibility" -ForegroundColor $visibilityColor
}
Write-Host ""

Write-Check $gitInstalled    'Git'          $(if ($gitInstalled) { 'installed' } else { 'not found' })
# "The hub resolved" is not "a hub was configured": with nothing set the module
# falls back to the folder above the package, which exists everywhere, and a
# green tick on it contradicted the Optional surfaces block below. The
# same test Start uses, from Resolve-HubConfig.ps1 -- not a second copy.
if (-not (Get-Command Get-P20ConfiguredHub -ErrorAction SilentlyContinue)) {
    . (Join-Path $PSScriptRoot 'Resolve-HubConfig.ps1')
}
if (Get-P20ConfiguredHub -PackageRoot (Split-Path $PSScriptRoot -Parent)) {
    Write-Check $repoFound       'Hub'          $(if ($repoFound) { $cfg.PromptsRoot } else { 'not found' })
}
else {
    Write-Check $true            'Hub'          "not configured -- run $(Get-CliPrefix)Start" -Note
}
# Did the hub declare Spaces of its own? Always ok -- a hub with no hub.json is
# the ordinary case; the row exists so "where did that org come from" has an
# answer without opening files.
$hubManifestDetail = 'none -- Spaces come from config alone'
if ($cfg.HubManifest) {
    $hubSpaceWord = 'Spaces'
    if ($cfg.HubSpaceCount -eq 1) { $hubSpaceWord = 'Space' }
    $hubManifestDetail = "read, $($cfg.HubSpaceCount) $hubSpaceWord declared"
}
Write-Check $true            'hub.json'     $hubManifestDetail

if ($trackerKind -eq 'github') {
    # The gh family of rows -- the same three questions the az family answers,
    # for the tracker this board's address names.
    Write-Check $ghCliInstalled 'gh CLI' $(if ($ghCliInstalled) { 'installed' } else { 'not installed' })
    if ($ghCliInstalled) {
        $ghLoginDetail = if (-not $ghAuthenticated) { 'not signed in -- run gh auth login' }
        elseif ($ghIdentity) { $ghIdentity }
        else { 'authenticated (identity not reported by gh)' }
        Write-Check $ghAuthenticated 'gh auth' $ghLoginDetail
        if ($cfg.OrgStatus -eq 'archive') {
            Write-Check $true 'GitHub Add-on' 'not contacted -- archived'
        }
        elseif (-not $trackerOwner) {
            Write-Check $false 'GitHub Add-on' 'the address names no owner'
        }
        else {
            Write-Check $ghReachable 'GitHub Add-on' $(if ($ghReachable) { "connected ($trackerOwner)" } else { "unreachable ($trackerOwner)" })
        }
    }
}
else {
    Write-Check $azCliInstalled 'az CLI' $(if ($azCliInstalled) { 'installed' } else { 'not installed' })
}

if ($azCliInstalled) {
    $orgIsQuiet = ($cfg.OrgStatus -eq 'local' -or $cfg.OrgStatus -eq 'archive')
    $loginDetail = if (-not $azAuthenticated) { 'not logged in -- run az login' }
    elseif ($azIdentity) { $azIdentity }
    else { 'authenticated (identity not reported by az)' }
    if ($orgIsQuiet -and -not $azAuthenticated) {
        # Nothing here asks az for anything, so a sign-in nobody needs is not a failure.
        Write-Check $true 'az login' "not needed -- $orgWord is $($cfg.OrgStatus)"
    }
    else {
        Write-Check $azAuthenticated 'az login' $loginDetail
    }
    # Azure DevOps is an add-on, and these are the agent's words for the same row
    # (agent/core/env.py _ado_access_check). A local or archived org is never
    # probed, by its own declaration; red is what a BROKEN connection looks like.
    if ($cfg.OrgStatus -eq 'archive') {
        Write-Check $true 'ADO Add-on' 'not contacted -- archived'
    }
    elseif ($orgIsQuiet) {
        Write-Check $true 'ADO Add-on' 'not configured (expected)'
    }
    elseif (-not $cfg.Org) {
        Write-Check $false 'ADO Add-on' 'no org URL configured'
    }
    else {
        $adoName = ([string]$cfg.Org).TrimEnd('/').Split('/')[-1]
        Write-Check $adoReachable 'ADO Add-on' $(if ($adoReachable) { "connected ($adoName)" } else { "unreachable ($adoName)" })
    }
}

# -- Optional surfaces ---------------------------------------------------------
# The inventory of everything that is not the ADO core: what exists, whether it
# is on, and the line that changes it. This is the report a reader opens when
# something is missing, so it must name a surface that is OFF rather than
# leaving the machine unable to say what it is not doing
# (AGENTS.md, "Opt in by configuration"). The menu shows what you can use now;
# this shows what exists. One list behind both, Scripts/Get-OptionalSurfaces.ps1,
# and it mirrors the `features` block GET /api/env serves.
if (-not (Get-Command Get-P20OptionalSurfaces -ErrorAction SilentlyContinue)) {
    . (Join-Path $PSScriptRoot 'Get-OptionalSurfaces.ps1')
}
$envFeatures = @{}
if (Get-Command Get-P20Features -ErrorAction SilentlyContinue) { $envFeatures = Get-P20Features }
$envNav = $null
if (Get-Command Get-P20NavAliases -ErrorAction SilentlyContinue) { $envNav = Get-P20NavAliases }

Write-Host ""
Write-Host "  Optional surfaces" -ForegroundColor Cyan
Write-Host ""
foreach ($surface in (Get-P20OptionalSurfaces -Config $cfg -Features $envFeatures -NavAliases $envNav `
        -Prefix (Get-CliPrefix) -PackageRoot (Split-Path $PSScriptRoot -Parent))) {
    $stateColour = 'DarkGray'
    if ($surface.state -eq 'on') { $stateColour = 'Green' }
    $detail = $surface.state
    if ($surface.note) { $detail = "$detail -- $($surface.note)" }
    # The question first (D-W10): the row answers it, in the person's words.
    if ($surface.question) { Write-Host "  $($surface.question)" -ForegroundColor White }
    Write-Host ("  {0} {1}" -f $surface.title.PadRight(24), $detail) -ForegroundColor $stateColour
    Write-Host ("  {0} {1}" -f ''.PadRight(24), $surface.config) -ForegroundColor DarkGray
}

if ($tier -ge 2) {
    Write-Host ""
    $unavailable = @("$(Get-CliPrefix)GetPRComments", "$(Get-CliPrefix)ReplyPR", "$(Get-CliPrefix)NewPrompt <id>", "$(Get-CliPrefix)MyPRs", "$(Get-CliPrefix)MyWork")
    if ($tier -eq 2) {
        $footerWord = if ($trackerKind -eq 'github') { 'GitHub' } else { 'ADO' }
        Write-Host "  $footerWord commands unavailable: $($unavailable -join ', ')" -ForegroundColor Yellow
        Write-Host ""
        # NewPrompt -Title is here on purpose: the creating verb has an offline
        # form, and a Tier-2 list that omitted it is what sent a cold start
        # hand-copying a template.
        Write-Host "  Available: $(Get-CliPrefix)NewPrompt -Title, $(Get-CliPrefix)Sync, $(Get-CliPrefix)Archive, $(Get-CliPrefix)Status, $(Get-CliPrefix)Log, $(Get-CliPrefix)Menu, $(Get-CliPrefix)Env" -ForegroundColor Gray
    }
    elseif ($tier -eq 3) {
        Write-Host "  Most commands unavailable -- repo or git not found." -ForegroundColor Red
        Write-Host "  Available: $(Get-CliPrefix)Menu, $(Get-CliPrefix)Env" -ForegroundColor Gray
    }
}

Write-Host ""
