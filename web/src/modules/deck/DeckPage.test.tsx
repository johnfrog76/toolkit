import { act, fireEvent, render, screen, waitFor } from "@testing-library/react";
import { MemoryRouter, Route, Routes, useLocation } from "react-router";
import { DeckPage } from "./DeckPage";

// A deck's page: the deck file's facts, Play to the player, and this
// machine's Archive written through Config -- never the deck file.

const mockDeck = {
  id: "the-toolkit",
  title: "Introducing ToolKit",
  state: "complete",
  summary: "A room where cards drift in as envelopes.",
  tags: ["product", "tour"],
  slides: () => [{ id: "a" }, { id: "b" }, { id: "c" }],
};
jest.mock("./decks/index", () => ({
  get DECKS() {
    return [mockDeck];
  },
}));
jest.mock("./engine/deckDuration", () => ({ estimateDeckDuration: () => "4:30" }));

let mockServed: string[] = [];
jest.mock("../../shell/api", () => ({
  useGetEnvQuery: () => ({ data: { config: { deckArchived: mockServed } } }),
}));
const mockWriteConfig = jest.fn();
jest.mock("../ado/api.ado", () => ({
  useWriteConfigMutation: () => [mockWriteConfig, { isLoading: false }],
}));

function Where() {
  return <span data-testid="where">{useLocation().pathname}</span>;
}

function at(id: string) {
  return render(
    <MemoryRouter initialEntries={[`/decks/${id}`]}>
      <Routes>
        <Route path="/decks/:deckId" element={<DeckPage />} />
        <Route path="*" element={null} />
      </Routes>
      <Where />
    </MemoryRouter>,
  );
}

beforeEach(() => {
  mockServed = [];
  mockWriteConfig.mockReset();
  mockWriteConfig.mockReturnValue({
    unwrap: () => Promise.resolve({ result: { status: "success", output: "" }, config: {} }),
  });
});

async function openMenu() {
  fireEvent.click(screen.getByRole("button", { name: "Actions for Introducing ToolKit" }));
  return screen.findByRole("menu");
}

describe("a deck's page", () => {
  it("shows what the deck file says: title, summary, state, tags, slides, running time, played copy", () => {
    at("the-toolkit");
    expect(screen.getByRole("heading", { name: "Introducing ToolKit" })).toBeTruthy();
    expect(screen.getByText(mockDeck.summary)).toBeTruthy();
    const facts = screen.getByLabelText("About this deck");
    expect(facts.textContent).toContain("complete");
    expect(facts.textContent).toContain("product");
    expect(facts.textContent).toContain("tour");
    expect(facts.textContent).toContain("3");
    expect(facts.textContent).toContain("about 4:30");
    expect(screen.getByText("web/src/modules/deck/decks/the-toolkit.tsx")).toBeTruthy();
  });

  it("Play is the one exposed action, and opens the player", () => {
    at("the-toolkit");
    fireEvent.click(screen.getByRole("button", { name: "Play" }));
    expect(screen.getByTestId("where").textContent).toBe("/deck/the-toolkit");
  });

  it("Archive writes this machine's list through Config, and nothing else", async () => {
    at("the-toolkit");
    await openMenu();
    expect(screen.queryByRole("menuitem", { name: /^Open on/ })).toBeNull();
    await act(async () => {
      fireEvent.click(screen.getByRole("menuitem", { name: "Archive" }));
    });
    expect(mockWriteConfig).toHaveBeenCalledWith({
      set: { "deck.archived": ["the-toolkit"] },
      unset: [],
    });
  });

  it("an archived deck says so, and Unarchive brings it back", async () => {
    mockServed = ["the-toolkit"];
    at("the-toolkit");
    expect(screen.getByText("archived on this machine")).toBeTruthy();
    await openMenu();
    expect(screen.queryByRole("menuitem", { name: "Archive" })).toBeNull();
    await act(async () => {
      fireEvent.click(screen.getByRole("menuitem", { name: "Unarchive" }));
    });
    expect(mockWriteConfig).toHaveBeenCalledWith({ set: {}, unset: ["deck.archived"] });
  });

  it("a refused write is said in the verb's words", async () => {
    mockWriteConfig.mockReturnValue({
      unwrap: () =>
        Promise.resolve({
          result: { status: "error", output: "", error: "Error: no such key." },
          config: {},
        }),
    });
    at("the-toolkit");
    await openMenu();
    await act(async () => {
      fireEvent.click(screen.getByRole("menuitem", { name: "Archive" }));
    });
    await waitFor(() => expect(screen.getByText(/no such key/)).toBeTruthy());
  });

  it("an id no deck carries is an empty state, not a blank page", () => {
    at("nope");
    expect(screen.getByText("No deck nope")).toBeTruthy();
    expect(screen.queryByRole("button", { name: "Play" })).toBeNull();
  });
});
