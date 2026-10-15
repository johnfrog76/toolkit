/**
 * The New Reminder dialog -- what, an optional due, an optional source and an
 * optional ref -- and the one place a reminder is created in the web UI.
 *
 * Two doors open it: the Reminders card's +, empty, and a card's "Remind me
 * about this", pre-filled with the card's title and its id as the ref
 * (docs/modules/organize.md, "The web UI"). The second door is in the ADO
 * module, which reaches this file only through a `lazyPart`, so a machine with
 * organize off never fetches it.
 *
 * The write is the CLI's `NewReminder` through the bridge. A refusal stays in
 * the dialog in the verb's own words; a success is handed back to the opener,
 * which says it where it has room to.
 */
import { useState } from "react";
import {
  Button,
  Caption1,
  Dialog,
  DialogActions,
  DialogBody,
  DialogContent,
  DialogSurface,
  DialogTitle,
  DialogTrigger,
  Field,
  Input,
  makeStyles,
  tokens,
} from "@fluentui/react-components";
import { DialogDismiss } from "../../shared/DialogDismiss";
import { buildNewReminderParams, commandResultMessage } from "../ado/cliBridge";
import type { CommandResponse } from "../ado/api.ado";
import { useRunNewReminderMutation } from "./api.organize";

export const useReminderFieldStyles = makeStyles({
  fields: {
    display: "flex",
    flexDirection: "column",
    gap: tokens.spacingVerticalM,
    paddingTop: tokens.spacingVerticalS,
  },
  // Two fields side by side: a date and its time, a source and its ref.
  pair: { display: "flex", gap: tokens.spacingHorizontalS, "& > *": { flex: 1, minWidth: 0 } },
});

/** The Ref field's hint, said once for both dialogs. */
export const REF_HINT = "Optional. A card's id, such as 214 or K7M2, links to the card.";

export interface NewReminderPrefill {
  title?: string;
  ref?: string;
}

export function NewReminderDialog({
  open,
  prefill,
  onClose,
  onAdded,
}: {
  open: boolean;
  /** What the fields start with when the dialog is mounted. */
  prefill?: NewReminderPrefill;
  onClose: () => void;
  /** The verb answered success; the opener closes the dialog and says so. */
  onAdded: (result: CommandResponse) => void;
}) {
  const styles = useReminderFieldStyles();
  const [runNewReminder, { isLoading: adding }] = useRunNewReminderMutation();
  // The fields start from the prefill. An opener mounts the dialog only while
  // it is open, so each opening starts afresh, not from what was typed last time.
  const [title, setTitle] = useState(prefill?.title ?? "");
  const [due, setDue] = useState("");
  const [source, setSource] = useState("");
  const [ref, setRef] = useState(prefill?.ref ?? "");
  const [message, setMessage] = useState<string | null>(null);

  const add = async () => {
    setMessage(null);
    try {
      const result = await runNewReminder({
        params: buildNewReminderParams({ title, due, source, ref }),
      }).unwrap();
      if (result.status === "success") {
        onAdded(result);
        return;
      }
      // A refusal is the dialog's message, in the verb's own words.
      setMessage(commandResultMessage(result, "Added."));
    } catch {
      setMessage("Could not reach the agent. Nothing was added.");
    }
  };

  return (
    <Dialog
      open={open}
      onOpenChange={(_e, d) => {
        if (!d.open) onClose();
      }}
    >
      <DialogSurface>
        <DialogBody>
          <DialogTitle action={<DialogDismiss />}>New Reminder</DialogTitle>
          <DialogContent>
            <div className={styles.fields}>
              <Field label="What" required>
                <Input
                  size="small"
                  value={title}
                  onChange={(_, d) => setTitle(d.value)}
                  placeholder="Review sprint goals"
                />
              </Field>
              <Field label="Due" hint="Optional. Local time.">
                <Input
                  type="datetime-local"
                  size="small"
                  value={due}
                  onChange={(_, d) => setDue(d.value)}
                />
              </Field>
              <div className={styles.pair}>
                <Field label="Source" hint="Optional tag, such as ado or goal. Default: manual.">
                  <Input size="small" value={source} onChange={(_, d) => setSource(d.value)} />
                </Field>
                <Field label="Ref" hint={REF_HINT}>
                  <Input size="small" value={ref} onChange={(_, d) => setRef(d.value)} />
                </Field>
              </div>
              {message && (
                <Caption1
                  role="alert"
                  style={{ color: tokens.colorPaletteRedForeground1, whiteSpace: "pre-wrap" }}
                >
                  {message}
                </Caption1>
              )}
            </div>
          </DialogContent>
          <DialogActions>
            <DialogTrigger disableButtonEnhancement>
              <Button appearance="secondary">Cancel</Button>
            </DialogTrigger>
            <Button appearance="primary" onClick={add} disabled={!title.trim() || adding}>
              {adding ? "Adding…" : "Submit"}
            </Button>
          </DialogActions>
        </DialogBody>
      </DialogSurface>
    </Dialog>
  );
}
