import type { CardItemSize } from "./cardItemTokens";

/** The space between things: one rule at every level -- spacing comes only
 *  from the wrapper's gap, never from a margin on the thing wrapped. A card
 *  item has no margin, and neither does a panel; the list that holds the items
 *  sets the gap between them. This file is where each wrapper's gap is named. */

/** The gap between two card items in a list panel's list, in px, by item size. */
export const cardListGap: Record<CardItemSize, number> = { full: 3, compact: 8, line: 0 };

/** The space over the first item, in px, by item size: one gap, so the list
 *  sits off the filter chips or the header as its items sit off each other. */
export const cardListPaddingTop: Record<CardItemSize, number> = { ...cardListGap };
