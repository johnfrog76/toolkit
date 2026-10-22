import { act, fireEvent, render, screen, within } from "@testing-library/react";
import { MemoryRouter, Route, Routes, useLocation } from "react-router";
import { readFileSync } from "fs";
import { join } from "path";
import { PromptsCard, hasSpaceFilter, promptReference } from "./PromptsCard";
import { PromptPage } from "./PromptPage";
import {
  CATEGORY_TABS_MAX,
  WORKFLOWS,
  categoryTabs,
  groupLabel,
  othersLine,
  ownerLabel,
  promptSets,
  senderLabel,
  spaceWorkflow,
  workflowLabel,
} from "./prompts";
import { promptPath } from "./paths";
import type { EnvStatus } from "../../shell/api";
import type { PromptRow, PromptSpace } from "./api.studio";

// The Prompts card: three filters -- ToolKit (the Space's set, by how you work
// there), Your hub, and the active Space's own agentic/ (only when the Space is
// not this package itself, which the agent says) -- each with its count, its
// rows and its empty state; the card's info tip in place of a footer; each
// row's one action Copy reference (Copy prompt in its menu), the name opening
// the reading room. The agent's reads are pinned in Tests/test_studio_prompts.py.
// The viewer is mocked (react-markdown is ESM).
jest.mock("../../shared/MarkdownViewer", () => ({
  MarkdownViewer: ({ content }: { content: string }) => <pre data-testid="viewer">{content}</pre>,
}));

const copiedText: string[] = [];
jest.mock("../../shared/copyText", () => ({
  copyText: (t: string) => {
    copiedText.push(t);
    return Promise.resolve();
  },
}));

function row(o: Partial<PromptRow>): PromptRow {
  const name = o.name ?? "x";
  const group = o.group ?? "toolkit";
  return {
    name,
    ref: name,
    group,
    path: `agentic/${name}.prompt.md`,
    file_path: `/pkg/agentic/${name}.prompt.md`,
    title: name,
    description: o.description ?? "",
    // The record: the purpose is the description; the owner is the agent's.
    purpose: o.description ?? "",
    owner: group === "space" ? "wasteland" : group,
    category: "uncategorized",
    workflows: ["alone", "team", "agents"],
    sender: "by hand",
    by_hand: true,
    module: "core",
    drives: "",
    overrides: false,
    changed: "2026-10-07",
    history: "",
    body: `# ${name}\n`,
    ...o,
  };
}

const PR_SHIP = row({
  name: "pr-ship",
  workflows: ["team"],
  description: "Ship-it flow, stage 1",
  drives: "NewPR",
  history: "https://github.com/acme/kit/commits/abc/agentic/pr-ship.prompt.md",
  body: "---\ndescription: ship\n---\n\n# PR Ship\n",
});
const NEW_ISSUE = row({
  name: "new-issue",
  workflows: ["alone", "agents"],
  drives: "gh issue create",
});
const PR_REVIEW = row({ name: "pr-review", sender: "AddPRReview", by_hand: false });
const GROWTH = row({ name: "growth-create-training", module: "growth" });
const BENCH = row({
  name: "bench-billing",
  ref: "yours/bench-billing",
  group: "yours",
  path: "agentic/bench-billing.prompt.md",
  workflows: [],
  sender: "",
});
// The Space's own: read from its repository, so no local path, no day, no history.
const DECK = row({
  name: "deck-contract",
  ref: "space/deck-contract",
  group: "space",
  path: "agentic/deck-contract.prompt.md",
  file_path: "https://github.com/acme/wasteland/blob/main/agentic/deck-contract.prompt.md",
  description: "What a deck must carry",
  workflows: [],
  sender: "",
  changed: "",
});
const TRAPS = row({
  name: "traps",
  ref: "space/traps",
  group: "space",
  file_path: "https://github.com/acme/wasteland/blob/main/agentic/traps.prompt.md",
  workflows: [],
  sender: "",
  changed: "",
});

const WASTELAND: PromptSpace = {
  slug: "wasteland",
  name: "Wasteland Studio",
  repo: "acme/wasteland",
  isToolkit: false,
};
const TOOLKIT_ITSELF: PromptSpace = {
  slug: "toolkit",
  name: "Toolkit",
  repo: "acme/kit",
  isToolkit: true,
};
const LOCAL: PromptSpace = { slug: "mine", name: "Mine", repo: "", isToolkit: false };

