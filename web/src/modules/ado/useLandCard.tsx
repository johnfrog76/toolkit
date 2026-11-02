/**
 * Land on a card: the merge recorded, the issue closed, the card archived.
 *
 * A form over the CLI's `Land` verb (`POST /api/cmd/Land`), not a second
 * closer or archiver -- the bridge runs the verb, and the refetch is what takes
 * the card off the board. Offered on every Code Review card (cardActions.ts);
 * whether the pull request merged is the verb's question, not the board's. It
 * closes an issue other people read, so it asks first, in the one confirm
 * (shared/ConfirmDialog). A refusal -- the pull request is not merged yet, the
 * issue could not be closed -- keeps the dialog open with the verb's own sentence.
 *
 * The mutation lives in the dialog, which is drawn only once a person chose
 * Land, so a view that never offers it never touches it.
 */
import { useCallback, useState } from "react";
import type { ReactElement } from "react";
import { ConfirmDialog } from "../../shared/ConfirmDialog";
import { useLandCardMutation } from "./api.ado";
import type { PromptInfo } from "./api.ado";
import { commandResultMessage } from "./cliBridge";

type LandCard = Pick<PromptInfo, "file" | "name" | "title">;

/** What the card is called, for the sentences. */
export function landName(card: LandCard): string {
  return card.name || card.title || card.file;
}

/** `what` for the confirm: the act, then what follows it. */
export function landWhat(card: LandCard) {
  return (
    <>
      Land <strong>{landName(card)}</strong>. Its merge is recorded on the card, the issue behind it
      is closed with a comment naming the commit, and the card moves to the archive.
    </>
  );
}

function LandConfirm({
  card,
  onCancel,
  onLanded,
}: {
  card: LandCard;
  onCancel: () => void;
  onLanded: (sentence: string) => void;
}) {
  const [land] = useLandCardMutation();
  const [busy, setBusy] = useState(false);
  const [message, setMessage] = useState<string | null>(null);

  const confirm = async () => {
    setBusy(true);
    setMessage(null);
    try {
      const result = await land({ file: card.file }).unwrap();
      if (result.status === "success") {
        onLanded(`Landed ${landName(card)} -- recorded, closed and archived.`);
        return;
      }
      setMessage(commandResultMessage(result, `${landName(card)} was not landed`));
    } catch {
      setMessage("Could not reach the agent. The card was not changed.");
    } finally {
      setBusy(false);
    }
  };

  return (
    <ConfirmDialog
      open
      what={landWhat(card)}
      confirmLabel="Land"
      busy={busy}
      message={message}
      onCancel={onCancel}
      onConfirm={() => void confirm()}
    />
  );
}

export function useLandCard(): {
  open: (card: PromptInfo) => void;
  /** The confirm while a card asked for it; null otherwise. */
  dialog: ReactElement | null;
  /** The sentence said once a card landed. */
  landed: string | null;
  clearLanded: () => void;
} {
  const [card, setCard] = useState<PromptInfo | null>(null);
  const [landed, setLanded] = useState<string | null>(null);

  const open = useCallback((c: PromptInfo) => {
    setLanded(null);
    setCard(c);
  }, []);

  // Keyed on the card, so choosing another card starts from nothing said.
  const dialog = card ? (
    <LandConfirm
      key={card.file}
      card={card}
      onCancel={() => setCard(null)}
      onLanded={(sentence) => {
        setLanded(sentence);
        setCard(null);
      }}
    />
  ) : null;

  return { open, dialog, landed, clearLanded: () => setLanded(null) };
}
