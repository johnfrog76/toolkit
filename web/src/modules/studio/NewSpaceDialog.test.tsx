import { act, cleanup, fireEvent, render, screen, within } from "@testing-library/react";
import { MemoryRouter } from "react-router";
import { FoyerCard } from "./FoyerCard";

// The + on the Spaces card: the New Space dialog. The picker is
// GET /api/spaces/candidates (NewSpace -Discover through the bridge), the write
// is POST /api/cmd/NewSpace -- both mocked here at the hooks, the way
// FoyerCard.test.tsx and DesignsCard.test.tsx mock theirs. The verb's own
// behaviour is Tests/test_new_space.py and tkTestToolkit -NewSpace.

type Space = { slug: string; name: string; status: string; tracker: string; org: string };
let spaces: Space[] = [];
jest.mock("../../shell/api", () => ({
  useGetEnvQuery: () => ({ data: { config: { activeSpace: "demo", spaces } }, isLoading: false }),
  useSwitchModeMutation: () => [
    () => ({ unwrap: () => Promise.resolve({}) }),
    { isLoading: false },
  ],
  // The rows' visibility is FoyerCard.test.tsx's subject; answered, so
  // the card draws.
  useGetSpaceVisibilityQuery: () => ({
    data: { supported: true, visibility: "unknown", repos: [] },
  }),
  useRefreshSpaceVisibilityMutation: () => [jest.fn(), { isLoading: false }],
}));

let candidates: { data?: unknown; error?: unknown; isLoading?: boolean; isFetching?: boolean } = {};
let candidatesAsked: { skip?: boolean; arg?: unknown }[] = [];
// The Add owner/name row's own read: GET /api/spaces/candidates?repo= (the verb's
// -Discover -Repo), asked once the search rests on a full owner/name.
let typed: { currentData?: unknown; error?: unknown; isLoading?: boolean; isFetching?: boolean } =
  {};
let typedAsked: { skip?: boolean; arg?: unknown }[] = [];
const sent: string[][] = [];
let reply: { status: string; output: string | null; error: string | null } = {
  status: "success",
  output: "",
  error: null,
};
// What a successful NewSpace does to /env: the Space is declared, so the next
// read of the Spaces has its row. The mutation's tag invalidation is that read.
let onSuccess: (() => void) | null = null;
jest.mock("./api.studio", () => ({
  // Answered, so the card draws (it holds its loading state, and its
  // foot, until every row's reads settle).
  // Every GitHub Space's slot in the one ledger read: not connected.
  useGetStudioLedgerQuery: () => ({
    data: {
      spaces: new Proxy(
        {},
        {
          get: () => ({
            report: { supported: false },
            deploys: { supported: false, runs: [] },
            visibility: { supported: true, visibility: "unknown", repos: [] },
          }),
        },
      ),
    },
  }),
  useRefreshStudioLedgerMutation: () => [jest.fn(), { isLoading: false }],
  useGetSpaceStatusQuery: () => ({ data: { count: 0, prompts: [] } }),
  useGetSpaceCandidatesQuery: (arg: unknown, opts: { skip?: boolean }) => {
    candidatesAsked.push({ ...opts, arg });
    return opts?.skip ? {} : { isLoading: false, isFetching: false, ...candidates };
  },
  useGetTypedSpaceCandidateQuery: (arg: unknown, opts: { skip?: boolean }) => {
    typedAsked.push({ ...opts, arg });
    return opts?.skip ? {} : { isLoading: false, isFetching: false, ...typed };
  },
  useRunNewSpaceMutation: () => [
    ({ params }: { params: string[] }) => {
      sent.push(params);
      if (reply.status === "success" && onSuccess) onSuccess();
      return {
        unwrap: () =>
          Promise.resolve({
            command: "NewSpace",
            exit_code: reply.status === "success" ? 0 : 2,
            duration: 1,
            ...reply,
          }),
      };
    },
    { isLoading: false },
  ],
}));
jest.mock("../ado/api.ado", () => ({
  useGetStatusQuery: () => ({ data: { count: 0, prompts: [] } }),
}));
// Retire and Remove share the card; their confirm is not opened here.
jest.mock("./SpaceLifecycleDialog", () => ({ SpaceLifecycleDialog: () => null }));

