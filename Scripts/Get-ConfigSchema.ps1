#
# The config schema -- what may be set, where it is written, and what a legal
# value looks like.
#
# NOT a runnable verb: this file is DOT-SOURCED, by Scripts/Set-ToolkitConfig.ps1
# and by the suites that exercise it in a bare pwsh. Same reasoning as
# Scripts/Resolve-HubConfig.ps1 and Scripts/Get-Consts.ps1: there must be exactly
# one answer to "is this a setting, and whose is it", and every caller -- the
# verb, the agent through `Config -Schema -Json`, the web card's tooltips -- has
# to reach the same one.
#
# DERIVED, NOT KEPT. The rows come from two places that already exist:
#
#   * config.default.json's own top-level keys. A key that is there is either a
#     MACHINE setting (this file names it, with its type and help) or the TEAM's
#     table -- commands, workItemTypes, aliases, cliVersion, managerWorkflow --
#     which this command never writes. Both are in the schema, because a reader
#     is owed the sentence that says which it is; only the first can be set.
#   * the hub contract in Scripts/Resolve-HubConfig.ps1 -- Get-P20HubManifestKeys,
#     Get-P20StoreSyncValues, Get-P20DefaultHubFolders. hub.json's shape is
#     declared there and read here rather than retyped.
#
# A schema FILE that the Portability suite also read was considered and not built. A file is a second copy of config.default.json's key set, and a
# second copy is what drifts: Tests/Test-Config.ps1 asserts instead that every
# non-underscore top-level key of the shipped config appears in this schema in
# some scope, which is the same guarantee with nothing to keep in step by hand.
#
# THREE SCOPES, and the scope is the whole design:
#
#   machine  -> config.local.json          this machine's, gitignored, personal
#   org      -> <promptsRoot>/hub.json     the engineer's orgs, beside their data
#   hub      -> <promptsRoot>/hub.json     folders and storeSync, facts about the hub
#   default  -> config.default.json        the team's, and this command never writes it
#
# That differs from the design before hub.json, which had the wizard
# patching `config.local.json` by slug for every org field. An org is the
# engineer's data now (docs/CONFIGURATION.md, "The hub declares its orgs"), so an org
# edit lands in the hub and only a MACHINE-scoped override of one lands locally,
# which is what -Local is for.
#
# PowerShell 5.1 clean: no ternary, no null-coalescing, ASCII hyphens only.
#

if (-not (Get-Command Get-P20HubManifestKeys -ErrorAction SilentlyContinue)) {
    . (Join-Path $PSScriptRoot 'Resolve-HubConfig.ps1')
}
# The prefix, and the one rule for a bare nav alias key. Dot-sourced for the
# same reason everything else here is: this file runs in a bare pwsh, with no
# module, whenever a suite or the bridge exercises the verb.
if (-not (Get-Command ConvertTo-P20BareAliasKey -ErrorAction SilentlyContinue)) {
    . (Join-Path $PSScriptRoot 'Resolve-CliPrefix.ps1')
}

function Get-P20SchemaPrefix {
    # What this package registers under, read from the package this file sits
    # in -- never a literal.
    return (Resolve-P20ConfigPrefix -PackageRoot (Split-Path $PSScriptRoot -Parent))
}

# The dotted path separator, and the two wildcard segments a path may carry.
# `spaces.<slug>.status` and `features.<name>` are patterns, not keys: the slug is
# whatever the orgs list holds and a feature flag is whatever a module declared.
$script:P20ConfigSpacePrefix = 'spaces'
# The older spelling of the container's typed keys (stage 3). Accepted,
# mapped onto the row it means, and answered with the new name in the hint.
$script:P20ConfigLegacySpacePrefix = 'orgs'
$script:P20ConfigLegacyActiveKey = 'activeOrg'

function Get-P20MachineOnlyKeys {
    <#
      Machine settings that config.default.json does NOT ship a line for, so
      they cannot be derived from it. Both are read by utilities.psm1 and both
      are per machine by construction.
    #>
    return @('suppressDeprecationHints', 'menuResetTimestamp')
}

