<#
.SYNOPSIS
    A card's pictures -- the cover and the before -- read, attached and removed
    by ONE set of functions. Dot-source it.

.DESCRIPTION
    Not a command -- no alias, no menu row, no help entry of its own. The verb is
    Cover (Scripts/Set-CardCover.ps1); NewPrompt -Cover / -Before attaches through
    the same code at birth.

    Where a picture lives (docs/hub/cards.md, "A card's pictures"):

        <promptsRoot>/<space>/
          current/  archive/        the cards
          assets/<card key>/        cover.png, before.png, cover-r2.png ...

    and the card names it with one footer line, relative to the card's folder:

        **Cover:** ../assets/<card key>/cover.png

    so the same line is right from current/ and from archive/, and Archive moves
    nothing. The stamps and the folder name are consts.json's (stamps.cover,
    stamps.before, folders.assets); the image types and the size limit are its
    assets block.

    THE LINE IS THE TRUTH. Resolve-P20CardImage is the reader both halves agree
    on (agent/core/parsers.py card_image; Tests/fixtures/parsers/covers.json is
    the one table): the file the line names, only when it resolves inside that
    Space's assets/, exactly <card key>/<file>, is an image type, and is there.
    Anything else reads as no picture.

    ROUNDS SHARE AN ID, SO THEY SHARE A FOLDER. A card that came back is a new
    file with the same id; its picture must not replace the one an archived
    round's line names. Add-P20CardImage takes the first free name -- cover,
    cover-r2, cover-r3 -- judged by the lines of the OTHER cards with that id in
    current/ and archive/, and never a name a file already has on disk unless
    this card's own line names it. A file the verb did not write is never
    touched: a mock someone put in the folder stays.

.NOTES
    PowerShell 5.1 compatible (ASCII only, no ternary, no null-coalescing).

        . (Join-Path $PSScriptRoot 'Add-CardImage.ps1')
#>

if (-not (Get-Command Get-P20Consts -ErrorAction SilentlyContinue)) {
    . (Join-Path $PSScriptRoot 'Get-Consts.ps1')
}
if (-not (Get-Command Get-P20CardIdPattern -ErrorAction SilentlyContinue)) {
    . (Join-Path $PSScriptRoot 'Resolve-CardName.ps1')
}
if (-not (Get-Command Set-P20CardLine -ErrorAction SilentlyContinue)) {
    . (Join-Path $PSScriptRoot 'Set-CardLine.ps1')
}

function Get-P20CardImageStamp {
    # 'cover' -> **Cover:**, 'before' -> **Before:**, from the contract.
    param([ValidateSet('cover', 'before')][string]$Kind)
    $stamps = (Get-P20Consts).stamps
    if ($Kind -eq 'before') { return [string]$stamps.before }
    return [string]$stamps.cover
}

function Get-P20CardKey {
    <#
        The card key: the filename's type prefix as written, then its id as
        Resolve-CardName.ps1 reads it -- US-467, Task211, Spike-K7M2, 214.
        $null for a name that carries no id.
    #>
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [hashtable]$WorkItemTypes
    )
    $pattern = Get-P20CardIdPattern -WorkItemTypes $WorkItemTypes
    $id = Get-P20CardId -Name $Name -Pattern $pattern
    if (-not $id) { return $null }
    $m = [regex]::Match($Name, $pattern)
    return ($Name.Substring(0, $m.Groups[1].Index) + $id)
}

function Get-P20CardImageLine {
    # The value of the card's **Cover:** (or **Before:**) line as written, or $null.
    param(
        [AllowEmptyString()][string]$Text,
        [Parameter(Mandatory = $true)][string]$Stamp
    )
    if (-not $Text) { return $null }
    $m = [regex]::Match($Text, '(?m)^' + [regex]::Escape($Stamp) + '[ \t]*(\S[^\r\n]*?)[ \t]*\r?$')
    if (-not $m.Success) { return $null }
    return $m.Groups[1].Value
}