const DEMO: Space = { slug: "demo", name: "Demo", status: "local", tracker: "none", org: "" };
const TOOLKIT: Space = {
  slug: "toolkit",
  name: "Toolkit",
  status: "active",
  tracker: "github",
  org: "https://github.com/johnfrog76/toolkit",
};

const LISTED = {
  available: true,
  reason: "",
  hint: "",
  account: "tester",
  repos: [
    {
      repo: "johnfrog76/toolkit",
      name: "toolkit",
      owner: "johnfrog76",
      visibility: "PRIVATE",
      description: "",
      proposedSlug: "toolkit",
      proposedName: "Toolkit",
      space: "toolkit",
      spaceName: "Toolkit",
      command: "tkNewSpace -Repo johnfrog76/toolkit",
    },
    {
      repo: "tester/juggling-engine",
      name: "juggling-engine",
      owner: "tester",
      visibility: "PUBLIC",
      description: "Balls in the air",
      proposedSlug: "juggling-engine",
      proposedName: "Juggling Engine",
      space: "",
      spaceName: "",
      command: "tkNewSpace -Repo tester/juggling-engine",
    },
    {
      repo: "tester/Notes_App",
      name: "Notes_App",
      owner: "tester",
      visibility: "PRIVATE",
      description: "x",
      proposedSlug: "notes-app",
      proposedName: "Notes App",
      space: "",
      spaceName: "",
      command: "tkNewSpace -Repo tester/Notes_App",
    },
  ],
};

function mount() {
  return render(
    <MemoryRouter initialEntries={["/studio"]}>
      <FoyerCard />
    </MemoryRouter>,
  );
}

function openDialog() {
  fireEvent.click(screen.getByRole("button", { name: "New Space" }));
  return screen.getByRole("dialog");
}

const field = (dialog: HTMLElement, label: string) =>
  within(dialog).getByRole("textbox", { name: new RegExp(`^${label}`) }) as HTMLInputElement;
const addButton = (dialog: HTMLElement) => within(dialog).getByRole("button", { name: "Add" });

