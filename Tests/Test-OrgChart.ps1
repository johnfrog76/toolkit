<#
.SYNOPSIS
    OrgChart -- the org's tree from the hub's org file, typed (Team Agile).
.DESCRIPTION
    Holds the contract in docs/hub/org.md in four layers.

    1. The reader     Scripts/Read-OrgChart.ps1 over the shared table
                      Tests/fixtures/org/table.json -- the agent's reader reads
                      the same file. One row per input the file's rules
                      distinguish: a valid tree shaped like ours, a second
                      tree chosen by activeTree and by -Tree, the unknown keys
                      said and the notes not, a renamed agentic folder, the
                      whole shape (a title over an older name, a seat's
                      roleTitle, session and merge, the retired keys read and
                      not drawn, each new field by its type), and
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
    4. The schema     Config/org.schema.json with Test-Json -Schema: the sample
                      hub's org.json as a file, each preset as one tree, what it
                      refuses and what it lets through. PowerShell 7 only:
                      Windows PowerShell 5.1 has no Test-Json, so there it is a
                      named SKIP, and Tests/test_org.py validates the same files.

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
    # The org presets Staff -Preset copies from (consts.json org.presetsFolder).
    . (Join-Path $pkgRoot 'Scripts/Get-Consts.ps1')
    $presetsRel = [string](Get-P20Consts).org.presetsFolder
    New-Item -ItemType Directory -Path (Split-Path (Join-Path $pkgDir $presetsRel) -Parent) -Force | Out-Null
    Copy-Item (Join-Path $pkgRoot $presetsRel) (Join-Path $pkgDir $presetsRel) -Recurse -Force
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
    Assert-Equal 'a file with a BOM reads, and a non-ASCII name comes through as the title' ('Caf' + [char]0x00E9) $bom.Chart.tree.title
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
    $typed = Invoke-OrgChart "'BEGIN:text'; tkOrgChart; 'END:text'; 'BEGIN:json'; tkOrgChart -AsJson; 'END:json'; 'BEGIN:branch'; tkOrgChart -Tree branch 3>`$null; 'END:branch'; 'BEGIN:branchjson'; tkOrgChart -Tree branch -AsJson; 'END:branchjson'"
    $textOut = Get-Section $typed.All 'text'
    $wantText = "Org chart: Laptop and mini (main)`n`n" + (Read-Fixture 'text/valid.txt').TrimEnd("`n")
    Assert-Equal 'the text: a header with the title (an older file''s name), then one line per seat, byte for byte -- no machine' $wantText $textOut $typed.All
    Assert-Equal 'it exits 0' '0' $typed.Exit
    $jsonDiff = Compare-Json (Read-Fixture 'charts/valid.json' | ConvertFrom-Json) ((Get-Section $typed.All 'json') | ConvertFrom-Json)
    Assert-True '-AsJson is the table''s chart' ($jsonDiff -eq '') $jsonDiff
    $branchText = Get-Section $typed.All 'branch'
    Assert-Equal '-Tree prints the other tree and says it is not the one in use' ("Org chart: One machine (branch) -- not the tree in use (main)`n`n" + (Read-Fixture 'text/valid-tree-by-id.txt').TrimEnd("`n")) $branchText
    $branchDiff = Compare-Json (Read-Fixture 'charts/valid-tree-by-id.json' | ConvertFrom-Json) ((Get-Section $typed.All 'branchjson') | ConvertFrom-Json)
    Assert-True '-Tree -AsJson is the table''s chart for it' ($branchDiff -eq '') $branchDiff
    Assert-True 'the four runs wrote nothing to the hub: not a byte, not a file' ((Get-Snapshot $hubDir) -ceq $hubWithFile)

    # The whole shape, typed: the title in the header, a seat's roleTitle, its session and the merge.
    $shapeCase = $table.cases | Where-Object { $_.name -eq 'the-shape-complete' } | Select-Object -First 1
    [System.IO.File]::WriteAllText($orgPath, (Read-Fixture $shapeCase.orgFile), $utf8)
    $shaped = Invoke-OrgChart "'BEGIN:text'; tkOrgChart; 'END:text'"
    Assert-Equal 'the whole shape: the title in the header, then the table''s lines' ("Org chart: The Branch Office (branch-office)`n`n" + (Read-Fixture $shapeCase.expect.text).TrimEnd("`n")) (Get-Section $shaped.All 'text') $shaped.All
    Assert-True '  a seat''s roleTitle stands in for the position''s title, with its session' ($shaped.All.Contains("Alpha lead $([char]0x00B7) claude-opus-5-5 [alpha] (lead-session)")) $shaped.All
    Assert-True '  and the seat that holds the merge says so' ($shaped.All.Contains("(product-session) $([char]0x00B7) merges")) $shaped.All
    [System.IO.File]::WriteAllText($orgPath, (Read-Fixture $validCase.orgFile), $utf8)

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

    # -- 4. The schema: Config/org.schema.json, validated for real ----------------------
    # docs/hub/org.md, "The schema". The sample hub's org.json is a file; each preset is one
    # tree, validated against the schema's tree. Test-Json -Schema is PowerShell 7's; Windows
    # PowerShell 5.1 has no Test-Json, and the agent suite (Tests/test_org.py) validates the
    # same files there with jsonschema.
    Write-Host ""
    Write-Host "-- The schema, Config/org.schema.json ------------------" -ForegroundColor Cyan
    if (-not (Get-Command Test-Json -ErrorAction SilentlyContinue)) {
        Write-Host "  SKIP  the schema cases: Windows PowerShell $($PSVersionTable.PSVersion) has no Test-Json (Tests/test_org.py validates the same files with jsonschema)" -ForegroundColor Yellow
    }
    else {
        $schemaText = [System.IO.File]::ReadAllText((Join-Path $pkgRoot 'Config/org.schema.json'))
        $schema = $schemaText | ConvertFrom-Json
        Assert-Equal 'the schema is draft 2020-12' 'https://json-schema.org/draft/2020-12/schema' $schema.'$schema'
        foreach ($def in $schema.'$defs'.PSObject.Properties) {
            Assert-True "  its $($def.Name) lets an unknown key through" ($def.Value.additionalProperties -eq $true)
        }
        # One part of the schema on its own: the file, or a tree (a preset is one tree).
        function Get-SchemaPart([string]$Part) {
            $one = $schemaText | ConvertFrom-Json
            $one.PSObject.Properties.Remove('oneOf')
            $one | Add-Member -NotePropertyName '$ref' -NotePropertyValue "#/`$defs/$Part" -Force
            return ($one | ConvertTo-Json -Depth 40)
        }
        $fileSchema = Get-SchemaPart 'file'
        $treeSchema = Get-SchemaPart 'tree'
        function Test-AgainstSchema([string]$Json, [string]$Schema) {
            $errs = $null
            $ok = $Json | Test-Json -Schema $Schema -ErrorAction SilentlyContinue -ErrorVariable errs
            return [pscustomobject]@{ Ok = [bool]$ok; Errors = (@($errs) | ForEach-Object { $_.ToString() }) -join '; ' }
        }
        $sampleText = [System.IO.File]::ReadAllText((Join-Path $pkgRoot 'samples/hub/org.json'))
        $r = Test-AgainstSchema $sampleText $fileSchema
        Assert-True 'the sample hub''s org.json is a valid file' $r.Ok $r.Errors
        $r = Test-AgainstSchema $sampleText $schemaText
        Assert-True '  and valid against the whole schema' $r.Ok $r.Errors
        $presetFiles = @(Get-ChildItem -LiteralPath (Join-Path $pkgRoot 'samples/org-presets') -Filter '*.json' | Sort-Object Name)
        Assert-Equal 'there are three presets' 3 $presetFiles.Count
        foreach ($file in $presetFiles) {
            $text = [System.IO.File]::ReadAllText($file.FullName)
            $r = Test-AgainstSchema $text $treeSchema
            Assert-True "the preset $($file.Name) is a valid tree" $r.Ok $r.Errors
            $r = Test-AgainstSchema $text $schemaText
            Assert-True "  and valid against the whole schema" $r.Ok $r.Errors
        }
        $r = Test-AgainstSchema (Read-Fixture 'docs/shape.json') $fileSchema
        Assert-True 'the table''s whole shape is a valid file' $r.Ok $r.Errors
        $refused = [ordered]@{
            'no trees'                    = @('{}', $fileSchema)
            'an empty trees'              = @('{"trees":[]}', $fileSchema)
            'a tree with no id'           = @('{"trees":[{"positions":[]}]}', $fileSchema)
            'two trees and no activeTree' = @('{"trees":[{"id":"a","positions":[]},{"id":"b","positions":[]}]}', $fileSchema)
            'a size that is not S, M, L'  = @('{"id":"t","positions":[],"size":"XL"}', $treeSchema)
            'a teamSize that is not 3/6/9' = @('{"id":"t","positions":[],"teamSize":4}', $treeSchema)
            'a recommend that is text'    = @('{"id":"t","positions":[{"id":"p","recommend":"opus"}]}', $treeSchema)
            'a seat with no id'           = @('{"id":"t","positions":[{"id":"p","seats":[{"model":"m"}]}]}', $treeSchema)
            'a merges that is text'       = @('{"id":"t","positions":[{"id":"p","seats":[{"id":"s","merges":"yes"}]}]}', $treeSchema)
        }
        foreach ($name in $refused.Keys) {
            $r = Test-AgainstSchema $refused[$name][0] $refused[$name][1]
            Assert-True "it refuses $name" (-not $r.Ok) $refused[$name][0]
        }
        $loose = '{"_note":"","colour":"x","trees":[{"id":"t","region":"x","machines":["a"],"positions":[{"id":"p","budget":1,"seats":[{"id":"s","badge":1,"machine":"a","active":true}]}]}]}'
        $r = Test-AgainstSchema $loose $fileSchema
        Assert-True 'it lets through an unknown key and a note at every level, and the retired keys' $r.Ok $r.Errors
    }

    # -- 5. Staff: the org file's one writer, typed ---------------------------------------
    # docs/hub/org.md, "The one writer". Every case types the verb in a fresh shell over
    # the scratch copy of samples/hub, and reads the file back as bytes.
    Write-Host ""
    Write-Host "-- Staff, the one writer, typed in a fresh shell -------" -ForegroundColor Cyan
    . (Join-Path $pkgRoot 'Scripts/Write-ConfigJson.ps1')
    # The serializer Staff writes with, over a table: one text on 5.1 and 7 alike.
    $serial = @(
        @{ Name = 'null, booleans, numbers'; Value = [ordered]@{ a = $null; b = $true; c = $false; d = 6; e = 6.5 }; Want = "{`n  `"a`": null,`n  `"b`": true,`n  `"c`": false,`n  `"d`": 6,`n  `"e`": 6.5`n}" }
        @{ Name = 'empty array and object'; Value = [ordered]@{ a = @(); b = [ordered]@{} }; Want = "{`n  `"a`": [],`n  `"b`": {}`n}" }
        @{ Name = 'nesting, two spaces a level, the order given'; Value = [ordered]@{ z = @([ordered]@{ y = 'x' }); a = 1 }; Want = "{`n  `"z`": [`n    {`n      `"y`": `"x`"`n    }`n  ],`n  `"a`": 1`n}" }
        @{ Name = 'non-ASCII as itself, not \u-escaped'; Value = ('Caf' + [char]0x00E9 + ' ' + [char]0x00B7); Want = ('"Caf' + [char]0x00E9 + ' ' + [char]0x00B7 + '"') }
        @{ Name = 'quote, backslash, newline, tab and a control escaped'; Value = ("a`"b\c`nd`te" + [char]1); Want = '"a\"b\\c\nd\te\u0001"' }
        @{ Name = 'a one-element array stays an array'; Value = [ordered]@{ a = @('x') }; Want = "{`n  `"a`": [`n    `"x`"`n  ]`n}" }
    )
    foreach ($row in $serial) { Assert-Equal "the serializer: $($row.Name)" $row.Want (ConvertTo-P20ConfigJson $row.Value) }
    $roundTrip = '{"_note":"2026-11-26T10:00:00Z","n":[1,2],"o":{"k":"v"}}'
    $parsed = $null
    if ((Get-Command ConvertFrom-Json).Parameters.ContainsKey('DateKind')) { $parsed = $roundTrip | ConvertFrom-Json -DateKind String } else { $parsed = $roundTrip | ConvertFrom-Json }
    Assert-Equal 'the serializer: a parsed file comes back the same, a timestamp note as its text' "{`n  `"_note`": `"2026-11-26T10:00:00Z`",`n  `"n`": [`n    1,`n    2`n  ],`n  `"o`": {`n    `"k`": `"v`"`n  }`n}" (ConvertTo-P20ConfigJson $parsed)

    $map = [System.IO.File]::ReadAllText((Join-Path $pkgRoot 'Config/models.json')) | ConvertFrom-Json
    $idOf = @{ opus = [string]$map.current.opus; fable = [string]$map.current.fable; sonnet = [string]$map.current.sonnet; haiku = [string]$map.current.haiku }
    function Read-Org { return ([System.IO.File]::ReadAllText($orgPath) | ConvertFrom-Json) }
    function Get-OrgTree($Doc, [string]$Id) { return (@($Doc.trees) | Where-Object { $_.id -ceq $Id } | Select-Object -First 1) }
    function Get-OrgSeat($TreeObj, [string]$PositionId) { return (@(@($TreeObj.positions | Where-Object { $_.id -ceq $PositionId } | Select-Object -First 1).seats)) }
    function Get-OrgBytes { if (Test-Path -LiteralPath $orgPath) { return [System.IO.File]::ReadAllBytes($orgPath) } return @() }
    function Test-SameBytes($A, $B) { return ((@($A) -join ',') -ceq (@($B) -join ',')) }
    Remove-Item -LiteralPath $orgPath -Force -ErrorAction SilentlyContinue
    # What Staff must never write: the package's sample hub and presets (the real tree's,
    # and the scratch package's presets, which are the ones the verb reads), snapshot now.
    $neverWritten = @((Join-Path $pkgRoot 'samples/hub'), (Join-Path $pkgRoot $presetsRel), (Join-Path $pkgDir $presetsRel))
    $neverBefore = @($neverWritten | ForEach-Object { Get-Snapshot $_ })

    # Off means absent: with Team Agile off there is no Staff verb.
    Write-Config $false
    $staffOff = Invoke-OrgChart "if (Get-Command tkStaff -ErrorAction SilentlyContinue) { 'VERB=present' } else { 'VERB=absent' }; 'MAP=' + ((Get-P20CommandMap) -match 'Staff')"
    Assert-True 'Team Agile off: there is no Staff verb' ($staffOff.All -match 'VERB=absent') $staffOff.All
    Assert-True '  and none in the bridge''s command table' ($staffOff.All -match 'MAP=False') $staffOff.All
    Write-Config $true
    $staffReg = Invoke-OrgChart "'MAP=' + (Get-P20CommandMap); tkStaff -Help"
    Assert-True 'Staff is in the command table the bridge reads' ($staffReg.All -match '"Staff":\s*"Set-P20Staff"') $staffReg.All
    Assert-True '  and -Help prints its usage' ($staffReg.All.Contains('tkStaff [-Preset <S|M|L>] [-Tree <id>]')) $staffReg.All

    # -WhatIf with no file: the file it would write, and nothing on disk.
    $snap = Get-Snapshot $hubDir
    $dry = Invoke-OrgChart "tkStaff -Preset S -Owner Sam -WhatIf"
    Assert-Equal '-WhatIf: exit 0' '0' $dry.Exit $dry.All
    Assert-True '  says what it would write' ($dry.All.Contains('What if: Staff would write') -and $dry.All.Contains('"preset": "executive-suite"')) $dry.All
    Assert-True '  and writes nothing' ((Get-Snapshot $hubDir) -ceq $snap)

    # Create the file.
    $made = Invoke-OrgChart "tkStaff -Preset S -Owner Sam; 'BEGIN:chart'; tkOrgChart; 'END:chart'"
    Assert-Equal 'Staff -Preset S with no org.json: exit 0' '0' $made.Exit $made.All
    Assert-True '  it says what it saved, and that the only org is the one in use' ($made.All.Contains("Wrote $orgPath") -and $made.All.Contains("Saved 'executive-suite'") -and $made.All.Contains('it is the only org, so it is the one in use.')) $made.All
    $bytes = Get-OrgBytes
    Assert-True '  the file is there, UTF-8 with no BOM' ($bytes.Length -gt 3 -and -not ($bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF))
    $made1 = [System.Text.Encoding]::UTF8.GetString($bytes)
    Assert-True '  LF on create, ending in one newline' (-not $made1.Contains("`r") -and $made1.EndsWith("}`n") -and -not $made1.EndsWith("`n`n"))
    Assert-True '  two-space JSON' ($made1.StartsWith("{`n  `"trees`": [`n    {`n      `"id`": `"executive-suite`",`n      `"preset`": `"executive-suite`",")) $made1
    $doc = Read-Org
    Assert-True '  one tree and no activeTree: the one tree is the one in use' (@($doc.trees).Count -eq 1 -and -not $doc.PSObject.Properties['activeTree'])
    $t = Get-OrgTree $doc 'executive-suite'
    Assert-Equal '  the tree names its preset' 'executive-suite' $t.preset
    Assert-True '  the preset file''s own note is not copied' (-not $t.PSObject.Properties['_comment'])
    Assert-Equal '  the owner is the person -Owner named, and no model' 'Sam|' ("$((Get-OrgSeat $t 'owner')[0].person)|$((Get-OrgSeat $t 'owner')[0].model)")
    Assert-Equal '  the VP of engineering: current.opus, as an id' $idOf.opus (Get-OrgSeat $t 'vp-engineering')[0].model
    Assert-Equal '  the VP of product: current.fable, as an id' $idOf.fable (Get-OrgSeat $t 'vp-product')[0].model
    Assert-True '  and the VP of product''s seat holds the merge' ((Get-OrgSeat $t 'vp-product')[0].merges -eq $true)
    Assert-Equal '  the builder pool''s line: current.sonnet, as an id' $idOf.sonnet (@($t.positions | Where-Object { $_.id -eq 'builder' })[0].defaultModel)
    Assert-True '  and the result is a chart OrgChart reads' ((Get-Section $made.All 'chart').Contains("VP of product $dot $($idOf.fable) $dot merges")) $made.All

    # Hand edits survive, and an edited file keeps its own line ending.
    $hand = $made1.Replace("{`n  `"trees`"", "{`n  `"_note`": `"mine`",`n  `"trees`"").Replace("`"preset`": `"executive-suite`",", "`"preset`": `"executive-suite`",`n      `"colour`": `"teal`",").Replace("`n", "`r`n")
    [System.IO.File]::WriteAllText($orgPath, $hand, $utf8)
    $second = Invoke-OrgChart "tkStaff -Preset S -Title 'A second suite' 3>`$null"
    Assert-Equal 'a second tree from the same preset: exit 0' '0' $second.Exit $second.All
    $text2 = [System.IO.File]::ReadAllText($orgPath)
    Assert-True '  the edited CRLF file stays CRLF, with no bare LF' ($text2.Contains("`r`n") -and -not ($text2.Replace("`r`n", '').Contains("`n"))) $text2
    $doc = Read-Org
    Assert-Equal '  its id is the preset''s, then -2' 'executive-suite,executive-suite-2' (@($doc.trees | ForEach-Object { $_.id }) -join ',')
    Assert-Equal '  -Title names it' 'A second suite' (Get-OrgTree $doc 'executive-suite-2').title
    Assert-Equal '  the owner is the preset''s You without -Owner' 'You' (Get-OrgSeat (Get-OrgTree $doc 'executive-suite-2') 'owner')[0].person
    Assert-Equal '  two trees now, so activeTree names the first, and comes first; the note and the rest keep their order' 'activeTree,_note,trees' (@($doc.PSObject.Properties.Name) -join ',')
    Assert-Equal '  the first tree is still the one in use: the new one is a draft' 'executive-suite' $doc.activeTree
    Assert-True '  and the output says so' ($second.All.Contains("Saved 'executive-suite-2'") -and $second.All.Contains("as a draft; 'executive-suite' stays active.")) $second.All
    Assert-Equal '  a hand-made key in the first tree is kept' 'teal' (Get-OrgTree $doc 'executive-suite').colour

    # An id that is already a tree is refused, never overwritten.
    $before = Get-OrgBytes
    $dup = Invoke-OrgChart "tkStaff -Preset M -Tree executive-suite"
    Assert-Equal 'an existing tree id: exit 2' '2' $dup.Exit $dup.All
    Assert-True '  says why, naming the trees' ($dup.All.Contains("'executive-suite' is already a tree in org.json, and a tree is never overwritten. Trees: executive-suite, executive-suite-2.")) $dup.All
    Assert-True '  and writes nothing' (Test-SameBytes $before (Get-OrgBytes))

    # A third tree, with the VPs given: still a draft, and the tree in use stays.
    $third = Invoke-OrgChart "tkStaff -Preset M -Tree branch -VpEngineering claude-sonnet-5-5 -VpProduct opus 3>`$null; 'BEGIN:branch'; tkOrgChart -Tree branch 3>`$null; 'END:branch'"
    Assert-Equal 'a third tree: exit 0' '0' $third.Exit $third.All
    $doc = Read-Org
    $b3 = Get-OrgTree $doc 'branch'
    Assert-Equal '  the tree in use stays as it was' 'executive-suite' $doc.activeTree
    Assert-Equal '  -VpEngineering takes a model id as it is' 'claude-sonnet-5-5' (Get-OrgSeat $b3 'vp-engineering')[0].model
    Assert-Equal '  -VpProduct takes a family, stored as its id' $idOf.opus (Get-OrgSeat $b3 'vp-product')[0].model
    Assert-Equal '  the team lead''s seat is current.opus, by its role (team-lead.prompt.md), whatever its office is called' $idOf.opus (@((Get-OrgSeat $b3 'lead-team') | ForEach-Object { $_.model }) -join ',')
    Assert-Equal '  and the team''s own builder pool''s line is current.sonnet' $idOf.sonnet (@($b3.positions | Where-Object { $_.id -eq 'builders-team' })[0].defaultModel)
    Assert-True '  the test runner starts vacant' (-not (Get-OrgSeat $b3 'test-runner')[0].PSObject.Properties['model'])
    Assert-True '  OrgChart -Tree prints the draft, not the tree in use' ((Get-Section $third.All 'branch').StartsWith('Org chart: The Branch Office (branch) -- not the tree in use (executive-suite)')) $third.All

    # A fourth tree is refused, naming the three.
    $before = Get-OrgBytes
    $fourth = Invoke-OrgChart "tkStaff -Preset L"
    Assert-Equal 'a fourth tree: exit 2' '2' $fourth.Exit $fourth.All
    Assert-True '  names the three' ($fourth.All.Contains('org.json already holds 3 trees (executive-suite, executive-suite-2, branch): a file holds at most 3')) $fourth.All
    Assert-True '  and writes nothing' (Test-SameBytes $before (Get-OrgBytes))

    # -Activate alone.
    $act = Invoke-OrgChart "tkStaff -Activate executive-suite-2"
    Assert-Equal '-Activate <tree-id>: exit 0' '0' $act.Exit $act.All
    Assert-Equal '  it is the tree in use' 'executive-suite-2' (Read-Org).activeTree
    $before = Get-OrgBytes
    $again = Invoke-OrgChart "tkStaff -Activate executive-suite-2"
    Assert-True '  again: already in use, nothing written' ($again.Exit -eq '0' -and $again.All.Contains('nothing was written') -and (Test-SameBytes $before (Get-OrgBytes))) $again.All
    $actDry = Invoke-OrgChart "tkStaff -Activate branch -WhatIf"
    Assert-True '  -WhatIf: says so, and writes nothing' ($actDry.Exit -eq '0' -and $actDry.All.Contains('What if:') -and (Test-SameBytes $before (Get-OrgBytes))) $actDry.All

    # Refusals: exit 2, the sentence, nothing written.
    $staffRefusals = [ordered]@{
        'no switch'                          = @('tkStaff', 'Nothing to do: give -Preset S|M|L')
        'an unknown -Activate tree'          = @('tkStaff -Activate nope', "-Activate names 'nope', which is not a tree in org.json. Trees: executive-suite, executive-suite-2, branch.")
        'a size that is not a preset'        = @('tkStaff -Preset XL', "-Preset 'XL' is not a preset size. The presets are: S, M, L.")
        'a model that is not in the map'     = @('tkStaff -Preset S -Tree x -VpProduct gpt-9', "-VpProduct 'gpt-9' is not a model id or a family in Config/models.json.")
        '-Owner without -Preset'             = @('tkStaff -Activate branch -Owner Sam', '-Owner goes with -Preset')
        '-Activate with -Preset'             = @('tkStaff -Preset S -Tree x -Activate', '-Activate does not go with -Preset: a saved tree is a draft')
    }
    foreach ($name in $staffRefusals.Keys) {
        $before = Get-OrgBytes
        $ran = Invoke-OrgChart $staffRefusals[$name][0]
        Assert-Equal "Staff refused ($name): exit 2" '2' $ran.Exit $ran.All
        Assert-True "  says why, once" (([regex]::Matches($ran.All, [regex]::Escape($staffRefusals[$name][1]))).Count -eq 1) $ran.All
        Assert-True "  and writes nothing" (Test-SameBytes $before (Get-OrgBytes))
    }
    # An invalid file is refused before anything is changed.
    [System.IO.File]::WriteAllText($orgPath, ($cycleRow.org | ConvertTo-Json -Depth 20), $utf8)
    $before = Get-OrgBytes
    $bad = Invoke-OrgChart "tkStaff -Activate a"
    Assert-Equal 'Staff over an invalid file: exit 2' '2' $bad.Exit $bad.All
    Assert-True '  says the file is not valid now, with the reader''s sentence' ($bad.All.Contains('is not valid now, so nothing was written') -and $bad.All.Contains($cycleRow.expect.message)) $bad.All
    Assert-True '  and writes nothing' (Test-SameBytes $before (Get-OrgBytes))

    # The L preset's defaults, in a file of its own.
    Remove-Item -LiteralPath $orgPath -Force
    $large = Invoke-OrgChart "tkStaff -Preset L -Tree hq"
    Assert-Equal 'Staff -Preset L: exit 0' '0' $large.Exit $large.All
    $hq = Get-OrgTree (Read-Org) 'hq'
    Assert-Equal '  the intern and the butler: current.haiku' "$($idOf.haiku),$($idOf.haiku)" ("$((Get-OrgSeat $hq 'intern')[0].model),$((Get-OrgSeat $hq 'butler')[0].model)")
    Assert-True '  the PM, the test runner and the merge stand-in start vacant' (@('pm', 'test-runner', 'merge-stand-in' | ForEach-Object { (Get-OrgSeat $hq $_)[0].PSObject.Properties['model'] } | Where-Object { $_ }).Count -eq 0)
    Assert-Equal '  the preset''s own id is kept as its preset' 'corporate-headquarters' $hq.preset
    Assert-Equal '  each team''s lead is current.opus, one lead to a team' "$($idOf.opus),$($idOf.opus)" ("$((Get-OrgSeat $hq 'lead-team-1')[0].model),$((Get-OrgSeat $hq 'lead-team-2')[0].model)")
    Assert-Equal '  and each team''s own pool''s line current.sonnet' "$($idOf.sonnet),$($idOf.sonnet)" ((@('builders-team-1', 'builders-team-2' | ForEach-Object { $id = $_; @($hq.positions | Where-Object { $_.id -eq $id })[0].defaultModel })) -join ',')
    Assert-True '  and no team is bound to a Space: binding one is a later step' (@('lead-team-1', 'lead-team-2' | ForEach-Object { (Get-OrgSeat $hq $_)[0].PSObject.Properties['space'] } | Where-Object { $_ }).Count -eq 0)

    # -Activate on a one-tree file with no activeTree: that tree is already in use.
    $before = Get-OrgBytes
    $lone = Invoke-OrgChart "tkStaff -Activate hq"
    Assert-True '-Activate on the only tree of a file with no activeTree: already in use, exit 0, nothing written' (
        $lone.Exit -eq '0' -and $lone.All.Contains("'hq' is already the tree in use") -and $lone.All.Contains('nothing was written') -and (Test-SameBytes $before (Get-OrgBytes))) $lone.All
    # A -Tree that is not a plain word is refused, so the printed -Activate hint always types.
    $badId = Invoke-OrgChart "tkStaff -Preset S -Tree 'our org!'"
    Assert-True 'a -Tree that is not a plain word: exit 2, the sentence, nothing written' (
        $badId.Exit -eq '2' -and $badId.All.Contains("-Tree 'our org!' is not a plain word: a tree id is letters, digits, - and _.") -and (Test-SameBytes $before (Get-OrgBytes))) $badId.All
    # A VP's model given by id needs no default: a map whose current names no fable still saves it.
    $mapPath = Join-Path $pkgDir 'Config/models.json'
    $mapText = [System.IO.File]::ReadAllText($mapPath)
    $noFable = $mapText | ConvertFrom-Json
    $noFable.current.PSObject.Properties.Remove('fable')
    [System.IO.File]::WriteAllText($mapPath, ($noFable | ConvertTo-Json -Depth 10), $utf8)
    try {
        $given = Invoke-OrgChart "tkStaff -Preset S -Tree given -VpProduct claude-opus-5-5"
        Assert-Equal 'a VP model given, with no default for it in the map: exit 0' '0' $given.Exit $given.All
        Assert-Equal '  and the given model is the one stored' 'claude-opus-5-5' (Get-OrgSeat (Get-OrgTree (Read-Org) 'given') 'vp-product')[0].model
        $before = Get-OrgBytes
        $none = Invoke-OrgChart "tkStaff -Preset S -Tree none"
        Assert-True '  with none given, the missing default is refused, nothing written' ($none.Exit -eq '2' -and $none.All.Contains("the default 'fable' is not a model id or a family") -and (Test-SameBytes $before (Get-OrgBytes))) $none.All
    }
    finally { [System.IO.File]::WriteAllText($mapPath, $mapText, $utf8) }
    # A write that fails leaves the old file as it was: a hub folder nobody may write to.
    if ($IsWindows -or $env:OS -eq 'Windows_NT') {
        Write-Host "  SKIP  a failed write leaving org.json intact: a read-only folder does not refuse a new file on Windows; the macOS and Linux runs prove it" -ForegroundColor Yellow
    }
    else {
        $before = Get-OrgBytes
        & chmod 555 $hubDir
        try { $locked = Invoke-OrgChart "tkStaff -Activate given" }
        finally { & chmod 755 $hubDir }
        Assert-Equal 'a write that fails: exit 2' '2' $locked.Exit $locked.All
        Assert-True '  says it could not write, and that the file is as it was' ($locked.All.Contains("Could not write $orgPath") -and $locked.All.Contains('the file is as it was')) $locked.All
        Assert-True '  the old file is intact, byte for byte' (Test-SameBytes $before (Get-OrgBytes))
        Assert-True '  and no temp file is left beside it' (-not (Test-Path -LiteralPath "$orgPath.p20tmp"))
    }
    # -Activate with no org.json is refused, and creates nothing.
    Remove-Item -LiteralPath $orgPath -Force
    $noFile = Invoke-OrgChart "tkStaff -Activate hq"
    Assert-True '-Activate with no org.json: exit 2, the sentence, no file made' (
        $noFile.Exit -eq '2' -and $noFile.All.Contains('There is no org.json in the hub, so there is no tree to put in use.') -and -not (Test-Path -LiteralPath $orgPath)) $noFile.All
    for ($i = 0; $i -lt $neverWritten.Count; $i++) {
        Assert-True "Staff never wrote $($neverWritten[$i].Replace($root, '<scratch>').Replace($pkgRoot, '<package>')): every file the same bytes as before its cases" ((Get-Snapshot $neverWritten[$i]) -ceq $neverBefore[$i])
    }
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
