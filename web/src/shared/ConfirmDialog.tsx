import type { ReactNode } from "react";
import {
  Body1,
  Button,
  Caption1,
  Dialog,
  DialogActions,
  DialogBody,
  DialogContent,
  DialogSurface,
  DialogTitle,
  Spinner,
  tokens,
} from "@fluentui/react-components";
import { DialogDismiss } from "./DialogDismiss";

/**
 * "Are you sure?" -- the one step between a person and an act they may regret.
 *
 * The owner's sketch: the question, one line naming the act,
 * Cancel (secondary) and Submit (primary), and the house dismiss top right.
 * Nothing runs until Submit; Cancel, the dismiss, Escape and the scrim all
 * leave everything as it was. The act itself stays with the caller -- this
 * only asks.
 *
 * The ONE confirm: the board's and the list's archive, a
 * growth item's retire and a meeting's close each drew their own, with four
 * titles and four button words. Now every act worth a second thought says it
 * the same way -- "Are you sure?", the act named in `what` with one sentence
 * of what follows, Cancel and Submit. A caller that runs the verb and can be
 * REFUSED passes `busy` while it runs and `message` with the verb's own
 * sentence; the dialog stays open showing it, as a refusal should.
 */
export function ConfirmDialog({
  open,
  what,
  onConfirm,
  onCancel,
  title = "Are you sure?",
  confirmLabel = "Submit",
  busy = false,
  confirmDisabled = false,
  message,
}: {
  open: boolean;
  /** The act, named: "Close issue #<n>." */
  what: ReactNode;
  onConfirm: () => void;
  onCancel: () => void;
  title?: string;
  confirmLabel?: string;
  /** The act is running: Submit spins and neither button can be pressed. */
  busy?: boolean;
  /** Submit cannot be pressed yet -- or at all, after a refused preview -- while
   *  Cancel still can. Unlike `busy`, nothing spins. */
  confirmDisabled?: boolean;
  /** A stated refusal, in the verb's own words -- shown under the act. */
  message?: ReactNode;
}) {
  return (
    <Dialog
      open={open}
      onOpenChange={(_e, d) => {
        if (!d.open) onCancel();
      }}
    >
      <DialogSurface style={{ maxWidth: "400px" }}>
        <DialogBody>
          <DialogTitle action={<DialogDismiss />}>{title}</DialogTitle>
          <DialogContent>
            <Body1>{what}</Body1>
            {message ? (
              <Caption1
                role="alert"
                style={{
                  display: "block",
                  marginTop: tokens.spacingVerticalS,
                  color: tokens.colorPaletteRedForeground1,
                  whiteSpace: "pre-wrap",
                }}
              >
                {message}
              </Caption1>
            ) : null}
          </DialogContent>
          <DialogActions>
            <Button appearance="secondary" onClick={onCancel} disabled={busy}>
              Cancel
            </Button>
            <Button appearance="primary" onClick={onConfirm} disabled={busy || confirmDisabled}>
              {busy ? <Spinner size="tiny" aria-label="Working..." /> : confirmLabel}
            </Button>
          </DialogActions>
        </DialogBody>
      </DialogSurface>
    </Dialog>
  );
}
