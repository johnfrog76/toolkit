# Bug 214: Search returns duplicates when tags overlap

## Branch
you/214-search-returns-duplicates-when-tags-overlap

## Git
Commits:
- a41c2e9 reproduce with a recipe tagged vegan and vegetarian

## Summary
Searching by tag joins recipes to tags and returns one row per MATCH, so a recipe carrying two of the searched tags comes back twice. The count in the header is wrong for the same reason.

## Acceptance Criteria
- [x] A recipe with two matching tags appears once
- [ ] Result counts match the number of distinct recipes
- [ ] A test covers the overlapping-tag case

---

**Sprint:** RecipeBox\Sprint 8
**Story Points:** 2
**Cover:** ../assets/214/cover.webp
**Created:** 2026-09-14
