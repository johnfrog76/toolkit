import { useMemo } from "react";
import { Link } from "react-router";
import { Badge, Caption1, Subtitle2, makeStyles, tokens } from "@fluentui/react-components";
import { BookOpenRegular } from "@fluentui/react-icons";
import { useGetDocQuery, useGetDocsQuery } from "./api.ado";
import type { DocEntry } from "./api.ado";
import { DocControls, docEmpty } from "./DocsDocPage";
import { docsRoomPath, repoLinkBase } from "./docRooms";
import { CardSpinner } from "../../shared/CardSpinner";
import { EmptyState } from "../../shared/EmptyState";
import { MarkdownViewer } from "../../shared/MarkdownViewer";
import { PageCard } from "../../shared/PageCard";
import { ALL, docMatches, filterSummary, useDocsFilters } from "./docFilters";

// The Docs tab (D-S12): what the product IS, beside Design's what it
// will be. It lands on the repo's README, rendered in the reading room -- the
// README's relative links are the drawers -- with the docs/ tree folded above
// it as the fallback index, for a repo whose README does not link everything.
// Folded, so opening it moves nothing until it is asked for.
const useStyles = makeStyles({
  titleBlock: {
    display: "flex",
    flexDirection: "column",
    rowGap: tokens.spacingVerticalXS,
    minWidth: 0,
  },
  meta: { color: tokens.colorNeutralForeground3 },
  tree: {
    marginTop: tokens.spacingVerticalS,
    marginBottom: tokens.spacingVerticalS,
    "& summary": { cursor: "pointer", color: tokens.colorNeutralForeground2 },
  },
  list: {
    listStyleType: "none",
    margin: 0,
    padding: `${tokens.spacingVerticalXS} 0 0 ${tokens.spacingHorizontalM}`,
    display: "flex",
    flexDirection: "column",
    rowGap: tokens.spacingVerticalXXS,
    fontSize: tokens.fontSizeBase200,
  },
  link: {
    color: tokens.colorBrandForeground1,
    textDecoration: "none",
    "&:hover": { textDecoration: "underline" },
  },
});

/** The docs/ tree as a folded list: every document, by path, each a room link. */
export function DocsTree({ items }: { items: DocEntry[] }) {
  const styles = useStyles();
  // The drawer's filters narrow THIS list and nothing else -- not the
  // README under it. The tree stays as folded as the person left it, so
  // filtering moves nothing; the count says how many are shown, and an empty
  // result says so inside the tree.
  const { text, folder } = useDocsFilters();
  const shown = items.filter((d) => docMatches(d, text, folder));
  const filtered = folder !== ALL || text.trim() !== "";
  if (items.length === 0) return null;
  return (
    <details className={styles.tree}>
      <summary>
        Everything under docs/{" "}
        <Badge appearance="tint" size="small">
          {filtered ? `${shown.length} of ${items.length}` : items.length}
        </Badge>
      </summary>
      {filtered && shown.length === 0 ? (
        <Caption1 role="status">No documents match the filters.</Caption1>
      ) : null}
      <ul className={styles.list}>
        {shown.map((d) => (
          <li key={d.path} style={{ paddingLeft: `${(d.path.split("/").length - 2) * 16}px` }}>
            <Link className={styles.link} to={docsRoomPath(d.path)}>
              {d.path}
            </Link>
          </li>
        ))}
      </ul>
    </details>
  );
}

export function DocsLanding() {
  const styles = useStyles();
  const list = useGetDocsQuery();
  const readmePath = list.data?.readme?.path ?? "";
  const doc = useGetDocQuery(readmePath, { skip: !readmePath });
  const items = list.data?.items ?? [];
  const data = doc.data;
  const readable = !!data && data.supported && !data.reason && !doc.error;
  const links = useMemo(
    () => (data && readable ? repoLinkBase(data.path, data.url, data.issues ?? "") : undefined),
    [readable, data],
  );
  const icon = <BookOpenRegular />;
  const { text, folder } = useDocsFilters();
  const summary = filterSummary(folder === ALL ? undefined : `${folder}/`, text);

  // A refused address (400) says its own sentence: the agent's detail.
  const refused =
    list.error && "status" in list.error && list.error.status === 400
      ? ((list.error.data as { detail?: string } | undefined)?.detail ??
        "This Space's address names no repository.")
      : null;
  const loading = list.isLoading || doc.isLoading;
  const listEmpty = loading ? undefined : refused ? (
    <EmptyState icon={icon} tone="error" title="No repository to read" detail={refused} />
  ) : list.error ? (
    <EmptyState
      icon={icon}
      tone="error"
      title="Could not read the docs"
      detail="GitHub did not answer. Nothing was read."
    />
  ) : list.data && !list.data.supported ? (
    <EmptyState
      icon={icon}
      title="No docs in this Space"
      detail="The Docs tab reads a GitHub repo's README.md and docs/."
    />
  ) : list.data?.reason ? (
    <EmptyState
      icon={icon}
      tone="error"
      title="Could not read the docs"
      detail={list.data.reason}
    />
  ) : list.data && !list.data.readme && items.length === 0 ? (
    <EmptyState
      icon={icon}
      title="No README.md or docs/ yet"
      detail={`${list.data.repo || "The repo"} has neither -- a README.md shows up here, and every document under docs/ beside it.`}
    />
  ) : undefined;
  const readmeEmpty =
    !listEmpty && readmePath && !loading && !readable
      ? docEmpty(readmePath, data, doc.error)
      : undefined;
  const refetch = () => {
    list.refetch();
    if (readmePath) doc.refetch();
  };

  return (
    <PageCard
      loading={loading}
      loadingLabel="Reading the README..."
      empty={listEmpty}
      headerLeft={
        <>
          {icon}
          <div className={styles.titleBlock}>
            <Subtitle2>{readable ? data.title : "Docs"}</Subtitle2>
            {list.data?.repo ? <Caption1 className={styles.meta}>{list.data.repo}</Caption1> : null}
            {summary ? <Caption1 className={styles.meta}>{summary}</Caption1> : null}
          </div>
        </>
      }
      headerRight={
        readable ? (
          <DocControls
            doc={data}
            refetch={refetch}
            isFetching={list.isFetching || doc.isFetching}
          />
        ) : undefined
      }
    >
      <DocsTree items={items} />
      {readable ? (
        <MarkdownViewer
          content={data.body.trim() || "_This README is empty._"}
          titleAbove={data.title}
          links={links}
        />
      ) : list.isFetching || doc.isFetching ? (
        <CardSpinner label="Reading the README..." />
      ) : (
        (readmeEmpty ?? null)
      )}
    </PageCard>
  );
}
