# Bug 205: Quantities lose precision on save

## Branch
you/205-quantities-lose-precision-on-save

## Git
Commits:
- b93a0c4 store quantities as rationals, not floats
- 2ac81f7 migrate existing rows

## Summary
A third of a cup came back as 0.33, and three of them no longer made one.

## Acceptance Criteria
- [x] 1/3 cup saves and loads as 1/3 cup
- [x] Existing recipes are migrated

---

**Sprint:** RecipeBox\Sprint 7
**Story Points:** 3
**Created:** 2026-09-01
**Closed:** 2026-09-10
