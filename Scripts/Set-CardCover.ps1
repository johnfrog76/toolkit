<#
.SYNOPSIS
    Gives a card a picture -- its cover, or the "before" of a before/after proof.
.DESCRIPTION
    A card can carry an image: a screen snap of what was wrong, or of what
    landed. The image is copied into the Space's assets/ folder, beside current/
    and archive/, and the card names it with one footer line:

        **Cover:** ../assets/<card key>/cover.png

    The board draws it as the top of the card's face, the list as a thumbnail,
    and the card page under its header (docs/hub/cards.md, "A card's pictures").

    The card is looked for in current/ and then in archive/: proof often arrives
    after the card is Done. Attaching again replaces this card's own picture and
    says so. A card that came back shares its folder with its earlier rounds, so
    it takes the first name no round's line holds -- cover, cover-r2, cover-r3.
    -Remove deletes the picture and the line. With storeSync: git the picture
    and the card are one commit.

    -Samples is the upgrade path for a hub whose Demo was copied out before the
    sample cards had covers: it gives every sample card that has no
    **Cover:** line the picture the package ships for it, through the same
    writer, and nothing else -- never a card that already has a cover, never a
    card the sample does not ship, never a Space that is not a sample's. Update
    says when it is worth running.
.PARAMETER Card
    The card's ID -- a work item number, or the four-character id of a card with
    no work item -- or its filename. An ID matches that id and no other.
.PARAMETER Image
    The picture to attach: png, jpg, jpeg, webp or gif, at most 5 MB.
.PARAMETER Before
    The "before" picture instead of the cover.
.PARAMETER Remove
    Delete the picture and its line.
.PARAMETER Samples
    Dress the sample cards in this hub that have no cover, with the package's
    pictures. Takes no card and no image.
.PARAMETER WhatIf
    Say what would be copied and written, and change nothing.
.EXAMPLE
    {cliPrefix}Cover K7M2 ./snap.png
    {cliPrefix}Cover 214 ./before.png -Before
    {cliPrefix}Cover K7M2 -Remove
    {cliPrefix}Cover -Samples
    {cliPrefix}Cover -Samples -WhatIf
#>
[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [string]$Card,

    [Parameter(Position = 1)]
    [string]$Image,

    [switch]$Before,

    [switch]$Remove,

    [switch]$Samples,

    [switch]$WhatIf,

    [switch]$Help
)

. (Join-Path $PSScriptRoot 'Initialize-CliFallbacks.ps1')

