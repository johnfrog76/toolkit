# Test counts

The counts a full run printed, as of version **1.9.0**: the CLI per suite and in total, the
agent's `pytest` and the web UI's `npm test`. `Scripts/Write-TestCounts.ps1` writes this page in the
release pull request, from a full `tkTest` run, and it changes only with the version: between
releases `main` moves on and these figures stay where the last release left them. No other document
states them. [Testing](TESTING.md), "The counts", says how they are written.

```text
Consts 269, Compat 1951, Menu 2239, Environment 86, Archive 217, PRComments 284, BackfillStamps 50, Changelog 90, Update 68, Start 88, PullRequest 10, CloseWorkItem 51, PromptStatus 125, ThreadHash 86, Setup 82, Move 51, Billable 46, Plan 117, Tag 34, Backlog 57, Cover 106, Design 270, NewPrompt 159, ExitCodes 133, Autoload 86, GitRoot 17, Sync 86, Connect 62, NewSpace 149, HowWeWork 42, EditItem 69, Land 139, Burn 198, PublishPR 39, Config 424, HubJson 186, Portability 289, Web 203, Agent 129, TestAll 383, ModuleCommands 88, Reminders 71, Rituals 1535, StandupRemind 85, Triage 266, StartWork 87, OrgChart 530, Review 82, WorkReview 36, SendTeams 56, NewMeeting 63, MeetingAgenda 178, DocCounts 197
53 suites, 12444 assertions
pytest: 1730 passed, 6 skipped
web: 202 suites, 2652 tests
```
