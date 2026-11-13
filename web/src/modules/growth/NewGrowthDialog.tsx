import { useState } from "react";
import { useNavigate } from "react-router";
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
  Dropdown,
  Field,
  Input,
  Option,
  Textarea,
  makeStyles,
  tokens,
} from "@fluentui/react-components";
import { DialogDismiss } from "../../shared/DialogDismiss";
import { useRunNewGrowthMutation } from "./api.growth";
import type { GrowthType } from "./api.growth";
import {
  buildNewGrowthParams,
  commandResultMessage,
  fileFromCommandOutput,
} from "../ado/cliBridge";
import { localToday } from "../../utility/dates";
import { TYPE_LABEL, goalPath } from "./growthLabels";

const useStyles = makeStyles({
  dialogFields: {
    display: "flex",
    flexDirection: "column" as const,
    gap: tokens.spacingVerticalM,
    paddingTop: tokens.spacingVerticalS,
  },
});

interface Props {
  /** The items growth/current/ already holds, by file name. */
  existing: string[];
  onClose: () => void;
}

/**
 * The New Growth Item dialog, mounted only while open so each opening starts
 * from empty fields.
 *
 * `NewGrowth` through the bridge: the verb the terminal types writes the file,
 * and its answer is a CommandResponse, not the item -- so the new item's name
 * comes off the verb's `FILE:` line. An item that was already in the list
 * before the call is the verb's "Already there": nothing was written, so the
 * dialog stays open and says so rather than opening it.
 */
export function NewGrowthDialog({ existing, onClose }: Props) {
  const styles = useStyles();
  const navigate = useNavigate();
  const [runNewGrowth, { isLoading: creating }] = useRunNewGrowthMutation();
  // What the verb said when it did not make a new item: a refusal in its own
  // words, or "Already there" for an item growth/current/ already holds.
  const [createMessage, setCreateMessage] = useState<string | null>(null);
  const [newType, setNewType] = useState<GrowthType>("training");
  const [newTitle, setNewTitle] = useState("");
  const [newDate, setNewDate] = useState(localToday);
  const [newDueDate, setNewDueDate] = useState("");
  const [newProvider, setNewProvider] = useState("");
  const [newHours, setNewHours] = useState("");
  const [newNotes, setNewNotes] = useState("");

  const handleSubmit = async () => {
    setCreateMessage(null);
    const before = new Set(existing);
    try {
      const result = await runNewGrowth({
        params: buildNewGrowthParams({
          type: newType,
          title: newTitle,
          date: newDate,
          dueDate: newDueDate,
          provider: newProvider,
          hours: newHours,
          notes: newNotes,
        }),
      }).unwrap();
      const filename = result.status === "success" ? fileFromCommandOutput(result.output) : null;
      if (!filename || before.has(filename)) {
        setCreateMessage(commandResultMessage(result, "Nothing was written."));
        return;
      }
      onClose();
      navigate(goalPath(filename));
    } catch {
      setCreateMessage("Could not reach the agent. Nothing was written.");
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
          <DialogTitle action={<DialogDismiss />}>New Growth Item</DialogTitle>
          <DialogContent>
            <div className={styles.dialogFields}>
              <Field label="Type">
                <Dropdown
                  size="small"
                  value={TYPE_LABEL[newType]}
                  selectedOptions={[newType]}
                  onOptionSelect={(_e, d) => setNewType(d.optionValue as GrowthType)}
                  style={{ minWidth: "150px" }}
                >
                  <Option value="training">Training</Option>
                  <Option value="presentation">Presentation</Option>
                  <Option value="goal">Goal</Option>
                </Dropdown>
              </Field>
              <Field label="Title">
                <Input
                  size="small"
                  value={newTitle}
                  onChange={(_, d) => setNewTitle(d.value)}
                  placeholder="Course or talk title"
                  style={{ width: "100%" }}
                />
              </Field>
              {newType === "training" ? (
                <div
                  style={{
                    display: "flex",
                    gap: tokens.spacingHorizontalM,
                    alignItems: "flex-end",
                  }}
                >
                  <Field label="Start date">
                    <Input
                      type="date"
                      size="small"
                      value={newDate}
                      onChange={(_, d) => setNewDate(d.value)}
                      style={{ width: "145px" }}
                    />
                  </Field>
                  {/* Required, and the field says so -- the Create button is
                      already disabled without it, which told the user nothing
                      about WHY. The CLI refuses the same case by name. */}
                  <Field label="Due date (required)" required>
                    <Input
                      type="date"
                      size="small"
                      value={newDueDate}
                      onChange={(_, d) => setNewDueDate(d.value)}
                      style={{ width: "145px" }}
                    />
                  </Field>
                </div>
              ) : (
                <Field label="Date">
                  <Input
                    type="date"
                    size="small"
                    value={newDate}
                    onChange={(_, d) => setNewDate(d.value)}
                    style={{ width: "150px" }}
                  />
                </Field>
              )}
              {newType === "training" && (
                <div
                  style={{
                    display: "flex",
                    gap: tokens.spacingHorizontalM,
                    alignItems: "flex-end",
                  }}
                >
                  <Field label="Provider">
                    <Input
                      size="small"
                      value={newProvider}
                      onChange={(_, d) => setNewProvider(d.value)}
                      placeholder="Udemy, Pluralsight, internal…"
                      style={{ width: "220px" }}
                    />
                  </Field>
                  <Field label="Hours">
                    <Input
                      size="small"
                      value={newHours}
                      onChange={(_, d) => setNewHours(d.value)}
                      placeholder="TBD"
                      style={{ width: "70px" }}
                    />
                  </Field>
                </div>
              )}
              <Field label="Notes">
                <Textarea
                  size="small"
                  rows={3}
                  resize="vertical"
                  value={newNotes}
                  onChange={(_, d) => setNewNotes(d.value)}
                  placeholder={
                    newType === "training"
                      ? "What it covers, why you enrolled…"
                      : newType === "goal"
                        ? "Why this matters, and what it would change…"
                        : "Context, audience, key message…"
                  }
                />
              </Field>
              {createMessage && (
                <Caption1
                  role="alert"
                  style={{ color: tokens.colorPaletteRedForeground1, whiteSpace: "pre-wrap" }}
                >
                  {createMessage}
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
              onClick={handleSubmit}
              disabled={
                creating || !newTitle.trim() || !newDate || (newType === "training" && !newDueDate)
              }
            >
              {creating ? "Creating…" : "Submit"}
            </Button>
          </DialogActions>
        </DialogBody>
      </DialogSurface>
    </Dialog>
  );
}
