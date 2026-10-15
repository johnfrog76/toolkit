# Bug 9: The shopping list double-counts an ingredient used twice

## Branch
you/9-the-shopping-list-double-counts-an-ingredient-used-twice

## Git
Commits:
- 4e1b9fa merge shopping-list lines by ingredient and unit
- 0d6a3c2 convert before merging when the units differ

## Summary
Two recipes on the plan that both use onions put onions on the list twice, as two lines. Lines now merge by ingredient and unit, converting first where the units differ. Waiting on a second pair of eyes -- the card is in the third lane by its `Review` line, not by a pull request.

## Acceptance Criteria
- [x] Two recipes with onions give one onion line
- [x] 200 g and 1 cup of flour merge into one line, in grams

---

**Sprint:** v0.2 -- Plan the week
**Story Points:** 3
**ADO Link:** https://github.com/johnfrog76/recipe-box-demo/issues/9
**Cover:** ../assets/9/cover.webp
**Created:** 2026-09-18
**Started:** 2026-09-21
**Review:** 2026-09-25
