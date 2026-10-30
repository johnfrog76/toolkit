import fs from "node:fs";
import path from "node:path";
import { DeckState } from "./decks/types";
import {
  ARCHIVED_FILTER,
  DECK_ARCHIVED_KEY,
  archiveEdit,
  archivedIds,
  deckFilePath,
  deckListView,
} from "./deckList";
import type { DeckFilter } from "./deckList";

// The Decks card's rules as one table (docs/modules/deck.md, "A deck's page"):
// what the default list holds with decks put away on this machine, what each
// chip shows, and the Config edit Archive and Unarchive send. The scenarios
// grid (shell/scenarios.test.tsx) carries the card's row of it.

const A = { id: "a", state: DeckState.Complete };
const B = { id: "b", state: DeckState.Complete };
const C = { id: "c", state: DeckState.Draft };

describe("the Decks card's list", () => {
  const rows: [string, (typeof A)[], string[], DeckFilter, string[], boolean, boolean][] = [
    // what, decks, put away, filter, shown, state chips, archived chip
    ["nothing put away: every deck, no chips", [A, B], [], null, ["a", "b"], false, false],
    ["one put away: the default list leaves it out", [A, B], ["b"], null, ["a"], false, true],
    [
      "one put away: the archived chip shows it",
      [A, B],
      ["b"],
      ARCHIVED_FILTER,
      ["b"],
      false,
      true,
    ],
    ["every deck put away: the default list is empty", [A, B], ["a", "b"], null, [], false, true],
    ["an id that names no deck is ignored", [A, B], ["gone"], null, ["a", "b"], false, false],
    [
      "two states: state chips, counted over the default list",
      [A, C],
      [],
      null,
      ["a", "c"],
      true,
      false,
    ],
    ["a state chip narrows the default list", [A, C], [], DeckState.Draft, ["c"], true, false],
    [
      "putting the draft away leaves one state: no state chips",
      [A, C],
      ["c"],
      null,
      ["a"],
      false,
      true,
    ],
    [
      "a deck whose own state is archive is still in the default list",
      [{ id: "x", state: DeckState.Archive }],
      [],
      null,
      ["x"],
      false,
      false,
    ],
  ];
  for (const [what, decks, away, filter, shown, states, archived] of rows) {
    it(what, () => {
      const v = deckListView(decks, away, filter);
      expect(v.shown.map((d) => d.id)).toEqual(shown);
      expect(v.showStates).toBe(states);
      expect(v.showArchived).toBe(archived);
    });
  }
});

describe("the put-away list, written through Config", () => {
  it("Archive adds the id to the whole list, once", () => {
    expect(archiveEdit([], "a", true)).toEqual({ set: { [DECK_ARCHIVED_KEY]: ["a"] }, unset: [] });
    expect(archiveEdit(["b"], "a", true)).toEqual({
      set: { [DECK_ARCHIVED_KEY]: ["b", "a"] },
      unset: [],
    });
    expect(archiveEdit(["a"], "a", true)).toEqual({
      set: { [DECK_ARCHIVED_KEY]: ["a"] },
      unset: [],
    });
  });

  it("Unarchive takes it out, and the last one out unsets the key", () => {
    expect(archiveEdit(["a", "b"], "a", false)).toEqual({
      set: { [DECK_ARCHIVED_KEY]: ["b"] },
      unset: [],
    });
    expect(archiveEdit(["a"], "a", false)).toEqual({ set: {}, unset: [DECK_ARCHIVED_KEY] });
  });

  it("is the machine key the CLI's schema names", () => {
    const schema = fs.readFileSync(
      path.join(__dirname, "..", "..", "..", "..", "Scripts", "Get-ConfigSchema.ps1"),
      "utf8",
    );
    expect(schema).toContain(`-Key '${DECK_ARCHIVED_KEY}' -Scope 'machine' -Type 'array'`);
  });

  it("reads a served list as strings, each once", () => {
    expect(archivedIds(undefined)).toEqual([]);
    expect(archivedIds(["a", "a", "", 3, "b"])).toEqual(["a", "b"]);
  });
});

describe("the played copy", () => {
  // The page shows deckFilePath(id): a deck file is named for its id. Read from
  // the files, not by importing them, so the rule holds for every deck in decks/.
  const dir = path.join(__dirname, "decks");
  const declared = fs
    .readdirSync(dir)
    .filter((f) => f.endsWith(".tsx"))
    .flatMap((f) => {
      const text = fs.readFileSync(path.join(dir, f), "utf8");
      const m = /:\s*Deck\s*=\s*\{\s*id:\s*"([^"]+)"/.exec(text);
      return m ? [[f, m[1]] as const] : [];
    });

  it("finds the shipped decks", () => {
    expect(declared.length).toBeGreaterThanOrEqual(2);
  });

  for (const [file, id] of declared) {
    it(`${file} is named for its id, ${id}`, () => {
      expect(deckFilePath(id)).toBe(`web/src/modules/deck/decks/${file}`);
    });
  }
});
