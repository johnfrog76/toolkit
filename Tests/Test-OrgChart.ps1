<#
.SYNOPSIS
    OrgChart -- the org's tree from the hub's org file, typed (Team Agile).
.DESCRIPTION
    Holds the contract in docs/hub/org.md in three layers.

    1. The reader     Scripts/Read-OrgChart.ps1 over the shared table
                      Tests/fixtures/org/table.json -- the agent's reader reads
                      the same file. One row per input the file's rules
                      distinguish: a valid tree shaped like ours, a second
                      tree chosen by activeTree and by -Tree, the unknown keys
                      said and the notes not, a renamed agentic folder, and
                      every way the file can be wrong -- unreadable, no trees,
                      an entry with no id, no or unknown activeTree, a repeated
                      id (trees, positions, seats), a reportsTo that names
                      nothing, a loop, no root or several, a prompt found in
                      each of the three folders a role is looked up in (the
                      hub's roles, the hub's agentic folder, the toolkit's
                      roles) and the hub's winning over the toolkit's, a prompt
                      in none of them, an unknown -Tree. Each ok
                      case says the response it returns (compared as JSON) and
                      the lines the CLI prints; each failure says its kind and
                      its sentence.
    2. The verb       OrgChart typed in a fresh shell over a scratch copy of
                      the package and of samples/hub (AGENTS.md: a suite that
                      runs a script directly does not test the verb). Off means
                      absent: with Team Agile off there is no verb. On: -Help,
                      the command table, the autoload manifest not naming it
                      (a module verb); the text and -AsJson byte-for-byte
                      against the table, -Tree, the unknown-key warnings; every
                      refusal -- no hub, no file, an invalid file, an unknown
                      tree -- exits 2 with the sentence and writes nothing;
                      and nothing in the hub changes on any run.
    3. The surfaces   the Org chart row: off where Team Agile is off, not
                      configured with no file, on with the tree's name and its
                      seats, and off with the sentence when the file is there
                      and invalid; and the sample hub's own org.json is valid.

    Run:  pwsh -File Tests/Test-OrgChart.ps1
    Or:   {cliPrefix}TestToolkit -OrgChart
#>
param([switch]$Help)

if ($Help) { Get-Help $MyInvocation.MyCommand.Path -Detailed; return }

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Get-TestHost.ps1')
$pkgRoot = Split-Path $PSScriptRoot -Parent
$fixtures = Join-Path $PSScriptRoot 'fixtures/org'
$script:passed = 0
$script:failed = 0

