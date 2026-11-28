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

function Get-P20OrgPortraits {
    # consts.json org.portraits: the ids a seat may carry as its portrait
    # (docs/hub/org.md, "A seat's portrait"). No key is the default.
    return @(@((Get-P20Consts).org.portraits) | ForEach-Object { [string]$_ })
}

function Test-P20OrgPortrait {
    # Is this a portrait the tool draws? The value read as text (trimmed), then
    # matched exactly, case included. agent/solitaire/org.py's is_portrait is the
    # same rule, and Tests/fixtures/org/portraits.json holds the two to it.
    param($Value)
    $text = Get-P20OrgText $Value
    if (-not $text) { return $false }
    return (@(Get-P20OrgPortraits) -ccontains $text)
}

function Test-P20OrgTakesPortrait {
    # Does a seat of this position take a portrait? consts.json org.portraitSeats
    # is the one rule: 'root' names the root position's seat, any other entry a key
    # of org.roles, naming the seats of a position whose role (its prompt) is that
    # file. agent/solitaire/org.py's takes_portrait is the same rule, and
    # Tests/fixtures/org/portraits.json holds the two to it.
    param([bool]$IsRoot, [string]$Prompt)
    $org = (Get-P20Consts).org
    foreach ($entry in @($org.portraitSeats)) {
        if ([string]$entry -ceq 'root') { if ($IsRoot) { return $true } }
        elseif ($Prompt -and $org.roles.PSObject.Properties[[string]$entry] -and [string]$org.roles.([string]$entry) -ceq $Prompt) { return $true }
    }
    return $false
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

function Get-P20OrgTexts {
    # A JSON array field as its elements' text, each read as Get-P20OrgText reads
    # one, the empty ones left out; a field that is not an array holds none.
    param($Value)
    $list = New-Object System.Collections.Generic.List[string]
    foreach ($item in (Get-P20OrgItems $Value)) {
        $text = Get-P20OrgText $item
        if ($text) { $list.Add($text) }
    }
    return , @($list.ToArray())
}

function Get-P20OrgFlag {
    # A JSON boolean as itself; anything else (absent, a string, a number) is $null.
    param($Value)
    if ($Value -is [bool]) { return [bool]$Value }
    return $null
}

function Get-P20OrgWhole {
    # A JSON whole number as itself; anything else (a boolean, a fraction, text) is $null.
    # ConvertFrom-Json reads one as [int] on 5.1 and [long] on 7.
    param($Value)
    if ($Value -is [int] -or $Value -is [long]) { return [long]$Value }
    return $null
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
        [int]$SeatCount = 0,
        $Trees = @()
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
        Trees      = @($Trees)
    }
}

