#Requires -Version 5.1
<#
.SYNOPSIS
    Read and write the machine's configuration -- the config wizard's CLI half.
.DESCRIPTION
    ONE writer for configuration, and the browser goes through it.

    Every setting this tool has lived in a file you edited by hand. The System
    page showed what the machine had resolved and could change none of it, so a
    missing `email` was a config gap rendered as "you have no pull requests",
    fixed with a text editor and an agent restart, once per machine.

    This is the verb that fixes it, and the web card is a form over this verb
    rather than a second implementation: `PUT /api/config` runs `Config -Set`
    through the bridge, exactly as the Archive button runs `Archive`. README's
    "Three halves, one repo" -- nothing in the web half writes config except
    through the CLI.

    WHERE EACH KIND OF KEY IS WRITTEN. Three files, and which one a key belongs
    to is the whole of this command's judgement:

      config.local.json   this machine's -- email, activeSpace, paths, prefix,
                          the engineer's feature flags, web.*. Gitignored,
                          personal, created here as a SPARSE PATCH if absent.
      <promptsRoot>/hub.json
                          the engineer's ORGS, the hub-root folder names and
                          storeSync. An org is data, and data lives with the
                          hub (docs/CONFIGURATION.md, "The hub declares its orgs").
                          -Local overrides one of its fields for THIS machine
                          only, in config.local.json's spaces.<slug> patch.
      config.default.json the TEAM's -- commands, workItemTypes, aliases,
                          cliVersion, managerWorkflow. NEVER written here. A
                          key that lives only there is refused by name.

    Retiring a Space is `-Set spaces.<slug>.status=archive`, which is the value
    the web shell already renders as the retrospective view (RetireSpace runs it).
    Removing one is `-Unset spaces.<slug> -Hub` -- its entry leaves hub.json --
    and `-Unset spaces.<slug>` for this machine's patch (RemoveSpace runs both).
    Neither touches the Space's folder: no card is ever deleted here.

    The schema -- what may be set, its type, its allowed values and its one line
    of help -- is DERIVED (Scripts/Get-ConfigSchema.ps1) from config.default.json's
    own keys plus the hub contract in Scripts/Resolve-HubConfig.ps1, so there is
    no second list to keep in step. `-Schema` prints it and `-Schema -AsJson` is
    what the web card renders its tooltips from.
.PARAMETER List
    Print every resolved setting with the file it came from. The default.
.PARAMETER Set
    One or more `key=value` pairs. Dotted paths: `email`, `features.growth`,
    `web.corsOrigins`, `spaces.<slug>.status`.
.PARAMETER Unset
    One or more keys to remove. A machine key by default; a hub org's field
    needs -Hub, and a required field is refused even then. A whole Space,
    `spaces.<slug>`: with -Hub its entry leaves hub.json (refused for the Space
    you are in and for one config.default.json ships); without, this machine's
    patch for it leaves config.local.json. Its folder is never touched.
.PARAMETER Schema
    Print what may be set: key, scope, type, allowed values, help.
.PARAMETER AsJson
    Machine-readable output for -List and -Schema. What the agent reads.
.PARAMETER Local
    Send a `spaces.<slug>.*` write to config.local.json -- this machine's
    override of the hub's org -- instead of to the hub.
.PARAMETER Hub
    Write (or unset) the HUB's own declaration: storeSync, folders.*, or a
    field of an org in hub.json.
.PARAMETER Help
    Usage from config.default.json.
.EXAMPLE
    {cliPrefix}Config
    {cliPrefix}Config -Set email=you@example.com
    {cliPrefix}Config -Set features.growth=true -Set activeSpace=acme
    {cliPrefix}Config -Set spaces.acme.status=archive
    {cliPrefix}Config -Unset email
    {cliPrefix}Config -Unset spaces.acme -Hub
    {cliPrefix}Config -Schema
.NOTES
    PowerShell 5.1 compatible.
#>
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'List', Justification = '-List names the default mode: with no -Set, -Unset or -Schema the script lists, so the switch is accepted for the reader and read by nothing.')]
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

$ErrorActionPreference = 'Stop'

$toolkitRoot = Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot 'Resolve-HubConfig.ps1')
. (Join-Path $PSScriptRoot 'Get-ConfigSchema.ps1')
. (Join-Path $PSScriptRoot 'Write-ConfigJson.ps1')

# These scripts also run with no module in the session -- a test sandbox,
# `pwsh -File`, a -Help before the first import -- so a missing module helper
# must not be fatal. Same guard Switch-Mode.ps1 carries.
. (Join-Path $PSScriptRoot 'Initialize-CliFallbacks.ps1')

$defaultPath = Join-Path $toolkitRoot 'config.default.json'
$localPath = Join-Path $toolkitRoot 'config.local.json'

# The prefix is data, and a sentence this script prints must name the surface
# the reader actually has. Get-CliPrefix is the module's; with no module in the
# session the configured value is read below, once the files are parsed.
$cliPrefix = ''
if (Get-Command Get-CliPrefix -ErrorAction SilentlyContinue) { $cliPrefix = Get-CliPrefix }

# ---------------------------------------------------------------------------
# Reading the three files, separately
#
# The module merges them into one answer, which is what every other command
# wants and the one thing this command must NOT have: -List's whole job is to
# say which file a value came from, and a merged object has forgotten.
# ---------------------------------------------------------------------------

