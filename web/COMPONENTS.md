# The web UI's shared components

The pieces every panel is built from: the frame, the row menu, the dialog parts, the empty state, the
small buttons and tiles. A contributor building a panel starts here, picks the piece, and reads its
props below. [`README.md`](README.md) is the rest of the web half; the grammar for dialogs and row
actions is written there once, and this file links it rather than repeating it.

**This file is held to the code.** `src/shell/components.doc.test.ts` reads it with the TypeScript
compiler and fails when a shared export has no section below, when a section names something that is
not an export, or when a props table and its exported type disagree about a key in either direction.
Adding an export or a prop means adding its section or its row in the same commit.

## Three words

- **Panel** -- one framed box on a page, drawn by a kind such as `ListPanel` on `PanelFrame`: a header, a body, a foot. What a person
  sees on Home or on a module's page as "the Prompts card" or "the Reminders card" is a panel.
- **Card item** -- one entry inside a panel's list: a row with a title, a line or two, and its actions.
  The "Active Cards" panel shows each prompt file as a card item.
- **Prompt file** -- the Markdown file a work item keeps in the hub, which the CLI also calls a card.
  Where the two meet, this document says "prompt file" for the file and "card item" for its entry in
  the UI. The hub's side is [`docs/hub/cards.md`](../docs/hub/cards.md).

## The grammar these pieces enforce

