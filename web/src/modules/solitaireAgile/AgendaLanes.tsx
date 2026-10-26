import { useNavigate } from "react-router";
import {
  Button,
  Caption1,
  Subtitle2,
  makeStyles,
  mergeClasses,
  tokens,
} from "@fluentui/react-components";
import { BoardCover } from "../ado/CardCover";
import { CARD_FACE_BOX, CardName, CardProgress } from "../ado/CardFace";
import { cardPath } from "../ado/paths";
import { RITUALS } from "../../shell/consts";
import type { Agenda, AgendaItem, StandupResponse } from "./api.solitaireAgile";
import { IssuePopover } from "./IssuePopover";
import type { IssueFacts } from "./IssuePopover";
import { REVIEW_IT, WORK_IT_NOW, agendaArg, agendaFact, sinceHeading } from "./agenda";

// The Agenda (docs/modules/solitaire-agile.md, "The page"): the standup's two
// questions as tiles -- what moved since the standup's window opened, and what is
// waiting on you -- read from the response's `agenda`, which the agent derives
// from the same read the text is rendered from. Nothing here re-derives a lane.
//
// A tile LOOKS like a board card because it is built from the board's own pieces
// (CardCover.tsx, CardFace.tsx): the cover, the name, the progress. It is not the
// board's tile -- no drag, no menu. One renderer for both kinds: an issue with no
// card simply has no cover and no progress. Each tile says one fact, with a long
// date, and no lane badge and no relative day: "Active since Friday 23 October".
// The first lane's tiles have no action; the second's have one -- Work it now
// (the hand-off box, the same one Start work opens) or, waiting on a review,
// Review it.
//
// The list is the same two groups as compact rows, with the same one button.

const useStyles = makeStyles({
  root: { display: "flex", flexDirection: "column", gap: tokens.spacingVerticalM },
  lanes: {
    display: "grid",
    gridTemplateColumns: "repeat(auto-fit, minmax(min(100%, 300px), 1fr))",
    gap: tokens.spacingHorizontalM,
    alignItems: "start",
  },
  // The board's lane, borrowed by look: the same ground, border and radius.
  lane: {
    display: "flex",
    flexDirection: "column",
    gap: tokens.spacingVerticalS,
    minWidth: 0,
    padding: tokens.spacingVerticalM,
    backgroundColor: tokens.colorNeutralBackgroundAlpha,
    border: `1px solid ${tokens.colorNeutralStroke2}`,
    borderRadius: tokens.borderRadiusLarge,
  },
  tiles: {
    display: "grid",
    gridTemplateColumns: "repeat(auto-fill, minmax(min(100%, 220px), 1fr))",
    gap: tokens.spacingVerticalS,
  },
  card: CARD_FACE_BOX,
  top: { display: "flex", alignItems: "flex-start", gap: tokens.spacingHorizontalXS },
  meta: {
    display: "flex",
    alignItems: "center",
    flexWrap: "wrap",
    gap: tokens.spacingHorizontalS,
  },
  quiet: { color: tokens.colorNeutralForeground3 },
  action: { alignSelf: "flex-start" },
  list: { listStyle: "none", margin: 0, padding: 0, display: "flex", flexDirection: "column" },
  row: {
    display: "flex",
    flexWrap: "wrap",
    alignItems: "baseline",
    columnGap: tokens.spacingHorizontalS,
    padding: `${tokens.spacingVerticalXS} 0`,
    borderBottom: `1px solid ${tokens.colorNeutralStroke2}`,
  },
  rowTitle: { flex: 1, minWidth: "12rem" },
});

interface TileProps {
  item: AgendaItem;
  moved: boolean;
  facts?: IssueFacts;
  onWork: (arg: string) => void;
}

/** The ref, as the standup page names it: an issue's number opens its popover. */
function Ref({ item, facts }: { item: AgendaItem; facts?: IssueFacts }) {
  const styles = useStyles();
  if (item.kind === "issue" && item.url)
    return <IssuePopover facts={facts ?? { label: item.ref, title: item.title, url: item.url }} />;
  // A card's id opens the same surface the standup's rows gave it: id, title, path.
  if (item.ref)
    return <IssuePopover facts={{ label: item.ref, title: item.title, path: item.path }} />;
  return <Caption1 className={styles.quiet}>{item.ref}</Caption1>;
}

