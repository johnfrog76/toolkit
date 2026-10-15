import { useMemo, useState } from "react";
import { useParams, useSearchParams } from "react-router";
import {
  Badge,
  Button,
  Caption1,
  Select,
  Subtitle2,
  makeStyles,
  tokens,
} from "@fluentui/react-components";
import {
  CheckmarkCircleRegular,
  DocumentAddRegular,
  DocumentTextRegular,
  OpenRegular,
  PinOffRegular,
  PinRegular,
} from "@fluentui/react-icons";
import { useEditWorkItemMutation, useGetIssueDetailQuery } from "./api.ado";
import type { CommandResponse, IssueDetail } from "./api.ado";
import { commandResultMessage } from "./cliBridge";
import { StatusMessage } from "../../shared/StatusMessage";
import { trackerName } from "./TrackerBadge";
import { BackButton } from "../../shared/BackButton";
import { EmptyState } from "../../shared/EmptyState";
import { FilePath } from "../../shared/FilePath";
import { PublicLine, useActiveSpaceIsPublic } from "../../shared/visibility";
import { MarkdownViewer } from "../../shared/MarkdownViewer";
import { PageCard } from "../../shared/PageCard";
import { RefreshButton } from "../../shared/RefreshButton";
import { ActionDialog } from "./ActionDialog";
import type { ActionDialogTab } from "./ActionDialog";

// The reading room for ONE issue -- "list and details" was the
// research walk's verdict, and this is the details half. It is the house's
// reading page, the same frame a card or a review is read in: PageCard, the
// back arrow and the title on the left, every control on the right -- compact,
// as the 1:1 page's are -- and ONE
// MarkdownViewer -- so one zoom, one "On this page", one Top. Read, then act,
// one place: pickup and close are the same ActionDialog the Backlog rows use,
// so the bridge stays the one writer.
const useStyles = makeStyles({
  page: {
    display: "flex",
    flexDirection: "column",
    gap: tokens.spacingVerticalM,
    width: "100%",
  },
  titleBlock: {
    display: "flex",
    flexDirection: "column",
    rowGap: tokens.spacingVerticalXS,
    minWidth: 0,
  },
  metaRow: {
    display: "flex",
    columnGap: tokens.spacingHorizontalS,
    rowGap: tokens.spacingVerticalXXS,
    flexWrap: "wrap",
    alignItems: "center",
    color: tokens.colorNeutralForeground3,
  },
});

const SEV = /^sev[123]$/;
const SEV_COLOR: Record<string, "danger" | "severe" | "warning"> = {
  sev1: "danger",
  sev2: "severe",
  sev3: "warning",
};

/** The issue as one document: the body, then the thread, then the timeline's
 *  high signal. One document is what gives the page one contents list -- the
 *  thread and the timeline are places to jump to, like any section. */
export function issueDocument(d: IssueDetail): string {
  const parts = [d.body.trim() || "_This issue has no body -- the title is the whole of it._"];
  if (d.comments.length > 0) {
    parts.push(`## ${d.comments.length} comment${d.comments.length === 1 ? "" : "s"}`);
    for (const c of d.comments) {
      parts.push(`### ${c.author} -- ${c.when}`, c.body.trim());
    }
  }
  if (d.timeline.length > 0) {
    parts.push(
      "## Timeline",
      d.timeline
        .map((t) => {
          const text = t.text.replace(/([[\]])/g, "\\$1");
          return `- (${t.kind}) ${t.url ? `[${text}](${t.url})` : text} ${t.when}`;
        })
        .join("\n"),
    );
  }
  return parts.join("\n\n");
}

