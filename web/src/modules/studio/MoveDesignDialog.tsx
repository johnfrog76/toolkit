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
import {
  buildCheckoutMoveDesignParams,
  buildMoveDesignParams,
  commandResultMessage,
  suggestedCommitLine,
} from "../ado/cliBridge";
import { HatGraduationRegular } from "@fluentui/react-icons";
import { ROW, defineRowMoves } from "../../shared/CardActions";
import type { RowMove } from "../../shared/CardActions";
import type { MoveDesignFields } from "../ado/cliBridge";
import type { Design } from "../ado/api.ado";
import { useRunMoveDesignMutation } from "./api.studio";

// A hub design's move along its road (design lifecycle L3), from the
// drawer: the same dialog grammar as New Design Note -- a title with a dismiss,
// the fields the road needs, Cancel and one primary -- and the verb through
// the bridge (POST /api/cmd/MoveDesign -Hub), never a native write. A refusal
// stays in the dialog in the verb's own words; success closes it and the card
// says the verb's line.
//
// A PRODUCT's design (the Design tab, #146) takes the same roads with a
// `checkout`: the verb runs as `MoveDesign -Space <slug>`, in that Space's clone
// on this machine (spaceCheckouts.<slug>.path), where it stages and never
// commits. Success then keeps the dialog open on what was staged and the commit
// line the verb suggests: the commit is the engineer's to make.

/** What a road asks for before it runs: the drop its reason, the completion
 *  the path the docs landed in; a graduation and a shipped archive nothing. */
export type MoveRoad = "spec" | "shipped" | "dropped" | "complete";

/** A hub design's own move: a graduation is on no other record. Its archives
 *  and its completion are the vocabulary's (shared/CardActions ROW). */
export const DESIGN_MOVES = defineRowMoves("design", {
  graduate: { word: "Graduate to a spec", icon: HatGraduationRegular },
});

function road(move: RowMove, detail?: string) {
  return { move, detail, label: move.label(detail) };
}

export const ROADS: Record<
  MoveRoad,
  {
    /** The row-menu move this road is, and the detail its word takes. */
    move: RowMove;
    detail?: string;
    label: string;
    to: MoveDesignFields["to"];
    dropped?: boolean;
    needs?: "reason" | "doc";
    what: string;
  }
> = {
  spec: {
    ...road(DESIGN_MOVES.graduate),
    to: "Spec",
    what: "Scaffold the spec beside the note, with the note's id, description and thread. The note stays in design/.",
  },
  shipped: {
    ...road(ROW.archive, "as shipped"),
    to: "Archive",
    what: "Move the note to design/archive/ and stamp it Closed and shipped -- a design that shipped as written.",
  },
  dropped: {
    ...road(ROW.archive, "as dropped"),
    to: "Archive",
    dropped: true,
    needs: "reason",
    what: "Move the note to design/archive/ and stamp it Closed and dropped. An idea that never made it is only worth keeping with why.",
  },
  complete: {
    ...road(ROW.complete),
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
  output: {
    fontFamily: tokens.fontFamilyMonospace,
    fontSize: tokens.fontSizeBase200,
    whiteSpace: "pre-wrap",
    overflowWrap: "anywhere",
    margin: 0,
  },
});

/** What a product move staged, in the verb's words, and the commit it suggests. */
function StagedResult({ output, checkout }: { output: string; checkout: ProductCheckout }) {
  const styles = useStyles();
  const commit = suggestedCommitLine(output);
  return (
    <div className={styles.fields} role="status">
      <Caption1>
        Staged in {checkout.root}, not committed. The commit is yours to make
        {commit ? ":" : "."}
      </Caption1>
      {commit ? (
        <Field label="Suggested commit">
          <pre className={styles.output}>{commit}</pre>
        </Field>
      ) : null}
      <Field label="What MoveDesign did">
        <pre className={styles.output}>{output}</pre>
      </Field>
      <Caption1 className={styles.what}>
        This tab reads {checkout.repo} on GitHub, so the row moves once the commit is pushed.
      </Caption1>
    </div>
  );
}

/** Where a product's design is moved: the Space's clone on this machine. */
export interface ProductCheckout {
  /** The Space's slug, which the verb's -Space takes. */
  space: string;
  /** owner/name, as the Design tab reads it. */
  repo: string;
  /** The clone's top level. */
  root: string;
}

export function MoveDesignDialog({
  design,
  road,
  open,
  onClose,
  onMoved,
  checkout,
}: {
  design: Design;
  road: MoveRoad;
  open: boolean;
  onClose: () => void;
  /** The verb's own line, for the card to say. */
  onMoved: (line: string) => void;
  /** A product's design: move it in this clone instead of the hub. */
  checkout?: ProductCheckout;
}) {
  const styles = useStyles();
  const [runMove, { isLoading: moving }] = useRunMoveDesignMutation();
  const [reason, setReason] = useState("");
  const [doc, setDoc] = useState("");
  const [message, setMessage] = useState<string | null>(null);
  // A product move's result: what the verb staged, shown until Done.
  const [staged, setStaged] = useState<string | null>(null);
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
    setStaged(null);
  };

  const run = async () => {
    setMessage(null);
    try {
      const fields = {
        name: moveName(design),
        to: spec.to,
        dropped: spec.dropped,
        reason,
        doc: spec.needs === "doc" ? doc : undefined,
      };
      const params = checkout
        ? buildCheckoutMoveDesignParams({ ...fields, space: checkout.space })
        : buildMoveDesignParams({ ...fields, space: design.space });
      const result = await runMove({ params }).unwrap();
      if (result.status === "success" && checkout) {
        // Staged in the clone, not committed: say so here, and let the tab re-read.
        const line = commandResultMessage(result, "Moved.");
        setStaged(line);
        onMoved(line);
        return;
      }
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
            {staged !== null && checkout ? (
              <StagedResult output={staged} checkout={checkout} />
            ) : (
              <div className={styles.fields}>
                <Caption1 className={styles.what}>{spec.what}</Caption1>
                {checkout ? (
                  <Caption1 className={styles.what}>
                    In {checkout.root}, the {checkout.repo} checkout on this machine: staged there,
                    never committed.
                  </Caption1>
                ) : null}
                {spec.needs === "doc" ? (
                  <Field
                    label="Where the docs landed"
                    required
                    hint={`A path in ${checkout ? checkout.repo : "the hub"}, e.g. docs/board.md. The spec is not complete until its durable part has a home.`}
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
            )}
          </DialogContent>
          <DialogActions>
            {staged !== null ? (
              <Button
                appearance="primary"
                onClick={() => {
                  reset();
                  onClose();
                }}
              >
                Done
              </Button>
            ) : (
              <>
                <DialogTrigger disableButtonEnhancement>
                  <Button appearance="secondary">Cancel</Button>
                </DialogTrigger>
                <Button appearance="primary" onClick={run} disabled={!ready || moving}>
                  {moving ? "Moving…" : spec.label}
                </Button>
              </>
            )}
          </DialogActions>
        </DialogBody>
      </DialogSurface>
    </Dialog>
  );
}
