/**
 * The panel rules, held statically: every source file under src/ is read with
 * the TypeScript parser, and a file that breaks a rule is named.
 *
 *   1. Fluent's Card is imported by PanelFrame and by nothing else.
 *   2. PanelFrame is the private base of the kinds: a feature module imports a
 *      kind, never the frame. A page that is not a panel is exempt by name,
 *      with its reason.
 *   3. ScenePanel, the one kind that takes free content, is the Lounge's.
 *   4. The pager is ListPanel's: nothing else draws Pagination or calls
 *      usePagination.
 *   5. A panel file -- one that fills a kind -- sets no height, min-height or
 *      max-height, names no px or vh length and no page size; draws no item,
 *      action, link, tooltip, heading or section of its own; and gives the kind
 *      no body: an explanation goes in the kind's `info` slot.
 *   6. A list panel is one fixed height: its floor is its cap. What does not
 *      fit is paged, never scrolled; a kind whose body is one block scrolls it
 *      in PanelFrame's own `scrollable` area. The other kinds have a floor only.
 *   7. The foot sits at a panel's bottom edge however short its content: the
 *      frame's body grows, in one rule every kind inherits.
 *   8. An item's lengths are tokens and its height is their sum; one padding
 *      serves its top and its bottom; it has no margin -- the gap between
 *      items is the list's, one <ul> the items sit directly inside.
 *   9. The item size is the panel's: `density` is a prop on the kind, never a
 *      field of an item, and a file whose panel is `compact` gives no item a
 *      description. The three sizes' heights are the tokens file's.
 *
 * A panel that has not moved onto its kind yet is on a NAMED list below. The
 * lists are the migration's to-do: each is held exact, so a file that moves
 * must come off its list and a new file cannot join one quietly.
 */
import fs from "node:fs";
import path from "node:path";
import ts from "typescript";
import { webLightTheme } from "@fluentui/react-components";
import {
  CARD_ITEM_BORDER_PX,
  CARD_ITEM_COMPACT_BAND_GAP_PX,
  CARD_ITEM_DESCRIPTION_BAND_PX,
  CARD_ITEM_DESCRIPTION_LINES,
  CARD_ITEM_DESCRIPTION_LINE_PX,
  CARD_ITEM_HEIGHTS_PX,
  CARD_ITEM_LINE_BAND_PX,
  CARD_ITEM_META_BAND_PX,
  CARD_ITEM_PADDING_Y_PX,
  CARD_ITEM_TITLE_BAND_PX,
} from "../cardItemTokens";
import {
  cardListGap,
  cardListGapPx,
  cardListPaddingTop,
  cardListPaddingTopPx,
  filterRowGap,
  filterRowGapPx,
} from "../layoutTokens";
import { PANEL_BODY, PANEL_MAX_HEIGHT_PX, PANEL_MIN_HEIGHT_PX, PANEL_SLOTS } from "../panelHeight";

const SRC = path.join(__dirname, "..", "..");

const FRAME = "shared/PanelFrame.tsx";
const KINDS_DIR = "shell/kinds/";
const KIND_NAMES = ["ListPanel", "StatusPanel", "StatPanel", "ChartPanel", "ScenePanel"];
const LOUNGE_DIR = "modules/lounge/";

/** Panels still on PanelFrame, and the kind each becomes. */
const FRAME_NOT_YET_MOVED: Record<string, string> = {
  "modules/ado/BurnCard.tsx": "StatPanel",
  "modules/ado/ConnectAdoCard.tsx": "merged into My Work's empty state",
  "modules/ado/Dashboard.tsx": "ListPanel (line): Build",
  "modules/ado/DeploysCard.tsx": "ListPanel (line)",
  "modules/ado/DesignList.tsx": "ListPanel (wide): Designs and specs",
  "modules/ado/EngagementSummary.tsx": "StatPanel",
  "modules/ado/EnvCard.tsx": "StatusPanel",
  "modules/ado/FacePicker.tsx": "ScenePanel",
  "modules/ado/IssueReportCard.tsx": "StatPanel",
  "modules/ado/MilestonesCard.tsx": "ListPanel",
  "modules/ado/ModulesCard.tsx": "StatusPanel",
  "modules/ado/MyPRs.tsx": "ListPanel",
  "modules/ado/PRCommentsList.tsx": "ListPanel",
  "modules/ado/SprintVelocity.tsx": "ChartPanel",
  "modules/ado/WorkBreakdown.tsx": "ChartPanel",
  "modules/communication/OneOnOne.tsx": "ListPanel: Meetings",
  "modules/growth/Goals.tsx": "ListPanel",
  "modules/growth/ReviewArchive.tsx": "ListPanel: Reviews",
  "modules/growth/SkillsSnapshot.tsx": "merged into Work breakdown, as its legend",
  "modules/lounge/GoBoard.tsx": "ScenePanel",
  "modules/lounge/TicTacToe.tsx": "ScenePanel",
  "modules/lounge/WordRing.tsx": "ScenePanel",
  "modules/organize/RemindersCard.tsx": "ListPanel",
  "modules/solitaireAgile/MilestonesPage.tsx": "ListPanel",
};

