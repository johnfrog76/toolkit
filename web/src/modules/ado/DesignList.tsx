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
import { CommentRegular, LightbulbRegular } from "@fluentui/react-icons";
import { CardActions, ROW } from "../../shared/CardActions";
import { trackerName } from "./TrackerBadge";
import type { CardAction } from "../../shared/CardActions";
import { CardSpinner } from "../../shared/CardSpinner";
import { EmptyState } from "../../shared/EmptyState";
import type { EmptyMessage } from "../../shared/EmptyState";
import { PageCard } from "../../shared/PageCard";
import { RefreshButton } from "../../shared/RefreshButton";
import { useGetDesignQuery, useLazySearchDesignQuery } from "./api.ado";
import { designRoomPath } from "./docRooms";
import type { Design, DesignCheckout, DesignDoc } from "./api.ado";
import { MoveDesignDialog, ROADS, roadsFor } from "../studio/MoveDesignDialog";
import type { MoveRoad, ProductCheckout } from "../studio/MoveDesignDialog";
import { DesignGroups, LearnMoreLink, NO_STRUCTURE, stateColor } from "./DesignGroups";
import { BoundCards, DesignDocsLine } from "./DesignBindings";
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
//
// A row's moves (#146): where this machine names the Space's checkout
// (spaceCheckouts.<slug>.path) and the agent found it a clone of this repo, a
// row offers the same roads a hub design's does -- the same ROADS entries, from
// the same vocabulary -- and the dialog runs MoveDesign -Space <slug> through
// the bridge, staged in that clone and never committed. Where it does not, the
// menu is what it was, and the card's foot names the setting.
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

/** The one line the card's foot says when the rows cannot move: which setting
 *  would let them, or why the one set does not. "" when they can, or when the
 *  agent said nothing (an older agent, no Space). */
export function checkoutLine(checkout: DesignCheckout | null | undefined, repo: string): string {
  if (!checkout || checkout.ready) return "";
  if (checkout.reason)
    return `${checkout.reason} Point it at a clone of ${repo} to move these designs from here.`;
  return `To move these designs from here, name this machine's clone of ${repo || "the repo"}: ${checkout.key} in Settings.`;
}

function DesignRow({
  design,
  canMove,
  onMove,
}: {
  design: Design;
  /** The Space's checkout is here: the row offers its roads. */
  canMove: boolean;
  onMove: (road: MoveRoad) => void;
}) {
  const styles = useStyles();
  const navigate = useNavigate();
  const main = primaryDoc(design);
  const secondary: CardAction[] = [];
  if (design.spec && design.note) {
    secondary.push(
      ROW.open.action({ detail: "the note", onClick: () => navigate(designDocPath(design.note!)) }),
    );
  }
  if (design.thread_number) {
    secondary.push(
      ROW.open.action({
        detail: "the thread",
        onClick: () =>
          navigate(
            `/issue/${design.thread_number}?repo=${encodeURIComponent(design.thread_repo.split("/")[1] ?? "")}`,
          ),
      }),
    );
  }
  // The moves a product row offers where its checkout is here (#146): the hub
  // row's roads, built the same way, from the same entries.
  const roads = canMove ? roadsFor(design) : [];
  roads.forEach((road, i) => {
    secondary.push(
      ROADS[road].move.action({
        detail: ROADS[road].detail,
        onClick: () => onMove(road),
        dividerBefore: i === 0 && secondary.length > 0,
      }),
    );
  });
  if (main?.url) {
    secondary.push(ROW.external.action({ detail: trackerName("github"), href: main.url }));
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
            primaryAction={ROW.open.action({
              detail: design.spec ? "the spec" : "the document",
              onClick: () => navigate(designDocPath(main)),
            })}
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
        {design.docs ? <DesignDocsLine docs={design.docs} linked /> : null}
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
  // One move at a time: the row's road and its design, until the dialog closes.
  const [move, setMove] = useState<{ design: Design; road: MoveRoad } | null>(null);
  const checkout = data?.checkout;
  const product: ProductCheckout | undefined =
    checkout?.ready && checkout.space && data?.repo
      ? { space: checkout.space, repo: data.repo, root: checkout.root }
      : undefined;
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
  const footLine = data?.supported && designs.length > 0 ? checkoutLine(checkout, data.repo) : "";
  return (
    <>
      <PageCard
        scrollable
        empty={empty ? <EmptyState {...empty} /> : undefined}
        footerLeft={footLine ? <Caption1 role="note">{footLine}</Caption1> : undefined}
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
              renderRow={(d) => (
                <DesignRow
                  key={d.id}
                  design={d}
                  canMove={!!product}
                  onMove={(road) => setMove({ design: d, road })}
                />
              )}
            />
            {designs.length > 0 && shown.length === 0 ? (
              <Caption1 role="status">No designs or specs match the filters.</Caption1>
            ) : null}
          </>
        )}
      </PageCard>
      {move && product ? (
        <MoveDesignDialog
          design={move.design}
          road={move.road}
          open
          checkout={product}
          onClose={() => setMove(null)}
          // Staged: the tab re-reads (the row moves once the commit is pushed).
          onMoved={() => void refetch()}
        />
      ) : null}
    </>
  );
}
