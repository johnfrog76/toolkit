import { Button, Caption1, makeStyles, tokens } from "@fluentui/react-components";
import { ChevronLeftRegular, ChevronRightRegular } from "@fluentui/react-icons";

const useStyles = makeStyles({
  root: { display: "flex", alignItems: "center", gap: tokens.spacingHorizontalXS },
});

export interface ListPagerProps {
  /** Zero-based. */
  page: number;
  totalPages: number;
  onPageChange: (page: number) => void;
}

/** The one pager a list panel draws, in its foot's centre: the same controls,
 *  words and keys on every panel. Nothing when there is no second page. The
 *  arrow keys page while the pager has focus. */
export function ListPager({ page, totalPages, onPageChange }: ListPagerProps) {
  const styles = useStyles();
  if (totalPages <= 1) return null;
  const go = (to: number) => onPageChange(Math.min(totalPages - 1, Math.max(0, to)));
  return (
    <div
      className={styles.root}
      role="group"
      aria-label="Pages"
      data-list-pager
      onKeyDown={(e) => {
        if (e.key === "ArrowLeft") go(page - 1);
        else if (e.key === "ArrowRight") go(page + 1);
      }}
    >
      <Button
        icon={<ChevronLeftRegular />}
        size="small"
        appearance="subtle"
        aria-label="Previous page"
        disabled={page === 0}
        onClick={() => go(page - 1)}
      />
      <Caption1 aria-live="polite">{`Page ${page + 1} of ${totalPages}`}</Caption1>
      <Button
        icon={<ChevronRightRegular />}
        size="small"
        appearance="subtle"
        aria-label="Next page"
        disabled={page >= totalPages - 1}
        onClick={() => go(page + 1)}
      />
    </div>
  );
}
