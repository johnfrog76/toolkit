<#
.SYNOPSIS
    Drive a meeting session through its three stages -- plan, prep, retro.
.DESCRIPTION
    A session is one file that moves through three stages before becoming a
    record. This command creates it, stamps which stage it is in, and tells you
    what to run next. Stage is stored in the file's own "## Stage" heading, so
    the state is derived from the file the same way a prompt card's is.

    Without a stage flag it reports the current session's status.

    Where the prompt text comes from: the shipped agentic prompt
    agentic/manager1on1.prompt.md, which detects the pass from the file's own
    contents. The three per-stage prompt files this used to print from lived in
    the hub and are retired; nothing reads them any more.
.EXAMPLE
    {cliPrefix}MeetingAgenda
.EXAMPLE
    {cliPrefix}MeetingAgenda -Plan
.EXAMPLE
    {cliPrefix}MeetingAgenda -Date <yyyy-mm-dd> -Retro
.NOTES
    PowerShell 5.1 compatible (ASCII dashes only).
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory = $false)]
    [string]$Date,

    [Parameter(Mandatory = $false)]
    [string]$Type = '1on1',

    [Parameter(Mandatory = $false)]
    [switch]$Plan,

    [Parameter(Mandatory = $false)]
    [switch]$Prep,

    [Parameter(Mandatory = $false)]
    [switch]$Retro,

    # -Close is a SEPARATE switch rather than something -Retro does, and that is
    # deliberate. -Retro is a stage stamp run within 30 minutes of the meeting,
    # before the notes exist -- it is re-runnable, and it leaves the file open
    # precisely because the record is still being written. Closing is the later,
    # one-way event: the record is complete, the file leaves current/ and gets
    # the date it closed. Folding the move into -Retro would archive a session
    # mid-sentence and would make a re-run of a stage stamp a destructive act.
    [Parameter(Mandatory = $false)]
    [switch]$Close,

    [Parameter(Mandatory = $false)]
    [switch]$DryRun,

    [Parameter(Mandatory = $false)]
    [switch]$Help
)

$repoRoot = Split-Path -Parent $PSScriptRoot

if (-not (Get-Command Get-CliPrefix -ErrorAction SilentlyContinue)) {
    function Get-CliPrefix {
        if ($global:P20Config -and $global:P20Config.CommandPrefix) { return $global:P20Config.CommandPrefix }
        return ''
    }
}

# Write-CliError normally comes from the module too, and it is what makes a
# refusal ONE block: the wrapper sees the stated exit code and adds nothing.
# See AGENTS.md, "The refusal contract".
if (-not (Get-Command Write-CliError -ErrorAction SilentlyContinue)) {
    function Write-CliError {
        param([string]$Message, [string]$Hint)
        $global:P20StatedError = $Message
        Write-Host "Error: $Message" -ForegroundColor Red
        if ($Hint) { Write-Host "Hint:  $Hint" -ForegroundColor Yellow }
    }
}

# -- The hub-root folder's NAME is the hub's, not this script's ----------------
# hub.json's "folders" block can rename manager/. Resolved BEFORE -Help so the
# help text names the folder this hub actually uses; Resolve-HubConfig.ps1 falls
# back to the shipped default when there is no hub to ask. Dot-sourced rather
# than reached through the module because this script also runs with no module
# in the session (a test sandbox, pwsh -File).
. (Join-Path $PSScriptRoot 'Resolve-HubConfig.ps1')
. (Join-Path $PSScriptRoot 'Get-Consts.ps1')
# Whether a session's "## Carried from" heading still names the latest earlier
# session in its series -- the rule docs/hub/manager.md owns, "Which session a
# record carries from". Read and reported; never rewritten.
. (Join-Path $PSScriptRoot 'Resolve-CarriedFrom.ps1')
# One resolver for "where is the hub", env first then config -- see
# Get-P20PromptsRoot. Both of this script's roots came from a hand-rolled
# config-first fallback.
$managerHubRoot = Get-P20PromptsRoot -PackageRoot $repoRoot
$managerFolder = (Get-P20HubFolderNames -PromptsRoot $managerHubRoot -PackageRoot $repoRoot)['manager']

