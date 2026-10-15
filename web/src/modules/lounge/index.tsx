/**
 * The Lounge module -- web-only, like deck: no verbs, no agent routes
 * (docs/modules/lounge.md, "Turn it on"). Gated on `features.lounge`,
 * the engineer's flag. Off means absent: no route, no nav entry, nothing
 * fetched, no bytes, and the tab is simply not there.
 *
 * The nav entry sits LAST by module order (the spec's open item, answered by
 * placement): you look up from the work, so the room stands apart from the
 * work's tabs.
 */
import type { ToolkitModule } from "../../shell/registry";
import { lazyPart } from "../../shell/lazy";

// The room is a chunk fetched when first entered (shell/lazy.tsx): this file
// is the module's DESCRIPTOR and imports no component of its own. The games,
// the skins dialog and the Face card all travel with the room.
const Lounge = lazyPart(
  () => import("./Lounge"),
  (m) => m.Lounge,
);

export const ROUTES = { home: "/lounge" } as const;

export const loungeModule: ToolkitModule = {
  id: "lounge",
  feature: "lounge",
  routes: [{ path: ROUTES.home, element: <Lounge /> }],
  nav: [
    {
      label: "Lounge",
      to: ROUTES.home,
      match: (p) => p.startsWith(ROUTES.home),
    },
  ],
};
