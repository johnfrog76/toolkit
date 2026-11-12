import { fireEvent, render, screen } from "@testing-library/react";
import { MemoryRouter } from "react-router";
import { ShellProvider } from "../../shell/cards";
import type { ShellValue } from "../../shell/cards";
import type { HomeTabId } from "../../shell/registry";
import { AdoHome } from "./routes";
import { NO_FILTERS } from "./FilterDrawer";
import { drawerSections } from "./homeTabs";
import { rulesOf } from "../../shell/kinds/panelShapeAssert";
import { controlRowsSpace } from "../../shell/layoutTokens";

// The strip's toolbar slot is drawn on EVERY tab of a GitHub Space, so
// nothing moves between tabs. A tab with filters has the control enabled; one
// without has the SAME control, disabled, carrying a tooltip. react-markdown is
// ESM (the registry tests' rule), so the heavy neighbours are stand-ins.
jest.mock("react-markdown", () => ({ __esModule: true, default: () => null }));
jest.mock("remark-gfm", () => ({ __esModule: true, default: () => null }));
// routes.tsx reads one function of the registry, and the registry imports every
// module -- so it is a stand-in here, with homeTabFor's own rule.
jest.mock("../../shell/registry", () => ({
  homeTabFor: (p: string, tabs: { path: string }[]) =>
    p === "/" || p === "" ? tabs[0] : tabs.find((t) => t.path === p),
}));
jest.mock("./Board", () => ({ Board: () => <div data-testid="board" /> }));
jest.mock("./ActionDialog", () => ({ ActionDialog: () => null }));
jest.mock("../../shared/Tips", () => ({ Tips: () => null, tipsReady: () => false }));

const ENV = {
  tier: 1,
  spaceStatus: "active",
  tracker: "github",
  features: {},
  cardTypes: [],
  config: { projects: [], activeSpace: "x", spaces: [{ slug: "x", name: "X", status: "active" }] },
};
jest.mock("../../shell/api", () => ({
  useGetEnvQuery: () => ({ data: ENV, isFetching: false }),
  useGetSurfacesQuery: () => ({ data: undefined, isFetching: false }),
}));
jest.mock("./api.ado", () => ({
  useGetStatusQuery: () => ({ data: { count: 0, prompts: [] } }),
  useGetWorkItemsQuery: () => ({ data: { count: 0, items: [] }, isFetching: false }),
  useGetDocsQuery: () => ({ data: { supported: true, repo: "o/r", readme: null, items: [] } }),
  useGetEngagementSummaryQuery: () => ({ isLoading: false }),
  useGetEngagementWorkBreakdownQuery: () => ({ isLoading: false }),
}));

// The GitHub strip, as the registry orders it (registry.test.tsx pins that
// order; importing the registry here would pull every module in).
const GH_STRIP: [HomeTabId, string, string][] = [
  ["backlog", "Issues", "/backlog"],
  ["board", "Board", "/board"],
  ["sprint", "Stats", "/sprint"],
  ["design", "Design", "/design"],
  ["docs", "Docs", "/docs"],
];
const pathOf = (id: string) => GH_STRIP.find((t) => t[0] === id)![2];
const tabsValue = (): ShellValue => ({
  cards: { home: [], system: [] },
  homeTabs: GH_STRIP.map(([id, label, path]) => ({ id, label, path, cards: [] })),
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
});

function at(path: string) {
  return render(
    <MemoryRouter initialEntries={[path]}>
      <ShellProvider value={tabsValue()}>
        <AdoHome />
      </ShellProvider>
    </MemoryRouter>,
  );
}

describe("the strip's toolbar slot", () => {
  it.each(GH_STRIP.map(([id, label]) => [label, id] as const))(
    "is drawn on %s, above the strip, and disabled exactly where the tab has no sections",
    (_label, id) => {
      const { container } = at(pathOf(id));
      const slot = screen.getByRole("button", { name: "Filters" });
      const filterable = drawerSections(ENV as never, id).length > 0;
      expect(slot.getAttribute("aria-disabled") === "true").toBe(!filterable);
      // The slot is before the strip in the page: its top edge is the same on
      // every tab because it is always the same element in the same place.
      const strip = screen.getByRole("tablist", { name: "Home" });
      expect(slot.compareDocumentPosition(strip) & Node.DOCUMENT_POSITION_FOLLOWING).toBeTruthy();
      expect(container.querySelectorAll("[aria-label='Filters']").length).toBe(1);
    },
  );

  it("says why on a tab with nothing to filter, reachable by keyboard", async () => {
    at("/sprint");
    const slot = screen.getByRole("button", { name: "Filters" });
    // disabledFocusable: still a tab stop, so the tooltip opens on focus.
    expect(slot.hasAttribute("disabled")).toBe(false);
    expect(slot.getAttribute("aria-disabled")).toBe("true");
    slot.focus();
    expect(document.activeElement).toBe(slot);
    fireEvent.focus(slot);
    expect((await screen.findByText(NO_FILTERS)).textContent).toBe("No filters on this tab");
  });

  it("does nothing when clicked while disabled", () => {
    at("/sprint");
    const slot = screen.getByRole("button", { name: "Filters" });
    fireEvent.click(slot);
    expect(slot.getAttribute("aria-expanded")).toBeNull();
  });
});

describe("Home's head: the drawer and what follows it", () => {
  it("has no margin under the drawer; the tab strip's wrapper owns the space below", () => {
    const { container } = at(pathOf("backlog"));
    const head = container.querySelector<HTMLElement>("[data-home-head]")!;
    expect(head).not.toBeNull();
    for (const el of [head, ...Array.from(head.children)] as HTMLElement[]) {
      expect(rulesOf(el)).not.toMatch(/margin/);
    }
    expect(rulesOf(head)).toContain(`row-gap: ${controlRowsSpace}`);
    expect(rulesOf(head)).not.toMatch(/padding-bottom/);
    expect(head.nextElementSibling?.hasAttribute("data-tab-rows")).toBe(true);
  });

  it("owns the space below itself when no strip follows", () => {
    const one = tabsValue();
    one.homeTabs = one.homeTabs.slice(0, 1);
    const { container } = render(
      <MemoryRouter initialEntries={["/backlog"]}>
        <ShellProvider value={one}>
          <AdoHome />
        </ShellProvider>
      </MemoryRouter>,
    );
    expect(container.querySelector("[data-tab-rows]")).toBeNull();
    const head = container.querySelector<HTMLElement>("[data-home-head]")!;
    expect(head).not.toBeNull();
    expect(rulesOf(head)).toContain(`padding-bottom: ${controlRowsSpace}`);
    expect(rulesOf(head)).not.toMatch(/margin/);
  });
});
