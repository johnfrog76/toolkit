import {
  Body1,
  Button,
  Dialog,
  DialogActions,
  DialogBody,
  DialogContent,
  DialogSurface,
  DialogTitle,
  makeStyles,
  tokens,
} from "@fluentui/react-components";
import { useState } from "react";
import { DialogDismiss } from "../../shared/DialogDismiss";
import { Wordmark } from "../../shared/Wordmark";
import { useFacePref } from "../../hooks/useFacePref";
import { useWornTheme } from "../../hooks/useWornTheme";
import type { Milestone } from "../ado/api.ado";
import { awardTitle, tookLine } from "./award";
import { Confetti } from "./Confetti";

// The award (docs/modules/solitaire-agile.md, "Milestones: the tab and the award"):
// the ONE place Team Agile celebrates. When a milestone is reached and the person
// next opens the Milestones tab, this dialog says so -- "Congratulations: <title>
// reached!", one line of what it took, the picture -- and throws the confetti once,
// inside the dialog's moment and nowhere else. It is the one caller of
// <Confetti> (a test holds that); the PM Corner only points here.
//
// Whether it opens is the page's business (award.ts: once per Space and milestone
// per browser); this component draws one award and says when it is closed.
//
// A lazyPart of the Milestones page (shell/lazy.tsx), so the confetti package's
// bytes are fetched only when an award is first drawn.

const useStyles = makeStyles({
  surface: { maxWidth: "440px" },
  content: {
    display: "flex",
    flexDirection: "column",
    alignItems: "center",
    textAlign: "center",
    rowGap: tokens.spacingVerticalM,
    paddingTop: tokens.spacingVerticalS,
  },
  took: { color: tokens.colorNeutralForeground2 },
});

/**
 * The award's picture.
 *
 * NOT DRAWN YET: the real picture -- the team lead of the standup's cast, lifting
 * weights -- is drawn in the studio and shipped the way slide art is. Until it
 * lands, the dialog wears the Team Agile wordmark (the app's own mark, in the worn
 * theme's colours, with the face the person chose) as the stand-in. Swapping it is
 * ONE line: point AWARD_PICTURE at the picture's component.
 */
function WordmarkStandIn() {
  const { theme, active } = useWornTheme();
  const { faceId } = useFacePref();
  return (
    <Wordmark
      size={200}
      ink={tokens.colorNeutralForeground1}
      blob={active.logo}
      face={faceId}
      theme={theme}
      title=""
    />
  );
}

/** The picture the award shows -- the stand-in until the real one is drawn. */
export const AWARD_PICTURE = WordmarkStandIn;

export function AwardDialog({ milestone, onClose }: { milestone: Milestone; onClose: () => void }) {
  const styles = useStyles();
  // One burst for this dialog's moment: it ends itself and is not drawn again
  // while the dialog stays open.
  const [raining, setRaining] = useState(true);
  const Picture = AWARD_PICTURE;
  return (
    <Dialog open onOpenChange={(_e, d) => !d.open && onClose()}>
      <DialogSurface className={styles.surface} data-testid="award-dialog">
        <DialogBody>
          <DialogTitle action={<DialogDismiss />}>{awardTitle(milestone)}</DialogTitle>
          <DialogContent className={styles.content}>
            <div data-testid="award-picture">
              <Picture />
            </div>
            <Body1 className={styles.took}>{tookLine(milestone)}</Body1>
          </DialogContent>
          <DialogActions>
            <Button appearance="primary" onClick={onClose}>
              Close
            </Button>
          </DialogActions>
        </DialogBody>
        {raining && <Confetti onDone={() => setRaining(false)} />}
      </DialogSurface>
    </Dialog>
  );
}
