import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import type { ReactNode } from "react";
import { useNavigate } from "react-router";
import {
  Button,
  Caption1,
  Link,
  Subtitle2,
  Tab,
  TabList,
  makeStyles,
  tokens,
} from "@fluentui/react-components";
import {
  CheckmarkRegular,
  CopyRegular,
  DismissRegular,
  PeopleTeamRegular,
  PlayRegular,
} from "@fluentui/react-icons";
import { EmptyState } from "../../shared/EmptyState";
import { copyText } from "../../shared/copyText";
import { PageCard } from "../../shared/PageCard";
import { usePersistedValue } from "../../shared/usePersistedState";
import { useGetEnvQuery } from "../../shell/api";
import { RITUALS } from "../../shell/consts";
import { lazyPart } from "../../shell/lazy";
import {
  useAttendStandupMutation,
  useGetStandupQuery,
  useGetTriageQuery,
} from "./api.solitaireAgile";
import type { RitualItem, StandupResponse, TriageResponse } from "./api.solitaireAgile";
import { IssuePopover } from "./IssuePopover";
import type { IssueFacts } from "./IssuePopover";
import { isIssue, itemFacts, itemRef } from "./itemRef";
import { ROUTES } from "./paths";
import { SEATS, plateFor } from "./stage/seats";
import { SURFACE_CHAIR, dismissRef, dismissedRefs } from "./suggestDismiss";
import { chairSuggestion, suggestionArg } from "./suggestion";

// The hand-off block's copy box (AR-1): a chunk fetched the first time a row's
// Start work is pressed, so the page's first draw carries none of it.
const StartWorkBox = lazyPart(
  () => import("./StartWorkBox"),
  (m) => m.StartWorkBox,
);

/** What `StartWork` is given for a row's item: the issue's number, else the card's id. */
export const startWorkArg = (i: RitualItem): string =>
  isIssue(i) ? String(i.number) : (i.id ?? "");

// Today's standup, `/solitaire-agile` (docs/modules/solitaire-agile.md,
// "The web UI"): the agent's `text`, VERBATIM -- the same string the CLI's Standup
// prints, so parity between the two renderers is one string comparison and
// this page renders nothing of its own. The text's first line is the
// ceremony's title and date, and it is the card's header; every line after it
// is the body, in a monospace block that keeps the padding and the LFs. The
// two put back together with the "\n" between them are `text`, byte for byte.
//
// Above the prose sits the chair's reading, the response's `brief`, one
// Caption1 per line, read as given. Copy still copies `text` and nothing else.
//
// Each number opens a small surface (IssuePopover.tsx): the issue's title, worker,
// severity, milestone and state, and Open on GitHub last.
//
// Nothing to click but the issue numbers (spec, "What the user sees"): each
// `#<n>` whose number the response names is a link to that issue's url --
// and, since V1, one quiet Play in the header, which opens the same
// standup played on the stage (ROUTES.play).
//
// The grain (D-TA20) is a setting per browser: detail (the text above,
// every item, the default), work (the ritual's grain -- `work.text`, each
// worker's items grouped by milestone or feature and spoken as prose, one
// sentence a group) or
// brief (the chair's reading alone). The three names are the contract's
// (rituals.grains), the same words `Standup -Grain` takes. Each is shown
// verbatim, as the agent rendered it; Copy copies the grain on screen.
//
// The chair's Next line may be the SUGGESTION (AR-3; docs/modules/solitaire-agile.md,
// "The suggestion: one next move, derived"): when nothing waits, the brief's last
// line is the first candidate's `line`. The page draws that line as a row of its
// own -- the line verbatim, the action (Start work opens the hand-off box for a
// start or a delegation; a route, or a place in a milestone, opens Triage) and a dismiss. A dismiss is per
// surface, per item, per session (suggestDismiss.ts): the next candidate's line
// takes its place, and with none left the line is today's briefNextNone. The
// brief's text is otherwise untouched, and Copy still copies it as the agent
// rendered it.
//
// Showing the standup IS attending it (D-TA15): the first time it draws,
// the page posts once to the attend route, which re-arms the standup's Organize
// reminder through Organize's own verbs -- once a day, and nothing at all with
// Organize off or no reminder set. Fire and forget: what it did is not shown.

