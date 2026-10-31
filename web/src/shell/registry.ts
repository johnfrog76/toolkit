import { useCallback } from "react";
import type { ReactElement } from "react";
import { useDispatch } from "react-redux";
import { matchPath } from "react-router";
import type { RouteObject } from "react-router";
import type { EnvStatus } from "./api";
import { adoModule } from "../modules/ado";
import { growthModule } from "../modules/growth";
import { communicationModule } from "../modules/communication";
import { deckModule } from "../modules/deck";
import { organizeModule } from "../modules/organize";
import { studioModule } from "../modules/studio";
import { solitaireAgileModule } from "../modules/solitaireAgile";
import { loungeModule } from "../modules/lounge";

// App.tsx needs the union of work-item and prompt states for CardContext's
// stateOptions, and it needs it while building that context during its own
// render -- before any module route has mounted, so there is no module
// component running yet to derive it from. That still means calling these two
// RTK Query hooks from the shell; what changed
// is WHERE the shell reaches for them. Re-exported here, so the registry stays
// the one import path from the shell into a module -- App.tsx imports these
// from "./registry", never from "../modules/ado/api.ado" directly. The drawer's
// The "How do you want to work in <Space>?" answers write through the one config writer the
// same way, so HowDoI.tsx reaches it here too.
export {
  useGetWorkItemsQuery,
  useGetStatusQuery,
  useWriteConfigMutation,
} from "../modules/ado/api.ado";

/**
 * The orchestrating answer's follow-up (docs/modules/studio.md, "HowWeWork"):
 * after "With agents" is set, the Space's how-we-work note is written through
 * the bridge unless the Prompts listing already carries it. The Studio's file
 * that does it is imported when this is called, never with the shell, so the
 * Studio's endpoints still arrive only when they are needed.
 */
export function useWriteHowWeWork() {
  const dispatch = useDispatch();
  return useCallback(
    async (slug: string) => {
      const { writeHowWeWorkWith } = await import("../modules/studio/howWeWork");
      return writeHowWeWorkWith(dispatch as Parameters<typeof writeHowWeWorkWith>[0], slug);
    },
    [dispatch],
  );
}

/**
 * The tuple the home/system card builders close over. It is exactly what
 * App.tsx used to hold in local state before the branching moved behind this
 * registry -- filter text, the state dropdown and its options, the active repo
 * tag and the active skill tag -- plus the /env payload every card gates on.
 */
export interface CardContext {
  env: EnvStatus | undefined;
  filterValue: string;
  stateFilter: string;
  stateOptions: string[];
  activeRepo: string | null;
  /** A card type, "Untyped", or "All" -- the filter drawer's type row. */
  typeFilter: string;
  /** "Linked", "Custom", or "All" -- the filter drawer's linkedness row. */
  linkFilter: string;
  activeSkillTag: string | null;
  setActiveSkillTag: (update: (prev: string | null) => string | null) => void;
}

export interface NavEntry {
  label: string;
  to: string;
  match: (path: string) => boolean;
  /**
   * Not in the original sketch of this interface, and added because the one
   * nav entry that is conditional -- Daily, which an archived org has no use
   * for -- has to say so somewhere. A predicate on the entry keeps `nav` a
   * plain array instead of turning it into a function of context.
   */
  hidden?: (ctx: CardContext) => boolean;
}

export interface SettingsLink {
  label: string;
  anchor: string;
}

/**
 * Home's named tabs, in the order the strip shows them (the owner:
 * "the three pages become three tabs: Cards | Sprint | Actions";
 * the List | Boards toggle became tabs too -- "Focus | Board | Sprint |
 * Actions", Focus being "local cards and prompts", the list, and Board the
 * swim lanes). A home card belongs to exactly ONE, by declaration -- not by
 * where it fell in a slice of four. Each tab is an address, so a tab can be
 * linked and Back walks between them. A tab with no cards is absent, and a
 * Home with fewer than two tabs shows no strip at all.
 */
