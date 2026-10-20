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
