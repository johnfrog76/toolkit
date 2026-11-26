<#
.SYNOPSIS
    Staff -- the org file's one writer: start a tree from a preset, or choose the tree in use (the Team Agile add-on).

.DESCRIPTION
    Writes the hub's org file (consts.json org.file, at the hub root beside
    hub.json; docs/hub/org.md). Two forms:

      Staff -Preset S|M|L [-Tree <id>] [-Title <text>] [-Owner <name>]
            [-VpEngineering <model>] [-VpProduct <model>] [-WhatIf]
      Staff -Activate <tree-id> [-WhatIf]

    -Preset copies the preset of that size (the package's org presets,
    consts.json org.presetsFolder) into the file as a new tree -- creating the
    file when there is none -- with `preset` set to the preset's id and the
    default models filled in (docs/hub/org.md, "The one writer: Staff"; the
    table is $seatDefaults below), the VP of product's seat holding the merge.
    Each is stored as the model map's id
    (Config/models.json): a family resolves through its `current` block, an id
    passes through, nothing is parsed. The PM, the test runner and the merge
    stand-in stay vacant. -VpEngineering and -VpProduct put another model in
    those two seats; -Owner names the owner (the root's seat, a person, never a
    model; the preset's "You" otherwise); -Title names the tree.

    The tree's id is -Tree, else the preset's id, then <id>-2 and <id>-3. An id
    that is already a tree is refused -- a tree is never overwritten -- and so
    is a fourth tree. A saved tree is a DRAFT: -Preset never changes the tree in
    use, and only -Activate <tree-id> does. Adding a second tree to a file that
    names no tree in use names the one that was in use, so the file stays
    valid; the first tree of a new file is the only one, and so the one in use.

    Every write reads the file, changes only what the command names, keeps every
    other tree, key and note in its order, checks the result with the reader's
    own checks (Scripts/Read-OrgChart.ps1), and writes it as two-space JSON,
    UTF-8 with no BOM, through Write-CardText: a created file is LF, an edited
    one keeps its own line ending. -WhatIf prints the file it would write and
    writes nothing. It never prompts.

.PARAMETER Tree
    The id of the tree: the new tree's with -Preset, the one to put in use with -Activate alone.
.PARAMETER Preset
    S, M or L: the preset to start the tree from.
.PARAMETER Title
    The new tree's title, in place of the preset's.
.PARAMETER Owner
    The owner's name, on the root's seat, in place of the preset's "You".
.PARAMETER VpEngineering
    The VP of engineering's model: a model id or a family; the default otherwise.
.PARAMETER VpProduct
    The VP of product's model: a model id or a family; the default otherwise.
.PARAMETER Activate
    Make the tree -Tree names the one in use. Not with -Preset: a saved tree is a draft.
.PARAMETER WhatIf
    Print the file it would write, and write nothing.

.EXAMPLE
    {cliPrefix}Staff -Preset S -Owner Sam
.EXAMPLE
    {cliPrefix}Staff -Preset M -Tree branch -VpProduct opus -WhatIf
.EXAMPLE
    {cliPrefix}Staff -Activate branch

.NOTES
    PowerShell 5.1 compatible (ASCII dashes only).
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $false, Position = 0)]
    [string]$Tree,
    [Parameter(Mandatory = $false)]
    [string]$Preset,
    [Parameter(Mandatory = $false)]
    [string]$Title,
    [Parameter(Mandatory = $false)]
    [string]$Owner,
    [Parameter(Mandatory = $false)]
    [string]$VpEngineering,
    [Parameter(Mandatory = $false)]
    [string]$VpProduct,
    [Parameter(Mandatory = $false)]
    [switch]$Activate,
    [Parameter(Mandatory = $false)]
    [switch]$WhatIf,
    [Parameter(Mandatory = $false)]
    [switch]$Help
)

$repoRoot = Split-Path -Parent $PSScriptRoot

. (Join-Path $PSScriptRoot 'Initialize-CliFallbacks.ps1')

$p = Get-CliPrefix
$usage = "${p}Staff -Preset S|M|L [-Tree <id>] [-Title <text>] [-Owner <name>] [-VpEngineering <model>] [-VpProduct <model>] [-WhatIf]  |  ${p}Staff -Activate <tree-id> [-WhatIf]"

if ($Help) {
    Write-Host ""
    Write-Host "  ${p}Staff -- the org file's one writer" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  Usage:" -ForegroundColor Yellow
    Write-Host "    ${p}Staff -Preset S|M|L [-Tree <id>] [-Title <text>] [-Owner <name>] [-VpEngineering <model>] [-VpProduct <model>] [-WhatIf]"
    Write-Host "    ${p}Staff -Activate <tree-id> [-WhatIf]"
    Write-Host ""
    Write-Host "  -Preset saves a tree from a preset, with the default models, as a draft; -Activate chooses the tree in use."
    Write-Host "  A tree is never overwritten, and a file holds at most three. -WhatIf writes nothing."
    Write-Host ""
    return
}

