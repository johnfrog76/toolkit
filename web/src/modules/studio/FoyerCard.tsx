import { useCallback, useEffect, useState } from "react";
import type { ReactNode } from "react";
import {
  Badge,
  Body1,
  Caption1,
  Card,
  Subtitle2,
  makeStyles,
  tokens,
} from "@fluentui/react-components";
import {
  ArchiveRegular,
  ArrowEnterRegular,
  BuildingFactoryRegular,
  LinkRegular,
  OpenRegular,
  SubtractCircleRegular,
} from "@fluentui/react-icons";
import { useNavigate } from "react-router";
import { CardActions } from "../../shared/CardActions";
import { CreateButton } from "../../shared/CreateButton";
import type { CardAction } from "../../shared/CardActions";
import { FilterBadge } from "../../shared/FilterBadge";
import { useFilterRowStyles, useListRowStyles } from "../../shared/listRowStyles";
import { EmptyState } from "../../shared/EmptyState";
import { PageCard } from "../../shared/PageCard";
import { Pagination } from "../../shared/Pagination";
import { RefreshButton } from "../../shared/RefreshButton";
import { usePagination } from "../../hooks/usePagination";
import { StatusMessage } from "../../shared/StatusMessage";
import { usePersistedValue } from "../../shared/usePersistedState";
import { visibilityLabel } from "../../shared/visibility";
import { useGetEnvQuery } from "../../shell/api";
import type { SpaceInfo } from "../../shell/api";
import { VISIBILITY } from "../../shell/consts";
import { useGetStatusQuery } from "../ado/api.ado";
import {
  useGetSpaceStatusQuery,
  useGetStudioLedgerQuery,
  useRefreshStudioLedgerMutation,
} from "./api.studio";
import type { SpaceLedger } from "./api.studio";
import {
  SPACES_FILTERS,
  cardsLine,
  filterSpaces,
  foyerLine,
  foyerSpaces,
  githubRowLine,
  isGithubRow,
  isSpacesFilter,
  readsCards,
  readsVisibility,
  spaceKind,
  spaceLifecycleActions,
  spacesFilterEmpty,
} from "./foyer";
import type { SpacesFilter } from "./foyer";
import type { SpaceLifecycleVerb } from "./api.studio";
import { NewSpaceDialog } from "./NewSpaceDialog";
import { SpaceLifecycleDialog } from "./SpaceLifecycleDialog";
import { STUDIO_PAGE_SIZE } from "./paths";
import { useEnterSpace } from "./useEnterSpace";

// The one sentence that says what a Space is. Written here and in docs/modules/studio.md.
const SPACE_DEFINITION =
  "A Space is where you work on one piece of software: your cards on a board, and the tracker's issues, designs and stats beside them once it is connected.";

// The foyer (Studio S2b, D-S2 as amended by D-S13): one row per Space -- every
// Space, whatever its tracker -- each read for THAT Space without switching
// into it: every GitHub row from one ledger read for all of them (one gh call
// on the agent, kept on its disk), every other row from its cards on disk
// through the core's /api/status. Never a merged backlog
// (D-G11): a row says how the Space stands in one line, and the row is the door
// into it. The foyer asks nothing; the one thing it keeps is the filter's
// choice, in this browser -- a convenience, never a setting. Its + adds
// a Space: the New Space dialog, which runs NewSpace through the bridge.
// It loads once and whole, reads again only on its Refresh, and pages its rows
// ten at a time. A row's `...` holds the end of a Space's life:
// Retire and Remove, each RetireSpace / RemoveSpace through the bridge behind
// the house confirm, which shows the verb's own -WhatIf first.
const useStyles = makeStyles({
  title: {
    flex: 1,
    minWidth: 0,
    display: "flex",
    flexDirection: "column",
    rowGap: tokens.spacingVerticalXXS,
  },
  name: {
    display: "flex",
    alignItems: "center",
    columnGap: tokens.spacingHorizontalS,
    flexWrap: "wrap",
  },
  line: { color: tokens.colorNeutralForeground2 },
});

const OPEN_LABEL: Record<string, string> = {
  github: "Open on GitHub",
  ado: "Open in Azure DevOps",
};