export const HOME_TABS = [
  { id: "cards", label: "Focus", path: "/" },
  { id: "board", label: "Board", path: "/board" },
  { id: "backlog", label: "Issues", path: "/backlog" },
  { id: "sprint", label: "Sprint", path: "/sprint" },
  { id: "actions", label: "Actions", path: "/actions" },
  // A GitHub Space's designs and specs, read from its repo (Studio S2, D-S11:
  // "Design is a Home tab of a GitHub Space, not a Studio page"). Only the
  // GitHub plan fills it, so an ADO or local Space has no such tab.
  { id: "design", label: "Design", path: "/design" },
  // A GitHub Space's README and docs/ (D-S12): what the product IS,
  // beside Design's what it will be -- its own tab, last in the strip.
  { id: "docs", label: "Docs", path: "/docs" },
] as const;

/** The label a tab WEARS follows the space's tracker (the owner:
 *  "board, backlog, stats"): a gh space's Cards tab is the Board, its Sprint
 *  tab is Stats -- Sprint is an ADO word and stays on ADO soil.
 *  The issues tab is "Issues" ("what we call Backlog
 *  should be called Issues", because the board ceremony is optional on a
 *  GitHub space, so the list is not a backlog waiting for a board -- it is the
 *  issues). Ids and plans never change; only the word on the strip. */
export function homeTabLabel(id: HomeTabId, tracker: string | undefined): string {
  if (tracker === "github" && id === "sprint") return "Stats";
  return HOME_TABS.find((t) => t.id === id)?.label ?? id;
}
export type HomeTabId = (typeof HOME_TABS)[number]["id"];

/** The ORDER the strip shows the tabs, by tracker. A GitHub space leads with
 *  its issues -- the owner: "a board is nice upfront because it is
 *  ToolKit forward design, but I think Issues tab is first and Board second and
 *  Stats 3rd" -- and everywhere else it is HOME_TABS' own order. The first tab
 *  is where Home lands, so on a GitHub space `/` is the issues and the Board
 *  keeps its own address, `/board`. */
export function homeTabOrder(tracker: string | undefined): HomeTabId[] {
  const ids = HOME_TABS.map((t) => t.id);
  if (tracker === "github") return ["backlog", ...ids.filter((id) => id !== "backlog")];
  return ids;
}

/** One tab as Home draws it: its name, its address and the cards on it. */
export interface HomeTab {
  id: HomeTabId;
  label: string;
  path: string;
  cards: ReactElement[];
}

/**
 * One export per module. Off means absent: a module whose feature flag is
 * false contributes no route, no nav entry and no card -- and no bytes. The
 * registry imports every module's DESCRIPTOR statically, because it has to
 * read the flag and the route paths to decide what mounts; the descriptor is
 * small and imports no component. Every page, card and header item an opt-in
 * module contributes is a `lazyPart` (shell/lazy.tsx): a chunk of its own,
 * fetched when first drawn, never for a machine that has the flag off. The
 * ADO core is the exception on purpose -- it is always on, so it is in the
 * first load. `lazyModules.test.ts` holds the rule per descriptor.
 */
