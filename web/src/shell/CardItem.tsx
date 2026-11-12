import type { ReactElement } from "react";
import {
  Badge,
  Body1,
  Caption1,
  ProgressBar,
  makeStyles,
  mergeClasses,
  tokens,
} from "@fluentui/react-components";
import { CardActions } from "../shared/CardActions";
import type { CardAction } from "../shared/CardActions";
import {
  CARD_ITEM_BORDER_PX,
  CARD_ITEM_COMPACT_HEIGHT_PX,
  CARD_ITEM_DESCRIPTION_BAND_PX,
  CARD_ITEM_DESCRIPTION_LINES,
  CARD_ITEM_DESCRIPTION_LINE_PX,
  CARD_ITEM_HEIGHT_PX,
  CARD_ITEM_LINE_HEIGHT_PX,
  CARD_ITEM_META_BAND_PX,
  CARD_ITEM_PROGRESS_WIDTH_PX,
  CARD_ITEM_THUMB_WIDTH_PX,
  CARD_ITEM_TITLE_BAND_PX,
} from "./cardItemTokens";

// The card item: one entry inside a list panel, drawn by ListPanel from data.
// A panel never draws its own. In `full` density it is three fixed bands -- the
// title on one line with its status badges and the controls at the right, up to
// two lines of description, and one meta band -- so every item is the same
// height whatever its text; an item with no description keeps its two lines
// empty. In `compact` density, for a panel whose items never have a description,
// it is the title line and the meta band with no description band between. In
// `line` density it is one band. The panel chooses the density for all of its
// items; an item never does. Text is clamped with an ellipsis and
// stays whole in the DOM (a screen reader reads all of it); there is no
// tooltip: Open is how a person sees more. The title is plain text, never a
// link; the item exposes one action and keeps every other in the `...` menu.
//
// A plain element styled with Fluent tokens, not a Fluent Card: the clamp, the
// one action and the menu then behave the same on every panel.
// Every length below is a token (cardItemTokens.ts); nothing is typed here.
// An item has no outer spacing of its own; the space between items is the list's.
const useStyles = makeStyles({
  item: {
    backgroundColor: tokens.colorNeutralBackgroundAlpha,
    border: `${CARD_ITEM_BORDER_PX}px solid ${tokens.colorNeutralStroke1}`,
    borderRadius: tokens.borderRadiusSmall,
    color: tokens.colorNeutralForeground1,
    paddingLeft: tokens.spacingHorizontalS,
    paddingRight: tokens.spacingHorizontalS,
    flexShrink: 0,
    minWidth: 0,
    boxSizing: "border-box",
    overflow: "hidden",
  },
  full: {
    display: "grid",
    gridTemplateRows: `${CARD_ITEM_TITLE_BAND_PX}px ${CARD_ITEM_DESCRIPTION_BAND_PX}px ${CARD_ITEM_META_BAND_PX}px`,
    rowGap: 0,
    height: `${CARD_ITEM_HEIGHT_PX}px`,
    // One padding, top and bottom: CARD_ITEM_PADDING_Y_PX is this token's number.
    paddingTop: tokens.spacingVerticalM,
    paddingBottom: tokens.spacingVerticalM,
  },
  compact: {
    display: "grid",
    gridTemplateRows: `${CARD_ITEM_TITLE_BAND_PX}px ${CARD_ITEM_META_BAND_PX}px`,
    // CARD_ITEM_COMPACT_BAND_GAP_PX is this token's number.
    rowGap: tokens.spacingVerticalS,
    height: `${CARD_ITEM_COMPACT_HEIGHT_PX}px`,
    // One padding, top and bottom: CARD_ITEM_PADDING_Y_PX is this token's number.
    paddingTop: tokens.spacingVerticalM,
    paddingBottom: tokens.spacingVerticalM,
  },
  line: {
    display: "flex",
    alignItems: "center",
    columnGap: tokens.spacingHorizontalS,
    height: `${CARD_ITEM_LINE_HEIGHT_PX}px`,
    paddingTop: 0,
    paddingBottom: 0,
    borderTopStyle: "none",
    borderRightStyle: "none",
    borderLeftStyle: "none",
    borderBottomColor: tokens.colorNeutralStroke3,
    borderRadius: 0,
    backgroundColor: "transparent",
  },
  titleLine: {
    display: "flex",
    alignItems: "center",
    justifyContent: "space-between",
    columnGap: tokens.spacingHorizontalS,
    minWidth: 0,
  },
  head: {
    display: "flex",
    alignItems: "center",
    columnGap: tokens.spacingHorizontalS,
    minWidth: 0,
    flex: 1,
  },
  title: {
    // The title's line is the band: no slack over or under it.
    lineHeight: `${CARD_ITEM_TITLE_BAND_PX}px`,
    minWidth: 0,
    overflow: "hidden",
    textOverflow: "ellipsis",
    whiteSpace: "nowrap",
    textAlign: "start",
  },
  badges: {
    display: "flex",
    alignItems: "center",
    columnGap: tokens.spacingHorizontalXS,
    flexShrink: 0,
  },
  controls: { flexShrink: 0, display: "flex", alignItems: "center" },
  description: {
    color: tokens.colorNeutralForeground2,
    display: "-webkit-box",
    WebkitBoxOrient: "vertical",
    WebkitLineClamp: String(CARD_ITEM_DESCRIPTION_LINES),
    overflow: "hidden",
    lineHeight: `${CARD_ITEM_DESCRIPTION_LINE_PX}px`,
    overflowWrap: "anywhere",
  },
  lineText: {
    flex: 1,
    minWidth: 0,
    overflow: "hidden",
    textOverflow: "ellipsis",
    whiteSpace: "nowrap",
  },
  meta: {
    display: "flex",
    alignItems: "center",
    // The band is a badge's height, so nothing is left under the badges.
    height: `${CARD_ITEM_META_BAND_PX}px`,
    lineHeight: `${CARD_ITEM_META_BAND_PX}px`,
    columnGap: tokens.spacingHorizontalM,
    flexWrap: "nowrap",
    overflow: "hidden",
    minWidth: 0,
    "& > *": { flexShrink: 0 },
    "& > [data-row-meta-text]": {
      flexShrink: 1,
      minWidth: 0,
      overflow: "hidden",
      textOverflow: "ellipsis",
      whiteSpace: "nowrap",
    },
  },
  lineMeta: { flexShrink: 0, overflow: "visible" },
  mono: { fontFamily: tokens.fontFamilyMonospace, color: tokens.colorNeutralForeground3 },
  warning: { color: tokens.colorPaletteDarkOrangeForeground1 },
  alert: { color: tokens.colorPaletteRedForeground1 },
  thumb: {
    width: `${CARD_ITEM_THUMB_WIDTH_PX}px`,
    aspectRatio: "16 / 10",
    backgroundSize: "cover",
    backgroundPosition: "center top",
    backgroundRepeat: "no-repeat",
    backgroundColor: tokens.colorNeutralBackground3,
    borderRadius: tokens.borderRadiusSmall,
    border: `${CARD_ITEM_BORDER_PX}px solid ${tokens.colorNeutralStroke2}`,
    boxSizing: "border-box",
  },
  progress: {
    display: "flex",
    alignItems: "center",
    columnGap: tokens.spacingHorizontalXS,
  },
  progressBar: { width: `${CARD_ITEM_PROGRESS_WIDTH_PX}px` },
});

