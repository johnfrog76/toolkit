import { fireEvent, render, screen, within } from "@testing-library/react";
import { MemoryRouter, useLocation } from "react-router";
import { DeckPickerCard } from "./DeckPickerCard";
import { expectListPanelShape } from "../../shell/kinds/panelShapeAssert";

// The Decks panel's card item: the title is plain text, Open is the deck's
// page, the menu is the vocabulary's (Play, and no link out -- no deck carries
// an address of its own), and a deck put away on this machine leaves the
// default list for the archived chip.

jest.mock("./decks/index", () => ({
  get DECKS() {
    return [
      { id: "older", title: "Older Deck", state: "complete", summary: "", slides: () => [] },
      { id: "newer", title: "Newer Deck", state: "complete", summary: "", slides: () => [] },
    ];
  },
}));
jest.mock("./engine/deckDuration", () => ({ estimateDeckDuration: () => "1:00" }));
let mockServed: string[] = [];
jest.mock("../../shell/api", () => ({
  useGetEnvQuery: () => ({ data: { config: { deckArchived: mockServed } } }),
}));

function Where() {
  return <span data-testid="where">{useLocation().pathname}</span>;
}

function card() {
  return render(
    <MemoryRouter initialEntries={["/growth"]}>
      <DeckPickerCard />
      <Where />
    </MemoryRouter>,
  );
}

beforeEach(() => {
  mockServed = [];
});

describe("the Decks card's row", () => {
  it("the title is plain text: a click on it goes nowhere, and Open is the way in", () => {
    const { container } = card();
    fireEvent.click(screen.getByText("Newer Deck"));
    expect(screen.getByTestId("where").textContent).toBe("/growth");
    expectListPanelShape(container.querySelector<HTMLElement>("[data-panel-kind]")!, {
      titles: ["Newer Deck", "Older Deck"],
      total: 2,
    });
  });

  it("its exposed action is Open the deck; its menu plays it, with no link out", async () => {
    card();
    fireEvent.click(screen.getAllByRole("button", { name: "Open the deck" })[0]);
    expect(screen.getByTestId("where").textContent).toBe("/decks/newer");
    fireEvent.click(screen.getByRole("button", { name: "Actions for Older Deck" }));
    const menu = await screen.findByRole("menu");
    expect(
      within(menu)
        .getAllByRole("menuitem")
        .map((m) => m.textContent),
    ).toEqual(["Play"]);
    fireEvent.click(within(menu).getByRole("menuitem", { name: "Play" }));
    expect(screen.getByTestId("where").textContent).toBe("/deck/older");
  });

  it("with nothing put away: both decks, no chips", () => {
    card();
    expect(screen.getByText("Older Deck")).toBeTruthy();
    expect(screen.getByText("Newer Deck")).toBeTruthy();
    expect(screen.queryByRole("group", { name: "Filter decks" })).toBeNull();
  });

  it("a deck put away leaves the default list and sits under the archived chip", () => {
    mockServed = ["older"];
    card();
    expect(screen.queryByText("Older Deck")).toBeNull();
    expect(screen.getByText("Newer Deck")).toBeTruthy();
    const chips = screen.getByRole("group", { name: "Filter decks" });
    fireEvent.click(within(chips).getByText("archived"));
    expect(screen.getByText("Older Deck")).toBeTruthy();
    expect(screen.queryByText("Newer Deck")).toBeNull();
  });
});