. (Join-Path $PSScriptRoot 'Resolve-HubConfig.ps1')
. (Join-Path $PSScriptRoot 'Get-Consts.ps1')
. (Join-Path $PSScriptRoot 'Read-OrgChart.ps1')
. (Join-Path $PSScriptRoot 'Write-CardText.ps1')
. (Join-Path $PSScriptRoot 'Write-ConfigJson.ps1')
. (Join-Path $PSScriptRoot 'Get-PromptFileStatus.ps1')

$fileName = Get-P20OrgFileName
$cfg = $global:P20Config
$maxTrees = 3

# The default models (docs/hub/org.md, "Staff"): a position's id -> the family
# its seats start with. The pool's family is its default-model line instead.
# Every other seat starts vacant.
$seatDefaults = [ordered]@{
    'vp-engineering' = 'opus'
    'vp-product'     = 'fable'
    'team-lead'      = 'opus'
    'intern'         = 'haiku'
    'butler'         = 'haiku'
}
$poolDefault = 'sonnet'
$mergesPosition = 'vp-product'

function Stop-Staff([string]$Message, [string]$Hint = '') {
    if (-not $Hint) { $Hint = "Usage: $usage" }
    Write-CliError -Message $Message -Hint $Hint
    exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
}

# -- What was asked ------------------------------------------------------------------

$Tree = ([string]$Tree).Trim()
$Preset = ([string]$Preset).Trim()
$creating = [bool]$Preset
if ($creating -and $Activate) {
    Stop-Staff '-Activate does not go with -Preset: a saved tree is a draft, and the tree in use stays as it was.' `
        "Save it first, then put it in use with '${p}Staff -Activate <tree-id>'."
}
if (-not $creating -and -not $Activate) {
    Stop-Staff 'Nothing to do: give -Preset S|M|L to add a tree, or -Activate <tree-id> to choose the tree in use.'
}
if (-not $creating) {
    foreach ($name in @('Title', 'Owner', 'VpEngineering', 'VpProduct')) {
        if ($PSBoundParameters.ContainsKey($name)) { Stop-Staff "-$name goes with -Preset: it fills the tree -Preset adds." }
    }
    if (-not $Tree) { Stop-Staff '-Activate needs the id of the tree to put in use.' }
}

# "The hub resolved" is not "a hub was configured" (OrgChart's own rule).
$hubRoot = ''
if ($cfg) { $hubRoot = [string]$cfg.PromptsRoot }
if (-not (Get-P20ConfiguredHub -PackageRoot $repoRoot)) {
    Stop-Staff "No hub is configured, so there is no $fileName to write." `
        "Point the toolkit at your hub with '${p}Config -Set promptsRoot=<folder>'; the chart is $fileName at its root (docs/hub/org.md)."
}
if (-not (Test-P20HubRoot $hubRoot)) { Stop-Staff (Get-P20HubMissingMessage $hubRoot) ' ' }
$orgPath = Join-Path $hubRoot $fileName

# -- Reading what is there -------------------------------------------------------------

function ConvertFrom-StaffJson([string]$Text) {
    # PowerShell 7 turns an ISO-looking string into a date unless told not to
    # (-DateKind String, 7.3+); 5.1 never does. A note that held a timestamp must
    # come back as the text it was.
    $cmd = Get-Command ConvertFrom-Json
    if ($cmd.Parameters.ContainsKey('DateKind')) { return ($Text | ConvertFrom-Json -DateKind String -ErrorAction Stop) }
    return ($Text | ConvertFrom-Json -ErrorAction Stop)
}

function Set-StaffField($Object, [string]$Name, $Value) {
    # Set a key in place when it is there (its position kept), else add it at the end.
    foreach ($prop in $Object.PSObject.Properties) {
        if ($prop.Name -ceq $Name) { $prop.Value = $Value; return }
    }
    $Object | Add-Member -NotePropertyName $Name -NotePropertyValue $Value
}

