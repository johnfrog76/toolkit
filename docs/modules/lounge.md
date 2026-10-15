# The lounge module

The lounge module is the ambient room: a web-only tab, drawn in the theme in force, holding the Face
card, three small games that keep no score, and the Skins dialog that dresses the whole product. It is
the room where a single thread of consciousness is restored -- where a person looks up from the work.
This document is the contract for what is built; the
living design -- the Virtual Team, the study, the story, everything past the room -- stays a
design note, and a piece of it comes to the spec only when the owner calls it ready.

The owner's why, in one breath: *"I want to have a lounge where single thread of
consciousness is restored and creative thinking can exist -- azure is the hydra -- opposite of zen
development."* And the nutshell: *"You do not get to move to the Temple -- you build it on Hydra
ground. The weather is underfoot; the calm is built on top."*

## Who it is for

Anyone whose working day is many-headed. Home, the board and Daily are where work gets done; the
Lounge is where you look up from it -- and it is judged on the RETURN: if the board does not look
simpler after five minutes in the room, the room has failed, whatever it looks like inside.

## Turn it on

```powershell
tkConfig -Set features.lounge=true      # or the Modules row in the settings drawer
```

Off means absent -- no tab, no route, nothing fetched. The flag is the engineer's (top-level
`features`, `config.local.json`), like every module's. While it is NOT CONFIGURED, the foot of Home
carries the discovery tip -- *"Turn on the Lounge for a restful place and restored creative
thought"* -- the first of the tips card's discovery family: an answered no (`features.lounge=false`)
retires the tip, because the tips never nag a decision.

## Where it is

Web-only, like deck: no verbs, no agent routes, one web module (`web/src/modules/lounge/`). The
nav entry sits LAST, deliberately -- you look up from the work, so the room stands apart from the
work's tabs.

## What the room is

**A tab styled like the GUI.** In the owner's words: *"you have Sunny theme you have sunny lounge."* The room
is drawn in the theme in force -- the one you chose, or the skin the product is wearing -- exactly
as every other page is. It has no scene slot, no skin of its own and no toolbar; the temple and the
tank are skins the whole product wears (below), not furniture the room keeps. Under the explain line,
**Face first, then the games**: two by two on a desktop, a column on a phone.

## The Face card

The Face card lives in the Lounge (spec D-L24) -- the ToolKit logo's mood, picked per browser, the
first thing the palette rule binds. It is the ADO module's card, imported, never forked, and
the Lounge is the only place it is drawn: with the Lounge off it is absent, like the rest of the
room ("face card now lives in lounge rather than system"). The face itself is a per-browser
preference, so the logo keeps whatever was chosen; a browser that refuses storage (a private window
with site data blocked) shows the default face, and a choice made there holds for the session and is
gone on reload. It carries no count badge -- no numeral stands in
the room, and a count of faces would be a number for its own sake.

## The coffee table

