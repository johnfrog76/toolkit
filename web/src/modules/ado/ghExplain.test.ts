// The Design tab's intro names the tracker from the Space, not a literal.
import { GH_EXPLAIN } from "./ghExplain";
import { trackerName } from "./TrackerBadge";

describe("the Design tab's intro", () => {
  it("reads the tracker's name and says what the order is", () => {
    expect(GH_EXPLAIN.design?.(trackerName("github"))).toBe(
      "The product's designs and specs, read from its GitHub repository: each note first, then the spec it became.",
    );
  });
});

describe("the Docs tab's intro", () => {
  it("reads the tracker's name, the way the Design line does", () => {
    expect(GH_EXPLAIN.docs?.(trackerName("github"))).toBe(
      "The product's README and its docs, read from its GitHub repository.",
    );
  });
});
