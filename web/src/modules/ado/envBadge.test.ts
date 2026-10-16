import { checkLabel, envBadge } from "./envBadge";

// The string pass: the Environment card names the place and the thing, and
// never an Azure DevOps word on a GitHub Space (D-G13).
describe("the Environment card's words", () => {
  it.each([
    ["github", 1, "Full", /GitHub answered/],
    ["github", 2, "Offline", /GitHub could not be reached/],
    ["ado", 1, "Full", /Azure DevOps answered/],
    ["ado", 2, "Offline", /Azure DevOps could not be reached/],
  ] as const)("a %s Space at tier %d says %s, naming its tracker", (tracker, tier, label, says) => {
    const badge = envBadge({ tier, spaceStatus: "active", tracker });
    expect(badge.label).toBe(label);
    expect(badge.tooltip).toMatch(says);
    if (tracker === "github") expect(badge.tooltip).not.toMatch(/Azure|ADO|az CLI/);
  });

  it.each([
    ["github", "GitHub"],
    ["ado", "Azure DevOps"],
    ["none", "Tracker"],
  ] as const)("the tracker row on a %s Space is called %s", (tracker, label) => {
    expect(checkLabel("adoReachable", tracker)).toBe(label);
  });

  it.each([["none"], [undefined]] as const)(
    "a Space whose tracker is %s never names Azure DevOps",
    (tracker) => {
      for (const tier of [1, 2]) {
        const badge = envBadge({ tier, spaceStatus: "active", tracker });
        expect(badge.tooltip).not.toMatch(/Azure|ADO/);
      }
      expect(checkLabel("adoReachable", tracker)).toBe("Tracker");
    },
  );

  it("calls the hub's checks by the hub, and a card a card", () => {
    expect(checkLabel("promptsVolume", "none")).toBe("Hub folder");
    expect(checkLabel("activePrompts", "none")).toBe("Cards in this Space");
    expect(checkLabel("someNewCheck", "none")).toBe("someNewCheck");
  });
});

describe("envBadge", () => {
  it("says Archive for an archived org, and does not warn: nothing was tried", () => {
    const badge = envBadge({ tier: 2, spaceStatus: "archive" });
    expect(badge.label).toBe("Archive");
    expect(badge.color).toBe("informative");
    expect(badge.tooltip).toMatch(/never contacted/);
    expect(badge.tooltip).not.toMatch(/unreachable|could not/i);
  });

  it("says Local, in green, for a local org: working from cards is a choice, not a fault", () => {
    const badge = envBadge({ tier: 2, spaceStatus: "local" });
    expect(badge.label).toBe("Local");
    expect(badge.color).toBe("success");
    expect(badge.tooltip).toMatch(/by choice/);
  });

  it("warns only when an ACTIVE org tried Azure DevOps and failed -- and calls it Offline, not Local", () => {
    const badge = envBadge({ tier: 2, spaceStatus: "active" });
    expect(badge.label).toBe("Offline");
    expect(badge.color).toBe("warning");
    expect(badge.tooltip).toMatch(/could not be reached/);
  });

  it("says Full, in green, for an active org that answered", () => {
    expect(envBadge({ tier: 1, spaceStatus: "active" })).toMatchObject({
      label: "Full",
      color: "success",
    });
  });

  it("says Minimal whatever the org: a missing repo or git comes first", () => {
    for (const spaceStatus of ["active", "local", "archive"] as const) {
      expect(envBadge({ tier: 3, spaceStatus })).toMatchObject({
        label: "Minimal",
        color: "danger",
      });
    }
  });
});
