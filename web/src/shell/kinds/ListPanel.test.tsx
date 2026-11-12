import { useState } from "react";
import { act, fireEvent, render, screen, within } from "@testing-library/react";
import { DocumentRegular } from "@fluentui/react-icons";
import { ListPanel } from "./ListPanel";
import type { FilterRow } from "./ListPanel";
import type { CardItemData, CompactItemData } from "../CardItem";
import type { ListChrome } from "../pageSize";
import { ROW } from "../../shared/CardActions";
import {
  LIST_CHROME_PX,
  LIST_ITEM_PITCH_PX,
  LIST_PAGE_SIZE,
  listChromePx,
  listHeightPx,
  listPageSize,
  pageSizeForRoom,
} from "../pageSize";
import { cardListGapPx, cardListPaddingTopPx } from "../layoutTokens";
import { CARD_ITEM_HEIGHTS_PX } from "../cardItemTokens";
import * as listRoom from "./listRoom";
import { PANEL_HEIGHT_PX, PANEL_MAX_HEIGHT_PX, PANEL_MIN_HEIGHT_PX } from "../panelHeight";
import { expectListPanelShape, expectSentenceInInfoTip, panelOf } from "./panelShapeAssert";

interface Note {
  name: string;
  group: "a" | "b";
}

const notes = (n: number, group: Note["group"] = "a"): Note[] =>
  Array.from({ length: n }, (_, i) => ({ name: `${group}-${i + 1}`, group }));

const toItem = (note: Note): CardItemData => ({
  id: note.name,
  title: note.name,
  description: `About ${note.name}`,
  primary: ROW.open.action({ detail: "the note", onClick: () => undefined }),
});

const icon = <DocumentRegular />;
const none = { icon, title: "No notes yet" };
const panel = () => panelOf(screen.getByText("Notes"));
const titles = () =>
  Array.from(panel().querySelectorAll("[data-card-item] strong")).map((s) => s.textContent);
/** The room, in px, that exactly `n` full items take: the items and the gaps between them. */
const fullRoom = (n: number) => n * CARD_ITEM_HEIGHTS_PX.full + (n - 1) * cardListGapPx.full;

describe("the page size", () => {
  it("is worked out from the panel's fixed height and its own chrome, never typed", () => {
    // One height, on the 4 px grid: a list panel's floor and its cap.
    expect(PANEL_MIN_HEIGHT_PX.list).toBe(PANEL_HEIGHT_PX);
    expect(PANEL_MAX_HEIGHT_PX.list).toBe(PANEL_HEIGHT_PX);
    expect(PANEL_HEIGHT_PX % 4).toBe(0);
    expect(LIST_ITEM_PITCH_PX).toEqual({
      full: CARD_ITEM_HEIGHTS_PX.full + cardListGapPx.full,
      compact: CARD_ITEM_HEIGHTS_PX.compact + cardListGapPx.compact,
      line: CARD_ITEM_HEIGHTS_PX.line + cardListGapPx.line,
    });
    expect(LIST_ITEM_PITCH_PX).toEqual({ full: 112, compact: 82, line: 28 });
    // The rule the panel's height was chosen by, and the one number stated
    // here: four full items under one row of filter chips.
    expect(LIST_PAGE_SIZE).toBe(listPageSize({ density: "full", filterRows: 1 }));
    expect(LIST_PAGE_SIZE).toBe(4);
    // Every other page is the same sum over its own chrome: the height less the
    // chrome, less the space over the first item, in items and the gaps between.
    const sum = (chrome: ListChrome) => {
      const room = PANEL_HEIGHT_PX - listChromePx(chrome) - cardListPaddingTopPx[chrome.density];
      const gap = cardListGapPx[chrome.density];
      return Math.max(1, Math.floor((room + gap) / LIST_ITEM_PITCH_PX[chrome.density]));
    };
    const cases: ListChrome[] = [
      { density: "full" },
      { density: "full", filterRows: 2 },
      { density: "full", filterRows: 1, footNote: true },
      { density: "full", filterRows: 2, footNote: true },
      { density: "full", filterRows: 1, footNote: true, status: true },
      { density: "full", filterRows: 1, lead: true },
      { density: "compact" },
      { density: "line" },
      { density: "line", lead: true },
    ];
    for (const chrome of cases) expect(listPageSize(chrome)).toBe(sum(chrome));
    // A line item is its band, flush against the next: the room in whole lines.
    expect(listPageSize({ density: "line" })).toBe(
      Math.floor((PANEL_HEIGHT_PX - LIST_CHROME_PX.frame) / CARD_ITEM_HEIGHTS_PX.line),
    );
  });

  it("more chrome is never a bigger page, and a smaller item never a smaller one", () => {
    const base = { density: "full", filterRows: 1 } as const;
    expect(listPageSize({ density: "full" })).toBeGreaterThanOrEqual(LIST_PAGE_SIZE);
    for (const more of [
      { filterRows: 2 },
      { footNote: true },
      { status: true },
      { lead: true },
      { footNote: true, status: true },
    ]) {
      expect(listPageSize({ ...base, ...more })).toBeLessThanOrEqual(LIST_PAGE_SIZE);
    }
    // A lead chart is taller than an item, so it always takes at least one.
    expect(listPageSize({ ...base, lead: true })).toBeLessThan(LIST_PAGE_SIZE);
    expect(listPageSize({ density: "line", lead: true })).toBeLessThan(
      listPageSize({ density: "line" }),
    );
    expect(listPageSize({ density: "compact" })).toBeGreaterThan(listPageSize({ density: "full" }));
    expect(listPageSize({ density: "line" })).toBeGreaterThan(listPageSize({ density: "compact" }));
  });

  it("a full page always fits, and one more item never would", () => {
    for (const density of ["full", "compact", "line"] as const) {
      for (const filterRows of [0, 1, 2, 3]) {
        for (const lead of [false, true]) {
          for (const footNote of [false, true]) {
            for (const status of [false, true]) {
              const chrome = { density, filterRows, lead, footNote, status };
              const n = listPageSize(chrome);
              const used = (count: number) => listChromePx(chrome) + listHeightPx(density, count);
              expect(n).toBeGreaterThanOrEqual(1);
              if (n > 1) expect(used(n)).toBeLessThanOrEqual(PANEL_MAX_HEIGHT_PX.list);
              expect(used(n + 1)).toBeGreaterThan(PANEL_MAX_HEIGHT_PX.list);
              // A list's height is its items, the gaps between them and the space over the first.
              expect(listHeightPx(density, n)).toBe(n * LIST_ITEM_PITCH_PX[density]);
            }
          }
        }
      }
    }
  });
});

