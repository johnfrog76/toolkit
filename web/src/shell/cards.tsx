import { Children, Fragment, cloneElement, createContext, isValidElement, useContext } from "react";
import type { ReactElement, ReactNode } from "react";
import type { HomeTab, SystemTab } from "./registry";
import { makeStyles, mergeClasses } from "@fluentui/react-components";
import { ListPager } from "./kinds/ListPager";
import { pageRowGap, panelGap } from "./layoutTokens";
import { PANEL_GRID_MIN_WIDTH_PX } from "./panelHeight";

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
  /** The System page's named tabs that have cards (registry `moduleSystemTabs`). */
  systemTabs: SystemTab[];
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
  systemTabs: [],
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

/** The System page's tabs that have cards, in strip order. */
export function useSystemTabs(): SystemTab[] {
  return useContext(ShellContext).systemTabs;
}

/** The shell's card pager, for a page that draws it somewhere other than under the grid. */
export function useShellPager(): ShellValue["pager"] {
  return useContext(ShellContext).pager;
}

/** The class every row of panels wears, for the eye in the devtools and for
 *  the structural test. `data-panel-row` marks the same element. */
export const PANEL_ROW_CLASS = "panelRow";

/** How many panels a row holds at most. */
const PANELS_PER_ROW = 2;

const useStyles = makeStyles({
  // The cards and the pager under them: a column whose gap is the page's.
  pagerStack: { display: "flex", flexDirection: "column", rowGap: pageRowGap },
  // One pager, centred under the rows: the panels' own, "Page n of m", with
  // the nav's name for a screen reader and no second label beside it.
  pager: { display: "flex", justifyContent: "center" },
  // The page: a column of rows. It owns the gap between two rows.
  page: { display: "flex", flexDirection: "column", rowGap: pageRowGap },
  // A row: a grid of its panels, stretched to the tallest. It owns the gap
  // between them, side by side or stacked. A row whose panels all drew nothing
  // is not there, so it takes no gap from the page.
  row: {
    display: "grid",
    gridTemplateColumns: "1fr",
    alignItems: "stretch",
    rowGap: panelGap,
    columnGap: panelGap,
    ":empty": { display: "none" },
  },
  rowPair: {
    [`@media (min-width: ${PANEL_GRID_MIN_WIDTH_PX}px)`]: {
      gridTemplateColumns: "1fr 1fr",
    },
  },
});

/** What a page handed over, as a flat list of panels in order. An array is
 *  laid flat and so is a fragment; `null`, `undefined` and a boolean -- a card
 *  the page left out with `cond ? <Card /> : null` -- are dropped, so a gated
 *  card leaves no slot behind. */
function panelsOf(children: ReactNode): ReactNode[] {
  return Children.toArray(children).flatMap((child) => {
    if (!isValidElement<{ children?: ReactNode }>(child) || child.type !== Fragment) return [child];
    return panelsOf(child.props.children).map((inner) =>
      isValidElement(inner) ? cloneElement(inner, { key: `${child.key}${inner.key}` }) : inner,
    );
  });
}

/** A panel's key, for the row that starts with it. */
function keyOf(panel: ReactNode, index: number): string {
  return isValidElement(panel) && panel.key !== null ? panel.key : `row-${index}`;
}

/** Panels as rows of `perRow`, in order. Each row is a real element. */
function Rows({ panels, perRow }: { panels: ReactNode[]; perRow: number }) {
  const styles = useStyles();
  const rows: ReactNode[][] = [];
  for (let i = 0; i < panels.length; i += perRow) rows.push(panels.slice(i, i + perRow));
  return (
    <>
      {rows.map((row, index) => (
        <div
          key={keyOf(row[0], index)}
          className={mergeClasses(PANEL_ROW_CLASS, styles.row, perRow > 1 && styles.rowPair)}
          data-panel-row=""
        >
          {row}
        </div>
      ))}
    </>
  );
}

/** One row of a page: up to two panels, side by side above 900px and stacked
 *  below it, stretched to the taller.
 *
 *  A page that groups its panels itself passes these to `PageGrid`; one that
 *  does not gets its panels paired in order. A row never holds more than two:
 *  hand it more and it draws them as further rows, two at a time. A row with
 *  nothing in it is not drawn. */
export function PanelRow({ children }: { children: ReactNode }) {
  return <Rows panels={panelsOf(children)} perRow={PANELS_PER_ROW} />;
}

/** The shell's page grid: a column of rows, each row up to two panels -- one
 *  column, two above 900px.
 *
 *  A module's page wraps its cards in this rather than declaring the columns
 *  again. The panels pair two to a row in the order given; a `PanelRow` among
 *  them is a row the page grouped itself, and the panels around it pair up on
 *  either side. The rule it keeps is the visible one: a page with a single card
 *  shows that card at HALF width, like every other card in the product, instead
 *  of stretching it across the window because it happens to be alone. Meetings
 *  did stretch, because its page rendered `PanelFrame` straight into the route.
 *
 *  Spacing is the wrapper's at both levels: this element's gap between rows, a
 *  row's gap between its panels. Nothing here has a margin.
 *
 *  A panel that is mounted and then draws nothing keeps its place in the
 *  pairing -- the page said where it goes, not what loaded -- so its neighbour
 *  stays where it was, at half width.
 *
 *  It is a component rather than an exported class name so there is one grid in
 *  the product and not a third copy of `gridTemplateColumns` to drift. */
export function PageGrid({ children, full }: { children: ReactNode; full?: boolean }) {
  // `full` is the LIST exception (the owner, the Backlog tab: "we go
  // full-width with backlog"): a tab whose one card is a long list reads best
  // across the window, the way the board does -- one panel to a row. Everything
  // else keeps the rule above -- half width, like every other card in the
  // product.
  const styles = useStyles();
  const perRow = full ? 1 : PANELS_PER_ROW;
  const rows: ReactNode[] = [];
  let loose: ReactNode[] = [];
  const flush = () => {
    if (loose.length === 0) return;
    rows.push(<Rows key={`rows-${keyOf(loose[0], rows.length)}`} panels={loose} perRow={perRow} />);
    loose = [];
  };
  for (const child of panelsOf(children)) {
    if (isValidElement(child) && child.type === PanelRow) {
      flush();
      rows.push(child);
    } else {
      loose.push(child);
    }
  }
  flush();
  return (
    <div className={styles.page} data-page-rows="">
      {rows}
    </div>
  );
}

/** The current page of a module's cards, in the shell's page grid: rows of
 *  two. The pager sits under the rows, spaced by this wrapper's gap.
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
    <div className={styles.pagerStack}>
      <PageGrid>{shown}</PageGrid>
      {pagerPlacement === "below" && pager.totalPages > 1 ? (
        <nav className={styles.pager} aria-label="More cards">
          <ListPager
            page={pager.page}
            totalPages={pager.totalPages}
            onPageChange={pager.onPageChange}
          />
        </nav>
      ) : null}
    </div>
  );
}
