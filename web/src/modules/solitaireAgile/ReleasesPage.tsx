import { useCallback, useEffect, useId, useLayoutEffect, useRef, useState } from "react";
import type { KeyboardEvent } from "react";
import {
  Body1,
  Button,
  Caption1,
  Link,
  ProgressBar,
  Subtitle1,
  Subtitle2,
  makeStyles,
  mergeClasses,
  tokens,
} from "@fluentui/react-components";
import {
  DismissRegular,
  FlagFilled,
  FlagRegular,
  OpenRegular,
  TimelineRegular,
} from "@fluentui/react-icons";
import { useGetEnvQuery } from "../../shell/api";
import { EmptyState } from "../../shared/EmptyState";
import { InlineMarkdown } from "../../shared/InlineMarkdown";
import { PanelFrame } from "../../shared/PanelFrame";
import { milestoneProgress } from "../ado/milestones";
import type { Release, ReleaseMilestone } from "./api.solitaireAgile";
import { useGetRitualReleaseTitlesQuery, useGetRitualReleasesQuery } from "./api.solitaireAgile";
import { dayWords } from "./award";
import { MilestonesPage } from "./MilestonesPage";

// The Releases timeline (docs/modules/solitaire-agile.md, "Releases: the
// timeline"): the release in progress first, then each tag going back in time,
// read from the Space's checkout through GET /api/ritual/releases. The GitHub
// milestones reached within a release stand over its stop as gold flags (an
// outlined flag: one the release in progress is still aimed at). A click on a
// stop or a flag opens the side panel: the release's dates, its milestones, its
// notes, its pull requests and issues. The track is one tab stop; Left and Right
// step between releases (Home and End to the ends), focus following, and an
// open panel follows the step. Escape closes the panel. The track scrolls the
// selected stop wholly into view on a stop's edge (scrollToShow), so no stop is
// cut at its left edge. The panel's issues carry their titles once a second,
// batched read of the tracker answers (GET /api/ritual/releases/titles); until
// then, and with no tracker, they are numbers.
//
// The flat GitHub milestones list and its award stay under the timeline until the
// award moves onto it: MilestonesPage, headed as the page's second level.

