import { Button, Caption1, makeStyles, mergeClasses, tokens } from "@fluentui/react-components";
import { RITUALS } from "../../shell/consts";
import type { Corner } from "./api.solitaireAgile";
import { Confetti, useCelebrateOnce } from "./Confetti";
import { CORNER_SEEN_KEY, cornerArg, hasChevron, isReached, milestoneKey } from "./corner";

// The PM Corner (AR-4; docs/modules/solitaire-agile.md, "The PM Corner: the line, the
// chevron, the confetti"): one line at the head of the Team Agile page -- the agent's
// `corner.line`, verbatim -- and, where it names a pick, the chevron, which opens the
// same hand-off copy box every Start work opens (one POST /api/cmd/StartWork, J2GV's).
// When the line reads reached, the page throws confetti ONCE per milestone per viewer
// (Confetti.tsx): on the transition to reached while the page watched, or on first
// sight with the browser's mark absent -- never on a reload with the mark set.
//
// A lazyPart of StandupPage (shell/lazy.tsx): its bytes, the confetti's and the
// package's are fetched when the Corner is first drawn.

const useStyles = makeStyles({
  corner: {
    display: "flex",
    flexWrap: "wrap",
    alignItems: "center",
    columnGap: tokens.spacingHorizontalS,
    padding: `${tokens.spacingVerticalXS} ${tokens.spacingHorizontalS}`,
    borderLeft: `3px solid ${tokens.colorBrandStroke1}`,
    backgroundColor: tokens.colorNeutralBackground2,
    borderRadius: tokens.borderRadiusMedium,
  },
  reached: { borderLeftColor: tokens.colorPaletteGreenBorder2 },
});

export function PmCorner({
  corner,
  space,
  onStart,
}: {
  corner: Corner;
  space: string;
  onStart: (arg: string) => void;
}) {
  const styles = useStyles();
  const reached = isReached(corner);
  const { firing, done } = useCelebrateOnce(CORNER_SEEN_KEY, milestoneKey(space, corner), reached);
  return (
    <div
      className={mergeClasses(styles.corner, reached && styles.reached)}
      data-testid="pm-corner"
      data-shape={corner.shape}
      role="status"
    >
      <Caption1>{corner.line}</Caption1>
      {hasChevron(corner) && (
        <Button
          appearance="subtle"
          size="small"
          aria-label={`Start work on ${corner.ref}`}
          onClick={() => onStart(cornerArg(corner))}
        >
          {RITUALS.text.cornerChevron}
        </Button>
      )}
      {firing && <Confetti onDone={done} />}
    </div>
  );
}