if ($Help) {
    $p = Get-CliPrefix
    Write-Host ""
    Write-Host "  ${p}MeetingAgenda -- the meeting session lifecycle" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  Usage:" -ForegroundColor Yellow
    Write-Host "    ${p}MeetingAgenda                         Status of today's session"
    Write-Host "    ${p}MeetingAgenda -Plan                   Create the session, stage it for the agenda pass"
    Write-Host "    ${p}MeetingAgenda -Prep                   Same-morning state check"
    Write-Host "    ${p}MeetingAgenda -Retro                  Stage it for the post-meeting pass"
    Write-Host "    ${p}MeetingAgenda -Close                  Record complete: move it to $managerFolder/archive/ and stamp the date"
    Write-Host "    ${p}MeetingAgenda -Date YYYY-MM-DD -Plan  Target a specific date"
    Write-Host "    ${p}MeetingAgenda -Type <t>               The series: which recurring meeting (default 1on1; client-weekly, team-sync ...)"
    Write-Host "    ${p}MeetingAgenda -Plan -DryRun           Print the path that would be created, write nothing"
    Write-Host ""
    Write-Host "  Stages:" -ForegroundColor Yellow
    Write-Host "    Plan   1-2 days before. Pulls the prior session's carry-forward."
    Write-Host "    Prep   Same morning. Not about content -- about state."
    Write-Host "    Retro  Within 30 minutes after. Capture while it is fresh."
    Write-Host "    Close  Once the record is complete. Moves the file to $managerFolder/archive/"
    Write-Host "           and stamps '$((Get-P20Consts).stamps.closed) YYYY-MM-DD' -- the same stamp ${p}Archive"
    Write-Host "           writes, and what the billing timeline reads."
    Write-Host ""
    Write-Host "  Each stage stamps '## Stage' in the session file. The agent prompt"
    Write-Host "  agentic/manager1on1.prompt.md reads the file and picks its own pass."
    Write-Host ""
    return
}

# -- The hub ---------------------------------------------------------------------
$promptsRoot = Get-P20PromptsRoot -PackageRoot $repoRoot
if (-not (Test-P20HubRoot $promptsRoot)) {
    Write-CliError -Message (Get-P20HubMissingMessage $promptsRoot)
    exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
}

if (-not $Date) { $Date = (Get-Date).ToString('yyyy-MM-dd') }
if ($Date -notmatch '^\d{4}-\d{2}-\d{2}$') {
    Write-Error "Invalid date '$Date' -- expected YYYY-MM-DD."
    return
}

# One writer for the "**Closed:**" stamp, shared with Archive -- see
# Scripts/Add-ClosedStamp.ps1 for why it is a dot-source and not a module call.
$closedStampPath = Join-Path $PSScriptRoot 'Add-ClosedStamp.ps1'
if (Test-Path $closedStampPath) { . $closedStampPath }

# ... and the byte contract underneath it, which this script's own writers need
# whether or not the stamp is there: UTF-8 with no BOM, LF when a session is
# created, the file's own terminator when one is edited.
# See Scripts/Write-CardText.ps1.
$cardWriterPath = Join-Path $PSScriptRoot 'Write-CardText.ps1'
if (Test-Path $cardWriterPath) { . $cardWriterPath }

$managerRoot = Join-Path $promptsRoot $managerFolder
$currentDir = Join-Path $managerRoot 'current'
$archiveDir = Join-Path $managerRoot 'archive'

