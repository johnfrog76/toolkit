# -- Platform helpers ----------------------------------------------------------
function script:Get-IsWindows {
    return ($PSVersionTable.PSEdition -eq 'Desktop') -or $IsWindows
}

function script:Get-MachineName {
    return [System.Environment]::MachineName
}

# -- Logging -------------------------------------------------------------------

# Where usage.{machine}.log is read and written. The repo root, unless
# P20_USAGE_LOG_DIR names somewhere else.
#
# ONE OVERRIDE, READ BY BOTH HALVES -- agent/core/log_writer.py reads the same
# variable. It exists for test runs: every suite and every pytest file used to
# append to the engineer's real log, so the web UI's Log card showed nine test
# assertions among its ten errors and `tkLog -Errors` stopped being a
# diagnostic on exactly the machines that run the tests.
#
#
# It is a DIRECTORY, not a file: every reader on both sides globs usage.*.log
# to merge machines, so redirecting the writer alone would leave the readers
# pointed at the real log. Unset means the repo root, exactly as before.
#
# test-results.{machine}.log deliberately does NOT follow it. The Health card
# reading real test results is the point of that file.
# Global, so Setup (a script the module launches) can ask where the log goes
# and prove it writable (Setup's C8) instead of retyping the rule.
function global:Get-P20ToolkitLogDir {
    $override = $env:P20_USAGE_LOG_DIR
    if ($override -and $override.Trim()) { return $override.Trim() }
    return $PSScriptRoot
}

function global:Write-ToolkitLog {
    param(
        [Parameter(Mandatory)][ValidateSet('CMD', 'ERR', 'WARN', 'INFO')][string]$Type,
        [Parameter(Mandatory)][string]$Source,
        [Parameter(Mandatory)][string]$Detail
    )
    $timestamp = (Get-Date -Format 'yyyy-MM-ddTHH:mm:ss')
    $machine = Get-MachineName
    # One entry is one line of tab-separated columns: a tab, a line break or any
    # other character the readers split a line on becomes a single space, so a
    # value cannot forge a second entry or shift the columns.
    $lineBreaks = '[\t\r\n\x0b\x0c\x1c-\x1e\x85\u2028\u2029]'
    $safeSource = ($Source -replace $lineBreaks, ' ')
    $safeDetail = ($Detail -replace $lineBreaks, ' ')
    $entry = "$timestamp`t$Type`t$machine`t$safeSource`t$safeDetail"
    $logPath = Join-Path (Get-P20ToolkitLogDir) "usage.$machine.log"
    try {
        [System.IO.File]::AppendAllText($logPath, "$entry`n", (New-Object System.Text.UTF8Encoding $false))
    }
    catch {
        Write-Warning "Failed to write to usage.$machine.log: $_"
    }
}

function global:Write-P20TestResult {
    param(
        [Parameter(Mandatory)][string]$Suite,
        [Parameter(Mandatory)][ValidateSet('pass', 'fail', 'warn')][string]$Result,
        [Parameter(Mandatory)][int]$Passed,
        [Parameter(Mandatory)][int]$Total,
        [string]$Detail = 'ok',
        [string]$Org = ''
    )
    $timestamp = (Get-Date -Format 'yyyy-MM-ddTHH:mm:ss')
    $machine = Get-MachineName
    # Detail is a non-terminal tab-delimited column (org follows it); a tab or a
    # line break would bleed into the org field or forge a second result line.
    $safeDetail = ($Detail -replace '[\t\r\n\x0b\x0c\x1c-\x1e\x85\u2028\u2029]', ' ')
    $entry = "$timestamp`t$Suite`t$Result`t$Passed`t$Total`t$safeDetail`t$Org"
    $logPath = Join-Path $PSScriptRoot "test-results.$machine.log"
    # A byte-level append, as Write-ToolkitLog's: under Windows PowerShell 5.1,
    # Add-Content -Encoding UTF8 on a file something still holds for a moment (a
    # scanner, the write just before this one) throws "Stream was not readable",
    # and the line was lost behind the warning below. UTF-8 with no BOM, and the
    # host's line ending, as Add-Content wrote it; every reader takes either.
    try {
        [System.IO.File]::AppendAllText($logPath, $entry + [Environment]::NewLine, (New-Object System.Text.UTF8Encoding $false))
    }
    catch {
        Write-Warning "Failed to write to test-results.$machine.log: $_"
    }
}

# -- Load config --------------------------------------------------------------
$toolkitRoot = $PSScriptRoot

# Windows PowerShell 5.1 negotiates with whatever [Net.ServicePointManager]
# offers, and an unpatched or policy-restricted machine still leads with TLS
# 1.0/1.1. dev.azure.com, the Anthropic API and Teams webhooks all require 1.2,
# so it is OR-ed in here, once, at import -- never assigned, so a stronger
# protocol a policy already enabled is kept. PowerShell 7 uses the OS default
# and needs nothing.
if ($PSVersionTable.PSEdition -eq 'Desktop') {
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
}

# Load .env if present (gitignored -- never committed). ONE location: the
# package root, beside this file -- the only one .gitignore can protect.
#
# It used to read the directory ABOVE the package first, a habit from when this
# module sat in a subfolder of a larger repo. For this package the parent is
# whatever folder the clone happens to be in (`~/Repos/`, `C:\ws\`), so a stray
# .env belonging to something else was read into the process environment of
# every verb.
#
# NOT during a test run. The runners strip every TEAMS_WEBHOOK_* by pattern and
# set the run marker; every suite then imports this module, and reading .env
# here put the webhooks straight back -- on the one machine that has them, the
# one that sends.
# While the marker is set, .env is not read at all: no
# suite reads a value from it, and none should see a key it holds.
. (Join-Path $toolkitRoot 'Scripts/Get-Consts.ps1')
$dotEnvSkip = [bool][System.Environment]::GetEnvironmentVariable((Get-P20Consts).env.testRunMarker)
foreach ($dotEnvPath in @(
    (Join-Path $toolkitRoot '.env')
)) {
    if ($dotEnvSkip) { break }
    if (-not (Test-Path $dotEnvPath)) { continue }
    Get-Content $dotEnvPath | Where-Object { $_ -match '^\s*[^#]\S+=.+' } | ForEach-Object {
        $parts = $_ -split '=', 2
        $key   = $parts[0].Trim()
        $value = $parts[1].Trim().Trim('"').Trim("'")
        [System.Environment]::SetEnvironmentVariable($key, $value, 'Process')
    }
}

# -- Module state a global function is allowed to read -------------------------
# ONE MUTABLE CONTAINER, and the accessors below close over it.
#
# This module defines its verbs as `function global:`. A global function
# defined by a module runs in the module's session state -- until it is reached
# from a SCRIPT THE MODULE ITSELF LAUNCHED (Get-P20Environment does exactly
# that: `& "$toolkitRoot\Scripts\Get-Environment.ps1"`, and the script then
# calls Get-P20NavAliases / Get-P20Features). In that shape the dynamic scope
# chain is function -> the script's own scope -> module scope, so `$script:X`
# binds to the NEAREST script scope, which is the running .ps1's, and comes
# back $null. That is how `Env` reported three configured nav shortcuts as
# `not configured` and an org with sprintAwareness true as `off`, while
# `Menu -All` on the same data in the same session was right.
#
#
# A closure over THIS HASHTABLE is the fix that holds in both call shapes: the
# accessor carries the container reference with it, and because a hashtable is
# a reference type, a later write through $script:ModuleState is visible to
# every accessor. AGENTS.md, "Traps worth knowing", has the five idioms that
# look like they should work and do not.
#
# What goes in here: state that a global function must read AND that changes
# after the module body has run, or is assembled by the module body at all.
# A constant belongs in a function (Get-P20SurfaceStates is the precedent);
# something already exported belongs there (Get-CliPrefix reads
# $global:P20Config first for the same reason).
$script:ModuleState = @{
    NavAliases        = $null   # merged, bare-keyed nav table (built ~line 440)
    SpaceScopedFeatures = @()     # flags a Space may set, not the engineer
    DefaultFeatures   = $null   # config.default.json's `features` block
    LocalFeatures     = $null   # config.local.json's `features` block
    ActiveSpaceFeatures = $null   # the active Space's `features` block
    HowIWork          = $null   # the active Space's answer (Resolve-P20HowIWork)
    HowIWorkGate      = $null   # Invoke-P20HowIWorkGate, as a scriptblock
    CommandPrefix     = ''      # the registered prefix, 'tk' by default
    ResolvedIdentity  = $null   # Resolve-P20Identity's lazy cache
    PackageRoot       = ''      # where this module lives; set right below
    # The audit: every module variable a `function global:`
    # body used to read through `$script:` lives here now, so the five that
    # read them are closures over this one table like the accessors above.
    # Assigned further down, where each used to be; read as `$s.<Key>`.
    Config                = $null   # the resolved runtime config (also exported as $global:P20Config)
    SkipNavAliases        = $false  # PROMPTS_TOOLKIT_NO_NAV_ALIASES=1
    Commands              = $null   # name -> help entry, the merged command table
    AdoCommands           = @()     # the verbs that need a tracker
    DeprecatedAliases     = $null   # old name -> new name, hinted once
    ShownDeprecationHints = $null   # the hints already printed this session
    CommandMap            = $null   # verb -> function, the bridge's table
    ModuleCommandsLoaded  = $null   # module -> the verbs its data file contributed
    ConfigWatch           = @()     # the files this import's config was read from
    ConfigStamp           = ''      # their write times at import; Update-P20StaleConfig compares
}
$script:ModuleState.PackageRoot = $toolkitRoot

$defaultConfig = Get-Content (Join-Path $toolkitRoot 'config.default.json') -Raw | ConvertFrom-Json
$localConfigPath = Join-Path $toolkitRoot 'config.local.json'
# The one warning for a config.local.json that will not parse, said once per
# process; the readers below and in Scripts/ call it too.
. (Join-Path $toolkitRoot 'Scripts/Write-ConfigParseWarning.ps1')

if (Test-Path $localConfigPath) {
    try {
        $localConfig = Get-Content $localConfigPath -Raw | ConvertFrom-Json
    }
    catch {
        $msg = $_.Exception.Message
        if (Write-P20ConfigParseWarning -Path $localConfigPath -Message $msg) {
            Write-ToolkitLog -Type ERR -Source 'utilities.psm1' -Detail "config.local.json parse failed: $msg"
        }
        $localConfig = $null
    }
}
else {
    $localConfig = $null
    # The first thing a fresh clone prints, so it says one thing: not set up
    # yet, and the verb that sets it up. It used to be a WARNING and six lines
    # on writing the sparse patch by hand, with a dev.azure.com example -- the
    # opening screen of a first run that needs no account, telling the reader
    # to go and get one, one command before Start writes the file itself.
    #Nothing is wrong yet, so it is not a warning. How to write
    # the file by hand is docs/CONFIGURATION.md's; it is a SPARSE PATCH, never
    # "copy config.default.json" (a private copy of the whole shipped table
    # stops tracking the committed one the moment either changes).
    $firstRunPrefix = 'tk'
    if ($defaultConfig -and $defaultConfig.commandPrefix) { $firstRunPrefix = [string]$defaultConfig.commandPrefix }
    # A non-interactive caller (the agent's bridge) marks itself with
    # TOOLKIT_QUIET_STARTUP, and what it returns is the verb's own sentence, so
    # the banner stays out of it -- the same marker the startup banner honours.
    if (-not $env:TOOLKIT_QUIET_STARTUP) {
        Write-Host "  This machine is not set up yet -- no config.local.json, so the shipped defaults are in use." -ForegroundColor Yellow
        Write-Host "  Run ${firstRunPrefix}Start for a sample hub that works with no account, or see docs/CONFIGURATION.md to point it at your own." -ForegroundColor Gray
    }
}

# Merge helper: local overrides default for simple properties
function script:Merge-ConfigValue($default, $local) {
    if ($null -ne $local -and $local -ne '') { return $local }
    return $default
}

# Merge helper: recursively apply a per-machine org patch onto a default org.
# Nested objects merge key-by-key, so a patch that sets one field inside a map
# (e.g. features.communication) keeps the default's siblings (e.g.
# features.sprintAwareness) instead of clobbering the whole map. Scalars and
# arrays replace. MUST mirror agent._deep_merge -- Test-ConfigMerge.ps1 asserts
# the two loaders agree.
function script:Merge-SpacePatch($target, $patch) {
    foreach ($prop in $patch.PSObject.Properties) {
        $name = $prop.Name
        $patchVal = $prop.Value
        $existing = $target.PSObject.Properties[$name]
        if ($null -ne $existing -and ($existing.Value -is [System.Management.Automation.PSCustomObject]) -and ($patchVal -is [System.Management.Automation.PSCustomObject])) {
            Merge-SpacePatch $existing.Value $patchVal
        }
        else {
            $target | Add-Member -NotePropertyName $name -NotePropertyValue $patchVal -Force
        }
    }
}

# Feature flags that belong to an ORG rather than to the engineer. Declared here
# because the hub manifest reader below has to tell one from the other; the long
# explanation is in the feature-flag section further down, with Get-P20Features.
$script:ModuleState.SpaceScopedFeatures = @(& { . (Join-Path $toolkitRoot 'Scripts/Get-Consts.ps1'); (Get-P20Consts).features.spaceScoped })  # the contract's list (consts.json features.orgScoped), read by the agent too

# The hub's own manifest, <promptsRoot>/hub.json. One implementation, in a file
# the standalone scripts can dot-source too -- see Scripts/Resolve-HubConfig.ps1
# for the rules it enforces and why a hub declares orgs at all.
. (Join-Path $toolkitRoot 'Scripts/Resolve-HubConfig.ps1')

# The container's keys are read in BOTH spellings (stage 2): `spaces` and
# `activeSpace` are the product's, `orgs` and `activeOrg` the older ones every
# file still carries. Canonicalised here, once, so the merge below reads one
# name; the writer still writes the old spelling until the next step.
$defaultConfig = ConvertTo-P20SpaceKeys $defaultConfig
$localConfig = ConvertTo-P20SpaceKeys $localConfig

# The contract file, consts.json -- the literals all three halves parse. Loaded
# once here beside the config merge, and dot-sourceable by a standalone script
# through the same file (AGENTS.md, "One place for magic strings").
. (Join-Path $toolkitRoot 'Scripts/Get-Consts.ps1')
$script:Consts = Get-P20Consts

# The shipped default prefix, in the one place that holds it. This module used
# to carry its own 'tk' literal beside Register-PromptAlias, 1300 lines below
# the nav loop that also needed the answer.
. (Join-Path $toolkitRoot 'Scripts/Resolve-CliPrefix.ps1')

# The inventory of opt-in surfaces -- what exists beyond the ADO core, and
# whether each one is on. `Menu -All` and `Env` both render it and neither owns
# it (AGENTS.md, "Opt in by configuration").
. (Join-Path $toolkitRoot 'Scripts/Get-OptionalSurfaces.ps1')
# Whether Azure DevOps is part of what this machine SHOWS -- one rule, in a file of
# its own so Menu, Setup, Env and a test all reach the same one
# (docs/modules/ado.md, "The switch, and its scope").
. (Join-Path $toolkitRoot 'Scripts/Test-AdoEnabled.ps1')
# WHICH tracker the active Space's address names: the rule above reads it, and
# so does Menu, which lists the tracker verbs wherever there is a tracker.
. (Join-Path $toolkitRoot 'Scripts/Resolve-Tracker.ps1')
# How do you want to work in this Space? -- the answer, derived from the
# tracker its address names and asked only on GitHub, and the gate it puts on
# Team Agile's switch. One rule, shared with the agent through a fixture.
. (Join-Path $toolkitRoot 'Scripts/Resolve-HowIWork.ps1')

# Resolve active org from orgs array
$spaces = @()
if ($defaultConfig.spaces) { $spaces = @($defaultConfig.spaces) }

# The hub declares its own orgs, and they land BETWEEN the two config files.
# config.default.json is the team's shipped list, hub.json is the engineer's
# (a private org must never reach the committed file), config.local.json is this
# machine's last word on either. Merging by slug means a hub entry either
# deep-merges over a shipped org or is appended as a new one.
# MUST mirror load_config in agent/core/config.py.
$hubPromptsRoot = ''
if ($localConfig -and $localConfig.promptsRoot) { $hubPromptsRoot = [string]$localConfig.promptsRoot }
elseif ($defaultConfig.promptsRoot) { $hubPromptsRoot = [string]$defaultConfig.promptsRoot }
$script:HubRoot = Resolve-P20HubRoot -PromptsRoot $hubPromptsRoot -PackageRoot $s.PackageRoot
# Checked ONCE, here, before anything joins a path onto it. A configured hub on
# a drive that is not mapped (an unplugged disk, a `subst` that has not run, a
# typo) used to be met with a stack trace from Join-Path, a null Test-Path under
# it, and a hub.json warning that blamed the file -- three error records and one
# of them wrong about the cause. It gets one sentence now, and every hub-reading
# verb refuses with the same one.
$script:HubMissing = ($script:HubRoot -and -not (Test-P20HubRoot $script:HubRoot))
if ($script:HubMissing) {
    Write-Warning (Get-P20HubMissingMessage $script:HubRoot)
}
$script:HubManifest = Read-P20HubManifest `
    -Root $script:HubRoot `
    -SpaceScopedFeatures $script:ModuleState.SpaceScopedFeatures
