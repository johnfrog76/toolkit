import { useMemo, useState } from "react";
import {
  Body1,
  Button,
  Caption1,
  Link,
  Select,
  Subtitle2,
  ToggleButton,
  makeStyles,
  mergeClasses,
  tokens,
} from "@fluentui/react-components";
import { ArrowNextRegular, TaskListLtrRegular } from "@fluentui/react-icons";
import { EmptyState } from "../../shared/EmptyState";
import { PageCard } from "../../shared/PageCard";
import { RefreshButton } from "../../shared/RefreshButton";
import { useGetEnvQuery } from "../../shell/api";
import { RITUALS } from "../../shell/consts";
import { useGetMilestonesQuery } from "../ado/api.ado";
import { ActionDialog } from "../ado/ActionDialog";
import { buildRouteParams, commandResultMessage } from "../ado/cliBridge";
import type { RouteFields } from "../ado/cliBridge";
import { useGetTriageQuery, useRunRouteMutation } from "./api.solitaireAgile";
import type { TriageGroup, TriageIssue, TriageResponse } from "./api.solitaireAgile";

// Triage, `/solitaire-agile/triage` (docs/modules/solitaire-agile.md, "The web UI"):
// the open issues ONE AT A TIME, the ones in no milestone first because nobody
// has placed them, then each milestone as the agent orders them. Above the
// issue, its milestone's context line ("N open, M routed, K unrouted") and who
// has it (D-AR10: me, @<login>, a size, or nobody); under it, the three
// questions -- which milestone, how severe, which size. The third question's
// first answer is **me**: `Route -Assign me`, you become the issue's assignee.
//
// Every answer is ONE write, and a write is the CLI's `Route` through the bridge
// (POST /api/cmd/Route, argv from buildRouteParams) -- a real label or milestone
// on the tracker, nothing stored here (D-TA2). The size IS the worker label
// (D-TA3); deep-water is the fourth answer and offers exactly two moves (D-TA4):
// Assign a worker, and Split: the new-issue dialog (ActionDialog's new-item door)
// opened with this issue named as the parent, so each piece is created through
// POST /api/cmd/NewItem with -Parent and lands as a sub-issue of it (the CLI says
// which link it made). The dialog keeps the parent after a create, so a split
// into several pieces is several creates in one sitting. "Next" skips.
//
// The queue is the read's ORDER taken once, when it first arrives: an answer
// refreshes the read (a milestone moves an issue to another group), and the
// issue in front of you must not jump. Every row below has a fixed box -- the
// title is one line, the deep-water moves row is always there and only shown --
// so nothing moves between issues or while an answer is in flight.

/** The heading the group with no milestone reads under -- this page's label. */
const NO_MILESTONE = "No milestone";
/** The worker deep water's first move assigns (D-TA4): that worker's label. */
const FABLE = "fable";
/** The third question's own answer beside the sizes (D-AR10): `Route -Assign me`. */
const ME = RITUALS.assignMe;
/** What Split does, said on its button: the precedent is GitHub's own "Create sub-issue". */
const SPLIT_TITLE = "Create sub-issues of this one, one at a time";

