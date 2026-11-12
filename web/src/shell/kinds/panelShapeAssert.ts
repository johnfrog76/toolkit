import { CARD_ITEM_DESCRIPTION_LINES, CARD_ITEM_HEIGHTS_PX } from "../cardItemTokens";
import { PANEL_BODY, PANEL_MAX_HEIGHT_PX, PANEL_MIN_HEIGHT_PX } from "../panelHeight";
import { cardListGap, cardListPaddingTop } from "../layoutTokens";
import { listChromePx, listHeightPx, listPageSize } from "../pageSize";
import type { ListChrome, ListDensity } from "../pageSize";

/** The structural test's DOM half: called from each panel's own test, on the
 *  panel as it is drawn. jsdom cannot measure a height, so the shape is the
 *  structure and the CSS rules its classes carry. */

/** The CSS rules whose class the element wears: what the browser applies to it. */
function rulesOf(el: Element): string {
  const classes = new Set((el.getAttribute("class") ?? "").split(/\s+/).filter(Boolean));
  return Array.from(document.styleSheets)
    .flatMap((sheet) => Array.from(sheet.cssRules))
    .flatMap((r) => {
      // A media rule's own rules are what apply inside it.
      const inner = (r as CSSMediaRule).cssRules;
      return inner ? [r, ...Array.from(inner)] : [r];
    })
    .filter((r) => {
      const sel = (r as CSSStyleRule).selectorText ?? "";
      return Array.from(classes).some((c) => sel.includes(`.${c}`));
    })
    .map((r) => r.cssText)
    .join("\n");
}

/** The panel root an element sits in. */
export function panelOf(el: Element): HTMLElement {
  const root = el.closest<HTMLElement>("[data-panel-kind]");
  if (!root) throw new Error("not inside a panel: no [data-panel-kind] above the element");
  return root;
}

/** The card items a panel has drawn, in order. */
export function cardItemsOf(panel: Element): HTMLElement[] {
  return Array.from(panel.querySelectorAll<HTMLElement>("[data-card-item]"));
}

export interface ListPanelShape {
  /** The titles of the items on the page, in order. */
  titles: string[];
  /** How many items the panel holds across every page, when the test knows:
   *  the pager is then drawn exactly when there is a second page. */
  total?: number;
  /** The panel splits its items: a chip row is drawn and a chip carries its count. */
  chips?: boolean;
}

/** A list panel, as drawn: its kind and minimum height on the root and no
 *  height of its own; every item a card item with one shape; no more than a
 *  page of them, and a pager exactly when there is more. */
