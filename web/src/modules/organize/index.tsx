import type { ToolkitModule } from "../../shell/registry";
import { lazyPart } from "../../shell/lazy";
import { ROUTES } from "./paths";

// The pages and the bell are chunks fetched when first drawn (shell/lazy.tsx):
// this file is the module's DESCRIPTOR and imports no component of its own.
// The bell sits in the header of every page, so its loading state is nothing
// at all -- a spinner beside the avatar would be a signal that means nothing.
const OrganizeHome = lazyPart(
  () => import("./OrganizePages"),
  (m) => m.OrganizeHome,
);
const OrganizeReference = lazyPart(
  () => import("./OrganizePages"),
  (m) => m.OrganizeReference,
);
const ReferencePage = lazyPart(
  () => import("./ReferencePage"),
  (m) => m.ReferencePage,
);
const ReminderBell = lazyPart(
  () => import("./ReminderBell"),
  (m) => m.ReminderBell,
  null,
);

/**
 * The Organize add-on: where the things a person keeps in order live.
 * Reminders is its first surface and Reference its second, not its definition;
 * the tab holds both under in-page tabs (OrganizePages.tsx).
 *
 * Gated on `features.organize`, the engineer's flag -- what you owe yourself on
 * Thursday does not stop being owed because you switched org. Both halves or
 * neither: the same flag gives the CLI's NewReminder and Reminders and the
 * agent's reference routes. Off means absent: no route, no nav entry, no card,
 * nothing fetched.
 */
export const organizeModule: ToolkitModule = {
  id: "organize",
  feature: "organize",

  routes: [
    { path: ROUTES.home, element: <OrganizeHome /> },
    { path: ROUTES.reference, element: <OrganizeReference /> },
    // One document's reading room, a page of its own like a card's.
    { path: ROUTES.referenceDoc, element: <ReferencePage /> },
  ],

  nav: [
    {
      label: "Organize",
      to: ROUTES.home,
      match: (p) => p.startsWith(ROUTES.home),
    },
  ],

  // The bell: past-due reminders, counted on every page. A click comes here.
  headerItems: () => [<ReminderBell key="organize-bell" />],

  // No home or system cards. Other modules' cards reach this page through the
  // `organize` slot -- today the Meetings card, when communication is on.
};