const useStyles = makeStyles({
  page: { display: "flex", flexDirection: "column", gap: tokens.spacingVerticalM, width: "100%" },
  body: {
    margin: 0,
    marginTop: tokens.spacingVerticalS,
    fontFamily: tokens.fontFamilyMonospace,
    fontSize: tokens.fontSizeBase300,
    lineHeight: tokens.lineHeightBase300,
    whiteSpace: "pre",
    overflowX: "auto",
    // A keyboard reaches it to scroll it, so it shows where focus is.
    ":focus-visible": { outline: `2px solid ${tokens.colorStrokeFocus2}`, outlineOffset: "2px" },
  },
  // The chair's reading: a short block above the long form, one line each.
  brief: {
    display: "flex",
    flexDirection: "column",
    marginTop: tokens.spacingVerticalS,
    color: tokens.colorNeutralForeground2,
  },
  // The toggle's box is constant: the label changes, the width does not.
  toggle: { alignSelf: "flex-start", minWidth: "120px", marginTop: tokens.spacingVerticalS },
  // The suggestion: the line, its action and its dismiss, on one wrapping row.
  suggestion: {
    display: "flex",
    flexWrap: "wrap",
    alignItems: "center",
    columnGap: tokens.spacingHorizontalS,
  },
  list: { listStyle: "none", margin: 0, padding: 0, display: "flex", flexDirection: "column" },
  row: {
    display: "flex",
    flexWrap: "wrap",
    alignItems: "baseline",
    columnGap: tokens.spacingHorizontalS,
    padding: `${tokens.spacingVerticalXS} 0`,
    borderBottom: `1px solid ${tokens.colorNeutralStroke2}`,
  },
  kind: { color: tokens.colorNeutralForeground3, minWidth: "72px" },
  title: { flex: 1, minWidth: 0 },
  who: { color: tokens.colorNeutralForeground3 },
});

/** The browser's own key for the grain it was last read at. */
export const GRAIN_KEY = "p20.solitaireAgile.grain";
const GRAINS = RITUALS.grains;
const [DETAIL, WORK, BRIEF] = GRAINS;
const isGrain = (v: string) => GRAINS.includes(v);
/** A grain's name as its tab says it: "work" -> "Work". */
const grainLabel = (g: string) => g.slice(0, 1).toUpperCase() + g.slice(1);

/** What one grain shows: the header line, the body under it, and what Copy copies.
 *  detail and work are their own texts (title line first); brief has no title
 *  line, so the header is the text's and the body the whole brief. A response
 *  from an agent that predates the work grain shows detail for it. */
export function grainParts(
  data: StandupResponse,
  grain: string,
): { header: string; body: string; copy: string } {
  const head = splitHeader(data.text).header;
  if (grain === BRIEF && data.brief) return { header: head, body: data.brief, copy: data.brief };
  const text = grain === WORK && data.work?.text ? data.work.text : data.text;
  return { ...splitHeader(text), copy: text };
}

/** One row of the list: where it came from, and the item. */
export interface ListRow {
  key: string;
  /** The queue's kind (walk|decide|look) or the worker's slot. */
  kind: string;
  item: RitualItem;
  worker: string;
}

/** The response's structured items as rows: the queue's first (walk, decide,
 *  look), then each worker's three slots. Read from the response; no fetch. */
export function listRows(data: StandupResponse): ListRow[] {
  const rows: ListRow[] = [];
  const add = (
    kind: string,
    items: (RitualItem & { worker?: string })[] | undefined,
    fallback: string,
  ) => {
    for (const item of items ?? [])
      rows.push({ key: `${kind}-${rows.length}`, kind, item, worker: item.worker ?? fallback });
  };
  for (const k of ["walk", "decide", "look"] as const) add(k, data.queue?.[k], "");
  for (const w of data.workers ?? []) {
    add("yesterday", w.yesterday, w.name);
    add("today", w.today, w.name);
    add("blockers", w.blockers, w.name);
  }
  return rows;
}

