# User Story 198: Import a recipe from a URL

## Branch
you/198-import-a-recipe-from-a-url

## Git
Commits:
- 1d4e7aa parse schema.org Recipe JSON-LD
- 5f20b61 fall back to microdata
- e07c3b2 show what could not be read instead of guessing

## Summary
Most recipe sites publish schema.org markup. Read that; never scrape prose.

## Acceptance Criteria
- [x] A page with Recipe JSON-LD imports title, ingredients and steps
- [x] A page without it says what is missing
- [x] Nothing is saved until the cook confirms

---

**Sprint:** RecipeBox\Sprint 7
**Story Points:** 8
**Created:** 2026-08-24
**Closed:** 2026-09-05
