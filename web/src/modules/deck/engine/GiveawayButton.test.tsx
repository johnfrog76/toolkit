import { render, screen } from "@testing-library/react";
import { DeckContext } from "./deckContext";
import { GIVEAWAY_TITLE, GiveawayButton, isDarkBehind } from "./GiveawayButton";
import { CONNECTED_DECK_REPO_URL, TOOLKIT_REPO_URL, giveawayUrlFor } from "./deckLinks";
import type { Deck } from "../decks/types";

// The giveaway button's whole contract: it is a link, its target follows the
// deck's project, and its contrast follows the stage. No deck configures it.

const deck = (over: Partial<Deck> = {}): Deck => ({
  id: "d",
  title: "D",
  summary: "",
  slides: () => [],
  ...over,
});

describe("GiveawayButton", () => {
  it("is a link that opens the repo in a new tab, never a copy button", () => {
    render(<GiveawayButton />);
    const a = screen.getByRole("link", { name: GIVEAWAY_TITLE });
    expect(a.getAttribute("target")).toBe("_blank");
    expect(a.getAttribute("rel")).toContain("noopener");
    expect(screen.queryByRole("button")).toBeNull();
  });

  it("hands out connected-deck when no deck is around it (poster wall, details, footer)", () => {
    render(<GiveawayButton />);
    expect(screen.getByRole("link").getAttribute("href")).toBe(CONNECTED_DECK_REPO_URL);
  });

  it("follows the deck's project", () => {
    const { rerender } = render(
      <DeckContext.Provider value={deck({ project: "toolkit" })}>
        <GiveawayButton />
      </DeckContext.Provider>,
    );
    expect(screen.getByRole("link").getAttribute("href")).toBe(TOOLKIT_REPO_URL);
    rerender(
      <DeckContext.Provider value={deck({ project: "wasteland" })}>
        <GiveawayButton />
      </DeckContext.Provider>,
    );
    expect(screen.getByRole("link").getAttribute("href")).toBe(CONNECTED_DECK_REPO_URL);
    rerender(
      <DeckContext.Provider value={deck({ project: "connected-deck" })}>
        <GiveawayButton />
      </DeckContext.Provider>,
    );
    expect(screen.getByRole("link").getAttribute("href")).toBe(CONNECTED_DECK_REPO_URL);
  });

  it("giveawayUrlFor never returns nothing", () => {
    expect(giveawayUrlFor(undefined)).toBe(CONNECTED_DECK_REPO_URL);
    expect(giveawayUrlFor("toolkit")).toBe(TOOLKIT_REPO_URL);
  });

  it("sits in the stage's bottom-right unless the composition places it inline", () => {
    const { rerender } = render(<GiveawayButton />);
    expect(screen.getByRole("link").style.position).toBe("absolute");
    rerender(<GiveawayButton inline />);
    expect(screen.getByRole("link").style.position).toBe("");
  });

  it("reads its contrast off the stage behind it", () => {
    const light = document.createElement("div");
    light.style.backgroundColor = "rgb(244, 242, 236)";
    const child = document.createElement("span");
    light.appendChild(child);
    document.body.appendChild(light);
    expect(isDarkBehind(child)).toBe(false);

    const dark = document.createElement("div");
    dark.style.backgroundColor = "#0b1316";
    const child2 = document.createElement("span");
    dark.appendChild(child2);
    document.body.appendChild(dark);
    expect(isDarkBehind(child2)).toBe(true);

    // nothing painted: the house default is a dark stage
    const bare = document.createElement("div");
    const child3 = document.createElement("span");
    bare.appendChild(child3);
    document.body.appendChild(bare);
    expect(isDarkBehind(child3)).toBe(true);
  });
});
