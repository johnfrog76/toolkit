import { cardActions } from "./cardActions";
import type { ActionCard, CardActionPlan } from "./cardActions";

// The action model as a TABLE: kind x state x whether Azure DevOps is in use.
// One row per combination the rule distinguishes, and each asserts the WHOLE
// answer -- every action present, which are disabled, and why -- so that "ADO
// card, Active" and "non-ADO card, Active" cannot quietly become the same row.
// A view renders this answer and asserts nothing of its own.

const ADO_URL = "https://dev.azure.com/o/p/_workitems/edit/119";
const PR = "https://dev.azure.com/o/p/_git/r/pullrequest/7";

const NO_COMMITS = "No commits recorded on the card -- thread them with tkThreadHash first.";
const HAS_PR = "It already has a pull request -- its review is the next step.";
const ONE_WAY = "A card travels one way.";

type Kind = "ado" | "local";
const card = (kind: Kind, status: string, extra: Partial<ActionCard> = {}): ActionCard => ({
  status,
  linked: kind === "ado",
  ado_url: kind === "ado" ? ADO_URL : null,
  pr_url: null,
  billable: true,
  commits: 0,
  ...extra,
});

/** A plan, flattened to one readable line per action: `label` or `label [x: reason]`. */
function shape(plan: CardActionPlan): { primary: string | null; menu: string[] } {
  return {
    primary: plan.primary ? plan.primary.label : null,
    menu: plan.secondary.map((a) => (a.disabled ? `${a.label} [x: ${a.whyNot ?? ""}]` : a.label)),
  };
}

const CARD_ONLY = ["Mark not billable", "Open the card"];

const rows: Array<{
  name: string;
  card: ActionCard;
  adoEnabled: boolean;
  primary: string | null;
  menu: string[];
}> = [
  // --- an ADO card, ADO in use --------------------------------------------------
  {
    name: "ADO card, Active, nothing threaded",
    card: card("ado", "Active"),
    adoEnabled: true,
    primary: "Open in ADO",
    menu: [
      "Move to In Progress",
      "Move to Code Review",
      "Move to Done (archive)",
      `Create PR [x: ${NO_COMMITS}]`,
      ...CARD_ONLY,
    ],
  },
  {
    name: "ADO card, In Progress with commits threaded",
    card: card("ado", "In Progress", { commits: 2 }),
    adoEnabled: true,
    primary: "Open in ADO",
    menu: [
      `Active [x: ${ONE_WAY}]`,
      "Move to Code Review",
      "Move to Done (archive)",
      "Create PR",
      ...CARD_ONLY,
    ],
  },
  {
    name: "ADO card, In Progress by a person's Started line (no commit)",
    card: card("ado", "In Progress", { commits: 0 }),
    adoEnabled: true,
    primary: "Open in ADO",
    menu: [
      `Active [x: ${ONE_WAY}]`,
      "Move to Code Review",
      "Move to Done (archive)",
      `Create PR [x: ${NO_COMMITS}]`,
      ...CARD_ONLY,
    ],
  },
  {
    name: "ADO card, Code Review with a pull request",
    card: card("ado", "Code Review", { commits: 1, pr_url: PR }),
    adoEnabled: true,
    primary: "Open in ADO",
    menu: [
      `Active [x: ${ONE_WAY}]`,
      `In Progress [x: ${ONE_WAY}]`,
      "Move to Done (archive)",
      `Create PR [x: ${HAS_PR}]`,
      ...CARD_ONLY,
    ],
  },
  {
    name: "ADO card, Code Review by a person's Review line, commits threaded",
    card: card("ado", "Code Review", { commits: 3 }),
    adoEnabled: true,
    primary: "Open in ADO",
    menu: [
      `Active [x: ${ONE_WAY}]`,
      `In Progress [x: ${ONE_WAY}]`,
      "Move to Done (archive)",
      "Create PR",
      ...CARD_ONLY,
    ],
  },
  {
    name: "ADO card, Done (archived): no PR, nothing ahead",
    card: card("ado", "Done", { commits: 1, pr_url: PR }),
    adoEnabled: true,
    primary: "Open in ADO",
    menu: [
      `Active [x: ${ONE_WAY}]`,
      `In Progress [x: ${ONE_WAY}]`,
      `Code Review [x: ${ONE_WAY}]`,
      ...CARD_ONLY,
    ],
  },
  // --- a card with no work item, ADO in use: no ADO action, ever ------------------
  {
    name: "non-ADO card, Active",
    card: card("local", "Active"),
    adoEnabled: true,
    primary: null,
    menu: ["Move to In Progress", "Move to Code Review", "Move to Done (archive)", ...CARD_ONLY],
  },
  {
    name: "non-ADO card, In Progress with a commit",
    card: card("local", "In Progress", { commits: 1 }),
    adoEnabled: true,
    primary: null,
    menu: [`Active [x: ${ONE_WAY}]`, "Move to Code Review", "Move to Done (archive)", ...CARD_ONLY],
  },
  {
    name: "non-ADO card, Code Review",
    card: card("local", "Code Review", { commits: 1 }),
    adoEnabled: true,
    primary: null,
    menu: [
      `Active [x: ${ONE_WAY}]`,
      `In Progress [x: ${ONE_WAY}]`,
      "Move to Done (archive)",
      ...CARD_ONLY,
    ],
  },
  {
    name: "non-ADO card, Done",
    card: card("local", "Done"),
    adoEnabled: true,
    primary: null,
    menu: [
      `Active [x: ${ONE_WAY}]`,
      `In Progress [x: ${ONE_WAY}]`,
      `Code Review [x: ${ONE_WAY}]`,
      ...CARD_ONLY,
    ],
  },
  // --- ADO off: an ADO card reads exactly as a card with no work item -------------
  {
    name: "ADO card, Active, ADO off",
    card: card("ado", "Active"),
    adoEnabled: false,
    primary: null,
    menu: ["Move to In Progress", "Move to Code Review", "Move to Done (archive)", ...CARD_ONLY],
  },
  {
    name: "ADO card, In Progress with commits, ADO off",
    card: card("ado", "In Progress", { commits: 2 }),
    adoEnabled: false,
    primary: null,
    menu: [`Active [x: ${ONE_WAY}]`, "Move to Code Review", "Move to Done (archive)", ...CARD_ONLY],
  },
  {
    name: "ADO card, Code Review with a PR, ADO off",
    card: card("ado", "Code Review", { commits: 1, pr_url: PR }),
    adoEnabled: false,
    primary: null,
    menu: [
      `Active [x: ${ONE_WAY}]`,
      `In Progress [x: ${ONE_WAY}]`,
      "Move to Done (archive)",
      ...CARD_ONLY,
    ],
  },
  {
    name: "ADO card, Done, ADO off",
    card: card("ado", "Done", { commits: 1, pr_url: PR }),
    adoEnabled: false,
    primary: null,
    menu: [
      `Active [x: ${ONE_WAY}]`,
      `In Progress [x: ${ONE_WAY}]`,
      `Code Review [x: ${ONE_WAY}]`,
      ...CARD_ONLY,
    ],
  },
  {
    name: "non-ADO card, Active, ADO off",
    card: card("local", "Active"),
    adoEnabled: false,
    primary: null,
    menu: ["Move to In Progress", "Move to Code Review", "Move to Done (archive)", ...CARD_ONLY],
  },
  {
    name: "non-ADO card, In Progress, ADO off",
    card: card("local", "In Progress", { commits: 1 }),
    adoEnabled: false,
    primary: null,
    menu: [`Active [x: ${ONE_WAY}]`, "Move to Code Review", "Move to Done (archive)", ...CARD_ONLY],
  },
  {
    name: "non-ADO card, Code Review, ADO off",
    card: card("local", "Code Review", { commits: 1 }),
    adoEnabled: false,
    primary: null,
    menu: [
      `Active [x: ${ONE_WAY}]`,
      `In Progress [x: ${ONE_WAY}]`,
      "Move to Done (archive)",
      ...CARD_ONLY,
    ],
  },
];