# A nameless entry under a renamed shipped Space's old slug is a patch on the
# new one (Rename-P20LegacyHubSpaces in Scripts/Resolve-HubConfig.ps1).
$script:HubManifest.Spaces = @(Rename-P20LegacyHubSpaces -Spaces @($script:HubManifest.Spaces) -ShippedSlugs @($spaces | ForEach-Object { [string]$_.slug }))
foreach ($hubSpace in @($script:HubManifest.Spaces)) {
    $existing = $spaces | Where-Object { $_.slug -eq $hubSpace.slug } | Select-Object -First 1
    if ($existing) { Merge-SpacePatch $existing $hubSpace }
    else { $spaces += $hubSpace }
}

# Apply per-machine org overrides: config.local.json may carry sparse patches
# keyed by slug (e.g. orgs.acme.status = "local") - see docs/CONFIGURATION.md, "The hub declares its orgs".
if ($localConfig.spaces) {
    # The two files hold `spaces` in two different shapes ON PURPOSE:
    # config.default.json's is an ARRAY (the list of Spaces, each carrying its own
    # slug); config.local.json's is an OBJECT keyed by slug (a sparse patch onto
    # one of them). A reader who mirrors the shipped file writes the array form,
    # which matches nothing here -- and used to do so in silence, on the one key
    # that decides which ADO org every command scopes to.
    if ($localConfig.spaces -is [System.Array]) {
        Write-Warning "config.local.json: 'spaces' is an array, so nothing in it was applied. Patch spaces as an object keyed by slug -- { `"spaces`": { `"<slug>`": { `"status`": `"local`" } } } -- not as a list of entries carrying 'slug'. config.default.json's array is the list of Spaces; the local file patches it by slug. See docs/CONFIGURATION.md."
        Write-ToolkitLog -Type ERR -Source 'utilities.psm1' -Detail "config.local.json spaces is an array; expected an object keyed by slug"
    }
    else {
        # A patch under a renamed Space's OLD slug lands first, then one under
        # its new slug, which has the last word (Resolve-P20RenamedSlug).
        $knownSlugs = @($spaces | ForEach-Object { [string]$_.slug })
        foreach ($o in $spaces) {
            foreach ($lp in $localConfig.spaces.PSObject.Properties) {
                if ($lp.Name -ne $o.slug -and (Resolve-P20RenamedSlug -Slug $lp.Name -Slugs $knownSlugs) -eq $o.slug -and $lp.Value) {
                    Merge-SpacePatch $o $lp.Value
                }
            }
            $patch = $localConfig.spaces.($o.slug)
            if ($patch) {
                Merge-SpacePatch $o $patch
            }
        }
    }
}

# Validate status values - unknown status must never reach Tier 1.
# docs/CLI.md, "Tiers: what works without ADO"; fail-closed to 'local'.
$validStatuses = @('active', 'local', 'archive')
foreach ($o in $spaces) {
    if ($o.status -and ($validStatuses -notcontains $o.status)) {
        Write-Warning "Space '$($o.slug)': unknown status '$($o.status)' -- treating as 'local' (fail-closed)"
        $o.status = 'local'
    }
}

# The environment may stand in for two of config.local.json's keys for this
# process -- activeSpace and the top-level features block -- which is how
# `Web -Dev -Fixture` starts servers (and their bridge children) against the
# fixture hub without writing the machine's file. Get-P20ActiveSpaceOverride
# and Get-P20FeaturesOverride in Scripts/Resolve-HubConfig.ps1; MUST mirror
# load_config in agent/core/config.py.
$activeSlugOverride = Get-P20ActiveSpaceOverride
$featuresOverride = Get-P20FeaturesOverride
$activeSlug = if ($activeSlugOverride) { $activeSlugOverride } elseif ($localConfig.activeSpace) { $localConfig.activeSpace } elseif ($defaultConfig.activeSpace) { $defaultConfig.activeSpace } else { '' }
# An activeSpace still naming a renamed Space's old slug is the new one.
$activeSlug = Resolve-P20RenamedSlug -Slug ([string]$activeSlug) -Slugs @($spaces | ForEach-Object { [string]$_.slug })
$activeSpace = $spaces | Where-Object { $_.slug -eq $activeSlug } | Select-Object -First 1
if (-not $activeSpace -and $spaces.Count -gt 0) {
    # R4: archive orgs are selectable - include them in fallback
    $activeSpace = $spaces | Where-Object { $_.status -eq 'active' -or $_.status -eq 'local' -or $_.status -eq 'archive' } | Select-Object -First 1
    if (-not $activeSpace) { $activeSpace = $spaces[0] }
}

# The three inputs Get-P20Features merges, parked in the container. That
# function is `global:` and is called from Scripts/Get-Environment.ps1 while the
# module is running it, where an unqualified $defaultConfig / $localConfig /
# $activeSpace walks up the scope chain and finds whatever the running script
# happens to have named -- it worked only for as long as no script defined one.
$script:ModuleState.DefaultFeatures = $null
if ($defaultConfig) { $script:ModuleState.DefaultFeatures = $defaultConfig.features }
$script:ModuleState.LocalFeatures = $null
if ($localConfig) { $script:ModuleState.LocalFeatures = $localConfig.features }
# The environment's block REPLACES the file's, it does not patch it: {} is "no
# flag set", which a patch could not say.
if ($null -ne $featuresOverride) { $script:ModuleState.LocalFeatures = $featuresOverride }
$script:ModuleState.ActiveSpaceFeatures = $null
if ($activeSpace) { $script:ModuleState.ActiveSpaceFeatures = $activeSpace.features }
# The active Space's answer to How do you want to work here?, and the gate
# it puts on Team Agile's switch -- held as the function's SCRIPTBLOCK, so the
# closure below runs the one rule in this module's session state rather than
# looking a module-private name up from a dynamic module it cannot see.
$script:ModuleState.HowIWork = $null
if ($activeSpace) { $script:ModuleState.HowIWork = Resolve-P20HowIWork -OrgUrl ([string]$activeSpace.org) -Stored ([string]$activeSpace.howIWork) }
else { $script:ModuleState.HowIWork = Resolve-P20HowIWork -OrgUrl '' -Stored '' }
$script:ModuleState.HowIWorkGate = ${function:Invoke-P20HowIWorkGate}

$script:ModuleState.Config = @{
    Org           = if ($activeSpace) { $activeSpace.org } else { '' }
    Tenant        = if ($activeSpace) { $activeSpace.tenant } else { '' }
    OrgStatus     = if ($activeSpace) { $activeSpace.status } else { '' }
    Email         = Merge-ConfigValue $defaultConfig.email         ($localConfig.email)
    WsRoot        = Merge-ConfigValue $defaultConfig.wsRoot        ($localConfig.wsRoot)
    # NOT a straight merge of the two files: PROMPTS_ROOT in the environment is
    # an explicit override and WINS, which is what the docs have always said and
    # what agent/core/config.py's hub_root() has always done. This value used to
    # ignore it, so the agent and the module disagreed about which hub they were
    # looking at under the same environment. $script:HubRoot above is
    # Resolve-P20HubRoot's answer -- env first, then config, ~ expanded, a
    # relative path read against the package -- and it is the ONE answer every
    # script reads through $global:P20Config.PromptsRoot or Get-P20PromptsRoot.
    #
    PromptsRoot   = $script:HubRoot
    CommandPrefix = Merge-ConfigValue $defaultConfig.commandPrefix ($localConfig.commandPrefix)
    # 'git' or 'none'. The tool maintains files in a directory; what keeps that
    # directory safe is the user's business, and nothing is ever read back from
    # git -- state is derived from file content alone.
    #
    # Three sources, same order the orgs take: the shipped default, then what
    # the HUB declared (whether the store is a git repo is a fact about the
    # hub, so it needs no per-machine switch), then this machine's override --
    # which is how a machine that must never push says so.
    StoreSync = Merge-ConfigValue (Merge-ConfigValue $defaultConfig.storeSync ([string]$script:HubManifest.StoreSync)) ($localConfig.storeSync)
    # House style for prompt filenames and suggested branches, per work-item type.
    # Config so a team can set its own without editing a script -- see
    # workItemTypes in config.default.json.
    WorkItemTypes = Merge-ConfigValue $defaultConfig.workItemTypes ($localConfig.workItemTypes)
    BranchUser    = Merge-ConfigValue $defaultConfig.branchUser    ($localConfig.branchUser)
    # A folder whose copy of a shipped agentic prompt wins here -- Scripts/Resolve-AgenticPrompt.ps1 is the one reader.
    AgenticExtensionPath = Merge-ConfigValue $defaultConfig.agenticExtensionPath ($localConfig.agenticExtensionPath)
    PromptsFolder = if ($activeSpace) { $activeSpace.promptsFolder } else { '' }
    Projects      = if ($activeSpace -and $activeSpace.projects) { @($activeSpace.projects) } else { @() }
    ActiveSpace     = if ($activeSpace) { $activeSpace.slug } else { '' }
    # The active space's DISPLAY name ("Demo", "Example") -- distinct from the
    # slug above, and what a tracker verb's header line names.
    #
    ActiveOrgName = if ($activeSpace -and $activeSpace.name) { $activeSpace.name } elseif ($activeSpace) { $activeSpace.slug } else { '' }
    Spaces          = $spaces
    # Hide the shipped Example org from what is OFFERED (Scripts/Select-OfferedSpaces.ps1).
    IsDemoDismissed = [bool](Merge-ConfigValue $defaultConfig.isDemoDismissed ($localConfig.isDemoDismissed))
    # What the hub declared: the sibling folder names in force, and a plain
    # report of whether a manifest was found, for Setup and Env to print.
    HubFolders      = (Get-P20HubFolderNames -Manifest $script:HubManifest)
    HubManifest     = [bool]$script:HubManifest.Manifest
    HubManifestPath = [string]$script:HubManifest.Path
    HubSpaceCount     = @($script:HubManifest.Spaces).Count
    SuppressDeprecationHints = [bool]$localConfig.suppressDeprecationHints
    # The port the agent listens on and the web half proxies to. The launchers
    # read web.agentPort out of the JSON themselves (they run with no module
    # imported); this is the same value for anything that does have the module,
    # which today is the help renderer -- a URL in a help line is read, never
    # typed.
    AgentPort = if ($localConfig.web -and $localConfig.web.agentPort) { [int]$localConfig.web.agentPort }
    elseif ($defaultConfig.web -and $defaultConfig.web.agentPort) { [int]$defaultConfig.web.agentPort }
    else { 4100 }
    # The provider profile: the model id every model call sends --
    # AddPRReview here, suggest and rewrite in the agent, which reads the same
    # key through its own config loader. The key itself stays in the environment.
    AiModel = if ($localConfig.ai -and $localConfig.ai.model) { [string]$localConfig.ai.model }
    elseif ($defaultConfig.ai -and $defaultConfig.ai.model) { [string]$defaultConfig.ai.model }
    else { '' }
}

# Fallback: derive PromptsRoot from toolkit location if not configured. Nothing
# to override here -- PROMPTS_ROOT was already consulted in $script:HubRoot, so
# reaching this line means neither the environment nor either config file named
# a hub.
if (-not $script:ModuleState.Config.PromptsRoot) {
    $script:ModuleState.Config.PromptsRoot = (Split-Path $toolkitRoot -Parent)
}

# -- Feature flags -------------------------------------------------------------
# A flag has a SCOPE, and the default scope is the engineer. Everything except
# the ADO core itself belongs to the person and lives in the top-level
# `features` block, so it holds steady across activeOrg -- switching from an
# active engagement to an archived one must not make Growth appear and
# disappear. The exceptions are listed here: flags that describe one org's
# board or store, read from that org's own `features`. An org cannot set
# anything else, and a top-level value for an org-scoped key is ignored.
#
# MUST mirror ORG_FEATURES / effective_features in agent/core/config.py -- the
# CLI and the agent answer the same question and must not disagree about it.
# The list itself is declared further up, beside the config merge: the hub
# manifest reader needs it to tell an org's flag from an engineer's.

# -CommittedOnly answers the same question about the COMMITTED config alone,
# ignoring config.local.json. One caller: the autoload alias discovery, which
# builds a manifest that is shared between machines and must therefore not see
# a flag one machine happens to have set. Same reasoning, and the same switch,
# as the personal nav aliases that used to make that manifest flap.
# A CLOSURE over $script:ModuleState, not a plain function body. This one is
# called by Scripts/Get-Environment.ps1 while the module is running that script,
# and there `$script:SpaceScopedFeatures` resolved against the .ps1's scope rather
# than the module's (empty, so sprintAwareness was never merged) while the
# unqualified `$defaultConfig` / `$localConfig` / `$activeSpace` reads worked only
# for as long as no intervening script named one. The container's comment beside
# the config load is the long version.
& {
    $s = $script:ModuleState
    Set-Item function:global:Get-P20Features -Value {
        [CmdletBinding()]
        param([switch]$CommittedOnly)
        $merged = @{}
        $sources = if ($CommittedOnly) { @($s.DefaultFeatures) } else { @($s.DefaultFeatures, $s.LocalFeatures) }
        foreach ($source in $sources) {
            if ($null -eq $source) { continue }
            foreach ($prop in $source.PSObject.Properties) {
                if ($s.SpaceScopedFeatures -contains $prop.Name) { continue }
                $merged[$prop.Name] = [bool]$prop.Value
            }
        }
        if (-not $CommittedOnly) {
            $orgFeatures = $s.ActiveSpaceFeatures
            foreach ($name in $s.SpaceScopedFeatures) {
                # Only a boolean is a flag: trainingHoursPerQuarter is a number the Space
                # states, read off the Space itself, and is not folded into this map.
                if ($orgFeatures -and $orgFeatures.PSObject.Properties[$name] -and $orgFeatures.$name -is [bool]) {
                    $merged[$name] = [bool]$orgFeatures.$name
                }
            }
            # Team Agile's switch is the person's; the module is on only where the
            # active Space's answer is 'agents' (Scripts/Resolve-HowIWork.ps1).
            if ($s.HowIWork -and $s.HowIWorkGate) { $null = & $s.HowIWorkGate -Features $merged -Answer ([string]$s.HowIWork.answer) }
        }
        return $merged
    }.GetNewClosure()
}

# -- Export config globally so scripts (e.g. Get-Environment.ps1) can read it --
$global:P20Config = $script:ModuleState.Config

# -- Prompt folder resolution (org-scoped current/archive) --------------------
function Get-PromptFolders {
    $cfg = $global:P20Config
    $root = $cfg.PromptsRoot
    $folder = $cfg.PromptsFolder
    # The names are a contract, not this function's choice: agent/core/config.py's
    # resolve_dirs and the communication module's session folders spell them too.
    #
    # Through the FUNCTION, not `$script:Consts`. This function is reached from
    # scripts the module launches (Archive -> Move-PromptToArchive.ps1 -> here),
    # and in that chain a `$script:` name binds to the LAUNCHED script's scope,
    # where it is $null -- so both names came back empty, the folder came out as
    # `<hub>/<org>/`, and Archive run as a verb saw no cards at all.
    # See AGENTS.md,
    # "cannot read module state through a $script: name".
    $consts = Get-P20Consts
    $current = $consts.folders.current
    $archive = $consts.folders.archive
    # The third card folder: planned, not yet in play (docs/hub/cards.md).
    $backlog = $consts.folders.backlog
    $base = $root
    if ($folder) { $base = Join-Path $root $folder }
    @{
        Current = Join-Path $base $current
        Archive = Join-Path $base $archive
        Backlog = Join-Path $base $backlog
    }
}

# -- Export WS_ROOT so scripts and child processes can use it -----------------
if ($script:ModuleState.Config.WsRoot) {
    $env:WS_ROOT = $script:ModuleState.Config.WsRoot
}

# -- The command prefix --------------------------------------------------------
# Resolved HERE, above everything that registers a name under it. The prefix is
# data, and EVERY name this package registers is built from it -- the verbs and
# the navigation shortcuts alike. It used to be resolved beside
# Register-PromptAlias, 1300 lines below the nav loop that also needs it, which
# is how nav alias keys came to carry a literal 'tk' of their own and the menu
# came to print 'tktkHub'.
#
$script:ModuleState.CommandPrefix = Get-P20DefaultPrefix
if ($defaultConfig -and $defaultConfig.commandPrefix) { $script:ModuleState.CommandPrefix = $defaultConfig.commandPrefix }
if ($localConfig   -and $localConfig.commandPrefix)   { $script:ModuleState.CommandPrefix = $localConfig.commandPrefix }

# -- Build navigation aliases from config -------------------------------------
# A nav alias key is stored BARE -- 'Home', never 'tkHome' -- exactly as a
# command key is, and the prefix is applied once at registration and once at
# render. That is the whole rule: change `commandPrefix` and the shortcuts move
# with the verbs, instead of being frozen in data under the prefix that happened
# to be in force the day they were written.
# A machine-local file is never rewritten by the package, so a config.local.json
# that still carries the old prefixed form ('tkHub') has to keep working: it is
# read as 'Hub', once, with the canonical spelling named.
# ConvertTo-P20BareAliasKey is Scripts/Resolve-CliPrefix.ps1's -- one answer,
# shared with the config schema that validates `aliases.<name>.path`.

# Merge alias definitions: start with defaults, overlay local overrides
$mergedAliases = @{}
foreach ($prop in $defaultConfig.aliases.PSObject.Properties) {
    $key = ConvertTo-P20BareAliasKey -Key $prop.Name -Prefix $script:ModuleState.CommandPrefix
    $mergedAliases[$key] = @{
        path        = $prop.Value.path
        display     = $prop.Value.display
        description = $prop.Value.description
    }
}
$navKeysRewritten = @()
if ($localConfig.aliases) {
    foreach ($prop in $localConfig.aliases.PSObject.Properties) {
        $key = ConvertTo-P20BareAliasKey -Key $prop.Name -Prefix $script:ModuleState.CommandPrefix
        if ($key -ne $prop.Name) { $navKeysRewritten += "$($prop.Name) -> $key" }
        if (-not $mergedAliases.ContainsKey($key)) {
            # A name of your own. It is SHOWN when it has a path: a person who
            # sets a path wants the shortcut, and this used to default
            # to hidden, so `Config -Set aliases.Hub.path=...` reported success and
            # registered nothing.
            # `"display": false` still hides it.
            $mergedAliases[$key] = @{ path = ''; display = (-not [string]::IsNullOrWhiteSpace([string]$prop.Value.path)); description = '' }
        }
        if ($null -ne $prop.Value.path) { $mergedAliases[$key].path = $prop.Value.path }
        if ($null -ne $prop.Value.display) { $mergedAliases[$key].display = $prop.Value.display }
        if ($prop.Value.description) { $mergedAliases[$key].description = $prop.Value.description }
    }
}
# Said ONCE per import, and mutable by the same switch every other deprecation
# hint answers to. The shortcut still works; the file is the reader's to fix.
if ($navKeysRewritten.Count -gt 0 -and -not $script:ModuleState.Config.SuppressDeprecationHints) {
    Write-Warning ("config.local.json spells a nav alias with the command prefix: " +
        ($navKeysRewritten -join ', ') +
        ". Nav alias keys are bare now -- the prefix is added when the alias is registered. Rename the key to the bare form; it is read that way meanwhile.")
}

# The merged table, kept so a SECOND prefix can register the same shortcuts --
# Register-PromptAlias -Prefix gt yields gtHome from this one definition.
$script:ModuleState.NavAliases = $mergedAliases

# The merged navigation table, bare-keyed. Read by the optional-surface
# inventory, which has to say whether the category is configured before it
# renders -- and by anything else that needs the shortcuts without re-merging
# two config files. `Menu -All` and `Env` both come through here: one resolver,
# one call shape, so they cannot disagree about the same data in one session.
#
# A CLOSURE over $script:ModuleState. `return $script:NavAliases` was right in
# every shape but the one that matters -- Env, which the module runs as a script
# of its own, where $script: binds to that script and the table came back $null.
& {
    $s = $script:ModuleState
    Set-Item function:global:Get-P20NavAliases -Value {
        [CmdletBinding()]
        param()
        return $s.NavAliases
    }.GetNewClosure()
}

# The optional-surface inventory and the settings-by-workflow entries as ONE
# JSON, for the agent's GET /api/surfaces (D-W2; docs/CONFIGURATION.md, "Settings
# by workflow: the questions, and the one list behind them"): the web never re-derives a state, it reads this the way the bridge
# reads Get-P20CommandMap. Ordinary global function reading through the
# accessor; the dot-sourced helpers it calls are module-scope.
function global:Get-P20SurfaceInventory {
    [CmdletBinding()]
    param()
    $s = Get-P20ModuleState
    $root = $s.PackageRoot
    if (-not (Get-Command Get-P20OptionalSurfaces -ErrorAction SilentlyContinue)) { . (Join-Path $root 'Scripts/Get-OptionalSurfaces.ps1') }
    $surfaces = @(Get-P20OptionalSurfaces -Config $s.Config -Features (Get-P20Features) -NavAliases (Get-P20NavAliases) `
        -Prefix $s.CommandPrefix -PackageRoot $root)
    $entries = @(Get-P20SettingsWorkflows -PackageRoot $root)
    $payload = [ordered]@{ surfaces = $surfaces; entries = $entries; activeSpace = [string]$s.Config.ActiveSpace; prefix = [string]$s.CommandPrefix }
    return ($payload | ConvertTo-Json -Depth 8 -Compress)
}

# THE container, for the global functions that need more of it than one
# accessor answers: Get-P20Menu, Get-P20MenuMarkdown, Register-PromptAlias,
# Get-P20CommandMap, Get-P20ModuleCommands, Write-P20DeprecationHint. They stay ordinary
# `function global:` bodies -- so their module-private helpers resolve -- and
# open with `$s = Get-P20ModuleState`. This closure is the only thing that may
# hold the table by reference; a GetNewClosure() body cannot call a private
# function, which is why the functions themselves are not closures.
& {
    $s = $script:ModuleState
    Set-Item function:global:Get-P20ModuleState -Value {
        [CmdletBinding()]
        param()
        return $s
    }.GetNewClosure()
}

# Autoload discovery (Prompt20Toolkit/Get-ToolkitAliases.ps1, used by the manifest
# generator and Test-Autoload) imports this module to learn which aliases exist.
# Nav shortcuts come from the gitignored, per-machine config.local.json, so
# letting them into that answer bakes one machine's repo layout into a shared
# committed manifest and makes the drift check flap between machines. The
# discovery shells set this to '1'; nothing else does.
$script:ModuleState.SkipNavAliases = ($env:PROMPTS_TOOLKIT_NO_NAV_ALIASES -eq '1')

# A shell reads its config ONCE, at import, so a change written afterwards -- the
# GUI's switch runs SwitchSpace in a child pwsh, Config -Set from another window --
# did not reach it, and a verb that writes (NewPrompt) filed into the old Space.
#The stamp is the write time and size of the two files the config is read
# from; Update-P20StaleConfig compares it at the start of a verb and re-imports,
# the way SwitchSpace refreshes its own shell. A missing file stamps as 'none'.
# The two environment overrides are part of the same stamp: PROMPTS_ROOT and the
# Space the environment names (consts.json env.activeSpace) win over the files at
# import, so one exported AFTER the import -- a profile that loads the toolkit
# before the variable is set, a walk that points an open shell at a scratch hub
# -- left every verb on the import-time hub while Env's surface row, which reads
# the environment fresh, named the other one: two hubs in one report. A changed
# override is seen on the next verb exactly as a changed file is, and both of
# Env's lines then read the one re-imported state.
function global:Get-P20ConfigStamp {
    [CmdletBinding()]
    param([string[]]$Paths)
    $parts = @(foreach ($p in @($Paths)) {
        if ($p -and (Test-Path -LiteralPath $p -PathType Leaf)) {
            $i = Get-Item -LiteralPath $p
            "$($i.LastWriteTimeUtc.Ticks):$($i.Length)"
        }
        else { 'none' }
    })
    $parts += @("hub=$(Get-P20HubOverride)", "space=$(Get-P20ActiveSpaceOverride)")
    return ($parts -join '|')
}

# Reads the table through Get-P20ModuleState, never `$script:` (Clause 8). Called
# by Invoke-ToolkitScript and by Env; says one line when it re-reads, and never
# throws -- a failed re-import leaves the shell as it was, with a warning.
function global:Update-P20StaleConfig {
    [CmdletBinding()]
    param()
    $s = Get-P20ModuleState
    if (-not $s -or -not $s.ConfigWatch -or @($s.ConfigWatch).Count -eq 0) { return }
    if ((Get-P20ConfigStamp -Paths $s.ConfigWatch) -eq $s.ConfigStamp) { return }
    $was = [string]$s.Config.ActiveSpace
    $wasHub = [string]$s.Config.PromptsRoot
    try {
        Import-Module (Join-Path $s.PackageRoot 'utilities.psm1') -Global -Force -DisableNameChecking 3>$null 6>$null
        $global:P20Env = $null
        $now = [string]$global:P20Config.ActiveSpace
        $nowHub = [string]$global:P20Config.PromptsRoot
        $msg = if ($nowHub -ne $wasHub) { "Hub changed to $nowHub since this shell loaded (it was $wasHub); re-read." }
        elseif ($now -ne $was) { "Space changed to $now since this shell loaded (it was $was); re-read." }
        else { 'Config changed since this shell loaded; re-read.' }
        Write-Host "  $msg" -ForegroundColor DarkGray
    }
    catch {
        Write-Warning "config changed since this shell loaded, and re-reading it failed ($($_.Exception.Message)); this shell still acts on '$was'. Open a new shell."
    }
}

# Create a navigation function + alias for each enabled entry, under one prefix.
# Defined as a function so a second prefix gets the same shortcuts from the same
# data (Register-PromptAlias), and declared BEFORE the import-time call below --
# a module body runs top to bottom, so the order here is the contract.
function script:Register-P20NavAliases {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingInvokeExpression', '', Justification = 'Generates one navigation function per configured shortcut; the path is the only value spliced in, and it is single-quoted with its quotes doubled.')]
    param([Parameter(Mandatory = $true)][string]$Prefix)
    foreach ($alias in $script:ModuleState.NavAliases.GetEnumerator()) {
        if (-not $alias.Value.display) { continue }

        $targetPath = $alias.Value.path
        # An alias with no path has nowhere to go, and a half-working shortcut
        # is worse than an absent one. Menu still NAMES the category -- see
        # Get-P20Menu's 'nav' empty state.
        if ([string]::IsNullOrWhiteSpace($targetPath)) { continue }

        $aliasName = $Prefix + $alias.Key
        $funcName = "Navigate-$aliasName"
        $funcBody = @"
function global:$funcName {
    Set-Location -Path '$($targetPath -replace "'", "''")'
    Get-ChildItem
}
"@
        Invoke-Expression $funcBody
        Set-Alias -Name $aliasName -Value $funcName -Scope Global
    }
}

if (-not $script:ModuleState.SkipNavAliases) {
    Register-P20NavAliases -Prefix $script:ModuleState.CommandPrefix
}

# -- Build commands metadata from config ---------------------------------------
$script:ModuleState.Commands = @{}
if ($defaultConfig.commands) {
    foreach ($prop in $defaultConfig.commands.PSObject.Properties) {
        $script:ModuleState.Commands[$prop.Name] = @{
            category    = $prop.Value.category
            description = $prop.Value.description
            usage       = $prop.Value.usage
            examples    = $prop.Value.examples
            # Optional, and only the core verbs that have real switch surface
            # carry them: one line per switch, and free-text notes (the URLs,
            # and what the command does to its sibling half). Help for a verb
            # lives in this table, so -Help, Menu and README parity all read
            # one source -- the per-switch detail used to exist only in
            # Start-Web.ps1's comment-based help, where -Help never looked.
            switches    = $prop.Value.switches
            notes       = $prop.Value.notes
            # Optional: how a verb that works with AND without Azure DevOps
            # describes itself on a machine where ADO is not in use. Menu reads it.
            descriptionWithoutAdo = $prop.Value.descriptionWithoutAdo
            # Optional: how long the bridge lets this verb run. Carried here so
            # Get-P20CommandMap can hand the agent ONE table with every verb's
            # value, a module's included.
            bridgeTimeoutSeconds = $prop.Value.bridgeTimeoutSeconds
        }
    }
}

# Merge navigation aliases into commands metadata (category = "nav")
foreach ($alias in $mergedAliases.GetEnumerator()) {
    if ($alias.Value.display -and -not [string]::IsNullOrWhiteSpace($alias.Value.path)) {
        $script:ModuleState.Commands[$alias.Key] = @{
            category    = 'nav'
            description = $alias.Value.description
        }
    }
}

# -- Scoring -------------------------------------------------------------------
# Scores from the usage log, keyed by BARE command name. The log holds the
# user-facing name (`tkSync`, or `gtSync` from another prefix) and the agent's
# route-shaped rows (`agent/prs`); the command table's keys are bare. The two
# once failed to meet, so the most-used section never appeared for
# anyone.
# -CommandNames is the table to normalise against: a name that is one of them,
# or one of them behind a lowercase prefix, scores under the bare name; an
# agent route is usage, not a verb a person types, and is not scored. With no
# -CommandNames the raw log names come back, which is what a suite that reads
# the log by its own entries wants.
function global:Get-P20CommandScores {
    param([string[]]$CommandNames = @(), [string]$Prefix = '')
    $logFiles = Get-ChildItem -Path (Get-P20ToolkitLogDir) -Filter 'usage.*.log' -ErrorAction SilentlyContinue
    if (-not $logFiles) { return @{} }

    $now = Get-Date
    $scores = @{}

    # Check for reset marker in config.local.json
    $localCfgPath = Join-Path $PSScriptRoot 'config.local.json'
    $resetTimestamp = $null
    if (Test-Path $localCfgPath) {
        try {
            $localCfg = Get-Content $localCfgPath -Raw | ConvertFrom-Json
        }
        catch { $null = Write-P20ConfigParseWarning -Path $localCfgPath -Message $_.Exception.Message; $localCfg = $null }
        # The file parsed; a value that is not a date says which key it is.
        if ($localCfg -and $localCfg.menuResetTimestamp) {
            $resetTimestamp = ConvertTo-P20ConfigDate -Path $localCfgPath -Key 'menuResetTimestamp' -Value $localCfg.menuResetTimestamp
        }
    }

    $logFiles | ForEach-Object {
        Get-Content $_.FullName -Encoding UTF8 | ForEach-Object {
            $parts = $_ -split "`t"
            if ($parts.Count -lt 4) { return }
            if ($parts[1] -ne 'CMD') { return }
            try { $ts = [datetime]$parts[0] } catch { return }
            if ($resetTimestamp -and $ts -lt $resetTimestamp) { return }
            $cmd = $parts[3]
            if ($CommandNames.Count -gt 0) {
                if ($cmd -match '/') { return }   # an agent route, not a verb
                $bare = $null
                if ($CommandNames -contains $cmd) { $bare = $cmd }
                elseif ($Prefix -and $cmd.StartsWith($Prefix) -and ($CommandNames -contains $cmd.Substring($Prefix.Length))) {
                    $bare = $cmd.Substring($Prefix.Length)
                }
                else {
                    # Another prefix this log has seen: lowercase letters in front of a known name.
                    foreach ($n in $CommandNames) {
                        if ($cmd.Length -gt $n.Length -and $cmd.EndsWith($n) -and $cmd.Substring(0, $cmd.Length - $n.Length) -cmatch '^[a-z]{1,8}$') { $bare = $n; break }
                    }
                }
                if (-not $bare) { return }
                $cmd = $bare
            }
            $age = ($now - $ts).TotalDays

            $weight = if ($age -le 14) { 3 } elseif ($age -le 30) { 2 } elseif ($age -le 90) { 1 } else { 0 }
            if ($weight -eq 0) { return }
            if (-not $scores.ContainsKey($cmd)) { $scores[$cmd] = 0 }
            $scores[$cmd] += $weight
        }
    }

    return $scores
}

# -- Tier detection (calls {cliPrefix}Env inline, caches in $global:P20Env) ---------
function script:Get-CurrentTier {
    if ($global:P20Env -and $global:P20Env.Tier) {
        return $global:P20Env.Tier
    }
    # Not yet populated -- run detection silently
    & "$toolkitRoot\Scripts\Get-Environment.ps1" -Startup
    if ($global:P20Env -and $global:P20Env.Tier) {
        return $global:P20Env.Tier
    }
    return 1  # fallback
}

# Why this machine is not Tier 1, in one clause, from what Get-Environment
# recorded. The refusal below prints it as the Hint, so a person reads the cause
# and not a list of other things they could type.
function script:Get-TierCause {
    $e = $global:P20Env
    if (-not $e) { return 'the environment has not been probed' }
    if ($e.Tier -ge 3) {
        if (-not $e.GitInstalled) { return 'git is not installed' }
        return 'the hub was not found'
    }
    $org = if ($e.ActiveSpace) { "'$($e.ActiveSpace)'" } else { 'the active Space' }
    if ($e.OrgStatus -eq 'local' -or $e.OrgStatus -eq 'archive') {
        return "$org is $($e.OrgStatus), so Azure DevOps is not contacted"
    }
    # The cause names the BOARD'S tracker and its tool -- gh and GitHub on a
    # GitHub board, az and Azure DevOps
    # everywhere else, which is every word this function ever said.
    if ($e.Tracker -eq 'github') {
        if (-not $e.GhCliInstalled) { return 'the gh CLI is not installed' }
        if (-not $e.GhAuthenticated) { return 'gh is not signed in -- run gh auth login' }
        if (-not $e.TrackerReachable) { return "GitHub did not answer for $org" }
        return 'GitHub is not reachable'
    }
    if (-not $e.AzCliInstalled) { return 'the az CLI is not installed' }
    if (-not $e.AzAuthenticated) { return 'az is not signed in -- run az login' }
    if (-not $e.AdoReachable) { return "Azure DevOps did not answer for $org" }
    return 'Azure DevOps is not reachable'
}

# The Tier-1 gate every ADO verb runs before its script. A refusal, not a
# notice: the documented sentence, the cause as the hint, exit 2, one block, and
# re-raised for a non-interactive caller -- Write-WrapperRefusal is the same
# contract every other wrapper-stated refusal uses. It used to print a page of
# one person's setup ("available on your work laptop") and return with exit 0,
# so the bridge reported success and a script checking $LASTEXITCODE saw
# nothing wrong.
function script:Test-AdoAvailable {
    param([string]$CommandName)
    $tier = Get-CurrentTier
    if ($tier -ge 2) {
        # The sentence names the board's tracker: "needs ADO" is the documented
        # form on an ADO board (Test-ExitCodes pins it) and stays the default;
        # a GitHub board says GitHub, because telling its user they need ADO
        # would name a product this board never contacts.
        $needs = if ($global:P20Env -and $global:P20Env.Tracker -eq 'github') { 'GitHub' } else { 'ADO' }
        Write-WrapperRefusal -Name $CommandName `
            -Message "$CommandName needs $needs (Tier 1); currently Tier $tier." `
            -Hint "$(Get-TierCause). '$(Get-CliPrefix)Env' shows the tier and what decides it."
        return $false
    }
    return $true
}

function script:Get-RecentErrors {
    $logFiles = Get-ChildItem -Path (Get-P20ToolkitLogDir) -Filter 'usage.*.log' -ErrorAction SilentlyContinue
    if (-not $logFiles) { return 0 }
    $cutoff = (Get-Date).AddHours(-24).ToString('yyyy-MM-ddTHH:mm:ss')

    # If errors were acknowledged, use the ack timestamp as a floor
    $localCfgPath = Join-Path $PSScriptRoot 'config.local.json'
    if (Test-Path $localCfgPath) {
        try {
            $localCfg = Get-Content $localCfgPath -Raw | ConvertFrom-Json
        }
        catch { $null = Write-P20ConfigParseWarning -Path $localCfgPath -Message $_.Exception.Message; $localCfg = $null }
        # The file parsed; a value that is not a date says which key it is.
        if ($localCfg -and $localCfg.errorsAckedAt) {
            $ackAt = ConvertTo-P20ConfigDate -Path $localCfgPath -Key 'errorsAckedAt' -Value $localCfg.errorsAckedAt
            if ($ackAt) {
                $ackStr = $ackAt.ToString('yyyy-MM-ddTHH:mm:ss')
                if ($ackStr -gt $cutoff) { $cutoff = $ackStr }
            }
        }
    }

    $count = 0
    $logFiles | ForEach-Object {
        Get-Content $_.FullName -Encoding UTF8 | ForEach-Object {
            $parts = $_ -split "`t"
            if ($parts.Count -ge 2 -and $parts[1] -eq 'ERR' -and $parts[0] -gt $cutoff) { $count++ }
        }
    }
    return $count
}

# ADO-dependent commands (used for availability flags in -All view)
# Bare command keys, matching config. This is a statement about which COMMANDS
# need ADO, which has nothing to do with the prefix -- and it is compared
# against config keys, which carry no prefix. Holding prefixed names here
# meant the comparison never matched, so the menu stopped dimming ADO
# commands in local mode; and building them with Get-CliPrefix at import
# time called the function before it was defined.
# NewPrompt is NOT here: its -Title form is exactly what works with
# no ADO, and Menu was dimming it as "(unavailable)" at Tier 2. Dashboard is pure
# ADO and was missing; CloseWorkItem was listed twice.
# Canonical names only: both readers compare this against the MENU's
# rows, which are config's keys, and a deprecated name in $script:ModuleState.DeprecatedAliases
# is by definition not one -- listing it here only invited a test to expect a row
# Menu never draws.
$script:ModuleState.AdoCommands = @('GetPRComments', 'ReplyPR', 'NewPR', 'PublishPR', 'AddPRReview', 'NewItem', 'MyPRs', 'MyWork', 'CloseItem', 'EditItem', 'Dashboard', 'LogPeerReview')

# Scripts under Scripts/ run outside the module's script scope, so they cannot
# read the module's prefix directly. This is how they render command names in
# their own help and hints without hardcoding a prefix.
# Reads the exported config FIRST, never a `$script:` variable. This function is
# global, so $script: resolves against whatever scope is current when it is
# called -- it returned the prefix from the session but an empty string when
# called from inside a module function, so help rendered with no prefix at all
# through a wrapper and correctly when the script was run directly. The fallback
# is a closure over $script:ModuleState for the same reason, so the two reads
# now fail the same way (i.e. not at all) rather than one of them silently.
& {
    $s = $script:ModuleState
    Set-Item function:global:Get-CliPrefix -Value {
        if ($global:P20Config -and $global:P20Config.CommandPrefix) { return $global:P20Config.CommandPrefix }
        if ($s.CommandPrefix) { return $s.CommandPrefix }
        return ''
    }.GetNewClosure()
}

# -- Links from a card back into the package -----------------------------------
# Templates and agentic workflows ship with the package; cards are written into
# the hub, a separate repo at an arbitrary relative position. A hardcoded
# "../../agentic/x.md" was correct only while the two lived in one repo, and has
# been quietly wrong in every hub card since they split -- a link that looks
# right and resolves nowhere, which is worse than no link at all.
#
# So compute the hop rather than counting it. The hub's shape
# ({user}/{org}/current) is a convention, not a guarantee.
#
# Resolve-Path -Relative, NOT [System.IO.Path]::GetRelativePath -- the latter is
# PS 6+ and fails the compat gate.
#
# When the card and the package are on different drives there is no relative path
# to give, and the answer is -Fallback: for the two package links that is the
# file's NAME, so a card never keeps a machine path. (Scripts/Repair-CardLinks.ps1
# carries a copy of this function for a caller with no module loaded; the two are
# edited together.)
function global:Resolve-P20PackageLink {
    # Deliberately NOT Mandatory. The caller may genuinely have no directory to
    # write from -- GetPRComments prints to the console when it cannot find a
    # card -- and a Mandatory string parameter rejects null BEFORE the guard
    # below can return the fallback, turning a handled case into a crash.
    param(
        [string]$TargetPath,     # in the package, absolute
        [string]$FromDirectory,  # where the link is written
        [string]$Fallback = ''
    )
    if (-not $TargetPath -or -not $FromDirectory) { return $Fallback }
    if (-not (Test-Path $TargetPath) -or -not (Test-Path $FromDirectory)) { return $Fallback }
    # No relative path exists between two drives, or onto a network share, and
    # Resolve-Path -Relative then answers with the ABSOLUTE path (spelled
    # ".\<drive>:\..." by Windows PowerShell 5.1). That names a machine, and a
    # card is synced to others, so it is the caller's -Fallback instead: the
    # roots are compared first, and the answer is checked after.
    try {
        $targetRoot = [System.IO.Path]::GetPathRoot((Convert-Path $TargetPath))
        $fromRoot = [System.IO.Path]::GetPathRoot((Convert-Path $FromDirectory))
    }
    catch { return $Fallback }
    if (-not [string]::Equals($targetRoot, $fromRoot, [System.StringComparison]::OrdinalIgnoreCase)) { return $Fallback }
    Push-Location $FromDirectory
    try {
        $rel = (Resolve-Path $TargetPath -Relative -ErrorAction Stop).Replace([char]92, [char]47)
        if ($rel.StartsWith('./')) { $rel = $rel.Substring(2) }
        if ($rel -match '^(?:[A-Za-z]:/|/)') { return $Fallback }
        return $rel
    }
    catch { return $Fallback }
    finally { Pop-Location }
}

# -- Invoked command name ------------------------------------------------------
# A wrapper must report the name the user actually typed. Hardcoding "{cliPrefix}NewPrompt"
# meant the log recorded a command nobody ran, and -- worse -- the error hint on
# the failure path pointed at {cliPrefix}Log, which is not registered when the prefix is
# something else. With two prefixes registered, a hardcoded name also cannot say
# which surface failed.
#
# Invoked through an alias, the alias IS the user-facing name and its leading
# characters are that user's prefix. Invoked by function name, there is no prefix
# to recover, so fall back to the configured one.
function script:Resolve-InvokedCommand {
    param(
        [string]$InvocationName,
        [Parameter(Mandatory = $true)][string]$Command
    )
    $prefix = $script:ModuleState.CommandPrefix
    # One verb calling another. Update -Sync runs Sync from INSIDE a script the
    # module launched, and in that call shape `$script:` binds to the running .ps1,
    # not to this module (AGENTS.md, "A function global: ... cannot read module
    # state through a $script: name") -- so the line above came back empty, the
    # call operator made InvocationName "&", and a good update died with "Cannot
    # bind argument to parameter 'Prefix'". The exported config is global and is
    # reachable from every call shape; Get-CliPrefix falls back to it the same way.
    if (-not $prefix -and $global:P20Config -and $global:P20Config.CommandPrefix) {
        $prefix = [string]$global:P20Config.CommandPrefix
    }
    if ($InvocationName -and $InvocationName -ne $Command -and $InvocationName.EndsWith($Command)) {
        $prefix = $InvocationName.Substring(0, $InvocationName.Length - $Command.Length)
    }
    return @{ Prefix = $prefix; Name = $prefix + $Command }
}

# -- Identity ------------------------------------------------------------------
# Who "me" is, for assigning work items. Config wins so a shared machine or a
# second account can override it; otherwise ask az, which already knows -- a
# tool should not warn about something it can work out. Resolved lazily and
# cached, because az account show costs about a second and most commands never
# need it. Never defaulted to a person's address in source.
# The cache lives in $script:ModuleState and this is a CLOSURE over it, because
# the cache has to work through a wrapper too: `$script:ResolvedIdentity` read
# and written from a global function reached through a module-launched script
# binds to that script's scope, so the write landed somewhere that died with the
# script and every call paid for `az account show` again. Writing through the
# container reference is visible to the next call in any shape.
& {
    $s = $script:ModuleState
    Set-Item function:global:Resolve-P20Identity -Value {
        [CmdletBinding()]
        param([switch]$Refresh)
        if ($s.ResolvedIdentity -and -not $Refresh) { return $s.ResolvedIdentity }
        $email = $null
        if ($global:P20Config -and $global:P20Config.Email) { $email = $global:P20Config.Email }
        if ([string]::IsNullOrWhiteSpace($email)) {
            try {
                # The one way to call az (Scripts/Invoke-TrackerRead.ps1), loaded
                # here: this body is a closure, so a module-scope copy is not seen.
                . (Join-Path (Join-Path $s.PackageRoot 'Scripts') 'Invoke-TrackerRead.ps1')
                $probeRead = Invoke-P20TrackerRead 'az' @('account', 'show', '--query', 'user.name', '-o', 'tsv')
                $probe = [string]($probeRead.Out -join '')
                if ($probeRead.Code -eq 0 -and -not [string]::IsNullOrWhiteSpace($probe)) {
                    $email = $probe.Trim()
                }
            }
            catch {
                Write-ToolkitLog -Type WARN -Source 'Resolve-P20Identity' -Detail $_.Exception.Message
            }
        }
        if ([string]::IsNullOrWhiteSpace($email)) { return $null }
        $s.ResolvedIdentity = $email
        return $email
    }.GetNewClosure()
}

# -- Command prefix placeholder ------------------------------------------------
# Command metadata in config stores the prefix as a {cliPrefix} placeholder so
# help, menus and generated docs read correctly whichever prefix is registered.
# Every render path goes through here -- a raw description reaching output is a
# bug, and having one resolver is what stops the next render path forgetting.
function script:Expand-CliPrefix {
    param([string]$Text, [string]$Prefix)
    if (-not $Text) { return $Text }
    if (-not $Prefix) { $Prefix = $script:ModuleState.CommandPrefix }
    # {p} is the older spelling. Nothing in config.default.json writes it any
    # more, but three menu render paths used to substitute it INSTEAD of
    # {cliPrefix} and so printed the live token verbatim. Both are expanded
    # here so there is one resolver and no second, silently-dead convention.
    return ($Text -replace '\{cliPrefix\}', $Prefix -replace '\{p\}', $Prefix)
}

# The ports a help entry may name. Read from config rather than typed into a
# sentence: `web.agentPort` is the key that decides, and the dev port is what
# web/vite.config.ts asks for. A help line that hardcodes 4100 is wrong on the
# machine that changed it.
function script:Get-HelpPorts {
    $agentPort = 4100
    if ($script:ModuleState.Config -and $script:ModuleState.Config.AgentPort) { $agentPort = [int]$script:ModuleState.Config.AgentPort }
    $devPort = 5174
    $viteConfig = Join-Path $toolkitRoot 'web/vite.config.ts'
    if (Test-Path $viteConfig) {
        $m = [regex]::Match((Get-Content $viteConfig -Raw -ErrorAction SilentlyContinue), 'port:\s*(\d+)')
        if ($m.Success) { $devPort = [int]$m.Groups[1].Value }
    }
    return @{ AgentPort = $agentPort; DevPort = $devPort }
}

function script:Expand-HelpTokens {
    param([string]$Text, [string]$Prefix)
    if (-not $Text) { return $Text }
    $ports = Get-HelpPorts
    $out = Expand-CliPrefix $Text $Prefix
    return ($out -replace '\{agentPort\}', $ports.AgentPort -replace '\{devPort\}', $ports.DevPort)
}

# -- Shared -Help handler -----------------------------------------------------
# Every wrapper calls this at the top. Emits NOTHING to the pipeline: it used to
# return a bool that no caller read, so every '-Help' printed a stray "True".
# Prints the config description so every command gets -Help for free.
function script:Show-CommandHelp {
    param([string]$CommandName)
    $p = $script:ModuleState.CommandPrefix
    $meta = $script:ModuleState.Commands[$CommandName]
    if (-not $meta) { return }
    Write-Host ""
    Write-Host "  $($script:ModuleState.CommandPrefix)$CommandName" -ForegroundColor Cyan
    Write-Host "  $(Expand-HelpTokens $meta.description $p)" -ForegroundColor Gray
    if ($meta.usage) {
        Write-Host ""
        Write-Host "  Usage:" -ForegroundColor Yellow
        Write-Host "    $(Expand-HelpTokens $meta.usage $p)" -ForegroundColor Gray
    }
    # One line per switch, when the entry has them. A usage line says which
    # switches exist; this says what each one does, which is what the
    # predecessor's hand-written help gave and the table did not.
    if ($meta.switches) {
        Write-Host ""
        Write-Host "  Switches:" -ForegroundColor Yellow
        foreach ($sw in $meta.switches.PSObject.Properties) {
            $label = "$($sw.Name)".PadRight(12)
            Write-Host "    $label $(Expand-HelpTokens $sw.Value $p)" -ForegroundColor Gray
        }
    }
    if ($meta.examples) {
        Write-Host ""
        Write-Host "  Examples:" -ForegroundColor Yellow
        foreach ($ex in $meta.examples) {
            Write-Host "    $(Expand-HelpTokens $ex $p)" -ForegroundColor Gray
        }
    }
    # The URLs, and what this verb does to the other half -- the two things a
    # reader of the old help had and a reader of this one did not.
    if ($meta.notes) {
        Write-Host ""
        Write-Host "  Notes:" -ForegroundColor Yellow
        foreach ($note in $meta.notes) {
            Write-Host "    $(Expand-HelpTokens $note $p)" -ForegroundColor Gray
        }
    }
    Write-Host ""
    return
}

# -- The refusal contract ------------------------------------------------------
# ONE exit code means "I have already said why". A script that has written its
# own Write-CliError block exits 2 -- a STATED refusal -- and the wrapper guard
# below prints nothing on top of it. Anything else non-zero is a failure that
# said nothing, and only that one gets the generic "exit code N" block.
#
# AGENTS.md, "The refusal contract", is the rule; docs/CLI.md's Errors section is
# the reader-facing half. The code itself is declared in
# Scripts/Invoke-CommandScript.ps1, with the guard that reads it -- a script only
# ever writes `exit 2`, with a comment naming this contract, because most scripts
# also run with no module in the session and cannot call into it.

# Consistent error + hint output for command failure paths (docs/CLI.md, "Errors").
# Errors should explain what went wrong and suggest the corrective action,
# rather than surfacing a raw exception or logging silently.
function global:Write-CliError {
    param(
        [Parameter(Mandatory)][string]$Message,
        [string]$Hint
    )
    # Every stated refusal passes through here, so here is where the reason is
    # recorded. The wrapper logs THAT rather than "exit code 2", and a
    # non-interactive caller is handed it instead of a stack trace.
    $global:P20StatedError = $Message
    Write-Host "Error: $Message" -ForegroundColor Red
    if ($Hint) {
        Write-Host "Hint:  $Hint" -ForegroundColor Yellow
    }
}

# The guard itself lives in a file both the module and a bare shell can reach --
# same reason as Scripts/Resolve-HubConfig.ps1. There must be exactly one
# implementation of the refusal contract, and the suites that exercise a module
# wrapper by dot-sourcing it into a plain pwsh have to be able to load the real
# one rather than a stub that agrees with it by hand.
. (Join-Path $toolkitRoot 'Scripts/Invoke-CommandScript.ps1')

# Deprecated alias -> canonical replacement. Reusable infrastructure:
# add entries here when an alias is renamed and the old name is dual-mapped, to
# emit a one-time hint per session. The Phase 3 renames were fully removed in
# Phase 4 (cliVersion 2); the window open now is the Item family's, below. A
# rename adds an alias, so it also re-runs Prompt20Toolkit/Update-ToolkitManifest.ps1
# in the same commit -- the manifest is what makes the new name autoload.
$script:ModuleState.DeprecatedAliases = @{
    # The Item family: the verbs went tracker-neutral
    # (D-G4), so the names follow -- "Ado" and "WorkItem" are one tracker's
    # words, and the house's neutral word was already "item" (card = your
    # file, item = the tracker's unit). Old names stay dual-mapped in
    # $script:ModuleState.CommandMap below, with the one-time hint here.
    'NewAdoItem'    = 'NewItem'
    'EditWorkItem'  = 'EditItem'
    'CloseWorkItem' = 'CloseItem'
    # The Space rename (stage 3): the container is a Space
    # (D-G13), so the verb that switches it says so.
    'SwitchOrg'     = 'SwitchSpace'
}
$script:ModuleState.ShownDeprecationHints = @{}

# Emit a one-time deprecation hint if the command was invoked via a legacy alias.
# Pass $MyInvocation.InvocationName from the calling function so we see which
# alias the user actually typed. Muted by config.local.json suppressDeprecationHints.
# Reads module state through Get-P20ModuleState, never `$script:`: reached
# from a module-launched script, `$script:` binds to that script and answers
# $null. Not a GetNewClosure() body either -- that is bound to a NEW dynamic
# module, where this function's private helpers are not visible.
function global:Write-P20DeprecationHint {
    param([string]$InvokedAs)
    $s = Get-P20ModuleState
    if ([string]::IsNullOrWhiteSpace($InvokedAs)) { return }
    $replacement = $s.DeprecatedAliases[$InvokedAs]
    if (-not $replacement) {
        # The table keys are BARE command names; what a person types carries
        # the prefix. Strip the configured one and answer in kind.
        $p = "$($s.CommandPrefix)"
        if (-not $p -and $global:P20Config) { $p = "$($global:P20Config.CommandPrefix)" }
        if ($p -and $InvokedAs.StartsWith($p)) {
            $canon = $s.DeprecatedAliases[$InvokedAs.Substring($p.Length)]
            if ($canon) { $replacement = "$p$canon" }
        }
    }
    if (-not $replacement) { return }
    if ($s.Config.SuppressDeprecationHints) { return }
    if ($s.ShownDeprecationHints[$InvokedAs]) { return }
    $s.ShownDeprecationHints[$InvokedAs] = $true
    Write-Host "$InvokedAs is deprecated; use $replacement (same behavior)." -ForegroundColor DarkYellow
}

# -- Menu ---------------------------------------------------------------------
# Four jobs, four functions, one switch each on the Menu verb: the help printer
# (-Help), the docs-table emitter (-Markdown), the scores reset (-Reset), and
# the menu itself (default and -All), which keeps the name Get-P20Menu and
# hands the other three to their own functions.
#
# Each reads module state through Get-P20ModuleState, never `$script:`: reached
# from a module-launched script, `$script:` binds to that script and answers
# $null. Not GetNewClosure() bodies either -- that is bound to a NEW dynamic
# module, where the module's private helpers are not visible.

# -Help. The prefix is the one the menu was invoked under, passed in.
function global:Show-P20MenuHelp {
    [CmdletBinding()]
    param([string]$Prefix)
    if (-not $Prefix) { $Prefix = (Get-P20ModuleState).CommandPrefix }
    Write-Host ""
    Write-Host "  $($Prefix)Menu           Show most-used + nav aliases" -ForegroundColor Cyan
    Write-Host "  $($Prefix)Menu -All      Show all aliases grouped by intent category" -ForegroundColor Cyan
    Write-Host "  $($Prefix)Menu -Markdown Emit the command tables as markdown (for docs)" -ForegroundColor Cyan
    Write-Host "  $($Prefix)Menu -Help     Show this help message" -ForegroundColor Cyan
    Write-Host "  $($Prefix)Menu -Reset    Reset usage scores (menu re-learns from scratch)" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  Categories: pr work prompt review growth org setup info test" -ForegroundColor Yellow
    Write-Host ""
}

# -Markdown: emit grouped command tables from config so docs derive from the
# single source of truth (docs/CLI.md, "Command reference"). Excludes nav + legacy.
function global:Get-P20MenuMarkdown {
    [CmdletBinding()]
    param([string]$Prefix)
    $s = Get-P20ModuleState
    $menuPrefix = $Prefix
    if (-not $menuPrefix) { $menuPrefix = $s.CommandPrefix }
    $cmds = $s.Commands
    # 'sync' sits after 'prompt', where the console renderer's label switch
    # already put it. Both lists omitted it, so Sync and Update -- the verb
    # that updates the Toolkit -- rendered in no section at all while being
    # registered, aliased and documented.
    #
    # 'studio' joined later: NewDesign and StampDesign became core
    # verbs, and this list had never met the category -- a module verb is not in
    # $s.Commands' config half -- so they rendered in no section, the same
    # omission 'sync' had.
    $catOrder = @('pr', 'work', 'prompt', 'sync', 'sprint', 'review', 'growth', 'studio', 'org', 'setup', 'info', 'test')
    $labels = @{
        pr = 'Pull Requests'; work = 'Work Items'; prompt = 'Prompts'; sync = 'Sync'; sprint = 'Sprint Awareness'
        review = 'Reviews & Reporting'; growth = 'Growth & Meetings'; studio = 'Studio'; org = 'Org & Infra'
        setup = 'Setup'; info = 'Info'; test = 'Tests'
    }
    foreach ($cat in $catOrder) {
        $items = $cmds.GetEnumerator() | Where-Object { $_.Value.category -eq $cat } | Sort-Object Key
        if (-not $items) { continue }
        Write-Output "### $($labels[$cat])"
        Write-Output ''
        Write-Output '| Command | Description |'
        Write-Output '|---|---|'
        foreach ($item in $items) {
            $usage = if ($item.Value.usage) { $item.Value.usage } else { $item.Key }
            $usage = Expand-CliPrefix $usage $menuPrefix
            Write-Output "| ``$usage`` | $(Expand-CliPrefix $item.Value.description $menuPrefix) |"
        }
        Write-Output ''
    }
}

# -Reset: the menu's scores start over from now. The marker, menuResetTimestamp
# in config.local.json, is written by Config -- the one writer of that file
# (AGENTS.md, "Configuration is written by Config, and by nothing else") -- so
# the file comes out the way Config writes it: no BOM, LF, the same bytes on
# both hosts. The script is run directly rather than through the Config verb,
# so the reset does not log a Config use that would head the fresh scores.
function global:Reset-P20MenuScoring {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'One marker key, written through the Config script, which owns validation and the write.')]
    [CmdletBinding()]
    param([string]$Name)
    $s = Get-P20ModuleState
    if (-not $Name) { $Name = "$($s.CommandPrefix)Menu" }
    $root = $s.PackageRoot
    $localCfgPath = Join-Path $root 'config.local.json'
    if (Test-Path $localCfgPath) {
        # A file that will not parse is left exactly as it is: writing the marker
        # into what was read (nothing) would replace the person's settings.
        try { $null = Get-Content $localCfgPath -Raw | ConvertFrom-Json }
        catch {
            $null = Write-P20ConfigParseWarning -Path $localCfgPath -Message $_.Exception.Message
            Write-WrapperRefusal -Name $Name -Message "config.local.json will not parse, so the menu scores were not reset." `
                -Hint 'Fix the file by hand (or delete it); it was not changed.'
            return
        }
    }
    $stamp = Get-Date -Format 'yyyy-MM-ddTHH:mm:ss'
    $configScript = Join-Path (Join-Path $root 'Scripts') 'Set-ToolkitConfig.ps1'
    # Config's own lines ("[+] menuResetTimestamp ...") are kept back on success:
    # the reset says what it did in its own sentence. A refusal is printed as
    # Config stated it, and its exit code is left for the caller.
    $global:LASTEXITCODE = 0
    try { $out = & $configScript -Set "menuResetTimestamp=$stamp" *>&1 | Out-String }
    catch {
        Write-WrapperRefusal -Name $Name -Message "The menu scores were not reset: $($_.Exception.Message)" `
            -Hint "Run '$($s.CommandPrefix)Log -Errors' for details."
        return
    }
    $code = $LASTEXITCODE
    if ($code) {
        Write-Host $out.TrimEnd()
        Write-ToolkitLog -Type ERR -Source $Name -Detail "scores not reset: Config exit $code"
        $global:LASTEXITCODE = $code
        return
    }
    Write-Host "  Menu scores reset. Usage scoring starts fresh from now." -ForegroundColor Green
    Write-ToolkitLog -Type INFO -Source $Name -Detail 'scores reset'
}

