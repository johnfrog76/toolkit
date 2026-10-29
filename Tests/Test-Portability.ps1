<#
.SYNOPSIS
    Portability suite -- could a stranger clone this and use it?

.DESCRIPTION
    The README claims the tool is forkable and that your cards are yours. That is
    a promise, so it gets a test.

    Every clause here exists because the same defect kept recurring in a different
    costume: a prefix baked into a string, an address baked into a parameter
    default, one person's ADO org shipped as the committed default. Noticing them
    one at a time does not scale -- only the ones someone happens to look at get
    found. These clauses fail the build instead.

    Clause 3 is a RATCHET, not a zero. There was real existing debt and
    failing the whole suite on it would just get the suite ignored. It freezes the
    count so the debt cannot grow, and the number comes down as it is worked.
#>

[CmdletBinding()]
param([switch]$Help)

if ($Help) {
    Write-Host @"

  Test-Portability -- can someone else use this?

  Clause 1  No real email addresses in source
  Clause 2  config.default.json ships a template org, not a real one
  Clause 3  Hardcoded command prefix in runtime strings (ratchet; docs/CLI.md, "The prefix")
  Clause 10 No `$script: read inside a global function body (ratchet 0)
  Clause 4  No absolute machine paths in shipped scripts
  Clause 5  No credentials in committed files; .gitignore excludes .env
  Clause 6  Nothing vendor-shaped is committed; AGENTS.md is the source
  Clause 7  Relative links in shipped docs resolve inside the package
  Clause 8  The README's logo matches docs/logo.txt
  Clause 9  config.local.json's documented shape is the shape the merge implements
  Clause 11 Every suite's top-level try ends with a catch
  Clause 12 Every Assert- call in a suite resolves to a helper it defines or loads
  Clause 17 Every suite's last statement is its own exit (exit 0 after a failure exit, or exit <verdict>)
  Clause 13 No work-marker comment (the four words a seam must not hide behind) ships
  Clause 14 No comment carries a date, a name, an agent, a nickname for a host, a tracker
            number, an archive pointer, a private repository or a machine path
  Clause 15 No gh, az or git call with a redirected stderr outside Invoke-TrackerRead.ps1
  Clause 16 No script in Scripts/ carries its own Get-CliPrefix or Write-CliError fallback;
            Scripts/Initialize-CliFallbacks.ps1 is the one copy

  Scope: all three halves -- *.psm1 at the root, Scripts/, Prompt20Toolkit/,
  web/src, web/tests and agent/ -- plus root JSON and Markdown, and Tests/
  for clause 5. Clause 3 is wider again: it also reads Tests/, *.psd1,
  config.default.json, Config/, and the shipped Markdown (agentic/, templates/,
  docs/, the READMEs, VERIFY.md), and it does not exempt comments -- a
  namespace that must not be in the package is wrong in a comment too.
  Vendored and generated folders are excluded at any depth
  (Tests/ScanExclusions.ps1). Tests/fixtures/ is not scanned: a fixture is
  meant to look like real input and needs its own rule.

"@
    return
}

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$pkgRoot   = Split-Path $scriptDir -Parent

$script:passed = 0
$script:failed = 0
$script:errors = @()

# A bare file name stopped being enough when the scan grew to three halves:
# there is more than one __init__.py and more than one index.ts. Report the path
# a reader can open.
function Get-RelPath {
    param($File)
    $full = $File.FullName
    if ($full.StartsWith($pkgRoot)) { $full = $full.Substring($pkgRoot.Length).TrimStart('\', '/') }
    return ($full -replace '\\', '/')
}

function Assert-True {
    param([string]$Name, [bool]$Condition, [string]$Detail = '')
    if ($Condition) {
        $script:passed++
        Write-Host "  PASS  $Name" -ForegroundColor Green
    }
    else {
        $script:failed++
        Write-Host "  FAIL  $Name" -ForegroundColor Red
        if ($Detail) {
            Write-Host "        $Detail" -ForegroundColor DarkYellow
            $script:errors += "$Name -- $Detail"
        }
    }
}

# The vendored/generated folders no sweep descends into. Shared with
# Test-PS51Compat, which had the same omission from the other direction --
# see Tests/ScanExclusions.ps1.
. (Join-Path $scriptDir 'ScanExclusions.ps1')

# Runtime source only. Tests may legitimately name things that shipped code may not.
#
# All THREE halves, not one. This set once stopped at the CLI, so the
# clauses that cost the most when they fail -- a committed address, a client's org
# URL, a token, a machine path -- ran over about a third of the shipped code while
# the newest code sat in web/ and agent/. The two halves were scrubbed by hand once
# when they were carved, which works exactly once.
#
# Tests/fixtures/ is deliberately NOT here. A fixture's whole job is to be a
# realistic input, so it needs its own rule rather than this one; clause 5 still
# sweeps Tests/ for secrets.
function Get-RuntimeFiles {
    $files = @()
    $root = Get-ChildItem (Join-Path $pkgRoot '*.psm1') -File -ErrorAction SilentlyContinue
    if ($root) { $files += $root }
    foreach ($d in @('Scripts', 'Prompt20Toolkit')) {
        $dir = Join-Path $pkgRoot $d
        if (Test-Path $dir) {
            $files += Get-ChildItem $dir -Include '*.ps1', '*.psm1' -Recurse -File -ErrorAction SilentlyContinue
        }
    }
    # The web shell and its browser smoke, and the whole agent package.
    foreach ($spec in @(
        @{ Dir = 'web/src';   Include = @('*.ts', '*.tsx') }
        @{ Dir = 'web/tests'; Include = @('*.ts', '*.tsx', '*.mjs') }
        @{ Dir = 'agent';     Include = @('*.py') }
    )) {
        $dir = Join-Path $pkgRoot $spec.Dir
        if (Test-Path $dir) {
            $files += Get-ChildItem $dir -Include $spec.Include -Recurse -File -ErrorAction SilentlyContinue
        }
    }
    return @($files | Select-ScannableFile)
}

# Clause 3's file set, which is wider than the runtime one on purpose.
#
# A prefix that belongs to another product is wrong wherever it is written: in a
# test that RUNS it, in the generated manifest that EXPORTS it, in the config
# that ships it, and in the docs and examples a reader copies from. Restricting
# the sweep to shipped runtime code is how ~70 occurrences in 18 files sat under
# a clause whose baseline was zero.
#
# Tests/fixtures/ stays out for the usual reason: a fixture is meant to look
# like real input.
function Get-PrefixScanFiles {
    $files = @()
    $root = Get-ChildItem (Join-Path $pkgRoot '*.psm1') -File -ErrorAction SilentlyContinue
    if ($root) { $files += $root }
    foreach ($name in @('README.md', 'AGENTS.md', 'VERIFY.md', 'config.default.json')) {
        $path = Join-Path $pkgRoot $name
        if (Test-Path $path) { $files += Get-Item $path }
    }
    foreach ($spec in @(
        @{ Dir = 'Scripts';          Include = @('*.ps1', '*.psm1') }
        @{ Dir = 'Prompt20Toolkit';  Include = @('*.ps1', '*.psm1', '*.psd1') }
        @{ Dir = 'Config';           Include = @('*.ps1', '*.psd1') }
        @{ Dir = 'Tests';            Include = @('*.ps1', '*.py') }
        @{ Dir = 'agent';            Include = @('*.py', '*.ps1', '*.md') }
        @{ Dir = 'web/src';          Include = @('*.ts', '*.tsx') }
        @{ Dir = 'web/tests';        Include = @('*.ts', '*.tsx', '*.mjs') }
        @{ Dir = 'agentic';          Include = @('*.md') }
        @{ Dir = 'templates';        Include = @('*.md') }
        @{ Dir = 'docs';             Include = @('*.md') }
    )) {
        $dir = Join-Path $pkgRoot $spec.Dir
        if (-not (Test-Path $dir)) { continue }
        $files += Get-ChildItem $dir -Include $spec.Include -Recurse -File -ErrorAction SilentlyContinue
    }
    $files = @($files | Where-Object { $_.FullName -notmatch '[\\/]Tests[\\/]fixtures[\\/]' })
    return @($files | Select-ScannableFile)
}

# A comment naming a prefix is documentation, not behaviour. Only lines that can
# reach a user count.
#
# Three languages now, so three comment syntaxes: PowerShell and Python share `#`,
# TypeScript adds `//` and a `/* ... */` block that spans lines. A block needs
# state the caller carries, which is what -BlockComment is for: pass a [ref] to a
# per-file boolean and reset it between files. Without it every explanatory comment
# in web/src became a candidate hit the moment that tree entered the scan.
function Test-IsCode {
    param([string]$Line, [ref]$BlockComment)

    $t = $Line.Trim()

    if ($null -ne $BlockComment -and $BlockComment.Value) {
        # Inside /* ... */. The closing marker ends it; the rest of that line is
        # conservatively still treated as comment.
        if ($t -match '\*/') { $BlockComment.Value = $false }
        return $false
    }

    if ($t -eq '') { return $false }
    if ($t.StartsWith('#')) { return $false }   # PowerShell and Python
    if ($t.StartsWith('.')) { return $false }   # comment-based help directives
    if ($t.StartsWith('//')) { return $false }  # TypeScript line comment
    if ($t.StartsWith('*')) { return $false }   # continuation line of a /* */ or JSDoc block
    if ($t.StartsWith('/*')) {
        if (($null -ne $BlockComment) -and ($t -notmatch '\*/')) { $BlockComment.Value = $true }
        return $false
    }

    # An exemption must be WRITTEN DOWN next to the line it excuses. A marker with
    # no reason after it is not an exemption -- the point is to make the author
    # justify it, not to provide a way to silence the check. It works the same in
    # a `#` comment, a `//` comment and a trailing one of either.
    if ($t -match 'portability-ok:\s*\S') { return $false }
    return $true
}

Write-Host ""
Write-Host "  Portability -- could someone else use this?" -ForegroundColor Cyan
Write-Host "  ─────────────────────────────────────────────" -ForegroundColor DarkGray
Write-Host ""

$runtimeFiles = Get-RuntimeFiles
Assert-True "Found runtime files to scan" ($runtimeFiles.Count -gt 0)

# ── Clause 1: no real email addresses ────────────────────────────────────────
# example.com / example.org / example.net are RFC 2606 reserved; contoso.com is
# Microsoft's documentation domain. Those are deliberately not real.
$reserved = @('example.com', 'example.org', 'example.net', 'contoso.com', 'localhost')
$emailPattern = '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}'
$emailHits = @()

foreach ($f in ($runtimeFiles + @(Get-ChildItem (Join-Path $pkgRoot '*.json') -File -ErrorAction SilentlyContinue))) {
    if ($f.Name -like 'config.local*') { continue }   # gitignored, personal by design
    $lineNo = 0
    $blk = $false
    foreach ($line in (Get-Content $f.FullName -ErrorAction SilentlyContinue)) {
        $lineNo++
        if (-not (Test-IsCode $line ([ref]$blk))) { continue }
        foreach ($m in [regex]::Matches($line, $emailPattern)) {
            $addr = $m.Value.ToLower()
            $isReserved = $false
            foreach ($r in $reserved) { if ($addr.EndsWith($r)) { $isReserved = $true } }
            if (-not $isReserved) { $emailHits += "$(Get-RelPath $f):$lineNo  $($m.Value)" }
        }
    }
}
Assert-True "Clause 1: no real email addresses in source" ($emailHits.Count -eq 0) ($emailHits -join '; ')

# ── Clause 2: the committed config ships a template, not someone's org ──────
$defaultCfgPath = Join-Path $pkgRoot 'config.default.json'
if (-not (Test-Path $defaultCfgPath)) {
    Assert-True "Clause 2: config.default.json exists" $false 'file not found'
}
else {
    $cfg = Get-Content $defaultCfgPath -Raw | ConvertFrom-Json
    $realOrgs = @()
    $realTenants = @()
    foreach ($o in @($cfg.spaces)) {
        if ($o.org -and ($o.org -notmatch 'YOUR-') -and ($o.org -notmatch 'example')) {
            $realOrgs += "$($o.slug) -> $($o.org)"
        }
        if ($o.tenant -and $o.tenant.Trim() -ne '') {
            $realTenants += "$($o.slug) -> $($o.tenant)"
        }
    }
    Assert-True "Clause 2a: no real ADO org URL in config.default.json" ($realOrgs.Count -eq 0) `
        (($realOrgs -join '; ') + ' -- put it in config.local.json under spaces.<slug>')
    Assert-True "Clause 2b: no tenant id in config.default.json" ($realTenants.Count -eq 0) `
        (($realTenants -join '; ') + ' -- a tenant guid identifies a specific organisation')
    Assert-True "Clause 2c: email is not committed" ([string]::IsNullOrWhiteSpace($cfg.email)) `
        'config.default.json carries an email; it belongs in config.local.json'
}

# ── Clause 3: hardcoded command prefix (RATCHET) ─────────────────
# The debt is paid: the baseline is zero and must stay there. Every user-facing
# string now resolves the prefix at runtime. If this fails, something hardcoded
# a prefix again -- use $(Get-CliPrefix) in a string, $MyInvocation.InvocationName
# in a wrapper, or {cliPrefix} in a comment.
$PrefixDebtBaseline = 0

# THREE shapes, and no longer only inside quotes.
#
# A prefix welded to a verb was caught from the start. The GLOB was not: it is
# how a message refers to the whole namespace ("after adding a <prefix>*
# command"), it is just as wrong in a repo whose prefix is `tk`, and a prefix
# followed by `*` is not a prefix followed by [A-Z]. The copy-mode hint in
# Install-ToolkitAutoload.ps1 carried one for the life of this repo and this
# clause read it as clean.
# The third is the BARE
# literal fallback -- the one that answers with another product's namespace
# whenever config cannot be read, and the one that wrote the wrong prefix into
# a user's card.
#
# The requirement for an opening quote on the same line is gone with them: it
# missed every here-string body, which is where a -Help block lives, and the
# runner's help named the legacy runner five times underneath a clean sweep.
#
# And the scan is wider than the runtime set. `Tests/`, `*.psd1`,
# `config.default.json` and the shipped Markdown were never read, so the suite
# that ran the legacy commands, the manifest that exported legacy nav aliases
# and the docs that named them were all invisible.
#
$prefixPattern = '\bgo(\*|[A-Z][A-Za-z0-9]*)|[''"]go[''"]'
$prefixCount = 0
$prefixWorst = @{}
foreach ($f in (Get-PrefixScanFiles)) {
    $n = 0
    foreach ($line in (Get-Content $f.FullName -ErrorAction SilentlyContinue)) {
        # A comment is NOT exempt here, unlike the other clauses. This clause is
        # about a namespace that must not appear in the package at all -- an
        # example in a comment is read and copied, and a `#` in front of it
        # changes nothing about that (the rule: "go should
        # not be in anywhere in toolkit").
        if ($line -match 'portability-ok:') { continue }
        # -cmatch, NOT -match: PowerShell matches case-insensitively by default, so
        # go[A-Z] happily matched "got", "Good" and "going" and this clause spent
        # its life counting ordinary English as hardcoded prefixes.
        if ($line -cmatch $prefixPattern) { $n++ }
    }
    if ($n -gt 0) { $prefixWorst[(Get-RelPath $f)] = $n }
    $prefixCount += $n
}