const useStyles = makeStyles({
  page: { display: "flex", flexDirection: "column", rowGap: tokens.spacingVerticalM, minWidth: 0 },
  repo: { color: tokens.colorNeutralForeground3, alignSelf: "center" },
  plain: { color: tokens.colorNeutralForeground3 },
  layout: {
    display: "grid",
    gridTemplateColumns: "minmax(0, 1fr)",
    columnGap: tokens.spacingHorizontalL,
    rowGap: tokens.spacingVerticalM,
    alignItems: "start",
  },
  layoutOpen: {
    "@media (min-width: 900px)": { gridTemplateColumns: "minmax(0, 1fr) minmax(280px, 380px)" },
  },
  scroller: {
    overflowX: "auto",
    paddingBottom: tokens.spacingVerticalS,
    minWidth: 0,
  },
  track: {
    display: "flex",
    alignItems: "stretch",
    minWidth: "min-content",
    paddingTop: tokens.spacingVerticalXS,
  },
  stop: {
    display: "grid",
    gridTemplateRows: "28px 20px auto",
    justifyItems: "center",
    width: "132px",
    flexShrink: 0,
  },
  flags: {
    display: "flex",
    alignItems: "flex-end",
    justifyContent: "center",
    columnGap: "2px",
    minHeight: "28px",
  },
  flag: {
    minWidth: "22px",
    width: "22px",
    height: "26px",
    padding: 0,
    fontSize: "18px",
    color: tokens.colorPaletteMarigoldForeground1,
  },
  rail: {
    position: "relative",
    width: "100%",
    display: "flex",
    alignItems: "center",
    justifyContent: "center",
    "::before": {
      content: '""',
      position: "absolute",
      left: 0,
      right: 0,
      top: "50%",
      borderTop: `2px solid ${tokens.colorNeutralStroke1}`,
    },
  },
  railOpen: {
    "::before": { borderTopStyle: "dashed", borderTopColor: tokens.colorBrandStroke1 },
  },
  railFirst: { "::before": { left: "50%" } },
  railLast: { "::before": { right: "50%" } },
  node: {
    position: "relative",
    width: "14px",
    height: "14px",
    borderRadius: tokens.borderRadiusCircular,
    backgroundColor: tokens.colorBrandBackground,
    border: `2px solid ${tokens.colorBrandBackground}`,
    boxSizing: "border-box",
  },
  nodeOpen: {
    backgroundColor: tokens.colorNeutralBackground1,
    border: `2px solid ${tokens.colorBrandStroke1}`,
  },
  nodeGold: { boxShadow: `0 0 0 3px ${tokens.colorPaletteMarigoldBorder2}` },
  stopButton: {
    display: "flex",
    flexDirection: "column",
    alignItems: "center",
    rowGap: "2px",
    marginTop: tokens.spacingVerticalXS,
    paddingTop: tokens.spacingVerticalXS,
    paddingBottom: tokens.spacingVerticalXS,
    paddingLeft: tokens.spacingHorizontalS,
    paddingRight: tokens.spacingHorizontalS,
    minWidth: "112px",
    border: `1px solid transparent`,
    borderRadius: tokens.borderRadiusMedium,
    backgroundColor: "transparent",
    color: tokens.colorNeutralForeground1,
    cursor: "pointer",
    fontFamily: "inherit",
    ":hover": { backgroundColor: tokens.colorNeutralBackground1Hover },
    ":focus-visible": { outline: `2px solid ${tokens.colorStrokeFocus2}`, outlineOffset: "1px" },
  },
  stopSelected: {
    backgroundColor: tokens.colorNeutralBackground1Selected,
    border: `1px solid ${tokens.colorNeutralStroke1}`,
  },
  stopMeta: { color: tokens.colorNeutralForeground3 },
  // Words a screen reader hears and the eye does not: the punctuation and the
  // facts between a stop's lines.
  unseen: {
    position: "absolute",
    width: "1px",
    height: "1px",
    margin: "-1px",
    padding: 0,
    overflow: "hidden",
    clip: "rect(0 0 0 0)",
    whiteSpace: "nowrap",
    border: 0,
  },
  // The panel's links: the panel's own text colour, underlined. The theme's link
  // colour does not hold its contrast on the panel in every theme.
  panelLink: {
    color: tokens.colorNeutralForeground1,
    textDecorationLine: "underline",
    ":hover": { color: tokens.colorNeutralForeground1Hover },
  },
  // The room after the last stop that lets the track's far end sit on a stop's
  // edge too (trackSpacer); never wide enough to make a track that fit overflow.
  spacer: { flexShrink: 0 },
  panel: {
    display: "flex",
    flexDirection: "column",
    rowGap: tokens.spacingVerticalM,
    padding: tokens.spacingVerticalM,
    borderRadius: tokens.borderRadiusLarge,
    border: `1px solid ${tokens.colorNeutralStroke2}`,
    backgroundColor: tokens.colorNeutralBackground1,
    minWidth: 0,
  },
  panelHead: { display: "flex", alignItems: "flex-start", columnGap: tokens.spacingHorizontalS },
  panelTitle: { display: "flex", flexDirection: "column", rowGap: "2px", flex: 1, minWidth: 0 },
  section: {
    display: "flex",
    flexDirection: "column",
    rowGap: tokens.spacingVerticalXS,
    margin: 0,
  },
  sectionHeading: { margin: 0 },
  list: { margin: 0, paddingLeft: tokens.spacingHorizontalL },
  milestone: {
    display: "flex",
    flexDirection: "column",
    rowGap: "2px",
    padding: tokens.spacingVerticalXS,
    borderRadius: tokens.borderRadiusMedium,
    borderLeft: `3px solid ${tokens.colorPaletteMarigoldBorderActive}`,
    paddingLeft: tokens.spacingHorizontalS,
  },
  milestoneOpen: { borderLeftStyle: "dashed" },
  milestoneSelected: { backgroundColor: tokens.colorPaletteMarigoldBackground1 },
  milestoneHead: { display: "flex", alignItems: "center", columnGap: tokens.spacingHorizontalXS },
  gold: { color: tokens.colorPaletteMarigoldForeground1, fontSize: "16px", lineHeight: 0 },
});

/** What a stop is called: the tag, or "In progress". */
export const releaseName = (r: Release): string => (r.inProgress ? "In progress" : r.tag);

