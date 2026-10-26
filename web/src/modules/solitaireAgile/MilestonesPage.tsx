import { useEffect, useMemo, useState } from "react";
import {
  Badge,
  Body1,
  Button,
  Caption1,
  ProgressBar,
  Subtitle2,
  makeStyles,
  tokens,
} from "@fluentui/react-components";
import { FlagRegular, OpenRegular, TrophyRegular } from "@fluentui/react-icons";
import { useGetEnvQuery } from "../../shell/api";
import { lazyPart } from "../../shell/lazy";
import { EmptyState } from "../../shared/EmptyState";
import { PageCard } from "../../shared/PageCard";
import type { Milestone } from "../ado/api.ado";
import { milestoneProgress, milestoneStage, orderMilestones } from "../ado/milestones";
import { useGetRitualMilestonesQuery } from "./api.solitaireAgile";
import type { AwardStage } from "./award";
import { awardKey, awardStage, dayWords, markAwarded, pendingAwards } from "./award";

// The Milestones tab (docs/modules/solitaire-agile.md, "Milestones: the tab and the
// award"): Team Agile's third page, after Standup and Triage. One row per milestone
// of the Space's tracker, each with a bar -- closed over total issues, the tracker's
// own numbers through GET /api/ritual/milestones --, the due date where there is one,
// and its state: open, reached, or awarded (this browser has shown its dialog).
//
// When a milestone is reached and the person next opens the tab, the award dialog
// opens for it -- once per Space and milestone per browser (award.ts) -- and is the
// one place the module throws confetti. Several waiting are awarded one after
// another, in the list's order. The queue is taken once, when the tab first reads
// the list: a milestone reached while you watch is awarded on your next visit.
//
// The rows are the Stats card's rules (ado/milestones.ts): the same order (in
// flight, then reached, then empty) and the same reached word, so the two
// surfaces cannot disagree about a milestone.

// The dialog and the confetti package are fetched when an award is first drawn.
const AwardDialog = lazyPart(
  () => import("./AwardDialog"),
  (m) => m.AwardDialog,
);

const useStyles = makeStyles({
  row: {
    display: "grid",
    gridTemplateColumns: "minmax(0, 1fr) auto",
    alignItems: "center",
    columnGap: tokens.spacingHorizontalM,
    paddingTop: tokens.spacingVerticalS,
    paddingBottom: tokens.spacingVerticalS,
    borderBottom: `1px solid ${tokens.colorNeutralStroke3}`,
  },
  body: {
    display: "flex",
    flexDirection: "column",
    rowGap: tokens.spacingVerticalXXS,
    minWidth: 0,
  },
  head: {
    display: "flex",
    flexWrap: "wrap",
    alignItems: "center",
    columnGap: tokens.spacingHorizontalS,
  },
  meta: {
    display: "flex",
    flexWrap: "wrap",
    columnGap: tokens.spacingHorizontalM,
    color: tokens.colorNeutralForeground3,
  },
});

/** What a row's state badge says. */
export const STAGE_WORDS: Record<AwardStage, string> = {
  "in flight": "open",
  reached: "reached",
  awarded: "awarded",
  empty: "no issues yet",
};

const STAGE_COLOR: Record<AwardStage, "brand" | "success" | "informative" | "subtle"> = {
  "in flight": "brand",
  reached: "success",
  awarded: "success",
  empty: "subtle",
};

/** "5 of 8 closed" -- the tracker's own two numbers. */
export const countWords = (m: Milestone): string => `${m.closed} of ${m.open + m.closed} closed`;

