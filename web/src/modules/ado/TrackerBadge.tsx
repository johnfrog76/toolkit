import { Badge, Tooltip } from "@fluentui/react-components";

// WHERE, the first chip of the chip grammar: whose ledger stands behind
// this card -- (gh), (ado), or nothing. The fact is the card model's `tracker`,
// which the agent derives by running the ONE tracker rule over the card's OWN
// link (agent/core/parsers.py -> config.tracker), never over the Space's
// address, so a card stays honest in a mixed Space and when it moves. Nothing
// here reads a URL. A custom card wears no badge: unlabeled IS its label.
//
// The Issues tab's rows wear the same chip (MyWork.tsx), so a GitHub issue and
// the card picked up from it read the same at a glance.

const CHIP: Record<string, { label: string; says: string }> = {
  github: { label: "gh", says: "Linked to a GitHub issue" },
  ado: { label: "ado", says: "Linked to an Azure DevOps work item" },
};

// A tracker's NAME, as a sentence says it (name the place and the thing).
// One table, so "Pinned on GitHub" and "Open on GitHub" read the
// Space's tracker rather than a literal -- a second tracker says its own name.
const NAME: Record<string, string> = {
  github: "GitHub",
  ado: "Azure DevOps",
};

/** The tracker's name for a sentence ("GitHub", "Azure DevOps"), or "" for
 *  none or unknown. */
export function trackerName(tracker: string | undefined | null): string {
  return (tracker && NAME[tracker]) || "";
}

/** The chip's word for a tracker, or null for "none", unknown, or an older
 *  agent that does not serve the field. */
export function trackerChip(tracker: string | undefined | null): string | null {
  return (tracker && CHIP[tracker]?.label) || null;
}

export function TrackerBadge({ tracker }: { tracker: string | undefined | null }) {
  const chip = tracker ? CHIP[tracker] : undefined;
  if (!chip) return null;
  return (
    <Tooltip content={chip.says} relationship="description">
      <Badge appearance="outline" size="small" color="informative" data-tracker-badge={tracker}>
        {chip.label}
      </Badge>
    </Tooltip>
  );
}