# The menu itself: default (the most used) and -All (everything, by category,
# and the opt-in inventory). The other three switches hand off above.
function global:Get-P20Menu {
    [CmdletBinding()]
    param(
        [switch]$All,
        [switch]$Help,
        [switch]$Reset,
        [switch]$Markdown
    )
    $s = Get-P20ModuleState
    $inv = Resolve-InvokedCommand $MyInvocation.InvocationName 'Menu'

    # Label commands with the prefix actually used to invoke this menu, so
    # tkMenu and gtMenu each describe their own surface. Falls back to the
    # configured prefix when called by function name.
    $menuPrefix = $s.CommandPrefix
    if ($MyInvocation.InvocationName -match '^(.+)Menu$') { $menuPrefix = $Matches[1] }

    if ($Help) { Show-P20MenuHelp -Prefix $menuPrefix; return }
    if ($Markdown) { Get-P20MenuMarkdown -Prefix $menuPrefix; return }
    if ($Reset) { Reset-P20MenuScoring -Name $inv.Name; return }

    $cmds = $s.Commands
    $tier = Get-CurrentTier
    $errCount = Get-RecentErrors

    # Azure DevOps is something you plug in. When it is not in use -- features.ado,
    # else the status of the org you are in -- its verbs are not SHOWN: a person who
    # has just made a hub of sample cards is not handed a menu that opens on "Pull
    # Requests" and seven verbs they cannot use. When it IS in use this block
    # changes nothing, which is the requirement (D-A2: not disruptive). The verbs
    # stay registered either way; this is the visible half (docs/modules/ado.md, "The switch, and its scope").
    # The rows are the TRACKER verbs: on a connected GitHub Space they answer
    # through gh, so they are shown there too, while the Azure DevOps surface
    # itself reads off (Test-P20AdoEnabled asks the tracker as well as
    # the status; a GitHub tracker is not Azure DevOps).
    $menuFeatures = Get-P20Features
    $adoFlag = $null
    if ($menuFeatures.ContainsKey('ado')) { $adoFlag = $menuFeatures['ado'] }
    $menuTracker = Resolve-P20Tracker -OrgUrl ([string]$s.Config.Org)
    $adoEnabled = Test-P20AdoEnabled -OrgStatus $s.Config.OrgStatus -Flag $adoFlag -Tracker $menuTracker
    $trackerShown = $adoEnabled -or ($menuTracker -eq 'github' -and $s.Config.OrgStatus -eq 'active')
    if (-not $trackerShown) {
        $shown = @{}
        foreach ($entry in $cmds.GetEnumerator()) {
            if ($entry.Key -in $s.AdoCommands) { continue }
            # A COPY: the table is the module's, and -Help and the bridge read it too.
            $value = @{}
            foreach ($k in $entry.Value.Keys) { $value[$k] = $entry.Value[$k] }
            # A verb that works both ways describes the way this machine uses it.
            if ($value.descriptionWithoutAdo) { $value.description = $value.descriptionWithoutAdo }
            # "Pull Requests" and "Work Items" are Azure DevOps's headings. What is
            # left under them with ADO gone -- making a card, threading its commits
            # -- is card work, and is listed with the rest of it.
            if ($value.category -eq 'pr' -or $value.category -eq 'work') { $value.category = 'prompt' }
            $shown[$entry.Key] = $value
        }
        $cmds = $shown
    }

    if ($All) {
        # -- Full view: grouped by intent category, with availability flags --
        Write-Host ""
        $catOrder = @('nav', 'pr', 'work', 'prompt', 'sync', 'sprint', 'review', 'growth', 'organize', 'studio', 'rituals', 'org', 'setup', 'info', 'test')
        foreach ($cat in $catOrder) {
            $items = $cmds.GetEnumerator() | Where-Object { $_.Value.category -eq $cat } | Sort-Object Key
            if (-not $items) {
                # Navigation is the one category that is NAMED before it is
                # configured. Its members come from nav aliases with a path, and
                # a path is personal, so the three shipped ones are empty and the
                # category used to vanish -- a shipped feature that looked absent.
                #
                # Same idiom as the Tier-2 `(unavailable)` marker below: the CLI
                # shows an empty state rather than hiding the surface. ASCII only
                # -- Test-PS51Compat scans for a dash that Windows-1252 misreads.
                if ($cat -ne 'nav') { continue }
                $navSurface = @(Get-P20OptionalSurfaces -Config $s.Config -Features (Get-P20Features) `
                    -NavAliases (Get-P20NavAliases) -Prefix $menuPrefix -PackageRoot $s.PackageRoot |
                    Where-Object { $_.key -eq 'aliases' })
                Write-Host "  Navigation" -ForegroundColor Yellow
                Write-Host "    not configured" -ForegroundColor DarkGray
                if ($navSurface.Count -eq 1) {
                    Write-Host "      $($navSurface[0].config)" -ForegroundColor DarkGray
                }
                Write-Host ""
                continue
            }

            $label = switch ($cat) {
                'nav' { 'Navigation' }
                'pr' { 'Pull Requests' }
                'work' { 'Work Items' }
                'prompt' { if ($adoEnabled) { 'Prompts' } else { 'Cards' } }
                'sync' { 'Sync' }
                'sprint' { 'Sprint Awareness' }
                'review' { 'Reviews & Reporting' }
                'growth' { 'Growth & Meetings' }
                'organize' { 'Organize' }
                'studio' { 'Studio' }
                'rituals' { 'Team Agile' }
                'org' { 'Org & Infra' }
                'setup' { 'Setup' }
                'info' { 'Info' }
                'test' { 'Tests' }
            }
            Write-Host "  $label" -ForegroundColor Yellow
            foreach ($item in $items) {
                $name = ($menuPrefix + $item.Key).PadRight(22)
                $flag = ''
                if ($tier -ge 2 -and $item.Key -in $s.AdoCommands) {
                    $flag = '(unavailable) '
                    Write-Host "    $name $flag$(Expand-CliPrefix $item.Value.description $menuPrefix)" -ForegroundColor DarkGray
                }
                else {
                    Write-Host "    $name $(Expand-CliPrefix $item.Value.description $menuPrefix)" -ForegroundColor Gray
                }
            }
            Write-Host ""
        }

        # -- What this machine is NOT doing ------------------------------------
        # The core workflow is above; this names every surface that is opt in,
        # its state, and the line that changes it, so a machine can say what it
        # has switched off rather than looking like it does not have it
        # (AGENTS.md, "Opt in by configuration"). Naming a module is not
        # mounting it: with the flag off there is still no verb, no -Help, no
        # bridge entry, no route, no nav entry and no card -- the listing is the
        # inventory, the categories above are the surface you can use now.
        Write-Host "  Opt in by configuration" -ForegroundColor Yellow
        foreach ($surface in (Get-P20OptionalSurfaces -Config $s.Config -Features (Get-P20Features) `
                -NavAliases (Get-P20NavAliases) -Prefix $menuPrefix -PackageRoot $s.PackageRoot)) {
            $state = $surface.state
            if ($surface.note) { $state = "$state ($($surface.note))" }
            if ($surface.question) { Write-Host "    $($surface.question)" -ForegroundColor White }
            Write-Host ("    {0} {1}" -f $surface.title.PadRight(22), $state) -ForegroundColor Gray
            Write-Host ("      {0}" -f $surface.config) -ForegroundColor DarkGray
        }
        Write-Host ""

        # Error indicator
        if ($errCount -gt 0) {
            Write-Host "  [!] $errCount error$(if($errCount -ne 1){'s'}) in last 24h -- $(Get-CliPrefix)Log -Errors to review" -ForegroundColor Red
            Write-Host ""
        }
        # Degraded mode indicator
        # Only where ADO verbs are on screen: with Azure DevOps not in use, nothing
        # shown is unavailable, so there is nothing to apologise for.
        if ($tier -ge 2 -and $adoEnabled) {
            Write-Host "  [*] Local mode -- ADO commands unavailable -- $(Get-CliPrefix)Env for details" -ForegroundColor Yellow
            Write-Host ""
        }
    }
    else {
        # -- Default view: top 6 by score --
        $scores = Get-P20CommandScores -CommandNames @($cmds.Keys) -Prefix $menuPrefix

        # Build ranked list from commands that have scores
        $ranked = @()
        foreach ($entry in $scores.GetEnumerator()) {
            if ($cmds.ContainsKey($entry.Key)) {
                $ranked += [PSCustomObject]@{
                    Name        = $entry.Key
                    Score       = $entry.Value
                    Description = $cmds[$entry.Key].description
                }
            }
        }
        $ranked = $ranked | Sort-Object Score -Descending | Select-Object -First 6

        Write-Host ""
        if ($ranked.Count -gt 0) {
            Write-Host "  Most used commands" -ForegroundColor Yellow
            Write-Host ""
            foreach ($r in $ranked) {
                # The bare key, printed under the prefix this menu was asked for.
                $name = ($menuPrefix + $r.Name).PadRight(22)
                Write-Host "    $name $(Expand-CliPrefix $r.Description)" -ForegroundColor Gray
            }
        }
        else {
            Write-Host "  No usage data yet - commands will appear here as you use them." -ForegroundColor DarkGray
            Write-Host ""
            # Fallback: show nav + the default-shown intent categories (pr/work/prompt/review)
            # 'sync' is here so Sync and Update are seen TOGETHER: the everyday
            # menu used to offer the hub's verb and hide the Toolkit's under -All.
            foreach ($cat in @('nav', 'pr', 'work', 'prompt', 'sync', 'review')) {
                $items = $cmds.GetEnumerator() | Where-Object { $_.Value.category -eq $cat } | Sort-Object Key
                if (-not $items) { continue }
                $label = switch ($cat) {
                    'nav' { 'Navigation' }
                    'pr' { 'Pull Requests' }
                    'work' { 'Work Items' }
                    'prompt' { if ($adoEnabled) { 'Prompts' } else { 'Cards' } }
                    'sync' { 'Sync' }
                    'review' { 'Reviews & Reporting' }
                }
                Write-Host "  $label" -ForegroundColor Yellow
                foreach ($item in $items) {
                    $name = ($menuPrefix + $item.Key).PadRight(22)
                    Write-Host "    $name $(Expand-CliPrefix $item.Value.description $menuPrefix)" -ForegroundColor Gray
                }
                Write-Host ""
            }
        }
        Write-Host ""

        # Error indicator
        if ($errCount -gt 0) {
            Write-Host "  [!] $errCount error$(if($errCount -ne 1){'s'}) in last 24h -- $(Get-CliPrefix)Log -Errors to review" -ForegroundColor Red
        }
        # Degraded mode indicator
        # Only where ADO verbs are on screen: with Azure DevOps not in use, nothing
        # shown is unavailable, so there is nothing to apologise for.
        if ($tier -ge 2 -and $adoEnabled) {
            Write-Host "  [*] Local mode -- ADO commands unavailable -- $(Get-CliPrefix)Env for details" -ForegroundColor Yellow
        }

        Write-Host "  $($menuPrefix)Menu -All for full command list" -ForegroundColor DarkGray
        Write-Host ""
    }
}

# -- ADO workflow functions ---------------------------------------------------

function global:Get-P20MyWorkItems {
    [CmdletBinding()]
    param(
        [string]$State,
        [switch]$Help
    )
    $inv = Resolve-InvokedCommand $MyInvocation.InvocationName 'MyWork'
    if ($Help) { Show-CommandHelp 'MyWork'; return }
    if (-not (Test-AdoAvailable $inv.Name)) { return }
    & "$toolkitRoot\Scripts\Get-MyWorkItems.ps1" @PSBoundParameters
}

function global:Get-P20PromptFromWorkItem {
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)][Alias('Id')][string]$WorkItemId,
        [string]$Title,
        [string]$Type,
        [string]$AssignTo,
        [string]$Date,
        [switch]$ReadOnly,
        [switch]$Force,
        [string]$OutputFolder,
        [switch]$Now,
        [string]$Cover,
        [string]$Before,
        [string]$Design,
        [switch]$Help
    )
    $inv = Resolve-InvokedCommand $MyInvocation.InvocationName 'NewPrompt'
    Write-P20DeprecationHint $MyInvocation.InvocationName
    # -Title is the offline path and makes no ADO call, so the ADO gate must not
    # stand in front of it -- it is the Tier-2 half of this verb. -Help was
    # gated too, which meant a Tier-2 machine could not even read how to use it.
    if (-not $Help -and -not $Title -and -not (Test-AdoAvailable $inv.Name)) { return }
    Invoke-ToolkitScript -Path "$toolkitRoot\Scripts\New-PromptFromWorkItem.ps1" -Parameters $PSBoundParameters `
        -Name $inv.Name -Prefix $inv.Prefix
}

function global:Get-P20MyPRs {
    [CmdletBinding()]
    param(
        [switch]$CreatorOnly,
        [switch]$Help
    )
    $inv = Resolve-InvokedCommand $MyInvocation.InvocationName 'MyPRs'
    # The script has no -Help: forwarding it was a binding error that exited 0
    # and pointed at `MyPRs -Help` for usage.
    if ($Help) { Show-CommandHelp 'MyPRs'; return }
    if (-not (Test-AdoAvailable $inv.Name)) { return }
    Invoke-ToolkitScript -Path "$toolkitRoot\Scripts\Get-MyPRs.ps1" -Parameters $PSBoundParameters `
        -Name $inv.Name -Prefix $inv.Prefix
}

