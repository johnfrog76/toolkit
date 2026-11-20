#
# The org chart's reader -- <promptsRoot>/org.json (docs/hub/org.md).
#
# NOT a runnable verb: this file is DOT-SOURCED, by Scripts/Get-OrgChart.ps1
# (the OrgChart verb), by Scripts/Get-OptionalSurfaces.ps1 (the inventory row)
# and by Tests/Test-OrgChart.ps1. One reader, so the verb, the row and the
# suite cannot disagree about what a valid file is.
#
# It finds the file at the hub root the way hub.json is found (the root is the
# caller's: the module's resolved promptsRoot), reads it as UTF-8, validates it
# and returns the tree in use as the response the agent serves. It never
# throws and never writes: every way the file can be wrong is a result with a
# KIND (a code both halves agree on, Tests/fixtures/org/table.json) and a
# MESSAGE (one sentence).
#
# PowerShell 5.1 clean: no -AsHashtable, no ternary, no null-coalescing, ASCII
# only (the one non-ASCII character the text uses is built from its code).
#

if (-not (Get-Command Get-P20Consts -ErrorAction SilentlyContinue)) {
    . (Join-Path $PSScriptRoot 'Get-Consts.ps1')
}
if (-not (Get-Command Read-P20HubManifest -ErrorAction SilentlyContinue)) {
    . (Join-Path $PSScriptRoot 'Resolve-HubConfig.ps1')
}

function Get-P20OrgFileName {
    # consts.json org.file -- typed by all three halves, so read, never retyped.
    return [string](Get-P20Consts).org.file
}

function Get-P20OrgField {
    # One field of a JSON object, by its exact spelling (PowerShell's own lookup
    # ignores case, JSON and the agent's reader do not). $null when absent. The
    # leading comma keeps a one-element or empty array an array on return.
    param($Object, [string]$Name)
    if ($Object -isnot [System.Management.Automation.PSCustomObject]) { return $null }
    foreach ($prop in $Object.PSObject.Properties) {
        if ($prop.Name -ceq $Name) { return , $prop.Value }
    }
    return $null
}

function Get-P20OrgText {
    # A field read as text: a string or a number is its trimmed text, anything
    # else (absent, null, an object, an array, a boolean) is ''.
    param($Value)
    if ($null -eq $Value) { return '' }
    if ($Value -is [string]) { return $Value.Trim() }
    if ($Value -is [int] -or $Value -is [long] -or $Value -is [double] -or $Value -is [decimal]) {
        return ([string]::Format([System.Globalization.CultureInfo]::InvariantCulture, '{0}', $Value)).Trim()
    }
    return ''
}

function Get-P20OrgItems {
    # The elements of a JSON array field, as a plain array; a field that is not an
    # array holds none. (The comma keeps a single element an array on return.)
    param($Value)
    if ($Value -is [System.Array]) { return , @($Value) }
    return , @()
}

function New-P20OrgResult {
    param(
        [string]$Status,
        [string]$Path = '',
        [string]$Kind = '',
        [string]$Message = '',
        $Warnings = @(),
        [string]$ActiveTree = '',
        $Chart = $null,
        [int]$SeatCount = 0
    )
    return [pscustomobject]@{
        Status     = $Status
        Path       = $Path
        Kind       = $Kind
        Message    = $Message
        Warnings   = @($Warnings)
        ActiveTree = $ActiveTree
        Chart      = $Chart
        SeatCount  = $SeatCount
    }
}

