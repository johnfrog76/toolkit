import { cleanup, fireEvent, render, screen, waitFor, within } from "@testing-library/react";
import { MemoryRouter, Route, Routes, useLocation } from "react-router";
import type { CommandResponse } from "../ado/api.ado";
import type { OrgPreset, OrgResponse, OrgTreeSummary } from "./api.solitaireAgile";
import {
  ORG_PAGE_TITLE,
  OrgPage,
  UNKNOWN_TREE_DETAIL,
  YOUR_ORG_LABEL,
  presetLabel,
  presetSizeWord,
} from "./OrgPage";
import { FAMILIES, FAMILY_NAMES, TEST_ETAG, modelNameOf, orgResponse } from "./orgFixture";
import { CHANGED_SINCE_TEXT, SeatDialog } from "./SeatDialog";
import { UseOrgDialog } from "./UseOrgDialog";

// The Org tab (docs/modules/solitaire-agile.md, "The web UI"): the tree the
// agent serves, drawn as offices by level, each seat a card with its plate.
// The responses are the SHARED table's (Tests/fixtures/org/charts/), the same
// documents the CLI's reader and the agent's are held to.

type ChartRead = { data?: OrgResponse; isLoading: boolean; error?: unknown };
let response: ChartRead = { isLoading: false };
/** Another saved tree, read by ?tree=<id>, by its id. */
let treeResponses: Record<string, ChartRead> = {};
let presetsResponse: { data?: { presets: OrgPreset[] }; isLoading: boolean } = { isLoading: false };
/** What the next Staff call through the bridge answers; a thrown value is the agent away. */
let staffAnswer: () => Promise<CommandResponse> = () =>
  Promise.resolve({ status: "success", output: "", error: "", duration: 1 } as CommandResponse);
/** Whether a Staff write is in flight, as the mutation hook says. */
let staffWriting = false;
const runStaff = jest.fn((arg: { params: string[] }) => ({ unwrap: () => staffAnswer(), arg }));
/** What a refetch of the active read answers (after a save). */
let refetched: ChartRead = { isLoading: false };
const refetch = jest.fn(() => {
  // The hook answers what the agent now serves: the next render reads it.
  response = refetched;
  return Promise.resolve(refetched);
});
jest.mock("./api.solitaireAgile", () => ({
  useGetOrgChartQuery: (tree: string, opts?: { skip?: boolean }) =>
    opts?.skip
      ? { isLoading: false }
      : tree
        ? (treeResponses[tree] ?? { isLoading: true })
        : { ...response, refetch },
  useGetOrgPresetsQuery: () => presetsResponse,
  useRunStaffMutation: () => [runStaff, { isLoading: staffWriting }],
}));

/** The Spaces /env lists: a team lead's seat dialog offers them. */
let envSpaces: Array<{ slug: string; name: string }> = [];
jest.mock("../../shell/api", () => ({
  useGetEnvQuery: () => ({ isLoading: false, data: { config: { spaces: envSpaces } } }),
}));

function Where() {
  return <p data-testid="where">{useLocation().pathname}</p>;
}

function draw() {
  render(
    <MemoryRouter initialEntries={["/solitaire-agile/org"]}>
      <Routes>
        <Route path="/solitaire-agile/org" element={<OrgPage />} />
        <Route path="*" element={<Where />} />
      </Routes>
    </MemoryRouter>,
  );
}

const office = (id: string) =>
  screen.getAllByTestId("org-office").find((o) => o.dataset.position === id)!;
/** Who sits in each seat, as each plate says it (its button aside). */
const plates = (el: HTMLElement) =>
  within(el)
    .getAllByTestId("org-plate-who")
    .map((p) => p.textContent);
/** The office's sign: its title, without View. */
const sign = (el: HTMLElement) => within(el).getByTestId("org-sign-text").textContent;
const wheres = (el: HTMLElement) =>
  within(el)
    .queryAllByTestId("org-plate-where")
    .map((p) => p.textContent);

beforeEach(() => {
  response = { isLoading: false, data: orgResponse("valid") };
  treeResponses = {};
  presetsResponse = { isLoading: false };
  runStaff.mockClear();
  staffWriting = false;
  refetch.mockClear();
  staffAnswer = () =>
    Promise.resolve({ status: "success", output: "", error: "", duration: 1 } as CommandResponse);
});