let listAnswer: { data?: unknown; error?: unknown } = {};
let oneAnswer: { data?: unknown; error?: unknown } = {};
function withoutBodies(data: unknown) {
  const d = data as { prompts?: PromptRow[] };
  return { ...d, prompts: (d.prompts ?? []).map(({ body: _body, ...rest }) => rest) };
}
let askedFor: string | null = null;
// The lazy read Copy prompt makes: which refs it asked for, whether it fails, what it answers.
const lazyAsked: string[] = [];
let lazyFails = false;
const lazyBody = (ref: string) => ({ body: ref === "pr-ship" ? PR_SHIP.body : `# ${ref}\n` });
jest.mock("./api.studio", () => ({
  useGetPromptsQuery: () => ({
    isLoading: false,
    isFetching: false,
    refetch: jest.fn(),
    ...listAnswer,
    // The agent's list carries no text: whatever a test lists, the card sees none.
    ...(listAnswer.data ? { data: withoutBodies(listAnswer.data) } : {}),
  }),
  useLazyGetPromptQuery: () => [
    (ref: string) => {
      lazyAsked.push(ref);
      return {
        unwrap: () =>
          lazyFails ? Promise.reject(new Error("down")) : Promise.resolve(lazyBody(ref)),
      };
    },
  ],
  useGetPromptQuery: (ref: string) => {
    askedFor = ref;
    return { isLoading: false, isFetching: false, refetch: jest.fn(), ...oneAnswer };
  },
}));

let envAnswer: Partial<EnvStatus> = {};
jest.mock("../../shell/api", () => ({
  useGetEnvQuery: () => ({ data: envAnswer }),
}));

function env(o: Partial<EnvStatus>): EnvStatus {
  return o as EnvStatus;
}

function Where() {
  const loc = useLocation();
  return <div data-testid="where">{loc.pathname}</div>;
}

function mount(at = "/studio") {
  return render(
    <MemoryRouter initialEntries={[at]}>
      <Routes>
        <Route
          path="/studio/prompts/*"
          element={
            <>
              <PromptPage />
              <Where />
            </>
          }
        />
        <Route
          path="*"
          element={
            <>
              <PromptsCard />
              <Where />
            </>
          }
        />
      </Routes>
    </MemoryRouter>,
  );
}

// /env's howIWork is the agent's answer for the Space; the card only reads it.
function how(answer: "alone" | "team" | "agents"): Partial<EnvStatus> {
  return {
    howIWork: { answer, source: "derived", tracker: "none", locked: false },
  } as Partial<EnvStatus>;
}

/** The source row's radios, by their accessible names (the label, then the count). */
const sourceRow = () => screen.getByRole("group", { name: "Filter prompts" });
const radios = () =>
  within(sourceRow())
    .getAllByRole("radio")
    .map((r) => r.textContent);
const radio = (label: string) =>
  within(sourceRow()).getByRole("radio", { name: new RegExp(`^${label}`) });
/** The category row's radios, the same way. */
const categoryRow = () => screen.getByRole("group", { name: "Filter by category" });
const categories = () =>
  within(categoryRow())
    .getAllByRole("radio")
    .map((r) => r.textContent);
const category = (label: string) =>
  within(categoryRow()).getByRole("radio", { name: new RegExp(`^${label}\\s*\\d*$`) });
/** The card's header chip: the active filter's count. */
const chip = () => screen.getByLabelText(/^\d+ prompts$/).textContent;
/** The info tip's words: rendered hidden at all times (relationship description). */
const tipFor = (label = "About the Prompts card") => {
  const icon = screen.getByRole("img", { name: label });
  const id = icon.getAttribute("aria-describedby") ?? "";
  return document.getElementById(id)?.textContent ?? "";
};

describe("the Space's answer to How do you want to work?", () => {
  it.each([
    ["the agent says alone", how("alone"), "alone"],
    ["the agent says team", how("team"), "team"],
    ["the agent says agents", how("agents"), "agents"],
    [
      "Team Agile's switch does not decide it: the Space's answer does",
      { ...how("alone"), features: { solitaireAgile: true } },
      "alone",
    ],
    ["an agent that sends no answer: alone", { features: {} }, "alone"],
    ["/env not read yet", undefined, "alone"],
  ] as const)("%s", (_name, e, want) => {
    expect(spaceWorkflow(e ? env(e as Partial<EnvStatus>) : undefined)).toBe(want);
  });

  it("names the ways of working in the drawer's own words", () => {
    expect(WORKFLOWS).toEqual(["agents", "alone", "team"]);
    expect(WORKFLOWS.map(workflowLabel)).toEqual(["with agents", "alone", "on a team in Azure"]);
  });
});

