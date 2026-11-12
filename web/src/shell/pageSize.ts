import type { CardItemSize } from "./cardItemTokens";
import { CARD_ITEM_HEIGHTS_PX } from "./cardItemTokens";
import { cardListGapPx, cardListPaddingTopPx, filterRowGapPx } from "./layoutTokens";
import { PANEL_MAX_HEIGHT_PX } from "./panelHeight";

/** How many card items a list panel shows on a page. It is never typed in a
 *  panel. At runtime it is measured: the room the list really has, divided by
 *  an item and the list's gap (`pageSizeForRoom`), so a full page always fits
 *  and nothing scrolls or is cut off, whatever sits above the list. The sum
 *  below (`listPageSize`) is the same answer worked out from the tokens, for
 *  the first paint and wherever there is no layout to measure. */
export type ListDensity = CardItemSize;

/** One item's share of the body, in px: its height and the list's gap. */
export const LIST_ITEM_PITCH_PX: Record<ListDensity, number> = {
  full: CARD_ITEM_HEIGHTS_PX.full + cardListGapPx.full,
  compact: CARD_ITEM_HEIGHTS_PX.compact + cardListGapPx.compact,
  line: CARD_ITEM_HEIGHTS_PX.line + cardListGapPx.line,
};

/** What a list of `count` items takes, in px: the space over the first, the
 *  items, and the gaps between them. */
export function listHeightPx(density: ListDensity, count: number): number {
  if (count === 0) return 0;
  return (
    cardListPaddingTopPx[density] +
    count * CARD_ITEM_HEIGHTS_PX[density] +
    (count - 1) * cardListGapPx[density]
  );
}

/** What a list panel's chrome takes of its height, in px, measured in the
 *  browser. `frame` is what every list panel has: the frame's padding (12 top
 *  and bottom), the header (24), its hairline (1), the foot row with the pager
 *  (32), and the three 12 px gaps between those and the body. */
export const LIST_CHROME_PX = {
  frame: 117,
  /** One row of filter chips. Two rows have `filterRowGap` between them. */
  filterRow: 26,
  /** A lead chart (152), with the hairline under it. */
  lead: 153,
  /** One line under the foot row (20), and the gap above it. */
  footNote: 32,
  /** A status line above the items, while one is shown. */
  status: 48,
} as const;

/** The chrome a panel has, as the kind counts it. */
export interface ListChrome {
  density: ListDensity;
  filterRows?: number;
  lead?: boolean;
  footNote?: boolean;
  status?: boolean;
}

/** The height, in px, a panel's chrome takes. */
export function listChromePx(chrome: ListChrome): number {
  const rows = chrome.filterRows ?? 0;
  return (
    LIST_CHROME_PX.frame +
    rows * LIST_CHROME_PX.filterRow +
    Math.max(0, rows - 1) * filterRowGapPx +
    (chrome.lead ? LIST_CHROME_PX.lead : 0) +
    (chrome.footNote ? LIST_CHROME_PX.footNote : 0) +
    (chrome.status ? LIST_CHROME_PX.status : 0)
  );
}

/** How many items fit on a page under that chrome: at least one. */
export function listPageSize(chrome: ListChrome): number {
  const room = PANEL_MAX_HEIGHT_PX.list - listChromePx(chrome);
  let count = 1;
  while (listHeightPx(chrome.density, count + 1) <= room) count += 1;
  return count;
}

/** How many items fit in `room` px of list, measured: at least one. The room
 *  holds n items and the n - 1 gaps between them. */
export function pageSizeForRoom(density: ListDensity, room: number): number {
  const item = CARD_ITEM_HEIGHTS_PX[density];
  const gap = cardListGapPx[density];
  return Math.max(1, Math.floor((room + gap) / (item + gap)));
}

/** The page of full items most list panels have: under one filter row. */
export const LIST_PAGE_SIZE = listPageSize({ density: "full", filterRows: 1 });
