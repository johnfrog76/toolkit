import { fireEvent, render, screen, within } from "@testing-library/react";
import { MemoryRouter } from "react-router";
import { DesignList } from "./DesignList";
import { DocsLanding } from "./DocsLanding";
import { FilterDrawer } from "./FilterDrawer";
import type { DrawerSection } from "./homeTabs";
import type { Design, DesignDoc, DocEntry } from "./api.ado";
import {
  DESIGN_KIND_KEY,
  DESIGN_TEXT_KEY,
  DOCS_FOLDER_KEY,
  DOCS_TEXT_KEY,
  designMatches,
  docFolders,
  docMatches,
  filterSummary,
  fuzzyMatch,
} from "./docFilters";

// Design filters by text over its titles and by kind; Docs by text over
// its paths and by folder, over the folded tree only. Pure rules first, then
// each tab's list, then the drawer's rows. react-markdown is ESM (the registry
// tests' rule), so the viewer is a stand-in.
jest.mock("../../shared/MarkdownViewer", () => ({
  MarkdownViewer: ({ content }: { content: string }) => <pre data-testid="viewer">{content}</pre>,
}));

const dd = (folder: string, name: string, title: string): DesignDoc => ({
  folder,
  name,
  path: `${folder}/${name}`,
  title,
  description: "",
  thread: "",
  thread_number: null,
  thread_repo: "",
  url: `https://github.com/o/r/blob/main/${folder}/${name}`,
});
// A DESIGN (L2): one id, a note and at most one spec; the kind is what it has.
const dz = (
  id: string,
  note: DesignDoc | null,
  spec: DesignDoc | null,
  state: string,
  description = "",
): Design => ({
  id,
  short: id.slice(0, 8),
  state,
  title: (note ?? spec)?.title ?? "",
  description,
  thread: "",
  thread_number: null,
  thread_repo: "",
  closed: "",
  outcome: "",
  mismatch: "",
  docs: "",
  note,
  spec,
  space: "",
  thread_space: "",
});
const DESIGNS = [
  dz(
    "11111111-0000-4000-8000-000000000001",
    dd("design", "board-note.md", "A note about the board"),
    null,
    "Design",
  ),
  dz(
    "22222222-0000-4000-8000-000000000002",
    dd("design", "lounge.md", "The Lounge"),
    null,
    "Design",
    "A room that asks nothing",
  ),
  dz(
    "33333333-0000-4000-8000-000000000003",
    dd("design", "studio.md", "The Studio"),
    dd("spec", "studio.spec.md", "The Studio (spec)"),
    "Spec",
  ),
];
const de = (path: string): DocEntry => ({
  path,
  name: path.split("/").pop() ?? path,
  folder: path.slice(0, path.lastIndexOf("/")),
  url: `https://github.com/o/r/blob/main/${path}`,
});
const DOCS = [
  de("docs/CLI.md"),
  de("docs/SCENARIOS.md"),
  de("docs/hub/cards.md"),
  de("docs/hub/growth.md"),
  de("docs/modules/ado.md"),
];

jest.mock("./api.ado", () => ({
  useGetStatusQuery: () => ({ data: { count: 0, prompts: [] } }),
  useLazySearchDesignQuery: () => [() => Promise.resolve(), { isFetching: false }],
  useGetDesignQuery: () => ({
    isLoading: false,
    isFetching: false,
    refetch: jest.fn(),
    data: {
      supported: true,
      repo: "o/r",
      items: [],
      designs: DESIGNS,
      notShown: [],
      structure: { design: true, spec: true },
    },
  }),
  useGetDocsQuery: () => ({
    isLoading: false,
    isFetching: false,
    refetch: jest.fn(),
    data: {
      supported: true,
      repo: "o/r",
      readme: { path: "README.md", name: "README.md", folder: "", url: "u" },
      items: DOCS,
    },
  }),
  useGetDocQuery: () => ({
    isLoading: false,
    isFetching: false,
    refetch: jest.fn(),
    data: {
      supported: true,
      repo: "o/r",
      path: "README.md",
      name: "README.md",
      folder: "",
      url: "u",
      title: "The README",
      body: "Hello README",
    },
  }),
}));

