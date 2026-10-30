import type { ReactNode } from "react";
import { Card, Spinner, makeStyles, mergeClasses, tokens } from "@fluentui/react-components";
import { HairlineDivider } from "./HairlineDivider";
import { thinScrollbar } from "./thinScrollbar";

const useStyles = makeStyles({
  cardBase: {
    padding: tokens.spacingVerticalM,
    backgroundColor: tokens.colorNeutralBackgroundAlpha,
    // A grid child's default min-width is its content, so one wide card used to
    // push the whole page past a phone viewport instead of shrinking.
    minWidth: 0,
    // Fluent's Card is `overflow: hidden`, which makes it the scroll container
    // for anything `position: sticky` inside it -- and a container that never
    // scrolls means sticky never sticks. `clip` cuts the corners the same way
    // without becoming one, so a long card's "On this page" can follow you.
    overflow: "clip",
  },
  cardScrollable: {
    padding: tokens.spacingVerticalM,
    backgroundColor: tokens.colorNeutralBackgroundAlpha,
    minWidth: 0,
    display: "grid",
    gridTemplateRows: "auto auto 1fr auto",
    justifyContent: "stretch",
    alignItems: "stretch",
    // this is cause of log not filling height to match env.
    // "@media (min-width: 900px)": {
    //   maxHeight: "600px",
    // },
  },
  header: {
    display: "flex",
    alignItems: "center",
    justifyContent: "space-between",
    flexWrap: "wrap" as const,
    gap: tokens.spacingHorizontalS,
  },
  headerLeft: {
    display: "flex",
    alignItems: "center",
    gap: tokens.spacingHorizontalS,
    flex: 1,
    minWidth: 0,
  },
  headerRight: {
    display: "flex",
    alignItems: "center",
    gap: tokens.spacingHorizontalS,
    flexWrap: "wrap" as const,
  },
  scrollArea: {
    display: "flex",
    flexDirection: "column" as const,
    overflowY: "auto",
    minHeight: 0,
    "& > *": { flexShrink: 0 },
    ...thinScrollbar,
  },
  footer: {
    display: "flex",
    alignItems: "center",
    justifyContent: "space-between",
    gap: tokens.spacingHorizontalS,
    paddingTop: tokens.spacingVerticalS,
  },
  // With a centre slot (the pager) the two sides share what is left equally, so
  // the centre sits in the middle and keeps its own width on one line, and a
  // long left sentence wraps inside its half instead of squeezing the pager.
  footerSide: { flex: "1 1 0", minWidth: 0 },
  footerSideEnd: { display: "flex", justifyContent: "flex-end" },
  footerMiddle: { flexShrink: 0, whiteSpace: "nowrap" },
  loadingBody: {
    display: "flex",
    justifyContent: "center",
    alignItems: "center",
    padding: tokens.spacingVerticalXL,
  },
});

interface PageCardProps {
  headerLeft?: ReactNode;
  headerRight?: ReactNode;
  children?: ReactNode;
  toast?: ReactNode;
  footer?: ReactNode;
  footerLeft?: ReactNode;
  footerCenter?: ReactNode;
  footerRight?: ReactNode;
  /** One line under the footer row, the width of the card -- the hub-sync foot
   *  line (modules/ado/HubSyncLine.tsx) on the cards that write into the hub.
   *  The node draws itself, or nothing; this only places it. */
  footNote?: ReactNode;
  scrollable?: boolean;
  loading?: boolean;
  loadingLabel?: string;
  /** What the card shows INSTEAD of its body when there is nothing to show, or
   *  nothing could be read. A slot, like headerLeft: hand it an <EmptyState>
   *  (shared/EmptyState.tsx) so every card says it the same way. `undefined`
   *  means the card has a body. The header and footer stay -- a filter that hid
   *  everything has to remain reachable. */
  empty?: ReactNode;
  className?: string;
}

export function PageCard({
  headerLeft,
  headerRight,
  children,
  toast,
  footer,
  footerLeft,
  footerCenter,
  footerRight,
  footNote,
  scrollable = false,
  loading = false,
  loadingLabel = "Loading...",
  empty,
  className,
}: PageCardProps) {
  const styles = useStyles();
  const hasHeader = headerLeft != null || headerRight != null;
  const mid = footerCenter != null;
  const hasFooterSlots = footerLeft != null || footerCenter != null || footerRight != null;

  let body: ReactNode;
  if (loading) {
    body = (
      <div className={styles.loadingBody}>
        <Spinner size="tiny" label={loadingLabel} />
      </div>
    );
  } else if (empty != null) {
    body = empty;
  } else if (scrollable) {
    body = <div className={styles.scrollArea}>{children}</div>;
  } else {
    body = children;
  }

  return (
    <Card
      className={mergeClasses(scrollable ? styles.cardScrollable : styles.cardBase, className)}
      appearance="outline"
    >
      {hasHeader && (
        <div className={styles.header}>
          <div className={styles.headerLeft}>{headerLeft}</div>
          {headerRight != null && <div className={styles.headerRight}>{headerRight}</div>}
        </div>
      )}
      {hasHeader && <HairlineDivider />}
      {body}
      {toast != null && !loading && toast}
      {hasFooterSlots && !loading && (
        <div className={styles.footer}>
          <div className={mid ? styles.footerSide : undefined}>{footerLeft}</div>
          <div className={mid ? styles.footerMiddle : undefined}>{footerCenter}</div>
          <div className={mid ? mergeClasses(styles.footerSide, styles.footerSideEnd) : undefined}>
            {footerRight}
          </div>
        </div>
      )}
      {!hasFooterSlots && footer != null && !loading && (
        <div className={styles.footer}>{footer}</div>
      )}
      {footNote != null && !loading && footNote}
    </Card>
  );
}