function global:Get-P20Dashboard {
    [CmdletBinding()]
    param([switch]$Help)
    $inv = Resolve-InvokedCommand $MyInvocation.InvocationName 'Dashboard'
    if ($Help) { Show-CommandHelp 'Dashboard'; return }
    # No tier gate: the script has its own Tier-2 path that shows local prompts
    # and repo status when ADO is unreachable, which is the more useful failure.
    Invoke-ToolkitScript -Path "$toolkitRoot\Scripts\Get-DailyDashboard.ps1" -Parameters $PSBoundParameters `
        -Name $inv.Name -Prefix $inv.Prefix
}

function global:Close-P20WorkItem {
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)]
        [int]$Id,
        [string]$Comment,
        # No ValidateSet here either: the script passes unknown reasons through so
        # the project's process template decides. See Scripts/Close-WorkItem.ps1.
        [string]$Reason,
        [switch]$WhatIf,
        [switch]$Help
    )
    $inv = Resolve-InvokedCommand $MyInvocation.InvocationName 'CloseItem'
    Write-P20DeprecationHint $MyInvocation.InvocationName
    # -Help falls through to the script, which carries the fuller help -- and it is
    # checked before the tier gate so usage is readable on a machine without ADO.
    if (-not $Help -and -not (Test-AdoAvailable $inv.Name)) { return }
    Invoke-ToolkitScript -Path "$toolkitRoot\Scripts\Close-WorkItem.ps1" -Parameters $PSBoundParameters `
        -Name $inv.Name -Prefix $inv.Prefix
}