describe("the page size, measured", () => {
  it("is the room divided by an item and the list's gap: n items and the n - 1 gaps between them", () => {
    // Full: 104 px items, 8 px apart. One more item fits at exactly its room, and not a px sooner.
    expect([fullRoom(1), fullRoom(2), fullRoom(4), fullRoom(5)]).toEqual([104, 216, 440, 552]);
    expect(pageSizeForRoom("full", fullRoom(1))).toBe(1);
    expect(pageSizeForRoom("full", fullRoom(2) - 1)).toBe(1);
    expect(pageSizeForRoom("full", fullRoom(2))).toBe(2);
    expect(pageSizeForRoom("full", fullRoom(4))).toBe(4);
    expect(pageSizeForRoom("full", fullRoom(5) - 1)).toBe(4);
    expect(pageSizeForRoom("full", fullRoom(5))).toBe(5);
    // Compact: 74 px items, 8 px apart.
    expect(pageSizeForRoom("compact", 402)).toBe(5);
    expect(pageSizeForRoom("compact", 401)).toBe(4);
    // Line: 28 px, touching.
    expect(pageSizeForRoom("line", 308)).toBe(11);
    expect(pageSizeForRoom("line", 307)).toBe(10);
  });

  it("is never less than one item, however little room there is", () => {
    for (const room of [0, 10, -400]) {
      expect(pageSizeForRoom("full", room)).toBe(1);
      expect(pageSizeForRoom("compact", room)).toBe(1);
      expect(pageSizeForRoom("line", room)).toBe(1);
    }
  });

  it("agrees with the static sum where the chrome is what the sum expects", () => {
    for (const density of ["full", "compact", "line"] as const) {
      for (const filterRows of [0, 1, 2]) {
        const chrome = { density, filterRows };
        const room =
          PANEL_MAX_HEIGHT_PX.list - listChromePx(chrome) - cardListPaddingTopPx[density];
        expect(pageSizeForRoom(density, room)).toBe(listPageSize(chrome));
      }
    }
  });
});

