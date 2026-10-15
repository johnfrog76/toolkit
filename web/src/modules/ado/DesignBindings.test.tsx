import { fireEvent, render, screen } from "@testing-library/react";
import { MemoryRouter, Route, Routes, useLocation } from "react-router";
import {
  BoundCards,
  DesignChip,
  boundCardPath,
  chipLabel,
  chipSays,
  designRoom,
} from "./DesignBindings";
import type { BoundCard, CardDesign } from "./api.ado";

// Design bindings (docs/hub/design.md): the card and its design, bound
// both ways. The agent parses the card's line and resolves its id; the page draws
// what it is given -- the chip on the card page, the cards on a design's row.

const ID = "b0a4d1de-5c3e-4f7a-8b21-9d0e6f3a2c11";

function design(over: Partial<CardDesign> = {}): CardDesign {
  return {
    kind: "design",
    title: "Board ideas",
    link: "../../design/board-ideas.md",
    id: ID,
    short: ID.slice(0, 8),
    note: "",
    state: "Design",
    where: "hub",
    path: "design/board-ideas.md",
    ...over,
  };
}

function card(over: Partial<BoundCard> = {}): BoundCard {
  return {
    file: "K7M2-lanes.prompt.md",
    id: "K7M2",
    title: "Task K7M2: Lanes",
    status: "Active",
    space: "demo",
    archived: false,
    ...over,
  };
}

function Where() {
  return <span data-testid="where">{useLocation().pathname}</span>;
}

function inRouter(node: React.ReactNode) {
  return render(
    <MemoryRouter initialEntries={["/prompts/x"]}>
      <Routes>
        <Route
          path="*"
          element={
            <>
              {node}
              <Where />
            </>
          }
        />
      </Routes>
    </MemoryRouter>,
  );
}

describe("the room a card's design opens in", () => {
  it("a hub design opens in the Studio's reading room; a repo's in the Design tab's", () => {
    expect(designRoom(design())).toBe("/studio/design/design/board-ideas.md");
    expect(designRoom(design({ where: "repo", path: "spec/archive/toolkit-card.spec.md" }))).toBe(
      "/design/spec/archive/toolkit-card.spec.md",
    );
  });
  it("a design the agent could not place has no room", () => {
    expect(designRoom(design({ where: "", path: "" }))).toBeNull();
  });
});

describe("the chip's words", () => {
  it("is the short id and the title for a Design line", () => {
    expect(chipLabel(design())).toBe("b0a4d1de Board ideas");
    expect(chipSays(design())).toBe(`Worked against the design ${ID} -- Design`);
  });
  it("unconnected, the line as last written, and says so", () => {
    const d = design({ state: "", where: "", path: "", title: "An old idea" });
    expect(chipLabel(d)).toBe("b0a4d1de An old idea");
    expect(chipSays(d)).toMatch(/as last written$/);
  });
  it("a hand-written Spec line reads as written: its title and its words, no id", () => {
    const d = design({
      kind: "spec",
      id: "",
      short: "",
      title: "Prize-Store.spec.md",
      note: "(D4)",
      state: "",
      where: "",
      path: "",
    });
    expect(chipLabel(d)).toBe("Prize-Store.spec.md (D4)");
    expect(chipSays(d)).toMatch(/hand-written Spec line, read as written$/);
  });
});

describe("DesignChip", () => {
  it("draws nothing for a card that names no design", () => {
    const { container } = inRouter(<DesignChip design={null} />);
    expect(container.querySelector("[data-design-chip]")).toBeNull();
  });
  it("draws the id, the title and the state, and opens the design's room", () => {
    inRouter(<DesignChip design={design()} />);
    expect(screen.getByText("b0a4d1de Board ideas")).toBeTruthy();
    expect(screen.getByText("Design")).toBeTruthy();
    fireEvent.click(screen.getByRole("button", { name: "Open the design Board ideas" }));
    expect(screen.getByTestId("where").textContent).toBe("/studio/design/design/board-ideas.md");
  });
  it("a repo design the agent could not read is a link to its page", () => {
    const { container } = inRouter(
      <DesignChip
        design={design({
          state: "",
          where: "",
          path: "",
          link: "https://github.com/acme/widgets/blob/HEAD/spec/x.spec.md",
        })}
      />,
    );
    expect(
      container.querySelector("a[href='https://github.com/acme/widgets/blob/HEAD/spec/x.spec.md']"),
    ).not.toBeNull();
  });
});

describe("the cards on a design's row", () => {
  it("a card in this Space's current/ opens its page; an archived one, or another Space's, is named only", () => {
    expect(boundCardPath(card(), "demo")).toBe("/prompts/K7M2-lanes.prompt.md");
    expect(boundCardPath(card({ archived: true, status: "Done" }), "demo")).toBeNull();
    expect(boundCardPath(card({ space: "toolkit" }), "demo")).toBeNull();
    expect(boundCardPath(card(), undefined)).toBe("/prompts/K7M2-lanes.prompt.md");
  });
  it("draws nothing when no card names the design", () => {
    const { container } = inRouter(<BoundCards cards={[]} />);
    expect(container.querySelector("[role='group']")).toBeNull();
  });
  it("draws each card's id and state, and a click opens the card", () => {
    inRouter(
      <BoundCards
        activeSpace="demo"
        cards={[
          card(),
          card({
            file: "Q4TN-zero.prompt.md",
            id: "Q4TN",
            status: "Done",
            archived: true,
            space: "toolkit",
          }),
        ]}
      />,
    );
    expect(screen.getByRole("group", { name: "Cards worked against this design" })).toBeTruthy();
    expect(screen.getByText("2 cards")).toBeTruthy();
    expect(screen.getByText("Q4TN Done (toolkit)")).toBeTruthy();
    fireEvent.click(screen.getByText("K7M2 Active"));
    expect(screen.getByTestId("where").textContent).toBe("/prompts/K7M2-lanes.prompt.md");
  });
});
