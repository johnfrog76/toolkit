#
# The hub's own manifest -- <promptsRoot>/hub.json.
#
# NOT a runnable verb: this file is DOT-SOURCED, by utilities.psm1 at import and
# by the handful of scripts that have to resolve a hub-root folder while running
# standalone (a test sandbox, `pwsh -File`, anything with no module in the
# session). That is why it is one file rather than a function inside the module:
# there must be exactly one implementation of "what did the hub declare", and
# both callers have to be able to reach it.
#
# Why a hub declares anything at all: config.default.json is committed and
# shared, so a private ADO org cannot go in it -- the Portability suite fails the
# build if one does. The hub is where the engineer's data already lives, so the
# hub is where the engineer's orgs are declared. The owner's rule: "data separate
# from software."
#
# The rules, which MUST match agent/core/config.py's read_hub_manifest exactly
# (Tests/fixtures/hub-parity pins the two together):
#
#   * hub.json carries `orgs`, `folders` and `storeSync` and nothing else.
#     Every machine-scoped key -- activeOrg, promptsRoot, email, branchUser,
#     wsRoot, web, commands, top-level features -- is ignored with a warning;
#     those belong to config.local.json.
#   * `storeSync` is 'git' or 'none' -- whether the hub is a git repository is
#     a fact about the HUB, so the hub settles it for every machine that reads
#     it, and config.local.json still has the last word. Anything else warns
#     and the configured value stands.
#   * an org needs `slug` and `promptsFolder` or it is skipped, with a warning:
#     without them there is nothing to merge on and nowhere to read.
#   * an org may set an ORG-SCOPED feature (sprintAwareness) exactly as a
#     shipped org may. Any other flag there is the engineer's, and is ignored
#     with a warning.
#   * absent changes nothing; malformed is a readable warning naming the path,
#     never a crash.
#
# PowerShell 5.1 clean: no ternary, no null-coalescing, ASCII hyphens only.
#

if (-not (Get-Command Write-P20ConfigParseWarning -ErrorAction SilentlyContinue)) { . (Join-Path $PSScriptRoot 'Write-ConfigParseWarning.ps1') }

function Get-P20HubManifestName {
    return 'hub.json'
}

function Get-P20HubManifestKeys {
    # The only top-level keys a hub may declare. Anything else is a machine
    # setting in the wrong file. `spaces` beside `orgs`: the container's key
    # in both spellings (ConvertTo-P20SpaceKeys, below).
    return @('hub', 'orgs', 'spaces', 'folders', 'storeSync')
}

function ConvertTo-P20SpaceKeys {
    <#
      The container is a Space. The files say `spaces` and `activeSpace`;
      an older file may still say `orgs` and `activeOrg`, and this is the ONE
      place the old spelling is read: it is mapped onto the new name and then
      dropped, so nothing downstream sees it. When a file carries both, the new
      name wins and an empty new value is no answer. Stage 3 made the new
      spelling canonical in memory too -- every reader after this line asks for
      `.spaces` / `.activeSpace` and nothing else.
      MUST mirror agent/core/config.py's space_keys -- Tests/fixtures/
      hub-parity-spaces pins the two together.
    #>
    param($Config)
    if ($null -eq $Config -or -not ($Config -is [System.Management.Automation.PSCustomObject])) { return $Config }
    foreach ($pair in @(@('spaces', 'orgs'), @('activeSpace', 'activeOrg'))) {
        $new = $pair[0]; $old = $pair[1]
        $oldProp = $Config.PSObject.Properties[$old]
        if ($null -eq $oldProp) { continue }
        $value = $oldProp.Value
        $Config.PSObject.Properties.Remove($old)
        $newProp = $Config.PSObject.Properties[$new]
        $blank = ($null -eq $newProp) -or ($null -eq $newProp.Value) -or ("$($newProp.Value)" -eq '')
        if ($blank) { $Config | Add-Member -NotePropertyName $new -NotePropertyValue $value -Force }
    }
    return $Config
}

