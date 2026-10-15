<#
.SYNOPSIS
    Connect a Space to its tracker -- the four steps, each named as whose it is.
.DESCRIPTION
    The connect wizard's verb (W2, D-W12 to D-W16; docs/CONFIGURATION.md,
    "Settings by workflow: the questions, and the one list behind them"). The web's /connect/<slug> page drives this with -AsJson; a person
    in a terminal types the same steps:

      1. YOURS   the address        -Address <url>       (we write it through Config;
                                                          an address implies active, D-W14)
      2. YOURS   sign in            az login / gh auth login -- said and CHECKED, never run
      3. OURS    discovery          -Discover lists projects or repos; -Projects writes the ones you tick
      4. OURS    sprint awareness   -Sprint true|false, this Space's one flag

    With no step switch it REPORTS where the Space stands. Every write is
    Scripts/Set-ToolkitConfig.ps1, the one writer, called in-process: a refusal
    there is a refusal here, with its own sentence. -As <new-slug> graduates the
    shipped Azure demo (or any demo Space) into your own Space (D-W15): the new
    Space is declared from its settings, the folder moves, and it becomes the
    active one.
.PARAMETER Slug
    The Space to connect. Required.
.PARAMETER Address
    The tracker's address: https://github.com/<owner>[/<repo>] or https://dev.azure.com/<org>.
.PARAMETER Discover
    List the repos (GitHub) or projects (ADO) the address holds. Needs the sign-in.
.PARAMETER Projects
    Write the projects: Name/repo; Other/repo2 (or a JSON array). Usually the ticked
    rows of -Discover.
.PARAMETER Repo
    GitHub only: the one repo this Space IS -- owner/name, usually a row of -Discover. Writes the
    address repo-grained (D-W17); a GitHub Space has no projects list.
.PARAMETER Sprint
    'true' or 'false': sprint awareness on this Space.
.PARAMETER As
    Graduate a shipped demo Space into a Space of this slug (only for a Space marked example).
.PARAMETER AsJson
    Print the report as one JSON object -- the web's form.
.PARAMETER WhatIf
    Say what would be written, write nothing.
#>
[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [string]$Slug,
    [string]$Address,
    [switch]$Discover,
    [string]$Projects,
    [string]$Repo,
    [string]$Sprint,
    [string]$As,
    [switch]$AsJson,
    [switch]$WhatIf,
    [switch]$Help
)

$ErrorActionPreference = 'Stop'
$scriptsDir = $PSScriptRoot
$packageRoot = Split-Path $scriptsDir -Parent
# Held as a scriptblock and DOT-invoked at SCRIPT scope, because a function a
# script defines does not survive the module being re-imported (AGENTS.md,
# "Traps worth knowing") -- and the one writer this script calls does exactly
# that on its way (Set-ToolkitConfig.ps1 re-imports the module so the session
# sees the new value). Local variables survive, so the loader is re-run after
# every write, where the call sits -- not inside the writer scriptblock, whose
# scope would swallow the reload.
$loadHelpers = {
    foreach ($helper in @('Resolve-CliPrefix.ps1', 'Resolve-Tracker.ps1', 'Invoke-TrackerRead.ps1', 'Test-TrackerSignIn.ps1', 'Resolve-HubConfig.ps1')) {
        . (Join-Path $scriptsDir $helper)
    }
}
. $loadHelpers
if (-not (Get-Command Write-CliError -ErrorAction SilentlyContinue)) {
    function Write-CliError { param([string]$Message, [string]$Hint) Write-Host "Error: $Message" -ForegroundColor Red; if ($Hint) { Write-Host "Hint: $Hint" -ForegroundColor Yellow } }
}
$prefix = ''
if (Get-Command Get-CliPrefix -ErrorAction SilentlyContinue) { $prefix = Get-CliPrefix }
if (-not $prefix) { $prefix = Resolve-P20ConfigPrefix -PackageRoot $packageRoot }

