import { useState } from "react";
import { useNavigate } from "react-router";
import {
  Badge,
  Body1,
  Caption1,
  Card,
  Subtitle2,
  makeStyles,
  tokens,
} from "@fluentui/react-components";
import {
  CommentRegular,
  DocumentTextRegular,
  LightbulbRegular,
  NotebookRegular,
  OpenRegular,
} from "@fluentui/react-icons";
import { CardActions } from "../../shared/CardActions";
import type { CardAction } from "../../shared/CardActions";
import { CardSpinner } from "../../shared/CardSpinner";
import { EmptyState } from "../../shared/EmptyState";
import type { EmptyMessage } from "../../shared/EmptyState";
import { PageCard } from "../../shared/PageCard";
import { RefreshButton } from "../../shared/RefreshButton";
import { useGetDesignQuery, useLazySearchDesignQuery } from "./api.ado";
import { designRoomPath } from "./docRooms";
import type { Design, DesignDoc } from "./api.ado";
import { DesignGroups, LearnMoreLink, NO_STRUCTURE, stateColor } from "./DesignGroups";
import { BoundCards } from "./DesignBindings";
import { DesignSearchInside, SearchInsideButton } from "./DesignSearchInside";
import { ALL, DESIGN_KINDS, designMatches, filterSummary, useDesignFilters } from "./docFilters";

// The Design tab (Studio S2, D-S11; the design lifecycle's reader, L2): a
// GitHub Space's designs, read from the product's repo THROUGH THE TRACKER.
// Since L2 the unit is the DESIGN -- one id, a note and at most one spec -- and
// the list is ONE list grouped by state in road order (Design, Spec, Complete,
// Archived), Complete and Archived collapsed to a count until opened or
// searched. A row is the design: title, description, the short id, its state,
// its thread chip; in Spec and Complete the row opens the spec with the note
// beside it ("no spec really exists without design"). The agent decides every
// state; this file draws.
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
  title: { flex: 1, minWidth: 0 },
  metaRow: {
    display: "flex",
    gap: tokens.spacingHorizontalM,
    flexWrap: "wrap" as const,
    marginTop: tokens.spacingVerticalXS,
    alignItems: "center",
  },
  mismatch: { color: tokens.colorPaletteDarkOrangeForeground1 },
});

/** The reading room's address for one document. */
export function designDocPath(doc: Pick<DesignDoc, "folder" | "name">): string {
  return designRoomPath(doc.folder, doc.name);
}

/** The document a row opens: the spec once the design has one, else the note. */
export function primaryDoc(d: Pick<Design, "note" | "spec">): DesignDoc | null {
  return d.spec ?? d.note;
}

