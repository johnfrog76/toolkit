import { useMemo, useState } from "react";
import type { MouseEvent } from "react";
import { useNavigate } from "react-router";
import {
  Badge,
  Subtitle2,
  tokens,
  makeStyles,
  Card,
  Tooltip,
  Dropdown,
  Option,
} from "@fluentui/react-components";
import { Clock12Regular } from "@fluentui/react-icons";
import { DECKS } from "./decks/index";
import { estimateDeckDuration } from "./engine/deckDuration";
import { CardActions, ROW } from "../../shared/CardActions";
import {
  ARCHIVED_FILTER,
  STATE_LABEL,
  STATE_ORDER,
  archivedIds,
  deckListView,
  deckState,
} from "./deckList";
import type { DeckFilter } from "./deckList";
import { DECK_MOVES } from "./deckMoves";
import { deckPagePath, deckPlayPath } from "./paths";
import { useGetEnvQuery } from "../../shell/api";
import { PageCard } from "../../shared/PageCard";
import { Pagination } from "../../shared/Pagination";
import { usePagination } from "../../hooks/usePagination";
import { FilterBadge } from "../../shared/FilterBadge";

const PAGE_SIZE = 5;
const ALL_TAGS = "all";

const usePickerStyles = makeStyles({
  list: {
    display: "flex",
    flexDirection: "column",
  },
  card: {
    marginTop: tokens.spacingVerticalS,
    padding: tokens.spacingVerticalS,
    backgroundColor: tokens.colorNeutralBackgroundAlpha,
    cursor: "pointer",
  },
  cardItem: {
    display: "flex",
    alignItems: "flex-start",
    justifyContent: "space-between",
    gap: tokens.spacingHorizontalM,
  },
  cardBody: {
    flex: 1,
    minWidth: 0,
  },
  meta: {
    display: "flex",
    flexDirection: "column",
    gap: "2px",
  },
  titleRow: {
    display: "flex",
    alignItems: "center",
    gap: tokens.spacingHorizontalS,
    minWidth: 0,
  },
  title: {
    // flex: 1 and minWidth: 0 are both load-bearing for the ellipsis below:
    // without them a flex item sizes to its own content and never truncates
    // until the row is already narrower than the text, which is later than a
    // reader expects when the card still has visible width to its right.
    flex: "1 1 auto",
    minWidth: 0,
    fontSize: tokens.fontSizeBase300,
    fontWeight: tokens.fontWeightSemibold,
    color: tokens.colorNeutralForeground1,
    overflow: "hidden",
    textOverflow: "ellipsis",
    whiteSpace: "nowrap",
  },
  subtitle: {
    fontSize: tokens.fontSizeBase200,
    color: tokens.colorNeutralForeground3,
    marginTop: tokens.spacingVerticalXS,
  },
  pager: {
    display: "flex",
    justifyContent: "center",
    marginTop: tokens.spacingVerticalM,
  },
  filterRow: {
    display: "flex",
    gap: tokens.spacingHorizontalS,
    flexWrap: "wrap",
    marginBottom: tokens.spacingVerticalS,
  },
});

interface DeckPickerProps {
  tagFilter: string;
  /** This machine's put-away list (`deck.archived`), from /env. */
  archived: string[];
}