- Dialogs and row actions: [One grammar for dialogs and row actions](README.md#one-grammar-for-dialogs-and-row-actions).
- The words, icons and tooltips of a row's menu: [One vocabulary for row actions](README.md#one-vocabulary-for-row-actions).

## Where a shared piece lives

Shared pieces are in `src/shared/`, with `lazyPart` in `src/shell/` and the panel kinds in `src/shell/kinds/`. A module imports from them; they
import from no module. Props are always an exported, named type, never an inline literal, never `any`,
never an index signature, and never `ComponentProps<typeof X>` standing in for a real type. A lint
rule (`@typescript-eslint/no-explicit-any` as an error under `src/shell/` and `src/shared/`) holds
the first of those.

## `PanelFrame`

**What it is for:** the frame every panel is drawn in, and the private base of the panel kinds. It is
the outline box (Fluent's `Card`, imported here and nowhere else), the header with its rule, the body,
the toast and the foot.

**Use it** only from a kind in `src/shell/kinds/`: a feature module fills a kind (`ListPanel`), never
the frame. A page that is not a panel (a detail or document page, the Docs reader, the Actions forms,
the Connect, Standup and Triage pages) keeps the frame and is exempt by name, with its reason, in
`src/shell/kinds/panelStructure.test.ts`. A panel that has not moved onto its kind yet is on a named
list in the same test, which is held exact: a file that moves comes off it, and a new file cannot join
it quietly. **Do not use it** for a list entry inside a panel (that is a card item), and do not set a
height or a margin on it from outside.

Props:

| Prop | Type | Notes |
| --- | --- | --- |
| `headerLeft` | `ReactNode` | Title side of the header; a rule follows when either side is set. |
| `headerRight` | `ReactNode` | Actions side: pickers, search, refresh, the count chip. |
| `body` | `ReactNode` | The body slot: what the panel holds, named like every other slot. |
| `children` | `ReactNode` | The default slot: it fills `body`. Pass `body` or children, never both: the types refuse both, and the frame throws when drawn with both. |
| `toast` | `ReactNode` | A `StatusMessage` under the body; hidden while loading. |
| `footer` | `ReactNode` | A single foot cell, used only when no foot slot is set. |
| `footerLeft` | `ReactNode` | Foot, left: usually a sentence. |
| `footerCenter` | `ReactNode` | Foot, middle: the pager. Keeps its width on one line; the two sides share what is left. |
| `footerRight` | `ReactNode` | Foot, right: usually a `CreateButton`. |
| `footNote` | `ReactNode` | One line under the foot row, the width of the panel. |
| `scrollable` | `boolean` | The body in the frame's thin-scrollbar scroll area, the header and foot fixed. The one sanctioned scroll form, for a panel whose body is a single block; a list panel never uses it, because it pages. |
| `loading` | `boolean` | Draws the spinner instead of the body, toast and foot. |
| `loadingLabel` | `string` | The spinner's label; default `Loading...`. |
| `empty` | `ReactNode` | Replaces the body; hand it an `EmptyState`. The header and foot stay, so a filter that hid everything stays reachable. |
| `className` | `string` | Merged onto the box. |

**The foot holds the bottom.** The frame is a column and its body grows (`flex-grow: 1`, one rule in
the frame's styles), so the foot sits at the frame's bottom edge however short the content is, with the
empty room between the body and the foot. No divider is drawn above the foot. The body's children are
wrapped in one element (`data-panel-frame-body`) that keeps the frame's 12 px gap between them.

### Slots

A panel reads as named slots. `PANEL_SLOTS` (`src/shell/panelHeight.ts`) names them once, in this
order; the last column is the `PanelFrame` prop that fills each today.

| Slot | What fills it | Optional | `PanelFrame` prop today |
| --- | --- | --- | --- |
| `header` | the panel's icon and title | no for a kind (`title` is required); optional on the frame | `headerLeft` |
| `info` | one sentence about what the panel holds, behind the info icon after the title | yes | `headerLeft` (an `InfoTip` after the title) |
| `actions` | the header's controls: pickers, search, the panel's one action, refresh, the count chip | yes | `headerRight` |
| `filters` | rows of filter chips, each chip with its count | yes | the top of `body` (a list panel draws them over its list) |
| `body` | what the panel holds: a list panel's card list, paged; a block kind's content, scrolled when it overflows | no (a kind always has one; `empty` or `loading` stand in for it) | `body`, or children as the default slot |
| `foot` | the foot row (words at the left, the pager in the centre, the **+** at the right) and one line under it | yes | `footerLeft`, `footerCenter`, `footerRight`, `footNote` |

A panel with a maximum height holds what does not fit in one of two forms, chosen by its kind and named
in `PANEL_BODY` (`src/shell/panelHeight.ts`): `paged` (card items, the pager at the foot) or `scroll`
(the `scrollable` prop). No panel sets an overflow of its own.

**Used by:** the kinds, the exempt pages and the panels on the migration's list. **Pattern:** a
slot-based frame that sets no height and has no margin; a panel is spaced by the wrapper that holds it.
**Test:** [`PanelFrame.footer.test.tsx`](src/shared/PanelFrame.footer.test.tsx) (the foot's slots and
that the foot holds the bottom), and `panelStructure.test.ts` for who may import it.

## `ListPanel`

**What it is for:** the kind for records you act on. A panel fills its slots and nothing else; a slot
the kind does not have is a compile error.

**Use it** for any panel whose body is a list of card items: Active Cards, My Work, the Log, Decks, the
Studio's lists. Hand it data, not JSX: `item` turns one entry into the card item's data, and the kind
draws it. **Do not use it** for a body that is one block (a set of checks, a chart alone).

```tsx
<ListPanel
  title="Reminders"
  items={reminders}
  item={toItem}                      // (entry) => CardItemData: data, not JSX
  empty={{ icon, title: "No reminders yet" }}
  create={{ label: "New Reminder", onClick: add }}
/>
```

Props:

| Prop | Type | Notes |
| --- | --- | --- |
| `title` | `string` | Required. The header's title. |
| `icon` | `ReactElement` | Before the title. |
| `info` | `ReactNode` | What the panel holds, behind the info icon after the title. |
| `infoLabel` | `string` | The info icon's accessible name; default `About <title>`. |
| `items` | `T[]` | Required. Every item, after the panel's own filtering; the kind pages them. |
| `item` | `(entry: T) => CardItemData` | Required. One entry as data. With `density="compact"` it returns `CompactItemData` (no `description`); with `density="line"`, `LineItemData`. |
| `density` | `"full" \| "compact" \| "line"` | The item size for every item of the panel: three bands (default), the title and meta bands, or one band. An item never chooses it, and it never changes the panel's height. |
| `empty` | `EmptyMessage` | Required. Shown when there are no items: nothing yet, or nothing could be read (`tone: "error"`). |
| `filteredEmpty` | `EmptyMessage` | Shown instead when a filter or a search hid every item. |
| `filters` | `FilterRow[]` | Rows of chips: `{ label, chips: [{ id, label, count?, active, onSelect }] }`. The rows sit in one wrapper (`data-panel-filters`), a column spaced by `filterRowGap` (Fluent's XS, 4 px, `src/shell/layoutTokens.ts`); a row has no margin and no tint of its own. The wrapper owns the space below the rows, `filtersSpaceBelow` (`controlRowsSpace`, Fluent's M, 12 px), and the list under it drops its own top padding, so the chips sit 12 px under the header rule and 12 px over the first item. |
| `pickers` | `SelectSlot[]` | Small header selects: `{ label, value, options, onChange, disabled? }`. |
| `search` | `SearchSlot` | The header's search box: `{ label, placeholder?, value, onChange }`. What a deeper search finds is handed to the kind as `items`, never drawn as a block over the list. |
| `action` | `ActionSlot` | One header button for a thing the whole panel does: `{ label, glyph, onClick, disabled?, title? }`. |
| `refresh` | `RefreshSlot` | `{ onClick, isFetching?, disabled? }`. |
| `count` | `number \| string` | The count chip. A string is a count that needs a word: `latest 500`. |
| `countLabel` | `string` | The count chip's accessible name: `12 prompts`. |
| `lead` | `ListLead` | What sits above the items, either or both: rows of figures, `stats: [{ label, stats: [{ id, count, label, tone?, detail? }] }]`, drawn as `StatTile`s with `detail` as the native title, then a chart, `chart: { label, chart }`. |
| `status` | `PanelStatus` | What a write came to (`success` or `error`, dismissable) or what the panel is doing (`busy`). |
| `create` | `CreateSlot` | The foot's **+**: `{ label, onClick }`; the label is the title of the dialog it opens. |
| `footLeft` | `string` | Words at the foot's left. |
| `footNote` | `ReactElement` | One line under the foot. |
| `loading` | `LoadingSlot` | `{ label }`, present while the panel is reading. |

There is no `className`, `style`, `height`, `children`, `pageSize` or pager slot.

**Paging is the kind's, and the page size is measured.** Once the list is laid out the kind reads the
room it really has, from the list's top under its padding down to where the foot begins
(`measureListRoom`, `src/shell/kinds/listRoom.ts`), and the page is
`max(1, floor((room + gap) / (item + gap)))` (`pageSizeForRoom`, `src/shell/pageSize.ts`), with the
density's item height and `cardListGap`. Whatever sits above the list takes its real height, so the
last item always ends above the foot: nothing scrolls and nothing is cut off. A `ResizeObserver` on the
panel and on what sits above the list measures again when any of them changes size; the foot row's
room is kept free while no foot is drawn, so a pager appearing never changes the page.

The same answer from the tokens, `listPageSize(chrome)` (`LIST_CHROME_PX`: frame 117, a chip row 26
with `filterRowGap` between two, a lead 153, a foot note 32, a status line 48), is the first paint's
page and the page where there is no layout to measure (a narrow page, the tests). Under a chip row
the list drops its own top padding, so the sum takes that padding off the chrome there. From
`listPageSize`, at the one panel height (`PANEL_HEIGHT_PX`, 600 px, chosen to hold four full items
under one chip row): four full items with no chip row or under one; three under two chip rows, or
where a foot note or a status line takes room as well; five compact; seventeen lines, eleven under a
lead. The sum counts a foot note whenever the panel passes one; the measured page follows the room
the note really takes.

The page is held as the index of its first item, so a resize that changes the page size keeps that
item in view. The pager (`ListPager`, private to the kind) is in the foot's centre, drawn only past one
page: Previous, `Page 2 of 5`, Next, and the arrow keys while it has focus. The page returns to the
first when an active chip, a picker's value or the search changes, and is clamped when the list
shrinks.

**The list.** The items are drawn in one wrapper, `<ul role="list" class="cardList" data-card-list>`
(`CARD_LIST_CLASS`), each alone in an `<li>`. The list owns the space between its items and over the
first, `cardListGap` (Fluent's S 8 px for full and compact, one value for every item that is a card;
0 for line, a log's rows) and
`cardListPaddingTop` in `src/shell/layoutTokens.ts`, each with a px twin for the sums; an item has no
margin. The list is handed to `PanelFrame` through its `body` slot.

**Height.** The root wears `data-panel-kind="list"` and both bounds, `PANEL_MIN_HEIGHT_PX.list` and
`PANEL_MAX_HEIGHT_PX.list` (`PANEL_HEIGHT_PX`, 600 px), above `PANEL_GRID_MIN_WIDTH_PX` (900 px), whatever the item size,
through `usePanelMinHeightClass(kind)` (`src/shell/kinds/panelMinHeight.ts`): a minimum for every kind,
and for `list` the same figure as its maximum. A panel not yet on its kind may wear that class
meanwhile, as the Environment panel does for `status`. The body is the paged form
(`data-panel-body="paged"`). Below 900 px the panel stacks and is as tall as its items.

### Card items

A card item is one entry inside a list panel, drawn by `ListPanel` from `CardItemData`
(`src/shell/CardItem.tsx`). A panel never renders one itself. It is a plain element styled with Fluent
tokens, not a Fluent `Card`.

| Field of `CardItemData` | Type | Notes |
| --- | --- | --- |
| `id` | `string` | Stable among the panel's items; the position on the page when left out. |
| `title` | `string` | Required. One line, clamped, plain text: never a link. |
| `description` | `string` | Two lines, clamped; the band stays, empty, when there is none. |
| `badges` | `BadgeSpec[]` | Status badges beside the title: `{ label, color?, appearance?, shape?, glyph?, title? }`. |
| `meta` | `MetaItem[]` | The meta band: `{ badge: BadgeSpec }` or `{ text, title?, shrink?, tone?, mono? }`. |
| `thumb` | `ThumbSpec` | A small picture at the start of the meta band: `{ url, label }`. |
| `progress` | `{ done: number; total: number }` | A bar and `done/total` in the meta band; nothing when `total` is 0. |
| `primary` | `PrimaryAction` | Required. The one exposed action, Open, built from `ROW.open.action()`. |
| `menu` | `MenuAction[]` | Every other action, in the `...` menu; an external link is drawn last. |
| `name` | `string` | The menu's accessible name is `Actions for <name>`; the title when left out. |
| `busy` | `boolean` | A write on this item is running: the menu trigger spins. |

`CompactItemData` (`density="compact"`) is `CardItemData` without `description`: the title band and the
meta band. My Work and GitHub Issues use it. `LineItemData` (`density="line"`) is one band (`meta`
texts, `badges`, then the title in bold and the description on one clamped line), and its `primary` is
optional: a line that opens nothing, such as a log entry, has no action.

Every length inside an item is a token in `src/shell/cardItemTokens.ts`, and each size's height is
their sum, so a change to a padding or a band changes the height with it:

| Token | Value | What it is |
| --- | --- | --- |
| `CARD_ITEM_BORDER_PX` | 1 | The outline, each edge. |
| `CARD_ITEM_PADDING_Y_PX` | 12 | The one vertical padding, top and bottom; Fluent's `tokens.spacingVerticalM`. |
| `CARD_ITEM_TITLE_BAND_PX` | 24 | The title band: the title's line height and the controls' height. |
| `CARD_ITEM_DESCRIPTION_LINE_PX` | 15 | One description line; `CARD_ITEM_DESCRIPTION_LINES` (2) of them make the band. |
| `CARD_ITEM_META_BAND_PX` | 16 | The meta band: a small badge's height. |
| `CARD_ITEM_META_GAP_PX` | 8 | Between a full item's description band and its meta band, a track of the item's grid; `tokens.spacingVerticalS`. |
| `CARD_ITEM_COMPACT_BAND_GAP_PX` | 8 | Between a compact item's two bands; `tokens.spacingVerticalS`. |
| `CARD_ITEM_LINE_BAND_PX` | 28 | A line item's one band. |
| `CARD_ITEM_HEIGHT_PX` | 104 | Full, derived: 1 + 12 + 24 + 30 + 8 + 16 + 12 + 1. |
| `CARD_ITEM_COMPACT_HEIGHT_PX` | 74 | Compact, derived: 1 + 12 + 24 + 8 + 16 + 12 + 1. |
| `CARD_ITEM_LINE_HEIGHT_PX` | 28 | Line: its band. |

Every spacing value in the panel layer is a Fluent spacing token on the 4 px grid; the bands (24, 15,
16) are content sizes and are not held to it. Text is clamped with an ellipsis and stays whole in the
DOM, with no tooltip on it; a badge or a short word in the meta band may carry a native `title`.

**Used by:** Active Cards, My Work, GitHub Issues, the Log, Decks and the Studio's lists. **Pattern:** a
template over data: the panel says what it holds and the kind decides how it is drawn, paged and
measured. **Test:** [`ListPanel.test.tsx`](src/shell/kinds/ListPanel.test.tsx) and
[`listRoom.test.ts`](src/shell/kinds/listRoom.test.ts); in a panel's own test, call
`expectListPanelShape(panel, { titles, total?, chips? })` from `src/shell/kinds/panelShapeAssert.ts`
on the drawn panel.

## `CARD_LIST_CLASS`

**What it is for:** the class name of a list panel's one `<ul>`, `cardList`, so a test or a style can
find the list without retyping it. Exported by `src/shell/kinds/ListPanel.tsx`. **Used by:** the kind
and its shape assertions. **Test:** `panelStructure.test.ts`.

## `CardActions`

**What it is for:** a card item's actions: one exposed button and a `...` menu for the rest.

**Use it** for every row of every list. The exposed action is the one thing a person most likely wants
(Open); everything else goes in the menu, even when there is only one. **Do not use it** for a form's
buttons or a dialog's footer, and do not type a `CardAction` by hand: build it from `ROW`.

Props:

| Prop | Type | Notes |
| --- | --- | --- |
| `primaryAction` | `CardAction` | The one exposed action, drawn as a flat button. |
| `secondaryActions` | `CardAction[]` | The menu's items; the external link is drawn last, behind a divider. |
| `forceOverflow` | `boolean` | Draw the menu even with no secondary action. |
| `menuLabel` | `string` | The trigger's accessible name: `Actions for <the row's title>`. |
| `busy` | `boolean` | A write is running: the trigger spins and cannot be opened. |

**Used by:** the row menus of My Work, My PRs, the board and the card attachments.

**Pattern:** a flat button plus an overflow menu, always in the same places. **Test:**
[`CardActions.test.tsx`](src/shared/CardActions.test.tsx), and
[`rowVocabulary.test.ts`](src/shared/rowVocabulary.test.ts), which reads every row menu in the source.

## `CardAction`

**What it is for:** the shape of one action in a row (a type, not a component).

**Use it** only as the result of `ROW.<move>.action()` or a `defineRowMoves` table; `move` is required,
so an action typed by hand with a word of its own does not compile.

Props:

| Prop | Type | Notes |
| --- | --- | --- |
| `move` | `string` | The vocabulary key (`archive`, `external`) or a module's own (`reminder.snooze`). |
| `icon` | `ReactElement` | Drawn in the button and the menu item. |
| `label` | `string` | The word, then its detail. |
| `tooltip` | `string` | The move's tooltip, from the vocabulary. |
| `external` | `boolean` | The link out: drawn last in the menu, behind a divider. |
| `onClick` | `() => void` | What the action does. |
| `href` | `string` | A link instead of a handler. |
| `disabled` | `boolean` | Shown and explained, not removed. |
| `whyNot` | `string` | Why a disabled action cannot be taken yet. |
| `dividerBefore` | `boolean` | A divider above this item in the menu. |

**Used by:** every file that builds a row menu (see `ROW`). **Pattern:** a record built by a
vocabulary function. **Test:** [`CardActions.test.tsx`](src/shared/CardActions.test.tsx).

## `ROW`

**What it is for:** the standard moves (`open`, `archive`, `complete`, `delete`, `move`, `copy`,
`external`), each defined once with its word, icon and tooltip.

**Use it** for every standard move: `ROW.archive.action({ onClick })`. **Do not use it** for a move
that exists on one kind of record only; declare that with `defineRowMoves`. It is a constant, not a
component, so it has no props; each entry's `action()` takes `RowActionOptions`. The table of words is
[One vocabulary for row actions](README.md#one-vocabulary-for-row-actions).

**Used by:** every row menu, among them My Work, My PRs and the board. **Pattern:** one vocabulary, read by every menu. **Test:**
[`rowVocabulary.test.ts`](src/shared/rowVocabulary.test.ts).

## `ROW_SYNONYMS`

**What it is for:** the words a module's own move may not use because a vocabulary move already owns
them.

**Use it** when you add a standard move to `ROW`: add its synonym list here. It is read only by
`rowVocabulary.test.ts`; it is not for rendering.

**Used by:** the vocabulary test. **Pattern:** a deny-list beside the vocabulary. **Test:**
[`rowVocabulary.test.ts`](src/shared/rowVocabulary.test.ts).

## `defineRowMoves`

**What it is for:** declaring a module's own row moves beside the row that draws them.

**Use it** for a move that exists on one kind of record only (snooze a reminder) or that is a
different thing from a vocabulary move (`differentMove` says why). Write the table as a literal: the
static test reads it from the source.

Props (its parameters):

| Prop | Type | Notes |
| --- | --- | --- |
| `record` | `string` | The record's name; keys are listed in the README as `record.key`. |
| `table` | `Record<K, RowMoveDef>` | Each move's word, icon, tooltip and optional `differentMove`. |

**Used by:** the modules that declare their own moves, such as reminders and designs. **Pattern:** a registry table, checked by a source-reading test. **Test:**
[`rowVocabulary.test.ts`](src/shared/rowVocabulary.test.ts).

## `DialogDismiss`

**What it is for:** the one close (X) control in a dialog's title.

**Use it** as `<DialogTitle action={<DialogDismiss />}>` in every dialog. **Do not use it** outside a
dialog title, and do not draw a close button of your own.

**Props:** none.

**Used by:** every dialog that draws a title. **Pattern:** a fixed control in a named slot.
**Test:** none of its own; it is exercised through
[`ConfirmDialog.test.tsx`](src/shared/ConfirmDialog.test.tsx).

## `ConfirmDialog`

**What it is for:** "Are you sure?" -- the one step before an act worth a second thought.

**Use it** for archive, close, delete and retire: the question, the act named in `what`, Cancel and
Submit. **Do not use it** as a form dialog; the act itself stays with the caller, this only asks.

Props:

| Prop | Type | Notes |
| --- | --- | --- |
| `open` | `boolean` | Whether the dialog is showing. |
| `what` | `ReactNode` | The act, named, with one sentence of what follows. |
| `onConfirm` | `() => void` | Runs on Submit only. |
| `onCancel` | `() => void` | Cancel, the dismiss, Escape and the scrim. |
| `title` | `string` | Default `Are you sure?`. |
| `confirmLabel` | `string` | Default `Submit`. |
| `busy` | `boolean` | The act is running: Submit spins, both buttons are held. |
| `confirmDisabled` | `boolean` | Submit cannot be pressed; nothing spins. |
| `message` | `ReactNode` | A stated refusal, shown under the act while the dialog stays open. |

**Used by:** archive, close and retire flows: Prompts, the board and the Land card hook. **Pattern:** a controlled dialog; the caller owns `open`. **Test:**
[`ConfirmDialog.test.tsx`](src/shared/ConfirmDialog.test.tsx).

## `lazyPart`

**What it is for:** a module's page, card or header item, fetched when first drawn.

**Use it** for every component a module contributes to the registry, so a module that is off ships no
bytes. **Do not use it** for a descriptor (`index.tsx`), which imports no component; a static import of
a module component is refused by `lazyModules.test.ts`.

Props (its parameters):

| Prop | Type | Notes |
| --- | --- | --- |
| `load` | `() => Promise<M>` | The dynamic `import()`. |
| `pick` | `(m: M) => ComponentType<P>` | Names the export, because components are exported by name. |
| `fallback` | `ReactElement \| null` | What shows while loading; default `lazyFallback`. |

**Used by:** the registry and the modules' descriptors. **Pattern:** a Suspense boundary per
part, so a loading card shows its own spinner in its own place. **Test:**
[`lazy.test.tsx`](src/shell/lazy.test.tsx), and
[`lazyModules.test.ts`](src/shell/lazyModules.test.ts).

## `lazyFallback`

**What it is for:** the house's "still loading" for a module part.

**Use it** only as `lazyPart`'s default. It is a constant element, so it has no props: a small spinner
that reads `Loading...`, the word the smoke test waits to clear.

**Used by:** `lazyPart`. **Pattern:** one shared constant. **Test:**
[`lazy.test.tsx`](src/shell/lazy.test.tsx).

## `EmptyState`

**What it is for:** how a panel says it has nothing to show. Its props are the exported
`EmptyMessage` type.

**Use it** as `PanelFrame`'s `empty` slot or `ListPanel`'s `empty` and `filteredEmpty`, or on its own where there is no panel. Three tones that
must not look alike: `empty` (nothing, and that is fine), `filtered` (something is hidden by a
filter), `error` (nothing was read -- never dressed as empty). **Do not use it** for plain text.

Props:

| Prop | Type | Notes |
| --- | --- | --- |
| `icon` | `ReactElement` | The card's own icon, for the plain empty case. |
| `title` | `ReactNode` | What is true. |
| `detail` | `ReactNode` | A reason, or what to do next. |
| `tone` | `"empty" \| "filtered" \| "error"` | Default `empty`; `error` is announced. |
| `action` | `ReactNode` | A button or link under the text. |

**Used by:** nearly every panel, among them Prompts, the Dashboard and Configuration. **Pattern:** one component, three tones. **Test:** none of its own yet.

## `RefreshButton`

**What it is for:** the header's refresh control.

**Use it** in `headerRight` of any panel that reads from the agent. **Do not use it** for a form's
reset or any action that is not a re-read.

Props:

| Prop | Type | Notes |
| --- | --- | --- |
| `onClick` | `() => void` | Re-reads. |
| `isFetching` | `boolean` | Shows a spinner and disables the button. |
| `disabled` | `boolean` | Disabled without spinning. |
| `title` | `string` | Tooltip; default `Refresh`. |

**Used by:** most data panels: Prompts, the Dashboard, Milestones and PR Comments. **Pattern:** a subtle small icon button. **Test:** none of its own yet.

## `CreateButton`

**What it is for:** a panel's footer **+**, how every panel that makes something says so.

**Use it** in `footerRight`, with `label` set to the title of the dialog it opens, word for word. **Do
not use it** for an action that does not open a creating dialog.

Props:

| Prop | Type | Notes |
| --- | --- | --- |
| `label` | `string` | The dialog's own title; it is the tooltip and the accessible name. |
| `onClick` | `() => void` | Opens the dialog. |
| `disabled` | `boolean` | Disabled. |

**Used by:** the panels that make something: Prompts, My Work and the Studio cards. **Pattern:** the label promises exactly what appears. **Test:** none of its own
yet.

## `FilterBadge`

**What it is for:** one chip in a filter row.

**Use it** for a single-select row (radios) or, with `multi`, a multi-select row (checkboxes). **Do
not use it** for a status label: it is a control.

Props:

| Prop | Type | Notes |
| --- | --- | --- |
| `label` | `string` | The chip's text. |
| `count` | `number` | A count beside the label. |
| `active` | `boolean` | Selected. |
| `onClick` | `() => void` | Toggle; Space and Enter work too. |
| `appearance` | `FilterBadgeAppearance` | `pink`, `purple` (default) or `orange`, the selected border colour. |
| `children` | `ReactNode` | Extra content after the label. |
| `multi` | `boolean` | Checkbox semantics instead of radio. |

**Used by:** the doc filters, Create Prompt, the Dashboard and the design groups. **Pattern:** an ARIA radio or checkbox on a div. **Test:** none of its own yet.

## `StatTiles`

**What it is for:** the row a panel's `StatTile`s sit in.

**Use it** around two or more tiles so they wrap, centre and space the same way everywhere.

Props:

| Prop | Type | Notes |
| --- | --- | --- |
| `children` | `ReactNode` | The tiles, or a tile wrapped in a `Tooltip`. |
| `className` | `string` | Merged onto the row. |

**Used by:** Milestones, Test Health and the engagement summary. **Pattern:** a layout wrapper. **Test:**
[`StatTile.test.tsx`](src/shared/StatTile.test.tsx).

## `StatTile`

**What it is for:** one boxed count: the number beside its caption.

**Use it** for a figure a person scans (items closed, tests passing). **Do not use it** for prose, or
for a count that belongs in a row's meta. It forwards its ref and spreads the rest of its props onto
the box, so a `Tooltip` can wrap one; those are plain `div` attributes and are not listed.

Props:

| Prop | Type | Notes |
| --- | --- | --- |
| `count` | `ReactNode` | The number (or `3/5`, `42%`), already formatted. |
| `label` | `ReactNode` | What it counts. |
| `color` | `string` | A health colour for the number, when the count is a verdict. |

**Used by:** Milestones, Burn, the issue report, and `ListPanel`'s lead (Test Health's figures). **Pattern:** a ref-forwarding presentational box. **Test:**
[`StatTile.test.tsx`](src/shared/StatTile.test.tsx).

## `StatusMessage`

**What it is for:** the result of an act: a success or a stated refusal, in the verb's own words.

**Use it** as a `PanelFrame` `toast`, or under a form. Success hides itself after 30 seconds; an error
stays until dismissed. **Do not use it** for a state of the page (use `EmptyState`).

Props:

| Prop | Type | Notes |
| --- | --- | --- |
| `status` | `"success" \| "error"` | Colours the box; `error` is announced as an alert. |
| `children` | `ReactNode` | The message. |
| `onDismiss` | `() => void` | Called when the person dismisses it or it hides itself. |
| `autoHideMs` | `number` | Overrides the 30 s success default; `0` never hides. |

**Used by:** Prompts, Configuration, the plan dialog and Create Prompt. **Pattern:** a dismissible live region. **Test:**
[`StatusMessage.test.tsx`](src/shared/StatusMessage.test.tsx).

## `InfoTip`

**What it is for:** a small info icon whose tooltip describes the thing beside it.

**Use it** beside a panel's title or a form section's title, in place of a helper sentence in the
body. **Do not use it** for the only copy of something a person must read.

Props:

| Prop | Type | Notes |
| --- | --- | --- |
| `content` | `ReactNode` | What the tooltip says. |
| `label` | `string` | The icon's accessible name; default `About this`. |

**Used by:** Create Prompt and the Prompts panel. **Pattern:** a keyboard-reachable description tooltip. **Test:** none of its own
yet.

## `TabRows`

**What it is for:** the one wrapper a page's in-page tab rows sit in. It owns their space, the way a
panel row owns the space around its panels.

**Use it** around every Fluent `TabList` that switches a page's views or a panel's sub-views: Home's
Focus, Board, Sprint and Actions strip, Team Agile's Standup, Triage and Releases strip, and the
Standup panel's Agenda and grain tabs. Two rows that stack go in one `TabRows`. **Do not** give the
`TabList` a className, a style or a margin: the wrapper's padding and gap are the only space.

Props:

| Prop | Type | Notes |
| --- | --- | --- |
| `children` | `ReactNode` | One tab row, or two stacked. |

What is drawn:

```html
<div class="tabRows" data-tab-rows>   <!-- column; padding-block: tabRowsPadding; row-gap: tabRowGap -->
  <!-- TabList --> <!-- TabList -->
</div>
```

| Token (`src/shell/layoutTokens.ts`) | Value | What it is |
| --- | --- | --- |
| `tabRowsPadding` | `controlRowsSpace`: `tokens.spacingVerticalM`, 12 px | Above and below the rows. The same value as the space under a list panel's filter chips, so tab rows and chip rows read as one family. |
| `tabRowGap` | `tokens.spacingVerticalS`, 8 px | Between two rows stacked in one wrapper. |

**Used by:** Home's strip (`src/modules/ado/routes.tsx`), `RitualTabs`
(`src/modules/solitaireAgile/RitualPage.tsx`) and the Standup panel. **Pattern:** a wrapper that owns
its children's spacing, so nothing inside has a margin. **Test:**
[`TabRows.test.tsx`](src/shared/TabRows.test.tsx), which also reads every source file and fails on a
`TabList` outside a `TabRows`, or one with a className or a style.

## `TAB_ROWS_CLASS`

**What it is for:** the wrapper's class name, `tabRows`, so a test or a style can find it without
retyping it. `data-tab-rows` marks the same element. **Used by:** `TabRows` and its test. **Test:**
`TabRows.test.tsx`.

## `HairlineDivider`

**What it is for:** the one-pixel rule between a panel's header and its body.

**Use it** where `PanelFrame` does not already draw one. **Do not use it** as spacing.

Props:

| Prop | Type | Notes |
| --- | --- | --- |
| `style` | `CSSProperties` | Merged over the rule's own style. |

**Used by:** the Dashboard, Test Health, Configuration and `PanelFrame`. **Pattern:** a styled `hr`. **Test:** none of its own yet.