function Get-P20OrgWarnings {
    # An unknown key is tolerated, like hub.json's: ignored, and said once. A key
    # that starts with an underscore is a note and is never said. The retired keys
    # -- a tree's name (read as its title when there is no title), machines, a
    # seat's machine and active -- are known, so an older file reads without a
    # word, and none of the last three is in the response.
    param($Data, [string]$FileName)
    $known = @{
        top      = @('activeTree', 'trees')
        tree     = @('id', 'title', 'name', 'size', 'shortDescription', 'description', 'teamSize', 'preset', 'activatedAt', 'positions', 'machines')
        position = @('id', 'title', 'prompt', 'reportsTo', 'defaultModel', 'recommend', 'seats')
        seat     = @('id', 'roleTitle', 'model', 'person', 'session', 'merges', 'space', 'portrait', 'machine', 'active')
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
            $isRoot = -not (Get-P20OrgText (Get-P20OrgField $position 'reportsTo'))
            foreach ($seat in (Get-P20OrgItems (Get-P20OrgField $position 'seats'))) {
                $seatId = Get-P20OrgText (Get-P20OrgField $seat 'id')
                $where = " in seat '$seatId' of position '$positionId' in tree '$treeId'"
                & $check $seat 'seat' $where
                # A portrait is on a seat the rule names (org.portraitSeats), and one
                # of the ids; anything else is ignored, and said. An empty one is no portrait.
                $portrait = Get-P20OrgText (Get-P20OrgField $seat 'portrait')
                if (-not $portrait) { continue }
                if (-not (Test-P20OrgTakesPortrait -IsRoot $isRoot -Prompt (Get-P20OrgText (Get-P20OrgField $position 'prompt')))) { $found.Add("${FileName}: the portrait$where is on a seat that takes none -- ignored.") }
                elseif (-not (Test-P20OrgPortrait $portrait)) { $found.Add("${FileName}: the portrait '$portrait'$where is not one this tool draws -- ignored.") }
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
        # An older file's name is the title when there is no title.
        $title = Get-P20OrgText (Get-P20OrgField $tree 'title')
        if (-not $title) { $title = Get-P20OrgText (Get-P20OrgField $tree 'name') }
        if (-not $title) { $title = $treeId }
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
                $seats.Add([pscustomobject]@{
                        Id        = $seatId
                        RoleTitle = Get-P20OrgText (Get-P20OrgField $seat 'roleTitle')
                        Model     = Get-P20OrgText (Get-P20OrgField $seat 'model')
                        Person    = Get-P20OrgText (Get-P20OrgField $seat 'person')
                        Session   = Get-P20OrgText (Get-P20OrgField $seat 'session')
                        Merges    = Get-P20OrgFlag (Get-P20OrgField $seat 'merges')
                        Space     = Get-P20OrgText (Get-P20OrgField $seat 'space')
                        Portrait  = Get-P20OrgText (Get-P20OrgField $seat 'portrait')
                    })
            }
            $positionTitle = Get-P20OrgText (Get-P20OrgField $position 'title')
            if (-not $positionTitle) { $positionTitle = $positionId }
            $positions.Add([pscustomobject]@{
                    Id           = $positionId
                    Title        = $positionTitle
                    Prompt       = Get-P20OrgText (Get-P20OrgField $position 'prompt')
                    ReportsTo    = Get-P20OrgText (Get-P20OrgField $position 'reportsTo')
                    DefaultModel = Get-P20OrgText (Get-P20OrgField $position 'defaultModel')
                    Recommend    = Get-P20OrgTexts (Get-P20OrgField $position 'recommend')
                    Seats        = $seats.ToArray()
                })
        }
        $trees.Add([pscustomobject]@{
                Id               = $treeId
                Title            = $title
                Size             = Get-P20OrgText (Get-P20OrgField $tree 'size')
                ShortDescription = Get-P20OrgText (Get-P20OrgField $tree 'shortDescription')
                Description      = Get-P20OrgText (Get-P20OrgField $tree 'description')
                TeamSize         = Get-P20OrgWhole (Get-P20OrgField $tree 'teamSize')
                Preset           = Get-P20OrgText (Get-P20OrgField $tree 'preset')
                ActivatedAt      = Get-P20OrgText (Get-P20OrgField $tree 'activatedAt')
                Positions        = $positions.ToArray()
            })
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

function Get-P20OrgPromptDirs {
    <#
      Where a position's prompt is looked for, in order (docs/hub/org.md, "Where
      a position's prompt is found"): the hub's agentic/org/, the hub's agentic/
      as it has always been read, then the toolkit's own agentic/org/. The first
      folder that has the file wins, so a hub's own role under a shipped name is
      the one used. Returns @{ Dirs; Places } -- Places is how the unknown-prompt
      sentence names the three.
    #>
    param([string]$PromptsRoot, [string]$AgenticFolder, [string]$PackageRoot)
    $roles = [string](Get-P20Consts).org.rolesFolder
    $hubAgentic = Join-Path $PromptsRoot $AgenticFolder
    $dirs = @(
        (Join-Path $hubAgentic $roles),
        $hubAgentic,
        (Join-Path (Join-Path $PackageRoot 'agentic') $roles)
    )
    $places = "the hub's $AgenticFolder/$roles/ or $AgenticFolder/ folder or the toolkit's agentic/$roles/"
    return @{ Dirs = $dirs; Places = $places }
}

function Find-P20OrgPrompt {
    # The path of the first folder's copy of a prompt file NAME, or '' when none has it.
    param([string]$Name, [string[]]$PromptDirs = @())
    foreach ($dir in @($PromptDirs)) {
        if (-not $dir) { continue }
        $candidate = Join-Path $dir $Name
        if (Test-Path -LiteralPath $candidate -PathType Leaf) { return $candidate }
    }
    return ''
}

function Test-P20OrgTree {
    # One tree's rules, in a fixed order, the first broken one a failure: a
    # position or seat id used twice, a reportsTo that names nothing, a loop, not
    # exactly one root, a prompt that is in none of the folders a role is
    # looked up in. -PromptDirs is that list, in order (Get-P20OrgPromptDirs);
    # -PromptPlaces is how the sentence names them.
    param($Tree, [string[]]$PromptDirs = @(), [string]$PromptPlaces = '')
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
        if ($isName) { $there = [bool](Find-P20OrgPrompt -Name $name -PromptDirs $PromptDirs) }
        if (-not $there) {
            return @{ Kind = 'unknown-prompt'; Message = "Position '$($position.Id)' in tree '$treeId' names the prompt '$name', which is not a file in $PromptPlaces." }
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
            $one = [ordered]@{
                id        = $seat.Id
                roleTitle = $(if ($seat.RoleTitle) { $seat.RoleTitle } else { $null })
                model     = $(if ($seat.Model) { $seat.Model } else { $null })
                person    = $(if ($seat.Person) { $seat.Person } else { $null })
                session   = $(if ($seat.Session) { $seat.Session } else { $null })
                merges    = $seat.Merges
                space     = $(if ($seat.Space) { $seat.Space } else { $null })
                state     = $state
            }
            # The seat's portrait, where the rule names the seat and the id is one
            # the tool draws; else nothing, so a file without it reads as before.
            if ((Test-P20OrgTakesPortrait -IsRoot ($Level -eq 0) -Prompt $Position.Prompt) -and (Test-P20OrgPortrait $seat.Portrait)) { $one['portrait'] = $seat.Portrait }
            $seats.Add($one)
        }
        $ordered.Add([ordered]@{
                id           = $Position.Id
                title        = $Position.Title
                prompt       = $(if ($Position.Prompt) { $Position.Prompt } else { $null })
                reportsTo    = $(if ($Position.ReportsTo) { $Position.ReportsTo } else { $null })
                defaultModel = $(if ($Position.DefaultModel) { $Position.DefaultModel } else { $null })
                recommend    = @($Position.Recommend)
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
            id               = $Tree.Id
            title            = $Tree.Title
            size             = $(if ($Tree.Size) { $Tree.Size } else { $null })
            shortDescription = $(if ($Tree.ShortDescription) { $Tree.ShortDescription } else { $null })
            description      = $(if ($Tree.Description) { $Tree.Description } else { $null })
            teamSize         = $Tree.TeamSize
            preset           = $(if ($Tree.Preset) { $Tree.Preset } else { $null })
            positions        = $ordered.ToArray()
        }
    }
}

function Get-P20OrgTreeState {
    # An org's state (docs/hub/org.md, "An org's state"), derived and never stored:
    # active for the tree in use (the file's activeTree, or its one tree); else
    # inactive for a tree that has been in use -- it carries an activatedAt -- and
    # draft for one that never was. agent/solitaire/org.py's tree_state is the same
    # rule, and Tests/fixtures/org/state.json holds the two to it.
    param($Tree, [string]$ActiveTree)
    if ($Tree.Id -ceq $ActiveTree) { return 'active' }
    if ($Tree.ActivatedAt) { return 'inactive' }
    return 'draft'
}

function Read-P20OrgChart {
    <#
      The org chart in use, read from <PromptsRoot>/org.json.

      Returns @{ Status; Path; Kind; Message; Warnings; ActiveTree; Chart; SeatCount; Trees }.
      Trees is every tree of the file, in its order: @{ id; title; active; state;
      activatedAt } -- its state derived by Get-P20OrgTreeState.
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

    $text = $null
    try { $text = Get-Content -LiteralPath $path -Raw -ErrorAction Stop -Encoding UTF8 }
    catch {
        return (New-P20OrgResult -Status 'invalid' -Path $path -Kind 'unreadable' -Message "$fileName is not readable ($($_.Exception.Message)).")
    }
    return (Read-P20OrgText -Text ([string]$text) -PromptsRoot $PromptsRoot -PackageRoot $PackageRoot -TreeId $TreeId -Path $path)
}

function Read-P20OrgText {
    <#
      The same reading as Read-P20OrgChart, over a document's TEXT rather than the
      file: every check, in the same order, with the same result. The org file's
      one writer (Staff, Scripts/Set-Staff.ps1) checks what it is about to write
      through this, so a write can never land a file the reader refuses.
      -PromptsRoot is the hub the prompts are looked up in; -Path is only echoed.
    #>
    [CmdletBinding()]
    param(
        [AllowEmptyString()][string]$Text,
        [string]$PromptsRoot,
        [string]$PackageRoot = '',
        [string]$TreeId = '',
        [string]$Path = ''
    )
    $fileName = Get-P20OrgFileName
    $path = $Path
    $data = $null
    try {
        $data = $Text | ConvertFrom-Json -ErrorAction Stop
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

    if (-not $PackageRoot) { $PackageRoot = Split-Path $PSScriptRoot -Parent }
    $manifest = Read-P20HubManifest -Root $PromptsRoot -WarningAction SilentlyContinue
    $names = Get-P20HubFolderNames -PromptsRoot $PromptsRoot -PackageRoot $PackageRoot -Manifest $manifest
    $lookup = Get-P20OrgPromptDirs -PromptsRoot $PromptsRoot -AgenticFolder ([string]$names['agentic']) -PackageRoot $PackageRoot
    foreach ($tree in $trees) {
        $broken = Test-P20OrgTree -Tree $tree -PromptDirs $lookup.Dirs -PromptPlaces $lookup.Places
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
    $summaries = @($trees | ForEach-Object {
            [pscustomobject]@{
                id          = $_.Id
                title       = $_.Title
                active      = ($_.Id -ceq $active)
                state       = (Get-P20OrgTreeState -Tree $_ -ActiveTree $active)
                activatedAt = $(if ($_.ActivatedAt) { $_.ActivatedAt } else { $null })
            }
        })
    return (New-P20OrgResult -Status 'ok' -Path $path -Warnings $warnings -ActiveTree $active -Chart $chart -SeatCount $seatCount -Trees $summaries)
}

function Format-P20OrgChartLines {
    # The tree as text, one line per seat: "Position . model [space] (session)",
    # indented two spaces a level, and ". merges" after the seat that holds the
    # merge. A seat's roleTitle stands in for the position's title. A vacant seat
    # says vacant; an owner's seat shows its person; a position with no seats is
    # a pool, shown once with its default-model line. No machine is printed.
    # A seat's portrait, where the response carries one, follows: ". portrait: <id>".
    # It ends with an empty line and the count, "staffed: <n> of <seats>": every
    # seat of every position is a seat (the owner's too) and a pool has none; a
    # seat is staffed when its state is -- a model or a person named -- the same
    # state the Org tab draws a vacant desk from.
    param($Chart)
    $dot = [string][char]0x00B7
    $lines = New-Object System.Collections.Generic.List[string]
    $seatTotal = 0
    $staffedTotal = 0
    foreach ($position in $Chart.tree.positions) {
        $indent = ('  ' * [int]$position.level)
        $seats = @($position.seats)
        if ($seats.Count -eq 0) {
            if ($position.defaultModel) { $lines.Add("$indent$($position.title) $dot pool: $($position.defaultModel)") }
            else { $lines.Add("$indent$($position.title) $dot no seats") }
            continue
        }
        foreach ($seat in $seats) {
            $seatTotal++
            if ($seat.state -eq 'staffed') { $staffedTotal++ }
            $who = 'vacant'
            if ($seat.model) { $who = [string]$seat.model }
            elseif ($seat.person) { $who = [string]$seat.person }
            $label = $position.title
            if ($seat.roleTitle) { $label = $seat.roleTitle }
            $line = "$indent$label $dot $who"
            if ($seat.space) { $line += " [$($seat.space)]" }
            if ($seat.session) { $line += " ($($seat.session))" }
            if ($seat.merges -eq $true) { $line += " $dot merges" }
            $portrait = ''
            if ($seat -is [System.Collections.IDictionary]) { if ($seat.Contains('portrait')) { $portrait = [string]$seat['portrait'] } }
            elseif ($seat.PSObject.Properties['portrait']) { $portrait = [string]$seat.portrait }
            if ($portrait) { $line += " $dot portrait: $portrait" }
            $lines.Add($line)
        }
    }
    $lines.Add('')
    $lines.Add("staffed: $staffedTotal of $seatTotal")
    return , @($lines.ToArray())
}

function Resolve-P20OrgSeatAddress {
    <#
      The seat a Staff -Seat address names, in one tree's positions as the file
      holds them (docs/hub/org.md, "The one writer: Staff"). <position>.<seat>
      first: an id may hold a dot, so every dot is tried as the one between the
      two, and the first split that names a real seat is the seat. Only where no
      split does is the whole address read as a position's id, which stands for
      its seat where it has exactly one. So a two-part address means what it
      always meant. Ids are compared exactly, case included.

      Returns @{ Kind; Position; Seat; Seats }: Kind is `ok` (Position and Seat
      are the file's own objects, to edit in place), `several-seats` (Seats is
      the position's addresses, <position>.<seat> each), `pool` (the position has
      no seats) or `unknown`.
    #>
    param($Positions, [string]$Address)
    $result = { param($Kind, $Position, $Seat, $Seats) return [pscustomobject]@{ Kind = $Kind; Position = $Position; Seat = $Seat; Seats = @($Seats) } }
    $positions = Get-P20OrgItems $Positions
    $at = $Address.IndexOf('.')
    while ($at -ge 0) {
        $wantPosition = $Address.Substring(0, $at)
        $wantSeat = $Address.Substring($at + 1)
        foreach ($position in $positions) {
            if ((Get-P20OrgText (Get-P20OrgField $position 'id')) -cne $wantPosition) { continue }
            foreach ($candidate in (Get-P20OrgItems (Get-P20OrgField $position 'seats'))) {
                if ((Get-P20OrgText (Get-P20OrgField $candidate 'id')) -ceq $wantSeat) { return (& $result 'ok' $position $candidate @()) }
            }
        }
        $at = $Address.IndexOf('.', $at + 1)
    }
    foreach ($position in $positions) {
        $positionId = Get-P20OrgText (Get-P20OrgField $position 'id')
        if ($positionId -cne $Address) { continue }
        $seats = Get-P20OrgItems (Get-P20OrgField $position 'seats')
        if ($seats.Count -eq 1) { return (& $result 'ok' $position $seats[0] @()) }
        if ($seats.Count -eq 0) { return (& $result 'pool' $position $null @()) }
        $names = @($seats | ForEach-Object { "$positionId.$(Get-P20OrgText (Get-P20OrgField $_ 'id'))" })
        return (& $result 'several-seats' $position $null $names)
    }
    return (& $result 'unknown' $null $null @())
}