if ($Help -or -not $Slug) {
    Write-Host ""
    Write-Host "  ${prefix}Connect <slug> [-Address <url>] [-Discover] [-Projects <Name/repo;...>] [-Repo <owner/name>] [-Sprint <true|false>] [-As <new-slug>] [-AsJson] [-WhatIf]" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  Connect a Space to its tracker, in four steps -- each named as whose it is:" -ForegroundColor Gray
    Write-Host "    1. yours  the address        -Address https://github.com/<owner>/<repo>  (a GitHub Space IS one repo)"
    Write-Host "                                 -Address https://dev.azure.com/<org>  (an Azure DevOps Space IS an organisation, projects inside it)"
    Write-Host "                                 no address: this Space works from your cards alone -- a whole shape, not a missing step"
    Write-Host "    2. yours  sign in            gh auth login  /  az login  -- said and checked, never run for you"
    Write-Host "    3. ours   discovery          -Discover lists what the address holds; -Repo (GitHub) or -Projects (ADO) writes what you pick"
    Write-Host "    4. ours   sprint awareness   -Sprint true  (a GitHub Space has milestones, not sprints; Azure DevOps has iterations)"
    Write-Host "  With no step, it reports where the Space stands. -As <slug> graduates a shipped demo Space (the Azure demo) into your own Space."
    Write-Host ""
    if (-not $Slug -and -not $Help) { exit 2 }
    exit 0
}

# -- The Space -----------------------------------------------------------------
# The module's resolved list when the verb ran us; the files when run alone.
$spaces = @()
$activeSlug = ''
$hubRoot = ''
if ($global:P20Config -and $global:P20Config.Spaces) {
    $spaces = @($global:P20Config.Spaces)
    $activeSlug = [string]$global:P20Config.ActiveSpace
    $hubRoot = [string]$global:P20Config.PromptsRoot
}
else {
    $defaultCfg = ConvertTo-P20SpaceKeys (Get-Content (Join-Path $packageRoot 'config.default.json') -Raw | ConvertFrom-Json)
    $localPath = Join-Path $packageRoot 'config.local.json'
    $localCfg = $null
    if (-not (Get-Command Read-P20LocalConfigJson -ErrorAction SilentlyContinue)) { . (Join-Path $PSScriptRoot 'Write-ConfigParseWarning.ps1') }
    $localCfg = ConvertTo-P20SpaceKeys (Read-P20LocalConfigJson -Path $localPath)
    $spaces = @($defaultCfg.spaces)
    $root = ''
    if ($localCfg -and $localCfg.promptsRoot) { $root = [string]$localCfg.promptsRoot } elseif ($defaultCfg.promptsRoot) { $root = [string]$defaultCfg.promptsRoot }
    $hubRoot = Resolve-P20HubRoot -PromptsRoot $root -PackageRoot $packageRoot
    $manifest = Read-P20HubManifest -Root $hubRoot
    foreach ($hs in @(Rename-P20LegacyHubSpaces -Spaces @($manifest.Spaces) -ShippedSlugs @($spaces | ForEach-Object { [string]$_.slug }))) {
        $existing = $spaces | Where-Object { $_.slug -eq $hs.slug } | Select-Object -First 1
        if ($existing) { foreach ($p in $hs.PSObject.Properties) { $existing | Add-Member -NotePropertyName $p.Name -NotePropertyValue $p.Value -Force } }
        else { $spaces += $hs }
    }
    if ($localCfg -and $localCfg.spaces -and -not ($localCfg.spaces -is [System.Array])) {
        $knownSlugs = @($spaces | ForEach-Object { [string]$_.slug })
        foreach ($sp in $spaces) {
            foreach ($lp in $localCfg.spaces.PSObject.Properties) {
                if (($lp.Name -eq $sp.slug -or (Resolve-P20RenamedSlug -Slug $lp.Name -Slugs $knownSlugs) -eq $sp.slug) -and $lp.Value) {
                    foreach ($p in $lp.Value.PSObject.Properties) { $sp | Add-Member -NotePropertyName $p.Name -NotePropertyValue $p.Value -Force }
                }
            }
        }
    }
    # The environment's stand-in first, as the module and the agent read it.
    $activeSlug = Get-P20ActiveSpaceOverride
    if (-not $activeSlug) { if ($localCfg -and $localCfg.activeSpace) { $activeSlug = [string]$localCfg.activeSpace } elseif ($defaultCfg.activeSpace) { $activeSlug = [string]$defaultCfg.activeSpace } }
    $activeSlug = Resolve-P20RenamedSlug -Slug $activeSlug -Slugs @($spaces | ForEach-Object { [string]$_.slug })
}
# A renamed shipped Space's old slug (`test`, the Azure demo's before the rename) is
# accepted, read as the new one, and the new one is what every hint below names.
$renamedTo = Resolve-P20RenamedSlug -Slug $Slug -Slugs @($spaces | ForEach-Object { [string]$_.slug })
if ($renamedTo -ne $Slug) {
    if (-not $AsJson) { Write-Host "  $(Get-P20RenamedSlugNote -From $Slug -To $renamedTo)" -ForegroundColor Yellow }
    $Slug = $renamedTo
}
$space = $spaces | Where-Object { [string]$_.slug -eq $Slug } | Select-Object -First 1
if (-not $space) {
    $known = @($spaces | ForEach-Object { $_.slug }) -join ', '
    Write-CliError -Message "No Space '$Slug'. Spaces: $known." -Hint "Add one first: ${prefix}Config -Set spaces.$Slug.name=<name> -Hub"
    exit 2
}