describe("the three sets", () => {
  const rows = [PR_SHIP, NEW_ISSUE, PR_REVIEW, BENCH, DECK];

  it("ToolKit's for the way of working, every one of yours, every one of the Space's, and counts the rest", () => {
    const alone = promptSets(rows, "alone");
    expect(alone.toolkit.map((r) => r.name)).toEqual(["new-issue", "pr-review"]);
    expect(alone.yours.map((r) => r.name)).toEqual(["bench-billing"]);
    expect(alone.space.map((r) => r.name)).toEqual(["deck-contract"]);
    expect(othersLine(alone)).toBe(
      "1 more of ToolKit's prompts is for another way of working: on a team in Azure (1).",
    );
    const team = promptSets(rows, "team");
    expect(team.toolkit.map((r) => r.name)).toEqual(["pr-ship", "pr-review"]);
    expect(team.space.map((r) => r.name)).toEqual(["deck-contract"]);
    expect(othersLine(team)).toBe(
      "1 more of ToolKit's prompts is for another way of working: with agents (1), alone (1).",
    );
  });

  it("says nothing when none are left out", () => {
    expect(othersLine(promptSets([PR_REVIEW], "agents"))).toBeNull();
  });

  it("names who sends it, and whose it is", () => {
    expect(senderLabel(PR_SHIP)).toBe("by hand");
    expect(senderLabel(PR_REVIEW)).toBe("sent by ToolKit: AddPRReview");
    expect(senderLabel(BENCH)).toBe("by hand");
    expect(senderLabel(DECK)).toBe("by hand");
    expect(["toolkit", "yours", "space"].map((g) => groupLabel(g as PromptRow["group"]))).toEqual([
      "ToolKit's",
      "yours",
      "the Space's",
    ]);
  });

  it("the Space has a filter only when the agent names a repository that is not this package", () => {
    expect(hasSpaceFilter(WASTELAND)).toBe(true);
    expect(hasSpaceFilter(TOOLKIT_ITSELF)).toBe(false);
    expect(hasSpaceFilter(LOCAL)).toBe(false);
    expect(hasSpaceFilter(undefined)).toBe(false);
  });

  it("Copy reference: ToolKit's and the Space's relative to their checkout, yours absolute", () => {
    expect(promptReference(PR_SHIP)).toBe("@agentic/pr-ship.prompt.md");
    expect(promptReference(DECK)).toBe("@agentic/deck-contract.prompt.md");
    expect(promptReference(BENCH)).toBe(`@${BENCH.file_path}`);
  });
});