const useStyles = makeStyles({
  page: { display: "flex", flexDirection: "column", gap: tokens.spacingVerticalM, width: "100%" },
  body: {
    display: "flex",
    flexDirection: "column",
    gap: tokens.spacingVerticalM,
    paddingTop: tokens.spacingVerticalS,
  },
  context: { color: tokens.colorNeutralForeground3, minHeight: tokens.lineHeightBase300 },
  issue: { display: "flex", flexDirection: "column", gap: tokens.spacingVerticalXXS, minWidth: 0 },
  // One line, always: a long title is cut, not wrapped, so the rows below stay put.
  title: { overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap", display: "block" },
  answers: { color: tokens.colorNeutralForeground3, minHeight: tokens.lineHeightBase200 },
  question: {
    display: "flex",
    alignItems: "center",
    gap: tokens.spacingHorizontalM,
    flexWrap: "wrap",
    minHeight: "32px",
  },
  label: { width: "6rem", flexShrink: 0, color: tokens.colorNeutralForeground2 },
  choices: {
    display: "flex",
    gap: tokens.spacingHorizontalS,
    flexWrap: "wrap",
    alignItems: "center",
  },
  select: { minWidth: "16rem" },
  hidden: { visibility: "hidden" },
  // A fixed box: the verb's answer can run to several lines, and it scrolls
  // inside three rather than pushing Next down.
  status: {
    height: `calc(3 * ${tokens.lineHeightBase200})`,
    overflowY: "auto",
    whiteSpace: "pre-wrap",
  },
  error: { color: tokens.colorPaletteRedForeground1 },
  footer: { display: "flex", justifyContent: "flex-end" },
});

/** The order the read gives: each group's issues, group by group. */
export function triageQueue(data: TriageResponse): number[] {
  return data.groups.flatMap((g) => g.issues.map((i) => i.number));
}

/** Where an issue stands in the read now: the issue and its group. */
export function locate(
  data: TriageResponse | undefined,
  n: number,
): { issue: TriageIssue; group: TriageGroup } | null {
  for (const group of data?.groups ?? []) {
    const issue = group.issues.find((i) => i.number === n);
    if (issue) return { issue, group };
  }
  return null;
}

/** The context line above the issue: its milestone (or none), then the counts. */
export function contextLine(group: TriageGroup): string {
  return `${group.milestone || NO_MILESTONE} -- ${group.context}`;
}

/** What the page calls an item nobody has. */
const NOBODY = "nobody";

/** Who has an issue, said (D-AR10): "me", "@<login>", its size's worker name,
 *  or nobody. The agent's `who` decides; a read from an older agent, with no
 *  `who`, falls back to the size it always sent. */
export function whoLabel(issue: TriageIssue): string {
  const who = issue.who ?? issue.size;
  if (issue.size && who === issue.size) return issue.worker || issue.size;
  return who || NOBODY;
}

/** The answers an issue carries, said in one line: who has it, its severity, deep water. */
export function answersLine(issue: TriageIssue, deepWaterLabel: string): string {
  const parts = [whoLabel(issue), issue.severity || "no severity"];
  if (issue.deepWater) parts.push(deepWaterLabel);
  return parts.join(" · ");
}

interface Outcome {
  ok: boolean;
  text: string;
}

export function TriagePage() {
  const styles = useStyles();
  const { data: env, isLoading: envLoading } = useGetEnvQuery();
  const space = env?.config?.activeSpace ?? "";
  const { data, isLoading, isFetching, error, refetch } = useGetTriageQuery(space, {
    skip: envLoading,
  });
  const { data: milestoneData } = useGetMilestonesQuery();
  const [runRoute, { isLoading: busy }] = useRunRouteMutation();

  // The queue and the snapshot are taken from the FIRST read; a refresh after
  // an answer updates what an issue carries, never which issue is in front.
  const [queue, setQueue] = useState<number[] | null>(null);
  const [snapshot, setSnapshot] = useState<TriageResponse | null>(null);
  const [index, setIndex] = useState(0);
  const [deepOpen, setDeepOpen] = useState(false);
  const [outcome, setOutcome] = useState<Outcome | null>(null);
  // The issue being split: the dialog is mounted only while it is open, so its
  // reads run only when Split is used.
  const [splitting, setSplitting] = useState<number | null>(null);

  const readable = !!data && !error;
  // Taken while rendering: once the queue is set the condition is false, so it
  // happens once, and the first frame with data already shows the queue.
  if (readable && queue === null && data.tracker.ok) {
    setQueue(triageQueue(data));
    setSnapshot(data);
  }

  const milestones = useMemo(() => {
    const titles = (milestoneData?.milestones ?? [])
      .filter((m) => m.state === "open")
      .map((m) => m.title);
    return Array.from(new Set(titles));
  }, [milestoneData]);

  const current = queue && index < queue.length ? queue[index] : null;
  const here =
    current === null ? null : (locate(data, current) ?? locate(snapshot ?? undefined, current));

  const next = () => {
    setIndex((i) => i + 1);
    setDeepOpen(false);
    setOutcome(null);
  };
  const startOver = () => {
    setQueue(null);
    setSnapshot(null);
    setIndex(0);
    setDeepOpen(false);
    setOutcome(null);
    void refetch();
  };

  const answer = async (fields: Omit<RouteFields, "number">, done: string) => {
    if (current === null) return;
    setOutcome(null);
    try {
      const result = await runRoute({
        params: buildRouteParams({ number: current, ...fields }),
      }).unwrap();
      setOutcome({ ok: result.status === "success", text: commandResultMessage(result, done) });
    } catch {
      setOutcome({ ok: false, text: "The agent did not answer. Nothing was written." });
    }
  };

  const header = readable ? (data.text.split("\n")[0] ?? "") : "";
  let empty;
  if (!readable) {
    empty = (
      <EmptyState
        icon={<TaskListLtrRegular />}
        tone="error"
        title="Could not read the open issues"
        detail="The agent did not answer. Nothing was read."
      />
    );
  } else if (!data.tracker.ok) {
    empty = (
      <EmptyState
        icon={<TaskListLtrRegular />}
        title="Triage reads a GitHub Space"
        detail={data.tracker.reason}
      />
    );
  } else if (queue !== null && queue.length === 0) {
    empty = <EmptyState icon={<TaskListLtrRegular />} title="Nothing is open to triage" />;
  } else if (queue !== null && current === null) {
    empty = (
      <EmptyState
        icon={<TaskListLtrRegular />}
        title="That was every open issue"
        action={<Button onClick={startOver}>Start again</Button>}
      />
    );
  }

  const issue = here?.issue;
  const sizes = readable ? data.sizes : [];
  const fable = sizes.find((s) => s.label.toLowerCase() === FABLE);
  const deepLabel = readable ? data.deepWaterLabel : "";

  return (
    <div className={styles.page}>
      <PageCard
        loading={envLoading || isLoading}
        loadingLabel="Reading the open issues..."
        empty={empty}
        headerLeft={readable ? <Subtitle2 as="h1">{header}</Subtitle2> : undefined}
        headerRight={
          readable && queue ? (
            <>
              <Caption1>
                {Math.min(index + 1, queue.length)} of {queue.length}
              </Caption1>
              <RefreshButton
                onClick={startOver}
                isFetching={isFetching}
                title="Read the issues again"
              />
            </>
          ) : undefined
        }
      >
        {issue && here && (
          <div className={styles.body} data-testid="triage-issue">
            <Body1 className={styles.context} data-testid="triage-context">
              {contextLine(here.group)}
            </Body1>
            <div className={styles.issue}>
              <Link
                className={styles.title}
                href={issue.url}
                target="_blank"
                rel="noopener noreferrer"
              >
                #{issue.number} {issue.title}
              </Link>
              <Caption1 className={styles.answers} data-testid="triage-answers">
                {answersLine(issue, deepLabel)}
              </Caption1>
            </div>

            <div className={styles.question}>
              <Body1 className={styles.label}>Milestone</Body1>
              <Select
                className={styles.select}
                aria-label="Milestone"
                value={here.group.milestone}
                disabled={busy || milestones.length === 0}
                onChange={(_e, d) => {
                  if (d.value)
                    void answer({ milestone: d.value }, `Set the milestone: ${d.value}.`);
                }}
              >
                <option value="">
                  {milestones.length ? "Choose a milestone" : "No open milestone"}
                </option>
                {milestones.map((m) => (
                  <option key={m} value={m}>
                    {m}
                  </option>
                ))}
              </Select>
            </div>

            <div className={styles.question}>
              <Body1 className={styles.label}>Severity</Body1>
              <div className={styles.choices}>
                {data!.severities.map((s) => (
                  <ToggleButton
                    key={s}
                    size="small"
                    checked={issue.severity === s}
                    disabled={busy}
                    onClick={() => void answer({ severity: s }, `Severity ${s}.`)}
                  >
                    {s}
                  </ToggleButton>
                ))}
              </div>
            </div>

            <div className={styles.question}>
              <Body1 className={styles.label}>Size</Body1>
              <div className={styles.choices}>
                {/* "me" first: you take it yourself, as its GitHub assignee (D-AR10).
                    The sizes after it are the crew's; fable is the owner's own seat. */}
                <ToggleButton
                  size="small"
                  checked={issue.who === ME && !deepOpen}
                  disabled={busy}
                  title="Take it yourself: you become its assignee"
                  onClick={() => {
                    setDeepOpen(false);
                    void answer({ assign: ME }, "You have it.");
                  }}
                >
                  {ME}
                </ToggleButton>
                {sizes.map((s) => (
                  <ToggleButton
                    key={s.label}
                    size="small"
                    checked={issue.size === s.label && !deepOpen}
                    disabled={busy}
                    onClick={() => {
                      setDeepOpen(false);
                      void answer({ size: s.label }, `Sized ${s.name}.`);
                    }}
                  >
                    {s.name}
                  </ToggleButton>
                ))}
                <ToggleButton
                  size="small"
                  checked={deepOpen}
                  disabled={busy}
                  onClick={() => setDeepOpen((o) => !o)}
                >
                  {deepLabel}
                </ToggleButton>
              </div>
            </div>

            {/* Deep water's two moves (D-TA4). Always in the layout, shown only
                when deep water is the answer, so choosing it moves nothing. */}
            <div
              className={mergeClasses(styles.question, !deepOpen && styles.hidden)}
              data-testid="triage-deep-moves"
            >
              <Body1 className={styles.label}>Two moves</Body1>
              <div className={styles.choices}>
                <Button
                  size="small"
                  appearance="primary"
                  disabled={busy || !fable || !deepOpen}
                  title={fable ? undefined : "No worker label on this repo routes to Fable."}
                  onClick={() =>
                    void answer({ size: fable?.label, deepWater: true }, "Fable has it.")
                  }
                >
                  Assign Fable
                </Button>
                <Button
                  size="small"
                  disabled={busy || !deepOpen}
                  title={SPLIT_TITLE}
                  onClick={() => setSplitting(issue.number)}
                >
                  Split
                </Button>
              </div>
            </div>

            <Caption1
              className={mergeClasses(styles.status, !!outcome && !outcome.ok && styles.error)}
              data-testid="triage-status"
              role="status"
            >
              {busy ? "Writing..." : (outcome?.text ?? "")}
            </Caption1>

            <div className={styles.footer}>
              <Button
                icon={<ArrowNextRegular />}
                iconPosition="after"
                onClick={next}
                disabled={busy}
              >
                Next
              </Button>
            </div>
          </div>
        )}
      </PageCard>
      {splitting !== null && (
        <ActionDialog
          open
          onClose={() => setSplitting(null)}
          tab="new-item"
          initialParent={splitting}
        />
      )}
    </div>
  );
}