$configScript = Join-Path $scriptsDir 'Set-ToolkitConfig.ps1'
# A SCRIPTBLOCK, not a function: the writer re-imports the module, which resets
# every function this script defined (AGENTS.md, "Traps worth knowing"); a
# variable survives, so `& $writeThroughConfig` works before and after.
$writeThroughConfig = {
    # The one writer, in-process: its refusal is ours, exit code and sentence.
    param([string[]]$Pairs, [switch]$Hub)
    if ($WhatIf) {
        foreach ($pair in $Pairs) { Write-Host "  [WhatIf] ${prefix}Config -Set $pair$(if ($Hub) { ' -Hub' })" -ForegroundColor Yellow }
        return
    }
    # A HASHTABLE splat: an array splat passes its elements positionally, so a
    # '-Hub' in an array would land as a value, not the switch.
    $splat = @{ Set = $Pairs }
    if ($Hub) { $splat.Hub = $true }
    $out = & $configScript @splat 2>&1 | Out-String
    if ($LASTEXITCODE -and $LASTEXITCODE -ne 0) { Write-Host $out; exit $LASTEXITCODE }
    if (-not $AsJson) { Write-Host $out.TrimEnd() }
}

# Not $address: PowerShell variable names are case-insensitive, and that IS the -Address parameter.
$spaceAddress = [string]$space.org
$did = @()

# -- 1. The address (yours), written (ours) -- and an address implies active (D-W14)
if ($PSBoundParameters.ContainsKey('Address')) {
    $addr = $Address.Trim()
    if ($addr -and $addr -notmatch '^https?://[^\s/]+') {
        Write-CliError -Message "'$addr' is not an address." -Hint 'https://github.com/<owner> or https://github.com/<owner>/<repo> for GitHub, https://dev.azure.com/<org> for Azure DevOps.'
        exit 2
    }
    $pairs = @("spaces.$Slug.org=$addr")
    if ($addr -and [string]$space.status -ne 'active') { $pairs += "spaces.$Slug.status=active" }
    & $writeThroughConfig -Pairs $pairs -Hub
    . $loadHelpers
    $spaceAddress = $addr
    $did += 'address'
}

$tracker = Resolve-P20Tracker -OrgUrl $spaceAddress

# -- 2. Sign in (yours): said and checked ------------------------------------
$signIn = Test-P20TrackerSignIn -Tracker $tracker

