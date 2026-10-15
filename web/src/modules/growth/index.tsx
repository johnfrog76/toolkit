import type { ToolkitModule } from "../../shell/registry";
import { lazyPart } from "../../shell/lazy";

// Every page and card is a chunk fetched when first drawn (shell/lazy.tsx):
// this file is the module's DESCRIPTOR, and imports no component of its own.
const GrowthPage = lazyPart(
  () => import("./GrowthPage"),
  (m) => m.GrowthPage,
);
const GoalDetailPage = lazyPart(
  () => import("./GoalDetailPage"),
  (m) => m.GoalDetailPage,
);
const SkillsPage = lazyPart(
  () => import("./SkillsPage"),
  (m) => m.SkillsPage,
);

/**
 * The growth module -- training, presentations, goals, and the career record
 * those feed: reviews and the resume.
 *
 * Opt-in, and the flag is the ENGINEER's rather than an org's. Growth data
 * spans engagements, so switching from an active org to an archived one must
 * not make this appear and disappear; `features.growth` is therefore read from
 * the top-level block and not from `orgs[]`.
 *
 * No home cards. The two cards this module owns that a home page wants --
 * ReviewArchive and SkillsSnapshot -- are exported below and imported by the
 * ADO module's archive-mode home (ADO spec S8.4). A module may import another
 * module's card; it may not fork one. They render there only when this module
 * is active, because that import is what the registry gates -- and they are
 * lazy parts like the pages, so importing them costs the core no bytes.
 */
export const growthModule: ToolkitModule = {
  id: "growth",
  feature: "growth",

  routes: [
    { path: "/growth", element: <GrowthPage /> },
    { path: "/growth/goals/:filename", element: <GoalDetailPage /> },
    { path: "/skills", element: <SkillsPage /> },
  ],

  nav: [
    {
      label: "Growth",
      to: "/growth",
      match: (p) => p.startsWith("/growth") || p === "/skills",
    },
  ],
};

export const ReviewArchive = lazyPart(
  () => import("./ReviewArchive"),
  (m) => m.ReviewArchive,
);
export const SkillsSnapshot = lazyPart(
  () => import("./SkillsSnapshot"),
  (m) => m.SkillsSnapshot,
);