# -- The series -------------------------------------------------------------------
# -Type IS the series (docs/hub/manager.md, "Where it lives"): a named recurring meeting
# with its own carry-forward. The 1:1 is the default series and its records are
# named by date alone, as they always were; any other series carries its name in
# front of the date -- `client-weekly-<date>.md` -- the way a card carries its
# type, so two meetings on one day cannot collide. The name rule is the
# contract's (consts.json regex.sessionName), read by the agent too.
$defaultSeries = '1on1'
if ($Type -ne $defaultSeries -and $Type -notmatch '^[a-z0-9]+(-[a-z0-9]+)*$') {
    Write-CliError -Message "'$Type' is not a series name." `
        -Hint "Lower-case letters, digits and dashes: client-weekly, team-sync. The 1:1 needs no -Type."
    exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
}
$isDefaultSeries = ($Type -eq $defaultSeries)
$sessionName = if ($isDefaultSeries) { "$Date.md" } else { "$Type-$Date.md" }
$sessionLabel = if ($isDefaultSeries) { '1:1' } else { $Type }
$templatePath = Join-Path (Join-Path $repoRoot 'templates') 'ManagerSession.template.md'
# The shipped name; the copy that runs is resolved below -- an extension folder
# of the engineer's own wins when it carries the file (Scripts/Resolve-AgenticPrompt.ps1).
. (Join-Path $PSScriptRoot 'Resolve-AgenticPrompt.ps1')
$agentPromptResolved = Resolve-P20AgenticPrompt -Name 'manager1on1.prompt.md'
$agentPromptRel = if ($agentPromptResolved.Source -eq 'extension') { "$($agentPromptResolved.Path) (your extension copy)" } else { 'agentic/manager1on1.prompt.md' }

# -- Helpers ---------------------------------------------------------------------

function Get-SessionSeries {
    # (series, date) from a record's name by the contract's rule; $null for a file that is not one.
    param([string]$Name)
    return (Get-P20SessionNameParts $Name)
}

function Get-CarriedFromNote {
    # The stated line for a session whose "## Carried from" heading no longer
    # names the latest earlier session in its series; '' when it does.
    param([string]$Path)
    return (Format-P20CarriedFromNote (Get-P20CarriedFromCheck -Path $Path -Folders @($currentDir, $archiveDir)))
}

function Get-NextSessionNote {
    # A session about to be created for an earlier date sits in front of a later
    # one, whose heading still names what came before. The line that says so,
    # or ''; asked BEFORE the write, with this session named as about to exist.
    $next = Get-P20NextSessionPath -Series $Type -Date $Date -Folders @($currentDir, $archiveDir)
    if (-not $next) { return '' }
    $note = Format-P20CarriedFromNote (Get-P20CarriedFromCheck -Path $next -Folders @($currentDir, $archiveDir) -Also @($sessionName))
    if (-not $note) { return '' }
    return "$(Split-Path $next -Leaf) -- $note"
}

function Get-PriorSessionDate {
    # The most recent record IN THIS SERIES before $Date, across both folders.
    # Carry-forward means "last time with these people", so a client weekly
    # never carries from the 1:1.
    $all = @()
    foreach ($dir in @($currentDir, $archiveDir)) {
        if (-not (Test-Path $dir)) { continue }
        foreach ($f in (Get-ChildItem -Path $dir -Filter '*.md' -File)) {
            $r = Get-SessionSeries $f.Name
            if ($r -and $r.Series -eq $Type -and $r.Date -lt $Date) { $all += $r.Date }
        }
    }
    return ($all | Sort-Object -Descending | Select-Object -First 1)
}

function Get-SessionStage {
    param([string]$Path)
    if (-not (Test-Path $Path)) { return $null }
    $inStage = $false
    foreach ($line in (Get-Content $Path)) {
        if ($inStage) {
            $v = $line.Trim()
            if ($v) { return $v }
            return 'draft'
        }
        if ($line.Trim() -eq '## Stage') { $inStage = $true }
    }
    return 'draft'
}

function Set-SessionStage {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Inner helper; the caller owns the ShouldProcess decision.')]
    param([string]$Path, [string]$Stage)
    $content = Get-Content $Path -Raw
    $content = $content -replace '(?m)(^## Stage\r?\n)\S[^\r\n]*', "`${1}$Stage"
    # EDITING: the file keeps the terminator it already has, and gains no BOM.
    # This rewrites the whole file on every stage change, so writing a BOM here
    # meant every Plan/Prep/Retro put one back that -Close would strip again.
    Write-CardText -Path $Path -Content $content
}

function Get-SectionValue {
    param([string[]]$Lines, [string]$Heading)
    $inSection = $false
    $result = @()
    foreach ($line in $Lines) {
        if ($inSection) {
            if ($line -match '^##') { break }
            $t = $line.Trim()
            if ($t -and $t -ne '---') { $result += $t }
        }
        if ($line.Trim() -eq "## $Heading") { $inSection = $true }
    }
    return ($result -join "`n").Trim()
}

