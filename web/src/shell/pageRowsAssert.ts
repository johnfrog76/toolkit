import { webLightTheme } from "@fluentui/react-components";
import { escapeRegExp } from "../shared/escapeRegExp";
import { pageRowGap, panelGap } from "./layoutTokens";
import { rulesOf } from "./kinds/panelShapeAssert";

/** The structural test's page half: called on a page as it is drawn. jsdom
 *  cannot lay a grid out, so the shape is the structure and the CSS rules each
 *  element's classes carry. */

/** A Fluent spacing token's length in px: `var(--spacingVerticalL)` is 16. */
export function tokenPx(token: string): number {
  const name = /^var\(--(spacing\w+)\)$/.exec(token)?.[1];
  if (!name) throw new Error(`not a Fluent spacing token: ${token}`);
  const value = (webLightTheme as unknown as Record<string, string>)[name];
  if (!/^\d+px$/.test(value ?? "")) throw new Error(`no px length for ${name}`);
  return parseInt(value, 10);
}

/** The rows of a page, in order. */
export function panelRowsOf(root: ParentNode): HTMLElement[] {
  return Array.from(root.querySelectorAll<HTMLElement>("[data-panel-row]"));
}

/** A page of panels, as drawn: one column of rows whose gap is the page's;
 *  every panel directly inside exactly one row; a row of at most two, its gap
 *  its own; and no margin on the page, a row or a panel. Returns the rows. */
export function expectPageRowsShape(root: ParentNode, panels: HTMLElement[]): HTMLElement[] {
  const pages = Array.from(root.querySelectorAll<HTMLElement>("[data-page-rows]"));
  expect(pages).toHaveLength(1);
  const page = pages[0];

  // The page: a flex column that owns the gap between rows, and holds rows only.
  const pageRules = rulesOf(page);
  expect(pageRules).toMatch(/display:\s*flex/);
  expect(pageRules).toMatch(/flex-direction:\s*column/);
  expect(pageRules).toMatch(new RegExp(`row-gap:\\s*${escapeRegExp(pageRowGap)}`));
  expect(pageRules).not.toMatch(/margin/);
  expect(page.style.margin).toBe("");
  const rows = panelRowsOf(root);
  expect(Array.from(page.children)).toEqual(rows);

  // A row: a grid that owns the gap between its panels, of at most two.
  for (const row of rows) {
    expect(row.classList.contains("panelRow")).toBe(true);
    expect(row.parentElement).toBe(page);
    const rowRules = rulesOf(row);
    expect(rowRules).toMatch(/display:\s*grid/);
    expect(rowRules).toMatch(/align-items:\s*stretch/);
    expect(rowRules).toMatch(new RegExp(`row-gap:\\s*${escapeRegExp(panelGap)}`));
    expect(rowRules).toMatch(new RegExp(`column-gap:\\s*${escapeRegExp(panelGap)}`));
    expect(rowRules).not.toMatch(/margin/);
    expect(row.style.margin).toBe("");
    expect(row.children.length).toBeGreaterThanOrEqual(1);
    expect(row.children.length).toBeLessThanOrEqual(2);
  }

  // A panel: directly inside exactly one row, never loose in the page, no margin.
  const inRows = rows.flatMap((row) => Array.from(row.children));
  expect(inRows).toEqual(panels);
  for (const panel of panels) {
    expect(panel.parentElement?.hasAttribute("data-panel-row")).toBe(true);
    expect(rows.filter((row) => row.contains(panel))).toHaveLength(1);
    expect(rulesOf(panel)).not.toMatch(/margin/);
    expect(panel.style.margin).toBe("");
  }
  return rows;
}

/** Whether a row is two columns on a wide page: its classes carry the rule.
 *  The rule sits in the 900px media query, which cards.tsx builds from
 *  `PANEL_GRID_MIN_WIDTH_PX`; one column is the only rule outside it. */
export function isPairRow(row: HTMLElement): boolean {
  return /grid-template-columns:\s*1fr 1fr/.test(rulesOf(row));
}
