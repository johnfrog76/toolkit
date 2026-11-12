# The deck module

The deck module plays presentations in the web UI: a slide is a React component -- so it can be a
live chart, a real piece of UI, or a drawing that moves -- and the deck can read itself aloud from
committed audio. It is web-only (no verbs, no agent routes), behind one flag, with its launcher on
the Growth page. It is for the engineer who presents a deck or two a year.

**The engine is [Connected Deck](https://github.com/johnfrog76/connected-deck).** Its README is the
manual: the slide-authoring contract, presenter and audience modes, presenter notes (`Say`,
`Context`, `Beat`), narration, and the design notes behind all of it. This file only says what is
different here.

## Connected Deck, the repo

| | |
| --- | --- |
| **Repository** | <https://github.com/johnfrog76/connected-deck> -- MIT, React 18 + Fluent UI |
| **Try it, no install** | <https://johnfrog76.github.io/connected-deck/> -- two decks, narrated, in a browser |
| **Read there** | the slide-authoring contract; presenter vs. audience mode; presenter notes (`Say`, `Context`, `Beat`); how narration and baked voices work; "Bringing your own decks"; the design notes |

Connected Deck is the public home of this engine: a presentation engine for engineers, built on the
idea that a slide should not have to choose between "looks good" and "is real". **If you want to
understand how a deck is written, start there, not here.**

How this module relates to it:

- **The deck that ships here is from that repo.** *Trailer -- The Connected Deck Universe*, its
  `cat-dev` figure and its 38 baked voice files were copied from `connected-deck` at commit
  `3d8a1a5`.
- **The engine here and Connected Deck are siblings.** Both come from the predecessor repo this
  Toolkit grew out of, and neither is a copy of the other. **The player matches Connected Deck
  [0.2.0](https://github.com/johnfrog76/connected-deck/releases/tag/v0.2.0)**: its two bars, its
  Audiobook mode and the modes a host offers were taken from that release's engine, file for file,
  with this module's import paths and the differences listed under "What is different from Connected
  Deck", below. This one also kept parts that one dropped. A deck written for one runs on the other
  with its import paths changed (`../deck-engine/` there, `../engine/` here) -- which is how the
  trailer got here.
- **Nothing is fetched from it.** There is no dependency on that repo at build time or at run
  time; a fix made there does not arrive here by itself.

## Who it is for

**Someone who presents a deck or two a year**, not someone who runs a library of them. In the
owner's words: "it is not for the power user - it is for presenting a deck or two a year. Not 102 decks
like I have in my blog." So there is no voice-audit verb, no staleness report, no publish step and no
predeploy checklist here -- that workflow exists, and it lives with the blog it serves. What this
module owes its user is small: turn it on, see a deck, present it, add one of your own.

## Turn it on

```powershell
tkConfig -Set features.deck=true      # or the toggle in the settings drawer (click your avatar)
```

Off means absent: no route, no card, no tab. On stays light -- the engine, the deck and its audio
are a chunk the browser fetches when a deck is shown, never part of the first load.

## Where it is

| | |
| --- | --- |
| **The launcher** | a **Decks** card on the **Growth** page -- a presentation is a growth item, and a deck is what a presentation produces. With growth off, the module has a **Decks** tab of its own |
| **A deck's page** | `/decks/<id>`, inside the shell: what the deck file says about it, **Play**, and this machine's **Archive** -- "A deck's page", below. **Open the deck** on an item of the Decks panel opens it |
| **A deck** | `/deck/<id>`, full screen: the Toolkit's nav bar is not drawn around it. **Exit** goes back where you came from |
| **The podium** | `/deck/<id>?present=1` -- Podium: the presenter's bar and notes in a second window (`/deck/<id>/notes`); the deck window is silent -- "The player's two bars", below |
| **The landing page** | Introducing ToolKit plays on the GitHub Pages landing page too, from the same engine and baked clips, whatever `features.deck` says: the page is not part of the app, so no flag applies to it ([`web/README.md`, "The landing page"](../../web/README.md#the-landing-page)) |

## What ships

Two decks:

- **Trailer -- The Connected Deck Universe** (19 slides, about four minutes), with 38 baked voice files
  in two voices, Jenny and Brian. It plays with sound, no key and no server.
- **Introducing ToolKit** (ten slides, Complete, about four and a half minutes narrated), the commercial:
  a Nordic living room in SVG where cards drift in as envelopes, settle into the lanes of a cabinet by
  what is written on them, the wall keeps the week, the shelf gathers the review, and the room's one
  window opens twice, in the order the product works: first on GitHub, where issues rest on the sill
  and the crew stands up through the glass, then, with Nimbus the Azure Butler, on Azure DevOps, where
  the cards move on their board. Slide 1 says the front door's sentence and the three ways of working
  (`README.md`). It is built in the Wasteland studio to its Design Review Gate
  and QA loop (a private repository, `src/decks/the-toolkit.tsx`; the design contract is kept
  there beside it). Its slide art is `toolkit-figures.tsx`, which carries
  `WordmarkMark` (the SVG twin of the HTML wordmark) and `TOOLKIT_REPO_URL`. Ships with the Demo slug
  out of the box. Every slide carries three `Say` lines written to play like an audiobook, and
  **20 baked voice files** under `voices/the-toolkit/`, Jenny (the default) and Brian, so it plays with
  sound, no key and no server; the three slides whose words the rework changed (1, 5 and 6) wait for the
  studio's re-bake, and until it lands slide 1 plays its previous lines and slides 5 and 6 play silent.
  The deck, its figures file and its voices are maintained in the studio and carried here by
  `goShipDeck`, byte-identical; a change made here is a bug. <!-- portability-ok: the Wasteland studio's own verb, named on purpose -- it is the carrier, not a command of ours -->

Kit's draft tour, **Meet the Toolkit**, is not shipped here: it is maintained in the Wasteland studio
(a private repository, `src/decks/meet-the-toolkit.tsx`), where Kit's full guided tour grows from it.

### The first-run banner

A machine `tkStart` set up opens on Home with a banner above the tabs: Introducing ToolKit's first slide
IS the banner, shaped like the Wasteland's home hero without the carousel -- the whole 16:9 frame on a
phone, the 3:1 letterbox from `md` (768px) up, the slide's own eyebrow, title and lead as its copy, and
its animations frozen (`stillPosters.tsx`, ported from the Wasteland) so nothing moves until the deck
plays. Two controls are built into it: **Get Started** at the bottom right (to `/deck/the-toolkit`; a
click anywhere on the banner does the same), and an **x** at the top right that closes it the way a
dialog closes -- no label. Either one writes `firstRun.welcome=false` through `PUT /api/config` ->
`Config -Set`, and the banner is gone for good. It is shown only when all three hold: the deck module is on, `/env` has answered, and
`/env`'s `config.firstRunWelcome` is true. `firstRun.welcome` is `false` in the shipped config, so a
machine that was never started from the sample hub never sees it (`docs/CONFIGURATION.md`). Settings
shows the key as a switch named **Hide Overview Deck**, drawn inverted -- on means the banner is hidden --
because hiding is what a person chooses there; `configLabels.ts` marks the row `inverted`.

The deck module contributes it to Home's **`home-banner`** slot (`web/src/shell/slots.ts`), and Home
renders whatever is in that slot -- so Home, which is the ADO module's page, imports nothing from here.
The poster is `SlidePoster` (`web/src/modules/deck/SlidePoster.tsx`, also the Wasteland's, unchanged):
a real slide rendered at its native 1280x720 and scaled to cover its box. The banner is lazy, like the
rest of the module, so a machine that has dismissed it never downloads it.

## The player's two bars

The player draws one of two bars under the slide, by the mode it plays in. The split into two bars,
the viewer's bar's layout rule, the play ring, the modes a host offers and the phone rule are
Connected Deck 0.2.0's; what this player does differently is listed under "What is different from
Connected Deck", below.

| Mode | Bar |
| --- | --- |
| **Paging** (the default) and **Audiobook** | **The viewer's bar**, at every width: **Exit** on the left; in the middle, the text arrows ← → either side of the slide counter in Paging, or chevrons either side of the **play ring** in Audiobook; on the right **Settings** (the gear), fullscreen and the **sound**. The gear opens a short sheet from the bottom, titled **Voice**: the **Narration** switch; **Mode**, with **Paging** and **Audiobook** side by side, where the host offers the choice; and the voice. No hint text. The sound and the sheet's Narration are one setting. On a phone the controls are thumb-sized, the arrows are chevrons, Exit drops its word and there is no fullscreen button |
| **Podium** (`?present=1`) | **The presenter's bar**: Exit, previous, the counter, next, the speaker notes and fullscreen. No sound and no voice: the deck window is the room's screen and stays silent, and narration is the notes window's |

**The mode row and narration.** Audiobook turns the slide when narration ends, so the mode row is dead
while Narration is off, and turning Narration off -- from the sheet or from the bar's sound -- sets
the choice back to Paging. A deck opened in Audiobook narrates on arrival.

**Who offers what**, host by host:

- **A deck listed in `decks/index.ts`** (`DeckHost.tsx`): Paging or Audiobook, chosen in the sheet
  and **kept per browser** (`localStorage` key `toolkit-deck-audiobook`,
  `DECK_AUDIOBOOK_STORAGE_KEY`), so a viewer who chose Audiobook opens the next deck reading itself
  aloud. Podium at `?present=1`, because its notes window finds the deck in the same list.
- **A deck built from data** (`GeneratedDeckHost.tsx`, the played standup): opens in Audiobook every
  time, and the sheet's choice lives only as long as the room -- a standup is played once, as it was
  written that morning, so there is no next viewing to remember it for. No Podium: its notes window
  would not find it in the list.
- **The landing page's commercial**: Paging, with no mode row and no Podium -- the page has no
  notes window, and the commercial is a fixed piece the call to action plays.

The modes each host offers are written once, in `web/src/modules/deck/offeredModes.ts`. **A phone never
gets Podium**, even at `?present=1`: the player plays it on the viewer's bar, since the presenter's
bar does not fold and a phone cannot open the second window.

## A deck's page

Between the Decks card and the player sits a page for each deck, `/decks/<id>`, in the shape of every
other detail page here: the page card, the back arrow and the title on the left (with a `deck` chip,
its state, and `archived on this machine` when it is), the controls on the right, and the body. The
body is read from the deck file and nothing else: its **summary**, its **state** (the studio's four:
draft, in progress, complete, archive), its **tags**, its **slide count**, its **running time** (the
same estimate the card's clock chip shows) and the path of its **played copy**,
`web/src/modules/deck/decks/<id>.tsx` -- a deck file is named for its id, and `deckList.test.ts` holds
that for every file in `decks/`.

**Play** is the page's one exposed action and opens the player, unchanged. Its `...` holds
**Archive**, and on an archived deck **Unarchive** in its place.

**Archive is this machine's, not the deck's.** The decks are built in the studio and shipped here as
files, so nothing in the product edits one -- not its state, not its tags, not its summary. Archive
adds the deck's id to `deck.archived`, a machine setting in `config.local.json`, through
`PUT /api/config` -> `Config -Set`, the one writer ([`docs/CONFIGURATION.md`](../CONFIGURATION.md),
"`deck.archived`"); Unarchive takes it out, and the last one out unsets the key. `/env` serves the list
as `config.deckArchived`, `tkConfig -List` shows it, and Settings names it **Archived decks**. A deck
archived this way leaves the Decks card's default list and sits under its **archived** filter; its
page says so. A deck whose own `state` is `archive` is a different thing -- the studio's word for it
-- and stays in the default list under that state's chip.

**The Decks panel's card item** keeps its title, its slide count, its running time and its state chip.
Its title is plain text, as on every card item; its exposed action is **Open the deck**, which opens the
page, and its `...` holds **Play**. The panel is a list panel: three decks a page under its filter
chips (four where it draws none), the pager in the foot.
The vocabulary puts a row's link out last (`web/README.md`, "One vocabulary for row actions"), and a
deck has none: the `Deck` type carries no address of its own (`project` picks the player's giveaway
repository, which is the engine's and not the deck's), so neither shipped deck has an **Open on**
entry, and none is drawn disabled in its place.

## Where the decks are made

Not here. The Toolkit's decks are **built, reviewed, fixed and baked in the Wasteland studio**
(a private repository), which has the tools -- the capture-and-judge QA loop, the bake, the register
plates -- and the artwork, the figures families every deck quotes. This repo holds the **played copy**:
the deck file, the family figures file it shares (`toolkit-figures.tsx`) and its `voices/<deckId>/`
folder, copied over whole after a change there, plus one line in `decks/index.ts` and an entry above.
The two copies are kept byte-identical; edit the studio's, then copy.

## What is different from Connected Deck

- **Nothing is published.** Connected Deck and the site it came from had a public audience, so a
  deck carried `deployed` and `audience` and there were two registries to keep a private deck out
  of the public bundle. The Toolkit publishes nothing: there is **one** registry,
  `web/src/modules/deck/decks/index.ts`, and nothing reads those two fields. They stay on the type
  so a deck file ports unchanged. `state` -- draft, in progress, complete, archive -- means what it
  always did, and the launcher filters on it -- **only once two decks in its list are in different
  states.** With every listed deck in the same state the row would offer four choices that all show
  the same thing, so `DeckPickerCard` counts distinct states in play and hides them rather than showing
  a filter that filters nothing. The **archived** chip follows the same rule: it is drawn once a deck
  is archived on this machine (`deckList.ts` holds both, `deckList.test.ts` is the table).
- **Audience is the default mode.** Presenter-as-default suits an engine with a live narration service,
  where the notes window does the talking. The Toolkit has no such service; its voices are baked
  files, which the audience path plays.
- **The engine is carried, not installed.** It lives whole in `web/src/modules/deck/engine/`, with no
  package dependency. Two pieces of the predecessor's engine are not here, because they call that
  app's API and no shipped deck uses them: `ShellEmbed` and its output renderers. The step functions
  are `stepNext` and `stepPrev`, because this repo's portability check reads `go` + a capital as a
  command of the old toolkit.
- **The bars: Connected Deck 0.2.0's split and layout, this player's own menu.** Taken from 0.2.0:
  the two bars, the viewer's bar's three columns with the transport on the screen's centre
  (`viewerBarLayout.ts`), the play ring, the modes a host offers (`offeredModes`) and the rule that a
  phone never gets Podium. Different here:
  - **The sheet** is titled **Voice**, is the drawer's small size, and holds three rows in this
    order: Narration, Mode (**Paging** and **Audiobook** side by side -- 0.2.0 says Sofa, and puts
    the mode first), the voice. No hint text: the controls say what they are. Its form is this
    module's own, `web/src/modules/deck/SettingsForm.tsx`, at the path the engine imports it from.
  - **Narration first, the mode after it.** The mode row is dead while narration is off, and turning
    narration off sets Audiobook back to Paging; in 0.2.0, choosing Audiobook turns narration on.
  - **Text arrows on a wide screen** beside the counter, as the presenter's bar has them; chevrons
    beside the ring and on a phone, where 0.2.0 has chevrons everywhere. On a phone Exit's glyph is a
    little larger than the arrows'.
  - **The presenter's bar has no sound and no voice dropdown**, and Podium never narrates in the deck
    window: it is the room's screen, and narration is the notes window's. 0.2.0 puts both on the
    presenter's bar.
  - **A host's mute.** Where a host keeps one (the played standup, `docs/modules/solitaire-agile.md`),
    it is the viewer's bar's sound and the sheet's Narration switch, one setting. Muted, each slide
    keeps its clock, so Audiobook still advances, keeps its choice and keeps its mode row live. With
    nothing to narrate the mute reads dead, like the speaker.
  - **Fullscreen** is drawn only where the browser has the Fullscreen API.
  - **What is remembered**: a listed deck's Paging or Audiobook, per browser. Not the voice, not
    narration on or off, and not Podium, which only `?present=1` asks for.
  - The notes window and the deck's sync channel keep this product's names, and the player does not
    take 0.2.0's deprecated `suitcase` prop, which no host here ever passed.
- **Kept here, not in Connected Deck.** The `audiobook` deck hint and the browser's voice
  (`useSpeechNarration.ts`, "Audiobook decks" below), the deck context and the giveaway button
  (`deckContext.tsx`, `deckLinks.ts`, `GiveawayButton.tsx`, `borrowSlide.tsx`), and the player's own
  phone-width question (`useCompactLayout.ts`, the same 575px edge as `viewport.tsx`).

## Adding a deck

A deck is a `.tsx` file that exports a `Deck`; register it in `decks/index.ts` and `/deck/<id>`
exists. A deck is **code** -- it is compiled into the web build -- so it lives in this tree, not in
your hub. Baked audio goes beside it as
`web/src/modules/deck/voices/<deckId>/<slideId>-<voiceId>.mp3`; the filename is the whole contract,
and a voice is offered for a slide exactly when its file is there.

## Audiobook decks

A deck may set **`audiobook: true`** (`decks/types.ts`) -- a deck made to be listened to end to end,
which today means Team Agile's ritual decks (`docs/modules/solitaire-agile.md`, "The played view").
**Audiobook mode** is a different thing, and the host's: the player's `audiobook` prop reads the deck
aloud and turns its slides at any width, with the play ring between previous and next, for any deck
that has something to read. The hint adds one thing, for that deck only: a slide with **no baked clip
is read aloud by the browser's `speechSynthesis`** from its title and `Say` text
(`engine/useSpeechNarration.ts`). With no speech API the slide still lives for its estimated read time
and then advances, silently. The two shipped decks set nothing;
`DeckPlayer.audiobook.test.tsx` holds the hint and that a deck without it never reaches
`speechSynthesis`.

Such a deck is not in `decks/index.ts`: it is **built from data** by the module that owns the data and
played through the engine's **second resolver**, `GeneratedDeckHost.tsx`, which takes a resolution
(the deck, or loading, or an error for the shared empty state) where `DeckHost.tsx` looks an id up in
`DECKS`. Nothing is pushed into the static list, the two share `DeckRoom.tsx` (the dark room, and the
page's `<main>` landmark, since a chromeless route has no shell around it to give one), and the generated
deck's route is its own module's -- so it plays with this module's flag off, the engine fetched as a
chunk by whichever module draws it. `GeneratedDeckHost` opens such a deck in Audiobook and keeps the
choice while the room is open: the sheet's mode row turns it to Paging and back, through the player's
`onAudiobookChange` ("The player's two bars", above).

**The deck room is dark on purpose, whatever the app wears** (reversing a change that had it follow the app's theme, at the owner's word).
`DeckRoom` provides the shell's dark theme and `DeckPlayer` (and the notes window) the engine's default
`webDarkTheme`, so a played deck looks the way Connected Deck's default does under Seaglass, Aurora or any
other theme. Nothing in the room reads `useWornTheme`; `DeckRoom.test.tsx` holds that the providers' tokens
do not move when the worn theme does.

## Known gaps

Not built yet: baking voices from the Toolkit, a way to keep your own decks outside this repo, and
`ShellEmbed` ([Deck voices and your own decks are not made in the Toolkit](../KNOWN-GAPS.md#deck-voices-and-your-own-decks-are-not-made-in-the-toolkit)).
