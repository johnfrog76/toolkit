import fs from "node:fs";
import path from "node:path";
import { fireEvent, render, screen, waitFor } from "@testing-library/react";
import { TriagePage, answersLine, contextLine, triageQueue, whoLabel } from "./TriagePage";
import type { TriageResponse } from "./api.solitaireAgile";

// The Triage page: one open issue at a time, the unmilestoned group
// first, its milestone's context line above it, the three questions under it,
// and every answer ONE POST /api/cmd/Route with the argv buildRouteParams makes.
// The response is built from the SHARED fixture the CLI and the agent assert
// (Tests/fixtures/rituals/triage.json) and the golden text beside it.

const FIXTURES = path.resolve(__dirname, "../../../../Tests/fixtures/rituals");

interface FixtureIssue {
  number: number;
  title: string;
  url: string;
  assignees?: (string | { login: string })[];
}
interface FixtureCase {
  name: string;
  space: string;
  tracker: { ok: boolean; reason: string };
  issues: FixtureIssue[];
  expected: {
    sizes: string[];
    groups: {
      milestone: string;
      open: number;
      routed: number;
      unrouted: number;
      context: string;
      issues: number[];
    }[];
    issues: Record<
      string,
      { worker: string; size: string; who: string; severity: string; deepWater: boolean }
    >;
    text: string;
  };
}
const table = JSON.parse(fs.readFileSync(path.join(FIXTURES, "triage.json"), "utf8")) as {
  labels: { name: string; description: string }[];
  cases: FixtureCase[];
};

/** The route's response for one fixture case. */
function responseFor(name: string): TriageResponse {
  const c = table.cases.find((x) => x.name === name);
  if (!c) throw new Error(`no fixture case ${name}`);
  const byNumber = new Map(c.issues.map((i) => [i.number, i]));
  const nameOf = (label: string) =>
    (table.labels.find((l) => l.name === label)?.description ?? "")
      .replace(/^Routed to\s*/, "")
      .split(" -- ")[0];
  return {
    ceremony: "triage",
    space: c.space,
    tracker: c.tracker,
    slots: ["milestone", "severity", "size"],
    severities: ["sev1", "sev2", "sev3"],
    deepWaterLabel: "deep-water",
    sizes: c.expected.sizes.map((label) => ({ label, name: nameOf(label) })),
    groups: c.expected.groups.map((g) => ({
      ...g,
      issues: g.issues.map((n) => {
        const i = byNumber.get(n);
        if (!i) throw new Error(`fixture ${name}: no issue #${n}`);
        const first = (i.assignees ?? [])[0];
        const assignee = typeof first === "string" ? first : (first?.login ?? "");
        return { number: n, title: i.title, url: i.url, assignee, ...c.expected.issues[String(n)] };
      }),
    })),
    text: fs.readFileSync(path.join(FIXTURES, c.expected.text), "utf8"),
  };
}

let answer: { data?: unknown; error?: unknown; isLoading?: boolean } = {};
let askedSpace: string | null = null;
const posted: string[][] = [];
let routeResult: { status: string; output: string; error: string | null } = {
  status: "success",
  output: "Routed.",
  error: null,
};

jest.mock("./api.solitaireAgile", () => ({
  useGetTriageQuery: (space: string) => {
    askedSpace = space;
    return { isLoading: false, isFetching: false, refetch: jest.fn(), ...answer };
  },
  useRunRouteMutation: () => [
    ({ params }: { params: string[] }) => {
      posted.push(params);
      return {
        unwrap: () =>
          Promise.resolve({ command: "Route", exit_code: 0, duration: 0, ...routeResult }),
      };
    },
    { isLoading: false },
  ],
}));
jest.mock("../ado/api.ado", () => ({
  useGetMilestonesQuery: () => ({
    data: {
      supported: true,
      milestones: [
        { title: "Phase 6: ledgers", state: "open" },
        { title: "Going public", state: "open" },
        { title: "Shipped long ago", state: "closed" },
      ],
    },
  }),
}));
// The new-issue dialog is ActionDialog's own subject (ActionDialog.parent.test.tsx);
// here it is a stand-in that says how it was opened.
const dialogOpens: { tab: string; initialParent?: number }[] = [];
jest.mock("../ado/ActionDialog", () => ({
  ActionDialog: (props: { tab: string; initialParent?: number; onClose: () => void }) => {
    dialogOpens.push({ tab: props.tab, initialParent: props.initialParent });
    return (
      <div role="dialog" aria-label="new-issue dialog">
        parent #{props.initialParent}
        <button onClick={props.onClose}>Close the dialog</button>
      </div>
    );
  },
}));
jest.mock("../../shell/api", () => ({
  useGetEnvQuery: () => ({ isLoading: false, data: { config: { activeSpace: "toolkit" } } }),
}));