# -- 3. Discovery (ours) ------------------------------------------------------
$available = @()
if ($Discover) {
    if ($tracker -eq 'none') {
        Write-CliError -Message "Space '$Slug' has no address yet, so there is nothing to discover." -Hint "Step 1 first: ${prefix}Connect $Slug -Address <url>"
        exit 2
    }
    if (-not $signIn.Installed) {
        Write-CliError -Message "Discovery needs $($signIn.Tool), and it is not installed." -Hint "Install $($signIn.Tool), then $($signIn.Command), then ${prefix}Connect $Slug -Discover"
        exit 2
    }
    if (-not $signIn.SignedIn) {
        Write-CliError -Message "Discovery needs you signed in to $($signIn.Tool)." -Hint "Run $($signIn.Command) yourself -- the toolkit never signs in for you -- then ${prefix}Connect $Slug -Discover"
        exit 2
    }
    if ($tracker -eq 'github') {
        $owner = Get-P20TrackerOwner -OrgUrl $spaceAddress
        $rest = (($spaceAddress -replace '^[a-z][a-z0-9+.-]*://', '') -split '/')
        if ($rest.Count -ge 3 -and $rest[2]) {
            $available += [PSCustomObject]@{ name = $rest[2]; repo = "$owner/$($rest[2])" }
        }
        else {
            $listed = Invoke-P20TrackerRead 'gh' @('repo', 'list', $owner, '--json', 'name,defaultBranchRef', '--limit', '100')
            $json = $listed.Out
            if ($listed.Code -ne 0) { Write-CliError -Message "gh could not list $owner's repos." -Hint "Check the address and gh auth status."; exit 2 }
            # Into a variable first: Windows PowerShell 5.1's ConvertFrom-Json writes a JSON
            # array as ONE object, which @(...) around the pipe would wrap whole.
            $repoList = ($json | Out-String) | ConvertFrom-Json
            foreach ($r in @($repoList)) {
                $branch = ''
                if ($r.defaultBranchRef -and $r.defaultBranchRef.name) { $branch = [string]$r.defaultBranchRef.name }
                $available += [PSCustomObject]@{ name = [string]$r.name; repo = "$owner/$($r.name)"; defaultBranch = $branch }
            }
        }
    }
    else {
        $listed = Invoke-P20TrackerRead 'az' @('devops', 'project', 'list', '--organization', $spaceAddress, '--output', 'json')
        $json = $listed.Out
        if ($listed.Code -ne 0) { Write-CliError -Message "az could not list the projects at $spaceAddress." -Hint "Check the address, and that az login reached this organisation (az devops configure --defaults organization=$spaceAddress helps too)."; exit 2 }
        $parsed = ($json | Out-String) | ConvertFrom-Json
        foreach ($p in @($parsed.value)) {
            $repos = @()
            $repoRead = Invoke-P20TrackerRead 'az' @('repos', 'list', '--organization', $spaceAddress, '--project', [string]$p.name, '--output', 'json')
            if ($repoRead.Code -eq 0) {
                $repoRows = ($repoRead.Out | Out-String) | ConvertFrom-Json
                $repos = @(foreach ($rr in @($repoRows)) { [string]$rr.name })
            }
            $available += [PSCustomObject]@{ name = [string]$p.name; repos = $repos }
        }
    }
    $did += 'discover'
}

if ($PSBoundParameters.ContainsKey('Projects')) {
    if ($tracker -eq 'github') {
        Write-CliError -Message "A GitHub Space is one repo, not a list of projects (D-W17)." -Hint "Pick the repo: ${prefix}Connect $Slug -Repo <owner/name> -- it becomes the Space's address."
        exit 2
    }
    & $writeThroughConfig -Pairs @("spaces.$Slug.projects=$Projects") -Hub
    . $loadHelpers
    $did += 'projects'
}

if ($PSBoundParameters.ContainsKey('Repo')) {
    if ($tracker -ne 'github') {
        Write-CliError -Message "-Repo is for a GitHub Space; '$Slug' is $(if ($tracker -eq 'ado') { 'an Azure DevOps organisation -- pick its projects with -Projects' } else { 'not connected -- give it an address first' })."
        exit 2
    }
    $r = $Repo.Trim().TrimStart('/').TrimEnd('/')
    if ($r -notmatch '^[^/\s]+/[^/\s]+$') { Write-CliError -Message "'$Repo' is not owner/name." -Hint "For example johnfrog76/toolkit -- a row of ${prefix}Connect $Slug -Discover"; exit 2 }
    $spaceAddress = "https://github.com/$r"
    & $writeThroughConfig -Pairs @("spaces.$Slug.org=$spaceAddress") -Hub
    . $loadHelpers
    $did += 'repo'
}

