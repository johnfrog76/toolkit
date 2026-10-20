import fs from "node:fs";
import path from "node:path";
import { act, fireEvent, render as rtlRender, screen, waitFor } from "@testing-library/react";
import type { ReactElement } from "react";
import { MemoryRouter, Route, Routes } from "react-router";
import {
  GRAIN_KEY,
  StandupPage,
  grainParts,
  issueFacts,
  slotState,
  issueUrls,
  linkIssues,
  listRows,
  splitHeader,
} from "./StandupPage";
import type { RitualItem, StandupResponse, TriageResponse } from "./api.solitaireAgile";

// Today's standup page (docs/modules/solitaire-agile.md, "The web UI"): the agent's
// `text` shown VERBATIM, the first line as the header and the rest in a
// monospace block, each `#<n>` the response names a link to its url. The
// response is built from the SHARED fixture both other halves assert
// (Tests/fixtures/rituals/standup.json) and the golden texts beside it, read
// from disk -- so the web is held to the same bytes the CLI and the agent are.

const FIXTURES = path.resolve(__dirname, "../../../../Tests/fixtures/rituals");

interface FixtureIssue {
  number: number;
  title: string;
  url: string;
}
interface FixtureWorker {
  label: string;
  name: string;
  yesterday: number[];
  today: number[];
  blockers: number[];
  empty: boolean;
}
interface FixtureCase {
  name: string;
  asOf: string;
  tracker: { ok: boolean; reason: string };
  issues: FixtureIssue[];
  expected: {
    since: string;
    queue: { walk: number[] };
    workers: FixtureWorker[];
    text: string | null;
    brief: string;
  };
}

const table = JSON.parse(fs.readFileSync(path.join(FIXTURES, "standup.json"), "utf8")) as {
  cases: FixtureCase[];
};

/** The route's response for one fixture case, per the contract's JSON (4b). */
function responseFor(name: string): StandupResponse {
  const c = table.cases.find((x) => x.name === name);
  if (!c || !c.expected.text) throw new Error(`no fixture case ${name} with a golden`);
  const byNumber = new Map(c.issues.map((i) => [i.number, i]));
  const items = (ns: number[]): RitualItem[] =>
    ns.map((n) => {
      const i = byNumber.get(n);
      if (!i) throw new Error(`fixture ${name}: no issue #${n}`);
      return { number: i.number, title: i.title, url: i.url };
    });
  const text = fs.readFileSync(path.join(FIXTURES, c.expected.text), "utf8");
  return {
    ceremony: "standup",
    register: "real",
    asOf: c.asOf,
    since: c.expected.since,
    space: "toolkit",
    tracker: c.tracker,
    // The chair's lines are in the golden text; the page never reads these.
    chair: { open: "", close: "" },
    queue: { walk: items(c.expected.queue.walk), decide: [], look: [] },
    workers: c.expected.workers.map((w) => ({
      label: w.label,
      name: w.name,
      yesterday: items(w.yesterday),
      today: items(w.today),
      blockers: items(w.blockers),
      empty: w.empty,
      excuse: "",
    })),
    text,
    brief: fs.readFileSync(path.join(FIXTURES, c.expected.brief), "utf8"),
  };
}

/** The page under a router (its Play control navigates), with the played
 *  route standing in so a test can see where Play went. */
function render(ui: ReactElement) {
  const wrap = (el: ReactElement) => (
    <MemoryRouter initialEntries={["/solitaire-agile"]}>
      <Routes>
        <Route path="/solitaire-agile" element={el} />
        <Route path="/deck/ritual/standup" element={<p>played</p>} />
      </Routes>
    </MemoryRouter>
  );
  const result = rtlRender(wrap(ui));
  // rerender keeps the router too: a re-draw of the page is still the page under its routes.
  return { ...result, rerender: (el: ReactElement) => result.rerender(wrap(el)) };
}

