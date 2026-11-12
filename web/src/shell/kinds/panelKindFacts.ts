import fs from "node:fs";
import ts from "typescript";

/**
 * What a source file says about its kind, read with the TypeScript parser: for
 * the tests that hold every list to ListPanel (modulePanels.test.ts over every
 * module, systemPanels.test.ts over the System page). Not for the app.
 */
export interface PanelKindFacts {
  /** The file fills ListPanel. */
  listPanel: boolean;
  /** The file draws rows: a `.map()` that turns entries into elements. */
  mapsToJsx: boolean;
  /** The file draws a panel or a page: it imports PanelFrame or a Fluent Card. */
  framed: boolean;
}

function parse(file: string, text: string): ts.SourceFile {
  return ts.createSourceFile(file, text, ts.ScriptTarget.Latest, true, ts.ScriptKind.TSX);
}

/** Read one file's text. `file` only names it. */
export function panelKindFactsOf(file: string, text: string): PanelKindFacts {
  const sf = parse(file, text);
  const out: PanelKindFacts = { listPanel: false, mapsToJsx: false, framed: false };
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
    if (ts.isJsxSelfClosingElement(node) || ts.isJsxOpeningElement(node)) {
      const tag = node.tagName.getText(sf);
      if (tag === "ListPanel") out.listPanel = true;
      if (tag === "PanelFrame" || tag === "Card") out.framed = true;
    }
    if (
      ts.isCallExpression(node) &&
      ts.isPropertyAccessExpression(node.expression) &&
      node.expression.name.text === "map" &&
      node.arguments.length > 0 &&
      (ts.isArrowFunction(node.arguments[0]) || ts.isFunctionExpression(node.arguments[0])) &&
      returnsJsx(node.arguments[0])
    ) {
      out.mapsToJsx = true;
    }
    ts.forEachChild(node, visit);
  };
  visit(sf);
  return out;
}

/** Read one file from disk. */
export function panelKindFacts(file: string): PanelKindFacts {
  return panelKindFactsOf(file, fs.readFileSync(file, "utf8"));
}