/** The one button a waiting tile carries; nothing on what moved. */
function Action({ item, moved, onWork }: Omit<TileProps, "facts">) {
  const styles = useStyles();
  const navigate = useNavigate();
  if (moved) return null;
  if (item.review) {
    const label = `${REVIEW_IT}: ${item.ref}`;
    if (item.file)
      return (
        <Button
          className={styles.action}
          size="small"
          aria-label={label}
          onClick={() => navigate(cardPath(item.file))}
        >
          {REVIEW_IT}
        </Button>
      );
    if (item.url)
      return (
        <Button
          className={styles.action}
          size="small"
          as="a"
          href={item.url}
          target="_blank"
          rel="noopener noreferrer"
          aria-label={label}
        >
          {REVIEW_IT}
        </Button>
      );
    return null;
  }
  const arg = agendaArg(item);
  if (!arg) return null;
  return (
    <Button
      className={styles.action}
      size="small"
      appearance="primary"
      aria-label={`${WORK_IT_NOW}: ${item.ref}`}
      onClick={() => onWork(arg)}
    >
      {WORK_IT_NOW}
    </Button>
  );
}

/** One Agenda card: the board's cover, name and progress, one fact, one button. */
export function AgendaCard({ item, moved, facts, onWork }: TileProps) {
  const styles = useStyles();
  const navigate = useNavigate();
  const open = item.file ? () => navigate(cardPath(item.file)) : undefined;
  return (
    <div className={styles.card} data-agenda-card={item.ref}>
      <BoardCover cover={item.cover} label={item.title} />
      <div className={styles.top}>
        <CardName onOpen={open} title={item.file || undefined}>
          {item.title}
        </CardName>
      </div>
      <div className={styles.meta}>
        <Ref item={item} facts={facts} />
      </div>
      <CardProgress checked={item.checked} total={item.total} progress={item.progress} />
      <Caption1 className={styles.quiet} data-agenda-fact="">
        {agendaFact(item, moved)}
      </Caption1>
      <Action item={item} moved={moved} onWork={onWork} />
    </div>
  );
}

function AgendaRow({ item, moved, facts, onWork }: TileProps) {
  const styles = useStyles();
  return (
    <li className={styles.row} data-agenda-row={item.ref}>
      <Ref item={item} facts={facts} />
      <span className={styles.rowTitle}>{item.title}</span>
      <Caption1 className={styles.quiet} data-agenda-fact="">
        {agendaFact(item, moved)}
      </Caption1>
      <Action item={item} moved={moved} onWork={onWork} />
    </li>
  );
}

/** The Agenda's two groups, as cards or as rows. */
export function AgendaLanes({
  data,
  view,
  facts,
  onWork,
}: {
  data: StandupResponse;
  view: string;
  facts?: Map<number, IssueFacts>;
  onWork: (arg: string) => void;
}) {
  const styles = useStyles();
  const agenda: Agenda = data.agenda ?? { moved: [], waiting: [] };
  const groups = [
    {
      key: "moved",
      heading: sinceHeading(data.since),
      items: agenda.moved,
      moved: true,
      empty: "Nothing moved.",
    },
    {
      key: "waiting",
      heading: RITUALS.text.queueHeading,
      items: agenda.waiting,
      moved: false,
      empty: RITUALS.text.queueEmpty,
    },
  ];
  const factsOf = (i: AgendaItem) => (i.number != null ? facts?.get(i.number) : undefined);
  return (
    <div className={mergeClasses(styles.root, view === "cards" && styles.lanes)}>
      {groups.map((g) => (
        <section
          key={g.key}
          className={view === "cards" ? styles.lane : undefined}
          aria-label={g.heading}
          data-agenda-group={g.key}
        >
          <Subtitle2 as="h2">{g.heading}</Subtitle2>
          {g.items.length === 0 ? (
            <Caption1 className={styles.quiet}>{g.empty}</Caption1>
          ) : view === "cards" ? (
            <div className={styles.tiles}>
              {g.items.map((i) => (
                <AgendaCard
                  key={i.ref}
                  item={i}
                  moved={g.moved}
                  facts={factsOf(i)}
                  onWork={onWork}
                />
              ))}
            </div>
          ) : (
            <ul className={styles.list}>
              {g.items.map((i) => (
                <AgendaRow
                  key={i.ref}
                  item={i}
                  moved={g.moved}
                  facts={factsOf(i)}
                  onWork={onWork}
                />
              ))}
            </ul>
          )}
        </section>
      ))}
    </div>
  );
}