/** A stop's second line: the tag's day, or what the release in progress runs from. */
export function releaseWhen(r: Release): string {
  if (!r.inProgress) return dayWords(r.date);
  return r.previous ? `since ${r.previous}` : "nothing tagged yet";
}

const entryCount = (r: Release): number => r.notes.reduce((n, g) => n + g.entries.length, 0);
const plural = (n: number, one: string, many = `${one}s`): string => `${n} ${n === 1 ? one : many}`;
const reachedCount = (r: Release): number => r.milestones.filter((m) => m.reachedOn).length;

/** A stop's words, as drawn and as heard: what the eye reads (`name`, `when`,
 *  `entries`) and what only a screen reader hears (`whenLead`, `extras`). */
export function stopParts(r: Release) {
  const reached = reachedCount(r);
  const aimed = r.milestones.length - reached;
  return {
    name: releaseName(r),
    whenLead: r.inProgress ? "" : "shipped ",
    when: releaseWhen(r),
    entries: plural(entryCount(r), "entry", "entries"),
    extras: [
      ...(reached ? [`${plural(reached, "milestone")} reached`] : []),
      ...(aimed ? [`${plural(aimed, "milestone")} open`] : []),
    ],
  };
}

/** A stop's accessible name: the whole fact, as a screen reader hears it. The
 *  button's own text IS this name -- what it draws, with the words only a screen
 *  reader needs hidden in between -- so the name always holds the visible text. */
export function stopLabel(r: Release): string {
  const p = stopParts(r);
  return [p.name, `${p.whenLead}${p.when}`, p.entries, ...p.extras].join(", ");
}

/** A milestone's one line: reached on its day, or how far along it is. */
export function milestoneWords(m: ReleaseMilestone): string {
  if (m.reachedOn) return `reached ${dayWords(m.reachedOn)}`;
  const total = m.open + m.closed;
  return total ? `open, ${m.closed} of ${total} closed` : "open, no issues yet";
}

/** A stop's left and right edges, in the track's own coordinates. */
export interface StopEdges {
  left: number;
  right: number;
}

/**
 * Where the track scrolls so the stop at `index` is wholly in view, on a stop's
 * left edge -- so no stop is cut at the track's left -- or null when it is in
 * view already. A stop off to the left goes to the left edge; one off to the
 * right brings the fewest stops in from the right that show it.
 */
export function scrollToShow(
  stops: StopEdges[],
  index: number,
  scrollLeft: number,
  width: number,
): number | null {
  const s = stops[index];
  if (!s || width <= 0) return null;
  if (s.left >= scrollLeft - 0.5 && s.right <= scrollLeft + width + 0.5) return null;
  if (s.left < scrollLeft) return Math.max(0, s.left);
  const need = s.right - width;
  return Math.max(0, stops.find((x) => x.left >= need - 0.5)?.left ?? s.left);
}

/**
 * The room after the last stop, so the track's farthest scroll is a stop's edge
 * too: the part of the view a whole number of stops does not fill. A track that
 * fits never overflows by it.
 */
export function trackSpacer(viewWidth: number, stopWidth: number): number {
  return viewWidth > 0 && stopWidth > 0 ? viewWidth % stopWidth : 0;
}

function MilestoneFlag({
  m,
  onOpen,
}: {
  m: ReleaseMilestone;
  onOpen: (m: ReleaseMilestone) => void;
}) {
  const styles = useStyles();
  const words = `${m.title}, GitHub milestone ${milestoneWords(m)}`;
  return (
    <Button
      appearance="transparent"
      className={styles.flag}
      // The track is the keyboard's one way in; the panel lists every milestone.
      tabIndex={-1}
      icon={m.reachedOn ? <FlagFilled /> : <FlagRegular />}
      title={words}
      aria-label={words}
      data-testid="release-flag"
      data-reached={m.reachedOn ? "true" : "false"}
      onClick={() => onOpen(m)}
    />
  );
}

/** The cap line: the read asked for the first `limit` of `asked` titles. */
export function titlesCapWords(asked: number, limit: number): string {
  return `Titles read for the first ${limit} of ${asked} issues.`;
}

