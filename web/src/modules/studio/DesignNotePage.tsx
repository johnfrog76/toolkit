import { useMemo, useState } from "react";
import { useParams } from "react-router";
import { Badge, Button, Caption1, Subtitle2, makeStyles, tokens } from "@fluentui/react-components";
import { CommentRegular, LightbulbRegular, ShareRegular } from "@fluentui/react-icons";
import { CardActions } from "../../shared/CardActions";
import { ConfirmDialog } from "../../shared/ConfirmDialog";
import { StatusMessage } from "../../shared/StatusMessage";
import { STUDIO } from "../../shell/consts";
import { BackButton } from "../../shared/BackButton";
import { EmptyState } from "../../shared/EmptyState";
import { MarkdownViewer } from "../../shared/MarkdownViewer";
import { PageCard } from "../../shared/PageCard";
import { RefreshButton } from "../../shared/RefreshButton";
import { useGetEnvQuery } from "../../shell/api";
import { useGetIssueDetailQuery } from "../ado/api.ado";
import { buildPromoteDesignParams, commandResultMessage } from "../ado/cliBridge";
import { documentWithThread } from "../ado/documentWithThread";
import { useGetDesignNoteQuery, useRunPromoteDesignMutation } from "./api.studio";
import type { DesignNote } from "./api.studio";
import type { EnvStatus } from "../../shell/api";
import { noteLinkBase } from "./noteLinks";

// The reading room for ONE hub design note (Studio S2b) -- the house's reading
// page, the frame a card, an issue or a repo's design is read in: PageCard, the
// back arrow and the title on the left, compact controls on the right, and ONE
// MarkdownViewer. Its links resolve through the one resolver (shared/docLinks).
//
// The "document with a thread" face (S2b): when the note's `> GitHub:` line
// names an issue that a declared GitHub Space can read (the agent says which,
// `thread_space`), the thread follows the note in the same viewer -- read
// through that Space, which need not be the one you are in. Elsewhere the
// header still links it.
/** Why Promote cannot run here, in words a person can act on -- or null when it
 *  can. Promote files the thread into the Space you are in (the verb's
 *  NewItem), so that Space must be GitHub (D-S9) and, when the note names a
 *  Space, must be that one. The verb holds the same two rules; this says them
 *  before the click. */
export function promoteBlocked(
  note: Pick<DesignNote, "space" | "thread">,
  env: EnvStatus | undefined,
): string | null {
  if (note.thread) return "it already has its thread";
  if (env?.tracker !== "github")
    return "a design's thread is a GitHub issue -- switch to a GitHub Space first";
  const here = env?.config?.activeSpace ?? "";
  if (note.space && note.space !== here) {
    const name = env?.config?.spaces.find((s) => s.slug === note.space)?.name || note.space;
    return `this note is for ${name} -- switch to it first`;
  }
  return null;
}

