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
  tokens,
} from "@fluentui/react-components";
import { DialogDismiss } from "../../shared/DialogDismiss";
import { buildReminderEditParams, commandResultMessage } from "../ado/cliBridge";
import type { CommandResponse } from "../ado/api.ado";
import { useRunRemindersMutation } from "./api.organize";
import type { Reminder } from "./api.organize";
import { joinDue, splitDue } from "./reminderEntry";
import { REF_HINT, useReminderFieldStyles } from "./NewReminderDialog";

interface Props {
  /** The reminder the dialog opened on. */
  editing: Reminder;
  onClose: () => void;
  /** After a successful save, with the verb's answer. */
  onSaved: (result: CommandResponse) => void;
}

/**
 * The Edit Reminder dialog: the entry, filled in, corrected through
 * `Reminders` on the bridge. Mounted only while open, on the reminder it
 * opened for. Save is off until something changed and sends only what
 * changed; a refusal stays in the dialog, in the verb's own words.
 */
export function EditReminderDialog({ editing, onClose, onSaved }: Props) {
  const styles = useReminderFieldStyles();
  const [runReminders, { isLoading: acting }] = useRunRemindersMutation();
  const [parts] = useState(() => splitDue(editing.due));
  const [editTitle, setEditTitle] = useState(editing.title);
  const [editDate, setEditDate] = useState(parts.date);
  const [editTime, setEditTime] = useState(parts.time);
  const [editSource, setEditSource] = useState(editing.source);
  const [editRef, setEditRef] = useState(editing.ref);
  const [editMessage, setEditMessage] = useState<string | null>(null);

  const editParams = buildReminderEditParams({
    id: editing.id,
    was: { title: editing.title, due: editing.due, source: editing.source, ref: editing.ref },
    now: {
      title: editTitle,
      due: joinDue({ date: editDate, time: editTime }),
      source: editSource,
      ref: editRef,
    },
  });

  const saveEdit = async () => {
    if (!editParams) return;
    setEditMessage(null);
    try {
      const result = await runReminders({ params: editParams }).unwrap();
      if (result.status === "success") {
        onSaved(result);
        return;
      }
      // A refusal stays in the dialog, in the verb's own words.
      setEditMessage(commandResultMessage(result, "Updated."));
    } catch {
      setEditMessage("Could not reach the agent. Nothing was changed.");
    }
  };

  return (
    <Dialog
      open
      onOpenChange={(_e, d) => {
        if (!d.open) onClose();
      }}
    >
      <DialogSurface>
        <DialogBody>
          <DialogTitle action={<DialogDismiss />}>Edit Reminder</DialogTitle>
          <DialogContent>
            <div className={styles.fields}>
              <Field label="What" required>
                <Input value={editTitle} onChange={(_, d) => setEditTitle(d.value)} />
              </Field>
              {/* A date and an optional time, not one datetime input: a
                  reminder due on a DAY has no time, and one input would
                  have to invent one (reminderEntry.ts). */}
              <div className={styles.pair}>
                <Field label="Due date" hint="Empty for no due date.">
                  <Input type="date" value={editDate} onChange={(_, d) => setEditDate(d.value)} />
                </Field>
                <Field label="Time" hint="Optional. Local time.">
                  <Input
                    type="time"
                    value={editTime}
                    disabled={!editDate}
                    onChange={(_, d) => setEditTime(d.value)}
                  />
                </Field>
              </div>
              <Field label="Source" required hint="A tag, such as manual, ado or goal.">
                <Input value={editSource} onChange={(_, d) => setEditSource(d.value)} />
              </Field>
              <Field label="Ref" hint={`${REF_HINT} Empty for none.`}>
                <Input value={editRef} onChange={(_, d) => setEditRef(d.value)} />
              </Field>
              {editMessage && (
                <Caption1
                  role="alert"
                  style={{ color: tokens.colorPaletteRedForeground1, whiteSpace: "pre-wrap" }}
                >
                  {editMessage}
                </Caption1>
              )}
            </div>
          </DialogContent>
          <DialogActions>
            <DialogTrigger disableButtonEnhancement>
              <Button appearance="secondary">Cancel</Button>
            </DialogTrigger>
            <Button
              appearance="primary"
              onClick={saveEdit}
              disabled={!editParams || !editTitle.trim() || !editSource.trim() || acting}
            >
              {acting ? "Saving…" : "Save"}
            </Button>
          </DialogActions>
        </DialogBody>
      </DialogSurface>
    </Dialog>
  );
}
