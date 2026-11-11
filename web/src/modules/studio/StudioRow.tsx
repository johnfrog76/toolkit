import type { ReactNode } from "react";
import { LIST_CARD_HEIGHT_PX, LIST_CARD_MIN_WIDTH_PX } from "../../shell/cardHeight";
import {
  Body1,
  Caption1,
  Card,
  Link,
  Tooltip,
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
// the full title and description are in a tooltip that opens on hover and on
// keyboard focus.
const TITLE_BAND_PX = 28;
const DESCRIPTION_LINES = 2;
const DESCRIPTION_LINE_PX = 16;
const META_BAND_PX = 20;

const useStyles = makeStyles({
  row: {
    marginTop: tokens.spacingVerticalS,
    padding: tokens.spacingVerticalS,
    backgroundColor: tokens.colorNeutralBackgroundAlpha,
    display: "grid",
    gridTemplateRows: `${TITLE_BAND_PX}px ${DESCRIPTION_LINES * DESCRIPTION_LINE_PX}px ${META_BAND_PX}px`,
    rowGap: tokens.spacingVerticalXXS,
    flexShrink: 0,
    minWidth: 0,
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
      height: `${LIST_CARD_HEIGHT_PX}px`,
    },
  },
});

/** The class every Studio list card wears: one height, the Focus cards', on a
 *  wide page, so Spaces, Hub Designs and Prompts line up. */
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
  /** Makes the title a button that opens the row's page. Without it the title
   *  is plain text that can still take focus, so the tooltip is reachable. */
  onOpen?: () => void;
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

export function StudioRow({
  title,
  onOpen,
  badges,
  controls,
  description,
  meta,
  kind,
}: StudioRowProps) {
  const styles = useStyles();
  const full = (
    <div>
      <div>
        <strong>{title}</strong>
      </div>
      {description ? <div>{description}</div> : null}
    </div>
  );
  const titleText = onOpen ? (
    <Link as="button" appearance="subtle" className={styles.title} onClick={onOpen}>
      <Body1>
        <strong>{title}</strong>
      </Body1>
    </Link>
  ) : (
    <Body1 className={styles.title} tabIndex={0}>
      <strong>{title}</strong>
    </Body1>
  );
  return (
    <Card className={styles.row} size="small" appearance="outline" data-studio-row={kind}>
      <div className={styles.titleLine}>
        <Tooltip content={full} relationship="inaccessible" positioning="below-start">
          <div className={mergeClasses(styles.head, styles.text)} data-row-text>
            {titleText}
            {badges ? <span className={styles.badges}>{badges}</span> : null}
          </div>
        </Tooltip>
        {controls ? <div className={styles.controls}>{controls}</div> : null}
      </div>
      <Tooltip content={full} relationship="inaccessible" positioning="below-start">
        <Caption1 className={styles.description} data-row-description>
          {description ?? ""}
        </Caption1>
      </Tooltip>
      <div className={styles.meta} data-row-meta>
        {meta}
      </div>
    </Card>
  );
}