function Get-P20OrgWarnings {
    # An unknown key is tolerated, like hub.json's: ignored, and said once. A key
    # that starts with an underscore is a note and is never said.
    param($Data, [string]$FileName)
    $known = @{
        top      = @('activeTree', 'trees')
        tree     = @('id', 'name', 'machines', 'positions')
        position = @('id', 'title', 'prompt', 'reportsTo', 'defaultModel', 'seats')
        seat     = @('id', 'model', 'person', 'machine', 'space', 'active')
    }
    $found = New-Object System.Collections.Generic.List[string]
    $check = {
        param($Object, [string]$Level, [string]$Where)
        if ($Object -isnot [System.Management.Automation.PSCustomObject]) { return }
        foreach ($prop in $Object.PSObject.Properties) {
            if ($prop.Name.StartsWith('_')) { continue }
            if ($known[$Level] -ccontains $prop.Name) { continue }
            $found.Add("${FileName}: '$($prop.Name)' is not a key this tool reads$Where -- ignored.")
        }
    }
    & $check $Data 'top' ''
    foreach ($tree in (Get-P20OrgItems (Get-P20OrgField $Data 'trees'))) {
        $treeId = Get-P20OrgText (Get-P20OrgField $tree 'id')
        & $check $tree 'tree' " in tree '$treeId'"
        foreach ($position in (Get-P20OrgItems (Get-P20OrgField $tree 'positions'))) {
            $positionId = Get-P20OrgText (Get-P20OrgField $position 'id')
            & $check $position 'position' " in position '$positionId' of tree '$treeId'"
            foreach ($seat in (Get-P20OrgItems (Get-P20OrgField $position 'seats'))) {
                $seatId = Get-P20OrgText (Get-P20OrgField $seat 'id')
                & $check $seat 'seat' " in seat '$seatId' of position '$positionId' in tree '$treeId'"
            }
        }
    }
    return , @($found.ToArray())
}

function ConvertTo-P20OrgModel {
    # The document as plain trees -> positions -> seats, or a failure: the first
    # entry with no id, in document order. Returns @{ Trees = ...; Failure = @{ Kind; Message } }.
    param($Data)
    $trees = New-Object System.Collections.Generic.List[object]
    $index = 0
    foreach ($tree in (Get-P20OrgItems (Get-P20OrgField $Data 'trees'))) {
        $index++
        $treeId = Get-P20OrgText (Get-P20OrgField $tree 'id')
        if (-not $treeId) { return @{ Trees = $null; Failure = @{ Kind = 'missing-id'; Message = "Tree $index has no id." } } }
        $machines = New-Object System.Collections.Generic.List[string]
        foreach ($m in (Get-P20OrgItems (Get-P20OrgField $tree 'machines'))) {
            $text = Get-P20OrgText $m
            if ($text) { $machines.Add($text) }
        }
        $name = Get-P20OrgText (Get-P20OrgField $tree 'name')
        if (-not $name) { $name = $treeId }
        $positions = New-Object System.Collections.Generic.List[object]
        $pIndex = 0
        foreach ($position in (Get-P20OrgItems (Get-P20OrgField $tree 'positions'))) {
            $pIndex++
            $positionId = Get-P20OrgText (Get-P20OrgField $position 'id')
            if (-not $positionId) { return @{ Trees = $null; Failure = @{ Kind = 'missing-id'; Message = "Position $pIndex of tree '$treeId' has no id." } } }
            $seats = New-Object System.Collections.Generic.List[object]
            $sIndex = 0
            foreach ($seat in (Get-P20OrgItems (Get-P20OrgField $position 'seats'))) {
                $sIndex++
                $seatId = Get-P20OrgText (Get-P20OrgField $seat 'id')
                if (-not $seatId) { return @{ Trees = $null; Failure = @{ Kind = 'missing-id'; Message = "Seat $sIndex of position '$positionId' in tree '$treeId' has no id." } } }
                $active = $null
                $rawActive = Get-P20OrgField $seat 'active'
                if ($rawActive -is [bool]) { $active = [bool]$rawActive }
                $seats.Add([pscustomobject]@{
                        Id      = $seatId
                        Model   = Get-P20OrgText (Get-P20OrgField $seat 'model')
                        Person  = Get-P20OrgText (Get-P20OrgField $seat 'person')
                        Machine = Get-P20OrgText (Get-P20OrgField $seat 'machine')
                        Space   = Get-P20OrgText (Get-P20OrgField $seat 'space')
                        Active  = $active
                    })
            }
            $title = Get-P20OrgText (Get-P20OrgField $position 'title')
            if (-not $title) { $title = $positionId }
            $positions.Add([pscustomobject]@{
                    Id           = $positionId
                    Title        = $title
                    Prompt       = Get-P20OrgText (Get-P20OrgField $position 'prompt')
                    ReportsTo    = Get-P20OrgText (Get-P20OrgField $position 'reportsTo')
                    DefaultModel = Get-P20OrgText (Get-P20OrgField $position 'defaultModel')
                    Seats        = $seats.ToArray()
                })
        }
        $trees.Add([pscustomobject]@{ Id = $treeId; Name = $name; Machines = $machines.ToArray(); Positions = $positions.ToArray() })
    }
    return @{ Trees = $trees.ToArray(); Failure = $null }
}

