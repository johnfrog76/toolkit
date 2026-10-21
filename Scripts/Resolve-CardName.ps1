<#
.SYNOPSIS
    The one card-filename rule: the type table, and how an id is read out of a
    card's name. Dot-source it.

.DESCRIPTION
    Not a command -- no alias, no menu row, no help entry of its own.

    Two verbs need the same answer to "which card is id 139?", and once
    only one of them had it. NewPrompt scanned card names with an
    anchored pattern built from workItemTypes to pick the next free local id;
    Archive matched `*$arg*` over every name in current/, so `Archive 39`
    resolved to `Task139-...` and moved -- and committed -- a card nobody
    named.

    So the rule lives here and both read it:

      - an optional type prefix from workItemTypes.filePrefix (US-, Task,
        Feat-, or whatever a team configured),
      - the id,
      - the dash that starts the slug.

    Anchored at the start of the name, and a dated file (<date>-PR141415)
    is not a card at all -- with no prefix it is a bare id followed by a dash,
    which is the one shape that survives the anchor.

    Dot-sourced rather than reached through utilities.psm1 because both callers
    have to work as a plain script with no module imported: that is how their
    test suites drive them.

        . (Join-Path $PSScriptRoot 'Resolve-CardName.ps1')

.NOTES
    PowerShell 5.1 compatible (ASCII dashes only).
#>

function Get-P20WorkItemTypes {
    <#
        Naming conventions per work-item type. These are HOUSE STYLE, not rules,
        so they come from config and another team can set their own without
        touching code. The values below are the fallback if config carries none
        -- they match the existing corpus (96 bare bugs, 38 Task, 25 US-, and
        story branches that use a third segment), so a card created today files
        alongside one from a year ago.
    #>
    param($Config)

    $types = @{
        'User Story' = @{ FilePrefix = 'US-';   Template = 'UserStory.template.md'; BranchSeparator = '/' }
        'Task'       = @{ FilePrefix = 'Task';  Template = 'Task.template.md';      BranchSeparator = '-' }
        'Feature'    = @{ FilePrefix = 'Feat-'; Template = 'Feature.template.md';   BranchSeparator = '-' }
        'Bug'        = @{ FilePrefix = '';      Template = 'Bug.template.md';       BranchSeparator = '-' }
        # Spike joined the shipped set later: work that ends in a finding.
        'Spike'      = @{ FilePrefix = 'Spike-'; Template = 'Spike.template.md';    BranchSeparator = '-' }
        # Meeting joined later: a meeting you attended, written after the fact.
        'Meeting'    = @{ FilePrefix = 'Meeting-'; Template = 'Meeting.template.md'; BranchSeparator = '-' }
    }

    if ($Config -and $Config.WorkItemTypes) {
        foreach ($prop in $Config.WorkItemTypes.PSObject.Properties) {
            if ($prop.Name -eq '_comment') { continue }
            $v = $prop.Value
            $types[$prop.Name] = @{
                FilePrefix      = [string]$v.filePrefix
                Template        = if ($v.template) { [string]$v.template } else { 'Bug.template.md' }
                BranchSeparator = if ($v.branchSeparator) { [string]$v.branchSeparator } else { '-' }
            }
        }
    }

    return $types
}