describe("the chart, over the table's tree shaped like ours", () => {
  it("one office a position, in tree order, each on its level's row", () => {
    draw();
    const offices = screen.getAllByTestId("org-office");
    expect(offices.map((o) => o.dataset.position)).toEqual([
      "owner",
      "vp-product",
      "vp-engineering",
      "pm",
      "team-lead",
      "builder",
    ]);
    const top = (id: string) => parseFloat(office(id).style.top);
    expect(top("vp-product")).toBe(top("vp-engineering"));
    const levels = ["owner", "vp-product", "pm", "team-lead", "builder"].map(top);
    expect(levels).toEqual([...levels].sort((a, b) => a - b));
    expect(new Set(levels).size).toBe(5);
    expect(screen.getByTestId("org-heading").textContent).toBe("Laptop and mini");
  });

  it("the lead's three seats are a row of three cards in one office, the vacant one last", () => {
    draw();
    const lead = office("team-lead");
    const seats = within(lead).getAllByTestId("org-seat");
    expect(seats.map((s) => s.dataset.state)).toEqual(["staffed", "staffed", "vacant"]);
    expect(sign(lead)).toBe("Team lead");
    expect(plates(lead)).toEqual([modelNameOf("fable"), modelNameOf("opus"), "vacant"]);
    expect(wheres(lead)).toEqual(["alpha", "beta", "gamma"]);
  });

  it("a staffed seat: the position on the sign, a bust in colour, the model's name on the plate, and no machine", () => {
    draw();
    const vp = office("vp-product");
    expect(within(vp).getByTestId("org-seat").dataset.state).toBe("staffed");
    expect(vp.querySelector('svg[data-refined="designer"]')).toBeTruthy();
    expect(sign(vp)).toBe("VP of product");
    expect(plates(vp)).toEqual([modelNameOf("fable")]);
    expect(wheres(vp)).toEqual([]);
    // The older file puts a machine on every seat; none is drawn, in the text or on hover.
    for (const word of ["laptop", "mini"]) {
      expect(screen.getByTestId("org-chart").textContent).not.toContain(word);
      for (const plate of screen.getAllByTestId("org-plate")) {
        expect(plate.getAttribute("title")).not.toContain(word);
      }
    }
  });

  it("a vacant seat: the empty desk in the door's opening, its mug by the seat, no bust", () => {
    draw();
    const lead = office("team-lead");
    const vacant = within(lead)
      .getAllByTestId("org-seat")
      .find((s) => s.dataset.state === "vacant")!;
    const opening = within(vacant).getByTestId("org-vacant-desk");
    expect(opening.tagName.toLowerCase()).toBe("foreignobject");
    expect(opening.closest("svg")?.getAttribute("width")).toBe("124");
    expect(opening.closest("svg")?.getAttribute("height")).toBe("104");
    expect(["x", "y", "width", "height"].map((a) => opening.getAttribute(a))).toEqual([
      "7",
      "7",
      "110",
      "90",
    ]);
    const desk = within(vacant).getByTestId("empty-desk");
    expect(desk.dataset.look).toBe("straw");
    expect(desk.style.background).toBe("rgb(168, 219, 187)");
    expect(within(desk).getByTestId("empty-desk-chair")).toBeTruthy();
    expect(within(desk).getByTestId("empty-desk-mug")).toBeTruthy();
    expect(within(desk).getByTestId("empty-desk-steam")).toBeTruthy();
    expect(desk.querySelector("style")?.textContent).toContain("@keyframes ed-steam");
    expect(vacant.querySelector("svg[data-refined]")).toBeNull();
  });

  it("the owner is a person: the position on the sign, the name on the plate, no model, no where", () => {
    draw();
    const owner = office("owner");
    expect(sign(owner)).toBe("Owner");
    expect(plates(owner)).toEqual(["Sam"]);
    expect(wheres(owner)).toEqual([]);
    expect(owner.querySelector('svg[data-refined="owner"]')).toBeTruthy();
  });

  it("the builders are a pool: one card, the position on the sign, pool on the plate, and the default-model line", () => {
    draw();
    const pool = office("builder");
    const seats = within(pool).getAllByTestId("org-seat");
    expect(seats.map((s) => s.dataset.state)).toEqual(["pool"]);
    expect(sign(pool)).toBe("Builder");
    expect(plates(pool)).toEqual(["pool"]);
    expect(within(pool).getByTestId("org-pool-line").textContent).toBe(
      "sonnet for crew cards, opus across halves, fable for art on the owner's word",
    );
  });

  it("a pool line written as a model id reads as the model's name", () => {
    const data = orgResponse("valid");
    const builder = data.tree.positions.find((p) => p.id === "builder")!;
    builder.defaultModel = "claude-sonnet-5-5";
    builder.defaultModelName = "Sonnet 5.5";
    response = { isLoading: false, data };
    draw();
    expect(within(office("builder")).getByTestId("org-pool-line").textContent).toBe("Sonnet 5.5");
  });

  it("an office with a prompt has View on its sign: a link into the reading room, named for the role", () => {
    draw();
    const pm = office("pm");
    const view = within(pm).getByRole("link", { name: "View the pm role" });
    expect(view.textContent).toBe("View");
    expect(view.getAttribute("href")).toBe("/studio/prompts/yours/pm");
    expect(within(office("team-lead")).getByRole("link").getAttribute("href")).toBe(
      "/studio/prompts/yours/team-lead",
    );
    fireEvent.click(view);
    expect(screen.getByTestId("where").textContent).toBe("/studio/prompts/yours/pm");
  });

  it("the card is not a link: every office is a plain box, and View is the only link", () => {
    draw();
    for (const o of screen.getAllByTestId("org-office")) {
      expect(o.tagName).toBe("DIV");
      expect(o.getAttribute("href")).toBeNull();
    }
    // The four offices with a role; the owner and the pool have none.
    expect(screen.getAllByRole("link")).toHaveLength(4);
    for (const id of ["owner", "builder"])
      expect(within(office(id)).queryByTestId("org-view")).toBeNull();
  });

  it("a prompt the reading room does not list has no View", () => {
    const data = orgResponse("valid");
    const pm = data.tree.positions.find((p) => p.id === "pm")!;
    pm.promptTitle = "Notes";
    pm.promptRef = null;
    response = { isLoading: false, data };
    draw();
    expect(within(office("pm")).queryByTestId("org-view")).toBeNull();
    expect(sign(office("pm"))).toBe("PM");
  });

  it("a long title clamps on the sign, the whole of it in the tooltip, and View stays", () => {
    const data = orgResponse("valid");
    const pm = data.tree.positions.find((p) => p.id === "pm")!;
    pm.title = "The programme manager of every product we have ever shipped";
    pm.seats[0].roleTitle = null;
    response = { isLoading: false, data };
    draw();
    const text = within(office("pm")).getByTestId("org-sign-text");
    expect(text.getAttribute("title")).toBe(pm.title);
    expect(within(office("pm")).getByTestId("org-view")).toBeTruthy();
  });

  it("a seat's own roleTitle stands in for the position's title, and its session is on hover", () => {
    response = { isLoading: false, data: orgResponse("the-shape-complete") };
    draw();
    expect(screen.getByTestId("org-heading").textContent).toBe("The Branch Office");
    const lead = office("team-lead");
    expect(sign(lead)).toBe("Team lead");
    expect(plates(lead)).toEqual(["Opus 5.5", "a-model-the-map-does-not-know"]);
    // In a room of seats, a seat's own label is on its plate, before its Space.
    expect(wheres(lead)).toEqual(["Alpha lead · alpha", "beta"]);
    const [alpha, beta] = within(lead).getAllByTestId("org-plate");
    expect(alpha.getAttribute("title")).toBe("Alpha lead · Opus 5.5, alpha. Session: lead-session");
    expect(beta.getAttribute("title")).toBe("Team lead · a-model-the-map-does-not-know, beta");
    expect(plates(office("vp-product"))).toEqual(["Fable 5.2"]);
    expect(within(office("vp-product")).getByTestId("org-plate").getAttribute("title")).toBe(
      "VP of product · Fable 5.2. Session: product-session",
    );
    // A session is said on hover, never in the plate's text.
    expect(screen.getByTestId("org-chart").textContent).not.toContain("lead-session");
  });

  it("the heading is an older file's name where the tree has no title", () => {
    response = { isLoading: false, data: orgResponse("name-alone") };
    draw();
    expect(screen.getByTestId("org-heading").textContent).toBe("An older file");
  });

  it("draws the table's other trees too: a lone root, and a pool alone", () => {
    for (const name of ["valid-branch-active", "same-position-id-in-two-trees"]) {
      response = { isLoading: false, data: orgResponse(name) };
      const { unmount } = render(
        <MemoryRouter>
          <OrgPage />
        </MemoryRouter>,
      );
      expect(screen.getAllByTestId("org-office")).toHaveLength(
        orgResponse(name).tree.positions.length,
      );
      unmount();
    }
  });
});

describe("when there is no chart", () => {
  it("loading says so", () => {
    response = { isLoading: true };
    draw();
    expect(screen.getByText("Reading the org chart...")).toBeTruthy();
  });

  it("no org.json (404 missing): the agent's sentence, plainly, not as an error", () => {
    response = {
      isLoading: false,
      error: {
        status: 404,
        data: { detail: { kind: "missing", message: "There is no org.json in the hub." } },
      },
    };
    draw();
    expect(screen.getByText("No org chart yet")).toBeTruthy();
    expect(screen.getByText("There is no org.json in the hub.")).toBeTruthy();
    expect(screen.queryByRole("alert")).toBeNull();
    expect(screen.queryByTestId("org-chart")).toBeNull();
  });

  it("an invalid file (409): the agent's sentence, plainly, not as an error", () => {
    const message = "Positions in tree 'a' report to each other in a loop: p -> r -> q -> p.";
    response = {
      isLoading: false,
      error: { status: 409, data: { detail: { kind: "cycle", message } } },
    };
    draw();
    expect(screen.getByText("The org chart could not be read")).toBeTruthy();
    expect(screen.getByText(message)).toBeTruthy();
    expect(screen.queryByRole("alert")).toBeNull();
  });

  it("a tree the file does not have (422): the page's own sentence, not the terminal's", () => {
    const message = "-Tree names 'other', which is not a tree in org.json. Trees: ours.";
    response = {
      isLoading: false,
      error: { status: 422, data: { detail: { kind: "unknown-tree", message } } },
    };
    draw();
    expect(screen.getByText("That org chart is not in the file")).toBeTruthy();
    expect(screen.getByText(UNKNOWN_TREE_DETAIL)).toBeTruthy();
    expect(screen.queryByRole("alert")).toBeNull();
    expect(document.body.textContent).not.toContain("-Tree");
    expect(screen.queryByText(message)).toBeNull();
    expect(screen.queryByTestId("org-chart")).toBeNull();
  });

  it("a 422 of another kind is not read as an unknown tree", () => {
    response = {
      isLoading: false,
      error: { status: 422, data: { detail: { kind: "bad-query", message: "Nope." } } },
    };
    draw();
    expect(screen.queryByText("That org chart is not in the file")).toBeNull();
    expect(screen.getByText("Could not read the org chart")).toBeTruthy();
  });

  it("no answer from the agent: an error that says nothing was read", () => {
    response = { isLoading: false, error: { status: "FETCH_ERROR", error: "TypeError" } };
    draw();
    const alert = screen.getByRole("alert");
    expect(within(alert).getByText("Could not read the org chart")).toBeTruthy();
    expect(within(alert).getByText("The agent did not answer. Nothing was read.")).toBeTruthy();
  });
});

