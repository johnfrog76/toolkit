/**
 * Archive a growth item from the browser (a goal's Archive, on its row and its
 * page -- it said Retire before the row vocabulary): `NewGrowth -Close <file>` through the
 * bridge, behind a confirm because it moves a file. The module closes its own
 * data -- Archive is org-scoped and cannot see growth/ -- and the CLI verb is
 * the one implementation; this dialog only asks.
 * The asking is the house's one
 * confirm, `shared/ConfirmDialog`.
 */
import { useState } from "react";
import { ConfirmDialog } from "../../shared/ConfirmDialog";
import { buildGrowthCloseParams, commandResultMessage } from "../ado/cliBridge";
import { useRunNewGrowthMutation } from "./api.growth";

interface Props {
  filename: string;
  title: string;
  open: boolean;
  onOpenChange: (open: boolean) => void;
  onRetired?: () => void;
}

export function RetireGoalDialog({ filename, title, open, onOpenChange, onRetired }: Props) {
  const [message, setMessage] = useState<string | null>(null);
  const [run, { isLoading }] = useRunNewGrowthMutation();

  const confirm = async () => {
    setMessage(null);
    try {
      const result = await run({ params: buildGrowthCloseParams({ file: filename }) }).unwrap();
      if (result.status === "success") {
        onOpenChange(false);
        onRetired?.();
        return;
      }
      // A refusal is the dialog's message, in the verb's own words.
      setMessage(commandResultMessage(result, "Archived."));
    } catch {
      setMessage("Could not reach the agent. Nothing was moved.");
    }
  };

  return (
    <ConfirmDialog
      open={open}
      what={
        <>
          Archive <strong>{title}</strong>. It moves to <code>growth/archive/</code>, stamped with
          the date it closed -- it stays in the year&apos;s evidence and is not edited from here
          again.
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