function Test-P20OrgDuplicates {
    # The first id that appears twice in a list of ids, else ''.
    param([string[]]$Ids)
    $seen = New-Object 'System.Collections.Generic.HashSet[string]'
    foreach ($id in @($Ids)) {
        if (-not $seen.Add($id)) { return $id }
    }
    return ''
}

function Test-P20OrgTree {
    # One tree's rules, in a fixed order, the first broken one a failure: a
    # position or seat id used twice, a reportsTo that names nothing, a loop, not
    # exactly one root, a prompt that is not a file in the agentic folder.
    param($Tree, [string]$AgenticDir)
    $treeId = $Tree.Id
    $dup = Test-P20OrgDuplicates -Ids @($Tree.Positions | ForEach-Object { $_.Id })
    if ($dup) { return @{ Kind = 'duplicate-position'; Message = "Two positions in tree '$treeId' share the id '$dup'." } }
    foreach ($position in $Tree.Positions) {
        $dup = Test-P20OrgDuplicates -Ids @($position.Seats | ForEach-Object { $_.Id })
        if ($dup) { return @{ Kind = 'duplicate-seat'; Message = "Two seats in position '$($position.Id)' of tree '$treeId' share the id '$dup'." } }
    }
    $byId = New-Object 'System.Collections.Generic.Dictionary[string,object]'
    foreach ($position in $Tree.Positions) { $byId[$position.Id] = $position }
    foreach ($position in $Tree.Positions) {
        if ($position.ReportsTo -and -not $byId.ContainsKey($position.ReportsTo)) {
            return @{ Kind = 'unknown-reports-to'; Message = "Position '$($position.Id)' in tree '$treeId' reports to '$($position.ReportsTo)', which is not a position in that tree." }
        }
    }
    # A loop: walk up from each position, in file order; the first chain that
    # meets itself names the loop from the position where it closes.
    foreach ($position in $Tree.Positions) {
        $path = New-Object System.Collections.Generic.List[string]
        $current = $position
        while ($null -ne $current) {
            $at = $path.IndexOf($current.Id)
            if ($at -ge 0) {
                $loop = @($path.GetRange($at, $path.Count - $at)) + @($current.Id)
                return @{ Kind = 'cycle'; Message = "Positions in tree '$treeId' report to each other in a loop: $($loop -join ' -> ')." }
            }
            $path.Add($current.Id)
            if ($current.ReportsTo) { $current = $byId[$current.ReportsTo] } else { $current = $null }
        }
    }
    $roots = @($Tree.Positions | Where-Object { -not $_.ReportsTo } | ForEach-Object { $_.Id })
    if ($roots.Count -eq 0) {
        return @{ Kind = 'no-root'; Message = "Tree '$treeId' has no root: exactly one position reports to nobody." }
    }
    if ($roots.Count -gt 1) {
        return @{ Kind = 'several-roots'; Message = "Tree '$treeId' has $($roots.Count) roots ($($roots -join ', ')): exactly one position reports to nobody." }
    }
    foreach ($position in $Tree.Positions) {
        if (-not $position.Prompt) { continue }
        $name = $position.Prompt
        $isName = ($name -notmatch '[\\/]') -and ($name -ne '.') -and ($name -ne '..')
        $there = $false
        if ($isName -and $AgenticDir) { $there = Test-Path -LiteralPath (Join-Path $AgenticDir $name) -PathType Leaf }
        if (-not $there) {
            $folderName = Split-Path -Leaf $AgenticDir
            return @{ Kind = 'unknown-prompt'; Message = "Position '$($position.Id)' in tree '$treeId' names the prompt '$name', which is not a file in the hub's $folderName/ folder." }
        }
    }
    return $null
}