let answer: { data?: unknown; error?: unknown; isLoading?: boolean } = {};
let triageAnswer: { data?: unknown } = {};
let askedSpace: string | null = null;
const attend = jest.fn();
jest.mock("./api.solitaireAgile", () => ({
  useGetStandupQuery: (space: string) => {
    askedSpace = space;
    return { isLoading: false, ...answer };
  },
  useGetTriageQuery: () => ({ isLoading: false, ...triageAnswer }),
  useAttendStandupMutation: () => [attend, { isLoading: false }],
  useRunStartWorkMutation: () => [startWork, { isLoading: false }],
}));
const startWork = jest.fn((_arg: { id: string }) => ({
  unwrap: () =>
    Promise.resolve({
      command: "StartWork",
      status: "success",
      exit_code: 0,
      output: "# Start work: Issue #104 -- a title\n\n## How we work in Toolkit (x)\nA sentence.\n",
      error: null,
      duration: 1,
    }),
}));
const copyMock = jest.fn((_t: string) => Promise.resolve());
jest.mock("../../shared/copyText", () => ({ copyText: (t: string) => copyMock(t) }));
jest.mock("../../shell/api", () => ({
  useGetEnvQuery: () => ({ isLoading: false, data: { config: { activeSpace: "toolkit" } } }),
}));

/** What the page shows, put back together: the header line, LF, the body. */
function shown(): string {
  const header = screen.getByRole("heading", { level: 1 }).textContent ?? "";
  const body = screen.getByTestId("standup-text").textContent ?? "";
  return `${header}\n${body}`;
}

/** The work grain, spoken as prose: the shared prose table's
 *  friday golden, as `work.text` -- the page shows it verbatim, like `text`. */
function withWork(data: StandupResponse): StandupResponse {
  return {
    ...data,
    work: {
      queue: { walk: [], decide: [], look: [] },
      workers: [],
      queueProse: [],
      text: fs.readFileSync(path.join(FIXTURES, "standup-prose-friday.txt"), "utf8"),
    },
  };
}

beforeEach(() => {
  localStorage.clear();
  answer = {};
  triageAnswer = {};
  askedSpace = null;
  attend.mockReset();
  copyMock.mockClear();
});

