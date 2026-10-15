import { act, fireEvent, render, screen, within } from "@testing-library/react";
import { MemoryRouter, Route, Routes, useLocation } from "react-router";
import { MyWork } from "./MyWork";
import { IssueFilterRows } from "./IssueFilterRows";
import type { WorkItemInfo } from "./api.ado";
import { workItemsPath } from "./issueAxes";

// The Issues row wears the house row: the title is text, the one exposed
// action goes somewhere, the menu holds the rest. On a gh space the exposed
// action is the reading room and github.com is a menu item; on ADO
// there is no reading room, so the row still opens the board.
jest.mock("./ActionDialog", () => ({ ActionDialog: () => null }));

let tracker = "github";
jest.mock("../../shell/api", () => ({
  useGetEnvQuery: () => ({ data: { tracker } }),
}));

const ITEM: WorkItemInfo = {
  id: 28,
  title: "Feature: Lounge M1 and M2",
  type: "Feature",
  state: "open",
  project: "toolkit",
  sprint: "",
  updated: "2026-09-27",
  url: "https://github.com/johnfrog76/toolkit/issues/28",
  labels: [],
};
let workAnswer: { data?: { count: number; items: WorkItemInfo[] }; error?: unknown } = {
  data: { count: 1, items: [ITEM] },
};
let lastArg: unknown;
const editCalls: unknown[] = [];
let editAnswer: { status: string; error?: string; output?: string | null } = { status: "success" };
jest.mock("./api.ado", () => ({
  useEditWorkItemMutation: () => [
    (fields: unknown) => {
      editCalls.push(fields);
      return {
        unwrap: () =>
          Promise.resolve({
            command: "EditItem",
            exit_code: 0,
            duration: 0,
            output: null,
            ...editAnswer,
          }),
      };
    },
    { isLoading: false },
  ],
  useGetWorkItemsQuery: (arg: unknown) => {
    lastArg = arg;
    return {
      isLoading: false,
      isFetching: false,
      error: undefined,
      ...workAnswer,
      refetch: jest.fn(),
    };
  },
}));
beforeEach(() => {
  workAnswer = { data: { count: 1, items: [ITEM] } };
  lastArg = undefined;
  editCalls.length = 0;
  editAnswer = { status: "success" };
  window.localStorage.clear();
});

function Where() {
  const loc = useLocation();
  return <div data-testid="where">{loc.pathname + loc.search}</div>;
}

// The Issues tab as Home draws it on a GitHub Space: the filter drawer's
// Issues section above the list, the two reading one set of choices. On ADO
// the drawer holds no Issues section, so none is drawn.
function mount(props: Parameters<typeof MyWork>[0] = {}) {
  const drawer = tracker === "github" ? <IssueFilterRows /> : null;
  return render(
    <MemoryRouter initialEntries={["/backlog"]}>
      <Routes>
        <Route
          path="*"
          element={
            <>
              {drawer}
              <MyWork {...props} />
              <Where />
            </>
          }
        />
      </Routes>
    </MemoryRouter>,
  );
}

describe("an Issues row", () => {
  it("on gh: the title is text, the exposed action opens the reading room", () => {
    tracker = "github";
    mount();
    const title = screen.getByText(ITEM.title);
    expect(title.closest("a")).toBeNull();
    expect(screen.queryByRole("link", { name: "Open on GitHub" })).toBeNull();
    fireEvent.click(screen.getByRole("button", { name: "Open the issue" }));
    expect(screen.getByTestId("where").textContent).toBe("/issue/28?repo=toolkit");
  });

  it("on gh: github.com is in the menu, last, after the in-app actions", async () => {
    tracker = "github";
    mount();
    fireEvent.click(screen.getByRole("button", { name: `Actions for ${ITEM.title}` }));
    const items = (await screen.findAllByRole("menuitem")).map((m) => m.textContent);
    expect(items).toEqual(["Make a card", "Close issue", "Pin on GitHub", "Open on GitHub"]);
  });

  it("on ADO: no reading room, the exposed action opens the board", () => {
    tracker = "ado";
    mount();
    expect(screen.queryByRole("button", { name: "Open the issue" })).toBeNull();
    expect(screen.getByRole("link", { name: "Open in ADO" }).getAttribute("href")).toBe(ITEM.url);
  });
});

