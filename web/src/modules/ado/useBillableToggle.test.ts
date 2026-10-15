import { billableActionLabel, billableOutcomeMessage } from "./useBillableToggle";
import type { CommandResponse } from "./api.ado";

const ok: CommandResponse = {
  command: "Billable",
  status: "success",
  exit_code: 0,
  output: "",
  error: null,
  duration: 1,
};

describe("the billable toggle's words", () => {
  it("offers the opposite of what the card says now", () => {
    expect(billableActionLabel({ billable: true })).toBe("Mark not billable");
    expect(billableActionLabel({ billable: false })).toBe("Make billable again");
  });

  it("says what the change means for Daily, which is the reason anyone does it", () => {
    expect(billableOutcomeMessage({ file: "x", billable: false, result: ok }, "K7M2")).toBe(
      "K7M2 is not billable -- it stays off Daily.",
    );
    expect(billableOutcomeMessage({ file: "x", billable: true, result: ok }, "K7M2")).toBe(
      "K7M2 is billable again -- it is back on Daily.",
    );
  });
});
