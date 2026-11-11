/** The height, in px, of a card that holds a fixed-size list on a wide page.
 *  It is the height a Focus card settles at once its rows are drawn, written
 *  here once so every card that wants to line up with the Focus cards reads
 *  the same number. */
export const LIST_CARD_HEIGHT_PX = 592;

/** The page width above which the grid has two columns, and a list card takes
 *  the fixed height. Below it the cards stack and grow with their rows. */
export const LIST_CARD_MIN_WIDTH_PX = 900;