/** A badge, as data: the item draws it small. */
export interface BadgeSpec {
  label: string;
  color?:
    "brand" | "danger" | "important" | "informative" | "severe" | "subtle" | "success" | "warning";
  appearance?: "filled" | "ghost" | "outline" | "tint";
  shape?: "circular" | "rounded";
  /** A small icon before the word. */
  glyph?: ReactElement;
  /** What the badge's short word stands for, as the element's native title. */
  title?: string;
}

/** A piece of text in the meta band. */
export interface MetaText {
  text: string;
  /** What a short word stands for, as the element's native title. */
  title?: string;
  /** May shrink and show an ellipsis, such as a file name. */
  shrink?: boolean;
  /** `warning` is a note, `alert` is announced. */
  tone?: "warning" | "alert";
  /** Fixed-width digits, such as a time. */
  mono?: boolean;
}

/** One thing in the meta band: a badge or a piece of text. */
export type MetaItem = { badge: BadgeSpec } | MetaText;

/** A small picture at the start of the meta band. */
export interface ThumbSpec {
  url: string;
  label: string;
}

/** The one exposed action: Open, from the row vocabulary. */
export type PrimaryAction = CardAction;
/** Any other action, in the `...` menu, from the row vocabulary. */
export type MenuAction = CardAction;

/** A `compact` item: the title line and the meta band. It has no description:
 *  a panel whose items have one is a `full` panel. */
export interface CompactItemData {
  /** Stable among the panel's items; the position on the page when left out. */
  id?: string;
  title: string;
  /** Status badges, beside the title. */
  badges?: BadgeSpec[];
  /** The meta band: the kind badge, a hash, a file name. */
  meta?: MetaItem[];
  thumb?: ThumbSpec;
  /** Checklist progress, drawn as a bar in the meta band. */
  progress?: { done: number; total: number };
  /** Exactly one exposed action. */
  primary: PrimaryAction;
  /** Every other action. */
  menu?: MenuAction[];
  /** The `...` menu's accessible name is "Actions for <name>"; the title when left out. */
  name?: string;
  /** A write on this item is running. */
  busy?: boolean;
  // No href, no link and no onClick on the title: it is plain text.
  // No density: the panel chooses it for every item.
}

/** What a list panel's `item` returns for one entry: data, never JSX. */
export interface CardItemData extends CompactItemData {
  /** Clamped to two lines by the item, never by the panel. */
  description?: string;
}

/** A `line` item: one band. A line that opens nothing has no action. */
export interface LineItemData {
  id?: string;
  title: string;
  description?: string;
  badges?: BadgeSpec[];
  meta?: MetaText[];
  primary?: PrimaryAction;
  menu?: MenuAction[];
  name?: string;
}