// -- The presets (docs/hub/org.md, "Org presets") ---------------------------

/** A preset over one of the table's charts: the page draws whatever tree it is given. */
function preset(id: string, size: string, title: string, chart: string): OrgPreset {
  const c = orgResponse(chart);
  c.tree.title = title;
  c.tree.size = size;
  return {
    id,
    size,
    title,
    shortDescription: `${title}, in short.`,
    description: `${title}, at length.`,
    teamSize: 3,
    chart: c,
  };
}

const PRESETS = [
  preset("executive-suite", "S", "The Executive Suite", "one-tree-no-active-tree"),
  preset("branch-office", "M", "The Branch Office", "valid-branch-active"),
  preset("corporate-headquarters", "L", "Corporate Headquarters", "valid"),
];

function pick(label: string) {
  fireEvent.click(screen.getByTestId("org-preset-select"));
  fireEvent.click(screen.getByRole("option", { name: label }));
}

const positions = () => screen.getAllByTestId("org-office").map((o) => o.dataset.position);

describe("the presets", () => {
  beforeEach(() => {
    presetsResponse = { isLoading: false, data: { presets: PRESETS } };
  });

  it("says a size on the badge as a word, and a size it does not know as written", () => {
    expect(["S", "M", "L", "XL"].map(presetSizeWord)).toEqual(["Small", "Medium", "Large", "XL"]);
  });

  it("names a preset by its title without a leading The, and its size", () => {
    expect(PRESETS.map(presetLabel)).toEqual([
      "Executive Suite (S)",
      "Branch Office (M)",
      "Corporate Headquarters (L)",
    ]);
  });

  it("opens on the active org: the hub's chart under its own name, with no description and no size", () => {
    draw();
    expect(screen.getByTestId("org-preset-select").textContent).toContain("Laptop and mini");
    expect(screen.getByTestId("org-heading").textContent).toBe("Laptop and mini");
    expect(positions()).toContain("pm");
    expect(screen.queryByTestId("org-preset-description")).toBeNull();
    expect(screen.queryByTestId("org-preset-size")).toBeNull();
  });

  it("puts the zoom controls in the header, just left of the dropdown", () => {
    draw();
    const zoom = screen.getByTestId("org-zoom");
    const select = screen.getByTestId("org-preset-select");
    expect(zoom.compareDocumentPosition(select) & Node.DOCUMENT_POSITION_FOLLOWING).toBeTruthy();
    // Both sit in the panel's header, before the chart's box.
    const chartBox = screen.getByTestId("org-chart-box");
    expect(zoom.compareDocumentPosition(chartBox) & Node.DOCUMENT_POSITION_FOLLOWING).toBeTruthy();
    expect(
      select.compareDocumentPosition(chartBox) & Node.DOCUMENT_POSITION_FOLLOWING,
    ).toBeTruthy();
  });

  it("offers the saved orgs, then the presets smallest first", () => {
    draw();
    fireEvent.click(screen.getByTestId("org-preset-select"));
    expect(screen.getAllByRole("option").map((o) => o.textContent)).toEqual([
      "Laptop and mini Active",
      "Executive Suite (S)",
      "Branch Office (M)",
      "Corporate Headquarters (L)",
    ]);
  });

  it("picking one makes its title the heading with its size beside it, its description under it, and draws its chart", () => {
    draw();
    pick("Executive Suite (S)");
    expect(positions()).toEqual(
      orgResponse("one-tree-no-active-tree").tree.positions.map((p) => p.id),
    );
    expect(screen.queryByText("The Executive Suite, in short.")).toBeNull();
    expect(screen.getByTestId("org-preset-description").textContent).toBe(
      "The Executive Suite, at length.",
    );
    expect(screen.getByTestId("org-heading").textContent).toBe("The Executive Suite");
    expect(screen.getByTestId("org-preset-size").textContent).toBe("Small");
  });

  it("picking your org again draws the hub's chart", () => {
    draw();
    pick("Branch Office (M)");
    pick("Laptop and mini Active");
    expect(positions()).toContain("pm");
    expect(screen.queryByTestId("org-preset-description")).toBeNull();
  });

  it("with no org.json the presets are still there to preview", () => {
    response = {
      isLoading: false,
      error: {
        status: 404,
        data: { detail: { kind: "missing", message: "There is no org.json in the hub." } },
      },
    };
    draw();
    expect(screen.getByTestId("org-heading").textContent).toBe("The Executive Suite");
    expect(screen.queryByText("No org chart yet")).toBeNull();
    pick("Corporate Headquarters (L)");
    expect(positions()).toContain("pm");
  });

  it("with no preset served, the page is the hub's chart alone", () => {
    presetsResponse = { isLoading: false };
    draw();
    expect(screen.queryByTestId("org-presets")).toBeNull();
  });
});

describe("the heading with no chart", () => {
  it("is the page's own name while there is no org.json and no preset to show", () => {
    presetsResponse = { isLoading: false };
    response = {
      isLoading: false,
      error: {
        status: 404,
        data: { detail: { kind: "missing", message: "There is no org.json in the hub." } },
      },
    };
    draw();
    expect(screen.getByTestId("org-heading").textContent).toBe(ORG_PAGE_TITLE);
  });
});

// -- Saved orgs, the Active dropdown and "Use this org" (card 4) ------------------

/** The hub's chart with its file's trees listed, the first of them active. */
function withTrees(trees: Partial<OrgTreeSummary>[], name = "valid"): OrgResponse {
  const c = orgResponse(name);
  c.trees = trees.map((t, i) => ({
    id: t.id ?? `t${i}`,
    title: t.title ?? `Tree ${i}`,
    size: t.size ?? null,
    preset: t.preset ?? null,
    active: t.active ?? i === 0,
    state: t.state ?? ((t.active ?? i === 0) ? "active" : "draft"),
    activatedAt: t.activatedAt ?? null,
  }));
  return c;
}

const TWO = [
  { id: "main", title: "Laptop and mini", active: true },
  { id: "branch", title: "One machine", active: false },
];

const options = () => screen.getAllByRole("option").map((o) => o.textContent);

describe("with no org saved yet (Small First)", () => {
  beforeEach(() => {
    presetsResponse = { isLoading: false, data: { presets: PRESETS } };
    response = {
      isLoading: false,
      error: {
        status: 404,
        data: { detail: { kind: "missing", message: "There is no org.json in the hub." } },
      },
    };
  });

  it("View opens on the Executive Suite (Small) preview, and says nothing is saved yet", () => {
    draw();
    expect(screen.getByTestId("org-heading").textContent).toBe("The Executive Suite");
    expect(screen.getByTestId("org-not-active").textContent).toBe(
      "A preview. Nothing is saved yet.",
    );
  });

  it("draws no Active dropdown: there is nothing to choose", () => {
    draw();
    expect(screen.queryByTestId("org-active-select")).toBeNull();
  });

  it("offers Use this org on the preview", () => {
    draw();
    expect(screen.getByTestId("org-use").textContent).toBe("Use this org");
  });
});