function global:Edit-P20WorkItem {
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)]
        [int]$Id,
        [string]$Title,
        [string]$Description,
        [string]$Sprint,
        [string]$AssignTo,
        [string]$AddTag,
        [string]$RemoveTag,
        [switch]$Pin,
        [switch]$Unpin,
        [switch]$WhatIf,
        [switch]$Help
    )
    $inv = Resolve-InvokedCommand $MyInvocation.InvocationName 'EditItem'
    Write-P20DeprecationHint $MyInvocation.InvocationName
    if (-not $Help -and -not (Test-AdoAvailable $inv.Name)) { return }
    Invoke-ToolkitScript -Path "$toolkitRoot\Scripts\Edit-WorkItem.ps1" -Parameters $PSBoundParameters `
        -Name $inv.Name -Prefix $inv.Prefix
}

function global:Connect-P20Space {
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
    # Never gated on the tracker: this is how a Space GETS a tracker.
    $inv = Resolve-InvokedCommand $MyInvocation.InvocationName 'Connect'
    Invoke-ToolkitScript -Path "$toolkitRoot\Scripts\Connect-Space.ps1" -Parameters $PSBoundParameters `
        -Name $inv.Name -Prefix $inv.Prefix
}

function global:Invoke-P20PRReview {
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)]
        [int]$PullRequestId,
        [string]$Repository,
        [string]$Project,
        [string]$Model,
        [switch]$DryRun,
        [switch]$Help
    )
    $inv = Resolve-InvokedCommand $MyInvocation.InvocationName 'AddPRReview'
    if ($Help) { Show-CommandHelp 'AddPRReview'; return }
    if (-not (Test-AdoAvailable $inv.Name)) { return }
    # Optional by design (docs/CLI.md, "AI review (optional)"): no key, no command -- and say so rather than
    # failing inside an HTTP call. Nothing in the core workflow depends on this.
    if (-not $env:ANTHROPIC_API_KEY -and -not $env:CLAUDE_API_KEY) {
        Write-WrapperRefusal -Name $inv.Name -Message "$($inv.Name) needs ANTHROPIC_API_KEY; it is not set." `
            -Hint "Set ANTHROPIC_API_KEY in the environment, or copy .env.example to .env beside this package and set it there. Every other command works without it."
        return
    }
    Invoke-ToolkitScript -Path "$toolkitRoot\Scripts\Invoke-PRReview.ps1" -Parameters $PSBoundParameters `
        -Name $inv.Name -Prefix $inv.Prefix
}

