import fs from "node:fs";
import path from "node:path";
import ts from "typescript";
import { render } from "@testing-library/react";
import { Tab, TabList } from "@fluentui/react-components";
import { TAB_ROWS_CLASS, TabRows } from "./TabRows";
import {
  controlRowsSpace,
  filtersSpaceBelow,
  tabRowGap,
  tabRowGapPx,
  tabRowsPadding,
  tabRowsPaddingPx,
} from "../shell/layoutTokens";
import { tokenPx } from "../shell/pageRowsAssert";

/**
 * The tab rows' wrapper, held as structure.
 *
 * Every in-page tab row sits in one wrapper, `TabRows`, which owns the space:
 * padding above and below, and a gap between two rows stacked in it. A tab row
 * has no margin of its own, so a `TabList` takes no className and no style.
 */

const SRC = path.join(__dirname, "..");

function sourceFiles(dir: string): string[] {
  return fs.readdirSync(dir, { withFileTypes: true }).flatMap((e) => {
    const full = path.join(dir, e.name);
    if (e.isDirectory()) return sourceFiles(full);
    return /\.tsx$/.test(e.name) && !/\.test\.tsx$/.test(e.name) ? [full] : [];
  });
}

function tagName(node: ts.JsxElement | ts.JsxSelfClosingElement): string {
  const tag = ts.isJsxElement(node) ? node.openingElement.tagName : node.tagName;
  return tag.getText();
}

function attributesOf(node: ts.JsxElement | ts.JsxSelfClosingElement): string[] {
  const attrs = ts.isJsxElement(node) ? node.openingElement.attributes : node.attributes;
  return attrs.properties.flatMap((p) => (ts.isJsxAttribute(p) ? [p.name.getText()] : []));
}

/** Every TabList in the source, with whether a TabRows holds it and its props. */
function tabLists(): { file: string; wrapped: boolean; attrs: string[] }[] {
  const out: { file: string; wrapped: boolean; attrs: string[] }[] = [];
  for (const file of sourceFiles(SRC)) {
    const text = fs.readFileSync(file, "utf8");
    if (!text.includes("<TabList")) continue;
    const sf = ts.createSourceFile(file, text, ts.ScriptTarget.Latest, true, ts.ScriptKind.TSX);
    const visit = (node: ts.Node) => {
      if (
        (ts.isJsxElement(node) || ts.isJsxSelfClosingElement(node)) &&
        tagName(node) === "TabList"
      ) {
        let up: ts.Node | undefined = node.parent;
        let wrapped = false;
        while (up && !wrapped) {
          if (ts.isJsxElement(up) && tagName(up) === "TabRows") wrapped = true;
          up = up.parent;
        }
        out.push({ file: path.relative(SRC, file), wrapped, attrs: attributesOf(node) });
      }
      ts.forEachChild(node, visit);
    };
    visit(sf);
  }
  return out;
}

describe("TabRows", () => {
  it("is one marked wrapper with its rows directly inside", () => {
    const { container } = render(
      <TabRows>
        <TabList aria-label="One">
          <Tab value="a">A</Tab>
        </TabList>
        <TabList aria-label="Two">
          <Tab value="b">B</Tab>
        </TabList>
      </TabRows>,
    );
    const wrapper = container.querySelector<HTMLElement>("[data-tab-rows]");
    expect(wrapper).not.toBeNull();
    expect(wrapper!.classList.contains(TAB_ROWS_CLASS)).toBe(true);
    expect(Array.from(wrapper!.children).map((c) => c.getAttribute("aria-label"))).toEqual([
      "One",
      "Two",
    ]);
  });

  it("pads top and bottom with the control rows' one space, and spaces two rows on the 4 px grid", () => {
    // Tabs and filter chips read as one family: the same breathing room.
    expect(tabRowsPadding).toBe(controlRowsSpace);
    expect(filtersSpaceBelow).toBe(controlRowsSpace);
    expect(tokenPx(tabRowsPadding)).toBe(tabRowsPaddingPx);
    expect(tabRowsPaddingPx % 4).toBe(0);
    expect(tokenPx(tabRowGap)).toBe(tabRowGapPx);
    expect(tabRowGapPx % 4).toBe(0);
  });

  it("holds every TabList in the app, and none carries a class or a style of its own", () => {
    const found = tabLists();
    expect(found.length).toBeGreaterThan(0);
    expect(found.filter((t) => !t.wrapped).map((t) => t.file)).toEqual([]);
    expect(
      found
        .filter((t) => t.attrs.includes("className") || t.attrs.includes("style"))
        .map((t) => t.file),
    ).toEqual([]);
  });
});
