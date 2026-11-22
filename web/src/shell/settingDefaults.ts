/**
 * The way back to unset, as every choice of a setting draws it: the
 * Configuration section's select and the drawer's asking radios both offer it
 * first, as one entry named "Default".
 *
 * The entry names what unset reads as only where the contract fixes ONE value
 * (the standup's size: `consts.json` `rituals.teamSizeDefault`). Where unset is
 * derived -- How you work here follows the tracker -- it is plain "Default":
 * the form never types a value the CLI and the agent work out.
 *
 * Keyed by SCHEMA key, `spaces.<slug>.<field>`, the shape GET
 * /api/config/schema serves.
 */
import { RITUALS } from "./consts";

export const DEFAULT_WORD = "Default";

const UNSET_READS: Record<string, string> = {
  "spaces.<slug>.features.teamSize": String(RITUALS.teamSizeDefault),
};

/** The label of a choice's unset entry: "Default (9)", or "Default". */
export function defaultLabel(schemaKey: string): string {
  const reads = UNSET_READS[schemaKey];
  return reads ? `${DEFAULT_WORD} (${reads})` : DEFAULT_WORD;
}