function ReleasePanel({
  r,
  id,
  space,
  repo,
  selectedMilestone,
  onClose,
}: {
  r: Release;
  id: string;
  space: string;
  repo: string;
  selectedMilestone: string;
  onClose: () => void;
}) {
  const styles = useStyles();
  const headingId = useId();
  const numbers = r.issues.map((i) => i.number);
  // One batched tracker read for this release's titles; none for a release with
  // no issue. A failed read, or no tracker, leaves the numbers as they are.
  const { data: read } = useGetRitualReleaseTitlesQuery(
    { space, numbers },
    { skip: numbers.length === 0 },
  );
  const titled = read?.tracker.ok ? read : undefined;
  const titleOf = new Map((titled?.titles ?? []).map((t) => [t.number, t.title]));
  const issuesUrl = repo ? `https://github.com/${repo}/issues` : undefined;
  const span = r.inProgress
    ? r.previous
      ? `From ${r.previous} (${dayWords(r.since)}) to now`
      : "Everything so far, nothing tagged yet"
    : r.previous
      ? `From ${r.previous} (${dayWords(r.since)}) to ${dayWords(r.date)}`
      : `Up to ${dayWords(r.date)}, the first release`;
  return (
    <aside
      id={id}
      className={styles.panel}
      aria-labelledby={headingId}
      data-testid="release-panel"
      onKeyDown={(e) => {
        if (e.key === "Escape") onClose();
      }}
    >
      <div className={styles.panelHead}>
        <div className={styles.panelTitle}>
          <Subtitle1 as="h2" id={headingId}>
            {r.inProgress ? "In progress" : r.tag}
          </Subtitle1>
          <Caption1 className={styles.plain}>{span}</Caption1>
          <Caption1 className={styles.plain}>{plural(r.commits, "commit")}</Caption1>
        </div>
        <Button
          appearance="subtle"
          icon={<DismissRegular />}
          aria-label="Close the release"
          title="Close"
          onClick={onClose}
        />
      </div>
      <Link className={styles.panelLink} href={r.url} target="_blank" rel="noopener noreferrer">
        {r.inProgress ? "Compare on GitHub" : "Release on GitHub"} <OpenRegular aria-hidden />
      </Link>

      {r.milestones.length > 0 && (
        <section className={styles.section} aria-label="GitHub milestones">
          <Subtitle2 as="h3" className={styles.sectionHeading}>
            GitHub milestones
          </Subtitle2>
          {r.milestones.map((m) => (
            <div
              key={`${m.repo}-${m.number}`}
              className={mergeClasses(
                styles.milestone,
                !m.reachedOn && styles.milestoneOpen,
                selectedMilestone === `${m.repo}-${m.number}` && styles.milestoneSelected,
              )}
              data-testid="release-milestone"
            >
              <div className={styles.milestoneHead}>
                <span className={styles.gold} aria-hidden>
                  {m.reachedOn ? <FlagFilled /> : <FlagRegular />}
                </span>
                <Link
                  className={styles.panelLink}
                  href={m.url}
                  target="_blank"
                  rel="noopener noreferrer"
                >
                  {m.title}
                </Link>
              </div>
              <Caption1 className={styles.plain}>{milestoneWords(m)}</Caption1>
              <ProgressBar
                value={milestoneProgress(m)}
                thickness="medium"
                color={m.reached ? "success" : "brand"}
                aria-label={`${m.title}: ${m.closed} of ${m.open + m.closed} closed`}
              />
            </div>
          ))}
        </section>
      )}

      <section className={styles.section} aria-label="Notes">
        <Subtitle2 as="h3" className={styles.sectionHeading}>
          {r.inProgress ? "Notes so far" : "Notes"}
        </Subtitle2>
        {r.notes.length === 0 ? (
          <Caption1 className={styles.plain}>
            {r.inProgress ? "No entry waiting yet." : "No changelog section for this tag."}
          </Caption1>
        ) : (
          r.notes.map((g) => (
            <div key={g.heading}>
              <Body1>
                <strong>{g.heading}</strong>
              </Body1>
              <ul className={styles.list}>
                {g.entries.map((e, i) => (
                  <li key={i}>
                    <Body1>
                      <InlineMarkdown issuesUrl={issuesUrl}>{e}</InlineMarkdown>
                    </Body1>
                  </li>
                ))}
              </ul>
            </div>
          ))
        )}
      </section>

      <section className={styles.section} aria-label="Pull requests">
        <Subtitle2 as="h3" className={styles.sectionHeading}>
          Pull requests
        </Subtitle2>
        {r.pulls.length === 0 ? (
          <Caption1 className={styles.plain}>None merged with a number.</Caption1>
        ) : (
          <ul className={styles.list}>
            {r.pulls.map((p) => (
              <li key={p.number}>
                <Link
                  className={styles.panelLink}
                  href={p.url}
                  target="_blank"
                  rel="noopener noreferrer"
                >
                  #{p.number}
                </Link>{" "}
                {p.title}
              </li>
            ))}
          </ul>
        )}
      </section>

      {r.issues.length > 0 && (
        <section className={styles.section} aria-label="Issues">
          <Subtitle2 as="h3" className={styles.sectionHeading}>
            Issues
          </Subtitle2>
          <ul className={styles.list}>
            {r.issues.map((i) => (
              <li key={i.number} data-testid="release-issue">
                <Link
                  className={styles.panelLink}
                  href={i.url}
                  target="_blank"
                  rel="noopener noreferrer"
                >
                  #{i.number}
                </Link>
                {titleOf.has(i.number) ? ` ${titleOf.get(i.number)}` : ""}
              </li>
            ))}
          </ul>
          {titled && titled.asked > titled.limit ? (
            <Caption1 className={styles.plain} data-testid="release-titles-cap">
              {titlesCapWords(titled.asked, titled.limit)}
            </Caption1>
          ) : null}
        </section>
      )}
    </aside>
  );
}