function Assert-True($label, $cond, $detail = '') {
    if ($cond) { $script:passed++; Write-Host "  PASS  $label" -ForegroundColor Green }
    else { $script:failed++; Write-Host "  FAIL  $label$(if ($detail) { " -- $($detail.ToString().Trim())" })" -ForegroundColor Red }
}
function Assert-Equal($label, $expected, $actual, $detail = '') {
    if ("$expected" -ceq "$actual") { $script:passed++; Write-Host "  PASS  $label" -ForegroundColor Green }
    else { $script:failed++; Write-Host "  FAIL  $label -- expected '$expected', got '$actual'$(if ($detail) { "`n        $($detail.ToString().Trim())" })" -ForegroundColor Red }
}

$utf8 = New-Object System.Text.UTF8Encoding($false)
$root = Join-Path ([System.IO.Path]::GetTempPath()) ("p20-orgchart-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
$pkgDir = Join-Path $root 'pkg'
$hubDir = Join-Path $root 'hub'
$logDir = Join-Path $root 'log'
$casesDir = Join-Path $root 'cases'

function Read-Fixture([string]$Relative) {
    # A fixture's text, LF: a checkout that turned a file CRLF must not fail on its endings.
    return [System.IO.File]::ReadAllText((Join-Path $fixtures $Relative)).Replace("`r`n", "`n")
}
function Test-Prop($Object, [string]$Name) { return [bool]$Object.PSObject.Properties[$Name] }
function ConvertTo-Plain($Value) {
    # Whatever the reader built, as the plain objects ConvertFrom-Json makes of the same text.
    return (($Value | ConvertTo-Json -Depth 20) | ConvertFrom-Json)
}
function Compare-Json($Expected, $Actual, [string]$At = '$') {
    # '' when equal, else the first difference. Key order does not matter, array order does.
    if ($null -eq $Expected -or $null -eq $Actual) {
        if ($null -eq $Expected -and $null -eq $Actual) { return '' }
        return "$At`: expected '$Expected', got '$Actual'"
    }
    if ($Expected -is [System.Management.Automation.PSCustomObject]) {
        if ($Actual -isnot [System.Management.Automation.PSCustomObject]) { return "$At`: expected an object" }
        $want = @($Expected.PSObject.Properties.Name | Sort-Object)
        $have = @($Actual.PSObject.Properties.Name | Sort-Object)
        if (($want -join ',') -cne ($have -join ',')) { return "$At`: keys differ -- expected [$($want -join ',')], got [$($have -join ',')]" }
        foreach ($name in $want) {
            $diff = Compare-Json $Expected.$name $Actual.$name "$At.$name"
            if ($diff) { return $diff }
        }
        return ''
    }
    if ($Expected -is [System.Array]) {
        if ($Actual -isnot [System.Array]) { return "$At`: expected an array" }
        if ($Expected.Count -ne $Actual.Count) { return "$At`: expected $($Expected.Count) items, got $($Actual.Count)" }
        for ($i = 0; $i -lt $Expected.Count; $i++) {
            $diff = Compare-Json $Expected[$i] $Actual[$i] "$At[$i]"
            if ($diff) { return $diff }
        }
        return ''
    }
    if ($Expected.GetType() -ne $Actual.GetType() -or "$Expected" -cne "$Actual") { return "$At`: expected '$Expected', got '$Actual'" }
    return ''
}
function New-CaseHub($Case, $Table) {
    # The scratch hub a table row describes (the table's own header says how).
    $hub = Join-Path $casesDir $Case.name
    New-Item -ItemType Directory -Path $hub -Force | Out-Null
    if (Test-Prop $Case 'hubJson') { [System.IO.File]::WriteAllText((Join-Path $hub 'hub.json'), ($Case.hubJson | ConvertTo-Json -Depth 20), $utf8) }
    if (Test-Prop $Case 'org') { [System.IO.File]::WriteAllText((Join-Path $hub 'org.json'), ($Case.org | ConvertTo-Json -Depth 20), $utf8) }
    if (Test-Prop $Case 'orgText') { [System.IO.File]::WriteAllText((Join-Path $hub 'org.json'), [string]$Case.orgText, $utf8) }
    if (Test-Prop $Case 'orgFile') { [System.IO.File]::WriteAllText((Join-Path $hub 'org.json'), (Read-Fixture $Case.orgFile), $utf8) }
    $folder = 'agentic'
    if (Test-Prop $Case 'promptsFolder') { $folder = [string]$Case.promptsFolder }
    New-Item -ItemType Directory -Path (Join-Path $hub $folder) -Force | Out-Null
    $names = @($Table.prompts)
    if (Test-Prop $Case 'prompts') { $names = @($Case.prompts) }
    foreach ($name in $names) { [System.IO.File]::WriteAllText((Join-Path $hub "$folder/$name"), '', $utf8) }
    if (Test-Prop $Case 'promptFolders') {
        foreach ($name in @($Case.promptFolders)) { New-Item -ItemType Directory -Path (Join-Path $hub "$folder/$name") -Force | Out-Null }
    }
    $roles = [string](Get-P20Consts).org.rolesFolder
    if (Test-Prop $Case 'hubOrgPrompts') {
        New-Item -ItemType Directory -Path (Join-Path $hub "$folder/$roles") -Force | Out-Null
        foreach ($name in @($Case.hubOrgPrompts)) { [System.IO.File]::WriteAllText((Join-Path $hub "$folder/$roles/$name"), '', $utf8) }
    }
    return $hub
}
function New-CasePackage($Case) {
    # The scratch package a table row reads against: exactly its shippedPrompts in
    # agentic/<roles>/ and its shippedFlatPrompts in agentic/, so the real shipped
    # roles never decide a row.
    $pkg = Join-Path $casesDir "$($Case.name).pkg"
    $roles = [string](Get-P20Consts).org.rolesFolder
    New-Item -ItemType Directory -Path (Join-Path $pkg "agentic/$roles") -Force | Out-Null
    if (Test-Prop $Case 'shippedPrompts') {
        foreach ($name in @($Case.shippedPrompts)) { [System.IO.File]::WriteAllText((Join-Path $pkg "agentic/$roles/$name"), '', $utf8) }
    }
    if (Test-Prop $Case 'shippedFlatPrompts') {
        foreach ($name in @($Case.shippedFlatPrompts)) { [System.IO.File]::WriteAllText((Join-Path $pkg "agentic/$name"), '', $utf8) }
    }
    return $pkg
}
function Get-Snapshot([string]$Dir) {
    return ((@(Get-ChildItem -LiteralPath $Dir -Recurse -Force | Sort-Object FullName | ForEach-Object {
                    if ($_.PSIsContainer) { "$($_.FullName)|dir" } else { "$($_.FullName)|$([System.IO.File]::ReadAllText($_.FullName))" }
                })) -join "`n")
}
function Write-Config([bool]$TeamAgile) {
    # The machine's config: the scratch hub, the GitHub demo Space (answered agents in
    # the scratch hub.json), the module's switch.
    $features = '{}'
    if ($TeamAgile) { $features = '{ "solitaireAgile": true }' }
    [System.IO.File]::WriteAllText((Join-Path $pkgDir 'config.local.json'),
        "{ `"promptsRoot`": `"$($hubDir -replace '\\', '/')`", `"activeSpace`": `"github-demo`", `"quietStart`": true, `"features`": $features }", $utf8)
}
function Invoke-OrgChart {
    # -Direct skips the module: for the one refusal the verb cannot be typed for
    # (with no hub there is no Space answered agents, so Team Agile is off and
    # the verb is absent), the script itself is run in a shell of its own.
    param([string]$Snippet, [switch]$Direct)
    $importLine = "Import-Module '$($pkgDir -replace "'", "''")/Prompt20Toolkit/Prompt20Toolkit.psd1' -Force 3>`$null 6>`$null"
    if ($Direct) { $importLine = '' }
    $pkg = $pkgDir -replace "'", "''"; $log = $logDir -replace "'", "''"
    $text = @"
`$env:PSModulePath = '$pkg'
`$env:PROMPTS_ROOT = ''
`$env:P20_USAGE_LOG_DIR = '$log'
Remove-Item Env:P20_ACTIVE_SPACE -ErrorAction SilentlyContinue
Get-ChildItem Env: | Where-Object { `$_.Name -like 'TEAMS_WEBHOOK_*' } | ForEach-Object { Remove-Item "Env:\`$(`$_.Name)" -ErrorAction SilentlyContinue }
$importLine
$Snippet
"EXIT=`$LASTEXITCODE"
"@
    $runner = Join-Path $root ("run-" + [guid]::NewGuid().ToString('N').Substring(0, 8) + ".ps1")
    [System.IO.File]::WriteAllText($runner, $text, $utf8)
    $out = Invoke-P20TestHost -File $runner -NonInteractive
    Remove-Item $runner -Force -ErrorAction SilentlyContinue
    $all = (($out | ForEach-Object { $_.ToString() }) -join "`n")
    $code = ''
    $m = [regex]::Matches($all, 'EXIT=(\d*)')
    if ($m.Count) { $code = $m[$m.Count - 1].Groups[1].Value }
    return [pscustomobject]@{ All = $all; Exit = $code }
}
function Get-Section([string]$All, [string]$Name) {
    $m = [regex]::Match($All, "(?s)BEGIN:$([regex]::Escape($Name))\r?\n(.*?)END:$([regex]::Escape($Name))")
    return $m.Groups[1].Value.TrimEnd("`r", "`n")
}

