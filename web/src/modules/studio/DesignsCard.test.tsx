import { act, fireEvent, render, screen, within } from "@testing-library/react";
import { MemoryRouter, Route, Routes, useLocation } from "react-router";
import { DesignsCard } from "./DesignsCard";
import { DesignNotePage, promoteBlocked } from "./DesignNotePage";
import { noteLinkBase } from "./noteLinks";
import { resolveLink } from "../../shared/docLinks";
import { buildNewDesignParams, buildPromoteDesignParams } from "../ado/cliBridge";
import type { EnvStatus } from "../../shell/api";
import type { DesignNote } from "./api.studio";

// The seed drawer (Studio S2b, D-S3): the hub's design/ notes, the + that
// writes one through NewDesign (the bridge -- never a native write), and one
// note's reading room. The agent's reads are pinned in Tests/test_studio.py,
// the verb's bytes there too. The viewer is mocked (react-markdown is ESM).
jest.mock("../../shared/MarkdownViewer", () => ({
  MarkdownViewer: ({ content }: { content: string }) => <pre data-testid="viewer">{content}</pre>,
}));

const NOTE: DesignNote = {
  name: "board-ideas.md",
  title: "Board ideas",
  description: "What the board could show next",
  space: "toolkit",
  thread: "https://github.com/johnfrog76/toolkit/issues/90",
  thread_number: 90,
  thread_repo: "johnfrog76/toolkit",
  thread_space: "toolkit",
};
const BARE: DesignNote = {
  ...NOTE,
  name: "offline.md",
  title: "Offline specs",
  description: "",
  space: "",
  thread: "",
  thread_number: null,
  thread_repo: "",
  thread_space: "",
};

let listAnswer: { data?: unknown; error?: unknown } = {};
let noteAnswer: { data?: unknown; error?: unknown } = {};
const sent: string[][] = [];
let reply: { status: string; output: string | null; error: string | null } = {
  status: "success",
  output: "Created design note: design/x.md",
  error: null,
};

jest.mock("./api.studio", () => ({
  useGetDesignNotesQuery: () => ({
    isLoading: false,
    isFetching: false,
    refetch: jest.fn(),
    ...listAnswer,
  }),
  useGetDesignNoteQuery: () => ({
    isLoading: false,
    isFetching: false,
    refetch: jest.fn(),
    ...noteAnswer,
  }),
  useRunNewDesignMutation: () => [
    ({ params }: { params: string[] }) => {
      sent.push(params);
      return {
        unwrap: () =>
          Promise.resolve({ command: "NewDesign", exit_code: 0, duration: 1, ...reply }),
      };
    },
    { isLoading: false },
  ],
  useRunPromoteDesignMutation: () => [
    ({ params }: { params: string[] }) => {
      promotedWith.push(params);
      return {
        unwrap: () =>
          Promise.resolve({ command: "NewItem", exit_code: 0, duration: 1, ...promoteReply }),
      };
    },
    { isLoading: false },
  ],
  useRunMoveDesignMutation: () => [
    ({ params }: { params: string[] }) => {
      movedWith.push(params);
      return {
        unwrap: () =>
          Promise.resolve({ command: "MoveDesign", exit_code: 0, duration: 1, ...moveReply }),
      };
    },
    { isLoading: false },
  ],
  // Search inside the hub (L2b): the lazy query, asked only on the button.
  useLazySearchHubDesignsQuery: () => [
    (q: string) => {
      hubSearchedFor.push(q);
      return Promise.resolve();
    },
    { isFetching: false, ...hubSearchAnswer },
  ],
}));
const hubSearchedFor: string[] = [];
let hubSearchAnswer: { data?: unknown; error?: unknown } = {};
const movedWith: string[][] = [];
let moveReply: { status: string; output: string | null; error: string | null } = {
  status: "success",
  output: "Moved: 'Board ideas' -> Spec.",
  error: null,
};
const promotedWith: string[][] = [];
let promoteReply: { status: string; output: string | null; error: string | null } = {
  status: "success",
  output: "[+] Created: issue #41 -- Board ideas",
  error: null,
};
let threadAnswer: { data?: unknown } = {};
let threadAsked: { arg: unknown; skip?: boolean } | null = null;
jest.mock("../ado/api.ado", () => ({
  useGetIssueDetailQuery: (arg: unknown, opts?: { skip?: boolean }) => {
    threadAsked = { arg, skip: opts?.skip };
    return opts?.skip ? {} : threadAnswer;
  },
}));
// The chip's switch is the foyer's (useEnterSpace), so it is mocked the way
// FoyerCard.test.tsx mocks it.
const switched: string[] = [];
let switchFails = false;
jest.mock("../../shell/api", () => ({
  useGetEnvQuery: () => ({
    data: {
      tracker: "github",
      config: {
        activeSpace: "toolkit",
        spaces: [
          { slug: "toolkit", name: "Toolkit", status: "active", tracker: "github" },
          { slug: "wasteland", name: "The Wasteland", status: "active", tracker: "github" },
        ],
      },
    },
  }),
  useSwitchModeMutation: () => [
    ({ mode }: { mode: string }) => {
      switched.push(mode);
      return {
        unwrap: () => (switchFails ? Promise.reject(new Error("no")) : Promise.resolve({})),
      };
    },
    { isLoading: false },
  ],
}));