**Go, nine by nine** (`GoBoard.tsx`). A placement sandbox from the owner's hub note, not an engine: a
grid of box-drawing glyphs, `●` and `○` at the intersections, a ghost stone where the pointer rests,
black and white in turn, a double-click lifts a stone (the note's manual capture), and the footer's
"black to play" is also the pass. No liberties, no ko, no score, no captured count -- a count is a
numeral, and the room has none -- and no coordinates: the intersections are named by letters both
ways. A stone settles rather than appears, instantly under reduced motion. The board persists per
browser, so a game left mid-way is there tomorrow; **Clear board** is the one control. Lines,
stones, ghost and accent are the theme's own tokens (D-L23), so the board wears a skin for free.
`GoBoard.test.tsx` holds the turn, the lift, the persistence and the no-numerals rule.

**Zen Word Scrape** (`WordRing.tsx`, `words.ts`). A ring of five or six letters dealt from a
bundled list of calm, positive words -- about two hundred, drafted for the owner's edit -- and you
type, or click the letters, to form a word; Enter keeps a real one into the quiet list beside the
ring, a false one goes without a sound, Escape lets the guess go. A ring is dealt only from words
with enough other words inside them (`RING_WORDS`, at least three), so every ring is worth sitting
with. No score, no streak, no timer, no fanfare: when the ring is spent it gives way to the next,
and the one reward the note asked for is kept where it costs nothing -- if the tank is worn and
Animate is on, a spent ring turns it to its next scene; a still tank stays, and nothing is ever
unlocked. The ring and the words kept persist per browser; **New ring** deals another.
`WordRing.test.tsx` holds the list's honesty, the rings' depth, the typing and clicking, the
persistence and the reward's one condition.

**Tic-tac-toe** (`TicTacToe.tsx`) -- the game the owner named first ("a game of tic-tac-toe. Idk"). You
are ✕; a POLITE opponent plays ○ at random the moment you move -- company, not competition. The
footer says whose move it is or how it ended, in words (✕ wins · ○ wins · a draw), and **New game**
clears it. No tally, no streak, no numerals; the Go grid's glyph register, the theme's tokens; the
board persists per browser. `TicTacToe.test.tsx` holds the reply, the win, the draw and the rules.

**The games say what they are**: one quiet sentence under them -- *The games are here for the mood. Ones that play back are on the way.* -- and Lounge.test.tsx holds that it renders exactly once.

**The room asks nothing**: zero numerals in its visible text, zero inputs, no fetch on an interval,
and ONE exposed action -- **Skins** -- held by `Lounge.test.tsx`, not by good intentions.

## The Skins dialog, and the grant

**Skins live in a dialog, opened from the Lounge and nowhere else** (spec D-L18; *"a skin is
worn -- I might have 20 skins and that really makes the theme picking overkill -- pick your theme --
if you want crazy skin, go to the lounge, apply a skin, play a game, leave the lounge and go back to
office from the settings"*). The dialog is a scrolling grid of cards: **No skin** first -- the
theme underneath, as a swatch, named -- then every scene as a frozen `#still` thumb with its
caption, the worn one ringed. Click a card and the whole product wears it at once, in this browser:
that is the GRANT, one click. The No-skin card takes it off in the same place, and so does picking a
theme anywhere (D-L17) -- the everyday way back to the office. Never in the ThemePicker, the avatar
menu or Settings; the avatar menu tells the truth about the worn skin and moves no control.

**Animate is a switch, default OFF** (D-L19). A worn skin is its still frame -- the zero-JS
`body:target` contract every scene document carries, `src#still` -- until the person turns Animate
on, and then the scene's slow clocks run behind every page, live. The switch remembers its resting
answer per browser, so the next skin picked wears it. The OS's `prefers-reduced-motion` still wins
(D-L12): reduced never means removed, the composition holds.

**The grant is FULL SKIN (D-L13, "toolkit becomes the room")**: the scene at FULL strength behind
every page -- no scrim -- and it REPLACES the theme: each skin carries a house-shape theme record
(`SKIN_THEMES` in `themeList.ts`, not in the picker's list), so every button, link, badge and card
re-derives from the skin's palette while it is worn (D-L22: every theme consumer reads
`useWornTheme`). `shared/skinGrant.ts` is the one owner of the key, the shape and the change event;
the dialog is its only writer; the shell's `GrantedSkin` wears it without importing the module. The
grant's `animate` field is the switch; an older grant that said `still` reads as its inverse.

**The scenes** are the `aquarium-saver` scapes -- seven, four fresh and three salt, each standing in
its own European living room at night -- ported by `web/tools/port-aquarium.mjs` into
self-contained, ZERO-JavaScript documents under `web/public/lounge/aquarium/`, plus the zen temple's
standalone twin, `public/lounge/temple.html`: assets, not bundle, fetched only when one mounts, each
in a fully sandboxed iframe. The saver's own words are the room's law arrived early: "runs on its
own slow clocks and never asks you for anything."

## Known gaps

Everything beyond the room -- the hand-tuning pass (wood-panel grain, the element-by-element zen), the
study, the company (Solitaire Agile), the story -- lives on the living design card and the spec's
open items, done with the owner's eye, never speculatively.