describe("the Prompts card's filters", () => {
  beforeEach(() => {
    copiedText.length = 0;
    listAnswer = {
      data: {
        count: 7,
        prompts: [PR_SHIP, NEW_ISSUE, PR_REVIEW, GROWTH, BENCH, DECK, TRAPS],
        space: WASTELAND,
      },
    };
    envAnswer = how("team");
  });

  it("draws three radios with their counts, ToolKit active, and the chip is the active filter's count", () => {
    mount();
    expect(radios()).toEqual(["ToolKit3", "Your hub1", "Wasteland Studio2"]);
    expect(radio("ToolKit").getAttribute("aria-checked")).toBe("true");
    expect(chip()).toBe("3");
    expect(screen.getByRole("group", { name: "Filter prompts" })).toBeTruthy();
  });

  it("ToolKit: the Space's set by how you work here, the others counted in the tip, not shown", () => {
    mount();
    expect(screen.getByText("pr-ship")).toBeTruthy();
    expect(screen.getByText("pr-review")).toBeTruthy();
    expect(screen.getByText("growth-create-training")).toBeTruthy();
    expect(screen.queryByText("new-issue")).toBeNull();
    expect(screen.queryByText("bench-billing")).toBeNull();
    expect(screen.queryByText("deck-contract")).toBeNull();
  });

  it("Your hub: every one of yours, and the chip follows", () => {
    mount();
    fireEvent.click(radio("Your hub"));
    expect(radio("Your hub").getAttribute("aria-checked")).toBe("true");
    expect(screen.getByText("bench-billing")).toBeTruthy();
    expect(screen.queryByText("pr-ship")).toBeNull();
    expect(chip()).toBe("1");
  });

  it("the Space's: its repository's own, whatever the way of working, and Copy reference is the @ path", async () => {
    mount();
    fireEvent.click(radio("Wasteland Studio"));
    expect(screen.getByText("deck-contract")).toBeTruthy();
    expect(screen.getByText("traps")).toBeTruthy();
    expect(screen.getByText("What a deck must carry")).toBeTruthy();
    expect(screen.queryByText("pr-ship")).toBeNull();
    expect(chip()).toBe("2");
    const deck = screen.getByText("deck-contract").closest(".fui-Card") as HTMLElement;
    await act(async () => {
      fireEvent.click(within(deck).getByRole("button", { name: "Copy reference" }));
    });
    expect(copiedText).toEqual(["@agentic/deck-contract.prompt.md"]);
    // No day and no history: the contents read carries neither.
    expect(within(deck).queryByText(/^changed/)).toBeNull();
    fireEvent.click(screen.getByText("deck-contract"));
    expect(screen.getByTestId("where").textContent).toBe("/studio/prompts/space/deck-contract");
  });

  it("the third radio is absent when the Space is ToolKit itself, and when it names no repository", () => {
    listAnswer = { data: { count: 5, prompts: [PR_SHIP, BENCH], space: TOOLKIT_ITSELF } };
    const view = mount();
    expect(radios()).toEqual(["ToolKit1", "Your hub1"]);
    expect(screen.queryByText("Toolkit")).toBeNull();
    view.unmount();
    listAnswer = { data: { count: 2, prompts: [PR_SHIP, BENCH], space: LOCAL } };
    mount();
    expect(radios()).toEqual(["ToolKit1", "Your hub1"]);
  });

  it("an older agent with no space block draws two", () => {
    listAnswer = { data: { count: 2, prompts: [PR_SHIP, BENCH] } };
    mount();
    expect(radios()).toEqual(["ToolKit1", "Your hub1"]);
  });

  it("the active filter follows the Space: a stale choice of the third reads as ToolKit", () => {
    const view = mount();
    fireEvent.click(radio("Wasteland Studio"));
    expect(chip()).toBe("2");
    view.unmount();
    // A fresh mount after a switch to ToolKit itself: no third, ToolKit active.
    listAnswer = { data: { count: 2, prompts: [PR_SHIP, BENCH], space: TOOLKIT_ITSELF } };
    mount();
    expect(radio("ToolKit").getAttribute("aria-checked")).toBe("true");
    expect(chip()).toBe("1");
  });

  it("each filter has its own empty state", () => {
    listAnswer = { data: { count: 1, prompts: [NEW_ISSUE], space: WASTELAND } };
    mount();
    // ToolKit: none for this way of working; the others said under it.
    expect(screen.getByText("None for working on a team in Azure")).toBeTruthy();
    expect(
      screen.getByText(
        "1 more of ToolKit's prompts is for another way of working: with agents (1), alone (1).",
        { selector: ".fui-Caption1" },
      ),
    ).toBeTruthy();
    expect(radios()).toEqual(["ToolKit", "Your hub", "Wasteland Studio"]);
    fireEvent.click(radio("Your hub"));
    expect(screen.getByText("None yet")).toBeTruthy();
    expect(
      screen.getByText("A <name>.prompt.md in your hub's agentic/ folder is listed here."),
    ).toBeTruthy();
    fireEvent.click(radio("Wasteland Studio"));
    expect(screen.getByText("None in acme/wasteland")).toBeTruthy();
    expect(
      screen.getByText(
        "A <name>.prompt.md in an agentic/ folder in that repository is listed here.",
      ),
    ).toBeTruthy();
    expect(chip()).toBe("0");
  });

  it("the info tip says what the card does, from the same sets, and the footer is gone", () => {
    mount();
    const tip = tipFor();
    expect(tip).toContain(
      "ToolKit's are what the product tells a model: the 3 for working on a team in Azure here.",
    );
    expect(tip).toContain(
      "1 more of ToolKit's prompts is for another way of working: with agents (1), alone (1).",
    );
    expect(tip).toContain("Your hub's are yours, on every machine.");
    expect(tip).toContain(
      "Wasteland Studio's are its repository's own: agentic/ in acme/wasteland.",
    );
    expect(screen.queryByText(/What ToolKit tells a model/)).toBeNull();
    expect(screen.queryByText(/You work here/)).toBeNull();
    expect(screen.queryByRole("button", { name: "How do you want to work?" })).toBeNull();
    expect(screen.queryByRole("note")).toBeNull();
    expect(screen.queryByText("ToolKit's")).toBeNull();
    expect(screen.queryByText("Your hub's")).toBeNull();
  });

  it("the tip has no Space line when the Space is ToolKit itself", () => {
    listAnswer = { data: { count: 2, prompts: [PR_SHIP, BENCH], space: TOOLKIT_ITSELF } };
    mount();
    const tip = tipFor();
    expect(tip).toContain("the 1 for working on a team in Azure here.");
    expect(tip).not.toContain("more of ToolKit's");
    expect(tip).not.toContain("repository's own");
  });
});

