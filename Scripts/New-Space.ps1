<#
.SYNOPSIS
    NewSpace -- add a Space: a GitHub repository, an Azure DevOps organisation,
    or your own cards with no tracker.
.DESCRIPTION
    The one easy way to declare a Space. Someone who knows only which repository
    they want types `NewSpace -Repo owner/name` (or presses the + on the Studio's
    Spaces card, which runs this verb through the bridge) and gets a Space that is
    right the first time: a slug, a display name, an address, a status and a cards
    folder.

    EVERY KEY IS WRITTEN THROUGH Config (Scripts/Set-ToolkitConfig.ps1, the one
    writer), in one in-process call with -Hub -- the same call Connect makes. This
    script never writes a JSON file. A refusal there is a refusal here, with its
    own sentence and exit code.

    The three forms:
      -Repo owner/name      a GitHub Space -- one repository; status active
      <slug> -Address <url> an Azure DevOps Space -- an organisation; status active.
                            Its projects are Connect's step 3 (Connect <slug> -Discover)
      <slug>                your own cards, no tracker; status local

    The cards folder is <hub>/<slug>, with current/ and archive/. A folder that is
    already there is ADOPTED and never touched -- removing a Space never deletes its
    folder, so adding it again brings its cards back -- and the output says
    how many cards it found.

    It does NOT switch to the new Space; its last line is the command that does.
    -Discover lists the signed-in account's repositories for the + dialog's picker,
    each with the exact NewSpace line that adds it; -Owner lists an organisation's,
    or (-Owner collaborator) the repositories shared with you. A repository
    you can read and not write is marked READ-ONLY, the way an archived one is.
.PARAMETER Slug
    The Space's slug: lowercase letters, digits and dashes, starting with a letter.
    Defaults to the repository's name for -Repo; required otherwise.