const useStyles = makeStyles({
  page: { display: "flex", flexDirection: "column", gap: tokens.spacingVerticalM, width: "100%" },
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

export function DesignNotePage() {
  const styles = useStyles();
  // The address is a live note's name, or a hub path into one of the four
  // folders -- design/archive/old.md, spec/x.spec.md (L2). The splat keeps the
  // slashes; the agent reads either.
  const params = useParams();
  const name = params["*"] ?? params.name ?? "";
  const { data, isLoading, isFetching, error, refetch } = useGetDesignNoteQuery(name);
  // Promote and the "design note" badge are a LIVE note's: a spec, or anything
  // in an archive, is read and not promoted (its road is MoveDesign's, L3).
  const isLiveNote = !!data && (data.kind ?? "note") === "note" && !data.archived;
  const { data: env } = useGetEnvQuery();
  const readable = !!data && !error;
  const threadReadable = !!(readable && data.thread_number && data.thread_space);
  const { data: thread } = useGetIssueDetailQuery(
    {
      id: data?.thread_number ?? 0,
      repo: data?.thread_repo.split("/")[1],
      space: data?.thread_space,
    },
    { skip: !threadReadable },
  );
  const content = useMemo(
    () => (readable ? documentWithThread(data.body, threadReadable ? thread : undefined) : ""),
    [readable, data, threadReadable, thread],
  );
  // A sibling link resolves against the folder the document sits in.
  const folder = name.includes("/") ? name.slice(0, name.lastIndexOf("/")) : "design";
  const file = name.split("/").pop() ?? name;
  const links = useMemo(() => noteLinkBase(folder, file), [folder, file]);
  const [promote, { isLoading: promoting }] = useRunPromoteDesignMutation();
  const [confirming, setConfirming] = useState(false);
  const [refusal, setRefusal] = useState<string | null>(null);
  const [promoted, setPromoted] = useState<string | null>(null);
  const runPromote = async () => {
    setRefusal(null);
    try {
      const result = await promote({ params: buildPromoteDesignParams({ name: file }) }).unwrap();
      if (result.status === "success") {
        setConfirming(false);
        setPromoted(commandResultMessage(result, "Promoted."));
        return;
      }
      setRefusal(commandResultMessage(result, "Promoted."));
    } catch {
      setRefusal("Could not reach the agent. Nothing was created.");
    }
  };
  const spaceName = (slug: string) =>
    env?.config?.spaces.find((s) => s.slug === slug)?.name || slug;

  const missing = error && "status" in error && error.status === 404;
  const empty = readable ? undefined : (
    <EmptyState
      icon={<LightbulbRegular />}
      tone="error"
      title={missing ? `No note ${name}` : "Could not open this note"}
      detail={
        missing
          ? "It is not in the hub's design/, spec/ or their archives -- it may have moved along its road, or into its product's repo."
          : "The agent did not answer. Nothing was read."
      }
    />
  );

  return (
    <div className={styles.page}>
      <PageCard
        loading={isLoading}
        loadingLabel="Reading the note..."
        empty={empty}
        headerLeft={
          <>
            <BackButton />
            {readable && (
              <div className={styles.titleBlock}>
                <Subtitle2 as="h1">{data.title}</Subtitle2>
                <div className={styles.metaRow}>
                  <Badge
                    appearance="tint"
                    size="small"
                    color={(data.kind ?? "note") === "note" ? "brand" : "informative"}
                  >
                    {(data.kind ?? "note") === "note" ? "design note" : "spec"}
                  </Badge>
                  {data.archived ? (
                    <Badge appearance="outline" size="small" color="subtle">
                      archived
                    </Badge>
                  ) : null}
                  {data.path ? <Caption1>{data.path}</Caption1> : null}
                  {data.space ? <Caption1>for {spaceName(data.space)}</Caption1> : null}
                  {data.description ? <Caption1>{data.description}</Caption1> : null}
                </div>
              </div>
            )}
          </>
        }
        headerRight={
          readable ? (
            <>
              {data.thread ? (
                <Button
                  size="small"
                  appearance="subtle"
                  icon={<CommentRegular />}
                  title={`The thread, #${data.thread_number} on GitHub`}
                  aria-label={`The thread, #${data.thread_number} on GitHub`}
                  as="a"
                  href={data.thread}
                  target="_blank"
                  rel="noopener noreferrer"
                />
              ) : isLiveNote ? (
                <CardActions
                  primaryAction={{
                    icon: <ShareRegular />,
                    label: "Promote",
                    onClick: () => setConfirming(true),
                    disabled: !!promoteBlocked(data, env) || promoting,
                    whyNot: promoteBlocked(data, env) ?? undefined,
                  }}
                />
              ) : null}
              <RefreshButton onClick={refetch} isFetching={isFetching} />
            </>
          ) : undefined
        }
      >
        {promoted ? (
          <StatusMessage status="success" onDismiss={() => setPromoted(null)}>
            {promoted}
          </StatusMessage>
        ) : null}
        {readable && (
          <MarkdownViewer
            content={content}
            titleAbove={data.title}
            links={links}
            style={{ marginTop: tokens.spacingVerticalS }}
          />
        )}
      </PageCard>
      <ConfirmDialog
        open={confirming}
        title="Promote this note?"
        what={
          readable ? (
            <>
              Open an issue in {spaceName(env?.config?.activeSpace ?? "")}, labelled{" "}
              {STUDIO.promoteLabel}: its title &ldquo;{data.title}&rdquo;, its body the note. The
              issue&apos;s URL is written back into the note as its thread, and review happens
              there.
            </>
          ) : (
            ""
          )
        }
        confirmLabel="Promote"
        busy={promoting}
        message={refusal}
        onConfirm={runPromote}
        onCancel={() => {
          setConfirming(false);
          setRefusal(null);
        }}
      />
    </div>
  );
}