describe("the + on the Spaces card", () => {
  beforeEach(() => {
    spaces = [DEMO, TOOLKIT];
    candidates = { data: LISTED };
    candidatesAsked = [];
    typed = {};
    typedAsked = [];
    sent.length = 0;
    reply = { status: "success", output: "", error: null };
    onSuccess = null;
  });

  it("is the card's foot +, named for the dialog it opens, and asks for nothing until it is pressed", () => {
    mount();
    expect(screen.getByRole("button", { name: "New Space" })).toBeTruthy();
    expect(screen.queryByRole("dialog")).toBeNull();
    expect(candidatesAsked.every((o) => o.skip)).toBe(true);
    const dialog = openDialog();
    expect(within(dialog).getByText("New Space")).toBeTruthy();
    expect(candidatesAsked.some((o) => !o.skip)).toBe(true);
  });

  it("lists your repositories with owner and Public/Private, the ones already Spaces disabled and marked", () => {
    mount();
    const dialog = openDialog();
    const jug = within(dialog).getByRole("radio", { name: /juggling-engine/ });
    expect((jug as HTMLInputElement).disabled).toBe(false);
    const held = within(dialog).getByRole("radio", { name: /toolkit/ });
    expect((held as HTMLInputElement).disabled).toBe(true);
    expect(within(dialog).getByText("already a Space: Toolkit")).toBeTruthy();
    expect(within(dialog).getByText("Public")).toBeTruthy();
    expect(within(dialog).getAllByText("Private").length).toBe(2);
    expect(within(dialog).getAllByText("tester").length).toBeGreaterThan(0);
  });

  it("marks a GitHub-archived repository with an Archived chip and lists it last", () => {
    const archived = {
      repo: "aaa/old-thing",
      name: "old-thing",
      owner: "aaa",
      visibility: "PRIVATE",
      isArchived: true,
      description: "",
      proposedSlug: "old-thing",
      proposedName: "Old Thing",
      space: "",
      spaceName: "",
      command: "tkNewSpace -Repo aaa/old-thing",
    };
    candidates = { data: { ...LISTED, repos: [archived, ...LISTED.repos] } };
    mount();
    const dialog = openDialog();
    expect(within(dialog).getAllByText("Archived").length).toBe(1);
    const names = within(within(dialog).getByRole("radiogroup", { name: "Your repositories" }))
      .getAllByRole("radio")
      .map((r) => r.parentElement?.textContent ?? "");
    expect(names[names.length - 1]).toMatch(/old-thing/);
    expect(names[0]).toMatch(/toolkit/);
  });

  it("searches the list", () => {
    mount();
    const dialog = openDialog();
    fireEvent.change(within(dialog).getByRole("searchbox", { name: "Search your repositories" }), {
      target: { value: "notes" },
    });
    expect(within(dialog).queryByRole("radio", { name: /juggling-engine/ })).toBeNull();
    expect(within(dialog).getByRole("radio", { name: /Notes_App/ })).toBeTruthy();
  });

  it("shows the proposed name and slug once a repository is chosen, editable, and adds exactly that", async () => {
    mount();
    const dialog = openDialog();
    expect(field(dialog, "Name").disabled).toBe(true);
    expect((addButton(dialog) as HTMLButtonElement).disabled).toBe(true);
    fireEvent.click(within(dialog).getByRole("radio", { name: /juggling-engine/ }));
    expect(field(dialog, "Name").value).toBe("Juggling Engine");
    expect(field(dialog, "Slug").value).toBe("juggling-engine");
    fireEvent.change(field(dialog, "Name"), { target: { value: "Juggling" } });
    fireEvent.change(field(dialog, "Slug"), { target: { value: "jug" } });
    await act(async () => {
      fireEvent.click(addButton(dialog));
    });
    expect(sent).toEqual([
      ["-Slug", "jug", "-Name", "Juggling", "-Repo", "tester/juggling-engine"],
    ]);
  });

  it("on success closes, says so, and the new row is in the list without a reload", async () => {
    const { rerender } = mount();
    onSuccess = () => {
      spaces = [
        ...spaces,
        {
          slug: "juggling-engine",
          name: "Juggling Engine",
          status: "active",
          tracker: "github",
          org: "https://github.com/tester/juggling-engine",
        },
      ];
    };
    const dialog = openDialog();
    fireEvent.click(within(dialog).getByRole("radio", { name: /juggling-engine/ }));
    await act(async () => {
      fireEvent.click(addButton(dialog));
    });
    rerender(
      <MemoryRouter initialEntries={["/studio"]}>
        <FoyerCard />
      </MemoryRouter>,
    );
    expect(screen.queryByRole("dialog")).toBeNull();
    expect(screen.getByText(/Added Juggling Engine\./)).toBeTruthy();
    expect(screen.getByRole("button", { name: "Go into Juggling Engine" })).toBeTruthy();
  });

  it("shows a refusal in the verb's own words, in the dialog, and keeps it open", async () => {
    reply = {
      status: "error",
      output: null,
      error: "Error: tester/juggling-engine is already a Space: Juggling Engine (juggling-engine).",
    };
    mount();
    const dialog = openDialog();
    fireEvent.click(within(dialog).getByRole("radio", { name: /juggling-engine/ }));
    await act(async () => {
      fireEvent.click(addButton(dialog));
    });
    expect(screen.getByRole("dialog")).toBeTruthy();
    expect(within(screen.getByRole("dialog")).getByRole("alert").textContent).toMatch(
      /already a Space: Juggling Engine/,
    );
  });

  it("when gh cannot list, offers a typed owner/name with the sentence why -- never a dead end", async () => {
    candidates = {
      data: {
        available: false,
        reason: "Your repositories cannot be listed: gh, the GitHub CLI, is not installed.",
        hint: "",
        account: "",
        repos: [],
      },
    };
    mount();
    const dialog = openDialog();
    expect(
      within(dialog).getByText(
        /gh, the GitHub CLI, is not installed\. Type the repository instead\./,
      ),
    ).toBeTruthy();
    expect(within(dialog).queryByRole("searchbox")).toBeNull();
    fireEvent.change(field(dialog, "Repository"), {
      target: { value: "https://github.com/tester/Notes_App" },
    });
    expect(field(dialog, "Name").value).toBe("Notes App");
    expect(field(dialog, "Slug").value).toBe("notes-app");
    await act(async () => {
      fireEvent.click(addButton(dialog));
    });
    expect(sent).toEqual([
      ["-Slug", "notes-app", "-Name", "Notes App", "-Repo", "tester/Notes_App"],
    ]);
  });

  it("the typed field is offered too when the agent does not answer", () => {
    candidates = { error: { status: 500 } };
    mount();
    const dialog = openDialog();
    expect(within(dialog).getByText(/The agent did not answer/)).toBeTruthy();
    expect(field(dialog, "Repository")).toBeTruthy();
  });

  it("adds a Space of your own cards, with no repository: the slug follows the name until you change it", async () => {
    mount();
    const dialog = openDialog();
    fireEvent.click(within(dialog).getByRole("radio", { name: "My own cards, no tracker" }));
    fireEvent.change(field(dialog, "Name"), { target: { value: "Side notes" } });
    expect(field(dialog, "Slug").value).toBe("side-notes");
    await act(async () => {
      fireEvent.click(addButton(dialog));
    });
    expect(sent).toEqual([["-Slug", "side-notes", "-Name", "Side notes"]]);
  });

  it("does not offer Add for a slug the verb would refuse, and says why", () => {
    mount();
    const dialog = openDialog();
    fireEvent.click(within(dialog).getByRole("radio", { name: "My own cards, no tracker" }));
    fireEvent.change(field(dialog, "Name"), { target: { value: "Demo" } });
    expect(within(dialog).getByText("There is already a Space 'demo': Demo.")).toBeTruthy();
    expect((addButton(dialog) as HTMLButtonElement).disabled).toBe(true);
    fireEvent.change(field(dialog, "Slug"), { target: { value: "Bad_Slug" } });
    expect(
      within(dialog).getByText("Lowercase letters, digits and dashes, starting with a letter."),
    ).toBeTruthy();
    expect((addButton(dialog) as HTMLButtonElement).disabled).toBe(true);
  });

  // -- a repository you do not own -------------------------------------------------
  const OWNERS = [
    { value: "tester", label: "tester (yours)", kind: "user" },
    { value: "acme", label: "acme", kind: "organization" },
    { value: "collaborator", label: "Collaborator", kind: "collaborator" },
  ];

  it("offers the verb's owners over the list, and a choice asks for that owner's repositories", () => {
    candidates = { data: { ...LISTED, owner: "tester", owners: OWNERS } };
    mount();
    const dialog = openDialog();
    const select = within(dialog).getByRole("combobox", { name: "Owner" }) as HTMLSelectElement;
    expect(Array.from(select.options).map((o) => o.textContent)).toEqual([
      "tester (yours)",
      "acme",
      "Collaborator",
    ]);
    expect(select.value).toBe("tester");
    expect(candidatesAsked.filter((o) => !o.skip).every((o) => o.arg === "")).toBe(true);
    fireEvent.change(select, { target: { value: "acme" } });
    expect(candidatesAsked[candidatesAsked.length - 1].arg).toBe("acme");
    fireEvent.change(within(dialog).getByRole("combobox", { name: "Owner" }), {
      target: { value: "collaborator" },
    });
    expect(candidatesAsked[candidatesAsked.length - 1].arg).toBe("collaborator");
    // Your own login is your own list again -- the first read, not a second one.
    fireEvent.change(within(dialog).getByRole("combobox", { name: "Owner" }), {
      target: { value: "tester" },
    });
    expect(candidatesAsked[candidatesAsked.length - 1].arg).toBe("");
  });

  it("keeps the owner selector when an owner's list cannot be read, over the typed field", () => {
    candidates = {
      data: {
        available: false,
        reason: "The repositories of 'nobody' cannot be listed: gh answered 'no'.",
        hint: "",
        account: "",
        owner: "nobody",
        owners: OWNERS,
        repos: [],
      },
    };
    mount();
    const dialog = openDialog();
    expect(within(dialog).getByRole("combobox", { name: "Owner" })).toBeTruthy();
    expect(within(dialog).getByText(/'nobody' cannot be listed/)).toBeTruthy();
    expect(field(dialog, "Repository")).toBeTruthy();
  });

  it("draws no owner selector for an agent that names no owners", () => {
    mount();
    const dialog = openDialog();
    expect(within(dialog).queryByRole("combobox", { name: "Owner" })).toBeNull();
  });

  it("marks a repository you can only read, Public said, and it can still be added", async () => {
    const theirs = {
      repo: "acme/site",
      name: "site",
      owner: "acme",
      visibility: "PUBLIC",
      isArchived: false,
      viewerPermission: "READ",
      readOnly: true,
      description: "",
      proposedSlug: "site",
      proposedName: "Site",
      space: "",
      spaceName: "",
      command: "tkNewSpace -Repo acme/site",
    };
    const ours = {
      ...theirs,
      repo: "acme/api",
      name: "api",
      visibility: "PRIVATE",
      viewerPermission: "WRITE",
      readOnly: false,
      proposedSlug: "api",
      proposedName: "Api",
    };
    candidates = { data: { ...LISTED, owner: "acme", owners: OWNERS, repos: [theirs, ours] } };
    mount();
    const dialog = openDialog();
    expect(within(dialog).getAllByText("Read-only").length).toBe(1);
    const site = within(dialog).getByRole("radio", { name: /site/ });
    expect(site.parentElement?.textContent).toMatch(/Public.*Read-only/);
    expect((site as HTMLInputElement).disabled).toBe(false);
    fireEvent.click(site);
    await act(async () => {
      fireEvent.click(addButton(dialog));
    });
    expect(sent).toEqual([["-Slug", "site", "-Name", "Site", "-Repo", "acme/site"]]);
  });

  it("a search that is a full owner/name not in the list offers one row, Add owner/name, chosen like any other", async () => {
    mount();
    const dialog = openDialog();
    fireEvent.change(within(dialog).getByRole("searchbox", { name: "Search your repositories" }), {
      target: { value: "https://github.com/someone/up-stream.git" },
    });
    const add = within(dialog).getByRole("radio", { name: /Add someone\/up-stream/ });
    expect(
      within(dialog)
        .getAllByRole("radio")
        .filter((r) => r.closest('[aria-label="Your repositories"]')).length,
    ).toBe(1);
    fireEvent.click(add);
    expect(field(dialog, "Name").value).toBe("Up Stream");
    expect(field(dialog, "Slug").value).toBe("up-stream");
    await act(async () => {
      fireEvent.click(addButton(dialog));
    });
    expect(sent).toEqual([
      ["-Slug", "up-stream", "-Name", "Up Stream", "-Repo", "someone/up-stream"],
    ]);
  });

  it("a full owner/name that IS listed shows that row, not an Add row", () => {
    mount();
    const dialog = openDialog();
    fireEvent.change(within(dialog).getByRole("searchbox", { name: "Search your repositories" }), {
      target: { value: "https://github.com/tester/juggling-engine" },
    });
    expect(within(dialog).getByRole("radio", { name: /juggling-engine/ })).toBeTruthy();
    expect(within(dialog).queryByRole("radio", { name: /^Add / })).toBeNull();
  });

  describe("the Add owner/name row reads the typed repository before it is added", () => {
    const UPSTREAM = {
      repo: "someone/up-stream",
      name: "up-stream",
      owner: "someone",
      visibility: "PUBLIC",
      isArchived: false,
      viewerPermission: "READ",
      readOnly: true,
      description: "",
      proposedSlug: "up-stream",
      proposedName: "Up Stream",
      space: "",
      spaceName: "",
      command: "tkNewSpace -Repo someone/up-stream",
      note: "",
    };
    const answered = (row: object) => ({
      currentData: { available: true, reason: "", hint: "", account: "tester", repos: [row] },
    });
    const typeInto = (dialog: HTMLElement, value: string) =>
      fireEvent.change(
        within(dialog).getByRole("searchbox", { name: "Search your repositories" }),
        {
          target: { value },
        },
      );
    const rest = () =>
      act(() => {
        jest.advanceTimersByTime(1000);
      });
    const addRow = (dialog: HTMLElement) =>
      within(dialog).getByRole("radio", { name: /^Add someone\/up-stream/ });

    beforeEach(() => jest.useFakeTimers());
    // Unmount while the fake clock is still the one Fluent's focus manager started on.
    afterEach(() => {
      cleanup();
      jest.useRealTimers();
    });

    it("asks once the search rests on a full owner/name, not once a letter, and says the visibility", () => {
      typed = answered(UPSTREAM);
      mount();
      const dialog = openDialog();
      for (const v of ["someone/u", "someone/up", "someone/up-st", "someone/up-stream"]) {
        typeInto(dialog, v);
        act(() => {
          jest.advanceTimersByTime(100);
        });
      }
      expect(typedAsked.filter((o) => !o.skip)).toEqual([]);
      expect(addRow(dialog).parentElement?.textContent).toMatch(/reading its visibility/);
      rest();
      expect(typedAsked.filter((o) => !o.skip).map((o) => o.arg)).toEqual(
        expect.arrayContaining(["someone/up-stream"]),
      );
      expect(new Set(typedAsked.filter((o) => !o.skip).map((o) => o.arg))).toEqual(
        new Set(["someone/up-stream"]),
      );
      const label = addRow(dialog).parentElement?.textContent ?? "";
      expect(label).toMatch(/Public.*Read-only/);
      expect(label).not.toMatch(/checked when it is added/);
    });

    it("a repository gh cannot see says Visibility unknown and the verb's note, and can still be added", async () => {
      typed = answered({
        ...UPSTREAM,
        visibility: "UNKNOWN",
        readOnly: false,
        viewerPermission: "",
        note: "not visible to this login: gh answered 'GraphQL: Could not resolve'",
      });
      mount();
      const dialog = openDialog();
      typeInto(dialog, "someone/up-stream");
      rest();
      const label = addRow(dialog).parentElement?.textContent ?? "";
      expect(label).toMatch(/Visibility unknown/);
      expect(label).toMatch(/not visible to this login: gh answered .* it can still be added/);
      expect((addRow(dialog) as HTMLInputElement).disabled).toBe(false);
      fireEvent.click(addRow(dialog));
      await act(async () => {
        fireEvent.click(addButton(dialog));
      });
      expect(sent).toEqual([
        ["-Slug", "up-stream", "-Name", "Up Stream", "-Repo", "someone/up-stream"],
      ]);
    });

    it("a typed repository that is already a Space is marked and not offered", () => {
      typed = answered({ ...UPSTREAM, space: "upstream", spaceName: "Upstream" });
      mount();
      const dialog = openDialog();
      typeInto(dialog, "someone/up-stream");
      rest();
      expect((addRow(dialog) as HTMLInputElement).disabled).toBe(true);
      expect(addRow(dialog).parentElement?.textContent).toMatch(/already a Space: Upstream/);
    });

    it("a read that cannot answer keeps the row addable and says the check comes at Add", () => {
      typed = {
        currentData: {
          available: false,
          reason: "gh is not signed in.",
          hint: "",
          account: "",
          repos: [],
        },
      };
      mount();
      const dialog = openDialog();
      typeInto(dialog, "someone/up-stream");
      rest();
      expect(addRow(dialog).parentElement?.textContent).toMatch(/checked when it is added/);
      expect((addRow(dialog) as HTMLInputElement).disabled).toBe(false);
    });
  });

  it("says when an owner's list stopped at the ceiling, and how to reach one past it", () => {
    candidates = { data: { ...LISTED, ceiling: 1000, more: true } };
    mount();
    let dialog = openDialog();
    expect(within(dialog).getByRole("note").textContent).toMatch(
      /The first 1000 are listed\. For one past them, type its owner\/name/,
    );
    fireEvent.click(within(dialog).getByRole("button", { name: "Cancel" }));
    candidates = { data: { ...LISTED, ceiling: 1000, more: false } };
    dialog = openDialog();
    expect(within(dialog).queryByText(/The first 1000 are listed/)).toBeNull();
  });

  it("keeps the repository area's box whatever it holds, so nothing below it moves", () => {
    mount();
    const dialog = openDialog();
    const picker = within(dialog).getByTestId("new-space-picker");
    fireEvent.click(within(dialog).getByRole("radio", { name: "My own cards, no tracker" }));
    expect(within(dialog).getByTestId("new-space-picker")).toBe(picker);
  });
});