export interface ToolkitModule {
  id:
    | "ado"
    | "growth"
    | "communication"
    | "deck"
    | "organize"
    | "studio"
    | "solitaireAgile"
    | "lounge";
  /** absent = always on (core) */
  feature?: keyof NonNullable<EnvStatus["features"]>;
  /** mounted verbatim; chromeless?: true hides nav */
  routes: RouteObject[];
  nav?: NavEntry[];
  /** Home cards with no tab of their own -- they land on Cards. */
  homeCards?: (ctx: CardContext) => ReactElement[];
  /** Home cards by the tab they belong on. A module that has cards for more
   *  than one of Home's tabs declares them here rather than in `homeCards`. */
  homeTabs?: (ctx: CardContext) => Partial<Record<HomeTabId, ReactElement[]>>;
  systemCards?: (ctx: CardContext) => ReactElement[];
  /** Sections of the settings drawer (shell/SettingsDrawer). The drawer is
   *  shell chrome and may not import a module, so a module's settings reach it
   *  the way its cards reach a page: contributed here, gated by the same flag. */
  settingsSections?: (ctx: CardContext) => ReactElement[];
  /** Places in this module's settings a person might want to GO -- the avatar
   *  menu lists them, and choosing one opens the drawer AT that place. The
   *  shell names no setting; it is handed a label and an anchor, and the
   *  section marks the matching element `data-settings-anchor="<anchor>"`. */
  settingsLinks?: (ctx: CardContext) => SettingsLink[];
  /** Cards for a NAMED slot on another module's page -- `slotCards.growth` is
   *  rendered by the Growth page. It is how one module appears inside another
   *  without either importing the other: the host page asks the shell for its
   *  slot, and the shell asks the registry. A slot nobody renders is simply
   *  unused, so a module that fills one should have a fallback of its own. */
  slotCards?: Record<string, (ctx: CardContext) => ReactElement[]>;
  /** Small controls for the header, left of the avatar -- what is true on
   *  EVERY page, so a module earns a place here only for a signal a person
   *  should see wherever they are (organize's reminder bell). Keyed elements;
   *  off means absent, like everything else a module contributes. */
  headerItems?: (ctx: CardContext) => ReactElement[];
  /** Layers drawn ONCE at the app root, after everything else and over the whole
   *  viewport -- whatever page or dialog is up. A thing that must not be clipped by a
   *  page's tree earns a place here: Team Agile's confetti mount, which draws nothing
   *  until a burst is thrown. Keyed elements, each a lazyPart like every other part;
   *  off means absent, so a module that is off has no layer in the tree. */
  overlays?: (ctx: CardContext) => ReactElement[];
  /** True for a path this module wants the WHOLE screen for: no nav bar, no
   *  page padding, no background. A deck is the case -- it is a room of its
   *  own, not a card on a page. */
  chromeless?: (pathname: string) => boolean;
}

/**
 * Module order is the order cards, nav entries and routes appear in. ADO is
 * the always-on core and therefore first; growth is opt-in, gated on
 * features.growth. Communication and the deck engine each land here as their
 * own export once they are carved, gated on their own feature flag; organize
 * (reminders) is the same shape.
 */
// The Lounge is deliberately LAST: you look up from the work, so its tab
// stands apart from the work's tabs (docs/modules/lounge.md). The
// Studio, a working room, sits before it (D-S1),
// and Solitaire Agile's standup between the two (docs/modules/solitaire-agile.md, "The web UI").
export const modules: ToolkitModule[] = [
  adoModule,
  growthModule,
  communicationModule,
  deckModule,
  organizeModule,
  studioModule,
  solitaireAgileModule,
  loungeModule,
];

/** The modules this environment actually runs. A module without a `feature`
 *  is always on; one with a feature runs only when /env says it is true. */
export function activeModules(all: ToolkitModule[], env: EnvStatus | undefined): ToolkitModule[] {
  return all.filter((m) => {
    if (!m.feature) return true;
    return Boolean(env?.features?.[m.feature]);
  });
}

export function moduleRoutes(active: ToolkitModule[]): RouteObject[] {
  return active.flatMap((m) => m.routes);
}

/** The module that owns `pathname` but is switched off, if there is one -- so
 *  "no such page" can say "that page belongs to a module that is off" when that
 *  is the truth. The shell still knows no module by name: it is handed back. */
export function dormantOwner(
  all: ToolkitModule[],
  active: ToolkitModule[],
  pathname: string,
): ToolkitModule | undefined {
  return all
    .filter((m) => !active.includes(m))
    .find((m) => m.routes.some((r) => r.path && matchPath(String(r.path), pathname)));
}

