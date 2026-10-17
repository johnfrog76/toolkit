<#
.SYNOPSIS
    The one list of folders a static sweep must never descend into.

.DESCRIPTION
    Two suites walk the package looking for text in files: Test-PS51Compat
    (5.1 syntax) and Test-Portability (addresses, orgs, secrets, machine
    paths). Both used to build their own file set, and both got the same thing
    wrong from opposite directions -- Compat recursed `web/node_modules` once
    `npm ci` had run, so its total moved with whether a sibling half's
    dependencies were installed; Portability never reached `web/` or `agent/`
    at all. Fixing one without the other would have left two lists to keep in
    step, so the list lives here and both dot-source it.

    What is excluded is vendored or generated: a dependency tree, a build
    output, a virtualenv, git's own store, a bytecode cache. None of it is
    written here and none of it is shipped as source, so a hit inside one is
    noise in either suite.

    A virtualenv is recognised by name (`.venv`, `venv`), which is what
    `.gitignore` pins for this package (`agent/.venv/`). A venv under some
    other name is a venv this package does not know about; put it outside the
    tree or name it one of these two.

    Matching is on whole path segments, at ANY depth. `web` is not excluded,
    `web/node_modules` is -- which is precisely the distinction the top-level
    directory filter could not make.
#>

# Whole directory names. Not substrings: a folder called `distribution` is
# source and stays in the sweep.
$script:ScanExcludedSegments = @(
    'node_modules'      # npm dependency tree -- vendored, thousands of files
    '__pycache__'       # Python bytecode cache
    '.pytest_cache'     # pytest's own scratch
    'dist'              # web build output -- generated from web/src
    '.venv'             # Python virtualenv (see .gitignore: agent/.venv/)
    'venv'              # the other conventional venv name
    '.git'              # git's object store
    '.mypy_cache'
    '.ruff_cache'
    'worktrees'         # .claude/worktrees -- an agent's checkout of this same package, gitignored
)

# The package root: the folder above Tests/. An exclusion is judged on a path
# RELATIVE to this, never on the absolute one, so where the checkout itself
# lives (an agent worktree under .claude/worktrees/, a folder named `dist`)
# never changes what is scanned.
$script:ScanRoot = Split-Path -Parent $PSScriptRoot

function Get-ScanRelativePath {
    <#
    .SYNOPSIS
        A path relative to the package root (or -Root); unchanged if outside it.
    #>
    param(
        [Parameter(Mandatory)][string]$Path,
        [string]$Root
    )

    if (-not $Root) { $Root = $script:ScanRoot }
    $rootFull = [System.IO.Path]::GetFullPath($Root).TrimEnd('\', '/')
    $pathFull = [System.IO.Path]::GetFullPath($Path)
    $sep = [System.IO.Path]::DirectorySeparatorChar
    if ($pathFull.Length -gt $rootFull.Length -and
        $pathFull.StartsWith($rootFull + $sep, [System.StringComparison]::OrdinalIgnoreCase)) {
        return $pathFull.Substring($rootFull.Length + 1)
    }
    return $Path
}

function Test-ScanExcluded {
    <#
    .SYNOPSIS
        True when a path runs through a vendored or generated folder INSIDE
        the package.
    .DESCRIPTION
        Splits the root-relative path on both separators so the answer is the
        same on Windows and macOS, and compares whole segments.
    #>
    param(
        [Parameter(Mandatory)][string]$Path,
        [string]$Root
    )

    $rel = Get-ScanRelativePath -Path $Path -Root $Root
    foreach ($seg in ($rel -split '[\\/]')) {
        if ($script:ScanExcludedSegments -contains $seg) { return $true }
    }
    return $false
}

function Select-ScannableFile {
    <#
    .SYNOPSIS
        Drops anything under an excluded folder from a list of FileInfo.
    #>
    param(
        [Parameter(ValueFromPipeline)]$File,
        [string]$Root
    )

    process {
        if ($null -eq $File) { return }
        if (-not (Test-ScanExcluded -Path $File.FullName -Root $Root)) { $File }
    }
}
