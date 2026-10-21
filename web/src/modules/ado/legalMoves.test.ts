import { LANES, laneHint, legalMoves, whyNotAMove } from "./legalMoves";

describe("legalMoves", () => {
  it("the lanes are the state vocabulary, in order, Backlog first, and nothing the board invented", () => {
    expect([...LANES]).toEqual(["Backlog", "Active", "In Progress", "Code Review", "Done"]);
  });

  it("a person may move a card to every lane AHEAD of it -- two writers per lane, since 2026-09-22", () => {
    expect(legalMoves("In Progress")).toEqual(["Code Review", "Done"]);
    expect(legalMoves("Code Review")).toEqual(["Done"]);
  });

  it("a planned card may be pulled into ANY lane ahead: Move pulls it into current/ first", () => {
    expect(legalMoves("Backlog")).toEqual(["Active", "In Progress", "Code Review", "Done"]);
  });

  it("an Active card may go back to Backlog -- it has nothing threaded, by the state rule", () => {
    expect(legalMoves("Active")).toEqual(["Backlog", "In Progress", "Code Review", "Done"]);
    expect(whyNotAMove("Active", "Backlog")).toBe("");
  });

  it("threaded work is in play: In Progress and Code Review never go back to Backlog", () => {
    expect(legalMoves("In Progress")).not.toContain("Backlog");
    expect(legalMoves("Code Review")).not.toContain("Backlog");
    expect(whyNotAMove("In Progress", "Backlog")).toBe("Threaded work is in play, not backlog.");
  });

  it("nothing moves out of Done, and an unknown state moves nowhere", () => {
    expect(legalMoves("Done")).toEqual([]);
    expect(legalMoves("Planned")).toEqual([]); // the folder is Backlog; "Planned" is not a state
    expect(legalMoves("")).toEqual([]);
  });

  it("a card travels one way: the lanes behind it are not targets, and each says why", () => {
    expect(whyNotAMove("Code Review", "In Progress")).toBe("A card travels one way.");
    expect(whyNotAMove("In Progress", "Active")).toBe("A card travels one way.");
    expect(whyNotAMove("In Progress", "In Progress")).toBe("It is already here.");
    expect(whyNotAMove("Active", "Done")).toBe("");
  });

  it("every lane but Done says who puts a card there, and that a person can too", () => {
    expect(laneHint("Backlog")).toMatch(/new card starts here/);
    expect(laneHint("Active")).toMatch(/first commit/);
    expect(laneHint("In Progress")).toMatch(/commit/);
    expect(laneHint("In Progress")).toMatch(/drop one/);
    expect(laneHint("Code Review")).toMatch(/pull request/);
    expect(laneHint("Done")).toBe("");
  });
});