// The category row: All, then each category with a prompt in the active
// source -- the vocabulary's order, any outside it after -- each with its count.
describe("the Prompts card's category row", () => {
  const VOCABULARY = ["ship", "review", "tracker", "growth", "meetings", "rituals", "design"];
  const tk = (name: string, cat: string) => row({ name, category: cat, workflows: ["team"] });
  const mine = (name: string, cat: string) =>
    row({ name, ref: `yours/${name}`, group: "yours", workflows: [], sender: "", category: cat });
  const MIXED = [
    tk("tk-review", "review"),
    tk("tk-ship-1", "ship"),
    tk("tk-ship-2", "ship"),
    tk("tk-growth", "growth"),
    tk("tk-loose", "uncategorized"),
    mine("my-billing", "billing"),
    mine("my-growth", "growth"),
  ];
  beforeEach(() => {
    envAnswer = how("team");
    listAnswer = {
      data: { count: MIXED.length, prompts: MIXED, space: LOCAL, categories: VOCABULARY },
    };
  });

  it("draws All and each category in the source with its count, in the vocabulary's order, the rest after", () => {
    mount();
    expect(categories()).toEqual(["All5", "ship2", "review1", "growth1", "uncategorized1"]);
    expect(category("All").getAttribute("aria-checked")).toBe("true");
    expect(chip()).toBe("5");
  });

  it("draws no badge for a category with no prompt in the active source", () => {
    mount();
    for (const empty of ["tracker", "meetings", "rituals", "design", "billing"]) {
      expect(
        within(categoryRow()).queryByRole("radio", { name: new RegExp(`^${empty}`) }),
      ).toBeNull();
    }
  });

  it("draws a category outside the vocabulary as written", () => {
    mount();
    fireEvent.click(radio("Your hub"));
    expect(categories()).toEqual(["All2", "growth1", "billing1"]);
    fireEvent.click(category("billing"));
    expect(screen.getByText("my-billing")).toBeTruthy();
    expect(screen.queryByText("my-growth")).toBeNull();
    expect(chip()).toBe("1");
  });

  it("composes with the source row: source AND category, the chip the shown count", () => {
    mount();
    fireEvent.click(category("ship"));
    expect(category("ship").getAttribute("aria-checked")).toBe("true");
    expect(screen.getByText("tk-ship-1")).toBeTruthy();
    expect(screen.getByText("tk-ship-2")).toBeTruthy();
    expect(screen.queryByText("tk-review")).toBeNull();
    expect(chip()).toBe("2");
    // The source row's counts are the source's, not the composed result's.
    expect(radios()).toEqual(["ToolKit5", "Your hub2"]);
    // growth is in both sources: the choice holds across the switch.
    fireEvent.click(category("growth"));
    fireEvent.click(radio("Your hub"));
    expect(category("growth").getAttribute("aria-checked")).toBe("true");
    expect(screen.getByText("my-growth")).toBeTruthy();
    expect(screen.queryByText("my-billing")).toBeNull();
    expect(chip()).toBe("1");
  });

  it("a choice the new source has no prompt in reads as All", () => {
    mount();
    fireEvent.click(category("ship"));
    fireEvent.click(radio("Your hub"));
    expect(category("All").getAttribute("aria-checked")).toBe("true");
    expect(chip()).toBe("2");
  });

  it("All shows the whole source again", () => {
    mount();
    fireEvent.click(category("review"));
    expect(chip()).toBe("1");
    fireEvent.click(category("All"));
    expect(chip()).toBe("5");
    expect(screen.getByText("tk-loose")).toBeTruthy();
  });

  it("the pager runs over the composed result, and a category change starts at its first page", () => {
    const ships = Array.from({ length: 7 }, (_, i) => tk(`ship-${i + 1}`, "ship"));
    const reviews = Array.from({ length: 2 }, (_, i) => tk(`review-${i + 1}`, "review"));
    listAnswer = {
      data: { count: 9, prompts: [...reviews, ...ships], space: LOCAL, categories: VOCABULARY },
    };
    mount();
    expect(screen.getByText("1 / 2")).toBeTruthy();
    fireEvent.click(screen.getByRole("button", { name: "Next page" }));
    expect(screen.getByText("2 / 2")).toBeTruthy();
    // Seven ships: two pages of their own, from the first.
    fireEvent.click(category("ship"));
    expect(screen.getByText("1 / 2")).toBeTruthy();
    expect(screen.getByText("ship-1")).toBeTruthy();
    expect(screen.queryByText("ship-6")).toBeNull();
    fireEvent.click(screen.getByRole("button", { name: "Next page" }));
    expect(screen.getByText("ship-7")).toBeTruthy();
    expect(screen.queryByText("review-1")).toBeNull();
    // Two reviews fit one page: no pager.
    fireEvent.click(category("review"));
    expect(screen.queryByRole("button", { name: "Next page" })).toBeNull();
    expect(chip()).toBe("2");
  });

  it("an empty source still draws the row, All with no count, so nothing moves", () => {
    listAnswer = {
      data: { count: 1, prompts: [tk("only", "ship")], space: LOCAL, categories: VOCABULARY },
    };
    mount();
    fireEvent.click(radio("Your hub"));
    expect(categories()).toEqual(["All"]);
  });

  it("an older agent with no vocabulary draws every category, alphabetically", () => {
    listAnswer = { data: { count: MIXED.length, prompts: MIXED, space: LOCAL } };
    mount();
    expect(categories()).toEqual(["All5", "growth1", "review1", "ship2", "uncategorized1"]);
  });

  it("the tip says what the row does", () => {
    mount();
    expect(tipFor()).toContain("The row under them narrows any of these to one category.");
  });

  it("categoryTabs: the vocabulary's order, then the rest alphabetically, no zeros", () => {
    const rows = [
      { category: "zeta" },
      { category: "design" },
      { category: "ship" },
      { category: "alpha" },
    ];
    expect(categoryTabs(rows, VOCABULARY)).toEqual([
      { category: "ship", count: 1 },
      { category: "design", count: 1 },
      { category: "alpha", count: 1 },
      { category: "zeta", count: 1 },
    ]);
    expect(categoryTabs([], VOCABULARY)).toEqual([]);
  });

  it("the shipped vocabulary fits the tabs: past CATEGORY_TABS_MAX the row becomes a dropdown", () => {
    const index = JSON.parse(
      readFileSync(join(__dirname, "..", "..", "..", "..", "agentic", "prompts.json"), "utf-8"),
    ) as { categories: string[] };
    expect(index.categories).toEqual(VOCABULARY);
    expect(index.categories.length).toBeLessThanOrEqual(CATEGORY_TABS_MAX);
  });
});

