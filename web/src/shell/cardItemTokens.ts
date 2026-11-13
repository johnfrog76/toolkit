/** A card item's tokens: one entry inside a list panel. Every length inside an
 *  item is named here, and each size's height is worked out from them, so
 *  changing a padding or a band changes the height with it. Never mixed with
 *  the panel heights (panelHeight.ts) or the space between items, which is the
 *  list's (layoutTokens.ts). */

/** The item sizes a list panel chooses between, for all of its items at once:
 *  `full` (title, description, meta), `compact` (title, meta) and `line` (one
 *  band). A single item never chooses. */
export type CardItemSize = "full" | "compact" | "line";

/** The item's outline, in px, on each edge. A line item has a rule under it only. */
export const CARD_ITEM_BORDER_PX = 1;

/** The item's vertical padding, in px: ONE value for the top and the bottom of
 *  a full and a compact item, so the space under the last band is the space
 *  over the first. It is Fluent's `tokens.spacingVerticalM`, which the item's
 *  styles use; this is the same length as a number, for the height sums, and a
 *  test holds the two equal. */
export const CARD_ITEM_PADDING_Y_PX = 12;

/** The title band, in px: one line. It is the title's line height and the
 *  height of the controls beside it, so the band holds no slack. */
export const CARD_ITEM_TITLE_BAND_PX = 24;

/** How many lines a card item's title is clamped to. */
export const CARD_ITEM_TITLE_LINES = 1;

/** One line of the description, in px. */
export const CARD_ITEM_DESCRIPTION_LINE_PX = 15;

/** How many lines a card item's description is clamped to. */
export const CARD_ITEM_DESCRIPTION_LINES = 2;

/** The description band, in px: its lines, and nothing more. */
export const CARD_ITEM_DESCRIPTION_BAND_PX =
  CARD_ITEM_DESCRIPTION_LINES * CARD_ITEM_DESCRIPTION_LINE_PX;

/** The meta band, in px: the height of a small badge and of a caption line, so
 *  the band holds no slack under the badges. */
export const CARD_ITEM_META_BAND_PX = 16;

/** The width, in px, of the small picture in the meta band; it is 16:10, so it
 *  stands inside the band. */
export const CARD_ITEM_THUMB_WIDTH_PX = 24;

/** The width, in px, of the progress bar in the meta band. */
export const CARD_ITEM_PROGRESS_WIDTH_PX = 64;

/** The space between a compact item's two bands, in px: Fluent's
 *  `tokens.spacingVerticalS`, which the item's styles use; this is its number,
 *  for the height sums. A full item's title and description touch; its meta band
 *  sits CARD_ITEM_META_GAP_PX under the description. */
export const CARD_ITEM_COMPACT_BAND_GAP_PX = 8;

/** The space between a full item's description band and its meta band, in px:
 *  Fluent's `tokens.spacingVerticalS`, which the item's grid uses for that
 *  track; this is its number, for the height sums. It is the same 8 px as the
 *  gap between two card items, so the meta row has the same room under a
 *  two-line description as under a one-line one. */
export const CARD_ITEM_META_GAP_PX = 8;

/** A line item's one band, in px, the rule under it included. A line item has
 *  no padding over or under it: the band is the item. */
export const CARD_ITEM_LINE_BAND_PX = 28;

const FRAME_PX = 2 * CARD_ITEM_BORDER_PX + 2 * CARD_ITEM_PADDING_Y_PX;

/** The height, in px, of a full card item: its outline, its padding, its three
 *  bands and the gap over the meta band. */
export const CARD_ITEM_HEIGHT_PX =
  FRAME_PX +
  CARD_ITEM_TITLE_BAND_PX +
  CARD_ITEM_DESCRIPTION_BAND_PX +
  CARD_ITEM_META_GAP_PX +
  CARD_ITEM_META_BAND_PX;

/** The height, in px, of a compact card item: the title band and the meta
 *  band, for a panel whose items never have a description. */
export const CARD_ITEM_COMPACT_HEIGHT_PX =
  FRAME_PX + CARD_ITEM_TITLE_BAND_PX + CARD_ITEM_COMPACT_BAND_GAP_PX + CARD_ITEM_META_BAND_PX;

/** The height, in px, of a line card item: one band. */
export const CARD_ITEM_LINE_HEIGHT_PX = CARD_ITEM_LINE_BAND_PX;

/** Each size's height, by name. */
export const CARD_ITEM_HEIGHTS_PX: Record<CardItemSize, number> = {
  full: CARD_ITEM_HEIGHT_PX,
  compact: CARD_ITEM_COMPACT_HEIGHT_PX,
  line: CARD_ITEM_LINE_HEIGHT_PX,
};
