import {
  Button,
  Caption1,
  Link,
  makeStyles,
  mergeClasses,
  tokens,
} from "@fluentui/react-components";
import { useNavigate } from "react-router";
import { RITUALS } from "../../shell/consts";
import type { Corner } from "./api.solitaireAgile";
import { WORK_IT_NOW } from "./agenda";
import { cornerArg, hasChevron, isReached } from "./corner";
import { ROUTES } from "./paths";

// The PM Corner (AR-4; docs/modules/solitaire-agile.md, "The PM Corner: the line, the
// chevron, the confetti"): one line at the head of the Team Agile page -- the agent's
// `corner.line`, verbatim -- and, where it names a pick, the chevron, which opens the
// same hand-off copy box every Start work opens (one POST /api/cmd/StartWork, J2GV's).
//
// It does NOT celebrate. When the line reads reached it says where the celebration is
// -- "reached: see Milestones", a link to the Milestones tab -- and the award dialog
// there is the one thing that throws confetti (AwardDialog.tsx; "Milestones: the tab
// and the award"). Confetti over a standup nobody asked about read as a glitch.
//
// A lazyPart of StandupPage (shell/lazy.tsx): its bytes are fetched when the Corner
// is first drawn.

/** The words of the link a reached line carries, to the Milestones tab. */
export const SEE_MILESTONES = "see Milestones";

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

export function PmCorner({ corner, onStart }: { corner: Corner; onStart: (arg: string) => void }) {
  const styles = useStyles();
  const navigate = useNavigate();
  const reached = isReached(corner);
  return (
    <div
      className={mergeClasses(styles.corner, reached && styles.reached)}
      data-testid="pm-corner"
      data-shape={corner.shape}
      role="status"
    >
      <Caption1>
        {corner.line}
        {reached && (
          <>
            {": "}
            <Link
              href={ROUTES.milestones}
              onClick={(e) => {
                e.preventDefault();
                navigate(ROUTES.milestones);
              }}
            >
              {SEE_MILESTONES}
            </Link>
          </>
        )}
      </Caption1>
      {hasChevron(corner) && (
        <Button
          appearance="subtle"
          size="small"
          aria-label={`${WORK_IT_NOW}: ${corner.ref}`}
          onClick={() => onStart(cornerArg(corner))}
        >
          {RITUALS.text.cornerChevron}
        </Button>
      )}
    </div>
  );
}
