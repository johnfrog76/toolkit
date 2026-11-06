import { act, render } from "@testing-library/react";
import { MemoryRouter, Route, Routes } from "react-router";
import DeckHost, { DeckNotesHost } from "./DeckHost";
import { DECK_AUDIOBOOK_STORAGE_KEY, DECK_PODIUM_STORAGE_KEY } from "./engine/narrationConstants";

// The player and the notes window narrate from the same baked clips, so both
// are handed hasApi={false} and a resolver: neither may ask for a service.

const playerProps: Record<string, unknown>[] = [];
const notesProps: Record<string, unknown>[] = [];

jest.mock("./engine/DeckPlayer", () => ({
  ALL_DECK_MODES: ["audience", "presenter"],
  DeckPlayer: (props: Record<string, unknown>) => {
    playerProps.push(props);
    return null;
  },
}));
jest.mock("./engine/PresenterNotes", () => ({
  PresenterNotes: (props: Record<string, unknown>) => {
    notesProps.push(props);
    return null;
  },
}));
jest.mock("./bakedVoices", () => ({
  BAKED_VOICES: [{ id: "v1", label: "V1" }],
  voiceUrl: () => null,
}));
jest.mock("./decks/index", () => ({ DECKS: [] }));
jest.mock("./DeckRoom", () => ({
  DeckRoom: ({ children }: { children: React.ReactNode }) => <>{children}</>,
}));

beforeEach(() => {
  playerProps.length = 0;
  notesProps.length = 0;
  window.localStorage.clear();
});

const mountPlayer = () =>
  render(
    <MemoryRouter initialEntries={["/deck/x"]}>
      <Routes>
        <Route path="/deck/:deckId" element={<DeckHost />} />
      </Routes>
    </MemoryRouter>,
  );
const last = () => playerProps[playerProps.length - 1];

describe("DeckHost -- a listed deck's Paging or Audiobook, kept per browser", () => {
  it("opens in Paging by default, with the choice offered", () => {
    mountPlayer();
    expect(last().audiobook).toBe(false);
    expect(typeof last().onAudiobookChange).toBe("function");
  });

  it("a choice of Audiobook is stored and opens the next deck in Audiobook", () => {
    const first = mountPlayer();
    act(() => {
      (last().onAudiobookChange as (next: boolean) => void)(true);
    });
    expect(last().audiobook).toBe(true);
    expect(window.localStorage.getItem(DECK_AUDIOBOOK_STORAGE_KEY)).toBe("1");
    first.unmount();

    mountPlayer();
    expect(last().audiobook).toBe(true);
  });

  it("Paging chosen back is stored too", () => {
    window.localStorage.setItem(DECK_AUDIOBOOK_STORAGE_KEY, "1");
    mountPlayer();
    act(() => {
      (last().onAudiobookChange as (next: boolean) => void)(false);
    });
    expect(window.localStorage.getItem(DECK_AUDIOBOOK_STORAGE_KEY)).toBe("0");
    expect(last().audiobook).toBe(false);
  });
});

describe("DeckHost -- both windows get the same narration facts", () => {
  it("the player is mounted with hasApi false and a resolver", () => {
    render(
      <MemoryRouter initialEntries={["/deck/x"]}>
        <Routes>
          <Route path="/deck/:deckId" element={<DeckHost />} />
        </Routes>
      </MemoryRouter>,
    );
    expect(playerProps[0].hasApi).toBe(false);
    expect(typeof playerProps[0].resolveNarrationUrl).toBe("function");
  });

  it("the notes window is mounted with hasApi false, the baked voices and a resolver", () => {
    render(
      <MemoryRouter initialEntries={["/deck/x/notes"]}>
        <Routes>
          <Route path="/deck/:deckId/notes" element={<DeckNotesHost />} />
        </Routes>
      </MemoryRouter>,
    );
    expect(notesProps[0].hasApi).toBe(false);
    expect(typeof notesProps[0].resolveNarrationUrl).toBe("function");
    expect(notesProps[0].voices).toBeDefined();
  });
});

describe("DeckHost -- Podium, chosen on the deck's page and kept per browser", () => {
  const mountAt = (entry: string) =>
    render(
      <MemoryRouter initialEntries={[entry]}>
        <Routes>
          <Route path="/deck/:deckId" element={<DeckHost />} />
        </Routes>
      </MemoryRouter>,
    );

  it("opens on the viewer's bar when nothing is remembered", () => {
    mountAt("/deck/x");
    expect(last().mode).toBe("audience");
  });

  it("opens in Podium when the page's choice was Podium", () => {
    window.localStorage.setItem(DECK_PODIUM_STORAGE_KEY, "1");
    mountAt("/deck/x");
    expect(last().mode).toBe("presenter");
  });

  it("?present=0 wins over a remembered Podium, for that viewing", () => {
    window.localStorage.setItem(DECK_PODIUM_STORAGE_KEY, "1");
    mountAt("/deck/x?present=0");
    expect(last().mode).toBe("audience");
    expect(window.localStorage.getItem(DECK_PODIUM_STORAGE_KEY)).toBe("1");
  });

  it("?present=1 is Podium with nothing remembered, as it always was", () => {
    mountAt("/deck/x?present=1");
    expect(last().mode).toBe("presenter");
  });
});
