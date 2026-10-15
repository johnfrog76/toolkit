import type { ToolkitModule } from "../../shell/registry";
import { lazyPart } from "../../shell/lazy";
import { ROUTES } from "./paths";

// The pages are chunks fetched when first drawn (shell/lazy.tsx): this file is
// the module's DESCRIPTOR and imports no component of its own. Lazy is about
// bytes, not about being optional -- the Studio is always mounted, and its
// pages still arrive only when someone opens the tab.
const StudioPage = lazyPart(
  () => import("./StudioPage"),
  (m) => m.StudioPage,
);
const DesignNotePage = lazyPart(
  () => import("./DesignNotePage"),
  (m) => m.DesignNotePage,
);
const PromptPage = lazyPart(
  () => import("./PromptPage"),
  (m) => m.PromptPage,
);

/**
 * The Studio (docs/modules/studio.md): the studio developer's view across
 * their products. The foyer is one row per Space, read from the routes the core
 * already has -- never a merged backlog (D-G11, D-S2). A row is a switch into
 * that Space.
 *
 * Core, from day one (D-S13, amending D-S1): there is no `feature` here,
 * so the registry always mounts it, the way it mounts the cards. A
 * `features.studio` line left in a machine's config is ignored.
 *
 * Its nav entry sits before Team Agile's and the Lounge's: a working room, and
 * the Lounge stays last by module order. Under the foyer, the seed drawer: the
 * hub's design/ notes (D-S3), each a reading room at /studio/design/:name; and
 * the Prompts card, each prompt a reading room at /studio/prompts/:ref.
 */
export const studioModule: ToolkitModule = {
  id: "studio",
  routes: [
    { path: ROUTES.home, element: <StudioPage /> },
    { path: ROUTES.note, element: <DesignNotePage /> },
    { path: ROUTES.prompt, element: <PromptPage /> },
  ],
  nav: [
    {
      label: "Studio",
      to: ROUTES.home,
      match: (p) => p.startsWith(ROUTES.home),
    },
  ],
};