/** The row's frame: name, kind, where you are, the line, and the door. */
function FoyerRow({
  space,
  here,
  line,
  onLifecycle,
}: {
  space: SpaceInfo;
  here: boolean;
  line: ReactNode;
  onLifecycle: (space: SpaceInfo, verb: SpaceLifecycleVerb) => void;
}) {
  const own = useStyles();
  const rows = useListRowStyles();
  const styles = { ...own, ...rows };
  const navigate = useNavigate();
  // The row is the switch the avatar menu makes (D-S2): the one switch, which
  // a design note's Space chip takes too.
  const { enter: enterSpace, switching, failed } = useEnterSpace(space.slug, here);
  const name = space.name || space.slug;
  const secondary: CardAction[] = [];
  // A Space that is not yet connected is one step from what connecting shows:
  // the connect wizard (/connect/<slug>) is the core's, and the same door the
  // How-do-I list opens.
  if (space.status !== "active" && space.status !== "archive") {
    secondary.push({
      icon: <LinkRegular />,
      label: `Connect ${name}`,
      onClick: () => navigate(`/connect/${space.slug}`),
    });
  }
  // The end of its life: Retire keeps it declared and archived, Remove
  // un-declares it -- its folder and cards stay either way.
  for (const action of spaceLifecycleActions(space, here)) {
    secondary.push(
      action === "retire"
        ? {
            icon: <ArchiveRegular />,
            label: `Retire ${name}`,
            onClick: () => onLifecycle(space, "RetireSpace"),
          }
        : {
            icon: <SubtractCircleRegular />,
            label: `Remove ${name}`,
            onClick: () => onLifecycle(space, "RemoveSpace"),
          },
    );
  }
  const openLabel = space.tracker ? OPEN_LABEL[space.tracker] : undefined;
  if (space.org && openLabel) {
    secondary.push({
      icon: <OpenRegular />,
      label: openLabel,
      href: space.org,
      dividerBefore: secondary.length > 0,
    });
  }
  return (
    <Card className={styles.row} size="small" appearance="outline">
      <div className={styles.rowHeader}>
        <div className={styles.title}>
          <div className={styles.name}>
            <Body1>
              <strong>{name}</strong>
            </Body1>
            <Badge appearance="outline" size="small" color="informative">
              {spaceKind(space)}
            </Badge>
            {space.status === "archive" ? (
              <Badge appearance="tint" size="small" color="subtle">
                archived
              </Badge>
            ) : null}
            {here ? (
              <Badge appearance="tint" size="small" color="brand">
                you are here
              </Badge>
            ) : null}
          </div>
          <Caption1 className={styles.line}>{line}</Caption1>
          {failed ? (
            <Caption1 role="alert">Could not switch to {name}. Nothing changed.</Caption1>
          ) : null}
        </div>
        <CardActions
          primaryAction={{
            icon: <ArrowEnterRegular />,
            label: here ? `Open ${name}` : `Go into ${name}`,
            onClick: enterSpace,
            disabled: switching,
          }}
          menuLabel={`Actions for ${name}`}
          secondaryActions={secondary}
        />
      </div>
    </Card>
  );
}

/** What one Space's reads came to: its line once every read has settled --
 *  answered or failed -- null before; and whether any of them is fetching. */
interface RowRead {
  line: string | null;
  fetching: boolean;
}
type OnRead = (slug: string, read: RowRead) => void;

/** Reports a Space's read up to the card whenever it changes. */
function useReport(slug: string, line: string | null, fetching: boolean, onRead: OnRead) {
  useEffect(() => {
    onRead(slug, { line, fetching });
  }, [slug, line, fetching, onRead]);
}

/** What the card's one ledger read came to, for every GitHub row. */
interface LedgerRead {
  spaces?: Record<string, SpaceLedger>;
  failed: boolean;
  fetching: boolean;
}

/** A GitHub Space's line, from its slot in the card's ledger read
 *  (GET /api/studio/ledger: every GitHub Space's issues, deploys and
 *  repository visibility in one read). Visibility is said only for a
 *  connected Space; a ledger that did not answer is `Visibility unknown` on
 *  the line, never a guess. Draws nothing: the card draws the row
 *  once every row has its line. */
function GithubReads({
  space,
  ledger,
  onRead,
}: {
  space: SpaceInfo;
  ledger: LedgerRead;
  onRead: OnRead;
}) {
  const asks = readsVisibility(space);
  const entry = ledger.spaces?.[space.slug];
  const visibility = !asks
    ? ""
    : ledger.failed
      ? visibilityLabel(VISIBILITY.unknown)
      : entry
        ? visibilityLabel(entry.visibility.visibility)
        : null;
  const facts = ledger.failed
    ? "Could not read this Space's issues -- the agent did not answer."
    : foyerLine(entry?.report, entry?.deploys);
  const line = ledger.failed || entry ? githubRowLine(visibility, facts) : null;
  useReport(space.slug, line, ledger.fetching, onRead);
  return null;
}

