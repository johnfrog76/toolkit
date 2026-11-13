#
# The Team Agile rituals' shared skeleton (Task3WGP): which Space, and the thin
# gh-call layer that turns a raw answer into @{ ok; value } or
# @{ ok = $false; reason }. DOT-SOURCED by the ritual verbs -- Scripts/Get-Standup.ps1,
# Scripts/Get-Triage.ps1 and Scripts/Set-Route.ps1 -- and by the suites, the way
# Scripts/Triage-Rules.ps1 is.
#
#     . (Join-Path $PSScriptRoot 'Invoke-TrackerRead.ps1')
#     . (Join-Path $PSScriptRoot 'Ritual-Common.ps1')
#     $space = Resolve-P20RitualSpace -Space $Space -Config $cfg
#     $slug = $space.slug; $org = $space.org; $status = $space.status; $projects = $space.projects
#
# Route keeps its own gh-call shape in Set-Route.ps1 (Invoke-P20RouteGh /
# Read-P20RouteJson): it needs the raw text of two different reads and the
# writes, where Standup and Triage parse one JSON array per call. Route
# already reads through Invoke-P20TrackerRead, so sharing the Space resolution
# below is the whole of what it takes from here.
#
# PowerShell 5.1 compatible (ASCII dashes only); reads no module state.
#

function Get-P20RitualViewer {
    # Who you are on GitHub: the signed-in gh user's login, so an item assigned
    # to you reads "me" (D-AR10). ONE read, `gh api user -q .login`, made once per
    # ritual call by the caller -- Triage, and the standup's suggestion. Best
    # effort: '' when gh cannot say, and nothing fails.
    if (-not (Get-Command Invoke-P20TrackerRead -ErrorAction SilentlyContinue)) {
        . (Join-Path $PSScriptRoot 'Invoke-TrackerRead.ps1')
    }
    try {
        $me = Invoke-P20TrackerRead 'gh' @('api', 'user', '-q', '.login')
        $login = ((@($me.Out) -join "`n").Trim())
        if ($me.Code -eq 0 -and $login -match '^[A-Za-z0-9-]+$') { return $login }
    }
    catch { $null = $_ }
    return ''
}

function Resolve-P20RitualSpace {
    # Which Space: no -Space is the one you are in; a slug is that Space's
    # own entry, read without switching into it -- the same three things the
    # agent's space_scope() takes. Returns slug, org, status, projects,
    # spaceName and promptsFolder (the last two are Standup's cards-fallback
    # fields; Triage and Route read past them). An undeclared -Space is a
    # stated refusal, printed and exited here so every caller's own refusal
    # reads identically (AGENTS.md, "The refusal contract").
    param(
        [string]$Space,
        $Config
    )
    $result = [ordered]@{ slug = ''; org = ''; status = ''; projects = @(); spaceName = ''; promptsFolder = '' }
    if ($Space) {
        $spaceValue = $Space.Trim()
        $declared = @()
        if ($Config -and $Config.Spaces) { $declared = @($Config.Spaces | Where-Object { $_ } | ForEach-Object { [string]$_.slug }) }
        $entry = $null
        if ($Config -and $Config.Spaces) { $entry = @($Config.Spaces | Where-Object { $_ -and [string]$_.slug -eq $spaceValue }) | Select-Object -First 1 }
        if (-not $entry) {
            $hint = 'Leave -Space out for the Space you are in.'
            if ($declared.Count -gt 0) { $hint = "Declared: $($declared -join ', '). Or leave -Space out for the Space you are in." }
            Write-CliError -Message "No Space '$spaceValue' is declared." -Hint $hint
            exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
        }
        $result.slug = $spaceValue
        $result.org = [string]$entry.org
        $result.status = [string]$entry.status
        if ($entry.projects) { $result.projects = @($entry.projects) }
        $result.spaceName = [string]$entry.name
        $result.promptsFolder = [string]$entry.promptsFolder
    }
    elseif ($Config) {
        $result.slug = [string]$Config.ActiveSpace
        $result.org = [string]$Config.Org
        $result.status = [string]$Config.OrgStatus
        if ($Config.Projects) { $result.projects = @($Config.Projects) }
        $result.spaceName = [string]$Config.ActiveOrgName
        $result.promptsFolder = [string]$Config.PromptsFolder
    }
    return [pscustomobject]$result
}

