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

- **Panel** -- one framed box on a page, drawn by `PageCard`: a header, a body, a footer. What a person
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

Shared pieces are in `src/shared/`, with `lazyPart` in `src/shell/`. A module imports from them; they
import from no module. Props are always an exported, named type, never an inline literal, never `any`,
never an index signature, and never `ComponentProps<typeof X>` standing in for a real type. A lint
rule (`@typescript-eslint/no-explicit-any` as an error under `src/shell/` and `src/shared/`) holds
the first of those.

## `PageCard`

**What it is for:** the one frame a panel is drawn in.

**Use it** for every panel: it gives the header with its rule, the body (a spinner, an empty message,
or the children), the toast, and the footer with its three slots. **Do not use it** for a list entry
inside a panel (that is a card item), and do not set a height on it from outside.

Props:

| Prop | Type | Notes |
| --- | --- | --- |
| `headerLeft` | `ReactNode` | Title side of the header. |
| `headerRight` | `ReactNode` | Actions side: search, refresh, count. |
| `children` | `ReactNode` | The body. |
| `toast` | `ReactNode` | A `StatusMessage` under the body; hidden while loading. |
| `footer` | `ReactNode` | A single footer cell, used only when no footer slot is set. |
| `footerLeft` | `ReactNode` | Footer, left: usually a sentence. |
| `footerCenter` | `ReactNode` | Footer, middle: the pager. Keeps its width on one line. |
| `footerRight` | `ReactNode` | Footer, right: usually a `CreateButton`. |
| `footNote` | `ReactNode` | One line under the footer, the width of the card. |
| `scrollable` | `boolean` | Body scrolls inside the panel. |
| `loading` | `boolean` | Draws the spinner instead of the body, toast and footer. |
| `loadingLabel` | `string` | The spinner's label; default `Loading...`. |
| `empty` | `ReactNode` | Replaces the body; hand it an `EmptyState`. |
| `className` | `string` | Merged onto the card. |

**Used by:** nearly every panel: Active Cards, My Work, Prompts and the Studio panels.

**Pattern:** a slot-based frame (header, body, footer) that sets no height; each panel's height is its
own. **Test:** [`PageCard.footer.test.tsx`](src/shared/PageCard.footer.test.tsx) (the footer's centre
slot only).

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

**Use it** as `PageCard`'s `empty` slot, or on its own where there is no `PageCard`. Three tones that
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

**Used by:** Milestones, Burn, the issue report and Test Health. **Pattern:** a ref-forwarding presentational box. **Test:**
[`StatTile.test.tsx`](src/shared/StatTile.test.tsx).

## `StatusMessage`

**What it is for:** the result of an act: a success or a stated refusal, in the verb's own words.

**Use it** as a `PageCard` `toast`, or under a form. Success hides itself after 30 seconds; an error
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

## `HairlineDivider`

**What it is for:** the one-pixel rule between a panel's header and its body.

**Use it** where `PageCard` does not already draw one. **Do not use it** as spacing.

Props:

| Prop | Type | Notes |
| --- | --- | --- |
| `style` | `CSSProperties` | Merged over the rule's own style. |

**Used by:** the Dashboard, Test Health, Configuration and `PageCard`. **Pattern:** a styled `hr`. **Test:** none of its own yet.