$detail = "found $prefixCount, baseline $PrefixDebtBaseline"
if ($prefixCount -gt $PrefixDebtBaseline) {
    $top = ($prefixWorst.GetEnumerator() | Sort-Object Value -Descending |
        Select-Object -First 3 | ForEach-Object { "$($_.Key)=$($_.Value)" }) -join ', '
    $detail = "$detail -- NEW hardcoded prefixes added. Worst: $top. Use `$MyInvocation.InvocationName or {cliPrefix}."
}
Assert-True "Clause 3: hardcoded prefix debt has not grown" ($prefixCount -le $PrefixDebtBaseline) $detail

# The clause's own regression cases: real lines that were in this package and
# swept clean. A pattern that stops matching one of these is the hole reopening,
# and it would reopen silently -- a sweep that finds nothing looks identical
# whether it is looking properly or not.
$knownPrefixLeaks = @(
    @{ Why = 'the glob in a message names the whole namespace, and is as wrong as a welded verb'
       Line = 'Write-Host "     after adding a go* command, or it won''t resolve in agent shells."' }  # portability-ok: a control has to BE the shape it proves is caught
    @{ Why = 'a here-string body has no opening quote on the line -- the runner''s -Help was five of these'
       Line = '    goTestToolkit -List               List available suites' }  # portability-ok: control
    @{ Why = 'a bare fallback answers with another product''s namespace when config cannot be read'
       Line = '$probePrefix = ''go''' }  # portability-ok: control
    @{ Why = 'a comment is read and copied like any other line'
       Line = '# Or:   goTestToolkit -Archive' }  # portability-ok: control
    @{ Why = 'a generated manifest exports the name it lists'
       Line = '        ''goHome'',' }  # portability-ok: control
)
foreach ($leak in $knownPrefixLeaks) {
    Assert-True "Clause 3: the sweep catches -- $($leak.Why)" ($leak.Line -cmatch $prefixPattern) $leak.Line
}

# ...and the shapes it must NOT match, or the clause is noise and gets ignored.
$prefixFalsePositives = @(
    'if ($goal -gt 0) { return $goal }'
    '# going forward, the good case is the one that got here'
    'const cargo = "Google"'
)
foreach ($ok in $prefixFalsePositives) {
    Assert-True "Clause 3: ordinary English is not a prefix -- $ok" (-not ($ok -cmatch $prefixPattern)) $ok
}

if ($prefixCount -lt $PrefixDebtBaseline) {
    Write-Host "  NOTE  prefix debt is down to $prefixCount (baseline $PrefixDebtBaseline) -- lower the baseline in this file" -ForegroundColor DarkCyan
}

# -- Clause 5: no secrets ------------------------------------------------------
# The highest-severity thing that can reach a commit. Matches the shapes of real
# credentials rather than the word "key", because a variable NAMED apiKey is
# correct code -- a literal sk-ant-... next to it is not.
$secretPatterns = @(
    @{ Name = 'Anthropic API key';  Pattern = 'sk-ant-[A-Za-z0-9_\-]{10,}' }
    @{ Name = 'OpenAI API key';     Pattern = 'sk-[A-Za-z0-9]{32,}' }
    @{ Name = 'GitHub token';       Pattern = 'gh[pousr]_[A-Za-z0-9]{20,}' }
    @{ Name = 'Azure DevOps PAT';   Pattern = '(?i)(pat|token)\s*=\s*[''"][A-Za-z0-9]{40,}[''"]' }
    @{ Name = 'Bearer literal';     Pattern = '(?i)bearer\s+[A-Za-z0-9_\-\.]{30,}' }
    @{ Name = 'Private key block';  Pattern = 'BEGIN (RSA |OPENSSH |EC )?PRIVATE KEY' }
)
$secretHits = @()
$scanFiles = @($runtimeFiles)
$scanFiles += @(Get-ChildItem $pkgRoot -Include '*.json', '*.md' -File -ErrorAction SilentlyContinue)
$testDir = Join-Path $pkgRoot 'Tests'
if (Test-Path $testDir) {
    $scanFiles += @(Get-ChildItem $testDir -Include '*.ps1', '*.md' -Recurse -File -ErrorAction SilentlyContinue)
}
foreach ($f in $scanFiles) {
    if ($f.Name -like 'config.local*') { continue }   # gitignored
    if ($f.Name -eq 'Test-Portability.ps1') { continue }   # holds the patterns themselves
    $lineNo = 0
    foreach ($line in (Get-Content $f.FullName -ErrorAction SilentlyContinue)) {
        $lineNo++
        foreach ($sp in $secretPatterns) {
            if ($line -match $sp.Pattern) { $secretHits += "$($f.Name):$lineNo  $($sp.Name)" }
        }
    }
}
Assert-True "Clause 5: no credentials in committed files" ($secretHits.Count -eq 0) ($secretHits -join '; ')

# A .env must never become trackable, whatever else changes.
$gitignore = Join-Path $pkgRoot '.gitignore'
$ignoresEnv = $false
if (Test-Path $gitignore) {
    foreach ($l in (Get-Content $gitignore)) { if ($l.Trim() -eq '.env') { $ignoresEnv = $true } }
}
Assert-True "Clause 5b: .gitignore excludes .env" $ignoresEnv '.env is where the API key lives'

# ── Clause 4: no absolute machine paths in shipped scripts ──────────────────
# One documented exception: the autoload shim's last-resort WS_ROOT fallback,
# which warns and names the fix rather than failing silently.
$absPattern = '[''"][A-Za-z]:[\\/]|[''"]/Users/|[''"]/home/'  # export:example
$absHits = @()
foreach ($f in $runtimeFiles) {
    if ($f.Name -eq 'Prompt20Toolkit.psm1') { continue }
    $lineNo = 0
    $blk = $false
    foreach ($line in (Get-Content $f.FullName -ErrorAction SilentlyContinue)) {
        $lineNo++
        if (-not (Test-IsCode $line ([ref]$blk))) { continue }
        if ($line -match $absPattern) { $absHits += "$(Get-RelPath $f):$lineNo" }
    }
}
Assert-True "Clause 4: no absolute machine paths in shipped scripts" ($absHits.Count -eq 0) ($absHits -join '; ')

# -- Clause 6: nothing vendor-shaped is committed -------------------------------
# The client picks the assistant, not us, so the repo must not favour one. The
# knowledge lives in AGENTS.md, which is neutral; each assistant's own discovery
# file is generated per machine and gitignored. A committed .claude/ or
# copilot-instructions.md would be a near-duplicate of AGENTS.md in one vendor's
# wrapping -- exactly the box this arrangement exists to stay out of.
$agentsPath = Join-Path $pkgRoot 'AGENTS.md'
Assert-True "Clause 6a: AGENTS.md exists as the neutral source" (Test-Path $agentsPath) `
    'agent guidance must have a vendor-neutral home'

$vendorPaths = @('.claude', '.cursor', '.cursorrules', '.windsurfrules', '.github/copilot-instructions.md')
$trackedVendor = @()
Push-Location $pkgRoot
try {
    $tracked = @(git ls-files 2>$null)
    foreach ($v in $vendorPaths) {
        $needle = $v
        foreach ($t in $tracked) {
            if ($t -eq $needle -or $t.StartsWith($needle + '/')) { $trackedVendor += $t }
        }
    }
}
catch {
    Assert-True 'the cases ran to the end without a terminating error' $false $_.Exception.Message
}
finally { Pop-Location }
Assert-True "Clause 6b: no vendor agent files are committed" ($trackedVendor.Count -eq 0) `
    (($trackedVendor | Select-Object -First 4) -join '; ')

