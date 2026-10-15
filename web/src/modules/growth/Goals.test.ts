/**
 * A goal or training with no `## Title` (or `## Goal`) heading is served with
 * the file's own stem as its title -- pinned agent-side behaviour
 * (Tests/test_growth.py: "the stem, as for a generated file with no title").
 * Read as a name rather than a file fact, that showed a raw slug where a
 * title should be.
 * `isUntitledGrowthItem` is how the card tells the two cases apart.
 */
import { isUntitledGrowthItem } from "./Goals";

describe("isUntitledGrowthItem", () => {
  it("is true when the title is exactly the filename with .md stripped", () => {
    expect(
      isUntitledGrowthItem(
        "training-2026-03-02-distributed-systems-fundamentals.prompt",
        "training-2026-03-02-distributed-systems-fundamentals.prompt.md",
      ),
    ).toBe(true);
  });

  it("is false for a real title, even one that resembles a filename", () => {
    expect(
      isUntitledGrowthItem("Distributed Systems Fundamentals", "training-2026-03-02.prompt.md"),
    ).toBe(false);
  });

  it("is false when the title only coincidentally shares a substring with the filename", () => {
    expect(isUntitledGrowthItem("Goal", "goal-2026-01-01-goal.prompt.md")).toBe(false);
  });
});
