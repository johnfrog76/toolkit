# Test counts

The counts a full run printed, as of version **1.7.0**: the CLI per suite and in total, the
agent's `pytest` and the web UI's `npm test`. `Scripts/Write-TestCounts.ps1` writes this page in the
release pull request, from a full `tkTest` run, and it changes only with the version: between
releases `main` moves on and these figures stay where the last release left them. No other document
states them. [Testing](TESTING.md), "The counts", says how they are written.

```text
Consts 260, Compat 1938, Menu 2217, Environment 86, Archive 217, PRComments 284, BackfillStamps 50, Changelog 90, Update 68, Start 88, PullRequest 10, CloseWorkItem 51, PromptStatus 125, ThreadHash 86, Setup 82, Move 51, Billable 46, Plan 114, Tag 34, Backlog 56, Cover 106, Design 270, NewPrompt 159, ExitCodes 133, Autoload 86, GitRoot 17, Sync 86, Connect 62, NewSpace 149, HowWeWork 42, EditItem 69, Land 139, Burn 198, PublishPR 39, Config 402, HubJson 186, Portability 289, Web 183, Agent 129, TestAll 382, ModuleCommands 88, Reminders 71, Rituals 1505, StandupRemind 85, Triage 266, StartWork 87, OrgChart 195, Review 82, WorkReview 36, SendTeams 56, NewMeeting 63, MeetingAgenda 178, DocCounts 195
53 suites, 11986 assertions
pytest: 1653 passed, 6 skipped
web: 194 suites, 2465 tests
```
