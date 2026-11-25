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

/** A YAML scalar as a reader sees it: one pair of quotes around it taken off. */
export function unquoted(value: string): string {
  const m = /^(["'])(.*)\1$/.exec(value.trim());
  return m ? m[2] : value.trim();
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
        {pairs.map(([key, value]) => (
          <div key={key}>
            <dt>{key}</dt>
            <dd>{value}</dd>
          </div>
        ))}
      </dl>
    </details>
  );
}
