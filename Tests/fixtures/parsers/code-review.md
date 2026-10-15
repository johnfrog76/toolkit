# Bug 61: VoiceOver swipe skips search progress characters

## Branch
youruser/61-voiceover-swipe-progress

## Git
Commits:
- `9abcdef` accessibility fix

## Acceptance Criteria
- [x] Progress role announced
- [x] Tested with VoiceOver iOS
- [ ] Tested with NVDA on Windows

## PR Review Comments (PR 140123)
PR: Fix VoiceOver swipe on search progress characters
Context: Reviewers asked for an a11y pass before merge.
Round: 1

PR URL: https://dev.azure.com/YOUR-ADO-ORG/YourProject/_git/your-repo/pullrequest/140123

### Comment 1 (Thread 1342185)
Line: `/src/components/Foo.tsx` L23
Reviewer/Bot: PR Assistant (AI Code Review) -- Severity: High -- Category: Accessibility
Status: active
Comment: The component can return null while requiring an id...
Code suggestion:
```tsx
return <div id={id} role="progressbar" />;
```
Decision:
Reply:

### Comment 2 (Thread 1342186)
Line: `/src/components/Bar.tsx` L42
Reviewer/Bot: jane.reviewer@example.com -- Severity: Low -- Category: Style
Status: active
Comment: Could rename `x` to something descriptive.
Decision: take
Reply: Fixed in abc1234.

---

**Sprint:** Search Coach\Sprint 4
**Story Points:** 3
**ADO Link:** https://dev.azure.com/YOUR-ADO-ORG/YourProject/_workitems/edit/61