describe("ListPanel, measuring its list", () => {
  // jsdom lays nothing out, so the room is handed in: the measurement itself is
  // listRoom's own test, and the browser check's.
  let room: number | null = null;
  const observed: Element[] = [];
  let notify: () => void = () => undefined;
  const RealObserver = globalThis.ResizeObserver;
  beforeEach(() => {
    room = null;
    observed.length = 0;
    jest.spyOn(listRoom, "measureListRoom").mockImplementation(() => room);
    globalThis.ResizeObserver = class {
      constructor(callback: ResizeObserverCallback) {
        notify = () => callback([], this as unknown as ResizeObserver);
      }
      observe(el: Element) {
        observed.push(el);
      }
      unobserve() {}
      disconnect() {}
    } as unknown as typeof ResizeObserver;
  });
  afterEach(() => {
    jest.restoreAllMocks();
    globalThis.ResizeObserver = RealObserver;
  });

  it("with nothing to measure, the static sum stands", () => {
    render(<ListPanel title="Notes" items={notes(9)} item={toItem} empty={none} />);
    expect(titles()).toHaveLength(4);
  });

  it("the measured room decides the page, down to one item", () => {
    room = fullRoom(5);
    const { rerender } = render(
      <ListPanel title="Notes" items={notes(9)} item={toItem} empty={none} />,
    );
    expect(titles()).toEqual(["a-1", "a-2", "a-3", "a-4", "a-5"]);
    expect(screen.getByText("Page 1 of 2")).toBeTruthy();
    room = 120;
    rerender(<ListPanel title="Notes" items={notes(9)} item={toItem} empty={none} />);
    expect(titles()).toEqual(["a-1"]);
    expect(screen.getByText("Page 1 of 9")).toBeTruthy();
  });

  it("watches the panel and what sits above the list, and a resize that changes the page keeps its first item in view", () => {
    room = fullRoom(4);
    render(
      <ListPanel
        title="Notes"
        items={notes(12)}
        item={toItem}
        empty={none}
        status={{ tone: "busy", text: "Reading..." }}
      />,
    );
    expect(observed).toContain(panel());
    expect(observed.some((el) => el.hasAttribute("data-panel-status"))).toBe(true);
    expect(observed.some((el) => el.hasAttribute("data-card-list"))).toBe(false);
    fireEvent.click(screen.getByRole("button", { name: "Next page" }));
    expect(titles()).toEqual(["a-5", "a-6", "a-7", "a-8"]);
    // The panel loses room: three fit. The page that holds a-5 is shown.
    room = fullRoom(3);
    act(() => notify());
    expect(titles()).toEqual(["a-4", "a-5", "a-6"]);
    expect(screen.getByText("Page 2 of 4")).toBeTruthy();
    // It gains room again: five fit, and a-5 is still on the page shown.
    room = fullRoom(5);
    act(() => notify());
    expect(titles()).toEqual(["a-1", "a-2", "a-3", "a-4", "a-5"]);
  });
});

