/**
 * Holds web/COMPONENTS.md to the code.
 *
 * The shared layer's files are listed below. For them the document and the
 * source must agree three ways: every value they export has a `## \`Name\``
 * section, every section names something they export, and each section's props
 * table has exactly the keys of the exported props type (or, for a function
 * with no props type, of its parameters). The keys are read with the TypeScript
 * compiler, so a prop added to a type without its row fails here.
 *
 * It also holds the props types themselves: no index signature and no `any`.
 * (`any` anywhere under shell/ and shared/ is refused by ESLint.)
 */
import fs from "node:fs";
import path from "node:path";
import ts from "typescript";

const WEB = path.resolve(__dirname, "..", "..");
const DOC = path.join(WEB, "COMPONENTS.md");

/** The files whose exports are the shared layer this document covers. */
const SHARED_FILES = [
  "src/shared/PageCard.tsx",
  "src/shared/CardActions.tsx",
  "src/shared/DialogDismiss.tsx",
  "src/shared/ConfirmDialog.tsx",
  "src/shared/EmptyState.tsx",
  "src/shared/RefreshButton.tsx",
  "src/shared/CreateButton.tsx",
  "src/shared/FilterBadge.tsx",
  "src/shared/StatTile.tsx",
  "src/shared/StatusMessage.tsx",
  "src/shared/InfoTip.tsx",
  "src/shared/HairlineDivider.tsx",
  "src/shell/lazy.tsx",
];

/**
 * Where a section's table comes from when it is not "the parameters of the
 * function". `type` is an exported props type; `none` is a constant, which
 * has no table.
 */
const SOURCES: Record<string, { type: string } | "none"> = {
  PageCard: { type: "PageCardProps" },
  CardActions: { type: "CardActionsProps" },
  CardAction: { type: "CardAction" },
  ROW: "none",
  ROW_SYNONYMS: "none",
  ConfirmDialog: { type: "ConfirmDialogProps" },
  lazyFallback: "none",
  EmptyState: { type: "EmptyMessage" },
  RefreshButton: { type: "RefreshButtonProps" },
  CreateButton: { type: "CreateButtonProps" },
  FilterBadge: { type: "FilterBadgeProps" },
  StatTiles: { type: "StatTilesProps" },
  StatTile: { type: "StatTileProps" },
  StatusMessage: { type: "StatusMessageProps" },
  InfoTip: { type: "InfoTipProps" },
  HairlineDivider: { type: "HairlineDividerProps" },
};

const doc = fs.readFileSync(DOC, "utf8");

