import { useMemo, useState } from "react";
import { useNavigate } from "react-router";
import { Clock12Regular, SlideTextRegular } from "@fluentui/react-icons";
import { DECKS } from "./decks/index";
import type { Deck } from "./decks/types";
import { estimateDeckDuration } from "./engine/deckDuration";
import { ROW } from "../../shared/CardActions";
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
import { ListPanel } from "../../shell/kinds/ListPanel";
import type { FilterChip } from "../../shell/kinds/ListPanel";
import type { CardItemData } from "../../shell/CardItem";

const ALL_TAGS = "all";

// The Decks panel: every registered deck, newest first, each a card item whose
// one exposed action is its page and whose menu plays it. No deck carries an
// address of its own (the Deck type has no field for one), so no item has a
// link out to put last. Nothing to refresh and nothing to create: the decks
// are the build's.
export function DeckPickerCard() {
  const navigate = useNavigate();
  const [tagFilter, setTagFilter] = useState<string>(ALL_TAGS);
  const [filter, setFilter] = useState<DeckFilter>(null);
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

  // Registration order in DECKS is chronological (oldest first) — reverse so
  // the newest presentation shows first.
  const newestFirst = useMemo(() => [...DECKS].reverse(), []);

  // The default list leaves out what this machine has put away; the archived
  // chip shows those. A filter that can only ever show everything is a control
  // that changes nothing -- the same rule as the Home drawer's -- so the state
  // chips wait until two decks in the list differ, and the archived chip until
  // a deck is put away (deckList.ts holds both).
  const view = deckListView(newestFirst, archived, filter);
  // A filter left on a chip that has gone (the last archived deck brought back) reads as All.
  const active: DeckFilter =
    (filter === ARCHIVED_FILTER && !view.showArchived) ||
    (filter !== null && filter !== ARCHIVED_FILTER && !view.showStates)
      ? null
      : filter;
  const shown = (active === filter ? view.shown : view.current).filter(
    (deck) => tagFilter === ALL_TAGS || (deck.tags ?? []).includes(tagFilter),
  );

  const choose = (next: DeckFilter) => setFilter(active === next ? null : next);
  const chips: FilterChip[] = [
    {
      id: "all",
      label: "All",
      count: view.current.length,
      active: active === null,
      onSelect: () => choose(null),
    },
  ];
  if (view.showStates) {
    for (const s of STATE_ORDER) {
      chips.push({
        id: s,
        label: STATE_LABEL[s],
        count: view.stateCounts[s] ?? 0,
        active: active === s,
        onSelect: () => choose(s),
      });
    }
  }
  if (view.showArchived) {
    chips.push({
      id: ARCHIVED_FILTER,
      label: ARCHIVED_FILTER,
      count: view.archived.length,
      active: active === ARCHIVED_FILTER,
      onSelect: () => choose(ARCHIVED_FILTER),
    });
  }

  const toItem = (deck: Deck): CardItemData => {
    const slides = deck.slides();
    const duration = estimateDeckDuration(slides);
    return {
      id: deck.id,
      title: deck.title,
      description: `${slides.length} slides · /deck/${deck.id}`,
      meta: [
        { badge: { label: "deck", color: "brand" } },
        {
          badge: {
            label: duration,
            color: "success",
            glyph: <Clock12Regular />,
            title: `Approximate time to get through this deck (~${duration})`,
          },
        },
        { badge: { label: deck.id, color: "informative" } },
        { badge: { label: STATE_LABEL[deckState(deck)], color: "subtle" } },
      ],
      primary: ROW.open.action({
        detail: "the deck",
        onClick: () => navigate(deckPagePath(deck.id)),
      }),
      menu: [DECK_MOVES.play.action({ onClick: () => navigate(deckPlayPath(deck.id)) })],
    };
  };

  const icon = <SlideTextRegular />;
  return (
    <ListPanel
      title="Decks"
      items={shown}
      item={toItem}
      empty={
        DECKS.length === 0
          ? { icon, title: "No decks registered" }
          : {
              icon,
              title: "Every deck is archived on this machine",
              detail: "The archived filter shows them.",
            }
      }
      filteredEmpty={
        DECKS.length > 0 && !(view.current.length === 0 && active === null)
          ? { icon, tone: "filtered", title: "No decks match this filter" }
          : undefined
      }
      filters={
        view.showStates || view.showArchived ? [{ label: "Filter decks", chips }] : undefined
      }
      pickers={
        allTags.length > 0
          ? [
              {
                label: "Tag",
                value: tagFilter,
                options: [
                  { value: ALL_TAGS, label: "All" },
                  ...allTags.map((tag) => ({ value: tag, label: tag })),
                ],
                onChange: setTagFilter,
              },
            ]
          : undefined
      }
      count={listed}
    />
  );
}
