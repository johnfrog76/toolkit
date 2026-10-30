<#
.SYNOPSIS
    Where a Space's own repository is checked out on this machine, if anywhere.
.DESCRIPTION
    A Space's address names its repository (Resolve-P20TrackerRepo,
    Resolve-Tracker.ps1); this asks whether a clone of it is here. The
    candidates, in order:

      1. the Space's CONFIGURED checkout -- spaceCheckouts.<slug>.path in
         config.local.json, this machine's own answer to "where is it here",
         written by Config -Set (Get-P20ConfiguredCheckout). Machine-scoped on
         purpose: the hub syncs between machines whose clones sit in different
         places, so a path never goes in hub.json.
      2. the caller's own candidates -- MoveDesign and NewPR pass the folder
         you stand in first, then the nav shortcuts' paths (aliases.<Name>.path,
         the toolkit's existing record of where things live on this machine,
         which the agent's stress-repos read uses for the same question).
      3. <wsRoot>/<repo>, the machine's workspace root (WS_ROOT, which the
         module exports from config) joined with the repository's own name.

    Get-P20SpaceCheckoutCandidates builds the folder-you-stand-in-and-nav-
    shortcuts half of 2; the caller passes the configured path as -Configured
    and its own candidates as -Candidates. A candidate counts only when it is
    inside a git repository whose origin IS the Space's repository
    (Get-P20GitHubOriginRepo, the rule StartWork -Launch holds a clone to), so
    a folder that merely shares a name never answers -- the configured path
    included: a setting that points at the wrong clone is named in the
    result's ConfiguredReason and passed over.

    Returns a hashtable:
        Root              the clone's top level, or '' when none was found
        Repo              'owner/name' when the address names one, else ''
        Source            'configured' when Root came from the setting, 'found'
                          when from a candidate or wsRoot, '' when none was found
        Reason            why there is no Root, in words a refusal or a note can print
        ConfiguredReason  why the configured path was passed over ('' when it
                          was not set, or was used)

    A Space whose tracker is not GitHub, or whose address names no single
    repository, has no Root and says so; the caller decides what that means.
    Every git call goes through Invoke-P20TrackerRead (AGENTS.md, "Traps worth
    knowing"), which the caller dot-sources, with Resolve-Tracker.ps1.

    The agent asks the same question of the configured path alone, for the
    Design tab's rows (agent/core/checkout.py): one candidate and the same
    origin rule, held to this one by Tests/fixtures/space-checkout/table.json.
    It never searches.

    PowerShell 5.1 compatible (ASCII only). Resolve-P20SpaceCheckout reads no
    module state; the helpers read $global:P20Config and the nav table.
#>

function Get-P20SpaceCheckoutKey {
    # The one spelling of the setting, for a refusal, a note or Config -Set.
    param([string]$Slug)
    return "spaceCheckouts.$Slug.path"
}

function ConvertTo-P20CheckoutPath {
    # A configured path as written: absolute, or ~ for the home folder. A
    # relative path has nothing on this machine to be relative to, so it is ''.
    param([AllowEmptyString()][AllowNull()][string]$Path)
    $p = "$Path".Trim()
    if (-not $p) { return '' }
    if ($p -eq '~' -or $p.StartsWith('~/') -or $p.StartsWith('~\')) {
        $rest = $p.Substring(1).TrimStart('/', '\')
        if ($rest) { return (Join-Path $HOME $rest) }
        return $HOME
    }
    if (-not [System.IO.Path]::IsPathRooted($p)) { return '' }
    return $p
}

function Get-P20ConfiguredCheckout {
    <#
      The path spaceCheckouts.<slug>.path names on this machine, as written
      ('' when none), read from the merged config ($global:P20Config's
      SpaceCheckouts, which utilities.psm1 takes from config.local.json and
      nowhere else).
    #>
    param([string]$Slug, $Config = $null)
    if (-not $Slug) { return '' }
    if ($null -eq $Config) { $Config = $global:P20Config }
    if (-not $Config) { return '' }
    $table = $null
    if ($Config -is [System.Collections.IDictionary]) { $table = $Config['SpaceCheckouts'] }
    elseif ($Config.PSObject.Properties['SpaceCheckouts']) { $table = $Config.SpaceCheckouts }
    if (-not $table) { return '' }
    $entry = $null
    if ($table -is [System.Collections.IDictionary]) { $entry = $table[$Slug] }
    elseif ($table.PSObject.Properties[$Slug]) { $entry = $table.$Slug }
    if (-not $entry) { return '' }
    if ($entry -is [System.Collections.IDictionary]) { return [string]$entry['path'] }
    if ($entry.PSObject.Properties['path']) { return [string]$entry.path }
    return ''
}

function Get-P20SpaceCheckoutCandidates {
    <#
      The searched candidates, after the configured one: the folder you stand
      in, then every nav shortcut's path, in name order.
    #>
    $candidates = @((Get-Location).Path)
    $navAliases = $null
    if (Get-Command Get-P20NavAliases -ErrorAction SilentlyContinue) { $navAliases = Get-P20NavAliases }
    if ($navAliases) {
        foreach ($key in @($navAliases.Keys | Sort-Object)) {
            $entry = $navAliases[$key]
            $aliasPath = ''
            if ($entry -is [System.Collections.IDictionary]) { $aliasPath = [string]$entry['path'] }
            elseif ($entry -and $entry.PSObject.Properties['path']) { $aliasPath = [string]$entry.path }
            if ($aliasPath) { $candidates += $aliasPath }
        }
    }
    return @($candidates)
}

<#
 The nav shortcuts' paths (aliases.<Name>.path), in name order -- the candidates
 MoveDesign and NewPR hand Resolve-P20SpaceCheckout. Takes the table
 Get-P20NavAliases returns (entries are hashtables or objects with a path);
 $null or empty gives an empty list.
#>
function Get-P20NavAliasPaths {
    param($NavAliases)
    $paths = @()
    if (-not $NavAliases) { return $paths }
    foreach ($key in @($NavAliases.Keys | Sort-Object)) {
        $entry = $NavAliases[$key]
        $aliasPath = ''
        if ($entry -is [System.Collections.IDictionary]) { $aliasPath = [string]$entry['path'] }
        elseif ($entry -and $entry.PSObject.Properties['path']) { $aliasPath = [string]$entry.path }
        if ($aliasPath) { $paths += $aliasPath }
    }
    return $paths
}

function Test-P20CheckoutCandidate {
    # The top level of the clone $Path is in when its origin is $Repo; else
    # Top is '' and Why says why, in words a note can print.
    param([string]$Path, [string]$Repo)
    $out = @{ Top = ''; Why = '' }
    if (-not (Test-Path -LiteralPath $Path -PathType Container)) { $out.Why = 'that is not a folder on this machine'; return $out }
    $topRead = Invoke-P20TrackerRead 'git' @('-C', $Path, 'rev-parse', '--show-toplevel')
    $top = ''
    if ($topRead.Code -eq 0) { $top = ([string](@($topRead.Out | Where-Object { "$_".Trim() }) | Select-Object -First 1)).Trim() }
    if (-not $top) { $out.Why = 'it is not inside a git repository'; return $out }
    $top = [System.IO.Path]::GetFullPath($top)
    $originRead = Invoke-P20TrackerRead 'git' @('-C', $top, 'remote', 'get-url', 'origin')
    $originUrl = ''
    if ($originRead.Code -eq 0) { $originUrl = ([string](@($originRead.Out) | Select-Object -First 1)).Trim() }
    $originRepo = Get-P20GitHubOriginRepo -Url $originUrl
    if ($originRepo -ine $Repo) {
        if ($originRepo) { $out.Why = "it is a clone of $originRepo, not $Repo" }
        else { $out.Why = "its origin is not on GitHub, so it is not a clone of $Repo" }
        return $out
    }
    $out.Top = $top
    return $out
}

function Resolve-P20SpaceCheckout {
    param(
        [AllowEmptyString()][AllowNull()][string]$OrgUrl,
        $Projects,
        [AllowEmptyString()][AllowNull()][string]$Configured = '',
        [string]$ConfiguredKey = '',
        [string[]]$Candidates = @(),
        # The machine's wsRoot. Defaults to WS_ROOT, which the module exports
        # from config; passed explicitly only by a caller that holds its own.
        [AllowEmptyString()][AllowNull()][string]$WsRoot = $env:WS_ROOT
    )
    $result = @{ Root = ''; Repo = ''; Source = ''; Reason = ''; ConfiguredReason = '' }
    if ((Resolve-P20Tracker -OrgUrl $OrgUrl) -ne 'github') {
        $result.Reason = 'its address is not a GitHub repository, so there is no clone to look for'
        return $result
    }
    $target = Resolve-P20TrackerRepo -OrgUrl $OrgUrl -Projects $Projects
    if (-not $target.Repo) {
        $result.Reason = "its address names no single repository ($($target.Reason))"
        return $result
    }
    $result.Repo = [string]$target.Repo
    $keyWords = 'the configured checkout'
    if ($ConfiguredKey) { $keyWords = $ConfiguredKey }
    # 1. The configured checkout: this machine said where the clone is.
    if ("$Configured".Trim()) {
        $path = ConvertTo-P20CheckoutPath $Configured
        if (-not $path) {
            $result.ConfiguredReason = "$keyWords is '$Configured', which is neither an absolute path nor under ~"
        }
        else {
            $hit = Test-P20CheckoutCandidate -Path $path -Repo $result.Repo
            if ($hit.Top) {
                $result.Root = $hit.Top
                $result.Source = 'configured'
                return $result
            }
            $result.ConfiguredReason = "$keyWords is $path, but $($hit.Why)"
        }
    }
    # 2. The caller's own candidates (the folder you stand in, the nav
    #    shortcuts' paths), then 3. <wsRoot>/<repo>.
    $all = @($Candidates)
    $wsCandidate = ''
    if ("$WsRoot".Trim()) {
        $wsCandidate = Join-Path "$WsRoot".Trim() ($result.Repo.Split('/')[1])
        $all += $wsCandidate
    }
    foreach ($candidate in $all) {
        $c = "$candidate".Trim()
        if (-not $c) { continue }
        $hit = Test-P20CheckoutCandidate -Path $c -Repo $result.Repo
        if (-not $hit.Top) { continue }
        $result.Root = $hit.Top
        $result.Source = 'found'
        return $result
    }
    # Every place asked, named -- the caller's own and wsRoot's -- so the
    # reason reads the same whoever printed it.
    $asked = @($all | ForEach-Object { "$_".Trim() } | Where-Object { $_ } | Select-Object -Unique)
    $where = 'there was no folder to look in, and no wsRoot set'
    if ($asked.Count -gt 0) { $where = 'looked in ' + ($asked -join ', ') }
    if ("$Configured".Trim()) {
        $result.Reason = "no clone of $($result.Repo) was found on this machine ($($result.ConfiguredReason); $where)"
    }
    else {
        $result.Reason = "no clone of $($result.Repo) was found on this machine ($keyWords is not set; $where)"
    }
    return $result
}