function Get-P20MarkerKeys {
    <#
      Machine keys a VERB writes as a marker -- not settings a person chooses.
      They are rows of the schema so Config can write them (it is the one
      writer of config.local.json), and -Schema names them; -List, and so the
      web's settings form, leaves them out, as it did before Config wrote them.
      menuResetTimestamp: Menu -Reset's stamp.
    #>
    return @('menuResetTimestamp')
}

function Get-P20EngineerFeatureKeys {
    <#
      The engineer's feature flags -- the top-level `features` block. The names
      come from the modules that exist (Config/<module>.commands.psd1 declares
      one each) plus the WEB-ONLY modules, `deck` and `lounge`, which add no
      verbs and whose folder under web/src/modules is their evidence. An org
      cannot set any of them; that rule is Get-P20Features' and this list is
      only what the schema offers as a known name.
    #>
    return @('growth', 'communication', 'deck', 'organize', 'solitaireAgile', 'lounge')
}

function Get-P20RetiredConfigKeys {
    <#
      Keys that USED to be settings and are not any more, each with the one
      sentence a write is refused with. A retired key is not "unknown": someone
      typed it because it was real once, so the refusal says what became of it.
      A line already in a config.local.json is ignored by every reader and is
      never an error -- this table only answers Config -Set and -Unset.

      features.studio: the Studio is core, from day one, and has no switch
      (D-S13).
    #>
    return @{
        'features.studio' = 'The Studio is part of the core and has no switch: features.studio is not a setting any more, and a line left in config.local.json is ignored.'
    }
}

function Get-P20AliasFieldSchema {
    <#
      The fields one NAVIGATION alias carries, and they are the machine's: a
      path is personal, which is why the three shipped aliases have empty ones
      and why the category renders `not configured` until someone fills one in.
      The key is BARE -- `aliases.Home.path`, never `aliases.tkHome.path` --
      because the prefix is applied when the alias is registered, not stored.
    #>
    $fields = @()
    $fields += [PSCustomObject]@{ key = 'path';        type = 'path';   help = 'Where the shortcut goes. Setting one is what turns the shortcut on; an alias with no path is never registered.' }
    $fields += [PSCustomObject]@{ key = 'description'; type = 'string'; help = 'The line Menu prints beside it.' }
    $fields += [PSCustomObject]@{ key = 'display';     type = 'bool';   help = 'Whether the shortcut is registered and listed at all. True for the shipped three.' }
    return $fields
}

function Get-P20StartWorkPromptHelp {
    # One help line for a startWork.prompts row, named or the pattern.
    param([string]$Kind)
    return "The agentic prompt StartWork's hand-off block carries for a $Kind (a card type with its spaces removed, or issue): a path relative to the Toolkit package, or absolute. StartWork -Prompt <path> overrides it for one call."
}

function Get-P20SpaceStatusValues {
    # MUST mirror $validStatuses in utilities.psm1 and _VALID_STATUSES in
    # agent/core/config.py. Fail-closed to 'local' happens there; refusing an
    # unknown one before it is written happens here.
    return @('active', 'local', 'archive')
}

function Get-P20SpaceTypeValues {
    return @('engagement', 'portfolio', 'internal')
}

function Get-P20RequiredSpaceFields {
    <#
      An org entry without these two is skipped by both loaders with a warning
      (ConvertTo-P20HubSpace, _sanitise_hub_space), so a new org must carry them and
      -Unset must never take one away.
    #>
    return @('slug', 'promptsFolder')
}

function New-P20SchemaRow {
    param(
        [string]$Key,
        [string]$Scope,
        [string]$Type,
        [string[]]$Allowed = @(),
        [string]$Help = '',
        [switch]$Required
    )
    $file = 'config.default.json'
    if ($Scope -eq 'machine') { $file = 'config.local.json' }
    elseif ($Scope -eq 'org' -or $Scope -eq 'hub') { $file = 'hub.json' }
    return [PSCustomObject]@{
        key      = $Key
        scope    = $Scope
        type     = $Type
        allowed  = @($Allowed)
        required = [bool]$Required
        file     = $file
        help     = $Help
    }
}