function ItemBadge({ spec }: { spec: BadgeSpec }) {
  return (
    <Badge
      size="small"
      appearance={spec.appearance ?? "tint"}
      color={spec.color ?? "informative"}
      shape={spec.shape}
      icon={spec.glyph}
      title={spec.title}
    >
      {spec.label}
    </Badge>
  );
}

function ItemMetaText({ item }: { item: MetaText }) {
  const styles = useStyles();
  return (
    <Caption1
      className={mergeClasses(
        item.mono && styles.mono,
        item.tone === "warning" && styles.warning,
        item.tone === "alert" && styles.alert,
      )}
      data-row-meta-text={item.shrink || item.tone ? "" : undefined}
      role={item.tone === "alert" ? "alert" : item.tone === "warning" ? "note" : undefined}
      title={item.title}
    >
      {item.text}
    </Caption1>
  );
}

function ItemControls({
  title,
  name,
  primary,
  menu,
  busy,
}: {
  title: string;
  name?: string;
  primary?: PrimaryAction;
  menu?: MenuAction[];
  busy?: boolean;
}) {
  const styles = useStyles();
  if (!primary && !menu?.length) return null;
  return (
    <div className={styles.controls} data-row-controls>
      <CardActions
        primaryAction={primary}
        menuLabel={`Actions for ${name ?? title}`}
        secondaryActions={menu}
        busy={busy}
      />
    </div>
  );
}

function Bands({ data, description }: { data: CompactItemData; description?: string | null }) {
  const styles = useStyles();
  const { title, badges, meta, thumb, progress } = data;
  return (
    <div
      className={mergeClasses(styles.item, description === null ? styles.compact : styles.full)}
      data-card-item=""
      data-density={description === null ? "compact" : "full"}
    >
      <div className={styles.titleLine}>
        <div className={styles.head} data-row-text>
          <Body1 className={styles.title}>
            <strong>{title}</strong>
          </Body1>
          {badges?.length ? (
            <span className={styles.badges}>
              {badges.map((b) => (
                <ItemBadge key={b.label} spec={b} />
              ))}
            </span>
          ) : null}
        </div>
        <ItemControls
          title={title}
          name={data.name}
          primary={data.primary}
          menu={data.menu}
          busy={data.busy}
        />
      </div>
      {description === null ? null : (
        <Caption1 className={styles.description} data-row-description>
          {description ?? ""}
        </Caption1>
      )}
      <div className={styles.meta} data-row-meta>
        {thumb ? (
          <div
            className={styles.thumb}
            role="img"
            aria-label={thumb.label}
            data-cover-thumb=""
            style={{ backgroundImage: `url(${JSON.stringify(thumb.url)})` }}
          />
        ) : null}
        {progress && progress.total > 0 ? (
          <span
            className={styles.progress}
            data-row-progress
            title={`${progress.done} of ${progress.total} checklist items completed`}
          >
            <ProgressBar
              className={styles.progressBar}
              value={progress.done / progress.total}
              thickness="large"
              color={progress.done === progress.total ? "success" : "brand"}
            />
            <Caption1>{`${progress.done}/${progress.total}`}</Caption1>
          </span>
        ) : null}
        {meta?.map((m, i) =>
          "badge" in m ? (
            <ItemBadge key={`b${i}`} spec={m.badge} />
          ) : (
            <ItemMetaText key={`t${i}`} item={m} />
          ),
        )}
      </div>
    </div>
  );
}

export interface CardItemProps {
  data: CardItemData;
}

/** A `full` item: three bands. The description band stays, empty, when there is none. */
export function CardItem({ data }: CardItemProps) {
  return <Bands data={data} description={data.description} />;
}

export interface CompactItemProps {
  data: CompactItemData;
}

/** A `compact` item: the title line and the meta band, and no description band. */
export function CompactItem({ data }: CompactItemProps) {
  return <Bands data={data} description={null} />;
}

export interface LineItemProps {
  data: LineItemData;
}

export function LineItem({ data }: LineItemProps) {
  const styles = useStyles();
  const { title, description, badges, meta } = data;
  return (
    <div className={mergeClasses(styles.item, styles.line)} data-card-item="" data-density="line">
      {meta?.length ? (
        <span className={mergeClasses(styles.meta, styles.lineMeta)} data-row-meta>
          {meta.map((m, i) => (
            <ItemMetaText key={i} item={m} />
          ))}
        </span>
      ) : null}
      {badges?.length ? (
        <span className={styles.badges}>
          {badges.map((b) => (
            <ItemBadge key={b.label} spec={b} />
          ))}
        </span>
      ) : null}
      <Caption1 className={styles.lineText} data-row-text>
        <strong>{title}</strong>
        {description ? ` ${description}` : ""}
      </Caption1>
      <ItemControls title={title} name={data.name} primary={data.primary} menu={data.menu} />
    </div>
  );
}