jest.mock("../../shell/api", () => ({
  useGetEnvQuery: () => ({ data: { cardTypes: [], config: { projects: [] } } }),
}));

beforeEach(() => window.localStorage.clear());

describe("the rules", () => {
  it("fuzzy is every word, any order, any case -- and nothing typed is everything", () => {
    expect(fuzzyMatch("A note about the Board", "BOARD note")).toBe(true);
    expect(fuzzyMatch("A note about the Board", "board lounge")).toBe(false);
    expect(fuzzyMatch("anything", "   ")).toBe(true);
  });

  it("Design: the kind is what the design has (a spec, or a note alone); the text is title, description, id and file name", () => {
    const [note, lounge, spec] = DESIGNS;
    expect(designMatches(note, "", "all")).toBe(true);
    expect(designMatches(spec, "", "design")).toBe(false);
    expect(designMatches(spec, "", "spec")).toBe(true);
    expect(designMatches(lounge, "lounge", "design")).toBe(true);
    expect(designMatches(lounge, "studio", "all")).toBe(false);
    // the description and the id are searched too
    expect(designMatches(lounge, "asks nothing", "all")).toBe(true);
    expect(designMatches(spec, "33333333", "all")).toBe(true);
  });

  it("a search by file name finds the design", () => {
    const [note, lounge, spec] = DESIGNS;
    // the note's name, which is in no title, description or id
    expect(designMatches(note, "board-note", "all")).toBe(true);
    expect(designMatches(note, "board-note.md", "all")).toBe(true);
    expect(designMatches(lounge, "board-note", "all")).toBe(false);
    // and the spec's, beside its note's
    expect(designMatches(spec, "studio.spec", "all")).toBe(true);
    expect(designMatches(spec, "studio.spec", "design")).toBe(false);
  });

  it("Docs: the text is the path, the folder is exact", () => {
    expect(docMatches(DOCS[2], "cards", "all")).toBe(true);
    expect(docMatches(DOCS[2], "hub card", "all")).toBe(true);
    expect(docMatches(DOCS[0], "", "docs/hub")).toBe(false);
    expect(docMatches(DOCS[2], "", "docs/hub")).toBe(true);
    // docs/ is the folder of its own files, not of docs/hub's
    expect(docMatches(DOCS[2], "", "docs")).toBe(false);
  });

  it("the folders are the ones the tree has, in order", () => {
    expect(docFolders(DOCS)).toEqual(["docs", "docs/hub", "docs/modules"]);
    expect(docFolders([])).toEqual([]);
  });

  it("the summary says what is set, and nothing when nothing is", () => {
    expect(filterSummary(undefined, " ")).toBe("");
    expect(filterSummary("spec", "studio")).toBe('spec · matching "studio"');
  });
});

describe("the Design tab", () => {
  const titles = () =>
    screen.queryAllByText(/note about the board|The Lounge|The Studio/).map((e) => e.textContent);
  const mount = () =>
    render(
      <MemoryRouter>
        <DesignList />
      </MemoryRouter>,
    );

  it("shows every document with nothing set", () => {
    mount();
    expect(titles()).toEqual(["A note about the board", "The Lounge", "The Studio"]);
  });

  it("narrows by kind", () => {
    window.localStorage.setItem(DESIGN_KIND_KEY, "spec");
    mount();
    expect(titles()).toEqual(["The Studio"]);
    // the one design left is in the Spec group, wearing its state
    expect(screen.getAllByText("Spec").length).toBeGreaterThan(0);
  });

  it("narrows by text over the titles, and says so in the header", () => {
    window.localStorage.setItem(DESIGN_TEXT_KEY, "the lounge");
    mount();
    expect(titles()).toEqual(["The Lounge"]);
    expect(screen.getByText('matching "the lounge"')).toBeTruthy();
  });

  it("keeps the card, and says so in a row, when nothing matches", () => {
    window.localStorage.setItem(DESIGN_KIND_KEY, "spec");
    window.localStorage.setItem(DESIGN_TEXT_KEY, "lounge");
    mount();
    expect(titles()).toEqual([]);
    expect(screen.getByText("Designs and specs")).toBeTruthy();
    expect(screen.getByText("No designs or specs match the filters.")).toBeTruthy();
  });
});