function New-SessionFile {
    if (-not (Test-Path $currentDir)) { New-Item -Path $currentDir -ItemType Directory -Force | Out-Null }
    if (-not (Test-Path $archiveDir)) { New-Item -Path $archiveDir -ItemType Directory -Force | Out-Null }

    $filePath = Join-Path $currentDir $sessionName
    if (Test-Path $filePath) { return $filePath }

    if (-not (Test-Path $templatePath)) {
        Write-Error "Template not found: $templatePath"
        return $null
    }

    $prior = Get-PriorSessionDate
    if (-not $prior) { $prior = '(none)' }

    $content = Get-Content -Path $templatePath -Raw -Encoding UTF8
    # The heading names the series where there is one; the 1:1 keeps the bare date.
    $content = $content -replace '^# \{\{DATE\}\}', ('# ' + $(if ($isDefaultSeries) { $Date } else { "$Type $Date" }))
    $content = $content -replace '\{\{DATE\}\}', $Date
    $content = $content -replace '\{\{PRIOR_DATE\}\}', $prior
    $nextNote = Get-NextSessionNote
    # No BOM, and -New because this CREATES the session: LF on every host, even
    # from a template a Windows clone checked out CRLF. Set-SessionStage above
    # is the other half -- it EDITS, so it passes no -New and the file keeps
    # whatever terminator it already has.
    Write-CardText -Path $filePath -Content $content -New
    Write-Host "Created session: $managerFolder/current/$sessionName" -ForegroundColor Green
    if ($nextNote) { Write-Host "  Check:   $nextNote" -ForegroundColor Yellow }
    return $filePath
}

# The stage block. It says what this stage is for, what the agent needs from
# you, and which prompt to run -- the prompt itself ships in this package and
# is not reprinted here, so there is one copy of that text, not two.
function Show-StageBlock {
    param([string]$Label, [string]$Purpose, [string[]]$Provide, [string]$Context, [string]$AgentPrompt)

    $divider = '-' * 60
    Write-Host ""
    Write-Host "  $divider" -ForegroundColor DarkGray
    Write-Host "  $Label -- $Purpose" -ForegroundColor Cyan
    Write-Host "  $divider" -ForegroundColor DarkGray
    Write-Host ""

    if ($Context) {
        Write-Host $Context -ForegroundColor Yellow
        Write-Host ""
    }

    if ($Provide) {
        Write-Host "  WHAT YOU PROVIDE:" -ForegroundColor DarkGray
        foreach ($line in $Provide) { Write-Host "  $line" }
        Write-Host ""
    }

    if ($AgentPrompt) {
        Write-Host "  RUN:" -ForegroundColor DarkGray
        Write-Host "  $AgentPrompt"
        Write-Host ""
    }

    Write-Host "  $divider" -ForegroundColor DarkGray
    Write-Host ""
}

# -- No flags: report status ------------------------------------------------------

if (-not $Plan -and -not $Prep -and -not $Retro -and -not $Close) {
    # The quick menu. With no date and no series named, every open record, each
    # with its stage and the exact next command -- the three lines a person
    # types this verb to read.
    # With one series it is the block it always was.
    if (-not $PSBoundParameters.ContainsKey('Date') -and -not $PSBoundParameters.ContainsKey('Type') -and (Test-Path $currentDir)) {
        $open = @()
        foreach ($f in (Get-ChildItem -Path $currentDir -Filter '*.md' -File)) {
            $r = Get-SessionSeries $f.Name
            if ($r) { $open += $r }
        }
        if ($open.Count -gt 0) {
            Write-Host ""
            foreach ($r in ($open | Sort-Object { $_.Series -ne $defaultSeries }, Series, Date)) {
                $st = Get-SessionStage (Join-Path $currentDir $r.Name)
                $nx = 'Plan (next session)'
                if ($st -eq 'draft') { $nx = 'Prep' } elseif ($st -eq 'prep') { $nx = 'Retro' } elseif ($st -eq 'retro') { $nx = 'Close' }
                $lbl = if ($r.Series -eq $defaultSeries) { '1:1' } else { $r.Series }
                $typeArg = if ($r.Series -eq $defaultSeries) { '' } else { " -Type $($r.Series)" }
                Write-Host "  $lbl - $($r.Date)  [$st]" -ForegroundColor Cyan
                $note = Get-CarriedFromNote (Join-Path $currentDir $r.Name)
                if ($note) { Write-Host "  Check:   $note" -ForegroundColor Yellow }
                Write-Host "  Next:    $(Get-CliPrefix)MeetingAgenda$typeArg -Date $($r.Date) -$nx" -ForegroundColor DarkGray
                Write-Host ""
            }
            return
        }
    }

    $filePath = Join-Path $currentDir $sessionName
    if (-not (Test-Path $filePath)) {
        Write-Host ""
        Write-Host "  No session for $Date." -ForegroundColor DarkGray
        Write-Host "  Run: $(Get-CliPrefix)MeetingAgenda -Plan" -ForegroundColor DarkGray
        Write-Host ""
        return
    }

    $stage = Get-SessionStage $filePath
    # The body under the heading the FILE has, not under one recomputed here: a
    # heading that names another session used to read as nothing carried at all.
    # Whether it names the right one is the check's to say, on its own line.
    $check = Get-P20CarriedFromCheck -Path $filePath -Folders @($currentDir, $archiveDir)
    $carried = ''
    if ($check.Verdict -ne 'absent' -and $check.Named -ne '(none)') {
        $carried = Get-SectionValue -Lines (Get-Content $filePath -Encoding UTF8) -Heading "Carried from $($check.Named)"
    }
    $carriedNote = Format-P20CarriedFromNote $check

    $next = 'Plan (next session)'
    if ($stage -eq 'draft') { $next = 'Prep' }
    elseif ($stage -eq 'prep') { $next = 'Retro' }

    Write-Host ""
    Write-Host "  Agenda ($sessionLabel) - $Date  [$stage]" -ForegroundColor Cyan
    if ($carried) { Write-Host "  Carried: $carried" -ForegroundColor DarkGray }
    if ($carriedNote) { Write-Host "  Check:   $carriedNote" -ForegroundColor Yellow }
    Write-Host "  File:    $managerFolder/current/$sessionName" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  Next:    $(Get-CliPrefix)MeetingAgenda -$next" -ForegroundColor DarkGray
    Write-Host ""
    return
}

