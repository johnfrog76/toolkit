<#
.SYNOPSIS
    The ONE list of PowerShell test suites -- what Test-Toolkit.ps1 runs, and
    the thing Test-DocCounts.ps1 checks the documented suite count against.
.DESCRIPTION
    This table lived inline in Test-Toolkit.ps1 until this suite needed to read
    it too: a count typed
    twice is a count that can disagree with itself, which is exactly what
    happened to the DOCUMENTED counts this suite exists to catch. Dot-sourced
    by both, so there is one table rather than two that must be kept in step.

    NOT a runnable verb -- dot-sourced only, the same shape as
    Scripts/Write-ConfigJson.ps1.
#>

function Get-P20ToolkitSuiteRegistry {
    return [ordered]@{
        Consts      = @{ File = 'Test-Consts.ps1'; Description = 'consts.json -- the literals all three halves parse: it reads on the 5.1 floor, every key resolves to the agreed value, the patterns work in .NET, and no script retypes one'; Scope = 'system' }
        Compat      = @{ File = 'Test-PS51Compat.ps1'; Description = 'PowerShell 5.1 syntax and API compatibility'; Scope = 'system' }
        Menu        = @{ File = 'Test-Menu.ps1'; Description = 'Menu system -- config coverage, alias wiring, scoring'; Scope = 'system' }
        Environment = @{ File = 'Test-Environment.ps1'; Description = 'Env -- the optional-surface inventory THROUGH THE WRAPPER: configured nav shortcuts and an org-scoped flag read on, the in-module and direct call shapes print one identical block, and a script cannot shadow the accessors away'; Scope = 'system' }
        Archive     = @{ File = 'Test-Archive.ps1'; Description = 'Move-P20PromptToArchive round-history, partial match, help'; Scope = 'system' }
        PRComments  = @{ File = 'Test-PRComments.ps1'; Description = 'Get-PRComments.ps1 actionable-thread filter (file-anchored, file-less, system, bot)'; Scope = 'system' }
        BackfillStamps = @{ File = 'Test-BackfillStamps.ps1'; Description = 'Backfill-CardStamps.ps1 -- Created/Closed from git history: a folder move is not an event, a copy lends no history, a stamp is never rewritten; run against a scratch repo with fixed dates'; Scope = 'system' }
        Update      = @{ File = 'Test-Update.ps1'; Description = 'Update verb -- fast-forward only against a scratch remote; every refusal (dirty, diverged, detached, no upstream, a copy) changes nothing; what else moved is noticed; -Sync goes through the Sync verb and never runs after a refusal'; Scope = 'system' }
        Start       = @{ File = 'Test-Start.ps1'; Description = 'Start verb -- the first run, end to end from a scratch copy of the package with no config: the sample hub is copied OUT, the machine is pointed at it in an order Config accepts, the same shell sees it afterwards; a machine with a hub keeps it; a folder with anything in it, a folder inside the package, and a configured hub that has gone missing are refusals that change nothing'; Scope = 'system' }
        PullRequest = @{ File = 'Test-PullRequest.ps1'; Description = 'New-PullRequest.ps1 Described Changes parser -- wrapped bullets, lead-in prose, section boundary'; Scope = 'system' }
        CloseWorkItem = @{ File = 'Test-CloseWorkItem.ps1'; Description = 'Close-WorkItem.ps1 transition rule and ADO error-message parsing -- non-Bug -Reason, rejected picklist values'; Scope = 'system' }
        PromptStatus = @{ File = 'Test-Status.ps1'; Description = 'Get-PromptFileStatus state machine against fixtures; Status -Board read-only join against the board (az stubbed), typed as the verb'; Scope = 'system' }
        ThreadHash  = @{ File = 'Test-ThreadHash.ps1'; Description = 'Thread-CommitHash.ps1 -- hashes come from the CODE repo not the hub, one bullet per branch commit with its subject, idempotent re-runs, the card keeps its own bytes'; Scope = 'system' }
        Setup       = @{ File = 'Test-Setup.ps1'; Description = 'Setup verb and Test-P20AdoEnabled -- the rule over every combination of org status, tracker and features.ado, a connected GitHub Space off with its tracker named and its verbs still listed; typed as a verb in a fresh shell with az off the PATH: a missing az is a note and never a failure, the tier is stated, a local org is told nothing is missing, and no hint names a script this package does not have'; Scope = 'system' }
        Move        = @{ File = 'Test-Move.ps1'; Description = 'Move verb -- a person moves a card to a lane and the move is a line in the file: In Progress writes **Started:**, Code Review writes **Review:**, Done is Archive; Backlog and Active move the FILE (backlog/ <-> current/, bytes untouched), a new card lands in backlog/ unless -Now, a backlog card is pulled into current/ before a line is written, and -To Backlog refuses threaded work; typed as a verb in a fresh shell, every refusal exits 2 and writes nothing, a card travels one way, and Status derives the state the verb reported'; Scope = 'system' }
        Billable    = @{ File = 'Test-Billable.ps1'; Description = 'Billable verb and Set-P20CardLine -- the line goes above Created, an unchanged card is not written, the card keeps its own bytes; typed as a verb in a fresh shell: refusals exit 2 and write nothing, an id in any case, a closed card is found in archive/'; Scope = 'system' }
        Plan        = @{ File = 'Test-Plan.ps1'; Description = 'Plan verb -- the write side of the Sprint token: -Milestone writes **Sprint:** whole and never truncated, -Remove deletes it, the two switches refuse together and refuse apart from each other; typed as a verb in a fresh shell: found in current/ AND backlog/ with a backlog card never pulled into play, an archived card not found (planning is forward, not Billable''s after-the-fact), every refusal exit 2 writing nothing, a repeat writing nothing'; Scope = 'system' }
        Cover       = @{ File = 'Test-Cover.ps1'; Description = 'Cover verb and the one reader of a card''s pictures -- Resolve-P20CardImage over the shared table (Tests/fixtures/parsers/covers.json, which the agent asserts too), the card key; typed as a verb in a fresh shell: the copy into assets/<card key>/ and one line above Created, every refusal exit 2 writing nothing, -WhatIf, -Remove, a second round taking cover-r2, a mock left alone, NewPrompt -Cover / -Before at birth, and storeSync: git making the picture and the card one commit'; Scope = 'system' }
        Design      = @{ File = 'Test-Design.ps1'; Description = 'The design lifecycle''s reader (L2) -- the state rule over the shared table (Tests/fixtures/design/states.json, which the agent asserts too), the tree reader over a scratch tree (four folders, grouping by id, no id counted not shown, a shared id a conflict, README skipped, CRLF), and the Design lifecycle surfaces row: not configured (no design/, or nothing but a README in it), on, off with the count; and a card''s design line over the shared table Tests/fixtures/parsers/design-lines.json (which the agent asserts too), and the one name rule Select-P20Design'; Scope = 'system' }
        NewPrompt   = @{ File = 'Test-NewPrompt.ps1'; Description = 'NewPrompt -Title (offline) -- the next free local id counts cards and nothing else, and a scaffolded card is LF with no BOM on every host; and -Design typed in a fresh shell: the Design line under Template with the design''s title, link and id, an id prefix, a spec linked over its note, a repo design by its GitHub page when the repo is the Space''s, nothing or two refused with no card written'; Scope = 'system' }
        ExitCodes   = @{ File = 'Test-ExitCodes.ps1'; Description = 'Exit-code contract -- success exits 0, failure exits non-zero'; Scope = 'system' }
        Autoload    = @{ File = 'Test-Autoload.ps1'; Description = 'Autoload shim -- manifest/alias drift, path resolution, missing-toolkit warning'; Scope = 'system' }
        GitRoot     = @{ File = 'Test-GitRoot.ps1'; Description = 'A folder inside someone else''s repository is not a checkout of its own -- the root check writers use, the tracked-path check readers use, the same folder spelled four ways (8.3 included), and Update refusing a copy inside an enclosing repo without touching it'; Scope = 'system' }
        Sync        = @{ File = 'Test-Sync.ps1'; Description = 'Sync-Prompts.ps1 -- storeSync resolved from the hub, pull and push against a real remote; auto-commit pre-commit hook interaction where the package ships hooks'; Scope = 'system' }
        Connect     = @{ File = 'Test-Connect.ps1'; Description = 'Connect -- the connect wizard''s verb, typed: the report, the address written through Config and implying active, the grain per tracker (D-W17), -Projects on ADO / -Repo on GitHub and each refused on the other, -Sprint, discovery refused without an address or a CLI, -WhatIf, and the Example graduating into your own Space (D-W15)' }
        NewSpace    = @{ File = 'Test-NewSpace.ps1'; Description = 'NewSpace -- add a Space, typed: -Repo a GitHub Space named from the repository, <slug> -Address an Azure DevOps one, <slug> alone your own cards; every key through Config; the folder made or an existing one adopted untouched and counted; no switch, the last line the SwitchSpace; -WhatIf writes nothing; every refusal exit 2 writing nothing; gh stubbed or absent, never required; -Discover marking the Spaces; the proposals over Tests/fixtures/spaces/proposals.json; and the other end: RetireSpace to status archive through Config, RemoveSpace un-declaring a Space with every card in its folder left as it was and the NewSpace line that adopts them back, cards in current/ refused without -Force for a caller that cannot answer, every refusal exit 2 writing nothing'; Scope = 'system' }
        EditItem    = @{ File = 'Test-EditItem.ps1'; Description = 'EditItem -Pin / -Unpin, typed with gh and az stubbed: the tracker''s own pin with the Space''s repo, -WhatIf calls nothing, a fourth pin said in the product''s sentence, and both switches refused on Azure DevOps before az is asked; and NewItem -FromCard typed the same way: the issue from the card''s name and Summary ending Toolkit card: <id>, the URL into the card''s ADO Link line with nothing else moved, -WhatIf creating nothing, and every refusal exit 2; and NewItem -Parent: the parent read first, the new issue added as its sub-issue through the REST route, a task-list line in the parent''s body where GitHub refuses it, -WhatIf printing both and making neither, a missing parent exit 2 with nothing created'; Scope = 'system' }
        PublishPR   = @{ File = 'Test-PublishPR.ps1'; Description = 'PublishPR, typed with az, gh and Invoke-RestMethod stubbed: -WhatIf prints the exact PATCH and calls nothing; the success path is one token, one GET, one PATCH with isDraft false and one PR published: line under the card''s PR URL: line in the card''s own line endings, never written twice; a card with no PR URL: line, a pull request already ready, a GitHub pull request (hint: gh pr ready) and an id that is not a card are each exit 2 writing nothing'; Scope = 'system' }
        Config      = @{ File = 'Test-Config.ps1'; Description = 'Config -- the one writer for configuration: -List names the file each value came from, a machine key creates config.local.json as a sparse patch, an org lands in the hub, a default-only key is refused, and every write is BOM-less LF'; Scope = 'system' }
        HubJson     = @{ File = 'Test-HubJson.ps1'; Description = 'hub.json -- the hub declares its own orgs and hub-root folder names; resolution order, ignored keys, and PS/Python parity against Tests/fixtures/hub-parity'; Scope = 'system' }
        Portability = @{ File = 'Test-Portability.ps1'; Description = 'Could a stranger clone and use this -- no personal identity, org or tenant in committed config; hardcoded-prefix debt ratchet; every suite''s top-level try ends with a catch and every Assert- call resolves'; Scope = 'system' }
        Web         = @{ File = 'Test-Web.ps1'; Description = 'Web launcher -- lifecycle no-ops, missing npm/node_modules/web, the no-Docker sentence, -Help from config'; Scope = 'system' }
        Agent       = @{ File = 'Test-Agent.ps1'; Description = 'Agent launcher -- lifecycle no-ops, web.agentPort is read not hardcoded, missing python, -Help from config'; Scope = 'system' }
        TestAll     = @{ File = 'Test-TestAll.ps1'; Description = 'The Test verb with all three halves stubbed -- the pytest, jest and CLI-runner parsers, the expected counts read from docs/TESTING.md, the summary merge, order, -Half, -Fast, every stated skip, exit 0 / 2, the web child''s environment, and the CLI entries left as the runner wrote them; and CI''s gate: one row per shape a half''s transcript can take, Test-CiHalf.ps1 run as verify.yml runs it, and the workflow reading every half and the browser smoke through it, its Windows job importing under Windows PowerShell 5.1, every job behind the one switch'; Scope = 'system' }
        ModuleCommands = @{ File = 'Test-ModuleCommands.ps1'; Description = 'How an opt-in module contributes verbs (D-CM) -- off means absent, prefix is data, a collision refuses the module whole, a bad data file is skipped'; Scope = 'system' }
        Reminders   = @{ File = 'Test-Reminders.ps1'; Description = 'The Organize add-on -- the bucket and snooze rules over the shared table, both verbs typed in a fresh shell, the refusals, the bytes'; Scope = 'system' }
        Rituals     = @{ File = 'Test-Rituals.ps1'; Description = 'Team Agile''s standup -- the slot rule over the shared table, the golden texts byte for byte, no fakeWork in the real register, off means no verb, and Standup typed in a fresh shell with gh stubbed'; Scope = 'system' }
        StandupRemind = @{ File = 'Test-StandupRemind.ps1'; Description = 'Team Agile''s reminder to attend -- the cadence rule over the shared table; Standup -Remind writes ONE Organize reminder and a second rewrites it; attending archives today''s and writes the next working day''s through Organize''s verbs, once a day; organize off is a stated refusal; the switch in three places'; Scope = 'system' }
        Triage      = @{ File = 'Test-Triage.ps1'; Description = 'Team Agile''s triage -- the grouping rule over the shared table, the golden texts byte for byte, who has each issue and a card''s **Assigned:** line by the shared table, off means no Triage and no Route, Triage typed with gh stubbed, and Route''s exact gh argv per switch (-Assign me among them), -Assign on a card, -WhatIf writing nothing, and every refusal exit 2 with no write'; Scope = 'system' }
        StartWork   = @{ File = 'Test-StartWork.ps1'; Description = 'Team Agile''s hand-off block -- StartWork typed in a fresh shell: off means no verb, the block byte for byte against Tests/fixtures/start-work/ (a CRLF card gives the same block), the Space''s how-we-work.md switching section one''s heading, an issue no card carries read through gh (stubbed), -Prompt, and every refusal exit 2 with nothing written -- no row for the kind, a missing prompt file, an archived card, a closed issue, a pull request, an Azure DevOps Space, a partial name for a non-interactive caller'; Scope = 'system' }
        Review      = @{ File = 'Test-GenerateReview.ps1'; Description = 'Generate-Review.ps1 against a scratch hub -- bare-date regression, scaffold sections, multi-org slug sets, edge cases'; Scope = 'system' }
        SendTeams   = @{ File = 'Test-SendTeams.ps1'; Description = 'SendTeams (communication module) -- gate 2 names the missing env var, -WhatIf posts nothing, -AsJson shape'; Scope = 'system' }
        NewMeeting  = @{ File = 'Test-NewMeeting.ps1'; Description = 'NewMeeting (communication module) -- scaffolds a session from the template into manager/current/'; Scope = 'system' }
        MeetingAgenda = @{ File = 'Test-MeetingAgenda.ps1'; Description = 'MeetingAgenda (communication module) -- Plan/Prep/Retro stage driver over the session file'; Scope = 'system' }
        DocCounts   = @{ File = 'Test-DocCounts.ps1'; Description = 'The suite count this table produces agrees with what AGENTS.md, docs/TESTING.md and VERIFY.md each say it is -- the drift a cold start used to find by hand'; Scope = 'system' }
    }
}

