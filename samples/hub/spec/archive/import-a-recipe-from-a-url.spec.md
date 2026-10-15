---
id: ccb832ef-d369-45e8-a7cb-626791c06a84
description: "Paste a link to a recipe page and get a draft recipe back"
---

# Import a recipe from a URL (spec)

> Docs: docs/importing-a-recipe-from-a-url.md

Version 1.0 -- built. The durable part of this spec is
[Importing a recipe from a URL](../../docs/importing-a-recipe-from-a-url.md); the spec stays as the record of
what was decided.

## 1. Problem

Most recipes a cook wants already live on a web page, and retyping one is the reason people stop keeping
their recipes in the app. The note this came from is `design/archive/import-a-recipe-from-a-url.md`.

## 2. Principles

1. The cook confirms a draft; nothing an import found is saved without being seen.
2. A page with no recipe in it is said so plainly, never filled in from guesswork.
3. The address the recipe came from is kept with it.

## 3. The contract

- An **Import** button on the recipes page takes a web address.
- The page is fetched, the recipe is read from the machine-readable block most recipe pages carry, and the
  result opens as a draft recipe: title, ingredients with quantities, steps, source address.
- A page with no such block, an address that does not answer, and an address that is not a web address each
  end in one sentence saying which.

## 4. Decisions

| # | Decision | By |
|---|---|---|
| D-1 | Read the page's own recipe block; do not try to scrape free text | the author |
| D-2 | The draft is never saved by the import itself | the author |
| D-3 | Keep the source address on the recipe | the author |

## 5. Milestones

1. Fetch and read the recipe block.
2. The draft screen and its confirmation.
3. The refusals.

## 6. Acceptance

- Importing a page with a recipe block opens a draft with its title, quantities and steps.
- Importing a page without one shows `No recipe found on that page.` and creates nothing.
- Saving the draft keeps the address as the recipe's source.

## 7. Open items

None at the time of completion.

## 8. Traps, known before starting

- Quantities arrive as text (`1 1/2 cups`); precision is lost if they are parsed as floats on the way in
  (see the archived bug about quantities losing precision on save).
**Closed:** 2026-10-07