function ConvertTo-P20SpaceSpelling {
    <#
      The WRITE side of ConvertTo-P20SpaceKeys (stage 2, step 2): the
      object as a file should carry it -- `spaces` and `activeSpace`, never
      `orgs` or `activeOrg`. A raw file may still carry the old name beside
      the new; the new name is the one the code mutates, so it wins, and it
      stands where the old one stood, so a file keeps its order. A non-object
      passes through.
    #>
    param($Config)
    if ($null -eq $Config -or -not ($Config -is [System.Management.Automation.PSCustomObject])) { return $Config }
    $out = New-Object PSObject
    $done = @{}
    foreach ($prop in $Config.PSObject.Properties) {
        $name = $prop.Name
        if ($name -eq 'orgs' -or $name -eq 'spaces') {
            if ($done['spaces']) { continue }
            # Plain assignment, never `$value = if (...) { ... }`: a statement's
            # output is enumerated, and a one-Space array came out a bare object.
            $value = $null
            if ($Config.PSObject.Properties['orgs']) { $value = $Config.PSObject.Properties['orgs'].Value }
            if ($Config.PSObject.Properties['spaces'] -and $null -ne $Config.spaces) { $value = $Config.spaces }
            $out | Add-Member -NotePropertyName 'spaces' -NotePropertyValue $value -Force
            $done['spaces'] = $true
            continue
        }
        if ($name -eq 'activeOrg' -or $name -eq 'activeSpace') {
            if ($done['activeSpace']) { continue }
            $value = $null
            if ($Config.PSObject.Properties['activeOrg']) { $value = $Config.PSObject.Properties['activeOrg'].Value }
            if ($Config.PSObject.Properties['activeSpace'] -and "$($Config.activeSpace)" -ne '') { $value = $Config.activeSpace }
            $out | Add-Member -NotePropertyName 'activeSpace' -NotePropertyValue $value -Force
            $done['activeSpace'] = $true
            continue
        }
        $out | Add-Member -NotePropertyName $name -NotePropertyValue $prop.Value -Force
    }
    return $out
}

