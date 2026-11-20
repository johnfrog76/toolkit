/** This module's route paths, in one place (see communication/paths.ts for why). */
export const ORGANIZE_HOME = "/organize";
export const REFERENCE_HOME = `${ORGANIZE_HOME}/reference`;

export const ROUTES = {
  home: ORGANIZE_HOME,
  reference: REFERENCE_HOME,
  referenceDoc: `${REFERENCE_HOME}/:name`,
} as const;

/** One reference document's reading room, by its file name. */
export function referencePath(name: string): string {
  return `${REFERENCE_HOME}/${encodeURIComponent(name)}`;
}

/** Router state that opens the Reminders card on one bucket -- the header bell
 *  sends `overdue`. State rather than a query string: the choice is the card's
 *  remembered filter from then on, and an address that re-applied it on every
 *  reload would fight the person who changed it. */
export const REMINDERS_BUCKET_STATE = "remindersBucket";