# -- 4. Sprint awareness (ours to offer, yours to answer) --------------------
if ($PSBoundParameters.ContainsKey('Sprint')) {
    $flag = $Sprint.Trim().ToLowerInvariant()
    if ($flag -ne 'true' -and $flag -ne 'false') { Write-CliError -Message "-Sprint is true or false -- got '$Sprint'."; exit 2 }
    & $writeThroughConfig -Pairs @("spaces.$Slug.features.sprintAwareness=$flag") -Hub
    . $loadHelpers
    $did += 'sprint'
}

# -- Graduation (D-W15): the Example becomes yours -----------------------------
if ($As) {
    if (-not $space.example) {
        Write-CliError -Message "Space '$Slug' is not one of the shipped demo Spaces; only a demo Space graduates." -Hint "To rename another Space, add the new slug with ${prefix}Config -Set spaces.<new>.name=<name> -Hub and archive the old one."
        exit 2
    }
    if ($As -notmatch '^[a-z][a-z0-9-]*$') { Write-CliError -Message "'$As' is not a slug." -Hint 'Lowercase letters, digits and dashes, starting with a letter: acme, my-team.'; exit 2 }
    if ($spaces | Where-Object { [string]$_.slug -eq $As }) { Write-CliError -Message "There is already a Space '$As'."; exit 2 }
    $pairs = @("spaces.$As.promptsFolder=$As", "spaces.$As.name=$As", "spaces.$As.status=active")
    if ($spaceAddress) { $pairs += "spaces.$As.org=$spaceAddress" }
    if ($space.projects) { $pairs += "spaces.$As.projects=" + (ConvertTo-Json @($space.projects) -Compress -Depth 4) }
    if ($space.features -and $space.features.sprintAwareness) { $pairs += "spaces.$As.features.sprintAwareness=true" }
    & $writeThroughConfig -Pairs $pairs -Hub
    . $loadHelpers
    $oldFolder = Join-Path $hubRoot ([string]$space.promptsFolder)
    $newFolder = Join-Path $hubRoot $As
    if ((Test-Path $oldFolder) -and -not (Test-Path $newFolder)) {
        if ($WhatIf) { Write-Host "  [WhatIf] move $oldFolder -> $newFolder" -ForegroundColor Yellow }
        else { Move-Item -LiteralPath $oldFolder -Destination $newFolder }
    }
    & $writeThroughConfig -Pairs @("activeSpace=$As", 'isDemoDismissed=true')
    . $loadHelpers
    $did += 'graduate'
    $Slug = $As
    $activeSlug = $As
}