/** Every issue the response names, by number: the queue's and each worker's
 *  three slots. A number with no url here stays plain text. */
export function issueUrls(data: StandupResponse): Map<number, string> {
  const urls = new Map<number, string>();
  const add = (items: RitualItem[] | undefined) => {
    // A card has no number and no url: its line stays plain text.
    for (const item of items ?? [])
      if (item.url && item.number != null) urls.set(item.number, item.url);
  };
  add(data.queue?.walk);
  add(data.queue?.decide);
  add(data.queue?.look);
  for (const w of data.workers ?? []) {
    add(w.yesterday);
    add(w.today);
    add(w.blockers);
  }
  return urls;
}

/** The worker chip, `ROLE · PERSONA (label)`, when the worker sits in a seat; else nothing.
 *  `who` is what the item names: the worker's label or its name. */
export function workerChip(data: StandupResponse, who: string): string | undefined {
  const w = (data.workers ?? []).find(
    (x) =>
      x.label.toLowerCase() === who.toLowerCase() || x.name.toLowerCase() === who.toLowerCase(),
  );
  if (!w) return undefined;
  const seat = SEATS.find((s) => s.kind === "worker" && s.workerLabel === w.label.toLowerCase());
  return seat ? plateFor(seat, w.label) : undefined;
}

/** The state a row's slot already says (the agent's rule, Standup-Rules.ps1): yesterday
 *  is closed in the window; today, blockers and the queue are open. Any other kind: none. */
export function slotState(kind: string): string | undefined {
  if (kind === "yesterday") return "Closed";
  if (["today", "blockers", "walk", "decide", "look"].includes(kind)) return "Open";
  return undefined;
}

/** What each popover shows, by number. State is the slot the row sits in; severity and
 *  milestone come from the one triage read, only for a number it lists. A field the data
 *  does not carry is left out, never guessed. */
export function issueFacts(
  data: StandupResponse,
  triage?: TriageResponse,
): Map<number, IssueFacts> {
  const open = new Map<number, { severity: string; milestone: string }>();
  const read = !!triage && !!triage.tracker?.ok;
  if (read)
    for (const g of triage.groups ?? [])
      for (const i of g.issues ?? [])
        open.set(i.number, { severity: i.severity, milestone: g.milestone });
  const out = new Map<number, IssueFacts>();
  for (const r of listRows(data)) {
    const n = r.item.number;
    if (n == null || !r.item.url) continue;
    const chip = r.worker ? workerChip(data, r.worker) : undefined;
    const seen = out.get(n);
    // The first row names the number; a later row (the walk names no worker, a slot does) can add the seat.
    if (seen) {
      if (!seen.worker && chip) seen.worker = chip;
      continue;
    }
    const o = open.get(n);
    out.set(n, {
      label: `#${n}`,
      title: r.item.title,
      url: r.item.url,
      worker: chip,
      severity: o?.severity || undefined,
      milestone: o?.milestone || undefined,
      state: slotState(r.kind),
    });
  }
  return out;
}

/** Split the text into its first line and the rest, at the first LF. */
export function splitHeader(text: string): { header: string; body: string } {
  const at = text.indexOf("\n");
  return at < 0
    ? { header: text, body: "" }
    : { header: text.slice(0, at), body: text.slice(at + 1) };
}

/** The body with each known `#<n>` as a link; every other character as given. */
export function linkIssues(
  body: string,
  urls: Map<number, string>,
  facts?: Map<number, IssueFacts>,
): ReactNode[] {
  const out: ReactNode[] = [];
  const re = /#(\d+)\b/g;
  let last = 0;
  let m: RegExpExecArray | null;
  while ((m = re.exec(body))) {
    const url = urls.get(Number(m[1]));
    if (!url) continue;
    if (m.index > last) out.push(body.slice(last, m.index));
    const f = facts?.get(Number(m[1]));
    out.push(
      f ? (
        <IssuePopover key={`${m.index}-${m[1]}`} facts={{ ...f, label: m[0] }} />
      ) : (
        <Link key={`${m.index}-${m[1]}`} href={url} target="_blank" rel="noopener noreferrer">
          {m[0]}
        </Link>
      ),
    );
    last = m.index + m[0].length;
  }
  if (last < body.length) out.push(body.slice(last));
  return out;
}

