<#
.SYNOPSIS
    Tags a card, or takes a tag off it -- the write side of the card's `Tags:` line.
.DESCRIPTION
    A card's tags are one line under `## Work Item Info`, directly below `Priority:`,
    as every template writes it:

        Tags: docs, sev3, sonnet

    `NewPrompt` writes it at birth -- the work item's tags, or the template's
    `Tags: (None)` -- and the suggestion and the board's tag filter read it (the
    line split on commas and trimmed: Get-P20CardTags, card_tags). This verb writes it
    on a card that already exists, through `Set-P20CardLine`, so the card keeps its
    own bytes and line endings (AGENTS.md, "One byte contract for a card"):

      - tags are added after the ones the card already carries, in the order given,
        and a tag it already carries (in any case) is not added twice;
      - -Remove takes the given tags off (in any case); the last one off leaves the
        template's `Tags: (None)`;
      - a card with no `Tags:` line gets one below its `Priority:` line, else below
        `## Work Item Info`, else above `**Created:**`;
      - a call that changes no tag writes nothing, and says so.

    The line is written as the reader splits it: tags joined by a comma and a space.
    This is purely a LOCAL, card-side write. It never touches the tracker -- a label on a
    GitHub issue is Route's write, an Azure DevOps tag the work item's own.

    A card is looked for in current/ and backlog/, like Plan.
.PARAMETER Card
    The card's ID, or its filename. An ID matches that id and no other.
.PARAMETER Tags
    The tags: one argument with commas (`docs,sev3`), or several.
.PARAMETER Remove
    Take the given tags off the card instead.
.EXAMPLE
    {cliPrefix}Tag K7M2 docs,sev3
    {cliPrefix}Tag K7M2 sev3 -Remove
#>
[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [string]$Card,

    [Parameter(Position = 1, ValueFromRemainingArguments = $true)]
    [string[]]$Tags,

    [switch]$Remove,

    [switch]$Help
)

. (Join-Path $PSScriptRoot 'Initialize-CliFallbacks.ps1')

if ($Help) {
    $p = Get-CliPrefix
    Write-Host ""
    Write-Host "  ${p}Tag <id|file> <tag>[,<tag>]           Add tags to the card's Tags line" -ForegroundColor Cyan
    Write-Host "  ${p}Tag <id|file> <tag>[,<tag>] -Remove   Take them off" -ForegroundColor Cyan
    Write-Host "  ${p}Tag -Help                             Show this help" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  Writes the card's Tags line under Work Item Info, through Set-P20CardLine: tags" -ForegroundColor Gray
    Write-Host "  joined by a comma, one already there not added twice, the last one off leaving" -ForegroundColor Gray
    Write-Host "  'Tags: (None)'. A call that changes nothing writes nothing. Never the tracker." -ForegroundColor Gray
    Write-Host "  Found in current/ or backlog/." -ForegroundColor Gray
    Write-Host ""
    return
}

$cfg = $global:P20Config
$promptsRoot = $cfg.PromptsRoot
. (Join-Path $PSScriptRoot 'Resolve-HubConfig.ps1')
if (-not (Test-P20HubRoot $promptsRoot)) {
    Write-CliError -Message (Get-P20HubMissingMessage $promptsRoot)
    exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
}

. (Join-Path $PSScriptRoot 'Get-Consts.ps1')
. (Join-Path $PSScriptRoot 'Get-PromptFileStatus.ps1')
. (Join-Path $PSScriptRoot 'Resolve-CardName.ps1')
. (Join-Path $PSScriptRoot 'Set-CardLine.ps1')
. (Join-Path $PSScriptRoot 'Move-CardFolder.ps1')

$p = Get-CliPrefix