# SupportsShouldProcess so -WhatIf binds natively and reaches the script through
# @PSBoundParameters, the way InstallAutoload's does.
function global:Update-P20Toolkit {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSShouldProcess', '', Justification='Delegated to inner script via -Parameters')]
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [switch]$Sync,
        [switch]$Help
    )
    $inv = Resolve-InvokedCommand $MyInvocation.InvocationName 'Update'
    if ($Help) { Show-CommandHelp 'Update'; return }
    Invoke-ToolkitScript -Path "$toolkitRoot\Scripts\Update-Toolkit.ps1" -Parameters $PSBoundParameters `
        -Name $inv.Name -Prefix $inv.Prefix
}

function global:Sync-P20Prompts {
    [CmdletBinding()]
    param(
        [switch]$Help
    )
    $inv = Resolve-InvokedCommand $MyInvocation.InvocationName 'Sync'
    if ($Help) { Show-CommandHelp 'Sync'; return }
    Invoke-ToolkitScript -Path "$toolkitRoot\Scripts\Sync-Prompts.ps1" -Arguments $args `
        -Name $inv.Name -Prefix $inv.Prefix
}

# The first run. SupportsShouldProcess so -WhatIf binds natively and reaches the
# script through @PSBoundParameters, as Update's does.
function global:Start-P20Toolkit {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSShouldProcess', '', Justification='Delegated to inner script via -Parameters')]
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [string]$Path,
        [switch]$NoWeb,
        [switch]$Help
    )
    $inv = Resolve-InvokedCommand $MyInvocation.InvocationName 'Start'
    if ($Help) { Show-CommandHelp 'Start'; return }
    Invoke-ToolkitScript -Path "$toolkitRoot\Scripts\Start-Toolkit.ps1" -Parameters $PSBoundParameters `
        -Name $inv.Name -Prefix $inv.Prefix
}

function global:Move-P20PromptToArchive {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSShouldProcess', '', Justification='Delegated to inner script via @PSBoundParameters')]
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [string]$File,
        [switch]$List,
        [switch]$Relink,
        [switch]$Help
    )
    $inv = Resolve-InvokedCommand $MyInvocation.InvocationName 'Archive'
    Invoke-ToolkitScript -Path "$toolkitRoot\Scripts\Move-PromptToArchive.ps1" -Parameters $PSBoundParameters `
        -Name $inv.Name -Prefix $inv.Prefix
}

function global:Get-P20PromptStatus {
    [CmdletBinding()]
    param(
        [switch]$Board,
        [switch]$Help
    )
    # Through the one guard, so -Board's stated refusal (exit 2) is carried to the
    # caller and the bridge as a refusal rather than reading as success.
    $inv = Resolve-InvokedCommand $MyInvocation.InvocationName 'Status'
    Invoke-ToolkitScript -Path "$toolkitRoot\Scripts\Get-PromptStatus.ps1" -Parameters $PSBoundParameters `
        -Name $inv.Name -Prefix $inv.Prefix
}

function global:Get-P20PRComments {
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)][int]$PullRequestId,
        [string]$BranchName,
        [string]$Repository,
        [string]$Project,
        [string]$OutputFile,
        [switch]$Help
    )
    $inv = Resolve-InvokedCommand $MyInvocation.InvocationName 'GetPRComments'
    # -Help answers before the tier is asked: help is not an ADO call.
    if ($Help) { & "$toolkitRoot\Scripts\Get-PRComments.ps1" -Help; return }
    if (-not (Test-AdoAvailable $inv.Name)) { return }
    Invoke-ToolkitScript -Path "$toolkitRoot\Scripts\Get-PRComments.ps1" -Parameters $PSBoundParameters `
        -Name $inv.Name -Prefix $inv.Prefix
}

function global:Send-P20PRReply {
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)][int]$PullRequestId,
        [Parameter(Position = 1)][int]$ThreadId,
        [string]$Reply,
        [string]$Status,
        [string]$Repository,
        [string]$Project,
        [switch]$Help
    )
    $inv = Resolve-InvokedCommand $MyInvocation.InvocationName 'ReplyPR'
    if ($Help) { & "$toolkitRoot\Scripts\Send-PRReply.ps1" -Help; return }
    if (-not (Test-AdoAvailable $inv.Name)) { return }
    # Through the one guard like every other verb: logged as a CMD line, and a
    # stated refusal (exit 2) reaches the bridge as an error rather than success.
    Invoke-ToolkitScript -Path "$toolkitRoot\Scripts\Send-PRReply.ps1" -Parameters $PSBoundParameters `
        -Name $inv.Name -Prefix $inv.Prefix
}

# SupportsShouldProcess so -WhatIf binds natively and reaches the script through
# -Parameters. -WhatIf passes the tier gate: it reads config and the card and calls
# nothing, so it is how a machine without az sees what NewPR would do.
function global:New-P20PullRequest {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSShouldProcess', '', Justification='Delegated to inner script via -Parameters')]
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Position = 0)]
        [string]$File,
        [string]$TargetBranch,
        [switch]$Draft,
        [switch]$AutoComplete,
        [switch]$SkipWorkItem,
        [string]$Repository,
        [string]$Project,
        [switch]$Help
    )
    $inv = Resolve-InvokedCommand $MyInvocation.InvocationName 'NewPR'
    Write-P20DeprecationHint $MyInvocation.InvocationName
    if ($Help) { & "$toolkitRoot\Scripts\New-PullRequest.ps1" -Help; return }
    if (-not $WhatIfPreference -and -not (Test-AdoAvailable $inv.Name)) { return }
    Invoke-ToolkitScript -Path "$toolkitRoot\Scripts\New-PullRequest.ps1" -Parameters $PSBoundParameters `
        -Name $inv.Name -Prefix $inv.Prefix
}