describe("with saved orgs: View and Active", () => {
  beforeEach(() => {
    presetsResponse = { isLoading: false, data: { presets: PRESETS } };
    response = { isLoading: false, data: withTrees(TWO) };
    treeResponses = { branch: { isLoading: false, data: withTrees(TWO, "valid-tree-by-id") } };
  });

  it("each dropdown carries a visible label that names it: View and Active", () => {
    draw();
    expect(screen.getByText("View", { selector: "label" })).toBeTruthy();
    expect(screen.getByText("Active", { selector: "label" })).toBeTruthy();
    expect(screen.getByRole("combobox", { name: "View" })).toBe(
      screen.getByTestId("org-preset-select"),
    );
    expect(screen.getByRole("combobox", { name: "Active" })).toBe(
      screen.getByTestId("org-active-select"),
    );
  });

  it("View lists the saved orgs first, then the presets", () => {
    draw();
    fireEvent.click(screen.getByTestId("org-preset-select"));
    expect(options()).toEqual([
      "Laptop and mini Active",
      "One machine Draft",
      "Executive Suite (S)",
      "Branch Office (M)",
      "Corporate Headquarters (L)",
    ]);
  });

  it("Active lists the saved orgs only, the active one chosen, and no None", () => {
    draw();
    const select = screen.getByTestId("org-active-select");
    expect(select.textContent).toContain("Laptop and mini");
    fireEvent.click(select);
    expect(options()).toEqual(["Laptop and mini", "One machine"]);
  });

  it("the active org has no line under its heading", () => {
    draw();
    expect(screen.queryByTestId("org-not-active")).toBeNull();
  });

  it("a saved draft says so, naming the active org", () => {
    draw();
    pick("One machine Draft");
    expect(screen.getByTestId("org-heading").textContent).toBe("One machine");
    expect(screen.getByTestId("org-not-active").textContent).toBe(
      "A draft. Your active org is Laptop and mini.",
    );
    expect(screen.queryByTestId("org-use")).toBeNull();
  });

  it("a preview says so, naming the active org", () => {
    draw();
    pick("Branch Office (M)");
    expect(screen.getByTestId("org-not-active").textContent).toBe(
      "A preview. Your active org is Laptop and mini.",
    );
  });

  it("changing Active runs Staff -Activate through the bridge, with no confirmation", async () => {
    draw();
    fireEvent.click(screen.getByTestId("org-active-select"));
    fireEvent.click(screen.getByRole("option", { name: "One machine" }));
    await waitFor(() => expect(runStaff).toHaveBeenCalledTimes(1));
    expect(runStaff.mock.calls[0][0]).toEqual({ params: ["-Activate", "branch"] });
    expect(screen.queryByRole("dialog")).toBeNull();
    await waitFor(() => expect(screen.getByTestId("org-heading").textContent).toBe("One machine"));
  });

  it("picking the org already active writes nothing", () => {
    draw();
    fireEvent.click(screen.getByTestId("org-active-select"));
    fireEvent.click(screen.getByRole("option", { name: "Laptop and mini" }));
    expect(runStaff).not.toHaveBeenCalled();
  });

  it("a refusal is the verb's own sentence, said plainly, not as an error", async () => {
    staffAnswer = () =>
      Promise.resolve({
        status: "error",
        output: "",
        error: "-Activate names 'branch', which is not a tree in org.json. Trees: main.",
        duration: 1,
      } as CommandResponse);
    draw();
    fireEvent.click(screen.getByTestId("org-active-select"));
    fireEvent.click(screen.getByRole("option", { name: "One machine" }));
    const note = await screen.findByTestId("org-note");
    expect(note.textContent).toBe(
      "-Activate names 'branch', which is not a tree in org.json. Trees: main.",
    );
    expect(screen.queryByRole("alert")).toBeNull();
  });

  it("the agent away is the one error", async () => {
    staffAnswer = () => Promise.reject(new Error("offline"));
    draw();
    fireEvent.click(screen.getByTestId("org-active-select"));
    fireEvent.click(screen.getByRole("option", { name: "One machine" }));
    const note = await screen.findByTestId("org-note");
    expect(note.textContent).toContain("Could not reach the agent");
  });
});

describe("Use this org: the steps", () => {
  beforeEach(() => {
    presetsResponse = { isLoading: false, data: { presets: PRESETS } };
    response = { isLoading: false, data: withTrees([TWO[0]]) };
  });

  const openSteps = () => {
    draw();
    pick("Executive Suite (S)");
    fireEvent.click(screen.getByTestId("org-use"));
    return screen.getByTestId("org-use-dialog");
  };

  it("asks three questions, each answered with its default, Sonnet not recommended", () => {
    const dialog = openSteps();
    expect((within(dialog).getByTestId("org-step-owner") as HTMLInputElement).value).toBe("You");
    const eng = within(dialog).getByTestId("org-step-vp-engineering");
    const prod = within(dialog).getByTestId("org-step-vp-product");
    expect((within(eng).getByLabelText("Opus") as HTMLInputElement).checked).toBe(true);
    expect((within(prod).getByLabelText("Fable") as HTMLInputElement).checked).toBe(true);
    expect(within(eng).getByLabelText("Sonnet (not recommended)")).toBeTruthy();
    expect(
      within(dialog).getByText(/saved as a draft: your active org stays Laptop and mini\./),
    ).toBeTruthy();
  });

  it("Cancel leaves, and nothing is written", () => {
    const dialog = openSteps();
    fireEvent.click(within(dialog).getByRole("button", { name: "Cancel" }));
    expect(screen.queryByTestId("org-use-dialog")).toBeNull();
    expect(runStaff).not.toHaveBeenCalled();
  });

  it("Save runs Staff -Preset with the answers, then shows the saved org", async () => {
    refetched = {
      isLoading: false,
      data: withTrees([
        TWO[0],
        { id: "executive-suite", title: "The Executive Suite", size: "S", active: false },
      ]),
    };
    treeResponses = {
      "executive-suite": { isLoading: false, data: orgResponse("one-tree-no-active-tree") },
    };
    treeResponses["executive-suite"].data!.tree.title = "The Executive Suite";
    const dialog = openSteps();
    fireEvent.change(within(dialog).getByTestId("org-step-owner"), { target: { value: "Sam" } });
    fireEvent.click(
      within(within(dialog).getByTestId("org-step-vp-engineering")).getByLabelText(
        "Sonnet (not recommended)",
      ),
    );
    fireEvent.click(within(dialog).getByTestId("org-use-save"));
    await waitFor(() => expect(runStaff).toHaveBeenCalledTimes(1));
    expect(runStaff.mock.calls[0][0]).toEqual({
      params: ["-Preset", "S", "-Owner", "Sam", "-VpEngineering", "sonnet", "-VpProduct", "fable"],
    });
    await waitFor(() => expect(screen.queryByTestId("org-use-dialog")).toBeNull());
    expect(refetch).toHaveBeenCalled();
    await waitFor(() =>
      expect(screen.getByTestId("org-not-active").textContent).toBe(
        "A draft. Your active org is Laptop and mini.",
      ),
    );
    expect(screen.queryByTestId("org-use")).toBeNull();
  });

  it("a first org is said to be the one in use", () => {
    response = {
      isLoading: false,
      error: { status: 404, data: { detail: { kind: "missing", message: "No file." } } },
    };
    draw();
    fireEvent.click(screen.getByTestId("org-use"));
    expect(screen.getByText(/It is your first org, so it is the one in use\./)).toBeTruthy();
  });

  it("a refusal stays in the dialog as the verb's sentence, plainly", async () => {
    staffAnswer = () =>
      Promise.resolve({
        status: "error",
        output: "",
        error:
          "org.json already holds 3 trees (a, b, c): a file holds at most 3, so nothing was written.",
        duration: 1,
      } as CommandResponse);
    const dialog = openSteps();
    fireEvent.click(within(dialog).getByTestId("org-use-save"));
    const refusal = await within(dialog).findByTestId("org-use-refusal");
    expect(refusal.textContent).toContain("a file holds at most 3");
    expect(within(dialog).queryByRole("alert")).toBeNull();
  });
});