describe("the Prompts card's rows", () => {
  beforeEach(() => {
    copiedText.length = 0;
    listAnswer = {
      data: { count: 5, prompts: [PR_SHIP, NEW_ISSUE, PR_REVIEW, GROWTH, BENCH], space: LOCAL },
    };
    envAnswer = how("team");
  });

  // The row is ONE record: title, purpose, owner, category, and the one action.
  // Its text, every piece of it, is those four; the index's fields are the reading room's.
  const rowText = (card: HTMLElement) =>
    Array.from(card.querySelectorAll("strong, .fui-Caption1, .fui-Badge")).map(
      (e) => e.textContent,
    );

  it("each row shows title, purpose, owner and category, and nothing else", () => {
    listAnswer = {
      data: {
        count: 4,
        prompts: [
          { ...PR_SHIP, title: "PR Ship", category: "ship" },
          { ...PR_REVIEW, title: "PR review", category: "review" },
          { ...GROWTH, title: "New Training", category: "growth" },
          {
            ...BENCH,
            title: "Bench billing",
            description: "Reconstruct a week",
            purpose: "Reconstruct a week",
          },
          { ...DECK, title: "Deck contract", category: "design" },
        ],
        space: WASTELAND,
      },
    };
    mount();
    const card = (title: string) => screen.getByText(title).closest(".fui-Card") as HTMLElement;
    expect(rowText(card("PR Ship"))).toEqual([
      "PR Ship",
      "Ship-it flow, stage 1",
      "ToolKit",
      "ship",
    ]);
    // A prompt with no purpose draws no line for it, and the tools' prompt is no different.
    expect(rowText(card("PR review"))).toEqual(["PR review", "ToolKit", "review"]);
    expect(rowText(card("New Training"))).toEqual(["New Training", "ToolKit", "growth"]);
    // None of the index's other fields, nor where it lives or when it changed.
    for (const gone of [
      "sent by ToolKit: AddPRReview",
      "by hand",
      "drives NewPR",
      "agentic/pr-ship.prompt.md",
      /^changed/,
    ]) {
      expect(screen.queryByText(gone)).toBeNull();
    }
    fireEvent.click(radio("Your hub"));
    expect(rowText(card("Bench billing"))).toEqual([
      "Bench billing",
      "Reconstruct a week",
      "Your hub",
      "uncategorized",
    ]);
    fireEvent.click(radio("Wasteland Studio"));
    expect(rowText(card("Deck contract"))).toEqual([
      "Deck contract",
      "What a deck must carry",
      "Wasteland Studio",
      "design",
    ]);
    // One exposed action, the rest in the menu.
    const deck = card("Deck contract");
    expect(
      within(deck)
        .getAllByRole("button")
        .map((b) => b.getAttribute("aria-label") ?? b.textContent),
    ).toEqual(["Deck contract", "Copy reference", "Actions for deck-contract"]);
  });

  it("names the owner in the filter row's words", () => {
    expect(ownerLabel(PR_SHIP, WASTELAND)).toBe("ToolKit");
    expect(ownerLabel(BENCH, WASTELAND)).toBe("Your hub");
    expect(ownerLabel(DECK, WASTELAND)).toBe("Wasteland Studio");
    expect(ownerLabel(DECK, undefined)).toBe("wasteland");
  });

  it("with agents, the agents' set: pr-ship is counted, new-issue shown", () => {
    envAnswer = how("agents");
    mount();
    expect(screen.getByText("new-issue")).toBeTruthy();
    expect(screen.queryByText("pr-ship")).toBeNull();
  });

  it("the one exposed action is Copy reference: the @ path, a ToolKit prompt's relative to the checkout", async () => {
    mount();
    const ship = screen.getByText("pr-ship").closest(".fui-Card") as HTMLElement;
    expect(within(ship).queryByRole("button", { name: "Copy prompt" })).toBeNull();
    await act(async () => {
      fireEvent.click(within(ship).getByRole("button", { name: "Copy reference" }));
    });
    expect(copiedText).toEqual(["@agentic/pr-ship.prompt.md"]);
    expect(screen.getByText(/Copied the reference to pr-ship/)).toBeTruthy();
  });

  it("one of the hub's copies its absolute path, which the hub is never inside the tree", async () => {
    mount();
    fireEvent.click(radio("Your hub"));
    const mine = screen.getByText("bench-billing").closest(".fui-Card") as HTMLElement;
    await act(async () => {
      fireEvent.click(within(mine).getByRole("button", { name: "Copy reference" }));
    });
    expect(copiedText).toEqual([`@${BENCH.file_path}`]);
    expect(BENCH.file_path.startsWith("/")).toBe(true);
  });

  it("Copy prompt reads the body when clicked, then copies the whole file", async () => {
    lazyAsked.length = 0;
    lazyFails = false;
    mount();
    const ship = screen.getByText("pr-ship").closest(".fui-Card") as HTMLElement;
    await act(async () => {
      fireEvent.click(within(ship).getByRole("button", { name: "Actions for pr-ship" }));
    });
    expect(lazyAsked).toEqual([]); // opening the card and its menu reads no text
    await act(async () => {
      fireEvent.click(await screen.findByRole("menuitem", { name: "Copy prompt" }));
    });
    expect(lazyAsked).toEqual(["pr-ship"]);
    expect(copiedText).toEqual([PR_SHIP.body]);
    expect(screen.getByText(/Copied pr-ship/)).toBeTruthy();
  });

  it("a Copy prompt whose read fails copies nothing and says so", async () => {
    lazyAsked.length = 0;
    lazyFails = true;
    mount();
    const ship = screen.getByText("pr-ship").closest(".fui-Card") as HTMLElement;
    await act(async () => {
      fireEvent.click(within(ship).getByRole("button", { name: "Actions for pr-ship" }));
    });
    await act(async () => {
      fireEvent.click(await screen.findByRole("menuitem", { name: "Copy prompt" }));
    });
    lazyFails = false;
    expect(copiedText).toEqual([]);
    expect(screen.getByRole("alert").textContent).toContain("Could not read pr-ship");
    expect(screen.queryByText(/Copied pr-ship/)).toBeNull();
  });

  it("the name opens the reading room", () => {
    mount();
    fireEvent.click(radio("Your hub"));
    fireEvent.click(screen.getByText("bench-billing"));
    expect(screen.getByTestId("where").textContent).toBe("/studio/prompts/yours/bench-billing");
  });

  it("an agent that does not answer is said, not an empty list", () => {
    listAnswer = { error: { status: "FETCH_ERROR" } };
    mount();
    expect(screen.getByText("Could not read the prompts")).toBeTruthy();
    expect(screen.queryAllByRole("radio")).toEqual([]);
  });
});

