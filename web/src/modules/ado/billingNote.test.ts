import { billingNote } from "./billingNote";

describe("billingNote", () => {
  it("says nothing before there is data, or for an agent that sends no source", () => {
    expect(billingNote(undefined)).toBe("");
    expect(billingNote({})).toBe("");
  });

  it("names what the week was built from", () => {
    expect(billingNote({ source: "stamps" })).toBe("Built from the cards' own dates.");
    expect(billingNote({ source: "stamps+git" })).toContain("plus the days git saw them worked");
  });

  it("keeps the git clause conditional -- a hub with no git never reads it", () => {
    // The subtitle up top says the cards' dates decide, for every hub; the git
    // clause is only true of a hub that has git, so it stays down here.
    expect(billingNote({ source: "stamps" })).not.toContain("git");
    expect(billingNote({ source: "stamps+git" })).toBe(
      "Built from the cards' own dates, plus the days git saw them worked.",
    );
  });

  it("accounts for the cards that are not on the page", () => {
    const one = billingNote({ source: "stamps", nonBillable: 1, unstamped: 1 });
    expect(one).toContain("1 card marked not billable is left off.");
    expect(one).toContain("1 card has no date and could not be placed.");
    const many = billingNote({ source: "stamps", nonBillable: 3, unstamped: 2 });
    expect(many).toContain("3 cards marked not billable are left off.");
    expect(many).toContain("2 cards have no date");
  });

  it("does not mention a count of zero", () => {
    expect(billingNote({ source: "stamps", nonBillable: 0, unstamped: 0 })).toBe(
      "Built from the cards' own dates.",
    );
  });
});
