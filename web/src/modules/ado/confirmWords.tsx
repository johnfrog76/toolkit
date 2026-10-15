import type { ReactNode } from "react";

// What the archive confirm says, once. The list's row and the board's card
// both archive a card, and each wrote its own question -- "Archive Prompt /
// Are you sure? Archive card X" on one, "Archive this card? X moves to the
// archive..." on the other. One act, one sentence: the act named, then
// what follows it.

/** `what` for the shared ConfirmDialog when a card is archived. */
export function archiveWhat(name: string): ReactNode {
  return (
    <>
      Archive card <strong>{name}</strong>. It moves to the archive, stamped closed today -- a card
      travels one way.
    </>
  );
}
