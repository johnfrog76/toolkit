import type { ReactNode } from "react";
import {
  LIST_CARD_HEIGHT_PX,
  LIST_CARD_MIN_WIDTH_PX,
  LIST_ITEM_HEIGHT_PX,
} from "../../shell/cardHeight";
import {
  Body1,
  Caption1,
  Card,
  makeStyles,
  mergeClasses,
  tokens,
} from "@fluentui/react-components";

// The one row the Studio's three cards draw (Spaces, Hub Designs, Prompts):
// the title on one line with its status badges and the row's controls at the
// right, up to two lines of description, and one bottom line for the kind
// badge, the hash and the file name. The three bands have fixed heights, so
// every row of every card is the same height whatever its text -- a row with
// no description keeps its two lines empty. Text is clamped with an ellipsis;
// the full text stays in the DOM (a screen reader reads all of it) and there
// is no tooltip: Open is how a person sees more. The title is plain text; the row exposes one action, Open,
// and keeps every other in the `...` menu.
const TITLE_BAND_PX = 24;
const DESCRIPTION_LINES = 2;
const DESCRIPTION_LINE_PX = 15;
const META_BAND_PX = 18;
const ROW_PADDING_PX = 4;

const useStyles = makeStyles({
  row: {
    marginTop: tokens.spacingVerticalXS,
    padding: `${ROW_PADDING_PX}px ${tokens.spacingHorizontalS}`,
    backgroundColor: tokens.colorNeutralBackgroundAlpha,
    display: "grid",
    gridTemplateRows: `${TITLE_BAND_PX}px ${DESCRIPTION_LINES * DESCRIPTION_LINE_PX}px ${META_BAND_PX}px`,
    rowGap: 0,
    flexShrink: 0,
    minWidth: 0,
    height: `${LIST_ITEM_HEIGHT_PX}px`,
    boxSizing: "border-box",
    overflow: "hidden",
  },
  titleLine: {
    display: "flex",
    alignItems: "center",
    justifyContent: "space-between",
    columnGap: tokens.spacingHorizontalS,
    minWidth: 0,
  },
  text: { minWidth: 0 },
  head: {
    display: "flex",
    alignItems: "center",
    columnGap: tokens.spacingHorizontalS,
    minWidth: 0,
    flex: 1,
  },
  title: {
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
    WebkitLineClamp: String(DESCRIPTION_LINES),
    overflow: "hidden",
    lineHeight: `${DESCRIPTION_LINE_PX}px`,
    overflowWrap: "anywhere",
  },
  meta: {
    display: "flex",
    alignItems: "center",
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
});

const useCardStyles = makeStyles({
  card: {
    [`@media (min-width: ${LIST_CARD_MIN_WIDTH_PX}px)`]: {
      minHeight: `${LIST_CARD_HEIGHT_PX}px`,
    },
  },
});

/** The class every Studio list card wears: one height, the Focus cards', on a
 *  wide page, so Spaces, Hub Designs and Prompts line up. */
const useChipStyles = makeStyles({
  chips: {
    display: "flex",
    flexWrap: "nowrap",
    overflowX: "auto",
    gap: tokens.spacingHorizontalXXS,
    marginBottom: tokens.spacingVerticalXS,
    // The chips are tighter here and never wrap: at the narrowest width the
    // row scrolls sideways instead.
    "& > [role='radio'], & > [role='checkbox']": {
      flexShrink: 0,
      whiteSpace: "nowrap",
      columnGap: tokens.spacingHorizontalXS,
      paddingLeft: tokens.spacingHorizontalS,
      paddingRight: tokens.spacingHorizontalS,
    },
  },
});

/** The class of a Studio card's filter chips: one row, tight, scrolling not wrapping. */
export function useStudioChipRowClass(): string {
  return useChipStyles().chips;
}

export function useStudioCardClass(): string {
  return useCardStyles().card;
}

/** A bottom-line item that may shrink and show an ellipsis, such as a file name. */
export function RowMetaText({ children, title }: { children: ReactNode; title?: string }) {
  return (
    <Caption1 data-row-meta-text title={title}>
      {children}
    </Caption1>
  );
}

export interface StudioRowProps {
  title: string;
  /** Status badges, beside the title: archived, you are here, the tracker. */
  badges?: ReactNode;
  /** The row's controls, at the right of the title line. */
  controls?: ReactNode;
  /** Up to two lines; longer text is clamped. */
  description?: string;
  /** The bottom line: the kind badge, the hash, the file name. */
  meta?: ReactNode;
  /** Marks the row for tests and the smoke: which card drew it. */
  kind: string;
}

export function StudioRow({ title, badges, controls, description, meta, kind }: StudioRowProps) {
  const styles = useStyles();
  // Plain text, not focusable, never a link or a button: opening goes through
  // the row's Open.
  const titleText = (
    <Body1 className={styles.title}>
      <strong>{title}</strong>
    </Body1>
  );
  return (
    <Card className={styles.row} size="small" appearance="outline" data-studio-row={kind}>
      <div className={styles.titleLine}>
        <div className={mergeClasses(styles.head, styles.text)} data-row-text>
          {titleText}
          {badges ? <span className={styles.badges}>{badges}</span> : null}
        </div>
        {controls ? <div className={styles.controls}>{controls}</div> : null}
      </div>
      <Caption1 className={styles.description} data-row-description>
        {description ?? ""}
      </Caption1>
      <div className={styles.meta} data-row-meta>
        {meta}
      </div>
    </Card>
  );
}