describe("the Docs tab", () => {
  const mount = () =>
    render(
      <MemoryRouter>
        <DocsLanding />
      </MemoryRouter>,
    );
  const linked = () => Array.from(document.querySelectorAll("details a")).map((a) => a.textContent);

  it("lists the whole tree with nothing set", () => {
    mount();
    expect(linked()).toEqual(DOCS.map((d) => d.path));
  });

  it("narrows the tree by folder, and counts it", () => {
    window.localStorage.setItem(DOCS_FOLDER_KEY, "docs/hub");
    mount();
    expect(linked()).toEqual(["docs/hub/cards.md", "docs/hub/growth.md"]);
    expect(screen.getByText("2 of 5")).toBeTruthy();
  });

  it("narrows the tree by text over the paths", () => {
    window.localStorage.setItem(DOCS_TEXT_KEY, "scen");
    mount();
    expect(linked()).toEqual(["docs/SCENARIOS.md"]);
  });

  it("leaves the README alone, whatever is set", () => {
    window.localStorage.setItem(DOCS_TEXT_KEY, "zzz");
    mount();
    expect(linked()).toEqual([]);
    expect(screen.getByTestId("viewer").textContent).toBe("Hello README");
    expect(screen.getByText("No documents match the filters.")).toBeTruthy();
    expect(screen.getByText("0 of 5")).toBeTruthy();
  });
});

describe("the drawer's rows", () => {
  function drawer(sections: DrawerSection[]) {
    render(
      <FilterDrawer
        sections={sections}
        value=""
        onChange={() => {}}
        activeRepo={null}
        onRepoChange={() => {}}
        stateFilter="All"
        onStateChange={() => {}}
        stateOptions={["All"]}
        typeFilter="All"
        onTypeChange={() => {}}
      />,
    );
  }

  it("Design: a search over titles and the kind row, set through the same chips", () => {
    drawer(["search", "kind"]);
    expect(screen.getByPlaceholderText("Title")).toBeTruthy();
    const row = screen.getByRole("radiogroup", { name: "Design kind" });
    expect(
      within(row)
        .getAllByRole("radio")
        .map((r) => r.textContent),
    ).toEqual(["any kind", "design note", "spec"]);
    fireEvent.click(within(row).getByRole("radio", { name: "spec" }));
    expect(window.localStorage.getItem(DESIGN_KIND_KEY)).toBe("spec");
    fireEvent.click(within(row).getByRole("radio", { name: "spec" }));
    expect(window.localStorage.getItem(DESIGN_KIND_KEY)).toBe("all");
    fireEvent.change(screen.getByPlaceholderText("Title"), { target: { value: "lounge" } });
    expect(window.localStorage.getItem(DESIGN_TEXT_KEY)).toBe("lounge");
  });

  it("Docs: a search over titles and paths and a row of the folders the tree has", () => {
    drawer(["search", "folder"]);
    expect(screen.getByPlaceholderText("Title or path")).toBeTruthy();
    const row = screen.getByRole("radiogroup", { name: "Docs folder" });
    expect(
      within(row)
        .getAllByRole("radio")
        .map((r) => r.textContent),
    ).toEqual(["all folders", "docs/", "docs/hub/", "docs/modules/"]);
    fireEvent.click(within(row).getByRole("radio", { name: "docs/modules/" }));
    expect(window.localStorage.getItem(DOCS_FOLDER_KEY)).toBe("docs/modules");
  });
});