# -- The report ------------------------------------------------------------------
$configured = @()
if ($space.projects) { $configured = @($space.projects) }
if ($PSBoundParameters.ContainsKey('Projects') -and -not $WhatIf) {
    $configured = @()
    foreach ($piece in ($Projects -split ';')) { $p = $piece.Trim(); if ($p) { $parts = $p -split '/', 2; $e = [ordered]@{ name = $parts[0].Trim() }; if ($parts.Count -gt 1 -and $parts[1].Trim()) { $e.repo = $parts[1].Trim() }; $configured += [PSCustomObject]$e } }
}
$sprintOn = [bool]($space.features -and $space.features.sprintAwareness)
# Step 1 is done when the Space HAS an address and is connected to it. A Space can
# ship with an address and still be local -- the GitHub demo does, so a
# cold machine never reads it as unreachable -- and then the address is there but
# the step is not: saving it (the same -Address) is what makes it active.
$reportStatus = [string]$space.status
if ($did -contains 'address' -and $spaceAddress) { $reportStatus = 'active' }
$addressDone = [bool]$spaceAddress -and ($reportStatus -ne 'local')
if ($PSBoundParameters.ContainsKey('Sprint') -and -not $WhatIf) { $sprintOn = ($Sprint.Trim().ToLowerInvariant() -eq 'true') }
$report = [ordered]@{
    slug     = $Slug
    name     = [string]$space.name
    active   = ($activeSlug -eq $Slug)
    example  = [bool]$space.example
    address  = $spaceAddress
    tracker  = $tracker
    grain    = $(switch ($tracker) { 'ado' { 'an Azure DevOps organisation, projects inside it' } 'github' { $(if ((($spaceAddress -replace '^[a-z][a-z0-9+.-]*://', '') -split '/').Count -ge 3) { 'one GitHub repo' } else { 'a GitHub owner -- pick the one repo this Space is' }) } default { 'your cards alone -- no tracker' } })
    status   = $reportStatus
    steps    = [ordered]@{
        address  = [ordered]@{ done = $addressDone; yours = $true }
        signIn   = [ordered]@{ done = [bool]$signIn.SignedIn; yours = $true; tool = $signIn.Tool; installed = [bool]$signIn.Installed; identity = $signIn.Identity; command = $signIn.Command }
        projects = [ordered]@{ done = ($configured.Count -gt 0); yours = $false; configured = $configured; available = $available }
        sprint   = [ordered]@{ done = $sprintOn; yours = $false; on = $sprintOn }
    }
    did      = $did
    whatIf   = [bool]$WhatIf
}
if ($AsJson) {
    $report | ConvertTo-Json -Depth 8 -Compress
    exit 0
}

$mark = { param([bool]$done) if ($done) { '[x]' } else { '[ ]' } }
Write-Host ""
Write-Host "  Connect $Slug -- $($report.name)$(if ($report.active) { ' (active)' })" -ForegroundColor Cyan
$addressLine = "none -- $($report.grain); to connect: ${prefix}Connect $Slug -Address <url>"
if ($spaceAddress -and $addressDone) { $addressLine = "$spaceAddress -- $($report.grain)" }
elseif ($spaceAddress) { $addressLine = "$spaceAddress -- $($report.grain); local until you connect it: ${prefix}Connect $Slug -Address $spaceAddress (or your own)" }
Write-Host "  $(& $mark $report.steps.address.done) 1. address       $addressLine"
if ($tracker -eq 'none') { Write-Host "  [ ] 2. sign in       after the address" -ForegroundColor DarkGray }
elseif (-not $signIn.Installed) { Write-Host "  [ ] 2. sign in       $($signIn.Tool) is not installed -- install it, then $($signIn.Command)" -ForegroundColor Yellow }
elseif ($signIn.SignedIn) { Write-Host "  [x] 2. sign in       $($signIn.Tool)$(if ($signIn.Identity) { " as $($signIn.Identity)" })" }
else { Write-Host "  [ ] 2. sign in       run $($signIn.Command) yourself, then come back" -ForegroundColor Yellow }
if ($available.Count -gt 0) {
    Write-Host "      available:"
    foreach ($a in $available) { Write-Host "        $($a.name)$(if ($a.repo) { "  ($($a.repo))" } elseif ($a.repos) { "  repos: $($a.repos -join ', ')" })" -ForegroundColor Gray }
    if ($tracker -eq 'github') { Write-Host "      pick the one repo this Space is: ${prefix}Connect $Slug -Repo <owner/name>" -ForegroundColor DarkGray }
    else { Write-Host "      pick with: ${prefix}Connect $Slug -Projects 'Name/repo; Other/repo'" -ForegroundColor DarkGray }
}
Write-Host "  $(& $mark $report.steps.projects.done) 3. projects      $(if ($configured.Count -gt 0) { (@($configured | ForEach-Object { if ($_.repo) { "$($_.name)/$($_.repo)" } else { $_.name } }) -join '; ') } else { "none -- ${prefix}Connect $Slug -Discover" })"
Write-Host "  $(& $mark $report.steps.sprint.done) 4. sprint        $(if ($sprintOn) { 'on' } else { "off -- ${prefix}Connect $Slug -Sprint true" })"
Write-Host ""
exit 0
