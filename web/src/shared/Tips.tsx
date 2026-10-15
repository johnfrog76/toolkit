import { useState } from "react";
import { Body1, Body1Strong, Link, makeStyles, tokens } from "@fluentui/react-components";
import { LightbulbRegular } from "@fluentui/react-icons";

/**
 * One tip: a sentence that is TRUE right now, and the action that makes it
 * stop being true. A tip is retired by DOING -- its condition is derived from
 * state the caller already has, so the caller stops offering it the moment the
 * thing is done, and no flag is written anywhere. The condition is a
 * synchronous read of what the page already holds: a tip that would need its
 * own fetch to decide is not eligible for this slot.
 */
export interface Tip {
  id: string;
  sentence: string;
  /** The CTA label. The action DOES the thing; it never opens a help page.
   *  Optional: a tip whose instruction IS the sentence -- "switch boards from
   *  your avatar menu" -- carries no action, because there is nothing for a
   *  click to do that the sentence has not already taught. */
  cta?: string;
  onAction?: () => void;
}

// One tip per visit, and the NEXT one on the next visit (the owner:
// "tips rotate, I think one each time the route is loaded"). The pick is
// decided once per mount, so a refetch or re-render cannot re-roll the line,
// and the counter underneath is session-scoped, so leaving and coming back
// advances by one. A fact about this visit, not about the machine: nothing is
// persisted, and a full reload starts the rotation over.
let sessionVisits = -1;

/**
 * A tip lives with its Space and loads with the rest of the content:
 *while /env is being fetched again -- a Space switch, a
 * refresh -- the tips are computed from the OLD answer, so the row stays
 * off until the new one is in, the way every card shows its spinner.
 */
export function tipsReady(envFetching: boolean): boolean {
  return !envFetching;
}

const useStyles = makeStyles({
  // Not a container (the owner: "visual anchor is Lightbulb icon").
  // One bare line at the foot: no card, no border, no fill, no heading -- the
  // icon is the anchor, so nothing else does that work. The geometry is the
  // connect line's this row replaced, and Body1 (14px) for the same reason the
  // explain lines are: the Link draws at 14 whatever the sentence around it does.
  // Vertical room is M (12px), one step under the explain rows' L -- "go 4px
  // less".
  row: {
    display: "flex",
    alignItems: "center",
    gap: tokens.spacingHorizontalS,
    marginTop: tokens.spacingVerticalM,
    padding: `${tokens.spacingVerticalM} ${tokens.spacingHorizontalS}`,
    color: tokens.colorNeutralForeground3,
  },
  // 24px and brand-colored, the row's one visual anchor -- 30 was tried and
  // read too big. The brand token keeps it right in every
  // theme; the text around it stays quiet (neutral fg3).
  icon: {
    flexShrink: 0,
    fontSize: "24px",
    color: tokens.colorBrandForeground1,
  },
  // The text wraps inside itself; the icon holds the line's left edge.
  text: { minWidth: 0 },
});

/**
 * A rotating one-line tip: lightbulb, sentence, CTA. Renders nothing from an
 * empty pool -- every condition met means there is nothing left to teach, and
 * absence is the right shape for that.
 */
export function Tips({ tips }: { tips: Tip[] }) {
  const styles = useStyles();
  // The index is fixed at mount; the pool may still be filling (env arrives
  // after the first render), so the modulo is applied per render.
  const [visit] = useState(() => ++sessionVisits);
  if (tips.length === 0) return null;
  const tip = tips[visit % tips.length];
  return (
    <div className={styles.row}>
      <LightbulbRegular className={styles.icon} aria-hidden />
      <Body1 className={styles.text}>
        <Body1Strong>Tips: </Body1Strong>
        {tip.sentence}
        {tip.cta && tip.onAction ? (
          <>
            {" "}
            <Link as="button" onClick={tip.onAction}>
              {tip.cta}
            </Link>
          </>
        ) : null}
      </Body1>
    </div>
  );
}

/** Test-only: rewind the session rotation so each test starts at the first tip. */
export function resetTipRotation() {
  sessionVisits = -1;
}