$exists = Test-Path -LiteralPath $orgPath -PathType Leaf
$data = $null
$trees = @()
if ($exists) {
    $before = Read-P20OrgChart -PromptsRoot $hubRoot -PackageRoot $repoRoot
    if ($before.Status -ne 'ok') {
        Stop-Staff "$orgPath is not valid now, so nothing was written: $($before.Message)" `
            "Fix the file first; ${p}OrgChart says what is wrong, and docs/hub/org.md lists what is checked."
    }
    $data = ConvertFrom-StaffJson (Read-CardText -Path $orgPath)
    $trees = (Get-P20OrgItems (Get-P20OrgField $data 'trees'))
}
elseif (-not $creating) {
    Stop-Staff "There is no $fileName in the hub, so there is no tree to put in use." `
        "Start one with '${p}Staff -Preset S|M|L'; docs/hub/org.md has the shape."
}
$treeIds = @($trees | ForEach-Object { Get-P20OrgText (Get-P20OrgField $_ 'id') })
$activeBefore = ''
if ($data) { $activeBefore = Get-P20OrgText (Get-P20OrgField $data 'activeTree') }

# -- The tree -Preset adds ---------------------------------------------------------------

$newTree = $null
$presetId = ''
if ($creating) {
    $presetDir = Join-Path $repoRoot ([string](Get-P20Consts).org.presetsFolder)
    $presetFile = $null
    $sizes = New-Object System.Collections.Generic.List[string]
    foreach ($file in @(Get-ChildItem -LiteralPath $presetDir -Filter '*.json' -File -ErrorAction SilentlyContinue | Sort-Object Name)) {
        try { $candidate = ConvertFrom-StaffJson (Read-CardText -Path $file.FullName) } catch { continue }
        $size = Get-P20OrgText (Get-P20OrgField $candidate 'size')
        if ($size) { $sizes.Add($size) }
        if ($size -and $size -eq $Preset) { $presetFile = $candidate }
    }
    if (-not $presetFile) {
        Stop-Staff "-Preset '$Preset' is not a preset size. The presets are: $((@($sizes | Sort-Object { @('S', 'M', 'L').IndexOf($_) }) -join ', '))." `
            "docs/hub/org.md, `"Org presets`", lists them."
    }
    $presetId = Get-P20OrgText (Get-P20OrgField $presetFile 'id')

    # The models: what was passed, else the defaults; each looked up in the model map.
    $models = Get-P20ModelMap -PackageRoot $repoRoot
    $resolve = {
        param([string]$Text, [string]$Switch)
        $want = ([string]$Text).Trim()
        if ($models.Contains($want)) { return $want }
        $id = Get-P20ModelForSize -Size $want -PackageRoot $repoRoot
        if ($id) { return $id }
        $families = @((ConvertFrom-StaffJson (Read-CardText -Path (Join-Path $repoRoot ([string](Get-P20Consts).models.file)))).current.PSObject.Properties.Name)
        Stop-Staff "$Switch '$want' is not a model id or a family in $([string](Get-P20Consts).models.file). Families: $($families -join ', ')." `
            'Give a family (opus) or a model id the map has a row for (claude-opus-5-5).'
    }
    $vpEngModel = & $resolve 'opus' 'the default'
    if ($PSBoundParameters.ContainsKey('VpEngineering')) { $vpEngModel = & $resolve $VpEngineering '-VpEngineering' }
    $vpProdModel = & $resolve 'fable' 'the default'
    if ($PSBoundParameters.ContainsKey('VpProduct')) { $vpProdModel = & $resolve $VpProduct '-VpProduct' }
    if ($PSBoundParameters.ContainsKey('Owner') -and -not ([string]$Owner).Trim()) { Stop-Staff '-Owner needs a name: the owner is a person, in your own words.' }
    if ($PSBoundParameters.ContainsKey('Title') -and -not ([string]$Title).Trim()) { Stop-Staff '-Title needs the words to call the tree.' }

    # The tree's id, and the room for it.
    if ($trees.Count -ge $maxTrees) {
        Stop-Staff "$fileName already holds $($trees.Count) trees ($($treeIds -join ', ')): a file holds at most $maxTrees, so nothing was written." `
            "Remove a tree by hand first, or choose one of these with '${p}Staff -Activate <tree-id>'."
    }
    $newId = $Tree
    if ($newId) {
        if ($treeIds -ccontains $newId) {
            Stop-Staff "'$newId' is already a tree in $fileName, and a tree is never overwritten. Trees: $($treeIds -join ', ')." `
                "Give another id with -Tree, or choose that tree with '${p}Staff -Activate $newId'."
        }
    }
    else {
        foreach ($try in @($presetId, "$presetId-2", "$presetId-3")) {
            if ($treeIds -cnotcontains $try) { $newId = $try; break }
        }
        if (-not $newId) {
            Stop-Staff "The ids $presetId, $presetId-2 and $presetId-3 are all trees in $fileName already." 'Give the new tree an id of its own with -Tree.'
        }
    }

    # The tree: the preset's own keys in its order, under the new id, with the
    # preset named. The preset file's own notes (its _ keys) describe the preset,
    # not the tree, so they stay in the package.
    $newTree = [pscustomobject][ordered]@{ id = $newId; preset = $presetId }
    foreach ($prop in $presetFile.PSObject.Properties) {
        if ($prop.Name.StartsWith('_') -or $prop.Name -ceq 'id' -or $prop.Name -ceq 'preset') { continue }
        $newTree | Add-Member -NotePropertyName $prop.Name -NotePropertyValue $prop.Value
    }
    if ($PSBoundParameters.ContainsKey('Title')) { Set-StaffField $newTree 'title' $Title.Trim() }
    foreach ($position in (Get-P20OrgItems (Get-P20OrgField $newTree 'positions'))) {
        $positionId = Get-P20OrgText (Get-P20OrgField $position 'id')
        $seats = (Get-P20OrgItems (Get-P20OrgField $position 'seats'))
        $isRoot = -not (Get-P20OrgText (Get-P20OrgField $position 'reportsTo'))
        if ($isRoot) {
            if ($PSBoundParameters.ContainsKey('Owner')) {
                foreach ($seat in $seats) { Set-StaffField $seat 'person' $Owner.Trim() }
            }
            continue
        }
        if ($seats.Count -eq 0) {
            if ($positionId -ceq 'builder') { Set-StaffField $position 'defaultModel' (& $resolve $poolDefault 'the default') }
            continue
        }
        $model = ''
        if ($positionId -ceq 'vp-engineering') { $model = $vpEngModel }
        elseif ($positionId -ceq 'vp-product') { $model = $vpProdModel }
        elseif ($seatDefaults.Contains($positionId)) { $model = & $resolve $seatDefaults[$positionId] 'the default' }
        if (-not $model) { continue }
        foreach ($seat in $seats) {
            Set-StaffField $seat 'model' $model
            if ($positionId -ceq $mergesPosition) { Set-StaffField $seat 'merges' $true }
        }
    }
}
else {
    if ($treeIds -cnotcontains $Tree) {
        Stop-Staff "-Activate names '$Tree', which is not a tree in $fileName. Trees: $($treeIds -join ', ')." `
            "${p}OrgChart -Tree <id> prints one; '${p}Staff -Preset S|M|L' adds one."
    }
}

# -- The document to write ----------------------------------------------------------------

$active = $activeBefore
$targetId = $Tree
if ($creating) { $targetId = $newId }
if ($Activate) { $active = $targetId }
$allTrees = @($trees)
if ($creating) { $allTrees = @($trees) + @($newTree) }
# A saved tree is a draft. A file with more than one tree must name the one in
# use, so adding a second to a file that named none (its lone tree was the one
# in use, by the reader's rule) names that tree -- never the draft.
if (-not $active -and $allTrees.Count -gt 1) { $active = $treeIds[0] }

if (-not $creating -and $active -ceq $activeBefore) {
    Write-Output "'$Tree' is already the tree in use in $orgPath; nothing was written."
    return
}

$doc = [ordered]@{}
if ($active -and -not (Get-P20OrgField $data 'activeTree')) { $doc['activeTree'] = $active }
if ($data) {
    foreach ($prop in $data.PSObject.Properties) {
        if ($prop.Name -ceq 'activeTree') { $doc['activeTree'] = $active; continue }
        if ($prop.Name -ceq 'trees') { $doc['trees'] = $allTrees; continue }
        $doc[$prop.Name] = $prop.Value
    }
}
if (-not $doc.Contains('trees')) { $doc['trees'] = $allTrees }
$text = (ConvertTo-P20ConfigJson $doc) + "`n"

# The result passes the reader's own checks, or nothing is written.
$after = Read-P20OrgText -Text $text -PromptsRoot $hubRoot -PackageRoot $repoRoot -TreeId $targetId -Path $orgPath
if ($after.Status -ne 'ok') {
    Stop-Staff "The $fileName Staff would write does not pass its checks, so nothing was written: $($after.Message)" `
        'docs/hub/org.md lists what is checked.'
}

$seatCount = 0
$staffed = 0
foreach ($position in $after.Chart.tree.positions) {
    foreach ($seat in @($position.seats)) {
        $seatCount++
        if ($seat.state -eq 'staffed') { $staffed++ }
    }
}
$what = "'$targetId' is now the tree in use."
if ($creating) {
    $saved = "Saved '$targetId' ($($after.Chart.tree.title), from the preset '$presetId': $seatCount seats, $staffed staffed)"
    if ($allTrees.Count -eq 1) { $what = "$saved; it is the only org, so it is the one in use." }
    else { $what = "$saved as a draft; '$($after.ActiveTree)' stays active. '${p}Staff -Activate $targetId' puts it in use." }
}

if ($WhatIf) {
    Write-Output "What if: Staff would write $orgPath. $what"
    Write-Output ''
    Write-Output $text.TrimEnd("`n")
    return
}

if ($exists) { Write-CardText -Path $orgPath -Content $text }
else { Write-CardText -Path $orgPath -Content $text -New }
Write-Output $what
Write-Output "Wrote $orgPath. ${p}OrgChart prints the tree in use; ${p}OrgChart -Tree $targetId prints this one."