function Invoke-P20RitualGh {
    # One gh call -> @{ ok; value } or @{ ok = $false; reason }. stderr's first
    # line is the reason; the value is the parsed JSON array, enumerated so
    # 5.1's unrolled-array quirk cannot hand back an array of one array. The
    # call itself is Invoke-P20TrackerRead's (Scripts/Invoke-TrackerRead.ps1,
    # dot-sourced by the caller before this file) -- this only shapes its
    # answer, the way Set-Route.ps1's own Invoke-P20RouteGh does.
    param([string[]]$Arguments, [string]$Repo)
    try { $read = Invoke-P20TrackerRead 'gh' $Arguments }
    catch { return @{ ok = $false; reason = "gh did not answer ($($_.Exception.Message))" } }
    $code = $read.Code
    $stdout = @($read.Out) -join "`n"
    $stderr = @($read.Err | ForEach-Object { ([string]$_).Trim() } | Where-Object { $_ })
    if ($code -ne 0) {
        $why = "gh did not answer for $Repo"
        if ($stderr.Count -gt 0) { $why += ": $($stderr[0])" }
        return @{ ok = $false; reason = $why }
    }
    try { $parsed = ConvertFrom-Json -InputObject $stdout }
    catch { return @{ ok = $false; reason = "gh answered for $Repo with something that is not JSON" } }
    $list = New-Object System.Collections.ArrayList
    foreach ($x in $parsed) { if ($null -ne $x) { [void]$list.Add($x) } }
    return @{ ok = $true; value = $list.ToArray() }
}

function Get-P20StandupDates {
    # The standup's dates read for ONE repo: one `gh api graphql` per chunk of
    # aliases (Get-P20StandupDatesLimits), the query in a temporary file and the
    # owner and name as fields, so no quote in it crosses a native argument.
    # -> @{ ok; commitDates; issueStarts } or @{ ok = $false; reason }. An alias
    # GitHub could not resolve is null in an answer that still has data (gh
    # exits 1 for it), so the answer is read from stdout whatever the exit code,
    # and only an answer with no data is a failed read. The query and the parse
    # are Standup-Rules.ps1's (Get-P20StandupDatesQuery, ConvertFrom-P20StandupDates).
    param([string]$Repo, [string[]]$Hashes, [int[]]$Numbers, [string[]]$WorkerLabels)
    $commits = @{}
    $starts = @{}
    $asks = New-Object System.Collections.ArrayList
    foreach ($h in @($Hashes | Where-Object { $_ })) { [void]$asks.Add(@('c', [string]$h)) }
    foreach ($n in @($Numbers | Where-Object { $null -ne $_ })) { [void]$asks.Add(@('i', [int]$n)) }
    $owner, $name = ([string]$Repo).Split('/', 2)
    $size = (Get-P20StandupDatesLimits).chunk
    for ($at = 0; $at -lt $asks.Count; $at += $size) {
        $chunk = @($asks.ToArray()[$at..([Math]::Min($at + $size, $asks.Count) - 1)])
        $ch = [string[]]@($chunk | Where-Object { $_[0] -ceq 'c' } | ForEach-Object { [string]$_[1] })
        $cn = [int[]]@($chunk | Where-Object { $_[0] -ceq 'i' } | ForEach-Object { [int]$_[1] })
        $file = Join-Path ([System.IO.Path]::GetTempPath()) ('p20-gql-' + [guid]::NewGuid().ToString('N') + '.graphql')
        try {
            [System.IO.File]::WriteAllText($file, (Get-P20StandupDatesQuery -Hashes $ch -Numbers $cn), (New-Object System.Text.UTF8Encoding($false)))
            $read = Invoke-P20TrackerRead 'gh' @('api', 'graphql', '-F', "query=@$file", '-f', "owner=$owner", '-f', "name=$name")
        }
        catch { return @{ ok = $false; reason = "gh did not answer ($($_.Exception.Message))" } }
        finally { Remove-Item -LiteralPath $file -Force -ErrorAction SilentlyContinue }
        $parsed = $null
        try { $parsed = ConvertFrom-Json -InputObject (@($read.Out) -join "`n") } catch { $parsed = $null }
        if ($null -eq $parsed -or $null -eq $parsed.PSObject.Properties['data'] -or $null -eq $parsed.data) {
            $why = "gh did not answer for $Repo"
            $err = @($read.Err | ForEach-Object { ([string]$_).Trim() } | Where-Object { $_ })
            if ($err.Count -gt 0) { $why += ": $($err[0])" }
            return @{ ok = $false; reason = $why }
        }
        $got = ConvertFrom-P20StandupDates -Repository $parsed.data.repository -Hashes $ch -Numbers $cn -WorkerLabels $WorkerLabels
        foreach ($k in @($got.commitDates.Keys)) { $commits[$k] = $got.commitDates[$k] }
        foreach ($k in @($got.issueStarts.Keys)) { $starts[$k] = $got.issueStarts[$k] }
    }
    return @{ ok = $true; commitDates = $commits; issueStarts = $starts }
}