# -- Plan -------------------------------------------------------------------------

if ($Plan) {
    if ($DryRun) {
        Write-Output (Join-Path $currentDir $sessionName)
        return
    }
    $filePath = New-SessionFile
    if (-not $filePath) { return }

    # Carry-forward is read from the prior session's retro rather than asked
    # for: it is already written down, and re-typing it is how it drifts.
    $context = ''
    $prior = Get-PriorSessionDate
    if ($prior) {
        # The prior record is named the way this session is: its own series in
        # front of the prior date, the default series by date alone.
        $priorName = New-P20SessionFileName -Series $Type -Date $prior
        $priorPath = $null
        foreach ($dir in @($currentDir, $archiveDir)) {
            $p = Join-Path $dir $priorName
            if (Test-Path $p) { $priorPath = $p; break }
        }
        if ($priorPath) {
            $retroText = Get-SectionValue -Lines (Get-Content $priorPath) -Heading 'Retro'
            if ($retroText) {
                $indented = $retroText -replace "`n", "`n  "
                $context = "  Carry-forward from ${prior}:`n  $indented"
            }
        }
    }

    # The carry-forward above is the latest earlier session's; the agent prompt
    # reads the session's own heading. When the two differ, say so here.
    $carriedNote = Get-CarriedFromNote $filePath
    if ($carriedNote) {
        $context = (@($context, "  Check: $carriedNote") | Where-Object { $_ }) -join "`n"
    }

    Set-SessionStage -Path $filePath -Stage 'draft'
    Show-StageBlock -Label 'PLAN' -Purpose 'run this 1-2 days before' -Context $context `
        -Provide @(
            'Since last session -- what happened, what shipped, what changed.',
            'Unresolved / forward -- anything still open, and one thing you are',
            '  thinking about beyond the current sprint.'
        ) `
        -AgentPrompt $agentPromptRel
    Write-Host "  Write your notes into '## Since Last Session' and" -ForegroundColor DarkGray
    Write-Host "  '## Unresolved / Forward' in $managerFolder/current/$sessionName, then run the prompt." -ForegroundColor DarkGray
    Write-Host ""
}

# -- Prep -------------------------------------------------------------------------

if ($Prep) {
    $filePath = Join-Path $currentDir $sessionName
    if (-not (Test-Path $filePath)) {
        Write-Host "No session for $Date. Run '$(Get-CliPrefix)MeetingAgenda -Plan' first." -ForegroundColor Yellow
        return
    }
    Set-SessionStage -Path $filePath -Stage 'prep'
    # No agent prompt: prep is a state check, not a writing pass. The questions
    # are the whole of it, and an assistant adds nothing to answering them.
    Show-StageBlock -Label 'PREP' -Purpose 'run this the same morning' `
        -Provide @(
            'How are you walking in -- settled, rushed, carrying something?',
            'Is anything in the agenda likely to land reactive? Which item?',
            'One sentence: how you intend to show up.'
        ) `
        -AgentPrompt ''
    Write-Host "  This one is for you. Nothing needs writing back to the file." -ForegroundColor DarkGray
    Write-Host ""
}

