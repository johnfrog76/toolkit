import { fireEvent, render, screen, within } from "@testing-library/react";
import { FilterDrawer } from "./FilterDrawer";
import type { PromptInfo } from "./api.ado";
import type { DrawerSection } from "./homeTabs";

// The drawer's linkedness row. The rule (which card is linked, when the
// row is drawn) is pinned as a table in promptFilters.test.ts; this holds the
// control: drawn in a mixed Space and absent in an all-custom one, counted from
// the cards, and each badge a toggle back to All.

let prompts: PromptInfo[] = [];

jest.mock("../../shell/api", () => ({
  useGetEnvQuery: () => ({ data: { cardTypes: [], config: { projects: [] } } }),
}));
jest.mock("./api.ado", () => ({
  useGetStatusQuery: () => ({ data: { count: prompts.length, prompts } }),
  useGetWorkItemsQuery: () => ({
    data: {
      count: 1,
      items: [
        {
          id: 1,
          title: "t",
          type: "Bug",
          state: "open",
          project: "p",
          sprint: "M1",
          updated: "",
          url: "",
          worker: "opus",
        },
      ],
    },
    isFetching: false,
  }),
}));

function card(file: string, ado_url: string | null): PromptInfo {
  return {
    file,
    id: null,
    type: null,
    name: file,
    linked: ado_url !== null,
    billable: true,
    title: file,
    sprint: "--",
    progress: "--",
    checked: 0,
    total: 0,
    modified: "",
    ado_url,
    pr_url: null,
    status: "Active",
  };
}

const LINKED_GH = card("Task4-filter.prompt.md", "https://github.com/johnfrog76/toolkit/issues/4");
const LINKED_ADO = card("141-search.prompt.md", "https://dev.azure.com/o/p/_workitems/edit/141");
const CUSTOM = card("Spike-K7M2-wallet.prompt.md", null);

function drawer(linkFilter: string, onLinkChange = jest.fn(), sections?: DrawerSection[]) {
  render(
    <FilterDrawer
      sections={sections}
      value=""
      onChange={() => {}}
      activeRepo={null}
      onRepoChange={() => {}}
      stateFilter="All"
      onStateChange={() => {}}
      stateOptions={["All"]}
      typeFilter="All"
      onTypeChange={() => {}}
      linkFilter={linkFilter}
      onLinkChange={onLinkChange}
    />,
  );
  return onLinkChange;
}

describe("the filter drawer's linkedness row", () => {
  it("is drawn in a mixed Space, counted from the cards", () => {
    prompts = [LINKED_GH, LINKED_ADO, CUSTOM];
    drawer("All");
    const row = screen.getByRole("radiogroup", { name: "Tracker link" });
    const radios = within(row).getAllByRole("radio");
    expect(radios.map((r) => r.textContent)).toEqual(["All3", "Linked2", "Custom1"]);
    expect(radios.map((r) => r.getAttribute("aria-checked"))).toEqual(["true", "false", "false"]);
  });

  it("sets a filter, and the active badge sets it back to All", () => {
    prompts = [LINKED_GH, CUSTOM];
    const set = drawer("All");
    const row = screen.getByRole("radiogroup", { name: "Tracker link" });
    fireEvent.click(within(row).getByRole("radio", { name: /Custom/ }));
    expect(set).toHaveBeenLastCalledWith("Custom");
  });

  it("clears an active badge back to All", () => {
    prompts = [LINKED_GH, CUSTOM];
    const set = drawer("Linked");
    const row = screen.getByRole("radiogroup", { name: "Tracker link" });
    fireEvent.click(within(row).getByRole("radio", { name: /Linked/ }));
    expect(set).toHaveBeenLastCalledWith("All");
  });

  it("grows no control in a Space where every card is custom", () => {
    prompts = [CUSTOM, card("Task-W3X7-bench.prompt.md", null)];
    drawer("All");
    expect(screen.queryByRole("radiogroup", { name: "Tracker link" })).toBeNull();
  });

  // The drawer's sections follow the tab. On a GitHub Space's Issues tab
  // it holds search and the issue filters, and none of the card rows.
  it("on the Issues it holds the issue filters and searches the issues, not the cards", () => {
    prompts = [LINKED_GH, LINKED_ADO, CUSTOM];
    window.localStorage.clear();
    drawer("All", jest.fn(), ["search", "issues"]);
    for (const g of ["Issue state", "Assigned to", "Worked by", "Kind", "Severity", "Milestone"]) {
      expect(screen.getByRole("radiogroup", { name: g })).toBeTruthy();
    }
    expect(screen.queryByRole("radiogroup", { name: "Tracker link" })).toBeNull();
    expect(screen.queryByRole("radiogroup", { name: "Card type" })).toBeNull();
    expect(screen.getByPlaceholderText("Issue number, title or label")).toBeTruthy();
  });

  it("with no sections named it is the card drawer it always was", () => {
    prompts = [LINKED_GH, LINKED_ADO, CUSTOM];
    drawer("All");
    expect(screen.queryByRole("radiogroup", { name: "Issue state" })).toBeNull();
    expect(screen.getByPlaceholderText("Card id, title or file")).toBeTruthy();
  });

  it("keeps the row while a filter is active, so the way back stays", () => {
    prompts = [CUSTOM];
    drawer("Custom");
    const row = screen.getByRole("radiogroup", { name: "Tracker link" });
    expect(
      within(row)
        .getByRole("radio", { name: /Custom/ })
        .getAttribute("aria-checked"),
    ).toBe("true");
  });
});
