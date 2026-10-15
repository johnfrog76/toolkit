/**
 * "Remind me about this" on a card: the organize module's New Reminder dialog,
 * pre-filled with the card's title and its id as the ref.
 *
 * The ADO core is always on and organize is opt-in, so the dialog is a
 * `lazyPart` -- a chunk fetched the first time it is drawn, and it is drawn
 * only after a person chose the menu item, which cardActions.ts offers only
 * while `features.organize` is on. With the flag off, nothing of the organize
 * module is fetched from here (docs/modules/organize.md, "The web UI").
 */
import { useCallback, useState } from "react";
import type { ReactElement } from "react";
import { lazyPart } from "../../shell/lazy";
import type { PromptInfo } from "./api.ado";

const NewReminderDialog = lazyPart(
  () => import("../organize/NewReminderDialog"),
  (m) => m.NewReminderDialog,
  null,
);

/** What a card puts in the dialog: what the work is called, and its id. */
export function reminderPrefill(card: Pick<PromptInfo, "id" | "name" | "title" | "file">): {
  title: string;
  ref: string;
} {
  return { title: card.name || card.title || card.file, ref: card.id ?? "" };
}

export function useRemindAbout(): {
  open: (card: PromptInfo) => void;
  /** The dialog while a card asked for it; null otherwise. */
  dialog: ReactElement | null;
  /** The sentence said once a reminder was added. */
  added: string | null;
  clearAdded: () => void;
} {
  const [card, setCard] = useState<PromptInfo | null>(null);
  const [added, setAdded] = useState<string | null>(null);

  const open = useCallback((c: PromptInfo) => {
    setAdded(null);
    setCard(c);
  }, []);

  // Keyed on the card, so choosing another card's item starts from its prefill.
  const dialog = card ? (
    <NewReminderDialog
      key={card.file}
      open
      prefill={reminderPrefill(card)}
      onClose={() => setCard(null)}
      onAdded={() => {
        setAdded(`Reminder added about ${reminderPrefill(card).title}. It is on the Organize tab.`);
        setCard(null);
      }}
    />
  ) : null;

  return { open, dialog, added, clearAdded: () => setAdded(null) };
}