describe("ListPanel's paging", () => {
  it("full items: one page of four, no pager at four, a pager at five", () => {
    const { rerender } = render(
      <ListPanel title="Notes" items={notes(4)} item={toItem} empty={none} />,
    );
    expectListPanelShape(panel(), { titles: ["a-1", "a-2", "a-3", "a-4"], total: 4 });
    rerender(<ListPanel title="Notes" items={notes(5)} item={toItem} empty={none} />);
    expectListPanelShape(panel(), { titles: ["a-1", "a-2", "a-3", "a-4"], total: 5 });
    expect(screen.getByText("Page 1 of 2")).toBeTruthy();
    fireEvent.click(screen.getByRole("button", { name: "Next page" }));
    expect(titles()).toEqual(["a-5"]);
    expect(screen.getByText("Page 2 of 2")).toBeTruthy();
  });

  it("compact density: every item the shorter one, no description band, five a page", () => {
    const compact = (n: Note) => ({
      id: n.name,
      title: n.name,
      meta: [{ text: `#${n.name}` }],
      primary: ROW.open.action({ detail: "the note", onClick: () => undefined }),
    });
    render(
      <ListPanel title="Notes" density="compact" items={notes(11)} item={compact} empty={none} />,
    );
    const items = expectListPanelShape(panel(), {
      titles: notes(5).map((n) => n.name),
      total: 11,
    });
    expect(items.every((i) => i.getAttribute("data-density") === "compact")).toBe(true);
    expect(panel().querySelector("[data-row-description]")).toBeNull();
  });

  it("more chrome is a smaller page: two chip rows over a foot note hold three full items, and so does one row over a foot note and under a status", () => {
    const rows: FilterRow[] = ["Filter notes", "Filter by kind"].map((label) => ({
      label,
      chips: [{ id: "all", label: "All", count: 9, active: true, onSelect: () => undefined }],
    }));
    const { rerender } = render(
      <ListPanel
        title="Notes"
        items={notes(9)}
        item={toItem}
        empty={none}
        filters={rows}
        footNote={<span>synced</span>}
      />,
    );
    expectListPanelShape(panel(), { titles: ["a-1", "a-2", "a-3"], total: 9, chips: true });
    // One row with a foot note and a status line shown above the items holds
    // three as well.
    rerender(
      <ListPanel
        title="Notes"
        items={notes(9)}
        item={toItem}
        empty={none}
        filters={rows.slice(0, 1)}
        footNote={<span>synced</span>}
        status={{ tone: "busy", text: "Reading..." }}
      />,
    );
    expectListPanelShape(panel(), { titles: ["a-1", "a-2", "a-3"], total: 9, chips: true });
  });

  it("the panel's height is its kind's whatever the item size: a compact panel with two items is still a list panel of the one height", () => {
    const floor = (density: "full" | "compact" | "line") => {
      const view = render(
        density === "full" ? (
          <ListPanel title="Notes" items={notes(2)} item={toItem} empty={none} />
        ) : density === "compact" ? (
          <ListPanel
            title="Notes"
            density="compact"
            items={notes(2)}
            item={(n) => ({ title: n.name, primary: toItem(n).primary })}
            empty={none}
          />
        ) : (
          <ListPanel
            title="Notes"
            density="line"
            items={notes(2)}
            item={(n) => ({ title: n.name })}
            empty={none}
          />
        ),
      );
      // The helper asserts the kind's minimum and maximum height on the root.
      expectListPanelShape(panel(), { titles: ["a-1", "a-2"], total: 2 });
      const classes = panel().getAttribute("class");
      view.unmount();
      return classes;
    };
    // The same root classes at every density: nothing about the item reaches the floor.
    expect(floor("compact")).toBe(floor("full"));
    expect(floor("line")).toBe(floor("full"));
  });

  it("line density: one-band items, a page of as many as fit and a pager past it", () => {
    const page = listPageSize({ density: "line" });
    render(
      <ListPanel
        title="Notes"
        density="line"
        items={notes(page + 1)}
        item={(n) => ({ title: n.name })}
        empty={none}
      />,
    );
    expectListPanelShape(panel(), { titles: notes(page).map((n) => n.name), total: page + 1 });
    expect(screen.getByText("Page 1 of 2")).toBeTruthy();
  });

  it("the arrow keys page while the pager has focus", () => {
    render(<ListPanel title="Notes" items={notes(11)} item={toItem} empty={none} />);
    const pager = screen.getByRole("group", { name: "Pages" });
    fireEvent.keyDown(pager, { key: "ArrowRight" });
    expect(screen.getByText("Page 2 of 3")).toBeTruthy();
    fireEvent.keyDown(pager, { key: "ArrowRight" });
    fireEvent.keyDown(pager, { key: "ArrowRight" });
    expect(screen.getByText("Page 3 of 3")).toBeTruthy();
    fireEvent.keyDown(pager, { key: "ArrowLeft" });
    expect(screen.getByText("Page 2 of 3")).toBeTruthy();
  });

  it("the page is clamped when the list shrinks", () => {
    const { rerender } = render(
      <ListPanel title="Notes" items={notes(11)} item={toItem} empty={none} />,
    );
    fireEvent.click(screen.getByRole("button", { name: "Next page" }));
    fireEvent.click(screen.getByRole("button", { name: "Next page" }));
    expect(titles()).toEqual(["a-9", "a-10", "a-11"]);
    rerender(<ListPanel title="Notes" items={notes(7)} item={toItem} empty={none} />);
    expect(titles()).toEqual(["a-5", "a-6", "a-7"]);
  });

  function Filtered() {
    const [group, setGroup] = useState<Note["group"]>("a");
    const [text, setText] = useState("");
    const [sort, setSort] = useState("new");
    const all = [...notes(7, "a"), ...notes(12, "b")];
    const items = all.filter((n) => n.group === group && n.name.includes(text));
    const filters: FilterRow[] = [
      {
        label: "Filter notes",
        chips: (["a", "b"] as const).map((g) => ({
          id: g,
          label: g.toUpperCase(),
          count: all.filter((n) => n.group === g).length,
          active: group === g,
          onSelect: () => setGroup(g),
        })),
      },
    ];
    return (
      <ListPanel
        title="Notes"
        items={items}
        item={toItem}
        empty={none}
        filteredEmpty={{ icon, tone: "filtered", title: "No note matches" }}
        filters={filters}
        search={{ label: "Search notes", value: text, onChange: setText }}
        pickers={[
          {
            label: "Order",
            value: sort,
            options: [
              { value: "new", label: "Newest" },
              { value: "old", label: "Oldest" },
            ],
            onChange: setSort,
          },
        ]}
        count={items.length}
        countLabel={`${items.length} notes`}
      />
    );
  }

  it("a chip, the search and a picker each send the list back to its first page", () => {
    render(<Filtered />);
    const next = () => fireEvent.click(screen.getByRole("button", { name: "Next page" }));
    // Under the one chip row a page is LIST_PAGE_SIZE: seven A notes and twelve
    // B notes are each more than a page.
    const page = LIST_PAGE_SIZE;
    const pages = (count: number) => Math.ceil(count / page);
    expect(pages(7)).toBeGreaterThan(1);
    next();
    expect(titles()).toEqual(
      notes(7)
        .slice(page, 2 * page)
        .map((n) => n.name),
    );
    fireEvent.click(screen.getByRole("radio", { name: /^B/ }));
    expect(screen.getByText(`Page 1 of ${pages(12)}`)).toBeTruthy();
    next();
    // Back on the first chip: its first page, not the page it was left on.
    fireEvent.click(screen.getByRole("radio", { name: /^A/ }));
    expect(screen.getByText(`Page 1 of ${pages(7)}`)).toBeTruthy();
    fireEvent.click(screen.getByRole("radio", { name: /^B/ }));
    next();
    fireEvent.change(screen.getByRole("searchbox", { name: "Search notes" }), {
      target: { value: "b-1" },
    });
    // b-1, b-10, b-11, b-12 are what the search leaves: their first page is shown.
    expect(titles()).toEqual(["b-1", "b-10", "b-11", "b-12"].slice(0, page));
    expect(screen.queryByText(/^Page [2-9]/)).toBeNull();
    fireEvent.change(screen.getByRole("searchbox", { name: "Search notes" }), {
      target: { value: "" },
    });
    expect(screen.getByText(`Page 1 of ${pages(12)}`)).toBeTruthy();
    next();
    fireEvent.change(screen.getByRole("combobox", { name: "Order" }), { target: { value: "old" } });
    expect(screen.getByText(`Page 1 of ${pages(12)}`)).toBeTruthy();
    expectListPanelShape(panel(), {
      titles: notes(page, "b").map((n) => n.name),
      total: 12,
      chips: true,
    });
  });

  it("a filter that hides everything says so under the chips, which stay", () => {
    render(<Filtered />);
    fireEvent.change(screen.getByRole("searchbox", { name: "Search notes" }), {
      target: { value: "zzz" },
    });
    expect(screen.getByText("No note matches")).toBeTruthy();
    expect(screen.queryByText("No notes yet")).toBeNull();
    expect(screen.getByRole("group", { name: "Filter notes" })).toBeTruthy();
    expect(screen.getByLabelText("0 notes").textContent).toBe("0");
  });
});

