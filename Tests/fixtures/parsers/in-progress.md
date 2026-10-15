# Bug 60: Token refresh races with sign-in flow

## Branch
youruser/60-token-refresh-race

## Git
Commits:
- `abc1234` initial fix
- `def5678` follow-up retry path
- (pending)

## Acceptance Criteria
- [x] Refresh guarded by lock
- [x] Retry on transient network error
- [ ] Telemetry counter added
- [ ] Doc updated

---

**Sprint:** Search Coach\Sprint 4
**Story Points:** 2
**ADO Link:** https://dev.azure.com/YOUR-ADO-ORG/YourProject/_workitems/edit/60
