// The Issues tab's filter choices, held ONCE for two readers:
// the filter drawer, where they are set, and the list under it, which applies
// them. Each is remembered per browser under its own key, and a change in one
// place re-renders the other (useSharedPersistedValue).
import { useSharedPersistedValue } from "../../shared/usePersistedState";
import {
  ISSUE_ASSIGNEE_KEY,
  ISSUE_KIND_KEY,
  ISSUE_MILESTONE_KEY,
  ISSUE_SEV_KEY,
  ISSUE_STATE_KEY,
  ISSUE_WORKER_KEY,
  KIND_CHOICES,
  SEV_CHOICES,
  STATE_CHIPS,
  orderWorkers,
} from "./issueAxes";
import type { AssigneeChoice, IssueFilterChoice, IssueStateChoice } from "./issueAxes";

export interface IssueChoices {
  /** What was chosen, as remembered -- before the list has been read. */
  stored: IssueFilterChoice;
  setState: (v: IssueStateChoice) => void;
  setAssignee: (v: AssigneeChoice) => void;
  setWorker: (v: string) => void;
  setKind: (v: string) => void;
  setSev: (v: string) => void;
  setMilestone: (v: string) => void;
  /** The two axes the AGENT answers: GET /api/work-items?state=&all=. */
  queryArg: { all: boolean; state: IssueStateChoice };
}

export function useIssueChoices(): IssueChoices {
  const state = useSharedPersistedValue(ISSUE_STATE_KEY, "open", (v) =>
    STATE_CHIPS.some((c) => c.value === v),
  );
  const assignee = useSharedPersistedValue(
    ISSUE_ASSIGNEE_KEY,
    "all",
    (v) => v === "all" || v === "me",
  );
  const worker = useSharedPersistedValue(ISSUE_WORKER_KEY, "all");
  const kind = useSharedPersistedValue(
    ISSUE_KIND_KEY,
    "all",
    (v) => v === "all" || (KIND_CHOICES as readonly string[]).includes(v),
  );
  const sev = useSharedPersistedValue(
    ISSUE_SEV_KEY,
    "all",
    (v) => v === "all" || (SEV_CHOICES as readonly string[]).includes(v),
  );
  const milestone = useSharedPersistedValue(ISSUE_MILESTONE_KEY, "all");
  const stored: IssueFilterChoice = {
    state: state.value as IssueStateChoice,
    assignee: assignee.value as AssigneeChoice,
    worker: worker.value,
    kind: kind.value,
    sev: sev.value,
    milestone: milestone.value,
  };
  return {
    stored,
    setState: state.setValue,
    setAssignee: assignee.setValue,
    setWorker: worker.setValue,
    setKind: kind.setValue,
    setSev: sev.setValue,
    setMilestone: milestone.setValue,
    queryArg: { all: stored.assignee !== "me", state: stored.state },
  };
}

/** The choices in effect against the rows the agent answered, and the options
 *  those rows offer. A remembered worker or milestone the list no longer
 *  carries reads as all -- otherwise its chip would be gone and the filter
 *  would hide everything with nothing on screen to undo it. */
export function effectiveIssueChoice(
  stored: IssueFilterChoice,
  items: { worker?: string; sprint: string }[],
): { choice: IssueFilterChoice; workers: string[]; milestones: string[] } {
  const workers = orderWorkers(items.map((i) => i.worker ?? ""));
  const milestones = Array.from(new Set(items.map((i) => i.sprint).filter(Boolean)));
  return {
    choice: {
      ...stored,
      worker: workers.includes(stored.worker) ? stored.worker : "all",
      milestone: milestones.includes(stored.milestone) ? stored.milestone : "all",
    },
    workers,
    milestones,
  };
}
