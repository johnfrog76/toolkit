import { render } from "@testing-library/react";
import { MemoryRouter, Route, Routes } from "react-router";
import DeckHost, { DeckNotesHost } from "./DeckHost";

// The player and the notes window narrate from the same baked clips, so both
// are handed hasApi={false} and a resolver: neither may ask for a service.

const playerProps: Record<string, unknown>[] = [];
const notesProps: Record<string, unknown>[] = [];

jest.mock("./engine/DeckPlayer", () => ({
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
