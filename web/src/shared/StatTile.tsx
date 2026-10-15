import { forwardRef } from "react";
import type { HTMLAttributes, ReactNode } from "react";
import { Caption1, makeStyles, mergeClasses, tokens } from "@fluentui/react-components";

// How a card counts. One component, because a counting card copies whichever
// style it saw last: the engagement summary boxed its numbers
// (81 Items closed / 4 Reviews / 6 Repos) while the Issue Report printed them
// bare (60 open / 5 closed), and Test Health and Sprint Velocity each carried a
// private copy of the summary's styles. The summary's boxed tile is the house
// style -- the number beside its caption, in a hairline box -- and this is it.
//
//   <StatTiles>
//     <StatTile count={81} label="Items closed" />
//     <Tooltip content="..." relationship="description"><StatTile ... /></Tooltip>
//   </StatTiles>
//
// A tile forwards its ref and spreads its props so a Tooltip can wrap one.

const useStyles = makeStyles({
  tiles: {
    display: "flex",
    columnGap: tokens.spacingHorizontalL,
    rowGap: tokens.spacingVerticalS,
    flexWrap: "wrap",
    justifyContent: "center",
    marginTop: tokens.spacingVerticalS,
    marginBottom: tokens.spacingVerticalS,
    flexShrink: 0,
  },
  tile: {
    display: "flex",
    alignItems: "center",
    gap: tokens.spacingHorizontalS,
    padding: `${tokens.spacingVerticalS} ${tokens.spacingHorizontalM}`,
    border: `1px solid ${tokens.colorNeutralStroke2}`,
    borderRadius: tokens.borderRadiusMedium,
    minWidth: "120px",
    cursor: "default",
  },
  count: {
    fontSize: "1.5rem",
    fontWeight: 600,
    lineHeight: 1,
  },
});

/** The row a card's tiles sit in: wraps, centred, the summary's spacing. */
export function StatTiles({ children, className }: { children: ReactNode; className?: string }) {
  const styles = useStyles();
  return (
    <div className={mergeClasses(styles.tiles, className)} data-stat-tiles="">
      {children}
    </div>
  );
}

export interface StatTileProps extends HTMLAttributes<HTMLDivElement> {
  /** The number (or `3/5`, `42%`) -- already formatted. */
  count: ReactNode;
  /** What it counts, in the card's own vocabulary. */
  label: ReactNode;
  /** A health colour for the number, when the count is a verdict. */
  color?: string;
}

/** One boxed count: the number beside its caption. */
export const StatTile = forwardRef<HTMLDivElement, StatTileProps>(function StatTile(
  { count, label, color, className, ...rest },
  ref,
) {
  const styles = useStyles();
  return (
    <div ref={ref} className={mergeClasses(styles.tile, className)} data-stat-tile="" {...rest}>
      <span className={styles.count} style={color ? { color } : undefined}>
        {count}
      </span>
      <Caption1>{label}</Caption1>
    </div>
  );
});
