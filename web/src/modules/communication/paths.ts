/**
 * This module's route paths, in one place.
 *
 * They appear in four files -- the route table, the card's row links, the
 * session page's redirect after a create, and the redirects from the old growth
 * prefix -- and a path retyped at each use is a drift bug waiting for one copy
 * to be edited alone. That already happened once here: these pages moved off
 * `/growth/` and every navigate() call had to be found by hand.
 */
export const COMMUNICATION_HOME = "/communication";

export const oneOnOnePath = (filename: string) =>
  `${COMMUNICATION_HOME}/1on1/${encodeURIComponent(filename)}`;

export const sessionPath = (filename: string) =>
  `${COMMUNICATION_HOME}/sessions/${encodeURIComponent(filename)}`;

export const NEW_SESSION = `${COMMUNICATION_HOME}/sessions/new`;

/** Route patterns, as the router matches them. */
export const ROUTES = {
  home: COMMUNICATION_HOME,
  oneOnOne: `${COMMUNICATION_HOME}/1on1/:filename`,
  newSession: NEW_SESSION,
  session: `${COMMUNICATION_HOME}/sessions/:filename`,
} as const;

/** The paths these pages answered to before the module was carved out. */
export const LEGACY_ROUTES = {
  oneOnOne: "/growth/1on1/:filename",
  newSession: "/growth/sessions/new",
  session: "/growth/sessions/:filename",
} as const;
