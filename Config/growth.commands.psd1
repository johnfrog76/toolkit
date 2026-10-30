#
# The growth module's contribution to the CLI's command table (build-plan D-CM).
#
# Read by the loader in utilities.psm1 BEFORE Register-PromptAlias runs, and
# only when features.growth is true at the top level. Off means absent: no row,
# no alias, no menu line, no help.
#
# Three keys, and all three are load-bearing:
#
#   Feature   the TOP-LEVEL features key that switches this module on. Growth
#             data spans engagements -- a training you took does not stop having
#             happened when you switch org -- so this flag is the engineer's and
#             must never be set inside an orgs[] entry.
#   Commands  CommandMap rows, name -> function. A PLAIN hashtable: this file is
#             read with Import-PowerShellDataFile, which will not evaluate an
#             expression -- including an [ordered] cast -- to build one. That is
#             the point. A file any module can drop into Config/ must not be
#             able to run code when the CLI starts.
#   Order     optional, and the one thing the cast would have bought: the order
#             these appear in Menu. Names left out follow the listed ones.
#   Help      the shape of config.default.json's commands.<Name> entries, merged
#             into the in-memory table Show-CommandHelp reads. A module's help
#             lives with the module; config.default.json stays the core's.
#
# The prefix is data. Nothing here names it -- {cliPrefix} is expanded at render
# time, so the same entry reads correctly as tkNewGrowth or anything else.
#
@{
    Feature = 'growth'

    Commands = @{
        'NewGrowth'         = 'New-P20GrowthItem'
        'NewWorkReview'     = 'New-P20WorkReview'
        'PublishWorkReview' = 'Publish-P20WorkReview'
        'WorkReview'        = 'Set-P20WorkReview'
        'LogPeerReview'     = 'Write-P20PeerReviewLog'
        'UpdateResume'      = 'Update-P20Resume'
    }

    # The order the work happens in: create the artifact, generate the review,
    # publish it, put it away. LogPeerReview and UpdateResume are the two that
    # stand alone.
    Order = @(
        'NewGrowth'
        'NewWorkReview'
        'PublishWorkReview'
        'WorkReview'
        'LogPeerReview'
        'UpdateResume'
    )

    Help = @{
        'NewGrowth' = @{
            category    = 'growth'
            description = 'Create a training, presentation or goal'
            usage       = '{cliPrefix}NewGrowth -Title <t> [-Type training|presentation|goal] [-Date <YYYY-MM-DD>] [-DueDate <YYYY-MM-DD> (required for a training)] [-Provider <p>] [-Hours <h>] [-Notes <n>] | -Close <file> | -Complete <file> [-WhatIf] [-Help]'
            examples    = @(
                '{cliPrefix}NewGrowth -Title ''Intro to PowerShell'' -DueDate 2026-10-01 -Hours 2',
                '{cliPrefix}NewGrowth -Type presentation -Title ''Designing for Non-Determinism'' -Date 2026-09-15',
                '{cliPrefix}NewGrowth -Type goal -Title ''Improve test coverage patterns''',
                '{cliPrefix}NewGrowth -Complete goal-2026-improve-test-coverage-patterns -WhatIf',
                '{cliPrefix}NewGrowth -Close training-2026-09-01-clean-architecture'
            )
            notes       = @(
                '-Close archives an item: growth/current/<file> moves to growth/archive/ and is stamped **Closed:** -- the module closes its own data, since Archive is org-scoped and cannot see growth/.',
                '-Complete marks a goal complete: the **Status** line under its ## Outcome heading is written as Achieved, and nothing else in the file changes. A goal only; it stays in growth/current/ until -Close.',
                '-WhatIf names the file that would be written or moved, and writes nothing.'
            )
        }
        'NewWorkReview' = @{
            # It walks git log over the whole hub; the bridge's default 120 s is not enough for a year of it.
            bridgeTimeoutSeconds = 300
            category    = 'review'
            description = 'Generate a work review scaffold for a period'
            usage       = '{cliPrefix}NewWorkReview -StartDate <YYYY-MM-DD> -EndDate <YYYY-MM-DD> [-Slugs <csv>] [-Help]'
            examples    = @(
                '{cliPrefix}NewWorkReview -StartDate 2026-01-01 -EndDate 2026-04-18',
                '{cliPrefix}NewWorkReview -StartDate 2026-01-01 -EndDate 2026-04-18 -Slugs first,second'
            )
        }
        'PublishWorkReview' = @{
            category    = 'review'
            description = 'Commit the reviews folder and sync the hub'
            usage       = '{cliPrefix}PublishWorkReview [-NoPush] [-Preview] [-Help]'
            examples    = @(
                '{cliPrefix}PublishWorkReview',
                '{cliPrefix}PublishWorkReview -NoPush'
            )
        }
        'WorkReview' = @{
            category    = 'review'
            description = 'Archive or delete a work review'
            usage       = '{cliPrefix}WorkReview <slug-set>/<start>_<end> -Archive | -Delete [-WhatIf] [-Help]'
            examples    = @(
                '{cliPrefix}WorkReview first/2026-04-01_2026-04-30 -Archive',
                '{cliPrefix}WorkReview first+second/2026-01-01_2026-03-31 -Delete -WhatIf',
                '{cliPrefix}WorkReview archive/first/2026-04-01_2026-04-30 -Delete'
            )
            notes       = @(
                '-Archive moves reviews/<slug-set>/<year>/<start>_<end>/ to reviews/archive/<slug-set>/<year>/<start>_<end>/ and stamps **Closed:** into its review.md -- the file every review has; summary.md moves untouched.',
                '-Delete removes the folder and every file in it. Name an archived review with archive/ in front.',
                'With storeSync: git the move is committed, scoped to the review''s own paths; Sync pushes it. -WhatIf names the folder and writes nothing.'
            )
        }
        'LogPeerReview' = @{
            category    = 'pr'
            description = 'Log a peer review you did of someone''s PR'
            usage       = '{cliPrefix}LogPeerReview <PullRequestId> [-Title <t>] [-Notes <n>] [-Help]'
            examples    = @(
                '{cliPrefix}LogPeerReview 6789',
                '{cliPrefix}LogPeerReview 6789 -Title ''Auth refactor'' -Notes ''Approved with nits'''
            )
        }
        'UpdateResume' = @{
            category    = 'review'
            description = 'Commit resume changes and sync the hub'
            usage       = '{cliPrefix}UpdateResume [-NoPush] [-Preview] [-Help]'
            examples    = @(
                '{cliPrefix}UpdateResume',
                '{cliPrefix}UpdateResume -NoPush'
            )
        }
    }
}
