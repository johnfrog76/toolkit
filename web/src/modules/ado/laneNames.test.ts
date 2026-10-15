import { laneConfigKey, laneLabel } from "./laneNames";

describe("laneLabel", () => {
  const demo = { Active: "To do", "In Progress": "Doing", "Code Review": "Waiting", Done: "Done" };

  it("prints the org's own word for a lane, keyed by the contract's word", () => {
    expect(laneLabel(demo, "Active")).toBe("To do");
    expect(laneLabel(demo, "Code Review")).toBe("Waiting");
  });

  it("an org that says nothing is called by the contract's words -- an ADO user sees no change", () => {
    expect(laneLabel(undefined, "Code Review")).toBe("Code Review");
    expect(laneLabel({}, "In Progress")).toBe("In Progress");
  });

  it("a state the org did not name keeps its contract word", () => {
    expect(laneLabel({ Active: "To do" }, "Done")).toBe("Done");
  });
});

// laneConfigKey: the write side. The
// contract word is what /env's laneNames map is keyed by; Config -Set (and
// PUT /api/config) take the schema's camelCase spelling instead
// (Scripts/Get-ConfigSchema.ps1), so this is the one place that translates
// between the two rather than each caller carrying its own copy.
describe("laneConfigKey", () => {
  it("builds the dotted config key for each contract word, camelCase", () => {
    expect(laneConfigKey("demo", "Active")).toBe("spaces.demo.laneNames.active");
    expect(laneConfigKey("demo", "In Progress")).toBe("spaces.demo.laneNames.inProgress");
    expect(laneConfigKey("demo", "Code Review")).toBe("spaces.demo.laneNames.codeReview");
    expect(laneConfigKey("demo", "Done")).toBe("spaces.demo.laneNames.done");
  });

  it("names the org it is for -- two spaces never collide", () => {
    expect(laneConfigKey("acme", "Active")).toBe("spaces.acme.laneNames.active");
  });
});
