import { useState } from "react";
import { useNavigate } from "react-router";
import {
  Badge,
  Body1,
  Caption1,
  Card,
  Link,
  Subtitle2,
  makeStyles,
  tokens,
} from "@fluentui/react-components";
import {
  CopyRegular,
  DocumentTextRegular,
  OpenRegular,
  SparkleRegular,
} from "@fluentui/react-icons";
import { CardActions } from "../../shared/CardActions";
import type { CardAction } from "../../shared/CardActions";
import { CardSpinner } from "../../shared/CardSpinner";
import { copyText } from "../../shared/copyText";
import { EmptyState } from "../../shared/EmptyState";
import { FilterBadge } from "../../shared/FilterBadge";
import { InfoTip } from "../../shared/InfoTip";
import { useFilterRowStyles } from "../../shared/listRowStyles";
import { PageCard } from "../../shared/PageCard";
import { RefreshButton } from "../../shared/RefreshButton";
import { StatusMessage } from "../../shared/StatusMessage";
import { useGetEnvQuery } from "../../shell/api";
import { usePagination } from "../../hooks/usePagination";
import { Pagination } from "../../shared/Pagination";
import { useGetPromptsQuery } from "./api.studio";
import type { PromptRow, PromptSpace } from "./api.studio";
import { STUDIO_PAGE_SIZE, promptPath } from "./paths";
import {
  categoryTabs,
  othersLine,
  ownerLabel,
  promptSets,
  spaceWorkflow,
  workflowLabel,
} from "./prompts";
import type { PromptSets } from "./prompts";

// The Prompts card: the agentic prompts ToolKit ships, the ones your hub adds,
// and the active Space's own -- beside Hub Designs because the first two are
// the same on every Space. The house filter row, the FilterBadge radios the
// Spaces card and the Dashboard use: ToolKit (the Space's set, by how you work
// there, prompts.ts), Your hub, and the Space's name -- the third only when
// the Space is not this package itself, which the agent says (`space.isToolkit`)
// and the card never works out. Each badge carries its count, the header chip
// is the shown rows', the pager runs over them, and each filter has its own
// empty state. What the card does is the info tip in its header.
//
// Under it, the category row: All, then each category with at least one prompt
// in the active source -- the index's vocabulary in its order (the agent serves
// it), any other after -- each with its count. The rows compose (source AND
// category), the chip is the shown count and the pager runs over the result.
// A choice the active source has no prompt in reads as All, the way a stale
// choice of the Space's filter reads as ToolKit. Past CATEGORY_TABS_MAX
// categories the row is meant to become a dropdown (prompts.ts); not yet.
//
// ONE record on every row, wherever the prompt lives: its title, its purpose,
// whose it is and its category -- the agent's four fields -- and nothing else.
// The index's other fields (the ways of working, who sends it, the add-on, what
// it drives) and where it lives and when it changed are the reading room's.
//
// The house row: the title opens the reading room, the ONE exposed action is
// Copy reference (the @ form of the file's path, for a chat that can read the
// disk), the menu holds Copy prompt (the body, for a chat that cannot), the
// reading room and the prompt's history on GitHub, the external link last.
const useStyles = makeStyles({
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
  name: { flex: 1, minWidth: 0, textAlign: "start" },
  metaRow: {
    display: "flex",
    gap: tokens.spacingHorizontalM,
    flexWrap: "wrap" as const,
    marginTop: tokens.spacingVerticalXS,
    alignItems: "center",
  },
  tip: { display: "flex", flexDirection: "column", gap: tokens.spacingVerticalXS },
});

/** The three filters, in the row's order; the agent's group names. */
export type PromptFilter = "toolkit" | "yours" | "space";

/** Whether the Space has a filter of its own: it names a repository, and that
 *  repository is not this package -- the agent's answer, read and not derived. */
export function hasSpaceFilter(space: PromptSpace | undefined): space is PromptSpace {
  return !!space && !!space.repo && !space.isToolkit;
}