function Get-P20ConfigSchema {
    <#
      Every setting, in one array of rows: key, scope, type, allowed values,
      whether it is required, the file a write lands in, and one line of help.

      -DefaultConfig takes the parsed config.default.json (the caller has
      usually read it already); -Spaces takes the resolved org list, which is what
      turns `activeOrg`'s allowed values and the `spaces.<slug>.*` rows into real
      names rather than a pattern. Both optional: with neither, the schema is
      still complete, `activeOrg` simply lists no slugs.
    #>
    [CmdletBinding()]
    param(
        $DefaultConfig = $null,
        $Spaces = @(),
        [switch]$IncludeOrgRows
    )

    $rows = @()

    # -- The machine's own settings -------------------------------------------
    # Ordered the way a reader meets them: who you are, where your work is, then
    # the two that change how the tool behaves.
    $slugs = @()
    foreach ($o in @($Spaces)) { if ($o -and $o.slug) { $slugs += [string]$o.slug } }

    $rows += New-P20SchemaRow -Key 'email' -Scope 'machine' -Type 'string' -Help 'Who "me" is, for the ADO lookups that filter by a person -- MyPRs, Dashboard, MyWork and the three agent routes. Empty falls back to branchUser if it is an address, then to az account show.'
    $rows += New-P20SchemaRow -Key 'branchUser' -Scope 'machine' -Type 'string' -Help 'Branch-name prefix, and the name the web shell greets you by. Defaults to your OS username.'
    $rows += New-P20SchemaRow -Key 'activeSpace' -Scope 'machine' -Type 'enum' -Allowed $slugs -Help 'Which Srg every command scopes to. SwitchOrg writes the same key.'
    $rows += New-P20SchemaRow -Key 'promptsRoot' -Scope 'machine' -Type 'path' -Help 'Your hub -- where prompt files live. Not this repo. PROMPTS_ROOT in the environment overrides it.'
    $rows += New-P20SchemaRow -Key 'wsRoot' -Scope 'machine' -Type 'path' -Help 'Where your code repositories are checked out, exported as WS_ROOT for scripts and child processes.'
    $rows += New-P20SchemaRow -Key 'agenticExtensionPath' -Scope 'machine' -Type 'path' -Help 'A folder of your own whose copy of a shipped agentic prompt wins on this machine (absolute, or relative to the hub). A name the folder does not carry falls back to the package. Empty: the shipped set.'
    $rows += New-P20SchemaRow -Key 'commandPrefix' -Scope 'machine' -Type 'string' -Help 'The prefix every verb is registered under. tk by default; the prefix is data, not code.'
    $rows += New-P20SchemaRow -Key 'storeSync' -Scope 'machine' -Type 'enum' -Allowed (Get-P20StoreSyncValues) -Help "How the prompt store is kept in sync. The hub may declare it too -- pass -Hub to write the hub's instead of this machine's override."
    $rows += New-P20SchemaRow -Key 'quietStart' -Scope 'machine' -Type 'bool' -Help 'Suppress the import banner.'
    $rows += New-P20SchemaRow -Key 'suppressDeprecationHints' -Scope 'machine' -Type 'bool' -Help 'Mute the one-time hint printed when a command is reached through a deprecated alias.'
    # Written by Menu -Reset, through this command, so config.local.json has one writer.
    $rows += New-P20SchemaRow -Key 'menuResetTimestamp' -Scope 'machine' -Type 'string' -Help 'When the menu''s usage scores last started over, yyyy-MM-ddTHH:mm:ss local time: the menu counts only the commands used since. Menu -Reset writes it; a value that is not a date is named and ignored.'
    $rows += New-P20SchemaRow -Key 'isDemoDismissed' -Scope 'machine' -Type 'bool' -Help "Hide the shipped demo Spaces (example: true -- Demo, the GitHub demo, the Azure demo) from the orgs you pick from -- the web's switcher and Settings, SwitchOrg Status. Nothing is removed from config, and the org you are in is always shown."
    $rows += New-P20SchemaRow -Key 'firstRun.welcome' -Scope 'machine' -Type 'bool' -Help "The Home banner that offers the deck Introducing ToolKit. Start sets it true; Get Started or Dismiss sets it false, and then it is gone for good. Shown only while the deck module is on."
    $rows += New-P20SchemaRow -Key 'web.agentPort' -Scope 'machine' -Type 'int' -Help 'The port the agent listens on and the web half proxies to.'
    $rows += New-P20SchemaRow -Key 'web.corsOrigins' -Scope 'machine' -Type 'array' -Help 'Dev-server origins allowed to call the agent, as a JSON array. Empty accepts the two defaults (5173, 5174).'
    $rows += New-P20SchemaRow -Key 'ai.model' -Scope 'machine' -Type 'string' -Help 'The model id every model call sends: AddPRReview, and the agent''s suggest and rewrite routes. The key stays in the environment (ANTHROPIC_API_KEY), never in a file this tool writes.'

    # A navigation shortcut's fields, as a PATTERN: the name is whatever the
    # engineer calls it, exactly as `spaces.<slug>.*` is. Machine-scoped, because
    # a path is this machine's and the committed file ships all three empty.
    foreach ($field in (Get-P20AliasFieldSchema)) {
        $rows += New-P20SchemaRow -Key "aliases.<name>.$($field.key)" -Scope 'machine' -Type $field.type -Help $field.help
    }

    # StartWork's prompt table (the Team Agile add-on): one row per kind the
    # shipped config names, read from it rather than listed here, and a pattern
    # row for a kind it does not -- a team's prompts are its own (D-AR4).
    if ($DefaultConfig -and $DefaultConfig.PSObject.Properties['startWork'] -and $DefaultConfig.startWork.prompts) {
        foreach ($kind in $DefaultConfig.startWork.prompts.PSObject.Properties) {
            if ($kind.Name.StartsWith('_')) { continue }
            $rows += New-P20SchemaRow -Key "startWork.prompts.$($kind.Name)" -Scope 'machine' -Type 'string' -Help (Get-P20StartWorkPromptHelp $kind.Name)
        }
    }
    $rows += New-P20SchemaRow -Key 'startWork.prompts.<kind>' -Scope 'machine' -Type 'string' -Help (Get-P20StartWorkPromptHelp '<kind>')

    foreach ($flag in (Get-P20EngineerFeatureKeys)) {
        $rows += New-P20SchemaRow -Key "features.$flag" -Scope 'machine' -Type 'bool' `
            -Help "Switch the $flag module on or off in all three halves at once. A feature flag's scope is the engineer, so it holds steady across activeOrg and an org cannot override it."
    }

    # Azure DevOps is not a module, and its flag is not a plain on/off: ABSENT is
    # an answer too, and the usual one -- "follow the org I am in".
    $rows += New-P20SchemaRow -Key 'features.ado' -Scope 'machine' -Type 'bool' `
        -Help "Whether Azure DevOps is part of what this machine shows: Menu's ADO verbs, Setup's az checks, the web's work-item controls. Leave it UNSET and it follows the org you are in -- on in an 'active' Azure DevOps org, off in a 'local' one and off on a GitHub Space. Set it to say otherwise. Nothing is unregistered either way; cards have no such flag and never will."

    # -- The hub's own declarations -------------------------------------------
    # storeSync appears twice on purpose: once above as this machine's override
    # and once here as the hub's declaration. -Hub picks which file is written,
    # and the resolution order (default, hub, local) is why both exist.
    $rows += New-P20SchemaRow -Key 'storeSync' -Scope 'hub' -Type 'enum' -Allowed (Get-P20StoreSyncValues) -Help 'What the HUB declares, for every machine that reads it -- whether the store is a git repository is a fact about the hub. Written with -Hub.'
    foreach ($folder in (Get-P20DefaultHubFolders).GetEnumerator()) {
        $rows += New-P20SchemaRow -Key "folders.$($folder.Key)" -Scope 'hub' -Type 'string' `
            -Help "The hub-root folder the $($folder.Key) data lives in. Defaults to '$($folder.Value)'. Written with -Hub."
    }

    # -- One org's fields ------------------------------------------------------
    # Emitted per known slug when -IncludeOrgRows is given, so -Schema can print
    # `spaces.<slug>.status` for the orgs that exist rather than a pattern nobody
    # can type. -Set resolves a path against the pattern either way: a slug that
    # is not there yet is how a NEW org is added.
    $orgFields = Get-P20SpaceFieldSchema
    if ($IncludeOrgRows) {
        foreach ($slug in $slugs) {
            foreach ($field in $orgFields) {
                $rows += New-P20SchemaRow -Key "spaces.$slug.$($field.key)" -Scope $field.scope -Type $field.type `
                    -Allowed $field.allowed -Help $field.help -Required:$field.required
            }
        }
    }
    else {
        foreach ($field in $orgFields) {
            $rows += New-P20SchemaRow -Key "spaces.<slug>.$($field.key)" -Scope $field.scope -Type $field.type `
                -Allowed $field.allowed -Help $field.help -Required:$field.required
        }
    }

    # -- The team's table ------------------------------------------------------
    # Derived: every remaining top-level key of the shipped config. They are in
    # the schema so a refusal can name what the key IS rather than call it
    # unknown, and they are scope 'default' so nothing can write one.
    if ($DefaultConfig) {
        $machineNames = @($rows | Where-Object { $_.scope -eq 'machine' } | ForEach-Object { ($_.key -split '\.')[0] })
        foreach ($prop in $DefaultConfig.PSObject.Properties) {
            $name = $prop.Name
            if ($name.StartsWith('_')) { continue }
            if ($machineNames -contains $name) { continue }
            if ($name -eq $script:P20ConfigSpacePrefix) { continue }
            $rows += New-P20SchemaRow -Key $name -Scope 'default' -Type 'object' `
                -Help "The team's, not this machine's: '$name' is defined in config.default.json and is edited there, in the commit that changes it."
        }
    }

    return @($rows)
}