Write-Host ""
Write-Host "  OrgChart -- the org's tree, from the hub's org file" -ForegroundColor Cyan
Write-Host "  ---------------------------------------------------" -ForegroundColor DarkGray
Write-Host ""

try {
    New-Item -ItemType Directory -Path $pkgDir, $logDir, $casesDir -Force | Out-Null
    foreach ($file in @('utilities.psm1', 'config.default.json', 'consts.json')) { Copy-Item (Join-Path $pkgRoot $file) $pkgDir -Force }
    foreach ($folder in @('Scripts', 'Config', 'Prompt20Toolkit', 'templates', 'agentic')) { Copy-Item (Join-Path $pkgRoot $folder) $pkgDir -Recurse -Force }
    Copy-Item (Join-Path $pkgRoot 'samples/hub') $hubDir -Recurse -Force
    # The GitHub demo Space answered "with agents": Team Agile is on where the answer and the switch agree.
    $hubJsonPath = Join-Path $hubDir 'hub.json'
    $hubJson = [System.IO.File]::ReadAllText($hubJsonPath) | ConvertFrom-Json
    foreach ($space in @($hubJson.spaces)) {
        if ($space.slug -eq 'github-demo') {
            if (Test-Prop $space 'howIWork') { $space.howIWork = 'agents' } else { $space | Add-Member -NotePropertyName howIWork -NotePropertyValue 'agents' }
        }
    }
    [System.IO.File]::WriteAllText($hubJsonPath, ($hubJson | ConvertTo-Json -Depth 10), $utf8)
    Write-Config $true

    $table = Read-Fixture 'table.json' | ConvertFrom-Json
    . (Join-Path $pkgRoot 'Scripts/Read-OrgChart.ps1')

    # -- 1. The reader over the shared table ---------------------------------------------
    Write-Host "-- The reader, over Tests/fixtures/org/table.json ------" -ForegroundColor Cyan
    Assert-Equal 'the file name is the contract'  'org.json' (Get-P20OrgFileName)
    Assert-True 'the table has cases' (@($table.cases).Count -gt 20) "$(@($table.cases).Count) cases"
    foreach ($case in $table.cases) {
        $hub = New-CaseHub $case $table
        $casePkg = New-CasePackage $case
        $treeId = ''
        if (Test-Prop $case 'tree') { $treeId = [string]$case.tree }
        $read = Read-P20OrgChart -PromptsRoot $hub -PackageRoot $casePkg -TreeId $treeId
        $want = $case.expect
        Assert-Equal "$($case.name): status" $want.status $read.Status $read.Message
        if ($want.status -eq 'ok') {
            Assert-Equal "$($case.name): the tree in use" $want.activeTree $read.ActiveTree
            Assert-Equal "$($case.name): its seats" $want.seatCount $read.SeatCount
            Assert-Equal "$($case.name): warnings, in order" (@($want.warnings) -join "`n") (@($read.Warnings) -join "`n")
            $diff = Compare-Json (Read-Fixture $want.chart | ConvertFrom-Json) (ConvertTo-Plain $read.Chart)
            Assert-True "$($case.name): the response is the table's chart" ($diff -eq '') $diff
            Assert-Equal "$($case.name): the lines it prints" ((Read-Fixture $want.text).TrimEnd("`n")) ((Format-P20OrgChartLines -Chart $read.Chart) -join "`n")
        }
        else {
            Assert-Equal "$($case.name): kind" $want.kind $read.Kind
            if (Test-Prop $want 'messageStartsWith') {
                Assert-True "$($case.name): sentence" ($read.Message.StartsWith([string]$want.messageStartsWith)) $read.Message
            }
            else {
                Assert-Equal "$($case.name): sentence" $want.message $read.Message
            }
        }
    }
    # No hub root at all, and a root that is not there, are a missing file, not a throw.
    Assert-Equal 'no hub root: missing' 'missing' (Read-P20OrgChart -PromptsRoot '').Status
    Assert-Equal 'a hub root that is not there: missing' 'missing' (Read-P20OrgChart -PromptsRoot (Join-Path $root 'nowhere')).Status
    # The file's bytes: a BOM is read through, and the reader writes nothing.
    $bomHub = Join-Path $casesDir 'bom'
    New-Item -ItemType Directory -Path $bomHub -Force | Out-Null
    [System.IO.File]::WriteAllText((Join-Path $bomHub 'org.json'), '{"trees":[{"id":"a","name":"Caf' + [char]0x00E9 + '","positions":[{"id":"x"}]}]}', (New-Object System.Text.UTF8Encoding($true)))
    $bom = Read-P20OrgChart -PromptsRoot $bomHub
    Assert-Equal 'a file with a BOM reads, and a non-ASCII name comes through' ('Caf' + [char]0x00E9) $bom.Chart.tree.name
    $dot = [string][char]0x00B7
    Assert-True 'the plate is the position, a middle dot, then who sits there' ((Format-P20OrgChartLines -Chart $bom.Chart)[0] -ceq "x $dot no seats")

    # -- 2. The verb, typed ----------------------------------------------------------------
    Write-Host ""
    Write-Host "-- The verb, typed in a fresh shell --------------------" -ForegroundColor Cyan
    Remove-Item -LiteralPath (Join-Path $hubDir 'org.json') -ErrorAction SilentlyContinue
    $orgPath = Join-Path $hubDir 'org.json'
    $hubBefore = Get-Snapshot $hubDir

    Write-Config $false
    $off = Invoke-OrgChart "if (Get-Command tkOrgChart -ErrorAction SilentlyContinue) { 'VERB=present' } else { 'VERB=absent' }; 'MAP=' + ((Get-P20CommandMap) -match 'OrgChart')"
    Assert-True 'Team Agile off: there is no OrgChart verb' ($off.All -match 'VERB=absent') $off.All
    Assert-True 'and none in the bridge''s command table' ($off.All -match 'MAP=False') $off.All
    Write-Config $true

    $reg = Invoke-OrgChart "'MAP=' + (Get-P20CommandMap); tkOrgChart -Help"
    Assert-True 'OrgChart is in the command table the bridge reads' ($reg.All -match '"OrgChart":\s*"Get-P20OrgChart"') $reg.All
    Assert-True '-Help prints the usage from config' ($reg.All.Contains('tkOrgChart [-Tree <id>] [-AsJson] [-Help]')) $reg.All
    $manifest = [System.IO.File]::ReadAllText((Join-Path $pkgRoot 'Prompt20Toolkit/Prompt20Toolkit.psd1'))
    Assert-True 'the autoload manifest does not name tkOrgChart (a module verb resolves after import)' ($manifest -notmatch "'tkOrgChart'")

    # The valid table row, typed: the text and the JSON the table states.
    $validCase = $table.cases | Where-Object { $_.name -eq 'valid' } | Select-Object -First 1
    [System.IO.File]::WriteAllText($orgPath, (Read-Fixture $validCase.orgFile), $utf8)
    foreach ($name in @($table.prompts)) {
        New-Item -ItemType Directory -Path (Join-Path $hubDir 'agentic') -Force | Out-Null
        [System.IO.File]::WriteAllText((Join-Path $hubDir "agentic/$name"), '', $utf8)
    }
    $hubWithFile = Get-Snapshot $hubDir
    $typed = Invoke-OrgChart "'BEGIN:text'; tkOrgChart; 'END:text'; 'BEGIN:json'; tkOrgChart -AsJson; 'END:json'; 'BEGIN:branch'; tkOrgChart -Tree branch; 'END:branch'; 'BEGIN:branchjson'; tkOrgChart -Tree branch -AsJson; 'END:branchjson'"
    $textOut = Get-Section $typed.All 'text'
    $wantText = "Org chart: Laptop and mini (main)`nMachines: laptop, mini`n`n" + (Read-Fixture 'text/valid.txt').TrimEnd("`n")
    Assert-Equal 'the text: a header, then one line per seat, byte for byte' $wantText $textOut $typed.All
    Assert-Equal 'it exits 0' '0' $typed.Exit
    $jsonDiff = Compare-Json (Read-Fixture 'charts/valid.json' | ConvertFrom-Json) ((Get-Section $typed.All 'json') | ConvertFrom-Json)
    Assert-True '-AsJson is the table''s chart' ($jsonDiff -eq '') $jsonDiff
    $branchText = Get-Section $typed.All 'branch'
    Assert-Equal '-Tree prints the other tree and says it is not the one in use' ("Org chart: One machine (branch) -- not the tree in use (main)`nMachines: mini`n`n" + (Read-Fixture 'text/valid-tree-by-id.txt').TrimEnd("`n")) $branchText
    $branchDiff = Compare-Json (Read-Fixture 'charts/valid-tree-by-id.json' | ConvertFrom-Json) ((Get-Section $typed.All 'branchjson') | ConvertFrom-Json)
    Assert-True '-Tree -AsJson is the table''s chart for it' ($branchDiff -eq '') $branchDiff
    Assert-True 'the four runs wrote nothing to the hub: not a byte, not a file' ((Get-Snapshot $hubDir) -ceq $hubWithFile)

    # Unknown keys: said as warnings, exit 0, the chart still printed.
    $keys = $table.cases | Where-Object { $_.name -eq 'unknown-keys-and-notes' } | Select-Object -First 1
    [System.IO.File]::WriteAllText($orgPath, ($keys.org | ConvertTo-Json -Depth 20), $utf8)
    $warned = Invoke-OrgChart "tkOrgChart 3>&1"
    Assert-Equal 'unknown keys: the chart is still printed, exit 0' '0' $warned.Exit
    foreach ($sentence in @($keys.expect.warnings)) {
        Assert-True "warned: $sentence" ($warned.All.Contains($sentence)) $warned.All
    }
    Assert-True 'an underscore key is a note and is not warned' (-not $warned.All.Contains('_note')) $warned.All

    # Refusals: exit 2, the sentence once, nothing written.
    Remove-Item -LiteralPath $orgPath -Force
    $refusals = @(
        @{ Name = 'no file'; Call = 'tkOrgChart'; Match = 'There is no org.json in the hub:'; Hint = 'docs/hub/org.md' }
        @{ Name = 'no file, -AsJson'; Call = 'tkOrgChart -AsJson'; Match = 'There is no org.json in the hub:'; Hint = 'samples/hub/org.json' }
    )
    foreach ($case in @('cycle', 'several-roots', 'duplicate-seat', 'unknown-active-tree')) {
        $row = $table.cases | Where-Object { $_.name -eq $case } | Select-Object -First 1
        $refusals += @{ Name = $case; Row = $row; Call = 'tkOrgChart'; Match = [string]$row.expect.message; Hint = 'docs/hub/org.md' }
    }
    $snapBefore = Get-Snapshot $hubDir
    foreach ($r in $refusals) {
        if ($r.Row) {
            [System.IO.File]::WriteAllText($orgPath, ($r.Row.org | ConvertTo-Json -Depth 20), $utf8)
            $snapBefore = Get-Snapshot $hubDir
        }
        $ran = Invoke-OrgChart $r.Call
        Assert-Equal "refused ($($r.Name)): exit 2" '2' $ran.Exit $ran.All
        Assert-True "refused ($($r.Name)): says why" ($ran.All.Contains($r.Match)) $ran.All
        Assert-True "refused ($($r.Name)): the hint points at the document" ($ran.All.Contains($r.Hint)) $ran.All
        Assert-True "refused ($($r.Name)): the sentence is said once" (([regex]::Matches($ran.All, [regex]::Escape($r.Match))).Count -eq 1) $ran.All
        Assert-True "refused ($($r.Name)): nothing written" ((Get-Snapshot $hubDir) -ceq $snapBefore)
    }
    # A prompt the valid file names that none of the three folders has. The toolkit ships a
    # team-lead role, so taking the hub's copy away would only fall through to it: the lead
    # names a role nobody ships instead.
    $validText = Read-Fixture $validCase.orgFile
    [System.IO.File]::WriteAllText($orgPath, $validText.Replace('"team-lead.prompt.md"', '"our-lead.prompt.md"'), $utf8)
    $snapBefore = Get-Snapshot $hubDir
    $noPrompt = Invoke-OrgChart 'tkOrgChart'
    Assert-Equal 'a prompt that is not in the agentic folder: exit 2' '2' $noPrompt.Exit $noPrompt.All
    Assert-True '  and names the position and the prompt' ($noPrompt.All.Contains("Position 'team-lead' in tree 'main' names the prompt 'our-lead.prompt.md', which is not a file in the hub's agentic/org/ or agentic/ folder or the toolkit's agentic/org/.")) $noPrompt.All
    Assert-True '  and writes nothing' ((Get-Snapshot $hubDir) -ceq $snapBefore)
    [System.IO.File]::WriteAllText($orgPath, $validText, $utf8)
    $unknownTree = Invoke-OrgChart 'tkOrgChart -Tree nope'
    Assert-Equal 'an unknown -Tree: exit 2' '2' $unknownTree.Exit
    Assert-True 'and says which trees there are' ($unknownTree.All.Contains("-Tree names 'nope', which is not a tree in org.json. Trees: main, branch.")) $unknownTree.All

    # No hub configured: nobody said where it is (no PROMPTS_ROOT, no promptsRoot in either file).
    [System.IO.File]::WriteAllText((Join-Path $pkgDir 'config.local.json'), '{ "quietStart": true }', $utf8)
    $noHub = Invoke-OrgChart ("& '" + (Join-Path $pkgDir 'Scripts/Get-OrgChart.ps1').Replace("'", "''") + "'") -Direct
    Assert-Equal 'no hub configured: exit 2' '2' $noHub.Exit $noHub.All
    Assert-True 'and the sentence says so' ($noHub.All.Contains('No hub is configured, so there is no org.json to read.')) $noHub.All
    Assert-True 'with the key and the file in the hint' ($noHub.All.Contains('Config -Set promptsRoot=<folder>') -and $noHub.All.Contains('docs/hub/org.md')) $noHub.All
    Write-Config $true

    # -- 3. The inventory row, and the sample -------------------------------------------------
    Write-Host ""
    Write-Host "-- The Org chart row, and the sample -------------------" -ForegroundColor Cyan
    . (Join-Path $pkgRoot 'Scripts/Get-OptionalSurfaces.ps1')
    $surfaceConfig = [pscustomobject]@{ PromptsRoot = $hubDir; ActiveSpace = 'github-demo'; Spaces = @() }
    $on = @{ solitaireAgile = $true }
    $offFeatures = @{ solitaireAgile = $false }
    function Get-Row($Features) {
        return (@(Get-P20OptionalSurfaces -Prefix 'tk' -PackageRoot $pkgRoot -Config $surfaceConfig -Features $Features) | Where-Object { $_.key -eq 'orgChart' } | Select-Object -First 1)
    }
    Remove-Item -LiteralPath $orgPath -Force
    $rowOff = Get-Row $offFeatures
    Assert-Equal 'Team Agile off: the row is off' 'off' $rowOff.state
    Assert-True '  and says it rides Team Agile' ($rowOff.note -match 'rides Team Agile, which is off in github-demo') $rowOff.note
    Assert-Equal 'Team Agile on, no file: not configured' 'not configured' (Get-Row $on).state
    Assert-True '  and says where it would go' ((Get-Row $on).note -match 'no org.json in the hub') (Get-Row $on).note
    [System.IO.File]::WriteAllText($orgPath, (Read-Fixture $validCase.orgFile), $utf8)
    $rowOn = Get-Row $on
    Assert-Equal 'a valid file: on' 'on' $rowOn.state
    Assert-Equal '  with the tree''s name, its seats and the verb' 'Laptop and mini, 7 seats; tkOrgChart prints it' $rowOn.note
    Assert-Equal 'a valid file with Team Agile off is still off' 'off' (Get-Row $offFeatures).state
    Assert-Equal 'the row carries its question' 'Who sits in which seat in my org?' $rowOn.question
    $cycleRow = $table.cases | Where-Object { $_.name -eq 'cycle' } | Select-Object -First 1
    [System.IO.File]::WriteAllText($orgPath, ($cycleRow.org | ConvertTo-Json -Depth 20), $utf8)
    $rowBad = Get-Row $on
    Assert-Equal 'a file that is there and invalid: off' 'off' $rowBad.state
    Assert-True '  with the sentence that says why' ($rowBad.note.Contains($cycleRow.expect.message)) $rowBad.note
    $oneSeat = Join-Path $casesDir 'one-seat'
    New-Item -ItemType Directory -Path $oneSeat -Force | Out-Null
    [System.IO.File]::WriteAllText((Join-Path $oneSeat 'org.json'), '{"trees":[{"id":"a","name":"Solo","positions":[{"id":"x","seats":[{"id":"s","person":"Sam"}]}]}]}', $utf8)
    $surfaceConfig.PromptsRoot = $oneSeat
    Assert-Equal 'one seat reads "1 seat"' 'Solo, 1 seat; tkOrgChart prints it' (Get-Row $on).note

    $sample = Read-P20OrgChart -PromptsRoot (Join-Path $pkgRoot 'samples/hub') -PackageRoot $pkgRoot
    Assert-Equal 'the sample hub''s org.json is valid' 'ok' $sample.Status $sample.Message
    Assert-Equal '  it names no warning' 0 @($sample.Warnings).Count
    Assert-True '  it holds the three shapes: a person, a vacant seat and a pool' (
        (@($sample.Chart.tree.positions | ForEach-Object { $_.seats } | Where-Object { $_.person }).Count -eq 1) -and
        (@($sample.Chart.tree.positions | ForEach-Object { $_.seats } | Where-Object { $_.state -eq 'vacant' }).Count -eq 1) -and
        (@($sample.Chart.tree.positions | Where-Object { @($_.seats).Count -eq 0 -and $_.defaultModel }).Count -eq 1))
    # Every office in the sample names a role the toolkit ships, and the sample hub copies none of them,
    # so each is found in the toolkit's agentic/org/. The owner is a person and the builder a pool:
    # neither names a role.
    $roles = [ordered]@{
        'vp-product' = @('vp-of-product.prompt.md', 'owner'); 'butler' = @('butler.prompt.md', 'vp-product')
        'vp-engineering' = @('vp-of-engineering.prompt.md', 'owner')
        'pm' = @('pm.prompt.md', 'owner'); 'team-lead' = @('team-lead.prompt.md', 'pm'); 'intern' = @('intern.prompt.md', 'pm')
    }
    foreach ($positionId in $roles.Keys) {
        $want = $roles[$positionId]
        $position = $sample.Chart.tree.positions | Where-Object { $_.id -eq $positionId } | Select-Object -First 1
        Assert-True "  its $positionId names the role the toolkit ships, $($want[0]), found in agentic/org/ (the sample hub has no copy)" (
            $position -and $position.prompt -eq $want[0] -and $position.reportsTo -eq $want[1] -and
            (Test-Path -LiteralPath (Join-Path $pkgRoot "agentic/org/$($want[0])") -PathType Leaf) -and
            -not (Test-Path -LiteralPath (Join-Path $pkgRoot "samples/hub/agentic/org/$($want[0])")))
    }
    $unroled = @($sample.Chart.tree.positions | Where-Object { $null -eq $_.prompt } | ForEach-Object { $_.id })
    Assert-Equal '  and only the owner and the builder pool name no role' 'owner,builder' ($unroled -join ',')
    $sampleRow = @(Get-P20OptionalSurfaces -Prefix 'tk' -PackageRoot $pkgRoot -Config ([pscustomobject]@{ PromptsRoot = (Join-Path $pkgRoot 'samples/hub'); ActiveSpace = 'github-demo'; Spaces = @() }) -Features $on) | Where-Object { $_.key -eq 'orgChart' } | Select-Object -First 1
    Assert-Equal '  the Org chart row over the sample: on, with its seats' 'on' $sampleRow.state $sampleRow.note
    Assert-Equal '  and the note counts them' 'My team, 8 seats; tkOrgChart prints it' $sampleRow.note
}
catch {
    $script:failed++
    Write-Host "  FAIL  the suite threw: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "        $($_.ScriptStackTrace)" -ForegroundColor DarkGray
}
finally {
    Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host ""
$total = $script:passed + $script:failed
Write-Host "  Results: $($script:passed)/$total passed" -ForegroundColor $(if ($script:failed -eq 0) { 'Green' } else { 'Red' })
if ($script:failed -gt 0) { exit 1 }
exit 0