describe("ListPanel's slots", () => {
  it("no items: the empty message, and no pager", () => {
    render(<ListPanel title="Notes" items={[]} item={toItem} empty={none} />);
    expect(screen.getByText("No notes yet")).toBeTruthy();
    expectListPanelShape(panel(), { titles: [], total: 0 });
  });

  it("loading: the label, no items, no pager", () => {
    render(
      <ListPanel
        title="Notes"
        items={notes(9)}
        item={toItem}
        empty={none}
        loading={{ label: "Reading the notes..." }}
      />,
    );
    expect(screen.getByText("Reading the notes...")).toBeTruthy();
    expect(titles()).toEqual([]);
    expect(screen.queryByRole("group", { name: "Pages" })).toBeNull();
  });

  it("the header: icon, title and info at the left; action, refresh and count at the right", () => {
    const run = jest.fn();
    const refresh = jest.fn();
    render(
      <ListPanel
        title="Notes"
        icon={icon}
        info="Notes that belong to no product yet."
        items={notes(1)}
        item={toItem}
        empty={none}
        action={{ label: "Tidy", glyph: icon, onClick: run }}
        refresh={{ onClick: refresh }}
        count="latest 500"
      />,
    );
    expectSentenceInInfoTip(panel(), "About Notes", "Notes that belong to no product yet.");
    fireEvent.click(screen.getByRole("button", { name: "Tidy" }));
    fireEvent.click(screen.getByTitle("Refresh"));
    expect(run).toHaveBeenCalled();
    expect(refresh).toHaveBeenCalled();
    expect(panel().querySelector("[data-panel-count]")!.textContent).toBe("latest 500");
  });

  it("the foot: the left words, the + named for its dialog, and the foot note", () => {
    const add = jest.fn();
    render(
      <ListPanel
        title="Notes"
        items={notes(1)}
        item={toItem}
        empty={none}
        footLeft="open, assigned to all"
        create={{ label: "New Note", onClick: add }}
        footNote={<span>synced a minute ago</span>}
      />,
    );
    expect(screen.getByText("open, assigned to all")).toBeTruthy();
    expect(screen.getByText("synced a minute ago")).toBeTruthy();
    fireEvent.click(screen.getByRole("button", { name: "New Note" }));
    expect(add).toHaveBeenCalled();
  });

  it("a status: what a write came to, dismissable; or what the panel is doing", async () => {
    const gone = jest.fn();
    const { rerender } = render(
      <ListPanel
        title="Notes"
        items={notes(1)}
        item={toItem}
        empty={none}
        status={{ tone: "error", text: "Nothing was written.", onDismiss: gone }}
      />,
    );
    expect((await screen.findByRole("alert")).textContent).toContain("Nothing was written.");
    fireEvent.click(within(screen.getByRole("alert")).getByRole("button", { name: "Dismiss" }));
    expect(gone).toHaveBeenCalled();
    rerender(
      <ListPanel
        title="Notes"
        items={notes(1)}
        item={toItem}
        empty={none}
        status={{ tone: "busy", text: "Reading a-1..." }}
      />,
    );
    expect(screen.getByRole("status").textContent).toBe("Reading a-1...");
  });

  it("a lead chart sits above the items, named", () => {
    render(
      <ListPanel
        title="Notes"
        density="line"
        items={notes(1)}
        item={(n) => ({ title: n.name })}
        empty={none}
        lead={{ chart: { label: "Notes by day", chart: <svg data-testid="chart" /> } }}
      />,
    );
    expect(
      within(screen.getByRole("group", { name: "Notes by day" })).getByTestId("chart"),
    ).toBeTruthy();
  });
});

