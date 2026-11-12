import { useState } from "react";
import { useNavigate } from "react-router";
import {
  Button,
  Caption1,
  Dialog,
  DialogActions,
  DialogBody,
  DialogContent,
  DialogSurface,
  DialogTitle,
  DialogTrigger,
  Dropdown,
  Field,
  Input,
  Option,
  makeStyles,
  tokens,
} from "@fluentui/react-components";
import { CommentRegular, DocumentSearchRegular, NotebookRegular } from "@fluentui/react-icons";
import { ROW } from "../../shared/CardActions";
import type { CardAction } from "../../shared/CardActions";
import { DialogDismiss } from "../../shared/DialogDismiss";
import type { EmptyMessage } from "../../shared/EmptyState";
import { HubSyncLine } from "../ado/HubSyncLine";
import { useGetEnvQuery } from "../../shell/api";
import { ListPanel } from "../../shell/kinds/ListPanel";
import type { FilterRow } from "../../shell/kinds/ListPanel";
import type { CardItemData, MetaItem } from "../../shell/CardItem";
import { buildNewDesignParams, commandResultMessage } from "../ado/cliBridge";
import {
  ALL_OUTCOMES,
  LearnMoreLink,
  NO_OUTCOME,
  NotShownLine,
  archivedByOutcome,
  groupByState,
  stateColor,
} from "../ado/DesignGroups";
import { DESIGN } from "../../shell/consts";
import { boundCardPath } from "../ado/DesignBindings";
import { DesignSearchInside } from "../ado/DesignSearchInside";
import { ALL, designMatches } from "../ado/docFilters";
import { roomFor } from "../ado/docRooms";
import { useSharedPersistedValue } from "../../shared/usePersistedState";
import type { Design } from "../ado/api.ado";
import {
  useGetDesignNotesQuery,
  useLazySearchHubDesignsQuery,
  useRunNewDesignMutation,
} from "./api.studio";
import { MoveDesignDialog } from "./MoveDesignDialog";
import { ROADS, roadsFor } from "../ado/designRoads";
import type { MoveRoad } from "../ado/designRoads";
import { notePath } from "./paths";
import { SPACE_MOVES } from "./spaceMoves";
import { useEnterSpace } from "./useEnterSpace";

// The seed drawer (Studio S2b, D-S3): the hub's designs -- the ones that belong
// to no product yet. Since the design lifecycle's reader (L2, D-DL12) the
// hub keeps the same four folders a product does, and the drawer draws the same
// states the Design tab draws, but as the Prompts card filters: one chip per
// state (Design, Spec, Complete, Archived, in road order) with its count, the
// first present one chosen when it opens, and the Archived chip adding a row of
// outcome chips. Each design is a card item: the title is text, the one
// exposed action opens the reading room, the menu holds the rest -- the spec,
// the Space it names, its roads, its docs, the cards worked against it and the
// thread. The +
// writes a note through NewDesign (the bridge), so the file is the record from
// its first minute.
const useStyles = makeStyles({
  fields: { display: "flex", flexDirection: "column", rowGap: tokens.spacingVerticalM },
});

const NO_SPACE = "";
/** The drawer's search, remembered per browser (not a Space's: a switch keeps it). */
export const HUB_DESIGN_TEXT_KEY = "studio.design.text";

