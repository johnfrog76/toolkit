/**
 * One vocabulary for every row's menu (#153): the same move reads with the same
 * word, icon and tooltip on every page, and the external link is last with one
 * icon.
 *
 * This reads EVERY source file under src/ -- not a list of pages -- with the
 * TypeScript parser, and holds four things:
 *
 *   1. No row action is written by hand. An object literal with an `icon` and a
 *      `label` is a CardAction typed outside the vocabulary; it is refused, so
 *      every action is `ROW.<move>.action()` or a module's own move.
 *   2. A module's own move (a `defineRowMoves` table) is not a vocabulary move
 *      under another name: its first word is not a vocabulary word, nor a
 *      synonym of one (Retire, Drop, Done, Remove, View...) unless it declares
 *      `differentMove` with why; and its icon is never a vocabulary move's icon.
 *      A word on two records' tables is no longer one record's: it belongs in
 *      the vocabulary.
 *   3. web/README.md lists the vocabulary -- each move's word, icon and tooltip
 *      as ROW holds them -- and every own move by `record.key`, and nothing that
 *      is not in the source.
 *   4. The checker has teeth: run over sources written wrong on purpose, it
 *      finds each one.
 *
 * The vocabulary itself, and how to add to it, is shared/CardActions.tsx.
 */
import fs from "node:fs";
import path from "node:path";
import ts from "typescript";
import { ROW, ROW_SYNONYMS } from "./CardActions";
import type { RowMoveKey } from "./CardActions";

const SRC = path.join(__dirname, "..");
const README = path.join(SRC, "..", "README.md");
const VOCABULARY_FILE = path.join("shared", "CardActions.tsx");

interface OwnMove {
  file: string;
  id: string;
  word: string;
  icon: string;
  differentMove?: string;
}

interface Scan {
  findings: string[];
  own: OwnMove[];
}

const VOCAB_KEYS = Object.keys(ROW) as RowMoveKey[];
const iconName = (key: RowMoveKey) =>
  (ROW[key].icon as unknown as { displayName?: string }).displayName ?? "";
const VOCAB_ICONS = new Map(VOCAB_KEYS.map((k) => [iconName(k), k]));

/** A word's first word, lowercased, with its punctuation off: "Snooze:" is "snooze". */
function firstWord(word: string): string {
  return (word.trim().split(/\s+/)[0] ?? "").toLowerCase().replace(/[^a-z]/g, "");
}
const VOCAB_FIRST = new Map(VOCAB_KEYS.map((k) => [firstWord(ROW[k].word), k]));
const SYNONYM_OF = new Map<string, RowMoveKey>();
for (const k of VOCAB_KEYS) for (const s of ROW_SYNONYMS[k]) SYNONYM_OF.set(s, k);

function propName(p: ts.ObjectLiteralElementLike): string | null {
  if (!p.name) return null;
  if (ts.isIdentifier(p.name) || ts.isStringLiteral(p.name)) return p.name.text;
  return null;
}

function literal(e: ts.Expression | undefined): string | null {
  if (!e) return null;
  if (ts.isStringLiteral(e) || ts.isNoSubstitutionTemplateLiteral(e)) return e.text;
  return null;
}

