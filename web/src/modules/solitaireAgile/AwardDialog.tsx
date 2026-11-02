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
import { useConfetti } from "../../hooks/useConfetti";

// The award (docs/modules/solitaire-agile.md, "Milestones: the tab and the award"):
// the ONE place Team Agile celebrates. When a milestone is reached and the person
// next opens the Milestones tab, this dialog says so -- "Congratulations: <title>
// reached!", one line of what it took, the gold trophy -- and throws the confetti once,
// when it opens. The burst is the app's, drawn at the shell's root over the whole
// viewport (shell/ConfettiProvider.tsx); this dialog only says when, through
// useConfetti(), and is its one caller (a test holds that); the PM Corner only
// points here.
//
// Whether it opens is the page's business (award.ts: once per Space and milestone
// per browser); this component draws one award and says when it is closed.
//
// A lazyPart of the Milestones page (shell/lazy.tsx); the confetti's own bytes are
// the root's lazyPart, fetched only when this dialog first throws.

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

/** The picture the award shows: the gold trophy (Trophy.tsx), in the 200px box. */
export const AWARD_PICTURE = Trophy;

export function AwardDialog({
  milestones,
  onClose,
}: {
  milestones: Milestone[];
  onClose: () => void;
}) {
  const styles = useStyles();
  // One burst for this dialog's moment, thrown when it opens: it ends itself and is
  // not thrown again while the dialog stays open.
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