export function ReleasesTimeline() {
  const styles = useStyles();
  const { data: env, isLoading: envLoading } = useGetEnvQuery();
  const space = env?.config?.activeSpace ?? "";
  const { data, isLoading, error } = useGetRitualReleasesQuery(space, { skip: envLoading });
  const releases = data?.source.ok ? data.releases : [];
  const [selected, setSelected] = useState(0);
  const [open, setOpen] = useState(false);
  const [milestone, setMilestone] = useState("");
  const stops = useRef<(HTMLButtonElement | null)[]>([]);
  const stopBoxes = useRef<(HTMLDivElement | null)[]>([]);
  const scroller = useRef<HTMLDivElement | null>(null);
  const [spacer, setSpacer] = useState(0);
  const panelId = useId();

  // The track's far end on a stop's edge: measured, and again when the view resizes.
  useLayoutEffect(() => {
    const view = scroller.current;
    const measure = () => {
      const first = stopBoxes.current[0];
      setSpacer(trackSpacer(view?.clientWidth ?? 0, first?.offsetWidth ?? 0));
    };
    measure();
    if (typeof ResizeObserver === "undefined" || !view) return;
    const watch = new ResizeObserver(measure);
    watch.observe(view);
    return () => watch.disconnect();
  }, [releases.length, open]);

  // The selected stop wholly in view, on a stop's edge.
  useEffect(() => {
    const view = scroller.current;
    if (!view) return;
    const origin = view.getBoundingClientRect().left - view.scrollLeft;
    const edges = stopBoxes.current.map((el) => {
      const box = el?.getBoundingClientRect();
      return { left: (box?.left ?? 0) - origin, right: (box?.right ?? 0) - origin };
    });
    const to = scrollToShow(edges, selected, view.scrollLeft, view.clientWidth);
    if (to !== null) view.scrollLeft = to;
  }, [selected, open, spacer, releases.length]);

  const step = useCallback(
    (to: number) => {
      const next = Math.max(0, Math.min(releases.length - 1, to));
      setSelected(next);
      setMilestone("");
      // The track scrolls itself (scrollToShow); focus must not scroll it first.
      stops.current[next]?.focus({ preventScroll: true });
    },
    [releases.length],
  );
  const close = useCallback(() => {
    setOpen(false);
    stops.current[selected]?.focus();
  }, [selected]);

  const onKey = (e: KeyboardEvent<HTMLDivElement>) => {
    const moves: Record<string, number> = {
      ArrowRight: selected + 1,
      ArrowLeft: selected - 1,
      Home: 0,
      End: releases.length - 1,
    };
    if (e.key in moves) {
      e.preventDefault();
      step(moves[e.key]);
    } else if (e.key === "Escape" && open) {
      e.preventDefault();
      close();
    }
  };

  const icon = <TimelineRegular />;
  const empty =
    isLoading || envLoading ? undefined : error || !data ? (
      <EmptyState
        icon={icon}
        tone="error"
        title="Could not read the releases"
        detail="The agent did not answer. Nothing was read."
      />
    ) : !data.source.ok ? (
      <EmptyState icon={icon} title="No releases read" detail={data.source.reason} />
    ) : undefined;
  const current = releases[Math.min(selected, releases.length - 1)];

  return (
    <PanelFrame
      loading={envLoading || isLoading}
      loadingLabel="Reading the releases..."
      empty={empty}
      headerLeft={
        <>
          {icon}
          <Subtitle2 as="h1">Releases</Subtitle2>
          {data?.repo ? (
            <Caption1 className={styles.repo} data-testid="releases-repo">
              {data.repo}
            </Caption1>
          ) : null}
        </>
      }
    >
      {data && !data.tracker.ok ? (
        <Caption1 className={styles.plain} data-testid="releases-tracker">
          GitHub milestones not read: {data.tracker.reason}
        </Caption1>
      ) : null}
      <div className={mergeClasses(styles.layout, open && current && styles.layoutOpen)}>
        <div className={styles.scroller} ref={scroller}>
          <div
            className={styles.track}
            role="group"
            aria-label="Releases, newest first"
            onKeyDown={onKey}
          >
            {releases.map((r, i) => {
              const gold = reachedCount(r) > 0;
              const parts = stopParts(r);
              return (
                <div
                  key={r.tag || "in-progress"}
                  ref={(el) => {
                    stopBoxes.current[i] = el;
                  }}
                  className={styles.stop}
                  data-testid="release-stop"
                >
                  <div className={styles.flags}>
                    {r.milestones.map((m) => (
                      <MilestoneFlag
                        key={`${m.repo}-${m.number}`}
                        m={m}
                        onOpen={(picked) => {
                          setSelected(i);
                          setMilestone(`${picked.repo}-${picked.number}`);
                          setOpen(true);
                          stops.current[i]?.focus({ preventScroll: true });
                        }}
                      />
                    ))}
                  </div>
                  <div
                    className={mergeClasses(
                      styles.rail,
                      r.inProgress && styles.railOpen,
                      i === 0 && styles.railFirst,
                      i === releases.length - 1 && styles.railLast,
                    )}
                    aria-hidden
                  >
                    <span
                      className={mergeClasses(
                        styles.node,
                        r.inProgress && styles.nodeOpen,
                        gold && styles.nodeGold,
                      )}
                    />
                  </div>
                  <button
                    type="button"
                    ref={(el) => {
                      stops.current[i] = el;
                    }}
                    className={mergeClasses(
                      styles.stopButton,
                      i === selected && styles.stopSelected,
                    )}
                    tabIndex={i === selected ? 0 : -1}
                    aria-current={i === selected ? "true" : undefined}
                    aria-expanded={open && i === selected}
                    aria-controls={open && i === selected ? panelId : undefined}
                    onClick={() => {
                      setSelected(i);
                      setMilestone("");
                      setOpen(true);
                    }}
                  >
                    <Body1>
                      <strong>{parts.name}</strong>
                      <span className={styles.unseen}>, </span>
                    </Body1>
                    <Caption1 className={styles.stopMeta}>
                      {parts.whenLead ? (
                        <span className={styles.unseen}>{parts.whenLead}</span>
                      ) : null}
                      {parts.when}
                      <span className={styles.unseen}>, </span>
                    </Caption1>
                    <Caption1 className={styles.stopMeta}>
                      {parts.entries}
                      {parts.extras.length ? (
                        <span className={styles.unseen}>{`, ${parts.extras.join(", ")}`}</span>
                      ) : null}
                    </Caption1>
                  </button>
                </div>
              );
            })}
            {spacer > 0 ? (
              <span className={styles.spacer} style={{ width: spacer }} aria-hidden />
            ) : null}
          </div>
        </div>
        {open && current ? (
          <ReleasePanel
            r={current}
            id={panelId}
            space={space}
            repo={data?.repo ?? ""}
            selectedMilestone={milestone}
            onClose={close}
          />
        ) : null}
      </div>
    </PanelFrame>
  );
}

/** The Releases tab: the timeline, and the GitHub milestones list under it. */
export function ReleasesPage() {
  const styles = useStyles();
  return (
    <div className={styles.page}>
      <ReleasesTimeline />
      <MilestonesPage />
    </div>
  );
}
