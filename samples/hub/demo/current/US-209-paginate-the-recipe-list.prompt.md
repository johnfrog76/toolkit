# User Story 209: Paginate the recipe list

## Branch
you/209-paginate-the-recipe-list

## Git
Commits:
- 7be0d13 add limit and cursor to GET /recipes
- c9a55f0 return nextCursor; cover the last page

## Summary
The list endpoint returns every recipe. At 2,000 recipes the first paint is four seconds. Cursor pagination, because offsets drift when someone adds a recipe while you scroll.

## Acceptance Criteria
- [x] GET /recipes takes limit and cursor
- [x] The last page returns no nextCursor
- [ ] The list view loads the next page on scroll
- [ ] An empty list says so instead of spinning

PR URL: https://dev.azure.com/YOUR-ADO-ORG/RecipeBox/_git/recipe-box/pullrequest/61

---

**Sprint:** RecipeBox\Sprint 8
**Story Points:** 5
**Cover:** ../assets/US-209/cover.webp
**Created:** 2026-09-08