// The tracker's own pin: pinned rows first within what the filters
// show, the row says so naming the tracker, and what is pinned can be
// unpinned from the same menu -- a closed issue still pinned included.
describe("a pinned issue", () => {
  const rows: WorkItemInfo[] = [
    { ...ITEM, id: 1, title: "open, newest" },
    { ...ITEM, id: 2, title: "open, pinned", pinned: true },
    {
      ...ITEM,
      id: 3,
      title: "closed, pinned",
      state: "closed",
      closed: "2026-09-20",
      pinned: true,
    },
    { ...ITEM, id: 4, title: "pinned but routed to opus", worker: "opus", pinned: true },
    { ...ITEM, id: 5, title: "for sonnet", worker: "sonnet" },
  ];
  const titles = () => Array.from(document.querySelectorAll("strong")).map((s) => s.textContent);

  it("sorts first, keeping the agent's order inside each half", () => {
    tracker = "github";
    workAnswer = { data: { count: rows.length, items: rows } };
    mount();
    expect(titles()).toEqual([
      "open, pinned",
      "closed, pinned",
      "pinned but routed to opus",
      "open, newest",
      "for sonnet",
    ]);
  });

  it("a filter still answers its question: a pin routed to Opus is not under Sonnet", () => {
    tracker = "github";
    window.localStorage.setItem("ado.issues.worker", "sonnet");
    workAnswer = { data: { count: rows.length, items: rows } };
    mount();
    expect(titles()).toEqual(["for sonnet"]);
  });

  it("says Pinned on GitHub, and an unpinned row does not", () => {
    tracker = "github";
    workAnswer = { data: { count: 2, items: [rows[0], rows[1]] } };
    mount();
    expect(screen.getAllByText("Pinned on GitHub")).toHaveLength(1);
  });

  it.each([
    ["open", rows[1]],
    ["closed", rows[2]],
  ])("the menu reads Unpin on a pinned %s row, and Unpin runs EditItem -Unpin", async (_s, row) => {
    tracker = "github";
    workAnswer = { data: { count: 1, items: [row] } };
    mount();
    fireEvent.click(screen.getByRole("button", { name: `Actions for ${row.title}` }));
    const items = (await screen.findAllByRole("menuitem")).map((m) => m.textContent);
    expect(items).toContain("Unpin");
    expect(items).not.toContain("Pin on GitHub");
    expect(items[items.length - 1]).toBe("Open on GitHub");
    fireEvent.click(screen.getByRole("menuitem", { name: "Unpin" }));
    expect(editCalls).toEqual([{ id: row.id, pinned: false }]);
    // The write settles; the refetch (the mutation's invalidation) moves the row.
    await act(async () => {});
  });

  it("Pin on GitHub runs EditItem -Pin; GitHub's refusal is said in the verb's sentence", async () => {
    tracker = "github";
    editAnswer = {
      status: "error",
      error: "GitHub pins three issues per repository; unpin one first. Issue 28 was not pinned.",
    };
    mount();
    fireEvent.click(screen.getByRole("button", { name: `Actions for ${ITEM.title}` }));
    fireEvent.click(await screen.findByRole("menuitem", { name: "Pin on GitHub" }));
    expect(editCalls).toEqual([{ id: 28, pinned: true }]);
    expect(
      await screen.findByText(/GitHub pins three issues per repository; unpin one first/),
    ).toBeTruthy();
  });

  it("on ADO there is no pin", async () => {
    tracker = "ado";
    workAnswer = { data: { count: 1, items: [{ ...ITEM, pinned: true }] } };
    mount();
    expect(screen.queryByText(/Pinned on/)).toBeNull();
    fireEvent.click(screen.getByRole("button", { name: `Actions for ${ITEM.title}` }));
    const items = (await screen.findAllByRole("menuitem")).map((m) => m.textContent);
    expect(items).not.toContain("Unpin");
  });
});