function DesignRow({ design }: { design: Design }) {
  const styles = useStyles();
  const navigate = useNavigate();
  const main = primaryDoc(design);
  const secondary: CardAction[] = [];
  if (design.spec && design.note) {
    secondary.push({
      icon: <NotebookRegular />,
      label: "Open the note",
      onClick: () => navigate(designDocPath(design.note!)),
    });
  }
  if (design.thread_number) {
    secondary.push({
      icon: <CommentRegular />,
      label: "Open the thread",
      onClick: () =>
        navigate(
          `/issue/${design.thread_number}?repo=${encodeURIComponent(design.thread_repo.split("/")[1] ?? "")}`,
        ),
    });
  }
  if (main?.url) {
    secondary.push({
      icon: <OpenRegular />,
      label: "Open on GitHub",
      href: main.url,
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
        </div>
        {main ? (
          <CardActions
            primaryAction={{
              icon: <DocumentTextRegular />,
              label: design.spec ? "Open the spec" : "Open the document",
              onClick: () => navigate(designDocPath(main)),
            }}
            menuLabel={`Actions for ${design.title}`}
            secondaryActions={secondary}
          />
        ) : null}
      </div>
      {design.description ? <Caption1>{design.description}</Caption1> : null}
      <div className={styles.metaRow}>
        <Badge appearance="tint" size="small" color={stateColor(design.state)}>
          {design.state}
        </Badge>
        <Caption1 title={design.id}>{design.short}</Caption1>
        {main ? <Caption1>{main.name}</Caption1> : null}
        {design.thread_number ? (
          <Badge appearance="outline" size="small" color="informative" icon={<CommentRegular />}>
            #{design.thread_number}
          </Badge>
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
          <Caption1 title="Where its durable part landed">Docs: {design.docs}</Caption1>
        ) : null}
      </div>
      {design.mismatch ? (
        <Caption1 role="note" className={styles.mismatch}>
          {design.mismatch}
        </Caption1>
      ) : null}
      {/* The cards worked against it: this Space's, read by the agent. */}
      <BoundCards cards={design.cards} />
    </Card>
  );
}

export function DesignList() {
  const { data, isLoading, isFetching, error, refetch } = useGetDesignQuery();
  // An older agent answers the flat list and no groups; it reads as no designs,
  // and its items stay counted in the chip so nothing looks lost.
  const designs = data?.designs ?? [];
  const notShown = data?.notShown ?? [];
  const structure = data?.structure;
  // The drawer's two filters: text over the rows, and the kind. The
  // page keeps its box: a filter that matches nothing says so in a row, the
  // card and its header stay where they were. A search opens the collapsed
  // groups that have a match.
  const { text, kind } = useDesignFilters();
  const shown = designs.filter((d) => designMatches(d, text, kind));
  const searching = text.trim().length > 0;
  // Search inside (L2b): the same words over the documents' text, through the
  // tracker's code search -- asked only on the button, after the groups are
  // drawn, and said in a row when it cannot run.
  const navigate = useNavigate();
  const [searchInside, inside] = useLazySearchDesignQuery();
  const [asked, setAsked] = useState<string | null>(null);
  const runSearch = () => {
    const q = text.trim();
    setAsked(q);
    void searchInside(q);
  };
  const summary = filterSummary(
    kind === ALL ? undefined : (DESIGN_KINDS.find((k) => k.value === kind)?.label ?? kind),
    text,
  );
  const icon = <LightbulbRegular />;
  // A refused address (400) says its own sentence: the agent's detail.
  const refused =
    error && "status" in error && error.status === 400
      ? ((error.data as { detail?: string } | undefined)?.detail ??
        "This Space's address names no repository.")
      : null;
  const noStructure =
    !!data &&
    data.supported &&
    !data.reason &&
    structure !== undefined &&
    !structure.design &&
    !structure.spec;
  const empty: EmptyMessage | undefined =
    isLoading || isFetching
      ? undefined
      : refused
        ? { icon, tone: "error", title: "No repository to read", detail: refused }
        : error
          ? {
              icon,
              tone: "error",
              title: "Could not read the designs",
              detail: "GitHub did not answer. Nothing was read.",
            }
          : data && !data.supported
            ? {
                icon,
                title: "No designs in this Space",
                detail: "The Design tab reads a GitHub repo's design/ and spec/.",
              }
            : data?.reason
              ? { icon, tone: "error", title: "Could not read the designs", detail: data.reason }
              : noStructure
                ? {
                    icon,
                    title: NO_STRUCTURE.title,
                    detail: NO_STRUCTURE.detail,
                    action: <LearnMoreLink />,
                  }
                : designs.length === 0 && notShown.length === 0
                  ? {
                      icon,
                      title: "No designs or specs yet",
                      detail: `A note in ${data?.repo || "the repo"}'s design/ or a spec in spec/ shows up here, grouped by state.`,
                      action: <LearnMoreLink />,
                    }
                  : undefined;
  return (
    <PageCard
      scrollable
      empty={empty ? <EmptyState {...empty} /> : undefined}
      headerLeft={
        <>
          <LightbulbRegular />
          <Subtitle2>Designs and specs</Subtitle2>
          {summary ? <Caption1>{summary}</Caption1> : null}
          {searching && data?.supported ? (
            <SearchInsideButton onClick={runSearch} busy={inside.isFetching} />
          ) : null}
        </>
      }
      headerRight={
        <>
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
    >
      {isLoading || isFetching ? (
        <CardSpinner label="Reading the repo's design/ and spec/..." />
      ) : (
        <>
          {asked !== null ? (
            <DesignSearchInside
              result={inside.data}
              loading={inside.isFetching}
              failed={!!inside.error}
              onOpen={(h) =>
                navigate(designRoomPath(h.path.slice(0, h.path.lastIndexOf("/")), h.name))
              }
              onClear={() => setAsked(null)}
            />
          ) : null}
          <DesignGroups
            designs={shown}
            notShown={notShown}
            stampHint="StampDesign"
            searching={searching}
            renderRow={(d) => <DesignRow key={d.id} design={d} />}
          />
          {designs.length > 0 && shown.length === 0 ? (
            <Caption1 role="status">No designs or specs match the filters.</Caption1>
          ) : null}
        </>
      )}
    </PageCard>
  );
}
