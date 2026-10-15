/** This module's route paths, in one place (see communication/paths.ts for why). */
export const ORGANIZE_HOME = "/organize";

export const ROUTES = {
  home: ORGANIZE_HOME,
} as const;

/** Router state that opens the Reminders card on one bucket -- the header bell
 *  sends `overdue`. State rather than a query string: the choice is the card's
 *  remembered filter from then on, and an address that re-applied it on every
 *  reload would fight the person who changed it. */
export const REMINDERS_BUCKET_STATE = "remindersBucket";