function Get-P20CardIdShape {
    <#
        The shape of an id, WITHOUT anchors, from consts.json (regex.cardId): a
        work item number, or the four-character id of a card with no work item.
        It is a cross-half literal -- the agent reads the same string -- so it is
        not typed here. The fallback is for a script run from a tree with no
        consts.json beside it (a test's scratch folder), and is digits only:
        the shape every card had before ids could be strings.
    #>
    if ($script:P20CardIdShape) { return $script:P20CardIdShape }
    $shape = '\d+'
    try {
        if (-not (Get-Command Get-P20Consts -ErrorAction SilentlyContinue)) {
            $constsScript = Join-Path $PSScriptRoot 'Get-Consts.ps1'
            if (Test-Path $constsScript) { . $constsScript }
        }
        if (Get-Command Get-P20Consts -ErrorAction SilentlyContinue) {
            $fromFile = (Get-P20Consts).regex.cardId
            if ($fromFile) { $shape = [string]$fromFile }
        }
    }
    catch { $shape = '\d+' }
    $script:P20CardIdShape = $shape
    return $shape
}

function Get-P20CardIdPattern {
    <#
        The card-id pattern, built from the SAME table the filename writer uses,
        so the scanner and the writer cannot disagree.

        The prefixes are a closed alternation on purpose. An open one -- any run
        of letters -- readmits exactly what this is here to reject, because
        "goal-2027-improve-things.prompt.md" would then read as prefix "goal-",
        id 2027.

        The PREFIX matches case-insensitively and the ID case-sensitively. An id
        with letters in it is uppercase (K7M2) and a slug is lowercase kebab, so
        "task-list-x" can never read as the id "TASK" or "LIST". Match this
        pattern WITHOUT RegexOptions.IgnoreCase -- Get-P20CardId does.
    #>
    param([hashtable]$WorkItemTypes)

    $alts = @()
    if ($WorkItemTypes) {
        foreach ($shape in $WorkItemTypes.Values) {
            if ($shape.FilePrefix) { $alts += [regex]::Escape([string]$shape.FilePrefix) }
        }
    }
    $alts = @($alts | Sort-Object -Unique)
    $id = Get-P20CardIdShape
    if ($alts.Count -eq 0) { return "^($id)-" }
    return '^(?i:' + ($alts -join '|') + ")?($id)-"
}

function Get-P20CardId {
    <#
        The id this filename carries, as a STRING, or $null if it carries none.
        "141" for a card with a work item, "K7M2" for one without.

        A dated file is skipped by name before the id is read: the PR-comment
        and review flows write "<date>-PR141415.prompt.md" into archive/,
        and with no type prefix that reads as a bare id followed by a dash.
        On the real hub it once read 2026 as the highest id and numbered the
        next offline card Task2027.

        It once returned [int]. A caller that does arithmetic on it
        must test Test-P20IsWorkItemId first: "99" -gt "100" is true for strings.
    #>
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string]$Pattern
    )

    if ($Name -match '^\d{4}-\d{2}-\d{2}-') { return $null }
    $m = [regex]::Match($Name, $Pattern)
    if (-not $m.Success) { return $null }
    $id = $m.Groups[1].Value
    # A number is normalised ("0141" and "141" are one work item); anything else
    # is returned as written.
    if ($id -match '^\d+$') {
        $n = 0L
        if ([long]::TryParse($id, [ref]$n)) { return [string]$n }
        return $null
    }
    return $id
}

function Test-P20IsWorkItemId {
    # All digits: the id of a card that has a work item behind it.
    param([AllowNull()][AllowEmptyString()][string]$Id)
    return [bool]($Id -and ($Id -match '^\d+$'))
}

function Test-P20IsCardId {
    <#
        Is this ARGUMENT an id, as opposed to a name or part of one? "141" is.
        "k7m2" is, in any case -- a person types it lowercase. "upload" is not.
        An argument that is an id is matched as an id and NEVER falls through to
        matching by partial name: that fallback once moved and committed
        Task139-... for `Archive 39`.
    #>
    param([AllowNull()][AllowEmptyString()][string]$Argument)
    if (-not $Argument) { return $false }
    return [bool]([regex]::IsMatch($Argument.Trim().ToUpperInvariant(), '^(?:' + (Get-P20CardIdShape) + ')$'))
}

