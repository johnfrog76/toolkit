import { useState } from "react";
import { usePagination } from "../../hooks/usePagination";
import { useNavigate } from "react-router";
import {
  Badge,
  Body1,
  Button,
  Caption1,
  Card,
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
  Subtitle2,
  Tooltip,
  makeStyles,
  tokens,
} from "@fluentui/react-components";
import {
  ArrowRightRegular,
  CommentRegular,
  DocumentTextRegular,
  NotebookRegular,
  OpenRegular,
} from "@fluentui/react-icons";
import { CardActions } from "../../shared/CardActions";
import type { CardAction } from "../../shared/CardActions";
import { CardSpinner } from "../../shared/CardSpinner";
import { CreateButton } from "../../shared/CreateButton";
import { DialogDismiss } from "../../shared/DialogDismiss";
import { EmptyState } from "../../shared/EmptyState";
import { PageCard } from "../../shared/PageCard";
import { HubSyncLine } from "../ado/HubSyncLine";
import { Pagination } from "../../shared/Pagination";
import { RefreshButton } from "../../shared/RefreshButton";
import { StatusMessage } from "../../shared/StatusMessage";
import { useGetEnvQuery } from "../../shell/api";
import { buildNewDesignParams, commandResultMessage } from "../ado/cliBridge";
import { DesignGroups, LearnMoreLink, groupByState, stateColor } from "../ado/DesignGroups";
import { BoundCards, DesignDocsLine } from "../ado/DesignBindings";
import { DesignSearchInside, SearchInsideButton } from "../ado/DesignSearchInside";
import { ALL, designMatches } from "../ado/docFilters";
import { useSharedPersistedValue } from "../../shared/usePersistedState";
import type { Design } from "../ado/api.ado";
import {
  useGetDesignNotesQuery,
  useLazySearchHubDesignsQuery,
  useRunNewDesignMutation,
} from "./api.studio";
import { MoveDesignDialog, ROADS, roadsFor } from "./MoveDesignDialog";
import type { MoveRoad } from "./MoveDesignDialog";
import { STUDIO_PAGE_SIZE, notePath } from "./paths";
import { useEnterSpace } from "./useEnterSpace";

// The seed drawer (Studio S2b, D-S3): the hub's designs -- the ones that belong
// to no product yet. Since the design lifecycle's reader (L2, D-DL12) the
// hub keeps the same four folders a product does, and the drawer draws the same
// groups the Design tab draws: one list by state, Complete and Archived
// collapsed to a count. Each row is the house row: the title is text, the one
// exposed action opens the reading room, the menu holds the thread. The +
// writes a note through NewDesign (the bridge), so the file is the record from
// its first minute.
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
  // The title and, after it, the Space chip, on one line that wraps.
  title: {
    flex: 1,
    minWidth: 0,
    display: "flex",
    alignItems: "center",
    flexWrap: "wrap" as const,
    columnGap: tokens.spacingHorizontalS,
  },
  chip: { minWidth: "auto" },
  metaRow: {
    display: "flex",
    gap: tokens.spacingHorizontalM,
    flexWrap: "wrap" as const,
    marginTop: tokens.spacingVerticalXS,
    alignItems: "center",
  },
  mismatch: { color: tokens.colorPaletteDarkOrangeForeground1 },
  fields: { display: "flex", flexDirection: "column", rowGap: tokens.spacingVerticalM },
});

const NO_SPACE = "";
/** The drawer's search, remembered per browser (not a Space's: a switch keeps it). */
export const HUB_DESIGN_TEXT_KEY = "studio.design.text";

/** The document a hub row opens: the note (the design IS the note), else the spec. */
function primaryPath(d: Design): string | null {
  const doc = d.note ?? d.spec;
  return doc ? doc.path : null;
}

