import {
  Badge,
  Body1,
  Button,
  Caption1,
  Card,
  Subtitle2,
  makeStyles,
  tokens,
} from "@fluentui/react-components";
import { DocumentSearchRegular } from "@fluentui/react-icons";
import type { DesignSearchHit, DesignSearchResponse } from "./api.ado";
import { stateColor } from "./DesignGroups";

// Search inside (design lifecycle L2b): the same words the
// box filters titles by, run over the documents' TEXT -- on disk for the hub,
// through the tracker's code search for a repo. It runs only when asked, after
// the groups are drawn, because code search is Tier 1, rate-limited and slow on
// a cold agent (the Spaces card's lesson): a search that cannot run says
// why in a row, and the note under the results says what the search cannot
// see. A result names the design, its state and the matching line, and opens
// its room. Drawn once here for the Design tab and the hub drawer.

const useStyles = makeStyles({
  section: { marginTop: tokens.spacingVerticalM },
  header: {
    display: "flex",
    alignItems: "center",
    gap: tokens.spacingHorizontalS,
    minHeight: "28px",
  },
  row: {
    marginTop: tokens.spacingVerticalS,
    padding: tokens.spacingVerticalS,
    backgroundColor: tokens.colorNeutralBackgroundAlpha,
  },
  rowHeader: {
    display: "flex",
    alignItems: "flex-start",
    justifyContent: "space-between",
    gap: tokens.spacingHorizontalS,
  },
  title: { flex: 1, minWidth: 0 },
  metaRow: {
    display: "flex",
    gap: tokens.spacingHorizontalM,
    flexWrap: "wrap" as const,
    marginTop: tokens.spacingVerticalXS,
    alignItems: "center",
  },
  line: { fontFamily: tokens.fontFamilyMonospace, whiteSpace: "pre-wrap", wordBreak: "break-word" },
  note: {
    display: "block",
    marginTop: tokens.spacingVerticalS,
    color: tokens.colorNeutralForeground3,
  },
  unavailable: {
    display: "block",
    marginTop: tokens.spacingVerticalS,
    color: tokens.colorPaletteDarkOrangeForeground1,
  },
});

/** The button that asks for a search inside: drawn beside the summary once the
 *  box has words, never before. */
export function SearchInsideButton({
  onClick,
  busy,
  disabled,
}: {
  onClick: () => void;
  busy?: boolean;
  disabled?: boolean;
}) {
  return (
    <Button
      size="small"
      appearance="subtle"
      icon={<DocumentSearchRegular />}
      onClick={onClick}
      disabled={disabled || busy}
    >
      {busy ? "Searching inside…" : "Search inside"}
    </Button>
  );
}

export function DesignSearchInside({
  result,
  loading,
  failed,
  onOpen,
  onClear,
}: {
  result?: DesignSearchResponse;
  loading: boolean;
  /** The agent did not answer at all. */
  failed: boolean;
  /** The room a hit opens in. */
  onOpen: (hit: DesignSearchHit) => void;
  onClear: () => void;
}) {
  const styles = useStyles();
  if (!result && !loading && !failed) return null;
  const hits = result?.hits ?? [];
  return (
    <section className={styles.section} aria-label="Matches inside">
      <div className={styles.header}>
        <DocumentSearchRegular />
        <Subtitle2>Matches inside{result?.query ? ` for "${result.query}"` : ""}</Subtitle2>
        {result ? (
          <Badge appearance="tint" size="small" color="informative">
            {hits.length}
          </Badge>
        ) : null}
        <Button
          size="small"
          appearance="subtle"
          onClick={onClear}
          aria-label="Clear the matches inside"
        >
          Clear
        </Button>
      </div>
      {loading ? <Caption1 role="status">Searching inside the documents…</Caption1> : null}
      {failed ? (
        <Caption1 role="status" className={styles.unavailable}>
          Could not search inside: the agent did not answer. Nothing was read.
        </Caption1>
      ) : null}
      {result && !result.supported ? (
        <Caption1 role="status" className={styles.unavailable}>
          Search inside reads a GitHub repo&apos;s design/ and spec/; this Space has none to read.
        </Caption1>
      ) : null}
      {result && result.supported && !result.available ? (
        <Caption1 role="status" className={styles.unavailable}>
          Could not search inside: {result.reason}
        </Caption1>
      ) : null}
      {result && result.available && hits.length === 0 && !loading ? (
        <Caption1 role="status">Nothing inside the documents carries every word.</Caption1>
      ) : null}
      {hits.map((h) => (
        <Card key={h.path} className={styles.row} size="small" appearance="outline">
          <div className={styles.rowHeader}>
            <div className={styles.title}>
              <Body1>
                <strong>{h.title}</strong>
              </Body1>
            </div>
            <Button
              size="small"
              appearance="subtle"
              onClick={() => onOpen(h)}
              aria-label={`Open ${h.path}`}
            >
              Open
            </Button>
          </div>
          {h.line ? <Caption1 className={styles.line}>{h.line}</Caption1> : null}
          <div className={styles.metaRow}>
            {h.state ? (
              <Badge appearance="tint" size="small" color={stateColor(h.state)}>
                {h.state}
              </Badge>
            ) : (
              <Caption1>no id</Caption1>
            )}
            <Caption1>{h.path}</Caption1>
          </div>
        </Card>
      ))}
      {result?.note ? <Caption1 className={styles.note}>{result.note}</Caption1> : null}
    </section>
  );
}
