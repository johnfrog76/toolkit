/** A panel's MINIMUM height, in px, by kind, on a wide page. A panel has no
 *  fixed height: it is as tall as what it holds and never less than this, so
 *  short panels line up and an empty one does not collapse. This file is about
 *  panels only -- a card item's height is in cardItemTokens.ts. */
export const PANEL_MIN_HEIGHT_PX = {
  list: 592,
  status: 592,
  /** Two stat panels stack beside one list panel, across the 16 px grid gap. */
  stat: 288,
  chart: 592,
  scene: 592,
} as const;

/** The kinds a panel can be. */
export type PanelKind = keyof typeof PANEL_MIN_HEIGHT_PX;

/** The page width above which the grid has two columns and a panel takes its
 *  minimum height. Below it the panels stack and are as tall as their items. */
export const PANEL_GRID_MIN_WIDTH_PX = 900;

/** A panel's MAXIMUM height, in px, for the kinds that have one. A list panel
 *  is exactly its minimum on a wide page: its page of items is sized to fit, so
 *  nothing scrolls and nothing is cut off. The other kinds have a floor only. */
export const PANEL_MAX_HEIGHT_PX = {
  list: PANEL_MIN_HEIGHT_PX.list,
} as const;

/** How a panel with a maximum height holds more than fits. Exactly two forms,
 *  chosen by the kind: `paged` -- card items, a page at a time, the pager at
 *  the foot -- or `scroll` -- a body that is one block, in PanelFrame's
 *  `scrollable` area, the header and foot fixed. */
export type PanelBody = "paged" | "scroll";

/** Each capped kind's form. A kind with a maximum height has an entry. */
export const PANEL_BODY: Record<keyof typeof PANEL_MAX_HEIGHT_PX, PanelBody> = {
  list: "paged",
};

/** A panel's slots, in the order a panel reads: named once, here. Each is
 *  filled, today, by these PanelFrame props:
 *    header  -- `headerLeft`: the icon and the title;
 *    info    -- `headerLeft` too: the info icon after the title;
 *    actions -- `headerRight`: the pickers, search, refresh and the count;
 *    filters -- the top of `body`: the chip rows a list panel draws;
 *    body    -- `body` (or children, the default slot): what the panel holds,
 *               a list panel's card list or a block kind's content;
 *    foot    -- `footerLeft`, `footerCenter`, `footerRight`, and `footNote`
 *               under them. */
export const PANEL_SLOTS = ["header", "info", "actions", "filters", "body", "foot"] as const;

/** The name of one slot. */
export type PanelSlot = (typeof PANEL_SLOTS)[number];
