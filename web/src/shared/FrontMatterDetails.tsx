import { makeStyles, tokens } from "@fluentui/react-components";

/**
 * The facts a file's front matter carries that its header does not draw, in a
 * collapsed row under the header (DetailHeader's `extra` slot): never raw rows
 * above the body. A page lifts the front matter off its text (frontMatterOf),
 * hands the header the keys it draws itself (the title, the description), and
 * hands the rest here. With nothing left, nothing is drawn.
 */
const useStyles = makeStyles({
  root: {
    fontSize: tokens.fontSizeBase200,
    color: tokens.colorNeutralForeground3,
    "& summary": { cursor: "pointer" },
  },
  list: {
    display: "flex",
    flexWrap: "wrap",
    columnGap: tokens.spacingHorizontalL,
    rowGap: tokens.spacingVerticalXXS,
    margin: `${tokens.spacingVerticalXS} 0 0`,
    "& div": { display: "flex", columnGap: tokens.spacingHorizontalXS },
    "& dt": { fontWeight: tokens.fontWeightSemibold },
    "& dd": { margin: 0, overflowWrap: "anywhere" },
  },
});

export const FRONT_MATTER_LABEL = "Details";

/** One YAML scalar as a reader sees it: a pair of quotes taken off, `\"` (or `''`) inside it unescaped. */
function scalar(value: string): string {
  const v = value.trim();
  const m = /^(["'])(.*)\1$/s.exec(v);
  if (!m) return v;
  return m[1] === '"' ? m[2].replace(/\\(["\\])/g, "$1") : m[2].replace(/''/g, "'");
}

/** The items of a flow sequence's inside, split on the commas outside quotes. */
function flowItems(inner: string): string[] {
  const items: string[] = [];
  let quote = "";
  let cur = "";
  for (let i = 0; i < inner.length; i++) {
    const c = inner[i];
    if (quote) {
      cur += c;
      if (c === "\\" && quote === '"') cur += inner[++i] ?? "";
      else if (c === quote) quote = "";
    } else if (c === '"' || c === "'") {
      quote = c;
      cur += c;
    } else if (c === ",") {
      items.push(cur);
      cur = "";
    } else cur += c;
  }
  items.push(cur);
  return items.map(scalar).filter((x) => x !== "");
}

/** A front matter value as a reader sees it: a scalar without its quotes, and a
 *  flow list `[a, "b"]` as the plain list `a, b`. */
export function unquoted(value: string): string {
  const v = value.trim();
  if (v.startsWith("[") && v.endsWith("]")) return flowItems(v.slice(1, -1)).join(", ");
  return scalar(v);
}

/** One key's value as a reader sees it, the key matched without regard to case; "" when absent. */
export function frontMatterValue(pairs: [string, string][], key: string): string {
  const hit = pairs.find(([k]) => k.toLowerCase() === key.toLowerCase());
  return hit ? unquoted(hit[1]) : "";
}

/** The pairs a header does not draw: `drawn` are the keys it does. */
export function leftoverFrontMatter(
  pairs: [string, string][],
  drawn: readonly string[],
): [string, string][] {
  return pairs
    .map(([key, value]): [string, string] => [key, unquoted(value)])
    .filter(([key, value]) => !drawn.includes(key.toLowerCase()) && value !== "");
}

export function FrontMatterDetails({ pairs }: { pairs: [string, string][] }) {
  const styles = useStyles();
  if (pairs.length === 0) return null;
  return (
    <details className={styles.root} data-testid="front-matter-details">
      <summary>{FRONT_MATTER_LABEL}</summary>
      <dl className={styles.list}>
        {pairs.map(([key, value], i) => (
          <div key={`${i}:${key}`}>
            <dt>{key}</dt>
            <dd>{value}</dd>
          </div>
        ))}
      </dl>
    </details>
  );
}
