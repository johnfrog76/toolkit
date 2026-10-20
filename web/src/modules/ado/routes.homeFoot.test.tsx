import { render, screen } from "@testing-library/react";
import { MemoryRouter } from "react-router";
import { ShellProvider } from "../../shell/cards";
import type { ShellValue } from "../../shell/cards";
import { AdoHome } from "./routes";
import { DOCS } from "../../shell/consts";

// Home's foot links the public landing page (issue #10), the same address
// consts.json's docs.landingUrl holds -- always there, on every tab, never
// retired like a tip. react-markdown is ESM (the registry tests' rule), so
// the heavy neighbours are stand-ins, as routes.slot.test.tsx's harness is.
jest.mock("react-markdown", () => ({ __esModule: true, default: () => null }));
jest.mock("remark-gfm", () => ({ __esModule: true, default: () => null }));
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

const tabsValue = (): ShellValue => ({
  cards: { home: [], system: [] },
  homeTabs: [{ id: "cards", label: "Cards", path: "/", cards: [] }],
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

describe("Home's foot", () => {
  it("links the landing page at the one address consts.json holds", () => {
    at("/");
    const link = screen.getByRole("link", { name: "What is ToolKit?" });
    expect(link.getAttribute("href")).toBe(DOCS.landingUrl);
    expect(link.getAttribute("target")).toBe("_blank");
    expect(link.getAttribute("rel")).toBe("noopener noreferrer");
  });
});
