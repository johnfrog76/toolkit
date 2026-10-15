<#
    The communication module's contribution to the CLI surface.

    Three verbs -- SendTeams, NewMeeting, MeetingAgenda -- and the help text
    that makes each one answer -Help. The loader merges Commands into
    $script:CommandMap and Help into $script:Commands ONLY when the top-level,
    engineer-scoped features.communication is true. Off means absent: no alias,
    no row in Menu, no -Help, nothing for the bridge to call.

    Keys are what a caller types (and what POST /api/cmd/{name} sends); values
    are the function that gets invoked. The function, never a prefixed alias --
    the prefix is data and more than one can be registered at once.

    Commands is a PLAIN hashtable, because Import-PowerShellDataFile -- the only
    reader the loader uses, on purpose: a data file must not be able to run
    code -- refuses a type cast such as [ordered]. Order carries the sequence
    Menu shows and Register-PromptAlias registers.

    Help entries have exactly the shape config.default.json's commands.<Name>
    uses, because Show-CommandHelp reads one table and does not care which half
    of it a verb came from. {cliPrefix} is expanded at render time.
#>
@{
    Feature  = 'communication'

    Commands = @{
        'SendTeams'     = 'Send-P20TeamsMessage'
        'NewMeeting'    = 'New-P20Meeting'
        'MeetingAgenda' = 'Get-P20MeetingAgenda'
    }
    Order = @('SendTeams', 'NewMeeting', 'MeetingAgenda')

    Help     = @{
        'SendTeams' = @{
            category    = 'org'
            description = 'Post a one-line message to Teams'
            notes       = @('Through the communication engine: -WhatIf runs every gate and shows the payload unsent; -AsJson for the raw result.', '-Session <file> names the meeting record (manager/current/) this send is for: after an ok, "Sent to <recipient>: <date>" goes under its ## Sent, the line the web button writes.', 'The URL is TEAMS_WEBHOOK_<RECIPIENT> in .env in the package root (copy .env.example), or the catch-all TEAMS_WEBHOOK_URL. A recipient is declared first -- manager is; a channel needs "type": "channel" in config.local.json. The agent reads .env when it starts, so restart it ({cliPrefix}Web -Stop, {cliPrefix}Web -Dev) after a change. Getting the URL: docs/modules/communication.md, "Getting a webhook URL".')
            usage       = '{cliPrefix}SendTeams <recipient> <message> [-Session <file>] [-WhatIf] [-AsJson] [-Help]'
            examples    = @(
                "{cliPrefix}SendTeams manager 'Retro summary posted'",
                "{cliPrefix}SendTeams manager 'Heads up' -WhatIf",
                "{cliPrefix}SendTeams demo_channel 'Build is green'"
            )
        }
        'NewMeeting' = @{
            category    = 'org'
            description = 'Create a meeting record in the hub'
            notes       = @('From the ManagerSession template: the 1:1 by default, or another series with -Type; -Date for a day other than today.')
            usage       = '{cliPrefix}NewMeeting [-Date <YYYY-MM-DD>] [-Type <series>] [-Help]'
            examples    = @(
                '{cliPrefix}NewMeeting',
                '{cliPrefix}NewMeeting -Date 2026-06-12'
            )
        }
        'MeetingAgenda' = @{
            category    = 'org'
            description = 'Plan, prep, retro or close a meeting'
            notes       = @('No switch: every open meeting with its stage and next command. -Plan, -Prep, -Retro, -Close drive one through its stages; -Type names the series (default 1on1).')
            usage       = '{cliPrefix}MeetingAgenda [-Plan] [-Prep] [-Retro] [-Close] [-Date <YYYY-MM-DD>] [-Type <t>] [-Help]'
            examples    = @(
                '{cliPrefix}MeetingAgenda',
                '{cliPrefix}MeetingAgenda -Plan',
                '{cliPrefix}MeetingAgenda -Date 2026-06-12 -Retro',
                '{cliPrefix}MeetingAgenda -Date 2026-06-12 -Close'
            )
        }
    }
}
