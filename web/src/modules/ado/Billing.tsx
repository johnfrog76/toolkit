import { useState, useCallback } from "react";
import {
  Accordion,
  AccordionItem,
  AccordionHeader,
  AccordionPanel,
  Badge,
  Button,
  Card,
  Select,
  Subtitle2,
  Caption1,
  makeStyles,
  tokens,
} from "@fluentui/react-components";
import { RefreshButton } from "../../shared/RefreshButton";
import { CopyRegular, CheckmarkRegular } from "@fluentui/react-icons";
import { CardSpinner } from "../../shared/CardSpinner";
import { HairlineDivider } from "../../shared/HairlineDivider";
import { useGetBillingQuery } from "./api.ado";
import ReactMarkdown from "react-markdown";
import { markdownPlugins } from "../../shared/markdownPlugins";
import { CalendarLtrRegular } from "@fluentui/react-icons";
import { EmptyState } from "../../shared/EmptyState";
import { billingNote } from "./billingNote";
import { copyText as copyToClipboard } from "../../shared/copyText";

const useStyles = makeStyles({
  card: {
    padding: tokens.spacingVerticalM,
    display: "flex",
    flexDirection: "column",
    gap: tokens.spacingVerticalS,
    backgroundColor: tokens.colorNeutralBackgroundAlpha,
    minHeight: "33vh",
  },
  headerRow: {
    display: "flex",
    alignItems: "center",
    justifyContent: "space-between",
    minHeight: "3rem",
    gap: tokens.spacingHorizontalM,
  },
  headerLeft: {
    display: "flex",
    alignItems: "baseline",
    flexWrap: "wrap",
    gap: tokens.spacingHorizontalS,
  },
  accordionItem: {
    border: `1px solid ${tokens.colorNeutralStroke2}`,
    borderRadius: tokens.borderRadiusMedium,
    marginBottom: tokens.spacingVerticalXS,
  },
  accordionHeader: {
    display: "flex",
    alignItems: "center",
    justifyContent: "space-between",
    width: "100%",
    paddingRight: tokens.spacingHorizontalM,
    boxSizing: "border-box",
  },
  dayBadge: {
    marginLeft: tokens.spacingHorizontalS,
  },
  panelContent: {
    padding: tokens.spacingVerticalS,
    "& ul": {
      listStyle: "none",
      paddingLeft: 0,
      margin: 0,
    },
    "& li": {
      padding: `${tokens.spacingVerticalXS} 0`,
      fontFamily: "monospace",
      fontSize: "13px",
      lineHeight: "1.5",
    },
  },
  copyBtn: {
    minWidth: "auto",
    flexShrink: 0,
  },
  copiedBtn: {
    minWidth: "auto",
    flexShrink: 0,
    color: tokens.colorPaletteGreenForeground1,
  },
  footerRow: {
    display: "flex",
    justifyContent: "space-between",
    alignItems: "center",
    flexWrap: "wrap",
    gap: tokens.spacingHorizontalM,
    paddingTop: tokens.spacingVerticalS,
    borderTop: `1px solid ${tokens.colorNeutralStroke2}`,
  },
  headerHint: { color: tokens.colorNeutralForeground3 },
  note: { color: tokens.colorNeutralForeground3, flex: "1 1 auto", minWidth: 0 },
  // Visually hidden, still in the accessibility tree: the live region.
  srOnly: {
    position: "absolute",
    width: "1px",
    height: "1px",
    padding: 0,
    margin: "-1px",
    overflow: "hidden",
    clip: "rect(0, 0, 0, 0)",
    whiteSpace: "nowrap" as const,
    border: 0,
  },
  compactContent: {
    padding: tokens.spacingVerticalS,
    fontFamily: "monospace",
    fontSize: "13px",
    lineHeight: "1.8",
    whiteSpace: "pre-wrap" as const,
  },
});

function dayToMarkdown(raw: string): string {
  // raw format: "5/5 Tuesday\n\t- Bug 123: title (status)\n\t- ..."
  const lines = raw.split("\n");
  // Skip the header line, convert items to markdown list
  return lines
    .slice(1)
    .map((l) => l.replace(/^\t/, ""))
    .join("\n");
}