function Get-P20SpaceFieldSchema {
    <#
      The fields one Space entry carries. Scope 'org' throughout: the hub is where
      an engineer's Spaces are declared, and -Local is what sends one of these to
      config.local.json's spaces.<slug> patch instead.
    #>
    $fields = @()
    $fields += [PSCustomObject]@{ key = 'name';          scope = 'org'; type = 'string'; allowed = @();                      required = $false; help = 'The Space''s display name, as SwitchSpace and the web shell print it.' }
    $fields += [PSCustomObject]@{ key = 'status';        scope = 'org'; type = 'enum';   allowed = (Get-P20SpaceStatusValues);  required = $false; help = 'active runs Tier 1; local and archive never contact ADO. archive is the retrospective view, and is how an engagement is retired -- nothing is ever deleted.' }
    $fields += [PSCustomObject]@{ key = 'orgType';       scope = 'org'; type = 'enum';   allowed = (Get-P20SpaceTypeValues);    required = $false; help = 'What kind of Space this is. Reporting reads it; nothing gates on it.' }
    $fields += [PSCustomObject]@{ key = 'org';           scope = 'org'; type = 'string'; allowed = @();                      required = $false; help = 'The Space''s address: a GitHub repo URL, or an Azure DevOps organisation URL. Real URLs belong in the hub or in config.local.json, never in the committed config -- the Portability suite fails the build over one.' }
    $fields += [PSCustomObject]@{ key = 'tenant';        scope = 'org'; type = 'string'; allowed = @();                      required = $false; help = 'The Azure AD tenant id this Space authenticates against. Per Space, so a second tenant is a config edit rather than a code change.' }
    $fields += [PSCustomObject]@{ key = 'promptsFolder'; scope = 'org'; type = 'string'; allowed = @();                      required = $true;  help = 'The folder under the hub root where this Space''s cards live. Required: a Space without it is skipped by both loaders.' }
    $fields += [PSCustomObject]@{ key = 'projects';      scope = 'org'; type = 'projects'; allowed = @();                    required = $false; help = 'The projects (Azure DevOps) or repos (GitHub) this Space works in: Name/repo; Other/repo2 -- or a JSON array of { name, repo, defaultBranch }. Connect''s discovery step writes it.' }
    foreach ($lane in @(@('backlog', 'Backlog'), @('active', 'Active'), @('inProgress', 'In Progress'), @('codeReview', 'Code Review'), @('done', 'Done'))) {
        $fields += [PSCustomObject]@{ key = "laneNames.$($lane[0])"; scope = 'org'; type = 'string'; allowed = @(); required = $false; help = "What the board and the list call the '$($lane[1])' lane for this Space. Display only: the state stored in a card, compared by every verb and served as status is always '$($lane[1])'. Unset, the lane is called '$($lane[1])'." }
    }
    # How do you want to work in this Space? -- the second Space-scoped
    # switch after sprintAwareness. Asked only on a GitHub Space; on Azure DevOps
    # and with no tracker the answer is derived and a stored one is ignored.
    if (-not (Get-Command Get-P20HowIWorkStored -ErrorAction SilentlyContinue)) {
        . (Join-Path $PSScriptRoot 'Resolve-HowIWork.ps1')
    }
    $fields += [PSCustomObject]@{ key = 'howIWork';      scope = 'org'; type = 'enum';   allowed = @(Get-P20HowIWorkStored);    required = $false; help = 'How you work in this Space, on a GitHub Space: agents turns Team Agile on here (its switch, features.solitaireAgile, still has to be on); alone, the default, keeps it off. On an Azure DevOps Space the answer is on a team and on one with no tracker it is alone -- both derived, so a value here is ignored.' }
    $fields += [PSCustomObject]@{ key = 'features.sprintAwareness'; scope = 'org'; type = 'bool'; allowed = @();             required = $false; help = 'A SPACE-scoped feature flag -- it describes this Space''s board. Every other flag is the engineer''s and lives in the top-level features block.' }
    $fields += [PSCustomObject]@{ key = 'features.suggestions'; scope = 'org'; type = 'bool'; allowed = @();                 required = $false; help = 'A SPACE-scoped switch: whether Team Agile suggests your next move here -- the chair''s Next line in Standup -Brief and on the Team Agile page. Unset is on wherever Team Agile is on; false turns the line back to "Next: nothing is waiting on you."' }
    $fields += [PSCustomObject]@{ key = 'features.trainingHoursPerQuarter'; scope = 'org'; type = 'int'; allowed = @(); required = $false; help = 'Training hours this Space''s engagement requires each calendar quarter, whole hours. Unset means no requirement and the Growth page says nothing about one.' }
    return $fields
}

