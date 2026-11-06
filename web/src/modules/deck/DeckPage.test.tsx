import { act, fireEvent, render, screen, waitFor, within } from "@testing-library/react";
import { MemoryRouter, Route, Routes, useLocation } from "react-router";
import { DeckPage } from "./DeckPage";
import { DECK_AUDIOBOOK_STORAGE_KEY, DECK_PODIUM_STORAGE_KEY } from "./engine/narrationConstants";

// A deck's page: the deck file's facts, Play to the player, and this
// machine's Archive written through Config -- never the deck file.

const mockDeck = {
  id: "the-toolkit",
  title: "Introducing ToolKit",
  state: "complete",
  summary: "A room where cards drift in as envelopes.",
  tags: ["product", "tour"],
  slides: () => mockSlides,
};
let mockSlides: { id: string }[] = [];
// The still is a real slide scaled down; jsdom does no layout and has no
// ResizeObserver, so a stand-in says which slide it was handed.
jest.mock("./SlidePoster", () => ({
  SlidePoster: ({ slide }: { slide: { id: string } }) => <span>{`still of ${slide.id}`}</span>,
}));
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
  mockSlides = [{ id: "a" }, { id: "b" }, { id: "c" }];
  window.localStorage.clear();
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

describe("a deck's page: the still", () => {
  it("shows a still of the deck's first slide", () => {
    at("the-toolkit");
    expect(screen.getByTestId("deck-still").textContent).toBe("still of a");
  });

  it("a deck with no slide to show has no still and no empty box, and reads as before", () => {
    mockSlides = [];
    at("the-toolkit");
    expect(screen.queryByTestId("deck-still")).toBeNull();
    expect(screen.getByText(mockDeck.summary)).toBeTruthy();
  });
});

describe("a deck's page: how a deck opens", () => {
  const openSettings = async () => {
    fireEvent.click(screen.getByRole("button", { name: "Deck settings" }));
    return screen.findByRole("dialog", { name: "Deck settings" });
  };
  const choices = async (dialog: HTMLElement) =>
    (await within(dialog).findAllByRole("radio")).map((r) => r.getAttribute("value"));

  it("the gear opens a dialog with the sheet's words: Mode, Paging, Audiobook, and Podium", async () => {
    at("the-toolkit");
    const dialog = await openSettings();
    expect(within(dialog).getByRole("radiogroup", { name: "Mode" })).toBeTruthy();
    expect(await choices(dialog)).toEqual(["paging", "audiobook", "podium"]);
    expect(
      (within(dialog).getByRole("radio", { name: "Paging" }) as HTMLInputElement).checked,
    ).toBe(true);
  });

  it("choosing Podium is kept in the browser, and Paging takes it back", async () => {
    at("the-toolkit");
    const dialog = await openSettings();
    fireEvent.click(within(dialog).getByRole("radio", { name: "Podium" }));
    expect(window.localStorage.getItem(DECK_PODIUM_STORAGE_KEY)).toBe("1");
    fireEvent.click(within(dialog).getByRole("radio", { name: "Paging" }));
    expect(window.localStorage.getItem(DECK_PODIUM_STORAGE_KEY)).toBe("0");
    expect(window.localStorage.getItem(DECK_AUDIOBOOK_STORAGE_KEY)).toBe("0");
  });

  it("choosing Audiobook is the same setting the player's sheet keeps", async () => {
    at("the-toolkit");
    const dialog = await openSettings();
    fireEvent.click(within(dialog).getByRole("radio", { name: "Audiobook" }));
    expect(window.localStorage.getItem(DECK_AUDIOBOOK_STORAGE_KEY)).toBe("1");
    expect(window.localStorage.getItem(DECK_PODIUM_STORAGE_KEY)).toBe("0");
  });

  it("a phone is not offered Podium, and a remembered Podium reads as the viewer's choice there", async () => {
    window.localStorage.setItem(DECK_PODIUM_STORAGE_KEY, "1");
    const before = window.matchMedia;
    window.matchMedia = ((query: string) => ({
      matches: false,
      media: query,
      addEventListener: () => {},
      removeEventListener: () => {},
    })) as unknown as typeof window.matchMedia;
    try {
      at("the-toolkit");
      const dialog = await openSettings();
      expect(await choices(dialog)).toEqual(["paging", "audiobook"]);
      expect(
        (within(dialog).getByRole("radio", { name: "Paging" }) as HTMLInputElement).checked,
      ).toBe(true);
    } finally {
      window.matchMedia = before;
    }
  });
});