function Resolve-P20CardArgument {
    <#
        The one way a verb turns what a person typed into a card.

          an id    -> the card(s) carrying exactly that id. Never fuzzy.
          a name   -> the file with exactly that name, else every file whose
                      name contains it (Fuzzy = $true; the caller decides
                      whether a fuzzy match may be acted on).

        Returns @{ Match = <FileInfo[]>; IsId = <bool>; Fuzzy = <bool> }. An id
        is compared ignoring case: macOS and Windows file systems do, and the
        person at the keyboard does.

        -Folder takes ONE folder or SEVERAL, searched together, in the order
        given. A verb names the folders it means on purpose: the ones that act
        on a card in play or planned pass current/ AND backlog/ (a card is in
        exactly one of them), so `Move K7M2 -To Active` finds a backlog card by
        the same rule `Move K7M2 -To InProgress` finds a current one. A match in
        more than one folder is returned as more than one match -- the caller's
        "matches N cards" refusal, never a guess.
    #>
    param(
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Argument,
        [Parameter(Mandatory = $true)][AllowEmptyString()][AllowEmptyCollection()][AllowNull()][string[]]$Folder,
        [hashtable]$WorkItemTypes
    )

    $result = @{ Match = @(); IsId = $false; Fuzzy = $false }
    $candidates = @()
    foreach ($one in @($Folder)) {
        if ($one -and (Test-Path -LiteralPath $one)) {
            $candidates += @(Get-ChildItem -LiteralPath $one -File -ErrorAction SilentlyContinue)
        }
    }
    if (Test-P20IsCardId $Argument) {
        $result.IsId = $true
        $wanted = $Argument.Trim()
        if (Test-P20IsWorkItemId $wanted) { $wanted = [string]([long]$wanted) }
        $pattern = Get-P20CardIdPattern -WorkItemTypes $WorkItemTypes
        $result.Match = @($candidates | Where-Object {
                $cardId = Get-P20CardId -Name $_.Name -Pattern $pattern
                ($null -ne $cardId) -and [string]::Equals($cardId, $wanted, [System.StringComparison]::OrdinalIgnoreCase)
            })
        return $result
    }
    $exact = @($candidates | Where-Object { $_.Name -eq $Argument })
    if ($exact.Count -gt 0) { $result.Match = $exact; return $result }
    if ($Argument) {
        $partial = @($candidates | Where-Object { $_.Name -like "*$Argument*" })
        if ($partial.Count -gt 0) { $result.Match = $partial; $result.Fuzzy = $true }
    }
    return $result
}

# The alphabet a generated id is drawn from. No 0 O 1 I L B 8 S 5 Z: every one of
# them has a twin when read aloud, written on a whiteboard, or typed from memory.
# Only this half ever GENERATES an id, so the alphabet lives here; the SHAPE it
# must satisfy is the contract, consts.json regex.cardId, and tkTestToolkit
# -Consts holds the two together (500 generated ids, every one must match).

function New-P20CardId {
    <#
        A fresh id for a card with no work item: four characters, at least one
        letter and at least one digit, unique in the folders given.

        Random, not a counter. "Highest plus one" is an integer -- it collides
        with a real work item number sooner or later -- and two machines that
        each make a card before a sync make the same one. Four characters from
        26 is ~450,000 ids; a hub holds a few hundred cards.

        RandomNumberGenerator with rejection sampling: PowerShell 5.1 has
        neither RandomNumberGenerator.GetInt32 nor Get-SecureRandom, and
        `byte % 26` favours the first 22 letters.

        Returns $null after -MaxTries collisions. The caller states the refusal.
    #>
    param(
        [string[]]$Folders = @(),
        [hashtable]$WorkItemTypes,
        [int]$MaxTries = 50,
        [scriptblock]$Generator   # a test seam: returns a candidate id
    )

    $taken = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
    $pattern = Get-P20CardIdPattern -WorkItemTypes $WorkItemTypes
    foreach ($folder in @($Folders | Where-Object { $_ } | Select-Object -Unique)) {
        if (-not (Test-Path -LiteralPath $folder)) { continue }
        foreach ($f in (Get-ChildItem -LiteralPath $folder -File -ErrorAction SilentlyContinue)) {
            $existing = Get-P20CardId -Name $f.Name -Pattern $pattern
            if ($existing) { [void]$taken.Add($existing) }
        }
    }

    # A literal, not $script:...: this file is dot-sourced, and a script-scope
    # read from inside a function resolves to whoever dot-sourced it.
    $alphabet = 'ACDEFGHJKMNPQRTUVWXY234679'
    $whole = '^(?:' + (Get-P20CardIdShape) + ')$'
    $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    try {
        for ($try = 0; $try -lt $MaxTries; $try++) {
            if ($Generator) { $candidate = [string](& $Generator) }
            else {
                $chars = New-Object char[] 4
                $one = New-Object byte[] 1
                $limit = 256 - (256 % $alphabet.Length)   # reject the biased tail
                for ($i = 0; $i -lt 4; $i++) {
                    do { $rng.GetBytes($one) } while ($one[0] -ge $limit)
                    $chars[$i] = $alphabet[$one[0] % $alphabet.Length]
                }
                $candidate = -join $chars
            }
            # The shape decides, not this function: all letters, or all digits,
            # is not an id and is simply drawn again.
            if ($candidate -cnotmatch $whole -or $candidate -match '^\d+$') { continue }
            if ($taken.Contains($candidate)) { continue }
            return $candidate
        }
    }
    finally { $rng.Dispose() }
    return $null
}
