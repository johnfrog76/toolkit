/**
 * The three stages a session moves through, in one place -- and which
 * `MeetingAgenda` switch takes a session to the next one.
 *
 * The keys are what `## Stage` holds in the file and what `MeetingAgenda -Plan`,
 * `-Prep` and `-Retro` write; the labels are what a badge shows. The list was
 * typed in the Meetings card and again in the read view, one with a `next` and
 * one without, which is the drift the repo's magic-string rule exists to stop.
 */
import { FOLDERS } from "../../shell/consts";

export interface WorkflowStage {
  /** What the file says under `## Stage`. */
  key: "draft" | "prep" | "retro";
  /** What a person reads: the stage the session is IN, not the file's word. */
  label: "Plan" | "Prep" | "Retro";
  color: "brand" | "warning" | "success";
}

export const WORKFLOW_STAGES: readonly WorkflowStage[] = [
  { key: "draft", label: "Plan", color: "brand" },
  { key: "prep", label: "Prep", color: "warning" },
  { key: "retro", label: "Retro", color: "success" },
];

/** The stage a file's word names; an unknown or empty word reads as the first. */
export function stageOf(key: string | undefined): WorkflowStage {
  return WORKFLOW_STAGES.find((s) => s.key === key) ?? WORKFLOW_STAGES[0];
}

/** The stage after this one, or null at the last -- what "Next up" names. */
export function stageAfter(key: string | undefined): WorkflowStage | null {
  const idx = WORKFLOW_STAGES.findIndex((s) => s.key === key);
  return idx >= 0 ? (WORKFLOW_STAGES[idx + 1] ?? null) : WORKFLOW_STAGES[1];
}

/** A session whose stages are all behind it: the one thing left is to close it. */
export function isComplete(key: string | undefined): boolean {
  return stageAfter(key) === null;
}

/**
 * The one `MeetingAgenda` switch the session page offers: the stage AHEAD, and
 * only that one (Scripts/Get-MeetingAgenda.ps1). `-Plan` creates the file if it
 * is missing and stamps `draft`; `-Prep` and `-Retro` need the file and stamp
 * their word. A session the page shows already exists, so:
 *
 *   no stage yet   -> Plan   (the file's ## Stage is blank or unknown: stamp it)
 *   draft          -> Prep
 *   prep           -> Retro
 *   retro          -> null   (the step after Retro is Close, which moves a file
 *                             and has its own button and its own confirm)
 *   closed         -> null   (archive/ is the record; nothing stamps it)
 */
export function nextStageAction(
  key: string | undefined,
  folder?: string,
): "Plan" | "Prep" | "Retro" | null {
  if (folder === FOLDERS.archive) return null;
  if (!WORKFLOW_STAGES.some((s) => s.key === key)) return "Plan";
  const next = stageAfter(key);
  return next ? next.label : null;
}
