# Bug 5: Search returns duplicates when tags overlap

## Branch
you/5-search-returns-duplicates-when-tags-overlap

## Git
Commits:
- c7d20e4 reproduce with a recipe tagged vegan and vegetarian

## Summary
Searching by tag joins recipes to tags and returns one row per MATCH, so a recipe carrying two of the searched tags comes back twice. The count in the header is wrong for the same reason. The issue is pinned on GitHub, so the Board sorts this card first in its lane once the Space is connected.

## Acceptance Criteria
- [x] A recipe with two matching tags appears once
- [ ] Result counts match the number of distinct recipes
- [ ] A test covers the overlapping-tag case

---

**Sprint:** v0.2 -- Plan the week
**Story Points:** 2
**ADO Link:** https://github.com/johnfrog76/recipe-box-demo/issues/5
**Cover:** ../assets/5/cover.webp
**Created:** 2026-09-22
