<#
.SYNOPSIS
    Marks a card as not billable -- or billable again.
.DESCRIPTION
    Daily is built from the cards. A card is on it unless the card itself says
    otherwise, with one line in its footer:

        **Billable:** no

    No line means billable, so no existing card needed migrating and a card that
    came from a work item is billable without anyone saying so. This verb writes
    that line (-No) or takes it away (no switch). It changes nothing else about
    the card, keeps the card's own line endings, and does not write a card that
    already says what was asked.

    The card is looked for in current/ first and then in archive/: the usual
    moment to notice a card should not have been billed is Friday, and by Friday
    it is often closed.
.PARAMETER Card
    The card's ID -- a work item number, or the four-character id of a card with
    no work item -- or its filename. An ID matches that id and no other.
.PARAMETER No
    Mark the card NOT billable. Without it, the card is made billable again.
.EXAMPLE
    {cliPrefix}Billable K7M2 -No
    {cliPrefix}Billable K7M2
#>
[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [string]$Card,

    [switch]$No,

    [switch]$Help
)

# Get-CliPrefix normally comes from the module. These scripts are also invoked
# directly -- by tests, by a user running the .ps1, by anything that wants -Help
# without importing first -- so a missing helper must not be fatal.
if (-not (Get-Command Get-CliPrefix -ErrorAction SilentlyContinue)) {
    function Get-CliPrefix {
        if ($global:P20Config -and $global:P20Config.CommandPrefix) { return $global:P20Config.CommandPrefix }
        return ''
    }
}

# Write-CliError normally comes from the module too, and it is what makes a
# refusal ONE block: the wrapper sees the stated exit code and adds nothing.
# See AGENTS.md, "The refusal contract".
if (-not (Get-Command Write-CliError -ErrorAction SilentlyContinue)) {
    function Write-CliError {
        param([string]$Message, [string]$Hint)
        $global:P20StatedError = $Message
        Write-Host "Error: $Message" -ForegroundColor Red
        if ($Hint) { Write-Host "Hint:  $Hint" -ForegroundColor Yellow }
    }
}

if ($Help) {
    $p = Get-CliPrefix
    Write-Host ""
    Write-Host "  ${p}Billable <id|file> -No     Keep this card OFF Daily -- it is not billable" -ForegroundColor Cyan
    Write-Host "  ${p}Billable <id|file>         Make it billable again" -ForegroundColor Cyan
    Write-Host "  ${p}Billable -Help             Show this help" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  A card is billable unless it says otherwise. -No writes one line into" -ForegroundColor Gray
    Write-Host "  the card's footer; without -No that line is removed. The card is looked" -ForegroundColor Gray
    Write-Host "  for in current/ and then in archive/, by its exact ID or its filename." -ForegroundColor Gray
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
. (Join-Path $PSScriptRoot 'Resolve-CardName.ps1')
. (Join-Path $PSScriptRoot 'Set-CardLine.ps1')

if (-not $Card) {
    Write-CliError -Message "no card given." `
        -Hint "Pass the card's ID or filename: '$(Get-CliPrefix)Billable <id> -No'. '$(Get-CliPrefix)Status' lists the cards."
    exit 2  # stated refusal
}

$folders = Get-PromptFolders
$types = Get-P20WorkItemTypes -Config $cfg

# current/ first, then archive/. The one rule for "what did they mean?" is
# Resolve-P20CardArgument: an id is never a partial name.
$found = @()
$isId = $false
foreach ($folder in @($folders.Current, $folders.Archive)) {
    $resolved = Resolve-P20CardArgument -Argument $Card -Folder $folder -WorkItemTypes $types
    $isId = $resolved.IsId
    $found = @($resolved.Match | Where-Object { $_.Name -like '*.md' })
    if ($found.Count -gt 0) { break }
}

if ($found.Count -eq 0) {
    if ($isId) {
        Write-CliError -Message "No card with id '$Card' in current/ or archive/." `
            -Hint "'$Card' has the shape of an ID, and an ID is not a partial name. Run '$(Get-CliPrefix)Status' to see the cards."
    }
    else {
        Write-CliError -Message "No card matching '$Card' in current/ or archive/." `
            -Hint "Run '$(Get-CliPrefix)Status' to see the cards."
    }
    exit 2  # stated refusal
}
if ($found.Count -gt 1) {
    Write-Host "Matches for '$Card':" -ForegroundColor Yellow
    $found | ForEach-Object { Write-Host "  $($_.Name)" }
    Write-CliError -Message "'$Card' matches $($found.Count) cards." `
        -Hint "Pass the full filename of the one you mean."
    exit 2  # stated refusal
}

$file = $found[0]
$stamp = (Get-P20Consts).stamps.billable
$label = Get-P20CardId -Name $file.Name -Pattern (Get-P20CardIdPattern -WorkItemTypes $types)
if (-not $label) { $label = $file.Name }

if ($No) {
    $changed = Set-P20CardLine -Path $file.FullName -Stamp $stamp -Value 'no'
    if ($changed) {
        Write-Host "[+] $label is not billable -- it stays off Daily. ($($file.Name))" -ForegroundColor Green
    }
    else {
        Write-Host "$label already says it is not billable -- nothing written." -ForegroundColor Gray
    }
}
else {
    $changed = Set-P20CardLine -Path $file.FullName -Stamp $stamp -Remove
    if ($changed) {
        Write-Host "[+] $label is billable again. ($($file.Name))" -ForegroundColor Green
    }
    else {
        Write-Host "$label is already billable -- a card is, unless it says otherwise. Nothing written." -ForegroundColor Gray
    }
}
exit 0
