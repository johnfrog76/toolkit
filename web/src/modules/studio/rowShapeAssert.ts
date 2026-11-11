/** Shared by the three Studio cards' tests: what "one row shape" means, asserted
 *  on the DOM. jsdom cannot measure a height, so the shape is the structure and
 *  the classes that give it its fixed height and its clamp -- the same on every
 *  row whatever its text. */
export function expectOneRowShape(card: HTMLElement, kind: string, titles: string[]) {
  const rows = Array.from(card.querySelectorAll<HTMLElement>(`[data-studio-row="${kind}"]`));
  expect(rows).toHaveLength(titles.length);
  const classOf = (row: HTMLElement, sel: string) =>
    row.querySelector(sel)?.getAttribute("class") ?? null;
  for (const [i, row] of rows.entries()) {
    // The title is on one line, clamped, and still whole in the DOM.
    const title = row.querySelector("strong");
    expect(title?.textContent).toBe(titles[i]);
    // Three bands in a fixed order: title line, description, bottom line.
    expect(row.querySelector("[data-row-description]")).not.toBeNull();
    expect(row.querySelector("[data-row-meta]")).not.toBeNull();
    // The same class on the row and on each band, so one rule sizes them all.
    expect(row.getAttribute("class")).toBe(rows[0].getAttribute("class"));
    expect(classOf(row, "[data-row-description]")).toBe(classOf(rows[0], "[data-row-description]"));
    expect(classOf(row, "[data-row-meta]")).toBe(classOf(rows[0], "[data-row-meta]"));
    expect(classOf(row, "[data-row-text]")).toBe(classOf(rows[0], "[data-row-text]"));
    // The clamp is real CSS on the elements, not left to the text.
    expect(row.querySelector("[data-row-description]")).toBeTruthy();
  }
  return rows;
}
