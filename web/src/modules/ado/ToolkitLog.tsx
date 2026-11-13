import { useState, useMemo } from "react";
import { DismissRegular, HistoryRegular } from "@fluentui/react-icons";
import { useUserRefetch } from "../../hooks/useUserRefetch";
import { ListPanel } from "../../shell/kinds/ListPanel";
import type { BadgeSpec, LineItemData } from "../../shell/CardItem";
import type { EmptyMessage } from "../../shared/EmptyState";
import { LOG_LATEST, useGetLogEntriesQuery, useRunCommandMutation } from "./api.ado";
import type { LogEntry } from "./api.ado";
import { logBadge } from "./logChart";
import { LogTypeChart } from "./LogTypeChart";
import { localToday, localDaysAgo } from "../../utility/dates";

function typeBadgeColor(type: string): BadgeSpec["color"] {
  if (type === "ERR") return "danger";
  if (type === "WARN") return "warning";
  if (type === "INFO") return "informative";
  return "success"; // CMD
}

/** A log entry, as a line item: the time, the type, then who said what. */
function toItem(entry: LogEntry): LineItemData {
  const time = entry.timestamp.length >= 19 ? entry.timestamp.slice(11, 19) : entry.timestamp;
  return {
    title: entry.source,
    description: entry.detail,
    meta: [{ text: time, mono: true }],
    badges: [{ label: entry.type, appearance: "outline", color: typeBadgeColor(entry.type) }],
  };
}

const TYPE_OPTIONS = ["All", "CMD", "ERR", "WARN", "INFO"];
const DAYS_OPTIONS = [
  { label: "All time", value: 0 },
  { label: "Today", value: 1 },
  { label: "7 days", value: 7 },
  { label: "30 days", value: 30 },
];

export function ToolkitLog() {
  const { data, isLoading, isFetching, error, refetch } = useGetLogEntriesQuery();
  const [runCommand] = useRunCommandMutation();

  const [typeFilter, setTypeFilter] = useState("All");
  const [daysFilter, setDaysFilter] = useState(7);
  const [sourceSearch, setSourceSearch] = useState("");
  const [acking, setAcking] = useState(false);

  const [userRefetching, handleRefetch] = useUserRefetch(isFetching, refetch);

  // The log's timestamps are local; so is its "today" (never the UTC date).
  const today = localToday();

  const filtered = useMemo(() => {
    let entries = data?.entries ?? [];
    if (typeFilter !== "All") entries = entries.filter((e) => e.type === typeFilter);
    if (daysFilter === 1) {
      entries = entries.filter((e) => e.timestamp.startsWith(today));
    } else if (daysFilter > 1) {
      const cutoffStr = localDaysAgo(daysFilter);
      entries = entries.filter((e) => e.timestamp.slice(0, 10) >= cutoffStr);
    }
    if (sourceSearch.trim()) {
      const q = sourceSearch.trim().toLowerCase();
      entries = entries.filter(
        (e) => e.source.toLowerCase().includes(q) || e.detail.toLowerCase().includes(q),
      );
    }
    return entries;
  }, [data, typeFilter, daysFilter, sourceSearch, today]);

  const handleAck = async () => {
    setAcking(true);
    try {
      await runCommand({ name: "Log", params: ["-Ack"] });
      refetch();
    } finally {
      setAcking(false);
    }
  };

  const icon = <HistoryRegular />;
  const served = data?.entries.length ?? 0;
  const empty: EmptyMessage = error
    ? {
        icon,
        tone: "error",
        title: "Could not load the log",
        detail: "The agent did not answer. Nothing was read.",
      }
    : {
        icon,
        title: "Nothing logged yet",
        detail: "Every command you run, from the terminal or from this page, leaves a line here.",
      };

  return (
    <ListPanel
      title="Log"
      density="line"
      items={error ? [] : filtered}
      item={toItem}
      empty={empty}
      filteredEmpty={
        !error && served > 0
          ? {
              icon,
              tone: "filtered",
              title: "No entries match the filters",
              detail: `${served} hidden by the filters.`,
            }
          : undefined
      }
      loading={isLoading ? { label: "Loading log..." } : undefined}
      lead={
        !error && filtered.length > 0
          ? {
              chart: {
                label: "Log entries by day and type",
                chart: <LogTypeChart entries={filtered} />,
              },
            }
          : undefined
      }
      pickers={[
        {
          label: "Entry type",
          value: typeFilter,
          options: TYPE_OPTIONS.map((t) => ({ value: t, label: t })),
          onChange: setTypeFilter,
        },
        {
          label: "Period",
          value: String(daysFilter),
          options: DAYS_OPTIONS.map((o) => ({ value: String(o.value), label: o.label })),
          onChange: (v) => setDaysFilter(Number(v)),
        },
      ]}
      search={{
        label: "Search the log",
        placeholder: "source or detail…",
        value: sourceSearch,
        onChange: setSourceSearch,
      }}
      action={{
        label: "Dismiss Errors",
        glyph: <DismissRegular />,
        title: "Acknowledge errors (Log -Ack)",
        disabled: acking || !data,
        onClick: () => void handleAck(),
      }}
      refresh={{ onClick: handleRefetch, isFetching: userRefetching, disabled: isLoading }}
      count={data ? logBadge(filtered.length, data.entries.length, LOG_LATEST) : 0}
    />
  );
}