/** Read one file: hand-written actions, and its `defineRowMoves` tables. */
function scanFile(file: string, text: string, out: Scan): void {
  const kind = file.endsWith(".tsx") ? ts.ScriptKind.TSX : ts.ScriptKind.TS;
  const sf = ts.createSourceFile(file, text, ts.ScriptTarget.Latest, true, kind);
  const at = (n: ts.Node) => `${file}:${sf.getLineAndCharacterOfPosition(n.getStart()).line + 1}`;
  const isVocabulary = file === VOCABULARY_FILE;

  const visit = (node: ts.Node) => {
    if (!isVocabulary && ts.isObjectLiteralExpression(node)) {
      const names = new Set(node.properties.map(propName));
      if (names.has("icon") && names.has("label")) {
        out.findings.push(
          `${at(node)}: a row action written by hand -- build it from ROW.<move>.action() or a defineRowMoves table`,
        );
      }
    }
    if (
      ts.isCallExpression(node) &&
      ts.isIdentifier(node.expression) &&
      node.expression.text === "defineRowMoves" &&
      node.arguments.length === 2
    ) {
      const record = literal(node.arguments[0]);
      const table = node.arguments[1];
      if (record === null || !ts.isObjectLiteralExpression(table)) {
        out.findings.push(
          `${at(node)}: write a defineRowMoves table as a literal, record name first`,
        );
      } else {
        for (const entry of table.properties) {
          const key = propName(entry);
          if (
            !key ||
            !ts.isPropertyAssignment(entry) ||
            !ts.isObjectLiteralExpression(entry.initializer)
          ) {
            out.findings.push(`${at(entry)}: an own move must be a literal { word, icon }`);
            continue;
          }
          const props = new Map(
            entry.initializer.properties
              .filter(ts.isPropertyAssignment)
              .map((p) => [propName(p), p.initializer] as const),
          );
          const word = literal(props.get("word"));
          const icon = props.get("icon");
          if (word === null || !icon || !ts.isIdentifier(icon)) {
            out.findings.push(
              `${at(entry)}: ${record}.${key} -- write its word as a string and its icon as a name`,
            );
            continue;
          }
          out.own.push({
            file: at(entry),
            id: `${record}.${key}`,
            word,
            icon: icon.text,
            differentMove: literal(props.get("differentMove")) ?? undefined,
          });
        }
      }
    }
    ts.forEachChild(node, visit);
  };
  visit(sf);
}

/** The own moves against the vocabulary, and the README against both. */
function judge(scan: Scan, readme: string): string[] {
  const findings = [...scan.findings];
  const seenId = new Map<string, string>();
  const seenWord = new Map<string, string>();
  for (const m of scan.own) {
    const first = firstWord(m.word);
    const vocab = VOCAB_FIRST.get(first);
    if (vocab) {
      findings.push(
        `${m.file}: ${m.id} says "${m.word}" -- that is ROW.${vocab}; build it from the vocabulary`,
      );
    }
    const synonym = SYNONYM_OF.get(first);
    if (synonym && !m.differentMove) {
      findings.push(
        `${m.file}: ${m.id} says "${m.word}" -- that is ${synonym} under another word. Use ROW.${synonym}, or declare differentMove with why it is a different thing`,
      );
    }
    const iconOf = VOCAB_ICONS.get(m.icon);
    if (iconOf) {
      findings.push(
        `${m.file}: ${m.id} wears ${m.icon}, the icon of ROW.${iconOf} -- a different move wears its own icon`,
      );
    }
    if (seenId.has(m.id))
      findings.push(`${m.file}: ${m.id} is declared twice (also ${seenId.get(m.id)})`);
    seenId.set(m.id, m.file);
    const record = m.id.split(".")[0];
    const other = seenWord.get(m.word.toLowerCase());
    if (other && other.split(".")[0] !== record) {
      findings.push(
        `${m.file}: "${m.word}" is on two records (${other}, ${m.id}) -- a move on more than one record belongs in the vocabulary`,
      );
    }
    seenWord.set(m.word.toLowerCase(), m.id);
  }

  // The README's section: the vocabulary table and the own moves' table.
  const start = readme.indexOf("### One vocabulary for row actions");
  if (start < 0)
    return [...findings, "web/README.md has no '### One vocabulary for row actions' section"];
  const rest = readme.slice(start + 1);
  const end = rest.search(/\n#{2,3} /);
  const section = end < 0 ? rest : rest.slice(0, end);
  const rows = section.split("\n").filter((l) => l.startsWith("| `"));
  const rowFor = (id: string) => rows.find((r) => r.startsWith(`| \`${id}\` |`));
  for (const k of VOCAB_KEYS) {
    const row = rowFor(k);
    const want = [ROW[k].word, `\`${iconName(k)}\``, ROW[k].tooltip("{detail}")];
    if (!row || want.some((w) => !row.includes(w))) {
      findings.push(`web/README.md: the vocabulary row for \`${k}\` must read ${want.join(" / ")}`);
    }
  }
  const declared = new Set(scan.own.map((m) => m.id));
  for (const m of scan.own) {
    const row = rowFor(m.id);
    if (!row || !row.includes(m.word) || !row.includes(`\`${m.icon}\``)) {
      findings.push(
        `web/README.md: no row for own move \`${m.id}\` naming "${m.word}" and \`${m.icon}\``,
      );
    } else if (m.differentMove && !row.includes("different move")) {
      findings.push(`web/README.md: \`${m.id}\` is a different move -- its row must say so`);
    }
  }
  for (const r of rows) {
    const id = /^\| `([^`]+)` \|/.exec(r)?.[1] ?? "";
    if (id.includes(".") && !declared.has(id)) {
      findings.push(`web/README.md: \`${id}\` is listed but no defineRowMoves table declares it`);
    }
  }
  return findings;
}