describe("the standup page", () => {
  it("shows Friday's standup verbatim and links an issue number to its issue", () => {
    const data = responseFor("friday");
    answer = { data };
    render(<StandupPage />);
    expect(askedSpace).toBe("toolkit");
    expect(shown()).toBe(data.text);
    // The first line is the header: the ceremony's title and its date.
    expect(screen.getByRole("heading", { level: 1 }).textContent).toBe(data.text.split("\n")[0]);
    const links = screen.getAllByRole("link", { name: "#104" });
    // Issue 104 is walked AND is a blocker: both lines link it.
    expect(links).toHaveLength(2);
    for (const a of links)
      expect(a.getAttribute("href")).toBe("https://github.com/johnfrog76/toolkit/issues/104");
    expect(screen.getByRole("link", { name: "#101" }).getAttribute("href")).toBe(
      "https://github.com/johnfrog76/toolkit/issues/101",
    );
    // The empty seat reports: the status sentence under the mug, never an excuse.
    expect(shown()).toContain('Mug        "Nothing on the board for me. All green, no blockers."');
    expect(shown()).not.toContain("The dog ate the sprint.");
    // Nothing to click but the issue numbers -- and Play.
    expect(screen.getAllByRole("button").map((b) => b.textContent)).toEqual([
      "Copy",
      "Play",
      "Show as list",
    ]);
    // The text scrolls sideways, so it is a named region a keyboard reaches.
    const region = screen.getByRole("region", { name: "Standup text" });
    expect(region).toBe(screen.getByTestId("standup-text"));
    expect(region.getAttribute("tabindex")).toBe("0");
  });

  it("shows the chair's reading above the prose, line for line, and Copy still copies the text only", async () => {
    const data = responseFor("friday");
    answer = { data };
    render(<StandupPage />);
    const brief = screen.getByTestId("standup-brief");
    expect((data.brief ?? "").length).toBeGreaterThan(0);
    expect(Array.from(brief.children).map((c) => c.textContent)).toEqual(
      (data.brief ?? "").split("\n").filter(Boolean),
    );
    // Above the prose: the brief precedes the text block in the document.
    expect(
      brief.compareDocumentPosition(screen.getByTestId("standup-text")) &
        Node.DOCUMENT_POSITION_FOLLOWING,
    ).toBeTruthy();
    // The long form is still the text, verbatim: the brief is not part of it.
    expect(shown()).toBe(data.text);
    await act(async () => {
      fireEvent.click(screen.getByRole("button", { name: "Copy" }));
    });
    expect(copyMock).toHaveBeenCalledWith(data.text);
  });

  it("opens on the counts line: what moved since the window began, at the top of the page", () => {
    const data = responseFor("friday");
    answer = { data };
    render(<StandupPage />);
    const first = screen.getByTestId("standup-brief").children[0]?.textContent ?? "";
    // The brief's own first line, verbatim: the counts line the agent and the CLI render.
    expect(first).toBe((data.brief ?? "").split("\n")[0]);
    expect(first).toBe("Since Thursday 1 October 2026: 2 closed, 2 in progress.");
    // An item says what moved only where it adds to its slot (started, commits): a closed
    // item under Yesterday with no commits is its number and title, the label says the rest.
    expect(shown()).toContain("Yesterday  #102 Rename the slug");
    expect(shown()).not.toContain("(closed)");
    expect(shown()).not.toContain("(in progress)");
  });

  it("Play opens the same standup, played on the stage", () => {
    answer = { data: responseFor("friday") };
    render(<StandupPage />);
    fireEvent.click(screen.getByRole("button", { name: "Play" }));
    expect(screen.getByText("played")).toBeTruthy();
  });

  it("with no tracker, shows the ritual anyway: the golden, and no links", () => {
    const data = responseFor("no-tracker");
    expect(data.tracker.ok).toBe(false);
    answer = { data };
    render(<StandupPage />);
    expect(shown()).toBe(data.text);
    expect(screen.queryAllByRole("link")).toEqual([]);
  });

  it("says the agent did not answer rather than drawing an empty standup", () => {
    answer = { error: { status: "FETCH_ERROR" } };
    render(<StandupPage />);
    expect(screen.getByRole("alert").textContent).toMatch(/did not answer/);
    // Nothing to play either.
    expect(screen.queryByRole("button", { name: "Play" })).toBeNull();
    expect(screen.queryByTestId("standup-text")).toBeNull();
  });

  it("while it reads, says so", () => {
    answer = { isLoading: true };
    render(<StandupPage />);
    expect(screen.getByText(/Checking/)).toBeTruthy();
  });
});

// Showing the standup is attending it -- one POST per page view, once it
// has drawn; the agent re-arms the reminder (or does nothing) and the page
// shows nothing of it.
describe("attending", () => {
  it("posts once when the standup is shown, however often the page draws", () => {
    answer = { data: responseFor("friday") };
    const { rerender } = render(<StandupPage />);
    rerender(<StandupPage />);
    rerender(<StandupPage />);
    expect(attend).toHaveBeenCalledTimes(1);
  });

  it("does not attend a standup that did not draw", () => {
    answer = { error: { status: "FETCH_ERROR" } };
    render(<StandupPage />);
    answer = { isLoading: true };
    render(<StandupPage />);
    expect(attend).not.toHaveBeenCalled();
  });

  it("attends again on the next page view", () => {
    answer = { data: responseFor("friday") };
    const first = render(<StandupPage />);
    first.unmount();
    render(<StandupPage />);
    expect(attend).toHaveBeenCalledTimes(2);
  });
});

