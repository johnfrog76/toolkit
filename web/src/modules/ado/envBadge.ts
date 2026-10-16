/**
 * The headline of the Environment card: one word, one colour, one sentence.
 *
 * It used to be a function of the TIER alone, and three different machines are
 * all tier 2 -- an archived org (Azure DevOps is never contacted), a local one
 * (never contacted, by choice) and an active one that tried and failed. All three
 * read "Local", in warning yellow, "ADO unreachable". The owner's rule: "this
 * should say archive ... archive doesn't request at all, and local tried and
 * failed to get access." Only the last of the three is a warning.
 *
 * The word, the colour and the sentence come back TOGETHER so they cannot
 * disagree, which is how the old three functions came to.
 *
 * And one word means one thing: "Local" is the org that works
 * from its cards by choice, in GREEN -- "we proud to be local now". The active
 * org that tried and failed is "Offline", the only yellow here.
 */
import type { EnvStatus } from "../../shell/api";
import { trackerName } from "./TrackerBadge";

export interface EnvBadge {
  label: string;
  color: "success" | "warning" | "danger" | "informative";
  tooltip: string;
}

/** What each Environment check is CALLED (the string pass): the place and
 *  the thing -- the hub, its cards, the Space's tracker -- in the product's own
 *  words. "Prompts" was the predecessor's word for a card, and "ADO Add-on" read
 *  as Azure DevOps on a GitHub Space (D-G13), so the tracker row wears its
 *  tracker's name. The keys stay the agent's; an unknown key shows as itself. */
export function checkLabel(key: string, tracker: EnvStatus["tracker"]): string {
  const labels: Record<string, string> = {
    promptsVolume: "Hub folder",
    hubManifest: "Hub manifest",
    promptsWritable: "Hub is writable",
    configLoaded: "Settings files",
    gitHistory: "Hub git history",
    activePrompts: "Cards in this Space",
    adoReachable: trackerName(tracker) || "Tracker",
    orgState: "Space state",
    bridgeHost: "Bridge host",
    identity: "Identity",
  };
  return labels[key] ?? key;
}

export function envBadge(
  env: Pick<EnvStatus, "tier" | "spaceStatus"> & Partial<Pick<EnvStatus, "tracker">>,
): EnvBadge {
  // A Space with no tracker (or an older agent that does not say) has no name to give.
  const name = trackerName(env.tracker) || "tracker";
  // Tier 3 is about the machine, not the org: nothing else matters until it is fixed.
  if (env.tier >= 3) {
    return {
      label: "Minimal",
      color: "danger",
      tooltip: "Minimal -- this machine has no Toolkit repo or no git",
    };
  }
  if (env.spaceStatus === "archive") {
    return {
      label: "Archive",
      color: "informative",
      tooltip:
        "Archive -- this Space is a finished engagement, kept for looking back. Its tracker is never contacted.",
    };
  }
  if (env.spaceStatus === "local") {
    return {
      label: "Local",
      color: "success",
      tooltip:
        "Local -- this Space works from your cards alone. No tracker is contacted, by choice.",
    };
  }
  if (env.tier === 1) {
    return {
      label: "Full",
      color: "success",
      tooltip: `Full -- this Space's ${name} answered, and this machine has the repo and git`,
    };
  }
  // An ACTIVE Space that is not at tier 1: it tried, and its tracker did not answer.
  return {
    label: "Offline",
    color: "warning",
    tooltip: `Offline -- this machine has the repo and git, but this Space's ${name} could not be reached`,
  };
}
