/**
 * The sentence under the week on Daily Activity: what the days were built from, and
 * what was left off. A timesheet is filled in from this page, so a card that is NOT on
 * it has to be accounted for in words -- "3 cards" missing silently reads as a bug.
 *
 * The subtitle at the top of the page already says the cards' dates decide; that is
 * true of every hub and stays static. Everything here is conditional on the week that
 * was actually built -- whether git enriched it, and which cards were left off -- which
 * is why it sits under the days rather than in the subtitle.
 */
import type { BillingResponse } from "./api.ado";

const cards = (n: number) => (n === 1 ? "1 card" : `${n} cards`);

export function billingNote(
  data: Pick<BillingResponse, "source" | "nonBillable" | "unstamped"> | undefined,
): string {
  if (!data) return "";
  const parts: string[] = [];
  if (data.source === "stamps+git") {
    parts.push("Built from the cards' own dates, plus the days git saw them worked.");
  } else if (data.source === "stamps") {
    parts.push("Built from the cards' own dates.");
  }
  const off = data.nonBillable ?? 0;
  if (off > 0)
    parts.push(`${cards(off)} marked not billable ${off === 1 ? "is" : "are"} left off.`);
  const blank = data.unstamped ?? 0;
  if (blank > 0) {
    parts.push(`${cards(blank)} ${blank === 1 ? "has" : "have"} no date and could not be placed.`);
  }
  return parts.join(" ");
}