describe("the Prompts card's pager", () => {
  const toolkit = (n: number) =>
    Array.from({ length: n }, (_, i) => row({ name: `tk-${i + 1}`, workflows: ["team"] }));
  const hub = (n: number) =>
    Array.from({ length: n }, (_, i) =>
      row({
        name: `mine-${i + 1}`,
        ref: `yours/mine-${i + 1}`,
        group: "yours",
        workflows: [],
        sender: "",
      }),
    );
  const prompts = (t: number, h: number, extra: PromptRow[] = []) => {
    listAnswer = {
      data: { count: t + h, prompts: [...toolkit(t), ...hub(h), ...extra], space: LOCAL },
    };
  };
  beforeEach(() => {
    envAnswer = how("team");
  });

  it("six rows draw a pager and page 2 shows the sixth; five draw none", () => {
    prompts(6, 0);
    const view = mount();
    expect(screen.getByText("tk-5")).toBeTruthy();
    expect(screen.queryByText("tk-6")).toBeNull();
    expect(screen.getByText("1 / 2")).toBeTruthy();
    fireEvent.click(screen.getByRole("button", { name: "Next page" }));
    expect(screen.getByText("tk-6")).toBeTruthy();
    view.unmount();
    prompts(5, 0);
    mount();
    expect(screen.queryByRole("button", { name: "Next page" })).toBeNull();
  });

  it("the pager runs over the active filter's rows, and a filter change starts at its first page", () => {
    prompts(7, 3);
    mount();
    expect(screen.getByText("1 / 2")).toBeTruthy();
    expect(chip()).toBe("7");
    fireEvent.click(screen.getByRole("button", { name: "Next page" }));
    expect(screen.getByText("tk-7")).toBeTruthy();
    // Your hub's three fit one page: no pager, page 1, the chip its count.
    fireEvent.click(radio("Your hub"));
    expect(screen.queryByRole("button", { name: "Next page" })).toBeNull();
    expect(screen.getByText("mine-1")).toBeTruthy();
    expect(screen.getByText("mine-3")).toBeTruthy();
    expect(screen.queryByText("tk-1")).toBeNull();
    expect(chip()).toBe("3");
    // Back to ToolKit: its first page again.
    fireEvent.click(radio("ToolKit"));
    expect(screen.getByText("tk-1")).toBeTruthy();
    expect(screen.queryByText("tk-7")).toBeNull();
  });

  it("the others are in the tip, never a line under the list", () => {
    prompts(7, 1, [row({ name: "other-way", workflows: ["agents"] })]);
    mount();
    expect(screen.queryByRole("note")).toBeNull();
    fireEvent.click(screen.getByRole("button", { name: "Next page" }));
    expect(screen.queryByRole("note")).toBeNull();
    expect(tipFor()).toContain("1 more of ToolKit's prompts is for another way of working");
  });
});