// What Copy reference puts on the clipboard, built at use and never stored: a
// ToolKit prompt is relative to the checkout the chat is open in, the Space's
// relative to a checkout of its repository, one of the hub's (never inside
// either tree) is its absolute path.
export function promptReference(row: PromptRow): string {
  return `@${row.group === "yours" ? row.file_path : row.path}`;
}

type Copied = { name: string; what: "reference" | "prompt" };

function PromptCardRow({
  row,
  space,
  onCopied,
}: {
  row: PromptRow;
  space: PromptSpace | undefined;
  onCopied: (c: Copied) => void;
}) {
  const styles = useStyles();
  const navigate = useNavigate();
  const open = () => navigate(promptPath(row.ref));
  const secondary: CardAction[] = [
    {
      icon: <CopyRegular />,
      label: "Copy prompt",
      onClick: () => {
        void copyText(row.body).then(() => onCopied({ name: row.name, what: "prompt" }));
      },
    },
    { icon: <DocumentTextRegular />, label: "Open the prompt", onClick: open },
  ];
  if (row.history) {
    secondary.push({
      icon: <OpenRegular />,
      label: "Its history on GitHub",
      href: row.history,
      dividerBefore: true,
    });
  }
  return (
    <Card className={styles.row} size="small" appearance="outline">
      <div className={styles.rowHeader}>
        <Link as="button" appearance="subtle" className={styles.name} onClick={open}>
          <Body1>
            <strong>{row.title || row.name}</strong>
          </Body1>
        </Link>
        <CardActions
          primaryAction={{
            icon: <CopyRegular />,
            label: "Copy reference",
            onClick: () => {
              void copyText(promptReference(row)).then(() =>
                onCopied({ name: row.name, what: "reference" }),
              );
            },
          }}
          menuLabel={`Actions for ${row.name}`}
          secondaryActions={secondary}
        />
      </div>
      {row.purpose ? <Caption1>{row.purpose}</Caption1> : null}
      <div className={styles.metaRow}>
        <Badge
          appearance="tint"
          size="small"
          color={row.group === "toolkit" ? "brand" : "informative"}
        >
          {ownerLabel(row, space)}
        </Badge>
        <Badge appearance="outline" size="small" color="subtle">
          {row.category}
        </Badge>
      </div>
    </Card>
  );
}

/** What the card does, for its info tip: read from the same sets the list is. */
function CardTip({
  sets,
  workflow,
  space,
}: {
  sets: PromptSets;
  workflow: ReturnType<typeof spaceWorkflow>;
  space: PromptSpace | undefined;
}) {
  const styles = useStyles();
  const others = othersLine(sets);
  return (
    <div className={styles.tip}>
      <span>
        ToolKit&apos;s are what the product tells a model: the {sets.toolkit.length} for working{" "}
        {workflowLabel(workflow)} here.
      </span>
      {others ? <span>{others}</span> : null}
      <span>Your hub&apos;s are yours, on every machine.</span>
      {hasSpaceFilter(space) ? (
        <span>
          {space.name}&apos;s are its repository&apos;s own: agentic/ in {space.repo}.
        </span>
      ) : null}
      <span>The row under them narrows any of these to one category.</span>
    </div>
  );
}