# Stage 2 of the ship flow: the card's draft pull request, published. The same
# shape as NewPR -- SupportsShouldProcess so -WhatIf binds and reaches the script,
# and -WhatIf passes the tier gate because it calls nothing.
function global:Publish-P20PullRequest {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSShouldProcess', '', Justification='Delegated to inner script via -Parameters')]
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Position = 0)]
        [string]$Card,
        [switch]$Help
    )
    $inv = Resolve-InvokedCommand $MyInvocation.InvocationName 'PublishPR'
    if ($Help) { & "$toolkitRoot\Scripts\Publish-PullRequest.ps1" -Help; return }
    if (-not $WhatIfPreference -and -not (Test-AdoAvailable $inv.Name)) { return }
    Invoke-ToolkitScript -Path "$toolkitRoot\Scripts\Publish-PullRequest.ps1" -Parameters $PSBoundParameters `
        -Name $inv.Name -Prefix $inv.Prefix
}

function global:Get-P20Environment {
    [CmdletBinding()]
    param(
        [switch]$Startup,
        [switch]$Help
    )
    if (-not $Startup -and -not $Help) { Update-P20StaleConfig }
    & "$toolkitRoot\Scripts\Get-Environment.ps1" @PSBoundParameters
}

function global:Get-P20ToolkitLog {
    [CmdletBinding()]
    param(
        [switch]$Errors,
        [switch]$Today,
        [int]$Days,
        [string]$Command,
        [ValidateSet('CMD', 'ERR', 'WARN', 'INFO')][string]$Type,
        [switch]$Clear,
        [switch]$Tail,
        [switch]$Ack,
        [switch]$Help,
        [int]$Count
    )
    # No success line: a CMD line for every read would be a new entry in the
    # very log being read, and -Clear would leave one behind in the fresh file.
    $inv = Resolve-InvokedCommand $MyInvocation.InvocationName 'Log'
    Invoke-ToolkitScript -Path "$toolkitRoot\Scripts\Get-ToolkitLog.ps1" -Parameters $PSBoundParameters `
        -Name $inv.Name -Prefix $inv.Prefix -NoSuccessLog
}

function global:Test-P20Prerequisites {
    [CmdletBinding()]
    param(
        [switch]$Help
    )
    & "$toolkitRoot\Scripts\Test-Prerequisites.ps1" @PSBoundParameters
}

function global:Move-P20CardLane {
    [CmdletBinding()]
    param(
        [string]$Card,
        [string]$To,
        [switch]$Help
    )
    $inv = Resolve-InvokedCommand $MyInvocation.InvocationName 'Move'
    Invoke-ToolkitScript -Path "$toolkitRoot\Scripts\Move-CardLane.ps1" -Parameters $PSBoundParameters `
        -Name $inv.Name -Prefix $inv.Prefix
}

function global:Set-P20CardBillable {
    [CmdletBinding()]
    param(
        [string]$Card,
        [switch]$No,
        [switch]$Help
    )
    $inv = Resolve-InvokedCommand $MyInvocation.InvocationName 'Billable'
    Invoke-ToolkitScript -Path "$toolkitRoot\Scripts\Set-CardBillable.ps1" -Parameters $PSBoundParameters `
        -Name $inv.Name -Prefix $inv.Prefix
}

function global:Set-P20CardCover {
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)][string]$Card,
        [Parameter(Position = 1)][string]$Image,
        [switch]$Before,
        [switch]$Remove,
        [switch]$Samples,
        [switch]$WhatIf,
        [switch]$Help
    )
    $inv = Resolve-InvokedCommand $MyInvocation.InvocationName 'Cover'
    Invoke-ToolkitScript -Path "$toolkitRoot\Scripts\Set-CardCover.ps1" -Parameters $PSBoundParameters `
        -Name $inv.Name -Prefix $inv.Prefix
}

function global:Set-P20CardSprint {
    <# Plan -- the write side of the Sprint token: -Milestone stamps **Sprint:**, -Remove clears it. Never touches the tracker. #>
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)][string]$Card,
        [string]$Milestone,
        [switch]$Remove,
        [switch]$Help
    )
    $inv = Resolve-InvokedCommand $MyInvocation.InvocationName 'Plan'
    Invoke-ToolkitScript -Path "$toolkitRoot\Scripts\Plan-Card.ps1" -Parameters $PSBoundParameters `
        -Name $inv.Name -Prefix $inv.Prefix
}

# The Studio's two verbs. The Studio is core, from day one (D-S13): there is no features.studio, so these are registered like every
# other core verb -- in the command table below, the autoload manifest and the
# bridge -- rather than contributed by a module data file under a flag.
function global:New-P20DesignNote {
    <# NewDesign -- one design note in the hub's design/. #>
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)][string]$Title,
        [string]$Description,
        [string]$Space,
        [switch]$Help
    )
    if ($Help) { Show-CommandHelp 'NewDesign'; return }
    $inv = Resolve-InvokedCommand $MyInvocation.InvocationName 'NewDesign'
    Invoke-ToolkitScript -Path "$toolkitRoot\Scripts\New-DesignNote.ps1" -Parameters $PSBoundParameters `
        -Name $inv.Name -Prefix $inv.Prefix
}

function global:Set-P20DesignStamp {
    <# StampDesign -- an id on every design note and spec of a repo, or of the hub. #>
    [CmdletBinding()]
    param(
        [switch]$Hub,
        [switch]$WhatIf,
        [switch]$Help
    )
    if ($Help) { Show-CommandHelp 'StampDesign'; return }
    $inv = Resolve-InvokedCommand $MyInvocation.InvocationName 'StampDesign'
    Invoke-ToolkitScript -Path "$toolkitRoot\Scripts\Set-DesignStamp.ps1" -Parameters $PSBoundParameters `
        -Name $inv.Name -Prefix $inv.Prefix
}

function global:Move-P20Design {
    <# MoveDesign -- move a design along its road: to a spec, the archive, or complete (L3). #>
    [CmdletBinding()]
    param(
        [string]$Name,
        [string]$To,
        [switch]$Dropped,
        [string]$Reason,
        [string]$Doc,
        [switch]$Hub,
        [string]$Space,
        [switch]$WhatIf,
        [switch]$Help
    )
    if ($Help) { Show-CommandHelp 'MoveDesign'; return }
    $inv = Resolve-InvokedCommand $MyInvocation.InvocationName 'MoveDesign'
    Invoke-ToolkitScript -Path "$toolkitRoot\Scripts\Move-Design.ps1" -Parameters $PSBoundParameters `
        -Name $inv.Name -Prefix $inv.Prefix
}

function global:New-P20Space {
    <# NewSpace -- add a Space: a GitHub repository, an Azure DevOps organisation, or your own cards. #>
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)][string]$Slug,
        [string]$Repo,
        [string]$Address,
        [string]$Name,
        [switch]$Discover,
        [string]$Owner,
        [switch]$AsJson,
        [switch]$WhatIf,
        [switch]$Help
    )
    if ($Help) { Show-CommandHelp 'NewSpace'; return }
    # Never gated on the tracker: this is how a Space comes to exist.
    $inv = Resolve-InvokedCommand $MyInvocation.InvocationName 'NewSpace'
    Invoke-ToolkitScript -Path "$toolkitRoot\Scripts\New-Space.ps1" -Parameters $PSBoundParameters `
        -Name $inv.Name -Prefix $inv.Prefix
}

function global:Invoke-P20RetireSpace {
    <# RetireSpace -- the engagement is over, keep the record: status archive, through Config. #>
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)][string]$Slug,
        [switch]$WhatIf,
        [switch]$Help
    )
    if ($Help) { Show-CommandHelp 'RetireSpace'; return }
    $inv = Resolve-InvokedCommand $MyInvocation.InvocationName 'RetireSpace'
    Invoke-ToolkitScript -Path "$toolkitRoot\Scripts\Retire-Space.ps1" -Parameters $PSBoundParameters `
        -Name $inv.Name -Prefix $inv.Prefix
}

function global:Remove-P20Space {
    <# RemoveSpace -- un-declare a Space through Config; its folder and cards stay. #>
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)][string]$Slug,
        [switch]$Force,
        [switch]$WhatIf,
        [switch]$Help
    )
    if ($Help) { Show-CommandHelp 'RemoveSpace'; return }
    $inv = Resolve-InvokedCommand $MyInvocation.InvocationName 'RemoveSpace'
    Invoke-ToolkitScript -Path "$toolkitRoot\Scripts\Remove-Space.ps1" -Parameters $PSBoundParameters `
        -Name $inv.Name -Prefix $inv.Prefix
}

function global:Add-P20CommitHash {
    [CmdletBinding()]
    param(
        [string]$File,
        [string]$Hash,
        [switch]$Help
    )
    # The script logs its own CMD line (with the count it threaded), so the
    # guard adds only what the script cannot: the ERR line and the re-raise.
    $inv = Resolve-InvokedCommand $MyInvocation.InvocationName 'ThreadHash'
    Invoke-ToolkitScript -Path "$toolkitRoot\Scripts\Thread-CommitHash.ps1" -Parameters $PSBoundParameters `
        -Name $inv.Name -Prefix $inv.Prefix -NoSuccessLog
}

function global:Start-P20Web {
    [CmdletBinding()]
    param(
        [switch]$Dev,
        # The smoke's servers against Tests/fixtures/hub, as a test run, with
        # nothing written to config.local.json. Scripts/Start-Web.ps1.
        [switch]$Fixture,
        [ValidateSet('on', 'off')]
        [string]$Modules,
        [switch]$Stop,
        [switch]$Restart,
        [switch]$Status,
        # Documented in config.default.json's usage line since the browser-open
        # landed, and once missing from this block: the binder
        # rejected it before the script ran, so the documented way for a
        # non-interactive caller to keep the browser shut started nothing --
        # and a binding error sets no $LASTEXITCODE, so it reported success.
        # Tests/Test-Menu.ps1's wrapper-parity case now holds every verb to
        # this.
        [switch]$NoBrowser,
        [switch]$Help
    )
    if ($Help) { Show-CommandHelp 'Web'; return }
    # Forwarded, not wrapped in a try/catch that re-reports. This script owns
    # its own failures: it calls Write-CliError, logs ERR and exits non-zero,
    # and Tests/Test-Web.ps1 asserts all three. A second report from here would
    # print 'Error: exit code 1' under the readable one the script just gave.
    & "$toolkitRoot\Scripts\Start-Web.ps1" @PSBoundParameters
}

# SupportsShouldProcess so -WhatIf binds natively (clause 9) rather than as a
# user-defined switch the wrapper would have to forward by hand.
function global:Install-P20ToolkitAutoload {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSShouldProcess', '', Justification='Delegated to inner script via @PSBoundParameters')]
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [switch]$Force,
        [switch]$Remove,
        [switch]$Help
    )
    if ($Help) { Show-CommandHelp 'InstallAutoload'; return }
    # The script logs its own CMD line (installed or removed), so no second one.
    $inv = Resolve-InvokedCommand $MyInvocation.InvocationName 'InstallAutoload'
    Invoke-ToolkitScript -Path "$toolkitRoot\Scripts\Install-ToolkitAutoload.ps1" -Parameters $PSBoundParameters `
        -Name $inv.Name -Prefix $inv.Prefix -NoSuccessLog
}

function global:Start-P20Agent {
    [CmdletBinding()]
    param(
        [switch]$Stop,
        [switch]$Status,
        [switch]$Dev,
        [int]$Port,
        [switch]$Help
    )
    if ($Help) { Show-CommandHelp 'Agent'; return }
    # Forwarded, not wrapped in a try/catch that re-reports. This script owns
    # its own failures: it calls Write-CliError, logs ERR and exits non-zero,
    # and Tests/Test-Agent.ps1 asserts all three. A second report from here would
    # print 'Error: exit code 1' under the readable one the script just gave, and
    # the guard's own ERR line would be a second entry for the same refusal.
    # Tests/Test-Menu.ps1 lists this wrapper (and Web's) as the deliberate
    # exceptions to "a script that exits 2 is reached through the guard".
    & "$toolkitRoot\Scripts\Start-Agent.ps1" @PSBoundParameters
}

function global:Switch-P20Mode {
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)]
        [string]$Mode = "Status",
        [switch]$Help
    )
    Write-P20DeprecationHint $MyInvocation.InvocationName
    if ($Help) { Show-CommandHelp 'SwitchSpace'; return }
    $inv = Resolve-InvokedCommand $MyInvocation.InvocationName 'SwitchSpace'
    Invoke-ToolkitScript -Path "$toolkitRoot\Scripts\Switch-Mode.ps1" -Parameters $PSBoundParameters `
        -Name $inv.Name -Prefix $inv.Prefix
}

# The one writer for configuration. Goes through Invoke-ToolkitScript like
# every other script-backed verb, so a refusal it states (exit 2) is printed
# once, logged with its reason, and re-raised for the bridge -- which is what
# lets PUT /api/config hand the browser the sentence rather than a stack trace.
function global:Set-P20ToolkitConfig {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Delegated to the inner script via @PSBoundParameters; the script owns the refusal contract.')]
    [CmdletBinding()]
    param(
        [switch]$List,
        [string[]]$Set,
        [string[]]$Unset,
        [switch]$Schema,
        [switch]$AsJson,
        [switch]$Local,
        [switch]$Hub,
        [switch]$Help
    )
    $inv = Resolve-InvokedCommand $MyInvocation.InvocationName 'Config'
    if ($Help) { Show-CommandHelp 'Config'; return }
    Invoke-ToolkitScript -Path "$toolkitRoot\Scripts\Set-ToolkitConfig.ps1" -Parameters $PSBoundParameters `
        -Name $inv.Name -Prefix $inv.Prefix
}

function global:New-P20AdoItem {
    [CmdletBinding()]
    param(
        [ValidateSet("UserStory", "Task", "Bug", "Feature")]
        [string]$Type = "UserStory",
        [string]$Title,
        [string]$Description,
        [string]$Project,
        [int]$Parent = 0,
        [string]$Sprint,
        [string]$AssignTo,
        [int]$Priority = 0,
        [int]$Points = 0,
        [string]$AcceptanceCriteria,
        [string]$ReproSteps,
        [string]$Tags,
        [string]$FromDesign,
        [string]$FromCard,
        [switch]$ReadOnly,
        [switch]$WhatIf,
        [switch]$Help
    )
    $inv = Resolve-InvokedCommand $MyInvocation.InvocationName 'NewItem'
    Write-P20DeprecationHint $MyInvocation.InvocationName
    if ($Help) { & "$toolkitRoot\Scripts\New-AdoItem.ps1" -Help; return }
    # -FromCard on a Space with no tracker, or an Azure DevOps one, is the
    # script's to refuse in its own sentence ("no tracker to publish card K7M2
    # on"); the tier gate would name a tier instead. A GitHub Space still passes
    # the gate, because the publish asks gh.
    $tierGate = $true
    if ($PSBoundParameters.ContainsKey('FromCard')) {
        . "$toolkitRoot\Scripts\Resolve-Tracker.ps1"
        if ((Resolve-P20Tracker -OrgUrl ([string]$global:P20Config.Org)) -ne 'github') { $tierGate = $false }
    }
    if ($tierGate -and -not (Test-AdoAvailable $inv.Name)) { return }
    Invoke-ToolkitScript -Path "$toolkitRoot\Scripts\New-AdoItem.ps1" -Parameters $PSBoundParameters `
        -Name $inv.Name -Prefix $inv.Prefix -NoSuccessLog
}

# -- Test aliases --------------------------------------------------------------
# -Help is declared explicitly so it stays introspectable (Test-Menu.ps1
# asserts every command supports -Help via Get-Command parameter reflection).
# Everything else -- suite-selection switches -- is forwarded via
# ValueFromRemainingArguments rather than a hardcoded param list, which
# previously drifted from Test-Toolkit.ps1's own suite registry (most suites
# added since this wrapper was written weren't forwardable at all).
function global:Test-P20Toolkit {
    param(
        [switch]$Help,
        [Parameter(ValueFromRemainingArguments = $true)]$Rest
    )
    $forwardArgs = @()
    if ($Help) { $forwardArgs += '-Help' }
    if ($Rest) { $forwardArgs += $Rest }
    & pwsh -NoProfile -File "$toolkitRoot\Tests\Test-Toolkit.ps1" @forwardArgs
}

# All three halves -- the agent's pytest, this runner, the web UI's npm test --
# in one run with one summary and one verdict. A script-backed verb like
# any other: its switches are declared, and the guard reads its exit code.
function global:Invoke-P20TestAll {
    [CmdletBinding()]
    param(
        [ValidateSet('cli', 'agent', 'web')]
        [string]$Half,
        [switch]$Fast,
        [switch]$Help
    )
    if ($Help) { Show-CommandHelp 'Test'; return }
    $inv = Resolve-InvokedCommand $MyInvocation.InvocationName 'Test'
    Invoke-ToolkitScript -Path "$toolkitRoot\Scripts\Invoke-TestAll.ps1" -Parameters $PSBoundParameters `
        -Name $inv.Name -Prefix $inv.Prefix
}

