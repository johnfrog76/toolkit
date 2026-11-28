import { render, screen } from "@testing-library/react";
import { MemoryRouter } from "react-router";
import { DeckPickerCard } from "./DeckPickerCard";

// The Decks card, drawn from the REAL registry: it is what fills Growth's slot, so
// every deck this Toolkit ships is a card in it, by title. (deckList.test.ts holds
// the rules; the other card suites stand decks in, to stay light.)

jest.mock("./engine/deckDuration", () => ({ estimateDeckDuration: () => 60 }));
jest.mock("../../shell/api", () => ({
  useGetEnvQuery: () => ({ data: { config: { deckArchived: [] } } }),
}));

describe("the Decks card, with the decks this Toolkit ships", () => {
  it("draws the Prompt Poet's card beside the commercial's and Connected Deck's", () => {
    render(
      <MemoryRouter>
        <DeckPickerCard />
      </MemoryRouter>,
    );
    for (const title of [
      "The Prompt Poet Works the Board",
      "Introducing ToolKit",
      "Trailer — The Connected Deck Universe",
    ]) {
      expect(screen.getAllByText(title).length).toBeGreaterThan(0);
    }
  });
});
