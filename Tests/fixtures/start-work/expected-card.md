# Start work: Task 23A3 -- Route the remaining raw git calls

## How we work in Widgets (hub.json: spaces[widgets].howIWork = agents)
You work with agents here: the repository's GitHub issues are the backlog, a worker label on an issue (its size) says which agent takes it, and the item below is the record -- write what you find, what you decide and each commit into it as you go.

## The work: Task 23A3 (widgets/current/Task23A3-route-the-remaining-raw-git-calls.prompt.md)
# Task 23A3: Route the remaining raw git calls

> Template: [Task.template.md](../../../toolkit/templates/Task.template.md)

## Branch
johnwebster/23A3-route-the-remaining-raw-git-calls

## Git
Commits:
- 80e2168 Route Sync-Prompts' status read through Invoke-P20TrackerRead
- `abcdef1234` Name the two passthrough lines in the allow-list

PR URL: https://github.com/acme/widgets/pull/57

## Summary
Two scripts still call git with a raw `2>&1`, which Windows PowerShell 5.1 turns into a throw under Stop.

## Acceptance Criteria
- [ ] No raw git call outside the allow-list.

---

**Sprint:** Phase 6: the long milestone title that is longer than twenty characters
**Story Points:** 2
**ADO Link:** https://github.com/acme/widgets/issues/23
**Started:** 2026-10-14
**Created:** 2026-10-12

## The prompt (agentic/build.prompt.md)
