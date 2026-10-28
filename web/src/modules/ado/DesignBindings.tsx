import { Badge, Caption1, Link, Tooltip, makeStyles, tokens } from "@fluentui/react-components";
import { LightbulbRegular } from "@fluentui/react-icons";
import { useNavigate } from "react-router";
import { notePath } from "../studio/paths";
import { cardPath } from "./paths";
import type { BoundCard, CardDesign } from "./api.ado";
import { stateColor } from "./DesignGroups";
import { designRoomPath, roomFor } from "./docRooms";

// The card and its design, bound both ways (docs/hub/design.md). A card names the design it was worked against with one line
// under its Template line; the agent parses it into the card's `design` and, on
// the card's own page, resolves the id -- so this file decides nothing:
//
//   - the CHIP on the card page: the design's short id and title, its state when
//     the agent could read it, and a click into its reading room (the Studio's
//     for a hub design, the Design tab's for a repo's). Unconnected -- the id
//     resolved nowhere -- it is the short id and the title last written. A
//     hand-written Spec line has no id: the chip shows its words as written.
//   - the CARDS on a design's row (the Design tab and Hub Designs): every card
//     whose line carries the design's id, read by the agent on every request.

const useStyles = makeStyles({
  chip: {
    display: "inline-flex",
    alignItems: "center",
    gap: tokens.spacingHorizontalXS,
    maxWidth: "100%",
    minWidth: 0,
  },
  chipText: { overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" },
  cards: {
    display: "flex",
    flexWrap: "wrap" as const,
    gap: tokens.spacingHorizontalS,
    alignItems: "center",
    marginTop: tokens.spacingVerticalXS,
  },
  muted: { color: tokens.colorNeutralForeground3 },
});

/** The app route that reads the design, or null when the agent could not place it. */
export function designRoom(design: Pick<CardDesign, "where" | "path">): string | null {
  if (!design.path) return null;
  if (design.where === "hub") return notePath(design.path);
  if (design.where === "repo") {
    const cut = design.path.lastIndexOf("/");
    if (cut <= 0) return null;
    return designRoomPath(design.path.slice(0, cut), design.path.slice(cut + 1));
  }
  return null;
}

/** The chip's words: the short id and the title for a Design line; the title
 *  and the words after it for a hand-written Spec line. */
export function chipLabel(design: CardDesign): string {
  if (design.id)
    return [design.short || design.id.slice(0, 8), design.title].filter(Boolean).join(" ");
  return [design.title, design.note].filter(Boolean).join(" ") || design.link;
}

/** What the chip's tooltip says: the id and its state, or why there is none. */
export function chipSays(design: CardDesign): string {
  if (!design.id) {
    const kind = design.kind === "spec" ? "Spec" : "Design";
    return `Worked against ${design.link || design.title} -- a hand-written ${kind} line, read as written`;
  }
  if (design.state) return `Worked against the design ${design.id} -- ${design.state}`;
  return `Worked against the design ${design.id} -- not read from the hub or this Space's repo, so this is the line as last written`;
}

/** The chip on the card page. Nothing when the card names no design. */
export function DesignChip({ design }: { design: CardDesign | null | undefined }) {
  const styles = useStyles();
  const navigate = useNavigate();
  if (!design) return null;
  const room = designRoom(design);
  const external = !room && /^https:\/\//.test(design.link) ? design.link : null;
  const body = (
    <span className={styles.chip}>
      <LightbulbRegular aria-hidden />
      <span className={styles.chipText}>{chipLabel(design)}</span>
      {design.state ? (
        <Badge appearance="tint" size="small" color={stateColor(design.state)}>
          {design.state}
        </Badge>
      ) : null}
    </span>
  );
  return (
    <Tooltip content={chipSays(design)} relationship="description">
      <span data-design-chip={design.id || design.kind}>
        {room ? (
          <Link
            onClick={() => navigate(room)}
            aria-label={`Open the design ${design.title || design.short}`}
          >
            {body}
          </Link>
        ) : external ? (
          <Link href={external} target="_blank" rel="noopener noreferrer">
            {body}
          </Link>
        ) : (
          <Caption1>{body}</Caption1>
        )}
      </span>
    </Tooltip>
  );
}

/** Where a bound card can be opened in the app: the card page reads the active
 *  Space's current/, so another Space's card, or an archived one, is named only. */
export function boundCardPath(card: BoundCard, activeSpace: string | undefined): string | null {
  if (card.archived) return null;
  if (activeSpace && card.space && card.space !== activeSpace) return null;
  return cardPath(card.file);
}

/** The cards on a design's row. Nothing when no card names it. */
export function BoundCards({
  cards,
  activeSpace,
}: {
  cards: BoundCard[] | undefined;
  activeSpace?: string;
}) {
  const styles = useStyles();
  const navigate = useNavigate();
  if (!cards || cards.length === 0) return null;
  return (
    <div className={styles.cards} role="group" aria-label="Cards worked against this design">
      <Caption1 className={styles.muted}>
        {cards.length === 1 ? "1 card" : `${cards.length} cards`}
      </Caption1>
      {cards.map((c) => {
        const to = boundCardPath(c, activeSpace);
        const words = `${c.id ?? c.file} ${c.status}`;
        const where = activeSpace && c.space && c.space !== activeSpace ? ` (${c.space})` : "";
        return (
          <Tooltip
            key={`${c.space}/${c.archived ? "a" : "c"}/${c.file}`}
            content={c.title || c.file}
            relationship="description"
          >
            {to ? (
              <Link onClick={() => navigate(to)}>{words}</Link>
            ) : (
              <Caption1>
                {words}
                {where}
              </Caption1>
            )}
          </Tooltip>
        );
      })}
    </div>
  );
}

/**
 * A Complete design's Docs line: where its durable part landed. A link to the
 * room the Docs tab reads that path in when `linked` (the path is in the active
 * Space's repository) and the app has a room for it; else the plain caption.
 */
export function DesignDocsLine({ docs, linked }: { docs: string; linked: boolean }) {
  const navigate = useNavigate();
  const room = linked ? roomFor(docs) : null;
  return room ? (
    <Caption1 title="Where its durable part landed">
      Docs: <Link onClick={() => navigate(room)}>{docs}</Link>
    </Caption1>
  ) : (
    <Caption1 title="Where its durable part landed">Docs: {docs}</Caption1>
  );
}