function ConvertTo-P20OrgChart {
    # One validated tree as the response (docs/hub/org.md, "The response"): its
    # positions in tree order -- the root, then each position's reports in file
    # order, depth first -- each with its level and its seats' derived state.
    param($Tree, [string]$ActiveTree)
    $children = @{}
    $root = $null
    foreach ($position in $Tree.Positions) {
        if (-not $position.ReportsTo) { $root = $position; continue }
        if (-not $children.ContainsKey($position.ReportsTo)) { $children[$position.ReportsTo] = New-Object System.Collections.Generic.List[object] }
        $children[$position.ReportsTo].Add($position)
    }
    $ordered = New-Object System.Collections.Generic.List[object]
    $walk = $null
    $walk = {
        param($Position, [int]$Level)
        $seats = New-Object System.Collections.Generic.List[object]
        foreach ($seat in $Position.Seats) {
            $state = 'vacant'
            if ($seat.Model -or $seat.Person) { $state = 'staffed' }
            $seats.Add([ordered]@{
                    id      = $seat.Id
                    model   = $(if ($seat.Model) { $seat.Model } else { $null })
                    person  = $(if ($seat.Person) { $seat.Person } else { $null })
                    machine = $(if ($seat.Machine) { $seat.Machine } else { $null })
                    space   = $(if ($seat.Space) { $seat.Space } else { $null })
                    active  = $seat.Active
                    state   = $state
                })
        }
        $ordered.Add([ordered]@{
                id           = $Position.Id
                title        = $Position.Title
                prompt       = $(if ($Position.Prompt) { $Position.Prompt } else { $null })
                reportsTo    = $(if ($Position.ReportsTo) { $Position.ReportsTo } else { $null })
                defaultModel = $(if ($Position.DefaultModel) { $Position.DefaultModel } else { $null })
                level        = $Level
                seats        = $seats.ToArray()
            })
        if ($children.ContainsKey($Position.Id)) {
            foreach ($child in $children[$Position.Id]) { & $walk $child ($Level + 1) }
        }
    }
    & $walk $root 0
    return [ordered]@{
        activeTree = $ActiveTree
        tree       = [ordered]@{
            id        = $Tree.Id
            name      = $Tree.Name
            machines  = @($Tree.Machines)
            positions = $ordered.ToArray()
        }
    }
}