<#
.SYNOPSIS
    What one suite's run counts for -- the runner's reading of a child's output
    and exit code, in one place so the runner's own self-test can hold it.
.DESCRIPTION
    A suite reports its score as `Results: n/m passed`. Once, a suite that
    threw BEFORE that line -- a bad path, a helper missing after a refactor, a
    write into a folder a `finally` had already removed -- contributed 0/0, and
    the run's Total read green: worse than a skip, because nothing in the
    summary said the suite had not run.

    The rule, one row per shape:
      - no Results line                     -> FAIL, counted as ONE failure,
                                               "no Results line -- the suite threw?"
      - a Results line, non-zero exit       -> FAIL, at least one failure (a suite
                                               that printed n/n and then exited 1
                                               did not pass)
      - Results: 0/0, exit 0                -> WARN, a stated skip (a suite that
                                               cannot run here says so AND prints
                                               its 0/0, as Test-Update does
                                               without git)
      - otherwise                           -> PASS if nothing failed, else FAIL
#>
function Get-P20SuiteVerdict {
    param([string]$Output, [int]$ExitCode)
    # The score is a LINE of its own, and the LAST one. A suite whose assertions quote a
    # Results line in their labels (Test-DocCounts prints "PASS  verdict: 'Results: 12/12
    # passed' ...") was scored by that quote: 12 where it had run 19.
    $all = [regex]::Matches([string]$Output, '(?m)^(?:\x1b\[[0-9;]*m|\s)*Results:\s*(\d+)/(\d+)\s+passed')
    $m = if ($all.Count -gt 0) { $all[$all.Count - 1] } else { [regex]::Match('', 'x') }
    if (-not $m.Success) {
        $why = if ($ExitCode -ne 0) { "no Results line -- the suite threw? (exit $ExitCode)" } else { 'no Results line -- the suite threw?' }
        return @{ Passed = 0; Failed = 1; Status = 'FAIL'; Detail = $why }
    }
    $passed = [int]$m.Groups[1].Value
    $failed = [int]$m.Groups[2].Value - $passed
    if ($ExitCode -ne 0) {
        if ($failed -lt 1) { $failed = 1 }
        return @{ Passed = $passed; Failed = $failed; Status = 'FAIL'; Detail = "exit code $ExitCode" }
    }
    if (($passed + $failed) -eq 0) {
        return @{ Passed = 0; Failed = 0; Status = 'WARN'; Detail = 'Results: 0/0 -- a stated skip' }
    }
    $status = if ($failed -gt 0) { 'FAIL' } else { 'PASS' }
    return @{ Passed = $passed; Failed = $failed; Status = $status; Detail = '' }
}
