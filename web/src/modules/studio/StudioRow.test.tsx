import { act, fireEvent, render, screen } from "@testing-library/react";
import { StudioRow, RowMetaText } from "./StudioRow";

const LONG_TITLE = "A title that is far too long to fit on one line ".repeat(6).trim();
const LONG_TEXT = "A description that runs on and on past two lines. ".repeat(20).trim();

function row(over: Partial<React.ComponentProps<typeof StudioRow>> = {}) {
  return (
    <StudioRow
      kind="test"
      title="Title"
      meta={<RowMetaText>file.md</RowMetaText>}
      controls={<button>Open</button>}
      {...over}
    />
  );
}

describe("StudioRow", () => {
  it("a long title, a long description and no description have the same structure and classes", () => {
    const { container } = render(
      <>
        {row({ title: LONG_TITLE, description: "short" })}
        {row({ description: LONG_TEXT })}
        {row({ description: undefined })}
      </>,
    );
    const rows = Array.from(container.querySelectorAll("[data-studio-row]"));
    expect(rows).toHaveLength(3);
    const shape = (r: Element) =>
      ["", "[data-row-text]", "[data-row-description]", "[data-row-meta]"].map((sel) =>
        (sel ? r.querySelector(sel) : r)?.getAttribute("class"),
      );
    expect(shape(rows[1])).toEqual(shape(rows[0]));
    expect(shape(rows[2])).toEqual(shape(rows[0]));
    // A row with no description keeps the description band, empty.
    const none = rows[2].querySelector("[data-row-description]");
    expect(none).not.toBeNull();
    expect(none?.textContent).toBe("");
  });

  it("the title is one line and the description two, each clamped with an ellipsis", () => {
    const { container } = render(row({ title: LONG_TITLE, description: LONG_TEXT }));
    const title = container.querySelector("strong")!.parentElement!;
    // The text is whole in the DOM; the clamp is in the styles of its elements.
    expect(title.textContent).toBe(LONG_TITLE);
    const rules = Array.from(document.styleSheets)
      .flatMap((sheet) => Array.from(sheet.cssRules))
      .map((r) => r.cssText)
      .join("\n");
    expect(rules).toMatch(/text-overflow:\s*ellipsis/);
    expect(rules).toMatch(/white-space:\s*nowrap/);
    expect(rules).toMatch(/-webkit-line-clamp:\s*2/);
    const description = container.querySelector("[data-row-description]")!;
    expect(description.textContent).toBe(LONG_TEXT);
  });

  it("the full title and description appear on keyboard focus", async () => {
    const { container } = render(row({ title: LONG_TITLE, description: LONG_TEXT }));
    expect(screen.queryByRole("tooltip")).toBeNull();
    const stop = container.querySelector<HTMLElement>("[data-row-text] [tabindex='0']")!;
    expect(stop).not.toBeNull();
    await act(async () => {
      stop.focus();
      fireEvent.focus(stop);
    });
    const tip = await screen.findByRole("tooltip");
    expect(tip.textContent).toContain(LONG_TITLE);
    expect(tip.textContent).toContain(LONG_TEXT);
  });

  it("a row that opens takes focus on its title button, which carries the tooltip too", async () => {
    const { container } = render(row({ onOpen: () => {}, description: LONG_TEXT }));
    const button = container.querySelector<HTMLElement>("[data-row-text] button")!;
    expect(button).not.toBeNull();
    // No second tab stop beside the button.
    expect(container.querySelector("[data-row-text] [tabindex='0']")).toBeNull();
    await act(async () => {
      fireEvent.focus(button);
    });
    expect((await screen.findByRole("tooltip")).textContent).toContain(LONG_TEXT);
  });

  it("badges sit in the title line, controls at its right, the bottom line apart", () => {
    const { container } = render(row({ badges: <span>archived</span> }));
    const text = container.querySelector("[data-row-text]")!;
    expect(text.textContent).toContain("archived");
    expect(text.parentElement!.textContent).toContain("Open");
    expect(container.querySelector("[data-row-meta]")!.textContent).toBe("file.md");
  });
});