// The footer + names what it makes in the tracker's own words: on gh
// it said "New ADO Item" once.
describe("the Issues tab's footer +", () => {
  it("on gh: New GitHub Issue", () => {
    tracker = "github";
    mount();
    expect(screen.getByRole("button", { name: "New GitHub Issue" })).toBeTruthy();
    expect(screen.queryByRole("button", { name: "New ADO Item" })).toBeNull();
  });

  it("on ADO: New ADO Item", () => {
    tracker = "ado";
    mount();
    expect(screen.getByRole("button", { name: "New ADO Item" })).toBeTruthy();
  });
});

// The string pass: every state names the tracker and the thing, and no
// ADO word stands on gh soil (D-G13). A table, one row per state x tracker.
describe("the Issues tab's states say where and what", () => {
  const cases: [string, string, typeof workAnswer, string, string][] = [
    [
      "github",
      "unset",
      { error: { status: 503 } },
      "GitHub is not set up",
      "This Space has no repo to ask. Give it one in Settings.",
    ],
    [
      "github",
      "failed",
      { error: { status: 500 } },
      "Could not load the GitHub issues",
      "GitHub did not answer. Nothing was read.",
    ],
    [
      "github",
      "empty",
      { data: { count: 0, items: [] } },
      "No open GitHub issues",
      "The repo's open issues show up here, ready to become a card.",
    ],
    [
      "ado",
      "unset",
      { error: { status: 503 } },
      "Azure DevOps is not set up",
      "This Space has no address to ask. Give it one in Settings.",
    ],
    [
      "ado",
      "failed",
      { error: { status: 500 } },
      "Could not load the ADO work items",
      "Azure DevOps did not answer. Nothing was read.",
    ],
    [
      "ado",
      "empty",
      { data: { count: 0, items: [] } },
      "No ADO work items assigned to you",
      "Work items assigned to you in Azure DevOps show up here, ready to become a card.",
    ],
  ];
  it.each(cases)("%s, %s", (tr, _state, answer, title, detail) => {
    tracker = tr;
    workAnswer = answer;
    mount();
    expect(screen.getByText(title)).toBeTruthy();
    expect(screen.getByText(detail)).toBeTruthy();
    if (tr === "github") {
      expect(document.body.textContent).not.toMatch(/Azure DevOps|work item/i);
    }
  });

  // The card is headed for what it holds -- "GitHub Issues", the collection
  // -- not "Backlog", which is what it was called
  // while the board was assumed to be its next stop.
  it("on gh, all: the header names the collection, GitHub Issues", () => {
    tracker = "github";
    mount();
    expect(screen.getByText("GitHub Issues")).toBeTruthy();
  });

  it("on gh, assigned to me: the header and the empty state name the issues", () => {
    tracker = "github";
    workAnswer = { data: { count: 0, items: [] } };
    mount();
    fireEvent.click(
      within(screen.getByRole("radiogroup", { name: "Assigned to" })).getByRole("radio", {
        name: "me",
      }),
    );
    expect(screen.getByText("GitHub issues assigned to me")).toBeTruthy();
    expect(screen.getByText("No GitHub issues assigned to you")).toBeTruthy();
    expect(
      screen.getByText("Issues assigned to you in GitHub show up here, ready to become a card."),
    ).toBeTruthy();
  });

  it("on ADO the row's pickup says Make a card, as it does on gh", async () => {
    tracker = "ado";
    mount();
    fireEvent.click(screen.getByRole("button", { name: `Actions for ${ITEM.title}` }));
    const items = (await screen.findAllByRole("menuitem")).map((m) => m.textContent);
    expect(items).toEqual(["Make a card", "Resolve Work Item"]);
  });
});