if ($Help) {
    $p = Get-CliPrefix
    Write-Host ""
    Write-Host "  ${p}Cover <id|file> <image>            Give the card a cover picture" -ForegroundColor Cyan
    Write-Host "  ${p}Cover <id|file> <image> -Before    The 'before' of a before/after proof" -ForegroundColor Cyan
    Write-Host "  ${p}Cover <id|file> -Remove [-Before]  Delete the picture and its line" -ForegroundColor Cyan
    Write-Host "  ${p}Cover -Samples                     Dress the sample cards that have no cover" -ForegroundColor Cyan
    Write-Host "  ${p}Cover ... -WhatIf                  Say what would happen; change nothing" -ForegroundColor Cyan
    Write-Host "  ${p}Cover -Help                        Show this help" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  The picture is copied to the Space's assets/<card key>/ folder and the card" -ForegroundColor Gray
    Write-Host "  names it with one footer line. png, jpg, jpeg, webp or gif, at most 5 MB." -ForegroundColor Gray
    Write-Host "  The card is looked for in current/ and then in archive/." -ForegroundColor Gray
    Write-Host "  -Samples gives only the sample cards that have no cover the package's picture;" -ForegroundColor Gray
    Write-Host "  a card that has a cover, or that the sample does not ship, is left alone." -ForegroundColor Gray
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
. (Join-Path $PSScriptRoot 'Add-CardImage.ps1')

$p = Get-CliPrefix

if ($Samples) {
    if ($Card -or $Image -or $Before -or $Remove) {
        Write-CliError -Message "-Samples takes no card, no image, -Before or -Remove." `
            -Hint "Run '${p}Cover -Samples' on its own, or '${p}Cover <id> <image>' for one card."
        exit 2  # stated refusal
    }
    . (Join-Path $PSScriptRoot 'Get-SampleCoverGaps.ps1')
    $pkgRoot = Split-Path -Parent $PSScriptRoot
    $typesForSamples = Get-P20WorkItemTypes -Config $cfg
    $gaps = @(Get-P20SampleCoverGaps -PromptsRoot $promptsRoot -PackageRoot $pkgRoot)
    if ($gaps.Count -eq 0) {
        Write-Host "No sample card in this hub is missing its cover -- nothing to do." -ForegroundColor Gray
        exit 0
    }
    $dressed = 0
    $refused = 0
    $changedPaths = @()
    foreach ($gap in $gaps) {
        $gapLabel = Get-P20CardId -Name $gap.Card.Name -Pattern (Get-P20CardIdPattern -WorkItemTypes $typesForSamples)
        if (-not $gapLabel) { $gapLabel = $gap.Card.Name }
        $one = Add-P20CardImage -CardFile $gap.Card -Source $gap.Image -Kind 'cover' -Folders $gap.Folders -WorkItemTypes $typesForSamples -WhatIf:$WhatIf
        if (-not $one.Ok) {
            $refused++
            Write-Host "  [!] $($gap.Space)/$gapLabel -- $($one.Message)" -ForegroundColor Yellow
            continue
        }
        $dressed++
        if ($WhatIf) {
            Write-Host "  What if: would dress $($gap.Space)/$gapLabel -- copy $($one.Key)/$($one.File) and write '$($one.Line)' into $($gap.Card.Name)" -ForegroundColor Yellow
        }
        else {
            Write-Host "  [+] $($gap.Space)/$gapLabel has a cover -- $($one.Key)/$($one.File)" -ForegroundColor Green
            $changedPaths += @($one.Changed)
        }
    }
    if ($WhatIf) {
        Write-Host "What if: would dress $dressed sample card(s). Nothing was changed." -ForegroundColor Yellow
    }
    else {
        Write-Host "Dressed $dressed sample card(s)." -ForegroundColor Green
        if ($changedPaths.Count -gt 0) {
            $note = Save-P20CardImageCommit -PromptsRoot $promptsRoot -StoreSync ([string]$cfg.StoreSync) -Paths $changedPaths `
                -Message "cover: dress $dressed sample card(s)"
            Write-Host "    $($note.Note)" -ForegroundColor DarkGray
            if (-not $note.Ok) {
                Write-CliError -Message $note.Message -Hint $note.Hint
                exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
            }
        }
    }
    if ($refused -gt 0) {
        Write-CliError -Message "$refused sample card(s) could not be dressed." `
            -Hint "The lines above say which; the package's picture may be missing -- '$($p)Update' brings it."
        exit 2  # stated refusal
    }
    exit 0
}
if (-not $Card) {
    Write-CliError -Message "no card given." `
        -Hint "Pass the card's ID or filename and a picture: '${p}Cover <id> <image>'. '${p}Status' lists the cards."
    exit 2  # stated refusal
}
if (-not $Remove -and -not $Image) {
    Write-CliError -Message "no picture given." `
        -Hint "Pass the image's path: '${p}Cover $Card <image>', or -Remove to take one off."
    exit 2  # stated refusal
}

$folders = Get-PromptFolders
$types = Get-P20WorkItemTypes -Config $cfg
. (Join-Path $PSScriptRoot 'Move-CardFolder.ps1')
$cardFolders = @($folders.Current, (Get-P20BacklogFolder -Folders $folders), $folders.Archive)

# current/ first, then backlog/, then archive/. The one rule for "what did they mean?" is
# Resolve-P20CardArgument: an id is never a partial name.
$found = @()
$isId = $false
foreach ($folder in $cardFolders) {
    $resolved = Resolve-P20CardArgument -Argument $Card -Folder $folder -WorkItemTypes $types
    $isId = $resolved.IsId
    $found = @($resolved.Match | Where-Object { $_.Name -like '*.md' })
    if ($found.Count -gt 0) { break }
}

if ($found.Count -eq 0) {
    if ($isId) {
        Write-CliError -Message "No card with id '$Card' in current/, backlog/ or archive/." `
            -Hint "'$Card' has the shape of an ID, and an ID is not a partial name. Run '${p}Status' to see the cards."
    }
    else {
        Write-CliError -Message "No card matching '$Card' in current/, backlog/ or archive/." `
            -Hint "Run '${p}Status' to see the cards."
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
$kind = 'cover'
$word = 'cover'
if ($Before) { $kind = 'before'; $word = 'before picture' }
$label = Get-P20CardId -Name $file.Name -Pattern (Get-P20CardIdPattern -WorkItemTypes $types)
if (-not $label) { $label = $file.Name }

if ($Remove) {
    $outcome = Remove-P20CardImage -CardFile $file -Kind $kind -Folders $cardFolders -WorkItemTypes $types -WhatIf:$WhatIf
    if (-not $outcome.Had) {
        Write-Host "$label has no $word -- nothing removed." -ForegroundColor Gray
        exit 0
    }
    if ($WhatIf) {
        $what = 'its line'
        if ($outcome.File) { $what = "$($outcome.File) and its line" }
        Write-Host "What if: would remove $label's $word -- $what. Nothing was changed." -ForegroundColor Yellow
        exit 0
    }
    if ($outcome.File) {
        Write-Host "[+] Removed $label's $word -- $($outcome.File) and its line. ($($file.Name))" -ForegroundColor Green
    }
    else {
        Write-Host "[+] Removed $label's $word line; the file it named was not one this verb keeps, so it was left alone. ($($file.Name))" -ForegroundColor Green
    }
    $note = Save-P20CardImageCommit -PromptsRoot $promptsRoot -StoreSync ([string]$cfg.StoreSync) -Paths $outcome.Changed `
        -Message "cover: remove $label's $word"
    Write-Host "    $($note.Note)" -ForegroundColor DarkGray
    if (-not $note.Ok) {
        Write-CliError -Message $note.Message -Hint $note.Hint
        exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
    }
    exit 0
}

$outcome = Add-P20CardImage -CardFile $file -Source $Image -Kind $kind -Folders $cardFolders -WorkItemTypes $types -WhatIf:$WhatIf
if (-not $outcome.Ok) {
    Write-CliError -Message $outcome.Message -Hint $outcome.Hint
    exit 2  # stated refusal
}

$assetsName = [string](Get-P20Consts).folders.assets
$where = "$assetsName/$($outcome.Key)/$($outcome.File)"
if ($WhatIf) {
    Write-Host "What if: would copy $Image to $where and write '$($outcome.Line)' into $($file.Name). Nothing was changed." -ForegroundColor Yellow
    if ($outcome.Replaced) { Write-Host "    It would replace this card's own $($outcome.Replaced)." -ForegroundColor Yellow }
    exit 0
}

if ($outcome.Replaced) {
    Write-Host "[+] Replaced $label's $word ($($outcome.Replaced)) with $where. ($($file.Name))" -ForegroundColor Green
}
else {
    Write-Host "[+] $label has a $word -- $where. ($($file.Name))" -ForegroundColor Green
}
$note = Save-P20CardImageCommit -PromptsRoot $promptsRoot -StoreSync ([string]$cfg.StoreSync) -Paths $outcome.Changed `
    -Message "cover: $label $($outcome.File)"
Write-Host "    $($note.Note)" -ForegroundColor DarkGray
if (-not $note.Ok) {
    Write-CliError -Message $note.Message -Hint $note.Hint
    exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
}
exit 0
