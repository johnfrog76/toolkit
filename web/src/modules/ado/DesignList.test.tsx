import { fireEvent, render, screen, within } from "@testing-library/react";
import { MemoryRouter, Route, Routes, useLocation } from "react-router";
import { DesignList } from "./DesignList";
import { DesignDocPage, designDocument } from "./DesignDocPage";
import { groupByState, notShownLine } from "./DesignGroups";
import type { Design, DesignDoc, DesignDocDetail, IssueDetail } from "./api.ado";

// The Design tab (Studio S2, D-S11; the design lifecycle's reader, L2).
// The agent's reads and the state rule are pinned in Tests/test_design.py; here
// the list -- ONE list grouped by state in road order, Complete and Archived
// collapsed to a count, a row the design with its state, id and thread, the
// files not shown counted with the fix named, the empty state that teaches --
// and the reading room, the document then its thread in ONE viewer, an
// archived document by its path. The viewer is mocked (react-markdown is ESM,
// the registry tests' rule).
jest.mock("../../shared/MarkdownViewer", () => ({
  MarkdownViewer: ({ content }: { content: string }) => <pre data-testid="viewer">{content}</pre>,
}));

const NOTE: DesignDoc = {
  folder: "design",
  name: "board-note.md",
  path: "design/board-note.md",
  title: "A note about the board",
  description: "",
  thread: "",
  thread_number: null,
  thread_repo: "",
  url: "https://github.com/johnfrog76/toolkit/blob/main/design/board-note.md",
  id: "11111111-0000-4000-8000-000000000001",
  kind: "note",
  archived: false,
};
const STUDIO_NOTE: DesignDoc = {
  ...NOTE,
  name: "toolkit-studio.md",
  path: "design/toolkit-studio.md",
  title: "Feature: the Studio",
  id: "22222222-0000-4000-8000-000000000002",
  url: "https://github.com/johnfrog76/toolkit/blob/main/design/toolkit-studio.md",
};
const SPEC: DesignDoc = {
  folder: "spec",
  name: "toolkit-studio.spec.md",
  path: "spec/toolkit-studio.spec.md",
  title: "The Studio",
  description: "Design contract for the Studio.",
  thread: "https://github.com/johnfrog76/toolkit/issues/90",
  thread_number: 90,
  thread_repo: "johnfrog76/toolkit",
  url: "https://github.com/johnfrog76/toolkit/blob/main/spec/toolkit-studio.spec.md",
  id: "22222222-0000-4000-8000-000000000002",
  kind: "spec",
  archived: false,
};
const OLD: DesignDoc = {
  ...NOTE,
  folder: "design/archive",
  name: "a-second-room.md",
  path: "design/archive/a-second-room.md",
  title: "A second room",
  id: "33333333-0000-4000-8000-000000000003",
  archived: true,
  closed: "2026-11-20",
  outcome: "dropped",
  url: "https://github.com/johnfrog76/toolkit/blob/main/design/archive/a-second-room.md",
};
const BUILT: DesignDoc = {
  ...SPEC,
  folder: "spec/archive",
  name: "cards.spec.md",
  path: "spec/archive/cards.spec.md",
  title: "Cards (spec)",
  description: "",
  thread: "",
  thread_number: null,
  thread_repo: "",
  id: "44444444-0000-4000-8000-000000000004",
  archived: true,
  closed: "2026-10-01",
  docs: "docs/hub/cards.md",
  url: "https://github.com/johnfrog76/toolkit/blob/main/spec/archive/cards.spec.md",
};

