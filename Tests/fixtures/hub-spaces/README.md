# The Studio smoke's hub

What `npm run smoke -- --studio` (`web/tests/smoke.mjs`, #179) runs against: a hub of one Space of
each kind the Studio's Spaces card files a row under, and the machine-half seed that carries a dead
line.

- `hub/hub.json` -- four Spaces: **Work Space** (no tracker, `local`; the run is in it), **Product
  Space** (a GitHub address, `local`, so nothing asks `gh`), **Sample Space** (`example: true`) and
  **Retired Space** (`status: archive`). `config.default.json`'s shipped Azure demo is listed beside
  them, so the card reads All 5, Products 1, Work 1, Out of box 2, Archive 1.
- `hub/work/current/` -- one Active card, so the row of the Space you are in has something to count.
- `config.local.json` -- `"features": { "studio": false }`, the line a person typed by hand before
  the Studio was core (D-S13, #169). The smoke copies it into a scratch package before its agent
  starts; nothing writes it.

The smoke never writes here: its flag flips go to the scratch package's own `config.local.json`
through `PUT /api/config`. The names and the address are placeholders and belong to nobody.
