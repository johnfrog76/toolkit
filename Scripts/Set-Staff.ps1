<#
.SYNOPSIS
    Staff -- the org file's one writer: start a tree from a preset, staff one seat, or choose the tree in use (the Team Agile add-on).

.DESCRIPTION
    Writes the hub's org file (consts.json org.file, at the hub root beside
    hub.json; docs/hub/org.md). Three forms:

      Staff -Preset S|M|L [-Tree <id>] [-Title <text>] [-Owner <name>]
            [-VpEngineering <model>] [-VpProduct <model>] [-WhatIf]
      Staff -Seat <position>.<seat> [-Tree <id>] [-Model <model>] [-Person <name>]
            [-Session <name>] [-Space <slug>] [-RoleName <file>] [-RoleTitle <text>]
            [-Merges] [-IfMatch <sha256>] [-WhatIf]
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

    -Seat edits one seat of a saved tree, active or not: the tree in use, or
    the one -Tree names. -Model (a family or an id, stored as the id), -Person,
    -Session, -Space (a Space the toolkit knows) and -Merges are the seat's own;
    -RoleName (the role file) and -RoleTitle belong to the POSITION, so they
    change every seat of it. The owner's seat (the root's) takes -Person only.
    An empty -Model, -Person, -Session, -Space or -RoleTitle takes that key
    away. -IfMatch is the SHA-256 of the file's bytes as the caller read them
    (the agent serves it as the chart's etag): a file that has changed since is
    refused, and nothing is written. One line says what changed; a call that
    changes nothing writes nothing.

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
    one keeps its own line ending. The bytes go to a temp file beside it and
    are renamed over it, so a write that fails leaves the file as it was. -WhatIf prints the file it would write and
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
.PARAMETER Seat
    The seat to edit, as <position>.<seat>: the position's id, a dot, the seat's id.
.PARAMETER Model
    The seat's model: a family (opus) or a model id; stored as the id. Empty takes it away.
.PARAMETER Person
    The person in the seat; on the owner's seat, the owner's name.
.PARAMETER Session
    The seat's session name, the address readies and messages go to.
.PARAMETER Space
    The Space the seat serves, a team lead's: a slug the toolkit knows.
.PARAMETER RoleName
    The position's role file (its prompt), for every seat of the position.
.PARAMETER RoleTitle
    The position's title, for every seat of the position.
.PARAMETER Merges
    Mark the seat as one that holds the merge.
.PARAMETER IfMatch
    The SHA-256 of org.json's bytes as they were read; a file that has changed since is refused.
.PARAMETER Activate
    Make the tree -Tree names the one in use. Not with -Preset: a saved tree is a draft.
.PARAMETER WhatIf
    Print the file it would write, and write nothing.

.EXAMPLE
    {cliPrefix}Staff -Preset S -Owner Sam
.EXAMPLE
    {cliPrefix}Staff -Preset M -Tree branch -VpProduct opus -WhatIf
.EXAMPLE
    {cliPrefix}Staff -Seat vp-engineering.vp-engineering -Model opus -Session mac-opus-vp
.EXAMPLE
    {cliPrefix}Staff -Seat owner.owner -Person Sam
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
    [string]$Seat,
    [Parameter(Mandatory = $false)]
    [string]$Model,
    [Parameter(Mandatory = $false)]
    [string]$Person,
    [Parameter(Mandatory = $false)]
    [string]$Session,
    [Parameter(Mandatory = $false)]
    [string]$Space,
    [Parameter(Mandatory = $false)]
    [string]$RoleName,
    [Parameter(Mandatory = $false)]
    [string]$RoleTitle,
    [Parameter(Mandatory = $false)]
    [switch]$Merges,
    [Parameter(Mandatory = $false)]
    [string]$IfMatch,
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
$usage = "${p}Staff -Preset S|M|L [-Tree <id>] [-Title <text>] [-Owner <name>] [-VpEngineering <model>] [-VpProduct <model>] [-WhatIf]  |  ${p}Staff -Seat <position>.<seat> [-Tree <id>] [-Model <model>] [-Person <name>] [-Session <name>] [-Space <slug>] [-RoleName <file>] [-RoleTitle <text>] [-Merges] [-IfMatch <sha256>] [-WhatIf]  |  ${p}Staff -Activate <tree-id> [-WhatIf]"

if ($Help) {
    Write-Host ""
    Write-Host "  ${p}Staff -- the org file's one writer" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  Usage:" -ForegroundColor Yellow
    Write-Host "    ${p}Staff -Preset S|M|L [-Tree <id>] [-Title <text>] [-Owner <name>] [-VpEngineering <model>] [-VpProduct <model>] [-WhatIf]"
    Write-Host "    ${p}Staff -Seat <position>.<seat> [-Tree <id>] [-Model <model>] [-Person <name>] [-Session <name>] [-Space <slug>] [-RoleName <file>] [-RoleTitle <text>] [-Merges] [-IfMatch <sha256>] [-WhatIf]"
    Write-Host "    ${p}Staff -Activate <tree-id> [-WhatIf]"
    Write-Host ""
    Write-Host "  -Preset saves a tree from a preset, with the default models, as a draft; -Seat staffs one seat; -Activate chooses the tree in use."
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

# The default models (docs/hub/org.md, "The one writer: Staff"), keyed by the
# ROLE a position names -- its prompt, the role file -- not by its id, so a
# preset may call its offices what it likes (lead-team-1, lead-team-2) and each
# still starts staffed: the role -> the family its seats start with. Every pool
# (a position with no seats: the builders) has its default-model line set to
# the pool's family instead. Every other seat starts vacant.
# The two VP defaults are the Org tab's step defaults too, so both read them
# from consts.json org.steps.
$steps = (Get-P20Consts).org.steps
$roleEngineering = 'vp-of-engineering.prompt.md'
$roleProduct = 'vp-of-product.prompt.md'
$seatDefaults = [ordered]@{
    $roleEngineering    = [string]$steps.vpEngineering
    $roleProduct        = [string]$steps.vpProduct
    'team-lead.prompt.md' = 'opus'
    'intern.prompt.md'  = 'haiku'
    'butler.prompt.md'  = 'haiku'
}
$poolDefault = 'sonnet'
$mergesRole = $roleProduct

function Stop-Staff([string]$Message, [string]$Hint = '') {
    if (-not $Hint) { $Hint = "Usage: $usage" }
    Write-CliError -Message $Message -Hint $Hint
    exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
}

# -- What was asked ------------------------------------------------------------------

$Tree = ([string]$Tree).Trim()
$Preset = ([string]$Preset).Trim()
$Seat = ([string]$Seat).Trim()
$creating = [bool]$Preset
$seating = $PSBoundParameters.ContainsKey('Seat')
$presetOnly = @('Title', 'Owner', 'VpEngineering', 'VpProduct')
$seatOnly = @('Model', 'Person', 'Session', 'Space', 'RoleName', 'RoleTitle', 'Merges', 'IfMatch')
if ($creating -and $Activate) {
    Stop-Staff '-Activate does not go with -Preset: a saved tree is a draft, and the tree in use stays as it was.' `
        "Save it first, then put it in use with '${p}Staff -Activate <tree-id>'."
}
if ($seating -and ($creating -or $Activate)) {
    $other = '-Preset'
    if ($Activate) { $other = '-Activate' }
    Stop-Staff "-Seat does not go with ${other}: it edits one seat of a tree that is already saved." `
        "Run them one at a time: '${p}Staff -Seat <position>.<seat> ...' edits a seat."
}
if (-not $creating -and -not $Activate -and -not $seating) {
    Stop-Staff 'Nothing to do: give -Preset S|M|L to add a tree, -Seat <position>.<seat> to staff a seat, or -Activate <tree-id> to choose the tree in use.'
}
if (-not $seating) {
    foreach ($name in $seatOnly) {
        if ($PSBoundParameters.ContainsKey($name)) { Stop-Staff "-$name goes with -Seat: it changes the seat -Seat names." }
    }
}
if (-not $creating) {
    foreach ($name in $presetOnly) {
        if ($PSBoundParameters.ContainsKey($name)) { Stop-Staff "-$name goes with -Preset: it fills the tree -Preset adds." }
    }
}
if ($Activate -and -not $Tree) { Stop-Staff '-Activate needs the id of the tree to put in use.' }
if ($seating) {
    if (-not $Seat) { Stop-Staff '-Seat needs the seat to edit, as <position>.<seat>.' }
    $asked = @($seatOnly | Where-Object { $_ -ne 'IfMatch' -and $PSBoundParameters.ContainsKey($_) })
    if ($asked.Count -eq 0) {
        Stop-Staff "Nothing to change in '$Seat': give -Model, -Person, -Session, -Space, -RoleName, -RoleTitle or -Merges."
    }
    if ($PSBoundParameters.ContainsKey('IfMatch') -and ([string]$IfMatch).Trim() -notmatch '^[0-9A-Fa-f]{64}$') {
        Stop-Staff "-IfMatch '$IfMatch' is not a SHA-256: 64 hex digits, the hash of $fileName's bytes as you read them." `
            'The Org page sends the etag GET /api/ritual/org served; typed by hand, leave it out.'
    }
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

function Get-StaffHash([byte[]]$Bytes) {
    # The SHA-256 of a file's bytes, lowercase hex: the etag the agent serves
    # (agent/solitaire/org.py), so the page's -IfMatch is compared byte for byte.
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try { $hash = $sha.ComputeHash($Bytes) } finally { $sha.Dispose() }
    return (-join ($hash | ForEach-Object { $_.ToString('x2') }))
}
function Get-StaffBytes {
    if (-not (Test-Path -LiteralPath $orgPath -PathType Leaf)) { return $null }
    return , [System.IO.File]::ReadAllBytes($orgPath)
}
$conflict = "$fileName changed since you read it; reload and try again."
$conflictHint = "Nothing was written. Read it again (${p}OrgChart, or reload the Org page), then make the change."

$exists = Test-Path -LiteralPath $orgPath -PathType Leaf
$data = $null
$trees = @()
$readHash = ''
if ($exists) { $readHash = Get-StaffHash (Get-StaffBytes) }
if ($seating -and $PSBoundParameters.ContainsKey('IfMatch') -and $readHash -ne ([string]$IfMatch).Trim().ToLowerInvariant()) {
    Stop-Staff $conflict $conflictHint
}
if ($exists) {
    $before = Read-P20OrgChart -PromptsRoot $hubRoot -PackageRoot $repoRoot
    if ($before.Status -ne 'ok') {
        Stop-Staff "$orgPath is not valid now, so nothing was written: $($before.Message)" `
            "Fix the file first; ${p}OrgChart says what is wrong, and docs/hub/org.md lists what is checked."
    }
    $data = ConvertFrom-StaffJson (Read-CardText -Path $orgPath)
    $trees = (Get-P20OrgItems (Get-P20OrgField $data 'trees'))
}
elseif ($seating) {
    Stop-Staff "There is no $fileName in the hub, so there is no seat to staff." `
        "Start one with '${p}Staff -Preset S|M|L'; docs/hub/org.md has the shape."
}
elseif (-not $creating) {
    Stop-Staff "There is no $fileName in the hub, so there is no tree to put in use." `
        "Start one with '${p}Staff -Preset S|M|L'; docs/hub/org.md has the shape."
}
$treeIds = @($trees | ForEach-Object { Get-P20OrgText (Get-P20OrgField $_ 'id') })
$activeBefore = ''
if ($data) { $activeBefore = Get-P20OrgText (Get-P20OrgField $data 'activeTree') }
# The tree in use as the reader sees it: the file's activeTree, or its one tree.
$inUseBefore = ''
if ($exists) { $inUseBefore = [string]$before.ActiveTree }

# A model, as a seat stores it: an id the model map has a row for passes
# through, a family resolves through its current block -- looked up, never
# parsed -- and anything else is refused, naming the families.
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
    # A given model is resolved on its own: a default is looked up only where none was given.
    if ($PSBoundParameters.ContainsKey('VpEngineering')) { $vpEngModel = & $resolve $VpEngineering '-VpEngineering' }
    else { $vpEngModel = & $resolve $seatDefaults[$roleEngineering] 'the default' }
    if ($PSBoundParameters.ContainsKey('VpProduct')) { $vpProdModel = & $resolve $VpProduct '-VpProduct' }
    else { $vpProdModel = & $resolve $seatDefaults[$roleProduct] 'the default' }
    if ($PSBoundParameters.ContainsKey('Owner') -and -not ([string]$Owner).Trim()) { Stop-Staff '-Owner needs a name: the owner is a person, in your own words.' }
    if ($PSBoundParameters.ContainsKey('Title') -and -not ([string]$Title).Trim()) { Stop-Staff '-Title needs the words to call the tree.' }

    # The tree's id, and the room for it.
    if ($trees.Count -ge $maxTrees) {
        Stop-Staff "$fileName already holds $($trees.Count) trees ($($treeIds -join ', ')): a file holds at most $maxTrees, so nothing was written." `
            "Remove a tree by hand first, or choose one of these with '${p}Staff -Activate <tree-id>'."
    }
    $newId = $Tree
    if ($newId) {
        # A plain word, so the 'Staff -Activate <id>' this prints always types as it reads.
        if ($newId -cnotmatch '^[A-Za-z0-9_-]+$') {
            Stop-Staff "-Tree '$newId' is not a plain word: a tree id is letters, digits, - and _." `
                'Give an id such as branch or our-org-2.'
        }
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
        $role = Get-P20OrgText (Get-P20OrgField $position 'prompt')
        $seats = (Get-P20OrgItems (Get-P20OrgField $position 'seats'))
        $isRoot = -not (Get-P20OrgText (Get-P20OrgField $position 'reportsTo'))
        if ($isRoot) {
            if ($PSBoundParameters.ContainsKey('Owner')) {
                foreach ($oneSeat in $seats) { Set-StaffField $oneSeat 'person' $Owner.Trim() }
            }
            continue
        }
        if ($seats.Count -eq 0) {
            Set-StaffField $position 'defaultModel' (& $resolve $poolDefault 'the default')
            continue
        }
        $presetModel = ''
        if ($role -ceq $roleEngineering) { $presetModel = $vpEngModel }
        elseif ($role -ceq $roleProduct) { $presetModel = $vpProdModel }
        elseif ($role -and $seatDefaults.Contains($role)) { $presetModel = & $resolve $seatDefaults[$role] 'the default' }
        if (-not $presetModel) { continue }
        foreach ($oneSeat in $seats) {
            Set-StaffField $oneSeat 'model' $presetModel
            if ($role -ceq $mergesRole) { Set-StaffField $oneSeat 'merges' $true }
        }
    }
}
elseif ($Activate) {
    if ($treeIds -cnotcontains $Tree) {
        Stop-Staff "-Activate names '$Tree', which is not a tree in $fileName. Trees: $($treeIds -join ', ')." `
            "${p}OrgChart -Tree <id> prints one; '${p}Staff -Preset S|M|L' adds one."
    }
}
else {
    # -- The seat -Seat edits -----------------------------------------------------------
    # One seat of a saved tree, active or not: the tree -Tree names, else the one
    # in use. The role name (the position's prompt) and the role title (its
    # title) are the POSITION's, so they change for every seat of it (docs/hub/org.md,
    # "The one writer: Staff"); everything else is the seat's own.
    $seatTreeId = $Tree
    if (-not $seatTreeId) { $seatTreeId = $inUseBefore }
    if ($treeIds -cnotcontains $seatTreeId) {
        Stop-Staff "-Tree names '$seatTreeId', which is not a tree in $fileName. Trees: $($treeIds -join ', ')." `
            "${p}OrgChart -Tree <id> prints one."
    }
    $seatTree = $trees | Where-Object { (Get-P20OrgText (Get-P20OrgField $_ 'id')) -ceq $seatTreeId } | Select-Object -First 1
    $seatPositions = Get-P20OrgItems (Get-P20OrgField $seatTree 'positions')
    # An id may hold a dot itself, so every dot is tried as the one between the
    # two, and the first split that names a real seat is the seat.
    $editPosition = $null
    $editSeat = $null
    $at = $Seat.IndexOf('.')
    while ($at -ge 0 -and -not $editSeat) {
        $wantPosition = $Seat.Substring(0, $at)
        $wantSeat = $Seat.Substring($at + 1)
        foreach ($position in $seatPositions) {
            if ((Get-P20OrgText (Get-P20OrgField $position 'id')) -cne $wantPosition) { continue }
            foreach ($candidate in (Get-P20OrgItems (Get-P20OrgField $position 'seats'))) {
                if ((Get-P20OrgText (Get-P20OrgField $candidate 'id')) -ceq $wantSeat) { $editPosition = $position; $editSeat = $candidate; break }
            }
            if ($editSeat) { break }
        }
        $at = $Seat.IndexOf('.', $at + 1)
    }
    if (-not $editSeat) {
        $names = New-Object System.Collections.Generic.List[string]
        foreach ($position in $seatPositions) {
            foreach ($candidate in (Get-P20OrgItems (Get-P20OrgField $position 'seats'))) {
                $names.Add("$(Get-P20OrgText (Get-P20OrgField $position 'id')).$(Get-P20OrgText (Get-P20OrgField $candidate 'id'))")
            }
        }
        $shape = ''
        if ($Seat.IndexOf('.') -lt 0) { $shape = ' A seat is named <position>.<seat>.' }
        Stop-Staff "'$Seat' is not a seat of the tree '$seatTreeId'.$shape Seats: $($names -join ', ')." `
            "${p}OrgChart -Tree $seatTreeId prints the tree; a position with no seats is a pool, and has none to staff."
    }

    # The owner's seat -- the root's -- is a person in the user's own words, never a model.
    $isRoot = -not (Get-P20OrgText (Get-P20OrgField $editPosition 'reportsTo'))
    if ($isRoot) {
        $notOwner = @($seatOnly | Where-Object { $_ -ne 'IfMatch' -and $_ -ne 'Person' -and $PSBoundParameters.ContainsKey($_) })
        if ($notOwner -contains 'Model') {
            Stop-Staff "The owner's seat takes -Person only: -Model does not go on it, because the owner is a person, never a model." `
                "Name the owner with '${p}Staff -Seat $Seat -Person <name>'."
        }
        if ($notOwner.Count -gt 0) {
            Stop-Staff "The owner's seat takes -Person only: $((@($notOwner | ForEach-Object { "-$_" })) -join ', ') does not go on it." `
                "Name the owner with '${p}Staff -Seat $Seat -Person <name>'."
        }
        if (-not ([string]$Person).Trim()) {
            Stop-Staff "-Person needs a name: the owner's seat always has a person, in your own words." `
                "Name the owner with '${p}Staff -Seat $Seat -Person <name>'."
        }
    }
    if ($PSBoundParameters.ContainsKey('Space') -and ([string]$Space).Trim()) {
        $slugs = @(@($cfg.Spaces) | ForEach-Object { [string]$_.slug } | Where-Object { $_ })
        if ($slugs -cnotcontains $Space.Trim()) {
            Stop-Staff "-Space '$($Space.Trim())' is not a Space the hub declares. Spaces: $($slugs -join ', ')." `
                "${p}Env lists the Spaces; give one of those."
        }
    }
    $seatModel = $null
    if ($PSBoundParameters.ContainsKey('Model') -and ([string]$Model).Trim()) { $seatModel = & $resolve $Model '-Model' }

    function Get-StaffSeatLine($Position, $SeatObj, [bool]$WithRole) {
        # The seat as OrgChart prints it -- its label, who sits there, [space],
        # (session), and merges -- and the role file where the role was asked about.
        $dot = [string][char]0x00B7
        $label = Get-P20OrgText (Get-P20OrgField $SeatObj 'roleTitle')
        if (-not $label) { $label = Get-P20OrgText (Get-P20OrgField $Position 'title') }
        if (-not $label) { $label = Get-P20OrgText (Get-P20OrgField $Position 'id') }
        $who = Get-P20OrgText (Get-P20OrgField $SeatObj 'model')
        if (-not $who) { $who = Get-P20OrgText (Get-P20OrgField $SeatObj 'person') }
        if (-not $who) { $who = 'vacant' }
        $line = "$label $dot $who"
        $where = Get-P20OrgText (Get-P20OrgField $SeatObj 'space')
        if ($where) { $line += " [$where]" }
        $named = Get-P20OrgText (Get-P20OrgField $SeatObj 'session')
        if ($named) { $line += " ($named)" }
        if ((Get-P20OrgFlag (Get-P20OrgField $SeatObj 'merges')) -eq $true) { $line += " $dot merges" }
        if ($WithRole) {
            $role = Get-P20OrgText (Get-P20OrgField $Position 'prompt')
            if (-not $role) { $role = 'no role' }
            $line += " {$role}"
        }
        return $line
    }
    function Set-StaffText($Object, [string]$Name, [string]$Value) {
        # A text key set to its trimmed value, or taken away when the value is empty.
        $v = ([string]$Value).Trim()
        if ($v) { Set-StaffField $Object $Name $v; return }
        foreach ($prop in @($Object.PSObject.Properties)) {
            if ($prop.Name -ceq $Name) { $Object.PSObject.Properties.Remove($prop.Name); return }
        }
    }

    $withRole = $PSBoundParameters.ContainsKey('RoleName')
    $seatBefore = Get-StaffSeatLine $editPosition $editSeat $withRole
    $positionBefore = ConvertTo-P20ConfigJson $editPosition
    if ($PSBoundParameters.ContainsKey('Model')) {
        if ($seatModel) { Set-StaffField $editSeat 'model' $seatModel } else { Set-StaffText $editSeat 'model' '' }
    }
    if ($PSBoundParameters.ContainsKey('Person')) { Set-StaffText $editSeat 'person' $Person }
    if ($PSBoundParameters.ContainsKey('Session')) { Set-StaffText $editSeat 'session' $Session }
    if ($PSBoundParameters.ContainsKey('Space')) { Set-StaffText $editSeat 'space' $Space }
    if ($Merges) { Set-StaffField $editSeat 'merges' $true }
    if ($PSBoundParameters.ContainsKey('RoleName')) { Set-StaffText $editPosition 'prompt' $RoleName }
    if ($PSBoundParameters.ContainsKey('RoleTitle')) { Set-StaffText $editPosition 'title' $RoleTitle }
    $seatAfter = Get-StaffSeatLine $editPosition $editSeat $withRole
    if ((ConvertTo-P20ConfigJson $editPosition) -ceq $positionBefore) {
        Write-Output "${Seat}: $seatBefore -- nothing changed, so nothing was written."
        return
    }
}

# -- The document to write ----------------------------------------------------------------

$active = $activeBefore
$targetId = $Tree
if ($creating) { $targetId = $newId }
if ($seating) { $targetId = $seatTreeId }
if ($Activate) { $active = $targetId }
$allTrees = @($trees)
if ($creating) { $allTrees = @($trees) + @($newTree) }
# A saved tree is a draft. A file with more than one tree must name the one in
# use, so adding a second to a file that named none (its lone tree was the one
# in use, by the reader's rule) names that tree -- never the draft.
if (-not $active -and $allTrees.Count -gt 1) { $active = $treeIds[0] }

if ($Activate -and $Tree -ceq $inUseBefore) {
    Write-Output "'$Tree' is already the tree in use in $orgPath; nothing was written."
    return
}

# activatedAt (docs/hub/org.md, "An org's state"): the day a tree BECOMES the org
# in use, the one stored fact that tells an inactive org from a draft. -Activate
# stamps the tree it puts in use; a new file's first tree is in use from the
# moment it is saved, so it is stamped then; and a tree added beside an older
# tree in use that has no stamp stamps that tree too, so it reads inactive, not
# draft, once another is put in use.
$today = (Get-Date).ToString('yyyy-MM-dd', [System.Globalization.CultureInfo]::InvariantCulture)
$treeById = @{}
foreach ($t in $allTrees) { $treeById[(Get-P20OrgText (Get-P20OrgField $t 'id'))] = $t }
# The same holds for the tree -Activate takes out of use: an older file's tree in
# use with no stamp is stamped as it leaves, so it reads inactive, never draft.
# A seat's edit is no change of the tree in use, so it stamps nothing.
if ($creating -and $allTrees.Count -eq 1) { Set-StaffField $newTree 'activatedAt' $today }
elseif (-not $seating -and $inUseBefore -and $treeById.ContainsKey($inUseBefore)) {
    $inUse = $treeById[$inUseBefore]
    if (-not (Get-P20OrgText (Get-P20OrgField $inUse 'activatedAt'))) { Set-StaffField $inUse 'activatedAt' $today }
}
if ($Activate) { Set-StaffField $treeById[$targetId] 'activatedAt' $today }

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
    # Not $seat: PowerShell names are case-blind, and $Seat is -Seat's.
    foreach ($oneSeat in @($position.seats)) {
        $seatCount++
        if ($oneSeat.state -eq 'staffed') { $staffed++ }
    }
}
$what = "'$targetId' is now the tree in use."
if ($creating) {
    $saved = "Saved '$targetId' ($($after.Chart.tree.title), from the preset '$presetId': $seatCount seats, $staffed staffed)"
    if ($allTrees.Count -eq 1) { $what = "$saved; it is the only org, so it is the one in use." }
    else { $what = "$saved as a draft; '$($after.ActiveTree)' stays active. '${p}Staff -Activate $targetId' puts it in use." }
}
if ($seating) { $what = "${Seat}: $seatBefore -> $seatAfter" }

if ($WhatIf) {
    Write-Output "What if: Staff would write $orgPath. $what"
    Write-Output ''
    Write-Output $text.TrimEnd("`n")
    return
}

# Crash-safe: the new bytes go to a sibling temp file, through Write-CardText,
# and are renamed over org.json, as Write-ConfigJson replaces a config file. An
# edit starts the temp as a copy of the file, so Write-CardText reads the file's
# own line ending there; a create is -New (LF). A write that fails removes the
# temp and leaves org.json as it was.
$temp = "$orgPath.p20tmp"
$raced = $false
try {
    if ($exists) {
        Copy-Item -LiteralPath $orgPath -Destination $temp -Force -ErrorAction Stop
        Write-CardText -Path $temp -Content $text
    }
    else { Write-CardText -Path $temp -Content $text -New }
    # -IfMatch holds to the last moment: a file changed while this ran is not overwritten.
    if ($seating -and $PSBoundParameters.ContainsKey('IfMatch') -and (Get-StaffHash (Get-StaffBytes)) -ne $readHash) {
        Remove-Item -LiteralPath $temp -Force -ErrorAction SilentlyContinue
        $raced = $true
    }
    else { Move-Item -LiteralPath $temp -Destination $orgPath -Force -ErrorAction Stop }
}
catch {
    Remove-Item -LiteralPath $temp -Force -ErrorAction SilentlyContinue
    $was = 'there is still no file'
    if ($exists) { $was = 'the file is as it was' }
    Stop-Staff "Could not write $orgPath ($($_.Exception.Message)); $was." `
        "Check that the hub's folder can be written, then run ${p}Staff again."
}
if ($raced) { Stop-Staff $conflict $conflictHint }
Write-Output $what
if ($seating) { Write-Output "Wrote $orgPath." }
else { Write-Output "Wrote $orgPath. ${p}OrgChart prints the tree in use; ${p}OrgChart -Tree $targetId prints this one." }
