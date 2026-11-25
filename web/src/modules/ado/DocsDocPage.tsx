import { useEffect, useMemo, useRef } from "react";
import type { ReactNode } from "react";
import { useLocation, useParams } from "react-router";
import { Button, Caption1, makeStyles, tokens } from "@fluentui/react-components";
import { BookOpenRegular, OpenRegular } from "@fluentui/react-icons";
import { useGetDocQuery } from "./api.ado";
import type { DocDetail } from "./api.ado";
import { repoLinkBase } from "./docRooms";
import { DetailHeader } from "../../shared/DetailHeader";
import { EmptyState } from "../../shared/EmptyState";
import { MarkdownViewer } from "../../shared/MarkdownViewer";
import { PanelFrame } from "../../shared/PanelFrame";
import { RefreshButton } from "../../shared/RefreshButton";

// The Docs room (D-S12): ONE document from a GitHub Space's README.md or
// docs/, read the house way -- PanelFrame, the back arrow and the title on the
// left, compact controls on the right with github.com LAST, and one
// MarkdownViewer given the document's place in the repo, so its relative links
// open here (the anchor kept), its images come through /api/docs/asset, and
// everything else leaves in a new tab.
//
// No layout jump between documents: while the next one is read, the room keeps
// the one it has (the query's last answer), then swaps the text in place.
const useStyles = makeStyles({
  page: { display: "flex", flexDirection: "column", gap: tokens.spacingVerticalM, width: "100%" },
});

/** The link out to github.com, the header's last control. */
export function DocOpenButton({ doc }: { doc: DocDetail }) {
  return doc.url ? (
    <Button
      size="small"
      appearance="subtle"
      icon={<OpenRegular />}
      title="Open on GitHub"
      aria-label="Open on GitHub"
      as="a"
      href={doc.url}
      target="_blank"
      rel="noopener noreferrer"
    />
  ) : null;
}

/** The header's right side: refresh, then github.com last (the house order). */
export function DocControls({
  doc,
  refetch,
  isFetching,
}: {
  doc: DocDetail;
  refetch: () => void;
  isFetching: boolean;
}) {
  return (
    <>
      <RefreshButton onClick={refetch} isFetching={isFetching} />
      <DocOpenButton doc={doc} />
    </>
  );
}

/** Why there is nothing to read, in the room's words. */
export function docEmpty(path: string, data: DocDetail | undefined, error: unknown): ReactNode {
  const missing = !!error && typeof error === "object" && "status" in error && error.status === 404;
  const unsupported = !!data && !data.supported;
  return (
    <EmptyState
      icon={<BookOpenRegular />}
      tone={unsupported ? undefined : "error"}
      title={
        unsupported
          ? "No docs in this Space"
          : missing
            ? `No ${path}`
            : "Could not open this document"
      }
      detail={
        data?.reason ??
        (unsupported
          ? "The Docs tab reads a GitHub repo's README.md and docs/."
          : missing
            ? "It is not in the repo's README.md or docs/ -- it may have moved."
            : "GitHub did not answer. Nothing was read.")
      }
    />
  );
}

export function DocsDocPage() {
  const styles = useStyles();
  const path = useParams()["*"] ?? "";
  const { hash } = useLocation();
  const { data, isLoading, isFetching, error, refetch } = useGetDocQuery(path, { skip: !path });
  const readable = !!data && data.supported && !data.reason && !error;
  const links = useMemo(
    () => (data && readable ? repoLinkBase(data.path, data.url, data.issues ?? "") : undefined),
    [readable, data],
  );
  const anchor = hash ? decodeURIComponent(hash.slice(1)) : undefined;

  // A new document with no anchor starts at its top, as a page would.
  const topRef = useRef<HTMLDivElement>(null);
  const shown = data?.path;
  useEffect(() => {
    if (!anchor && shown) topRef.current?.scrollIntoView?.({ block: "start" });
  }, [shown, anchor]);

  return (
    <div className={styles.page} ref={topRef}>
      <PanelFrame
        loading={isLoading}
        loadingLabel="Reading the document..."
        empty={readable ? undefined : docEmpty(path, data, error)}
        headerLeft={
          <DetailHeader
            title={readable ? data.title : undefined}
            meta={
              readable ? (
                <>
                  <Caption1>{data.repo}</Caption1>
                  <Caption1>{data.path}</Caption1>
                </>
              ) : undefined
            }
            path={readable && data.file_path ? data.file_path : undefined}
            url={readable ? data.url : undefined}
            refresh={readable ? { onClick: refetch, isFetching } : undefined}
            external={readable ? <DocOpenButton doc={data} /> : undefined}
          />
        }
      >
        {readable && (
          <MarkdownViewer
            content={data.body.trim() || "_This document is empty._"}
            titleAbove={data.title}
            links={links}
            anchor={anchor}
            style={{ marginTop: tokens.spacingVerticalS }}
          />
        )}
      </PanelFrame>
    </div>
  );
}
