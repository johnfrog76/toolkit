#
# The byte contract for a CONFIG file this tool writes -- config.local.json and
# the hub's hub.json.
#
# NOT a runnable verb: this file is DOT-SOURCED, by Scripts/Set-ToolkitConfig.ps1
# and by its suite.
#
# WHY IT IS NOT Write-CardText. Scripts/Write-CardText.ps1 is the contract for a
# CARD -- a document in the user's hub, written once and edited in place, whose
# rule is "created is LF, edited keeps what it had". A config file is not a
# document: it is parsed at every import by three halves, it is rewritten whole
# on every change rather than appended to, and a half-written one is a toolkit
# that will not load. So it needs two things a card does not:
#
#   1. ATOMIC REPLACEMENT. Write a sibling temp file, then rename over the
#      target. [System.IO.File]::WriteAllText truncates first and writes second;
#      a crash, a full disk or a Ctrl-C in between leaves an empty
#      config.local.json, and the next import warns "Failed to parse" and falls
#      back to defaults -- which on this tool means the wrong org and the wrong
#      hub. A rename is the one filesystem operation that cannot be half done.
#
#   2. DETERMINISTIC SERIALISATION. ConvertTo-Json is not one format: Windows
#      PowerShell 5.1 indents with four spaces and escapes every non-ASCII
#      character to \uXXXX, PowerShell 7 indents with two and does not. The same
#      -Set from the two hosts this package supports would produce two different
#      files, and on a hub with storeSync: git that is a whole-file diff per
#      machine -- the exact shape a closed stamp's bytes once had
#      on the card side. ConvertTo-P20ConfigJson below writes ONE format on both:
#      two-space indent, LF, the key order it was given.
#
# The BYTES themselves still come from one place. The temp file is written with
# Write-CardText -New -- UTF-8, no BOM, LF -- so "how this package puts text on
# disk" has exactly one implementation and this file only adds the rename.
#
# Two-space indent because that is what docs/CONFIGURATION.md's example shows and
# what the file a person hand-wrote already looks like; a formatter that
# reflowed it on first touch would make every subsequent diff unreadable.
#
# PowerShell 5.1 clean: no ternary, no null-coalescing, ASCII hyphens only.
#

if (-not (Get-Command Write-CardText -ErrorAction SilentlyContinue)) {
    . (Join-Path $PSScriptRoot 'Write-CardText.ps1')
}

$script:P20ConfigIndent = '  '

function ConvertTo-P20ConfigJson {
    <#
        One JSON text for a config object, the same on 5.1 and 7.

        Takes a PSCustomObject / hashtable / array / scalar tree and returns a
        string with no trailing newline -- the caller adds one. Key order is the
        order the object carries, which for a PSCustomObject read back from disk
        is the order it was written in, so a sparse patch keeps the shape its
        author gave it.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0)][AllowNull()]$Value,
        [int]$Depth = 0
    )

    $pad = $script:P20ConfigIndent * $Depth
    $padInner = $script:P20ConfigIndent * ($Depth + 1)

    if ($null -eq $Value) { return 'null' }
    if ($Value -is [bool]) {
        if ($Value) { return 'true' }
        return 'false'
    }
    if ($Value -is [int] -or $Value -is [long] -or $Value -is [double] -or $Value -is [decimal]) {
        return ([string]$Value)
    }
    if ($Value -is [string]) { return (ConvertTo-P20JsonString $Value) }

    if ($Value -is [System.Collections.IDictionary]) {
        $keys = @($Value.Keys)
        if ($keys.Count -eq 0) { return '{}' }
        $lines = @()
        foreach ($k in $keys) {
            $lines += "$padInner$(ConvertTo-P20JsonString ([string]$k)): $(ConvertTo-P20ConfigJson $Value[$k] -Depth ($Depth + 1))"
        }
        return "{`n" + ($lines -join ",`n") + "`n$pad}"
    }

    if ($Value -is [System.Management.Automation.PSCustomObject]) {
        $props = @($Value.PSObject.Properties)
        if ($props.Count -eq 0) { return '{}' }
        $lines = @()
        foreach ($p in $props) {
            $lines += "$padInner$(ConvertTo-P20JsonString $p.Name): $(ConvertTo-P20ConfigJson $p.Value -Depth ($Depth + 1))"
        }
        return "{`n" + ($lines -join ",`n") + "`n$pad}"
    }

    if ($Value -is [System.Collections.IEnumerable]) {
        $items = @($Value)
        if ($items.Count -eq 0) { return '[]' }
        $lines = @()
        foreach ($item in $items) {
            $lines += "$padInner$(ConvertTo-P20ConfigJson $item -Depth ($Depth + 1))"
        }
        return "[`n" + ($lines -join ",`n") + "`n$pad]"
    }

    return (ConvertTo-P20JsonString ([string]$Value))
}

function ConvertTo-P20JsonString {
    <#
        One JSON string literal. The escape set is JSON's own minimum -- quote,
        backslash and the C0 controls -- and nothing else: a non-ASCII character
        is written as itself, in UTF-8, which 5.1's ConvertTo-Json would have
        turned into \uXXXX and 7's would not.
    #>
    param([Parameter(Mandatory = $true)][AllowEmptyString()][string]$Text)

    $sb = New-Object System.Text.StringBuilder
    [void]$sb.Append('"')
    foreach ($ch in $Text.ToCharArray()) {
        $code = [int]$ch
        if ($ch -eq '"') { [void]$sb.Append('\"') }
        elseif ($ch -eq '\') { [void]$sb.Append('\\') }
        elseif ($ch -eq "`n") { [void]$sb.Append('\n') }
        elseif ($ch -eq "`r") { [void]$sb.Append('\r') }
        elseif ($ch -eq "`t") { [void]$sb.Append('\t') }
        elseif ($code -eq 8) { [void]$sb.Append('\b') }
        elseif ($code -eq 12) { [void]$sb.Append('\f') }
        elseif ($code -lt 32) { [void]$sb.Append('\u' + $code.ToString('x4')) }
        else { [void]$sb.Append($ch) }
    }
    [void]$sb.Append('"')
    return $sb.ToString()
}

function Write-ConfigJson {
    <#
        Replace a config file with the serialised object, atomically.

        Temp sibling (same directory, so the rename never crosses a volume),
        written through Write-CardText -New for the bytes, then Move-Item -Force
        over the target. The directory is created if it is not there, which is
        how a first config.local.json appears.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Inner helper; the calling verb owns the ShouldProcess decision.')]
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)]$Value
    )

    $dir = Split-Path -Parent $Path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    # Move-Item refuses a Windows 8.3 short path that Test-Path accepts ("An object
    # at the specified path `C:\Users\<name>~1.<domain>` does not exist."), so the folder
    # is named in its long form first. The hub's path already is (Resolve-P20HubPath);
    # config.local.json sits under the package, whose path is wherever the module
    # was imported from. Resolve-HubConfig.ps1 defines the expansion; a
    # caller that dot-sourced only this file writes exactly as before.
    if ($dir -and (Get-Command ConvertTo-P20LongPath -ErrorAction SilentlyContinue)) {
        $longDir = ConvertTo-P20LongPath -Path $dir
        if ($longDir -ne $dir) { $Path = Join-Path $longDir (Split-Path -Leaf $Path) }
    }

    $text = (ConvertTo-P20ConfigJson $Value) + "`n"
    $temp = "$Path.p20tmp"
    Write-CardText -Path $temp -Content $text -New
    Move-Item -LiteralPath $temp -Destination $Path -Force
}