// The ledger, both halves of it. Three chip groups, three controls:
// state and assignee are asked of the agent, worked-by filters the list.
describe("the Issues tab's chip groups", () => {
  const group = (name: string) => screen.getByRole("radiogroup", { name });
  const chip = (g: string, name: string) => within(group(g)).getByRole("radio", { name });

  it("opens on today's view -- open issues, assigned to all -- and asks for nothing closed", () => {
    tracker = "github";
    mount();
    expect(chip("Issue state", "open").getAttribute("aria-checked")).toBe("true");
    expect(chip("Assigned to", "assigned to all").getAttribute("aria-checked")).toBe("true");
    expect(lastArg).toEqual({ all: true, state: "open" });
  });

  it("state and assignee are two controls, and each choice is asked of the agent", () => {
    tracker = "github";
    mount();
    fireEvent.click(chip("Issue state", "closed"));
    expect(lastArg).toEqual({ all: true, state: "closed" });
    fireEvent.click(chip("Assigned to", "me"));
    expect(lastArg).toEqual({ all: false, state: "closed" });
    fireEvent.click(chip("Issue state", "all issues"));
    expect(lastArg).toEqual({ all: false, state: "all" });
  });

  it("the choice is remembered per browser", () => {
    tracker = "github";
    const first = mount();
    fireEvent.click(chip("Issue state", "closed"));
    fireEvent.click(chip("Assigned to", "me"));
    first.unmount();
    mount();
    expect(chip("Issue state", "closed").getAttribute("aria-checked")).toBe("true");
    expect(chip("Assigned to", "me").getAttribute("aria-checked")).toBe("true");
    expect(lastArg).toEqual({ all: false, state: "closed" });
  });

  it("the path carries each axis only when it is not the default", () => {
    expect(workItemsPath()).toBe("work-items");
    expect(workItemsPath({ all: true, state: "open" })).toBe("work-items?all=1");
    expect(workItemsPath({ all: true, state: "closed" })).toBe("work-items?all=1&state=closed");
    expect(workItemsPath({ all: false, state: "all" })).toBe("work-items?state=all");
  });

  it("a closed row wears its state and still opens the reading room", () => {
    tracker = "github";
    workAnswer = {
      data: {
        count: 1,
        items: [{ ...ITEM, id: 12, title: "an old one", state: "closed", closed: "2026-09-20" }],
      },
    };
    mount();
    expect(screen.getByText("closed 2026-09-20")).toBeTruthy();
    fireEvent.click(screen.getByRole("button", { name: "Open the issue" }));
    expect(screen.getByTestId("where").textContent).toBe("/issue/12?repo=toolkit");
  });

  it("an empty closed view says so, names the filter, and the chips stay reachable", () => {
    tracker = "github";
    window.localStorage.setItem("ado.issues.state", "closed");
    workAnswer = { data: { count: 0, items: [] } };
    mount();
    expect(screen.getByText("No closed GitHub issues")).toBeTruthy();
    expect(screen.getByText("closed issues · assigned to all")).toBeTruthy();
    expect(chip("Issue state", "open")).toBeTruthy();
  });

  describe("worked by", () => {
    const items: WorkItemInfo[] = [
      { ...ITEM, id: 1, title: "one for sonnet", worker: "sonnet" },
      { ...ITEM, id: 2, title: "one for haiku", worker: "haiku" },
      { ...ITEM, id: 3, title: "one for opus", worker: "opus" },
      { ...ITEM, id: 4, title: "one for fable", worker: "fable" },
      { ...ITEM, id: 5, title: "one for nobody" },
    ];

    it("the chips are the labels present: opus, fable, sonnet lead, a fourth follows", () => {
      tracker = "github";
      workAnswer = { data: { count: items.length, items } };
      mount();
      const labels = within(group("Worked by"))
        .getAllByRole("radio")
        .map((r) => r.textContent);
      expect(labels).toEqual(["all", "opus", "fable", "sonnet", "haiku"]);
    });

    it("every row wears its worker, so the list shows who gets what", () => {
      tracker = "github";
      workAnswer = { data: { count: 3, items: items.slice(0, 3) } };
      mount();
      for (const w of ["sonnet", "haiku", "opus"]) {
        // one chip in the group, one on the row
        expect(screen.getAllByText(w).length).toBe(2);
      }
    });

    it("choosing one filters the list and is remembered", () => {
      tracker = "github";
      workAnswer = { data: { count: items.length, items } };
      const first = mount();
      fireEvent.click(chip("Worked by", "fable"));
      expect(screen.getByText("one for fable")).toBeTruthy();
      expect(screen.queryByText("one for opus")).toBeNull();
      first.unmount();
      mount();
      expect(chip("Worked by", "fable").getAttribute("aria-checked")).toBe("true");
      expect(screen.queryByText("one for opus")).toBeNull();
    });

    it("no worker labels, no group -- and a remembered worker the list lost reads as all", () => {
      tracker = "github";
      window.localStorage.setItem("ado.issues.worker", "opus");
      mount();
      expect(screen.queryByRole("radiogroup", { name: "Worked by" })).toBeNull();
      expect(screen.getByText(ITEM.title)).toBeTruthy();
    });
  });

  it("on ADO there are no chip groups", () => {
    tracker = "ado";
    mount();
    expect(screen.queryByRole("radiogroup")).toBeNull();
    expect(lastArg).toBeUndefined();
  });
});