export function moduleNav(active: ToolkitModule[], ctx: CardContext): NavEntry[] {
  return active.flatMap((m) => (m.nav ?? []).filter((n) => !n.hidden?.(ctx)));
}

/**
 * The nav as the shell DRAWS it: the always-on core's first entry
 * -- Home -- is the anchor, drawn at the left as the Space pill, and the rest
 * are the tabs after the divider. The data model is unchanged: `moduleNav`
 * still lists Home, so page titles and `match` keep working; only the drawing
 * splits. With no core entry (a registry under test), there is no anchor.
 */
export function moduleNavSplit(
  active: ToolkitModule[],
  ctx: CardContext,
): { anchor?: NavEntry; tabs: NavEntry[] } {
  const entries = moduleNav(active, ctx);
  const first = active.find((m) => !m.feature)?.nav?.[0];
  const anchor = first && entries.includes(first) ? first : undefined;
  return { anchor, tabs: entries.filter((n) => n !== anchor) };
}

export function moduleSlot(
  active: ToolkitModule[],
  ctx: CardContext,
  slot: string,
): ReactElement[] {
  return active.flatMap((m) => m.slotCards?.[slot]?.(ctx) ?? []);
}

export function moduleHeaderItems(active: ToolkitModule[], ctx: CardContext): ReactElement[] {
  return active.flatMap((m) => m.headerItems?.(ctx) ?? []);
}

export function moduleOverlays(active: ToolkitModule[], ctx: CardContext): ReactElement[] {
  return active.flatMap((m) => m.overlays?.(ctx) ?? []);
}

export function isChromeless(active: ToolkitModule[], pathname: string): boolean {
  return active.some((m) => m.chromeless?.(pathname) ?? false);
}

export function moduleSettings(active: ToolkitModule[], ctx: CardContext): ReactElement[] {
  return active.flatMap((m) => m.settingsSections?.(ctx) ?? []);
}

export function moduleSettingsLinks(active: ToolkitModule[], ctx: CardContext): SettingsLink[] {
  return active.flatMap((m) => m.settingsLinks?.(ctx) ?? []);
}

export function moduleCards(
  active: ToolkitModule[],
  ctx: CardContext,
  kind: "home" | "system",
): ReactElement[] {
  if (kind === "home") return moduleHomeTabs(active, ctx).flatMap((t) => t.cards);
  return active.flatMap((m) => m.systemCards?.(ctx) ?? []);
}

/** Home's tabs that have cards, in the tracker's order (`homeTabOrder`); within
 *  a tab, module order. An empty tab is absent -- not disabled, not "nothing
 *  here": absent, the way a module that is off is. `homeCards` with no tab land
 *  on Focus. `/` belongs to whichever tab is FIRST (homeTabFor). */
export function moduleHomeTabs(active: ToolkitModule[], ctx: CardContext): HomeTab[] {
  const byModule = active.map((m) => ({
    untabbed: m.homeCards?.(ctx) ?? [],
    tabbed: m.homeTabs?.(ctx) ?? {},
  }));
  const tracker = ctx.env?.tracker;
  return homeTabOrder(tracker)
    .map((id) => HOME_TABS.find((t) => t.id === id)!)
    .map((t) => ({
      id: t.id,
      label: homeTabLabel(t.id, tracker),
      path: t.path as string,
      cards: byModule.flatMap((m) => [
        ...(t.id === "cards" ? m.untabbed : []),
        ...(m.tabbed[t.id] ?? []),
      ]),
    }))
    .filter((t) => t.cards.length > 0);
}

/** The tab an address shows: `/` is the strip's first tab, anything else its
 *  own tab's address. An address that is no tab (or a tab this Home does not
 *  have) is undefined. */
export function homeTabFor(pathname: string, tabs: HomeTab[]): HomeTab | undefined {
  if (pathname === "/" || pathname === "") return tabs[0];
  return tabs.find((t) => t.path === pathname);
}
