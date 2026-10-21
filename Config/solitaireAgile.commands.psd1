<#
    The Solitaire Agile add-on's contribution to the CLI surface (build-plan D-CM).

    Solitaire Agile is a team's own rituals with the real tracker as the board
    and a cast that is not people (docs/modules/solitaire-agile.md). M0 is
    the standup as text: the human's queue, then one block per worker label,
    filled from the Space's GitHub issues by the Ritual Engine. Both halves or
    neither: the flag gives this verb AND the agent's GET /api/ritual/standup
    and the web tab.

    Standup writes nothing -- not to the hub, not to the tracker. The ceremonies
    keep no state (D-TA2): every line is derived from what the tracker says now.

    V1 adds triage: Triage reads the open issues by milestone, and Route
    is the module's first WRITE -- each answer a real label or milestone on the
    tracker through gh, never anything in the hub.

    AR-1 (the agent in the room) adds StartWork: the hand-off block, one
    read of three files that already exist -- how we work in the Space, the
    card or issue, the kind's agentic prompt -- printed for a cold agent.
    It writes nothing; the web's copy box runs it through the bridge.

    Commands is a PLAIN hashtable: Import-PowerShellDataFile, the only reader
    the loader uses, refuses a type cast such as [ordered].
#>
@{
    Feature  = 'solitaireAgile'

    Commands = @{
        'Standup' = 'Get-P20Standup'
        'Triage'  = 'Get-P20Triage'
        'Route'   = 'Set-P20Route'
        'StartWork' = 'Get-P20StartWork'
    }
    Order = @('Standup', 'Triage', 'Route', 'StartWork')

    Help     = @{
        'Standup' = @{
            category    = 'rituals'
            description = 'Today''s standup, filled from the tracker'
            notes       = @(
                'The queue first -- every open issue labelled verify-close is yours to walk -- then one block per worker: a label whose description starts "Routed to <Name> -- ...". Yesterday is what closed since the previous working day began, Today what is open, Blockers what is open and waiting on you.',
                'A worker with nothing in flight shows the mug and reports it (the vocabulary''s `nothing` family); the chair''s lines come from the phrasebook. Neither claims any work (Config/standup-vocabulary.json).',
                'GitHub Spaces only. With no tracker -- an Azure DevOps or local Space, gh missing or not answering -- the standup still happens, and its Tracker line says why the slots are empty.',
                '-Space reads a declared Space other than the one you are in. -AsJson prints the response the agent''s GET /api/ritual/standup serves, text included. Nothing is written to the tracker.',
                '-Brief prints only the chair''s reading, a few lines and no model: what waits on you by kind, each worker as closed / open / in flight / blockers, and the one thing next. -AsJson carries it as brief. Reading is not attending, so -Brief does not re-arm the reminder.',
                '-Remind <HH:mm> [-Days ...] sets the reminder to attend: ONE Organize reminder, source standup, its cadence (time and days, Monday to Friday unless -Days says otherwise) on its own Ref line, due the next time in the cadence. A second -Remind rewrites it rather than adding one. Needs features.organize.',
                '-Walk prints only the walk list, by issue number: each verify-close issue and, under it, the VERIFY.md Gate 12 row that names it (or "no VERIFY row -- close on the issue''s own words"). The PC''s morning as one printout; -AsJson carries walk[] of number, title, url, verifyRow. It is a read, not attending (it does not re-arm the reminder), and it does not go with -Remind.',
                '-Grain detail|work|brief picks the register of detail: detail is the text above, every item and its number; work is the ritual''s grain, each worker''s items grouped by milestone, else the design card the issue names, else the titles'' common stem, spoken as standup prose, one sentence a group, no model ("Opus: Yesterday I closed two in Team Agile (#<n>, #<n>). Nothing blocked."); brief is -Brief''s reading. The played view speaks the work grain. -AsJson carries all three (text, work, brief).',
                'Each item says what moved, after its number: closed (yesterday''s), started or in progress (today''s and the blockers'') -- started is a card whose **Started:** day, else its **Created:** day, is in the window; an issue with no card says closed or in progress -- and its card''s commits ("#143 (closed, 2 commits) Rename the slug"). The brief opens on the counts line: what moved since the window began, closed, started, in progress and commits, a hash counted once however many cards thread it; each worker''s brief line adds its own.',
                '-Since <yyyy-MM-dd> widens yesterday back to that day: every issue closed and every card archived since then is said, and the counts sum the window. Today and the blockers are what is open now. The default is the previous working day. Not -Days, which is the reminder''s cadence; a day that is not one, or is after today, is a stated refusal, and it does not go with -Remind.',
                'Attending re-arms it: Standup (or the Team Agile page) archives the open standup reminder and writes the next day''s in the cadence, once a day, through Organize''s own verbs. To stop it, archive it in Organize.'
            )
            usage       = '{cliPrefix}Standup [-Space <slug>] [-AsJson] [-Brief] [-Grain <detail|work|brief>] [-Since <yyyy-MM-dd>] [-Remind <HH:mm>] [-Days <Mon,Tue,...>] [-Walk] [-Help]'
            examples    = @(
                '{cliPrefix}Standup',
                '{cliPrefix}Standup -Space toolkit',
                '{cliPrefix}Standup -AsJson',
                '{cliPrefix}Standup -Walk',
                '{cliPrefix}Standup -Brief',
                '{cliPrefix}Standup -Grain work',
                '{cliPrefix}Standup -Since 2026-10-12 -Brief',
                '{cliPrefix}Standup -Remind 09:00',
                '{cliPrefix}Standup -Remind 17:30 -Days Mon,Wed,Fri'
            )
        }
        'Triage' = @{
            category    = 'rituals'
            description = 'The open issues by milestone, unplaced first'
            notes       = @(
                'The issues in no milestone first, because nobody has placed them; then each milestone, most open first, with its context line: N open, M routed, K unrouted -- routed meaning someone has it.',
                'Each issue is one line: its number and title, then who has it -- me (assigned to you), @<login> (assigned to someone else), its worker (the size -- the worker label IS the size), or nobody -- its severity label, -- where it has none, and the deep-water mark.',
                'GitHub Spaces only. An Azure DevOps or local Space, or gh not answering, prints a Tracker line saying why and exits 0. -AsJson prints what the agent''s GET /api/ritual/triage serves. Nothing is written; Route answers.'
            )
            usage       = '{cliPrefix}Triage [-Space <slug>] [-AsJson] [-Help]'
            examples    = @(
                '{cliPrefix}Triage',
                '{cliPrefix}Triage -Space toolkit -AsJson'
            )
        }
        'Route' = @{
            category    = 'rituals'
            description = 'Answer triage''s questions, or say who takes it'
            notes       = @(
                'One gh write per switch on the Space''s repo: -Size adds that worker label and removes the other sizes; -Assign me makes you the assignee (gh issue edit --add-assignee @me), and -Assign <size> is the -Size write; -Milestone sets an OPEN milestone by title; -Severity adds that label and removes the other two; -DeepWater adds deep-water.',
                'A size is a worker label on the repo (sonnet, opus, fable here; fable is the owner''s own seat). Deep water gets two moves -- assign Fable or split -- and Route prints them; it makes neither.',
                'On a card -- an id of its own (K7M2), or any card in a Space with no tracker or a local one -- -Assign me or -Assign <size> writes one **Assigned:** line in the card''s footer and nothing else. A card''s sizes are the repo''s worker labels on a connected GitHub Space; with no connected repository there are no labels to read, so a card there takes -Assign me alone.',
                'Refused, with nothing written: no number, no switch, an unknown severity, size or milestone (the hint lists the known ones), -Assign and -Size that disagree, an undeclared -Space, a Space that is not GitHub (an Azure DevOps Space refuses -Assign too), a card given any switch but -Assign. -WhatIf prints every write and makes none. Nothing is written to the hub but a card''s **Assigned:** line.'
            )
            usage       = '{cliPrefix}Route <n|id> [-Size <label>] [-Assign <me|size>] [-Milestone <title>] [-Severity <sev>] [-DeepWater] [-Space <slug>] [-WhatIf] [-Help]'
            examples    = @(
                '{cliPrefix}Route 132 -Size opus -Severity sev3',
                '{cliPrefix}Route 132 -Milestone "Team Agile V1" -WhatIf',
                '{cliPrefix}Route 140 -DeepWater',
                '{cliPrefix}Route 4 -Assign me -WhatIf',
                '{cliPrefix}Route K7M2 -Assign sonnet'
            )
        }
        'StartWork' = @{
            category    = 'rituals'
            description = 'One block a cold agent can start the work from'
            notes       = @(
                'Prints one markdown block and nothing else: how we work in this Space, the card (or the issue) and its prompt, each under a heading that names the file it came from. Pipe it to the clipboard or a file, or paste it into a fresh editor chat.',
                'How we work is the Space''s how-we-work.md when it has one, else one sentence derived from spaces[].howIWork. The card goes in whole, as written -- its commits, PR URL: and footer lines with it. A number no card in current/ carries is the Space''s GitHub issue of that number: its title, labels, milestone and body.',
                'The prompt is the kind''s row in startWork.prompts (Config -Set startWork.prompts.<kind>=<path>); -Prompt <path> carries another one for this call. A kind with no row, or a row whose file is missing, is refused naming the key.',
                'Refused, with nothing written: no id, an id that matches nothing (an id is never a partial name), an archived card or a closed issue, an Azure DevOps Space, a partial name from the bridge, an undeclared -Space. -Clip puts the block on the clipboard and says so in one line.'
            )
            usage       = '{cliPrefix}StartWork <id> [-Clip] [-Prompt <path>] [-Space <slug>] [-Help]'
            examples    = @(
                '{cliPrefix}StartWork 23A3',
                '{cliPrefix}StartWork 23A3 -Clip',
                '{cliPrefix}StartWork 4 -Prompt agentic/new-issue.prompt.md'
            )
        }
    }
}
