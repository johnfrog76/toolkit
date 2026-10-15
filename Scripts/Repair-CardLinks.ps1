<#
.SYNOPSIS
    The two links a card carries back into the Toolkit package -- written, and
    rewritten from where things are NOW. Dot-source it.

.DESCRIPTION
    Not a command -- no alias, no menu row, no help entry of its own.

    A card's `> Template:` link and the `ado-comments workflow` link
    GetPRComments appends point at files that ship with the package, from a
    card that lives in the hub. The hop between them was computed once, at
    write time, and then frozen. Move the hub, move the package, or pull the
    hub onto a machine whose clone sits somewhere else and every card written
    before the move has one `../` too many -- a link that looks right and
    resolves nowhere, fixed only by counting `../` by hand. It happened to all
    six cards in the demo hub's `demo/current`.

    So the layout is no longer a fact a card stores. It is recomputed:

      - `New-P20TemplateLine` and `New-P20WorkflowLine` BUILD the two lines, and
        they are the only things that build them -- the writers call them, so a
        card and a refreshed card come out byte-identical.
      - `Repair-P20CardLinks` REWRITES both lines in a file that already exists,
        from that file's current folder. `Archive` calls it on the card it just
        moved and `Sync` calls it over the org's folders after a pull, which is
        what makes a hub fix itself on the machine that pulled it.

    `Resolve-P20PackageLink` stays the single thing that knows how to express the
    hop; this file is the single thing that knows which links a card has.

    Idempotent, and byte-preserving when there is nothing to do: an unchanged
    card is not written at all, so a refresh pass over a hub produces no diff
    and no line-ending churn.

    Across drives there is no relative path. Resolve-P20PackageLink then returns
    its -Fallback instead of the absolute path Resolve-Path -Relative would hand
    back, so both lines are written with the file's NAME and no link -- a card
    never keeps a drive letter or a share name. A card that already carries an
    absolute link is rewritten the same way by Repair-P20CardLinks, which rebuilds
    both lines whatever they held.

    No GUESSED fallback. When the package cannot be found from here, the line
    is written with the file's NAME and no link. `../../templates/` was the
    legacy layout, where templates sat beside {org}/current in one repo; in
    toolkit the package and the hub are separate trees, so that path is wrong
    for every hub and a wrong link is worse than none.

    Dot-sourced rather than reached through utilities.psm1 because every caller
    has to work as a plain script with no module imported: that is how their
    test suites drive them.

        . (Join-Path $PSScriptRoot 'Repair-CardLinks.ps1')

.NOTES
    PowerShell 5.1 compatible (ASCII dashes only).
#>

. (Join-Path $PSScriptRoot 'Write-CardText.ps1')
# The id rule (which archived files are THIS card's earlier rounds) and the
# cross-half token for the third link below. Both are read from where they live.
. (Join-Path $PSScriptRoot 'Resolve-CardName.ps1')
. (Join-Path $PSScriptRoot 'Get-Consts.ps1')