function Where() {
  const loc = useLocation();
  return <div data-testid="where">{loc.pathname}</div>;
}

function mount(at = "/studio") {
  return render(
    <MemoryRouter initialEntries={[at]}>
      <Routes>
        <Route
          path="/studio/design/*"
          element={
            <>
              <DesignNotePage />
              <Where />
            </>
          }
        />
        <Route
          path="*"
          element={
            <>
              <DesignsCard />
              <Where />
            </>
          }
        />
      </Routes>
    </MemoryRouter>,
  );
}

describe("the Designs card", () => {
  beforeEach(() => {
    sent.length = 0;
    reply = { status: "success", output: "Created design note: design/x.md", error: null };
    listAnswer = { data: { folder: "design", count: 2, items: [NOTE, BARE] } };
  });

  it("lists each note: its title, its sentence, the Space it names and its thread", () => {
    mount();
    expect(screen.getByText("Board ideas")).toBeTruthy();
    expect(screen.getByText("What the board could show next")).toBeTruthy();
    expect(screen.getByText("Toolkit")).toBeTruthy();
    expect(screen.getByText("#90")).toBeTruthy();
    expect(screen.getByText("no thread yet")).toBeTruthy();
  });

  it("says what it is: Hub Designs, your private files", () => {
    mount();
    expect(screen.getByText("Hub Designs")).toBeTruthy();
    expect(
      screen.getByText("Your private files. Notes that belong to no product yet."),
    ).toBeTruthy();
  });

  it("a note that names a Space shows it as a chip; a note with none shows no chip", () => {
    mount();
    const chips = screen.getAllByRole("button", { name: /^Switch to / });
    expect(chips.map((c) => c.textContent)).toEqual(["Toolkit"]);
    expect(chips[0].getAttribute("aria-label")).toBe("Switch to Toolkit");
  });

  it("the chip names the Space by its display name, the slug when none is declared", () => {
    listAnswer = {
      data: {
        folder: "design",
        count: 2,
        items: [
          { ...NOTE, space: "wasteland" },
          { ...BARE, space: "nowhere" },
        ],
      },
    };
    mount();
    expect(screen.getByRole("button", { name: "Switch to The Wasteland" }).textContent).toBe(
      "The Wasteland",
    );
    expect(screen.getByRole("button", { name: "Switch to nowhere" })).toBeTruthy();
  });

  it("the chip switches into its Space and lands on that Space's first tab", async () => {
    switched.length = 0;
    switchFails = false;
    listAnswer = { data: { folder: "design", count: 1, items: [{ ...NOTE, space: "wasteland" }] } };
    mount();
    await act(async () => {
      fireEvent.click(screen.getByRole("button", { name: "Switch to The Wasteland" }));
    });
    expect(switched).toEqual(["wasteland"]);
    expect(screen.getByTestId("where").textContent).toBe("/");
  });

  it("the chip for the Space you are in only goes home, switching nothing", async () => {
    switched.length = 0;
    mount();
    await act(async () => {
      fireEvent.click(screen.getByRole("button", { name: "Switch to Toolkit" }));
    });
    expect(switched).toEqual([]);
    expect(screen.getByTestId("where").textContent).toBe("/");
  });

  it("a switch that fails says so on the row and goes nowhere", async () => {
    switched.length = 0;
    switchFails = true;
    listAnswer = { data: { folder: "design", count: 1, items: [{ ...NOTE, space: "wasteland" }] } };
    mount();
    await act(async () => {
      fireEvent.click(screen.getByRole("button", { name: "Switch to The Wasteland" }));
    });
    switchFails = false;
    expect(screen.getByRole("alert").textContent).toBe(
      "Could not switch to The Wasteland. Nothing changed.",
    );
    expect(screen.getByTestId("where").textContent).toBe("/studio");
  });

  it("a row's one action opens the note's reading room", () => {
    mount();
    fireEvent.click(screen.getAllByRole("button", { name: "Open the note" })[0]);
    expect(screen.getByTestId("where").textContent).toBe("/studio/design/board-ideas.md");
  });

  it("says what the drawer is when it is empty", () => {
    listAnswer = { data: { folder: "design", count: 0, items: [] } };
    mount();
    expect(screen.getByText("No design notes yet")).toBeTruthy();
  });

  it("a hub with no design/ folder says so, and it is not a fault", () => {
    // A hub an older Start copied out: the agent answers 200, exists false.
    listAnswer = { data: { folder: "design", exists: false, count: 0, items: [] } };
    mount();
    expect(screen.getByText("No design/ folder yet")).toBeTruthy();
    expect(screen.queryByText("Could not read the notes")).toBeNull();
    expect(screen.getByRole("button", { name: /New Design Note/i })).toBeTruthy();
  });

  it("the + writes a note through NewDesign, sending only what was given", async () => {
    mount();
    fireEvent.click(screen.getByRole("button", { name: "New Design Note" }));
    fireEvent.change(screen.getByPlaceholderText("Board ideas"), {
      target: { value: "  A new idea " },
    });
    await act(async () => {
      fireEvent.click(screen.getByRole("button", { name: "Submit" }));
    });
    expect(sent).toEqual([["-Title", "A new idea"]]);
    expect(screen.getByText("Created design note: design/x.md")).toBeTruthy();
  });

  it("a refusal stays in the dialog, in the verb's words", async () => {
    reply = {
      status: "error",
      output: "Error: design/board-ideas.md already exists. Not overwriting it.",
      error: "exit code 2",
    };
    mount();
    fireEvent.click(screen.getByRole("button", { name: "New Design Note" }));
    fireEvent.change(screen.getByPlaceholderText("Board ideas"), {
      target: { value: "Board ideas" },
    });
    await act(async () => {
      fireEvent.click(screen.getByRole("button", { name: "Submit" }));
    });
    expect(screen.getByRole("alert").textContent).toContain("already exists. Not overwriting it.");
  });
});

