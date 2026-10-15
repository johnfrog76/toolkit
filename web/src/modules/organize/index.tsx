import type { ToolkitModule } from "../../shell/registry";
import { PageGrid, useShellSlot } from "../../shell/cards";
import { lazyPart } from "../../shell/lazy";
import { ROUTES } from "./paths";

// The card and the bell are chunks fetched when first drawn (shell/lazy.tsx):
// this file is the module's DESCRIPTOR and imports no component of its own.
// The bell sits in the header of every page, so its loading state is nothing
// at all -- a spinner beside the avatar would be a signal that means nothing.
const RemindersCard = lazyPart(
  () => import("./RemindersCard"),
  (m) => m.RemindersCard,
);
const ReminderBell = lazyPart(
  () => import("./ReminderBell"),
  (m) => m.ReminderBell,
  null,
);

/**
 * The Organize tab, `/organize`: the place the things a person keeps in order
 * live, laid out like any other tab -- cards in the shell's grid at half width.
 *
 * Meetings first, then Reminders. Meetings is the
 * communication module's card and arrives through the `organize` SLOT: this page
 * imports nothing of that module and does not know what the slot holds, so with
 * communication off the slot is empty and the page is Reminders alone. Each card
 * fetches its own data from the store; the page only places them.
 */
function OrganizeHome() {
  const slotCards = useShellSlot("organize");
  return (
    <PageGrid>
      {slotCards}
      <RemindersCard />
    </PageGrid>
  );
}

/**
 * The Organize add-on: where the things a person keeps in order live.
 * Reminders is its first surface, not its definition.
 *
 * Gated on `features.organize`, the engineer's flag -- what you owe yourself on
 * Thursday does not stop being owed because you switched org. Both halves or
 * neither: the same flag gives the CLI's NewReminder and Reminders. Off means
 * absent: no route, no nav entry, no card, nothing fetched.
 */
export const organizeModule: ToolkitModule = {
  id: "organize",
  feature: "organize",

  routes: [{ path: ROUTES.home, element: <OrganizeHome /> }],

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
