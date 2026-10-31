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
import { useEffect, useRef } from "react";
import { DialogDismiss } from "../../shared/DialogDismiss";
import type { Milestone } from "../ado/api.ado";
import { awardTitle, tookLine } from "./award";
import { Trophy } from "./Trophy";
import { useConfetti } from "./useConfetti";

// The award (docs/modules/solitaire-agile.md, "Milestones: the tab and the award"):
// the ONE place Team Agile celebrates. When a milestone is reached and the person
// next opens the Milestones tab, this dialog says so -- "Congratulations: <title>
// reached!", one line of what it took, the picture -- and throws the confetti once,
// when it opens, through useConfetti(). The burst is drawn by the module's one mount at
// the app root (ConfettiLayer.tsx), over the whole viewport, not under this dialog's
// tree. This dialog is the one caller of useConfetti() (a test holds that); the PM
// Corner only points here.
//
// Whether it opens is the page's business (award.ts: once per Space and milestone
// per browser); this component draws one award and says when it is closed.
//
// A lazyPart of the Milestones page (shell/lazy.tsx); the confetti package's bytes are
// fetched by the root mount when this first throws.

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
 * The award's picture: a gold trophy (Trophy.tsx), the gold tier of the studio's
 * bowling-deck trophy, in the 200px picture box. Named here so a later picture is
 * still a one-line swap.
 */
export const AWARD_PICTURE = Trophy;

export function AwardDialog({
  milestones,
  onClose,
}: {
  milestones: Milestone[];
  onClose: () => void;
}) {
  const styles = useStyles();
  // One burst for this dialog's moment, thrown when it opens: it ends itself and is not
  // thrown again while the dialog stays open (a ref, so StrictMode's second effect run
  // throws nothing).
  const throwConfetti = useConfetti();
  const thrown = useRef(false);
  useEffect(() => {
    if (thrown.current) return;
    thrown.current = true;
    throwConfetti();
  }, [throwConfetti]);
  const Picture = AWARD_PICTURE;
  return (
    <Dialog open onOpenChange={(_e, d) => !d.open && onClose()}>
      <DialogSurface className={styles.surface} data-testid="award-dialog">
        <DialogBody>
          <DialogTitle action={<DialogDismiss />}>{awardTitle(milestones)}</DialogTitle>
          <DialogContent className={styles.content}>
            <div data-testid="award-picture">
              <Picture />
            </div>
            {milestones.length === 1 ? (
              <Body1 className={styles.took}>{tookLine(milestones[0])}</Body1>
            ) : (
              milestones.map((m) => (
                <Body1
                  key={`${m.repo}#${m.number}`}
                  className={styles.took}
                  data-testid="award-line"
                >
                  <strong>{m.title}</strong>: {tookLine(m)}
                </Body1>
              ))
            )}
          </DialogContent>
          <DialogActions>
            <Button appearance="primary" onClick={onClose}>
              Close
            </Button>
          </DialogActions>
        </DialogBody>
      </DialogSurface>
    </Dialog>
  );
}
