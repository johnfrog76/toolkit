import type { StandupResponse, Suggestion } from "./api.solitaireAgile";
import { briefSansCorner } from "./corner";

// The chair's suggestion as the Team Agile page reads it (AR-3; docs/modules/
// solitaire-agile.md, "The suggestion: one next move, derived"). Pure, and kept
// out of the page so the scenarios test can read it without drawing anything.

/** What `StartWork` is given for a suggestion: the issue's number, else the card's id. */
export const suggestionArg = (s: Suggestion): string =>
  s.number != null ? String(s.number) : (s.id ?? "");

/** The chair's suggestion as the page draws it. `standing`: the brief's last line
 *  IS the first candidate's line (the Space's switch is on and nothing waits --
 *  D-AR7); `current`: the first candidate not dismissed on this surface, or null
 *  when every one is. With nothing standing the brief is drawn as it came. */
export function chairSuggestion(
  data: StandupResponse,
  dismissed: string[],
): { standing: boolean; current: Suggestion | null } {
  // The PM Corner, when attached, is the brief's LAST line (corner.ts): the Next line
  // is the one above it, so the Corner's line is set aside before reading it.
  const lines = briefSansCorner(data).split("\n").filter(Boolean);
  const first = data.suggestion ?? null;
  const standing = !!first && !!first.line && lines[lines.length - 1] === first.line;
  if (!first || !standing) return { standing: false, current: null };
  const current = (data.suggestions ?? [first]).find((s) => !dismissed.includes(s.ref)) ?? null;
  return { standing, current };
}