function MilestoneRow({ m, stage }: { m: Milestone; stage: AwardStage }) {
  const styles = useStyles();
  const due = dayWords(m.due);
  return (
    <div className={styles.row} data-testid="milestone-row" data-milestone={m.title}>
      <div className={styles.body}>
        <div className={styles.head}>
          <Body1>
            <strong>{m.title}</strong>
          </Body1>
          <Badge
            appearance={stage === "awarded" ? "filled" : "tint"}
            color={STAGE_COLOR[stage]}
            icon={stage === "awarded" ? <TrophyRegular /> : undefined}
            data-testid="milestone-state"
          >
            {STAGE_WORDS[stage]}
          </Badge>
        </div>
        <ProgressBar
          value={milestoneProgress(m)}
          thickness="large"
          color={m.reached ? "success" : "brand"}
          aria-label={`${m.title}: ${countWords(m)}`}
        />
        <div className={styles.meta}>
          <Caption1>{countWords(m)}</Caption1>
          {due ? <Caption1>due {due}</Caption1> : null}
          {m.state === "closed" ? <Caption1>closed on the tracker</Caption1> : null}
        </div>
      </div>
      {/* The external link, last in the row, as external links are. */}
      <Button
        size="small"
        appearance="subtle"
        icon={<OpenRegular />}
        title="Open on GitHub"
        aria-label={`Open ${m.title} on GitHub`}
        as="a"
        href={m.url}
        target="_blank"
        rel="noopener noreferrer"
      />
    </div>
  );
}

export function MilestonesPage() {
  const styles = useStyles();
  const { data: env, isLoading: envLoading } = useGetEnvQuery();
  const space = env?.config?.activeSpace ?? "";
  const { data, isLoading, error } = useGetRitualMilestonesQuery(space, { skip: envLoading });
  const readable = !!data && !error && data.tracker.ok;
  const slug = data?.space || space;
  const list = useMemo(() => (readable ? orderMilestones(data.milestones) : []), [readable, data]);

  // The awards this visit owes, taken ONCE when the list first reads: the reached
  // milestones with no mark. Taken while rendering (React's "adjusting state when
  // a prop changes"), so the first draw with the list already knows its queue; the
  // marks are only set in the effect below, so a second render reads the same one.
  const [queue, setQueue] = useState<Milestone[] | null>(null);
  if (queue === null && readable) setQueue(pendingAwards(slug, list));
  const awarding = queue?.[0] ?? null;
  // The mark is set when the dialog is SHOWN, one at a time: closing the page
  // mid-award never shows that award again, and the ones still waiting keep theirs.
  useEffect(() => {
    if (awarding) markAwarded(slug, awarding);
  }, [awarding, slug]);
  const waiting = new Set((queue ?? []).map((m) => awardKey(slug, m)));
  const stageOf = (m: Milestone): AwardStage =>
    waiting.has(awardKey(slug, m)) ? milestoneStage(m) : awardStage(slug, m);

  const icon = <FlagRegular />;
  const empty =
    isLoading || envLoading ? undefined : error || !data ? (
      <EmptyState
        icon={icon}
        tone="error"
        title="Could not read the milestones"
        detail="The agent did not answer. Nothing was read."
      />
    ) : !data.tracker.ok ? (
      <EmptyState
        icon={icon}
        tone="error"
        title="Could not read the milestones"
        detail={data.tracker.reason}
      />
    ) : list.length === 0 ? (
      <EmptyState
        icon={icon}
        title="No milestones yet"
        detail="Milestones are made on the tracker; each one shows here with how far along it is."
      />
    ) : undefined;

  return (
    <div className={styles.body}>
      <PageCard
        loading={envLoading || isLoading}
        loadingLabel="Reading the milestones..."
        empty={empty}
        headerLeft={
          <>
            {icon}
            <Subtitle2 as="h1">Milestones</Subtitle2>
          </>
        }
      >
        {list.map((m) => (
          <MilestoneRow key={`${m.repo}-${m.number}`} m={m} stage={stageOf(m)} />
        ))}
      </PageCard>
      {awarding && (
        <AwardDialog
          key={awardKey(slug, awarding)}
          milestone={awarding}
          onClose={() => setQueue((q) => (q ? q.slice(1) : q))}
        />
      )}
    </div>
  );
}