export function DeckPicker({ tagFilter, archived }: DeckPickerProps) {
  const styles = usePickerStyles();
  const navigate = useNavigate();
  const [filter, setFilter] = useState<DeckFilter>(null);

  // Registration order in DECKS is chronological (oldest first) — reverse so
  // the newest presentation shows first.
  const newestFirst = useMemo(() => [...DECKS].reverse(), []);

  // The default list leaves out what this machine has put away; the archived
  // chip shows those. A filter that can only ever show everything is a control
  // that changes nothing -- the same rule as the Home drawer's -- so the state
  // chips wait until two decks in the list differ, and the archived chip until
  // a deck is put away (deckList.ts holds both).
  const view = useMemo(
    () => deckListView(newestFirst, archived, filter),
    [newestFirst, archived, filter],
  );
  // A filter left on a chip that has gone (the last archived deck brought back) reads as All.
  const active: DeckFilter =
    (filter === ARCHIVED_FILTER && !view.showArchived) ||
    (filter !== null && filter !== ARCHIVED_FILTER && !view.showStates)
      ? null
      : filter;
  const shown = useMemo(
    () =>
      (active === filter ? view.shown : view.current).filter(
        (deck) => tagFilter === ALL_TAGS || (deck.tags ?? []).includes(tagFilter),
      ),
    [active, filter, view, tagFilter],
  );

  const { page, totalPages, pageItems: pageDecks, setPage } = usePagination(shown, PAGE_SIZE);

  const choose = (next: DeckFilter) => {
    setFilter(active === next ? null : next);
    setPage(0);
  };

  if (DECKS.length === 0) {
    return (
      <span style={{ color: tokens.colorNeutralForeground3, fontSize: tokens.fontSizeBase200 }}>
        No decks registered.
      </span>
    );
  }

  // The row's controls sit inside a row that is itself a click target.
  const only = (e: MouseEvent) => e.stopPropagation();

  return (
    <div>
      {(view.showStates || view.showArchived) && (
        <div className={styles.filterRow} role="group" aria-label="Filter decks">
          <FilterBadge
            label="All"
            count={view.current.length}
            active={active === null}
            onClick={() => choose(null)}
          />
          {view.showStates &&
            STATE_ORDER.map((s) => (
              <FilterBadge
                key={s}
                label={STATE_LABEL[s]}
                count={view.stateCounts[s] ?? 0}
                active={active === s}
                onClick={() => choose(s)}
              />
            ))}
          {view.showArchived && (
            <FilterBadge
              label={ARCHIVED_FILTER}
              count={view.archived.length}
              active={active === ARCHIVED_FILTER}
              onClick={() => choose(ARCHIVED_FILTER)}
            />
          )}
        </div>
      )}
      {shown.length === 0 && (
        <span style={{ color: tokens.colorNeutralForeground3, fontSize: tokens.fontSizeBase200 }}>
          {view.current.length === 0 && active === null
            ? "Every deck is archived on this machine -- the archived filter shows them."
            : "No decks match this filter."}
        </span>
      )}
      <div className={styles.list}>
        {pageDecks.map((deck) => {
          const slides = deck.slides();
          const slideCount = slides.length;
          const duration = estimateDeckDuration(slides);
          const open = () => navigate(deckPagePath(deck.id));
          return (
            <Card
              key={deck.id}
              size="small"
              appearance="outline"
              className={styles.card}
              onClick={open}
            >
              <div className={styles.cardItem}>
                <div className={styles.cardBody}>
                  <div className={styles.meta}>
                    <div className={styles.titleRow}>
                      <Badge appearance="tint" color="brand" size="small">
                        deck
                      </Badge>
                      <Tooltip content={deck.title} relationship="label">
                        <span className={styles.title}>{deck.title}</span>
                      </Tooltip>
                    </div>
                    <span className={styles.subtitle}>
                      {slideCount} slides · /deck/{deck.id}
                    </span>
                  </div>
                </div>
                <Badge
                  appearance="tint"
                  color="success"
                  size="small"
                  icon={<Clock12Regular />}
                  title={`Approximate time to get through this deck (~${duration})`}
                >
                  {duration}
                </Badge>
                <Badge appearance="tint" color="informative" size="small">
                  {deck.id}
                </Badge>
                <Badge appearance="tint" color="subtle" size="small">
                  {STATE_LABEL[deckState(deck)]}
                </Badge>
                <span onClick={only}>
                  {/* The row's one exposed action is its page; the menu plays it.
                      No deck carries an address of its own (the Deck type has no
                      field for one), so no row has a link out to put last. */}
                  <CardActions
                    primaryAction={ROW.open.action({ detail: "the deck", onClick: open })}
                    menuLabel={`Actions for ${deck.title}`}
                    secondaryActions={[
                      DECK_MOVES.play.action({ onClick: () => navigate(deckPlayPath(deck.id)) }),
                    ]}
                  />
                </span>
              </div>
            </Card>
          );
        })}
      </div>
      <div className={styles.pager}>
        <Pagination page={page} totalPages={totalPages} onPageChange={setPage} />
      </div>
    </div>
  );
}

export function DeckPickerCard() {
  const [tagFilter, setTagFilter] = useState<string>(ALL_TAGS);
  const { data: env } = useGetEnvQuery();
  const archived = archivedIds(env?.config?.deckArchived);
  const listed = DECKS.filter((d) => !archived.includes(d.id)).length;

  const allTags = useMemo(() => {
    const tags = new Set<string>();
    for (const deck of DECKS) {
      for (const tag of deck.tags ?? []) tags.add(tag);
    }
    return [...tags].sort();
  }, []);

  return (
    <PageCard
      headerLeft={<Subtitle2>Decks</Subtitle2>}
      headerRight={
        <>
          {allTags.length > 0 && (
            <Dropdown
              size="small"
              aria-label="Tag"
              value={tagFilter === ALL_TAGS ? "All" : tagFilter}
              selectedOptions={[tagFilter]}
              onOptionSelect={(_e, d) => setTagFilter(d.optionValue as string)}
              style={{ minWidth: "110px" }}
            >
              <Option value={ALL_TAGS} text="All">
                All
              </Option>
              {allTags.map((tag) => (
                <Option key={tag} value={tag} text={tag}>
                  {tag}
                </Option>
              ))}
            </Dropdown>
          )}
          <Badge color="informative" appearance="filled" size="large">
            {listed}
          </Badge>
        </>
      }
    >
      <DeckPicker tagFilter={tagFilter} archived={archived} />
    </PageCard>
  );
}