function Resolve-P20SchemaKey {
    <#
      Match a dotted path against the schema and hand back the row it belongs
      to, plus the slug when the path named one.

      Returns @{ Row = <row or $null>; Slug = ''; Field = ''; Reason = '' }.
      Reason is set only when nothing matched, and is the sentence the caller
      refuses with -- one place, so the verb and its suite cannot disagree about
      the wording.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Key,
        [Parameter(Mandatory = $true)]$Schema
    )

    $result = @{ Row = $null; Slug = ''; Field = ''; Reason = ''; Alias = '' }
    $key = ([string]$Key).Trim()
    if (-not $key) {
        $result.Reason = 'No setting named. Use -Set <key>=<value>.'
        return $result
    }

    # The older spelling is still typed (and sent by older callers): it means
    # the same row, and the caller is told the new name once.
    if ($key -eq $script:P20ConfigLegacyActiveKey) {
        $result.Alias = $key
        $key = 'activeSpace'
    }
    elseif ($key -like "$($script:P20ConfigLegacySpacePrefix).*") {
        $result.Alias = $key
        $key = $script:P20ConfigSpacePrefix + $key.Substring($script:P20ConfigLegacySpacePrefix.Length)
    }

    $retired = Get-P20RetiredConfigKeys
    if ($retired.ContainsKey($key)) {
        $result.Reason = $retired[$key]
        return $result
    }

    if ($key -like "$($script:P20ConfigSpacePrefix).*") {
        $parts = $key.Split('.')
        if ($parts.Count -lt 3) {
            $result.Reason = "'$key' names a Space but no field. The shape is spaces.<slug>.<field> -- for example spaces.acme.status."
            return $result
        }
        $slug = $parts[1]
        $field = ($parts[2..($parts.Count - 1)] -join '.')
        $match = @(Get-P20SpaceFieldSchema | Where-Object { $_.key -eq $field })
        if ($match.Count -eq 0) {
            $known = ((Get-P20SpaceFieldSchema | ForEach-Object { $_.key }) -join ', ')
            $result.Reason = "'$field' is not a field of a Space. Known: $known."
            return $result
        }
        $f = $match[0]
        $result.Row = New-P20SchemaRow -Key $key -Scope $f.scope -Type $f.type -Allowed $f.allowed -Help $f.help -Required:$f.required
        $result.Slug = $slug
        $result.Field = $field
        return $result
    }

    # A navigation shortcut, the same shape as an org: `aliases.<name>.<field>`,
    # where the name is the engineer's and the field is one of three.
    if ($key -like 'aliases.*') {
        $parts = $key.Split('.')
        if ($parts.Count -lt 3) {
            $result.Reason = "'$key' names a nav alias but no field. The shape is aliases.<name>.<field> -- for example aliases.Home.path."
            return $result
        }
        $name = $parts[1]
        $field = ($parts[2..($parts.Count - 1)] -join '.')
        $match = @(Get-P20AliasFieldSchema | Where-Object { $_.key -eq $field })
        if ($match.Count -eq 0) {
            $known = ((Get-P20AliasFieldSchema | ForEach-Object { $_.key }) -join ', ')
            $result.Reason = "'$field' is not a field of a nav alias. Known: $known."
            return $result
        }
        $bare = ConvertTo-P20BareAliasKey -Key $name -Prefix (Get-P20SchemaPrefix)
        if ($name -ne $bare) {
            $result.Reason = "'$name' carries the command prefix. A nav alias key is bare -- set aliases.$bare.$field instead; the prefix is added when the alias is registered."
            return $result
        }
        $f = $match[0]
        $result.Row = New-P20SchemaRow -Key $key -Scope 'machine' -Type $f.type -Help $f.help
        return $result
    }

    # StartWork's prompt table: a kind the shipped rows do not name is still a
    # row -- a team adds its own kinds -- matched against the pattern row.
    if ($key -like 'startWork.prompts.*' -and -not @($Schema | Where-Object { $_.key -eq $key }).Count) {
        $kind = $key.Substring('startWork.prompts.'.Length)
        if (-not $kind -or $kind.Contains('.')) {
            $result.Reason = "'$key' is not a prompt row. The shape is startWork.prompts.<kind> -- for example startWork.prompts.Bug."
            return $result
        }
        $result.Row = New-P20SchemaRow -Key $key -Scope 'machine' -Type 'string' -Help (Get-P20StartWorkPromptHelp $kind)
        return $result
    }

    $row = @($Schema | Where-Object { $_.key -eq $key -and $_.scope -ne 'hub' })
    if ($row.Count -eq 0) {
        # A hub-scoped key that has no machine twin -- folders.* -- still
        # resolves; the verb is what insists on -Hub for it.
        $row = @($Schema | Where-Object { $_.key -eq $key })
    }
    if ($row.Count -eq 0) {
        $result.Reason = "Unknown setting '$key'."
        return $result
    }
    $result.Row = $row[0]
    return $result
}

