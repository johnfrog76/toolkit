import fs from "node:fs";
import path from "node:path";
import { Fragment } from "react";
import type { ReactElement } from "react";
import { render } from "@testing-library/react";
import { DocumentRegular } from "@fluentui/react-icons";
import { ModuleCardGrid, PageGrid, PanelRow, ShellProvider } from "./cards";
import type { ShellValue } from "./cards";
import { pageRowGap, panelGap } from "./layoutTokens";
import { ListPanel } from "./kinds/ListPanel";
import { rulesOf } from "./kinds/panelShapeAssert";
import { expectPageRowsShape, isPairRow, panelRowsOf, tokenPx } from "./pageRowsAssert";
import { ROW } from "../shared/CardActions";
import { StudioPage } from "../modules/studio/StudioPage";
import { GrowthPage } from "../modules/growth/GrowthPage";

/**
 * The page's rows, held as structure.
 *
 * A page's panels sit in real row elements: the page is a column of rows, a
 * row is a grid of up to two panels. Spacing is the wrapper's at both levels --
 * the page's gap between rows, a row's gap between its panels -- and nothing
 * has a margin: not a panel, a card item, a row or a list.
 *
 * Each page's panels are stand-ins here: the subject is where a panel is put,
 * not what it draws. One case draws real list panels for the margins inside.
 */

// A function declaration, so it is there when jest hoists the mocks above it.
function mockStub(name: string) {
  const Stub = () => <section data-stub-panel={name}>{name}</section>;
  return Stub;
}

jest.mock("../modules/studio/FoyerCard", () => ({ FoyerCard: mockStub("Spaces") }));
jest.mock("../modules/studio/DesignsCard", () => ({ DesignsCard: mockStub("Hub Designs") }));
jest.mock("../modules/studio/PromptsCard", () => ({ PromptsCard: mockStub("Prompts") }));
jest.mock("../modules/growth/ReviewArchive", () => ({ ReviewArchive: mockStub("Reviews") }));
jest.mock("../modules/growth/Goals", () => ({ Goals: mockStub("Goals") }));
jest.mock("../modules/growth/QuarterLine", () => ({ QuarterLine: () => null }));

function Panel({ name }: { name: string }) {
  return <section data-stub-panel={name}>{name}</section>;
}

/** A card that is mounted and then draws nothing. */
function Nothing() {
  return null;
}

const stubs = (root: ParentNode) =>
  Array.from(root.querySelectorAll<HTMLElement>("[data-stub-panel]"));
const names = (els: Element[]) => els.map((el) => el.getAttribute("data-stub-panel"));
const layout = (root: ParentNode) =>
  panelRowsOf(root).map((row) => names(Array.from(row.children)));

function shell(over: Partial<ShellValue>): ShellValue {
  return {
    cards: { home: [], system: [] },
    homeTabs: [],
    slot: () => [],
    openSettings: () => undefined,
    pager: { page: 0, totalPages: 1, onPageChange: () => undefined },
    filters: {
      filterValue: "",
      setFilterValue: () => undefined,
      activeRepo: null,
      setActiveRepo: () => undefined,
      stateFilter: "All",
      setStateFilter: () => undefined,
      stateOptions: ["All"],
      typeFilter: "All",
      setTypeFilter: () => undefined,
      linkFilter: "All",
      setLinkFilter: () => undefined,
    },
    ...over,
  };
}