// What a panel cannot say. Each line below is a compile error, held by tsc:
// were the slot to exist, the directive itself would fail the type check.
export function NotAllowed() {
  return (
    <>
      {/* @ts-expect-error -- a panel sets no height */}
      <ListPanel title="Log" items={notes(1)} item={toItem} empty={none} height={600} />
      {/* @ts-expect-error -- a panel names no page size */}
      <ListPanel title="Log" items={notes(1)} item={toItem} empty={none} pageSize={3} />
      {/* @ts-expect-error -- a panel wears no class */}
      <ListPanel title="Log" items={notes(1)} item={toItem} empty={none} className="mine" />
      {/* @ts-expect-error -- a panel draws no pager */}
      <ListPanel title="Log" items={notes(1)} item={toItem} empty={none} pager={<div />} />
      {/* @ts-expect-error -- `item` returns data, not JSX */}
      <ListPanel title="Log" items={notes(1)} item={(n: Note) => <b>{n.name}</b>} empty={none} />
      {/* @ts-expect-error -- a panel has no body of its own */}
      <ListPanel title="Log" items={notes(1)} item={toItem} empty={none}>
        <p>These are the notes.</p>
      </ListPanel>
      <ListPanel
        title="Log"
        density="compact"
        items={notes(1)}
        item={(n: Note): CompactItemData => ({
          title: n.name,
          primary: toItem(n).primary,
          // @ts-expect-error -- a compact item carries no description
          description: "more",
        })}
        empty={none}
      />
      <ListPanel
        title="Log"
        items={notes(1)}
        item={(n: Note): CardItemData => ({
          ...toItem(n),
          // @ts-expect-error -- an item does not choose its density
          density: "compact",
        })}
        empty={none}
      />
      {/* @ts-expect-error -- the empty message is required */}
      <ListPanel title="Log" items={notes(1)} item={toItem} />
    </>
  );
}
