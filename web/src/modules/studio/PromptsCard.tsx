import { useState } from "react";
import { useNavigate } from "react-router";
import { makeStyles, tokens } from "@fluentui/react-components";
import { SparkleRegular } from "@fluentui/react-icons";
import { ROW } from "../../shared/CardActions";
import type { CardAction } from "../../shared/CardActions";
import { copyText } from "../../shared/copyText";
import type { EmptyMessage } from "../../shared/EmptyState";
import { useGetEnvQuery } from "../../shell/api";
import { ListPanel } from "../../shell/kinds/ListPanel";
import type { FilterRow, PanelStatus } from "../../shell/kinds/ListPanel";
import type { CardItemData } from "../../shell/CardItem";
import { useGetPromptsQuery, useLazyGetPromptQuery } from "./api.studio";
import type { PromptListRow, PromptSpace } from "./api.studio";
import { promptPath } from "./paths";
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
// The card item: the title is text, the ONE exposed action opens the reading
// room, the menu holds Copy reference (the @ form of the file's path, for a
// chat that can read the disk), Copy prompt (the body, for a chat that cannot)
// and the prompt's history on GitHub, the external link last.
const useStyles = makeStyles({
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
export function promptReference(row: PromptListRow): string {
  return `@${row.group === "yours" ? row.file_path : row.path}`;
}

type Copied = { name: string; what: "reference" | "prompt" | "failed" };

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
  const navigate = useNavigate();
  const [readPrompt] = useLazyGetPromptQuery();
  const { data, isLoading, isFetching, error, refetch } = useGetPromptsQuery();
  const { data: env } = useGetEnvQuery();
  const [copied, setCopied] = useState<Copied | null>(null);
  // The prompt whose text is being read for Copy prompt, null when none is.
  const [reading, setReading] = useState<string | null>(null);
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

  const icon = <SparkleRegular />;
  // Each filter's own empty state, under the chip rows.
  const empty: EmptyMessage = error
    ? {
        icon,
        tone: "error",
        title: "Could not read the prompts",
        detail: "The agent did not answer. Nothing was read.",
      }
    : filter === "toolkit"
      ? {
          icon,
          title: `None for working ${workflowLabel(workflow)}`,
          detail: othersLine(sets) ?? undefined,
        }
      : filter === "yours"
        ? {
            icon,
            title: "None yet",
            detail: "A <name>.prompt.md in your hub's agentic/ folder is listed here.",
          }
        : {
            icon,
            title: `None in ${withSpace ? space.repo : "this Space"}`,
            detail: "A <name>.prompt.md in an agentic/ folder in that repository is listed here.",
          };

  const sources: { value: PromptFilter; label: string; count: number }[] = [
    { value: "toolkit", label: "ToolKit", count: sets.toolkit.length },
    { value: "yours", label: "Your hub", count: sets.yours.length },
  ];
  if (withSpace) sources.push({ value: "space", label: space.name, count: sets.space.length });
  const filters: FilterRow[] = [
    {
      label: "Filter prompts",
      // A zero draws no number, as the Spaces panel's chips do: the filter's
      // empty state says it.
      chips: sources.map((f) => ({
        id: f.value,
        label: f.label,
        count: f.count > 0 ? f.count : undefined,
        active: filter === f.value,
        onSelect: () => setChosen(f.value),
      })),
    },
    {
      label: "Filter by category",
      chips: [
        {
          id: "",
          label: "All",
          count: inSource.length > 0 ? inSource.length : undefined,
          active: category === null,
          onSelect: () => setChosenCategory(null),
        },
        ...tabs.map((t) => ({
          id: `category:${t.category}`,
          label: t.category,
          count: t.count,
          active: category === t.category,
          onSelect: () => setChosenCategory(t.category),
        })),
      ],
    },
  ];

  const status: PanelStatus | undefined = reading
    ? { tone: "busy", text: `Reading ${reading}...` }
    : copied
      ? {
          tone: copied.what === "failed" ? "error" : "success",
          text:
            copied.what === "reference"
              ? `Copied the reference to ${copied.name}. Paste it into your assistant's chat.`
              : copied.what === "failed"
                ? `Could not read ${copied.name}, so nothing was copied. Try again.`
                : `Copied ${copied.name}. Paste it into a chat that cannot read your files.`,
          onDismiss: () => setCopied(null),
        }
      : undefined;

  const toItem = (row: PromptListRow): CardItemData => {
    const menu: CardAction[] = [
      ROW.copy.action({
        detail: "reference",
        onClick: () => {
          void copyText(promptReference(row)).then(() =>
            setCopied({ name: row.name, what: "reference" }),
          );
        },
      }),
      ROW.copy.action({
        detail: "prompt",
        // The list carries no text: the body is read now, by the one-prompt
        // route, and copied when it arrives.
        onClick: () => {
          setReading(row.name);
          readPrompt(row.ref, true)
            .unwrap()
            .then((one) => copyText(one.body))
            .then(() => setCopied({ name: row.name, what: "prompt" }))
            .catch(() => setCopied({ name: row.name, what: "failed" }))
            .finally(() => setReading(null));
        },
      }),
    ];
    // Its history: the folder's log on GitHub, the external link, last.
    if (row.history) menu.push(ROW.external.action({ detail: "GitHub", href: row.history }));
    return {
      id: row.ref,
      title: row.title || row.name,
      name: row.name,
      description: row.purpose || undefined,
      meta: [
        {
          badge: {
            label: ownerLabel(row, space),
            color: row.group === "toolkit" ? "brand" : "informative",
          },
        },
        { badge: { label: row.category, color: "subtle" } },
        { text: row.path.split("/").pop() ?? "", shrink: true },
      ],
      primary: ROW.open.action({
        detail: "the prompt",
        onClick: () => navigate(promptPath(row.ref)),
      }),
      menu,
    };
  };

  return (
    <ListPanel
      title="Prompts"
      icon={icon}
      info={<CardTip sets={sets} workflow={workflow} space={space} />}
      infoLabel="About the Prompts card"
      items={error ? [] : listed}
      item={toItem}
      empty={empty}
      filters={error ? undefined : filters}
      loading={isLoading || isFetching ? { label: "Reading the prompts..." } : undefined}
      refresh={{ onClick: refetch, isFetching: isFetching && !isLoading, disabled: isLoading }}
      count={listed.length}
      countLabel={`${listed.length} prompts`}
      status={status}
    />
  );
}
