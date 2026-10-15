import { joinDue, splitDue } from "./reminderEntry";

describe("a stored due, split for the Edit dialog and joined back", () => {
  it.each([
    ["2026-10-01T14:00", { date: "2026-10-01", time: "14:00" }],
    ["2026-10-01", { date: "2026-10-01", time: "" }],
    ["", { date: "", time: "" }],
    ["not a date", { date: "", time: "" }],
  ])("%s splits to %o", (due, parts) => {
    expect(splitDue(due)).toEqual(parts);
  });

  it("round-trips every stored shape unchanged", () => {
    for (const due of ["2026-10-01T14:00", "2026-10-01", ""]) {
      expect(joinDue(splitDue(due))).toBe(due);
    }
  });

  it("a day keeps no invented time, and a time with no day is no due", () => {
    expect(joinDue({ date: "2026-10-01", time: "" })).toBe("2026-10-01");
    expect(joinDue({ date: "", time: "09:00" })).toBe("");
  });
});
