---
id: 4c9c2aee-fced-4114-8cb2-e3a8582251c0
description: "Change the servings and every quantity follows, rounded the way a cook measures"
---

# Scale a recipe by servings (spec)

Version 0.2 -- draft, not locked. A spec is a draft until its owner locks it; a locked spec changes by a
dated note at this head.

## 1. Problem

A recipe is written for one number of servings and cooked for another. Scaling by hand mid-recipe is error
prone, and a calculator's answer (1.4999 cups) cannot be measured. The note this came from is
`design/scale-a-recipe-by-servings.md`.

## 2. Principles

1. A scaled quantity is one a cook can measure: halves, quarters and thirds of a unit, never a long decimal.
2. An amount that is not a number is not touched: "a pinch" stays "a pinch".
3. Scaling is arithmetic on a copy. The recipe as written is never changed by looking at it for six.

## 3. The contract

- A servings control on the recipe page: a number, starting at the recipe's own.
- Changing it rescales every ingredient quantity from the recipe's original amounts, not from the last
  scaled value, so going from 4 to 6 and back to 4 shows exactly what was written.
- Rounding goes through the unit conversion module (Task 211), the one place that knows what a cup divides
  into. Scaling does not carry its own copy.
- A servings value of zero, or one that is not a whole number of at least 1, is refused where it is typed,
  with a sentence, and the quantities stay as they were.

## 4. Decisions

| # | Decision | By |
|---|---|---|
| D-1 | Round to halves, quarters and thirds. Eighths read as noise on a measuring cup | the cook's test: would you measure it |
| D-2 | Scale from the original amounts every time, so rounding never compounds | the author |
| D-3 | Cooking time is not scaled; the page says it does not know | the author |

## 5. Milestones

1. The unit conversion module exposes `roundForCooking` (Task 211).
2. The servings control, with the rescaled list.
3. The refusals, and the "a pinch" rule.

## 6. Acceptance

- A recipe for 4 with `1 cup flour`, scaled to 6, shows `1 1/2 cups flour`.
- Scaled to 3 and back to 4, it shows `1 cup flour` again.
- `a pinch of salt` reads the same at 2 servings and at 12.
- Typing 0 in the servings box shows a sentence and changes nothing.

## 7. Open items

- Whether the scaled view can be saved as a copy of the recipe. Recommendation: not in the first release.

## 8. Traps, known before starting

- Rounding a scaled value and then scaling that again compounds the error; always start from the original.
- "1/2 egg" is not a quantity anyone can use. Whole items round to whole numbers, with a note.
