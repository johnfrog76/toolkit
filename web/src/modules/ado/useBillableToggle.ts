/**
 * The one way the web marks a card not billable, or billable again.
 *
 * It is a form over the CLI's `Billable` verb (`POST /api/cmd/Billable`), not a
 * second writer. The mutation invalidates `Status` and `Billing`, so the mark on
 * the card and the week on Daily both come from the refetch -- nothing here keeps
 * a copy of the answer, and there is no optimistic update to roll back.
 */
import { useCallback, useState } from "react";
import { useSetBillableMutation } from "./api.ado";
import type { CommandResponse, PromptInfo } from "./api.ado";

export interface BillableOutcome {
  file: string;
  /** What was asked for: true = billable again, false = not billable. */
  billable: boolean;
  result: CommandResponse;
}

// The menu item's words live with the rest of a card's actions (cardActions.ts,
// which is pure and must not pull the API in to say one sentence).
export { billableActionLabel } from "./cardActions";

/** The sentence said once the write came back. */
export function billableOutcomeMessage(outcome: BillableOutcome, name: string): string {
  return outcome.billable
    ? `${name} is billable again -- it is back on Daily.`
    : `${name} is not billable -- it stays off Daily.`;
}

export function useBillableToggle() {
  const [setBillable] = useSetBillableMutation();
  const [busyFile, setBusyFile] = useState<string | null>(null);
  const [outcome, setOutcome] = useState<BillableOutcome | null>(null);

  const toggle = useCallback(
    async (card: Pick<PromptInfo, "file" | "billable">) => {
      const billable = !card.billable;
      setBusyFile(card.file);
      setOutcome(null);
      try {
        const result = await setBillable({ file: card.file, billable }).unwrap();
        setOutcome({ file: card.file, billable, result });
      } catch {
        setOutcome({
          file: card.file,
          billable,
          result: {
            command: "Billable",
            status: "error",
            exit_code: -1,
            output: null,
            error: "Could not reach the agent. The card was not changed.",
            duration: 0,
          },
        });
      } finally {
        setBusyFile(null);
      }
    },
    [setBillable],
  );

  return { toggle, busyFile, outcome, clearOutcome: () => setOutcome(null) };
}