export function IssueDetailPage() {
  const styles = useStyles();
  const { num } = useParams();
  const [search] = useSearchParams();
  const id = Number(num);
  const repo = search.get("repo") ?? undefined;
  const { data, isLoading, isFetching, error, refetch } = useGetIssueDetailQuery({ id, repo });
  const [editWorkItem, { isLoading: editing }] = useEditWorkItemMutation();
  const [dialog, setDialog] = useState<{ open: boolean; tab: ActionDialogTab }>({
    open: false,
    tab: "create",
  });
  // The reading room is a GitHub page (the route answers supported: false
  // elsewhere), so the tracker it names is GitHub's -- read from the one table.
  const tracker = trackerName("github");
  // On stage: the room's actions -- severity, close, pin -- write to the
  // Space you are in. When its repository is public the room says so, once.
  // A Space that is not GitHub's answers with no visibility, and no line.
  const onStage = useActiveSpaceIsPublic(true);
  const [pinRefusal, setPinRefusal] = useState<CommandResponse | null>(null);
  const togglePin = async (d: IssueDetail) => {
    setPinRefusal(null);
    try {
      const result = await editWorkItem({ id: d.number, pinned: !d.pinned }).unwrap();
      if (result.status !== "success") setPinRefusal(result);
    } catch {
      setPinRefusal({
        command: "EditItem",
        status: "error",
        exit_code: -1,
        output: null,
        error: "Could not reach the agent. The pin was not changed.",
        duration: 0,
      });
    }
  };

  const readable = data && data.supported && !data.reason && !error;
  const content = useMemo(() => (readable ? issueDocument(data) : ""), [readable, data]);
  const sev = readable ? data.labels.find((l) => SEV.test(l)) : undefined;

  const empty = readable ? undefined : (
    <EmptyState
      icon={<DocumentTextRegular />}
      tone={data && !data.supported ? undefined : "error"}
      title={data && !data.supported ? "No issues in this space" : "Could not open this issue"}
      detail={
        data?.reason ??
        (data && !data.supported
          ? "This space does not read issues -- the reading room is a GitHub page."
          : "The issue could not be read.")
      }
    />
  );

  return (
    <div className={styles.page}>
      <PageCard
        toast={
          pinRefusal ? (
            <StatusMessage status="error" onDismiss={() => setPinRefusal(null)}>
              {commandResultMessage(pinRefusal, "The pin was not changed.")}
            </StatusMessage>
          ) : undefined
        }
        loading={isLoading}
        loadingLabel="Loading issue..."
        empty={empty}
        headerLeft={
          <>
            <BackButton />
            {readable && (
              <div className={styles.titleBlock}>
                <Subtitle2 as="h1">
                  #{data.number} {data.title}
                </Subtitle2>
                <div className={styles.metaRow}>
                  <Badge
                    color={data.state === "open" ? "success" : "informative"}
                    appearance="tint"
                    size="small"
                  >
                    {data.state}
                  </Badge>
                  {/* Beside the state: the tracker's own pin, named. */}
                  {data.pinned ? (
                    <Badge appearance="tint" size="small" color="brand" icon={<PinRegular />}>
                      {`Pinned on ${tracker}`}
                    </Badge>
                  ) : null}
                  <Badge appearance="outline" size="small" color="informative">
                    gh
                  </Badge>
                  <Badge
                    appearance="outline"
                    size="small"
                    color={
                      data.kind === "Bug"
                        ? "warning"
                        : data.kind === "Feature"
                          ? "brand"
                          : "informative"
                    }
                  >
                    {data.kind === "Feature" ? "feat" : data.kind.toLowerCase()}
                  </Badge>
                  {data.labels
                    .filter((l) => SEV.test(l))
                    .map((l) => (
                      <Badge key={l} appearance="outline" size="small" color={SEV_COLOR[l]}>
                        {l}
                      </Badge>
                    ))}
                  {data.milestone ? <Caption1>{data.milestone}</Caption1> : null}
                  {data.assignee ? <Caption1>assigned to {data.assignee}</Caption1> : null}
                  <Caption1>
                    {data.author} opened {data.created}
                    {data.closed ? ` -- closed ${data.closed}` : ""}
                  </Caption1>
                </div>
                {/* The record's address, as every detail page carries its file's:
                    what goes into a chat with an agent. */}
                <FilePath path={data.url} what="issue link" />
                <PublicLine show={onStage} />
              </div>
            )}
          </>
        }
        headerRight={
          readable ? (
            <>
              {/* The triage half: sev changed in place, through the
                  same verb the CLI types. */}
              <Select
                size="small"
                aria-label="Severity"
                value={sev ?? ""}
                disabled={editing}
                onChange={async (_e, d) => {
                  if (d.value === (sev ?? "")) return;
                  // The mutation invalidates this issue's tag; the store
                  // refetches, no refetch() by hand.
                  await editWorkItem({
                    id: data.number,
                    addTag: d.value || undefined,
                    removeTag: sev,
                  });
                }}
              >
                <option value="">no sev</option>
                <option value="sev1">sev1</option>
                <option value="sev2">sev2</option>
                <option value="sev3">sev3</option>
              </Select>
              {/* Compact, as the 1:1 page's header is: icons with a title, and
                  words only on the step a reader came here to take. */}
              <Button
                size="small"
                appearance="subtle"
                icon={<CheckmarkCircleRegular />}
                title="Close issue"
                onClick={() => setDialog({ open: true, tab: "resolve" })}
              />
              {/* The same Pin / Unpin the row's menu holds, through
                  EditItem; the mutation invalidates this issue and the list. */}
              <Button
                size="small"
                appearance="subtle"
                icon={data.pinned ? <PinOffRegular /> : <PinRegular />}
                title={data.pinned ? "Unpin" : `Pin on ${tracker}`}
                aria-label={data.pinned ? "Unpin" : `Pin on ${tracker}`}
                disabled={editing}
                onClick={() => void togglePin(data)}
              />
              <Button
                size="small"
                appearance="subtle"
                icon={<OpenRegular />}
                title={`Open on ${tracker}`}
                as="a"
                href={data.url}
                target="_blank"
                rel="noopener noreferrer"
              />
              <Button
                size="small"
                appearance="subtle"
                icon={<DocumentAddRegular />}
                onClick={() => setDialog({ open: true, tab: "create" })}
              >
                Make a card
              </Button>
              <RefreshButton onClick={refetch} isFetching={isFetching} />
            </>
          ) : undefined
        }
      >
        {readable && (
          <MarkdownViewer
            content={content}
            titleAbove={data.title}
            style={{ marginTop: tokens.spacingVerticalS }}
          />
        )}
      </PageCard>
      {readable && (
        <ActionDialog
          open={dialog.open}
          onClose={() => setDialog((d) => ({ ...d, open: false }))}
          tab={dialog.tab}
          initialWorkItemId={String(data.number)}
          initialWorkItemType={data.kind}
        />
      )}
    </div>
  );
}
