---
id: 4c9c2aee-fced-4114-8cb2-e3a8582251c0
description: "Change the servings and every quantity follows, rounded the way a cook measures"
space: demo
---

# Scale a recipe by servings

## Problem

A recipe is written for four, and the cook is feeding six. Doing the arithmetic by hand in the middle of
cooking is where mistakes happen, and a calculator gives 1.4999 cups, which nobody can measure.

## The idea

Change the servings and every quantity follows, rounded to something a measuring cup actually has: 1 1/2
cups, not 1.4999. Amounts that are not numbers -- "a pinch", "to taste" -- are left exactly as written.

## Open questions

- Which fractions do we round to: halves and quarters, or thirds and eighths as well?
- Does scaling change the cooking time? Probably not, and the app should say it does not know.
- Is the scaled recipe saved, or only shown until the cook leaves the page?

## Source

Card US 216, *Scale a recipe by servings*, in the Demo Space. It depends on the unit conversion being a
pure module (Task 211), so scaling is not a fourth copy of the same rounding.

## Journey

- 2026-10-07 Design: written as design/scale-a-recipe-by-servings.md in the hub.
- 2026-10-07 Spec: became spec/scale-a-recipe-by-servings.spec.md in the hub.

**Created:** 2026-10-07
