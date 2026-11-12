import { tokens } from "@fluentui/react-components";
import type { CardItemSize } from "./cardItemTokens";

/** The space between things: one rule at every level -- spacing comes only
 *  from the wrapper's gap, never from a margin on the thing wrapped. A card
 *  item has no margin, and neither does a panel; the list that holds the items
 *  sets the gap between them. This file is where each wrapper's gap is named,
 *  from the page down: the page's rows, a row's panels, a list's items, a
 *  panel's filter rows.
 *
 *  Every spacing value in the panel layer is one of Fluent's spacing tokens,
 *  on the 4 px grid (XS 4, S 8, M 12, L 16...). The styles use the token; the
 *  number beside it is the same length for the height sums, and a test holds
 *  each pair equal. */

/** The gap between two rows of panels on a page: the page wrapper's. A Fluent
 *  spacing token, and a multiple of 4 px. */
export const pageRowGap = tokens.spacingVerticalL;

/** The gap between the panels in one row, side by side or stacked: the row's.
 *  A Fluent spacing token, and a multiple of 4 px. */
export const panelGap = tokens.spacingHorizontalL;

/** The gap between two card items in a list panel's list, by item size. */
export const cardListGap: Record<CardItemSize, string> = {
  full: tokens.spacingVerticalXS,
  compact: tokens.spacingVerticalS,
  line: "0",
};

/** `cardListGap`, in px, for the sums. */
export const cardListGapPx: Record<CardItemSize, number> = { full: 4, compact: 8, line: 0 };

/** The space over the first item, by item size: one gap, so the list sits off
 *  the filter chips or the header as its items sit off each other. */
export const cardListPaddingTop: Record<CardItemSize, string> = { ...cardListGap };

/** `cardListPaddingTop`, in px, for the sums. */
export const cardListPaddingTopPx: Record<CardItemSize, number> = { ...cardListGapPx };

/** The gap between two rows of filter chips in a panel's filters. A gap spaces
 *  a row only when it is drawn, so the space comes and goes with the row. */
export const filterRowGap = tokens.spacingVerticalXS;

/** `filterRowGap`, in px, for the sums. */
export const filterRowGapPx = 4;

/** The breathing room around a panel's or a page's rows of controls -- tab rows
 *  and filter-chip rows alike, one value so they read as one family: the space
 *  below the rows matches the space above them. A Fluent spacing token, and a
 *  multiple of 4 px. */
export const controlRowsSpace = tokens.spacingVerticalM;

/** `controlRowsSpace`, in px. */
export const controlRowsSpacePx = 12;

/** The space above and below a page's tab rows: the tab-row wrapper's
 *  (`TabRows`, shared/TabRows.tsx), top and bottom. */
export const tabRowsPadding = controlRowsSpace;

/** `tabRowsPadding`, in px. */
export const tabRowsPaddingPx = controlRowsSpacePx;

/** The space under a list panel's filter chips, before what follows them. The
 *  space above is the frame's own gap under the header rule, the same 12 px;
 *  the list under the chips drops its own top padding, so the chips sit
 *  centred between the rule and the first item. */
export const filtersSpaceBelow = controlRowsSpace;

/** `filtersSpaceBelow`, in px. */
export const filtersSpaceBelowPx = controlRowsSpacePx;

/** The gap between two tab rows stacked in one wrapper. A Fluent spacing token,
 *  and a multiple of 4 px. */
export const tabRowGap = tokens.spacingVerticalS;

/** `tabRowGap`, in px. */
export const tabRowGapPx = 8;