describe("a file that does not read, with presets to offer", () => {
  it("opens on Your org with the sentence that says why, the presets still there", () => {
    presetsResponse = { isLoading: false, data: { presets: PRESETS } };
    const message = "Positions in tree 'a' report to each other in a loop: p -> r -> q -> p.";
    response = {
      isLoading: false,
      error: { status: 409, data: { detail: { kind: "cycle", message } } },
    };
    draw();
    expect(screen.getByTestId("org-preset-select").textContent).toContain(YOUR_ORG_LABEL);
    expect(screen.getByText("The org chart could not be read")).toBeTruthy();
    expect(screen.getByText(message)).toBeTruthy();
    expect(screen.queryByTestId("org-active-select")).toBeNull();
    pick("Executive Suite (S)");
    expect(screen.getByTestId("org-heading").textContent).toBe("The Executive Suite");
  });
});

describe("an org's state: active, draft, inactive", () => {
  const THREE = [
    { id: "main", title: "Laptop and mini", active: true, state: "active" as const },
    {
      id: "branch",
      title: "One machine",
      active: false,
      state: "inactive" as const,
      activatedAt: "2026-11-01",
    },
    { id: "draft", title: "A draft org", active: false, state: "draft" as const },
  ];
  beforeEach(() => {
    presetsResponse = { isLoading: false, data: { presets: PRESETS } };
    response = { isLoading: false, data: withTrees(THREE) };
    treeResponses = {
      branch: { isLoading: false, data: withTrees(THREE, "valid-tree-by-id") },
      draft: { isLoading: false, data: withTrees(THREE, "valid-tree-by-id") },
    };
  });

  it("View names each saved org's state beside its title, in muted text", () => {
    draw();
    fireEvent.click(screen.getByTestId("org-preset-select"));
    expect(screen.getAllByTestId("org-view-state").map((s) => s.textContent)).toEqual([
      "Active",
      "Inactive",
      "Draft",
    ]);
  });

  it("an inactive org says so, naming the active org", () => {
    draw();
    pick("One machine Inactive");
    expect(screen.getByTestId("org-not-active").textContent).toBe(
      "Inactive. Your active org is Laptop and mini.",
    );
  });

  it("a draft still says it is a draft", () => {
    draw();
    pick("A draft org Draft");
    expect(screen.getByTestId("org-not-active").textContent).toBe(
      "A draft. Your active org is Laptop and mini.",
    );
  });

  it("Active lists the saved orgs only, by title, with no state words", () => {
    draw();
    fireEvent.click(screen.getByTestId("org-active-select"));
    expect(options()).toEqual(["Laptop and mini", "One machine", "A draft org"]);
  });
});

describe("one Staff write at a time (Staff takes no lock)", () => {
  beforeEach(() => {
    presetsResponse = { isLoading: false, data: { presets: PRESETS } };
    response = { isLoading: false, data: withTrees(TWO) };
  });

  it("while a write is in flight, Use this org and Active are disabled", () => {
    staffWriting = true;
    draw();
    expect(screen.getByRole("combobox", { name: "Active" }).hasAttribute("disabled")).toBe(true);
    pick("Executive Suite (S)");
    expect((screen.getByTestId("org-use") as HTMLButtonElement).disabled).toBe(true);
  });

  it("the dialog's Save, Cancel and Close wait for a write already in flight on the page", () => {
    render(
      <UseOrgDialog
        preset={PRESETS[0]}
        activeTitle="Laptop and mini"
        run={() => Promise.resolve({ status: "success" } as CommandResponse)}
        busy
        onSaved={() => {}}
        onClose={() => {}}
      />,
    );
    const dialog = screen.getByTestId("org-use-dialog");
    expect((within(dialog).getByTestId("org-use-save") as HTMLButtonElement).disabled).toBe(true);
    expect(
      (within(dialog).getByRole("button", { name: "Cancel" }) as HTMLButtonElement).disabled,
    ).toBe(true);
    expect(
      (within(dialog).getByRole("button", { name: "Close" }) as HTMLButtonElement).disabled,
    ).toBe(true);
  });

  it("while its save runs, Save says so, and Cancel and Close wait", async () => {
    let finish: (r: CommandResponse) => void = () => {};
    staffAnswer = () => new Promise<CommandResponse>((resolve) => (finish = resolve));
    draw();
    pick("Executive Suite (S)");
    fireEvent.click(screen.getByTestId("org-use"));
    const dialog = screen.getByTestId("org-use-dialog");
    fireEvent.click(within(dialog).getByTestId("org-use-save"));
    await waitFor(() =>
      expect(within(dialog).getByTestId("org-use-save").textContent).toBe("Saving..."),
    );
    expect(
      (within(dialog).getByRole("button", { name: "Cancel" }) as HTMLButtonElement).disabled,
    ).toBe(true);
    expect(
      (within(dialog).getByRole("button", { name: "Close" }) as HTMLButtonElement).disabled,
    ).toBe(true);
    fireEvent.keyDown(dialog, { key: "Escape" });
    expect(screen.getByTestId("org-use-dialog")).toBeTruthy();
    finish({ status: "error", output: "", error: "Refused.", duration: 1 } as CommandResponse);
    await waitFor(() =>
      expect(within(dialog).getByTestId("org-use-save").textContent).toBe("Save"),
    );
    expect(
      (within(dialog).getByRole("button", { name: "Cancel" }) as HTMLButtonElement).disabled,
    ).toBe(false);
  });
});

describe("the live regions stay mounted", () => {
  it("the line under the heading sits in a polite region that is there on the active org too", () => {
    presetsResponse = { isLoading: false, data: { presets: PRESETS } };
    response = { isLoading: false, data: withTrees(TWO) };
    draw();
    const region = screen.getByTestId("org-not-active-region");
    expect(region.getAttribute("aria-live")).toBe("polite");
    expect(region.textContent).toBe("");
    pick("Branch Office (M)");
    expect(screen.getByTestId("org-not-active-region")).toBe(region);
    expect(region.textContent).toContain("A preview.");
  });

  it("the refusal's status regions are there before anything is said", () => {
    presetsResponse = { isLoading: false, data: { presets: PRESETS } };
    response = { isLoading: false, data: withTrees(TWO) };
    draw();
    expect(screen.getByTestId("org-note-region").getAttribute("role")).toBe("status");
    pick("Executive Suite (S)");
    fireEvent.click(screen.getByTestId("org-use"));
    expect(screen.getByTestId("org-use-refusal-region").getAttribute("role")).toBe("status");
  });
});