$genScript = Join-Path $pkgRoot 'Scripts/Update-AgentDocs.ps1'
Assert-True "Clause 6c: the adapter generator ships" (Test-Path $genScript) `
    'Scripts/Update-AgentDocs.ps1 is what makes a vendor-neutral source usable'

# -- Clause 6d: every generated copy is checked on its own ---------------------
# The home copy of the Claude skill was written only when the CHECKOUT copy
# drifted, so the checkout read [ok] while the skill an assistant loads was weeks
# behind.
# Run over a scratch package and a scratch home, so no real copy is touched.
$adScratch = Join-Path ([System.IO.Path]::GetTempPath()) "p20-agentdocs-$([guid]::NewGuid())"
$adPkg = Join-Path $adScratch 'pkg'
$adHome = Join-Path $adScratch 'home'
New-Item -ItemType Directory -Path (Join-Path $adPkg 'Scripts'), $adHome -Force | Out-Null
Copy-Item $genScript (Join-Path $adPkg 'Scripts/Update-AgentDocs.ps1')
Copy-Item (Join-Path $pkgRoot 'Scripts/Write-CardText.ps1') (Join-Path $adPkg 'Scripts/Write-CardText.ps1')
Copy-Item (Join-Path $pkgRoot 'Scripts/Initialize-CliFallbacks.ps1') (Join-Path $adPkg 'Scripts/Initialize-CliFallbacks.ps1')
Copy-Item (Join-Path $pkgRoot 'AGENTS.md') (Join-Path $adPkg 'AGENTS.md')
$adScript = Join-Path $adPkg 'Scripts/Update-AgentDocs.ps1'
$adHomeSkill = Join-Path $adHome '.claude/skills/toolkit-ado/SKILL.md'
try {
    $null = & pwsh -NoProfile -File $adScript -UserHome $adHome 2>&1
    Assert-True "Clause 6d: generating writes the home copy" (Test-Path $adHomeSkill)
    $adBytes = [System.IO.File]::ReadAllBytes($adHomeSkill)
    Assert-True "Clause 6d: and writes it without a BOM" (-not ($adBytes.Length -ge 3 -and $adBytes[0] -eq 0xEF -and $adBytes[1] -eq 0xBB -and $adBytes[2] -eq 0xBF))
    $null = & pwsh -NoProfile -File $adScript -Check -UserHome $adHome 2>&1
    Assert-True "Clause 6d: freshly generated, -Check is clean (exit $LASTEXITCODE)" ($LASTEXITCODE -eq 0)

    # The regression: the checkout copy current, the home copy stale.
    [System.IO.File]::WriteAllText($adHomeSkill, "stale`n")
    $adOut = & pwsh -NoProfile -File $adScript -Check -UserHome $adHome 2>&1 | Out-String
    Assert-True "Clause 6d: a stale HOME copy is drift, though the checkout's is current (exit $LASTEXITCODE)" ($LASTEXITCODE -eq 1) $adOut
    Assert-True "Clause 6d: and -Check names the home copy, not the checkout's" ($adOut -match '\(home\) has drifted' -and $adOut -notmatch '\(checkout\) has drifted') $adOut
    $null = & pwsh -NoProfile -File $adScript -UserHome $adHome 2>&1
    Assert-True "Clause 6d: regenerating repairs the home copy alone" (([System.IO.File]::ReadAllText($adHomeSkill)) -ne "stale`n")

    # A copy that was never generated is not behind.
    Remove-Item (Join-Path $adPkg '.github/copilot-instructions.md') -Force
    $null = & pwsh -NoProfile -File $adScript -Check -UserHome $adHome 2>&1
    Assert-True "Clause 6d: a missing copy is not drift (exit $LASTEXITCODE)" ($LASTEXITCODE -eq 0)
}
catch {
    Assert-True 'the cases ran to the end without a terminating error' $false $_.Exception.Message
}
finally { Remove-Item $adScratch -Recurse -Force -ErrorAction SilentlyContinue }

# -- Clause 6e: the generator reads and writes UTF-8 whatever the host ----------
# Get-Content -Raw with no -Encoding read AGENTS.md as the ANSI code page under Windows
# PowerShell 5.1, so an em dash was written garbled and 5.1 and 7 disagreed about drift
# for good. A macOS machine has no 5.1, so the test holds what it can: a source with an
# em dash and an accented letter renders to the same text, without a BOM, and -Check on
# the result is clean; and the source read is the explicit UTF-8 one. The 5.1 half is a
# VERIFY.md Gate 12 row.
$u8Scratch = Join-Path ([System.IO.Path]::GetTempPath()) "p20-agentdocs-u8-$([guid]::NewGuid())"
$u8Pkg = Join-Path $u8Scratch 'pkg'
$u8Home = Join-Path $u8Scratch 'home'
New-Item -ItemType Directory -Path (Join-Path $u8Pkg 'Scripts'), $u8Home -Force | Out-Null
Copy-Item $genScript (Join-Path $u8Pkg 'Scripts/Update-AgentDocs.ps1')
Copy-Item (Join-Path $pkgRoot 'Scripts/Write-CardText.ps1') (Join-Path $u8Pkg 'Scripts/Write-CardText.ps1')
Copy-Item (Join-Path $pkgRoot 'Scripts/Initialize-CliFallbacks.ps1') (Join-Path $u8Pkg 'Scripts/Initialize-CliFallbacks.ps1')
$u8Enc = New-Object System.Text.UTF8Encoding($false)
$u8Marker = "configurable $([char]0x2014) caf$([char]0x00E9)"
$u8Src = @('<!--', 'ONE LINE SUMMARY', "A summary $([char]0x2014) for the trigger.", '-->', '', '# Guide', '', $u8Marker) -join "`n"
[System.IO.File]::WriteAllText((Join-Path $u8Pkg 'AGENTS.md'), $u8Src + "`n", $u8Enc)
$u8Skill = Join-Path $u8Home '.claude/skills/toolkit-ado/SKILL.md'
try {
    $null = & pwsh -NoProfile -File (Join-Path $u8Pkg 'Scripts/Update-AgentDocs.ps1') -UserHome $u8Home 2>&1
    Assert-True "Clause 6e: a non-ASCII source generates the skill" (Test-Path $u8Skill)
    if (Test-Path $u8Skill) {
        $u8Bytes = [System.IO.File]::ReadAllBytes($u8Skill)
        $u8Text = $u8Enc.GetString($u8Bytes)
        Assert-True "Clause 6e: the bytes decode as UTF-8 to the source's text, em dash and accent intact" ($u8Text.Contains($u8Marker))
        Assert-True "Clause 6e: no mojibake, and the summary's em dash survives in the frontmatter" (-not $u8Text.Contains([string][char]0x00E2) -and $u8Text.Contains("description: A summary $([char]0x2014) for the trigger."))
        Assert-True "Clause 6e: written without a BOM and with LF only" (-not ($u8Bytes.Length -ge 3 -and $u8Bytes[0] -eq 0xEF) -and -not $u8Text.Contains("`r"))
    }
    $null = & pwsh -NoProfile -File (Join-Path $u8Pkg 'Scripts/Update-AgentDocs.ps1') -Check -UserHome $u8Home 2>&1
    Assert-True "Clause 6e: -Check on the result exits 0 (exit $LASTEXITCODE)" ($LASTEXITCODE -eq 0)
}
catch {
    Assert-True 'the cases ran to the end without a terminating error' $false $_.Exception.Message
}
finally { Remove-Item $u8Scratch -Recurse -Force -ErrorAction SilentlyContinue }
$genSrc = [System.IO.File]::ReadAllText($genScript)
Assert-True "Clause 6e: the generator reads its source with an explicit UTF-8 reader" `
    ($genSrc -match 'ReadAllText\(\$sourcePath, \[System\.Text\.Encoding\]::UTF8\)' -and $genSrc -notmatch 'Get-Content\s+\$sourcePath')

# -- Clause 8: the README's logo matches its source -----------------------------
# The mark lives in docs/logo.txt and is inlined into the README as a fenced
# block. Two copies drift: the README carried an older version for a day after
# the art was redrawn, and nothing noticed.
$logoPath = Join-Path $pkgRoot 'docs/logo.txt'
$readmePath2 = Join-Path $pkgRoot 'README.md'
if ((Test-Path $logoPath) -and (Test-Path $readmePath2)) {
    $logo = (Get-Content $logoPath -Raw) -replace "`r`n", "`n"
    $readme = (Get-Content $readmePath2 -Raw) -replace "`r`n", "`n"
    Assert-True "Clause 8: README logo matches docs/logo.txt" ($readme.Contains($logo.TrimEnd("`n"))) `
        'the README has an older copy of the mark -- re-inline it from docs/logo.txt'
}

# -- Clause 7: shipped docs do not link outside the package ---------------------
# A relative link that resolved in the repo something was carved from arrives
# broken. That is not hypothetical: GetPRComments writes a link to an agentic
# prompt into every card it touches, and for a while that folder had not come
# across. A link in a shipped document is a promise the package has to keep.
$mdFiles = @()
$mdFiles += @(Get-ChildItem $pkgRoot -Filter '*.md' -File -ErrorAction SilentlyContinue)
foreach ($d in @('agentic', 'templates', 'docs', '.claude')) {
    $dir = Join-Path $pkgRoot $d
    if (Test-Path $dir) {
        $mdFiles += @(Get-ChildItem $dir -Filter '*.md' -Recurse -File -ErrorAction SilentlyContinue | Select-ScannableFile)
    }
}

$brokenLinks = @()
foreach ($f in $mdFiles) {
    $text = Get-Content $f.FullName -Raw -ErrorAction SilentlyContinue
    if (-not $text) { continue }
    foreach ($m in [regex]::Matches($text, '\]\(([^)#:]+\.md[^)]*)\)')) {
        $target = $m.Groups[1].Value.Split('#')[0].Trim()
        if ($target -match '^(https?|mailto):') { continue }
        $resolved = Join-Path (Split-Path $f.FullName -Parent) $target
        if (-not (Test-Path $resolved)) {
            $brokenLinks += "$($f.Name) -> $target"
        }
    }
}
Assert-True "Clause 7: relative links in shipped docs resolve" ($brokenLinks.Count -eq 0) `
    (($brokenLinks | Select-Object -First 4) -join '; ')