function Update-P20SpaceKeysInFile {
    <#
      Rewrite ONE config file to the new spelling if it still carries the old
      -- Sync's migration of the hub's manifest, done once, on the machine
      that pulled it. Returns $true when the file changed. A file that is not
      there, not JSON, or already spelled `spaces` is left alone and answers
      $false; nothing here ever refuses.
    #>
    param([Parameter(Mandatory = $true)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return $false }
    $data = $null
    try {
        $raw = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
        $cmd = Get-Command ConvertFrom-Json
        if ($cmd.Parameters.ContainsKey('DateKind')) { $data = $raw | ConvertFrom-Json -DateKind String }
        else { $data = $raw | ConvertFrom-Json }
    }
    catch { return $false }
    if ($null -eq $data -or -not ($data -is [System.Management.Automation.PSCustomObject])) { return $false }
    if (-not ($data.PSObject.Properties['orgs'] -or $data.PSObject.Properties['activeOrg'])) { return $false }
    if (-not (Get-Command Write-ConfigJson -ErrorAction SilentlyContinue)) {
        . (Join-Path $PSScriptRoot 'Write-ConfigJson.ps1')
    }
    Write-ConfigJson -Path $Path -Value (ConvertTo-P20SpaceSpelling $data)
    return $true
}

function Get-P20StoreSyncValues {
    # How the prompt store is kept in sync. MUST mirror STORE_SYNC_VALUES in
    # agent/core/config.py.
    return @('git', 'none')
}

function Get-P20DefaultHubFolders {
    # The hub-root siblings the modules read, and the name each has unless the
    # hub renames it. AGENTS.md, "one place for magic strings": these were nine
    # string literals across two languages before this existed.
    # MUST mirror DEFAULT_HUB_FOLDERS in agent/core/config.py.
    return [ordered]@{
        growth  = 'growth'
        manager = 'manager'
        reviews = 'reviews'
        resume  = 'resume'
        agentic = 'agentic'
        # The Organize add-on's reminders: named for the data, not
        # the module, the way growth owns growth/, reviews/ and resume/.
        reminders = 'reminders'
        # The Studio's seed drawer: design notes that belong
        # to no product yet (D-S3).
        design = 'design'
        # The hub's specs (design lifecycle L2): the same four
        # folders a product keeps -- design/, design/archive/, spec/,
        # spec/archive/ -- at the hub's root (D-DL12).
        spec = 'spec'
    }
}

function Test-P20HubRoot {
    <#
      Is the configured hub actually THERE? Every reader asks this before it
      builds a path under the root, because Join-Path does not tolerate a drive
      that does not exist -- on Windows, joining onto a drive letter that is not
      mapped THROWS ("Cannot find drive"), and the next Test-Path then binds a
      null and throws again. Test-Path is the safe question: it answers $false
      on a missing drive rather than raising.

      Realistic on Windows and not exotic: an unplugged USB disk, a `subst` that
      has not run, a mapped network drive that is not up yet, a typo.
    #>
    param([string]$Root)
    if (-not $Root) { return $false }
    try { return [bool](Test-Path -LiteralPath $Root) }
    catch { return $false }
}

function Get-P20HubMissingMessage {
    <#
      ONE sentence for "your hub is not there", said by the import warning and
      by every verb that refuses. It names the cause the user can act on -- the
      drive -- and the file the path came from. AGENTS.md, "One place for magic
      strings".
    #>
    param([string]$Root)
    return "Hub not found: '$Root' -- is the drive connected? promptsRoot in config.local.json"
}

function Write-P20HubWarning {
    param([string]$Detail)
    Write-Warning $Detail
    if (Get-Command Write-ToolkitLog -ErrorAction SilentlyContinue) {
        Write-ToolkitLog -Type WARN -Source 'hub.json' -Detail $Detail
    }
}

function ConvertTo-P20LongPath {
    <#
      A Windows 8.3 short path in its LONG form, and any other path unchanged.

      `C:\Users\<name>~1.<domain>\...` -- what %TEMP% and Python's tempfile hand out for
      a user name that does not fit 8.3 -- passes Test-Path, and then every
      PowerShell call that normalises a path through the FileSystem provider
      (Push-Location, Set-Location, Move-Item, Remove-Item) refuses it with "An
      object at the specified path `C:\Users\<name>~1.<domain>` does not exist."
      Resolve-Path keeps the short form; Get-Item's FullName is the one call that
      expands it.

      Exactly today's answer whenever there is nothing to expand: off Windows, a
      path with no `~` in it, a path that does not exist yet, or a Get-Item that
      fails for any reason. PowerShell 5.1 clean.
    #>
    param([string]$Path = '')

    if (-not $Path) { return $Path }
    if ([System.IO.Path]::DirectorySeparatorChar -ne [char]92) { return $Path }
    if ($Path.IndexOf('~') -lt 0) { return $Path }
    try {
        if (-not (Test-Path -LiteralPath $Path)) { return $Path }
        $long = [string](Get-Item -LiteralPath $Path -Force -ErrorAction Stop).FullName
        if ($long) { return $long }
    }
    catch { $null = $_ }
    return $Path
}

function Resolve-P20HubPath {
    <#
      Normalise one configured hub path: a leading ~ expands, and a relative
      value is read against the package root so a committed config stays
      portable. Exactly what agent/core/config.py's _resolve_root does.

      And a Windows 8.3 short path comes back LONG (ConvertTo-P20LongPath).
      This is the one place a hub path is first read -- PROMPTS_ROOT and
      promptsRoot both pass through here, for the module and for every script --
      so every verb gets the long form and a new verb cannot forget it.
    #>
    param([string]$Path = '', [string]$PackageRoot = '')

    $raw = ([string]$Path).Trim()
    if (-not $raw) { return '' }
    if ($raw.StartsWith('~')) {
        $rest = $raw.Substring(1).TrimStart('/', '\')
        if ($rest) { $raw = Join-Path $HOME $rest } else { $raw = $HOME }
    }
    if (-not [System.IO.Path]::IsPathRooted($raw)) {
        if (-not $PackageRoot) { $PackageRoot = Split-Path $PSScriptRoot -Parent }
        $raw = Join-Path $PackageRoot $raw
    }
    return (ConvertTo-P20LongPath -Path $raw)
}

function Get-P20ConfiguredHub {
    <#
      Did anyone SAY where the hub is? PROMPTS_ROOT in the environment, or a
      promptsRoot in config.local.json, else config.default.json. Returns what
      was said ('' when nothing was) -- NOT where the hub resolved to: with
      nothing set the module falls back to the package's parent folder, which
      exists on every machine (AGENTS.md, "The hub resolved is not a hub was
      configured"). This is the one test; Start, Env and the Optional surfaces
      block all ask it, so they cannot answer differently on one screen. The
      agent's twin is hub_configured() in agent/core/config.py.
    #>
    param([string]$PackageRoot = '')

    if (-not $PackageRoot) { $PackageRoot = Split-Path $PSScriptRoot -Parent }
    if ($env:PROMPTS_ROOT -and "$($env:PROMPTS_ROOT)".Trim()) { return [string]$env:PROMPTS_ROOT }
    foreach ($name in @('config.local.json', 'config.default.json')) {
        $file = Join-Path $PackageRoot $name
        if (-not (Test-Path -LiteralPath $file -PathType Leaf)) { continue }
        try {
            $value = (Get-Content -LiteralPath $file -Raw -Encoding UTF8 | ConvertFrom-Json).promptsRoot
            if ($value -and "$value".Trim()) { return [string]$value }
        }
        catch { if ($name -eq 'config.local.json') { $null = Write-P20ConfigParseWarning -Path $file -Message $_.Exception.Message }; continue }  # said once; the reader falls through to the next file
    }
    return ''
}

function Resolve-P20HubRoot {
    <#
      Where to look for hub.json when the caller has NOT resolved the hub
      itself: PROMPTS_ROOT in the environment is the explicit override and wins,
      then the configured promptsRoot -- the same precedence hub_root() has in
      agent/core/config.py, so the two halves cannot look in different places.

      A caller that already resolved the hub passes it to Get-P20HubFolder
      instead, and there the argument is authoritative: every such caller has
      applied PROMPTS_ROOT itself, and an accessor that then overrode its own
      caller would be answering a different question than it was asked.

      Most callers want Get-P20PromptsRoot below, which reads the configured
      half for them. This one takes the configured value as an argument because
      utilities.psm1 has already merged it out of two files by the time it asks.
    #>
    param([string]$PromptsRoot = '', [string]$PackageRoot = '')

    $raw = ''
    if ($env:PROMPTS_ROOT) { $raw = ([string]$env:PROMPTS_ROOT).Trim() }
    if (-not $raw -and $PromptsRoot) { $raw = ([string]$PromptsRoot).Trim() }
    return (Resolve-P20HubPath -Path $raw -PackageRoot $PackageRoot)
}

function Get-P20PromptsRoot {
    <#
      WHERE THE HUB IS. One question, one answer, for the module and for every
      script -- ask this and do not re-derive it.

      The rule is `PROMPTS_ROOT` in the environment FIRST, then the configured
      promptsRoot, which is what docs/modules/README.md, agent/README.md,
      docs/modules/growth.md and agent/core/config.py's hub_root() all say and
      have always said. The code used to say three different things: the agent
      and five scripts let the env var win, the module's
      $global:P20Config.PromptsRoot ignored it outright, and New-Meeting and
      Get-MeetingAgenda used it only as a FALLBACK when config was empty. So
      with both set, the web half read one hub and the 1:1 verbs wrote into
      another -- and the one they wrote into was whatever config named, which on
      an engineer's machine is their real store.

      The configured half comes from the module when there is one and from the
      same two config files when there is not, because these scripts also run
      with no module in the session (a test sandbox, `pwsh -File`). The module
      sets its own PromptsRoot from Resolve-P20HubRoot, so both routes apply the
      same precedence and the same ~ / relative normalisation.
    #>
    param([string]$PackageRoot = '')

    if (-not $PackageRoot) { $PackageRoot = Split-Path $PSScriptRoot -Parent }

    $configured = ''
    if ($global:P20Config -and $global:P20Config.PromptsRoot) {
        $configured = [string]$global:P20Config.PromptsRoot
    }
    else {
        # Same order the module merges in: the shipped file, then this machine's.
        foreach ($name in @('config.default.json', 'config.local.json')) {
            $path = Join-Path $PackageRoot $name
            if (-not (Test-Path $path)) { continue }
            try {
                $cfg = Get-Content $path -Raw -Encoding UTF8 | ConvertFrom-Json
                if ($cfg -and $cfg.promptsRoot) { $configured = [string]$cfg.promptsRoot }
            }
            catch { if ($name -eq 'config.local.json') { $null = Write-P20ConfigParseWarning -Path $path -Message $_.Exception.Message } }
        }
    }

    return (Resolve-P20HubRoot -PromptsRoot $configured -PackageRoot $PackageRoot)
}

# -- Two per-PROCESS stand-ins for config.local.json ----------------------
# PROMPTS_ROOT says WHERE the hub is. These two say which Space is active and
# which flags are on, so `Web -Dev -Fixture` can start servers against
# Tests/fixtures/hub without rewriting the machine's config.local.json. Each one
# REPLACES the one key it names in that file and nothing else. The variable
# names are the contract's (consts.json env.activeSpace, env.features), because
# the agent reads the same two: MUST mirror active_space_override and
# features_override in agent/core/config.py.

function Get-P20EnvOverrideName {
    param([ValidateSet('activeSpace', 'features')][string]$Key)
    if (-not (Get-Command Get-P20Consts -ErrorAction SilentlyContinue)) {
        . (Join-Path $PSScriptRoot 'Get-Consts.ps1')
    }
    return [string](Get-P20Consts).env.$Key
}

function Get-P20ActiveSpaceOverride {
    # The Space slug the environment names, or '' when it names none.
    $raw = [System.Environment]::GetEnvironmentVariable((Get-P20EnvOverrideName -Key 'activeSpace'))
    if ($raw) { return ([string]$raw).Trim() }
    return ''
}

function Get-P20HubOverride {
    # The hub path the environment names, or '' when it names none -- what was
    # SAID, before Resolve-P20HubPath normalises it. Get-P20ConfigStamp compares
    # it between verbs, so a PROMPTS_ROOT exported after the import is seen by
    # the next verb the way a changed config.local.json is.
    if ($env:PROMPTS_ROOT) { return ([string]$env:PROMPTS_ROOT).Trim() }
    return ''
}

function Get-P20FeaturesOverride {
    <#
      The features block the environment supplies, as a PSCustomObject, or $null
      when the files decide. A JSON object -- {"growth":true}; {} means "no flag
      set", which is config.local.json with no `features` block. Anything else
      warns and is ignored, so a typo falls back to the files rather than
      switching every module off in silence.
    #>
    $name = Get-P20EnvOverrideName -Key 'features'
    $raw = [System.Environment]::GetEnvironmentVariable($name)
    if (-not $raw -or -not ([string]$raw).Trim()) { return $null }
    $value = $null
    try { $value = ([string]$raw) | ConvertFrom-Json -ErrorAction Stop } catch { $value = $null }
    if ($null -eq $value -or -not ($value -is [System.Management.Automation.PSCustomObject])) {
        Write-Warning "$name is not a JSON object -- ignored, config.local.json's features stand."
        return $null
    }
    return $value
}

# -- A shipped Space whose slug changed -----------------------------------
# consts.json spaces.renamed, old -> new: the Azure demo was `test`
# and is `azure-demo` now. A machine's hub.json or config.local.json
# written before then still says `test`, and keeps working: the old slug is
# ACCEPTED, MAPPED, and answered with the new name (the shape of the Space rename). One rule,
# Resolve-P20RenamedSlug: an old slug means its new Space while no Space is
# declared under the old one and one is under the new. Applied twice:
#   - to a hub.json entry that carries no `name`, against the SHIPPED slugs
#     (Rename-P20LegacyHubSpaces): such an entry is a patch on the shipped Space
#     -- what `Config -Set spaces.test.org=...` wrote -- and is read under the
#     new slug, keeping its promptsFolder. One that names itself is a Space of
#     its own and keeps its slug -- Tests/fixtures/hub's `test` is one.
#   - to everything else that names a slug -- a config.local.json patch,
#     activeSpace, a slug a person types -- against the resolved Spaces.
# MUST mirror renamed_slug / rename_legacy_hub_spaces in agent/core/config.py;
# Tests/fixtures/space-renamed/table.json is the one table both suites assert.

function Get-P20RenamedSpaceSlugs {
    # old slug -> new slug, as an ordered hashtable.
    if (-not (Get-Command Get-P20Consts -ErrorAction SilentlyContinue)) {
        . (Join-Path $PSScriptRoot 'Get-Consts.ps1')
    }
    $map = [ordered]@{}
    $renamed = (Get-P20Consts).spaces.renamed
    if ($renamed) { foreach ($p in $renamed.PSObject.Properties) { $map[$p.Name] = [string]$p.Value } }
    return $map
}

function Resolve-P20RenamedSlug {
    <#
      The slug to read $Slug as, given the slugs that exist: an old slug means
      its new Space while nothing is declared under the old one and something is
      under the new one; every other slug is itself.
    #>
    param([string]$Slug, [string[]]$Slugs)
    $map = Get-P20RenamedSpaceSlugs
    if ($Slug -and $map.Contains($Slug)) {
        $new = $map[$Slug]
        if (($Slugs -notcontains $Slug) -and ($Slugs -contains $new)) { return $new }
    }
    return $Slug
}

function Rename-P20LegacyHubSpaces {
    <#
      The hub's entries, with every nameless one under an old slug moved to the
      new slug -- when the config it merges over ships the new slug and not the
      old (Resolve-P20RenamedSlug over the SHIPPED slugs). Run between
      Read-P20HubManifest and the merge, by every reader that merges. Mutates and
      returns the entries; promptsFolder is kept, so the cards stay where they are.
    #>
    param($Spaces, [string[]]$ShippedSlugs)
    foreach ($entry in @($Spaces)) {
        if ($null -eq $entry -or $entry.PSObject.Properties['name']) { continue }
        $to = Resolve-P20RenamedSlug -Slug ([string]$entry.slug) -Slugs $ShippedSlugs
        if ($to -ne [string]$entry.slug) { $entry | Add-Member -NotePropertyName 'slug' -NotePropertyValue $to -Force }
    }
    return @($Spaces)
}

function Get-P20RenamedSlugNote {
    # The one sentence a verb prints when it read an old slug as the new one.
    param([string]$From, [string]$To)
    return "'$From' is this Space's old slug; it is '$To' now. Type $To from here on."
}

function ConvertTo-P20HubSpace {
    <#
      One entry from hub.json's `orgs`, cleaned, or $null if it cannot be used.
      SpaceScopedFeatures is passed in rather than read from a variable so this
      file has no dependency on the module's scope.
    #>
    param($Entry, [string]$Label, [string[]]$SpaceScopedFeatures)

    $slug = ''
    if ($Entry.PSObject.Properties['slug'] -and ($Entry.slug -is [string])) { $slug = $Entry.slug.Trim() }
    if (-not $slug) {
        Write-P20HubWarning "$Label`: an org with no 'slug' was skipped -- a hub org needs 'slug' and 'promptsFolder'."
        return $null
    }
    $folder = ''
    if ($Entry.PSObject.Properties['promptsFolder'] -and ($Entry.promptsFolder -is [string])) { $folder = $Entry.promptsFolder.Trim() }
    if (-not $folder) {
        Write-P20HubWarning "$Label`: org '$slug' has no 'promptsFolder' and was skipped -- a hub org needs 'slug' and 'promptsFolder'."
        return $null
    }
    $Entry | Add-Member -NotePropertyName 'slug' -NotePropertyValue $slug -Force
    $Entry | Add-Member -NotePropertyName 'promptsFolder' -NotePropertyValue $folder -Force

    if ($Entry.PSObject.Properties['features']) {
        $feats = $Entry.features
        if (-not ($feats -is [System.Management.Automation.PSCustomObject])) {
            Write-P20HubWarning "$Label`: org '$slug' has a 'features' that is not an object -- ignored."
            $Entry.PSObject.Properties.Remove('features')
        }
        else {
            $kept = New-Object PSObject
            $keptAny = $false
            foreach ($prop in $feats.PSObject.Properties) {
                if ($SpaceScopedFeatures -contains $prop.Name) {
                    $kept | Add-Member -NotePropertyName $prop.Name -NotePropertyValue $prop.Value -Force
                    $keptAny = $true
                }
                else {
                    Write-P20HubWarning "$Label`: org '$slug' sets features.$($prop.Name), which is the engineer's flag and not the org's -- ignored. It belongs in config.local.json's top-level 'features'."
                }
            }
            if ($keptAny) { $Entry | Add-Member -NotePropertyName 'features' -NotePropertyValue $kept -Force }
            else { $Entry.PSObject.Properties.Remove('features') }
        }
    }
    return $Entry
}

function Read-P20HubManifest {
    <#
      Read <Root>/hub.json. Never throws.
      Returns @{ Manifest = <bool>; Path = <string>; Spaces = @(); Folders = @{};
      StoreSync = <string> } where Folders holds only the DECLARED overrides --
      the defaults are applied by Get-P20HubFolderNames -- and StoreSync is ''
      unless the hub declared a usable one.

      [CmdletBinding()] so a caller can collect what it warned about with
      -WarningVariable; Tests/Test-HubJson.ps1 reads every warning that way.
    #>
    [CmdletBinding()]
    param([string]$Root, [string[]]$SpaceScopedFeatures)

    # Which flags an org may set is the contract's list (consts.json
    # features.spaceScoped), so a standalone caller that passes nothing gets the
    # same answer the module does rather than a second copy kept here.
    if (-not $SpaceScopedFeatures) {
        . (Join-Path $PSScriptRoot 'Get-Consts.ps1')
        $SpaceScopedFeatures = @((Get-P20Consts).features.spaceScoped)
    }

    $result = @{ Manifest = $false; Path = ''; Spaces = @(); Folders = @{}; StoreSync = '' }
    if (-not $Root) { return $result }
    # BEFORE any Join-Path on the root. A hub on a drive that is not mapped used
    # to throw here and be reported as "hub.json: not valid JSON ... fix the file
    # or delete it" -- a warning about a file problem that did not exist, with an
    # empty path, in front of a real one nobody had said out loud.
    #A hub that is not
    # there declared nothing, and says nothing here: the ONE warning about it is
    # the import's, and the verbs refuse with the same sentence.
    if (-not (Test-P20HubRoot $Root)) { return $result }
    $path = Join-Path $Root (Get-P20HubManifestName)
    $result.Path = $path
    if (-not (Test-Path $path -PathType Leaf)) { return $result }

    $data = $null
    try {
        $data = Get-Content $path -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        Write-P20HubWarning "$path`: not valid JSON ($($_.Exception.Message)) -- the hub declared nothing. Fix the file or delete it."
        return $result
    }
    if (-not ($data -is [System.Management.Automation.PSCustomObject])) {
        Write-P20HubWarning "$path`: expected a JSON object at the top level -- the hub declared nothing."
        return $result
    }

    $result.Manifest = $true
    # The unknown-key warning names what the FILE said, so it runs before the
    # spelling is canonicalised: an `activeOrg` in hub.json is refused as
    # `activeOrg`, and an `orgs` is a known key in either spelling.
    $known = Get-P20HubManifestKeys
    foreach ($prop in $data.PSObject.Properties) {
        if ($prop.Name.StartsWith('_')) { continue }
        if ($known -contains $prop.Name) { continue }
        Write-P20HubWarning "$path`: '$($prop.Name)' is a machine setting, not a hub declaration -- ignored. hub.json carries 'spaces' and 'folders'; everything else stays in config.local.json."
    }
    $data = ConvertTo-P20SpaceKeys $data

    if ($data.PSObject.Properties['spaces']) {
        $rawSpaces = $data.spaces
        if ($null -ne $rawSpaces -and -not ($rawSpaces -is [System.Array])) {
            Write-P20HubWarning "$path`: 'spaces' must be an array of Space entries, the shape config.default.json uses -- ignored."
            $rawSpaces = $null
        }
        $collected = @()
        foreach ($entry in @($rawSpaces)) {
            if ($null -eq $entry) { continue }
            if (-not ($entry -is [System.Management.Automation.PSCustomObject])) {
                Write-P20HubWarning "$path`: an entry in 'spaces' is not an object -- skipped."
                continue
            }
            $space = ConvertTo-P20HubSpace -Entry $entry -Label $path -SpaceScopedFeatures $SpaceScopedFeatures
            if ($null -ne $space) { $collected += $space }
        }
        $result.Spaces = $collected
    }

    if ($data.PSObject.Properties['folders']) {
        $rawFolders = $data.folders
        if ($null -ne $rawFolders -and -not ($rawFolders -is [System.Management.Automation.PSCustomObject])) {
            Write-P20HubWarning "$path`: 'folders' must be an object of name -> folder -- ignored."
            $rawFolders = $null
        }
        $defaults = Get-P20DefaultHubFolders
        if ($null -ne $rawFolders) {
            foreach ($prop in $rawFolders.PSObject.Properties) {
                if (-not $defaults.Contains($prop.Name)) {
                    $knownNames = (@($defaults.Keys) | Sort-Object) -join ', '
                    Write-P20HubWarning "$path`: 'folders.$($prop.Name)' is not a hub-root folder this tool reads -- ignored. Known: $knownNames."
                    continue
                }
                $value = ''
                if ($prop.Value -is [string]) { $value = $prop.Value.Trim() }
                if (-not $value) {
                    Write-P20HubWarning "$path`: 'folders.$($prop.Name)' must be a folder name -- ignored, keeping '$($defaults[$prop.Name])'."
                    continue
                }
                $result.Folders[$prop.Name] = $value
            }
        }
    }

    if ($data.PSObject.Properties['storeSync']) {
        $known = Get-P20StoreSyncValues
        $value = ''
        if ($data.storeSync -is [string]) { $value = $data.storeSync.Trim() }
        if ($known -contains $value) {
            $result.StoreSync = $value
        }
        else {
            $wanted = (($known | ForEach-Object { "'$_'" }) -join ' or ')
            Write-P20HubWarning "$path`: 'storeSync' must be $wanted -- ignored, keeping the configured value."
        }
    }

    return $result
}

function Get-P20HubFolderNames {
    <#
      The hub-root sibling names in force: the declared ones over the defaults.
      Prefers what the module already resolved at import ($global:P20Config);
      falls back to reading the manifest, which is what a standalone script in
      a session with no module needs.
    #>
    param([string]$PromptsRoot = '', [string]$PackageRoot = '', $Manifest = $null)

    $names = @{}
    foreach ($entry in (Get-P20DefaultHubFolders).GetEnumerator()) { $names[$entry.Key] = $entry.Value }

    # -Manifest is how the module asks, because it has already read the file
    # and because a stale $global:P20Config from an earlier import in the same
    # session must not survive a re-import.
    if ($null -ne $Manifest) {
        foreach ($key in @($Manifest.Folders.Keys)) { $names[$key] = $Manifest.Folders[$key] }
        return $names
    }

    if ($global:P20Config -and $global:P20Config.HubFolders) {
        foreach ($key in @($global:P20Config.HubFolders.Keys)) { $names[$key] = $global:P20Config.HubFolders[$key] }
        return $names
    }

    # An explicitly named hub is authoritative -- see Resolve-P20HubRoot.
    if ($PromptsRoot) { $root = Resolve-P20HubPath -Path $PromptsRoot -PackageRoot $PackageRoot }
    else { $root = Resolve-P20HubRoot -PackageRoot $PackageRoot }
    if (-not $root) { return $names }
    $manifest = Read-P20HubManifest -Root $root
    foreach ($key in @($manifest.Folders.Keys)) { $names[$key] = $manifest.Folders[$key] }
    return $names
}

function Get-P20HubFolder {
    <#
      The path of one hub-root sibling -- Get-P20HubFolder growth $promptsRoot.
      The single accessor the growth, communication and review scripts read, so
      a hub folder's name is a declaration in one file rather than a string
      literal at every use.
    #>
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string]$PromptsRoot,
        [string]$PackageRoot = ''
    )
    $names = Get-P20HubFolderNames -PromptsRoot $PromptsRoot -PackageRoot $PackageRoot
    $folder = $Name
    if ($names.ContainsKey($Name)) { $folder = $names[$Name] }
    return (Join-Path $PromptsRoot $folder)
}
