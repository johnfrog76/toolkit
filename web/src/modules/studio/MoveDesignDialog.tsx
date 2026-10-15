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
  Textarea,
  makeStyles,
  tokens,
} from "@fluentui/react-components";
import { DialogDismiss } from "../../shared/DialogDismiss";
import { buildMoveDesignParams, commandResultMessage } from "../ado/cliBridge";
import type { MoveDesignFields } from "../ado/cliBridge";
import type { Design } from "../ado/api.ado";
import { useRunMoveDesignMutation } from "./api.studio";

// A hub design's move along its road (design lifecycle L3), from the
// drawer: the same dialog grammar as New Design Note -- a title with a dismiss,
// the fields the road needs, Cancel and one primary -- and the verb through
// the bridge (POST /api/cmd/MoveDesign -Hub), never a native write. A refusal
// stays in the dialog in the verb's own words; success closes it and the card
// says the verb's line.

/** What a road asks for before it runs: the drop its reason, the completion
 *  the path the docs landed in; a graduation and a shipped archive nothing. */
export type MoveRoad = "spec" | "shipped" | "dropped" | "complete";

export const ROADS: Record<
  MoveRoad,
  {
    label: string;
    to: MoveDesignFields["to"];
    dropped?: boolean;
    needs?: "reason" | "doc";
    what: string;
  }
> = {
  spec: {
    label: "Graduate to a spec",
    to: "Spec",
    what: "Scaffold the spec beside the note, with the note's id, description and thread. The note stays in design/.",
  },
  shipped: {
    label: "Archive as shipped",
    to: "Archive",
    what: "Move the note to design/archive/ and stamp it Closed and shipped -- a design that shipped as written.",
  },
  dropped: {
    label: "Drop",
    to: "Archive",
    dropped: true,
    needs: "reason",
    what: "Move the note to design/archive/ and stamp it Closed and dropped. An idea that never made it is only worth keeping with why.",
  },
  complete: {
    label: "Complete",
    to: "Complete",
    needs: "doc",
    what: "Move the spec to spec/archive/ and the note to design/archive/, stamp both Closed, and write where the docs landed into the spec.",
  },
};

/** The roads a row offers, by what the design has and where it is (4.4). */
export function roadsFor(d: Pick<Design, "state" | "note" | "spec">): MoveRoad[] {
  const liveNote = !!d.note && !d.note.archived;
  const liveSpec = !!d.spec && !d.spec.archived;
  if (liveSpec) return ["complete"];
  if (liveNote) return ["spec", "shipped", "dropped"];
  return [];
}

/** The file name the verb is given: the note's, else the spec's. */
export function moveName(d: Pick<Design, "note" | "spec">): string {
  return d.note?.name ?? d.spec?.name ?? "";
}

const useStyles = makeStyles({
  fields: { display: "flex", flexDirection: "column", rowGap: tokens.spacingVerticalM },
  what: { color: tokens.colorNeutralForeground3 },
});

export function MoveDesignDialog({
  design,
  road,
  open,
  onClose,
  onMoved,
}: {
  design: Design;
  road: MoveRoad;
  open: boolean;
  onClose: () => void;
  /** The verb's own line, for the card to say. */
  onMoved: (line: string) => void;
}) {
  const styles = useStyles();
  const [runMove, { isLoading: moving }] = useRunMoveDesignMutation();
  const [reason, setReason] = useState("");
  const [doc, setDoc] = useState("");
  const [message, setMessage] = useState<string | null>(null);
  const spec = ROADS[road];
  const ready =
    spec.needs === "reason"
      ? reason.trim().length > 0
      : spec.needs === "doc"
        ? doc.trim().length > 0
        : true;

  const reset = () => {
    setReason("");
    setDoc("");
    setMessage(null);
  };

  const run = async () => {
    setMessage(null);
    try {
      const params = buildMoveDesignParams({
        name: moveName(design),
        to: spec.to,
        dropped: spec.dropped,
        reason,
        doc: spec.needs === "doc" ? doc : undefined,
        space: design.space,
      });
      const result = await runMove({ params }).unwrap();
      if (result.status === "success") {
        onMoved(commandResultMessage(result, "Moved."));
        reset();
        onClose();
        return;
      }
      setMessage(commandResultMessage(result, "Moved."));
    } catch {
      setMessage("Could not reach the agent. Nothing was moved.");
    }
  };

  return (
    <Dialog
      open={open}
      onOpenChange={(_e, d) => {
        if (!d.open) {
          reset();
          onClose();
        }
      }}
    >
      <DialogSurface>
        <DialogBody>
          <DialogTitle action={<DialogDismiss />}>
            {spec.label}: {design.title}
          </DialogTitle>
          <DialogContent>
            <div className={styles.fields}>
              <Caption1 className={styles.what}>{spec.what}</Caption1>
              {spec.needs === "doc" ? (
                <Field
                  label="Where the docs landed"
                  required
                  hint="A path in the hub, e.g. docs/board.md. The spec is not complete until its durable part has a home."
                >
                  <Input
                    size="small"
                    value={doc}
                    onChange={(_, d) => setDoc(d.value)}
                    placeholder="docs/board.md"
                  />
                </Field>
              ) : null}
              <Field
                label={spec.needs === "reason" ? "Why it never made it" : "Reason"}
                required={spec.needs === "reason"}
                hint={
                  spec.needs === "reason"
                    ? "Written into the note's journey line."
                    : "Optional. Appended to the note's journey line."
                }
              >
                <Textarea
                  size="small"
                  value={reason}
                  onChange={(_, d) => setReason(d.value)}
                  resize="vertical"
                />
              </Field>
              {message ? (
                <Caption1
                  role="alert"
                  style={{ color: tokens.colorPaletteRedForeground1, whiteSpace: "pre-wrap" }}
                >
                  {message}
                </Caption1>
              ) : null}
            </div>
          </DialogContent>
          <DialogActions>
            <DialogTrigger disableButtonEnhancement>
              <Button appearance="secondary">Cancel</Button>
            </DialogTrigger>
            <Button appearance="primary" onClick={run} disabled={!ready || moving}>
              {moving ? "Moving…" : spec.label}
            </Button>
          </DialogActions>
        </DialogBody>
      </DialogSurface>
    </Dialog>
  );
}
