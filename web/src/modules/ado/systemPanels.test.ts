import fs from "node:fs";
import path from "node:path";
import ts from "typescript";

/**
 * Every System panel's kind, read from the source.
 *
 * The System page draws the panels `systemCards` (index.tsx) returns. A panel
 * there that draws a list -- a `.map()` turning records into elements -- is a
 * ListPanel, so it pages in a pinned foot and stands the list kind's one height
 * beside its neighbour. A panel that is not a ListPanel and draws a list fails
 * here, unless it is named below with its reason: a short, fixed set of rows --
 * status rows or a table of figures -- that the status or stat kind will draw.
 */

const HERE = __dirname;

/** Not a ListPanel, and drawing a fixed set of rows: why that is right. */
const FIXED_ROWS: Record<string, string> = {
  EnvCard: "the machine's checks: a fixed set of status rows, the status kind's",
  ModulesCard: "the add-ons: one fixed status row each, the status kind's",
  BurnCard: "the week's figures: a table of a few models and their notes, the stat kind's",
};

function source(file: string): ts.SourceFile {
  const text = fs.readFileSync(file, "utf8");
  return ts.createSourceFile(file, text, ts.ScriptTarget.Latest, true, ts.ScriptKind.TSX);
}

/** The panels systemCards returns, as component name -> file. */
function systemPanels(): Map<string, string> {
  const index = source(path.join(HERE, "index.tsx"));
  const imports = new Map<string, string>();
  const names = new Set<string>();
  const visit = (node: ts.Node, inSystem: boolean) => {
    if (ts.isImportDeclaration(node) && ts.isStringLiteral(node.moduleSpecifier)) {
      const from = node.moduleSpecifier.text;
      const bindings = node.importClause?.namedBindings;
      if (bindings && ts.isNamedImports(bindings)) {
        for (const el of bindings.elements) imports.set(el.name.text, from);
      }
    }
    const here = inSystem || (ts.isFunctionDeclaration(node) && node.name?.text === "systemCards");
    if (here && (ts.isJsxSelfClosingElement(node) || ts.isJsxOpeningElement(node))) {
      names.add(node.tagName.getText(index));
    }
    ts.forEachChild(node, (c) => visit(c, here));
  };
  visit(index, false);
  const out = new Map<string, string>();
  for (const name of names) {
    const from = imports.get(name);
    if (from?.startsWith(".")) out.set(name, path.join(HERE, `${from}.tsx`));
  }
  return out;
}

/** Whether a file fills ListPanel, and whether it maps records to elements. */
function facts(file: string): { listPanel: boolean; mapsToJsx: boolean } {
  const sf = source(file);
  let listPanel = false;
  let mapsToJsx = false;
  const returnsJsx = (fn: ts.Node): boolean => {
    let found = false;
    const look = (n: ts.Node) => {
      if (ts.isJsxElement(n) || ts.isJsxSelfClosingElement(n) || ts.isJsxFragment(n)) found = true;
      else ts.forEachChild(n, look);
    };
    look(fn);
    return found;
  };
  const visit = (node: ts.Node) => {
    if (
      (ts.isJsxSelfClosingElement(node) || ts.isJsxOpeningElement(node)) &&
      node.tagName.getText(sf) === "ListPanel"
    ) {
      listPanel = true;
    }
    if (
      ts.isCallExpression(node) &&
      ts.isPropertyAccessExpression(node.expression) &&
      node.expression.name.text === "map" &&
      node.arguments.length > 0 &&
      (ts.isArrowFunction(node.arguments[0]) || ts.isFunctionExpression(node.arguments[0])) &&
      returnsJsx(node.arguments[0])
    ) {
      mapsToJsx = true;
    }
    ts.forEachChild(node, visit);
  };
  visit(sf);
  return { listPanel, mapsToJsx };
}

describe("the System page's panels", () => {
  const panels = systemPanels();

  it("finds the panels systemCards draws", () => {
    expect([...panels.keys()].sort()).toEqual(
      ["BurnCard", "EnvCard", "ModulesCard", "TestHealth", "ToolkitLog"].sort(),
    );
  });

  it("draws every list in a ListPanel, but for the fixed rows named with a reason", () => {
    const offKind = [...panels]
      .filter(([name, file]) => {
        const f = facts(file);
        return f.mapsToJsx && !f.listPanel && !(name in FIXED_ROWS);
      })
      .map(([name]) => name);
    expect(offKind).toEqual([]);
  });

  it("names no fixed-rows exemption that is a ListPanel, or that draws no rows", () => {
    for (const [name, reason] of Object.entries(FIXED_ROWS)) {
      const file = panels.get(name);
      expect(file).toBeDefined();
      const f = facts(file!);
      expect({ name, listPanel: f.listPanel, mapsToJsx: f.mapsToJsx }).toEqual({
        name,
        listPanel: false,
        mapsToJsx: true,
      });
      expect(reason.length).toBeGreaterThan(10);
    }
  });

  it("puts Test Health and the Log on the list kind", () => {
    expect(facts(panels.get("TestHealth")!).listPanel).toBe(true);
    expect(facts(panels.get("ToolkitLog")!).listPanel).toBe(true);
  });
});
