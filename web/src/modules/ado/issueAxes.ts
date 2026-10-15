// The Issues tab's three axes -- state, assignee, worked by -- three
// controls, never one. State and assignee are asked of the agent
// (GET /api/work-items?state=&all=); worked by filters the list it answered.
// Pure, so the path and the order are tested without a store.

/** The ledger's state axis, in gh's own words. Open is the route's default. */
export type IssueStateChoice = "all" | "open" | "closed";

/** Where each choice is remembered, per browser -- shared by the filter
 *  drawer that sets it and the list that reads it
 *  (useSharedPersistedValue). */
export const ISSUE_STATE_KEY = "ado.issues.state";
export const ISSUE_ASSIGNEE_KEY = "ado.issues.assignee";
export const ISSUE_WORKER_KEY = "ado.issues.worker";
/** GitHub's own label vocabulary, in the drawer. */
export const ISSUE_KIND_KEY = "ado.issues.kind";
export const ISSUE_SEV_KEY = "ado.issues.sev";
export const ISSUE_MILESTONE_KEY = "ado.issues.milestone";

export type AssigneeChoice = "all" | "me";

/** The chips' words, one place: the drawer draws them, the tab's summary
 *  line repeats the active ones. */
export const STATE_CHIPS: { value: IssueStateChoice; label: string }[] = [
  { value: "all", label: "all issues" },
  { value: "open", label: "open" },
  { value: "closed", label: "closed" },
];
export const ASSIGNEE_CHIPS: { value: AssigneeChoice; label: string }[] = [
  { value: "all", label: "assigned to all" },
  { value: "me", label: "me" },
];
/** GitHub's kinds -- `bug`, `enhancement` (feat), no label (issue). */
export const KIND_CHOICES = ["bug", "feat", "issue"] as const;
export const SEV_CHOICES = ["sev1", "sev2", "sev3"] as const;

/** What the list is asked to show, all six axes. "all" is off. */
export interface IssueFilterChoice {
  state: IssueStateChoice;
  assignee: AssigneeChoice;
  worker: string;
  kind: string;
  sev: string;
  milestone: string;
}

interface IssueLike {
  id: number;
  title: string;
  type: string;
  labels?: string[];
  sprint: string;
  worker?: string;
}

/** The kind word a row wears: `feat` for GitHub's enhancement, else the type. */
export function issueKind(i: Pick<IssueLike, "type">): string {
  return i.type === "Feature" ? "feat" : i.type.toLowerCase();
}

/** The three list-side axes -- worked by, kind, sev, milestone -- over the
 *  rows the agent answered for the other two. */
export function filterIssues<T extends IssueLike>(items: T[], f: IssueFilterChoice): T[] {
  return items.filter((i) => {
    if (f.kind !== "all" && issueKind(i) !== f.kind) return false;
    if (f.sev !== "all" && !(i.labels ?? []).includes(f.sev)) return false;
    if (f.milestone !== "all" && i.sprint !== f.milestone) return false;
    if (f.worker !== "all" && i.worker !== f.worker) return false;
    return true;
  });
}

/** Search, on the Issues: a NUMBER is an id and matches that issue only
 *  (a number, with or without a leading `#`, never one it is merely inside -- an id is not a substring); anything else is
 *  words, every one found in the title, the labels, the worker or the
 *  milestone, in any order. */
export function issueMatches(i: IssueLike, text: string): boolean {
  const t = text.trim();
  if (!t) return true;
  const num = /^#?(\d+)$/.exec(t);
  if (num) return i.id === Number(num[1]);
  const hay = [i.title, ...(i.labels ?? []), i.worker ?? "", i.sprint].join(" ").toLowerCase();
  return t
    .toLowerCase()
    .split(/\s+/)
    .every((w) => hay.includes(w));
}

/** The tab's one-line summary of what the drawer is set to: the chips
 *  live in the drawer, and the list says what they are showing. */
export function issueFilterSummary(f: IssueFilterChoice, text = ""): string {
  const parts: string[] = [
    f.state === "all" ? "all issues" : `${f.state} issues`,
    f.assignee === "me" ? "assigned to me" : "assigned to all",
  ];
  if (f.worker !== "all") parts.push(`worked by ${f.worker}`);
  if (f.kind !== "all") parts.push(f.kind);
  if (f.sev !== "all") parts.push(f.sev);
  if (f.milestone !== "all") parts.push(`milestone ${f.milestone}`);
  if (text.trim()) parts.push(`matching "${text.trim()}"`);
  return parts.join(" · ");
}

/** GET /api/work-items's path for the two agent axes: assignee (`all=1`)
 *  and state (`state=closed|all`; open is the default, so it goes unsaid). */
export function workItemsPath(arg?: { all?: boolean; state?: IssueStateChoice }): string {
  const params: string[] = [];
  if (arg?.all) params.push("all=1");
  if (arg?.state && arg.state !== "open") params.push(`state=${arg.state}`);
  return params.length ? `work-items?${params.join("&")}` : "work-items";
}

/** Pinned rows first -- the tracker's own pin -- keeping the agent's
 *  order inside each half (open before closed, newest first). Applied AFTER
 *  the filters, so a filter still answers its question: a pinned issue routed
 *  to one worker does not appear under another. */
export function pinnedFirst<T extends { pinned?: boolean }>(items: T[]): T[] {
  return [...items.filter((i) => i.pinned), ...items.filter((i) => !i.pinned)];
}

/** The workers issues are routed to, in the order the owner reads them. The chips
 *  are whatever worker labels the list carries (the agent reads a worker from
 *  the label's own description, "Routed to ..."), so a fourth is a label
 *  away: these three lead, in this order, when present, and any other
 *  follows alphabetically. */
const WORKER_ORDER = ["opus", "fable", "sonnet"];

export function orderWorkers(present: string[]): string[] {
  const rank = (w: string) => {
    const i = WORKER_ORDER.indexOf(w);
    return i === -1 ? WORKER_ORDER.length : i;
  };
  return Array.from(new Set(present.filter(Boolean))).sort(
    (a, b) => rank(a) - rank(b) || a.localeCompare(b),
  );
}
