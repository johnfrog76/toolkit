import type { ReactNode } from "react";
import { Subtitle2, makeStyles, tokens } from "@fluentui/react-components";
import { BackButton } from "./BackButton";
import { FilePath } from "./FilePath";
import { RefreshButton } from "./RefreshButton";

/**
 * The header of every page that shows ONE record, and of every markdown viewer:
 * the parts in one order, so the pages cannot drift.
 *
 *   left   back, then the title (the page's h1), the meta slot, the extra slot,
 *          and the File line
 *   right  `actions`, then refresh, then `external` (the link out) last
 *
 * The File line has one rule: the record's absolute path on this machine when it
 * is a local file (`path`); otherwise its address (`url`), named by `what`
 * ("issue link", "document link"); with neither, no line. Hand the whole thing
 * to PanelFrame's `headerLeft` -- it draws its own right side, so a page passes
 * no `headerRight`.
 *
 * Before the record has loaded, give no `title`: the back button stands alone.
 */
const useStyles = makeStyles({
  row: {
    display: "flex",
    alignItems: "center",
    justifyContent: "space-between",
    flexWrap: "wrap",
    columnGap: tokens.spacingHorizontalS,
    rowGap: tokens.spacingVerticalXS,
    flex: 1,
    minWidth: 0,
  },
  left: {
    display: "flex",
    alignItems: "center",
    columnGap: tokens.spacingHorizontalS,
    flex: 1,
    minWidth: 0,
  },
  titleBlock: {
    display: "flex",
    flexDirection: "column",
    rowGap: tokens.spacingVerticalXS,
    minWidth: 0,
  },
  meta: {
    display: "flex",
    columnGap: tokens.spacingHorizontalS,
    rowGap: tokens.spacingVerticalXXS,
    flexWrap: "wrap",
    alignItems: "center",
    color: tokens.colorNeutralForeground3,
  },
  right: {
    display: "flex",
    alignItems: "center",
    columnGap: tokens.spacingHorizontalS,
    flexWrap: "wrap",
  },
});

export interface DetailHeaderProps {
  /** The page's h1. Absent while there is no record to title. */
  title?: ReactNode;
  /** Badges and captions beside each other, under the title. */
  meta?: ReactNode;
  /** Anything custom under the meta line (a 1:1 session's Retro, Agenda, Prep). */
  extra?: ReactNode;
  /** The record's absolute path on this machine, when it is a local file. */
  path?: string;
  /** Its address when it is not: a URL. Used only when there is no `path`. */
  url?: string;
  /** What the line is, for the copy button: "issue link", "document link". Unset, "file path". */
  what?: string;
  /** Buttons that come before refresh. */
  actions?: ReactNode;
  /** The page's refetch; draws the house refresh button. */
  refresh?: { onClick: () => void; isFetching?: boolean; title?: string };
  /** The link out (github.com, the tracker): always the last control. */
  external?: ReactNode;
}

export function DetailHeader({
  title,
  meta,
  extra,
  path,
  url,
  what,
  actions,
  refresh,
  external,
}: DetailHeaderProps) {
  const styles = useStyles();
  const address = path || url;
  const hasRight = actions != null || refresh != null || external != null;
  return (
    <div className={styles.row} data-testid="detail-header">
      <div className={styles.left}>
        <BackButton />
        {title != null && (
          <div className={styles.titleBlock}>
            <Subtitle2 as="h1">{title}</Subtitle2>
            {meta != null && <div className={styles.meta}>{meta}</div>}
            {extra}
            {address ? <FilePath path={address} what={what} /> : null}
          </div>
        )}
      </div>
      {hasRight && (
        <div className={styles.right}>
          {actions}
          {refresh ? (
            <RefreshButton
              onClick={refresh.onClick}
              isFetching={refresh.isFetching}
              title={refresh.title}
            />
          ) : null}
          {external}
        </div>
      )}
    </div>
  );
}