/** An Azure DevOps Space's reads, or one with no tracker: its cards, counted
 *  in place under the Space's own lane names. The Space you are in reads the
 *  core's /api/status (the Board's own cache); any other, unless archived, the
 *  same route through its `space` argument. A failed read says so on
 *  that row only. */
function CardsReads({
  space,
  here,
  laneNames,
  generation,
  onRead,
}: {
  space: SpaceInfo;
  here: boolean;
  laneNames?: Record<string, string>;
  generation: number;
  onRead: OnRead;
}) {
  const reads = readsCards(space, here);
  const mine = useGetStatusQuery(undefined, { skip: !here });
  const theirs = useGetSpaceStatusQuery(space.slug, { skip: here || !reads });
  const status = here ? mine : theirs;
  useEffect(() => {
    if (generation === 0 || !reads) return;
    void status.refetch();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [generation]);
  const line =
    reads && status.error
      ? "Could not read this Space's cards -- the agent did not answer."
      : cardsLine(space, reads, status.data, space.laneNames ?? laneNames);
  useReport(space.slug, line, Boolean(reads && status.isFetching), onRead);
  return null;
}

/** Where this browser keeps the Spaces card's filter. */
export const SPACES_FILTER_KEY = "studio.spaces.filter";

export function FoyerCard() {
  const styles = useFilterRowStyles();
  const { data: env, isLoading } = useGetEnvQuery();
  const spaces = foyerSpaces(env);
  const active = env?.config?.activeSpace ?? "";
  const laneNames = env?.config?.laneNames;
  // The filter: opens on All, remembered per browser. A stored value the
  // dropdown does not offer -- or a browser that refuses storage -- reads as All.
  const { value: stored, setValue: setFilter } = usePersistedValue(
    SPACES_FILTER_KEY,
    "all",
    isSpacesFilter,
  );
  const filter = stored as SpacesFilter;
  const shown = filterSpaces(spaces, filter);
  const [adding, setAdding] = useState(false);
  const [ending, setEnding] = useState<{ space: SpaceInfo; verb: SpaceLifecycleVerb } | null>(null);
  const [outcome, setOutcome] = useState<string | null>(null);
  // One clean load: every Space's reads start at once, each row's
  // reader reports its line here, and the card stays on its loading state
  // until every line has settled -- answered or failed -- then draws the list
  // once. ALL Spaces are read up front, not the visible page: the reads run in
  // parallel, so that costs only the slowest row, and a page or filter change
  // then never lands on a row that has not been read. Once drawn, the card
  // never goes back to loading: a Refresh keeps the list and spins the button,
  // and a Space added later joins the list when its own line is ready.
  const [reads, setReads] = useState<Record<string, RowRead>>({});
  const onRead = useCallback<OnRead>((slug, read) => {
    setReads((prev) =>
      prev[slug]?.line === read.line && prev[slug]?.fetching === read.fetching
        ? prev
        : { ...prev, [slug]: read },
    );
  }, []);
  const [drawn, setDrawn] = useState(false);
  if (!drawn && !isLoading && spaces.every((s) => reads[s.slug]?.line != null)) setDrawn(true);
  const refreshing = Object.values(reads).some((r) => r.fetching);
  // Refresh: each reader reads its Space again when this moves.
  const [generation, setGeneration] = useState(0);
  // Every GitHub row's facts come from ONE read, asked once a GitHub Space is
  // declared; Refresh asks it again past the agent's disk cache.
  const ledgerQuery = useGetStudioLedgerQuery(undefined, { skip: !spaces.some(isGithubRow) });
  const [refreshLedger, refreshingLedger] = useRefreshStudioLedgerMutation();
  useEffect(() => {
    if (generation === 0 || !spaces.some(isGithubRow)) return;
    void refreshLedger();
    // Refresh is the only thing that asks again.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [generation]);
  const ledger: LedgerRead = {
    spaces: ledgerQuery.data?.spaces,
    failed: ledgerQuery.data === undefined && ledgerQuery.error != null,
    fetching: Boolean(ledgerQuery.isFetching || refreshingLedger.isLoading),
  };
  const listed = shown.filter((s) => reads[s.slug]?.line != null);
  const { page, totalPages, pageItems, setPage } = usePagination(listed, STUDIO_PAGE_SIZE);
  const choose = (next: SpacesFilter) => {
    setFilter(next);
    setPage(0);
  };
  // Two empties, and they are different facts: no Space at all (nothing to
  // filter, so it takes the body's place), and a filter that matches none --
  // that one sits UNDER the tag row, which has to stay reachable.
  const empty = !drawn ? undefined : spaces.length === 0 ? (
    <EmptyState icon={<BuildingFactoryRegular />} title="No Spaces yet" detail={SPACE_DEFINITION} />
  ) : undefined;
  const filteredEmpty =
    spaces.length > 0 && shown.length === 0 ? (
      <EmptyState
        icon={<BuildingFactoryRegular />}
        tone="filtered"
        title={spacesFilterEmpty(filter)}
        detail={`${spaces.length} ${spaces.length === 1 ? "Space is" : "Spaces are"} under All.`}
      />
    ) : null;
  return (
    <>
      <PageCard
        // scrollable, like the Reminders and Hub Designs cards: the rows then sit
        // in the card's scroll area, whose only spacing is the row's own margin.
        // Without it they were direct children of the card and took its 12px
        // gap ON TOP of that margin -- the looser list the owner marked.
        scrollable
        loading={!drawn}
        loadingLabel="Reading the Spaces..."
        empty={empty}
        headerLeft={
          <>
            <BuildingFactoryRegular />
            <Subtitle2>Spaces</Subtitle2>
          </>
        }
        headerRight={
          <>
            {/* The house position, as the Environment card has it: Refresh
                left of the count chip. */}
            <RefreshButton
              onClick={() => setGeneration((g) => g + 1)}
              isFetching={!drawn || refreshing}
            />
            <Badge
              color="informative"
              appearance="filled"
              size="large"
              aria-label={`${spaces.length} Spaces`}
            >
              {spaces.length}
            </Badge>
          </>
        }
        footerCenter={
          totalPages > 1 ? (
            <Pagination page={page} totalPages={totalPages} onPageChange={setPage} />
          ) : undefined
        }
        footerRight={<CreateButton label="New Space" onClick={() => setAdding(true)} />}
      >
        {outcome ? (
          <StatusMessage status="success" onDismiss={() => setOutcome(null)}>
            {outcome}
          </StatusMessage>
        ) : null}
        {/* No helper sentence on this card, populated or empty: the
            title, the tags (All and its count say "these are all your Spaces")
            and the rows carry it, and the empty card is its title and the +. */}
        <div className={styles.chips} role="group" aria-label="Filter Spaces">
          {SPACES_FILTERS.map((f) => {
            const n = filterSpaces(spaces, f.value).length;
            return (
              <FilterBadge
                key={f.value}
                label={f.label}
                count={n > 0 ? n : undefined}
                active={filter === f.value}
                onClick={() => choose(f.value)}
              />
            );
          })}
        </div>
        {filteredEmpty}
        {pageItems.map((s) => (
          <FoyerRow
            key={s.slug}
            space={s}
            here={s.slug === active}
            line={reads[s.slug]?.line}
            onLifecycle={(space, verb) => setEnding({ space, verb })}
          />
        ))}
      </PageCard>
      {/* The readers: one per Space, every Space, outside the card -- the card
          draws no children while it loads, and these are what it waits on. */}
      {spaces.map((s) =>
        isGithubRow(s) ? (
          <GithubReads key={s.slug} space={s} ledger={ledger} onRead={onRead} />
        ) : (
          <CardsReads
            key={s.slug}
            space={s}
            here={s.slug === active}
            laneNames={laneNames}
            generation={generation}
            onRead={onRead}
          />
        ),
      )}
      <NewSpaceDialog
        open={adding}
        spaces={env?.config?.spaces ?? []}
        onClose={() => setAdding(false)}
        onAdded={(name) => {
          setAdding(false);
          setOutcome(`Added ${name}. Its row is in the list; go into it from there.`);
        }}
      />
      <SpaceLifecycleDialog
        target={ending}
        onClose={() => setEnding(null)}
        onDone={(said) => {
          setEnding(null);
          setOutcome(said);
        }}
      />
    </>
  );
}