// The drawer's groups (design lifecycle L2): the agent answers the hub's
// four folders grouped by id, the same shape the Design tab reads, plus the
// Space a note names and which Space reads its thread on each row.
const doc = (folder: string, name: string, title: string, over: Record<string, unknown> = {}) => ({
  folder,
  name,
  path: `${folder}/${name}`,
  title,
  description: "",
  thread: "",
  thread_number: null,
  thread_repo: "",
  url: "",
  kind: folder.startsWith("spec") ? "spec" : "note",
  archived: folder.endsWith("/archive"),
  ...over,
});
const row = (over: Record<string, unknown>) => ({
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
const GROUPED = {
  folder: "design",
  specFolder: "spec",
  exists: true,
  count: 2,
  items: [NOTE, BARE],
  structure: { design: true, spec: true },
  notShown: [{ path: "design/unstamped.md", reason: "no id" }],
  designs: [
    row({
      id: "b0a4d1de-5c3e-4f7a-8b21-9d0e6f3a2c11",
      short: "b0a4d1de",
      state: "Spec",
      title: "Board ideas",
      description: "What the board could show next",
      thread: NOTE.thread,
      thread_number: 90,
      thread_repo: NOTE.thread_repo,
      space: "toolkit",
      thread_space: "toolkit",
      note: doc("design", "board-ideas.md", "Board ideas"),
      spec: doc("spec", "board-ideas.spec.md", "Board ideas (spec)"),
    }),
    row({
      id: "aaaaaaaa-0000-4000-8000-000000000002",
      short: "aaaaaaaa",
      state: "Design",
      title: "Offline specs",
      note: doc("design", "offline.md", "Offline specs"),
    }),
    row({
      id: "aaaaaaaa-0000-4000-8000-000000000003",
      short: "aaaaaaaa",
      state: "Archived",
      title: "A second room",
      closed: "2026-11-20",
      outcome: "dropped",
      note: doc("design/archive", "a-second-room.md", "A second room", {
        closed: "2026-11-20",
        outcome: "dropped",
      }),
    }),
    row({
      id: "aaaaaaaa-0000-4000-8000-000000000004",
      short: "aaaaaaaa",
      state: "Complete",
      title: "Built (spec)",
      closed: "2026-10-01",
      docs: "docs/x.md",
      spec: doc("spec/archive", "built.spec.md", "Built (spec)", {
        closed: "2026-10-01",
        docs: "docs/x.md",
      }),
    }),
  ],
};

describe("the Designs card's pager", () => {
  const notes = (n: number) =>
    Array.from({ length: n }, (_, i) => ({
      ...BARE,
      name: `n${i + 1}.md`,
      title: `Note ${i + 1}`,
    }));
  beforeEach(() => {
    window.localStorage.clear();
  });

  it("six designs draw a pager, page 2 shows the sixth, and the chip stays the total", () => {
    listAnswer = { data: { folder: "design", count: 6, items: notes(6) } };
    mount();
    expect(screen.getByText("Note 5")).toBeTruthy();
    expect(screen.queryByText("Note 6")).toBeNull();
    expect(screen.getByText("1 / 2")).toBeTruthy();
    expect(screen.getByLabelText("Design designs").textContent).toContain("6");
    fireEvent.click(screen.getByRole("button", { name: "Next page" }));
    expect(screen.getByText("Note 6")).toBeTruthy();
    expect(screen.queryByText("Note 1")).toBeNull();
    expect(screen.getByRole("button", { name: /New Design Note/ })).toBeTruthy();
  });

  it("five designs draw no pager", () => {
    listAnswer = { data: { folder: "design", count: 5, items: notes(5) } };
    mount();
    expect(screen.getByText("Note 5")).toBeTruthy();
    expect(screen.queryByRole("button", { name: "Next page" })).toBeNull();
  });

  it("the search pages what it leaves, and changing it returns to page 1", () => {
    listAnswer = { data: { folder: "design", count: 12, items: notes(12) } };
    mount();
    fireEvent.click(screen.getByRole("button", { name: "Next page" }));
    expect(screen.getByText("2 / 3")).toBeTruthy();
    fireEvent.change(screen.getByRole("searchbox", { name: "Search the hub's designs" }), {
      target: { value: "note 1" },
    });
    // Note 1, 10, 11, 12: one page.
    expect(screen.queryByRole("button", { name: "Next page" })).toBeNull();
    expect(screen.getByText("Note 1")).toBeTruthy();
    fireEvent.change(screen.getByRole("searchbox", { name: "Search the hub's designs" }), {
      target: { value: "" },
    });
    expect(screen.getByText("1 / 3")).toBeTruthy();
  });
});

describe("the Designs card's Docs line", () => {
  const complete = (space: string) => ({
    ...GROUPED,
    designs: [
      row({
        id: "aaaaaaaa-0000-4000-8000-000000000004",
        short: "aaaaaaaa",
        state: "Complete",
        title: "Built",
        closed: "2026-10-01",
        docs: "docs/x.md",
        space,
        spec: doc("spec/archive", "built.spec.md", "Built", { docs: "docs/x.md" }),
      }),
    ],
  });

  it("opens the document in the Docs tab when the design names the Space you are in", () => {
    listAnswer = { data: complete("toolkit") };
    mount();
    fireEvent.click(screen.getByRole("button", { name: "Show Complete" }));
    fireEvent.click(screen.getByText("docs/x.md"));
    expect(screen.getByTestId("where").textContent).toBe("/docs/docs/x.md");
  });

  it("stays a caption when the design names another Space, or none", () => {
    for (const space of ["wasteland", ""]) {
      listAnswer = { data: complete(space) };
      const { unmount } = mount();
      fireEvent.click(screen.getByRole("button", { name: "Show Complete" }));
      expect(screen.getByText("Docs: docs/x.md")).toBeTruthy();
      expect(screen.queryByRole("link", { name: "docs/x.md" })).toBeNull();
      unmount();
    }
  });
});

describe("the Designs card's groups (L2)", () => {
  beforeEach(() => {
    listAnswer = { data: GROUPED };
  });

  it("draws the same groups the Design tab draws, in road order, the archive collapsed", () => {
    mount();
    expect(screen.getAllByRole("region").map((r) => r.getAttribute("aria-label"))).toEqual([
      "Design designs",
      "Spec designs",
      "Complete designs",
      "Archived designs",
    ]);
    expect(screen.queryByText("A second room")).toBeNull();
    fireEvent.click(screen.getByRole("button", { name: "Show Archived" }));
    expect(screen.getByText("A second room")).toBeTruthy();
    // The row's outcome badge, beside the group's outcome chip of the same word (L2b).
    expect(screen.getAllByText("dropped").length).toBeGreaterThan(1);
    expect(screen.getByText("Closed 2026-11-20")).toBeTruthy();
  });

  it("a row keeps the Space chip and the thread, and wears its state and id", () => {
    mount();
    expect(screen.getByRole("button", { name: "Switch to Toolkit" })).toBeTruthy();
    expect(screen.getByText("#90")).toBeTruthy();
    expect(screen.getByText("b0a4d1de").getAttribute("title")).toBe(
      "b0a4d1de-5c3e-4f7a-8b21-9d0e6f3a2c11",
    );
    expect(screen.getAllByText("Spec").length).toBeGreaterThan(0);
    // The chip counts designs, not files.
    expect(screen.getByText("4")).toBeTruthy();
  });

  it("a note with its spec opens the note; the spec is in the menu", async () => {
    mount();
    fireEvent.click(screen.getAllByRole("button", { name: "Open the note" })[1]);
    expect(screen.getByTestId("where").textContent).toBe("/studio/design/design/board-ideas.md");
  });

  it("an archived note opens by its hub path", () => {
    mount();
    fireEvent.click(screen.getByRole("button", { name: "Show Archived" }));
    const archived = within(screen.getByRole("region", { name: "Archived designs" }));
    fireEvent.click(archived.getByRole("button", { name: "Open the note" }));
    expect(screen.getByTestId("where").textContent).toBe(
      "/studio/design/design/archive/a-second-room.md",
    );
  });

  it("files without an id are counted under the list, naming the hub's stamp", () => {
    mount();
    expect(screen.getByRole("status").textContent).toContain(
      "1 file not shown: no id. Give it one with StampDesign -Hub.",
    );
  });
});

// The moves a hub row offers (design lifecycle L3): by what the design has
// and where it is, run as MoveDesign -Hub through the bridge from a dialog that
// asks only for what the road needs.
describe("the Designs card's moves (L3)", () => {
  beforeEach(() => {
    listAnswer = { data: GROUPED };
    movedWith.length = 0;
    moveReply = { status: "success", output: "Moved: 'Board ideas' -> Spec.", error: null };
  });

  const menuOf = async (title: string) => {
    fireEvent.click(screen.getByRole("button", { name: `Actions for ${title}` }));
    return (await screen.findAllByRole("menuitem")).map((m) => m.textContent);
  };

  it("a note alone offers Graduate, Archive as shipped and Archive as dropped; a design with a live spec offers Complete and Archive as dropped; the archive nothing", async () => {
    mount();
    expect(await menuOf("Offline specs")).toEqual([
      "Graduate to a spec",
      "Archive as shipped",
      "Archive as dropped",
    ]);
    fireEvent.keyDown(document.activeElement ?? document.body, { key: "Escape" });
    expect(await menuOf("Board ideas")).toEqual([
      "Open the spec",
      "Complete",
      "Archive as dropped",
      "Open on GitHub",
    ]);
    fireEvent.keyDown(document.activeElement ?? document.body, { key: "Escape" });
    fireEvent.click(screen.getByRole("button", { name: "Show Complete" }));
    expect(screen.queryByRole("button", { name: "Actions for Built (spec)" })).toBeNull();
  });

  it("a graduation runs MoveDesign -Hub with the note's name and says the verb's line", async () => {
    mount();
    await menuOf("Offline specs");
    fireEvent.click(screen.getByRole("menuitem", { name: "Graduate to a spec" }));
    expect(screen.getByRole("dialog")).toBeTruthy();
    await act(async () => {
      fireEvent.click(screen.getByRole("button", { name: "Graduate to a spec" }));
    });
    expect(movedWith).toEqual([["offline.md", "-To", "Spec", "-Hub"]]);
    expect(screen.getByText("Moved: 'Board ideas' -> Spec.")).toBeTruthy();
    expect(screen.queryByRole("dialog")).toBeNull();
  });

  it("a drop asks for its reason first, and sends -Dropped with it", async () => {
    mount();
    await menuOf("Offline specs");
    fireEvent.click(screen.getByRole("menuitem", { name: "Archive as dropped" }));
    const go = screen.getByRole("button", { name: "Archive as dropped" });
    expect(go.hasAttribute("disabled")).toBe(true);
    fireEvent.change(screen.getByRole("textbox", { name: /Why it never made it/ }), {
      target: { value: " The Lounge already does this " },
    });
    await act(async () => {
      fireEvent.click(screen.getByRole("button", { name: "Archive as dropped" }));
    });
    expect(movedWith).toEqual([
      [
        "offline.md",
        "-To",
        "Archive",
        "-Hub",
        "-Dropped",
        "-Reason",
        "The Lounge already does this",
      ],
    ]);
  });

  it("a completion asks where the docs landed, and carries the design's Space", async () => {
    mount();
    await menuOf("Board ideas");
    fireEvent.click(screen.getByRole("menuitem", { name: "Complete" }));
    expect(screen.getByRole("button", { name: "Complete" }).hasAttribute("disabled")).toBe(true);
    fireEvent.change(screen.getByPlaceholderText("docs/board.md"), {
      target: { value: "docs/board.md" },
    });
    await act(async () => {
      fireEvent.click(screen.getByRole("button", { name: "Complete" }));
    });
    expect(movedWith).toEqual([
      ["board-ideas.md", "-To", "Complete", "-Hub", "-Space", "toolkit", "-Doc", "docs/board.md"],
    ]);
  });

  it("a refusal stays in the dialog, in the verb's words", async () => {
    moveReply = {
      status: "error",
      output: "Error: design/archive/offline.md already exists. Not overwriting it.",
      error: "exit code 2",
    };
    mount();
    await menuOf("Offline specs");
    fireEvent.click(screen.getByRole("menuitem", { name: "Archive as shipped" }));
    await act(async () => {
      fireEvent.click(screen.getByRole("button", { name: "Archive as shipped" }));
    });
    expect(screen.getByRole("alert").textContent).toContain("already exists. Not overwriting it.");
    expect(screen.getByRole("dialog")).toBeTruthy();
  });
});

// The drawer's search (L2b): the box narrows the groups by the Design
// tab's rule and opens the archive when it matches; Search inside runs the words
// over the hub's files on disk, on the button, and a hit opens by its hub path.
describe("the Designs card's search (L2b)", () => {
  beforeEach(() => {
    window.localStorage.clear();
    listAnswer = { data: GROUPED };
    hubSearchedFor.length = 0;
    hubSearchAnswer = {};
  });

  it("the box narrows the groups, opens the archive that matches, and the chip counts what is shown", () => {
    mount();
    expect(screen.queryByText("A second room")).toBeNull();
    fireEvent.change(screen.getByRole("searchbox", { name: "Search the hub's designs" }), {
      target: { value: "second" },
    });
    expect(screen.getByText("A second room")).toBeTruthy();
    expect(screen.queryByText("Board ideas")).toBeNull();
    // Only the group that matches is drawn, and it is open although it is the archive.
    expect(screen.getAllByRole("region").map((r) => r.getAttribute("aria-label"))).toEqual([
      "Archived designs",
    ]);
    fireEvent.change(screen.getByRole("searchbox", { name: "Search the hub's designs" }), {
      target: { value: "nothing here" },
    });
    // Beside the not-shown line, which stays: a search hides rows, never the count of what is not a design.
    expect(screen.getAllByRole("status").map((s) => s.textContent)).toContain(
      "No design matches the search.",
    );
  });

  it("a search by file name finds the design, by the Design tab's one rule", () => {
    mount();
    // "a-second-room" is the note's file name: in no title, description or id.
    fireEvent.change(screen.getByRole("searchbox", { name: "Search the hub's designs" }), {
      target: { value: "a-second-room" },
    });
    expect(screen.getByText("A second room")).toBeTruthy();
    expect(screen.queryByText("Board ideas")).toBeNull();
  });

  it("Search inside asks the hub route with the words, and a hit opens by its hub path", () => {
    hubSearchAnswer = {
      data: {
        supported: true,
        repo: "the hub",
        query: "nobody",
        available: true,
        reason: "",
        note: "Searched on disk.",
        hits: [
          {
            path: "design/archive/a-second-room.md",
            name: "a-second-room.md",
            line: "Waiting for nobody.",
            url: "",
            id: "aaaaaaaa-0000-4000-8000-000000000003",
            title: "A second room",
            state: "Archived",
            kind: "note",
            archived: true,
          },
        ],
      },
    };
    mount();
    expect(screen.queryByRole("button", { name: "Search inside" })).toBeNull();
    fireEvent.change(screen.getByRole("searchbox", { name: "Search the hub's designs" }), {
      target: { value: " nobody " },
    });
    fireEvent.click(screen.getByRole("button", { name: "Search inside" }));
    expect(hubSearchedFor).toEqual(["nobody"]);
    const section = within(screen.getByRole("region", { name: "Matches inside" }));
    expect(section.getByText("Waiting for nobody.")).toBeTruthy();
    expect(section.getByText("Searched on disk.")).toBeTruthy();
    fireEvent.click(section.getByRole("button", { name: "Open design/archive/a-second-room.md" }));
    expect(screen.getByTestId("where").textContent).toBe(
      "/studio/design/design/archive/a-second-room.md",
    );
  });
});

describe("the bridge argv", () => {
  it("title always; description and Space only when given", () => {
    expect(buildNewDesignParams({ title: " T " })).toEqual(["-Title", "T"]);
    expect(buildNewDesignParams({ title: "T", description: " d ", space: "toolkit" })).toEqual([
      "-Title",
      "T",
      "-Description",
      "d",
      "-Space",
      "toolkit",
    ]);
    expect(buildNewDesignParams({ title: "T", description: " ", space: "" })).toEqual([
      "-Title",
      "T",
    ]);
  });
});

const THREAD = {
  supported: true,
  number: 90,
  title: "Feature: the Studio",
  state: "open",
  body: "The contract is the spec.",
  author: "johnfrog76",
  created: "2026-09-29",
  closed: "",
  url: "https://github.com/johnfrog76/toolkit/issues/90",
  labels: ["design"],
  kind: "Feature",
  milestone: "",
  assignee: "",
  repo: "toolkit",
  pinned: false,
  comments: [{ author: "fable", when: "2026-10-01", body: "Reviewed: ship it." }],
  timeline: [],
  reason: null,
};

describe("a note's reading room", () => {
  beforeEach(() => {
    noteAnswer = {
      data: { ...NOTE, body: "---\ndescription: x\n---\n\n# Board ideas\n\nThe idea." },
    };
    threadAnswer = { data: THREAD };
    threadAsked = null;
  });

  it("is the document with its thread: the note, then the issue and its comments, in the one viewer", () => {
    mount("/studio/design/board-ideas.md");
    const text = screen.getByTestId("viewer").textContent ?? "";
    expect(text.indexOf("The idea.")).toBeLessThan(
      text.indexOf("## The thread: [#90 Feature: the Studio]"),
    );
    expect(text).toContain("Reviewed: ship it.");
    // Read through the Space whose repo holds it, not the one you are in.
    expect(threadAsked).toEqual({
      arg: { id: 90, repo: "toolkit", space: "toolkit" },
      skip: false,
    });
    expect(
      screen.getByRole("link", { name: "The thread, #90 on GitHub" }).getAttribute("href"),
    ).toBe(NOTE.thread);
  });

  it("a thread no declared Space can read is linked, not read", () => {
    noteAnswer = { data: { ...NOTE, thread_space: "", body: "# Board ideas\n\nThe idea." } };
    mount("/studio/design/board-ideas.md");
    expect(threadAsked?.skip).toBe(true);
    expect(screen.getByTestId("viewer").textContent).not.toContain("## The thread");
    expect(screen.getByRole("link", { name: "The thread, #90 on GitHub" })).toBeTruthy();
  });

  it("a thread that could not be read leaves the note alone", () => {
    threadAnswer = { data: { ...THREAD, reason: "o/r: gh did not answer" } };
    mount("/studio/design/board-ideas.md");
    expect(screen.getByTestId("viewer").textContent).not.toContain("## The thread");
  });

  it("is the note in the one viewer, its title and its Space above", () => {
    mount("/studio/design/board-ideas.md");
    expect(screen.getByRole("heading", { name: "Board ideas" })).toBeTruthy();
    expect(screen.getByText("for Toolkit")).toBeTruthy();
    expect(screen.getByTestId("viewer").textContent).toContain("The idea.");
  });

  it("a note that is gone says where it may have gone", () => {
    noteAnswer = { error: { status: 404 } };
    mount("/studio/design/gone.md");
    expect(screen.getByText("No note gone.md")).toBeTruthy();
  });
});

describe("a note's links, through the one resolver", () => {
  const base = noteLinkBase("design", "board-ideas.md");
  it("a sibling note opens its room; anything else is left as written", () => {
    expect(resolveLink("other-idea.md", base)).toEqual({
      kind: "room",
      to: "/studio/design/other-idea.md",
    });
    expect(resolveLink("other-idea.md#why", base)).toEqual({
      kind: "room",
      to: "/studio/design/other-idea.md#why",
    });
    expect(resolveLink("../growth/x.md", base)).toEqual({ kind: "out", href: "../growth/x.md" });
    expect(resolveLink("#the-idea", base)).toEqual({ kind: "anchor", id: "the-idea" });
    expect(resolveLink("https://example.com", base)).toEqual({
      kind: "out",
      href: "https://example.com",
    });
  });
});

describe("Promote", () => {
  const env = (tracker: string, here: string) =>
    ({
      tracker,
      config: {
        activeSpace: here,
        spaces: [
          { slug: "toolkit", name: "Toolkit", status: "active", tracker: "github" },
          { slug: "acme", name: "Acme", status: "active", tracker: "ado" },
        ],
      },
    }) as unknown as EnvStatus;

  it.each([
    [
      "a promoted note",
      { space: "", thread: "https://github.com/o/r/issues/1" },
      env("github", "toolkit"),
      "it already has its thread",
    ],
    [
      "an ADO Space (D-S9)",
      { space: "", thread: "" },
      env("ado", "acme"),
      "a design's thread is a GitHub issue -- switch to a GitHub Space first",
    ],
    [
      "a note for another Space",
      { space: "toolkit", thread: "" },
      env("github", "elsewhere"),
      "this note is for Toolkit -- switch to it first",
    ],
    ["a note for this Space", { space: "toolkit", thread: "" }, env("github", "toolkit"), null],
    [
      "a note for no Space, on a GitHub Space",
      { space: "", thread: "" },
      env("github", "toolkit"),
      null,
    ],
  ])("%s", (_why, note, e, want) => {
    expect(promoteBlocked(note, e)).toBe(want);
  });

  it("the argv is the note's name and nothing else", () => {
    expect(buildPromoteDesignParams({ name: "board-ideas.md" })).toEqual([
      "-FromDesign",
      "board-ideas.md",
    ]);
  });

  it("runs NewItem -FromDesign through the bridge, after saying what it will do", async () => {
    promotedWith.length = 0;
    promoteReply = {
      status: "success",
      output: "[+] Created: issue #41 -- Board ideas",
      error: null,
    };
    noteAnswer = {
      data: {
        ...BARE,
        name: "board-ideas.md",
        title: "Board ideas",
        space: "toolkit",
        body: "# Board ideas",
      },
    };
    mount("/studio/design/board-ideas.md");
    fireEvent.click(screen.getByRole("button", { name: "Promote" }));
    expect(screen.getByText(/labelled design/)).toBeTruthy();
    await act(async () => {
      fireEvent.click(screen.getAllByRole("button", { name: "Promote" }).slice(-1)[0]);
    });
    expect(promotedWith).toEqual([["-FromDesign", "board-ideas.md"]]);
    expect(screen.getByText("[+] Created: issue #41 -- Board ideas")).toBeTruthy();
  });

  it("a refusal stays in the dialog, in the verb's words", async () => {
    promotedWith.length = 0;
    promoteReply = {
      status: "error",
      output: "Error: design/board-ideas.md already has its thread",
      error: "exit code 2",
    };
    noteAnswer = {
      data: { ...BARE, name: "board-ideas.md", title: "Board ideas", body: "# Board ideas" },
    };
    mount("/studio/design/board-ideas.md");
    fireEvent.click(screen.getByRole("button", { name: "Promote" }));
    await act(async () => {
      fireEvent.click(screen.getAllByRole("button", { name: "Promote" }).slice(-1)[0]);
    });
    expect(screen.getByText(/already has its thread/)).toBeTruthy();
  });

  it("a promoted note has no Promote, only its thread", () => {
    noteAnswer = { data: { ...NOTE, body: "# Board ideas" } };
    mount("/studio/design/board-ideas.md");
    expect(screen.queryByRole("button", { name: "Promote" })).toBeNull();
  });
});