if (-not $Card) {
    Write-CliError -Message "no card given." `
        -Hint "Pass the card's ID or filename and a tag: '${p}Tag <id> docs'. '${p}Status' lists the cards."
    exit 2  # stated refusal
}

# One argument with commas, or several: the same split the reader makes.
$given = New-Object System.Collections.Generic.List[string]
foreach ($t in @($Tags)) {
    foreach ($one in ("$t" -split ',')) {
        $one = $one.Trim()
        if (-not $one) { continue }
        if ($one.StartsWith('(')) {
            Write-CliError -Message "'$one' is not a tag -- a value in brackets reads as no tags at all." `
                -Hint "Pass a word, '${p}Tag <id> docs'; '-Remove' takes tags off."
            exit 2  # stated refusal
        }
        if (-not (@($given) | Where-Object { $_ -ieq $one })) { [void]$given.Add($one) }
    }
}
if ($given.Count -eq 0) {
    Write-CliError -Message "no tag given." `
        -Hint "Pass one or more, with commas: '${p}Tag <id> docs,sev3'. '-Remove' takes them off."
    exit 2  # stated refusal
}

$folders = Get-PromptFolders
$backlogDir = Get-P20BacklogFolder -Folders $folders
$types = Get-P20WorkItemTypes -Config $cfg

# -AllowPath: a card's full path is that card, whichever Space is active.
$resolved = Resolve-P20CardArgument -Argument $Card -Folder @($folders.Current, $backlogDir) -WorkItemTypes $types -AllowPath -PromptsRoot $promptsRoot
$found = @($resolved.Match | Where-Object { $_.Name -like '*.md' })
if ($found.Count -eq 0) {
    if ($resolved.IsId) {
        Write-CliError -Message "No card with id '$Card' in current/ or backlog/." `
            -Hint "'$Card' has the shape of an ID, and an ID is not a partial name. A card in archive/ is already Done. Run '${p}Status' to see the cards."
    }
    else {
        Write-CliError -Message "No card matching '$Card' in current/ or backlog/." -Hint "Run '${p}Status' to see the cards."
    }
    exit 2  # stated refusal
}
if ($found.Count -gt 1) {
    Write-Host "Matches for '$Card':" -ForegroundColor Yellow
    $found | ForEach-Object { Write-Host "  $($_.Name)" }
    Write-CliError -Message "'$Card' matches $($found.Count) cards." -Hint "Pass the full filename of the one you mean."
    exit 2  # stated refusal
}

$file = $found[0]
$label = Get-P20CardId -Name $file.Name -Pattern (Get-P20CardIdPattern -WorkItemTypes $types)
if (-not $label) { $label = $file.Name }

$have = @(Get-P20CardTags ([System.IO.File]::ReadAllText($file.FullName)))
$next = New-Object System.Collections.Generic.List[string]
$touched = New-Object System.Collections.Generic.List[string]
if ($Remove) {
    foreach ($t in $have) {
        if (@($given) | Where-Object { $_ -ieq $t }) { [void]$touched.Add($t) } else { [void]$next.Add($t) }
    }
}
else {
    foreach ($t in $have) { [void]$next.Add($t) }
    foreach ($t in $given) {
        if (-not (@($have) | Where-Object { $_ -ieq $t })) { [void]$next.Add($t); [void]$touched.Add($t) }
    }
}

$list = ($touched -join ', ')
if ($touched.Count -eq 0) {
    if ($Remove) { Write-Host "$label carries none of $($given -join ', ') -- nothing written." -ForegroundColor Gray }
    else { Write-Host "$label already carries $($given -join ', ') -- nothing written." -ForegroundColor Gray }
    exit 0
}

# The template's own placeholder when the last tag comes off: the line stays where a
# person (and the template) expects it, and reads as no tags.
$value = '(None)'
if ($next.Count -gt 0) { $value = ($next -join ', ') }
$stamp = [string](Get-P20Consts).tokens.tags
[void](Set-P20CardLine -Path $file.FullName -Stamp $stamp -Value $value -InsertAfter @('^Priority:', '^##\s+Work Item Info\s*$'))
if ($Remove) { Write-Host "[+] $label is no longer tagged $list. ($($file.Name))" -ForegroundColor Green }
else { Write-Host "[+] $label is tagged $list. ($($file.Name))" -ForegroundColor Green }
Write-Host "    $stamp $value" -ForegroundColor Gray
exit 0