/** Section name -> its body, for each `## \`Name\`` heading. */
function sections(text: string): Map<string, string> {
  const out = new Map<string, string>();
  const parts = text.split(/^## /m).slice(1);
  for (const part of parts) {
    const m = /^`([^`]+)`\s*\n/.exec(part);
    if (m) out.set(m[1], part.slice(m[0].length));
  }
  return out;
}

/** The first column of the section's props table, or null when there is none. */
function tableKeys(body: string): string[] | null {
  const lines = body.split("\n");
  const start = lines.findIndex((l) => /^\|\s*Prop\s*\|/.test(l));
  if (start < 0) return null;
  const keys: string[] = [];
  for (const line of lines.slice(start + 2)) {
    if (!line.startsWith("|")) break;
    const first = line.split("|")[1].trim().replace(/^`|`$/g, "");
    keys.push(first);
  }
  return keys;
}

const config = ts.readConfigFile(path.join(WEB, "tsconfig.json"), ts.sys.readFile);
const parsed = ts.parseJsonConfigFileContent(config.config, ts.sys, WEB);
const program = ts.createProgram(
  SHARED_FILES.map((f) => path.join(WEB, f)),
  { ...parsed.options, noEmit: true },
);
const checker = program.getTypeChecker();

interface Exported {
  symbol: ts.Symbol;
  isValue: boolean;
  file: string;
}

function exportsOf(): Map<string, Exported> {
  const out = new Map<string, Exported>();
  for (const file of SHARED_FILES) {
    const sf = program.getSourceFile(path.join(WEB, file));
    if (!sf) throw new Error(`not in the program: ${file}`);
    const mod = checker.getSymbolAtLocation(sf);
    if (!mod) throw new Error(`no module symbol: ${file}`);
    for (const sym of checker.getExportsOfModule(mod)) {
      const real = sym.flags & ts.SymbolFlags.Alias ? checker.getAliasedSymbol(sym) : sym;
      out.set(sym.getName(), {
        symbol: real,
        isValue: (real.flags & ts.SymbolFlags.Value) !== 0,
        file,
      });
    }
  }
  return out;
}

/** The type's own keys: those declared in this repo, not inherited from a library. */
function ownKeys(type: ts.Type): string[] {
  return checker
    .getPropertiesOfType(type)
    .filter((p) =>
      (p.declarations ?? []).some((d) => !d.getSourceFile().fileName.includes("node_modules")),
    )
    .map((p) => p.getName());
}

function paramNames(symbol: ts.Symbol): string[] {
  const decl = symbol.valueDeclaration ?? symbol.declarations?.[0];
  if (!decl) return [];
  const sigs = checker.getTypeOfSymbolAtLocation(symbol, decl).getCallSignatures();
  return sigs.length ? sigs[0].parameters.map((p) => p.getName()) : [];
}

const exported = exportsOf();
const docSections = sections(doc);

/** What the table should list for an export, or null when it should have none. */
function expectedKeys(name: string): string[] | null {
  const source = SOURCES[name];
  if (source === "none") return null;
  const e = exported.get(name)!;
  if (source) {
    const t = exported.get(source.type);
    if (!t) throw new Error(`${name}: props type ${source.type} is not exported`);
    return ownKeys(checker.getDeclaredTypeOfSymbol(t.symbol));
  }
  return paramNames(e.symbol);
}

const sorted = (xs: string[]) => [...xs].sort();

describe("web/COMPONENTS.md and the shared layer", () => {
  it("has a section for every value the shared files export", () => {
    const missing = [...exported]
      .filter(([n, e]) => e.isValue && !docSections.has(n))
      .map(([n]) => n);
    expect(missing).toEqual([]);
  });

  it("has no section that is not an export", () => {
    const extra = [...docSections.keys()].filter((n) => !exported.has(n));
    expect(extra).toEqual([]);
  });

  it("names a real export for every entry in the source table", () => {
    const unknown = Object.keys(SOURCES).filter((n) => !exported.has(n));
    expect(unknown).toEqual([]);
  });

  const names = [...docSections.keys()].filter((n) => exported.has(n));
  it.each(names)("%s: the props table and the type's keys agree", (name) => {
    const want = expectedKeys(name);
    const got = tableKeys(docSections.get(name)!);
    if (want === null) {
      expect(got).toBeNull();
      return;
    }
    if (want.length === 0) {
      expect(got ?? []).toEqual([]);
      return;
    }
    expect(got).not.toBeNull();
    const inDocOnly = got!.filter((k) => !want.includes(k));
    const inCodeOnly = want.filter((k) => !got!.includes(k));
    expect({ inDocOnly, inCodeOnly, duplicates: got!.length - new Set(got).size }).toEqual({
      inDocOnly: [],
      inCodeOnly: [],
      duplicates: 0,
    });
    expect(sorted(got!)).toEqual(sorted(want));
  });

  it("types every props type without an index signature or an any", () => {
    const problems: string[] = [];
    for (const source of Object.values(SOURCES)) {
      if (source === "none") continue;
      const type = checker.getDeclaredTypeOfSymbol(exported.get(source.type)!.symbol);
      if (checker.getIndexInfosOfType(type).length)
        problems.push(`${source.type}: index signature`);
      for (const prop of checker.getPropertiesOfType(type)) {
        const decl = prop.valueDeclaration ?? prop.declarations?.[0];
        if (!decl || decl.getSourceFile().fileName.includes("node_modules")) continue;
        if (checker.getTypeOfSymbolAtLocation(prop, decl).flags & ts.TypeFlags.Any) {
          problems.push(`${source.type}.${prop.getName()}: any`);
        }
      }
    }
    expect(problems).toEqual([]);
  });

  it("links only to tests and files that exist", () => {
    const links = [...doc.matchAll(/\]\((?!https?:)([^)#]+)(?:#[^)]*)?\)/g)].map((m) => m[1]);
    const broken = links.filter((l) => !fs.existsSync(path.resolve(path.dirname(DOC), l)));
    expect(broken).toEqual([]);
  });

  it("is linked from web/README.md and docs/ARCHITECTURE.md", () => {
    const readme = fs.readFileSync(path.join(WEB, "README.md"), "utf8");
    const arch = fs.readFileSync(path.join(WEB, "..", "docs", "ARCHITECTURE.md"), "utf8");
    expect(readme).toContain("(COMPONENTS.md)");
    expect(arch).toContain("web/COMPONENTS.md");
  });
});
