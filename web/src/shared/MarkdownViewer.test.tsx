/**
 * The shared "On this page" list, on the REAL viewer (no mock): every page that
 * shows a markdown body draws it through MarkdownViewer, so the rule is held here
 * once. It is drawn for a body with three or more h2/h3 headings and absent for
 * fewer; two headings with the same words get distinct ids.
 */
import { render, screen, within } from "@testing-library/react";
import { MarkdownViewer } from "./MarkdownViewer";

const LONG = [
  "# Title",
  "",
  "## Problem",
  "Text.",
  "",
  "## Round",
  "Text.",
  "",
  "### Detail",
  "Text.",
  "",
  "## Round",
  "Again.",
].join("\n");

beforeAll(() => {
  Element.prototype.scrollIntoView = jest.fn();
  window.CSS = window.CSS ?? ({} as typeof CSS);
  window.CSS.escape = window.CSS.escape ?? ((v: string) => v);
});

describe("MarkdownViewer: On this page", () => {
  // Below 1100px the aside is hidden by CSS (so queried by element) and the list folds above the text.
  it("lists the headings you can jump to, as buttons with an accessible name", () => {
    const { container } = render(<MarkdownViewer content={LONG} />);
    const nav = container.querySelector<HTMLElement>("nav")!;
    expect(nav.getAttribute("aria-label")).toBe("On this page");
    const names = within(nav)
      .getAllByRole("button", { hidden: true })
      .map((b) => b.textContent)
      .slice(3); // the zoom control (minus, level, plus) sits above the list
    expect(names).toEqual(["Problem", "Round", "Detail", "Round"]);
  });

  it("gives two headings with the same words two ids, and the list points at them", () => {
    const { container } = render(<MarkdownViewer content={LONG} />);
    const ids = Array.from(container.querySelectorAll("h2")).map((h) => h.id);
    expect(new Set(ids).size).toBe(ids.length);
    expect(ids).toEqual(["problem", "round", "round-2"]);
  });

  it("is absent when the body has fewer than three headings", () => {
    render(<MarkdownViewer content={"# Title\n\n## One\nText.\n\n## Two\nText.\n"} />);
    expect(document.querySelector("nav")).toBeNull();
    expect(screen.queryByText("On this page")).toBeNull();
  });

  it("is absent when the body has no headings", () => {
    render(<MarkdownViewer content={"Just prose.\n"} />);
    expect(document.querySelector("nav")).toBeNull();
  });

  it("is absent in a scrolling box of its own", () => {
    render(<MarkdownViewer content={LONG} maxHeight="10rem" />);
    expect(document.querySelector("nav")).toBeNull();
  });
});
