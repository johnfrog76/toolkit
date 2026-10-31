import { render, screen } from "@testing-library/react";
import { MemoryRouter } from "react-router";
import { DeckPickerCard } from "./DeckPickerCard";

// Axe's button-name (critical): the Decks card's tag filter is a Fluent
// Dropdown whose only text is its value ("All"); it carries an aria-label, a
// contract held here. The decks are two stand-ins with tags, so the filter
// draws -- the real list pulls in every deck's source.

jest.mock("./decks/index", () => ({
  DECKS: [
    { slug: "one", title: "One", tags: ["css"], slides: () => [] },
    { slug: "two", title: "Two", tags: ["ritual"], slides: () => [] },
  ],
}));
jest.mock("./engine/deckDuration", () => ({ estimateDeckDuration: () => 60 }));
jest.mock("../../shell/api", () => ({
  useGetEnvQuery: () => ({ data: { config: { deckArchived: [] } } }),
}));

describe("the Decks card's filter", () => {
  it("is named Tag", () => {
    render(
      <MemoryRouter>
        <DeckPickerCard />
      </MemoryRouter>,
    );
    expect(screen.getByRole("combobox", { name: "Tag" })).toBeTruthy();
  });
});