describe("a saved org read by its own ?tree= read", () => {
  const INACTIVE = [
    { id: "main", title: "Laptop and mini", active: true, state: "active" as const },
    {
      id: "branch",
      title: "One machine",
      active: false,
      state: "inactive" as const,
      activatedAt: "2026-11-01",
    },
  ];
  beforeEach(() => {
    presetsResponse = { isLoading: false, data: { presets: PRESETS } };
    response = { isLoading: false, data: withTrees(INACTIVE) };
  });

  it("an inactive org says it is loading while its read runs", () => {
    treeResponses = { branch: { isLoading: true } };
    draw();
    pick("One machine Inactive");
    expect(screen.getByText("Reading the org chart...")).toBeTruthy();
  });

  it("a read that fails says why, plainly, with the page's own words", () => {
    treeResponses = {
      branch: {
        isLoading: false,
        error: {
          status: 422,
          data: { detail: { kind: "unknown-tree", message: "-Tree names 'branch'." } },
        },
      },
    };
    draw();
    pick("One machine Inactive");
    expect(screen.getByText("That org chart is not in the file")).toBeTruthy();
    expect(screen.getByText(UNKNOWN_TREE_DETAIL)).toBeTruthy();
    expect(screen.queryByRole("alert")).toBeNull();
  });
});

// -- Zoom (card 6b) ----------------------------------------------------------------

describe("the zoom", () => {
  /** The chart box's width, as the browser would measure it. */
  let boxWidth = 0;
  let widthSpy: jest.SpyInstance;
  beforeEach(() => {
    boxWidth = 0;
    widthSpy = jest.spyOn(HTMLElement.prototype, "clientWidth", "get").mockImplementation(function (
      this: HTMLElement,
    ) {
      return this.dataset.testid === "org-chart-box" ? boxWidth : 0;
    });
  });
  afterEach(() => widthSpy.mockRestore());

  const level = () => screen.getByTestId("org-zoom-level");
  const chart = () => screen.getByTestId("org-chart");
  const zoomButton = (name: string) => screen.getByRole("button", { name });

  it("is a toolbar of three real buttons over the chart, the percentage in a polite live region", () => {
    draw();
    const bar = screen.getByRole("toolbar", { name: "Zoom" });
    expect(
      within(bar)
        .getAllByRole("button")
        .map((b) => b.getAttribute("aria-label") ?? b.textContent),
    ).toEqual(["Zoom out", "Zoom in", "Fit to width"]);
    expect(level().getAttribute("aria-live")).toBe("polite");
    expect(level().textContent).toBe("Zoom 100%");
  });

  it("a tree that fits opens at 100%, as it always looked", () => {
    boxWidth = 5000;
    draw();
    expect(level().textContent).toBe("Zoom 100%");
    expect(chart().style.transform).toBe("scale(1)");
  });

  it("a tree wider than its box opens fitted to the box's width", () => {
    draw();
    const width = parseFloat(chart().style.width);
    boxWidth = Math.round(width / 2);
    cleanupAndDraw();
    expect(level().textContent).toBe(`Zoom ${Math.round((boxWidth / width) * 100)}%`);
  });

  it("only the chart's own layer scales: the scroll area is its scaled size, nothing else moves", () => {
    draw();
    const width = parseFloat(chart().style.width);
    const height = parseFloat(chart().style.height);
    fireEvent.click(zoomButton("Zoom in"));
    expect(level().textContent).toBe("Zoom 110%");
    expect(chart().style.transform).toBe("scale(1.1)");
    // The chart keeps its own size; its box's scroll area is the scaled one.
    expect(parseFloat(chart().style.width)).toBe(width);
    const sizer = chart().parentElement!;
    expect(parseFloat(sizer.style.width)).toBeCloseTo(width * 1.1);
    expect(parseFloat(sizer.style.height)).toBeCloseTo(height * 1.1);
    // The heading, the dropdown and the zoom bar are outside the scaled layer.
    expect(chart().contains(screen.getByTestId("org-heading"))).toBe(false);
    expect(chart().contains(screen.getByRole("toolbar", { name: "Zoom" }))).toBe(false);
    expect(
      screen.getByTestId("org-chart-box").contains(screen.getByRole("toolbar", { name: "Zoom" })),
    ).toBe(false);
  });

  it("steps by 10% and stops at 25% and 200%, each button disabled at its end", () => {
    draw();
    for (let i = 0; i < 12; i++) fireEvent.click(zoomButton("Zoom in"));
    expect(level().textContent).toBe("Zoom 200%");
    expect((zoomButton("Zoom in") as HTMLButtonElement).disabled).toBe(true);
    for (let i = 0; i < 20; i++) fireEvent.click(zoomButton("Zoom out"));
    expect(level().textContent).toBe("Zoom 25%");
    expect((zoomButton("Zoom out") as HTMLButtonElement).disabled).toBe(true);
  });

  it("Fit to width goes back to the fit", () => {
    boxWidth = 5000;
    draw();
    fireEvent.click(zoomButton("Zoom out"));
    expect(level().textContent).toBe("Zoom 90%");
    fireEvent.click(zoomButton("Fit to width"));
    expect(level().textContent).toBe("Zoom 100%");
  });

  it("View inside the scaled chart still opens the role", () => {
    draw();
    fireEvent.click(zoomButton("Zoom out"));
    fireEvent.click(within(office("pm")).getByTestId("org-view"));
    expect(screen.getByTestId("where").textContent).toBe("/studio/prompts/yours/pm");
  });
});

/** Draw again from nothing, so the next first frame measures the new width. */
function cleanupAndDraw() {
  cleanup();
  draw();
}