export function StandupPage() {
  const styles = useStyles();
  const navigate = useNavigate();
  const { data: env, isLoading: envLoading } = useGetEnvQuery();
  const space = env?.config?.activeSpace ?? "";
  const { data, isLoading, error } = useGetStandupQuery(space, { skip: envLoading });
  const readable = !!data && !error;
  // One read for the popovers' severity and milestone: the Triage page's own,
  // cached under the same key. Its failure only leaves those lines out.
  const { data: triage } = useGetTriageQuery(space, { skip: envLoading || !readable });
  const [attend] = useAttendStandupMutation();
  const attended = useRef(false);
  useEffect(() => {
    if (!readable || attended.current) return;
    attended.current = true;
    void attend();
  }, [readable, attend]);
  const [copied, setCopied] = useState(false);
  const [showList, setShowList] = useState(false);
  // The item whose hand-off block is open: the box is mounted only while it is.
  const [startFor, setStartFor] = useState<string | null>(null);
  const { value: grain, setValue: setGrain } = usePersistedValue(GRAIN_KEY, DETAIL, isGrain);
  // The refs dismissed on the chair's line this session (never throws).
  const [dismissed, setDismissed] = useState<string[]>(() => dismissedRefs(SURFACE_CHAIR));
  const chair = useMemo(
    () => (readable ? chairSuggestion(data, dismissed) : { standing: false, current: null }),
    [readable, data, dismissed],
  );
  const parts = useMemo(() => {
    if (!readable) return { header: "", body: "", copy: "" };
    const p = grainParts(data, grain);
    // The brief grain draws the suggestion as its own row: the body stops above it.
    if (grain === BRIEF && chair.standing) {
      const lines = p.body.replace(/\n$/, "").split("\n");
      return { ...p, body: lines.slice(0, -1).join("\n") + "\n" };
    }
    return p;
  }, [readable, data, grain, chair.standing]);
  const copy = useCallback(async () => {
    if (!parts.copy) return;
    await copyText(parts.copy);
    setCopied(true);
    setTimeout(() => setCopied(false), 2000);
  }, [parts]);
  const rows = useMemo(() => (readable ? listRows(data) : []), [readable, data]);
  // The chair's reading sits above the prose -- unless it IS the prose.
  const briefLines = useMemo(() => {
    if (!readable || !data.brief || grain === BRIEF) return [];
    const lines = data.brief.split("\n").filter(Boolean);
    return chair.standing ? lines.slice(0, -1) : lines;
  }, [readable, data, grain, chair.standing]);
  const dismiss = useCallback((ref: string) => setDismissed(dismissRef(SURFACE_CHAIR, ref)), []);
  const current = chair.current;
  const suggestionRow = chair.standing ? (
    <div className={styles.suggestion} data-testid="standup-suggestion">
      <Caption1>{current ? current.line : RITUALS.text.briefNextNone}</Caption1>
      {current && RITUALS.suggestShapes.slice(0, 2).includes(current.shape) && (
        <Button
          appearance="subtle"
          size="small"
          aria-label={`Start work on ${current.ref}`}
          onClick={() => setStartFor(suggestionArg(current))}
        >
          Start work
        </Button>
      )}
      {current && !RITUALS.suggestShapes.slice(0, 2).includes(current.shape) && (
        <Button appearance="subtle" size="small" onClick={() => navigate(ROUTES.triage)}>
          Open Triage
        </Button>
      )}
      {current && (
        <Button
          appearance="subtle"
          size="small"
          icon={<DismissRegular />}
          aria-label={`Dismiss the suggestion ${current.ref}`}
          onClick={() => dismiss(current.ref)}
        />
      )}
    </div>
  ) : null;
  const facts = useMemo(
    () => (readable ? issueFacts(data, triage) : undefined),
    [readable, data, triage],
  );
  const linked = useMemo(
    () => (readable ? linkIssues(parts.body, issueUrls(data), facts) : []),
    [readable, data, parts, facts],
  );

  const empty = readable ? undefined : (
    <EmptyState
      icon={<PeopleTeamRegular />}
      tone="error"
      title="Could not read today's standup"
      detail="The agent did not answer. Nothing was read."
    />
  );

  return (
    <div className={styles.page}>
      <PageCard
        loading={envLoading || isLoading}
        loadingLabel="Checking the tracker..."
        empty={empty}
        headerLeft={readable ? <Subtitle2 as="h1">{parts.header}</Subtitle2> : undefined}
        headerRight={
          readable ? (
            <>
              <Button
                appearance="subtle"
                icon={copied ? <CheckmarkRegular /> : <CopyRegular />}
                onClick={() => void copy()}
              >
                {copied ? "Copied!" : "Copy"}
              </Button>
              <Button
                appearance="subtle"
                icon={<PlayRegular />}
                onClick={() => navigate(ROUTES.play)}
              >
                Play
              </Button>
            </>
          ) : undefined
        }
      >
        {readable && (
          <>
            <TabList
              size="small"
              aria-label="Grain"
              selectedValue={grain}
              onTabSelect={(_e, d) => setGrain(String(d.value))}
            >
              {GRAINS.map((g) => (
                <Tab key={g} value={g}>
                  {grainLabel(g)}
                </Tab>
              ))}
            </TabList>
            {briefLines.length > 0 && (
              <div className={styles.brief} data-testid="standup-brief">
                {briefLines.map((line, i) => (
                  <Caption1 key={i}>{line}</Caption1>
                ))}
                {suggestionRow}
              </div>
            )}
            {/* The text keeps its columns (white-space: pre), so a long line
                scrolls sideways -- and a region that scrolls must be reachable
                by keyboard (axe's scrollable-region-focusable). A named
                region is the pattern that may take the tab stop and a label. */}
            <pre
              className={styles.body}
              data-testid="standup-text"
              tabIndex={0}
              role="region"
              aria-label="Standup text"
            >
              {linked}
            </pre>
            {grain === BRIEF && suggestionRow}
            <Button
              appearance="transparent"
              size="small"
              className={styles.toggle}
              aria-expanded={showList}
              onClick={() => setShowList((v) => !v)}
            >
              {showList ? "Hide list" : "Show as list"}
            </Button>
            {showList && (
              <ul className={styles.list} data-testid="standup-list">
                {rows.map((r) => (
                  <li key={r.key} className={styles.row}>
                    <span className={styles.kind}>{r.kind}</span>
                    <span>
                      {isIssue(r.item) && facts?.get(r.item.number!) ? (
                        <IssuePopover facts={facts.get(r.item.number!)!} />
                      ) : isIssue(r.item) ? (
                        <Link href={r.item.url} target="_blank" rel="noopener noreferrer">
                          {itemRef(r.item)}
                        </Link>
                      ) : r.item.id ? (
                        <IssuePopover facts={itemFacts(r.item)} />
                      ) : (
                        ""
                      )}
                    </span>
                    <span className={styles.title}>{r.item.title}</span>
                    {r.worker && <span className={styles.who}>{r.worker}</span>}
                    {startWorkArg(r.item) && (
                      <Button
                        appearance="subtle"
                        size="small"
                        aria-label={`Start work on ${itemRef(r.item)}`}
                        onClick={() => setStartFor(startWorkArg(r.item))}
                      >
                        Start work
                      </Button>
                    )}
                  </li>
                ))}
              </ul>
            )}
          </>
        )}
      </PageCard>
      {startFor !== null && <StartWorkBox id={startFor} onClose={() => setStartFor(null)} />}
    </div>
  );
}
