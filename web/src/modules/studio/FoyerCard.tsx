import { useCallback, useEffect, useState } from "react";
import { BuildingFactoryRegular } from "@fluentui/react-icons";
import { useNavigate } from "react-router";
import { ROW } from "../../shared/CardActions";
import { trackerName } from "../ado/TrackerBadge";
import type { CardAction } from "../../shared/CardActions";
import type { EmptyMessage } from "../../shared/EmptyState";
import { HubSyncLine } from "../ado/HubSyncLine";
import { usePersistedValue } from "../../shared/usePersistedState";
import { visibilityLabel } from "../../shared/visibility";
import { useGetEnvQuery } from "../../shell/api";
import type { SpaceInfo } from "../../shell/api";
import { VISIBILITY } from "../../shell/consts";
import { ListPanel } from "../../shell/kinds/ListPanel";
import type { BadgeSpec, CardItemData, MetaItem } from "../../shell/CardItem";
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
import { SPACE_MOVES } from "./spaceMoves";
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
// as every list panel does. A row's `...` holds the end of a Space's life:
// Retire and Remove, each RetireSpace / RemoveSpace through the bridge behind
// the house confirm, which shows the verb's own -WhatIf first.

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
    : foyerLine(entry?.report, entry?.deploys, undefined, entry?.design);
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
  const navigate = useNavigate();
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
  // The item is the switch the avatar menu makes (D-S2): the one switch, which
  // a design note's Space takes too.
  const { enter, switching, failed } = useEnterSpace(active);
  const icon = <BuildingFactoryRegular />;
  // Two empties, and they are different facts: no Space at all, and a filter
  // that matches none -- that one sits under the chips, which stay reachable.
  const empty: EmptyMessage = { icon, title: "No Spaces yet", detail: SPACE_DEFINITION };
  const filteredEmpty: EmptyMessage | undefined =
    spaces.length > 0
      ? {
          icon,
          tone: "filtered",
          title: spacesFilterEmpty(filter),
          detail: `${spaces.length} ${spaces.length === 1 ? "Space is" : "Spaces are"} under All.`,
        }
      : undefined;

  /** A Space, as a card item: name, kind, where you are, the line, and the door. */
  const toItem = (space: SpaceInfo): CardItemData => {
    const here = space.slug === active;
    const name = space.name || space.slug;
    const menu: CardAction[] = [];
    // A Space that is not yet connected is one step from what connecting
    // shows: the connect wizard is the core's, and the same door the How-do-I
    // list opens.
    if (space.status !== "active" && space.status !== "archive") {
      menu.push(
        SPACE_MOVES.connect.action({
          detail: name,
          onClick: () => navigate(`/connect/${space.slug}`),
        }),
      );
    }
    // The end of its life: Retire keeps it declared and archived, Remove
    // un-declares it -- its folder and cards stay either way.
    for (const action of spaceLifecycleActions(space, here)) {
      menu.push(
        action === "retire"
          ? SPACE_MOVES.retire.action({
              detail: name,
              onClick: () => setEnding({ space, verb: "RetireSpace" }),
            })
          : SPACE_MOVES.remove.action({
              detail: name,
              onClick: () => setEnding({ space, verb: "RemoveSpace" }),
            }),
      );
    }
    // The Space's address on its tracker: the external link, last.
    const tracker = trackerName(space.tracker);
    if (space.org && tracker) menu.push(ROW.external.action({ detail: tracker, href: space.org }));
    const badges: BadgeSpec[] = [{ label: spaceKind(space), color: "informative" }];
    if (space.status === "archive") badges.push({ label: "archived", color: "subtle" });
    if (here) badges.push({ label: "you are here", color: "brand" });
    const meta: MetaItem[] = [
      { badge: { label: "Space", color: "subtle" } },
      { text: space.slug, shrink: true },
    ];
    if (failed === space.slug) {
      meta.push({ text: `Could not switch to ${name}. Nothing changed.`, tone: "alert" });
    }
    return {
      id: space.slug,
      title: name,
      badges,
      description: reads[space.slug]?.line ?? undefined,
      meta,
      primary: ROW.open.action({
        detail: name,
        onClick: () => enter(space.slug),
        disabled: switching,
      }),
      menu,
    };
  };

  return (
    <>
      <ListPanel
        title="Spaces"
        icon={icon}
        items={listed}
        item={toItem}
        empty={empty}
        filteredEmpty={filteredEmpty}
        loading={drawn ? undefined : { label: "Reading the Spaces..." }}
        // No helper sentence on this panel, populated or empty: the title, the
        // chips (All and its count say "these are all your Spaces") and the
        // items carry it, and the empty panel is its title and the +.
        filters={
          spaces.length > 0
            ? [
                {
                  label: "Filter Spaces",
                  chips: SPACES_FILTERS.map((f) => {
                    const n = filterSpaces(spaces, f.value).length;
                    return {
                      id: f.value,
                      label: f.label,
                      count: n > 0 ? n : undefined,
                      active: filter === f.value,
                      onSelect: () => setFilter(f.value),
                    };
                  }),
                },
              ]
            : undefined
        }
        refresh={{
          onClick: () => setGeneration((g) => g + 1),
          isFetching: !drawn || refreshing,
        }}
        count={spaces.length}
        countLabel={`${spaces.length} Spaces`}
        status={
          outcome
            ? { tone: "success", text: outcome, onDismiss: () => setOutcome(null) }
            : undefined
        }
        create={{ label: "New Space", onClick: () => setAdding(true) }}
        footNote={<HubSyncLine />}
      />
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