describe("the seat dialog: Assign and Change on a saved org", () => {
  const TREE = () => response.data!.tree.id;
  const actions = () => screen.getAllByTestId("org-seat-action");
  const open = (positionId: string, name: string) => {
    fireEvent.click(within(office(positionId)).getByRole("button", { name }));
    return screen.getByTestId("org-seat-dialog");
  };
  const radio = (dialog: HTMLElement, name: string) =>
    within(dialog).getByRole("radio", { name }) as HTMLInputElement;
  const lastParams = () => runStaff.mock.calls[runStaff.mock.calls.length - 1][0].params;

  /** The name each family's current model is served by (familyNames). */
  const named = (family: string) => FAMILY_NAMES[family];

  beforeEach(() => {
    envSpaces = [
      { slug: "alpha", name: "Alpha" },
      { slug: "toolkit", name: "Toolkit" },
    ];
    // The roles' own titles, as the reading room reads them: each position's title is its role's.
    const data = orgResponse("valid");
    for (const p of data.tree.positions) if (p.promptTitle) p.promptTitle = p.title;
    response = { isLoading: false, data };
  });

  it("every seat of a saved org has its button on the plate, named for the seat and who sits there", () => {
    draw();
    expect(actions().map((b) => b.getAttribute("aria-label"))).toEqual([
      "Change Owner, Sam",
      `Change VP of product, ${modelNameOf("fable")}`,
      `Change VP of engineering, ${modelNameOf("fable")}`,
      `Change PM, ${modelNameOf("opus")}`,
      `Change Team lead, ${modelNameOf("fable")}`,
      `Change Team lead, ${modelNameOf("opus")}`,
      "Assign Team lead",
    ]);
    expect(actions().map((b) => b.textContent)).toEqual([...Array(6).fill("Change"), "Assign"]);
    // A pool has no seat to staff.
    expect(within(office("builder")).queryByTestId("org-seat-action")).toBeNull();
  });

  it("a preview has View and no Assign or Change", () => {
    presetsResponse = { isLoading: false, data: { presets: PRESETS } };
    draw();
    pick("Executive Suite (S)");
    expect(screen.getAllByTestId("org-office").length).toBeGreaterThan(0);
    expect(screen.queryAllByTestId("org-seat-action")).toHaveLength(0);
  });

  it("while a Staff write is in flight, Assign and Change wait", () => {
    staffWriting = true;
    draw();
    for (const b of actions()) expect((b as HTMLButtonElement).disabled).toBe(true);
  });

  it("Assign on a vacant team lead: the position's default model, the session, a Space, the shared role said", async () => {
    draw();
    const dialog = open("team-lead", "Assign Team lead");
    expect(within(dialog).getByText("Assign Team lead")).toBeTruthy();
    // Every family the model map's current block names, none marked; the position's default chosen.
    expect(
      within(dialog)
        .getAllByRole("radio")
        .map((r) => (r as HTMLInputElement).value),
    ).toEqual(FAMILIES);
    expect(within(dialog).queryByText(/not recommended/)).toBeNull();
    expect(radio(dialog, named("opus")).checked).toBe(true);
    expect((within(dialog).getByTestId("org-seat-session") as HTMLInputElement).value).toBe("");
    expect(within(dialog).getByTestId("org-seat-space")).toBeTruthy();
    // The role title, and the note that it is every seat's, wait behind the link.
    expect(within(dialog).queryByTestId("org-seat-role-title")).toBeNull();
    expect(within(dialog).queryByTestId("org-seat-shared")).toBeNull();
    fireEvent.click(within(dialog).getByRole("button", { name: "Use a different title" }));
    expect(within(dialog).getByTestId("org-seat-shared").textContent).toBe(
      "Team lead has 3 seats: its role name and title change for all of them.",
    );
    fireEvent.click(within(dialog).getByRole("button", { name: "Use a different title" }));
    // The acceptance scenario: the model is filled, the session is the only thing typed.
    fireEvent.change(within(dialog).getByTestId("org-seat-session"), {
      target: { value: "lead-gamma" },
    });
    fireEvent.click(within(dialog).getByTestId("org-seat-save"));
    await waitFor(() => expect(screen.queryByTestId("org-seat-dialog")).toBeNull());
    expect(lastParams()).toEqual([
      "-Seat",
      "team-lead.gamma",
      "-Tree",
      TREE(),
      "-Model",
      "opus",
      "-Session",
      "lead-gamma",
      "-IfMatch",
      TEST_ETAG,
    ]);
  });

  it("Change on a VP: Opus and Fable, Sonnet not recommended, the seat's own model chosen; a Save that changes nothing writes nothing", async () => {
    draw();
    const dialog = open("vp-product", `Change VP of product, ${modelNameOf("fable")}`);
    expect(
      within(dialog)
        .getAllByRole("radio")
        .map((r) => (r as HTMLInputElement).value),
    ).toEqual(["opus", "fable", "sonnet"]);
    expect(
      within(dialog)
        .getAllByRole("radio")
        .map((r) => r.closest("span")?.textContent ?? ""),
    ).toEqual([named("opus"), named("fable"), `${named("sonnet")} (not recommended)`]);
    expect(radio(dialog, named("fable")).checked).toBe(true);
    expect(within(dialog).queryByTestId("org-seat-role-title")).toBeNull();
    expect(within(dialog).queryByTestId("org-seat-space")).toBeNull();
    expect(within(dialog).queryByTestId("org-seat-shared")).toBeNull();
    fireEvent.click(within(dialog).getByTestId("org-seat-save"));
    await waitFor(() => expect(screen.queryByTestId("org-seat-dialog")).toBeNull());
    expect(runStaff).not.toHaveBeenCalled();
  });

  it("only what changed is sent: a new model and a role title", async () => {
    draw();
    const dialog = open("vp-product", `Change VP of product, ${modelNameOf("fable")}`);
    fireEvent.click(radio(dialog, named("opus")));
    fireEvent.click(within(dialog).getByRole("button", { name: "Use a different title" }));
    fireEvent.change(within(dialog).getByTestId("org-seat-role-title"), {
      target: { value: "Head of product" },
    });
    fireEvent.click(within(dialog).getByTestId("org-seat-save"));
    await waitFor(() => expect(runStaff).toHaveBeenCalled());
    expect(lastParams()).toEqual([
      "-Seat",
      "vp-product.vp-product",
      "-Tree",
      TREE(),
      "-Model",
      "opus",
      "-RoleTitle",
      "Head of product",
      "-IfMatch",
      TEST_ETAG,
    ]);
  });

  it("Use a different title opens the field in place, filled with the position's title, focused, its state announced", async () => {
    draw();
    const dialog = open("pm", `Change PM, ${modelNameOf("opus")}`);
    const link = within(dialog).getByRole("button", { name: "Use a different title" });
    expect(link.getAttribute("aria-expanded")).toBe("false");
    fireEvent.click(link);
    expect(link.getAttribute("aria-expanded")).toBe("true");
    const field = within(dialog).getByTestId("org-seat-role-title") as HTMLInputElement;
    expect(field.value).toBe("PM");
    await waitFor(() => expect(document.activeElement).toBe(field));
    expect(link.getAttribute("aria-controls")).toBe(field.closest("[id]")?.id ?? field.id);
    // Left as the position's title, it is not sent.
    fireEvent.change(within(dialog).getByTestId("org-seat-session"), {
      target: { value: "desk-pm" },
    });
    fireEvent.click(within(dialog).getByTestId("org-seat-save"));
    await waitFor(() => expect(runStaff).toHaveBeenCalled());
    expect(lastParams()).not.toContain("-RoleTitle");
  });

  it("a position whose title already differs from its role's opens the field from the start", () => {
    const data = orgResponse("valid");
    for (const p of data.tree.positions) if (p.promptTitle) p.promptTitle = p.title;
    data.tree.positions.find((p) => p.id === "pm")!.title = "Planner";
    response = { isLoading: false, data };
    draw();
    const dialog = open("pm", `Change Planner, ${modelNameOf("opus")}`);
    expect((within(dialog).getByTestId("org-seat-role-title") as HTMLInputElement).value).toBe(
      "Planner",
    );
    expect(
      within(dialog)
        .getByRole("button", { name: "Use a different title" })
        .getAttribute("aria-expanded"),
    ).toBe("true");
  });

  it("a seat holding an older model keeps it as its own named choice, chosen; kept, it sends no -Model", async () => {
    const data = response.data!;
    const vp = data.tree.positions.find((p) => p.id === "vp-engineering")!.seats[0];
    Object.assign(vp, { model: "claude-opus-5", modelName: "Opus 5", modelFamily: "opus" });
    draw();
    const dialog = open("vp-engineering", "Change VP of engineering, Opus 5");
    const labels = within(dialog)
      .getAllByRole("radio")
      .map((r) => r.closest("span")?.textContent ?? "");
    expect(labels).toEqual([
      "Opus 5",
      named("opus"),
      named("fable"),
      `${named("sonnet")} (not recommended)`,
    ]);
    expect(radio(dialog, "Opus 5").checked).toBe(true);
    fireEvent.change(within(dialog).getByTestId("org-seat-session"), {
      target: { value: "desk-one" },
    });
    fireEvent.click(within(dialog).getByTestId("org-seat-save"));
    await waitFor(() => expect(runStaff).toHaveBeenCalled());
    expect(lastParams()).not.toContain("-Model");
  });

  it("picking the family's current model over a held older one is a change, and is sent", async () => {
    const data = response.data!;
    const vp = data.tree.positions.find((p) => p.id === "vp-engineering")!.seats[0];
    Object.assign(vp, { model: "claude-opus-5", modelName: "Opus 5", modelFamily: "opus" });
    draw();
    const dialog = open("vp-engineering", "Change VP of engineering, Opus 5");
    fireEvent.click(radio(dialog, named("opus")));
    fireEvent.click(within(dialog).getByTestId("org-seat-save"));
    await waitFor(() => expect(runStaff).toHaveBeenCalled());
    expect(lastParams()).toEqual([
      "-Seat",
      "vp-engineering.vp-engineering",
      "-Tree",
      TREE(),
      "-Model",
      "opus",
      "-IfMatch",
      TEST_ETAG,
    ]);
  });

  it("the owner's seat asks for the name alone, and a name that starts with a dash travels as the name", async () => {
    draw();
    const dialog = open("owner", "Change Owner, Sam");
    expect(within(dialog).queryAllByRole("radio")).toHaveLength(0);
    expect(within(dialog).queryByTestId("org-seat-session")).toBeNull();
    expect((within(dialog).getByTestId("org-seat-person") as HTMLInputElement).value).toBe("Sam");
    fireEvent.change(within(dialog).getByTestId("org-seat-person"), {
      target: { value: "-WhatIf" },
    });
    fireEvent.click(within(dialog).getByTestId("org-seat-save"));
    await waitFor(() => expect(runStaff).toHaveBeenCalled());
    expect(lastParams()).toEqual([
      "-Seat",
      "owner.owner",
      "-Tree",
      TREE(),
      "-Person:-WhatIf",
      "-IfMatch",
      TEST_ETAG,
    ]);
  });

  it("a team lead's Space is a choice of /env's Spaces, None first, and the seat's own kept", () => {
    draw();
    const dialog = open("team-lead", `Change Team lead, ${modelNameOf("fable")}`);
    fireEvent.click(within(dialog).getByTestId("org-seat-space"));
    expect(screen.getAllByRole("option").map((o) => o.textContent)).toEqual([
      "None",
      "Alpha",
      "Toolkit",
    ]);
  });

  it("a file changed since the page read it: the conflict, said plainly, with Reload; nothing else is offered", async () => {
    staffAnswer = () =>
      Promise.resolve({
        status: "error",
        output: "",
        error: "org.json changed since you read it; reload and try again.",
        duration: 1,
      } as CommandResponse);
    draw();
    const dialog = open("pm", `Change PM, ${modelNameOf("opus")}`);
    fireEvent.change(within(dialog).getByTestId("org-seat-session"), {
      target: { value: "desk-pm" },
    });
    fireEvent.click(within(dialog).getByTestId("org-seat-save"));
    const conflict = await within(dialog).findByTestId("org-seat-conflict");
    expect(conflict.textContent).toContain(CHANGED_SINCE_TEXT);
    // Information, not a failure: no error bar, and it sits in the status region.
    expect(within(dialog).queryByTestId("org-seat-away")).toBeNull();
    expect(conflict.closest('[role="status"]')).toBeTruthy();
    expect((within(dialog).getByTestId("org-seat-save") as HTMLButtonElement).disabled).toBe(true);
    fireEvent.click(within(dialog).getByTestId("org-seat-reload"));
    await waitFor(() => expect(screen.queryByTestId("org-seat-dialog")).toBeNull());
    expect(refetch).toHaveBeenCalled();
  });

  it("any other refusal is the verb's sentence, plainly, in the dialog", async () => {
    staffAnswer = () =>
      Promise.resolve({
        status: "error",
        output: "",
        error: "Some other refusal.",
        duration: 1,
      } as CommandResponse);
    draw();
    const dialog = open("pm", `Change PM, ${modelNameOf("opus")}`);
    fireEvent.change(within(dialog).getByTestId("org-seat-session"), { target: { value: "x" } });
    fireEvent.click(within(dialog).getByTestId("org-seat-save"));
    expect((await within(dialog).findByTestId("org-seat-refusal")).textContent).toBe(
      "Some other refusal.",
    );
    expect(within(dialog).queryByTestId("org-seat-conflict")).toBeNull();
  });

  it("the agent away is the one error", async () => {
    staffAnswer = () => Promise.reject(new Error("away"));
    draw();
    const dialog = open("pm", `Change PM, ${modelNameOf("opus")}`);
    fireEvent.change(within(dialog).getByTestId("org-seat-session"), { target: { value: "x" } });
    fireEvent.click(within(dialog).getByTestId("org-seat-save"));
    expect((await within(dialog).findByTestId("org-seat-away")).textContent).toContain(
      "Could not reach the agent",
    );
  });

  const seatButton = (positionId: string, seatId: string) =>
    within(office(positionId))
      .getAllByTestId("org-seat-action")
      .find((b) => b.dataset.seat === `${positionId}.${seatId}`)!;

  it("Cancel puts focus back on the seat's button", async () => {
    draw();
    open("pm", `Change PM, ${modelNameOf("opus")}`);
    fireEvent.click(screen.getByRole("button", { name: "Cancel" }));
    await waitFor(() => expect(screen.queryByTestId("org-seat-dialog")).toBeNull());
    await waitFor(() => expect(document.activeElement).toBe(seatButton("pm", "pm")));
  });

  it("Escape puts focus back on the seat's button", async () => {
    draw();
    const dialog = open("pm", `Change PM, ${modelNameOf("opus")}`);
    fireEvent.keyDown(within(dialog).getByTestId("org-seat-session"), { key: "Escape" });
    await waitFor(() => expect(screen.queryByTestId("org-seat-dialog")).toBeNull());
    await waitFor(() => expect(document.activeElement).toBe(seatButton("pm", "pm")));
  });

  it("after an Assign is saved, focus lands on the seat's new Change button", async () => {
    const staffed = orgResponse("valid");
    const gamma = staffed.tree.positions
      .find((p) => p.id === "team-lead")!
      .seats.find((x) => x.id === "gamma")!;
    Object.assign(gamma, {
      model: "opus",
      modelName: modelNameOf("opus"),
      modelFamily: "opus",
      session: "lead-gamma",
      state: "staffed",
    });
    staffAnswer = () => {
      // The write lands, and the next read serves the seat staffed, under a new etag.
      response = { isLoading: false, data: { ...staffed, etag: "b".repeat(64) } };
      return Promise.resolve({
        status: "success",
        output: "",
        error: "",
        duration: 1,
      } as CommandResponse);
    };
    draw();
    const dialog = open("team-lead", "Assign Team lead");
    fireEvent.change(within(dialog).getByTestId("org-seat-session"), {
      target: { value: "lead-gamma" },
    });
    fireEvent.click(within(dialog).getByTestId("org-seat-save"));
    await waitFor(() => expect(screen.queryByTestId("org-seat-dialog")).toBeNull());
    await waitFor(() => {
      const button = seatButton("team-lead", "gamma");
      expect(button.textContent).toBe("Change");
      expect(document.activeElement).toBe(button);
    });
  });

  it("Save, Cancel and Close wait for a write already in flight on the page", () => {
    const data = orgResponse("valid");
    const pm = data.tree.positions.find((p) => p.id === "pm")!;
    render(
      <SeatDialog
        position={pm}
        seat={pm.seats[0]}
        treeId={data.tree.id}
        etag={TEST_ETAG}
        families={FAMILIES}
        spaces={[]}
        run={() => Promise.resolve({ status: "success" } as CommandResponse)}
        busy
        onSaved={() => {}}
        onReload={() => {}}
        onClose={() => {}}
      />,
    );
    const dialog = screen.getByTestId("org-seat-dialog");
    for (const name of ["Save", "Cancel", "Close"]) {
      expect((within(dialog).getByRole("button", { name }) as HTMLButtonElement).disabled).toBe(
        true,
      );
    }
  });
});