# ── Clause 10: no `$script:` read inside a global function (RATCHET, baseline 0) ──
# AGENTS.md, "A `function global:` in utilities.psm1 cannot read module state
# through a `$script:` name": reached from a script the module launched, the
# name binds to THAT script's scope and the answer is $null -- a wrong answer,
# not an error. The audit moved every such read into the one
# container, $script:ModuleState, read through a closure (`$s.<Key>`). This
# clause is what keeps it there: an AST walk over every `function global:`
# body and every `Set-Item function:global:` closure, counting variable
# expressions in the script scope. A grep cannot do this -- it cannot tell a
# read in the module body (correct) from one inside a function (the trap).
# A line that is genuinely fine takes a `scope-ok:` comment.
$ScopeReadBaseline = 0
$moduleFile = Join-Path $pkgRoot 'utilities.psm1'
$scopeTokens = $null; $scopeErrors = $null
$scopeAst = [System.Management.Automation.Language.Parser]::ParseFile($moduleFile, [ref]$scopeTokens, [ref]$scopeErrors)
$moduleLines = Get-Content $moduleFile
$isScriptRead = { param($n) $n -is [System.Management.Automation.Language.VariableExpressionAst] -and $n.VariablePath.IsScript }
$scopeBodies = @()
$scopeBodies += $scopeAst.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -like 'global:*' }, $true) |
    ForEach-Object { @{ Name = $_.Name; Node = $_.Body } }
$scopeBodies += $scopeAst.FindAll({ param($n) $n -is [System.Management.Automation.Language.CommandAst] -and $n.GetCommandName() -eq 'Set-Item' -and $n.CommandElements.Count -gt 1 -and $n.CommandElements[1].Extent.Text -like 'function:global:*' }, $true) |
    ForEach-Object { @{ Name = $_.CommandElements[1].Extent.Text; Node = $_ } }
$scopeHits = @()
foreach ($b in $scopeBodies) {
    foreach ($v in $b.Node.FindAll($isScriptRead, $true)) {
        $line = $moduleLines[$v.Extent.StartLineNumber - 1]
        if ($line -match 'scope-ok:') { continue }
        $scopeHits += "$($b.Name):$($v.Extent.StartLineNumber) $($v.Extent.Text)"
    }
}
$scopeDetail = "found $($scopeHits.Count) in $($scopeBodies.Count) global bodies, baseline $ScopeReadBaseline"
if ($scopeHits.Count -gt $ScopeReadBaseline) {
    $scopeDetail = "$scopeDetail -- a global function reads module state through `$script:, which is `$null when a launched script reaches it. Put the value in `$script:ModuleState and close over it (`$s.<Key>`): " + (($scopeHits | Select-Object -First 5) -join '; ')
}
Assert-True "Clause 10: no `$script: read inside a global function body" ($scopeHits.Count -le $ScopeReadBaseline) $scopeDetail
Assert-True "Clause 10: the scan saw the global functions it is guarding" ($scopeBodies.Count -ge 40) "saw $($scopeBodies.Count)"

# -- Clauses 11 and 12: a suite cannot under-count in silence -----------
# A suite's count is the proof, so a suite that can finish short without saying
# so is a proof with a hole in it. Two shapes did exactly that: a
# top-level `try { cases } finally { summary }` with no catch, where a
# terminating error ends the try, drops every case below it and the summary
# prints a smaller N/N in green; and a call to an Assert- helper the file never
# defines, which prints CommandNotFound and is never counted. Both are AST
# walks over every Tests/Test-*.ps1, for the reason Clause 10 is: a grep
# cannot tell a top-level try from a helper's, or a call from a string.
#
# Clause 11: a TryStatementAst whose parent is the script's own block has a
# catch -- the convention is a catch that records the error as a named FAIL
# (docs/TESTING.md, "A suite ends with a catch").
# Clause 12: every command named Assert-* resolves to a function the file
# defines, or one defined in a file it dot-sources or imports by a path the
# AST spells in literals ((Join-Path $pkgRoot 'Scripts/X.ps1'),
# (Join-Path $scriptDir 'X.ps1')), read recursively. A path held in a
# variable cannot be followed; a call that only such a file could answer is
# reported, and the fix is to spell the path or define the helper.
#
# The runner is not a suite: Test-Toolkit.ps1 counts no cases of its own, and
# its top-level try restores the shell's environment around the run.
$SuiteShapeExempt = @('Test-Toolkit.ps1')
$testsDir = Join-Path $pkgRoot 'Tests'
$suiteFiles = @(Get-ChildItem $testsDir -Filter 'Test-*.ps1' -File | Where-Object { $SuiteShapeExempt -notcontains $_.Name } | Sort-Object Name)
$isTopTry = {
    param($n)
    $n -is [System.Management.Automation.Language.TryStatementAst] -and
    $n.Parent -is [System.Management.Automation.Language.NamedBlockAst] -and
    $n.Parent.Parent -is [System.Management.Automation.Language.ScriptBlockAst] -and
    $null -eq $n.Parent.Parent.Parent
}
# Every function name a file defines, plus those of the files it dot-sources or
# imports by a literal path, followed recursively. $Seen stops a cycle.
$getHelperNames = $null
$getHelperNames = {
    param([string]$Path, [hashtable]$Seen)
    $names = @()
    if ($Seen.ContainsKey($Path)) { return $names }
    $Seen[$Path] = $true
    $tk = $null; $pe = $null
    $fileAst = [System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]$tk, [ref]$pe)
    $names += @($fileAst.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true) |
        ForEach-Object { $_.Name -replace '^(global|script|local):', '' })
    $loads = @($fileAst.FindAll({ param($n) $n -is [System.Management.Automation.Language.CommandAst] -and ($n.InvocationOperator -eq 'Dot' -or $n.GetCommandName() -eq 'Import-Module') }, $true))
    foreach ($load in $loads) {
        $elements = @($load.CommandElements)
        if ($load.InvocationOperator -ne 'Dot') { $elements = @($elements | Select-Object -Skip 1) }
        foreach ($el in $elements) {
            $parts = @($el.FindAll({ param($n) $n -is [System.Management.Automation.Language.StringConstantExpressionAst] -and $n.StringConstantType -ne 'BareWord' }, $true) | ForEach-Object { $_.Value })
            if ($parts.Count -eq 0) { continue }
            $rel = $parts -join '/'
            foreach ($base in @((Split-Path -Parent $Path), $pkgRoot)) {
                $candidate = Join-Path $base $rel
                if ((Test-Path $candidate -PathType Leaf) -and ($candidate -match '\.ps(m)?1$')) {
                    $names += & $getHelperNames ((Resolve-Path $candidate).Path) $Seen
                    break
                }
            }
        }
    }
    return $names
}
$catchlessTries = @()
$unresolvedAsserts = @()
foreach ($sf in $suiteFiles) {
    $tk = $null; $pe = $null
    $sAst = [System.Management.Automation.Language.Parser]::ParseFile($sf.FullName, [ref]$tk, [ref]$pe)
    foreach ($try in $sAst.FindAll($isTopTry, $false)) {
        if ($try.CatchClauses.Count -eq 0) { $catchlessTries += "Tests/$($sf.Name):$($try.Extent.StartLineNumber)" }
    }
    $defined = @(& $getHelperNames $sf.FullName @{})
    $calls = @($sAst.FindAll({ param($n) $n -is [System.Management.Automation.Language.CommandAst] -and "$($n.GetCommandName())" -like 'Assert-*' }, $true))
    foreach ($call in $calls) {
        if ($defined -notcontains $call.GetCommandName()) {
            $unresolvedAsserts += "Tests/$($sf.Name):$($call.Extent.StartLineNumber) $($call.GetCommandName())"
        }
    }
}
$tryDetail = "read $($suiteFiles.Count) suites"
if ($catchlessTries.Count -gt 0) {
    $tryDetail = "$tryDetail -- a top-level try with no catch drops every case below a terminating error and the count shrinks in green. End it with catch { Assert-True 'the cases ran to the end without a terminating error' `$false `$_.Exception.Message }: " + (($catchlessTries | Select-Object -First 6) -join '; ')
}
Assert-True "Clause 11: every suite's top-level try ends with a catch" (($catchlessTries.Count -eq 0) -and ($suiteFiles.Count -ge 30)) $tryDetail
$assertDetail = "read $($suiteFiles.Count) suites"
if ($unresolvedAsserts.Count -gt 0) {
    $assertDetail = "$assertDetail -- an Assert- call the file neither defines nor loads by a literal path prints CommandNotFound and is never counted: " + (($unresolvedAsserts | Select-Object -First 6) -join '; ')
}
Assert-True "Clause 12: every Assert- call in a suite resolves to a helper it defines or loads" (($unresolvedAsserts.Count -eq 0) -and ($suiteFiles.Count -ge 30)) $assertDetail

# -- Clause 17: a suite ends with its own verdict -----------------------------
# A suite's exit code is its verdict. One that ends without an `exit` hands its
# caller the code of the last child process it ran, so a green run can report 1
# (a pwsh -Command wrapper, the PowerShell tool) and a red one 0. The last
# top-level statement of every Tests/Test-*.ps1 (the runner aside) is an `exit`.
# Two shapes are correct: `exit 0`, which needs an earlier `exit` with a non-zero
# verdict somewhere in the file, and an `exit <expression>` that carries the
# verdict itself (`exit $script:failed`). Anything else is reported by file.
$noVerdict = @()
foreach ($sf in $suiteFiles) {
    $tk = $null; $pe = $null
    $vAst = [System.Management.Automation.Language.Parser]::ParseFile($sf.FullName, [ref]$tk, [ref]$pe)
    $vStatements = @($vAst.EndBlock.Statements)
    $vLast = if ($vStatements.Count -gt 0) { $vStatements[-1] } else { $null }
    $vOk = $false
    if ($null -ne $vLast -and $vLast.Extent.Text -match '^exit\b') {
        $vArg = ($vLast.Extent.Text -replace '^exit\b', '').Trim()
        if ($vArg -eq '0') {
            $vOk = @($vAst.FindAll({ param($n) $n.Extent.Text -match '^exit\s+[1-9]' }, $true)).Count -gt 0
        }
        else {
            $vOk = $vArg.Length -gt 0
        }
    }
    if (-not $vOk) { $noVerdict += "Tests/$($sf.Name)" }
}
$verdictDetail = "read $($suiteFiles.Count) suites"
if ($noVerdict.Count -gt 0) {
    $verdictDetail = "$verdictDetail -- a suite that does not end with an exit hands its caller the last child process's code. End it with ``if (`$script:failed -gt 0) { exit 1 }`` then ``exit 0``: " + ($noVerdict -join '; ')
}
Assert-True "Clause 17: every suite ends with its own exit verdict" (($noVerdict.Count -eq 0) -and ($suiteFiles.Count -ge 30)) $verdictDetail

