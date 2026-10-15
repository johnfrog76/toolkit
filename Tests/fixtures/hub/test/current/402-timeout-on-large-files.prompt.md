# Bug 402: Upload times out on files over 50 MB

## Branch
user/402-timeout-on-large-files

## Git
Commits:
- 4f1c9ab raise the upload timeout and stream the body
- 9d20e73 cover the streaming path with a test

## Acceptance Criteria
- [x] Files over 50 MB upload without timing out
- [x] The body is streamed rather than buffered
- [ ] The timeout is read from config

PR URL: https://dev.azure.com/YOUR-ADO-ORG/YourProject/_git/your-repo/pullrequest/4021

---

**Sprint:** Example Project\Sprint 3
**Story Points:** 3
**ADO Link:** https://dev.azure.com/YOUR-ADO-ORG/YourProject/_workitems/edit/402

## PR Review Comments (PR 4021)

### Comment 1
- **Thread:** 90001
- **File:** /src/upload/client.ts
- **Line:** 42
- **Reviewer:** PR Assistant (AI Code Review)
- **Severity:** Medium
- **Category:** Reliability
- **Status:** active

**Comment:**
The retry loop swallows the last exception -- re-raise it so the caller sees why the upload failed.

**Decision:** take / reject / modify
**Reply:**