# Convenience shortcuts - run a single suite by name
function global:Test-P20ToolkitCompat { param([switch]$Help) if ($Help) { Test-P20Toolkit -Help } else { Test-P20Toolkit -Compat } }
function global:Test-P20ToolkitMenu { param([switch]$Help) if ($Help) { Test-P20Toolkit -Help } else { Test-P20Toolkit -Menu } }
function global:Test-P20ToolkitSync { param([switch]$Help) if ($Help) { Test-P20Toolkit -Help } else { Test-P20Toolkit -Sync } }

# -- Export config so scripts can access it -----------------------------------
$global:P20Config = $script:ModuleState.Config
# The files this import read, and their write times.
$script:ModuleState.ConfigWatch = @($localConfigPath, $(if ($script:HubRoot) { Join-Path $script:HubRoot 'hub.json' } else { '' }))
$script:ModuleState.ConfigStamp = Get-P20ConfigStamp -Paths $script:ModuleState.ConfigWatch

# -- Startup: detect environment tier (silent on Tier 1) ----------------------
# TOOLKIT_QUIET_STARTUP is set by non-interactive callers (e.g. the agent) that
# parse a command's stdout as JSON; the startup banner would otherwise corrupt it.
# Startup banner is opt-out: config quietStart, or TOOLKIT_QUIET_STARTUP for a
# one-off in a shell that should stay silent (CI, agent tool calls, scripts).
$script:QuietStart = [bool]$env:TOOLKIT_QUIET_STARTUP
if ($defaultConfig -and $null -ne $defaultConfig.quietStart) { $script:QuietStart = [bool]$defaultConfig.quietStart }
if ($localConfig   -and $null -ne $localConfig.quietStart)   { $script:QuietStart = [bool]$localConfig.quietStart }
if ($env:TOOLKIT_QUIET_STARTUP) { $script:QuietStart = $true }
& "$toolkitRoot\Scripts\Get-Environment.ps1" -Startup -Quiet:$script:QuietStart
# The startup probe runs native commands (az) that may fail against the committed
# template org, leaving $LASTEXITCODE non-zero in the importing session. Every
# wrapper guard reads that variable after its script returns; without this
# reset the first verb after Import-Module reports "exit code 1" for a failure
# that was never its own.
$global:LASTEXITCODE = 0

# -- Command registration (prefix-driven) --------------------------------------
# The prefix is data, not code. Change commandPrefix in config to rename the
# whole surface; call Register-PromptAlias again to expose another prefix
# alongside it. Prefixes are independent -- nothing reconciles them.
$script:ModuleState.CommandMap = [ordered]@{
    'Menu'             = 'Get-P20Menu'
    'MyWork'           = 'Get-P20MyWorkItems'
    'Sync'             = 'Sync-P20Prompts'
    'Archive'          = 'Move-P20PromptToArchive'
    'Status'           = 'Get-P20PromptStatus'
    'Billable'         = 'Set-P20CardBillable'
    'Cover'            = 'Set-P20CardCover'
    'Move'             = 'Move-P20CardLane'
    'Plan'             = 'Set-P20CardSprint'
    'GetPRComments'    = 'Get-P20PRComments'
    'ReplyPR'          = 'Send-P20PRReply'
    'Env'              = 'Get-P20Environment'
    'Log'              = 'Get-P20ToolkitLog'
    'ThreadHash'       = 'Add-P20CommitHash'
    'Setup'            = 'Test-P20Prerequisites'
    'InstallAutoload'  = 'Install-P20ToolkitAutoload'
    'Update'           = 'Update-P20Toolkit'
    'Start'            = 'Start-P20Toolkit'
    'SwitchSpace'      = 'Switch-P20Mode'
    'SwitchOrg'        = 'Switch-P20Mode'   # deprecated, dual-mapped
    'Config'           = 'Set-P20ToolkitConfig'
    'NewPR'            = 'New-P20PullRequest'
    'PublishPR'        = 'Publish-P20PullRequest'
    'NewPrompt'        = 'Get-P20PromptFromWorkItem'
    'NewItem'          = 'New-P20AdoItem'
    'CloseItem'        = 'Close-P20WorkItem'
    'EditItem'         = 'Edit-P20WorkItem'
    'Connect'          = 'Connect-P20Space'
    'NewDesign'        = 'New-P20DesignNote'      # the Studio's, core since D-S13
    'StampDesign'      = 'Set-P20DesignStamp'
    'MoveDesign'       = 'Move-P20Design'          # the design lifecycle's one verb, core (L3)
    'NewSpace'         = 'New-P20Space'           # the Spaces card's +, core
    'RetireSpace'      = 'Invoke-P20RetireSpace'  # a Space's row menu, core
    'RemoveSpace'      = 'Remove-P20Space'        # a Space's row menu, core
    # Deprecated names, dual-mapped (see $script:ModuleState.DeprecatedAliases): the alias
    # still answers and the bridge still accepts it; the menu shows only the
    # canonical row because config.default.json names only that.
    'NewAdoItem'       = 'New-P20AdoItem'
    'CloseWorkItem'    = 'Close-P20WorkItem'
    'EditWorkItem'     = 'Edit-P20WorkItem'
    'Dashboard'        = 'Get-P20Dashboard'
    'MyPRs'            = 'Get-P20MyPRs'
    'AddPRReview'      = 'Invoke-P20PRReview'
    'Web'              = 'Start-P20Web'
    'Agent'            = 'Start-P20Agent'
    'Test'             = 'Invoke-P20TestAll'      # all three halves, one verdict
    'TestToolkit'      = 'Test-P20Toolkit'
    'TestCompat'       = 'Test-P20ToolkitCompat'
    'TestMenu'         = 'Test-P20ToolkitMenu'
    'TestSync'         = 'Test-P20ToolkitSync'
}

# The bridge's read of the table above, as JSON: { "Archive": "Move-P20PromptToArchive", ... }.
#
# The agent's POST /api/cmd/{name} derives its allowlist from this and from
# nothing else, so a command added as docs/ARCHITECTURE.md, "The bridge", says is bridgeable with no backend edit. That is the whole reason this
# exists: the package this was carved from hand-kept a second list of command
# names in Python, and a second list is how two lists drift.
#
# Deliberately NOT registered as a verb. The table is the user-facing surface;
# this is a read OF that surface for one machine consumer, and registering it
# would put a row in Menu, in -Help and in the docs for something no person
# types. Callers reach it by name -- utilities.psm1 defines it globally on
# import, exactly like every wrapper.
#
# -Compress so the caller gets one line: this is parsed, not read.
# Reads module state through Get-P20ModuleState, never `$script:`: reached
# from a module-launched script, `$script:` binds to that script and answers
# $null. Not a GetNewClosure() body either -- that is bound to a NEW dynamic
# module, where this function's private helpers are not visible.
function global:Get-P20CommandMap {
    [CmdletBinding()]
    param()
    $s = Get-P20ModuleState
    # One reserved key beside the verbs, `_timeouts`: name -> bridgeTimeoutSeconds
    # for every verb that declares one, from config.default.json for a core verb
    # and from Config/<module>.commands.psd1's Help for a module verb -- the
    # agent never reads a data file, so the one table it reads carries both.
    #
    $table = [ordered]@{}
    foreach ($k in $s.CommandMap.Keys) { $table[$k] = $s.CommandMap[$k] }
    $timeouts = [ordered]@{}
    foreach ($k in $s.CommandMap.Keys) {
        $help = $s.Commands[$k]
        if ($null -eq $help) { continue }
        $declared = $null
        if ($help -is [System.Collections.IDictionary]) { if ($help.Contains('bridgeTimeoutSeconds')) { $declared = $help['bridgeTimeoutSeconds'] } }
        elseif ($help.PSObject.Properties['bridgeTimeoutSeconds']) { $declared = $help.bridgeTimeoutSeconds }
        if ($null -ne $declared -and [int]$declared -gt 0) { $timeouts[$k] = [int]$declared }
    }
    $table['_timeouts'] = $timeouts
    return ($table | ConvertTo-Json -Compress)
}

# Reads module state through Get-P20ModuleState, never `$script:`: reached
# from a module-launched script, `$script:` binds to that script and answers
# $null. Not a GetNewClosure() body either -- that is bound to a NEW dynamic
# module, where this function's private helpers are not visible.
function global:Register-PromptAlias {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [ValidatePattern('^[A-Za-z][A-Za-z0-9]*$')]
        [string]$Prefix,

        [string[]]$Commands,

        [switch]$Force
    )
    $s = Get-P20ModuleState

    $names = $Commands
    if (-not $names) { $names = @($s.CommandMap.Keys) }

    foreach ($n in $names) {
        if (-not $s.CommandMap.Contains($n)) {
            Write-Warning "Register-PromptAlias: unknown command '$n' -- skipped"
            continue
        }
        $aliasName = $Prefix + $n
        $target    = $s.CommandMap[$n]
        $existing  = Get-Alias -Name $aliasName -ErrorAction SilentlyContinue
        if ($existing -and $existing.Definition -ne $target -and -not $Force) {
            Write-Warning "Register-PromptAlias: '$aliasName' exists and points elsewhere -- skipped (use -Force)"
            continue
        }
        Set-Alias -Name $aliasName -Value $target -Scope Global
    }

    # The navigation shortcuts are part of the surface a prefix registers, not a
    # separate namespace: `Register-PromptAlias -Prefix gt` yields gtHome from
    # the same config the import read. Skipped when the caller asked for named
    # commands only -- that form is about one verb, not the whole surface.
    if (-not $Commands -and -not $s.SkipNavAliases) {
        Register-P20NavAliases -Prefix $Prefix
    }
}

# $script:ModuleState.CommandPrefix is resolved far above, beside the nav
# aliases -- the names those register are built from it too, and it had to be
# known before anything registered a name.
# -- Opt-in module commands (build-plan D-CM) ----------------------------------
# One mechanism for every module that is not the ADO core. A module ships a
# PowerShell data file, Config/<module>.commands.psd1:
#
#   @{
#       Feature  = 'growth'                  # the top-level features key
#       Commands = @{ 'NewGrowth' = 'New-P20GrowthItem' }
#       Order    = @('NewGrowth')            # optional: menu / registration order
#       Help     = @{ 'NewGrowth' = @{ description = '...'; usage = '...'
#                                      examples = @('...'); category = 'growth' } }
#   }
#
# PLAIN hashtables, with no [ordered] cast. Import-PowerShellDataFile refuses a
# cast -- it reads a data file and will not evaluate an expression to build one
# -- and that refusal is the feature, not the obstacle: a file any module can
# drop into Config/ must not be able to run code on import. A hashtable has no
# order, so `Order` carries the one thing the cast was there for. Names left out
# of `Order` follow the listed ones; a name in `Order` that is not in `Commands`
# is a readable warning and nothing else.
#
# and a sibling Config/<module>.commands.ps1 holding the wrapper functions. If
# the flag is on, the wrappers are dot-sourced, the rows are appended to
# $script:ModuleState.CommandMap and the help entries are merged into the in-memory commands
# table Show-CommandHelp reads -- so a module's help never has to be written
# into the committed config.default.json, which is the ADO core's.
#
# This runs BEFORE Register-PromptAlias, which is the whole point: the aliases
# are generated from the table, so a module verb gets its prefixed alias, its
# menu line and its bridge entry for free. Get-P20CommandMap reads the same
# table at call time, so a module verb is bridgeable with no backend edit.
#
# If the flag is off, nothing at all happens -- no row, no alias, no help, no
# menu line. Off means absent (docs/modules/README.md, "Off means absent"), not present-and-refusing.
#
# Two failures are handled rather than thrown, because one bad module file must
# not cost a user the whole CLI:
#   - a name that is already in the table: the module is REFUSED whole, with the
#     colliding name in the message. A core command is never overwritten, and a
#     half-merged module is worse than an unloaded one.
#   - a malformed or unreadable data file: reported with its path, skipped.
# The order a module's commands are registered in, which is the order they
# appear in Menu. `Order` first, for the names that are really there, then
# everything else the data file declared.
function script:Resolve-P20CommandOrder {
    param($ModuleData, [string]$Path)

    $declared = @($ModuleData.Commands.Keys)
    if (-not $ModuleData.Order) { return $declared }

    $ordered = @()
    $unknown = @()
    foreach ($name in @($ModuleData.Order)) {
        if ($ModuleData.Commands.Contains($name)) {
            if ($ordered -notcontains $name) { $ordered += $name }
        }
        else {
            $unknown += $name
        }
    }
    if ($unknown.Count -gt 0) {
        Write-Warning "Module commands: $Path lists $($unknown -join ', ') in Order but does not declare $(if ($unknown.Count -eq 1) { 'it' } else { 'them' }) in Commands -- ignored"
    }
    foreach ($name in $declared) {
        if ($ordered -notcontains $name) { $ordered += $name }
    }
    return $ordered
}

$script:repoRoot = $toolkitRoot
$script:ModuleState.ModuleCommandsLoaded = [ordered]@{}

$moduleCommandDir = Join-Path $toolkitRoot 'Config'
if (Test-Path $moduleCommandDir) {
    # In the autoload discovery shell, read the COMMITTED config only. The
    # manifest that shell produces is committed and shared between machines, so
    # a module verb may only be in it when config.default.json itself turns the
    # module on -- a flag set in one machine's config.local.json must not put a
    # verb into a file every machine reads, or the drift check goes red on
    # whichever machine did not last generate it. Exactly the fix the personal
    # nav aliases already have, applied to the same question one level up.
    $enabledFeatures = Get-P20Features -CommittedOnly:$script:ModuleState.SkipNavAliases
    $moduleFiles = @(Get-ChildItem -Path $moduleCommandDir -Filter '*.commands.psd1' -File -ErrorAction SilentlyContinue | Sort-Object Name)
    foreach ($moduleFile in $moduleFiles) {
        $moduleData = $null
        try {
            $moduleData = Import-PowerShellDataFile -Path $moduleFile.FullName -ErrorAction Stop
        }
        catch {
            Write-Warning "Module commands: $($moduleFile.FullName) is not a readable data file ($($_.Exception.Message)) -- module skipped"
            continue
        }
        if (-not $moduleData -or -not $moduleData.Feature -or -not $moduleData.Commands) {
            Write-Warning "Module commands: $($moduleFile.FullName) has no Feature or no Commands -- module skipped"
            continue
        }
        if (-not $enabledFeatures[$moduleData.Feature]) { continue }

        $moduleScript = Join-Path $moduleFile.DirectoryName ($moduleFile.BaseName + '.ps1')
        if (-not (Test-Path $moduleScript)) {
            Write-Warning "Module commands: $($moduleFile.FullName) has no wrapper file at $moduleScript -- module skipped"
            continue
        }

        $collisions = @($moduleData.Commands.Keys | Where-Object { $script:ModuleState.CommandMap.Contains($_) })
        if ($collisions.Count -gt 0) {
            Write-Warning "Module commands: '$($moduleData.Feature)' ($($moduleFile.FullName)) declares $($collisions -join ', '), which this CLI already defines -- module skipped, the existing command is unchanged. Rename the module's command."
            continue
        }

        try {
            . $moduleScript
        }
        catch {
            Write-Warning "Module commands: $moduleScript failed to load ($($_.Exception.Message)) -- module skipped"
            continue
        }

        $moduleOrder = @(Resolve-P20CommandOrder $moduleData $moduleFile.FullName)
        foreach ($commandName in $moduleOrder) {
            $script:ModuleState.CommandMap[$commandName] = $moduleData.Commands[$commandName]
        }
        if ($moduleData.Help) {
            foreach ($helpName in $moduleData.Help.Keys) {
                $script:ModuleState.Commands[$helpName] = $moduleData.Help[$helpName]
            }
        }
        $script:ModuleState.ModuleCommandsLoaded[$moduleData.Feature] = $moduleOrder
    }
}

# A read of which opt-in modules contributed commands to this session, for the
# tests and for anything that has to explain why a verb is or is not there.
# Reads module state through Get-P20ModuleState, never `$script:`: reached
# from a module-launched script, `$script:` binds to that script and answers
# $null. Not a GetNewClosure() body either -- that is bound to a NEW dynamic
# module, where this function's private helpers are not visible.
function global:Get-P20ModuleCommands {
    [CmdletBinding()]
    param()
    $s = Get-P20ModuleState
    return ($s.ModuleCommandsLoaded | ConvertTo-Json -Compress)
}

Register-PromptAlias -Prefix $script:ModuleState.CommandPrefix
