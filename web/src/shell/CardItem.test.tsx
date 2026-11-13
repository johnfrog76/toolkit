import { act, fireEvent, render, screen } from "@testing-library/react";
import { CardItem, CompactItem, LineItem } from "./CardItem";
import type { CardItemData } from "./CardItem";
import { ROW } from "../shared/CardActions";
import {
  CARD_ITEM_COMPACT_HEIGHT_PX,
  CARD_ITEM_DESCRIPTION_LINES,
  CARD_ITEM_HEIGHT_PX,
} from "./cardItemTokens";
import { expectMetaGap, rulesOf } from "./kinds/panelShapeAssert";

const LONG_TITLE = "A title that is far too long to fit on one line ".repeat(6).trim();
const LONG_TEXT = "A description that runs on and on past two lines. ".repeat(20).trim();

function data(over: Partial<CardItemData> = {}): CardItemData {
  return {
    title: "Title",
    meta: [{ text: "file.md", shrink: true }],
    primary: ROW.open.action({ detail: "the note", onClick: () => undefined }),
    ...over,
  };
}

const rules = () =>
  Array.from(document.styleSheets)
    .flatMap((sheet) => Array.from(sheet.cssRules))
    .map((r) => r.cssText)
    .join("\n");

describe("CardItem", () => {
  it("a long title, a long description and no description have the same structure and classes", () => {
    const { container } = render(
      <>
        <CardItem data={data({ title: LONG_TITLE, description: "short" })} />
        <CardItem data={data({ description: LONG_TEXT })} />
        <CardItem data={data({ description: undefined })} />
      </>,
    );
    const items = Array.from(container.querySelectorAll("[data-card-item]"));
    expect(items).toHaveLength(3);
    const shape = (r: Element) =>
      ["", "[data-row-text]", "[data-row-description]", "[data-row-meta]"].map((sel) =>
        (sel ? r.querySelector(sel) : r)?.getAttribute("class"),
      );
    expect(shape(items[1])).toEqual(shape(items[0]));
    expect(shape(items[2])).toEqual(shape(items[0]));
    // An item with no description keeps the description band, empty.
    const none = items[2].querySelector("[data-row-description]");
    expect(none).not.toBeNull();
    expect(none?.textContent).toBe("");
  });

  it("the title is one line and the description two, each clamped, the text whole in the DOM", () => {
    const { container } = render(
      <CardItem data={data({ title: LONG_TITLE, description: LONG_TEXT })} />,
    );
    expect(container.querySelector("strong")!.textContent).toBe(LONG_TITLE);
    expect(container.querySelector("[data-row-description]")!.textContent).toBe(LONG_TEXT);
    const css = rules();
    expect(css).toMatch(/text-overflow:\s*ellipsis/);
    expect(css).toMatch(/white-space:\s*nowrap/);
    expect(css).toMatch(new RegExp(`-webkit-line-clamp:\\s*${CARD_ITEM_DESCRIPTION_LINES}`));
    expect(css).toMatch(new RegExp(`height:\\s*${CARD_ITEM_HEIGHT_PX}px`));
  });

  it("the meta band sits one gap under the description, the same under one line, two lines or none: a grid track, never a margin", () => {
    const { container } = render(
      <>
        <CardItem data={data({ description: "short" })} />
        <CardItem data={data({ description: LONG_TEXT })} />
        <CardItem data={data({ description: undefined })} />
      </>,
    );
    const items = Array.from(container.querySelectorAll<HTMLElement>("[data-card-item]"));
    expect(items).toHaveLength(3);
    // The track, the meta band's row, no margin on a band, and the height sum.
    for (const item of items) expectMetaGap(item);
    // One rule places all three: the description's length changes nothing.
    expect(rulesOf(items[1])).toBe(rulesOf(items[0]));
    expect(rulesOf(items[2])).toBe(rulesOf(items[0]));
  });

  it("is a plain element, not a Fluent Card", () => {
    const { container } = render(<CardItem data={data()} />);
    expect(container.querySelector(".fui-Card")).toBeNull();
  });

  it("the title is plain text: no link, no button, not focusable, and no tooltip on it or the description", async () => {
    const { container } = render(
      <CardItem data={data({ title: LONG_TITLE, description: LONG_TEXT })} />,
    );
    const text = container.querySelector("[data-row-text]")!;
    expect(text.querySelector("a, button, [role='link'], [role='button']")).toBeNull();
    expect(text.querySelector("[tabindex]")).toBeNull();
    for (const el of [text, container.querySelector("[data-row-description]")!]) {
      await act(async () => {
        fireEvent.mouseEnter(el);
        fireEvent.focus(el);
      });
      expect(el.hasAttribute("title")).toBe(false);
    }
    expect(screen.queryByRole("tooltip")).toBeNull();
  });

  it("one exposed action, Open, and every other action in the menu", async () => {
    const copied = jest.fn();
    render(
      <CardItem
        data={data({
          name: "the-file",
          menu: [ROW.copy.action({ detail: "reference", onClick: copied })],
        })}
      />,
    );
    const buttons = screen.getAllByRole("button").map((b) => b.getAttribute("aria-label"));
    expect(buttons).toEqual(["Open the note", "Actions for the-file"]);
    fireEvent.click(screen.getByRole("button", { name: "Actions for the-file" }));
    fireEvent.click(await screen.findByRole("menuitem", { name: "Copy reference" }));
    expect(copied).toHaveBeenCalled();
  });

  it("badges sit in the title line; the meta band holds the thumb, the progress, badges and text", () => {
    const { container } = render(
      <CardItem
        data={data({
          badges: [{ label: "archived" }],
          thumb: { url: "/api/cover/a b.png", label: "Cover of Title" },
          progress: { done: 2, total: 4 },
          meta: [
            { badge: { label: "Space", title: "what it is" } },
            { text: "file.md", shrink: true },
            { text: "Could not switch.", tone: "alert" },
          ],
        })}
      />,
    );
    expect(container.querySelector("[data-row-text]")!.textContent).toContain("archived");
    const meta = container.querySelector("[data-row-meta]")!;
    expect(meta.textContent).toBe("2/4Spacefile.mdCould not switch.");
    expect(screen.getByRole("img", { name: "Cover of Title" })).toBeTruthy();
    expect(screen.getByRole("progressbar")).toBeTruthy();
    expect(screen.getByRole("alert").textContent).toBe("Could not switch.");
    expect(screen.getByText("Space").getAttribute("title")).toBe("what it is");
  });

  it("a progress with nothing to count draws no bar", () => {
    render(<CardItem data={data({ progress: { done: 0, total: 0 } })} />);
    expect(screen.queryByRole("progressbar")).toBeNull();
  });
});