function Read-JsonFile {
    <#
      This is the read half of a read-modify-write round trip: -Set patches one
      key and this command re-serialises the WHOLE file, so every value it does
      not touch has to come back out exactly as it went in. PowerShell 7's
      ConvertFrom-Json auto-detects an ISO-8601-looking string and returns a
      [datetime] instead -- config.local.json's own `errorsAckedAt`
      (Get-ToolkitLog.ps1's stamp) is exactly that shape -- and the writer below
      then re-serialises it with .NET's culture-shaped ToString(), which is a
      different string. -DateKind String (added 7.3) turns the coercion off;
      5.1's ConvertFrom-Json never did it, so there the parameter is simply
      absent.
    #>
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    try {
        $raw = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
        $cmd = Get-Command ConvertFrom-Json
        # Both spellings of the container's keys are read (ConvertTo-P20SpaceKeys,
        # the Space rename); the write below puts the new one on disk.
        # Both spellings are read; inside this verb the object is the file's
        # own shape, `spaces` and `activeSpace` (ConvertTo-P20SpaceSpelling),
        # and is written back as it is.
        if ($cmd.Parameters.ContainsKey('DateKind')) {
            return (ConvertTo-P20SpaceSpelling ($raw | ConvertFrom-Json -DateKind String))
        }
        return (ConvertTo-P20SpaceSpelling ($raw | ConvertFrom-Json))
    }
    catch {
        Write-CliError -Message "$Path is not valid JSON ($($_.Exception.Message))." `
            -Hint 'Fix the file by hand, or delete it and set the keys again.'
        exit 2
    }
}

function Get-PathValue {
    <# @{ Found = <bool>; Value = <object> } for a dotted path in a parsed object. #>
    param($Object, [string]$Path)
    $miss = @{ Found = $false; Value = $null }
    if ($null -eq $Object) { return $miss }
    $node = $Object
    foreach ($segment in $Path.Split('.')) {
        if ($null -eq $node) { return $miss }
        if ($node -is [System.Management.Automation.PSCustomObject]) {
            $prop = $node.PSObject.Properties[$segment]
            if (-not $prop) { return $miss }
            $node = $prop.Value
        }
        else { return $miss }
    }
    return @{ Found = $true; Value = $node }
}

function Set-PathValue {
    <#
      Set a dotted path on a parsed object, creating the intermediate objects.
      Returns the object so a caller can start from $null and get one back --
      which is how a first config.local.json is created as a sparse patch rather
      than as a copy of the shipped file.
    #>
    param($Object, [string]$Path, $Value)
    if ($null -eq $Object) { $Object = New-Object PSObject }
    $segments = @($Path.Split('.'))
    $node = $Object
    for ($i = 0; $i -lt $segments.Count - 1; $i++) {
        $name = $segments[$i]
        $prop = $node.PSObject.Properties[$name]
        if (-not $prop -or -not ($prop.Value -is [System.Management.Automation.PSCustomObject])) {
            $child = New-Object PSObject
            $node | Add-Member -NotePropertyName $name -NotePropertyValue $child -Force
            $node = $child
        }
        else { $node = $prop.Value }
    }
    # An existing key is assigned in place: Add-Member -Force removes and re-adds
    # it, which moves it to the END of its object, so a repeated -Set of a key
    # that is not the last one rewrote the file in a new order.
    $leaf = $node.PSObject.Properties[$segments[-1]]
    if ($leaf) { $leaf.Value = $Value }
    else { $node | Add-Member -NotePropertyName $segments[-1] -NotePropertyValue $Value }
    return $Object
}

function Remove-PathValue {
    <# Remove a dotted path. Returns $true if something was there to remove. #>
    param($Object, [string]$Path)
    if ($null -eq $Object) { return $false }
    $segments = @($Path.Split('.'))
    $node = $Object
    for ($i = 0; $i -lt $segments.Count - 1; $i++) {
        $prop = $node.PSObject.Properties[$segments[$i]]
        if (-not $prop -or -not ($prop.Value -is [System.Management.Automation.PSCustomObject])) { return $false }
        $node = $prop.Value
    }
    if (-not $node.PSObject.Properties[$segments[-1]]) { return $false }
    $node.PSObject.Properties.Remove($segments[-1])
    return $true
}

function Format-Value {
    <# One cell of the -List table. Scalars as themselves, arrays inline. #>
    param($Value)
    if ($null -eq $Value) { return '' }
    if ($Value -is [bool]) {
        if ($Value) { return 'true' }
        return 'false'
    }
    if ($Value -is [string]) { return $Value }
    if ($Value -is [System.Collections.IEnumerable]) {
        # A projects list is objects: show each as Name/repo, the form -Set takes.
        return (@($Value | ForEach-Object {
            if ($_ -is [System.Management.Automation.PSCustomObject] -or $_ -is [System.Collections.IDictionary]) {
                $n = [string]$_.name; if ($_.repo) { "$n/$($_.repo)" } else { $n }
            } else { [string]$_ }
        }) -join '; ')
    }
    return [string]$Value
}

$defaultCfg = Read-JsonFile $defaultPath
$localCfg = Read-JsonFile $localPath

if (-not $cliPrefix) {
    if ($localCfg -and $localCfg.commandPrefix) { $cliPrefix = [string]$localCfg.commandPrefix }
    elseif ($defaultCfg -and $defaultCfg.commandPrefix) { $cliPrefix = [string]$defaultCfg.commandPrefix }
}

# The hub, resolved exactly as the module resolves it: PROMPTS_ROOT first, then
# the configured promptsRoot, ~ expanded, a relative value read against the
# package. One implementation, in Resolve-HubConfig.ps1.
$configuredRoot = ''
if ($localCfg -and $localCfg.promptsRoot) { $configuredRoot = [string]$localCfg.promptsRoot }
elseif ($defaultCfg -and $defaultCfg.promptsRoot) { $configuredRoot = [string]$defaultCfg.promptsRoot }
$hubRoot = Resolve-P20HubRoot -PromptsRoot $configuredRoot -PackageRoot $toolkitRoot
$hubPath = ''
$hubCfg = $null
if ($hubRoot -and (Test-P20HubRoot $hubRoot)) {
    $hubPath = Join-Path $hubRoot (Get-P20HubManifestName)
    $hubCfg = Read-JsonFile $hubPath
}

# The org list, in the resolution order the module uses: the shipped array, the
# hub's merged by slug, then this machine's patches. Read here only to give
# `activeSpace` its allowed values and to show a Space's effective fields.
function Get-ResolvedSpaces {
    $list = @()
    if ($defaultCfg -and $defaultCfg.spaces) {
        foreach ($o in @($defaultCfg.spaces)) { $list += $o }
    }
    if ($hubCfg -and $hubCfg.spaces) {
        $shippedSlugs = @($list | ForEach-Object { [string]$_.slug })
        foreach ($h in @($hubCfg.spaces)) {
            if (-not $h.slug) { continue }
            # A nameless entry under a renamed Space's old slug is a patch on the
            # new one, as both loaders read it (Rename-P20LegacyHubSpaces --
            # not called here, because $hubCfg is the file this writes back).
            $hSlug = [string]$h.slug
            if (-not $h.PSObject.Properties['name']) { $hSlug = Resolve-P20RenamedSlug -Slug $hSlug -Slugs $shippedSlugs }
            $existing = @($list | Where-Object { $_.slug -eq $hSlug })
            if ($existing.Count -eq 0) { $list += $h }
        }
    }
    return @($list)
}
$resolvedOrgs = Get-ResolvedSpaces
$resolvedSlugs = @($resolvedOrgs | ForEach-Object { [string]$_.slug })

$configSchema = Get-P20ConfigSchema -DefaultConfig $defaultCfg -Spaces $resolvedOrgs

# ---------------------------------------------------------------------------
# -Help
# ---------------------------------------------------------------------------
if ($Help) {
    # One renderer, the same entry the module's Show-CommandHelp reads, so this
    # command describes itself the same way whether it runs as a tk* verb or as
    # a plain .ps1 (which is how its suite drives it).
    . (Join-Path $PSScriptRoot 'Show-ConfigHelp.ps1')
    $prefix = ''
    if (Get-Command Get-CliPrefix -ErrorAction SilentlyContinue) { $prefix = Get-CliPrefix }
    Show-P20ConfigHelp -CommandName 'Config' -RepoRoot $toolkitRoot -Prefix $prefix `
        -Fallback 'Read and write the machine configuration.'
    exit 0
}

# ---------------------------------------------------------------------------
# -Schema
# ---------------------------------------------------------------------------
if ($Schema) {
    $rows = Get-P20ConfigSchema -DefaultConfig $defaultCfg -Spaces $resolvedOrgs
    if ($AsJson) {
        Write-Output (ConvertTo-P20ConfigJson @($rows))
        exit 0
    }
    Write-Host ''
    Write-Host '  Config schema -- what may be set, and where it is written' -ForegroundColor Cyan
    Write-Host ''
    $scopeLabels = @{
        machine = 'config.local.json -- this machine'
        org     = 'hub.json -- the engineer''s orgs (-Local for this machine only)'
        hub     = 'hub.json -- the hub''s own declaration (-Hub)'
        default = 'config.default.json -- the team''s, never written here'
    }
    foreach ($scope in @('machine', 'org', 'hub', 'default')) {
        $inScope = @($rows | Where-Object { $_.scope -eq $scope })
        if ($inScope.Count -eq 0) { continue }
        Write-Host "  $($scopeLabels[$scope])" -ForegroundColor Yellow
        foreach ($row in $inScope) {
            $type = $row.type
            if (@($row.allowed).Count -gt 0) { $type = "$type(" + (@($row.allowed) -join '|') + ')' }
            $req = ''
            if ($row.required) { $req = ' *required' }
            Write-Host ("    {0,-34} {1}{2}" -f $row.key, $type, $req) -ForegroundColor Gray
            Write-Host ("      {0}" -f $row.help) -ForegroundColor DarkGray
        }
        Write-Host ''
    }
    exit 0
}

# ---------------------------------------------------------------------------
# -List (and the default)
# ---------------------------------------------------------------------------

function Get-ResolvedSetting {
    <#
      One row of -List: the value in force and which file put it there.

      The order is the module's own: config.default.json, then the hub (which
      declares storeSync and the folder names), then config.local.json -- with
      PROMPTS_ROOT above all of them for the hub path, because that is what
      Resolve-P20HubRoot does and -List must report what the tool will actually
      use rather than what the files say.
    #>
    param([string]$Key)

    $value = $null
    $source = 'unset'

    $fromDefault = Get-PathValue $defaultCfg $Key
    if ($fromDefault.Found -and ('' -ne $fromDefault.Value) -and ($null -ne $fromDefault.Value)) {
        $value = $fromDefault.Value; $source = 'default'
    }
    $fromHub = Get-PathValue $hubCfg $Key
    if ($fromHub.Found -and ('' -ne $fromHub.Value) -and ($null -ne $fromHub.Value)) {
        $value = $fromHub.Value; $source = 'hub'
    }
    $fromLocal = Get-PathValue $localCfg $Key
    if ($fromLocal.Found -and ('' -ne $fromLocal.Value) -and ($null -ne $fromLocal.Value)) {
        $value = $fromLocal.Value; $source = 'local'
    }
    # A boolean false is a value, not an absence -- the guards above treat '' as
    # empty and $false is not '', so this only matters for the record.
    if ($fromLocal.Found -and ($fromLocal.Value -is [bool])) { $value = $fromLocal.Value; $source = 'local' }
    elseif ($fromHub.Found -and ($fromHub.Value -is [bool])) { $value = $fromHub.Value; $source = 'hub' }
    elseif ($fromDefault.Found -and ($fromDefault.Value -is [bool]) -and -not $fromLocal.Found) { $value = $fromDefault.Value; $source = 'default' }

    if ($Key -eq 'promptsRoot' -and $env:PROMPTS_ROOT -and $env:PROMPTS_ROOT.Trim()) {
        $value = $env:PROMPTS_ROOT.Trim(); $source = 'env'
    }
    return @{ Key = $Key; Value = $value; Source = $source }
}

function Get-SpaceSetting {
    <# The same, for one field of one org: default array, hub array, local patch. #>
    param([string]$Slug, [string]$Field)
    $value = $null
    $source = 'unset'
    if ($defaultCfg -and $defaultCfg.spaces) {
        $hit = @($defaultCfg.spaces | Where-Object { $_.slug -eq $Slug })
        if ($hit.Count -gt 0) {
            $v = Get-PathValue $hit[0] $Field
            if ($v.Found) { $value = $v.Value; $source = 'default' }
        }
    }
    if ($hubCfg -and $hubCfg.spaces) {
        $hit = @($hubCfg.spaces | Where-Object { $_.slug -eq $Slug })
        if ($hit.Count -gt 0) {
            $v = Get-PathValue $hit[0] $Field
            if ($v.Found) { $value = $v.Value; $source = 'hub' }
        }
    }
    if ($localCfg -and $localCfg.spaces -and -not ($localCfg.spaces -is [System.Array])) {
        $patch = $localCfg.spaces.PSObject.Properties[$Slug]
        if ($patch) {
            $v = Get-PathValue $patch.Value $Field
            if ($v.Found) { $value = $v.Value; $source = 'local' }
        }
    }
    return @{ Key = "spaces.$Slug.$Field"; Value = $value; Source = $source }
}

function Get-ActiveSlug {
    $slug = ''
    if ($defaultCfg -and $defaultCfg.activeSpace) { $slug = [string]$defaultCfg.activeSpace }
    if ($localCfg -and $localCfg.activeSpace) { $slug = [string]$localCfg.activeSpace }
    return (Resolve-P20RenamedSlug -Slug $slug -Slugs @($resolvedOrgs | ForEach-Object { [string]$_.slug }))
}

function Get-NavAliasNames {
    <#
      Every nav alias this machine knows, bare, in one list: the shipped three
      plus whatever config.local.json added. Read the same way the module reads
      them, so -List names the shortcuts that really exist rather than a pattern.
    #>
    $names = @()
    $prefix = Get-P20SchemaPrefix
    foreach ($cfg in @($defaultCfg, $localCfg)) {
        if ($null -eq $cfg -or -not $cfg.PSObject.Properties['aliases']) { continue }
        foreach ($prop in $cfg.aliases.PSObject.Properties) {
            $bare = ConvertTo-P20BareAliasKey -Key $prop.Name -Prefix $prefix
            if ($names -notcontains $bare) { $names += $bare }
        }
    }
    return @($names | Sort-Object)
}

function Get-ListRows {
    $rows = @()
    # A schema row whose key carries a <name> is a PATTERN -- aliases.<name>.path
    # -- and there is nothing to resolve it against. The real ones are listed
    # below, one per alias the machine has.
    foreach ($row in @($configSchema | Where-Object { $_.scope -eq 'machine' -and $_.key -notlike '*<*' })) {
        $resolved = Get-ResolvedSetting $row.key
        $rows += [PSCustomObject]@{
            key = $row.key; scope = 'machine'; file = 'config.local.json'
            value = (Format-Value $resolved.Value); source = $resolved.Source
        }
    }
    foreach ($name in (Get-NavAliasNames)) {
        $key = "aliases.$name.path"
        $resolved = Get-ResolvedSetting $key
        if ($resolved.Source -eq 'unset') {
            # The file may still spell the key with the prefix. The module reads
            # that as the bare name, so this report has to as well -- the row is
            # printed canonically either way.
            $legacy = Get-ResolvedSetting "aliases.$((Get-P20SchemaPrefix))$name.path"
            if ($legacy.Source -ne 'unset') { $resolved = $legacy }
        }
        $rows += [PSCustomObject]@{
            key = $key; scope = 'machine'; file = 'config.local.json'
            value = (Format-Value $resolved.Value); source = $resolved.Source
        }
    }
    foreach ($row in @($configSchema | Where-Object { $_.scope -eq 'hub' })) {
        $resolved = Get-ResolvedSetting $row.key
        $rows += [PSCustomObject]@{
            key = "hub:$($row.key)"; scope = 'hub'; file = 'hub.json'
            value = (Format-Value $resolved.Value); source = $resolved.Source
        }
    }
    $slug = Get-ActiveSlug
    if ($slug) {
        foreach ($field in (Get-P20SpaceFieldSchema)) {
            $resolved = Get-SpaceSetting $slug $field.key
            $rows += [PSCustomObject]@{
                key = $resolved.Key; scope = 'org'; file = 'hub.json'
                value = (Format-Value $resolved.Value); source = $resolved.Source
            }
        }
    }
    return @($rows)
}

if (-not $Set -and -not $Unset) {
    $rows = Get-ListRows
    if ($AsJson) {
        $payload = [PSCustomObject]@{
            activeSpace = (Get-ActiveSlug)
            files     = [PSCustomObject]@{
                default = $defaultPath
                local   = $localPath
                hub     = $hubPath
            }
            settings  = @($rows)
        }
        Write-Output (ConvertTo-P20ConfigJson $payload)
        exit 0
    }

    Write-Host ''
    Write-Host '  Configuration' -ForegroundColor Cyan
    Write-Host "  config.default.json  $defaultPath" -ForegroundColor DarkGray
    $localNote = $localPath
    if (-not (Test-Path -LiteralPath $localPath)) { $localNote = "$localPath (not created yet)" }
    Write-Host "  config.local.json    $localNote" -ForegroundColor DarkGray
    if ($hubPath) { Write-Host "  hub.json             $hubPath" -ForegroundColor DarkGray }
    else { Write-Host '  hub.json             (no hub configured)' -ForegroundColor DarkGray }
    Write-Host ''
    Write-Host ('  {0,-34} {1,-8} {2}' -f 'Setting', 'Source', 'Value') -ForegroundColor Yellow
    Write-Host ('  {0,-34} {1,-8} {2}' -f '-------', '------', '-----') -ForegroundColor DarkGray
    foreach ($row in $rows) {
        $colour = 'Gray'
        if ($row.source -eq 'unset') { $colour = 'DarkGray' }
        elseif ($row.source -eq 'local' -or $row.source -eq 'env') { $colour = 'Cyan' }
        Write-Host ('  {0,-34} {1,-8} {2}' -f $row.key, $row.source, $row.value) -ForegroundColor $colour
    }
    Write-Host ''
    exit 0
}

# ---------------------------------------------------------------------------
# -Set / -Unset
#
# Every pair is validated BEFORE any file is touched, and each file is written
# once at the end. A run that refuses has changed nothing.
# ---------------------------------------------------------------------------

$changes = @()          # { Key, File, Old, New, Action }
$aliasNotes = @()       # said once, after the change list
$pendingLocal = $localCfg
$pendingHub = $hubCfg
$touchLocal = $false
$touchHub = $false

function Deny {
    param([string]$Message, [string]$Hint)
    Write-CliError -Message $Message -Hint $Hint
    exit 2
}

function Get-HubSpaceEntry {
    <# The org entry in the pending hub manifest, or $null. #>
    param([string]$Slug)
    if ($null -eq $pendingHub -or -not $pendingHub.PSObject.Properties['spaces']) { return $null }
    $hit = @($pendingHub.spaces | Where-Object { $_ -and $_.slug -eq $Slug })
    if ($hit.Count -eq 0) {
        # The patch a machine wrote under a renamed Space's OLD slug is this
        # Space's entry: write into it, so its promptsFolder (where the cards
        # are) stands, rather than add a second entry beside it.
        $renamedMap = Get-P20RenamedSpaceSlugs
        $hit = @($pendingHub.spaces | Where-Object {
            $_ -and $_.slug -and $renamedMap.Contains([string]$_.slug) -and $renamedMap[[string]$_.slug] -eq $Slug -and -not $_.PSObject.Properties['name']
        })
    }
    if ($hit.Count -eq 0) { return $null }
    return $hit[0]
}

function Assert-HubWritable {
    param([string]$Key)
    if (-not $hubRoot) {
        Deny "'$Key' is the hub's, and no hub is configured." `
            "Set promptsRoot first: Config -Set promptsRoot=<path to your hub>."
    }
    if (-not (Test-P20HubRoot $hubRoot)) {
        Deny (Get-P20HubMissingMessage $hubRoot) `
            'Connect the drive, or point promptsRoot somewhere that exists.'
    }
}

# TWO SPELLINGS FOR -Set, AND WHY.
#
# `-Set email=you@example.com` is what a person types, and `-Set a=1,b=2` is the
# array form PowerShell already gives every [string[]] parameter. Neither
# survives the bridge when there is more than one pair: argv arrives at
# bridge.ps1 as flat strings and is splatted, so `-Set a=1 -Set b=2` is "Set is
# specified more than once" and `-Set a=1 b=2` has nowhere positional to land.
#
# So a single element that begins with `{` is read as a JSON OBJECT of
# key -> value, which carries any number of pairs in one argv token and keeps a
# value's own type. That is what PUT /api/config sends, and the values are
# turned back into the same strings the key=value form produces so BOTH
# spellings go through one validator.
function ConvertTo-SetPairs {
    param([string[]]$Raw)
    $pairs = @()
    foreach ($element in @($Raw)) {
        if ($null -eq $element) { continue }
        $text = [string]$element
        if ($text.TrimStart().StartsWith('{')) {
            $parsed = $null
            try { $parsed = ConvertFrom-Json $text -ErrorAction Stop }
            catch { Deny "-Set was given something that starts like JSON and is not: $($_.Exception.Message)" 'Either one key=value pair per element, or one JSON object of key to value.' }
            foreach ($prop in $parsed.PSObject.Properties) {
                $pairs += [PSCustomObject]@{ Key = $prop.Name; Value = (ConvertTo-SetValueText $prop.Value) }
            }
            continue
        }
        $split = $text.IndexOf('=')
        if ($split -lt 1) {
            Deny "'$text' is not a key=value pair." 'The shape is -Set <key>=<value>, for example -Set email=you@example.com.'
        }
        $pairs += [PSCustomObject]@{ Key = $text.Substring(0, $split).Trim(); Value = $text.Substring($split + 1) }
    }
    return @($pairs)
}

function ConvertTo-SetValueText {
    <# A JSON value as the string the key=value form would have carried. #>
    param($Value)
    if ($null -eq $Value) { return '' }
    if ($Value -is [bool]) {
        if ($Value) { return 'true' }
        return 'false'
    }
    if ($Value -is [string]) { return $Value }
    if ($Value -is [System.Collections.IEnumerable]) { return (ConvertTo-P20ConfigJson @($Value)) }
    return [string]$Value
}

function ConvertTo-UnsetKeys {
    <#
      -Unset takes keys, and a key never contains a comma, so the comma-separated
      form is unambiguous here in a way it is not for -Set. A single element that
      begins with `[` is read as a JSON array, which is what the agent sends.
    #>
    param([string[]]$Raw)
    $keys = @()
    foreach ($element in @($Raw)) {
        if ($null -eq $element) { continue }
        $text = ([string]$element).Trim()
        if (-not $text) { continue }
        if ($text.StartsWith('[')) {
            $parsed = $null
            try { $parsed = ConvertFrom-Json $text -ErrorAction Stop }
            catch { Deny "-Unset was given something that starts like JSON and is not: $($_.Exception.Message)" 'Either one key per element, or one JSON array of keys.' }
            foreach ($item in @($parsed)) { $keys += [string]$item }
            continue
        }
        foreach ($part in $text.Split(',')) {
            $trimmed = $part.Trim()
            if ($trimmed) { $keys += $trimmed }
        }
    }
    return @($keys)
}

foreach ($pair in (ConvertTo-SetPairs $Set)) {
    $key = $pair.Key
    $rawValue = [string]$pair.Value

    $resolvedKey = Resolve-P20SchemaKey -Key $key -Schema $configSchema
    if ($resolvedKey.Reason) {
        Deny $resolvedKey.Reason 'Run Config -Schema for every setting this command knows, and which file each one is written to.'
    }
    $row = $resolvedKey.Row
    if ($resolvedKey.Alias) {
        # The older spelling still works; the new name is said once per key.
        $aliasNotes += "$($resolvedKey.Alias) is $($row.key) now -- the container is a Space. Both are accepted."
        $key = $row.key
    }
    if ($resolvedKey.Slug) {
        # A renamed Space's old slug is accepted and written as the new one.
        $renamedTo = Resolve-P20RenamedSlug -Slug $resolvedKey.Slug -Slugs $resolvedSlugs
        if ($renamedTo -ne $resolvedKey.Slug) {
            $aliasNotes += (Get-P20RenamedSlugNote -From $resolvedKey.Slug -To $renamedTo)
            $key = "spaces.$renamedTo.$($resolvedKey.Field)"
            $resolvedKey.Slug = $renamedTo
        }
    }

    if ($row.scope -eq 'default') {
        Deny "'$key' is defined in config.default.json, which this command never writes." `
            'It is the team''s table, not this machine''s: edit config.default.json in the commit that changes it.'
    }

    # storeSync and folders.* are the hub's declarations. storeSync also exists
    # as a machine override, which is why -Hub picks between them; folders.* has
    # no machine form at all and so insists on the switch rather than guessing.
    if ($row.scope -eq 'hub' -and -not $Hub) {
        Deny "'$key' is the hub's own declaration, not this machine's." `
            "Pass -Hub to write it into hub.json."
    }

    if ($key -eq 'activeSpace') {
        # A renamed Space's old slug is accepted and written as the new one
        # -- before the enum check, which knows only the slugs that exist.
        $renamedTo = Resolve-P20RenamedSlug -Slug $rawValue.Trim() -Slugs $resolvedSlugs
        if ($renamedTo -ne $rawValue.Trim()) {
            $aliasNotes += (Get-P20RenamedSlugNote -From $rawValue.Trim() -To $renamedTo)
            $rawValue = $renamedTo
        }
    }
    $checked = Test-P20ConfigValue -Row $row -Value $rawValue
    if (-not $checked.Ok) {
        Deny $checked.Reason 'Run Config -Schema to see the values this setting takes.'
    }
    $value = $checked.Value

    if ($resolvedKey.Slug) {
        # ---- an org's field --------------------------------------------------
        $slug = $resolvedKey.Slug
        $field = $resolvedKey.Field
        if ($field -eq 'slug') {
            Deny "A Space's slug is the key it is stored under and cannot be set as a field." `
                'To rename a Space, add the new slug and archive the old one.'
        }
        if ($Local) {
            $path = "spaces.$slug.$field"
            $old = (Get-PathValue $pendingLocal $path)
            $pendingLocal = Set-PathValue $pendingLocal $path $value
            $touchLocal = $true
            $changes += [PSCustomObject]@{ Key = $path; File = 'config.local.json'; Old = (Format-Value $old.Value); New = (Format-Value $value); Action = 'set' }
            continue
        }

        Assert-HubWritable $key
        if ($null -eq $pendingHub) { $pendingHub = New-Object PSObject }
        if (-not $pendingHub.PSObject.Properties['hub']) {
            $pendingHub | Add-Member -NotePropertyName 'hub' -NotePropertyValue 1 -Force
        }
        if (-not $pendingHub.PSObject.Properties['spaces'] -or -not ($pendingHub.spaces -is [System.Array])) {
            $pendingHub | Add-Member -NotePropertyName 'spaces' -NotePropertyValue @() -Force
        }
        $entry = Get-HubSpaceEntry $slug
        $shippedSpace = $null
        if ($null -eq $entry -and $defaultCfg -and $defaultCfg.spaces) {
            $shippedSpace = @($defaultCfg.spaces | Where-Object { $_ -and $_.slug -eq $slug }) | Select-Object -First 1
        }
        if ($null -eq $entry -and $shippedSpace) {
            # A slug the SHIPPED config declares is not a new org. The entry is a
            # sparse patch -- slug, the promptsFolder both loaders require, and the
            # field being set -- which both loaders deep-merge over the shipped
            # org. Seeding it like a new org (name = slug, status = local) made
            # `Config -Set orgs.test.org=<url>`, the first step of connecting the
            # Example org, rename it "test" and switch ADO OFF.
            $folder = [string]$shippedSpace.promptsFolder
            if (-not $folder) { $folder = $slug }
            $entry = [PSCustomObject]@{
                slug          = $slug
                promptsFolder = $folder
            }
            $pendingHub.spaces = @($pendingHub.spaces) + @($entry)
            $changes += [PSCustomObject]@{ Key = "spaces.$slug"; File = 'hub.json'; Old = ''; New = "patch on the shipped Space (promptsFolder $folder; everything else stays as shipped)"; Action = 'add' }
        }
        if ($null -eq $entry) {
            # A slug nobody has declared is how a NEW org is added. It arrives
            # with the two fields both loaders require -- without them the entry
            # is skipped with a warning and the write would look like it worked
            # -- and with status 'local', which is the fail-closed value: an org
            # contacts ADO only once someone has given it a URL and said so.
            $entry = [PSCustomObject]@{
                slug          = $slug
                name          = $slug
                status        = 'local'
                promptsFolder = $slug
            }
            $pendingHub.spaces = @($pendingHub.spaces) + @($entry)
            $changes += [PSCustomObject]@{ Key = "spaces.$slug"; File = 'hub.json'; Old = ''; New = "new Space (status local, promptsFolder $slug)"; Action = 'add' }
        }
        $old = (Get-PathValue $entry $field)
        [void](Set-PathValue $entry $field $value)
        $touchHub = $true
        $changes += [PSCustomObject]@{ Key = "spaces.$slug.$field"; File = 'hub.json'; Old = (Format-Value $old.Value); New = (Format-Value $value); Action = 'set' }
        continue
    }

    if ($row.scope -eq 'hub') {
        # ---- the hub's own declaration --------------------------------------
        Assert-HubWritable $key
        if ($null -eq $pendingHub) { $pendingHub = New-Object PSObject }
        if (-not $pendingHub.PSObject.Properties['hub']) {
            $pendingHub | Add-Member -NotePropertyName 'hub' -NotePropertyValue 1 -Force
        }
        $old = (Get-PathValue $pendingHub $key)
        $pendingHub = Set-PathValue $pendingHub $key $value
        $touchHub = $true
        $changes += [PSCustomObject]@{ Key = $key; File = 'hub.json'; Old = (Format-Value $old.Value); New = (Format-Value $value); Action = 'set' }
        continue
    }

    # ---- a machine setting ---------------------------------------------------
    if ($key -eq 'activeSpace') {
        $slugs = @($resolvedOrgs | ForEach-Object { $_.slug })
        if ($slugs.Count -gt 0 -and -not ($slugs -contains [string]$value)) {
            Deny "'$value' is not a Space this machine knows." "Available: $($slugs -join ', '). Add one with Config -Set spaces.<slug>.name=<name>."
        }
    }
    $old = (Get-ResolvedSetting $key)
    $pendingLocal = Set-PathValue $pendingLocal $key $value
    $touchLocal = $true
    $changes += [PSCustomObject]@{ Key = $key; File = 'config.local.json'; Old = (Format-Value $old.Value); New = (Format-Value $value); Action = 'set' }

    # A nav shortcut of your own, set by its path. Two things the person typing
    # it cannot see: a local-only alias is registered only while `display` is
    # true, so it is written true here in the same write (a person who sets a
    # path wants the shortcut); and a name the shipped config does not declare is
    # not in the autoload manifest, so it answers once the module is loaded and
    # not as the first command of a fresh shell. Both are said, once, below.
    #
    if ($key -match '^aliases\.([^.]+)\.path$') {
        $aliasName = $Matches[1]
        $shipped = @()
        if ($defaultCfg -and $defaultCfg.PSObject.Properties['aliases']) {
            $shipped = @($defaultCfg.aliases.PSObject.Properties | ForEach-Object { ConvertTo-P20BareAliasKey -Key $_.Name -Prefix (Get-P20SchemaPrefix) })
        }
        if ($shipped -notcontains $aliasName) {
            $displayKey = "aliases.$aliasName.display"
            $displayNow = Get-PathValue $pendingLocal $displayKey
            if ($null -eq $displayNow.Value) {
                $pendingLocal = Set-PathValue $pendingLocal $displayKey $true
                $changes += [PSCustomObject]@{ Key = $displayKey; File = 'config.local.json'; Old = ''; New = 'true'; Action = 'set' }
            }
            $aliasNotes += "$($cliPrefix)$aliasName is yours, not a shipped name: it answers once any $($cliPrefix)* command has loaded the module, not as the first command of a new shell. A name in config.default.json is what autoloads."
        }
    }
}

foreach ($rawKey in (ConvertTo-UnsetKeys $Unset)) {
    $key = ([string]$rawKey).Trim()

    # A WHOLE Space, `spaces.<slug>` with no field: -Hub un-declares it --
    # its entry leaves hub.json -- and without -Hub this machine's patch for it
    # leaves config.local.json. Nothing here touches a folder: removing a Space
    # never deletes a card. RemoveSpace is the verb that runs these two lines.
    if ($key -match '^(spaces|orgs)\.([^.]+)$') {
        $slug = $Matches[2]
        if ($Matches[1] -eq 'orgs') { $aliasNotes += "orgs.$slug is spaces.$slug now -- the container is a Space. Both are accepted." }
        if ($Hub) {
            $renamedTo = Resolve-P20RenamedSlug -Slug $slug -Slugs $resolvedSlugs
            if ($renamedTo -ne $slug) {
                $aliasNotes += (Get-P20RenamedSlugNote -From $slug -To $renamedTo)
                $slug = $renamedTo
            }
            Assert-HubWritable "spaces.$slug"
            if ($slug -eq (Get-ActiveSlug)) {
                Deny "'$slug' is the Space you are in, and a Space is not removed from under you." `
                    "Switch to another first: $($cliPrefix)SwitchSpace <slug>."
            }
            if ($defaultCfg -and $defaultCfg.spaces -and @($defaultCfg.spaces | Where-Object { $_ -and $_.slug -eq $slug }).Count -gt 0) {
                Deny "'$slug' is a Space config.default.json ships, which this command never removes." `
                    "It is the team's. Hide the demo Spaces with $($cliPrefix)Config -Set isDemoDismissed=true, or retire it: $($cliPrefix)RetireSpace $slug."
            }
            $entry = Get-HubSpaceEntry $slug
            if ($null -eq $entry) {
                Write-Host "  spaces.$slug is not declared in hub.json -- nothing to remove." -ForegroundColor DarkGray
                continue
            }
            $folder = [string]$entry.promptsFolder
            $kept = @($pendingHub.spaces | Where-Object { -not [object]::ReferenceEquals($_, $entry) })
            $pendingHub.spaces = $kept
            $touchHub = $true
            $changes += [PSCustomObject]@{ Key = "spaces.$slug"; File = 'hub.json'; Old = "declared (promptsFolder $folder)"; New = ''; Action = 'unset' }
            continue
        }
        $patchHolder = $null
        if ($pendingLocal -and $pendingLocal.PSObject.Properties['spaces'] -and ($pendingLocal.spaces -is [System.Management.Automation.PSCustomObject])) {
            $patchHolder = $pendingLocal.spaces
        }
        if ($patchHolder -and $patchHolder.PSObject.Properties[$slug]) {
            $patchHolder.PSObject.Properties.Remove($slug)
            $touchLocal = $true
            $changes += [PSCustomObject]@{ Key = "spaces.$slug"; File = 'config.local.json'; Old = "this machine's patch"; New = ''; Action = 'unset' }
        }
        else {
            Write-Host "  spaces.$slug has no patch in config.local.json -- nothing to remove." -ForegroundColor DarkGray
        }
        continue
    }

    $resolvedKey = Resolve-P20SchemaKey -Key $key -Schema $configSchema
    if ($resolvedKey.Reason) {
        Deny $resolvedKey.Reason 'Run Config -Schema for every setting this command knows.'
    }
    $row = $resolvedKey.Row
    if ($resolvedKey.Alias) { $key = $row.key }
    # In hub.json a renamed Space's old-slug patch IS the new Space's entry
    # (Get-HubSpaceEntry finds it); this machine's file keeps the key it was
    # written under, so a local -Unset removes exactly what was typed.
    if ($resolvedKey.Slug -and $Hub) {
        $renamedTo = Resolve-P20RenamedSlug -Slug $resolvedKey.Slug -Slugs $resolvedSlugs
        if ($renamedTo -ne $resolvedKey.Slug) {
            $aliasNotes += (Get-P20RenamedSlugNote -From $resolvedKey.Slug -To $renamedTo)
            $key = "spaces.$renamedTo.$($resolvedKey.Field)"
            $resolvedKey.Slug = $renamedTo
        }
    }
    if ($row.scope -eq 'default') {
        Deny "'$key' is defined in config.default.json, which this command never writes." `
            'It is the team''s table, not this machine''s.'
    }

    if ($resolvedKey.Slug -and $Hub) {
        Assert-HubWritable $key
        $slug = $resolvedKey.Slug
        $field = $resolvedKey.Field
        if ((Get-P20RequiredSpaceFields) -contains $field) {
            Deny "'$field' is required on a Space and cannot be removed." `
                "A Space without slug and promptsFolder is skipped by both loaders. To retire the Space, set spaces.$slug.status=archive."
        }
        $entry = Get-HubSpaceEntry $slug
        if ($null -eq $entry) {
            Write-Host "  spaces.$slug is not declared in hub.json -- nothing to remove." -ForegroundColor DarkGray
            continue
        }
        $old = (Get-PathValue $entry $field)
        if (Remove-PathValue $entry $field) {
            $touchHub = $true
            $changes += [PSCustomObject]@{ Key = "spaces.$slug.$field"; File = 'hub.json'; Old = (Format-Value $old.Value); New = ''; Action = 'unset' }
        }
        else {
            Write-Host "  spaces.$slug.$field is not set in hub.json -- nothing to remove." -ForegroundColor DarkGray
        }
        continue
    }

    if ($row.scope -eq 'hub' -and -not $Hub) {
        Deny "'$key' is the hub's own declaration, not this machine's." 'Pass -Hub to remove it from hub.json.'
    }
    if ($row.scope -eq 'hub') {
        Assert-HubWritable $key
        $old = (Get-PathValue $pendingHub $key)
        if (Remove-PathValue $pendingHub $key) {
            $touchHub = $true
            $changes += [PSCustomObject]@{ Key = $key; File = 'hub.json'; Old = (Format-Value $old.Value); New = ''; Action = 'unset' }
        }
        else {
            Write-Host "  $key is not set in hub.json -- nothing to remove." -ForegroundColor DarkGray
        }
        continue
    }

    # A machine key, or an org field without -Hub: both are removals of a LOCAL
    # override, which is all -Unset means by default. The hub's own value, and
    # the shipped default, stand.
    $path = $key
    if ($resolvedKey.Slug) { $path = "spaces.$($resolvedKey.Slug).$($resolvedKey.Field)" }
    $old = (Get-PathValue $pendingLocal $path)
    if (Remove-PathValue $pendingLocal $path) {
        $touchLocal = $true
        $changes += [PSCustomObject]@{ Key = $path; File = 'config.local.json'; Old = (Format-Value $old.Value); New = ''; Action = 'unset' }
    }
    else {
        Write-Host "  $path is not set in config.local.json -- nothing to remove." -ForegroundColor DarkGray
    }
}

if ($changes.Count -eq 0) {
    Write-Host ''
    Write-Host '  Nothing to change.' -ForegroundColor DarkGray
    Write-Host ''
    exit 0
}

# The files carry the product's spelling, `spaces` and `activeSpace`, from
# here on (stage 2, step 2): a file that still said `orgs` or `activeOrg`
# comes out saying the new name where the old one stood. The keys a person
# TYPES (`spaces.<slug>.status`, `activeOrg`) are the verb's vocabulary and
# stay until stage 3 renames it.
if ($touchLocal) { Write-ConfigJson -Path $localPath -Value $pendingLocal }
if ($touchHub) { Write-ConfigJson -Path $hubPath -Value $pendingHub }

Write-Host ''
foreach ($change in $changes) {
    $old = $change.Old
    if (-not $old) { $old = '(unset)' }
    $new = $change.New
    if (-not $new) { $new = '(unset)' }
    Write-Host ("  [+] {0,-30} {1} -> {2}" -f $change.Key, $old, $new) -ForegroundColor Green
    Write-Host ("      {0}" -f $change.File) -ForegroundColor DarkGray
}

# What a restart actually needs.
#
# Nothing, almost always, and saying so is the point: the agent re-reads config
# on every request that touches it, so an org, a feature flag or a path is live
# on the next call. The two exceptions are caches with a 45-second TTL -- the
# ADO reachability probe and the resolved identity -- which `email` and a change
# of org fall behind. The agent's PUT /api/config clears both after a write, so
# a browser edit is immediate; a hand-run of this verb waits out the TTL.
foreach ($note in $aliasNotes) {
    Write-Host ''
    Write-Host "  $note" -ForegroundColor Yellow
}
$needsAgentNote = @($changes | Where-Object { $_.Key -eq 'web.agentPort' -or $_.Key -eq 'web.corsOrigins' })
if ($needsAgentNote.Count -gt 0) {
    Write-Host ''
    Write-Host "  The agent binds its port and its CORS list at startup -- restart it: $($cliPrefix)Agent -Stop, $($cliPrefix)Agent" -ForegroundColor Yellow
}
# A module flag is read per request by the agent and the web UI, but a shell
# registered its verbs, menu and inventory when it imported the module.
# A note on success, not a refusal: no Write-CliError, exit code untouched.
$flagNote = @($changes | Where-Object { $_.Key -like 'features.*' })
if ($flagNote.Count -gt 0) {
    Write-Host ''
    Write-Host '  Open shells keep their current menu until they re-import; the agent and the web UI see this on the next request.' -ForegroundColor Yellow
}
Write-Host ''

# The session that ran this is holding the old answer. SwitchSpace has reloaded
# the module since it was written, for the same reason and in the same way.
if ($global:P20Config) {
    $modulePath = Join-Path $toolkitRoot 'utilities.psm1'
    if (Test-Path -LiteralPath $modulePath) {
        Import-Module $modulePath -Global -Force -DisableNameChecking 2>$null
        $global:P20Env = $null
    }
}

exit 0