# -- Clause 13: no work-marker comment ships ------------------------------
# A seam the code leaves open is a roadmap row in docs/KNOWN-GAPS.md, not a
# comment in the source: a stranger reading the tree should find what is
# unfinished in one place, with what they see when they hit it. The four marker
# words are matched at a word boundary and case-sensitively, so a token that
# merely contains one (an XXXL spacing name, a \uXXXX escape) is not a hit and
# a lowercase prose "todo" is not either. The words are assembled from halves
# here so this file does not match its own sweep.
#
# The file set is every shipped source file of the three halves -- the CLI,
# web/src and web/tests, agent/ -- and Tests/ (fixtures excepted, for the usual
# reason: a fixture is meant to look like real input). It is wider than
# Get-RuntimeFiles on purpose: a marker in a suite is as visible to a reader as
# one in a script.
#
# What this clause does NOT hold is commented-out code. That was swept once by
# hand and no heuristic that reads a comment line can hold it: a line
# of prose ending in a semicolon, a usage example in a header comment and a
# `Verb -Param` sentence all parse as code, and the one sweep found ~30 such
# lines and no dead code. A check with a standing allow-list of those is noise;
# review holds that rule (docs/CONTRIBUTING.md).
$markerWords   = @(('TO' + 'DO'), ('FIX' + 'ME'), ('HA' + 'CK'), ('XX' + 'X'))
$markerPattern = '\b(' + ($markerWords -join '|') + ')\b'
$markerFiles = @()
$markerRoot = Get-ChildItem (Join-Path $pkgRoot '*.psm1') -File -ErrorAction SilentlyContinue
if ($markerRoot) { $markerFiles += $markerRoot }
foreach ($spec in @(
    @{ Dir = 'Scripts';         Include = @('*.ps1', '*.psm1', '*.psd1') }
    @{ Dir = 'Prompt20Toolkit'; Include = @('*.ps1', '*.psm1', '*.psd1') }
    @{ Dir = 'Tests';           Include = @('*.ps1', '*.psm1', '*.py', '*.mjs', '*.js') }
    @{ Dir = 'agent';           Include = @('*.py', '*.ps1') }
    @{ Dir = 'web/src';         Include = @('*.ts', '*.tsx', '*.mjs', '*.js') }
    @{ Dir = 'web/tests';       Include = @('*.ts', '*.tsx', '*.mjs', '*.js') }
)) {
    $dir = Join-Path $pkgRoot $spec.Dir
    if (Test-Path $dir) {
        $markerFiles += Get-ChildItem $dir -Include $spec.Include -Recurse -File -ErrorAction SilentlyContinue
    }
}
$markerFiles = @($markerFiles | Where-Object { $_.FullName -notmatch '[\\/]Tests[\\/]fixtures[\\/]' } | Select-ScannableFile)
$markerHits = @()
foreach ($f in $markerFiles) {
    $lineNo = 0
    foreach ($line in [System.IO.File]::ReadAllLines($f.FullName)) {
        $lineNo++
        $m = [regex]::Match($line, $markerPattern)
        if ($m.Success) { $markerHits += "$(Get-RelPath $f):$lineNo  $($m.Value)" }
    }
}
$markerDetail = "read $($markerFiles.Count) files"
if ($markerHits.Count -gt 0) {
    $markerDetail = "a seam is a row in docs/KNOWN-GAPS.md, not a comment: " + ($markerHits -join '; ')
}
Assert-True "Clause 13: no work-marker comment in shipped source" (($markerHits.Count -eq 0) -and ($markerFiles.Count -ge 400)) $markerDetail
Assert-True "Clause 13: the marker pattern matches a word, case-sensitively, and nothing it merely sits inside" (
    ([regex]::IsMatch(('// ' + $markerWords[0] + ': later'), $markerPattern)) -and
    (-not [regex]::IsMatch('tokens.spacingHorizontal' + $markerWords[3] + 'L', $markerPattern)) -and
    (-not [regex]::IsMatch('\u' + $markerWords[3] + 'X', $markerPattern)) -and
    (-not [regex]::IsMatch($markerWords[1].ToLower(), $markerPattern))) ''

# -- Clause 14: no comment carries what a public tree cannot ship -----------
# A comment is read by whoever opens the file, so it is written for a stranger:
# no date, no person's name, no agent's name, no tracker number as the subject of
# a sentence, no pointer into a private archive, no private repository, no machine
# path, and no nickname for a host ("Windows" and "macOS" say what is meant,
# or the sentence goes). The rule is held on
# COMMENTS only: a string, a fixture and a test's data may name anything.
#
# What counts as a comment is per language, and exact where the language gives a
# parser: PowerShell comes from the parser's own tokens (a here-string is not a
# comment), Python docstrings are the strings that open a block, and the rest is
# read line by line with string literals blanked first. A trailing comment is a
# comment too.
#
# Two kinds of reference are allowed to stay where a rewrite drops them cleanly:
# on a comment that fills its whole line, a closed parenthetical made only of
# tracker numbers or archive citations may stay. Everything else is flat.
#
# The words are assembled from halves so this file does not match its own sweep.
# Scope: every shipped source file of the three halves plus the root files, minus
# the documents (docs/, spec/, design/), the data
# (samples/, templates/, any fixtures/ folder),
# and the vendored or generated folders of Tests/ScanExclusions.ps1.
$cpPatterns = @(
    @{ Name = 'date'; Rx = '(?<!\d)20\d\d-\d\d-\d\d(?!\d)' }
    @{ Name = 'tracker number'; Rx = '(?<![\w&#/=:"''-])#[1-9]\d{0,3}(?![\w-])'
       ItemRx = '^(?:(?:[Ii]ssues?|[Rr]efs|[Ss]ee|[Cc]loses)\s+)?#[1-9]\d{0,3}(?!\w)(?:\s*:\s*.*|\s+\S+(?:\s+\S+){0,2})?$|^(?:D-)?[A-Z][A-Za-z]*\d+[a-z]?\s+#[1-9]\d{0,3}$' }
    @{ Name = 'person';  Rx = ('\b[Jj]o' + 'hn\b|\bWeb' + 'ster\b|\bjo' + 'hndemo\b') }
    @{ Name = 'agent';   Rx = ('\b(?:Fa' + 'ble|Op' + 'us|Son' + 'net|Hai' + 'ku)\b') }
    @{ Name = 'host';    Rx = ('(?i:\b(?:the|this|that|our|windows))\s+(?:PC|Mac)\b|\b5\.1-only (?:PC|Mac)\b|\b(?:PC|Mac)''s\b|\bMac Fa' + 'ble\b|\bPC (?:team|crew|walk)\b') }
    @{ Name = 'archive pointer'; Rx = ('fixed-' + 'issues|\bissues?:\s+[a-z0-9]+(?:-[a-z0-9]+)+|\b(?:bug|improve|feature|enhancement)(?:-[a-z0-9]+){3,}')
       ItemRx = ('^issues?:\s+[a-z0-9][a-z0-9-]+(?:\.prompt\.md)?$') }
    @{ Name = 'private repository'; Rx = ('(?i)\bcss-was' + 'teland[\w-]*|\bdeck-' + 'qa\b|Repos/pro' + 'mpts\b|johnfr' + 'og76') }
    @{ Name = 'machine path'; Rx = '(?i)\b[a-z]:(?:\\\\|\\|/)+Users(?:\\\\|\\|/)+(?!runneradmin\b|RUNNER~1\b|<|\.\.\.|you\b|\*)[^\\/\s''"`]+|/Users/[a-z][^/\s''"`]*/|/home/[a-z][^/\s''"`]*/' }  # export:example
)
$cpParenRx = [regex]'\([^()]*\)'
$cpStringRx = [regex]'"(?:\\.|[^"\\])*"|''(?:\\.|[^''\\])*''|`(?:\\.|[^`\\])*`'
$cpBlankEval = [System.Text.RegularExpressions.MatchEvaluator] { param($m) 'x' * $m.Length }
$cpDataPath = '^(samples|templates|design|docs|spec)/|(^|/)(fixtures|__fixtures__)/|^\.claude/'
$cpSkipFiles = @()
$cpKinds = @{
    '.ps1' = 'ps'; '.psm1' = 'ps'; '.psd1' = 'ps'
    '.py' = 'py'
    '.ts' = 'c'; '.tsx' = 'c'; '.js' = 'c'; '.jsx' = 'c'; '.mjs' = 'c'; '.cjs' = 'c'; '.css' = 'c'; '.jsonc' = 'c'
    '.yml' = 'hash'; '.yaml' = 'hash'; '.toml' = 'hash'; '.sh' = 'hash'; '.txt' = 'hash'; '.template' = 'hash'; '.example' = 'hash'
    '.gitignore' = 'hash'; '.dockerignore' = 'hash'; '.prettierignore' = 'hash'; '.gitattributes' = 'hash'
    '.html' = 'xml'; '.svg' = 'xml'
    '.json' = 'json'
}

function New-CpComment {
    param([int]$Line, [string]$Text, [bool]$Whole)
    return [pscustomobject]@{ Line = $Line; Text = $Text; Whole = $Whole }
}

function Get-CpHashComments {
    # '#' comments of a YAML, TOML or shell file, ignoring a '#' inside quotes.
    param([string[]]$Lines)
    for ($i = 0; $i -lt $Lines.Count; $i++) {
        $l = $Lines[$i]
        if ($l.TrimStart().StartsWith('#')) { New-CpComment ($i + 1) $l $true; continue }
        $masked = $cpStringRx.Replace($l, $cpBlankEval)
        $m = [regex]::Match($masked, '\s#(\s|$)')
        if ($m.Success) { New-CpComment ($i + 1) $l.Substring($m.Index) $false }
    }
}

function Get-CpCComments {
    # '//' and '/* */' comments of a TypeScript, JavaScript or CSS file.
    param([string[]]$Lines)
    $block = $false
    for ($i = 0; $i -lt $Lines.Count; $i++) {
        $l = $Lines[$i]
        $t = $l.Trim()
        if ($block) {
            New-CpComment ($i + 1) $l $true
            if ($t.Contains('*/')) { $block = $false }
            continue
        }
        if ($t.StartsWith('//') -or $t.StartsWith('*')) { New-CpComment ($i + 1) $l $true; continue }
        if ($t.StartsWith('/*') -or $t.StartsWith('{/*')) {
            New-CpComment ($i + 1) $l $true
            if (-not $t.Contains('*/')) { $block = $true }
            continue
        }
        $masked = $cpStringRx.Replace($l, $cpBlankEval)
        $m = [regex]::Match($masked, '(?<![:\w/])//(?!/)|/\*')
        if ($m.Success) {
            New-CpComment ($i + 1) $l.Substring($m.Index) $false
            if ($m.Value -eq '/*' -and -not $masked.Substring($m.Index).Contains('*/')) { $block = $true }
        }
    }
}

function Get-CpXmlComments {
    # '<!-- ... -->' in an HTML or SVG file, one entry per line it covers.
    param([string[]]$Lines)
    $open = $false
    for ($i = 0; $i -lt $Lines.Count; $i++) {
        $l = $Lines[$i]
        if ($open -or $l.Contains('<!--')) {
            New-CpComment ($i + 1) $l $true
            $from = 0
            if (-not $open) { $from = $l.IndexOf('<!--') + 4 }
            $open = -not $l.Substring($from).Contains('-->')
        }
    }
}

function Get-CpPyComments {
    # '#' comments and docstrings (a triple-quoted string that opens a block or
    # the file). A triple-quoted string used as a value is data, not a comment.
    param([string[]]$Lines)
    $dq = '"' * 3
    $sq = "'" * 3
    $openRx = [regex]('^[rRuUbBfF]{0,2}(' + $dq + '|' + $sq + ')')
    $inString = ''
    $isDoc = $false
    $prev = ''
    for ($i = 0; $i -lt $Lines.Count; $i++) {
        $l = $Lines[$i]
        $t = $l.Trim()
        if ($inString) {
            if ($isDoc) { New-CpComment ($i + 1) $l $true }
            if ($l.Contains($inString)) { $inString = ''; $isDoc = $false; $prev = $t }
            continue
        }
        if ($t.StartsWith('#')) { New-CpComment ($i + 1) $l $true; continue }
        $open = $openRx.Match($t)
        if ($open.Success) {
            $q = $open.Groups[1].Value
            $doc = ($prev -eq '') -or $prev.EndsWith(':') -or $prev.StartsWith('#') -or $prev.EndsWith($q)
            $closed = $t.Substring($open.Length).Contains($q)
            if ($doc) { New-CpComment ($i + 1) $l $true }
            if (-not $closed) { $inString = $q; $isDoc = $doc }
            $prev = $t
            continue
        }
        # A line that opens a triple-quoted value: its text is data from the quotes on.
        $dqn = ([regex]::Matches($l, $dq)).Count
        $sqn = ([regex]::Matches($l, $sq)).Count
        if ($dqn -gt 0 -or $sqn -gt 0) {
            if ($dqn % 2 -eq 1) { $inString = $dq; $isDoc = $false }
            elseif ($sqn % 2 -eq 1) { $inString = $sq; $isDoc = $false }
            $prev = $t
            continue
        }
        $masked = $cpStringRx.Replace($l, $cpBlankEval)
        $m = [regex]::Match($masked, '\s#(\s|$)')
        if ($m.Success) { New-CpComment ($i + 1) $l.Substring($m.Index) $false }
        $prev = $t
    }
}