/** Pages that are not panels, each with its reason. They keep the frame. */
const FRAME_EXEMPT: Record<string, string> = {
  "modules/ado/ConnectPage.tsx": "the Connect page: a wizard, not a panel",
  "modules/ado/CreatePrompt.tsx": "the Actions forms",
  "modules/ado/DesignDocPage.tsx": "a document page: one design, read whole",
  "modules/ado/DocsDocPage.tsx": "the Docs reader",
  "modules/ado/DocsLanding.tsx": "the Docs reader's landing page",
  "modules/ado/IssueDetailPage.tsx": "a detail page: one issue",
  "modules/ado/PromptDetailPage.tsx": "a detail page: one prompt file",
  "modules/ado/ReviewPage.tsx": "a detail page: one pull request's review",
  "modules/communication/ManagerDetailPage.tsx": "a detail page: one meeting",
  "modules/communication/ManagerSessionPage.tsx": "a document page: one session",
  "modules/deck/DeckPage.tsx": "a detail page: one deck",
  "modules/growth/GoalDetailPage.tsx": "a detail page: one growth item",
  "modules/growth/SkillsPage.tsx": "a detail page: the skills behind the snapshot",
  "modules/solitaireAgile/StandupPage.tsx": "the Standup page",
  "modules/solitaireAgile/TriagePage.tsx": "the Triage page",
  "modules/studio/DesignNotePage.tsx": "a document page: one hub design note",
  "modules/studio/PromptPage.tsx": "a document page: one prompt",
};

/** Files still drawing a Fluent Card of their own: mostly an item inside a panel. */
const CARD_NOT_YET_MOVED: string[] = [
  "modules/ado/Billing.tsx",
  "modules/ado/DesignList.tsx",
  "modules/ado/DesignSearchInside.tsx",
  "modules/ado/MyPRs.tsx",
  "modules/ado/PRCommentsDetail.tsx",
  "modules/ado/PRCommentsList.tsx",
  "modules/communication/OneOnOne.tsx",
  "modules/growth/Goals.tsx",
  "modules/growth/ReviewArchive.tsx",
  "modules/organize/RemindersCard.tsx",
];

/** Panels still drawing their own pager. */
const PAGER_NOT_YET_MOVED: string[] = [
  "modules/communication/OneOnOne.tsx",
  "modules/growth/Goals.tsx",
  "modules/growth/ReviewArchive.tsx",
  "modules/organize/RemindersCard.tsx",
];

/** Files exempt from the pager rule, each with its reason. None: the shell's
 *  pager over a page of panels draws the kinds' own ListPager. */
const PAGER_EXEMPT: Record<string, string> = {};

interface Imported {
  from: string;
  names: string[];
  typeOnly: boolean;
}

function importsOf(sf: ts.SourceFile): Imported[] {
  const out: Imported[] = [];
  for (const st of sf.statements) {
    if (!ts.isImportDeclaration(st) || !ts.isStringLiteral(st.moduleSpecifier)) continue;
    const clause = st.importClause;
    const names: string[] = [];
    const bindings = clause?.namedBindings;
    if (bindings && ts.isNamedImports(bindings)) {
      for (const el of bindings.elements) {
        if (!el.isTypeOnly) names.push((el.propertyName ?? el.name).text);
      }
    }
    if (clause?.name) names.push(clause.name.text);
    out.push({ from: st.moduleSpecifier.text, names, typeOnly: Boolean(clause?.isTypeOnly) });
  }
  return out;
}

const endsWith = (from: string, name: string) => from === name || from.endsWith(`/${name}`);

export interface Facts {
  importsCard: boolean;
  importsFrame: boolean;
  importsPager: boolean;
  /** The kinds the file fills: it is a panel file when there is one. */
  kinds: string[];
  /** What a panel file does that a panel may not. */
  findings: string[];
}