export function PromptsCard() {
  const filterStyles = useFilterRowStyles();
  const { data, isLoading, isFetching, error, refetch } = useGetPromptsQuery();
  const { data: env } = useGetEnvQuery();
  const [copied, setCopied] = useState<Copied | null>(null);
  const [chosen, setChosen] = useState<PromptFilter>("toolkit");
  // null is All: a category is free text, so no word can stand for it.
  const [chosenCategory, setChosenCategory] = useState<string | null>(null);
  const workflow = spaceWorkflow(env);
  const sets = promptSets(data?.prompts ?? [], workflow);
  const space = data?.space;
  const withSpace = hasSpaceFilter(space);
  // Switching Space changes the filter with it: a Space with no filter of its
  // own reads a stale choice of the third as the first.
  const filter: PromptFilter = chosen === "space" && !withSpace ? "toolkit" : chosen;
  const inSource = sets[filter];
  const tabs = categoryTabs(inSource, data?.categories ?? []);
  const category =
    chosenCategory !== null && tabs.some((t) => t.category === chosenCategory)
      ? chosenCategory
      : null;
  const listed = category === null ? inSource : inSource.filter((r) => r.category === category);
  const { page, totalPages, pageItems, setPage } = usePagination(listed, STUDIO_PAGE_SIZE);
  const choose = (f: PromptFilter) => {
    setChosen(f);
    setPage(0);
  };
  const chooseCategory = (c: string | null) => {
    setChosenCategory(c);
    setPage(0);
  };

  const icon = <SparkleRegular />;
  const empty =
    isLoading || isFetching ? undefined : error ? (
      <EmptyState
        icon={icon}
        tone="error"
        title="Could not read the prompts"
        detail="The agent did not answer. Nothing was read."
      />
    ) : undefined;

  const filters: { value: PromptFilter; label: string; count: number }[] = [
    { value: "toolkit", label: "ToolKit", count: sets.toolkit.length },
    { value: "yours", label: "Your hub", count: sets.yours.length },
  ];
  if (withSpace) filters.push({ value: "space", label: space.name, count: sets.space.length });

  // Each filter's own empty state, in the body's place under the row.
  const filteredEmpty =
    inSource.length > 0 ? null : filter === "toolkit" ? (
      <EmptyState
        icon={icon}
        title={`None for working ${workflowLabel(workflow)}`}
        detail={othersLine(sets) ?? undefined}
      />
    ) : filter === "yours" ? (
      <EmptyState
        icon={icon}
        title="None yet"
        detail="A <name>.prompt.md in your hub's agentic/ folder is listed here."
      />
    ) : (
      <EmptyState
        icon={icon}
        title={`None in ${withSpace ? space.repo : "this Space"}`}
        detail="A <name>.prompt.md in an agentic/ folder in that repository is listed here."
      />
    );

  return (
    <PageCard
      scrollable
      empty={empty}
      headerLeft={
        <>
          {icon}
          <Subtitle2>Prompts</Subtitle2>
          <InfoTip
            label="About the Prompts card"
            content={<CardTip sets={sets} workflow={workflow} space={space} />}
          />
        </>
      }
      headerRight={
        <>
          <RefreshButton
            onClick={refetch}
            isFetching={isFetching && !isLoading}
            disabled={isLoading}
          />
          <Badge
            color="informative"
            appearance="filled"
            size="large"
            aria-label={`${listed.length} prompts`}
          >
            {listed.length}
          </Badge>
        </>
      }
      footerCenter={
        totalPages > 1 ? (
          <Pagination page={page} totalPages={totalPages} onPageChange={setPage} />
        ) : undefined
      }
    >
      {copied ? (
        <StatusMessage status="success" onDismiss={() => setCopied(null)}>
          {copied.what === "reference"
            ? `Copied the reference to ${copied.name}. Paste it into your assistant's chat.`
            : `Copied ${copied.name}. Paste it into a chat that cannot read your files.`}
        </StatusMessage>
      ) : null}
      {isLoading || isFetching ? (
        <CardSpinner label="Reading the prompts..." />
      ) : (
        <>
          <div className={filterStyles.chips} role="group" aria-label="Filter prompts">
            {filters.map((f) => (
              <FilterBadge
                key={f.value}
                label={f.label}
                // A zero draws no number, as the Spaces card's chips do: the
                // filter's empty state says it.
                count={f.count > 0 ? f.count : undefined}
                active={filter === f.value}
                onClick={() => choose(f.value)}
              />
            ))}
          </div>
          <div className={filterStyles.chips} role="group" aria-label="Filter by category">
            <FilterBadge
              label="All"
              count={inSource.length > 0 ? inSource.length : undefined}
              active={category === null}
              onClick={() => chooseCategory(null)}
            />
            {tabs.map((t) => (
              <FilterBadge
                key={t.category}
                label={t.category}
                count={t.count}
                active={category === t.category}
                onClick={() => chooseCategory(t.category)}
              />
            ))}
          </div>
          {filteredEmpty}
          {pageItems.map((row) => (
            <PromptCardRow key={row.ref} row={row} space={space} onCopied={setCopied} />
          ))}
        </>
      )}
    </PageCard>
  );
}
