#
# The inventory of OPT-IN surfaces -- what this product has beyond the ADO core,
# whether each one is on, and the config line that changes it.
#
# NOT a runnable verb: this file is DOT-SOURCED, by utilities.psm1 (for
# `Menu -All`) and by Scripts/Get-Environment.ps1 (for `Env`). Same reasoning as
# Scripts/Get-ConfigSchema.ps1 and Scripts/Get-Consts.ps1: there must be exactly
# one answer to "what is optional here", and every renderer has to reach the
# same one. A second list is how two lists drift.
#
# THE RULE THIS FILE SERVES (AGENTS.md, "Opt in by configuration"):
#
#   * The ADO core workflow is always on and has no flag.
#   * Every other surface is opt in, declared in configuration, and NAMED by the
#     CLI whether or not it is on -- a machine has to be able to tell you what
#     it is not doing.
#
# Naming a surface is not mounting it. A module that is off is still absent
# everywhere it matters -- no verb, no -Help, no bridge entry, no route, no nav
# entry, no card, no data. What this list adds is the one sentence that says the
# thing exists and which key turns it on.
#
# THREE STATES, and the difference between the last two is the whole point:
#
#   on              switched on, or a value is set
#   off             a flag that resolves false, or a setting whose value means
#                   off -- the default answered, and the answer was no
#   not configured  nothing has been set anywhere, and nothing defaults for it
#
# PowerShell 5.1 clean: no ternary, no null-coalescing, ASCII hyphens only.
#

# The one test for "was a hub configured" (Resolve-HubConfig.ps1), shared with Start and Env.
if (-not (Get-Command Get-P20ConfiguredHub -ErrorAction SilentlyContinue)) {
    . (Join-Path $PSScriptRoot 'Resolve-HubConfig.ps1')
}
if (-not (Get-Command Get-P20EngineerFeatureKeys -ErrorAction SilentlyContinue)) {
    . (Join-Path $PSScriptRoot 'Get-ConfigSchema.ps1')
}
if (-not (Get-Command Get-P20Consts -ErrorAction SilentlyContinue)) {
    . (Join-Path $PSScriptRoot 'Get-Consts.ps1')
}
# How do you want to work in this Space? -- the answer that gates Team Agile.
if (-not (Get-Command Resolve-P20HowIWork -ErrorAction SilentlyContinue)) {
    . (Join-Path $PSScriptRoot 'Resolve-HowIWork.ps1')
}
# The question each row answers, in the person's words (Config/settings-workflows.json).
if (-not (Get-Command Get-P20SettingsWorkflows -ErrorAction SilentlyContinue)) {
    . (Join-Path $PSScriptRoot 'Get-SettingsWorkflows.ps1')
}

function Get-P20SurfaceStates {
    <#
      The three states, spelled once. The renderers print these strings verbatim
      and the suites assert them, so they are a contract between this file and
      both.

      A FUNCTION rather than three $script: variables on purpose. This file is
      dot-sourced into utilities.psm1 AND read by scripts the module then runs
      as children of its own session state, where `$script:` resolves to the
      running script's scope rather than to the module's -- so the variables
      came back empty and every state rendered blank in `Env` while `Menu` was
      fine. A function carries its answer with it.

      That is one half of a trap that bit twice: AGENTS.md, "Traps worth
      knowing", "A `function global:` in utilities.psm1 cannot read module
      state through a `$script:` name". A function is the answer for a CONSTANT,
      as here; mutable state needs the closure-over-a-container idiom that
      $script:ModuleState carries in utilities.psm1, because a function cannot
      be redefined when the value changes.
    #>
    return [PSCustomObject]@{
        On    = 'on'
        Off   = 'off'
        Unset = 'not configured'
    }
}

function New-P20SurfaceRow {
    param(
        [string]$Key,
        [string]$Title,
        [string]$State,
        [string]$Config,
        [string]$Note = '',
        [string]$Question = ''
    )
    return [PSCustomObject]@{
        key      = $Key
        title    = $Title
        state    = $State
        config   = $Config
        note     = $Note
        question = $Question
    }
}