function Get-CpPsComments {
    # The parser's own comment tokens: exact, and a here-string is not one.
    param([string]$Path, [string[]]$Lines)
    $tokens = $null
    $errs = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]$tokens, [ref]$errs)
    foreach ($tok in $tokens) {
        if ($tok.Kind -ne [System.Management.Automation.Language.TokenKind]::Comment) { continue }
        $startLine = $tok.Extent.StartLineNumber
        $col = $tok.Extent.StartColumnNumber
        $srcLine = $(if ($startLine -le $Lines.Count) { $Lines[$startLine - 1] } else { '' })
        $whole = ($col -le 1) -or ($srcLine.Substring(0, [Math]::Min($col - 1, $srcLine.Length)).Trim() -eq '')
        $n = 0
        foreach ($piece in ($tok.Extent.Text -split "\r?\n")) {
            New-CpComment ($startLine + $n) $piece ($whole -or $n -gt 0)
            $n++
        }
    }
}

function Get-CpJsonComments {
    # The '_' and '_comment' keys a JSON file uses to carry prose, at any depth.
    param([string]$Path)
    $raw = [System.IO.File]::ReadAllText($Path)
    if ($raw -notmatch '"_(comment)?"\s*:') { return }
    try { $doc = $raw | ConvertFrom-Json } catch { return }
    $stack = New-Object System.Collections.Stack
    $stack.Push(@{ Node = $doc; Path = '' })
    while ($stack.Count -gt 0) {
        $item = $stack.Pop()
        $node = $item.Node
        if ($node -is [System.Management.Automation.PSCustomObject]) {
            foreach ($p in $node.PSObject.Properties) {
                if (($p.Name -eq '_' -or $p.Name -eq '_comment') -and $p.Value -is [string]) {
                    New-CpComment 0 ("$($item.Path)$($p.Name): $($p.Value)") $false
                }
                elseif ($null -ne $p.Value -and -not ($p.Value -is [string])) {
                    $stack.Push(@{ Node = $p.Value; Path = "$($item.Path)$($p.Name)." })
                }
            }
        }
        elseif ($node -is [System.Array]) {
            foreach ($e in $node) { if ($null -ne $e -and -not ($e -is [string])) { $stack.Push(@{ Node = $e; Path = $item.Path }) } }
        }
    }
}

function Get-CpComments {
    param([string]$Path, [string]$Kind)
    $lines = [System.IO.File]::ReadAllLines($Path)
    switch ($Kind) {
        'ps'   { return @(Get-CpPsComments $Path $lines) }
        'py'   { return @(Get-CpPyComments $lines) }
        'c'    { return @(Get-CpCComments $lines) }
        'hash' { return @(Get-CpHashComments $lines) }
        'xml'  { return @(Get-CpXmlComments $lines) }
        'json' { return @(Get-CpJsonComments $Path) }
    }
    return @()
}

function Get-CpFindings {
    # The names of the patterns a comment line matches. On a comment that fills
    # its whole line, a parenthetical made only of tracker numbers or archive
    # citations is the export's to remove (its issue-ref and fixed-issue-citation
    # rules read the same shapes), so the group is set aside before matching.
    param([string]$Text, [bool]$Whole)
    $found = @()
    foreach ($p in $cpPatterns) {
        $t = $Text
        if ($Whole -and $p.ItemRx) {
            $rx = $p.Rx
            $itemRx = $p.ItemRx
            $t = $cpParenRx.Replace($t, [System.Text.RegularExpressions.MatchEvaluator] {
                    param($m)
                    foreach ($item in ($m.Value.Trim('(', ')') -split '[,;]')) {
                        $item = $item.Trim()
                        if (($item -cmatch $rx) -and ($item -cnotmatch $itemRx)) { return $m.Value }
                    }
                    return ''
                })
        }
        if ($t -cmatch $p.Rx) { $found += $p.Name }
    }
    return $found
}