describe("cardActions -- one action model for a card, in every view", () => {
  it.each(rows)("$name", ({ card: c, adoEnabled, primary, menu }) => {
    expect(shape(cardActions(c, { adoEnabled, cliPrefix: "tk" }))).toEqual({ primary, menu });
  });

  it("every disabled action says why, and no enabled one carries a reason", () => {
    for (const { card: c, adoEnabled } of rows) {
      for (const a of cardActions(c, { adoEnabled, cliPrefix: "tk" }).secondary) {
        if (a.disabled) expect(a.whyNot).toBeTruthy();
        else expect(a.whyNot).toBeUndefined();
      }
    }
  });

  it("the reason names the verb with THIS machine's prefix", () => {
    const pr = cardActions(card("ado", "Active"), {
      adoEnabled: true,
      cliPrefix: "p20",
    }).secondary.find((a) => a.id === "create-pr");
    expect(pr?.whyNot).toMatch(/p20ThreadHash/);
  });

  it("the lanes use the org's own words, and the primary links to the work item", () => {
    const plan = cardActions(card("ado", "Active"), {
      adoEnabled: true,
      cliPrefix: "tk",
      laneLabel: (s) => ({ "In Progress": "Doing" })[s] ?? s,
    });
    expect(plan.secondary[0]).toMatchObject({
      id: "move",
      to: "In Progress",
      label: "Move to Doing",
    });
    expect(plan.primary).toMatchObject({ id: "open-ado", href: ADO_URL });
  });

  it("the lanes are one group, what you do with the card another", () => {
    const menu = cardActions(card("ado", "Active"), {
      adoEnabled: true,
      cliPrefix: "tk",
    }).secondary;
    expect(menu.filter((a) => a.dividerBefore).map((a) => a.id)).toEqual(["create-pr"]);
  });

  it("a not-billable card offers to make it billable again", () => {
    const menu = cardActions(card("local", "Active", { billable: false }), {
      adoEnabled: true,
      cliPrefix: "tk",
    }).secondary;
    expect(menu.map((a) => a.label)).toContain("Make billable again");
  });

  it("an older agent that sends no commit count is not refused on a guess past Active", () => {
    const older = (status: string) =>
      cardActions(card("ado", status, { commits: undefined }), {
        adoEnabled: true,
        cliPrefix: "tk",
      }).secondary.find((a) => a.id === "create-pr");
    expect(older("Active")).toMatchObject({ disabled: true, whyNot: NO_COMMITS });
    expect(older("In Progress")?.disabled).toBeUndefined();
  });

  it("offers Remind me about this, last, only while the organize module is on", () => {
    for (const kind of ["ado", "local"] as const) {
      const ctx = { adoEnabled: true, cliPrefix: "tk" };
      const off = cardActions(card(kind, "Active"), ctx).secondary.map((a) => a.id);
      const on = cardActions(card(kind, "Active"), { ...ctx, organize: true }).secondary;
      expect(off).not.toContain("remind");
      expect(on[on.length - 1]).toMatchObject({ id: "remind", label: "Remind me about this" });
      expect(on.slice(0, -1).map((a) => a.id)).toEqual(off);
    }
  });
});
