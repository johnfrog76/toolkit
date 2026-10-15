import { Button, Caption1, makeStyles, tokens } from "@fluentui/react-components";
import { ChevronLeftRegular, ChevronRightRegular } from "@fluentui/react-icons";

const useStyles = makeStyles({
  root: {
    display: "flex",
    alignItems: "center",
    gap: tokens.spacingHorizontalXS,
  },
  // The touch floor, applied only at size="medium". Fluent's own medium icon
  // button is 32px — comfortable with a mouse, short of a thumb. 44px is the
  // number the rest of the app's mobile chrome already uses (the deck's mobile
  // gear and controls), so a pager on a phone matches its neighbors rather
  // than being the one control you have to aim at.
  //
  // A floor, not a fixed size: min-width/min-height let the button keep its
  // own metrics if a future Fluent tier is larger.
  touch: {
    minWidth: "44px",
    minHeight: "44px",
  },
});

/**
 * `small` (default) is the desktop pager everywhere in the toolkit — 24px
 * icon buttons that sit quietly in a header row. `medium` is the touch
 * variant: Fluent's 32px tier lifted to a 44px tap target. Callers pick by
 * viewport tier (see wasteland's useViewport) rather than by media query,
 * because this is a prop value changing, not markup restyling.
 */
export type PaginationSize = "small" | "medium";

interface PaginationProps {
  page: number;
  totalPages: number;
  onPageChange: (page: number) => void;
  /** Defaults to "small" — every existing desktop call site is unaffected. */
  size?: PaginationSize;
}

export function Pagination({ page, totalPages, onPageChange, size = "small" }: PaginationProps) {
  const styles = useStyles();
  if (totalPages <= 1) return null;
  const touch = size === "medium" ? styles.touch : undefined;
  return (
    <div className={styles.root}>
      <Button
        icon={<ChevronLeftRegular />}
        size={size}
        className={touch}
        appearance="subtle"
        aria-label="Previous page"
        disabled={page === 0}
        onClick={() => onPageChange(Math.max(0, page - 1))}
      />
      <Caption1>
        {page + 1} / {totalPages}
      </Caption1>
      <Button
        icon={<ChevronRightRegular />}
        size={size}
        className={touch}
        appearance="subtle"
        aria-label="Next page"
        disabled={page >= totalPages - 1}
        onClick={() => onPageChange(Math.min(totalPages - 1, page + 1))}
      />
    </div>
  );
}