export function DesignsCard() {
  const styles = useStyles();
  const navigate = useNavigate();
  const { data, isLoading, isFetching, error, refetch } = useGetDesignNotesQuery();
  const { data: env } = useGetEnvQuery();
  const [runNewDesign, { isLoading: adding }] = useRunNewDesignMutation();
  const [open, setOpen] = useState(false);
  const [title, setTitle] = useState("");
  const [description, setDescription] = useState("");
  const [space, setSpace] = useState(NO_SPACE);
  const [message, setMessage] = useState<string | null>(null);
  const [outcome, setOutcome] = useState<string | null>(null);
  // One move at a time: the row's road and its design, until the dialog closes.
  const [move, setMove] = useState<{ design: Design; road: MoveRoad } | null>(null);
  // The box over the drawer (L2b): the same rule as the Design tab's -- title,
  // description and id, every word, any order -- remembered per browser and
  // not cleared by a Space switch, because the hub is the engineer's, not a
  // Space's. Search inside runs the words over the files on disk, on the button.
  const search = useSharedPersistedValue(HUB_DESIGN_TEXT_KEY, "");
  const searching = search.value.trim().length > 0;
  const [searchInside, inside] = useLazySearchHubDesignsQuery();
  const [asked, setAsked] = useState<string | null>(null);
  const runSearch = () => {
    const q = search.value.trim();
    setAsked(q);
    void searchInside(q);
  };

  const spaces = env?.config?.spaces ?? [];
  const activeSpace = env?.config?.activeSpace ?? "";
  const spaceName = (slug: string) => spaces.find((s) => s.slug === slug)?.name || slug;
  // The groups (L2). An older agent answers no groups: its live notes are
  // then drawn as plain Designs, so nothing a person wrote goes missing.
  const designs: Design[] =
    data?.designs ??
    (data?.items ?? []).map((n) => ({
      id: n.name,
      short: "",
      state: "Design",
      title: n.title,
      description: n.description,
      thread: n.thread,
      thread_number: n.thread_number,
      thread_repo: n.thread_repo,
      closed: "",
      outcome: "",
      mismatch: "",
      docs: "",
      note: {
        folder: data?.folder || "design",
        name: n.name,
        path: n.name,
        title: n.title,
        description: n.description,
        thread: n.thread,
        thread_number: n.thread_number,
        thread_repo: n.thread_repo,
        url: "",
      },
      spec: null,
      space: n.space,
      thread_space: n.thread_space,
    }));
  const notShown = data?.notShown ?? [];
  const shown = designs.filter((d) => designMatches(d, search.value, ALL));
  const folder = data?.folder || "design";
  // The chips are the states the search leaves, in road order. The chosen one
  // is the person's pick while it still has designs, else the first present.
  const groups = groupByState(shown);
  const [picked, setPicked] = useState<string | null>(null);
  const [outcomeFilter, setOutcomeFilter] = useState(ALL_OUTCOMES);
  const current = groups.find((g) => g.state === picked)?.state ?? groups[0]?.state ?? "";
  const archived = current === DESIGN.states[3];
  const inState = groups.find((g) => g.state === current)?.designs ?? [];
  const ordered = archived ? archivedByOutcome(inState, outcomeFilter) : inState;
  // The Space a note names is a switch into it: the foyer item's move.
  const { enter, switching, failed } = useEnterSpace(activeSpace);

  const reset = () => {
    setTitle("");
    setDescription("");
    setSpace(NO_SPACE);
    setMessage(null);
  };

  const create = async () => {
    setMessage(null);
    try {
      const result = await runNewDesign({
        params: buildNewDesignParams({ title, description, space }),
      }).unwrap();
      if (result.status === "success") {
        setOpen(false);
        reset();
        setOutcome(commandResultMessage(result, "Created."));
        return;
      }
      // A refusal is the dialog's message, in the verb's own words.
      setMessage(commandResultMessage(result, "Created."));
    } catch {
      setMessage("Could not reach the agent. Nothing was written.");
    }
  };

  // A notebook, not a tracker's mark or an issue's glyph: these are the hub's
  // own files. The header and the empty state draw the same one.
  const icon = <NotebookRegular />;
  const empty: EmptyMessage = error
    ? {
        icon,
        tone: "error",
        title: "Could not read the notes",
        detail: "The agent did not answer. Nothing was read.",
      }
    : data?.exists === false
      ? // A hub copied out before the Studio was core has no design/ folder.
        // That is not a fault: the first note makes it.
        {
          icon,
          title: `No ${folder}/ folder yet`,
          detail: `This hub has no ${folder}/ folder yet. Your private notes live there until they belong to a product; the + writes the first one and makes the folder.`,
          action: <LearnMoreLink />,
        }
      : {
          icon,
          title: "No design notes yet",
          detail: `Your private notes live in the hub's ${folder}/ until they belong to a product. The + writes one.`,
        };
  const filteredEmpty: EmptyMessage | undefined =
    error || designs.length === 0
      ? undefined
      : shown.length === 0
        ? { icon, tone: "filtered", title: "No design matches the search" }
        : { icon, tone: "filtered", title: "No archived design with that outcome" };

  const filters: FilterRow[] = [];
  if (groups.length > 0) {
    filters.push({
      label: "Filter designs",
      chips: groups.map((g) => ({
        id: g.state,
        label: g.state,
        count: g.designs.length,
        active: current === g.state,
        onSelect: () => setPicked(g.state),
      })),
    });
  }
  if (archived) {
    // A second press on an outcome goes back to any.
    const toggle = (o: string) => setOutcomeFilter(outcomeFilter === o ? ALL_OUTCOMES : o);
    filters.push({
      label: "Filter archived by outcome",
      tone: "pink",
      chips: [
        {
          id: "outcome:any",
          label: "any outcome",
          active: outcomeFilter === ALL_OUTCOMES,
          onSelect: () => setOutcomeFilter(ALL_OUTCOMES),
        },
        ...DESIGN.outcomes.map((o) => ({
          id: `outcome:${o}`,
          label: o,
          active: outcomeFilter === o,
          onSelect: () => toggle(o),
        })),
        {
          id: "outcome:none",
          label: "nothing said",
          active: outcomeFilter === NO_OUTCOME,
          onSelect: () => toggle(NO_OUTCOME),
        },
      ],
    });
  }

  const toItem = (design: Design): CardItemData => {
    // The document the item opens: the note (the design IS the note), else the spec.
    const main = (design.note ?? design.spec)?.path ?? null;
    const space = design.space ? spaceName(design.space) : "";
    const menu: CardAction[] = [];
    if (design.note && design.spec) {
      menu.push(
        ROW.open.action({
          detail: "the spec",
          onClick: () => navigate(notePath(design.spec!.path)),
        }),
      );
    }
    // The Space a note names is a switch into it: a move in the menu.
    if (design.space) {
      menu.push(
        SPACE_MOVES.enter.action({
          detail: space,
          onClick: () => enter(design.space),
          disabled: switching,
        }),
      );
    }
    // Where a Complete design's durable part landed, when this Space's
    // repository holds it and the app has a room for it.
    const docsRoom =
      design.docs && !!design.space && design.space === activeSpace ? roomFor(design.docs) : null;
    if (docsRoom) {
      menu.push(ROW.open.action({ detail: "its docs", onClick: () => navigate(docsRoom) }));
    }
    // The cards worked against it that can be opened here.
    for (const c of design.cards ?? []) {
      const to = boundCardPath(c, activeSpace);
      if (to) {
        menu.push(
          ROW.open.action({ detail: `card ${c.id ?? c.file}`, onClick: () => navigate(to) }),
        );
      }
    }
    // The moves a hub design offers: by what it has and where it is.
    roadsFor(design).forEach((road, i) => {
      menu.push(
        ROADS[road].move.action({
          detail: ROADS[road].detail,
          onClick: () => setMove({ design, road }),
          dividerBefore: i === 0 && menu.length > 0,
        }),
      );
    });
    // The thread lives on GitHub: the external link, last.
    if (design.thread) menu.push(ROW.external.action({ detail: "GitHub", href: design.thread }));

    const meta: MetaItem[] = [
      { badge: { label: design.state, color: stateColor(design.state) } },
      { text: design.short, title: design.id },
    ];
    if (main) meta.push({ text: main.split("/").pop() ?? "", shrink: true });
    if (design.thread_number) {
      meta.push({
        badge: {
          label: `#${design.thread_number}`,
          appearance: "outline",
          color: "informative",
          glyph: <CommentRegular />,
        },
      });
    } else if (design.note && !design.note.archived) {
      meta.push({ text: "no thread yet" });
    }
    if (design.closed) {
      meta.push({ text: `Closed ${design.closed}`, title: "The day it entered the archive" });
    }
    if (design.outcome) {
      meta.push({
        badge: {
          label: design.outcome,
          appearance: "outline",
          color: design.outcome === "dropped" ? "warning" : "success",
        },
      });
    }
    if (design.docs) {
      meta.push({ text: `Docs: ${design.docs}`, title: "Where its durable part landed" });
    }
    if (design.mismatch) meta.push({ text: design.mismatch, tone: "warning" });
    if (design.space && failed === design.space) {
      meta.push({ text: `Could not switch to ${space}. Nothing changed.`, tone: "alert" });
    }
    const cards = design.cards ?? [];
    if (cards.length > 0) {
      meta.push({
        text: cards.length === 1 ? "1 card" : `${cards.length} cards`,
        title: cards.map((c) => `${c.id ?? c.file} ${c.status}`).join(", "),
      });
    }
    return {
      id: design.id,
      title: design.title,
      badges: design.space
        ? [{ label: space, appearance: "outline", shape: "circular", color: "informative" }]
        : undefined,
      description: design.description || undefined,
      meta,
      // A design with neither a note nor a spec has nothing to read: Open says so.
      primary: ROW.open.action({
        detail: design.note ? "the note" : "the spec",
        onClick: main ? () => navigate(notePath(main)) : undefined,
        disabled: !main,
      }),
      menu,
    };
  };

  return (
    <>
      <ListPanel
        title="Hub Designs"
        icon={icon}
        info="Your private files. Notes that belong to no product yet."
        infoLabel="About Hub Designs"
        items={error ? [] : ordered}
        item={toItem}
        empty={empty}
        filteredEmpty={filteredEmpty}
        loading={
          isLoading || isFetching ? { label: "Reading the hub's design notes..." } : undefined
        }
        filters={filters.length > 0 ? filters : undefined}
        search={{
          label: "Search the hub's designs",
          placeholder: "Search designs",
          value: search.value,
          onChange: search.setValue,
          results:
            asked !== null ? (
              <DesignSearchInside
                result={inside.data}
                loading={inside.isFetching}
                failed={!!inside.error}
                onOpen={(h) => navigate(notePath(h.path))}
                onClear={() => setAsked(null)}
              />
            ) : undefined,
        }}
        // Search inside runs the words over the files on disk: offered once
        // the box has words.
        action={
          searching
            ? {
                label: inside.isFetching ? "Searching inside…" : "Search inside",
                glyph: <DocumentSearchRegular />,
                onClick: runSearch,
                disabled: inside.isFetching,
              }
            : undefined
        }
        refresh={{ onClick: refetch, isFetching: isFetching && !isLoading, disabled: isLoading }}
        count={shown.length}
        status={
          outcome
            ? { tone: "success", text: outcome, onDismiss: () => setOutcome(null) }
            : undefined
        }
        create={{ label: "New Design Note", onClick: () => setOpen(true) }}
        footNote={
          <>
            <NotShownLine notShown={notShown} stampHint="StampDesign -Hub" />
            <HubSyncLine />
          </>
        }
      />

      {move ? (
        <MoveDesignDialog
          design={move.design}
          road={move.road}
          open
          onClose={() => setMove(null)}
          onMoved={(line) => setOutcome(line)}
        />
      ) : null}

      <Dialog
        open={open}
        onOpenChange={(_e, d) => {
          setOpen(d.open);
          if (!d.open) reset();
        }}
      >
        <DialogSurface>
          <DialogBody>
            <DialogTitle action={<DialogDismiss />}>New Design Note</DialogTitle>
            <DialogContent>
              <div className={styles.fields}>
                <Field label="Title" required>
                  <Input
                    size="small"
                    value={title}
                    onChange={(_, d) => setTitle(d.value)}
                    placeholder="Board ideas"
                  />
                </Field>
                <Field
                  label="In a sentence"
                  hint="Optional. The line the list shows under the title."
                >
                  <Input
                    size="small"
                    value={description}
                    onChange={(_, d) => setDescription(d.value)}
                  />
                </Field>
                <Field label="For a Space" hint="Optional. A note may belong to no product yet.">
                  <Dropdown
                    size="small"
                    value={space ? spaceName(space) : "No Space"}
                    selectedOptions={[space]}
                    onOptionSelect={(_, d) => setSpace(d.optionValue ?? NO_SPACE)}
                  >
                    <Option value={NO_SPACE}>No Space</Option>
                    {spaces.map((s) => (
                      <Option key={s.slug} value={s.slug}>
                        {s.name || s.slug}
                      </Option>
                    ))}
                  </Dropdown>
                </Field>
                {message ? (
                  <Caption1
                    role="alert"
                    style={{ color: tokens.colorPaletteRedForeground1, whiteSpace: "pre-wrap" }}
                  >
                    {message}
                  </Caption1>
                ) : null}
              </div>
            </DialogContent>
            <DialogActions>
              <DialogTrigger disableButtonEnhancement>
                <Button appearance="secondary">Cancel</Button>
              </DialogTrigger>
              <Button appearance="primary" onClick={create} disabled={!title.trim() || adding}>
                {adding ? "Writing…" : "Submit"}
              </Button>
            </DialogActions>
          </DialogBody>
        </DialogSurface>
      </Dialog>
    </>
  );
}
