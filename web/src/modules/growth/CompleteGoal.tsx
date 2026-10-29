/**
 * Complete a goal from the browser: `NewGrowth -Complete <file>` through the
 * bridge, behind the house's one confirm, `shared/ConfirmDialog`. The verb
 * writes the goal's Outcome Status line as `Achieved` and nothing else, so the
 * derived status reads complete exactly as it does when a person writes the
 * line by hand. The CLI verb is the one writer; this dialog only asks.
 */
import { useState } from "react";
import { ConfirmDialog } from "../../shared/ConfirmDialog";
import { buildGrowthCompleteParams, commandResultMessage } from "../ado/cliBridge";
import { useRunNewGrowthMutation } from "./api.growth";

interface Props {
  filename: string;
  title: string;
  open: boolean;
  onOpenChange: (open: boolean) => void;
  onCompleted?: () => void;
}

export function CompleteGoalDialog({ filename, title, open, onOpenChange, onCompleted }: Props) {
  const [message, setMessage] = useState<string | null>(null);
  const [run, { isLoading }] = useRunNewGrowthMutation();

  const confirm = async () => {
    setMessage(null);
    try {
      const result = await run({ params: buildGrowthCompleteParams({ file: filename }) }).unwrap();
      if (result.status === "success") {
        onOpenChange(false);
        onCompleted?.();
        return;
      }
      // A refusal is the dialog's message, in the verb's own words.
      setMessage(commandResultMessage(result, "Completed."));
    } catch {
      setMessage("Could not reach the agent. Nothing was written.");
    }
  };

  return (
    <ConfirmDialog
      open={open}
      what={
        <>
          Complete <strong>{title}</strong>. Its Outcome Status line is written as{" "}
          <code>Achieved</code> and nothing else in the file changes. It stays in{" "}
          <code>growth/current/</code> until you archive it.
        </>
      }
      busy={isLoading}
      message={message}
      onCancel={() => {
        setMessage(null);
        onOpenChange(false);
      }}
      onConfirm={confirm}
    />
  );
}
