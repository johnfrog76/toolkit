/**
 * Close a meeting from the browser: `MeetingAgenda -Close`, through the bridge.
 *
 * It moves a file -- the record leaves `manager/current/` for `manager/archive/`
 * and gains its `**Closed:**` stamp -- so it is the one action on these pages
 * that sits behind a confirm. Everything else here is a save. The confirm is
 * the house's one, `shared/ConfirmDialog`.
 *
 * Nothing in this component decides how a session closes. The verb does, in a
 * child pwsh; this asks, and shows what it said. A stated refusal (exit 2 --
 * a duplicate of the record already in archive/) comes back as `status: error`
 * with the sentence in `error`, and the dialog stays open showing it.
 */
import { useState } from "react";
import { Button } from "@fluentui/react-components";
import { ArchiveRegular } from "@fluentui/react-icons";
import { ConfirmDialog } from "../../shared/ConfirmDialog";
import { buildMeetingAgendaParams, commandResultMessage } from "../ado/cliBridge";
import { useRunMeetingAgendaMutation } from "./api.communication";

interface ConfirmProps {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  filename: string;
  /** The record's date, as the agent serves it. */
  date: string;
  /** "" for the 1:1. */
  series?: string;
  /** After a successful close -- the list is already invalidated. */
  onClosed?: () => void;
}

/**
 * The confirm and the bridge call, controlled by whoever draws the trigger: the
 * header button below, or a row's `...` menu.
 */
export function CloseMeetingConfirm({
  open,
  onOpenChange,
  filename,
  date,
  series,
  onClosed,
}: ConfirmProps) {
  const [message, setMessage] = useState<string | null>(null);
  const [run, { isLoading }] = useRunMeetingAgendaMutation();

  const confirm = async () => {
    setMessage(null);
    try {
      const result = await run({
        params: buildMeetingAgendaParams({ date, series, action: "Close" }),
      }).unwrap();
      if (result.status === "success") {
        onOpenChange(false);
        onClosed?.();
        return;
      }
      // A refusal is the dialog's message, in the verb's own words.
      setMessage(commandResultMessage(result, "Closed."));
    } catch {
      setMessage("Could not reach the agent. Nothing was moved.");
    }
  };

  return (
    <ConfirmDialog
      open={open}
      what={
        <>
          Close this meeting. <code>{filename}</code> moves to the archive, stamped with the date it
          closed -- a closed session is the record, and is not edited or sent from here again.
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

interface Props {
  filename: string;
  date: string;
  series?: string;
  /** Icon only or with its word (a page header). */
  compact?: boolean;
  onClosed?: () => void;
}

export function CloseMeetingButton({ filename, date, series, compact, onClosed }: Props) {
  const [open, setOpen] = useState(false);

  return (
    <>
      <Button
        icon={<ArchiveRegular />}
        size="small"
        appearance={compact ? "subtle" : "secondary"}
        title="Close this meeting"
        aria-label={compact ? "Close this meeting" : undefined}
        onClick={() => setOpen(true)}
      >
        {compact ? undefined : "Close"}
      </Button>
      <CloseMeetingConfirm
        open={open}
        onOpenChange={setOpen}
        filename={filename}
        date={date}
        series={series}
        onClosed={onClosed}
      />
    </>
  );
}
