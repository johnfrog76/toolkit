<#
.SYNOPSIS
    Which sample cards in a hub are missing the cover the package now ships for
    them. Dot-source it.

.DESCRIPTION
    Not a command. Start copies samples/hub out once; a Demo made before the
    covers shipped has no assets/ and no **Cover:** lines. This is the one
    place that knows how to tell, for Update (which says so) and for
    `Cover -Samples` (which dresses them): both read this list, so what Update
    counts is exactly what the verb will do.

    A gap is a card that passes ALL of these:
      - it sits in a sample Space's folder: <hub>/<name>/ where <name> is also a
        folder under samples/hub -- current/, backlog/ or archive/, the three
        folders Cover itself looks in (the Demo's first tutorial card ships in
        backlog/);
      - the sample ships a card of the very same filename, so it is the sample's
        card and not one the person added (a card the sample does not know is
        never listed);
      - that sample card carries a **Cover:** the package can resolve to a picture
        (Resolve-P20CardImage, the one reader);
      - the hub's card has no **Cover:** line at all. A card that has a cover --
        the sample's or its own, even one whose file is gone -- is never listed:
        the line is the person's.

    Read-only. Returns objects with Space, Card (the hub's FileInfo), Image (the
    package's picture), Folders (the Space's current/, backlog/ and archive/).

.NOTES
    PowerShell 5.1 compatible (ASCII only, no ternary, no null-coalescing).

        . (Join-Path $PSScriptRoot 'Get-SampleCoverGaps.ps1')
#>

. (Join-Path $PSScriptRoot 'Add-CardImage.ps1')

function Get-P20SampleCoverGaps {
    param(
        [string]$PromptsRoot,
        [Parameter(Mandatory = $true)][string]$PackageRoot
    )
    $gaps = @()
    if (-not $PromptsRoot -or -not (Test-Path -LiteralPath $PromptsRoot -PathType Container)) { return $gaps }
    $sampleRoot = Join-Path (Join-Path $PackageRoot 'samples') 'hub'
    if (-not (Test-Path -LiteralPath $sampleRoot -PathType Container)) { return $gaps }

    $consts = Get-P20Consts
    $currentName = [string]$consts.folders.current
    $archiveName = [string]$consts.folders.archive
    $backlogName = [string]$consts.folders.backlog
    $stamp = Get-P20CardImageStamp -Kind 'cover'

    foreach ($sampleSpace in @(Get-ChildItem -LiteralPath $sampleRoot -Directory -ErrorAction SilentlyContinue)) {
        $hubSpace = Join-Path $PromptsRoot $sampleSpace.Name
        if (-not (Test-Path -LiteralPath $hubSpace -PathType Container)) { continue }
        $folders = @((Join-Path $hubSpace $currentName), (Join-Path $hubSpace $backlogName), (Join-Path $hubSpace $archiveName))
        foreach ($folderName in @($currentName, $backlogName, $archiveName)) {
            $sampleFolder = Join-Path $sampleSpace.FullName $folderName
            if (-not (Test-Path -LiteralPath $sampleFolder -PathType Container)) { continue }
            foreach ($sampleCard in @(Get-ChildItem -LiteralPath $sampleFolder -File -Filter '*.md' -ErrorAction SilentlyContinue)) {
                $rel = Resolve-P20CardImage -CardPath $sampleCard.FullName -Stamp $stamp
                if (-not $rel) { continue }
                $image = Join-Path (Get-P20SpaceAssetsDir -CardPath $sampleCard.FullName) $rel
                # The card may have moved lanes since: look in every card folder of the person's Space.
                foreach ($f in $folders) {
                    $candidate = Join-Path $f $sampleCard.Name
                    if (-not (Test-Path -LiteralPath $candidate -PathType Leaf)) { continue }
                    $hubCard = Get-Item -LiteralPath $candidate
                    $text = [System.IO.File]::ReadAllText($hubCard.FullName)
                    if (Get-P20CardImageLine -Text $text -Stamp $stamp) { break }
                    $gaps += [pscustomobject]@{
                        Space   = $sampleSpace.Name
                        Card    = $hubCard
                        Image   = $image
                        Folders = $folders
                    }
                    break
                }
            }
        }
    }
    return $gaps
}
