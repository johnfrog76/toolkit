import { useParams } from "react-router";
import { Badge, Caption1, Subtitle2, makeStyles, tokens } from "@fluentui/react-components";
import { BookRegular } from "@fluentui/react-icons";
import { BackButton } from "../../shared/BackButton";
import { EmptyState } from "../../shared/EmptyState";
import { FilePath } from "../../shared/FilePath";
import { MarkdownViewer } from "../../shared/MarkdownViewer";
import { PanelFrame } from "../../shared/PanelFrame";
import { RefreshButton } from "../../shared/RefreshButton";
import { useGetReferenceDocumentQuery } from "./api.organize";

// The reading room for ONE reference document, read only: the house's reading
// page -- PanelFrame, the back arrow and the title on the left, the refresh on
// the right, ONE MarkdownViewer. The document is read as it is filed; there is
// nothing here that writes (docs/modules/organize.md, "Reference").
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

export function ReferencePage() {
  const styles = useStyles();
  const { name = "" } = useParams();
  const { data, isLoading, isFetching, error, refetch } = useGetReferenceDocumentQuery(name);
  const readable = !!data && !error;
  const missing = error && "status" in error && error.status === 404;

  const empty = readable ? undefined : (
    <EmptyState
      icon={<BookRegular />}
      title={missing ? `No reference document ${name}` : "Could not open this document"}
      detail={
        missing
          ? "It is not in the hub's reference folder -- it may have been moved or renamed."
          : "The agent did not answer. Nothing was read."
      }
    />
  );

  return (
    <div className={styles.page}>
      <PanelFrame
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
                  <Badge appearance="tint" size="small" color="informative">
                    reference
                  </Badge>
                  {data.valid ? <Caption1>Valid: {data.valid}</Caption1> : null}
                  {data.source ? <Caption1>Source: {data.source}</Caption1> : null}
                </div>
                <FilePath path={data.path} />
              </div>
            )}
          </>
        }
        headerRight={
          readable ? <RefreshButton onClick={refetch} isFetching={isFetching} /> : undefined
        }
      >
        {readable && (
          <MarkdownViewer
            content={data.body}
            titleAbove={data.title}
            style={{ marginTop: tokens.spacingVerticalS }}
          />
        )}
      </PanelFrame>
    </div>
  );
}