// The Issues filters live in the filter drawer; the tab says what they
// are set to in one line, and search reaches the issues.
describe("the Issues filters, in the drawer", () => {
  const rows: WorkItemInfo[] = [
    {
      ...ITEM,
      id: 12,
      title: "Bug: the drawer hides the search",
      type: "Bug",
      labels: ["bug", "sev2"],
      sprint: "Next three",
    },
    {
      ...ITEM,
      id: 112,
      title: "Feature: milestones on Stats",
      type: "Feature",
      labels: ["enhancement"],
      worker: "opus",
    },
    { ...ITEM, id: 7, title: "A plain one", type: "Issue", labels: [] },
  ];
  const shown = () => Array.from(document.querySelectorAll("strong")).map((s) => s.textContent);
  const chip = (g: string, name: string) =>
    within(screen.getByRole("radiogroup", { name: g })).getByRole("radio", { name });

  it("the list itself holds no chip: one summary line says what the drawer shows", () => {
    tracker = "github";
    render(
      <MemoryRouter>
        <MyWork />
      </MemoryRouter>,
    );
    expect(screen.queryByRole("radiogroup")).toBeNull();
    expect(screen.getByText("open issues · assigned to all")).toBeTruthy();
  });

  it("a choice made in the drawer is the list's, and the summary names it", () => {
    tracker = "github";
    workAnswer = { data: { count: rows.length, items: rows } };
    mount();
    fireEvent.click(chip("Severity", "sev2"));
    expect(shown()).toEqual(["Bug: the drawer hides the search"]);
    expect(screen.getByText("open issues · assigned to all · sev2")).toBeTruthy();
    fireEvent.click(chip("Severity", "any sev"));
    fireEvent.click(chip("Kind", "feat"));
    expect(shown()).toEqual(["Feature: milestones on Stats"]);
    fireEvent.click(chip("Kind", "feat")); // the active chip sets it back
    fireEvent.click(chip("Milestone", "Next three"));
    expect(shown()).toEqual(["Bug: the drawer hides the search"]);
  });

  it("the label choices are remembered per browser, like the chip groups", () => {
    tracker = "github";
    workAnswer = { data: { count: rows.length, items: rows } };
    const first = mount();
    fireEvent.click(chip("Kind", "bug"));
    first.unmount();
    mount();
    expect(chip("Kind", "bug").getAttribute("aria-checked")).toBe("true");
    expect(shown()).toEqual(["Bug: the drawer hides the search"]);
  });

  it.each([
    ["12", ["Bug: the drawer hides the search"]],
    ["#112", ["Feature: milestones on Stats"]],
    ["1", []], // a number is an id, never a substring
    ["drawer search", ["Bug: the drawer hides the search"]], // words, any order
    ["sev2", ["Bug: the drawer hides the search"]], // a label is searchable
    ["opus", ["Feature: milestones on Stats"]], // so is the worker
  ])("search %s reaches the issues", (text, want) => {
    tracker = "github";
    workAnswer = { data: { count: rows.length, items: rows } };
    mount({ filter: text });
    expect(shown()).toEqual(want);
  });

  it("a lane or repo chosen for the cards never empties the Issues", () => {
    tracker = "github";
    workAnswer = { data: { count: rows.length, items: rows } };
    mount({ globalState: "Active", activeRepo: "somewhere-else" });
    expect(shown()).toHaveLength(3);
  });
});
