import type { ReactElement, ReactNode } from "react";
import { Caption1, Subtitle2, makeStyles, mergeClasses, tokens } from "@fluentui/react-components";
import { ErrorCircleRegular, FilterDismissRegular } from "@fluentui/react-icons";

// How a card says it has nothing to show. One component, because four cards had
// four answers: PR Comments had an icon and a considered line, and the three
// beside it on Home had a bare sentence in body text -- so an empty page looked
// half finished rather than empty.
//
// Three different facts, and they must not look alike:
//   empty    -- there is nothing, and that is fine. The card's own icon.
//   filtered -- there IS something, and a filter is hiding it.
//   error    -- nothing was read. Never dressed as "empty": see Daily, which
//               said "No billing activity found" for a week it had not read.

const useStyles = makeStyles({
  root: {
    display: "flex",
    flexDirection: "column",
    alignItems: "center",
    textAlign: "center",
    gap: tokens.spacingVerticalS,
    padding: `${tokens.spacingVerticalXXL} ${tokens.spacingHorizontalM}`,
    color: tokens.colorNeutralForeground3,
  },
  error: { color: tokens.colorPaletteRedForeground1 },
  icon: { fontSize: "28px", lineHeight: 0 },
  // Fluent's Caption1 sets its own alignment, so this has to say so.
  detail: { maxWidth: "36ch", color: tokens.colorNeutralForeground3, textAlign: "center" },
  action: { marginTop: tokens.spacingVerticalXS },
});

/** What a card has to say when it has no body. `PageCard` takes one as its
 *  `empty` slot; anything that is not a PageCard renders <EmptyState> with it. */
export interface EmptyMessage {
  /** The card's own icon, for the plain empty case. */
  icon: ReactElement;
  title: ReactNode;
  /** A reason, or what to do next. */
  detail?: ReactNode;
  tone?: "empty" | "filtered" | "error";
  action?: ReactNode;
}

export function EmptyState({ icon, title, detail, tone = "empty", action }: EmptyMessage) {
  const styles = useStyles();
  const shown =
    tone === "error" ? (
      <ErrorCircleRegular />
    ) : tone === "filtered" ? (
      <FilterDismissRegular />
    ) : (
      icon
    );
  return (
    // An error is announced; an empty list is just read when reached.
    <div
      className={mergeClasses(styles.root, tone === "error" && styles.error)}
      role={tone === "error" ? "alert" : undefined}
    >
      <span className={styles.icon} aria-hidden>
        {shown}
      </span>
      <Subtitle2>{title}</Subtitle2>
      {detail ? <Caption1 className={styles.detail}>{detail}</Caption1> : null}
      {action ? <div className={styles.action}>{action}</div> : null}
    </div>
  );
}