/** Read one file. `file` is its path under src/, with forward slashes. */
export function readFile(file: string, text: string): Facts {
  const kind = file.endsWith(".tsx") ? ts.ScriptKind.TSX : ts.ScriptKind.TS;
  const sf = ts.createSourceFile(file, text, ts.ScriptTarget.Latest, true, kind);
  const at = (n: ts.Node) => `${file}:${sf.getLineAndCharacterOfPosition(n.getStart()).line + 1}`;
  const imports = importsOf(sf).filter((i) => !i.typeOnly);
  const has = (module: string, name: string) =>
    imports.some((i) => endsWith(i.from, module) && i.names.includes(name));
  const facts: Facts = {
    importsCard: imports.some(
      (i) => i.from === "@fluentui/react-components" && i.names.includes("Card"),
    ),
    importsFrame: has("PanelFrame", "PanelFrame"),
    importsPager: has("Pagination", "Pagination") || has("usePagination", "usePagination"),
    kinds: KIND_NAMES.filter((k) => has(k, k)),
    findings: [],
  };
  if (facts.kinds.includes("ScenePanel") && !file.startsWith(LOUNGE_DIR)) {
    facts.findings.push(`${file}: ScenePanel is the Lounge's -- it takes free content`);
  }
  if (facts.kinds.length === 0 || file.startsWith(KINDS_DIR)) return facts;

  // A panel file.
  const say = (n: ts.Node, what: string) => facts.findings.push(`${at(n)}: ${what}`);
  for (const i of imports) {
    for (const name of i.names) {
      if (i.from === "@fluentui/react-components" && /^(Tooltip|Link)$/.test(name)) {
        say(sf, `imports ${name} -- a card item's text has no tooltip and no link`);
      }
      if (i.from === "@fluentui/react-components" && /^(Subtitle|Title|LargeTitle)/.test(name)) {
        say(sf, `imports ${name} -- no inline subhead: a panel splits its items with filters`);
      }
      if (endsWith(i.from, "CardItem") && /^(CardItem|LineItem)$/.test(name)) {
        say(sf, `imports ${name} -- the kind draws the card item, from data`);
      }
      if (endsWith(i.from, "CardActions") && name === "CardActions") {
        say(sf, "imports CardActions -- an item's actions are data: one primary, and a menu");
      }
    }
  }
  let compact = false;
  const descriptions: ts.Node[] = [];
  const visit = (node: ts.Node) => {
    const name =
      (ts.isPropertyAssignment(node) || ts.isJsxAttribute(node)) &&
      (ts.isIdentifier(node.name) || ts.isStringLiteral(node.name))
        ? node.name.text
        : null;
    if (name && /^(height|max-?height|min-?height)$/i.test(name)) {
      say(node, `sets ${name} -- a panel has its kind's minimum height and no other`);
    }
    if (ts.isPropertyAssignment(node) && name === "density") {
      say(node, "sets density on an item -- the panel chooses it, for every item at once");
    }
    if (
      ts.isJsxAttribute(node) &&
      name === "density" &&
      node.initializer &&
      ts.isStringLiteral(node.initializer) &&
      node.initializer.text === "compact"
    ) {
      compact = true;
    }
    if (ts.isPropertyAssignment(node) && name === "description") descriptions.push(node);
    if (ts.isIdentifier(node) && /page_?size/i.test(node.text)) {
      say(node, `names a page size (${node.text}) -- the page size is the shell's table`);
    }
    if (
      (ts.isStringLiteral(node) || ts.isNoSubstitutionTemplateLiteral(node)) &&
      /(^|[\s(])\d+(\.\d+)?(px|vh)\b/.test(node.text)
    ) {
      say(node, `writes a length ("${node.text}") -- a panel file styles nothing by the pixel`);
    }
    if (ts.isJsxOpeningElement(node) || ts.isJsxSelfClosingElement(node)) {
      const tag = node.tagName.getText(sf);
      if (/^(a|section|h[1-6])$/.test(tag)) {
        say(node, `draws <${tag}> -- no link, heading or section of a panel's own`);
      }
      if (KIND_NAMES.includes(tag) && ts.isJsxOpeningElement(node)) {
        say(node, `gives ${tag} a body -- an explanation goes in the kind's info slot`);
      }
    }
    ts.forEachChild(node, visit);
  };
  visit(sf);
  if (compact) {
    for (const d of descriptions) {
      say(d, "gives an item a description in a compact panel -- a compact item has none");
    }
  }
  return facts;
}

function sourceFiles(dir: string, out: string[] = []): string[] {
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) sourceFiles(full, out);
    else if (/\.tsx?$/.test(entry.name) && !/\.test\.tsx?$/.test(entry.name)) out.push(full);
  }
  return out;
}

const facts = new Map<string, Facts>();
for (const full of sourceFiles(SRC)) {
  const file = path.relative(SRC, full).split(path.sep).join("/");
  facts.set(file, readFile(file, fs.readFileSync(full, "utf8")));
}
const filesWhere = (test: (f: Facts, file: string) => boolean) =>
  Array.from(facts.entries())
    .filter(([file, f]) => test(f, file))
    .map(([file]) => file)
    .sort();

