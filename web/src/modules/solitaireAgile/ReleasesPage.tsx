import { useCallback, useId, useRef, useState } from "react";
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
import { PanelFrame } from "../../shared/PanelFrame";
import { milestoneProgress } from "../ado/milestones";
import type { Release, ReleaseMilestone } from "./api.solitaireAgile";
import { useGetRitualReleasesQuery } from "./api.solitaireAgile";
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
// open panel follows the step. Escape closes the panel.
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

/** A stop's accessible name: the whole fact, as a screen reader hears it. */
export function stopLabel(r: Release): string {
  const head = r.inProgress
    ? `In progress${r.previous ? `, since ${r.previous}` : ""}`
    : `${r.tag}, shipped ${dayWords(r.date)}`;
  const reached = reachedCount(r);
  const aimed = r.milestones.length - reached;
  return [
    head,
    plural(entryCount(r), "entry", "entries"),
    ...(reached ? [`${plural(reached, "milestone")} reached`] : []),
    ...(aimed ? [`${plural(aimed, "milestone")} open`] : []),
  ].join(", ");
}

/** A milestone's one line: reached on its day, or how far along it is. */
export function milestoneWords(m: ReleaseMilestone): string {
  if (m.reachedOn) return `reached ${dayWords(m.reachedOn)}`;
  const total = m.open + m.closed;
  return total ? `open, ${m.closed} of ${total} closed` : "open, no issues yet";
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

function ReleasePanel({
  r,
  id,
  selectedMilestone,
  onClose,
}: {
  r: Release;
  id: string;
  selectedMilestone: string;
  onClose: () => void;
}) {
  const styles = useStyles();
  const headingId = useId();
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
      <Link href={r.url} target="_blank" rel="noopener noreferrer">
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
                <Link href={m.url} target="_blank" rel="noopener noreferrer">
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
                    <Body1>{e}</Body1>
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
                <Link href={p.url} target="_blank" rel="noopener noreferrer">
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
          <Body1>
            {r.issues.map((i, n) => (
              <span key={i.number}>
                {n > 0 ? ", " : ""}
                <Link href={i.url} target="_blank" rel="noopener noreferrer">
                  #{i.number}
                </Link>
              </span>
            ))}
          </Body1>
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
  const panelId = useId();

  const step = useCallback(
    (to: number) => {
      const next = Math.max(0, Math.min(releases.length - 1, to));
      setSelected(next);
      setMilestone("");
      stops.current[next]?.focus();
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
        <div className={styles.scroller}>
          <div
            className={styles.track}
            role="group"
            aria-label="Releases, newest first"
            onKeyDown={onKey}
          >
            {releases.map((r, i) => {
              const gold = reachedCount(r) > 0;
              return (
                <div
                  key={r.tag || "in-progress"}
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
                          stops.current[i]?.focus();
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
                    aria-label={stopLabel(r)}
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
                      <strong>{releaseName(r)}</strong>
                    </Body1>
                    <Caption1 className={styles.stopMeta}>{releaseWhen(r)}</Caption1>
                    <Caption1 className={styles.stopMeta}>
                      {plural(entryCount(r), "entry", "entries")}
                    </Caption1>
                  </button>
                </div>
              );
            })}
          </div>
        </div>
        {open && current ? (
          <ReleasePanel r={current} id={panelId} selectedMilestone={milestone} onClose={close} />
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