function Test-P20ConfigValue {
    <#
      Is this a legal value for this row? Returns @{ Ok = <bool>; Value = <typed
      value>; Reason = '' }.

      The value arrives as the STRING half of -Set key=value, because argv is
      how the bridge carries it and a browser form has nothing better. Typing
      happens here: 'true' becomes a boolean, '4100' becomes an int, a JSON
      array becomes an array, and anything that cannot be read as its declared
      type is refused by name before a file is touched.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Row,
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Value
    )

    $result = @{ Ok = $false; Value = $null; Reason = '' }
    $raw = [string]$Value

    switch ($Row.type) {
        'bool' {
            $lower = $raw.Trim().ToLowerInvariant()
            if ($lower -eq 'true' -or $lower -eq '1') { $result.Ok = $true; $result.Value = $true; return $result }
            if ($lower -eq 'false' -or $lower -eq '0') { $result.Ok = $true; $result.Value = $false; return $result }
            $result.Reason = "$($Row.key) is true or false -- got '$raw'."
            return $result
        }
        'int' {
            $parsed = 0
            if ([int]::TryParse($raw.Trim(), [ref]$parsed)) { $result.Ok = $true; $result.Value = $parsed; return $result }
            $result.Reason = "$($Row.key) is a whole number -- got '$raw'."
            return $result
        }
        'array' {
            $trimmed = $raw.Trim()
            if (-not $trimmed) { $result.Ok = $true; $result.Value = @(); return $result }
            if (-not $trimmed.StartsWith('[')) {
                $result.Reason = "$($Row.key) is a JSON array -- got '$raw'. For example [`"http://localhost:5174`"]."
                return $result
            }
            try { $parsed = ConvertFrom-Json $trimmed -ErrorAction Stop }
            catch {
                $result.Reason = "$($Row.key) is a JSON array and '$raw' is not valid JSON."
                return $result
            }
            $result.Ok = $true
            $result.Value = @($parsed)
            return $result
        }
        'projects' {
            # Two forms: `Name/repo; Other/repo2` (a repo is optional, a
            # semicolon never appears in a name) or a JSON array of
            # { name, repo, defaultBranch } -- the shape config.default.json ships.
            $trimmed = $raw.Trim()
            if (-not $trimmed) { $result.Ok = $true; $result.Value = @(); return $result }
            if ($trimmed.StartsWith('[')) {
                try { $parsed = ConvertFrom-Json $trimmed -ErrorAction Stop }
                catch { $result.Reason = "$($Row.key) is a JSON array of projects and '$raw' is not valid JSON."; return $result }
                $list = @()
                foreach ($item in @($parsed)) {
                    if ($null -eq $item -or -not $item.name) { $result.Reason = "$($Row.key): every project needs a name."; return $result }
                    # Every key the entry carries is kept: hasRepo is read by
                    # MyWork and the agent (a project with no repo is skipped
                    # for repo queries), and a field this parser does not know
                    # is not its to drop.
                    $entry = [ordered]@{ name = [string]$item.name }
                    foreach ($prop in $item.PSObject.Properties) {
                        if ($prop.Name -eq 'name') { continue }
                        $entry[$prop.Name] = $prop.Value
                    }
                    $list += [PSCustomObject]$entry
                }
                $result.Ok = $true; $result.Value = @($list); return $result
            }
            $list = @()
            foreach ($piece in ($trimmed -split ';')) {
                $p = $piece.Trim()
                if (-not $p) { continue }
                $parts = $p -split '/', 2
                $entry = [ordered]@{ name = $parts[0].Trim() }
                if (-not $entry.name) { $result.Reason = "$($Row.key): '$p' has no project name. The shape is Name/repo; Other/repo2."; return $result }
                if ($parts.Count -gt 1 -and $parts[1].Trim()) { $entry.repo = $parts[1].Trim() }
                # A project named with no repo has none: MyWork and the agent
                # read hasRepo=false as "do not ask this project for repos".
                else { $entry.hasRepo = $false }
                $list += [PSCustomObject]$entry
            }
            $result.Ok = $true; $result.Value = @($list); return $result
        }
        'enum' {
            $allowed = @($Row.allowed)
            $trimmed = $raw.Trim()
            if ($allowed.Count -eq 0) {
                # activeOrg with no orgs resolved. Nothing to check it against,
                # and refusing every value would be worse than accepting one.
                $result.Ok = $true; $result.Value = $trimmed; return $result
            }
            $hit = @($allowed | Where-Object { $_ -eq $trimmed })
            if ($hit.Count -eq 1) { $result.Ok = $true; $result.Value = $trimmed; return $result }
            $result.Reason = "$($Row.key) is one of: $($allowed -join ', ') -- got '$trimmed'."
            return $result
        }
        default {
            # string and path. An empty value is legal and means "clear it";
            # -Unset is how the key is removed outright.
            $result.Ok = $true
            $result.Value = $raw
            return $result
        }
    }
}
