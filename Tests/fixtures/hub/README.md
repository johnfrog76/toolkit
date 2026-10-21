# Fixture hub

A two-file prompt store, used by the Python agent tests and the web smoke test.
It is a *hub*, not a repository: there is no toolkit inside it and no `.git`,
which is exactly the arrangement `promptsRoot` exists to support.

- `test/current/Task401-...` -- an **Active** card (no commits, no PR URL)
- `test/current/402-...` -- a **Code Review** card (has `PR URL:`)
- `test/backlog/Task403-...` -- a **Backlog** card: planned, not in play, so `/api/status` serves it with
  status `Backlog` and the board draws it in its first lane (`web/tests/smoke.mjs`). It is in no
  reader that means "in play" -- the health count, the standup, Daily

`test` is the `promptsFolder` of the `test` org in `config.default.json`. The
names, ids and URLs here are placeholders and belong to nobody.

`hub.json` is here so the manifest path is exercised by every run that points
`promptsRoot` at this hub. It re-declares the same `test` org the committed
config already ships and the folder names the modules already read, so it is a
deliberate no-op: if adding it changes an answer, the merge is wrong. It omits
`status` on purpose -- `test_growth.py` and `test_manager.py` declare this slug
as `local`, and a hub-declared `active` would put them on the `az` probe.

`reminders/current/` holds three reminders for the Organize add-on's route (`Tests/test_reminders.py`)
-- one due at a time, one due on a date, one with no due date -- plus `notes.md`, which has no id in its
name and so is not a reminder. There is deliberately no `reminders/archive/`: a hub without one must
still serve the route.

