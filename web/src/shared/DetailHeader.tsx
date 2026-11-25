import type { ReactNode } from "react";
import { Body1, Subtitle2, makeStyles, tokens } from "@fluentui/react-components";
import { BackButton } from "./BackButton";
import { FilePath } from "./FilePath";
import { RefreshButton } from "./RefreshButton";

/**
 * The header of every page that shows ONE record, and of every markdown viewer:
 * the parts in one order, so the pages cannot drift.
 *
 *   left   back, then the title (the page's h1), its description line, the meta
 *          slot, the extra slot, and the File line
 *   right  `actions`, then refresh, then `external` (the link out) last
 *
 * The File line has one rule: the record's absolute path on this machine when it
 * is a local file (`path`); otherwise its address (`url`); with neither, no line.
 * The line is compact (FilePath): a label, the address in its tooltip. Hand the whole thing
 * to PanelFrame's `headerLeft` -- it draws its own right side, so a page passes
 * no `headerRight`.
 *
 * Before the record has loaded, give no `title`: the back button stands alone.
 */
/** Lines a header's description keeps at phone width. */
const DESCRIPTION_LINES_PHONE = 3;

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
  // The left side asks for a readable measure before it shares the row: when the
  // row cannot hold it beside the controls, the controls drop to their own line
  // instead of squeezing the title into a sliver.
  left: {
    display: "flex",
    alignItems: "center",
    columnGap: tokens.spacingHorizontalS,
    flexGrow: 1,
    flexShrink: 1,
    flexBasis: "20rem",
    minWidth: 0,
  },
  titleBlock: {
    display: "flex",
    flexDirection: "column",
    alignItems: "flex-start",
    rowGap: tokens.spacingVerticalXS,
    flex: 1,
    minWidth: 0,
  },
  // A heading brings the browser's own margins; the header's rhythm is its row gap.
  title: { margin: 0, overflowWrap: "anywhere" },
  meta: {
    display: "flex",
    columnGap: tokens.spacingHorizontalS,
    rowGap: tokens.spacingVerticalXXS,
    flexWrap: "wrap",
    alignItems: "center",
    color: tokens.colorNeutralForeground3,
  },
  description: {
    margin: 0,
    color: tokens.colorNeutralForeground2,
    overflowWrap: "anywhere",
    // Whole at desktop width. On a phone it is clamped to a few lines the way
    // a card item's description is (CardItem), the full text in its title.
    "@media (max-width: 600px)": {
      display: "-webkit-box",
      WebkitBoxOrient: "vertical",
      WebkitLineClamp: String(DESCRIPTION_LINES_PHONE),
      overflow: "hidden",
    },
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
  /** One line of prose under the title (a prompt's `description`), above the meta. */
  description?: ReactNode;
  /** Badges and captions beside each other, under the title. */
  meta?: ReactNode;
  /** Anything custom under the meta line (a 1:1 session's Retro, Agenda, Prep). */
  extra?: ReactNode;
  /** The record's absolute path on this machine, when it is a local file. */
  path?: string;
  /** Its address when it is not: a URL. Used only when there is no `path`. */
  url?: string;
  /** Buttons that come before refresh. */
  actions?: ReactNode;
  /** The page's refetch; draws the house refresh button. */
  refresh?: { onClick: () => void; isFetching?: boolean; title?: string };
  /** The link out (github.com, the tracker): always the last control. */
  external?: ReactNode;
}

/** A slot that holds something to draw: not absent, not false, not an empty string. */
const present = (node: ReactNode) => node != null && node !== false && node !== "";

export function DetailHeader({
  title,
  description,
  meta,
  extra,
  path,
  url,
  actions,
  refresh,
  external,
}: DetailHeaderProps) {
  const styles = useStyles();
  const address = path || url;
  const hasRight = present(actions) || refresh != null || present(external);
  return (
    <div className={styles.row} data-testid="detail-header">
      <div className={styles.left}>
        <BackButton />
        {title != null && (
          <div className={styles.titleBlock}>
            <Subtitle2 as="h1" className={styles.title}>
              {title}
            </Subtitle2>
            {present(description) && (
              <Body1
                as="p"
                className={styles.description}
                data-testid="detail-description"
                title={typeof description === "string" ? description : undefined}
              >
                {description}
              </Body1>
            )}
            {present(meta) && (
              <div className={styles.meta} data-testid="detail-meta">
                {meta}
              </div>
            )}
            {present(extra) ? extra : null}
            {address ? <FilePath path={address} /> : null}
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
