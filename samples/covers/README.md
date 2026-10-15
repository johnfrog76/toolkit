# Covers

Twenty cover pictures for cards, drawn as SVG and sliced to 800x500 WebP (16:10, the board's card
face). Ten are the out-of-box cards' own -- the recipe app's search, shopping list, servings, pages,
units, photo import, sprint review and welcome card, a recipe and a timer -- and ten are for a card
of any kind: the board, a card as a file, a pull request, the archive, the hub, connecting a tracker,
the Studio, the Lounge, a bug and a spike.

One visual system: a self-contained ground, so a picture reads the same on a light or a dark theme;
a small palette; large shapes; no text. `svg/` holds the sources, the `.webp` files beside this
README are the slices, and `make-covers.mjs` draws both (it uses the web tree's Playwright; run it
from `web/`):

```bash
cd web && node ../samples/covers/make-covers.mjs
```

The sample hub's cards wear these already: each `samples/hub/<space>/assets/<card key>/cover.webp`
is one of them, attached with the `Cover` verb, and `Start` copies them out with the cards. To put
one on a card of your own: `tkCover <id> samples/covers/<name>.webp`, or drop it on the card page.