describe("copy and the list", () => {
  it("Copy puts text on the clipboard exactly and says Copied!", async () => {
    const data = responseFor("friday");
    answer = { data };
    render(<StandupPage />);
    await act(async () => {
      fireEvent.click(screen.getByRole("button", { name: "Copy" }));
    });
    expect(copyMock).toHaveBeenCalledWith(data.text);
    expect(screen.getByRole("button", { name: "Copied!" })).toBeTruthy();
  });

  it("hides the list by default and shows the items in order when toggled", () => {
    const data = responseFor("friday");
    answer = { data };
    render(<StandupPage />);
    expect(screen.queryByTestId("standup-list")).toBeNull();
    fireEvent.click(screen.getByRole("button", { name: "Show as list" }));
    const items = screen.getAllByRole("listitem");
    const expected = listRows(data);
    expect(items).toHaveLength(expected.length);
    expected.forEach((r, i) => {
      expect(items[i].textContent).toContain(r.item.title);
      expect(items[i].textContent).toContain(`#${r.item.number}`);
    });
    // The queue's rows come first, as walk.
    expect(items[0].textContent).toContain("walk");
    const link = screen
      .getAllByRole("link", { name: "#104" })
      .find((a) => items.some((li) => li.contains(a)));
    expect(link?.getAttribute("href")).toBe("https://github.com/johnfrog76/toolkit/issues/104");
    fireEvent.click(screen.getByRole("button", { name: "Hide list" }));
    expect(screen.queryByTestId("standup-list")).toBeNull();
  });

  it("opens the hand-off block from a row's Start work: one StartWork call, the issue's number", async () => {
    startWork.mockClear();
    answer = { data: responseFor("friday") };
    render(<StandupPage />);
    // Nothing is asked before a row asks for it.
    expect(startWork).not.toHaveBeenCalled();
    fireEvent.click(screen.getByRole("button", { name: "Show as list" }));
    fireEvent.click(screen.getAllByRole("button", { name: "Start work on #104" })[0]);
    const block = await screen.findByTestId("start-work-block");
    expect(block.textContent).toContain("## How we work in Toolkit (x)");
    expect(startWork).toHaveBeenCalledTimes(1);
    expect(startWork).toHaveBeenCalledWith({ id: "104" });
  });

  it("shows a GitHub Space's joined standup verbatim: issues linked, a card by its id, the Check lines as text", () => {
    // The shared joined fixture (Tests/fixtures/rituals/standup-joined.json) and its golden.
    const joined = JSON.parse(
      fs.readFileSync(path.join(FIXTURES, "standup-joined.json"), "utf8"),
    ) as {
      asOf: string;
      since: string;
      cases: {
        name: string;
        issues: FixtureIssue[];
        cards: { id: string; title: string; file: string; folder: string }[];
        expected: {
          walk: string[];
          workers: { label: string; name: string; [slot: string]: unknown }[];
        };
      }[];
    };
    const c = joined.cases.find((x) => x.name === "together");
    if (!c) throw new Error("no joined case together");
    const item = (ref: string): RitualItem => {
      if (ref.startsWith("#")) {
        const i = c.issues.find((x) => x.number === Number(ref.slice(1)));
        if (!i) throw new Error(`no issue ${ref}`);
        return { number: i.number, id: null, title: i.title, url: i.url, path: "" };
      }
      const k = c.cards.find((x) => x.id === ref);
      if (!k) throw new Error(`no card ${ref}`);
      return { number: null, id: k.id, title: k.title, url: "", path: `${k.folder}/${k.file}` };
    };
    const slot = (w: Record<string, unknown>, s: string) => (w[s] as string[]).map(item);
    const text = fs.readFileSync(path.join(FIXTURES, "standup-joined-together.txt"), "utf8");
    const data: StandupResponse = {
      ceremony: "standup",
      register: "real",
      asOf: joined.asOf,
      since: joined.since,
      space: "widgets",
      source: "both",
      tracker: { ok: true, reason: "" },
      chair: { open: "", close: "" },
      queue: { walk: c.expected.walk.map(item), decide: [], look: [] },
      workers: c.expected.workers.map((w) => ({
        label: w.label,
        name: w.name,
        yesterday: slot(w, "yesterday"),
        today: slot(w, "today"),
        blockers: slot(w, "blockers"),
        empty: Boolean(w.empty),
        excuse: "",
      })),
      text,
    };
    answer = { data };
    render(<StandupPage />);
    expect(shown()).toBe(text);
    expect(screen.getAllByRole("link", { name: "#146" })[0].getAttribute("href")).toBe(
      "https://github.com/acme/widgets/issues/146",
    );
    expect(screen.queryByRole("link", { name: "K7M2" })).toBeNull();
    expect(shown()).toMatch(/^ {2}Check {6}#142 Port the cast atoms -- /m);
  });

  it("shows a card by its id, with no link", () => {
    const data = responseFor("friday");
    data.source = "cards";
    data.queue = {
      walk: [{ number: null, id: "K7M2", title: "A card", url: "", path: "current/K7M2-a.md" }],
      decide: [],
      look: [],
    };
    data.workers = [];
    data.text = "Standup\n  nothing linked\n";
    answer = { data };
    render(<StandupPage />);
    fireEvent.click(screen.getByRole("button", { name: "Show as list" }));
    const li = screen.getByRole("listitem");
    expect(li.textContent).toContain("K7M2");
    expect(li.textContent).toContain("A card");
    expect(li.querySelector("a")).toBeNull();
    // A card's row starts the work by its id.
    expect(screen.getByRole("button", { name: "Start work on K7M2" })).toBeTruthy();
  });
});

// D-TA20: the grain is a setting per browser -- detail (the default),
// work (the ritual's grain) or brief (the chair's reading) -- and each is the
// agent's own string, shown verbatim.
describe("the grain", () => {
  it("offers the contract's three grains as tabs, detail selected by default", () => {
    answer = { data: withWork(responseFor("friday")) };
    render(<StandupPage />);
    expect(screen.getAllByRole("tab")).toHaveLength(3);
    const tabs = ["Detail", "Work", "Brief"].map((name) => screen.getByRole("tab", { name }));
    expect(tabs.map((t) => t.getAttribute("aria-selected"))).toEqual(["true", "false", "false"]);
    // The tabs are not buttons: nothing else to click was added.
    expect(screen.getAllByRole("button").map((b) => b.textContent)).toEqual([
      "Copy",
      "Play",
      "Show as list",
    ]);
  });

  it("work shows work.text verbatim, keeps the brief above it, and Copy copies it", async () => {
    const data = withWork(responseFor("friday"));
    answer = { data };
    render(<StandupPage />);
    fireEvent.click(screen.getByRole("tab", { name: "Work" }));
    expect(shown()).toBe(data.work!.text);
    expect(shown()).toContain("Opus: Yesterday I closed two in Team Agile (#501, #502).");
    expect(shown()).toContain(
      "Fable: Today I'm on the Studio: #511, the archived-repository mark.",
    );
    expect(screen.getByTestId("standup-brief")).toBeTruthy();
    await act(async () => {
      fireEvent.click(screen.getByRole("button", { name: "Copy" }));
    });
    expect(copyMock).toHaveBeenCalledWith(data.work!.text);
  });

  it("brief shows the chair's reading as the body, once", () => {
    const data = withWork(responseFor("friday"));
    answer = { data };
    render(<StandupPage />);
    fireEvent.click(screen.getByRole("tab", { name: "Brief" }));
    expect(screen.getByTestId("standup-text").textContent).toBe(data.brief);
    expect(screen.queryByTestId("standup-brief")).toBeNull();
  });

  it("is remembered by the browser", () => {
    answer = { data: withWork(responseFor("friday")) };
    const first = render(<StandupPage />);
    fireEvent.click(screen.getByRole("tab", { name: "Work" }));
    expect(localStorage.getItem(GRAIN_KEY)).toBe("work");
    first.unmount();
    render(<StandupPage />);
    expect(screen.getByRole("tab", { name: "Work" }).getAttribute("aria-selected")).toBe("true");
  });

  it("a stored grain that is not one reads as detail", () => {
    localStorage.setItem(GRAIN_KEY, "ticket");
    const data = withWork(responseFor("friday"));
    answer = { data };
    render(<StandupPage />);
    expect(shown()).toBe(data.text);
  });

  it("an agent that predates the work grain shows detail for it", () => {
    const data = responseFor("friday");
    expect(grainParts(data, "work").copy).toBe(data.text);
    expect(grainParts(withWork(data), "work").copy).toBe(withWork(data).work!.text);
    expect(grainParts(data, "brief")).toEqual({
      header: data.text.split("\n")[0],
      body: data.brief,
      copy: data.brief,
    });
  });
});

describe("the page's three helpers", () => {
  it("splits at the first LF and keeps the rest byte for byte", () => {
    expect(splitHeader("A\n  b\n\nc\n")).toEqual({ header: "A", body: "  b\n\nc\n" });
    expect(splitHeader("only")).toEqual({ header: "only", body: "" });
  });

  it("maps every number the response names, from the queue and every slot", () => {
    const urls = issueUrls(responseFor("friday"));
    expect([...urls.keys()].sort()).toEqual([101, 102, 104, 105, 107]);
  });

  it("links only the numbers it knows, and changes no character", () => {
    const parts = linkIssues("#1 and #2.", new Map([[2, "u"]]));
    expect(parts.filter((p) => typeof p === "string")).toEqual(["#1 and ", "."]);
  });
});

// An issue number opens a Fluent Popover with the issue, not a bare link.
describe("the issue popover", () => {
  /** The one triage read the popovers use: issue 104 is open, sev2, in a milestone; the rest are not listed. */
  const triage = (): TriageResponse =>
    ({
      ceremony: "triage",
      space: "toolkit",
      tracker: { ok: true, reason: "" },
      slots: [],
      severities: [],
      deepWaterLabel: "",
      sizes: [],
      text: "",
      groups: [
        {
          milestone: "Ship the standup",
          open: 1,
          routed: 1,
          unrouted: 0,
          context: "",
          issues: [
            {
              number: 104,
              title: "t",
              url: "u",
              worker: "Fable",
              size: "fable",
              severity: "sev2",
              deepWater: false,
            },
          ],
        },
      ],
    }) as TriageResponse;

  const first = (name: string) => screen.getAllByRole("link", { name })[0];
  const surface = () => screen.getByTestId("issue-popover");

  it("keeps the number's text and the page's textContent verbatim", () => {
    const data = responseFor("friday");
    answer = { data };
    triageAnswer = { data: triage() };
    render(<StandupPage />);
    expect(shown()).toBe(data.text);
    expect(first("#104").textContent).toBe("#104");
  });

  it("a click opens the surface with the title, the worker chip, severity, milestone and state, and does not leave", async () => {
    const data = responseFor("friday");
    answer = { data };
    triageAnswer = { data: triage() };
    render(<StandupPage />);
    expect(screen.queryByTestId("issue-popover")).toBeNull();
    const notPrevented = fireEvent.click(first("#104"));
    // The default (following the href) was prevented: the page is still here.
    expect(notPrevented).toBe(false);
    await waitFor(() => expect(surface()).toBeTruthy());
    const title = data.queue.walk.find((i) => i.number === 104)!.title;
    const text = surface().textContent ?? "";
    expect(text).toContain(title);
    // Issue 104 is a blocker: the chip is ROLE · PERSONA (label).
    expect(text).toContain("TEAM LEAD · DEV-HERO (fable)");
    expect(text).toContain("sev2");
    expect(text).toContain("Ship the standup");
    expect(text).toContain("Open");
  });

  it("opens on hover too", async () => {
    answer = { data: responseFor("friday") };
    triageAnswer = { data: triage() };
    render(<StandupPage />);
    fireEvent.mouseEnter(first("#104"));
    await waitFor(() => expect(surface()).toBeTruthy());
  });

  it("puts Open on GitHub last, as the one external link", async () => {
    answer = { data: responseFor("friday") };
    triageAnswer = { data: triage() };
    render(<StandupPage />);
    fireEvent.click(first("#104"));
    await waitFor(() => expect(surface()).toBeTruthy());
    const links = Array.from(surface().querySelectorAll("a"));
    expect(links).toHaveLength(1);
    expect(links[0].textContent).toBe("Open on GitHub");
    expect(links[0].getAttribute("href")).toBe("https://github.com/johnfrog76/toolkit/issues/104");
    expect(links[0].parentElement!.lastElementChild).toBe(links[0]);
  });

  it("shows severity and milestone only when the triage read has the number", async () => {
    answer = { data: responseFor("friday") };
    triageAnswer = { data: triage() };
    render(<StandupPage />);
    // Issue 101 is not in the read: no severity or milestone (its state is its slot's, below).
    fireEvent.click(first("#101"));
    await waitFor(() => expect(surface()).toBeTruthy());
    const text = surface().textContent ?? "";
    expect(text).not.toMatch(/sev\d/);
    expect(text).not.toContain("Ship the standup");
  });

  it("states what the slot says, with or without the triage read", async () => {
    // Friday: issues 102 and 107 are yesterday's; 101 is today's; 104 is walked and a blocker.
    expect(slotState("yesterday")).toBe("Closed");
    for (const k of ["today", "blockers", "walk", "decide", "look"])
      expect(slotState(k)).toBe("Open");
    expect(slotState("elsewhere")).toBeUndefined();
    const facts = issueFacts(responseFor("friday"));
    expect(facts.get(102)?.state).toBe("Closed");
    expect(facts.get(107)?.state).toBe("Closed");
    expect(facts.get(101)?.state).toBe("Open");
    expect(facts.get(104)?.state).toBe("Open");
    // No triage read: no severity or milestone, the state stands.
    answer = { data: responseFor("friday") };
    render(<StandupPage />);
    fireEvent.click(first("#102"));
    await waitFor(() => expect(surface()).toBeTruthy());
    const text = surface().textContent ?? "";
    expect(text).toContain("Closed");
    expect(text).not.toMatch(/sev\d/);
    expect(text).toContain("Open on GitHub");
  });

  it("Escape closes it", async () => {
    answer = { data: responseFor("friday") };
    render(<StandupPage />);
    fireEvent.click(first("#104"));
    await waitFor(() => expect(surface()).toBeTruthy());
    fireEvent.keyDown(surface(), { key: "Escape" });
    await waitFor(() => expect(screen.queryByTestId("issue-popover")).toBeNull());
  });

  it("the chip is left out when the seat is not known", () => {
    const data = responseFor("friday");
    data.workers[0].label = "someone-else";
    data.workers[0].name = "Someone";
    const facts = issueFacts(data);
    expect(facts.get(104)?.worker).toBeUndefined();
    expect(facts.get(102)?.worker).toBe("AI VIBEMANCER (opus)");
  });

  it("a card's surface shows its id, title and path, and no external link", async () => {
    const data = responseFor("friday");
    data.source = "cards";
    data.queue = {
      walk: [{ number: null, id: "K7M2", title: "A card", url: "", path: "current/K7M2-a.md" }],
      decide: [],
      look: [],
    };
    data.workers = [];
    data.text = "Standup\n  nothing linked\n";
    answer = { data };
    render(<StandupPage />);
    fireEvent.click(screen.getByRole("button", { name: "Show as list" }));
    fireEvent.click(screen.getByText("K7M2"));
    await waitFor(() => expect(surface()).toBeTruthy());
    expect(surface().textContent).toContain("A card");
    expect(surface().textContent).toContain("current/K7M2-a.md");
    expect(surface().querySelector("a")).toBeNull();
  });
});
