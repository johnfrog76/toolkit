/**
 * Fluent's `subtle` badge colour is drawn for dark and brand surfaces. With the
 * `outline` appearance on a light card it is white text on a white border, so
 * the badge cannot be read. `tint` with `subtle`, or `outline` with
 * `informative`, read in every theme. This reads the source and refuses the
 * combination on a Badge, so it is not added again.
 */
import fs from "node:fs";
import path from "node:path";

const SRC = path.join(__dirname, "..");

function sourceFiles(dir: string): string[] {
  return fs.readdirSync(dir, { withFileTypes: true }).flatMap((e) => {
    const full = path.join(dir, e.name);
    if (e.isDirectory()) return e.name === "node_modules" ? [] : sourceFiles(full);
    return /\.tsx?$/.test(e.name) && !/\.test\.tsx?$/.test(e.name) ? [full] : [];
  });
}

/** The opening tags of every `<Badge ...>` in a source text: from `<Badge` to
 *  the `>` that closes it, skipping a `>` inside braces (an arrow function, a
 *  comparison) or a string. */
export function badgeTags(source: string): string[] {
  const tags: string[] = [];
  const re = /<Badge(?=[\s/>])/g;
  let m: RegExpExecArray | null;
  while ((m = re.exec(source))) {
    let depth = 0;
    let quote = "";
    let i = m.index + m[0].length;
    for (; i < source.length; i++) {
      const c = source[i];
      if (quote) {
        if (c === quote) quote = "";
      } else if (c === '"' || c === "'" || (depth > 0 && c === "`")) quote = c;
      else if (c === "{") depth++;
      else if (c === "}") depth--;
      else if (c === ">" && depth === 0) break;
    }
    tags.push(source.slice(m.index, i + 1));
  }
  return tags;
}

export function isOutlineSubtle(tag: string): boolean {
  return /\bappearance="outline"/.test(tag) && /\bcolor="subtle"/.test(tag);
}

/** A Badge that can be outline and whose colour is a variable or an
 *  expression, so the literal rule cannot read it. */
export function isOutlineWithComputedColor(tag: string): boolean {
  const outline = /\bappearance="outline"/.test(tag) || /\bappearance=\{[^]*?"outline"/.test(tag);
  return outline && /\bcolor=\{/.test(tag);
}

/** Files whose outline Badge has a computed colour AND the string "subtle",
 *  each with why it is safe. `badgeContrastRender.test.tsx` mounts them. */
const COMPUTED_ALLOW: Record<string, string> = {
  "shared/visibility.tsx": "outline only when the colour is informative; tint with subtle",
  "modules/ado/ConfigSettings.tsx": "sourceColor's subtle gets tint",
  "modules/ado/DesignDocPage.tsx":
    "its subtle colour is on a tint Badge; the outline one is warning or success",
  "modules/growth/GoalDetailPage.tsx":
    "its subtle colour is on a tint Badge; the outline one is not computed to subtle",
  "modules/growth/Goals.tsx":
    "its subtle colour is on a tint Badge; the outline one reads TYPE_COLOUR, which has none",
};

describe("no Badge is outline with the subtle colour", () => {
  it("in any source file under web/src", () => {
    const offenders: string[] = [];
    for (const file of sourceFiles(SRC)) {
      const source = fs.readFileSync(file, "utf8");
      for (const tag of badgeTags(source)) {
        if (isOutlineSubtle(tag)) {
          const line = source.slice(0, source.indexOf(tag)).split("\n").length;
          offenders.push(`${path.relative(SRC, file)}:${line}`);
        }
      }
    }
    expect(offenders).toEqual([]);
  });

  it("no file pairs a computed-colour outline Badge with the word subtle, unlisted", () => {
    const offenders: string[] = [];
    for (const file of sourceFiles(SRC)) {
      const rel = path.relative(SRC, file).split(path.sep).join("/");
      const source = fs.readFileSync(file, "utf8");
      // A Button's appearance="subtle" is not a Badge colour.
      const mentionsSubtle = source.replace(/appearance="subtle"/g, "").includes('"subtle"');
      if (!mentionsSubtle || rel in COMPUTED_ALLOW) continue;
      if (badgeTags(source).some(isOutlineWithComputedColor)) offenders.push(rel);
    }
    expect(offenders).toEqual([]);
  });

  it("the computed rule flags the two shapes that slipped through", () => {
    const flagged = [
      '<Badge appearance="outline" size="small" color={isPublic(v) ? "informative" : "subtle"}>x</Badge>',
      '<Badge appearance="outline" color={sourceColor(setting.source)} size="small">x</Badge>',
      '<Badge appearance={p ? "outline" : "tint"} color={c}>x</Badge>',
    ];
    for (const src of flagged) {
      expect(isOutlineWithComputedColor(badgeTags(src)[0])).toBe(true);
    }
    expect(isOutlineWithComputedColor('<Badge appearance="tint" color={c}>x</Badge>')).toBe(false);
    expect(isOutlineWithComputedColor('<Badge appearance="outline" color="brand">x</Badge>')).toBe(
      false,
    );
  });

  it("the rule reads what it thinks it reads: any order, across lines", () => {
    const flagged = [
      '<Badge appearance="outline" size="small" color="subtle">x</Badge>',
      '<Badge color="subtle" appearance="outline">x</Badge>',
      '<Badge\n  size="small"\n  color="subtle"\n  title="a > b"\n  appearance="outline"\n>x</Badge>',
      '<Badge onClick={() => go()} color="subtle" appearance="outline" />',
    ];
    for (const src of flagged) {
      const tags = badgeTags(src);
      expect(tags).toHaveLength(1);
      expect(isOutlineSubtle(tags[0])).toBe(true);
    }
    const fine = [
      '<Badge appearance="tint" color="subtle">x</Badge>',
      '<Badge appearance="outline" color="informative">x</Badge>',
      '<Badge appearance="outline" size="small">x</Badge>',
      '<Badge appearance="outline">subtle</Badge><Badge color="subtle">x</Badge>',
    ];
    for (const src of fine) {
      expect(badgeTags(src).some(isOutlineSubtle)).toBe(false);
    }
  });
});