describe("CompactItem", () => {
  it("is the title line and the meta band: no description band, one shorter height, the same title and controls", () => {
    const { container } = render(
      <>
        <CompactItem data={data({ title: LONG_TITLE })} />
        <CompactItem data={data({ badges: [{ label: "pinned" }] })} />
      </>,
    );
    const items = Array.from(container.querySelectorAll("[data-card-item]"));
    expect(items.map((i) => i.getAttribute("data-density"))).toEqual(["compact", "compact"]);
    expect(items[1].getAttribute("class")).toBe(items[0].getAttribute("class"));
    expect(container.querySelector("[data-row-description]")).toBeNull();
    expect(items[0].querySelector("strong")!.textContent).toBe(LONG_TITLE);
    expect(items[0].querySelector("[data-row-meta]")!.textContent).toBe("file.md");
    expect(rules()).toMatch(new RegExp(`height:\\s*${CARD_ITEM_COMPACT_HEIGHT_PX}px`));
    expect(CARD_ITEM_COMPACT_HEIGHT_PX).toBeLessThan(CARD_ITEM_HEIGHT_PX);
    expect(screen.getAllByRole("button").map((b) => b.getAttribute("aria-label"))).toEqual([
      "Open the note",
      "Open the note",
    ]);
  });
});

describe("LineItem", () => {
  it("is one band: the meta, the badges, then the title and description on one clamped line", () => {
    const { container } = render(
      <LineItem
        data={{
          title: "Status",
          description: LONG_TEXT,
          meta: [{ text: "09:00:00", mono: true }],
          badges: [{ label: "CMD" }],
        }}
      />,
    );
    const item = container.querySelector("[data-card-item]")!;
    expect(item.getAttribute("data-density")).toBe("line");
    expect(item.textContent).toBe(`09:00:00CMDStatus ${LONG_TEXT}`);
    expect(item.querySelector("[data-row-description]")).toBeNull();
    // A line that opens nothing has no action.
    expect(screen.queryByRole("button")).toBeNull();
    expect(item.querySelector("[title]")).toBeNull();
  });

  it("a line that opens something has its one action", () => {
    render(
      <LineItem
        data={{
          title: "Run 12",
          primary: ROW.open.action({ detail: "the run", onClick: () => undefined }),
        }}
      />,
    );
    expect(screen.getAllByRole("button").map((b) => b.getAttribute("aria-label"))).toEqual([
      "Open the run",
    ]);
  });
});