function Get-P20SpaceAssetsDir {
    # A card in <space>/current/ or <space>/archive/ keeps its pictures in <space>/assets/.
    param([Parameter(Mandatory = $true)][string]$CardPath)
    $cardDir = Split-Path -Parent $CardPath
    $spaceDir = Split-Path -Parent $cardDir
    return (Join-Path $spaceDir ([string](Get-P20Consts).folders.assets))
}

function Resolve-P20CardImage {
    <#
        The picture a card's line names, as '<card key>/<file>' inside its Space's
        assets/, or $null. The rule the agent's card_image() keeps, row for row
        (Tests/fixtures/parsers/covers.json):

          - the line is there, and its path is relative,
          - it resolves INSIDE the Space's assets/ -- resolved first, then checked,
            so ../assets/../current/x.png is outside however it is spelled,
          - exactly two segments deep: <card key>/<file>,
          - the extension is one of assets.coverExtensions,
          - and the file is there. A line whose file is missing is no picture.
    #>
    param(
        [Parameter(Mandatory = $true)][string]$CardPath,
        [Parameter(Mandatory = $true)][string]$Stamp,
        # The card's text, when the caller already has it.
        [AllowEmptyString()][string]$Text
    )
    if (-not $PSBoundParameters.ContainsKey('Text')) {
        if (-not (Test-Path -LiteralPath $CardPath -PathType Leaf)) { return $null }
        $Text = [System.IO.File]::ReadAllText($CardPath)
    }
    $value = Get-P20CardImageLine -Text $Text -Stamp $Stamp
    if (-not $value) { return $null }
    $value = $value.Replace('\', '/')
    if ($value.StartsWith('/') -or $value -match '^[A-Za-z]:' -or $value.Contains('://')) { return $null }

    $cardDir = Split-Path -Parent $CardPath
    $assets = [System.IO.Path]::GetFullPath((Get-P20SpaceAssetsDir -CardPath $CardPath)).TrimEnd('\', '/')
    $full = [System.IO.Path]::GetFullPath((Join-Path $cardDir $value))
    $sep = [System.IO.Path]::DirectorySeparatorChar
    if (-not $full.StartsWith($assets + $sep, [System.StringComparison]::Ordinal)) { return $null }

    $rel = $full.Substring($assets.Length + 1).Replace('\', '/')
    $segments = @($rel.Split('/'))
    if ($segments.Count -ne 2 -or -not $segments[0] -or -not $segments[1]) { return $null }
    $ext = [System.IO.Path]::GetExtension($segments[1]).TrimStart('.').ToLowerInvariant()
    if (@((Get-P20Consts).assets.coverExtensions) -notcontains $ext) { return $null }
    if (-not (Test-Path -LiteralPath $full -PathType Leaf)) { return $null }
    return $rel
}

function Test-P20CoverSource {
    <#
        Is this a picture Cover may copy? @{ Ok; Message; Hint; Path; Extension }.
        One sentence each, and the size refusal names the limit.
    #>
    param([AllowEmptyString()][string]$Path)
    $kinds = @((Get-P20Consts).assets.coverExtensions)
    $kindWords = ($kinds -join ', ')
    $result = @{ Ok = $false; Message = ''; Hint = ''; Path = ''; Extension = '' }
    if (-not $Path -or -not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        $result.Message = "'$Path' is not a file."
        $result.Hint = "Give the path of an image: $kindWords."
        return $result
    }
    $item = Get-Item -LiteralPath $Path
    $ext = $item.Extension.TrimStart('.').ToLowerInvariant()
    if ($kinds -notcontains $ext) {
        $shown = if ($ext) { ".$ext" } else { 'no extension' }
        $result.Message = "'$($item.Name)' is $shown -- a cover is one of $kindWords."
        $result.Hint = 'Save the picture as one of those types, then attach it.'
        return $result
    }
    $max = [long](Get-P20Consts).assets.coverMaxBytes
    if ($item.Length -gt $max) {
        $limitMb = [math]::Round($max / 1MB, 1)
        $sizeMb = [math]::Round($item.Length / 1MB, 1)
        $result.Message = "'$($item.Name)' is $sizeMb MB -- a cover is at most $limitMb MB."
        $result.Hint = 'A cover is a screen snap, not a recording: crop it or save it smaller.'
        return $result
    }
    $result.Ok = $true
    $result.Path = $item.FullName
    $result.Extension = $ext
    return $result
}

function Get-P20CardRoundSiblings {
    # The OTHER cards with this card's id, in current/ and archive/ -- its rounds.
    param(
        [Parameter(Mandatory = $true)][System.IO.FileInfo]$CardFile,
        [string[]]$Folders,
        [hashtable]$WorkItemTypes
    )
    $pattern = Get-P20CardIdPattern -WorkItemTypes $WorkItemTypes
    $id = Get-P20CardId -Name $CardFile.Name -Pattern $pattern
    if (-not $id) { return @() }
    $found = @()
    foreach ($folder in @($Folders | Where-Object { $_ })) {
        $r = Resolve-P20CardArgument -Argument $id -Folder $folder -WorkItemTypes $WorkItemTypes
        $found += @($r.Match | Where-Object { $_.Name -like '*.md' -and $_.FullName -ne $CardFile.FullName })
    }
    return $found
}

function Get-P20ImageLeaf {
    # The file name a line names, when it points into <assets>/<keyDir>/; else $null.
    param([AllowNull()][AllowEmptyString()][string]$Value, [string]$KeyDir)
    if (-not $Value) { return $null }
    $parts = @($Value.Replace('\', '/').Split('/') | Where-Object { $_ -ne '' })
    if ($parts.Count -lt 2) { return $null }
    if (-not [string]::Equals($parts[$parts.Count - 2], $KeyDir, [System.StringComparison]::OrdinalIgnoreCase)) { return $null }
    return $parts[$parts.Count - 1]
}

function Get-P20CardKeyDir {
    # The card key's folder under assets/: an existing one that differs only in case is used as it is.
    param([string]$AssetsDir, [string]$Key)
    if (Test-Path -LiteralPath $AssetsDir) {
        $existing = @(Get-ChildItem -LiteralPath $AssetsDir -Directory -ErrorAction SilentlyContinue |
            Where-Object { [string]::Equals($_.Name, $Key, [System.StringComparison]::OrdinalIgnoreCase) })
        if ($existing.Count -gt 0) { return $existing[0].Name }
    }
    return $Key
}

function Add-P20CardImage {
    <#
        Copy $Source into the card's assets folder and write its line. Returns
        @{ Ok; Message; Hint; Key; File; Line; Replaced; Changed } -- the caller
        states a refusal (Ok = $false) through Write-CliError and exits 2.

        Replaced is the card's own earlier file when this replaced it. Changed
        lists the hub paths written or deleted, for a storeSync commit.
    #>
    param(
        [Parameter(Mandatory = $true)][System.IO.FileInfo]$CardFile,
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Source,
        [ValidateSet('cover', 'before')][string]$Kind = 'cover',
        [string[]]$Folders,
        [hashtable]$WorkItemTypes,
        [switch]$WhatIf
    )
    $result = @{ Ok = $false; Message = ''; Hint = ''; Key = ''; File = ''; Line = ''; Replaced = $null; Changed = @(); Path = '' }
    $src = Test-P20CoverSource -Path $Source
    if (-not $src.Ok) { $result.Message = $src.Message; $result.Hint = $src.Hint; return $result }

    $key = Get-P20CardKey -Name $CardFile.Name -WorkItemTypes $WorkItemTypes
    if (-not $key) {
        $result.Message = "'$($CardFile.Name)' carries no id in its name, so it has no assets folder."
        $result.Hint = 'A card is named <prefix><id>-<slug>.prompt.md; NewPrompt names it so.'
        return $result
    }
    $assetsName = [string](Get-P20Consts).folders.assets
    $assetsDir = Get-P20SpaceAssetsDir -CardPath $CardFile.FullName
    $keyDir = Get-P20CardKeyDir -AssetsDir $assetsDir -Key $key
    $keyPath = Join-Path $assetsDir $keyDir
    $stamp = Get-P20CardImageStamp -Kind $Kind

    $text = [System.IO.File]::ReadAllText($CardFile.FullName)
    $ownLeaf = Get-P20ImageLeaf -Value (Get-P20CardImageLine -Text $text -Stamp $stamp) -KeyDir $keyDir

    # Names the other rounds' lines hold -- cover AND before, by stem, any extension.
    $taken = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($sib in (Get-P20CardRoundSiblings -CardFile $CardFile -Folders $Folders -WorkItemTypes $WorkItemTypes)) {
        $sibText = [System.IO.File]::ReadAllText($sib.FullName)
        foreach ($k in @('cover', 'before')) {
            $leaf = Get-P20ImageLeaf -Value (Get-P20CardImageLine -Text $sibText -Stamp (Get-P20CardImageStamp -Kind $k)) -KeyDir $keyDir
            if ($leaf) { [void]$taken.Add([System.IO.Path]::GetFileNameWithoutExtension($leaf)) }
        }
    }
    # Stems a file already has on disk -- a mock someone put there by hand is not ours.
    $onDisk = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
    if (Test-Path -LiteralPath $keyPath) {
        foreach ($f in (Get-ChildItem -LiteralPath $keyPath -File -ErrorAction SilentlyContinue)) {
            if ($ownLeaf -and [string]::Equals($f.Name, $ownLeaf, [System.StringComparison]::OrdinalIgnoreCase)) { continue }
            [void]$onDisk.Add($f.BaseName)
        }
    }

    $stem = $null
    if ($ownLeaf) {
        $ownStem = [System.IO.Path]::GetFileNameWithoutExtension($ownLeaf)
        if (-not $taken.Contains($ownStem) -and -not $onDisk.Contains($ownStem)) { $stem = $ownStem }
    }
    if (-not $stem) {
        for ($n = 1; $n -lt 1000; $n++) {
            $candidate = $Kind
            if ($n -gt 1) { $candidate = "$Kind-r$n" }
            if ($taken.Contains($candidate) -or $onDisk.Contains($candidate)) { continue }
            $stem = $candidate
            break
        }
    }
    $leafName = "$stem.$($src.Extension)"
    $dest = Join-Path $keyPath $leafName
    $line = "../$assetsName/$keyDir/$leafName"

    $result.Key = $keyDir
    $result.File = $leafName
    $result.Line = "$stamp $line"
    $result.Path = $dest
    # Only this card's OWN picture is replaced: one another round's line also names is left alone.
    if ($ownLeaf -and -not $taken.Contains([System.IO.Path]::GetFileNameWithoutExtension($ownLeaf)) -and
        (Test-Path -LiteralPath (Join-Path $keyPath $ownLeaf))) { $result.Replaced = $ownLeaf }
    $result.Ok = $true
    if ($WhatIf) { return $result }

    if (-not (Test-Path -LiteralPath $keyPath)) { New-Item -ItemType Directory -Path $keyPath -Force | Out-Null }
    Copy-Item -LiteralPath $src.Path -Destination $dest -Force
    $changed = @($dest, $CardFile.FullName)
    if ($result.Replaced -and -not [string]::Equals($result.Replaced, $leafName, [System.StringComparison]::OrdinalIgnoreCase)) {
        # The card's own earlier picture under another name: this card's line named it,
        # and no other round's does.
        $old = Join-Path $keyPath $result.Replaced
        Remove-Item -LiteralPath $old -Force -ErrorAction SilentlyContinue
        $changed += $old
    }
    [void](Set-P20CardLine -Path $CardFile.FullName -Stamp $stamp -Value $line)
    $result.Changed = $changed
    return $result
}

function Remove-P20CardImage {
    <#
        Delete the card's picture and its line. The file goes only when the line
        resolves inside the Space's assets/ and no other round's line names it --
        the verb never touches a file it did not write. Returns
        @{ Had; File; Changed }.
    #>
    param(
        [Parameter(Mandatory = $true)][System.IO.FileInfo]$CardFile,
        [ValidateSet('cover', 'before')][string]$Kind = 'cover',
        [string[]]$Folders,
        [hashtable]$WorkItemTypes,
        [switch]$WhatIf
    )
    $result = @{ Had = $false; File = $null; Changed = @() }
    $stamp = Get-P20CardImageStamp -Kind $Kind
    $text = [System.IO.File]::ReadAllText($CardFile.FullName)
    if (-not (Get-P20CardImageLine -Text $text -Stamp $stamp)) { return $result }
    $result.Had = $true

    $rel = Resolve-P20CardImage -CardPath $CardFile.FullName -Stamp $stamp -Text $text
    $assetsDir = Get-P20SpaceAssetsDir -CardPath $CardFile.FullName
    $target = $null
    if ($rel) {
        $keyDir = $rel.Split('/')[0]
        $leaf = $rel.Split('/')[1]
        $sharedWithRound = $false
        foreach ($sib in (Get-P20CardRoundSiblings -CardFile $CardFile -Folders $Folders -WorkItemTypes $WorkItemTypes)) {
            $sibText = [System.IO.File]::ReadAllText($sib.FullName)
            foreach ($k in @('cover', 'before')) {
                $sibLeaf = Get-P20ImageLeaf -Value (Get-P20CardImageLine -Text $sibText -Stamp (Get-P20CardImageStamp -Kind $k)) -KeyDir $keyDir
                if ($sibLeaf -and [string]::Equals($sibLeaf, $leaf, [System.StringComparison]::OrdinalIgnoreCase)) { $sharedWithRound = $true }
            }
        }
        if (-not $sharedWithRound) {
            $target = Join-Path (Join-Path $assetsDir $keyDir) $leaf
            $result.File = $leaf
        }
    }
    if ($WhatIf) { return $result }

    $changed = @($CardFile.FullName)
    if ($target) {
        Remove-Item -LiteralPath $target -Force -ErrorAction SilentlyContinue
        $changed += $target
        # The key's folder goes too when this was the last thing in it.
        $folder = Split-Path -Parent $target
        if ((Test-Path -LiteralPath $folder) -and @(Get-ChildItem -LiteralPath $folder -Force -ErrorAction SilentlyContinue).Count -eq 0) {
            Remove-Item -LiteralPath $folder -Force -ErrorAction SilentlyContinue
        }
    }
    [void](Set-P20CardLine -Path $CardFile.FullName -Stamp $stamp -Remove)
    $result.Changed = $changed
    return $result
}

function Save-P20CardImageCommit {
    <#
        With storeSync: git, the picture and the card are one commit -- the way
        Archive commits its move. Anything else commits nothing and says so.
        Returns a sentence for the caller to print.
    #>
    param(
        [Parameter(Mandatory = $true)][string]$PromptsRoot,
        [string]$StoreSync,
        [string[]]$Paths,
        [Parameter(Mandatory = $true)][string]$Message
    )
    if ($StoreSync -ne 'git') { return "Store is not git (storeSync='$StoreSync') -- nothing committed." }
    $root = [System.IO.Path]::GetFullPath($PromptsRoot).TrimEnd('\', '/')
    $rels = @()
    foreach ($p in @($Paths | Where-Object { $_ })) {
        $full = [System.IO.Path]::GetFullPath($p)
        if ($full.StartsWith($root, [System.StringComparison]::OrdinalIgnoreCase)) {
            $rels += $full.Substring($root.Length + 1).Replace('\', '/')
        }
    }
    if ($rels.Count -eq 0) { return 'Nothing to commit.' }
    Push-Location $PromptsRoot
    try {
        # One path at a time: a picture deleted before git ever saw it is not a
        # pathspec git knows, and one unknown path would fail the whole add.
        $staged = @()
        foreach ($rel in $rels) {
            & git add -A -- $rel 2>&1 | Out-Null
            if ($LASTEXITCODE -eq 0) { $staged += $rel }
        }
        if ($staged.Count -eq 0) { return 'Commit failed: the picture and the card are written but not committed.' }
        & git commit -m $Message -- @staged 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) { return 'Commit failed: the picture and the card are written but not committed.' }
        return 'Committed.'
    }
    finally {
        Pop-Location
        $global:LASTEXITCODE = 0
    }
}
