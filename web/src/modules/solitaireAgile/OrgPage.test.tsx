import { fireEvent, render, screen, within } from "@testing-library/react";
import { MemoryRouter, Route, Routes, useLocation } from "react-router";
import type { OrgResponse } from "./api.solitaireAgile";
import { OrgPage, UNKNOWN_TREE_DETAIL } from "./OrgPage";
import { orgResponse } from "./orgFixture";

// The Org tab (docs/modules/solitaire-agile.md, "The web UI"): the tree the
// agent serves, drawn as offices by level, each seat a card with its plate.
// The responses are the SHARED table's (Tests/fixtures/org/charts/), the same
// documents the CLI's reader and the agent's are held to.

let response: { data?: OrgResponse; isLoading: boolean; error?: unknown } = { isLoading: false };
jest.mock("./api.solitaireAgile", () => ({
  useGetOrgChartQuery: () => response,
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
    expect(screen.getByTestId("org-subtitle").textContent).toBe("Laptop and mini");
  });

  it("the lead's three seats are a row of three cards in one office, the vacant one last", () => {
    draw();
    const lead = office("team-lead");
    const seats = within(lead).getAllByTestId("org-seat");
    expect(seats.map((s) => s.dataset.state)).toEqual(["staffed", "staffed", "vacant"]);
    expect(plates(lead)).toEqual(["Team lead · fable", "Team lead · opus", "Team lead · vacant"]);
    expect(wheres(lead)).toEqual(["alpha on mini", "beta on mini", "gamma on mini"]);
  });

  it("a staffed seat: a bust in colour and POSITION · model, with its machine", () => {
    draw();
    const vp = office("vp-product");
    expect(within(vp).getByTestId("org-seat").dataset.state).toBe("staffed");
    expect(vp.querySelector('svg[data-refined="designer"]')).toBeTruthy();
    expect(plates(vp)).toEqual(["VP of product · fable"]);
    expect(wheres(vp)).toEqual(["on laptop"]);
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
