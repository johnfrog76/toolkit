import { useMemo } from "react";
import { useParams } from "react-router";
import { Badge, Button, Caption1, Subtitle2, makeStyles, tokens } from "@fluentui/react-components";
import { CommentRegular, LightbulbRegular, OpenRegular } from "@fluentui/react-icons";
import { useGetDesignDocQuery, useGetIssueDetailQuery } from "./api.ado";
import type { DesignDocDetail, IssueDetail } from "./api.ado";
import { documentWithThread } from "./documentWithThread";
import { repoLinkBase } from "./docRooms";
import { FOLDERS } from "../../shell/consts";
import { BackButton } from "../../shared/BackButton";
import { EmptyState } from "../../shared/EmptyState";
import { FilePath } from "../../shared/FilePath";
import { MarkdownViewer } from "../../shared/MarkdownViewer";
import { PageCard } from "../../shared/PageCard";
import { RefreshButton } from "../../shared/RefreshButton";

// The reading room for ONE design or spec (Studio S2, D-S11) -- the house's
// reading page, the same frame an issue or a card is read in: PageCard, the
// back arrow and the title on the left, compact controls on the right, and ONE
// MarkdownViewer. When the document names a thread (a `> GitHub:` line), the
// thread is part of that one document, after the file -- read from the same
// route the issue's own reading room reads, so one zoom, one "On this page".
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

/** The document, then its thread when it has one and it could be read -- the
 *  reading room's "document with a thread" face (documentWithThread.ts). */
export function designDocument(doc: DesignDocDetail, thread?: IssueDetail): string {
  return documentWithThread(doc.body, thread);
}

export function DesignDocPage({ archive = false }: { archive?: boolean }) {
  const styles = useStyles();
  const params = useParams();
  const name = params.name ?? "";
  // The archive route (design lifecycle L2): /design/:folder/archive/:name
  // reads folder/archive/name -- the folder the agent lists it under.
  const folder = archive ? `${params.folder ?? ""}/${FOLDERS.archive}` : (params.folder ?? "");
  const { data, isLoading, isFetching, error, refetch } = useGetDesignDocQuery({ folder, name });
  const readable = data && data.supported && !data.reason && !error;
  // The thread is read only when the document names one in THIS Space's repo:
  // the issue route resolves its repo among the Space's, so another repo's
  // issue would be the wrong one. Elsewhere the header still links it.
  const threadHere = !!(readable && data.thread_number && data.thread_repo === data.repo);
  const { data: thread } = useGetIssueDetailQuery(
    { id: data?.thread_number ?? 0, repo: data?.repo.split("/")[1] },
    { skip: !threadHere },
  );
  const content = useMemo(
    () => (readable ? designDocument(data, threadHere ? thread : undefined) : ""),
    [readable, data, threadHere, thread],
  );

  // The document's place in the repo: its relative links resolve against it,
  // ONE resolver for both rooms -- a spec's link to its design note
  // opens the note here, a link into docs/ opens the Docs room.
  const links = useMemo(
    () => (data && readable ? repoLinkBase(data.path, data.url) : undefined),
    [readable, data],
  );

  const missing = error && "status" in error && error.status === 404;
  const empty = readable ? undefined : (
    <EmptyState
      icon={<LightbulbRegular />}
      tone={data && !data.supported ? undefined : "error"}
      title={
        data && !data.supported
          ? "No designs in this Space"
          : missing
            ? `No ${folder}/${name}`
            : "Could not open this document"
      }
      detail={
        data?.reason ??
        (data && !data.supported
          ? "The Design tab reads a GitHub repo's design/ and spec/."
          : missing
            ? "It is not in the repo's design/, spec/ or their archives -- it may have moved along its road."
            : "GitHub did not answer. Nothing was read.")
      }
    />
  );

  return (
    <div className={styles.page}>
      <PageCard
        loading={isLoading}
        loadingLabel="Reading the document..."
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
                    color={data.folder.startsWith("design") ? "brand" : "informative"}
                  >
                    {data.folder}
                  </Badge>
                  {data.closed ? (
                    <Badge
                      appearance="outline"
                      size="small"
                      color="subtle"
                      title="The day it entered the archive"
                    >
                      Closed {data.closed}
                    </Badge>
                  ) : null}
                  {data.outcome ? (
                    <Badge
                      appearance="outline"
                      size="small"
                      color={data.outcome === "dropped" ? "warning" : "success"}
                    >
                      {data.outcome}
                    </Badge>
                  ) : null}
                  {data.id ? <Caption1 title={data.id}>{data.id.slice(0, 8)}</Caption1> : null}
                  <Caption1>{data.repo}</Caption1>
                  {data.description ? <Caption1>{data.description}</Caption1> : null}
                </div>
                <FilePath path={data.url} what="document link" />
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
                  as="a"
                  href={data.thread}
                  target="_blank"
                  rel="noopener noreferrer"
                />
              ) : null}
              <Button
                size="small"
                appearance="subtle"
                icon={<OpenRegular />}
                title="Open on GitHub"
                as="a"
                href={data.url}
                target="_blank"
                rel="noopener noreferrer"
              />
              <RefreshButton onClick={refetch} isFetching={isFetching} />
            </>
          ) : undefined
        }
      >
        {readable && (
          <MarkdownViewer
            content={content}
            titleAbove={data.title}
            links={links}
            style={{ marginTop: tokens.spacingVerticalS }}
          />
        )}
      </PageCard>
    </div>
  );
}