const design = (over: Partial<Design>): Design => ({
  id: "",
  short: "",
  state: "Design",
  title: "",
  description: "",
  thread: "",
  thread_number: null,
  thread_repo: "",
  closed: "",
  outcome: "",
  mismatch: "",
  docs: "",
  note: null,
  spec: null,
  space: "",
  thread_space: "",
  ...over,
});
const D_NOTE = design({
  id: NOTE.id!,
  short: "11111111",
  state: "Design",
  title: NOTE.title,
  note: NOTE,
});
const D_STUDIO = design({
  id: SPEC.id!,
  short: "22222222",
  state: "Spec",
  title: STUDIO_NOTE.title,
  description: "What the Studio is.",
  thread: SPEC.thread,
  thread_number: 90,
  thread_repo: SPEC.thread_repo,
  note: STUDIO_NOTE,
  spec: SPEC,
});
const D_OLD = design({
  id: OLD.id!,
  short: "33333333",
  state: "Archived",
  title: OLD.title,
  closed: "2026-11-20",
  outcome: "dropped",
  note: OLD,
});
const D_BUILT = design({
  id: BUILT.id!,
  short: "44444444",
  state: "Complete",
  title: BUILT.title,
  closed: "2026-10-01",
  docs: "docs/hub/cards.md",
  spec: BUILT,
});
const FULL = {
  supported: true,
  repo: "johnfrog76/toolkit",
  items: [NOTE, STUDIO_NOTE, OLD, SPEC, BUILT],
  designs: [D_NOTE, D_STUDIO, D_BUILT, D_OLD],
  notShown: [],
  structure: { design: true, spec: true },
};

let listAnswer: { data?: unknown; error?: unknown } = {};
let docAnswer: { data?: unknown; error?: unknown } = {};
let docAsked: { folder: string; name: string } | null = null;
let threadAnswer: { data?: unknown } = {};
let threadSkipped: boolean | undefined;
// Search inside (L2b): the lazy query, asked only on the button.
const searchedFor: string[] = [];
let searchAnswer: { data?: unknown; error?: unknown; isFetching?: boolean } = {};
jest.mock("./api.ado", () => ({
  useGetDesignQuery: () => ({
    isLoading: false,
    isFetching: false,
    refetch: jest.fn(),
    ...listAnswer,
  }),
  useLazySearchDesignQuery: () => [
    (q: string) => {
      searchedFor.push(q);
      return Promise.resolve();
    },
    { isFetching: false, ...searchAnswer },
  ],
  useGetDesignDocQuery: (arg: { folder: string; name: string }) => {
    docAsked = arg;
    return { isLoading: false, isFetching: false, refetch: jest.fn(), ...docAnswer };
  },
  useGetIssueDetailQuery: (_arg: unknown, opts?: { skip?: boolean }) => {
    threadSkipped = opts?.skip;
    return opts?.skip ? {} : threadAnswer;
  },
}));

function Where() {
  const loc = useLocation();
  return <div data-testid="where">{loc.pathname + loc.search}</div>;
}

function mountList() {
  return render(
    <MemoryRouter initialEntries={["/design"]}>
      <Routes>
        <Route
          path="*"
          element={
            <>
              <DesignList />
              <Where />
            </>
          }
        />
      </Routes>
    </MemoryRouter>,
  );
}

const group = (state: string) => screen.getByRole("region", { name: `${state} designs` });