function sourceFiles(dir: string): string[] {
  const out: string[] = [];
  for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
    const p = path.join(dir, e.name);
    if (e.isDirectory()) out.push(...sourceFiles(p));
    else if (/\.tsx?$/.test(e.name) && !/\.test\.tsx?$/.test(e.name) && !e.name.endsWith(".d.ts")) {
      out.push(p);
    }
  }
  return out;
}

function scanTree(): Scan {
  const scan: Scan = { findings: [], own: [] };
  for (const f of sourceFiles(SRC))
    scanFile(path.relative(SRC, f), fs.readFileSync(f, "utf8"), scan);
  return scan;
}

describe("one vocabulary for every row's menu", () => {
  const readme = fs.readFileSync(README, "utf8");
  const scan = scanTree();

  it("finds the product's own moves (the scan is reading the tree)", () => {
    const ids = scan.own.map((m) => m.id);
    for (const id of ["reminder.snooze", "space.retire", "design.graduate", "card.createPr"]) {
      expect(ids).toContain(id);
    }
  });

  it("holds every row menu in the product to the vocabulary, and the README to both", () => {
    expect(judge(scan, readme)).toEqual([]);
  });

  it("names each standard move once, with icons no two moves share", () => {
    expect(VOCAB_KEYS.sort()).toEqual(
      ["archive", "complete", "copy", "delete", "external", "move", "open"].sort(),
    );
    expect(new Set(VOCAB_KEYS.map(iconName)).size).toBe(VOCAB_KEYS.length);
  });

  it("labels the external link 'Open on' and the system's name, with the one icon", () => {
    const gh = ROW.external.action({ detail: "GitHub", href: "https://github.com" });
    const ado = ROW.external.action({ detail: "Azure DevOps", href: "https://dev.azure.com" });
    expect([gh.label, ado.label]).toEqual(["Open on GitHub", "Open on Azure DevOps"]);
    expect(gh.external && ado.external).toBe(true);
    expect(ROW.open.action({ detail: "the note" }).external).toBeUndefined();
  });
});

describe("the vocabulary check has teeth", () => {
  const readme = fs.readFileSync(README, "utf8");
  const tree = scanTree();
  // Each source below is the tree plus ONE wrong row. Every one must be found.
  const wrong: [string, string, RegExp][] = [
    [
      "a hand-written action with a new word for archive",
      `const a = { icon: <ArchiveRegular />, label: "Retire", onClick: () => {} };`,
      /written by hand/,
    ],
    [
      "an own move that is archive under another word",
      `const M = defineRowMoves("goal", { retire: { word: "Retire", icon: HistoryRegular } });`,
      /archive under another word/,
    ],
    [
      "an own move that is open under another word",
      `const M = defineRowMoves("goal", { view: { word: "View goal", icon: EyeRegular } });`,
      /open under another word/,
    ],
    [
      "an own move wearing a vocabulary icon",
      `const M = defineRowMoves("goal", { stash: { word: "Put away", icon: ArchiveRegular } });`,
      /icon of ROW.archive/,
    ],
    [
      "an own move using a vocabulary word",
      `const M = defineRowMoves("goal", { a: { word: "Archive now", icon: BoxRegular } });`,
      /that is ROW.archive/,
    ],
    [
      "an own move the README does not name",
      `const M = defineRowMoves("goal", { celebrate: { word: "Celebrate", icon: PartyRegular } });`,
      /no row for own move `goal.celebrate`/,
    ],
    [
      "one record's move copied onto a second record",
      `const M = defineRowMoves("goal", { edit: { word: "Edit", icon: EditRegular } });`,
      /on two records/,
    ],
  ];
  for (const [what, source, expected] of wrong) {
    it(`finds ${what}`, () => {
      const scan: Scan = { findings: [...tree.findings], own: [...tree.own] };
      scanFile(path.join("modules", "growth", "Wrong.tsx"), source, scan);
      const found = judge(scan, readme);
      expect(found.some((f) => expected.test(f))).toBe(true);
    });
  }
});
