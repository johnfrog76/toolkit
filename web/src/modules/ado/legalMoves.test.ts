import { LANES, laneHint, legalMoves, whyNotAMove } from "./legalMoves";

describe("legalMoves", () => {
  it("the lanes are the state vocabulary, in order, and nothing the board invented", () => {
    expect([...LANES]).toEqual(["Active", "In Progress", "Code Review", "Done"]);
  });

  it("a person may move a card to every lane AHEAD of it -- two writers per lane, since 2026-09-22", () => {
    expect(legalMoves("Active")).toEqual(["In Progress", "Code Review", "Done"]);
    expect(legalMoves("In Progress")).toEqual(["Code Review", "Done"]);
    expect(legalMoves("Code Review")).toEqual(["Done"]);
  });

  it("nothing moves out of Done, and an unknown state moves nowhere", () => {
    expect(legalMoves("Done")).toEqual([]);
    expect(legalMoves("Planned")).toEqual([]); // not a state: D-C12
    expect(legalMoves("")).toEqual([]);
  });

  it("a card travels one way: the lanes behind it are not targets, and each says why", () => {
    expect(whyNotAMove("Code Review", "In Progress")).toBe("A card travels one way.");
    expect(whyNotAMove("In Progress", "Active")).toBe("A card travels one way.");
    expect(whyNotAMove("In Progress", "In Progress")).toBe("It is already here.");
    expect(whyNotAMove("Active", "Done")).toBe("");
  });

  it("every lane but Done says who puts a card there, and that a person can too", () => {
    expect(laneHint("Active")).toMatch(/moment it is made/);
    expect(laneHint("In Progress")).toMatch(/commit/);
    expect(laneHint("In Progress")).toMatch(/drop one/);
    expect(laneHint("Code Review")).toMatch(/pull request/);
    expect(laneHint("Done")).toBe("");
  });
});
