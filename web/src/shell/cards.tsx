import { createContext, useContext } from "react";
import type { ReactElement, ReactNode } from "react";
import type { HomeTab } from "./registry";
import { Caption1, makeStyles, tokens } from "@fluentui/react-components";
import { Pagination } from "../shared/Pagination";

/**
 * What the shell hands down to a module's `/` and `/system` route elements.
 *
 * The split exists because the two halves genuinely belong to different
 * owners. The shell filters and pages the cards -- its pager sits in the nav
 * bar, so the page number cannot live inside a route element -- and it holds
 * the filter tuple every card is built from. The module owns what else is on
 * those pages: its filter drawer, its own loading gates. Passing both down
 * through one context is what lets that be true without the shell importing a
 * module's components or the module owning the pager.
 */
export interface FilterControls {
  filterValue: string;
  setFilterValue: (value: string) => void;
  activeRepo: string | null;
  setActiveRepo: (repo: string | null) => void;
  stateFilter: string;
  setStateFilter: (state: string) => void;
  stateOptions: string[];
  typeFilter: string;
  setTypeFilter: (type: string) => void;
  /** "Linked", "Custom", or "All". */
  linkFilter: string;
  setLinkFilter: (link: string) => void;
}

export interface CardPages {
  home: ReactElement[];
  system: ReactElement[];
}

export interface ShellValue {
  cards: CardPages;
  /** Home's named tabs that have cards (registry `moduleHomeTabs`). The page
   *  that draws Home picks the one its address names. */
  homeTabs: HomeTab[];
  filters: FilterControls;
  /** The cards other modules contributed to a named slot on a page (the
   *  registry's `slotCards`). A page renders its own slot; it never imports the
   *  module that filled it. */
  slot: (name: string) => ReactElement[];
  /** Open the settings drawer -- at `anchor` if given: the drawer scrolls to
   *  the element marked `data-settings-anchor`, and puts focus in it. How a
   *  page that REPORTS a setting sends you to the place that changes it. */
  openSettings: (anchor?: string) => void;
  /** Which page of the current card grid is showing. The grid renders its own
   *  pager, under the cards, with words -- it was an unlabelled "1 / 3" in the
   *  header, on Home only. */
  pager: { page: number; totalPages: number; onPageChange: (page: number) => void };
}

const EMPTY: ShellValue = {
  cards: { home: [], system: [] },
  homeTabs: [],
  slot: () => [],
  openSettings: () => {},
  pager: { page: 0, totalPages: 1, onPageChange: () => {} },
  filters: {
    filterValue: "",
    setFilterValue: () => {},
    activeRepo: null,
    setActiveRepo: () => {},
    stateFilter: "All",
    setStateFilter: () => {},
    stateOptions: ["All"],
    typeFilter: "All",
    setTypeFilter: () => {},
    linkFilter: "All",
    setLinkFilter: () => {},
  },
};

const ShellContext = createContext<ShellValue>(EMPTY);

export function ShellProvider({ value, children }: { value: ShellValue; children: ReactNode }) {
  return <ShellContext.Provider value={value}>{children}</ShellContext.Provider>;
}

/** The filter tuple the card grid was built from, for whatever renders the
 *  controls that change it. */
/** The cards contributed to `name` by whichever modules are on. */
export function useShellSlot(name: string): ReactElement[] {
  return useContext(ShellContext).slot(name);
}

/** Open the settings drawer, at a setting. For a page that REPORTS one. */
export function useOpenSettings(): (anchor?: string) => void {
  return useContext(ShellContext).openSettings;
}

export function useShellFilters(): FilterControls {
  return useContext(ShellContext).filters;
}

/** Home's tabs that have cards, in strip order. */
export function useHomeTabs(): HomeTab[] {
  return useContext(ShellContext).homeTabs;
}

/** The shell's card pager, for a page that draws it somewhere other than under the grid. */
export function useShellPager(): ShellValue["pager"] {
  return useContext(ShellContext).pager;
}

const useStyles = makeStyles({
  pager: {
    display: "flex",
    alignItems: "center",
    justifyContent: "center",
    gap: tokens.spacingHorizontalM,
    marginTop: tokens.spacingVerticalL,
  },
  pagerWords: { color: tokens.colorNeutralForeground3 },
  grid: {
    display: "grid",
    gridTemplateColumns: "1fr",
    gap: tokens.spacingVerticalL,
    "@media (min-width: 900px)": {
      gridTemplateColumns: "1fr 1fr",
    },
  },
  gridFull: {
    display: "grid",
    gridTemplateColumns: "1fr",
    gap: tokens.spacingVerticalL,
  },
});

/** The shell's two-column page grid: one column, two above 900px.
 *
 *  A module's page wraps its cards in this rather than declaring the columns
 *  again. The rule it keeps is the visible one: a page with a single card shows
 *  that card at HALF width, like every other card in the product, instead of
 *  stretching it across the window because it happens to be alone. Meetings did
 *  stretch, because its page rendered `PageCard` straight into the route.
 *
 *  It is a component rather than an exported class name so there is one grid in
 *  the product and not a third copy of `gridTemplateColumns` to drift. */
export function PageGrid({ children, full }: { children: ReactNode; full?: boolean }) {
  // `full` is the LIST exception (the owner, the Backlog tab: "we go
  // full-width with backlog"): a tab whose one card is a long list reads best
  // across the window, the way the board does. Everything else keeps the rule
  // above -- half width, like every other card in the product.
  const styles = useStyles();
  return <div className={full ? styles.gridFull : styles.grid}>{children}</div>;
}

/** The current page of a module's cards, in the shell's two-column grid.
 *
 *  `pager="none"` leaves the pager out: the page draws it itself, from
 *  `useShellPager()`. Home does -- its pager sits on the view-toggle row, at the
 *  right, where the eye goes to page, not under four cards
 *  where it was below the fold. The System page keeps the default. */
export function ModuleCardGrid({
  kind,
  pager: pagerPlacement = "below",
}: {
  kind: keyof CardPages;
  pager?: "below" | "none";
}) {
  const styles = useStyles();
  const { cards, pager } = useContext(ShellContext);
  const shown = cards[kind];
  return (
    <>
      <div className={styles.grid}>{shown}</div>
      {pagerPlacement === "below" && pager.totalPages > 1 ? (
        <nav className={styles.pager} aria-label="More cards">
          <Caption1 className={styles.pagerWords}>
            Cards, page {pager.page + 1} of {pager.totalPages}
          </Caption1>
          <Pagination
            page={pager.page}
            totalPages={pager.totalPages}
            onPageChange={pager.onPageChange}
          />
        </nav>
      ) : null}
    </>
  );
}