function Get-P20ModuleSurfaces {
    <#
      The modules that exist, read from the files that declare them --
      Config/<module>.commands.psd1's `Feature` key -- plus any engineer flag
      the schema knows that has no module file yet (deck is specified and not
      built). Enumerated, never listed by hand: a module added tomorrow appears
      here without this file being edited.

      Returns @{ Feature = <flag name>; Built = <bool> } per module.
    #>
    param([string]$PackageRoot)

    $found = @{}
    $configDir = Join-Path $PackageRoot 'Config'
    if (Test-Path $configDir) {
        foreach ($psd1 in (Get-ChildItem $configDir -Filter '*.commands.psd1' -File -ErrorAction SilentlyContinue)) {
            # Import-PowerShellDataFile and nothing else, the same reader the
            # module loader uses: a data file in Config/ must never run code.
            try { $data = Import-PowerShellDataFile -Path $psd1.FullName -ErrorAction Stop }
            catch { continue }
            if ($data -and $data.Feature) { $found[[string]$data.Feature] = $true }
        }
    }

    $rows = @()
    foreach ($name in $found.Keys) {
        $rows += @{ Feature = $name; Built = $true }
    }
    foreach ($name in (Get-P20EngineerFeatureKeys)) {
        if ($found.ContainsKey($name)) { continue }
        # A module may be built in the web UI and contribute no verbs at all --
        # the deck module is: a launcher card and a player, nothing for a
        # terminal to do. Its folder is the evidence, the way a commands file is
        # for the others; without this the report said "specified, not built"
        # about a module that was on the screen.
        $webModule = Join-Path (Join-Path (Join-Path (Join-Path $PackageRoot 'web') 'src') 'modules') $name
        if (Test-Path (Join-Path $webModule 'index.tsx')) {
            $rows += @{ Feature = $name; Built = $true; WebOnly = $true }
            continue
        }
        $rows += @{ Feature = $name; Built = $false }
    }
    return @($rows | Sort-Object { $_.Feature })
}

