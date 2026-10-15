// What a card's text needs before a markdown renderer sees it. A card is
// written for TWO readers -- a person and an agent -- and three things in it are
// for the agent or for the file system, not for the page:
//
//   1. HTML comments. Templates carry instructions in them ("One commit PER
//      LINE..."). react-markdown used to print them as literal "<!-- ... -->"
//      text. Now raw HTML is parsed and a comment no longer prints, but
//      this stays on purpose: a multi-line comment between list items would
//      otherwise cut the list, and the pass already knows to leave comments
//      inside code (fenced or inline) alone.
//   2. YAML front matter. A generated review opens with one; CommonMark reads
//      "key: value / ---" as a setext HEADING, so it rendered as the page's
//      biggest line: "org: demo period: ... generated: ...".
//   3. Field lines. "**Sprint:** x" / "**Story Points:** y" on consecutive lines
//      is one paragraph to CommonMark, so four facts ran together as a sentence.
//
// Nothing here changes the file. It is a view of it.

export interface PreparedMarkdown {
  body: string;
  /** Front matter as written, in order. Empty when the card has none. */
  frontMatter: [key: string, value: string][];
}

const FENCE = /^\s*(```|~~~)/;
// A short capitalised label and a colon, bold or not: "**Sprint:** ", "Tags: ".
const FIELD = /^(\*\*[A-Z][^*\n]{0,40}:\*\*|[A-Z][\w /&-]{0,30}:)\s+\S/;

function splitFrontMatter(text: string): [string, PreparedMarkdown["frontMatter"]] {
  if (!/^---\r?\n/.test(text)) return [text, []];
  const lines = text.split(/\r?\n/);
  const end = lines.indexOf("---", 1);
  if (end < 0) return [text, []];
  const block = lines.slice(1, end);
  // Only a block that IS key: value lines. A card that opens with a rule and
  // prose is a card that opens with a rule.
  const pairs: PreparedMarkdown["frontMatter"] = [];
  for (const line of block) {
    if (!line.trim()) continue;
    const m = /^([A-Za-z_][\w-]*):\s*(.*)$/.exec(line);
    if (!m) return [text, []];
    pairs.push([m[1], m[2].trim()]);
  }
  return [
    lines
      .slice(end + 1)
      .join("\n")
      .replace(/^\n+/, ""),
    pairs,
  ];
}

// Comments, outside code. Inline code is protected span by span so a card that
// DOCUMENTS a comment (`<!-- like this -->`) still shows it.
function stripComments(text: string): string {
  const out: string[] = [];
  let inFence = false;
  let inComment = false;
  for (const line of text.split("\n")) {
    if (!inComment && FENCE.test(line)) {
      inFence = !inFence;
      out.push(line);
      continue;
    }
    if (inFence) {
      out.push(line);
      continue;
    }
    let rest = line;
    let kept = "";
    while (rest.length > 0) {
      if (inComment) {
        const close = rest.indexOf("-->");
        if (close < 0) {
          rest = "";
          break;
        }
        rest = rest.slice(close + 3);
        inComment = false;
        continue;
      }
      const code = /`[^`\n]*`/.exec(rest);
      const open = rest.indexOf("<!--");
      if (open < 0) {
        kept += rest;
        break;
      }
      if (code && code.index < open) {
        kept += rest.slice(0, code.index + code[0].length);
        rest = rest.slice(code.index + code[0].length);
        continue;
      }
      kept += rest.slice(0, open);
      rest = rest.slice(open + 4);
      inComment = true;
    }
    // A line that was ONLY a comment leaves nothing behind -- not a blank line,
    // which would split the list or paragraph it sat inside.
    if (kept.trim() === "" && line.trim() !== "") continue;
    out.push(kept.replace(/\s+$/, ""));
  }
  return out.join("\n");
}

function breakFieldLines(text: string): string {
  const lines = text.split("\n");
  let inFence = false;
  for (let i = 0; i < lines.length; i++) {
    if (FENCE.test(lines[i])) inFence = !inFence;
    if (inFence || i + 1 >= lines.length) continue;
    if (FIELD.test(lines[i]) && FIELD.test(lines[i + 1])) lines[i] = `${lines[i].trimEnd()}  `;
  }
  return lines.join("\n");
}

export function prepareMarkdown(text: string): PreparedMarkdown {
  const [withoutFront, frontMatter] = splitFrontMatter(text ?? "");
  return { body: breakFieldLines(stripComments(withoutFront)), frontMatter };
}

// ── Reading a long card ─────────────────────────────────────────────────────