.PARAMETER Repo
    owner/name of a GitHub repository (a pasted https://github.com/owner/name works too).
.PARAMETER Address
    An Azure DevOps organisation's address, https://dev.azure.com/<org>.
.PARAMETER Name
    The display name. Defaults to the repository's name, title-cased, dashes as
    spaces; for the other forms, the slug the same way.
.PARAMETER Discover
    List your repositories (gh repo list), marking the ones that are already Spaces.
    A list is read to 1000 repositories; past that the first 1000 are listed and
    the answer says there are more. With -Repo: that one repository, its
    visibility read before it is added, or 'not visible to this login'.
.PARAMETER Owner
    With -Discover: whose repositories to list -- a user or an organisation
    (gh repo list <owner>), or the word collaborator for the ones shared with you
    (gh api user/repos, affiliation collaborator). Without it, your own.
.PARAMETER AsJson
    One JSON object -- the bridge's form.
.PARAMETER WhatIf
    Say every key it would write and the folder it would make; write nothing.
.NOTES
    PowerShell 5.1 compatible (ASCII only).
#>
[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [string]$Slug,
    [string]$Repo,
    [string]$Address,
    [string]$Name,
    [switch]$Discover,
    [string]$Owner,
    [switch]$AsJson,
    [switch]$WhatIf,
    [switch]$Help
)

$ErrorActionPreference = 'Stop'
$scriptsDir = $PSScriptRoot
$packageRoot = Split-Path $scriptsDir -Parent

# Dot-sourced through a scriptblock and re-run after the write: the Config writer
# re-imports the module, which resets every function a script defined (AGENTS.md,
# "Traps worth knowing"). Local variables -- scriptblocks included -- survive.
$loadHelpers = {
    foreach ($helper in @('Resolve-CliPrefix.ps1', 'Resolve-Tracker.ps1', 'Invoke-TrackerRead.ps1', 'Test-TrackerSignIn.ps1', 'Resolve-HubConfig.ps1')) {
        . (Join-Path $scriptsDir $helper)
    }
}
. $loadHelpers
. (Join-Path $PSScriptRoot 'Initialize-CliFallbacks.ps1')
$prefix = ''
if (Get-Command Get-CliPrefix -ErrorAction SilentlyContinue) { $prefix = Get-CliPrefix }
if (-not $prefix) { $prefix = Resolve-P20ConfigPrefix -PackageRoot $packageRoot }

$usageLine = "${prefix}NewSpace [<slug>] [-Repo <owner/name>] [-Address <url>] [-Name <text>] [-Discover] [-Owner <owner>] [-AsJson] [-WhatIf]"
if ($Help) {
    Write-Host ""
    Write-Host "  ${prefix}NewSpace -- add a Space" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "    $usageLine"
    Write-Host ""
    Write-Host "    ${prefix}NewSpace -Repo owner/name                          a GitHub repository; the slug and name come from it"
    Write-Host "    ${prefix}NewSpace <slug> -Address https://dev.azure.com/<org>  an Azure DevOps organisation"
    Write-Host "    ${prefix}NewSpace <slug>                                    your own cards, no tracker"
    Write-Host "    ${prefix}NewSpace -Discover                                 your repositories, each with the line that adds it"
    Write-Host "    ${prefix}NewSpace -Discover -Owner <org>                    an organisation's; -Owner collaborator: shared with you"
    Write-Host "    ${prefix}NewSpace -Discover -Repo owner/name                one repository, its visibility read before it is added"
    Write-Host ""
    Write-Host "  Writes through Config, makes <hub>/<slug>/current and archive (an existing folder is adopted,"
    Write-Host "  never touched), and does not switch: its last line is the ${prefix}SwitchSpace that does."
    Write-Host ""
    exit 0
}

# -- The rules this verb owns ---------------------------------------------------
# A slug: the rule Connect -As already holds (lowercase letters, digits and dashes,
# starting with a letter). The proposals from a repository's name: the slug is the
# name lowercased with every run of anything else one dash; the display name is the
# name with dashes, underscores and dots as spaces and each word's first letter
# capitalised. The web's mirror is web/src/modules/studio/newSpace.ts, held to this
# one by Tests/fixtures/spaces/proposals.json (Test-NewSpace and newSpace.test.ts).
$slugPattern = '^[a-z][a-z0-9-]*$'
$proposeSlug = {
    param([string]$Text)
    return ((([string]$Text).ToLowerInvariant() -replace '[^a-z0-9]+', '-').Trim('-'))
}
$proposeName = {
    param([string]$Text)
    $words = @((([string]$Text) -replace '[-_.]+', ' ').Trim() -split '\s+' | Where-Object { $_ })
    $out = @()
    foreach ($w in $words) { $out += ($w.Substring(0, 1).ToUpperInvariant() + $w.Substring(1)) }
    return ($out -join ' ')
}
# A pasted address is a familiar thing to paste: https://github.com/owner/name(.git)
# reads as owner/name. Anything else is kept as typed and checked below.
$normaliseRepo = {
    param([string]$Text)
    $r = ([string]$Text).Trim()
    $r = $r -replace '^(?i)(https?://)?(www\.)?github\.com/', ''
    $r = $r.Trim('/')
    $r = $r -replace '(?i)\.git$', ''
    return $r
}
# A repository you can read and not write: gh's viewerPermission, or the
# REST permissions the collaborator listing carries. ADMIN, MAINTAIN and WRITE can
# push; TRIAGE and READ cannot. Unknown -- a check that did not run, a gh that did
# not say -- is not marked.
$writePermissions = @('ADMIN', 'MAINTAIN', 'WRITE')
$isReadOnly = {
    param([string]$Permission)
    $p = ([string]$Permission).ToUpperInvariant()
    return [bool]($p -and ($writePermissions -notcontains $p))
}
$restPermission = {
    param($Perms)
    if (-not $Perms) { return '' }
    if ($Perms.admin) { return 'ADMIN' }
    if ($Perms.maintain) { return 'MAINTAIN' }
    if ($Perms.push) { return 'WRITE' }
    if ($Perms.triage) { return 'TRIAGE' }
    if ($Perms.pull) { return 'READ' }
    return ''
}
# A JSON list from gh, read through a variable: Windows PowerShell 5.1's
# ConvertFrom-Json writes a JSON array as ONE object, which @(...) around the pipe
# would wrap whole. Throws when it is not JSON; the caller says so.
$readList = {
    param($Raw)
    $decoded = (($Raw | Out-String) | ConvertFrom-Json)
    $items = @()
    foreach ($item in $decoded) { if ($null -ne $item) { $items += $item } }
    return $items
}
# -Owner's one word that is not an owner: the repositories shared with you.
$collaboratorOwner = 'collaborator'
$ownerPattern = '^[A-Za-z0-9][A-Za-z0-9-]*$'
$repoPattern = '^[A-Za-z0-9][A-Za-z0-9-]*/[A-Za-z0-9._-]+$'
# How far -Discover reads one list -- an owner's repositories, the ones shared with
# you, your organisations -- and what it says past it (docs/modules/studio.md,
# "The verbs"). gh repo list is asked for one more than the ceiling,
# and a REST list is read a page of 100 at a time until a short page or the
# ceiling, so a list longer than the ceiling is known to be longer, not guessed.
$listCeiling = 1000
$pageSize = 100
# A repository gh cannot see: the visibility the contract has for "did not answer"
# (consts.json visibility.unknown), as gh's own upper case, and what that means.
if (-not (Get-Command Get-P20Consts -ErrorAction SilentlyContinue)) { . (Join-Path $scriptsDir 'Get-Consts.ps1') }
$unknownVisibility = ([string](Get-P20Consts).visibility.unknown).ToUpperInvariant()
$notVisible = 'not visible to this login'
$readPages = {
    param([string]$Path, [string[]]$Fields)
    $all = @()
    $page = 1
    while ($true) {
        $pageArgs = @('api', $Path, '-X', 'GET') + @($Fields) + @('-f', "per_page=$pageSize", '-f', "page=$page")
        $read = Invoke-P20TrackerRead 'gh' $pageArgs
        if ($read.Code -ne 0) { return @{ Ok = $false; Read = $read; Items = @(); More = $false } }
        $batch = @(& $readList ($read.Out -join "`n"))
        $all += $batch
        if ($batch.Count -lt $pageSize -or $all.Count -gt $listCeiling) { break }
        $page++
    }
    $more = ($all.Count -gt $listCeiling)
    if ($more) { $all = @($all[0..($listCeiling - 1)]) }
    return @{ Ok = $true; Read = $null; Items = $all; More = $more }
}

# -- The Spaces this machine knows ----------------------------------------------
# The module's resolved list when the verb ran us; the shipped config plus the
# hub's declarations when run alone (the read Connect makes).
$spaces = @()
$hubRoot = ''
if ($global:P20Config -and $global:P20Config.Spaces) {
    $spaces = @($global:P20Config.Spaces)
    $hubRoot = [string]$global:P20Config.PromptsRoot
}
else {
    $defaultCfg = ConvertTo-P20SpaceKeys (Get-Content (Join-Path $packageRoot 'config.default.json') -Raw | ConvertFrom-Json)
    $spaces = @($defaultCfg.spaces)
    $hubRoot = Get-P20PromptsRoot -PackageRoot $packageRoot
    if ($hubRoot -and (Test-P20HubRoot $hubRoot)) {
        $manifest = Read-P20HubManifest -Root $hubRoot
        foreach ($hs in @(Rename-P20LegacyHubSpaces -Spaces @($manifest.Spaces) -ShippedSlugs @($spaces | ForEach-Object { [string]$_.slug }))) {
            if (-not (@($spaces | Where-Object { $_.slug -eq $hs.slug }).Count)) { $spaces += $hs }
        }
    }
}
if ($env:PROMPTS_ROOT) { $hubRoot = Get-P20PromptsRoot -PackageRoot $packageRoot }
$knownSlugs = @($spaces | ForEach-Object { [string]$_.slug })
$spaceLabel = { param($s) $n = [string]$s.name; if (-not $n) { $n = [string]$s.slug }; return "$n ($($s.slug))" }

# Every GitHub repository a declared Space IS, lowercased owner/name -> the Space.
$repoOwners = @{}
foreach ($s in $spaces) {
    if ((Resolve-P20Tracker -OrgUrl ([string]$s.org)) -ne 'github') { continue }
    foreach ($r in @(Get-P20TrackerRepos -OrgUrl ([string]$s.org) -Projects $s.projects)) {
        $key = ([string]$r).ToLowerInvariant()
        if (-not $repoOwners.ContainsKey($key)) { $repoOwners[$key] = $s }
    }
}

# -- -Owner belongs to -Discover ---------------------------------------------------
$ownerGiven = ([string]$Owner).Trim()
if ($ownerGiven -and -not $Discover) {
    Write-CliError -Message '-Owner says whose repositories -Discover lists; it does not add a Space.' -Hint "${prefix}NewSpace -Discover -Owner <owner> lists them; ${prefix}NewSpace -Repo <owner>/<name> adds one."
    exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
}

# -- -Discover: your repositories, for the picker ----------------------------------
# With -Owner: a user's or an organisation's (gh repo list <owner>), or --
# the word collaborator -- the ones shared with you (gh api user/repos with
# affiliation=collaborator as an -f field: never a & in a URL, which cmd.exe splits).
# With -Repo: that one repository, read before it is added (gh repo view), so its
# visibility is said first -- and a repository this login cannot see says so.
if ($Discover) {
    $isCollaborator = ($ownerGiven -ieq $collaboratorOwner)
    $oneRepo = ''
    if ($PSBoundParameters.ContainsKey('Repo') -and ([string]$Repo).Trim()) {
        if ($ownerGiven) {
            Write-CliError -Message '-Discover reads one owner''s repositories or one repository, not both: give -Owner or -Repo.' -Hint "${prefix}NewSpace -Discover -Owner <owner> lists an owner's; ${prefix}NewSpace -Discover -Repo <owner>/<name> reads one."
            exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
        }
        $oneRepo = & $normaliseRepo $Repo
        if ($oneRepo -notmatch $repoPattern) {
            Write-CliError -Message "'$Repo' is not owner/name." -Hint "For example johnfrog76/toolkit. ${prefix}NewSpace -Discover lists yours."
            exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
        }
    }
    if ($ownerGiven -and -not $isCollaborator -and $ownerGiven -notmatch $ownerPattern) {
        Write-CliError -Message "'$ownerGiven' is not an owner." -Hint "A GitHub user or organisation is letters, digits and dashes; -Owner $collaboratorOwner lists the repositories shared with you. ${prefix}NewSpace -Discover names the owners you can choose."
        exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
    }
    $owners = @()
    $account = ''
    $unavailable = {
        param([string]$Why, [string]$Hint)
        if ($AsJson) {
            [ordered]@{ available = $false; reason = $Why; hint = $Hint; account = [string]$account; owner = $ownerGiven; owners = @($owners); ceiling = $listCeiling; more = $false; repos = @() } | ConvertTo-Json -Depth 4 -Compress
            exit 0
        }
        Write-CliError -Message $Why -Hint $Hint
        exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
    }
    $typeIt = "Or name the repository yourself: ${prefix}NewSpace -Repo owner/name"
    $signIn = Test-P20TrackerSignIn -Tracker 'github'
    $cannot = 'Your repositories cannot be listed'
    if ($oneRepo) { $cannot = "$oneRepo cannot be read" }
    if (-not $signIn.Installed) { & $unavailable "${cannot}: gh, the GitHub CLI, is not installed." "Install gh and run gh auth login. $typeIt" }
    if (-not $signIn.SignedIn) { & $unavailable "${cannot}: gh is not signed in." "Run gh auth login yourself -- the toolkit never signs in for you. $typeIt" }
    $account = [string]$signIn.Identity

    # One row of the picker, from what gh said of a repository (gh's shape, or the
    # REST shape the collaborator listing carries).
    $toRow = {
        param($r, [bool]$Rest, [string]$Note)
        $rOwner = ''
        if ($r.owner -and $r.owner.login) { $rOwner = [string]$r.owner.login }
        $archived = [bool]$r.isArchived
        $permission = ([string]$r.viewerPermission).ToUpperInvariant()
        if ($Rest) {
            $archived = [bool]$r.archived
            $permission = & $restPermission $r.permissions
        }
        $full = "$rOwner/$($r.name)"
        $held = $repoOwners[$full.ToLowerInvariant()]
        return [PSCustomObject][ordered]@{
            repo             = $full
            name             = [string]$r.name
            owner            = $rOwner
            visibility       = ([string]$r.visibility).ToUpperInvariant()
            isArchived       = $archived
            viewerPermission = $permission
            readOnly         = (& $isReadOnly $permission)
            description      = [string]$r.description
            proposedSlug     = (& $proposeSlug ([string]$r.name))
            proposedName     = (& $proposeName ([string]$r.name))
            space            = $(if ($held) { [string]$held.slug } else { '' })
            spaceName        = $(if ($held) { [string]$held.name } else { '' })
            command          = "${prefix}NewSpace -Repo $full"
            note             = $Note
        }
    }

    $rows = @()
    $more = $false
    if ($oneRepo) {
        # The one read the Add makes, made first. A repository gh cannot see is a row
        # all the same -- its visibility unknown and the reason said -- because it can
        # still be added: a Space's cards do not need the tracker to answer.
        $viewed = Invoke-P20TrackerRead 'gh' @('repo', 'view', $oneRepo, '--json', 'name,owner,visibility,isArchived,description,viewerPermission')
        $view = $null
        $why = ''
        if ($viewed.Code -eq 0) {
            try { $view = (($viewed.Out | Out-String) | ConvertFrom-Json) } catch { $view = $null }
            if (-not $view -or -not $view.visibility) { $view = $null; $why = 'gh answered with something that is not JSON' }
        }
        else {
            $first = @($viewed.Lines | ForEach-Object { ([string]$_).Trim() } | Where-Object { $_ })[0]
            $why = "gh answered '$first'"
        }
        $parts = $oneRepo.Split('/')
        if ($view) {
            # gh names the repository as GitHub spells it; a view without them keeps the typed one.
            if (-not $view.name) { $view | Add-Member -NotePropertyName name -NotePropertyValue $parts[1] -Force }
            if (-not ($view.owner -and $view.owner.login)) { $view | Add-Member -NotePropertyName owner -NotePropertyValue ([PSCustomObject]@{ login = $parts[0] }) -Force }
            $rows += (& $toRow $view $false '')
        }
        else {
            $ghost = [PSCustomObject]@{ name = $parts[1]; owner = [PSCustomObject]@{ login = $parts[0] }; visibility = $unknownVisibility }
            $rows += (& $toRow $ghost $false "${notVisible}: $why")
        }
        if ($AsJson) {
            [ordered]@{ available = $true; reason = ''; hint = ''; account = $account; owner = $parts[0]; owners = @(); ceiling = $listCeiling; more = $false; repos = $rows } | ConvertTo-Json -Depth 4 -Compress
            exit 0
        }
        $row = $rows[0]
        Write-Host ""
        Write-Host "  $($row.repo)$(if ($account) { " -- read by gh as $account" })" -ForegroundColor Cyan
        $mark = ''
        if ($row.isArchived) { $mark += 'ARCHIVED ' }
        if ($row.readOnly) { $mark += 'READ-ONLY ' }
        if ($row.space) {
            Write-Host ("    {0,-8} {1}already a Space: {2}" -f $row.visibility.ToLowerInvariant(), $mark, (& $spaceLabel ($spaces | Where-Object { $_.slug -eq $row.space } | Select-Object -First 1))) -ForegroundColor DarkGray
        }
        else {
            Write-Host ("    {0,-8} {1}{2}" -f $row.visibility.ToLowerInvariant(), $mark, $row.command)
        }
        if ($row.note) { Write-Host "    $($row.note) -- it can still be added, and is added unchecked." -ForegroundColor Yellow }
        Write-Host ""
        exit 0
    }

    # The owners you can choose: you, the organisations you belong to, and the
    # repositories shared with you. Asked, never required: a gh that cannot list
    # your organisations leaves you and collaborator.
    if ($account) { $owners += [ordered]@{ value = $account; label = "$account (yours)"; kind = 'user' } }
    $orgs = @()
    try {
        $orgsRead = & $readPages 'user/orgs' @()
        if ($orgsRead.Ok) { $orgs = @($orgsRead.Items) }
    } catch { $orgs = @() }
    foreach ($o in $orgs) {
        if ($o -and $o.login) { $owners += [ordered]@{ value = [string]$o.login; label = [string]$o.login; kind = 'organization' } }
    }
    $owners += [ordered]@{ value = $collaboratorOwner; label = 'Collaborator'; kind = 'collaborator' }

    $whose = 'Your repositories'
    if ($isCollaborator) { $whose = 'The repositories shared with you' }
    elseif ($ownerGiven) { $whose = "The repositories of '$ownerGiven'" }
    $checkOwner = ''
    if ($ownerGiven -and -not $isCollaborator) { $checkOwner = "Check the owner's name: ${prefix}NewSpace -Discover names the owners you can choose. " }
    $parsed = @()
    if ($isCollaborator) {
        $listed = $null
        try { $listed = & $readPages 'user/repos' @('-f', 'affiliation=collaborator') }
        catch { & $unavailable "$whose cannot be listed: gh answered with something that is not JSON." $typeIt }
        if (-not $listed.Ok) {
            $first = @($listed.Read.Lines | ForEach-Object { ([string]$_).Trim() } | Where-Object { $_ })[0]
            & $unavailable "$whose cannot be listed: gh answered '$first'." "$checkOwner$typeIt"
        }
        $parsed = @($listed.Items)
        $more = [bool]$listed.More
    }
    else {
        $ghArgs = @('repo', 'list')
        if ($ownerGiven) { $ghArgs += $ownerGiven }
        $ghArgs += @('--json', 'name,owner,visibility,isArchived,description,viewerPermission', '--limit', [string]($listCeiling + 1))
        $listRead = Invoke-P20TrackerRead 'gh' $ghArgs
        if ($listRead.Code -ne 0) {
            $first = @($listRead.Lines | ForEach-Object { ([string]$_).Trim() } | Where-Object { $_ })[0]
            & $unavailable "$whose cannot be listed: gh answered '$first'." "$checkOwner$typeIt"
        }
        try { $parsed = @(& $readList ($listRead.Out -join "`n")) } catch { & $unavailable "$whose cannot be listed: gh answered with something that is not JSON." $typeIt }
        if ($parsed.Count -gt $listCeiling) { $parsed = @($parsed[0..($listCeiling - 1)]); $more = $true }
    }
    foreach ($r in $parsed) {
        if (-not $r -or -not $r.name) { continue }
        $rows += (& $toRow $r $isCollaborator '')
    }
    $rows = @($rows | Sort-Object { $_.repo.ToLowerInvariant() })
    $listedOwner = $ownerGiven
    if (-not $listedOwner) { $listedOwner = $account }
    if ($AsJson) {
        [ordered]@{ available = $true; reason = ''; hint = ''; account = $account; owner = $listedOwner; owners = @($owners); ceiling = $listCeiling; more = $more; repos = $rows } | ConvertTo-Json -Depth 4 -Compress
        exit 0
    }
    Write-Host ""
    Write-Host "  $whose$(if ($account) { " -- signed in to gh as $account" }): $($rows.Count)$(if ($more) { " (the first $listCeiling)" })" -ForegroundColor Cyan
    foreach ($row in $rows) {
        $vis = $row.visibility.ToLowerInvariant()
        # GitHub-archived and read-only: marked, never hidden -- the
        # Space's status is the engineer's word, and a repository you can only read
        # is still one you can keep cards for.
        $mark = ''
        if ($row.isArchived) { $mark += 'ARCHIVED ' }
        if ($row.readOnly) { $mark += 'READ-ONLY ' }
        if ($row.space) {
            Write-Host ("    {0,-40} {1,-8} {2}already a Space: {3}" -f $row.repo, $vis, $mark, (& $spaceLabel ($spaces | Where-Object { $_.slug -eq $row.space } | Select-Object -First 1))) -ForegroundColor DarkGray
        }
        else {
            Write-Host ("    {0,-40} {1,-8} {2}{3}" -f $row.repo, $vis, $mark, $row.command)
        }
    }
    if ($more) {
        Write-Host ""
        Write-Host "  The first $listCeiling are listed and there are more. For one past them, ${prefix}NewSpace -Discover -Repo <owner>/<name> reads it and ${prefix}NewSpace -Repo <owner>/<name> adds it." -ForegroundColor Yellow
    }
    Write-Host ""
    $ownerWords = @($owners | ForEach-Object { if ($_.kind -eq 'user') { "$($_.value) (yours)" } else { [string]$_.value } })
    Write-Host "  Owners: $($ownerWords -join ', ') -- ${prefix}NewSpace -Discover -Owner <one>" -ForegroundColor DarkGray
    Write-Host ""
    exit 0
}

# -- The form -----------------------------------------------------------------
$hasRepo = $PSBoundParameters.ContainsKey('Repo') -and ([string]$Repo).Trim()
$hasAddress = $PSBoundParameters.ContainsKey('Address') -and ([string]$Address).Trim()
if (-not $hasRepo -and -not $hasAddress -and -not ([string]$Slug).Trim()) {
    Write-CliError -Message "Say which Space: ${prefix}NewSpace -Repo owner/name for a GitHub repository, ${prefix}NewSpace <slug> -Address https://dev.azure.com/<org> for an Azure DevOps organisation, or ${prefix}NewSpace <slug> for your own cards." `
        -Hint "${prefix}NewSpace -Discover lists your repositories, each with the line that adds it."
    exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
}
if ($hasRepo -and $hasAddress) {
    Write-CliError -Message 'A Space is one repository or one organisation, not both: give -Repo or -Address.' -Hint "-Repo owner/name for GitHub; <slug> -Address https://dev.azure.com/<org> for Azure DevOps."
    exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
}

$spaceAddress = ''
$repoFull = ''
$tracker = 'none'
if ($hasAddress) {
    $addr = ([string]$Address).Trim().TrimEnd('/')
    if ($addr -notmatch '^https?://[^\s/]+') {
        Write-CliError -Message "'$addr' is not an address." -Hint 'An Azure DevOps organisation is https://dev.azure.com/<org>. For a GitHub repository use -Repo owner/name.'
        exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
    }
    if ((Resolve-P20Tracker -OrgUrl $addr) -eq 'github') {
        # A GitHub Space is one repository (D-W17): a repository's address is -Repo
        # by another spelling; an owner's is not a Space.
        $parts = @(($addr -replace '^[a-zA-Z][a-zA-Z0-9+.-]*://', '').Split('/') | Where-Object { $_ })
        if ($parts.Count -ge 3) { $Repo = "$($parts[1])/$($parts[2])"; $hasRepo = $true; $hasAddress = $false }
        else {
            Write-CliError -Message "A GitHub Space is one repository, and '$addr' is an owner." -Hint "${prefix}NewSpace -Repo <owner>/<name> -- ${prefix}NewSpace -Discover lists yours."
            exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
        }
    }
    else {
        $spaceAddress = $addr
        $tracker = 'ado'
    }
}
if ($hasRepo) {
    $repoFull = & $normaliseRepo $Repo
    if ($repoFull -notmatch '^[A-Za-z0-9][A-Za-z0-9-]*/[A-Za-z0-9._-]+$') {
        Write-CliError -Message "'$Repo' is not owner/name." -Hint "For example johnfrog76/toolkit. ${prefix}NewSpace -Discover lists yours."
        exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
    }
    $spaceAddress = "https://github.com/$repoFull"
    $tracker = 'github'
    $held = $repoOwners[$repoFull.ToLowerInvariant()]
    if ($held) {
        Write-CliError -Message "$repoFull is already a Space: $(& $spaceLabel $held)." -Hint "Go into it: ${prefix}SwitchSpace $($held.slug)"
        exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
    }
}

# -- The slug and the name ---------------------------------------------------------
$repoName = ''
if ($repoFull) { $repoName = $repoFull.Split('/')[1] }
$slugGiven = ([string]$Slug).Trim()
if ($slugGiven) { $newSlug = $slugGiven }
elseif ($repoName) { $newSlug = & $proposeSlug $repoName }
else {
    Write-CliError -Message 'An Azure DevOps Space needs a slug: the short name it is stored and switched by.' -Hint "${prefix}NewSpace <slug> -Address $spaceAddress -- for example ${prefix}NewSpace acme -Address https://dev.azure.com/acme"
    exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
}
if ($newSlug -cnotmatch $slugPattern) {
    $why = "'$newSlug' is not a slug."
    if (-not $slugGiven) { $why = "'$repoName' does not make a slug ('$newSlug')." }
    Write-CliError -Message $why -Hint "A slug is lowercase letters, digits and dashes, starting with a letter: acme, my-team. Give one: ${prefix}NewSpace <slug>$(if ($repoFull) { " -Repo $repoFull" })"
    exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
}
$renamedTo = Resolve-P20RenamedSlug -Slug $newSlug -Slugs $knownSlugs
$taken = $spaces | Where-Object { [string]$_.slug -eq $newSlug -or [string]$_.slug -eq $renamedTo } | Select-Object -First 1
if ($taken) {
    Write-CliError -Message "There is already a Space '$newSlug': $(& $spaceLabel $taken)." -Hint "Give this one another slug: ${prefix}NewSpace <slug>$(if ($repoFull) { " -Repo $repoFull" } elseif ($spaceAddress) { " -Address $spaceAddress" })"
    exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
}
$folderOwner = $spaces | Where-Object { ([string]$_.promptsFolder).ToLowerInvariant() -eq $newSlug } | Select-Object -First 1
if ($folderOwner) {
    Write-CliError -Message "The folder '$newSlug' is already $(& $spaceLabel $folderOwner)'s cards." -Hint "Give this Space another slug: ${prefix}NewSpace <slug>$(if ($repoFull) { " -Repo $repoFull" })"
    exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
}
$reserved = @()
foreach ($entry in (Get-P20HubFolderNames -PackageRoot $packageRoot).GetEnumerator()) { $reserved += ([string]$entry.Value).ToLowerInvariant() }
if ($reserved -contains $newSlug) {
    Write-CliError -Message "'$newSlug' is the hub's own folder, not a Space's." -Hint "Give this Space another slug: ${prefix}NewSpace <slug>$(if ($repoFull) { " -Repo $repoFull" })"
    exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
}

$displayName = ([string]$Name).Trim()
if (-not $displayName) {
    if ($repoName) { $displayName = & $proposeName $repoName } else { $displayName = & $proposeName $newSlug }
}
$status = 'local'
if ($spaceAddress) { $status = 'active' }

# -- The hub, and the folder --------------------------------------------------------
if (-not $hubRoot -or -not (Test-P20HubRoot $hubRoot)) {
    Write-CliError -Message (Get-P20HubMissingMessage $hubRoot) -Hint "A Space's cards live in the hub. ${prefix}Start makes one; ${prefix}Config -Set promptsRoot=<folder> points at yours."
    exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
}
$folder = Join-Path $hubRoot $newSlug
if ((Test-Path -LiteralPath $folder) -and -not (Test-Path -LiteralPath $folder -PathType Container)) {
    Write-CliError -Message "There is a file named '$newSlug' in the hub, where the Space's folder would go." -Hint "Move it, or give this Space another slug: ${prefix}NewSpace <slug>"
    exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
}
$adopted = Test-Path -LiteralPath $folder -PathType Container
$cardsCurrent = 0
$cardsArchive = 0
if ($adopted) {
    $cur = Join-Path $folder 'current'
    $arc = Join-Path $folder 'archive'
    if (Test-Path -LiteralPath $cur) { $cardsCurrent = @(Get-ChildItem -LiteralPath $cur -File -Filter '*.md' -ErrorAction SilentlyContinue).Count }
    if (Test-Path -LiteralPath $arc) { $cardsArchive = @(Get-ChildItem -LiteralPath $arc -File -Filter '*.md' -ErrorAction SilentlyContinue).Count }
}
$cards = $cardsCurrent + $cardsArchive

# -- Is the repository there? Asked, never required ------------------------------------
$visibility = ''
$isArchived = $false
$viewerPermission = ''
$checkNote = ''
if ($repoFull) {
    $signIn = Test-P20TrackerSignIn -Tracker 'github'
    if (-not $signIn.Installed) { $checkNote = 'not checked: gh is not installed' }
    elseif (-not $signIn.SignedIn) { $checkNote = 'not checked: gh is not signed in (gh auth login)' }
    else {
        $viewed = Invoke-P20TrackerRead 'gh' @('repo', 'view', $repoFull, '--json', 'visibility,isArchived,viewerPermission')
        if ($viewed.Code -eq 0) {
            try {
                $view = (($viewed.Out | Out-String) | ConvertFrom-Json)
                $visibility = ([string]$view.visibility).ToUpperInvariant()
                $isArchived = [bool]$view.isArchived
                $viewerPermission = ([string]$view.viewerPermission).ToUpperInvariant()
            } catch { $visibility = ''; $isArchived = $false; $viewerPermission = '' }
            if (-not $visibility) { $checkNote = 'not checked: gh answered with something that is not JSON' }
        }
        else {
            $first = @($viewed.Lines | ForEach-Object { ([string]$_).Trim() } | Where-Object { $_ })[0]
            # gh asked and refused: this login cannot see the repository (or gh could not
            # reach it) -- said as that, with gh's own line, not as a check that never ran.
            $checkNote = "${notVisible}: gh answered '$first'"
        }
    }
}

# -- The write: through Config, every key, one call ---------------------------------
$pairs = @("spaces.$newSlug.name=$displayName", "spaces.$newSlug.status=$status", "spaces.$newSlug.promptsFolder=$newSlug")
if ($spaceAddress) { $pairs += "spaces.$newSlug.org=$spaceAddress" }

if ($WhatIf) {
    if (-not $AsJson) {
        Write-Host ""
        foreach ($pair in $pairs) { Write-Host "  [WhatIf] ${prefix}Config -Set $pair -Hub" -ForegroundColor Yellow }
        if ($adopted) { Write-Host "  [WhatIf] adopt $folder as it is -- $cards cards ($cardsCurrent current, $cardsArchive archive)" -ForegroundColor Yellow }
        else { Write-Host "  [WhatIf] make $(Join-Path $folder 'current') and $(Join-Path $folder 'archive')" -ForegroundColor Yellow }
    }
}
else {
    $configScript = Join-Path $scriptsDir 'Set-ToolkitConfig.ps1'
    # In-process, all streams caught: Config's own lines are shown in a terminal and
    # kept out of -AsJson, whose one line the bridge parses.
    # Reset first: a gh check above may have left a non-zero code behind.
    $global:LASTEXITCODE = 0
    $out = & $configScript -Set $pairs -Hub *>&1 | Out-String
    $code = $LASTEXITCODE
    . $loadHelpers
    if ($code -and $code -ne 0) {
        Write-Host $out.TrimEnd()
        exit $code
    }
    if (-not $AsJson) { Write-Host $out.TrimEnd() }
    if (-not $adopted) {
        foreach ($sub in @('current', 'archive')) { [void][System.IO.Directory]::CreateDirectory((Join-Path $folder $sub)) }
    }
    if (Get-Command Write-ToolkitLog -ErrorAction SilentlyContinue) {
        Write-ToolkitLog -Type CMD -Source "${prefix}NewSpace" -Detail "$newSlug $status$(if ($spaceAddress) { " $spaceAddress" })$(if ($adopted) { " adopted $cards" })"
    }
}

if ($AsJson) {
    [ordered]@{
        slug       = $newSlug
        name       = $displayName
        status     = $status
        tracker    = $tracker
        address    = $spaceAddress
        repo       = $repoFull
        folder     = $folder
        adopted    = [bool]$adopted
        cards      = $cards
        visibility = $visibility
        isArchived = [bool]$isArchived
        viewerPermission = $viewerPermission
        readOnly   = (& $isReadOnly $viewerPermission)
        checked    = [bool]$visibility
        note       = $checkNote
        written    = @($pairs)
        whatIf     = [bool]$WhatIf
        next       = "${prefix}SwitchSpace $newSlug"
    } | ConvertTo-Json -Depth 4 -Compress
    exit 0
}

Write-Host ""
$verbWord = 'Added'
if ($WhatIf) { $verbWord = 'Would add' }
Write-Host "  [+] $verbWord the Space '$newSlug' -- $displayName" -ForegroundColor Green
if ($repoFull) {
    if ($visibility) {
        $archivedWord = ''
        if ($isArchived) { $archivedWord = ' ARCHIVED' }
        if (& $isReadOnly $viewerPermission) { $archivedWord += ' READ-ONLY' }
        Write-Host "      $spaceAddress -- $visibility$archivedWord"
    }
    else { Write-Host "      $spaceAddress -- the repository was $checkNote" -ForegroundColor Yellow }
}
elseif ($spaceAddress) { Write-Host "      $spaceAddress -- an Azure DevOps organisation" }
else { Write-Host "      your own cards, no tracker (local)" }
if ($adopted) { Write-Host "      cards: $folder -- an existing folder, adopted as it is: $cards cards ($cardsCurrent current, $cardsArchive archive)" }
else { Write-Host "      cards: $folder -- new, with current/ and archive/" }
if ($tracker -eq 'ado') {
    Write-Host "      Its projects are not discovered here; that is the next step: ${prefix}Connect $newSlug -Discover" -ForegroundColor DarkGray
}
Write-Host "  Go into it:"
Write-Host "    ${prefix}SwitchSpace $newSlug"
exit 0