# Resolve-P20PackageLink normally comes from the module. These scripts are also
# invoked directly -- by tests, by a user running the .ps1, by anything that
# wants to write a card without importing first -- so a missing helper must not
# be fatal. It used to be a copy-paste in TWO scripts; this is
# the one copy, next to the only callers that need it.
if (-not (Get-Command Resolve-P20PackageLink -ErrorAction SilentlyContinue)) {
    function Resolve-P20PackageLink {
        param([string]$TargetPath, [string]$FromDirectory, [string]$Fallback = '')
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
}

# The two lines, in one place. A literal retyped at the write site and again at
# the repair site is a drift bug waiting for its second copy to be edited alone
# (AGENTS.md, "One place for magic strings").
$script:P20TemplateLinePrefix   = '> Template: '
$script:P20WorkflowLinePrefix   = 'Triage these with the '
$script:P20WorkflowLinkText     = 'ado-comments workflow'
$script:P20WorkflowFileName     = 'ado-comments.prompt.md'
$script:P20TemplatesFolder      = 'templates'
$script:P20AgenticFolder        = 'agentic'
# The third link, and the only one that points INSIDE the hub: a card that came
# back after archive names its latest earlier round. The label is a cross-half
# token (consts.json tokens.previousRound -- the agent reads it too); the
# archive folder's name is consts.json folders.archive.
$script:P20PreviousRoundPrefix  = (Get-P20Consts).tokens.previousRound + ' '
$script:P20PreviousRoundPattern = '(?m)^' + [regex]::Escape((Get-P20Consts).tokens.previousRound) + ' [^\r\n]*(?=\r?$)'

# Whole-line patterns: the line IS the unit, so a refresh replaces it outright
# rather than patching a target inside it.
# [^\r\n]* and (?=\r?$), never .*$: in .NET multiline mode $ matches before \n
# only, never before \r. So on a CRLF card .* swallowed the \r into the match,
# the replacement had none, and an up-to-date card came back with that one line
# ending in bare LF -- and the name pattern, which excluded \r and then asked
# for $, matched nothing at all, so the link it exists to repair was never
# repaired on Windows.
# The lookahead keeps the \r OUT of the match and still anchors at the line end.
$script:P20TemplateLinePattern  = '(?m)^> Template: [^\r\n]*(?=\r?$)'
$script:P20WorkflowLinePattern  = '(?m)^Triage these with the [^\r\n]*(?=\r?$)'
# ...and the one capture a refresh needs out of the old line: which template.
$script:P20TemplateNamePattern  = '(?m)^> Template: (?:\[([^\]]+)\]\([^)]*\)|([^\r\n\[]+?))[ \t]*\r?$'

function Get-P20PackageRoot {
    # Where this package sits NOW. Scripts/ is one level down from the root.
    return (Split-Path $PSScriptRoot -Parent)
}

function New-P20TemplateLine {
    <#
        The `> Template:` line for a card in $CardDirectory. Linked when the
        template is findable from here, and the bare name when it is not.
    #>
    param(
        [Parameter(Mandatory = $true)][string]$TemplateName,
        [string]$CardDirectory
    )
    $target = Join-Path (Join-Path (Get-P20PackageRoot) $script:P20TemplatesFolder) $TemplateName
    $rel = Resolve-P20PackageLink -TargetPath $target -FromDirectory $CardDirectory
    if ($rel) { return "$($script:P20TemplateLinePrefix)[$TemplateName]($rel)" }
    return "$($script:P20TemplateLinePrefix)$TemplateName"
}

function New-P20WorkflowLine {
    <#
        The line GetPRComments appends so the agent loads the triage workflow as
        context when the prompt runs. The file name stays in the text either
        way, because the caller's "already there?" guard reads it.
    #>
    param([string]$CardDirectory)

    $target = Join-Path (Join-Path (Get-P20PackageRoot) $script:P20AgenticFolder) $script:P20WorkflowFileName
    $rel = Resolve-P20PackageLink -TargetPath $target -FromDirectory $CardDirectory
    if ($rel) {
        return "$($script:P20WorkflowLinePrefix)[$($script:P20WorkflowLinkText)]($rel)"
    }
    return "$($script:P20WorkflowLinePrefix)$($script:P20WorkflowLinkText) -- $($script:P20AgenticFolder)/$($script:P20WorkflowFileName) in the Toolkit package"
}

function Get-P20ArchiveFolderFor {
    <#
        The archive/ that belongs with the folder a card is in: the folder itself
        when the card is already in an archive, else its sibling. The same hop
        Get-NextLocalId makes.
    #>
    param([Parameter(Mandatory = $true)][string]$CardDirectory)
    $archiveName = (Get-P20Consts).folders.archive
    if ((Split-Path $CardDirectory -Leaf) -eq $archiveName) { return $CardDirectory }
    $parent = Split-Path $CardDirectory -Parent
    if (-not $parent) { return $null }
    return (Join-Path $parent $archiveName)
}

function Get-P20PriorRounds {
    <#
        The archived files that are earlier rounds of card $CardId, oldest first.
        The SAME match Archive's round-aware pass uses: the card's id, read out of
        the name with the -rN suffix taken off (Get-P20CardId), never a pattern of
        its own. A file with no -rN is round 1 and sorts first; -ExcludeName keeps
        a card out of its own history.
    #>
    param(
        [string]$ArchiveDirectory,
        [string]$CardId,
        [hashtable]$WorkItemTypes,
        [string]$ExcludeName = ''
    )
    if (-not $CardId -or -not $ArchiveDirectory -or -not (Test-Path -LiteralPath $ArchiveDirectory -PathType Container)) { return @() }
    $pattern = Get-P20CardIdPattern -WorkItemTypes $WorkItemTypes
    $found = @(Get-ChildItem -LiteralPath $ArchiveDirectory -Filter '*.prompt.md' -File -ErrorAction SilentlyContinue | Where-Object {
        $_.Name -ne $ExcludeName -and
        (Get-P20CardId -Name ($_.Name -replace '-r\d+(?=\.prompt\.md$)', '') -Pattern $pattern) -eq $CardId
    })
    $keyed = foreach ($f in $found) {
        $n = 0
        if ($f.Name -match '-r(\d+)\.prompt\.md$') { $n = [int]$Matches[1] }
        [pscustomobject]@{ Round = $n; Name = $f.Name; File = $f }
    }
    return @($keyed | Sort-Object Round, Name | ForEach-Object { $_.File })
}

function New-P20PreviousRoundLine {
    <#
        The `> Previous round:` line for a card in $CardDirectory, naming
        $PreviousPath. Built the way the other two are, and the only thing that
        builds it. The path is relative to the card's own folder, so it is
        ../archive/<file> from current/.
    #>
    param(
        [Parameter(Mandatory = $true)][string]$PreviousPath,
        [Parameter(Mandatory = $true)][string]$CardDirectory
    )
    $rel = Resolve-P20PackageLink -TargetPath $PreviousPath -FromDirectory $CardDirectory
    if (-not $rel) { $rel = (Get-P20Consts).folders.archive + '/' + (Split-Path $PreviousPath -Leaf) }
    return "$($script:P20PreviousRoundPrefix)$rel"
}

function Get-P20PreviousRoundPath {
    <#
        What a card's `> Previous round:` line says, or $null. The CLI's reader of
        the token; agent/core/parsers.py is the other, and one fixture
        (Tests/fixtures/parsers/previous-round.md) holds the two to each other.
    #>
    param([AllowNull()][string]$Content)
    if (-not $Content) { return $null }
    $m = [regex]::Match($Content, '(?m)^' + [regex]::Escape((Get-P20Consts).tokens.previousRound) + '[ \t]*([^\r\n]*?)[ \t]*\r?$')
    if (-not $m.Success) { return $null }
    $v = $m.Groups[1].Value
    if ($v) { return $v }
    return $null
}

function Repair-P20CardLinks {
    <#
        Rewrite a card's package links from where the card and the package are
        now. Returns $true when the file changed.

        Never throws: a card that cannot be read is reported and left alone.
        The contract of every verb that calls this is about something else --
        moving a card, syncing a hub -- and a link is not worth failing either.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Inner helper; the caller owns the ShouldProcess decision.')]
    param([Parameter(Mandatory = $true)][string]$Path)

    try {
        if (-not (Test-Path $Path)) { return $false }
        # -Encoding UTF8 on the way in as well as the way out: without it,
        # Windows PowerShell 5.1 reads a BOM-less file in the ANSI code page and
        # a card with an emoji or a curly quote comes back mangled -- and this
        # function writes back everything it read.
        $content = Get-Content -Path $Path -Raw -Encoding UTF8 -ErrorAction Stop
        if ($null -eq $content) { return $false }
        $cardDir = Split-Path $Path -Parent
        $updated = $content

        $nameMatch = [regex]::Match($updated, $script:P20TemplateNamePattern)
        if ($nameMatch.Success) {
            $tpl = $nameMatch.Groups[1].Value
            if (-not $tpl) { $tpl = $nameMatch.Groups[2].Value }
            # A line that held a bare absolute path instead of a name: keep the name.
            $tpl = (($tpl.Trim()) -split '[\\/]')[-1]
            if ($tpl) {
                $line = New-P20TemplateLine -TemplateName $tpl -CardDirectory $cardDir
                $updated = [regex]::Replace($updated, $script:P20TemplateLinePattern,
                    [System.Text.RegularExpressions.MatchEvaluator] { $line })
            }
        }

        if ($updated -match $script:P20WorkflowLinePattern) {
            $wline = New-P20WorkflowLine -CardDirectory $cardDir
            $updated = [regex]::Replace($updated, $script:P20WorkflowLinePattern,
                [System.Text.RegularExpressions.MatchEvaluator] { $wline })
        }

        # The third link. An archive pass renames a plain earlier round to -r1, so
        # the name this line carries can go stale; the hop between current/ and
        # archive/ never moves with the hub, which is why this is a re-aim at the
        # card's latest earlier round and not a re-count of ../ the way the two
        # package links are. No earlier round found: the line is left alone.
        if ($updated -match $script:P20PreviousRoundPattern) {
            $archiveDir = Get-P20ArchiveFolderFor -CardDirectory $cardDir
            $cardName = Split-Path $Path -Leaf
            $types = Get-P20WorkItemTypes -Config $global:P20Config
            $myId = Get-P20CardId -Name ($cardName -replace '-r\d+(?=\.prompt\.md$)', '') -Pattern (Get-P20CardIdPattern -WorkItemTypes $types)
            $priors = @(Get-P20PriorRounds -ArchiveDirectory $archiveDir -CardId $myId -WorkItemTypes $types -ExcludeName $cardName)
            if ($priors.Count -gt 0) {
                $pline = New-P20PreviousRoundLine -PreviousPath $priors[-1].FullName -CardDirectory $cardDir
                $updated = [regex]::Replace($updated, $script:P20PreviousRoundPattern,
                    [System.Text.RegularExpressions.MatchEvaluator] { $pline })
            }
        }

        # Byte-for-byte identical means NOT WRITTEN. A refresh that rewrites an
        # unchanged card would show up as a whole-file diff on a Windows hub the
        # first time a PowerShell 5.1 session ran it.
        if ($updated -ceq $content) { return $false }

        Write-CardText -Path $Path -Content $updated
        return $true
    }
    catch {
        $name = Split-Path $Path -Leaf
        Write-Warning "Could not refresh package links in ${name}: $($_.Exception.Message)"
        return $false
    }
}

function Get-P20CardFolders {
    <#
        Every card folder the hub declares: each org's current/ and archive/,
        plus any folder passed in -Also (the active Space's, from Get-PromptFolders).
        Only folders that exist, each once.

        Sync and Archive -Relink walked the ACTIVE org's two folders only, so an
        org nobody switches to -- an archived one, with every card it ever had -- kept
        the links it was written with forever.
        Pure over its input, so a suite can drive it without a module.
    #>
    param(
        [string]$Root,
        $Spaces,
        [string]$CurrentName = 'current',
        [string]$ArchiveName = 'archive',
        [string[]]$Also = @()
    )
    $candidates = New-Object System.Collections.Generic.List[string]
    foreach ($a in @($Also)) { if ($a) { $candidates.Add($a) } }
    if ($Root) {
        foreach ($space in @($Spaces)) {
            if (-not $space) { continue }
            $folder = [string]$space.promptsFolder
            if (-not $folder) { $folder = [string]$space.slug }
            if (-not $folder) { continue }
            $candidates.Add((Join-Path (Join-Path $Root $folder) $CurrentName))
            $candidates.Add((Join-Path (Join-Path $Root $folder) $ArchiveName))
        }
    }
    $seen = @{}
    $out = @()
    foreach ($c in $candidates) {
        if (-not (Test-Path -LiteralPath $c -PathType Container)) { continue }
        $key = ((Resolve-Path -LiteralPath $c).Path -replace '\\', '/').TrimEnd('/').ToLowerInvariant()
        if ($seen.ContainsKey($key)) { continue }
        $seen[$key] = $true
        $out += $c
    }
    return , $out
}

function Repair-P20FolderLinks {
    <#
        The same pass over every card in a folder. Returns how many changed.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Inner helper; the caller owns the ShouldProcess decision.')]
    param([Parameter(Mandatory = $true)][string]$Folder)

    $changed = 0
    if (-not (Test-Path $Folder)) { return 0 }
    foreach ($f in (Get-ChildItem -Path $Folder -Filter '*.prompt.md' -File -ErrorAction SilentlyContinue)) {
        if (Repair-P20CardLinks -Path $f.FullName) { $changed++ }
    }
    return $changed
}
