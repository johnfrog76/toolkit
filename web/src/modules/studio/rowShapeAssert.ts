import { LIST_ITEM_HEIGHT_PX, LIST_PAGE_SIZE } from "../../shell/cardHeight";

/** Shared by the three Studio cards' tests: what "one row shape" means, asserted
 *  on the DOM. jsdom cannot measure a height, so the shape is the structure and
 *  the classes that give it its fixed height and its clamp -- the same on every
 *  row whatever its text. */
/** The CSS rules whose class the element wears: what the browser applies to it. */
function clampRules(el: Element): string {
  const classes = new Set((el.getAttribute("class") ?? "").split(/\s+/));
  return Array.from(document.styleSheets)
    .flatMap((sheet) => Array.from(sheet.cssRules))
    .filter((r) => {
      const sel = (r as CSSStyleRule).selectorText ?? "";
      return Array.from(classes).some((c) => c && sel.includes(`.${c}`));
    })
    .map((r) => r.cssText)
    .join("\n");
}

export function expectOneRowShape(card: HTMLElement, kind: string, titles: string[]) {
  // The shared list settings: five items a page, each item 80 px (measured in
  // the browser), so a page 2 exists only past five.
  expect(LIST_PAGE_SIZE).toBe(5);
  expect(LIST_ITEM_HEIGHT_PX).toBe(80);
  const rows = Array.from(card.querySelectorAll<HTMLElement>(`[data-studio-row="${kind}"]`));
  expect(rows).toHaveLength(titles.length);
  expect(rows.length).toBeLessThanOrEqual(LIST_PAGE_SIZE);
  // No inline group subhead in the body: a card that splits its items does it
  // with the one chip row, never a headed section.
  expect(card.querySelectorAll("section, [role='region']")).toHaveLength(0);
  // The filter chips exist and at least one carries its count.
  const groups = Array.from(
    card.querySelectorAll<HTMLElement>("[role='group'][aria-label^='Filter']"),
  );
  expect(groups.length).toBeGreaterThan(0);
  const radios = Array.from(groups[0].querySelectorAll<HTMLElement>("[role='radio']"));
  expect(radios.length).toBeGreaterThan(0);
  expect(radios.some((r) => /\d/.test(r.textContent ?? ""))).toBe(true);
  // Any filter chips on the card sit in one row that never wraps.
  for (const group of groups) {
    const rules = clampRules(group);
    expect(rules).toMatch(/flex-wrap:\s*nowrap/);
    expect(rules).toMatch(/overflow-x:\s*auto/);
  }
  const classOf = (row: HTMLElement, sel: string) =>
    row.querySelector(sel)?.getAttribute("class") ?? null;
  for (const [i, row] of rows.entries()) {
    // The title is on one line, clamped, and still whole in the DOM.
    const title = row.querySelector("strong");
    expect(title?.textContent).toBe(titles[i]);
    // The title is plain text: opening goes through Open, never the title.
    const titleBand = row.querySelector("[data-row-text]")!;
    expect(titleBand.querySelector("a, button, [role='link'], [role='button']")).toBeNull();
    // Not focusable, and no tooltip: the whole text is in the DOM instead.
    expect(titleBand.querySelector("[tabindex]")).toBeNull();
    expect(row.querySelector("[aria-describedby]:not(button)")).toBeNull();
    // One exposed action, Open, and the `...` menu: nothing else is a button
    // in the title line (a badge is text, not a control).
    const buttons = Array.from(row.querySelectorAll<HTMLElement>("button, a[href]"));
    const names = buttons.map((b) => b.getAttribute("aria-label") ?? b.textContent ?? "");
    expect(names).toHaveLength(2);
    expect(names[0]).toMatch(/^Open\b/);
    expect(names[1]).toMatch(/^Actions for /);
    // Three bands in a fixed order: title line, description, bottom line.
    expect(row.querySelector("[data-row-description]")).not.toBeNull();
    expect(row.querySelector("[data-row-meta]")).not.toBeNull();
    // The item's height is the shared token, in the row's own rule.
    expect(clampRules(row)).toMatch(new RegExp(`height:\\s*${LIST_ITEM_HEIGHT_PX}px`));
    // The same class on the row and on each band, so one rule sizes them all.
    expect(row.getAttribute("class")).toBe(rows[0].getAttribute("class"));
    expect(classOf(row, "[data-row-description]")).toBe(classOf(rows[0], "[data-row-description]"));
    expect(classOf(row, "[data-row-meta]")).toBe(classOf(rows[0], "[data-row-meta]"));
    expect(classOf(row, "[data-row-text]")).toBe(classOf(rows[0], "[data-row-text]"));
    // The clamp is real CSS on the elements, not left to the text: two lines.
    const description = row.querySelector("[data-row-description]")!;
    expect(description).toBeTruthy();
    expect(description.hasAttribute("tabindex")).toBe(false);
    expect(clampRules(description)).toMatch(/-webkit-line-clamp:\s*2\b/);
    expect(clampRules(description)).toMatch(/overflow:\s*hidden/);
    expect(clampRules(description)).toMatch(/display:\s*-webkit-box/);
  }
  return rows;
}

/** A helper sentence lives in the header's info tip, never in the body: the
 *  icon's description is the sentence, and the card's own body and foot hold no copy of it. */
export function expectSentenceInInfoTip(card: HTMLElement, label: string, sentence: string) {
  const icon = card.querySelector<HTMLElement>(`[role='img'][aria-label='${label}']`);
  expect(icon).not.toBeNull();
  const described = document.getElementById(icon!.getAttribute("aria-describedby") ?? "");
  expect(described?.textContent).toBe(sentence);
  const drawn = Array.from(card.querySelectorAll("*")).filter(
    (el) => el.children.length === 0 && el.textContent === sentence,
  );
  // The tip is portalled out of the card: the card itself holds no copy.
  expect(drawn).toEqual([]);
}
