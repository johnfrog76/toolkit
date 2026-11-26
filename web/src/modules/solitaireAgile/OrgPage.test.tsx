import { cleanup, fireEvent, render, screen, within } from "@testing-library/react";
import { MemoryRouter, Route, Routes, useLocation } from "react-router";
import type { OrgPreset, OrgResponse } from "./api.solitaireAgile";
import {
  ORG_PAGE_TITLE,
  OrgPage,
  UNKNOWN_TREE_DETAIL,
  YOUR_ORG_LABEL,
  presetLabel,
  presetSizeWord,
} from "./OrgPage";
import { modelNameOf, orgResponse } from "./orgFixture";

// The Org tab (docs/modules/solitaire-agile.md, "The web UI"): the tree the
// agent serves, drawn as offices by level, each seat a card with its plate.
// The responses are the SHARED table's (Tests/fixtures/org/charts/), the same
// documents the CLI's reader and the agent's are held to.

let response: { data?: OrgResponse; isLoading: boolean; error?: unknown } = { isLoading: false };
let presetsResponse: { data?: { presets: OrgPreset[] }; isLoading: boolean } = { isLoading: false };
jest.mock("./api.solitaireAgile", () => ({
  useGetOrgChartQuery: () => response,
  useGetOrgPresetsQuery: () => presetsResponse,
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
const plates = (el: HTMLElement) =>
  within(el)
    .getAllByTestId("org-plate-line")
    .map((p) => p.textContent);
const wheres = (el: HTMLElement) =>
  within(el)
    .queryAllByTestId("org-plate-where")
    .map((p) => p.textContent);

beforeEach(() => {
  response = { isLoading: false, data: orgResponse("valid") };
  presetsResponse = { isLoading: false };
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
    expect(plates(lead)).toEqual([
      `Team lead · ${modelNameOf("fable")}`,
      `Team lead · ${modelNameOf("opus")}`,
      "Team lead · vacant",
    ]);
    expect(wheres(lead)).toEqual(["alpha", "beta", "gamma"]);
  });

  it("a staffed seat: a bust in colour and POSITION · the model's name, and no machine", () => {
    draw();
    const vp = office("vp-product");
    expect(within(vp).getByTestId("org-seat").dataset.state).toBe("staffed");
    expect(vp.querySelector('svg[data-refined="designer"]')).toBeTruthy();
    expect(plates(vp)).toEqual([`VP of product · ${modelNameOf("fable")}`]);
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

  it("the owner is a person: the position and the name, no model, no where", () => {
    draw();
    const owner = office("owner");
    expect(plates(owner)).toEqual(["Owner · Sam"]);
    expect(wheres(owner)).toEqual([]);
    expect(owner.querySelector('svg[data-refined="owner"]')).toBeTruthy();
  });

  it("the builders are a pool: one card, POSITION · pool, and the default-model line", () => {
    draw();
    const pool = office("builder");
    const seats = within(pool).getAllByTestId("org-seat");
    expect(seats.map((s) => s.dataset.state)).toEqual(["pool"]);
    expect(plates(pool)).toEqual(["Builder · pool"]);
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

  it("an office with a prompt is a link into the reading room, under its prompt's title", () => {
    draw();
    const pm = office("pm");
    expect(pm.tagName).toBe("A");
    expect(pm.getAttribute("href")).toBe("/studio/prompts/yours/pm");
    expect(within(pm).getByText("pm")).toBeTruthy();
    expect(office("team-lead").getAttribute("href")).toBe("/studio/prompts/yours/team-lead");
    fireEvent.click(pm);
    expect(screen.getByTestId("where").textContent).toBe("/studio/prompts/yours/pm");
  });

  it("the owner and the pool have no prompt, and are not links", () => {
    draw();
    for (const id of ["owner", "builder"]) {
      expect(office(id).tagName).toBe("DIV");
      expect(office(id).getAttribute("href")).toBeNull();
    }
    expect(screen.getAllByRole("link")).toHaveLength(4);
  });

  it("a prompt the reading room does not list has its title and no link", () => {
    const data = orgResponse("valid");
    const pm = data.tree.positions.find((p) => p.id === "pm")!;
    pm.promptTitle = "Notes";
    pm.promptRef = null;
    response = { isLoading: false, data };
    draw();
    expect(office("pm").tagName).toBe("DIV");
    expect(within(office("pm")).getByText("Notes")).toBeTruthy();
  });

  it("a seat's own roleTitle stands in for the position's title, and its session is on hover", () => {
    response = { isLoading: false, data: orgResponse("the-shape-complete") };
    draw();
    expect(screen.getByTestId("org-heading").textContent).toBe("The Branch Office");
    const lead = office("team-lead");
    expect(plates(lead)).toEqual([
      "Alpha lead · Opus 5.5",
      "Team lead · a-model-the-map-does-not-know",
    ]);
    const [alpha, beta] = within(lead).getAllByTestId("org-plate");
    expect(alpha.getAttribute("title")).toBe("Alpha lead · Opus 5.5, alpha. Session: lead-session");
    expect(beta.getAttribute("title")).toBe("Team lead · a-model-the-map-does-not-know, beta");
    expect(plates(office("vp-product"))).toEqual(["VP of product · Fable 5.2"]);
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

  it("opens on your org: the hub's chart under its own name, with no description and no size", () => {
    draw();
    expect(screen.getByTestId("org-preset-select").textContent).toContain(YOUR_ORG_LABEL);
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

  it("offers your org, then the presets smallest first", () => {
    draw();
    fireEvent.click(screen.getByTestId("org-preset-select"));
    expect(screen.getAllByRole("option").map((o) => o.textContent)).toEqual([
      YOUR_ORG_LABEL,
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
    pick(YOUR_ORG_LABEL);
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
    expect(screen.getByText("No org chart yet")).toBeTruthy();
    pick("Corporate Headquarters (L)");
    expect(screen.queryByText("No org chart yet")).toBeNull();
    expect(positions()).toContain("pm");
  });

  it("with no preset served, the page is the hub's chart alone", () => {
    presetsResponse = { isLoading: false };
    draw();
    expect(screen.queryByTestId("org-presets")).toBeNull();
  });
});

describe("the heading with no chart", () => {
  it("is the page's own name while there is no org.json and no preset picked", () => {
    presetsResponse = { isLoading: false, data: { presets: PRESETS } };
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

  it("the offices inside the scaled chart are still links", () => {
    draw();
    fireEvent.click(zoomButton("Zoom out"));
    fireEvent.click(office("pm"));
    expect(screen.getByTestId("where").textContent).toBe("/studio/prompts/yours/pm");
  });
});

/** Draw again from nothing, so the next first frame measures the new width. */
function cleanupAndDraw() {
  cleanup();
  draw();
}
