/**
 * Zen Word Scrape asks nothing: a ring, a quiet list, no score. The list is
 * honest (every word lowercase letters, no duplicates), every ring has
 * enough inside it, typing and clicking both spell, Enter keeps a real word
 * and lets a false one go, the ring is there tomorrow, and a spent ring
 * gives way -- moving a worn, animated tank on, and nothing else. D-L21.
 */
import { render, screen, fireEvent } from "@testing-library/react";
import { WORDS_KEY, WordRing, isWordsState } from "./WordRing";
import { RING_MIN_OTHERS, RING_WORDS, WORDS, canMake, isWord, nextRing, wordsFrom } from "./words";
import { writeSkinGrant, parseSkinGrant } from "../../shared/skinGrant";
import { TANK_SCENES } from "./skins";

beforeEach(() => {
  window.localStorage.clear();
});

function visibleText(container: HTMLElement): string {
  const clone = container.cloneNode(true) as HTMLElement;
  clone.querySelectorAll("style, svg").forEach((el) => el.remove());
  return clone.textContent ?? "";
}

function seed(ring: string, found: string[] = []) {
  window.localStorage.setItem(WORDS_KEY, JSON.stringify({ ring, letters: ring, found }));
}

function type(group: HTMLElement, word: string) {
  for (const ch of word) fireEvent.keyDown(group, { key: ch });
}

describe("the words", () => {
  it("are lowercase letters, three or more, each once", () => {
    expect(WORDS.length).toBeGreaterThan(150);
    expect(WORDS.every((w) => /^[a-z]{3,}$/.test(w))).toBe(true);
    expect(new Set(WORDS).size).toBe(WORDS.length);
  });

  it("the everyday words a ring's letters make are in the list -- meat and seam", () => {
    // The first ring the owner played: [m,e,a,s,t] refused MEAT and SEAM.
    // A drafted list of calm words is not a dictionary; the common short words
    // inside every ring have to be there too, or the ring lies.
    const inside = wordsFrom("meats");
    for (const w of [
      "meat",
      "seam",
      "team",
      "mate",
      "tame",
      "same",
      "seat",
      "east",
      "eats",
      "ate",
      "met",
      "mast",
      "stem",
      "teas",
    ]) {
      expect(inside).toContain(w);
    }
    expect(WORDS.length).toBeGreaterThan(700);
  });

  it("every ring word holds enough other words, and there are rings to spare", () => {
    expect(RING_WORDS.length).toBeGreaterThanOrEqual(12);
    for (const r of RING_WORDS) {
      expect([5, 6]).toContain(r.length);
      expect(wordsFrom(r).length - 1).toBeGreaterThanOrEqual(RING_MIN_OTHERS);
    }
    expect(canMake("pea", "peace")).toBe(true);
    expect(canMake("peep", "peace")).toBe(false);
    expect(isWord("peace")).toBe(true);
    expect(isWord("hydra")).toBe(false);
  });

  it("the next ring is never the one just spent, and keeps its letters", () => {
    const only = nextRing("stream", () => 0);
    expect(only.ring).not.toBe("stream");
    expect(only.letters.split("").sort().join("")).toBe(only.ring.split("").sort().join(""));
  });
});

describe("the word ring", () => {
  it("shows the ring's letters, a place for your word, and no digit", () => {
    seed("peace");
    const { container } = render(<WordRing />);
    expect(screen.getAllByRole("button", { name: /^letter / })).toHaveLength(5);
    expect(screen.getByRole("button", { name: "New ring" })).toBeTruthy();
    expect(visibleText(container)).not.toMatch(/\d/);
    expect(container.querySelectorAll("input, textarea, a")).toHaveLength(0);
    // The word is a named status -- a polite live region that may carry
    // its label, where a labelled bare div may not.
    expect(screen.getByRole("status", { name: "your word" })).toBeTruthy();
  });

  it("typing spells, Enter keeps a real word, a false one goes quietly, a click spells too", () => {
    seed("peace");
    render(<WordRing />);
    const group = screen.getByRole("group", { name: "Word ring" });
    type(group, "pea");
    expect(screen.getByLabelText("your word").textContent).toBe("pea");
    fireEvent.keyDown(group, { key: "Enter" });
    expect(screen.getByRole("list", { name: "words kept" }).textContent).toBe("pea");
    type(group, "pcae");
    fireEvent.keyDown(group, { key: "Enter" });
    expect(screen.getByRole("list", { name: "words kept" }).textContent).toBe("pea");
    // A letter the ring does not have, or has no more of, is not taken.
    type(group, "zpp");
    expect(screen.getByLabelText("your word").textContent).toBe("p");
    fireEvent.keyDown(group, { key: "Escape" });
    expect(screen.getByLabelText("your word").textContent).toBe("");
    fireEvent.click(screen.getAllByRole("button", { name: "letter a" })[0]);
    fireEvent.click(screen.getAllByRole("button", { name: "letter c" })[0]);
    fireEvent.click(screen.getAllByRole("button", { name: "letter e" })[0]);
    fireEvent.keyDown(group, { key: "Enter" });
    expect(screen.getByRole("list", { name: "words kept" }).textContent).toBe("peaace");
    expect(JSON.parse(window.localStorage.getItem(WORDS_KEY) ?? "null").found).toEqual([
      "pea",
      "ace",
    ]);
  });

  it("a spent ring gives way to another, and moves a worn, animated tank on -- a still one stays", () => {
    const ring = "peace";
    const inside = wordsFrom(ring);
    const lagoon = TANK_SCENES.find((s) => s.id === "lagoon")!;
    writeSkinGrant({ skinId: "tank", src: lagoon.src, caption: lagoon.caption, animate: false });
    seed(ring, inside.slice(0, -1));
    render(<WordRing />);
    const group = screen.getByRole("group", { name: "Word ring" });
    const last = inside[inside.length - 1];
    type(group, last);
    fireEvent.keyDown(group, { key: "Enter" });
    const after = JSON.parse(window.localStorage.getItem(WORDS_KEY) ?? "null");
    expect(isWordsState(after)).toBe(true);
    expect(after.ring).not.toBe(ring);
    expect(after.found).toEqual([]);
    expect(parseSkinGrant(window.localStorage.getItem("toolkit-skin-grant"))?.src).toBe(lagoon.src);

    // Animated: the tank turns to the next scene.
    writeSkinGrant({ skinId: "tank", src: lagoon.src, caption: lagoon.caption, animate: true });
    seed(ring, inside.slice(0, -1));
    render(<WordRing />);
    const groups = screen.getAllByRole("group", { name: "Word ring" });
    type(groups[1], last);
    fireEvent.keyDown(groups[1], { key: "Enter" });
    const ix = TANK_SCENES.findIndex((s) => s.id === "lagoon");
    expect(parseSkinGrant(window.localStorage.getItem("toolkit-skin-grant"))?.src).toBe(
      TANK_SCENES[(ix + 1) % TANK_SCENES.length].src,
    );
  });

  it("an unreadable saved ring reads as a fresh one, never as a crash", () => {
    window.localStorage.setItem(WORDS_KEY, JSON.stringify({ ring: 4 }));
    render(<WordRing />);
    expect(screen.getAllByRole("button", { name: /^letter / }).length).toBeGreaterThanOrEqual(5);
  });
});
