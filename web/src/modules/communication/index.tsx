import { Navigate, useParams } from "react-router";
import type { ToolkitModule } from "../../shell/registry";
import { PageGrid } from "../../shell/cards";
import { useGetEnvQuery } from "../../shell/api";
import { lazyPart } from "../../shell/lazy";

// The pages and the card are chunks fetched when first drawn (shell/lazy.tsx):
// this file is the module's DESCRIPTOR and imports no component of its own.
const OneOnOne = lazyPart(
  () => import("./OneOnOne"),
  (m) => m.OneOnOne,
);
const ManagerDetailPage = lazyPart(
  () => import("./ManagerDetailPage"),
  (m) => m.ManagerDetailPage,
);
const ManagerSessionPage = lazyPart(
  () => import("./ManagerSessionPage"),
  (m) => m.ManagerSessionPage,
);
import { LEGACY_ROUTES, NEW_SESSION, ROUTES, oneOnOnePath, sessionPath } from "./paths";

/**
 * The card needs somewhere to live now that it has left the growth page.
 *
 * A one-card page is the smallest thing that keeps it reachable without
 * borrowing another module's route, and it is what the `Meetings` nav entry points
 * at. It contributes no home card on purpose: a 1:1 workflow is something you
 * go to, not something that should appear on the home screen of an install that
 * happens to have the flag on.
 */
function OneOnOneHome() {
  // With Organize on, Meetings lives on the Organize tab (the slot below), so
  // this page sends its visitors there -- one place for the card, and an old
  // bookmark still lands on it. With Organize off it is the page, as it was.
  const { data: env } = useGetEnvQuery();
  if (env?.features?.organize === true) return <Navigate to={ORGANIZE_TAB} replace />;
  return (
    <PageGrid>
      <OneOnOne />
    </PageGrid>
  );
}

/** Where the Organize add-on draws its tab. A path, not an import: this module
 *  knows the page exists, never what is on it (the slot is the whole contract). */
const ORGANIZE_TAB = "/organize";

/**
 * The old paths, kept working.
 *
 * These pages lived under /growth/ because 1:1s used to be part of that module.
 * Leaving them there would file them under a URL the growth module no longer
 * serves; moving them without a redirect would break every bookmark. Three
 * lines is a cheap price for neither.
 *
 * The filename has to be forwarded by hand -- a <Navigate> cannot read a route
 * parameter for you -- which is why these are components rather than plain
 * redirect entries.
 */
function RedirectToOneOnOne() {
  const { filename } = useParams<{ filename: string }>();
  return <Navigate to={oneOnOnePath(filename ?? "")} replace />;
}

function RedirectToSession() {
  const { filename } = useParams<{ filename: string }>();
  return <Navigate to={sessionPath(filename ?? "")} replace />;
}

/**
 * The communication module: manager 1:1s and the Teams engine.
 *
 * Gated on `features.communication`, which is the engineer's flag and holds
 * across orgs -- a 1:1 history spans engagements, so switching from an active
 * org to an archived one must not make this module disappear.
 *
 * Off means absent: no route, no nav entry, no card, no data fetched, and --
 * since the pages became lazy parts -- no bytes: this descriptor is all
 * the bundle carries of the module until a page or the card is drawn.
 */
export const communicationModule: ToolkitModule = {
  id: "communication",
  feature: "communication",

  routes: [
    { path: ROUTES.home, element: <OneOnOneHome /> },
    { path: ROUTES.oneOnOne, element: <ManagerDetailPage /> },
    { path: ROUTES.newSession, element: <ManagerSessionPage /> },
    { path: ROUTES.session, element: <ManagerSessionPage /> },

    // Bookmarks from when these lived in growth.
    { path: LEGACY_ROUTES.oneOnOne, element: <RedirectToOneOnOne /> },
    { path: LEGACY_ROUTES.newSession, element: <Navigate to={NEW_SESSION} replace /> },
    { path: LEGACY_ROUTES.session, element: <RedirectToSession /> },
  ],

  nav: [
    {
      // "Meetings", not "1:1s" (renamed): it is what the page's own card
      // has always been titled, and MeetingAgenda -Type covers any recurring
      // meeting, not only the manager 1:1.
      label: "Meetings",
      to: ROUTES.home,
      match: (p) => p.startsWith(ROUTES.home),
      // Under the Organize tab when there is one; a tab of its own when there
      // is not -- the deck launcher's shape under Growth (the owner:
      // "meetings and reminders live in /organize").
      hidden: (ctx) => ctx.env?.features?.organize === true,
    },
  ],

  // The Meetings card on the Organize page, when features.organize is on. The
  // Organize page renders the slot and imports nothing of this module; with
  // organize off the slot is simply unused and the card keeps its own page.
  slotCards: { organize: () => [<OneOnOne key="meetings" />] },

  // No home cards and no system cards. Nothing about a 1:1 belongs on a page
  // someone opens to see what needs doing today.
};