# -- Retro ------------------------------------------------------------------------

if ($Retro) {
    $filePath = Join-Path $currentDir $sessionName
    if (-not (Test-Path $filePath)) {
        Write-Host "No session for $Date. Run '$(Get-CliPrefix)MeetingAgenda -Plan' first." -ForegroundColor Yellow
        return
    }
    Set-SessionStage -Path $filePath -Stage 'retro'
    Show-StageBlock -Label 'RETRO' -Purpose 'run this within 30 minutes after' `
        -Provide @(
            'What got covered. What did not.',
            'Commitments on both sides, with timelines where they were given.',
            'How you showed up -- honestly.'
        ) `
        -AgentPrompt $agentPromptRel
    Write-Host "  Write the raw notes into '## Retro' in $managerFolder/current/$sessionName," -ForegroundColor DarkGray
    Write-Host "  then run the prompt: it rewrites that section in place." -ForegroundColor DarkGray
    # Still deliberately not "$(Get-CliPrefix)Archive": that verb is org-scoped --
    # it moves a prompt card out of the ACTIVE ORG's current/ -- and manager/ is
    # a sibling of the org folders, so it would not find this file. What changed
    # is that the move is no longer a manual mv: -Close owns it,
    # and owning it is what gets the "**Closed:**" stamp written, which a hand
    # move never did.
    Write-Host "  When the record is complete, run '$(Get-CliPrefix)MeetingAgenda -Date $Date -Close'." -ForegroundColor DarkGray
    Write-Host "  That moves it to $managerFolder/archive/ and stamps the date it closed." -ForegroundColor DarkGray
    Write-Host ""
}

# -- Close ------------------------------------------------------------------------

if ($Close) {
    $filePath = Join-Path $currentDir $sessionName
    $destPath = Join-Path $archiveDir $sessionName

    if (-not (Test-Path $filePath)) {
        # Idempotent: a second -Close on a session already retired is a report,
        # not an error. The state is derived from where the file is, exactly as
        # a prompt card's is.
        if (Test-Path $destPath) {
            Write-Host "Already closed: $managerFolder/archive/$sessionName" -ForegroundColor DarkGray
            return
        }
        Write-Host "No session for $Date. Run '$(Get-CliPrefix)MeetingAgenda -Plan' first." -ForegroundColor Yellow
        return
    }

    if ($DryRun) {
        Write-Host "Would move $managerFolder/current/$sessionName to $managerFolder/archive/$sessionName" -ForegroundColor Yellow
        Write-Host "Would stamp '$((Get-P20Consts).stamps.closed) $((Get-Date -Format 'yyyy-MM-dd'))'" -ForegroundColor Yellow
        return
    }

    if ($PSCmdlet.ShouldProcess("$managerFolder/current/$sessionName", 'Close and archive')) {
        # The destination folder is created here rather than assumed. New-SessionFile
        # makes both folders, but -Close can be the first thing a process runs
        # against a hub whose session file arrived some other way -- and an archive
        # verb that fails because its own destination is missing is a bug this
        # package has already had once, in Archive.
        if (-not (Test-Path $archiveDir)) {
            New-Item -Path $archiveDir -ItemType Directory -Force | Out-Null
        }

        if (Test-Path $destPath) {
            # A refusal the caller can see: this used to report in yellow and
            # return, leaving $LASTEXITCODE 0, so a duplicate in current/ read as
            # a successful close.
            Write-CliError -Message "A session for $Date is already in $managerFolder/archive/. Not overwriting it." `
                -Hint "The archived copy is the record. Compare it with $managerFolder/current/$sessionName and delete whichever is the duplicate."
            exit 2  # stated refusal -- see AGENTS.md, "The refusal contract"
        }

        Move-Item -Path $filePath -Destination $destPath -ErrorAction Stop

        # Stamped AFTER the move, on the archived copy, for the same reason
        # Archive does it that way: the move is the promise and the stamp is the
        # record, so a stamp that fails must not leave the file in current/.
        if (Get-Command Add-ClosedDate -ErrorAction SilentlyContinue) {
            Add-ClosedDate -Path $destPath
        }
        else {
            Write-Warning "Add-ClosedStamp.ps1 was not found beside this script; the session moved but was not stamped."
        }

        Write-Host "Closed: $managerFolder/archive/$sessionName" -ForegroundColor Green
    }
}
