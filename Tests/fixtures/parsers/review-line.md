# Spike 902: Can the export be done in one pass?

> A spike ends in a finding, not a pull request. "Look at this thing" is the
> `**Review:**` line, and the state rule reads it as Code Review exactly as it
> reads a `PR URL:` line -- and, like that line, it is checked BEFORE the
> commit bullet, so this card is Code Review and not In Progress (2026-09-22).
> Asserted from BOTH halves' suites.

## Git
Commits:
- a41c2e9 try it one way

## Findings
Yes, if the index is built first.

---

**Sprint:** YourProject\Sprint 1
**Review:** 2026-09-22
**Created:** 2026-09-20
