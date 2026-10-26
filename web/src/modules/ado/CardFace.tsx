import type { ReactNode } from "react";
import { Caption1, ProgressBar, makeStyles, tokens } from "@fluentui/react-components";

// The pieces of the board's card face that another surface may borrow
// (docs/modules/solitaire-agile.md, "The page": the Agenda's tiles LOOK like the
// board's cards). The face's box, its name and its progress row; the cover is
// CardCover.tsx's BoardCover. The board's tile itself stays the board's -- it
// carries the lane drag and the action menu, which nothing else wants -- so what
// is shared is the look, and the board draws exactly what it drew.

/** The face's box: the board's card, without the board's drag cursor. */
export const CARD_FACE_BOX = {
  display: "flex",
  flexDirection: "column",
  gap: tokens.spacingVerticalXS,
  padding: tokens.spacingVerticalS,
  backgroundColor: tokens.colorNeutralBackground1,
  border: `1px solid ${tokens.colorNeutralStroke2}`,
  borderRadius: tokens.borderRadiusMedium,
} as const;

const useStyles = makeStyles({
  name: {
    flex: "1 1 auto",
    minWidth: 0,
    textAlign: "left",
    font: "inherit",
    fontWeight: tokens.fontWeightSemibold,
    color: "inherit",
    background: "none",
    border: "none",
    padding: 0,
    cursor: "pointer",
    overflowWrap: "anywhere",
    ":hover": { textDecoration: "underline" },
    ":focus-visible": { outline: `2px solid ${tokens.colorStrokeFocus2}`, outlineOffset: "2px" },
  },
  // The same weight, for a name with nowhere to open.
  plain: {
    flex: "1 1 auto",
    minWidth: 0,
    fontWeight: tokens.fontWeightSemibold,
    overflowWrap: "anywhere",
  },
  meta: {
    display: "flex",
    alignItems: "center",
    flexWrap: "wrap",
    gap: tokens.spacingHorizontalS,
  },
  quiet: { color: tokens.colorNeutralForeground3 },
});

/** The card's name, as the board draws it: a button that opens the card, or,
 *  with no `onOpen`, the same text that opens nothing. */
export function CardName({
  children,
  onOpen,
  title,
}: {
  children: ReactNode;
  onOpen?: () => void;
  title?: string;
}) {
  const styles = useStyles();
  if (!onOpen) return <span className={styles.plain}>{children}</span>;
  return (
    <button type="button" className={styles.name} onClick={onOpen} title={title}>
      {children}
    </button>
  );
}

/** The card's checklist progress: the bar and its `n/m`. Nothing with no checklist. */
export function CardProgress({
  checked,
  total,
  progress,
}: {
  checked: number;
  total: number;
  progress: string;
}) {
  const styles = useStyles();
  if (!(total > 0)) return null;
  return (
    <div className={styles.meta}>
      <ProgressBar
        value={checked / total}
        thickness="medium"
        color={checked === total ? "success" : "brand"}
        aria-label={`${checked} of ${total} done`}
        style={{ flex: "1 1 auto" }}
      />
      <Caption1 className={styles.quiet}>{progress}</Caption1>
    </div>
  );
}