beforeEach(() => {
  answer = {};
  askedSpace = null;
  posted.length = 0;
  dialogOpens.length = 0;
  routeResult = { status: "success", output: "Routed.", error: null };
});

const shownNumber = () => screen.getByRole("link").textContent;

describe("the rules the page reads", () => {
  it("the queue is the read's order: the group with no milestone first", () => {
    expect(triageQueue(responseFor("mixed"))).toEqual([
      140, 141, 142, 143, 144, 146, 148, 145, 147,
    ]);
  });

  it("the context line names the milestone, or says there is none", () => {
    const [none, phase] = responseFor("mixed").groups;
    expect(contextLine(none)).toBe("No milestone -- 2 open, 2 routed, 0 unrouted");
    expect(contextLine(phase)).toBe("Phase 6: ledgers -- 3 open, 3 routed, 0 unrouted");
  });

  it("the answers an issue carries, in one line: who has it first", () => {
    const [none, phase, publicGroup] = responseFor("mixed").groups;
    expect(answersLine(phase.issues[0], "deep-water")).toBe("Fable · sev1 · deep-water");
    expect(answersLine(phase.issues[1], "deep-water")).toBe("@octo-crew · no severity");
    expect(answersLine(none.issues[0], "deep-water")).toBe("me · sev2");
    expect(answersLine(publicGroup.issues[1], "deep-water")).toBe("nobody · sev3");
  });

  it("who: the agent's who decides, and an older read with none falls back to the size", () => {
    const [, phase] = responseFor("mixed").groups;
    expect(whoLabel(phase.issues[2])).toBe("Sonnet");
    expect(whoLabel({ ...phase.issues[2], who: undefined })).toBe("Sonnet");
    expect(whoLabel({ ...phase.issues[1], who: undefined })).toBe("nobody");
    const [noViewer] = responseFor("no-viewer").groups;
    expect(noViewer.issues.map(whoLabel)).toEqual(["@johnfrog76", "Fable", "nobody"]);
  });
});