function Get-P20OptionalSurfaces {
    <#
      Every optional surface, in one array of rows: key, title, state, the
      config line that changes it, and a note where one is owed.

      -Config takes the merged config ($global:P20Config), -Features the
      resolved flags (Get-P20Features), -NavAliases the merged nav table
      (Get-P20NavAliases). All optional: with none of them the inventory is
      still complete, every row simply reads `not configured`, which is exactly
      what a machine with no config should say.
    #>
    [CmdletBinding()]
    param(
        $Config = $null,
        $Features = $null,
        $NavAliases = $null,
        [string]$Prefix = '',
        [string]$PackageRoot = ''
    )

    if (-not $PackageRoot) { $PackageRoot = (Split-Path $PSScriptRoot -Parent) }
    if (-not $Prefix) { $Prefix = (Resolve-P20ConfigPrefix -PackageRoot $PackageRoot) }

    $states = Get-P20SurfaceStates
    $rows = @()

    # -- The hub: where the cards live (D-W7) ---------------------------------
    # The first thing Setup checks and the one key Quick start sets. "Configured"
    # means someone SAID where it is -- PROMPTS_ROOT, or promptsRoot in a config
    # file -- never the package-parent fallback that exists on every machine
    # (AGENTS.md, "The hub resolved is not a hub was configured").
    $hubState = $states.Unset
    $hubNote = 'falls back to the folder above the package'
    $hubSaid = Get-P20ConfiguredHub -PackageRoot $PackageRoot
    if ($hubSaid) { $hubState = $states.On; $hubNote = $hubSaid }
    $rows += New-P20SurfaceRow -Key 'promptsRoot' -Title 'Your hub' -State $hubState `
        -Config "$($Prefix)Config -Set promptsRoot=<folder>" -Note $hubNote

    # -- The Spaces ------------------------------------------------------------
    # Always on -- a machine has at least the shipped Azure demo -- and named here
    # because "how do I add another" is a question with a setting behind it. The
    # line that answers it is NewSpace, which writes the spaces.<slug>.* keys
    # through Config -- the + on the Studio's Spaces card runs the same verb.
    $spaceCount = 0
    $spaceActive = ''
    if ($Config) {
        $spaceCount = @($Config.Spaces).Count
        if ($Config.ActiveSpace) { $spaceActive = [string]$Config.ActiveSpace }
    }
    $spaceNote = "$spaceCount declared"
    if ($spaceActive) { $spaceNote = "$spaceCount declared; you are in $spaceActive" }
    $spaceState = $states.On
    if ($spaceCount -eq 0) { $spaceState = $states.Unset; $spaceNote = '' }
    $rows += New-P20SurfaceRow -Key 'spaces' -Title 'Spaces' -State $spaceState `
        -Config "$($Prefix)NewSpace -Repo <owner/name>  (or: $($Prefix)NewSpace <slug>)" -Note $spaceNote

    # -- Navigation shortcuts --------------------------------------------------
    # The one surface whose state is a PATH rather than a flag: the three shipped
    # aliases carry empty paths on purpose, because a path is personal.
    $navExample = 'Home'
    $navConfigured = 0
    if ($NavAliases) {
        $names = @($NavAliases.Keys | Sort-Object)
        if ($names.Count -gt 0) { $navExample = $names[0] }
        foreach ($name in $names) {
            $entry = $NavAliases[$name]
            if ($entry -and -not [string]::IsNullOrWhiteSpace([string]$entry.path)) { $navConfigured++ }
        }
    }
    $navState = $states.Unset
    $navNote = ''
    if ($navConfigured -gt 0) {
        $navState = $states.On
        $navNote = "$navConfigured configured"
    }
    $rows += New-P20SurfaceRow -Key 'aliases' -Title 'Navigation shortcuts' -State $navState `
        -Config "$($Prefix)Config -Set aliases.$navExample.path=<path>" -Note $navNote

    # -- A Space's checkout on this machine ------------------------------------
    # The second surface whose state is a PATH: where a Space's own repository
    # is cloned here (spaceCheckouts.<slug>.path, config.local.json only). It is
    # the resolver's first candidate (Scripts/Resolve-SpaceCheckout.ps1), and
    # what lets the Design tab's rows move a product's designs. Named, not
    # validated, here: the Design tab says whether the folder is really a clone.
    $checkoutSlug = 'toolkit'
    if ($Config -and $Config.ActiveSpace) { $checkoutSlug = [string]$Config.ActiveSpace }
    $checkoutCount = 0
    $checkoutActive = ''
    if ($Config -and $Config.SpaceCheckouts) {
        foreach ($prop in @($Config.SpaceCheckouts.PSObject.Properties)) {
            $p = ''
            if ($prop.Value -and $prop.Value.PSObject.Properties['path']) { $p = [string]$prop.Value.path }
            if ([string]::IsNullOrWhiteSpace($p)) { continue }
            $checkoutCount++
            if ($prop.Name -eq $checkoutSlug) { $checkoutActive = $p }
        }
    }
    $checkoutState = $states.Unset
    $checkoutNote = ''
    if ($checkoutCount -gt 0) {
        $checkoutState = $states.On
        $checkoutNote = "$checkoutCount configured"
        if ($checkoutActive) { $checkoutNote += "; $checkoutSlug is at $checkoutActive" }
        else { $checkoutNote += "; none for $checkoutSlug" }
    }
    $rows += New-P20SurfaceRow -Key 'spaceCheckouts' -Title 'Space checkouts' -State $checkoutState `
        -Config "$($Prefix)Config -Set spaceCheckouts.$checkoutSlug.path=<folder>" -Note $checkoutNote

    # -- Azure DevOps ----------------------------------------------------------
    # Something you plug in. Its state is DERIVED (Scripts/Test-AdoEnabled.ps1):
    # features.ado if anyone set it, else the status of the org you are in AND
    # the tracker its address names (Scripts/Resolve-Tracker.ps1). So the note
    # says which of them answered -- "off" alone would read as a decision
    # somebody made, on a machine where nobody has decided anything, and "off"
    # on a connected GitHub Space has to name the tracker, not the status: the
    # Space IS active, and the GitHub row below is the one that says so.
    if (-not (Get-Command Test-P20AdoEnabled -ErrorAction SilentlyContinue)) {
        . (Join-Path $PSScriptRoot 'Test-AdoEnabled.ps1')
    }
    if (-not (Get-Command Resolve-P20Tracker -ErrorAction SilentlyContinue)) {
        . (Join-Path $PSScriptRoot 'Resolve-Tracker.ps1')
    }
    $adoFlag = $null
    if ($Features -and $Features.ContainsKey('ado')) { $adoFlag = $Features['ado'] }
    $adoOrgStatus = ''
    $adoTracker = 'none'
    $adoSlug = '<slug>'
    if ($Config) {
        $adoOrgStatus = [string]$Config.OrgStatus
        $adoTracker = Resolve-P20Tracker -OrgUrl ([string]$Config.Org)
        if ($Config.ActiveSpace) { $adoSlug = [string]$Config.ActiveSpace }
    }
    $adoState = $states.Off
    if (Test-P20AdoEnabled -OrgStatus $adoOrgStatus -Flag $adoFlag -Tracker $adoTracker) { $adoState = $states.On }
    $adoNote = "follows the org you are in: $adoSlug is '$adoOrgStatus'"
    if ($adoOrgStatus -eq 'active' -and $adoTracker -eq 'github') { $adoNote = "follows the org you are in: $adoSlug's tracker is GitHub" }
    elseif ($adoOrgStatus -eq 'active' -and $adoTracker -eq 'none') { $adoNote = "follows the org you are in: $adoSlug has no tracker address" }
    if (-not $adoOrgStatus) { $adoNote = 'follows the org you are in' }
    if ($null -ne $adoFlag) { $adoNote = 'set explicitly; unset it to follow the org you are in' }
    # The line is the one that CHANGES the state, so it depends on the state --
    # and on an active Space it is the flag alone, since the status is already
    # what the status line would set.
    $adoLine = "$($Prefix)Config -Set spaces.$adoSlug.status=active -Hub   (or features.ado=true)"
    if ($adoOrgStatus -eq 'active') { $adoLine = "$($Prefix)Config -Set features.ado=true" }
    if ($adoState -eq $states.On) { $adoLine = "$($Prefix)Config -Set features.ado=false" }
    $rows += New-P20SurfaceRow -Key 'features.ado' -Title 'Azure DevOps' -State $adoState `
        -Config $adoLine -Note $adoNote

    # -- GitHub issues ---------------------------------------------------
    # The other tracker a Space can be connected to, and formerly the one the
    # inventory never named. Its state is the honest one for "has anybody wired
    # GitHub up here": on when a declared Space's address is GitHub AND that Space
    # is active (connected); otherwise nothing has been set up -- the shipped
    # GitHub demo carries an address but is local until the wizard connects it --
    # so `not configured`, never `off`: nobody answered no. One rule for which
    # tracker an address names, Scripts/Resolve-Tracker.ps1.
    if (-not (Get-Command Resolve-P20Tracker -ErrorAction SilentlyContinue)) {
        . (Join-Path $PSScriptRoot 'Resolve-Tracker.ps1')
    }
    $ghConnected = @()
    $ghDeclared = @()
    if ($Config) {
        foreach ($sp in @($Config.Spaces)) {
            if (-not $sp) { continue }
            if ((Resolve-P20Tracker -OrgUrl ([string]$sp.org)) -ne 'github') { continue }
            $ghDeclared += [string]$sp.slug
            if ([string]$sp.status -eq 'active') { $ghConnected += [string]$sp.slug }
        }
    }
    $ghState = $states.Unset
    $ghNote = 'a GitHub Space is one repo; sign in with gh'
    $ghSlug = '<slug>'
    if ($ghDeclared.Count -gt 0) { $ghSlug = $ghDeclared[0]; $ghNote = "$($ghDeclared -join ', ') not connected yet; sign in with gh" }
    if ($ghConnected.Count -gt 0) { $ghState = $states.On; $ghNote = "connected: $($ghConnected -join ', ')" }
    $rows += New-P20SurfaceRow -Key 'tracker.github' -Title 'GitHub issues' -State $ghState `
        -Config "$($Prefix)Connect $ghSlug -Address https://github.com/<owner>/<repo>" -Note $ghNote

    # -- The opt-in modules ----------------------------------------------------
    foreach ($module in (Get-P20ModuleSurfaces -PackageRoot $PackageRoot)) {
        $flag = $module.Feature
        $moduleState = $states.Off
        if ($Features -and $Features.ContainsKey($flag) -and $Features[$flag]) { $moduleState = $states.On }
        $note = ''
        if (-not $module.Built) {
            $note = 'specified, not built'
            $moduleState = $states.Unset
        }
        elseif ($module.WebOnly) {
            $note = 'web UI only -- it adds no verbs'
        }
        # Team Agile is the module a Space's answer gates: "How do you
        # want to work in <Space>?" -- Scripts/Resolve-HowIWork.ps1. The switch,
        # features.solitaireAgile, is the person's; -Features arrives with the
        # gate already applied (Get-P20Features), so the row is on only where the
        # switch is on AND the active Space answered agents. Off says which:
        # derived from the tracker, or chosen; a GitHub Space nobody has
        # answered is `not configured`, and its default is alone.
        elseif ($flag -eq (Get-P20HowIWorkGatedFeature)) {
            $howSlug = '<slug>'
            $howOrg = ''
            $howStored = ''
            if ($Config -and $Config.ActiveSpace) {
                $howSlug = [string]$Config.ActiveSpace
                foreach ($sp in @($Config.Spaces)) {
                    if ($sp -and [string]$sp.slug -eq $howSlug) {
                        $howOrg = [string]$sp.org
                        if ($sp.PSObject.Properties['howIWork']) { $howStored = [string]$sp.howIWork }
                    }
                }
            }
            $how = Resolve-P20HowIWork -OrgUrl $howOrg -Stored $howStored
            $howLine = "$($Prefix)Config -Set spaces.$howSlug.howIWork=agents -Hub"
            if ($how.tracker -ne 'github') {
                $howLine = "$($Prefix)Connect $howSlug -Address https://github.com/<owner>/<repo>"
                if ($how.answer -eq 'team') { $note = "derived: on a team in Azure -- $howSlug's board holds the rituals" }
                else { $note = "derived: alone -- $howSlug has no tracker; connect one to work with agents" }
            }
            elseif ($how.source -eq 'default') {
                $moduleState = $states.Unset
                $note = "nobody has answered for $howSlug; alone until then"
            }
            elseif ($how.answer -eq 'alone') {
                $note = "chosen: alone in $howSlug"
            }
            elseif ($moduleState -eq $states.On) {
                $note = "chosen: with agents in $howSlug"
                $howLine = "$($Prefix)Config -Set spaces.$howSlug.howIWork=alone -Hub"
            }
            else {
                $note = "chosen: with agents in $howSlug, and the switch is off"
                $howLine = "$($Prefix)Config -Set features.$flag=true"
            }
        }
        # A flag is camelCase and its title is words -- organize is "Organize
        # module" -- unless the person's word for it differs from its id:
        # solitaireAgile is the engine's name and "Team Agile" is what the tab
        # says, so the title follows the tab.
        $titles = @{ solitaireAgile = 'Team Agile' }
        if ($titles.ContainsKey($flag)) { $words = $titles[$flag] }
        else { $words = $flag -creplace '([a-z0-9])([A-Z])', '$1 $2' }
        $title = ($words.Substring(0, 1).ToUpperInvariant() + $words.Substring(1)) + ' module'
        $line = "$($Prefix)Config -Set features.$flag=true"
        if ($flag -eq (Get-P20HowIWorkGatedFeature) -and $module.Built -and -not $module.WebOnly) { $line = $howLine }
        $rows += New-P20SurfaceRow -Key "features.$flag" -Title $title -State $moduleState `
            -Config $line -Note $note
    }

    # -- Sprint awareness: a Space-scoped flag (the other is howIWork) -----------
    $slug = '<slug>'
    if ($Config -and $Config.ActiveSpace) { $slug = [string]$Config.ActiveSpace }
    $sprintState = $states.Off
    if ($Features -and $Features.ContainsKey('sprintAwareness') -and $Features['sprintAwareness']) {
        $sprintState = $states.On
    }
    $rows += New-P20SurfaceRow -Key 'sprintAwareness' -Title 'Sprint awareness' -State $sprintState `
        -Config "$($Prefix)Config -Set spaces.$slug.features.sprintAwareness=true -Hub" `
        -Note "this org's board, not the engineer's"

    # -- The suggestion: Team Agile's next move, a Space-scoped switch ----------
    # spaces[].features.suggestions (Scripts/Suggest-Rules.ps1, Test-P20SuggestionsOn):
    # it rides Team Agile, so where Team Agile is off here the row says so and is
    # off; where it is on, unset is `not configured` -- on by default, nobody has
    # answered -- and a stored true or false is on or off.
    $sugSlug = '<slug>'
    $sugStored = $null
    if ($Config -and $Config.ActiveSpace) {
        $sugSlug = [string]$Config.ActiveSpace
        foreach ($sp in @($Config.Spaces)) {
            if ($sp -and [string]$sp.slug -eq $sugSlug -and $sp.features -and $sp.features.PSObject.Properties['suggestions'] -and $sp.features.suggestions -is [bool]) {
                $sugStored = [bool]$sp.features.suggestions
            }
        }
    }
    $sugTeamAgile = ($Features -and $Features.ContainsKey('solitaireAgile') -and $Features['solitaireAgile'])
    $sugState = $states.Off
    $sugNote = "rides Team Agile, which is off in $sugSlug"
    $sugLine = "$($Prefix)Config -Set spaces.$sugSlug.features.suggestions=true -Hub"
    if ($sugTeamAgile) {
        if ($null -eq $sugStored) {
            $sugState = $states.Unset
            $sugNote = "on by default where Team Agile is on; the chair's Next line in $sugSlug"
            $sugLine = "$($Prefix)Config -Set spaces.$sugSlug.features.suggestions=false -Hub"
        }
        elseif ($sugStored) {
            $sugState = $states.On
            $sugNote = "the chair's Next line in $sugSlug"
            $sugLine = "$($Prefix)Config -Set spaces.$sugSlug.features.suggestions=false -Hub"
        }
        else {
            $sugNote = "switched off in ${sugSlug}: the Next line is today's"
        }
    }
    $rows += New-P20SurfaceRow -Key 'suggestions' -Title 'Suggestions' -State $sugState -Config $sugLine -Note $sugNote

    # -- Training hours per quarter: a Space's requirement ---------------------
    # A NUMBER the Space states, not a flag, so its state is on (a requirement is
    # set) or not configured (none is) -- there is no answered "no" to respect.
    # Read off the active Space itself: the merged features map carries flags only.
    $trainingHours = 0
    if ($Config -and $Config.ActiveSpace) {
        foreach ($sp in @($Config.Spaces)) {
            if ($sp -and [string]$sp.slug -eq [string]$Config.ActiveSpace -and $sp.features -and $sp.features.PSObject.Properties['trainingHoursPerQuarter']) {
                $parsedHours = 0
                if ([int]::TryParse([string]$sp.features.trainingHoursPerQuarter, [ref]$parsedHours) -and $parsedHours -gt 0) { $trainingHours = $parsedHours }
            }
        }
    }
    $trainingState = $states.Unset
    $trainingNote = 'growth module; this Space''s rule, not the engineer''s'
    if ($trainingHours -gt 0) { $trainingState = $states.On; $trainingNote = "$trainingHours hours a quarter; growth module" }
    $rows += New-P20SurfaceRow -Key 'trainingHoursPerQuarter' -Title 'Training hours per quarter' -State $trainingState `
        -Config "$($Prefix)Config -Set spaces.$slug.features.trainingHoursPerQuarter=<hours> -Hub" -Note $trainingNote

    # -- The WIP limit: a number the machine states, never a gate ---------------
    # limits.inPlay: on with the number once set, `not configured` while it is
    # not -- nobody has answered "how many at once", and there is no answered no.
    # Status and the board's Active column SAY when the count passes it; nothing
    # refuses and nothing is hidden. Read off the merged config (InPlayLimit).
    $limitState = $states.Unset
    $limitNote = 'a line Status and the board say past the number; never a gate'
    if ($Config -and $null -ne $Config.InPlayLimit) {
        $limitState = $states.On
        $limitNote = "$($Config.InPlayLimit) cards in play; said past it, never enforced"
    }
    $rows += New-P20SurfaceRow -Key 'limits.inPlay' -Title 'WIP limit' -State $limitState `
        -Config "$($Prefix)Config -Set limits.inPlay=<number>" -Note $limitNote

    # -- The prompt store's git sync -------------------------------------------
    $syncState = $states.Off
    if ($Config -and [string]$Config.StoreSync -eq 'git') { $syncState = $states.On }
    $rows += New-P20SurfaceRow -Key 'storeSync' -Title 'Prompt store git sync' -State $syncState `
        -Config "$($Prefix)Config -Set storeSync=git" -Note 'the hub may declare it with -Hub'

    # -- Who "me" is -----------------------------------------------------------
    # Not a module, and it is here because a missing one renders as an empty
    # board rather than as a config gap.
    #
    $emailState = $states.Unset
    if ($Config -and -not [string]::IsNullOrWhiteSpace([string]$Config.Email)) { $emailState = $states.On }
    $rows += New-P20SurfaceRow -Key 'email' -Title 'ADO identity' -State $emailState `
        -Config "$($Prefix)Config -Set email=<you@example.com>" -Note 'who "me" is; falls back to az login'

    # -- The web half ----------------------------------------------------------
    # Opt in by starting it: the agent and the shell are a surface the CLI does
    # not need, and a machine that never runs them loses nothing.
    $port = 0
    if ($Config -and $Config.AgentPort) { $port = [int]$Config.AgentPort }
    $webNote = 'start it with ' + $Prefix + 'Web -Dev'
    $webState = $states.On
    if ($port -le 0) { $webState = $states.Unset }
    $rows += New-P20SurfaceRow -Key 'web' -Title 'Web UI and agent' -State $webState `
        -Config "$($Prefix)Config -Set web.agentPort=<port>" -Note $webNote

    # -- The design lifecycle (L2; docs/hub/design.md, "State -- derived, never stored")
    # DERIVED, from the repository you are standing in and from the hub: a
    # product declares by having design/ and stamping its files (D-DL10), so the
    # row reads the tree rather than a key. `on` when the repository's design/
    # exists and every file in the four folders is stamped; `off` with the
    # count when some are not (the structure is there and the answer is
    # incomplete); `not configured` when there is no design/ to read -- no
    # repository here, or one without the folder -- and when the folders hold
    # nothing but a README: a product that has not written its first note has
    # not answered, and `on` with `0 designs` would say it had. The hub's folders are read
    # the same way and said in the note, never a second state: the row is one.
    # One reader for the tree, Scripts/Read-DesignTree.ps1 -- the same one the
    # stamp and the agent's /api/design share through the states fixture.
    if (-not (Get-Command Read-P20DesignTree -ErrorAction SilentlyContinue)) {
        . (Join-Path $PSScriptRoot 'Read-DesignTree.ps1')
    }
    if (-not (Get-Command Get-P20HubFolder -ErrorAction SilentlyContinue)) {
        . (Join-Path $PSScriptRoot 'Resolve-HubConfig.ps1')
    }
    $designState = $states.Unset
    $designNote = 'no design/ in this repository'
    $designLine = "mkdir design; $($Prefix)StampDesign   (or -Hub for the hub's)"
    $repoTop = ''
    if (Get-Command git -ErrorAction SilentlyContinue) {
        try { $repoTop = "$(git rev-parse --show-toplevel 2>$null)".Trim() } catch { $repoTop = '' }
    }
    if ($repoTop -and (Test-Path -LiteralPath (Join-Path $repoTop 'design') -PathType Container)) {
        $tree = Read-P20DesignTree -DesignDir (Join-Path $repoTop 'design') -SpecDir (Join-Path $repoTop 'spec') -Base $repoTop
        $unstamped = @($tree.NotShown | Where-Object { $_.Reason -eq 'no id' }).Count
        if (@($tree.Designs).Count -eq 0 -and @($tree.NotShown).Count -eq 0) {
            $designNote = 'no designs in this repository yet'
        }
        elseif ($unstamped -eq 0) {
            $designState = $states.On
            $designNote = "$(@($tree.Designs).Count) designs in this repository"
            $designLine = "$($Prefix)StampDesign -WhatIf"
        }
        else {
            $designState = $states.Off
            $designNote = "$unstamped file$(if ($unstamped -ne 1) { 's' }) not stamped in this repository"
            $designLine = "$($Prefix)StampDesign"
        }
    }
    if ($Config -and $Config.PromptsRoot) {
        $hubDesign = Get-P20HubFolder -Name 'design' -PromptsRoot ([string]$Config.PromptsRoot) -PackageRoot $PackageRoot
        $hubSpec = Get-P20HubFolder -Name 'spec' -PromptsRoot ([string]$Config.PromptsRoot) -PackageRoot $PackageRoot
        if (Test-Path -LiteralPath $hubDesign -PathType Container) {
            $hubTree = Read-P20DesignTree -DesignDir $hubDesign -SpecDir $hubSpec -Base ([string]$Config.PromptsRoot)
            $hubUnstamped = @($hubTree.NotShown | Where-Object { $_.Reason -eq 'no id' }).Count
            if ($hubUnstamped -eq 0) { $designNote += "; the hub: $(@($hubTree.Designs).Count) designs" }
            else { $designNote += "; the hub: $hubUnstamped not stamped ($($Prefix)StampDesign -Hub)" }
        }
    }
    $rows += New-P20SurfaceRow -Key 'design' -Title 'Design lifecycle' -State $designState `
        -Config $designLine -Note $designNote

    # -- The two environment-variable gates ------------------------------------
    # Neither is config: a key and a webhook are secrets, and a secret does not
    # go in a file this tool writes.
    $aiState = $states.Unset
    if ($env:ANTHROPIC_API_KEY -and $env:ANTHROPIC_API_KEY.Trim()) { $aiState = $states.On }
    $rows += New-P20SurfaceRow -Key 'ANTHROPIC_API_KEY' -Title 'AI code review' -State $aiState `
        -Config 'ANTHROPIC_API_KEY in the environment; the model is ai.model in config' -Note "$($Prefix)AddPRReview, Suggest a reply on a PR Comments page, the notes tidy-up, and Team Agile's dressed standup"

    $webhooks = @(Get-ChildItem Env: -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -like 'TEAMS_WEBHOOK_*' -and $_.Value -and $_.Value.Trim() })
    $hookState = $states.Unset
    $hookNote = 'gate 2 of a Teams send'
    if ($webhooks.Count -gt 0) {
        $hookState = $states.On
        $hookNote = "$($webhooks.Count) set -- gate 2 of a Teams send"
    }
    $rows += New-P20SurfaceRow -Key 'TEAMS_WEBHOOK_*' -Title 'Teams delivery' -State $hookState `
        -Config 'TEAMS_WEBHOOK_<RECIPIENT> in .env in the package root (copy .env.example)' -Note $hookNote

    # -- StartWork -Launch (D-AR13; docs/modules/solitaire-agile.md) -----------
    # DERIVED, like the webhook row: `on` where the tool is found on the PATH,
    # `not configured` otherwise -- never `off`, because nothing was answered.
    # The block works either way; the Team Agile page shows its second button
    # only when /env's launch flag says the same (agent/core/config.py,
    # start_work_launch -- the agent's PATH, which is the bridge's). The row's
    # key IS that flag's name: consts.json startWork.launchEnvFlag.
    $launchState = $states.Unset
    $launchNote = $Prefix + 'StartWork <id> -Launch: a session in a worktree; the block works without it'
    if (Get-Command claude -CommandType Application -ErrorAction SilentlyContinue) { $launchState = $states.On }
    $rows += New-P20SurfaceRow -Key (Get-P20Consts).startWork.launchEnvFlag -Title 'StartWork launch' -State $launchState `
        -Config 'claude on the PATH (install Claude Code)' -Note $launchNote

    # The question on every row, from the one list (D-W1). A row with no entry
    # carries '' and tkTestToolkit -Environment fails naming the key.
    # A question may name the Space you are in -- {space} -- ("How do you
    # want to work in <Space>?"); with no Space known it reads "this Space".
    $spaceWords = 'this Space'
    if ($Config -and $Config.ActiveOrgName) { $spaceWords = [string]$Config.ActiveOrgName }
    foreach ($row in $rows) { $row.question = (Get-P20SurfaceQuestion -Key $row.key -PackageRoot $PackageRoot).Replace('{space}', $spaceWords) }
    return @($rows)
}
