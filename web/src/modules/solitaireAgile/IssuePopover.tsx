import type { ReactNode } from "react";
import {
  Caption1,
  Link,
  Popover,
  PopoverSurface,
  PopoverTrigger,
  Subtitle2,
  makeStyles,
  tokens,
} from "@fluentui/react-components";

// An issue number in the standup opens a small surface instead of a
// bare link: what the issue is, without leaving the page. The trigger keeps the
// link's text verbatim (`#<n>`), so the page's text is unchanged. Placement is
// the engine's (`positioning`, `withArrow`): it flips and shifts to stay on
// screen and follows the anchor on scroll and resize -- no fixed side or offset.
//
// Hover opens it, and a click (or Enter on the focused
// trigger) toggles it, which is what touch and the keyboard use; Escape closes.
// The surface adds no animation of its own, so reduced motion has nothing to turn off.
// A card (no url) shows its id, title and path, and no external link.

const useStyles = makeStyles({
  surface: {
    display: "flex",
    flexDirection: "column",
    rowGap: tokens.spacingVerticalXS,
    maxWidth: "320px",
  },
  fact: { color: tokens.colorNeutralForeground3 },
});

/** What the surface shows for one number or card; every field but the title is optional. */
export interface IssueFacts {
  title: string;
  /** The text the trigger shows: `#<n>`, or a card's id. Kept verbatim. */
  label: string;
  /** The issue's address; "" for a card, which has no external link. */
  url?: string;
  /** The worker chip, `ROLE · PERSONA (label)`, only when the seat is known. */
  worker?: string;
  severity?: string;
  milestone?: string;
  state?: string;
  /** A card's path. */
  path?: string;
}

/** The engine has no open delay; this is how long the surface stays after the pointer leaves, long enough to cross the arrow's gap to it. */
export const HOVER_CLOSE_DELAY_MS = 250;

export function IssuePopover({ facts }: { facts: IssueFacts }) {
  const styles = useStyles();
  const { url } = facts;
  // The trigger is a real link for an issue (the text and the href stay); a click
  // opens the surface rather than leaving, and "Open on GitHub" is the way out.
  const trigger: ReactNode = url ? (
    <Link href={url} target="_blank" rel="noopener noreferrer" onClick={(e) => e.preventDefault()}>
      {facts.label}
    </Link>
  ) : (
    <Link>{facts.label}</Link>
  );
  return (
    <Popover openOnHover mouseLeaveDelay={HOVER_CLOSE_DELAY_MS} positioning="below-start" withArrow>
      <PopoverTrigger disableButtonEnhancement>{trigger}</PopoverTrigger>
      <PopoverSurface aria-label={facts.label} data-testid="issue-popover">
        <div className={styles.surface}>
          <Subtitle2>{facts.title}</Subtitle2>
          {facts.worker && <Caption1 className={styles.fact}>{facts.worker}</Caption1>}
          {facts.severity && <Caption1 className={styles.fact}>{facts.severity}</Caption1>}
          {facts.milestone && <Caption1 className={styles.fact}>{facts.milestone}</Caption1>}
          {facts.state && <Caption1 className={styles.fact}>{facts.state}</Caption1>}
          {facts.path && <Caption1 className={styles.fact}>{facts.path}</Caption1>}
          {url && (
            <Link href={url} target="_blank" rel="noopener noreferrer">
              Open on GitHub
            </Link>
          )}
        </div>
      </PopoverSurface>
    </Popover>
  );
}