describe("the Triage page", () => {
  it("asks about the Space you are in, and opens on the first unplaced issue", () => {
    answer = { data: responseFor("mixed") };
    render(<TriagePage />);
    expect(askedSpace).toBe("toolkit");
    expect(screen.getByRole("heading", { level: 1 }).textContent).toBe("Triage -- toolkit");
    expect(shownNumber()).toBe("#140 Split the drawer");
    expect(screen.getByRole("link").getAttribute("href")).toBe(
      "https://github.com/johnfrog76/toolkit/issues/140",
    );
    expect(screen.getByTestId("triage-context").textContent).toBe(
      "No milestone -- 2 open, 2 routed, 0 unrouted",
    );
    expect(screen.getByText("1 of 9")).toBeTruthy();
    // Who has it is said under the title: the first issue is yours.
    expect(screen.getByTestId("triage-answers").textContent).toBe("me · sev2");
  });

  it("the third question offers me first, and me is one Route -Assign me", async () => {
    answer = { data: responseFor("mixed") };
    render(<TriagePage />);
    fireEvent.click(screen.getByRole("button", { name: "Next" }));
    fireEvent.click(screen.getByRole("button", { name: "Next" }));
    fireEvent.click(screen.getByRole("button", { name: "Next" }));
    expect(shownNumber()).toBe("#143 Ledger counts");
    expect(screen.getByTestId("triage-answers").textContent).toBe("@octo-crew · no severity");
    const me = screen.getByRole("button", { name: "me" });
    expect(me.getAttribute("aria-pressed")).toBe("false");
    fireEvent.click(me);
    expect(posted).toEqual([["143", "-Assign", "me"]]);
    expect(await screen.findByText("Routed.")).toBeTruthy();
  });

  it("me shows as the answer when the issue is already yours", () => {
    answer = { data: responseFor("mixed") };
    render(<TriagePage />);
    expect(screen.getByRole("button", { name: "me" }).getAttribute("aria-pressed")).toBe("true");
  });

  it("Next skips, and the context line follows the issue into its milestone", () => {
    answer = { data: responseFor("mixed") };
    render(<TriagePage />);
    fireEvent.click(screen.getByRole("button", { name: "Next" }));
    expect(shownNumber()).toBe("#141 Port the cast atoms");
    fireEvent.click(screen.getByRole("button", { name: "Next" }));
    expect(shownNumber()).toBe("#142 Re-plumb the bridge");
    expect(screen.getByTestId("triage-context").textContent).toBe(
      "Phase 6: ledgers -- 3 open, 3 routed, 0 unrouted",
    );
    expect(posted).toEqual([]);
  });

  it("a severity is one Route", async () => {
    answer = { data: responseFor("mixed") };
    render(<TriagePage />);
    fireEvent.click(screen.getByRole("button", { name: "sev1" }));
    expect(posted).toEqual([["140", "-Severity", "sev1"]]);
    expect(await screen.findByText("Routed.")).toBeTruthy();
  });

  it("a milestone is one Route, chosen from the OPEN milestones", async () => {
    answer = { data: responseFor("mixed") };
    render(<TriagePage />);
    const select = screen.getByRole("combobox", { name: "Milestone" }) as HTMLSelectElement;
    expect(Array.from(select.options).map((o) => o.value)).toEqual([
      "",
      "Phase 6: ledgers",
      "Going public",
    ]);
    fireEvent.change(select, { target: { value: "Going public" } });
    expect(posted).toEqual([["140", "-Milestone", "Going public"]]);
    expect(await screen.findByText("Routed.")).toBeTruthy();
  });

  it("a size is the worker label, one Route", async () => {
    answer = { data: responseFor("mixed") };
    render(<TriagePage />);
    fireEvent.click(screen.getByRole("button", { name: "Opus" }));
    expect(posted).toEqual([["140", "-Size", "opus"]]);
    expect(await screen.findByText("Routed.")).toBeTruthy();
  });

  it("deep water offers exactly two moves: Assign Fable and Split, both live", async () => {
    answer = { data: responseFor("mixed") };
    render(<TriagePage />);
    const moves = screen.getByTestId("triage-deep-moves");
    // Always in the layout, so choosing deep water moves nothing -- hidden until chosen.
    expect(moves.className).toMatch(/\S/);
    fireEvent.click(screen.getByRole("button", { name: "deep-water" }));
    const split = screen.getByRole("button", { name: "Split" }) as HTMLButtonElement;
    expect(split.disabled).toBe(false);
    expect(screen.queryByText(/Azure DevOps/)).toBeNull();
    fireEvent.click(screen.getByRole("button", { name: "Assign Fable" }));
    expect(posted).toEqual([["140", "-Size", "fable", "-DeepWater"]]);
    expect(await screen.findByText("Routed.")).toBeTruthy();
  });

  it("Split opens the new-issue dialog with the issue in front named as the parent", () => {
    answer = { data: responseFor("mixed") };
    render(<TriagePage />);
    // No dialog, and none of its reads, until Split is used.
    expect(screen.queryByRole("dialog")).toBeNull();
    expect(dialogOpens).toEqual([]);
    fireEvent.click(screen.getByRole("button", { name: "deep-water" }));
    fireEvent.click(screen.getByRole("button", { name: "Split" }));
    expect(screen.getByRole("dialog", { name: "new-issue dialog" }).textContent).toMatch(
      /parent #140/,
    );
    expect(dialogOpens[dialogOpens.length - 1]).toEqual({ tab: "new-item", initialParent: 140 });
    // Split writes nothing itself: the create is the dialog's, through NewItem.
    expect(posted).toEqual([]);
    fireEvent.click(screen.getByRole("button", { name: "Close the dialog" }));
    expect(screen.queryByRole("dialog")).toBeNull();
  });

  it("Split is not offered until deep water is the answer", () => {
    answer = { data: responseFor("mixed") };
    render(<TriagePage />);
    const split = screen.getByText("Split").closest("button") as HTMLButtonElement;
    expect(split.disabled).toBe(true);
  });

  it("a refusal from the verb is shown as it was said", async () => {
    answer = { data: responseFor("mixed") };
    routeResult = {
      status: "error",
      output: "",
      error: "No open milestone 'X' on johnfrog76/toolkit.",
    };
    render(<TriagePage />);
    fireEvent.click(screen.getByRole("button", { name: "sev2" }));
    // The status line is always in the layout, so finding it is not waiting for the answer.
    const status = screen.getByTestId("triage-status");
    await waitFor(() => expect(status.textContent).toMatch(/No open milestone 'X'/));
  });

  it("past the last issue it says so, and offers to start again", () => {
    answer = { data: responseFor("all-placed") };
    render(<TriagePage />);
    expect(shownNumber()).toBe("#150 Count the closes");
    fireEvent.click(screen.getByRole("button", { name: "Next" }));
    expect(screen.getByText("That was every open issue")).toBeTruthy();
    expect(screen.getByRole("button", { name: "Start again" })).toBeTruthy();
  });

  it("nothing open says so, with no questions", () => {
    answer = { data: responseFor("nothing-open") };
    render(<TriagePage />);
    expect(screen.getByText("Nothing is open to triage")).toBeTruthy();
    expect(screen.queryByTestId("triage-issue")).toBeNull();
  });

  it("no tracker shows the reason, and asks nothing", () => {
    answer = { data: responseFor("no-tracker") };
    render(<TriagePage />);
    expect(screen.getByText("gh did not answer")).toBeTruthy();
    expect(screen.queryByTestId("triage-issue")).toBeNull();
  });

  it("the agent away is an error, never an empty triage", () => {
    answer = { error: { status: "FETCH_ERROR" } };
    render(<TriagePage />);
    expect(screen.getByText("Could not read the open issues")).toBeTruthy();
  });
});