/** "Work Item Info" -> "work-item-info". The id an h2 gets, and its link. */
export function slugOf(text: string): string {
  return (
    text
      .toLowerCase()
      .replace(/[`*_~[\]()]/g, "")
      .replace(/[^\p{L}\p{N}]+/gu, "-")
      .replace(/^-+|-+$/g, "") || "section"
  );
}

/** The plain words of a heading line: no #s, no emphasis marks, no links. */
function headingText(line: string): string {
  return line
    .replace(/^#+\s+/, "")
    .replace(/\s+#+\s*$/, "")
    .replace(/\[([^\]]*)\]\([^)]*\)/g, "$1")
    .replace(/[`*_~]/g, "")
    .trim();
}

export interface Heading {
  text: string;
  id: string;
  /** 2 for a section, 3 for a part of one -- how deep the list draws it. An h3
   *  with no h2 above it is listed at 2, so an oddly shaped file still gets a
   *  menu. */
  level: 2 | 3;
  /** 1-based line of the heading in the body: how the rendered element gets the
   *  same id the list points at, even when two headings share their words. */
  line: number;
}

/** The card's h2s and h3s, in order, outside code -- what "On this page" lists.
 *  h4 and below stay out: a list is a menu, not an outline. Two headings with
 *  the same words get distinct ids (`round`, `round-2`), in document order. */
export function headingsOf(body: string, style: HeadingIdStyle = "card"): Heading[] {
  // A repo's document is linked INTO by its anchors, so it wears GitHub's ids;
  // a card is only linked by its own list, so it keeps the house's.
  const githubIds = style === "github" ? headingIdsOf(body) : null;
  const out: Heading[] = [];
  const seen = new Map<string, number>();
  let inFence = false;
  let underSection = false;
  const lines = body.split("\n");
  for (let i = 0; i < lines.length; i++) {
    const line = lines[i];
    if (FENCE.test(line)) inFence = !inFence;
    if (inFence) continue;
    const m = /^(##|###)\s+\S/.exec(line);
    if (!m) continue;
    const text = headingText(line);
    if (!text) continue;
    if (m[1].length === 2) underSection = true;
    const level: 2 | 3 = m[1].length === 3 && underSection ? 3 : 2;
    const base = slugOf(text);
    const n = (seen.get(base) ?? 0) + 1;
    seen.set(base, n);
    const id = githubIds?.get(i + 1) ?? (n === 1 ? base : `${base}-${n}`);
    out.push({ text, id, level, line: i + 1 });
  }
  return out;
}

/** How a heading's id is made: the house's (`slugOf`, `-2` for a repeat) for
 *  a card, or GitHub's (`githubSlug`, `-1` for a repeat) for a repo's document,
 *  whose `#anchor` links were written against github.com. */
export type HeadingIdStyle = "card" | "github";

/**
 * The id GitHub gives a heading, so the anchors a repo's docs already use
 * (`CLI.md#the-bytes-a-card-is-written-with`) land in the reading room too:
 * lowercase; drop everything that is not a letter, a mark, a digit, `_`, a
 * space or a hyphen; each space becomes a hyphen. Nothing is collapsed --
 * "a -- b" is `a----b` on GitHub, and so here.
 */
export function githubSlug(text: string): string {
  return text
    .toLowerCase()
    .replace(/[^\p{L}\p{M}\p{N}\p{Pc} -]/gu, "")
    .replace(/ /g, "-");
}

/** A heading's words as GitHub renders them: the markup goes, a snake_case
 *  word keeps its underscores. */
function renderedHeadingText(line: string): string {
  return line
    .replace(/^#+\s+/, "")
    .replace(/\s+#+\s*$/, "")
    .replace(/!?\[([^\]]*)\]\([^)]*\)/g, "$1")
    .replace(/[`*~]/g, "")
    .replace(/(^|\s)_+|_+(\s|$)/g, "$1$2")
    .trim();
}

/** Every heading's GitHub id, h1 to h6, by its 1-based line, outside code. A
 *  repeat takes `-1`, `-2`, ... in document order, across all levels -- the
 *  way github.com numbers them. */
export function headingIdsOf(body: string): Map<number, string> {
  const ids = new Map<number, string>();
  const used = new Map<string, number>();
  let inFence = false;
  const lines = body.split("\n");
  for (let i = 0; i < lines.length; i++) {
    const line = lines[i];
    if (FENCE.test(line)) inFence = !inFence;
    if (inFence || !/^#{1,6}\s+\S/.test(line)) continue;
    const base = githubSlug(renderedHeadingText(line));
    let id = base;
    let n = used.get(base);
    if (n !== undefined) {
      for (n += 1; used.has(`${base}-${n}`); n += 1);
      id = `${base}-${n}`;
      used.set(base, n);
    }
    if (!used.has(id)) used.set(id, 0);
    ids.set(i + 1, id);
  }
  return ids;
}

/** The section a heading sits in: itself for a section, the nearest section
 *  above for a part of one. What the marker also lights when the reader is
 *  inside a part -- "where am I" is the section AND the part. */
export function sectionOf(headings: Heading[], id: string | null): string | null {
  if (id === null) return null;
  let section: string | null = null;
  for (const h of headings) {
    if (h.level === 2) section = h.id;
    if (h.id === id) return h.level === 2 ? h.id : section;
  }
  return null;
}

/** Drop the card's opening h1 when the page's own header already says it. A
 *  detail page prints the title in its header, then the card printed it again
 *  as the biggest thing on the page. Only an EXACT match goes: a card whose h1
 *  says something else keeps it. */
export function dropLeadingTitle(body: string, titleAbove: string | undefined): string {
  if (!titleAbove) return body;
  const lines = body.split("\n");
  const first = lines.findIndex((l) => l.trim() !== "");
  if (first < 0 || !/^#\s+\S/.test(lines[first])) return body;
  const same = (s: string) => s.replace(/\s+/g, " ").trim().toLowerCase();
  if (same(headingText(lines[first])) !== same(titleAbove)) return body;
  return lines
    .slice(first + 1)
    .join("\n")
    .replace(/^\n+/, "");
}