describe("the Design tab's list", () => {
  beforeEach(() => {
    window.localStorage.clear();
    listAnswer = { data: FULL };
  });

  it("is one list grouped by state in road order, Complete and Archived collapsed to a count", () => {
    mountList();
    const headings = screen.getAllByRole("region").map((r) => r.getAttribute("aria-label"));
    expect(headings).toEqual([
      "Design designs",
      "Spec designs",
      "Complete designs",
      "Archived designs",
    ]);
    expect(within(group("Design")).getByText("A note about the board")).toBeTruthy();
    expect(within(group("Spec")).getByText("Feature: the Studio")).toBeTruthy();
    expect(within(group("Complete")).queryByText("Cards (spec)")).toBeNull();
    expect(within(group("Archived")).queryByText("A second room")).toBeNull();
    expect(within(group("Complete")).getByText("1")).toBeTruthy();
    expect(
      screen.getByRole("button", { name: "Show Archived" }).getAttribute("aria-expanded"),
    ).toBe("false");
  });

  it("a collapsed group opens on its toggle, and shows the archive as it is read", () => {
    mountList();
    fireEvent.click(screen.getByRole("button", { name: "Show Archived" }));
    const archived = group("Archived");
    expect(within(archived).getByText("A second room")).toBeTruthy();
    // The row's outcome badge, beside the group's outcome chip of the same word (L2b).
    expect(within(archived).getAllByText("dropped").length).toBeGreaterThan(1);
    expect(within(archived).getByText("Closed 2026-11-20")).toBeTruthy();
    fireEvent.click(screen.getByRole("button", { name: "Show Complete" }));
    expect(within(group("Complete")).getByText("docs/hub/cards.md")).toBeTruthy();
  });

  it("a Complete design's Docs line opens the document in the Docs tab", () => {
    mountList();
    fireEvent.click(screen.getByRole("button", { name: "Show Complete" }));
    fireEvent.click(within(group("Complete")).getByText("docs/hub/cards.md"));
    expect(screen.getByTestId("where").textContent).toBe("/docs/docs/hub/cards.md");
  });

  it("a row is the design: its title, description, state, short id and thread chip", () => {
    mountList();
    const row = within(group("Spec"));
    expect(row.getByText("What the Studio is.")).toBeTruthy();
    expect(row.getAllByText("Spec").length).toBeGreaterThan(0);
    expect(row.getByText("22222222").getAttribute("title")).toBe(SPEC.id!);
    expect(row.getByText("#90")).toBeTruthy();
    expect(row.getByText("toolkit-studio.spec.md")).toBeTruthy();
  });

  it("in Spec the row opens the spec, with the note beside it in the menu", async () => {
    mountList();
    fireEvent.click(within(group("Spec")).getByRole("button", { name: "Open the spec" }));
    expect(screen.getByTestId("where").textContent).toBe("/design/spec/toolkit-studio.spec.md");
    fireEvent.click(screen.getByRole("button", { name: "Actions for Feature: the Studio" }));
    const items = (await screen.findAllByRole("menuitem")).map((m) => m.textContent);
    expect(items).toEqual(["Open the note", "Open the thread", "Open on GitHub"]);
  });

  it("a note alone opens its document; the menu ends on github.com", async () => {
    mountList();
    fireEvent.click(within(group("Design")).getByRole("button", { name: "Open the document" }));
    expect(screen.getByTestId("where").textContent).toBe("/design/design/board-note.md");
    fireEvent.click(screen.getByRole("button", { name: "Actions for A note about the board" }));
    const items = (await screen.findAllByRole("menuitem")).map((m) => m.textContent);
    expect(items).toEqual(["Open on GitHub"]);
  });

  it("an archived document's row opens it by its archive path", () => {
    mountList();
    fireEvent.click(screen.getByRole("button", { name: "Show Archived" }));
    fireEvent.click(within(group("Archived")).getByRole("button", { name: "Open the document" }));
    expect(screen.getByTestId("where").textContent).toBe("/design/design/archive/a-second-room.md");
  });

  it("a search opens the collapsed groups that have a match", () => {
    window.localStorage.setItem("ado.design.text", "second room");
    mountList();
    expect(within(group("Archived")).getByText("A second room")).toBeTruthy();
    expect(screen.queryByRole("region", { name: "Design designs" })).toBeNull();
  });

  it("files without an id are counted under the list, with the fix and Learn more", () => {
    listAnswer = {
      data: {
        ...FULL,
        notShown: [
          { path: "design/x.md", reason: "no id" },
          { path: "design/y.md", reason: "no id" },
          { path: "spec/a.md", reason: "2 specs carry the id 5555" },
        ],
      },
    };
    mountList();
    const line = screen.getByRole("status");
    expect(line.textContent).toContain("2 files not shown: no id. Give them ids with StampDesign.");
    expect(line.textContent).toContain("1 file not shown: two notes or two specs carry one id.");
    expect(within(line).getByRole("link", { name: "Learn more" }).getAttribute("href")).toContain(
      "docs/hub/design.md",
    );
  });

  it("a row says when its two files disagree about where the design is", () => {
    listAnswer = {
      data: {
        ...FULL,
        designs: [
          { ...D_BUILT, mismatch: "The spec is archived and the note was left behind in design/." },
        ],
      },
    };
    mountList();
    fireEvent.click(screen.getByRole("button", { name: "Show Complete" }));
    expect(screen.getByRole("note").textContent).toBe(
      "The spec is archived and the note was left behind in design/.",
    );
  });

  it("no structure: the tab teaches what the folders give, with Learn more", () => {
    listAnswer = {
      data: {
        supported: true,
        repo: "o/r",
        items: [],
        designs: [],
        notShown: [],
        structure: { design: false, spec: false },
      },
    };
    mountList();
    expect(screen.getByText("No design/ folder yet")).toBeTruthy();
    expect(screen.getByText(/gives a product a Design tab/)).toBeTruthy();
    expect(screen.getByRole("link", { name: "Learn more" }).getAttribute("href")).toBe(
      "https://github.com/johnfrog76/toolkit/blob/main/docs/hub/design.md",
    );
  });

  it("folders with nothing in them say where the documents would come from", () => {
    listAnswer = {
      data: {
        supported: true,
        repo: "o/r",
        items: [],
        designs: [],
        notShown: [],
        structure: { design: true, spec: false },
      },
    };
    mountList();
    expect(screen.getByText("No designs or specs yet")).toBeTruthy();
    expect(
      screen.getByText(/A note in o\/r's design\/ or a spec in spec\/ shows up here/),
    ).toBeTruthy();
  });

  it("only unstamped files: no rows, and the count says why", () => {
    listAnswer = {
      data: {
        supported: true,
        repo: "o/r",
        items: [NOTE],
        designs: [],
        notShown: [{ path: "design/board-note.md", reason: "no id" }],
        structure: { design: true, spec: false },
      },
    };
    mountList();
    expect(screen.queryByText("No designs or specs yet")).toBeNull();
    expect(screen.getByRole("status").textContent).toContain(
      "1 file not shown: no id. Give it one with StampDesign.",
    );
  });

  it("an owner-grained address says the agent's sentence", () => {
    listAnswer = {
      error: {
        status: 400,
        data: { detail: "This Space's address names a GitHub owner, not a repository." },
      },
    };
    mountList();
    expect(screen.getByText("No repository to read")).toBeTruthy();
    expect(
      screen.getByText("This Space's address names a GitHub owner, not a repository."),
    ).toBeTruthy();
  });

  it("an older agent with no groups reads as nothing to show, not as an error", () => {
    listAnswer = { data: { supported: true, repo: "o/r", items: [NOTE] } };
    mountList();
    expect(screen.getByText("No designs or specs yet")).toBeTruthy();
  });
});

// Search inside (L2b): on the button only, after the groups are drawn;
// a hit names the design, its state and the line, and opens its room; a search
// that cannot run says why in a row; the note says what it cannot see.
describe("search inside", () => {
  const HIT = {
    path: "spec/archive/cards.spec.md",
    name: "cards.spec.md",
    line: "the ambient room",
    url: BUILT.url,
    id: BUILT.id!,
    title: "Cards (spec)",
    state: "Complete",
    kind: "spec",
    archived: true,
  };
  const NO_ID = {
    ...HIT,
    path: "design/x.md",
    name: "x.md",
    line: "an ambient room, unstamped",
    id: "",
    title: "No id here",
    state: "",
    kind: "note",
    archived: false,
  };
  const FOUND = {
    supported: true,
    repo: "johnfrog76/toolkit",
    query: "ambient",
    available: true,
    reason: "",
    note: "GitHub's code search reads the default branch only.",
    hits: [HIT, NO_ID],
  };

  beforeEach(() => {
    window.localStorage.clear();
    listAnswer = { data: FULL };
    searchedFor.length = 0;
    searchAnswer = {};
  });

  it("offers the button only once the box has words, and asks with them when pressed", () => {
    mountList();
    expect(screen.queryByRole("button", { name: "Search inside" })).toBeNull();
    window.localStorage.setItem("ado.design.text", "  ambient ");
    mountList();
    fireEvent.click(screen.getAllByRole("button", { name: "Search inside" })[0]);
    expect(searchedFor).toEqual(["ambient"]);
  });

  it("shows each hit with its state and line, opens its room, and says the note", () => {
    window.localStorage.setItem("ado.design.text", "ambient");
    searchAnswer = { data: FOUND };
    mountList();
    fireEvent.click(screen.getByRole("button", { name: "Search inside" }));
    const section = within(screen.getByRole("region", { name: "Matches inside" }));
    expect(section.getByText('Matches inside for "ambient"')).toBeTruthy();
    expect(section.getByText("Cards (spec)")).toBeTruthy();
    expect(section.getByText("the ambient room")).toBeTruthy();
    expect(section.getByText("no id")).toBeTruthy();
    expect(section.getByText("GitHub's code search reads the default branch only.")).toBeTruthy();
    fireEvent.click(section.getByRole("button", { name: "Open spec/archive/cards.spec.md" }));
    expect(screen.getByTestId("where").textContent).toBe("/design/spec/archive/cards.spec.md");
  });

  it("a search that cannot run says why in a row, and Clear takes the section away", () => {
    window.localStorage.setItem("ado.design.text", "ambient");
    searchAnswer = {
      data: {
        ...FOUND,
        available: false,
        reason: "johnfrog76/toolkit: API rate limit exceeded",
        hits: [],
      },
    };
    mountList();
    fireEvent.click(screen.getByRole("button", { name: "Search inside" }));
    const inside = within(screen.getByRole("region", { name: "Matches inside" }));
    expect(inside.getByRole("status").textContent).toContain(
      "Could not search inside: johnfrog76/toolkit: API rate limit exceeded",
    );
    fireEvent.click(screen.getByRole("button", { name: "Clear the matches inside" }));
    expect(screen.queryByRole("region", { name: "Matches inside" })).toBeNull();
  });

  it("the agent not answering is said as such, not as an empty result", () => {
    window.localStorage.setItem("ado.design.text", "ambient");
    searchAnswer = { error: { status: "FETCH_ERROR" } };
    mountList();
    fireEvent.click(screen.getByRole("button", { name: "Search inside" }));
    const inside = within(screen.getByRole("region", { name: "Matches inside" }));
    expect(inside.getByRole("status").textContent).toContain("the agent did not answer");
  });
});

// The Archived group's outcome filter (L2b): shipped, dropped, or nothing said.
describe("the outcome filter", () => {
  const SHIPPED = design({
    ...D_OLD,
    id: "55555555-0000-4000-8000-000000000005",
    title: "A shipped deck",
    outcome: "shipped",
    note: { ...OLD, name: "deck.md", path: "design/archive/deck.md", outcome: "shipped" },
  });
  const PLAIN = design({
    ...D_OLD,
    id: "66666666-0000-4000-8000-000000000006",
    title: "An old note",
    outcome: "",
    note: { ...OLD, name: "old.md", path: "design/archive/old.md", outcome: "" },
  });

  beforeEach(() => {
    window.localStorage.clear();
    listAnswer = { data: { ...FULL, designs: [D_NOTE, D_OLD, SHIPPED, PLAIN] } };
  });

  it("is drawn on the open Archived group, narrows its rows and says how many of how many", () => {
    mountList();
    expect(screen.queryByRole("radiogroup", { name: "Archived outcome" })).toBeNull();
    fireEvent.click(screen.getByRole("button", { name: "Show Archived" }));
    const chips = within(screen.getByRole("radiogroup", { name: "Archived outcome" }));
    expect(chips.getAllByRole("radio").map((r) => r.textContent)).toEqual([
      "any outcome",
      "shipped",
      "dropped",
      "nothing said",
    ]);
    const archived = () => within(screen.getByRole("region", { name: "Archived designs" }));
    expect(archived().getAllByRole("button", { name: "Open the document" })).toHaveLength(3);
    fireEvent.click(chips.getByRole("radio", { name: "dropped" }));
    expect(archived().getAllByRole("button", { name: "Open the document" })).toHaveLength(1);
    expect(archived().getByText("A second room")).toBeTruthy();
    expect(archived().getByText("1 of 3")).toBeTruthy();
    fireEvent.click(chips.getByRole("radio", { name: "nothing said" }));
    expect(archived().getByText("An old note")).toBeTruthy();
    expect(archived().queryByText("A shipped deck")).toBeNull();
    // The same chip again is off.
    fireEvent.click(chips.getByRole("radio", { name: "nothing said" }));
    expect(archived().getAllByRole("button", { name: "Open the document" })).toHaveLength(3);
  });

  it("the Design group is not filtered by it", () => {
    mountList();
    fireEvent.click(screen.getByRole("button", { name: "Show Archived" }));
    fireEvent.click(
      within(screen.getByRole("radiogroup", { name: "Archived outcome" })).getByRole("radio", {
        name: "shipped",
      }),
    );
    expect(
      within(screen.getByRole("region", { name: "Design designs" })).getByText(
        "A note about the board",
      ),
    ).toBeTruthy();
  });
});

describe("the grouping rules", () => {
  it("groups in road order and leaves an empty state out", () => {
    expect(groupByState([D_OLD, D_NOTE]).map((g) => [g.state, g.designs.length])).toEqual([
      ["Design", 1],
      ["Archived", 1],
    ]);
  });

  it("the not-shown line counts by reason, and is empty when every file is a design", () => {
    expect(notShownLine([], "StampDesign")).toBe("");
    expect(notShownLine([{ path: "a", reason: "no id" }], "StampDesign -Hub")).toBe(
      "1 file not shown: no id. Give it one with StampDesign -Hub.",
    );
  });
});

const DETAIL: DesignDocDetail = {
  ...SPEC,
  supported: true,
  repo: "johnfrog76/toolkit",
  body: "# The Studio\n\nBody.",
  reason: null,
};
const THREAD: IssueDetail = {
  supported: true,
  number: 90,
  title: "Feature: the Studio",
  state: "open",
  body: "The issue body.",
  author: "johnfrog76",
  created: "2026-09-29",
  closed: "",
  url: "https://github.com/johnfrog76/toolkit/issues/90",
  labels: [],
  kind: "Feature",
  milestone: "",
  assignee: "",
  repo: "toolkit",
  comments: [{ author: "fable", when: "2026-09-29", body: "D-S11 recorded." }],
  timeline: [],
  reason: null,
};

function mountDoc(at = "/design/spec/toolkit-studio.spec.md") {
  return render(
    <MemoryRouter initialEntries={[at]}>
      <Routes>
        <Route path="/design/:folder/:name" element={<DesignDocPage />} />
        <Route path="/design/:folder/archive/:name" element={<DesignDocPage archive />} />
      </Routes>
    </MemoryRouter>,
  );
}

describe("a design document's reading room", () => {
  beforeEach(() => {
    docAsked = null;
  });

  it("reads the document, then its thread, in one viewer", () => {
    docAnswer = { data: DETAIL };
    threadAnswer = { data: THREAD };
    mountDoc();
    const text = screen.getByTestId("viewer").textContent ?? "";
    expect(text.indexOf("Body.")).toBeLessThan(
      text.indexOf("## The thread: [#90 Feature: the Studio]"),
    );
    expect(text).toContain("D-S11 recorded.");
    expect(screen.getAllByTestId("viewer")).toHaveLength(1);
    expect(threadSkipped).toBe(false);
    expect(docAsked).toEqual({ folder: "spec", name: "toolkit-studio.spec.md" });
  });

  it("a document with no thread asks for none", () => {
    docAnswer = { data: { ...DETAIL, thread: "", thread_number: null, thread_repo: "" } };
    mountDoc();
    expect(threadSkipped).toBe(true);
    expect(screen.getByTestId("viewer").textContent).not.toContain("The thread");
  });

  it("a thread in another repo is linked, not read -- the issue route would read the wrong one", () => {
    docAnswer = { data: { ...DETAIL, thread_repo: "someone/else" } };
    mountDoc();
    expect(threadSkipped).toBe(true);
    expect(screen.getByTitle("The thread, #90 on GitHub").getAttribute("href")).toBe(DETAIL.thread);
  });

  it("an archived document is read by its archive path and wears its Closed date and outcome", () => {
    docAnswer = {
      data: {
        ...OLD,
        supported: true,
        repo: "johnfrog76/toolkit",
        body: "# A second room\n\nDropped.",
        reason: null,
      },
    };
    mountDoc("/design/design/archive/a-second-room.md");
    expect(docAsked).toEqual({ folder: "design/archive", name: "a-second-room.md" });
    expect(screen.getByText("design/archive")).toBeTruthy();
    expect(screen.getByText("Closed 2026-11-20")).toBeTruthy();
    expect(screen.getByText("dropped")).toBeTruthy();
    expect(screen.getByText("33333333").getAttribute("title")).toBe(OLD.id!);
  });

  it("a missing document says so", () => {
    docAnswer = { error: { status: 404, data: { detail: "No spec/x.md" } } };
    mountDoc();
    expect(screen.getByText("No spec/toolkit-studio.spec.md")).toBeTruthy();
  });

  it("designDocument leaves an unreadable thread out", () => {
    expect(designDocument(DETAIL, { ...THREAD, reason: "gh did not answer" })).toBe(DETAIL.body);
  });
});