describe("the gaps are named tokens, side by side", () => {
  it("the page's and a row's gap are Fluent spacing tokens, each a multiple of 4 px", () => {
    for (const gap of [pageRowGap, panelGap]) {
      expect(gap).toMatch(/^var\(--spacing(Vertical|Horizontal)\w+\)$/);
      expect(tokenPx(gap) % 4).toBe(0);
      expect(tokenPx(gap)).toBeGreaterThan(0);
    }
    // What the one grid used before it had rows: nothing moves.
    expect(tokenPx(pageRowGap)).toBe(16);
    expect(tokenPx(panelGap)).toBe(16);
  });

  it("layoutTokens.ts names them beside the list's and the filter rows' gaps", () => {
    const text = fs.readFileSync(path.join(__dirname, "layoutTokens.ts"), "utf8");
    for (const name of ["pageRowGap", "panelGap", "cardListGap", "filterRowGap"])
      expect(text).toContain(`export const ${name}`);
  });

  it("cards.tsx has no margin and no length of its own: every space is a wrapper's gap", () => {
    const text = fs.readFileSync(path.join(__dirname, "cards.tsx"), "utf8");
    const code = text.replace(/\/\*[\s\S]*?\*\//g, "").replace(/\/\/.*$/gm, "");
    expect(code).not.toMatch(/margin/i);
    expect(code).not.toMatch(/["'`]\d+px/);
    expect(code).toContain("rowGap: pageRowGap");
    // Two columns only above the one breakpoint the panels' heights read too.
    expect(code).toMatch(
      /\[`@media \(min-width: \$\{PANEL_GRID_MIN_WIDTH_PX\}px\)`\]: \{\s*gridTemplateColumns: "1fr 1fr"/,
    );
    expect(code.match(/gridTemplateColumns/g)).toHaveLength(2);
    expect(code).toContain("rowGap: panelGap");
    expect(code).toContain("columnGap: panelGap");
  });
});

describe("PageGrid: a column of rows", () => {
  it("pairs its panels two to a row, in order, and a lone one keeps its half", () => {
    const { container } = render(
      <PageGrid>
        <Panel name="a" />
        <Panel name="b" />
        <Panel name="c" />
        <Panel name="d" />
        <Panel name="e" />
      </PageGrid>,
    );
    const rows = expectPageRowsShape(container, stubs(container));
    expect(layout(container)).toEqual([["a", "b"], ["c", "d"], ["e"]]);
    // Every row is two columns on a wide page, the lone panel's too: half width.
    expect(rows.every(isPairRow)).toBe(true);
  });

  it("the row element is there for one panel too", () => {
    const { container } = render(
      <PageGrid>
        <Panel name="only" />
      </PageGrid>,
    );
    expectPageRowsShape(container, stubs(container));
    expect(layout(container)).toEqual([["only"]]);
  });

  it("a card the page left out leaves no slot: null, false, undefined and an empty list", () => {
    const gated: ReactElement[] = [];
    const off = false as boolean;
    const { container } = render(
      <PageGrid>
        {null}
        <Panel name="a" />
        {off ? <Panel name="gated" /> : null}
        {off && <Panel name="gated" />}
        {undefined}
        {gated}
        <Panel name="b" />
        <Panel name="c" />
      </PageGrid>,
    );
    expectPageRowsShape(container, stubs(container));
    expect(layout(container)).toEqual([["a", "b"], ["c"]]);
  });

  it("lays a list and a fragment of panels flat before pairing them", () => {
    const slot = [<Panel key="s1" name="s1" />, <Panel key="s2" name="s2" />];
    const { container } = render(
      <PageGrid>
        {slot}
        <Panel name="a" />
        <Fragment>
          <Panel name="f1" />
          <Panel name="f2" />
        </Fragment>
      </PageGrid>,
    );
    expectPageRowsShape(container, stubs(container));
    expect(layout(container)).toEqual([["s1", "s2"], ["a", "f1"], ["f2"]]);
  });

  it("full is one panel to a row, in one column at every width", () => {
    const { container } = render(
      <PageGrid full>
        <Panel name="a" />
        <Panel name="b" />
      </PageGrid>,
    );
    const rows = expectPageRowsShape(container, stubs(container));
    expect(layout(container)).toEqual([["a"], ["b"]]);
    expect(rows.some(isPairRow)).toBe(false);
  });

  it("a panel that mounts and draws nothing keeps its place, and a row of nothing takes no room", () => {
    const { container } = render(
      <PageGrid>
        <Panel name="a" />
        <Nothing />
        <Panel name="b" />
        <Panel name="c" />
        <Nothing />
        <Nothing />
      </PageGrid>,
    );
    const rows = panelRowsOf(container);
    expect(layout(container)).toEqual([["a"], ["b", "c"], []]);
    // The row that drew nothing is out of the column, so the page's gap skips it.
    expect(rows[2].children).toHaveLength(0);
    for (const row of rows) expect(rulesOf(row)).toMatch(/:empty\s*\{[^}]*display:\s*none/);
  });
});

describe("PanelRow: a row the page groups itself", () => {
  it("is a row among the paired ones, and the panels around it pair on either side", () => {
    const { container } = render(
      <PageGrid>
        <Panel name="a" />
        <PanelRow>
          <Panel name="b" />
        </PanelRow>
        <Panel name="c" />
        <Panel name="d" />
        <Panel name="e" />
      </PageGrid>,
    );
    expectPageRowsShape(container, stubs(container));
    expect(layout(container)).toEqual([["a"], ["b"], ["c", "d"], ["e"]]);
  });

  it("never holds more than two, drops a card left out, and draws no row for nothing", () => {
    const off = false as boolean;
    const { container } = render(
      <PageGrid>
        <PanelRow>
          <Panel name="a" />
          {off ? <Panel name="gated" /> : null}
          <Panel name="b" />
          <Panel name="c" />
        </PanelRow>
        <PanelRow>{off ? <Panel name="gated" /> : null}</PanelRow>
      </PageGrid>,
    );
    expectPageRowsShape(container, stubs(container));
    expect(layout(container)).toEqual([["a", "b"], ["c"]]);
  });
});

describe("the pages", () => {
  it("Studio: Spaces beside Hub Designs, then Prompts alone", () => {
    const { container } = render(<StudioPage />);
    const rows = expectPageRowsShape(container, stubs(container));
    expect(layout(container)).toEqual([["Spaces", "Hub Designs"], ["Prompts"]]);
    expect(rows.every(isPairRow)).toBe(true);
  });

  it("System (ModuleCardGrid): the shell's cards in rows of two, the pager under them by a gap", () => {
    const system = ["Environment", "Modules", "Log", "Test Health"].map((name) => (
      <Panel key={name} name={name} />
    ));
    const { container } = render(
      <ShellProvider
        value={shell({
          cards: { home: [], system },
          pager: { page: 0, totalPages: 2, onPageChange: () => undefined },
        })}
      >
        <ModuleCardGrid kind="system" />
      </ShellProvider>,
    );
    expectPageRowsShape(container, stubs(container));
    expect(layout(container)).toEqual([
      ["Environment", "Modules"],
      ["Log", "Test Health"],
    ]);
    // The pager is the rows' sibling in a column whose gap spaces it: no margin.
    const pager = container.querySelector<HTMLElement>('nav[aria-label="More cards"]')!;
    const page = container.querySelector<HTMLElement>("[data-page-rows]")!;
    expect(pager.previousElementSibling).toBe(page);
    expect(rulesOf(pager)).not.toMatch(/margin/);
    const stack = pager.parentElement!;
    expect(rulesOf(stack)).toMatch(/flex-direction:\s*column/);
    expect(rulesOf(stack)).toContain(`row-gap: ${pageRowGap}`);
    expect(rulesOf(stack)).not.toMatch(/margin/);
  });

  it("System with one page of cards draws no pager", () => {
    const { container } = render(
      <ShellProvider value={shell({ cards: { home: [], system: [<Panel key="e" name="e" />] } })}>
        <ModuleCardGrid kind="system" />
      </ShellProvider>,
    );
    expectPageRowsShape(container, stubs(container));
    expect(container.querySelector("nav")).toBeNull();
  });

  it("Growth: its two panels, then whatever another module put in its slot", () => {
    const { container } = render(
      <ShellProvider value={shell({ slot: () => [<Panel key="decks" name="Decks" />] })}>
        <GrowthPage />
      </ShellProvider>,
    );
    expectPageRowsShape(container, stubs(container));
    expect(layout(container)).toEqual([["Reviews", "Goals"], ["Decks"]]);
  });

  it("Growth with an empty slot is one row", () => {
    const { container } = render(<GrowthPage />);
    expectPageRowsShape(container, stubs(container));
    expect(layout(container)).toEqual([["Reviews", "Goals"]]);
  });
});

describe("no margin at either level", () => {
  it("real list panels in rows: no margin on the page, a row, a panel, a list or an item", () => {
    const notes = ["one", "two", "three"].map((name) => ({ name }));
    const panel = (title: string) => (
      <ListPanel
        title={title}
        items={notes}
        item={(n: { name: string }) => ({
          id: n.name,
          title: n.name,
          primary: ROW.open.action({ detail: "the note", onClick: () => undefined }),
        })}
        empty={{ icon: <DocumentRegular />, title: "No notes yet" }}
      />
    );
    const { container } = render(
      <PageGrid>
        {panel("First")}
        {panel("Second")}
        {panel("Third")}
      </PageGrid>,
    );
    const panels = Array.from(container.querySelectorAll<HTMLElement>("[data-panel-kind]"));
    expect(panels).toHaveLength(3);
    const rows = expectPageRowsShape(container, panels);
    expect(rows.map((row) => row.children.length)).toEqual([2, 1]);
    const lists = Array.from(container.querySelectorAll<HTMLElement>("[data-card-list]"));
    const items = Array.from(container.querySelectorAll<HTMLElement>("[data-card-item]"));
    expect(lists).toHaveLength(3);
    expect(items).toHaveLength(9);
    // A list resets the browser's own margin to none and sets no other.
    for (const list of lists) expect(rulesOf(list)).not.toMatch(/margin[\w-]*:\s*[^0\s]/);
    for (const el of [...items, ...lists.flatMap((l) => Array.from(l.children))]) {
      expect(rulesOf(el)).not.toMatch(/margin/);
      expect((el as HTMLElement).style.margin).toBe("");
    }
  });
});
