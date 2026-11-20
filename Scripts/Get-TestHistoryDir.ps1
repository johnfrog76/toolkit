<#
.SYNOPSIS
    Where this machine keeps its test history. Dot-source it.

.DESCRIPTION
    Not a command. One folder per machine, outside every checkout, holds the two
    files a test run leaves behind -- test-summary.<machine>.json and
    test-results.<machine>.log (consts.json tests.summaryFile, tests.resultsFile)
    -- so a run made in any git worktree reaches the System page's Health card,
    whichever checkout the agent runs from.

      Resolve-P20TestHistorySegments  the rule, pure: platform, home and the
                                      variables in, the folder as segments out
                                      ($null for no folder). Held to
                                      Tests/fixtures/test-history/paths.json,
                                      the table agent/core/log.py's
                                      history_segments is held to.
      Get-P20TestHistoryDir           the rule over this process: the folder,
                                      or '' when there is none. With
                                      -PackageRoot, a record that checkout kept
                                      at its root before the folder existed is
                                      copied in, once.
      Get-P20TestHistoryFile          one of the two files in it, by kind.
      Copy-P20LegacyTestHistory       that copy, on its own.

    The rule: env.testHistoryDir when it is set; else, while the run marker
    (env.testRunMarker) is set, no folder at all -- a suite's scratch run never
    writes the machine's real record; else the platform's folder from
    tests.historyBase, historyFallback and historyPath.

.NOTES
    PowerShell 5.1 compatible: ASCII only, no ternary, no null-coalescing.
    Reads no module state.
#>

if (-not (Get-Command Get-P20Consts -ErrorAction SilentlyContinue)) {
    . (Join-Path $PSScriptRoot 'Get-Consts.ps1')
}

function Get-P20TestHistoryPlatform {
    <# windows, macos or linux -- anything that is neither of the first two. #>
    if (($PSVersionTable.PSEdition -eq 'Desktop') -or $IsWindows) { return 'windows' }
    if ($PSVersionTable.PSEdition -ne 'Desktop' -and $IsMacOS) { return 'macos' }
    return 'linux'
}

function Resolve-P20TestHistorySegments {
    <#
      The folder as segments, the first a root (the override, the base variable's
      value or the home folder); $null when there is no folder. -Variables holds
      the environment the rule reads, name -> value; an absent name is unset, and
      a blank value is too.
    #>
    param(
        [Parameter(Mandatory)][string]$Platform,
        [Parameter(Mandatory)][AllowEmptyString()][string]$HomeDir,
        [System.Collections.IDictionary]$Variables = @{}
    )
    $c = Get-P20Consts
    $read = {
        param([string]$Name)
        if (-not $Name -or -not $Variables.Contains($Name)) { return '' }
        $v = $Variables[$Name]
        if ($null -eq $v) { return '' }
        return ([string]$v).Trim()
    }
    $override = & $read ([string]$c.env.testHistoryDir)
    if ($override) { return , @($override) }
    if (& $read ([string]$c.env.testRunMarker)) { return $null }

    $segments = @()
    $baseName = ''
    if ($c.tests.historyBase.PSObject.Properties.Name -contains $Platform) { $baseName = [string]$c.tests.historyBase.$Platform }
    $base = & $read $baseName
    if ($base) { $segments += $base }
    else {
        $segments += $HomeDir
        $segments += @(([string]$c.tests.historyFallback.$Platform).Split('/') | Where-Object { $_ })
    }
    $segments += @(([string]$c.tests.historyPath.$Platform).Split('/') | Where-Object { $_ })
    return , $segments
}

function Get-P20TestHistoryDir {
    <#
      This process's test-history folder, or '' when there is none (the run
      marker is set and no override names one). With -PackageRoot and no
      override, a record that checkout kept at its root is copied in first if
      the folder has none for this machine (Copy-P20LegacyTestHistory).
    #>
    param([string]$PackageRoot)
    $c = Get-P20Consts
    $platform = Get-P20TestHistoryPlatform
    $homeDir = ''
    if ($platform -eq 'windows') { $homeDir = $env:USERPROFILE }
    else { $homeDir = $env:HOME }
    if (-not $homeDir) { $homeDir = [System.Environment]::GetFolderPath('UserProfile') }
    $vars = @{}
    foreach ($name in @([string]$c.env.testHistoryDir, [string]$c.env.testRunMarker)) {
        $vars[$name] = [System.Environment]::GetEnvironmentVariable($name)
    }
    if ($c.tests.historyBase.PSObject.Properties.Name -contains $platform) {
        $baseName = [string]$c.tests.historyBase.$platform
        $vars[$baseName] = [System.Environment]::GetEnvironmentVariable($baseName)
    }
    $segments = Resolve-P20TestHistorySegments -Platform $platform -HomeDir $homeDir -Variables $vars
    if ($null -eq $segments -or $segments.Count -eq 0) { return '' }
    $dir = [string]$segments[0]
    for ($i = 1; $i -lt $segments.Count; $i++) { $dir = Join-Path $dir $segments[$i] }

    $overridden = [string][System.Environment]::GetEnvironmentVariable([string]$c.env.testHistoryDir)
    if ($PackageRoot -and -not $overridden.Trim()) {
        try { $null = Copy-P20LegacyTestHistory -PackageRoot $PackageRoot -Dir $dir } catch { $null = $_ }
    }
    return $dir
}

function Get-P20TestHistoryFileName {
    <# test-summary.<machine>.json or test-results.<machine>.log, from consts.json tests. #>
    param(
        [Parameter(Mandatory)][ValidateSet('summary', 'results')][string]$Kind,
        [string]$Machine = [System.Environment]::MachineName
    )
    $c = Get-P20Consts
    $pattern = [string]$c.tests.summaryFile
    if ($Kind -eq 'results') { $pattern = [string]$c.tests.resultsFile }
    return $pattern.Replace('{machine}', $Machine)
}

function Get-P20TestHistoryFile {
    <# One of the two files in -Dir (default: this process's folder); '' when there is no folder. #>
    param(
        [Parameter(Mandatory)][ValidateSet('summary', 'results')][string]$Kind,
        [string]$Dir,
        [string]$PackageRoot
    )
    if (-not $PSBoundParameters.ContainsKey('Dir')) { $Dir = Get-P20TestHistoryDir -PackageRoot $PackageRoot }
    if (-not $Dir) { return '' }
    return (Join-Path $Dir (Get-P20TestHistoryFileName -Kind $Kind))
}

function Copy-P20LegacyTestHistory {
    <#
      A checkout kept this machine's two files at its own root before the
      history had a folder of its own. Each one -Dir does not have yet is copied
      in from -PackageRoot, so the first read after the move is not "not run";
      once the folder has the file, the old one is never read again. The old
      file is left where it is. Returns the names copied.
    #>
    param(
        [Parameter(Mandatory)][string]$PackageRoot,
        [Parameter(Mandatory)][string]$Dir,
        [string]$Machine = [System.Environment]::MachineName
    )
    $copied = @()
    foreach ($kind in @('summary', 'results')) {
        $name = Get-P20TestHistoryFileName -Kind $kind -Machine $Machine
        $from = Join-Path $PackageRoot $name
        $to = Join-Path $Dir $name
        if (Test-Path -LiteralPath $to) { continue }
        if (-not (Test-Path -LiteralPath $from -PathType Leaf)) { continue }
        if (-not (Test-Path -LiteralPath $Dir)) { New-Item -ItemType Directory -Path $Dir -Force | Out-Null }
        Copy-Item -LiteralPath $from -Destination $to
        $copied += $name
    }
    return , $copied
}