function Get-CpFiles {
    # Every source file under the package, not descending into a vendored,
    # generated or document folder, and not through a junction.
    param([string]$Dir, [string]$Rel)
    foreach ($entry in [System.IO.Directory]::EnumerateFileSystemEntries($Dir)) {
        $name = [System.IO.Path]::GetFileName($entry)
        $childRel = $(if ($Rel) { "$Rel/$name" } else { $name })
        if ([System.IO.Directory]::Exists($entry)) {
            if ($script:ScanExcludedSegments -contains $name) { continue }
            if (([System.IO.File]::GetAttributes($entry) -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) { continue }
            if (("$childRel/") -match $cpDataPath) { continue }
            Get-CpFiles $entry $childRel
        }
        else {
            if ($childRel -match $cpDataPath -or $cpSkipFiles -contains $childRel) { continue }
            $ext = [System.IO.Path]::GetExtension($name).ToLowerInvariant()
            $kind = $null
            if ($cpKinds.ContainsKey($ext)) { $kind = $cpKinds[$ext] }
            elseif ($name -eq 'Dockerfile') { $kind = 'hash' }
            if ($kind) { [pscustomobject]@{ Path = $entry; Rel = $childRel; Kind = $kind } }
        }
    }
}

$cpHits = @()
$cpFiles = @(Get-CpFiles $pkgRoot '')
foreach ($cf in $cpFiles) {
    foreach ($c in (Get-CpComments $cf.Path $cf.Kind)) {
        $kindsHit = @(Get-CpFindings $c.Text $c.Whole)
        if ($kindsHit.Count -gt 0) {
            $shown = $c.Text.Trim()
            if ($shown.Length -gt 90) { $shown = $shown.Substring(0, 90) + '...' }
            $at = $(if ($c.Line -gt 0) { "$($cf.Rel):$($c.Line)" } else { $cf.Rel })
            $cpHits += "$at [$($kindsHit -join ', ')] $shown"
        }
    }
}
$cpDetail = "read $($cpFiles.Count) files"
if ($cpHits.Count -gt 0) {
    $cpDetail = "$($cpHits.Count) comment(s) name what a public tree cannot ship -- say the rule without the date, the name or the number: " + (($cpHits | Select-Object -First 12) -join ' | ')
}
Assert-True "Clause 14: no comment names a date, a person, an agent, a host by its nickname, a tracker number, an archive pointer, a private repository or a machine path" (($cpHits.Count -eq 0) -and ($cpFiles.Count -ge 400)) $cpDetail

# The sweep's own cases: one comment per language that must be found, and the
# look-alikes that must not. A scan that finds nothing looks the same whether it
# is looking properly or not, so each language reads a real file written here.
$cpScratch = Join-Path ([System.IO.Path]::GetTempPath()) "p20-comment-scan-$([guid]::NewGuid().ToString('N'))"
try {
    New-Item -ItemType Directory -Path $cpScratch -Force | Out-Null
    $cpWho = 'Jo' + 'hn'
    $cpDay = '2026' + '-09-' + '16'
    $cpCases = @(
        @{ File = 'a.ps1'; Kind = 'ps'; Hit = $true; Why = 'a PowerShell line comment with a name and a date'; Body = "`$x = 1`r`n# $cpWho, $cpDay`r`n" }
        @{ File = 'b.ps1'; Kind = 'ps'; Hit = $true; Why = 'a PowerShell trailing comment with a date'; Body = "`$x = 1 # since $cpDay`r`n" }
        @{ File = 'c.ps1'; Kind = 'ps'; Hit = $true; Why = 'a PowerShell help block'; Body = "<#`r`n.SYNOPSIS`r`n    until $cpDay it did less`r`n#>`r`n" }
        @{ File = 'd.ps1'; Kind = 'ps'; Hit = $false; Why = 'a here-string is data, not a comment'; Body = "`$x = @'`r`n# $cpWho, $cpDay`r`n'@`r`n" }
        @{ File = 'e.py'; Kind = 'py'; Hit = $true; Why = 'a Python docstring with a name'; Body = "def f():`n    `"`"`"$cpWho said so.`"`"`"`n    return 1`n" }
        @{ File = 'f.py'; Kind = 'py'; Hit = $false; Why = 'a Python string value is data'; Body = "x = `"`"`"`n$cpWho $cpDay`n`"`"`"`ny = `"# $cpDay`"`n" }
        @{ File = 'g.ts'; Kind = 'c'; Hit = $true; Why = 'a TypeScript trailing comment with a tracker number'; Body = "const a = 1; // see #123 for why`n" }
        @{ File = 'h.ts'; Kind = 'c'; Hit = $false; Why = 'a // inside a string is not a comment'; Body = "const u = `"https://example.com/#123`"; const d = '$cpDay';`n" }
        @{ File = 'i.ts'; Kind = 'c'; Hit = $false; Why = 'a number inside a parenthetical on a whole-line comment is the export rule''s'; Body = "// the rule (#123) holds`n" }
        @{ File = 'j.yml'; Kind = 'hash'; Hit = $true; Why = 'a YAML comment with a host nickname'; Body = "a: 1  # run on the Mac`n" }
        @{ File = 'k.html'; Kind = 'xml'; Hit = $true; Why = 'an HTML comment with a name'; Body = "<p>x</p>`n<!-- by $cpWho -->`n" }
        @{ File = 'l.json'; Kind = 'json'; Hit = $true; Why = 'a JSON _comment key with a date'; Body = "{ `"_comment`": `"changed $cpDay`", `"a`": 1 }" }
        @{ File = 'm.json'; Kind = 'json'; Hit = $false; Why = 'a JSON value that is data is not a comment'; Body = "{ `"title`": `"$cpWho $cpDay`" }" }
    )
    foreach ($case in $cpCases) {
        $cpPath = Join-Path $cpScratch $case.File
        [System.IO.File]::WriteAllText($cpPath, $case.Body)
        $caseHits = 0
        foreach ($c in (Get-CpComments $cpPath $case.Kind)) {
            if (@(Get-CpFindings $c.Text $c.Whole).Count -gt 0) { $caseHits++ }
        }
        Assert-True "Clause 14: the sweep $(if ($case.Hit) { 'finds' } else { 'leaves alone' }) $($case.Why)" (($caseHits -gt 0) -eq $case.Hit) "hits: $caseHits"
    }
}
catch {
    Assert-True 'Clause 14: the sweep cases ran to the end without a terminating error' $false $_.Exception.Message
}
finally {
    Remove-Item -Path $cpScratch -Recurse -Force -ErrorAction SilentlyContinue
}

# -- Clause 15: a script calls gh or az through Invoke-P20TrackerRead ----------
# AGENTS.md, "Traps worth knowing": under Windows PowerShell 5.1 a native call
# whose stderr is redirected (2>&1, 2>$null, *> $null) while the preference is
# 'Stop' throws on the first stderr line, before the exit code can be read, so a
# verb's own refusal is never printed. pwsh 7 reads the same line as text, so a
# run there is green either way. Scripts/Invoke-TrackerRead.ps1 is the one place
# that redirection is written; every other gh or az call goes through it.
#
# Read with the PowerShell tokenizer, not a grep: a comment or a string that
# NAMES such a call (help text, a hint) is not a call. The file set is the CLI's
# runtime code -- the root *.psm1, Scripts/ and Config/.
#
# The sweep covers git as well (D3J7): New-PullRequest.ps1 called it raw, and a
# caller holding 'Stop' stopped it outside a repository before it could say so.
#
# The allow-list is files that keep their own copy of the split, each with its
# reason. It only shrinks. A value is one of two shapes: a reason string (the
# whole file is allowed), or a hashtable @{ Reason = '...'; Lines = @(...) }, an
# entry-level allowance: only a raw call whose matched text (the sweep's regex
# match, trimmed, as printed after the line number) is in Lines is allowed, and
# any other raw call in that file is a hit, so a new one cannot arrive quietly
# beside a deliberate one. The files once marked 'D3J7 follow-up' are converted.
# Get-Standup.ps1 and Get-Triage.ps1 shared their raw copy out into
# Scripts/Ritual-Common.ps1 (Task3WGP), which reads through Invoke-P20TrackerRead
# like every other script, so neither needs an entry here any more.
$rawTrackerAllowed = @{
    'Scripts/Invoke-TrackerRead.ps1' = 'the one place the redirection is written'
    # git, deliberate: the hub sync prints git's own pull/push output as it arrives and reads the exit code itself
    'Scripts/Sync-Prompts.ps1'       = @{
        Reason = 'the hub sync passes git output through to the terminal'
        Lines  = @('git pull --rebase 2>', 'git push 2>')
    }
}
$rawTrackerPattern = '(?<![\w$-])(gh|az|git)\s[^|\r\n]*(2>|\*>)'
function Get-RawTrackerCalls {
    # Every match of the pattern that starts outside a comment and a string.
    param([string]$Text)
    $tokens = $null; $parseErrors = $null
    [void][System.Management.Automation.Language.Parser]::ParseInput($Text, [ref]$tokens, [ref]$parseErrors)
    $skip = @($tokens | Where-Object {
            $_.Kind -eq 'Comment' -or $_ -is [System.Management.Automation.Language.StringToken]
        })
    $found = @()
    foreach ($m in [regex]::Matches($Text, $rawTrackerPattern)) {
        $inside = $false
        foreach ($t in $skip) {
            if ($m.Index -ge $t.Extent.StartOffset -and $m.Index -lt $t.Extent.EndOffset) { $inside = $true; break }
        }
        if ($inside) { continue }
        $lineNo = ([regex]::Matches($Text.Substring(0, $m.Index), "`n")).Count + 1
        $found += "${lineNo}: $($m.Value.Trim())"
    }
    return $found
}
$rawTrackerFiles = @()
$rawTrackerRoot = Get-ChildItem (Join-Path $pkgRoot '*.psm1') -File -ErrorAction SilentlyContinue
if ($rawTrackerRoot) { $rawTrackerFiles += $rawTrackerRoot }
foreach ($d in @('Scripts', 'Config')) {
    $dir = Join-Path $pkgRoot $d
    if (Test-Path $dir) { $rawTrackerFiles += Get-ChildItem $dir -Filter '*.ps1' -File -ErrorAction SilentlyContinue }
}
function Get-UnlistedRawTrackerCalls {
    # The calls a file's allow-list value does not cover. A reason string allows
    # the whole file; a hashtable allows only the calls whose matched text is in
    # its Lines. $null (no entry) allows nothing.
    param([string]$Text, $Allowance)
    if ($Allowance -is [string]) { return @() }
    $listed = @()
    if ($Allowance -is [hashtable]) { $listed = @($Allowance.Lines) }
    return @(Get-RawTrackerCalls $Text | Where-Object { $listed -notcontains ($_ -replace '^\d+:\s*', '') })
}
$rawTrackerHits = @()
foreach ($f in $rawTrackerFiles) {
    $rel = Get-RelPath $f
    $allowance = $null
    if ($rawTrackerAllowed.ContainsKey($rel)) { $allowance = $rawTrackerAllowed[$rel] }
    foreach ($hit in (Get-UnlistedRawTrackerCalls ([System.IO.File]::ReadAllText($f.FullName)) $allowance)) {
        $rawTrackerHits += "${rel}:$hit"
    }
}
$rawTrackerDetail = "read $($rawTrackerFiles.Count) files"
if ($rawTrackerHits.Count -gt 0) {
    $rawTrackerDetail = "call it as Invoke-P20TrackerRead 'gh' (or 'git') @(...) and read .Code/.Out/.Err (Scripts/Invoke-TrackerRead.ps1): " + ($rawTrackerHits -join '; ')
}
Assert-True "Clause 15: no gh, az or git call with a redirected stderr outside Invoke-TrackerRead.ps1" (($rawTrackerHits.Count -eq 0) -and ($rawTrackerFiles.Count -ge 80)) $rawTrackerDetail

# The sweep's own cases: what it must find, and what only names a call.
$rawTrackerCases = @(
    @{ Hit = $true;  Why = 'a raw call that drops stderr';             Body = '$x = gh api user -q .login 2>$null' }
    @{ Hit = $true;  Why = 'a raw call that keeps stderr as records';  Body = '$out = & gh @Arguments 2>&1' }
    @{ Hit = $true;  Why = 'a raw az call that silences every stream'; Body = 'az boards work-item update --id 1 *> $null' }
    @{ Hit = $true;  Why = 'a raw git call that drops stderr';         Body = '$top = & git rev-parse --show-toplevel 2>$null' }
    @{ Hit = $false; Why = 'a git call through the one helper';        Body = '$r = Invoke-P20TrackerRead ''git'' @(''rev-parse'', ''--show-toplevel'')' }
    @{ Hit = $false; Why = 'a call through the one helper';            Body = '$r = Invoke-P20TrackerRead ''gh'' @(''api'', ''user'')' }
    @{ Hit = $false; Why = 'a comment that names the trap';            Body = '# gh x 2>&1 throws under Stop on 5.1' }
    @{ Hit = $false; Why = 'a hint string that names a call';          Body = 'Write-Host "run: gh auth status 2>&1"' }
    @{ Hit = $false; Why = 'a variable that only ends in the name';    Body = '$gh 2>$null' }
    @{ Hit = $true;  Why = 'a raw call inside an expandable string''s $(...)'; Body = 'Write-Host "$(git rev-parse HEAD 2>$null)"' }
)
foreach ($case in $rawTrackerCases) {
    $caseHits = @(Get-RawTrackerCalls $case.Body).Count
    Assert-True "Clause 15: the sweep $(if ($case.Hit) { 'finds' } else { 'leaves alone' }) $($case.Why)" (($caseHits -gt 0) -eq $case.Hit) "hits: $caseHits"
}

# An entry-level allowance covers its listed calls and nothing else in the file.
$entryBody = "git push 2>&1 | ForEach-Object { Write-Host `$_ }`n`$x = git rev-parse HEAD 2>`$null"
$entryAllow = @{ Reason = 'test'; Lines = @('git push 2>') }
$entryHits = @(Get-UnlistedRawTrackerCalls $entryBody $entryAllow)
Assert-True "Clause 15: an entry-level file reports the raw call its Lines do not list" (($entryHits.Count -eq 1) -and ($entryHits[0] -match 'rev-parse')) "hits: $($entryHits -join '; ')"
Assert-True "Clause 15: an entry-level file lets its listed call through" (@(Get-UnlistedRawTrackerCalls "git push 2>&1 | Out-Null" $entryAllow).Count -eq 0) 'the listed call was reported'
Assert-True "Clause 15: a whole-file reason string allows every raw call in the file" (@(Get-UnlistedRawTrackerCalls $entryBody 'reason').Count -eq 0) 'a string entry reported a call'
Assert-True "Clause 15: no allow-list entry is left marked D3J7 follow-up" (-not (($rawTrackerAllowed.Values | ForEach-Object { if ($_ -is [hashtable]) { $_.Reason } else { $_ } }) -match 'D3J7 follow-up')) 'a follow-up entry remains'

# -- Clause 9: the documented config shape is the implemented one --------------
# Two failures of the same kind, both found on a cold start: the no-config
# warning told a reader to copy the whole shipped table, and docs/CONFIGURATION.md
# told them to patch `orgs` as an ARRAY, which the merge ignores in silence. A
# forkable tool whose first instruction produces a working-but-wrong setup is
# not forkable; these run the module rather than reading it.

$cfgScratch = Join-Path ([System.IO.Path]::GetTempPath()) "p20-portability-cfg-$([guid]::NewGuid())"

function Invoke-WithLocalConfig {
    # Imports a throwaway copy of the package with the given config.local.json
    # and returns every stream as one string. -NoProfile so an autoload shim on
    # the machine cannot shadow the copy under test.
    param([string]$LocalJson, [string]$Snippet)
    $pkg = Join-Path $cfgScratch ([guid]::NewGuid().ToString('N').Substring(0, 8))
    New-Item -ItemType Directory -Path $pkg -Force | Out-Null
    Copy-Item (Join-Path $pkgRoot 'utilities.psm1')      $pkg -Force
    Copy-Item (Join-Path $pkgRoot 'config.default.json') $pkg -Force
    # consts.json travels with the module: utilities.psm1 dot-sources Scripts/Get-Consts.ps1
    # at import and the contract file has no default, so a package without it is not a package.
    Copy-Item (Join-Path $pkgRoot 'consts.json')         $pkg -Force
    Copy-Item (Join-Path $pkgRoot 'Scripts')             $pkg -Recurse -Force
    Copy-Item (Join-Path $pkgRoot 'Config')              $pkg -Recurse -Force
    # A [string] parameter turns $null into '', so this is the guard that means
    # "no local config at all" rather than "an empty one".
    if (-not [string]::IsNullOrWhiteSpace($LocalJson)) {
        Set-Content -Path (Join-Path $pkg 'config.local.json') -Value $LocalJson -Encoding UTF8
    }
    $modulePath = (Join-Path $pkg 'utilities.psm1') -replace "'", "''"
    # The snippet goes to the child in a file, not on its command line. A command line
    # is argv to a native exe, and the two hosts quote it differently: Windows
    # PowerShell 5.1 hands a bare " over as nothing (a snippet spelling "azure-demo"
    # arrived as azure-demo, a parse error), and pwsh 7 re-escapes a \" a caller
    # added to survive that. A file has no argv to get wrong on either.
    $runner = Join-Path $pkg 'run-snippet.ps1'
    Set-Content -Path $runner -Value "Import-Module '$modulePath' -Force -DisableNameChecking`n$Snippet" -Encoding UTF8
    $out = & pwsh -NoProfile -File $runner 2>&1
    return (($out | ForEach-Object { $_.ToString() }) -join "`n")
}

try {
    # 9a -- the no-config notice points at Start, and never at a copy. Earlier,
    # it was a WARNING teaching the sparse patch by hand, with a dev.azure.com
    # example, one command before Start writes the file itself.
    # An interactive shell has no TOOLKIT_QUIET_STARTUP, so the banner must still print there;
    # a marker inherited from the runner is cleared for this one import and put back.
    $prevQuiet9a = $env:TOOLKIT_QUIET_STARTUP
    Remove-Item Env:\TOOLKIT_QUIET_STARTUP -ErrorAction SilentlyContinue
    try { $noConfig = Invoke-WithLocalConfig -LocalJson $null -Snippet '$null' }
    finally { if ($null -ne $prevQuiet9a) { $env:TOOLKIT_QUIET_STARTUP = $prevQuiet9a } }
    # A non-interactive caller (the agent's bridge) sets TOOLKIT_QUIET_STARTUP and gets the
    # verb's own output with nothing before it.
    try {
        $env:TOOLKIT_QUIET_STARTUP = '1'
        $noConfigQuiet = Invoke-WithLocalConfig -LocalJson $null -Snippet '$null'
    }
    finally {
        if ($null -eq $prevQuiet9a) { Remove-Item Env:\TOOLKIT_QUIET_STARTUP -ErrorAction SilentlyContinue }
        else { $env:TOOLKIT_QUIET_STARTUP = $prevQuiet9a }
    }
    Assert-True "Clause 9a: TOOLKIT_QUIET_STARTUP keeps the not-set-up banner out of a non-interactive import" `
        ($noConfigQuiet -notmatch 'not set up yet') $noConfigQuiet
    Assert-True "Clause 9a: the no-config notice does not say to copy config.default.json" `
        ($noConfig -notmatch 'Copy config\.default\.json') $noConfig
    Assert-True "Clause 9a: it says the machine is not set up and names the Start verb" `
        ($noConfig -match 'not set up yet' -and $noConfig -match 'Start for a sample hub') $noConfig
    Assert-True "Clause 9a: it leaves the by-hand route to docs/CONFIGURATION.md" `
        ($noConfig -match 'docs/CONFIGURATION\.md') $noConfig
    Assert-True "Clause 9a: nothing is wrong yet, so it is not a WARNING" `
        ($noConfig -notmatch 'WARNING') $noConfig
    Assert-True "Clause 9a: and the first screen asks for no Azure DevOps" `
        ($noConfig -notmatch 'dev\.azure\.com') $noConfig

    # 9b -- the documentation's own config.local.json example parses and merges.
    # Taken from the file, so the two cannot drift: an example that stops working
    # is a failure. The example lives in docs/CONFIGURATION.md.
    $readmeText = Get-Content (Join-Path $pkgRoot 'docs/CONFIGURATION.md') -Raw
    # The example teaches the CURRENT spelling: "spaces" / "activeSpace". The old
    # "orgs" / "activeOrg" are still read (9c, 9d pin that) but a new reader copies this
    # block, so the docs must not teach them. [^`]*? keeps the match inside one fence.
    $exampleMatch = [regex]::Match($readmeText, '(?s)```json\s*(\{[^`]*?"spaces"[^`]*?\})\s*```')
    Assert-True "Clause 9b: docs/CONFIGURATION.md has a config.local.json example" $exampleMatch.Success
    if ($exampleMatch.Success) {
        $example = $exampleMatch.Groups[1].Value
        Assert-True "Clause 9b: the example spells the keys activeSpace / spaces, not the older activeOrg / orgs" `
            (($example -match '"activeSpace"') -and ($example -notmatch '"activeOrg"') -and ($example -notmatch '"orgs"')) $example
        $parsed = $null
        try { $parsed = $example | ConvertFrom-Json } catch { $parsed = $null }
        Assert-True "Clause 9b: the example is valid JSON" ($null -ne $parsed) $example

        $merged = Invoke-WithLocalConfig -LocalJson $example -Snippet '$global:P20Config.ActiveSpace'
        Assert-True "Clause 9b: the example's activeSpace is what the module resolves" `
            ($merged -match 'azure-demo') $merged
        # The README's example names a Windows hub, which does not exist on the
        # machine running this suite -- and since f9c2bfd the module says so,
        # once, deliberately. That is a fact about this host, not about the
        # example's SHAPE, which is what this clause is about. Every other
        # warning still fails it.
        $shapeWarnings = @($merged -split "`n" |
            Where-Object { $_ -match 'WARNING' -and $_ -notmatch 'Hub not found' })
        Assert-True "Clause 9b: the example produces no warning about its shape" `
            ($shapeWarnings.Count -eq 0) $merged
    }

    # 9c -- the object form, keyed by slug, is applied.
    $objectForm = '{ "quietStart": true, "activeOrg": "azure-demo", "orgs": { "azure-demo": { "name": "ObjectFormOrg" } } }'
    $objOut = Invoke-WithLocalConfig -LocalJson $objectForm -Snippet '($global:P20Config.Spaces | Where-Object { $_.slug -eq "azure-demo" }).name'
    Assert-True "Clause 9c: an orgs object keyed by slug patches the shipped entry" `
        ($objOut -match 'ObjectFormOrg') $objOut

    # 9d -- the array form is the natural wrong guess, because the SHIPPED file
    # is an array. It cannot be made to work (it is a different shape), so it
    # must at least be loud.
    $arrayForm = '{ "quietStart": true, "activeOrg": "azure-demo", "orgs": [ { "slug": "azure-demo", "name": "ArrayFormOrg" } ] }'
    $arrOut = Invoke-WithLocalConfig -LocalJson $arrayForm -Snippet '($global:P20Config.Spaces | Where-Object { $_.slug -eq "azure-demo" }).name'
    Assert-True "Clause 9d: an orgs ARRAY in config.local.json warns" `
        ($arrOut -match 'WARNING' -and $arrOut -match "'spaces' is an array") $arrOut
    Assert-True "Clause 9d: the warning names the shape it wanted" `
        ($arrOut -match 'keyed by slug') $arrOut
    Assert-True "Clause 9d: the array form still applies nothing" `
        ($arrOut -notmatch 'ArrayFormOrg') $arrOut
}
catch {
    Assert-True 'the cases ran to the end without a terminating error' $false $_.Exception.Message
}
finally {
    Remove-Item -Path $cfgScratch -Recurse -Force -ErrorAction SilentlyContinue
}

# -- Clause 16: one copy of the standalone fallbacks ---------------------------
# A script run with no module loaded takes Get-CliPrefix and Write-CliError from
# Scripts/Initialize-CliFallbacks.ps1, which it dot-sources. Every script used to
# carry its own pair, and copies drift: some of them stopped recording the stated
# reason in $global:P20StatedError, so a refusal from those lost it. A definition
# of either name anywhere else in Scripts/ is a new copy waiting to drift.
$fbFile    = 'Initialize-CliFallbacks.ps1'
$fbPattern = '^\s*function\s+(global:)?(Get-CliPrefix|Write-CliError)\b'
$fbScripts = @(Get-ChildItem (Join-Path $pkgRoot 'Scripts') -Filter '*.ps1' -File -ErrorAction SilentlyContinue)
$fbHits = @()
foreach ($f in $fbScripts) {
    if ($f.Name -eq $fbFile) { continue }
    $lineNo = 0
    foreach ($line in [System.IO.File]::ReadAllLines($f.FullName)) {
        $lineNo++
        if ($line -match $fbPattern) { $fbHits += "Scripts/$($f.Name):$lineNo  $($Matches[2])" }
    }
}
$fbDetail = "read $($fbScripts.Count) scripts"
if ($fbHits.Count -gt 0) {
    $fbDetail = "dot-source Scripts/$fbFile instead of defining the helper: " + ($fbHits -join '; ')
}
Assert-True "Clause 16: no script in Scripts/ defines its own Get-CliPrefix or Write-CliError" (($fbHits.Count -eq 0) -and ($fbScripts.Count -ge 40)) $fbDetail
$fbPrelude = Join-Path (Join-Path $pkgRoot 'Scripts') $fbFile
$fbNames = @()
if (Test-Path $fbPrelude) {
    foreach ($line in [System.IO.File]::ReadAllLines($fbPrelude)) {
        if ($line -match $fbPattern) { $fbNames += $Matches[2] }
    }
}
Assert-True "Clause 16: Scripts/$fbFile defines both, once each" (
    (@($fbNames | Where-Object { $_ -eq 'Get-CliPrefix' }).Count -eq 1) -and
    (@($fbNames | Where-Object { $_ -eq 'Write-CliError' }).Count -eq 1)) "found: $($fbNames -join ', ')"
$fbDotSourced = @($fbScripts | Where-Object { $_.Name -ne $fbFile -and ([System.IO.File]::ReadAllText($_.FullName)).Contains("'$fbFile'") })
Assert-True "Clause 16: the scripts dot-source it ($($fbDotSourced.Count))" ($fbDotSourced.Count -ge 40) "dot-sourced by $($fbDotSourced.Count)"
Assert-True "Clause 16: the sweep finds an inline definition, indented or global, and not a call" (
    ('    function Write-CliError {' -match $fbPattern) -and
    ('function global:Get-CliPrefix {' -match $fbPattern) -and
    (-not ('    Write-CliError -Message "x"' -match $fbPattern)) -and
    (-not ('function Get-CliPrefixes {' -match $fbPattern))) ''

# ── The scan exclusions are relative to the package root ─────────────────────
# A checkout whose own path runs through an excluded name (an agent worktree
# under .claude/worktrees/) must still be read; a decoy INSIDE the tree must not.
$pinBase = Join-Path ([System.IO.Path]::GetTempPath()) ("p20-scan-" + [guid]::NewGuid().ToString('N'))
$pinRoot = Join-Path (Join-Path (Join-Path $pinBase '.dot') 'worktrees') 'pkg'
try {
    foreach ($rel in @('Scripts/a.ps1', 'Scripts/b.ps1', 'web/src/c.ts', 'web/node_modules/x.js')) {
        $pinPath = Join-Path $pinRoot $rel
        New-Item -ItemType Directory -Force -Path (Split-Path $pinPath -Parent) | Out-Null
        Set-Content -LiteralPath $pinPath -Value 'x'
    }
    $pinFiles = @(Get-ChildItem $pinRoot -Recurse -File)
    $pinKept = @($pinFiles | Select-ScannableFile -Root $pinRoot | ForEach-Object { $_.Name } | Sort-Object)
    Assert-True "Scan exclusions: a tree under a .dot/worktrees path is read, the node_modules decoy is not" (
        ($pinKept -join ',') -eq 'a.ps1,b.ps1,c.ts') "kept: $($pinKept -join ', ')"
} catch {
    Assert-True 'the cases ran to the end without a terminating error' $false $_.Exception.Message
} finally {
    Remove-Item -LiteralPath $pinBase -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host ""
Write-Host "  Results: $script:passed/$($script:passed + $script:failed) passed" -ForegroundColor $(if ($script:failed -eq 0) { 'Green' } else { 'Red' })
if ($script:failed -gt 0) {
    Write-Host ""
    foreach ($e in $script:errors) { Write-Host "  $e" -ForegroundColor Red }
}
Write-Host ""

if ($script:failed -gt 0) { exit 1 }
exit 0