function Read-P20OrgChart {
    <#
      The org chart in use, read from <PromptsRoot>/org.json.

      Returns @{ Status; Path; Kind; Message; Warnings; ActiveTree; Chart; SeatCount }.
      Status is `ok` (Chart is the response), `missing` (no file at the hub root:
      Kind `missing`) or `invalid` (Kind and Message say what is wrong, in one
      sentence). -TreeId asks for another tree of the same file; a name that is
      not a tree is `invalid` with Kind `unknown-tree`. Never throws, writes nothing.
    #>
    [CmdletBinding()]
    param(
        [string]$PromptsRoot,
        [string]$PackageRoot = '',
        [string]$TreeId = ''
    )
    $fileName = Get-P20OrgFileName
    $path = ''
    if ($PromptsRoot) { $path = Join-Path $PromptsRoot $fileName }
    if (-not $PromptsRoot -or -not (Test-P20HubRoot $PromptsRoot) -or -not (Test-Path -LiteralPath $path -PathType Leaf)) {
        return (New-P20OrgResult -Status 'missing' -Path $path -Kind 'missing' -Message "There is no $fileName in the hub.")
    }

    $data = $null
    try {
        $data = Get-Content -LiteralPath $path -Raw -ErrorAction Stop -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        return (New-P20OrgResult -Status 'invalid' -Path $path -Kind 'unreadable' -Message "$fileName is not valid JSON ($($_.Exception.Message)).")
    }
    if ($data -isnot [System.Management.Automation.PSCustomObject]) {
        return (New-P20OrgResult -Status 'invalid' -Path $path -Kind 'unreadable' -Message "$fileName must be a JSON object at the top level.")
    }

    $warnings = Get-P20OrgWarnings -Data $data -FileName $fileName
    $fail = {
        param([string]$Kind, [string]$Message)
        return (New-P20OrgResult -Status 'invalid' -Path $path -Kind $Kind -Message $Message -Warnings $warnings)
    }

    $rawTrees = Get-P20OrgField $data 'trees'
    if (-not ($rawTrees -is [System.Array]) -or @($rawTrees).Count -eq 0) {
        return (& $fail 'no-trees' "$fileName has no trees: 'trees' must be an array with at least one tree.")
    }
    $model = ConvertTo-P20OrgModel -Data $data
    if ($model.Failure) { return (& $fail $model.Failure.Kind $model.Failure.Message) }
    $trees = @($model.Trees)

    $dup = Test-P20OrgDuplicates -Ids @($trees | ForEach-Object { $_.Id })
    if ($dup) { return (& $fail 'duplicate-tree' "Two trees share the id '$dup'.") }

    $treeIds = @($trees | ForEach-Object { $_.Id })
    $active = Get-P20OrgText (Get-P20OrgField $data 'activeTree')
    if (-not $active) {
        if ($trees.Count -eq 1) { $active = $trees[0].Id }
        else { return (& $fail 'no-active-tree' "'activeTree' is not set and $fileName has $($trees.Count) trees ($($treeIds -join ', ')): name the one in use.") }
    }
    if ($treeIds -cnotcontains $active) {
        return (& $fail 'unknown-active-tree' "'activeTree' names '$active', which is not a tree. Trees: $($treeIds -join ', ').")
    }

    $agenticDir = ''
    $manifest = Read-P20HubManifest -Root $PromptsRoot -WarningAction SilentlyContinue
    $names = Get-P20HubFolderNames -PromptsRoot $PromptsRoot -PackageRoot $PackageRoot -Manifest $manifest
    $agenticDir = Join-Path $PromptsRoot ([string]$names['agentic'])
    foreach ($tree in $trees) {
        $broken = Test-P20OrgTree -Tree $tree -AgenticDir $agenticDir
        if ($broken) { return (& $fail $broken.Kind $broken.Message) }
    }

    $chosen = $active
    if ($TreeId) {
        if ($treeIds -cnotcontains $TreeId) {
            return (& $fail 'unknown-tree' "-Tree names '$TreeId', which is not a tree in $fileName. Trees: $($treeIds -join ', ').")
        }
        $chosen = $TreeId
    }
    $picked = $trees | Where-Object { $_.Id -ceq $chosen } | Select-Object -First 1
    $chart = ConvertTo-P20OrgChart -Tree $picked -ActiveTree $active
    $seatCount = 0
    foreach ($position in $chart.tree.positions) { $seatCount += @($position.seats).Count }
    return (New-P20OrgResult -Status 'ok' -Path $path -Warnings $warnings -ActiveTree $active -Chart $chart -SeatCount $seatCount)
}

function Format-P20OrgChartLines {
    # The tree as text, one line per seat: "Position . model [space] (machine)",
    # indented two spaces a level. A vacant seat says vacant; an owner's seat
    # shows its person; a position with no seats is a pool, shown once with its
    # default-model line.
    param($Chart)
    $dot = [string][char]0x00B7
    $lines = New-Object System.Collections.Generic.List[string]
    foreach ($position in $Chart.tree.positions) {
        $indent = ('  ' * [int]$position.level)
        $seats = @($position.seats)
        if ($seats.Count -eq 0) {
            if ($position.defaultModel) { $lines.Add("$indent$($position.title) $dot pool: $($position.defaultModel)") }
            else { $lines.Add("$indent$($position.title) $dot no seats") }
            continue
        }
        foreach ($seat in $seats) {
            $who = 'vacant'
            if ($seat.model) { $who = [string]$seat.model }
            elseif ($seat.person) { $who = [string]$seat.person }
            $line = "$indent$($position.title) $dot $who"
            if ($seat.space) { $line += " [$($seat.space)]" }
            if ($seat.machine) { $line += " ($($seat.machine))" }
            $lines.Add($line)
        }
    }
    return , @($lines.ToArray())
}
