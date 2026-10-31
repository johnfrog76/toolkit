/**
 * Plan milestone, Plan sprint and Tag, from a card's row menu: one small form over
 * the CLI's `Plan` and `Tag` verbs (`POST /api/cmd/Plan`, `POST /api/cmd/Tag`). The
 * verbs write the card's lines through `Set-P20CardLine`; nothing here writes a card,
 * and nothing here touches the tracker (docs/hub/cards.md, "Milestone and sprint: two
 * lines"). The page re-reads the card from the refetch the mutation triggers.
 */
import { useCallback, useState } from "react";
import type { ReactElement } from "react";
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
  Field,
  Input,
} from "@fluentui/react-components";
import { DialogDismiss } from "../../shared/DialogDismiss";
import { StatusMessage } from "../../shared/StatusMessage";
import { usePlanCardMutation, useTagCardMutation } from "./api.ado";
import type { CommandResponse, PromptInfo } from "./api.ado";
import { commandResultMessage } from "./cliBridge";

/** Which of the card's lines the form edits. */
export type PlanKind = "milestone" | "sprint" | "tags";

const NOUN: Record<PlanKind, string> = { milestone: "Milestone", sprint: "Sprint", tags: "Tags" };

/** What the card says now, in words: the line's value, or "none". */
export function currentValue(
  card: Pick<PromptInfo, "milestone" | "sprint" | "tags">,
  kind: PlanKind,
): string {
  if (kind === "milestone") return card.milestone || "none";
  if (kind === "tags") return (card.tags ?? []).join(", ") || "none";
  const s = card.sprint;
  return s && s !== "--" && !s.startsWith("(") ? s : "none";
}

/** The tags typed in the box: split on commas, trimmed, the empty ones dropped. */
export function typedTags(text: string): string[] {
  return text
    .split(",")
    .map((t) => t.trim())
    .filter(Boolean);
}

const unreachable = (command: string): CommandResponse => ({
  command,
  status: "error",
  exit_code: -1,
  output: null,
  error: "Could not reach the agent. The card was not changed.",
  duration: 0,
});

interface PlanCardDialogProps {
  card: PromptInfo;
  kind: PlanKind;
  onClose: () => void;
  /** The verb answered success: what it said, for the page to show once. */
  onDone: (message: string) => void;
}

export function PlanCardDialog({ card, kind, onClose, onDone }: PlanCardDialogProps) {
  const [planCard, planState] = usePlanCardMutation();
  const [tagCard, tagState] = useTagCardMutation();
  const [text, setText] = useState(kind === "milestone" ? (card.milestone ?? "") : "");
  const [failed, setFailed] = useState<string | null>(null);
  const busy = planState.isLoading || tagState.isLoading;
  const name = card.name || card.title || card.file;
  const now = currentValue(card, kind);

  const run = async (call: () => Promise<CommandResponse>, command: string) => {
    setFailed(null);
    let result: CommandResponse;
    try {
      result = await call();
    } catch {
      result = unreachable(command);
    }
    if (result.status === "success") {
      onDone(commandResultMessage(result, `${name} was changed.`));
    } else {
      setFailed(commandResultMessage(result, `${name} was not changed.`));
    }
  };

  const save = () =>
    kind === "tags"
      ? run(() => tagCard({ file: card.file, tags: typedTags(text) }).unwrap(), "Tag")
      : run(() => planCard({ file: card.file, line: kind, title: text }).unwrap(), "Plan");
  const clear = () =>
    kind === "tags"
      ? run(() => tagCard({ file: card.file, tags: typedTags(text), remove: true }).unwrap(), "Tag")
      : run(() => planCard({ file: card.file, line: kind, remove: true }).unwrap(), "Plan");

  const empty = kind === "tags" ? typedTags(text).length === 0 : !text.trim();
  const label = kind === "tags" ? "Tags, with commas between" : NOUN[kind];

  return (
    <Dialog open onOpenChange={(_e, d) => (!d.open ? onClose() : undefined)}>
      <DialogSurface aria-label={`${NOUN[kind]} for ${name}`}>
        <DialogBody>
          <DialogTitle action={<DialogDismiss />}>
            {NOUN[kind]} for {name}
          </DialogTitle>
          <DialogContent>
            <Body1>
              Now: <strong>{now}</strong>
            </Body1>
            <Field label={label}>
              <Input
                value={text}
                onChange={(_e, d) => setText(d.value)}
                disabled={busy}
                onKeyDown={(e) => {
                  if (e.key === "Enter" && !empty && !busy) void save();
                }}
              />
            </Field>
            <Caption1>
              {kind === "tags"
                ? "Add puts these on the card's Tags line; Take off removes them. A tag it already carries is not added twice."
                : `Written whole on the card's own ${NOUN[kind]} line, never on the tracker.`}
            </Caption1>
            {failed ? <StatusMessage status="error">{failed}</StatusMessage> : null}
          </DialogContent>
          <DialogActions>
            {kind === "tags" ? (
              <Button disabled={busy || empty} onClick={() => void clear()}>
                Take off
              </Button>
            ) : now !== "none" ? (
              <Button disabled={busy} onClick={() => void clear()}>
                Clear {NOUN[kind].toLowerCase()}
              </Button>
            ) : null}
            <Button appearance="secondary" disabled={busy} onClick={onClose}>
              Cancel
            </Button>
            <Button appearance="primary" disabled={busy || empty} onClick={() => void save()}>
              {kind === "tags" ? "Add" : "Save"}
            </Button>
          </DialogActions>
        </DialogBody>
      </DialogSurface>
    </Dialog>
  );
}

/** The form, opened from a card's row menu, and the sentence said once it wrote. */
export function usePlanCard(): {
  open: (card: PromptInfo, kind: PlanKind) => void;
  dialog: ReactElement | null;
  done: string | null;
  clearDone: () => void;
} {
  const [target, setTarget] = useState<{ card: PromptInfo; kind: PlanKind } | null>(null);
  const [done, setDone] = useState<string | null>(null);
  const open = useCallback((card: PromptInfo, kind: PlanKind) => {
    setDone(null);
    setTarget({ card, kind });
  }, []);
  const dialog = target ? (
    <PlanCardDialog
      key={`${target.card.file}:${target.kind}`}
      card={target.card}
      kind={target.kind}
      onClose={() => setTarget(null)}
      onDone={(message) => {
        setDone(message);
        setTarget(null);
      }}
    />
  ) : null;
  return { open, dialog, done, clearDone: () => setDone(null) };
}