function DesignRow({
  design,
  spaceName,
  activeSpace,
  onMove,
}: {
  design: Design;
  spaceName: (slug: string) => string;
  activeSpace: string;
  /** A road the row offers (L3): the dialog runs MoveDesign -Hub through the bridge. */
  onMove: (road: MoveRoad) => void;
}) {
  const styles = useStyles();
  const navigate = useNavigate();
  // The Space a note names is a switch into it: the foyer row's move,
  // through the one hook. A note with no Space draws no chip.
  const space = design.space ? spaceName(design.space) : "";
  const { enter, switching, failed } = useEnterSpace(design.space, design.space === activeSpace);
  const main = primaryPath(design);
  const secondary: CardAction[] = [];
  if (design.note && design.spec) {
    secondary.push({
      icon: <DocumentTextRegular />,
      label: "Open the spec",
      onClick: () => navigate(notePath(design.spec!.path)),
    });
  }
  // The moves a hub row offers (L3): by what the design has and where it is.
  const roads = roadsFor(design);
  roads.forEach((road, i) => {
    secondary.push({
      icon: <ArrowRightRegular />,
      label: ROADS[road].label,
      onClick: () => onMove(road),
      dividerBefore: i === 0 && secondary.length > 0,
    });
  });
  if (design.thread) {
    secondary.push({
      icon: <OpenRegular />,
      label: "Open the thread on GitHub",
      href: design.thread,
      dividerBefore: secondary.length > 0,
    });
  }
  return (
    <Card className={styles.row} size="small" appearance="outline">
      <div className={styles.rowHeader}>
        <div className={styles.title}>
          <Body1>
            <strong>{design.title}</strong>
          </Body1>
          {design.space ? (
            <Tooltip content={design.space} relationship="description">
              <Button
                className={styles.chip}
                size="small"
                shape="circular"
                appearance="outline"
                aria-label={`Switch to ${space}`}
                onClick={enter}
                disabled={switching}
              >
                {space}
              </Button>
            </Tooltip>
          ) : null}
        </div>
        {main ? (
          <CardActions
            primaryAction={{
              icon: <DocumentTextRegular />,
              label: design.note ? "Open the note" : "Open the spec",
              onClick: () => navigate(notePath(main)),
            }}
            menuLabel={`Actions for ${design.title}`}
            secondaryActions={secondary}
          />
        ) : null}
      </div>
      {failed ? (
        <Caption1 role="alert">Could not switch to {space}. Nothing changed.</Caption1>
      ) : null}
      {design.description ? <Caption1>{design.description}</Caption1> : null}
      <div className={styles.metaRow}>
        <Badge appearance="tint" size="small" color={stateColor(design.state)}>
          {design.state}
        </Badge>
        <Caption1 title={design.id}>{design.short}</Caption1>
        {main ? <Caption1>{main.split("/").pop()}</Caption1> : null}
        {design.thread_number ? (
          <Badge appearance="outline" size="small" color="informative" icon={<CommentRegular />}>
            #{design.thread_number}
          </Badge>
        ) : design.note && !design.note.archived ? (
          <Caption1>no thread yet</Caption1>
        ) : null}
        {design.closed ? (
          <Caption1 title="The day it entered the archive">Closed {design.closed}</Caption1>
        ) : null}
        {design.outcome ? (
          <Badge
            appearance="outline"
            size="small"
            color={design.outcome === "dropped" ? "warning" : "success"}
          >
            {design.outcome}
          </Badge>
        ) : null}
        {design.docs ? (
          <DesignDocsLine
            docs={design.docs}
            linked={!!design.space && design.space === activeSpace}
          />
        ) : null}
      </div>
      {design.mismatch ? (
        <Caption1 role="note" className={styles.mismatch}>
          {design.mismatch}
        </Caption1>
      ) : null}
      {/* The cards worked against it, from every Space: another Space's is named, not opened. */}
      <BoundCards cards={design.cards} activeSpace={activeSpace} />
    </Card>
  );
}

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
  // One pager over the list as the card draws it: the search applies first,
  // then the groups' order (state, in road order), then five a page.
  const ordered = groupByState(shown).flatMap((g) => g.designs);
  const { page, totalPages, pageItems, setPage } = usePagination(ordered, STUDIO_PAGE_SIZE);

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
  const empty =
    isLoading || isFetching ? undefined : error ? (
      <EmptyState
        icon={icon}
        tone="error"
        title="Could not read the notes"
        detail="The agent did not answer. Nothing was read."
      />
    ) : data?.exists === false ? (
      // A hub copied out before the Studio was core has no design/ folder.
      // That is not a fault: the first note makes it.
      <EmptyState
        icon={icon}
        title={`No ${folder}/ folder yet`}
        detail={`This hub has no ${folder}/ folder yet. Your private notes live there until they belong to a product; the + writes the first one and makes the folder.`}
        action={<LearnMoreLink />}
      />
    ) : designs.length === 0 && notShown.length === 0 ? (
      <EmptyState
        icon={icon}
        title="No design notes yet"
        detail={`Your private notes live in the hub's ${folder}/ until they belong to a product. The + writes one.`}
      />
    ) : undefined;

  return (
    <>
      <PageCard
        scrollable
        empty={empty}
        headerLeft={
          <>
            {icon}
            <Subtitle2>Hub Designs</Subtitle2>
          </>
        }
        headerRight={
          <>
            <Input
              size="small"
              type="search"
              aria-label="Search the hub's designs"
              placeholder="Search designs"
              value={search.value}
              onChange={(_, d) => {
                search.setValue(d.value);
                setPage(0);
              }}
            />
            {searching ? <SearchInsideButton onClick={runSearch} busy={inside.isFetching} /> : null}
            <RefreshButton
              onClick={refetch}
              isFetching={isFetching && !isLoading}
              disabled={isLoading}
            />
            <Badge color="informative" appearance="filled" size="large">
              {shown.length}
            </Badge>
          </>
        }
        footerLeft={<Caption1>Your private files. Notes that belong to no product yet.</Caption1>}
        footerCenter={
          totalPages > 1 ? (
            <Pagination page={page} totalPages={totalPages} onPageChange={setPage} />
          ) : undefined
        }
        footerRight={<CreateButton label="New Design Note" onClick={() => setOpen(true)} />}
        footNote={<HubSyncLine />}
      >
        {outcome ? (
          <StatusMessage status="success" onDismiss={() => setOutcome(null)}>
            {outcome}
          </StatusMessage>
        ) : null}
        {isLoading || isFetching ? (
          <CardSpinner label="Reading the hub's design notes..." />
        ) : (
          <>
            {asked !== null ? (
              <DesignSearchInside
                result={inside.data}
                loading={inside.isFetching}
                failed={!!inside.error}
                onOpen={(h) => navigate(notePath(h.path))}
                onClear={() => setAsked(null)}
              />
            ) : null}
            <DesignGroups
              designs={pageItems}
              counted={shown}
              notShown={notShown}
              stampHint="StampDesign -Hub"
              searching={searching}
              renderRow={(d) => (
                <DesignRow
                  key={d.id}
                  design={d}
                  spaceName={spaceName}
                  activeSpace={activeSpace}
                  onMove={(road) => setMove({ design: d, road })}
                />
              )}
            />
            {designs.length > 0 && shown.length === 0 ? (
              <Caption1 role="status">No design matches the search.</Caption1>
            ) : null}
          </>
        )}
      </PageCard>

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
