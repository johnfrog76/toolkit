import type { ToolkitModule } from "../../shell/registry";
import { lazyPart } from "../../shell/lazy";
import { ROUTES } from "./paths";

// The pages are chunks fetched when first drawn (shell/lazy.tsx): this file is
// the module's DESCRIPTOR and imports no component of its own.
// Standup, Triage and Milestones share one chunk: the tab's Standup | Triage |
// Milestones strip and the page under it. StandupPage itself is drawn unchanged
// inside it; the award dialog and its confetti are a chunk of their own.
const RitualPage = lazyPart(
  () => import("./RitualPage"),
  (m) => m.RitualPage,
);
// The played view: the stage, the generated deck and the deck ENGINE are one
// chunk, fetched when Play is pressed -- whether or not features.deck is on.
const StandupPlay = lazyPart(
  () => import("./stage/StandupPlay"),
  (m) => m.StandupPlay,
);
const StandupRemindSettings = lazyPart(
  () => import("./StandupRemindSettings"),
  (m) => m.StandupRemindSettings,
);

/**
 * Solitaire Agile (docs/modules/solitaire-agile.md): the team's
 * ceremonies, derived from the tracker and keeping no state of their own
 * (D-TA2). M0 is today's standup as TEXT (D-SA1) -- the agent's standup route
 * renders it, the same string the CLI's `Standup` prints, and the page shows
 * it verbatim with the issue numbers linked. V1 PLAYS it: the Play
 * control opens the same standup on the Remote Standup's stage, an audiobook
 * deck on the deck module's engine.
 *
 * Gated on `features.solitaireAgile`, the engineer's flag. Both halves or
 * neither -- the same flag gives the CLI's `Standup`. Off means absent: no
 * route, no nav entry, nothing fetched, no bytes.
 *
 * Its nav entry sits after the Studio's and before the Lounge's: a working
 * room, and the Lounge stays last by module order.
 *
 * Triage is the tab's second page, under a Standup | Triage strip: the
 * open issues one at a time, unplaced first, each answer the CLI's `Route`
 * through the bridge -- the module's first write, to the tracker (a card with no
 * issue behind it takes one **Assigned:** line, through the same verb).
 *
 * Milestones is the third: one row per tracker milestone with its bar, and
 * the award dialog when one is reached -- the module's one confetti
 * (docs/modules/solitaire-agile.md, "Milestones: the tab and the award").
 *
 * Its settings section is the reminder to attend (D-TA15): a time and
 * the days, saved as `Standup -Remind` through the bridge. The reminder is
 * Organize's, so the row needs `features.organize` and says so without it.
 */
export const solitaireAgileModule: ToolkitModule = {
  id: "solitaireAgile",
  feature: "solitaireAgile",
  routes: [
    { path: ROUTES.home, element: <RitualPage ceremony="standup" /> },
    { path: ROUTES.triage, element: <RitualPage ceremony="triage" /> },
    { path: ROUTES.milestones, element: <RitualPage ceremony="milestones" /> },
    { path: ROUTES.play, element: <StandupPlay /> },
  ],
  nav: [
    {
      label: "Team Agile",
      to: ROUTES.home,
      match: (p) => p.startsWith(ROUTES.home),
    },
  ],
  // A played ritual is a room of its own, like any deck: no nav bar.
  chromeless: (pathname) => pathname === ROUTES.play,
  // The anchor it marks, `standup.remind`, is where the "How do I…" entry
  // "Can it remind me to attend?" opens the drawer (Config/settings-workflows.json).
  settingsSections: () => [<StandupRemindSettings key="solitaireAgile.remind" />],
};
