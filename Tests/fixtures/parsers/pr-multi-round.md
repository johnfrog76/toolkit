# Bug 62: Carousel pause control missing

## Branch
youruser/62-carousel-pause

## Git
Commits:
- `1111aaa` initial fix
- `2222bbb` round 2 follow-up

## Acceptance Criteria
- [x] Pause button rendered
- [x] Pause toggles autoplay
- [x] Tested with keyboard only

## PR Review Comments (PR 140123)
PR: Add carousel pause control
Round: 1

PR URL: https://dev.azure.com/YOUR-ADO-ORG/YourProject/_git/your-repo/pullrequest/140123

### Comment 1 (Thread 5000001)
Line: `/src/Carousel.tsx` L10
Reviewer/Bot: bot -- Severity: Medium -- Category: A11y
Status: fixed
Comment: Missing aria-label.
Decision: take
Reply: Fixed in 1111aaa.

## PR Review Comments -- Round 2 (PR 140123)
PR: Add carousel pause control
Round: 2

### Comment 2 (Thread 5000002)
Line: `/src/Carousel.tsx` L18
Reviewer/Bot: bot -- Severity: Low -- Category: Style
Status: active
Comment: Use const.
Decision:
Reply:

---

**Sprint:** Demo Sprint 1
**Story Points:** 2
**ADO Link:** https://dev.azure.com/YOUR-ADO-ORG/YourProject/_workitems/edit/62
