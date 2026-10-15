# Importing a recipe from a URL

RecipeBox can turn a web page into a draft recipe. This page says how it behaves, so a cook, a tester and the
next developer all read the same thing.

## How to use it

1. Open **Recipes** and choose **Import**.
2. Paste the address of a page that holds a recipe and press **Fetch**.
3. A draft opens with the title, the ingredients with their quantities, the steps and the address it came
   from. Correct anything that is wrong.
4. Press **Save**. Until you do, nothing has been added to your recipes.

## What it reads

Most recipe pages describe their recipe in a machine-readable block alongside the visible page. RecipeBox
reads that block. It does not try to understand the page's prose, which is why an import is either right or
says it found nothing, and never half-invented.

| You paste | You get |
|---|---|
| A page with a recipe block | A draft with title, quantities, steps and source |
| A page without one | `No recipe found on that page.` and nothing created |
| An address that does not answer | `That address did not answer.` and nothing created |
| Something that is not a web address | `That is not a web address.` and nothing created |

## Quantities

Quantities are kept as the page wrote them (`1 1/2 cups`). They are not turned into decimals on the way in,
so nothing is lost to rounding before you have seen it.

## The source address

The address is saved with the recipe and shown as a link on its page, so a recipe always says where it came
from.

## Known limits

- A page that hides its recipe behind a login cannot be read.
- Pages that describe the recipe only in prose import as "no recipe found". Use **New recipe** for those.