describe("the panel rules, over every source file", () => {
  it("Fluent Card is imported by PanelFrame only, but for the files not yet moved", () => {
    expect(facts.get(FRAME)?.importsCard).toBe(true);
    expect(filesWhere((f, file) => f.importsCard && file !== FRAME)).toEqual(
      [...CARD_NOT_YET_MOVED].sort(),
    );
  });

  it("PanelFrame is imported by the kinds only, but for the pages exempt by name and the panels not yet moved", () => {
    const importers = filesWhere((f, file) => f.importsFrame && !file.startsWith(KINDS_DIR));
    expect(importers).toEqual(
      [...Object.keys(FRAME_NOT_YET_MOVED), ...Object.keys(FRAME_EXEMPT)].sort(),
    );
    // Each exemption says why.
    for (const reason of Object.values(FRAME_EXEMPT)) expect(reason.length).toBeGreaterThan(10);
  });

  it("the pager is ListPanel's: nothing else draws Pagination or calls usePagination, but for the panels not yet moved", () => {
    expect(filesWhere((f, file) => f.importsPager && !file.startsWith(KINDS_DIR))).toEqual(
      [...PAGER_NOT_YET_MOVED, ...Object.keys(PAGER_EXEMPT)].sort(),
    );
  });

  it("a panel on a kind is on no to-do list", () => {
    const moved = filesWhere((f, file) => f.kinds.length > 0 && !file.startsWith(KINDS_DIR));
    expect(moved).toEqual([
      "modules/ado/MyWork.tsx",
      "modules/ado/PromptStatus.tsx",
      "modules/ado/TestHealth.tsx",
      "modules/ado/ToolkitLog.tsx",
      "modules/deck/DeckPickerCard.tsx",
      "modules/studio/DesignsCard.tsx",
      "modules/studio/FoyerCard.tsx",
      "modules/studio/PromptsCard.tsx",
    ]);
    const todo = new Set([
      ...Object.keys(FRAME_NOT_YET_MOVED),
      ...CARD_NOT_YET_MOVED,
      ...PAGER_NOT_YET_MOVED,
    ]);
    expect(moved.filter((file) => todo.has(file))).toEqual([]);
  });

  it("no panel file sets a height, names a page size, or draws an item, a link, a tooltip, a subhead or a body of its own", () => {
    expect(Array.from(facts.values()).flatMap((f) => f.findings)).toEqual([]);
  });

  it("an item's lengths are tokens, and its height is worked out from them", () => {
    expect(CARD_ITEM_HEIGHTS_PX).toEqual({ full: 96, compact: 74, line: 28 });
    // Each height is the outline, the one padding twice, and the bands: no
    // fixed height can cancel a change to a padding or a band.
    const frame = 2 * CARD_ITEM_BORDER_PX + 2 * CARD_ITEM_PADDING_Y_PX;
    expect(CARD_ITEM_HEIGHTS_PX.full).toBe(
      frame + CARD_ITEM_TITLE_BAND_PX + CARD_ITEM_DESCRIPTION_BAND_PX + CARD_ITEM_META_BAND_PX,
    );
    expect(CARD_ITEM_HEIGHTS_PX.compact).toBe(
      frame + CARD_ITEM_TITLE_BAND_PX + CARD_ITEM_COMPACT_BAND_GAP_PX + CARD_ITEM_META_BAND_PX,
    );
    expect(CARD_ITEM_HEIGHTS_PX.line).toBe(CARD_ITEM_LINE_BAND_PX);
    expect(CARD_ITEM_DESCRIPTION_BAND_PX).toBe(
      CARD_ITEM_DESCRIPTION_LINES * CARD_ITEM_DESCRIPTION_LINE_PX,
    );
    const item = fs.readFileSync(path.join(SRC, "shell/CardItem.tsx"), "utf8");
    for (const token of [
      "CARD_ITEM_HEIGHT_PX",
      "CARD_ITEM_COMPACT_HEIGHT_PX",
      "CARD_ITEM_LINE_HEIGHT_PX",
    ]) {
      expect(item).toContain(`height: \`\${${token}}px\``);
    }
    // Nothing is typed in the item: no length of its own.
    expect(item).not.toMatch(/\d+(\.\d+)?(px|rem|em)\b/);
    const tokensFile = fs.readFileSync(path.join(SRC, "shell/cardItemTokens.ts"), "utf8");
    expect(tokensFile).not.toMatch(/CARD_ITEM(_COMPACT|_LINE)?_HEIGHT_PX = \d/);
  });

  it("the space under an item's last band is the space over its first: one padding, and no slack in a band", () => {
    // One padding token, top and bottom, and it is Fluent's.
    expect(CARD_ITEM_PADDING_Y_PX).toBe(parseInt(webLightTheme.spacingVerticalM, 10));
    expect(webLightTheme.spacingVerticalM).toBe(`${CARD_ITEM_PADDING_Y_PX}px`);
    const item = fs.readFileSync(path.join(SRC, "shell/CardItem.tsx"), "utf8");
    expect(item.match(/paddingTop: tokens\.spacingVerticalM,/g)).toHaveLength(2);
    expect(item.match(/paddingBottom: tokens\.spacingVerticalM,/g)).toHaveLength(2);
    expect(item.match(/paddingTop:/g)).toHaveLength(3);
    expect(item.match(/paddingBottom:/g)).toHaveLength(3);
    expect(item).not.toMatch(/padding: /);
    // The title's line is its band, and the meta band is a small badge's
    // height, which is a caption's line: each band's content fills it.
    expect(item).toContain("lineHeight: `${CARD_ITEM_TITLE_BAND_PX}px`");
    expect(item).toContain("height: `${CARD_ITEM_META_BAND_PX}px`");
    expect(CARD_ITEM_META_BAND_PX).toBe(16);
    expect(CARD_ITEM_META_BAND_PX).toBe(parseInt(webLightTheme.lineHeightBase200, 10));
    // So over the title and under the badges there is the padding and the outline, and no more.
    const over = CARD_ITEM_BORDER_PX + CARD_ITEM_PADDING_Y_PX;
    const under = CARD_ITEM_PADDING_Y_PX + CARD_ITEM_BORDER_PX;
    expect(over).toBe(under);
    expect(over).toBe(13);
  });

  it("the space between items is the collection's: an item has no margin, and the list owns the gap", () => {
    const item = fs.readFileSync(path.join(SRC, "shell/CardItem.tsx"), "utf8");
    expect(item).not.toMatch(/margin\w*["']?\s*:/i);
    // Nor does the frame, or a list panel's root: a panel is spaced by what holds it.
    const frameText = fs.readFileSync(path.join(SRC, FRAME), "utf8");
    expect(frameText).not.toMatch(/margin\w*["']?\s*:/i);
    const itemTokens = fs.readFileSync(path.join(SRC, "shell/cardItemTokens.ts"), "utf8");
    expect(itemTokens).not.toMatch(/export const \w*(GAPS|MARGIN)\w*/);
    expect(cardListGapPx).toEqual({ full: 4, compact: 8, line: 0 });
    expect(cardListPaddingTopPx).toEqual(cardListGapPx);
    expect(cardListPaddingTop).toEqual(cardListGap);
    const panel = fs.readFileSync(path.join(SRC, "shell/kinds/ListPanel.tsx"), "utf8");
    // One wrapper, a real list, findable by class and attribute, wearing the tokens.
    expect(panel.match(/<ul\s/g)).toHaveLength(1);
    expect(panel.match(/<li\s/g)).toHaveLength(1);
    expect(panel).toMatch(/<ul\s[^>]*role="list"/);
    expect(panel).toContain('export const CARD_LIST_CLASS = "cardList";');
    expect(panel).toContain('data-card-list=""');
    for (const size of ["full", "compact", "line"]) {
      expect(panel).toContain(`rowGap: cardListGap.${size}`);
      expect(panel).toContain(`paddingTop: cardListPaddingTop.${size}`);
    }
    // The items are drawn inside it and nowhere else.
    expect(panel.match(/<(CardItem|CompactItem|LineItem)\b/g)).toHaveLength(3);
  });

  it("the filter rows sit in one wrapper whose gap spaces them: a row has no margin, and no tint of its own", () => {
    expect(filterRowGapPx).toBe(4);
    const panel = fs.readFileSync(path.join(SRC, "shell/kinds/ListPanel.tsx"), "utf8");
    expect(panel.match(/data-panel-filters/g)).toHaveLength(1);
    expect(panel).toContain("rowGap: filterRowGap,");
    // The only margins in the kind are the list's reset to none.
    expect(panel.match(/margin\w*:\s*[^0\s]/g)).toBeNull();
    // A row of chips is its label and its chips: every row looks alike.
    const sf = ts.createSourceFile("ListPanel.tsx", panel, ts.ScriptTarget.Latest, true);
    const fields = (name: string) =>
      sf.statements
        .filter(ts.isInterfaceDeclaration)
        .find((d) => d.name.text === name)!
        .members.map((m) => (m.name as ts.Identifier).text);
    expect(fields("FilterRow")).toEqual(["label", "chips"]);
    expect(fields("FilterChip")).toEqual(["id", "label", "count", "active", "onSelect"]);
    expect(panel).not.toMatch(/appearance=\{row/);
  });

  it("every spacing value in the panel layer is a Fluent spacing token on the 4 px grid, and no length is typed", () => {
    // The panel layer: the item, the kinds, the frame and the layout tokens.
    const layer = Array.from(facts.keys()).filter(
      (file) =>
        file === "shell/CardItem.tsx" ||
        file === FRAME ||
        file === "shell/layoutTokens.ts" ||
        file.startsWith(KINDS_DIR),
    );
    expect(layer).toEqual(expect.arrayContaining(["shell/kinds/ListPanel.tsx", FRAME]));
    const theme = webLightTheme as unknown as Record<string, string>;
    const SPACING = /^(margin|padding|gap|rowGap|columnGap)/;
    const offGrid: string[] = [];
    const typed: string[] = [];
    for (const file of layer) {
      const text = fs.readFileSync(path.join(SRC, file), "utf8");
      const sf = ts.createSourceFile(file, text, ts.ScriptTarget.Latest, true, ts.ScriptKind.TSX);
      const at = (n: ts.Node) =>
        `${file}:${sf.getLineAndCharacterOfPosition(n.getStart()).line + 1}`;
      const visit = (node: ts.Node) => {
        // A spacing property takes a token (or a name that holds one), or 0: never a typed length.
        if (
          ts.isPropertyAssignment(node) &&
          (ts.isIdentifier(node.name) || ts.isStringLiteral(node.name)) &&
          SPACING.test(node.name.text)
        ) {
          const value = node.initializer;
          const zero = ts.isNumericLiteral(value) && value.text === "0";
          const name =
            ts.isPropertyAccessExpression(value) ||
            ts.isIdentifier(value) ||
            ts.isElementAccessExpression(value);
          if (!zero && !name) typed.push(`${at(node)}: ${node.getText(sf).slice(0, 60)}`);
        }
        // Every Fluent spacing token named in the layer is a multiple of 4 px.
        if (
          ts.isPropertyAccessExpression(node) &&
          ts.isIdentifier(node.expression) &&
          node.expression.text === "tokens" &&
          /^spacing/.test(node.name.text)
        ) {
          const px = parseInt(theme[node.name.text], 10);
          if (!(px > 0 && px % 4 === 0)) offGrid.push(`${at(node)}: ${node.name.text} is ${px}px`);
        }
        ts.forEachChild(node, visit);
      };
      visit(sf);
    }
    expect(typed).toEqual([]);
    expect(offGrid).toEqual([]);

    // Each number kept for the sums is its token's length, and on the grid.
    const tokenPx = (value: string) =>
      value === "0" ? 0 : parseInt(theme[/^var\(--(\w+)\)$/.exec(value)![1]], 10);
    for (const size of ["full", "compact", "line"] as const) {
      expect(tokenPx(cardListGap[size])).toBe(cardListGapPx[size]);
      expect(tokenPx(cardListPaddingTop[size])).toBe(cardListPaddingTopPx[size]);
    }
    expect(tokenPx(filterRowGap)).toBe(filterRowGapPx);
    expect(theme.spacingVerticalM).toBe(`${CARD_ITEM_PADDING_Y_PX}px`);
    expect(theme.spacingVerticalS).toBe(`${CARD_ITEM_COMPACT_BAND_GAP_PX}px`);
    for (const px of [
      ...Object.values(cardListGapPx),
      ...Object.values(cardListPaddingTopPx),
      filterRowGapPx,
      CARD_ITEM_PADDING_Y_PX,
      CARD_ITEM_COMPACT_BAND_GAP_PX,
    ]) {
      expect(px % 4).toBe(0);
    }
    // Not spacing, so not held to the grid: the bands are content sizes -- the
    // title's line (24), a description line (15) and a badge's height (16).
    const item = fs.readFileSync(path.join(SRC, "shell/CardItem.tsx"), "utf8");
    expect(item).toContain("rowGap: tokens.spacingVerticalS,");
  });

  it("an item's data has no density of its own, and a compact item no description", () => {
    const item = fs.readFileSync(path.join(SRC, "shell/CardItem.tsx"), "utf8");
    const sf = ts.createSourceFile("CardItem.tsx", item, ts.ScriptTarget.Latest, true);
    const fields = (name: string) =>
      sf.statements
        .filter(ts.isInterfaceDeclaration)
        .find((d) => d.name.text === name)!
        .members.map((m) => (m.name as ts.Identifier).text);
    expect(fields("CompactItemData")).not.toContain("description");
    for (const data of ["CompactItemData", "CardItemData", "LineItemData"]) {
      expect(fields(data)).not.toContain("density");
    }
  });

  it("a list panel has both bounds, its kind's, whatever the item size; the other kinds have a floor only", () => {
    const text = fs.readFileSync(path.join(SRC, "shell/kinds/ListPanel.tsx"), "utf8");
    // One class for its height, asked for by the kind's name and nothing else:
    // not by density, and no length of its own.
    expect(text.match(/usePanelMinHeightClass\([^)]*\)/g)).toEqual([
      'usePanelMinHeightClass("list")',
    ]);
    expect(text).not.toMatch(/(minHeight|maxHeight|\bheight|min-height|max-height)"?\s*:\s*[`"']/);
    expect(PANEL_MIN_HEIGHT_PX.list).toBe(592);
    expect(PANEL_MAX_HEIGHT_PX).toEqual({ list: 592 });
    const bounds = fs.readFileSync(path.join(SRC, "shell/kinds/panelMinHeight.ts"), "utf8");
    expect(bounds).not.toMatch(/density|compact|cardItem/i);
    // The rule for each kind: list has a max-height, no other kind does.
    const rule = (kind: string) => {
      const rest = bounds.slice(bounds.indexOf(`\n  ${kind}: `) + 3);
      return rest.slice(0, rest.search(/\n {2}[a-z]+: \{|\n\}\);/));
    };
    expect(rule("list")).toContain("minHeight: `${PANEL_MIN_HEIGHT_PX.list}px`");
    expect(rule("list")).toContain("maxHeight: `${PANEL_MAX_HEIGHT_PX.list}px`");
    for (const kind of ["status", "stat", "chart", "scene"]) {
      expect(rule(kind)).toMatch(/minHeight/);
      expect(rule(kind)).not.toMatch(/maxHeight/);
    }
  });

  it("a capped panel holds more than fits in one of two forms, chosen by its kind: a list panel pages, and never scrolls", () => {
    // Every kind with a maximum height names its form.
    expect(Object.keys(PANEL_BODY).sort()).toEqual(Object.keys(PANEL_MAX_HEIGHT_PX).sort());
    for (const form of Object.values(PANEL_BODY)) expect(["paged", "scroll"]).toContain(form);
    expect(PANEL_BODY.list).toBe("paged");
    const text = fs.readFileSync(path.join(SRC, "shell/kinds/ListPanel.tsx"), "utf8");
    // Paged: the frame's scroll area is not asked for, nothing scrolls up and
    // down, and the page size is the shell's sum over the panel's chrome.
    expect(text).not.toMatch(/\bscrollable\b/);
    expect(text).not.toMatch(/overflowY|overflow:\s/);
    expect(text).toMatch(/data-panel-body=\{PANEL_BODY\.list\}/);
    expect(text).toMatch(/listPageSize\(chrome\)/);
    // The scroll form is PanelFrame's own `scrollable`, and nothing else's.
    const frame = fs.readFileSync(path.join(SRC, FRAME), "utf8");
    expect(frame).toMatch(/scrollable\?: boolean/);
  });

  it("the foot sits at a panel's bottom edge: the frame's body grows, in one rule every kind inherits", () => {
    const frame = fs.readFileSync(path.join(SRC, FRAME), "utf8");
    // One body rule that grows, worn by the body of a frame that is not a grid.
    expect(frame).toMatch(/\n {2}body: \{[^}]*flexGrow: 1,/);
    expect(frame.match(/styles\.body\b/g)).toHaveLength(1);
    // The grid form's body row is the flexible one.
    expect(frame).toContain('gridTemplateRows: "auto auto 1fr auto"');
    // No kind or panel pins a foot of its own.
    const own = Array.from(facts.keys()).filter(
      (file) =>
        file !== FRAME &&
        (file.startsWith(KINDS_DIR) || (facts.get(file)?.kinds.length ?? 0) > 0) &&
        /marginTop:\s*"auto"/.test(fs.readFileSync(path.join(SRC, file), "utf8")),
    );
    expect(own).toEqual([]);
  });

  it("a panel reads as named slots: the names are defined once, and the body is one of them", () => {
    expect([...PANEL_SLOTS]).toEqual(["header", "info", "actions", "filters", "body", "foot"]);
    const frame = fs.readFileSync(path.join(SRC, FRAME), "utf8");
    // The frame takes the body by name, or as the default slot, never both.
    expect(frame).toMatch(/body\?: ReactNode;\s*children\?: never;/);
    expect(frame).toMatch(/body\?: never;[\s\S]{0,80}children\?: ReactNode;/);
    // A kind fills the body by name: it hands the frame no children.
    for (const file of Array.from(facts.keys()).filter((f) => f.startsWith(KINDS_DIR))) {
      const text = fs.readFileSync(path.join(SRC, file), "utf8");
      if (!/<PanelFrame\b/.test(text)) continue;
      expect(text).toMatch(/\n\s+body=\{/);
      expect(text).not.toMatch(/<\/PanelFrame>/);
    }
  });

  it("the compact panels are My Work and GitHub Issues, and no other", () => {
    const compact = Array.from(facts.keys())
      .filter((file) => !file.startsWith(KINDS_DIR))
      .filter((file) => /density="compact"/.test(fs.readFileSync(path.join(SRC, file), "utf8")));
    expect(compact).toEqual(["modules/ado/MyWork.tsx"]);
  });

  it("the card item and the kinds carry no tooltip", () => {
    for (const file of ["shell/CardItem.tsx", "shell/kinds/ListPanel.tsx"]) {
      const text = fs.readFileSync(path.join(SRC, file), "utf8");
      expect(text).not.toMatch(/\bTooltip\b/);
    }
  });
});

describe("the checker has teeth", () => {
  const panel = (body: string, imports = "") =>
    readFile(
      "modules/x/Thing.tsx",
      `import { ListPanel } from "../../shell/kinds/ListPanel";\n${imports}\nexport const Thing = () => (${body});\n`,
    ).findings;

  it("a full panel's item may carry a description", () => {
    expect(
      panel(
        `<ListPanel title="T" items={[]} item={() => ({ title: "T", description: "more" })} empty={e} />`,
      ),
    ).toEqual([]);
  });

  it("a clean panel file has no finding", () => {
    expect(panel(`<ListPanel title="Things" items={[]} item={toItem} empty={none} />`)).toEqual([]);
  });

  it.each([
    [
      "a height",
      `<ListPanel title="T" items={[]} item={i} empty={e} height={600} />`,
      /sets height/,
    ],
    ["a max-height in a style", `<div style={{ maxHeight: 300 }} />`, /sets maxHeight/],
    ["a min-height in a rule", `({ "min-height": "10em" })`, /sets min-height/],
    ["a px length", `({ width: "200px" })`, /writes a length/],
    ["a vh length", `({ top: "40vh" })`, /writes a length/],
    ["a typed page size", `((PAGE_SIZE = 5) => PAGE_SIZE)`, /names a page size/],
    [
      "a pageSize prop",
      `<ListPanel title="T" items={[]} item={i} empty={e} pageSize={3} />`,
      /names a page size/,
    ],
    ["a linked title", `<a href="/x">Title</a>`, /draws <a>/],
    [
      "an inline subhead used as a filter",
      `<section><h3>Design (5)</h3></section>`,
      /draws <section>/,
    ],
    ["a density set per item", `({ title: "T", density: "compact" })`, /sets density on an item/],
    [
      "a description on a compact panel's item",
      `<ListPanel title="T" density="compact" items={[]} item={() => ({ title: "T", description: "more" })} empty={e} />`,
      /a compact item has none/,
    ],
    [
      "a body helper sentence",
      `<ListPanel title="T" items={[]} item={i} empty={e}><p>These are the things.</p></ListPanel>`,
      /gives ListPanel a body/,
    ],
  ])("%s is refused", (_what, body, finding) => {
    expect(panel(body).join("\n")).toMatch(finding);
  });

  it.each([
    ["a tooltip", `import { Tooltip } from "@fluentui/react-components";`, /imports Tooltip/],
    ["a link", `import { Link } from "@fluentui/react-components";`, /imports Link/],
    ["a subhead", `import { Subtitle2 } from "@fluentui/react-components";`, /imports Subtitle2/],
    ["an item of its own", `import { CardItem } from "../../shell/CardItem";`, /imports CardItem/],
    [
      "a second exposed action",
      `import { CardActions } from "../../shared/CardActions";`,
      /imports CardActions/,
    ],
  ])("%s is refused", (_what, imports, finding) => {
    expect(
      panel(`<ListPanel title="T" items={[]} item={i} empty={e} />`, imports).join("\n"),
    ).toMatch(finding);
  });

  it("the imports that put a file on a list are seen", () => {
    const f = readFile(
      "modules/x/Old.tsx",
      [
        `import { Card, Badge } from "@fluentui/react-components";`,
        `import { PanelFrame } from "../../shared/PanelFrame";`,
        `import { Pagination } from "../../shared/Pagination";`,
        `import { usePagination } from "../../hooks/usePagination";`,
      ].join("\n"),
    );
    expect([f.importsCard, f.importsFrame, f.importsPager, f.kinds]).toEqual([
      true,
      true,
      true,
      [],
    ]);
  });

  it("a type-only import is not a use", () => {
    const f = readFile(
      "modules/x/Types.tsx",
      `import type { CardItemData } from "../../shell/CardItem";\nimport { ListPanel } from "../../shell/kinds/ListPanel";\nimport { type CardAction, ROW } from "../../shared/CardActions";`,
    );
    expect(f.findings).toEqual([]);
  });

  it("ScenePanel outside the Lounge is refused, and allowed inside it", () => {
    const text = `import { ScenePanel } from "../../shell/kinds/ScenePanel";`;
    expect(readFile("modules/ado/Face.tsx", text).findings.join("\n")).toMatch(/the Lounge's/);
    expect(readFile("modules/lounge/Go.tsx", text).findings).toEqual([]);
  });
});