export function Billing() {
  const styles = useStyles();
  const [week, setWeek] = useState("current");
  const [format, setFormat] = useState<"normal" | "compact">("normal");
  const { data, isLoading, isFetching, isError, refetch } = useGetBillingQuery(week);
  const [copiedKey, setCopiedKey] = useState<string | null>(null);
  // What a screen reader is told a copy did. The button's own label flips to
  // "Copied!" for two seconds, but a label change on the control you just
  // pressed is not announced; a polite live region is.
  const [announcement, setAnnouncement] = useState("");

  const copyText = useCallback(async (text: string, key: string, what: string) => {
    await copyToClipboard(text);
    setCopiedKey(key);
    setAnnouncement(`Copied ${what} to the clipboard.`);
    setTimeout(() => setCopiedKey((k) => (k === key ? null : k)), 2000);
  }, []);

  return (
    <Card className={styles.card} appearance="outline">
      <div className={styles.headerRow}>
        <div className={styles.headerLeft}>
          {/* The tab and the address are "Daily"; the page says what it holds. The subtitle
              carries the one rule true of every hub -- the cards' dates decide -- and the
              footer (billingNote) carries what is conditional on the week that was built. */}
          <Subtitle2 as="h1">Daily Activity</Subtitle2>
          <Caption1 className={styles.headerHint}>
            What you worked on, a day at a time, from the cards&apos; own dates. Copy a day into
            your timesheet.
          </Caption1>
        </div>
        <div style={{ display: "flex", alignItems: "center", gap: "8px" }}>
          <Select
            size="small"
            value={format}
            aria-label="How much of each line is copied"
            onChange={(_, d) => setFormat(d.value as "normal" | "compact")}
          >
            <option value="normal">Full lines</option>
            <option value="compact">Short lines</option>
          </Select>
          <Select
            size="small"
            value={week}
            aria-label="Which week"
            onChange={(_, d) => setWeek(d.value)}
          >
            <option value="current">This Week</option>
            <option value="last">Last Week</option>
          </Select>
          <RefreshButton
            onClick={refetch}
            isFetching={isFetching && !isLoading}
            disabled={isLoading || isFetching}
          />
        </div>
      </div>

      <HairlineDivider />

      {isLoading || isFetching ? (
        <CardSpinner label="Loading..." size="medium" />
      ) : isError ? (
        // Not "no activity": nothing was read. An empty week and a failed
        // request are different facts, and a timesheet is filled in from this.
        <EmptyState
          icon={<CalendarLtrRegular />}
          tone="error"
          title="Could not load this week"
          detail="The agent did not answer. Nothing was read."
          action={
            <Button size="small" onClick={() => refetch()}>
              Try again
            </Button>
          }
        />
      ) : data?.error ? (
        // The agent answered, and what it said is that the week could not be
        // built. Its sentence is the detail: it names what is missing.
        <EmptyState
          icon={<CalendarLtrRegular />}
          tone="error"
          title="This week could not be built"
          detail={data.error}
          action={
            <Button size="small" onClick={() => refetch()}>
              Try again
            </Button>
          }
        />
      ) : !data || data.days.length === 0 ? (
        <EmptyState
          icon={<CalendarLtrRegular />}
          title="Nothing recorded for this week"
          detail={["A day fills in as you work on cards. Try last week, above.", billingNote(data)]
            .filter(Boolean)
            .join(" ")}
        />
      ) : (
        <>
          <Accordion collapsible defaultOpenItems={["0"]}>
            {[...data.days].reverse().map((day, idx) => {
              const dayText = format === "compact" ? day.compact_raw : day.raw;
              return (
                <AccordionItem key={day.date} value={String(idx)} className={styles.accordionItem}>
                  {/* The copy button sits BESIDE the header, not in it: the header
                      is itself a <button>, and a button inside a button is
                      invalid HTML that a screen reader cannot reach. */}
                  <div className={styles.accordionHeader}>
                    <AccordionHeader style={{ flex: "1 1 auto", minWidth: 0 }}>
                      <span>
                        {day.day_name}
                        {/* A count, when there is one. A "0" badge on an empty
                            day read as a number to check rather than as
                            nothing; the panel already says the day is empty. */}
                        {day.items.length > 0 && (
                          <Badge
                            className={styles.dayBadge}
                            size="small"
                            appearance="filled"
                            color="informative"
                          >
                            {day.items.length}
                          </Badge>
                        )}
                      </span>
                    </AccordionHeader>
                    <Button
                      className={copiedKey === day.date ? styles.copiedBtn : styles.copyBtn}
                      size="small"
                      appearance="subtle"
                      icon={copiedKey === day.date ? <CheckmarkRegular /> : <CopyRegular />}
                      onClick={() => copyText(dayText, day.date, day.day_name)}
                    >
                      {copiedKey === day.date ? "Copied!" : "Copy Day"}
                    </Button>
                  </div>
                  <AccordionPanel>
                    <div
                      className={format === "compact" ? styles.compactContent : styles.panelContent}
                    >
                      {format === "compact" ? (
                        dayToMarkdown(dayText)
                      ) : (
                        <ReactMarkdown {...markdownPlugins}>{dayToMarkdown(dayText)}</ReactMarkdown>
                      )}
                    </div>
                  </AccordionPanel>
                </AccordionItem>
              );
            })}
          </Accordion>

          <div className={styles.footerRow}>
            {/* What the days were built from, and what is NOT on them and why. */}
            <Caption1 className={styles.note}>{billingNote(data)}</Caption1>
            <Button
              appearance="primary"
              size="small"
              icon={copiedKey === "all" ? <CheckmarkRegular /> : <CopyRegular />}
              onClick={() =>
                copyText(format === "compact" ? data.compact : data.raw, "all", "the whole week")
              }
            >
              {copiedKey === "all" ? "Copied!" : "Copy All"}
            </Button>
          </div>
          {/* Off screen, read aloud: the copy's outcome. One region for every
              copy on the page, so it never has to be found. */}
          <span className={styles.srOnly} role="status" aria-live="polite">
            {announcement}
          </span>
        </>
      )}
    </Card>
  );
}
