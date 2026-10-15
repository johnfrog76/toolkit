import { useMemo, useState } from "react";
import { useNavigate } from "react-router";
import {
  Button,
  Badge,
  Subtitle2,
  tokens,
  makeStyles,
  Card,
  Tooltip,
  Dropdown,
  Option,
} from "@fluentui/react-components";
import { ArrowRightRegular, Clock12Regular } from "@fluentui/react-icons";
import { DECKS } from "./decks/index";
import { DeckState } from "./decks/types";
import { estimateDeckDuration } from "./engine/deckDuration";
import { PageCard } from "../../shared/PageCard";
import { Pagination } from "../../shared/Pagination";
import { usePagination } from "../../hooks/usePagination";
import { FilterBadge } from "../../shared/FilterBadge";

const STATE_BADGE: Record<DeckState, { label: string; color: "subtle" }> = {
  [DeckState.Draft]: { label: "draft", color: "subtle" },
  [DeckState.InProgress]: { label: "in progress", color: "subtle" },
  [DeckState.Complete]: { label: "complete", color: "subtle" },
  [DeckState.Archive]: { label: "archive", color: "subtle" },
};

const STATE_FILTERS: DeckState[] = [
  DeckState.Draft,
  DeckState.InProgress,
  DeckState.Complete,
  DeckState.Archive,
];

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
}

export function DeckPicker({ tagFilter }: DeckPickerProps) {
  const styles = usePickerStyles();
  const navigate = useNavigate();
  const [stateFilter, setStateFilter] = useState<DeckState | null>(null);

  // Registration order in DECKS is chronological (oldest first) — reverse so
  // the newest presentation shows first.
  const newestFirst = useMemo(() => [...DECKS].reverse(), []);

  const stateCounts = useMemo(() => {
    const counts: Partial<Record<DeckState, number>> = {};
    for (const deck of newestFirst) {
      const state = deck.state ?? DeckState.Complete;
      counts[state] = (counts[state] ?? 0) + 1;
    }
    return counts;
  }, [newestFirst]);

  const filteredDecks = useMemo(
    () =>
      newestFirst
        .filter(
          (deck) => stateFilter === null || (deck.state ?? DeckState.Complete) === stateFilter,
        )
        .filter((deck) => tagFilter === ALL_TAGS || (deck.tags ?? []).includes(tagFilter)),
    [newestFirst, stateFilter, tagFilter],
  );

  const {
    page,
    totalPages,
    pageItems: pageDecks,
    setPage,
  } = usePagination(filteredDecks, PAGE_SIZE);

  const handleStateChange = (next: DeckState | null) => {
    setStateFilter(next);
    setPage(0);
  };

  // A filter that can only ever show everything is a control that changes
  // nothing -- the same rule as the Home drawer's
  // applies here: with every deck in one state (today, both are Complete),
  // the state row is the SECOND filter on a card with one deck to filter,
  // and it filters nothing.
  const distinctStates = Object.values(stateCounts).filter((n) => (n ?? 0) > 0).length;

  if (DECKS.length === 0) {
    return (
      <span style={{ color: tokens.colorNeutralForeground3, fontSize: tokens.fontSizeBase200 }}>
        No decks registered.
      </span>
    );
  }

  return (
    <div>
      {distinctStates > 1 && (
        <div className={styles.filterRow}>
          <FilterBadge
            label="All"
            count={newestFirst.length}
            active={stateFilter === null}
            onClick={() => handleStateChange(null)}
          />
          {STATE_FILTERS.map((s) => (
            <FilterBadge
              key={s}
              label={STATE_BADGE[s].label}
              count={stateCounts[s] ?? 0}
              active={stateFilter === s}
              onClick={() => handleStateChange(stateFilter === s ? null : s)}
            />
          ))}
        </div>
      )}
      {filteredDecks.length === 0 && (
        <span style={{ color: tokens.colorNeutralForeground3, fontSize: tokens.fontSizeBase200 }}>
          No decks match this filter.
        </span>
      )}
      <div className={styles.list}>
        {pageDecks.map((deck) => {
          const slides = deck.slides();
          const slideCount = slides.length;
          const duration = estimateDeckDuration(slides);
          const state = STATE_BADGE[deck.state ?? DeckState.Complete];
          return (
            <Card key={deck.id} size="small" appearance="outline" className={styles.card}>
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
                <Badge appearance="tint" color={state.color} size="small">
                  {state.label}
                </Badge>
                <Button
                  icon={<ArrowRightRegular />}
                  size="small"
                  appearance="subtle"
                  title="Present deck"
                  onClick={() => navigate(`/deck/${deck.id}`)}
                />
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
            {DECKS?.length ?? 0}
          </Badge>
        </>
      }
    >
      <DeckPicker tagFilter={tagFilter} />
    </PageCard>
  );
}
