<#
    The Organize add-on's contribution to the CLI surface (build-plan D-CM).

    Organize is where the things a person keeps in order live. Reminders is its
    FIRST surface, not its definition -- a later planning surface joins it under
    the same flag, so the key a machine has written (features.organize) never
    has to be renamed. Both halves or neither: the flag gives the verbs AND the
    web tab, and there is no web-only or CLI-only mode.

    Two verbs carrying switches, MeetingAgenda's shape, rather than four nouns.
    The data is the hub's reminders/ folder, named for the data and not the
    module; nothing here reads another module's folder.

    Commands is a PLAIN hashtable: Import-PowerShellDataFile, the only reader
    the loader uses, refuses a type cast such as [ordered].
#>
@{
    Feature  = 'organize'

    Commands = @{
        'NewReminder' = 'New-P20Reminder'
        'Reminders'   = 'Get-P20Reminders'
    }
    Order = @('Reminders', 'NewReminder')

    Help     = @{
        'Reminders' = @{
            category    = 'organize'
            description = 'List, snooze, edit or archive your reminders'
            notes       = @(
                'No id: every open reminder grouped overdue / today / upcoming, worked out against the local clock each time -- never stored. -All adds the archived.',
                '<id> -Snooze 1h|tomorrow|nextweek rewrites the due time and nothing else: 1h is from now, tomorrow and nextweek mean 09:00 (nextweek is the next Monday).',
                '<id> -Archive moves the reminder to reminders/archive/ and stamps **Closed:**. Archive is the card verb and cannot see this folder.',
                '<id> -Due <when> | -NoDue | -Title <text> | -Source <tag> | -Ref <ref> corrects the entry: each rewrites its own line and nothing else, together or alone. -Due takes what NewReminder -Due takes; an empty -Ref removes the ref. The filename keeps its slug -- the id is the identity.'
            )
            usage       = '{cliPrefix}Reminders [<id>] [-Snooze 1h|tomorrow|nextweek] [-Archive] [-Due <when>] [-NoDue] [-Title <text>] [-Source <tag>] [-Ref <ref>] [-All] [-Help]'
            examples    = @(
                '{cliPrefix}Reminders',
                '{cliPrefix}Reminders K7M2 -Snooze tomorrow',
                '{cliPrefix}Reminders K7M2 -Due 2026-10-01T14:00 -Title "Review sprint goals"',
                '{cliPrefix}Reminders K7M2 -Archive'
            )
        }
        'NewReminder' = @{
            category    = 'organize'
            description = 'Add a reminder for yourself'
            notes       = @(
                '-Due takes YYYY-MM-DD (due by the end of that day), YYYY-MM-DDTHH:MM, or 1h / tomorrow / nextweek. Local time, no zone.',
                '-Source is a tag saying where it came from (default manual); -Ref a pointer in that source. Shown, never followed.',
                'Writes reminders/current/<ID>-<slug>.md in the hub with a fresh short id. Never overwrites.'
            )
            usage       = '{cliPrefix}NewReminder -Title <text> [-Due <when>] [-Source <tag>] [-Ref <ref>] [-Help]'
            examples    = @(
                '{cliPrefix}NewReminder -Title "Review sprint goals" -Due 2026-09-24T14:00',
                '{cliPrefix}NewReminder -Title "Book the training" -Due tomorrow -Source goal'
            )
        }
    }
}
