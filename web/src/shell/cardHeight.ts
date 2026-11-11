/** The MINIMUM height, in px, of a card that holds a list on a wide page: the
 *  height a Focus card settles at once its rows are drawn, written here once
 *  so every card that wants to line up with the Focus cards reads the same
 *  number. A card taller than this grows to fit; it is never clipped. */
export const LIST_CARD_HEIGHT_PX = 592;

/** The page width above which the grid has two columns, and a list card takes
 *  the fixed height. Below it the cards stack and grow with their rows. */
export const LIST_CARD_MIN_WIDTH_PX = 900;

/** How many items a list card shows on a page. One setting every list card
 *  reads; a page 2 appears only past it. */
export const LIST_PAGE_SIZE = 5;

/** The height, in px, of one Studio list item: a one-line title, two clamped
 *  lines of description and the badge line, measured in the browser. */
export const LIST_ITEM_HEIGHT_PX = 80;