export function expectListPanelShape(panel: HTMLElement, shape: ListPanelShape): HTMLElement[] {
  // The root carries the kind and both bounds -- a list panel's floor is its
  // cap -- whatever the item size, and no height of its own.
  expect(panel.getAttribute("data-panel-kind")).toBe("list");
  const rootRules = rulesOf(panel);
  expect(rootRules).toMatch(new RegExp(`min-height:\\s*${PANEL_MIN_HEIGHT_PX.list}px`));
  expect(rootRules).toMatch(new RegExp(`max-height:\\s*${PANEL_MAX_HEIGHT_PX.list}px`));
  expect(PANEL_MAX_HEIGHT_PX.list).toBe(PANEL_MIN_HEIGHT_PX.list);
  expect(rootRules).not.toMatch(/(^|[^-])\bheight:/);
  expect(panel.style.height).toBe("");
  expect(panel.style.maxHeight).toBe("");

  // The foot sits at the panel's bottom edge however few items there are: the
  // frame is a column filling the root, its body grows, and the foot row is
  // the last thing in it but for a foot note.
  const frame = panel.firstElementChild as HTMLElement;
  expect(rulesOf(frame)).toMatch(/flex:\s*1 1 auto|flex-grow:\s*1/);
  const frameBody = frame.querySelector<HTMLElement>(":scope > [data-panel-frame-body]")!;
  expect(frameBody).not.toBeNull();
  expect(rulesOf(frameBody)).toMatch(/flex-grow:\s*1/);
  const after = Array.from(frame.children).slice(Array.from(frame.children).indexOf(frameBody) + 1);
  expect(after.length).toBeLessThanOrEqual(panel.hasAttribute("data-panel-foot-note") ? 2 : 1);
  for (const el of after) expect(el.matches("hr, [role='separator']")).toBe(false);

  // Overflow pages: the body is the paged form and nothing in the panel
  // scrolls up and down (a chip row may scroll sideways).
  const body = panel.querySelector<HTMLElement>("[data-panel-body]")!;
  expect(body.getAttribute("data-panel-body")).toBe(PANEL_BODY.list);
  const boxes = [panel, panel.firstElementChild!, body, ...cardItemsOf(panel)];
  for (const el of boxes) {
    expect(rulesOf(el)).not.toMatch(/overflow-y:\s*(auto|scroll)/);
    expect(rulesOf(el)).not.toMatch(/overflow:\s*(auto|scroll)/);
  }

  // One page of items: as many as fit under the chrome this panel has drawn.
  const density = panel.getAttribute("data-panel-density") as ListDensity;
  const chrome: ListChrome = {
    density,
    filterRows: body.querySelectorAll(":scope > [role='group'][aria-label^='Filter']").length,
    lead: body.querySelector(":scope > [data-panel-lead]") !== null,
    footNote: panel.hasAttribute("data-panel-foot-note"),
    status: body.querySelector(":scope > [data-panel-status]") !== null,
  };
  const pageSize = listPageSize(chrome);
  const items = cardItemsOf(panel);
  expect(items.map((i) => i.querySelector("strong")?.textContent)).toEqual(shape.titles);
  expect(items.length).toBeLessThanOrEqual(pageSize);
  // The content is no taller than the panel: the chrome and the items drawn,
  // by the heights the tokens give them, come to no more than the cap.
  expect(listChromePx(chrome) + listHeightPx(density, items.length)).toBeLessThanOrEqual(
    PANEL_MAX_HEIGHT_PX.list,
  );
  // The space between the items is the collection's: they sit in one list, a
  // flex column with the gap and the space over the first; no item has a margin.
  const lists = panel.querySelectorAll<HTMLElement>("[data-card-list]");
  expect(lists.length).toBe(items.length > 0 ? 1 : 0);
  const list = lists.length ? lists[0] : null;
  if (list) {
    // One real wrapper, findable by name: a <ul> in the body, each item alone
    // in an <li> that is the list's direct child.
    expect(list.tagName).toBe("UL");
    expect(list.getAttribute("role")).toBe("list");
    expect(list.classList.contains("cardList")).toBe(true);
    expect(list.parentElement).toBe(body);
    expect(Array.from(list.children).every((li) => li.tagName === "LI")).toBe(true);
    expect(Array.from(list.children).map((li) => li.firstElementChild)).toEqual(items);
    expect(Array.from(list.children).every((li) => li.children.length === 1)).toBe(true);
    expect(rulesOf(list)).toMatch(/list-style(-type)?:\s*none/);
    for (const li of Array.from(list.children)) expect(rulesOf(li)).not.toMatch(/margin|padding/);
    const listRules = rulesOf(list);
    expect(listRules).toMatch(/flex-direction:\s*column/);
    expect(listRules).toMatch(new RegExp(`row-gap:\\s*${cardListGap[density]}px`));
    expect(listRules).toMatch(new RegExp(`padding-top:\\s*${cardListPaddingTop[density]}px`));
  }
  for (const item of items) {
    expect(rulesOf(item)).not.toMatch(/margin/);
    expect(item.style.margin).toBe("");
  }

  const pagers = panel.querySelectorAll("[data-list-pager]");
  expect(pagers.length).toBeLessThanOrEqual(1);
  if (shape.total !== undefined) expect(pagers.length).toBe(shape.total > pageSize ? 1 : 0);
  if (pagers.length === 1) {
    expect(pagers[0].textContent).toMatch(/^Page \d+ of \d+$/);
    const names = Array.from(pagers[0].querySelectorAll("button")).map((b) =>
      b.getAttribute("aria-label"),
    );
    expect(names).toEqual(["Previous page", "Next page"]);
  }

  // No inline group subhead in the body: a panel that splits its items does it
  // with a chip row, never a headed section.
  expect(panel.querySelectorAll("section, [role='region'], h1, h2, h3, h4, h5, h6")).toHaveLength(
    0,
  );
  // Any filter chips sit in one row that never wraps.
  const groups = Array.from(
    panel.querySelectorAll<HTMLElement>("[role='group'][aria-label^='Filter']"),
  );
  if (shape.chips) {
    expect(groups.length).toBeGreaterThan(0);
    const radios = Array.from(groups[0].querySelectorAll<HTMLElement>("[role='radio']"));
    expect(radios.some((r) => /\d/.test(r.textContent ?? ""))).toBe(true);
  }
  for (const group of groups) {
    const rules = rulesOf(group);
    expect(rules).toMatch(/flex-wrap:\s*nowrap/);
    expect(rules).toMatch(/overflow-x:\s*auto/);
  }

  const classOf = (item: HTMLElement, sel: string) =>
    item.querySelector(sel)?.getAttribute("class") ?? null;
  for (const item of items) {
    expect(item.getAttribute("data-density")).toBe(density);
    // Not a Fluent Card: a plain element.
    expect(item.className).not.toMatch(/fui-Card/);
    // The title is plain text, whole in the DOM: no link, no button, not
    // focusable. Opening goes through Open, never the title.
    const titleBand = item.querySelector("[data-row-text]")!;
    expect(titleBand).not.toBeNull();
    expect(titleBand.querySelector("a, button, [role='link'], [role='button']")).toBeNull();
    expect(titleBand.querySelector("[tabindex]")).toBeNull();
    expect(titleBand.querySelector("[title]")).toBeNull();
    // No tooltip on the item's text: nothing but a button is described by one.
    expect(item.querySelector("[aria-describedby]:not(button):not(a)")).toBeNull();
    // Exactly one exposed action besides the `...` menu, and every control in
    // the item's controls: nothing in the description or the meta band acts.
    const controls = Array.from(
      item.querySelectorAll<HTMLElement>("button, a[href], [role='link']"),
    );
    const names = controls.map((b) => b.getAttribute("aria-label") ?? b.textContent ?? "");
    const menus = names.filter((n) => /^Actions for /.test(n));
    const exposed = names.filter((n) => !/^Actions for /.test(n));
    expect(menus.length).toBeLessThanOrEqual(1);
    for (const c of controls) expect(c.closest("[data-row-controls]")).not.toBeNull();
    // The same classes on every item and on each band, so one rule sizes them all.
    expect(item.getAttribute("class")).toBe(items[0].getAttribute("class"));
    expect(classOf(item, "[data-row-text]")).toBe(classOf(items[0], "[data-row-text]"));
    if (density === "line") {
      // A line that opens nothing has no action; one that does has one.
      expect(exposed.length).toBeLessThanOrEqual(1);
      expect(rulesOf(titleBand)).toMatch(/text-overflow:\s*ellipsis/);
      continue;
    }
    expect(exposed).toHaveLength(1);
    expect(exposed[0]).toMatch(/^Open\b/);
    expect(names[0]).toBe(exposed[0]);
    // The item's height is its density's token, in the item's own rule: the
    // panel's density, so every item of a panel is the same height.
    expect(rulesOf(item)).toMatch(
      new RegExp(`(^|[^-])height:\\s*${CARD_ITEM_HEIGHTS_PX[density]}px`),
    );
    expect(item.querySelector("[data-row-meta]")).not.toBeNull();
    expect(classOf(item, "[data-row-meta]")).toBe(classOf(items[0], "[data-row-meta]"));
    if (density === "compact") {
      // Two bands: a compact item carries no description, not even an empty band.
      expect(item.querySelector("[data-row-description]")).toBeNull();
      continue;
    }
    // Three bands in a fixed order: title line, description, meta.
    const description = item.querySelector("[data-row-description]")!;
    expect(description).not.toBeNull();
    expect(classOf(item, "[data-row-description]")).toBe(
      classOf(items[0], "[data-row-description]"),
    );
    // The clamp is real CSS on the elements, not left to the text.
    expect(description.hasAttribute("tabindex")).toBe(false);
    expect(description.hasAttribute("title")).toBe(false);
    const clamp = rulesOf(description);
    expect(clamp).toMatch(new RegExp(`-webkit-line-clamp:\\s*${CARD_ITEM_DESCRIPTION_LINES}\\b`));
    expect(clamp).toMatch(/overflow:\s*hidden/);
    expect(clamp).toMatch(/display:\s*-webkit-box/);
    expect(rulesOf(titleBand.querySelector("strong")!.parentElement!)).toMatch(
      /text-overflow:\s*ellipsis/,
    );
  }
  return items;
}

/** A helper sentence lives in the header's info tip, never in the body: the
 *  icon's description is the sentence, and the panel itself holds no copy of it. */
export function expectSentenceInInfoTip(panel: HTMLElement, label: string, sentence: string) {
  const icon = panel.querySelector<HTMLElement>(`[role='img'][aria-label='${label}']`);
  expect(icon).not.toBeNull();
  const described = document.getElementById(icon!.getAttribute("aria-describedby") ?? "");
  expect(described?.textContent).toBe(sentence);
  const drawn = Array.from(panel.querySelectorAll("*")).filter(
    (el) => el.children.length === 0 && el.textContent === sentence,
  );
  // The tip is portalled out of the panel: the panel itself holds no copy.
  expect(drawn).toEqual([]);
}
