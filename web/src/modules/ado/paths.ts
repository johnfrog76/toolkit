/**
 * The card page's address, in one place. The board, the list, a design's bound
 * cards and a reminder's ref all open a card, and each used to type the path.
 * The card page reads the active Space's current/, so the address is keyed by
 * the card's filename there.
 */
export const CARD_ROUTE = "/prompts/:filename";

/** The System page: the Environment card, where the hub is synced. */
export const SYSTEM_PATH = "/system";

export const cardPath = (file: string) => `/prompts/${encodeURIComponent(file)}`;