describe("a prompt's reading room", () => {
  beforeEach(() => {
    copiedText.length = 0;
    envAnswer = {};
  });

  it("reads the prompt by the address's ref, and renders its text", () => {
    oneAnswer = { data: PR_SHIP };
    mount(promptPath("pr-ship"));
    expect(askedFor).toBe("pr-ship");
    expect(screen.getByRole("heading", { name: "pr-ship" })).toBeTruthy();
    expect(screen.getByTestId("viewer").textContent).toBe(PR_SHIP.body);
    expect(screen.getByText("ToolKit's")).toBeTruthy();
    expect(screen.getByText("for working on a team in Azure")).toBeTruthy();
    expect(screen.getByTestId("file-path").textContent).toContain(PR_SHIP.file_path);
  });

  it("carries the detail the row does not: category, sender, add-on, what it drives, when it changed", () => {
    oneAnswer = {
      data: {
        ...PR_REVIEW,
        title: "PR review",
        category: "review",
        module: "growth",
        drives: "NewPR",
      },
    };
    mount(promptPath("pr-review"));
    expect(screen.getByRole("heading", { name: "PR review" })).toBeTruthy();
    expect(screen.getByText("review")).toBeTruthy();
    expect(screen.getByText("sent by ToolKit: AddPRReview")).toBeTruthy();
    expect(screen.getByText("growth")).toBeTruthy();
    expect(screen.getByText("drives NewPR")).toBeTruthy();
    expect(screen.getByText("changed 2026-10-07").closest("a")).toBeNull();
  });

  it("links the day it changed to its history, and says when a copy of yours runs instead", () => {
    oneAnswer = { data: { ...PR_SHIP, overrides: true } };
    mount(promptPath("pr-ship"));
    expect(screen.getByText("changed 2026-10-07").closest("a")?.getAttribute("href")).toBe(
      PR_SHIP.history,
    );
    expect(screen.getByText("runs instead of ToolKit's on this machine")).toBeTruthy();
  });

  it("one of yours reads by yours/<name>", () => {
    oneAnswer = { data: BENCH };
    mount(promptPath("yours/bench-billing"));
    expect(askedFor).toBe("yours/bench-billing");
    expect(screen.getByText("yours")).toBeTruthy();
  });

  it("one of the Space's reads by space/<name>, with the file's address on GitHub", () => {
    oneAnswer = { data: DECK };
    mount(promptPath("space/deck-contract"));
    expect(askedFor).toBe("space/deck-contract");
    expect(screen.getByText("the Space's")).toBeTruthy();
    expect(screen.getByTestId("file-path").textContent).toContain(DECK.file_path);
    expect(screen.getByTestId("viewer").textContent).toBe(DECK.body);
  });

  it("Copy prompt copies the whole file", async () => {
    oneAnswer = { data: PR_SHIP };
    mount(promptPath("pr-ship"));
    await act(async () => {
      fireEvent.click(screen.getByRole("button", { name: "Copy prompt" }));
    });
    expect(copiedText).toEqual([PR_SHIP.body]);
    expect(screen.getByRole("button", { name: "Copied" })).toBeTruthy();
  });

  it("a name the agent does not know is said in its words", () => {
    oneAnswer = {
      error: {
        status: 404,
        data: { detail: "generate-review belongs to the growth module, which is not enabled." },
      },
    };
    mount(promptPath("generate-review"));
    expect(screen.getByText("No prompt generate-review")).toBeTruthy();
    expect(screen.getByText(/belongs to the growth module/)).toBeTruthy();
  });
});
