import { useState } from "react";
import { useParams } from "react-router";
import {
  Subtitle2,
  Caption1,
  Badge,
  ProgressBar,
  Tooltip,
  makeStyles,
  tokens,
} from "@fluentui/react-components";
import { BackButton } from "../../shared/BackButton";
import { PageCard } from "../../shared/PageCard";
import { MarkdownViewer } from "../../shared/MarkdownViewer";
import { useGetPromptDetailQuery } from "./api.ado";
import { STATUS } from "../../shell/consts";
import { DocumentTextRegular } from "@fluentui/react-icons";
import { EmptyState } from "../../shared/EmptyState";
import { FilePath } from "../../shared/FilePath";
import { CardPictures, imageLine } from "./CardCover";
import { AttachActions, AttachZone } from "./AttachCover";
import { STAMPS } from "../../shell/consts";
import { DesignChip } from "./DesignBindings";

const useStyles = makeStyles({
  page: {
    display: "flex",
    flexDirection: "column",
    gap: tokens.spacingVerticalM,
    width: "100%",
  },
  titleBlock: {
    display: "flex",
    flexDirection: "column" as const,
    gap: "2px",
    minWidth: 0,
  },
  progressRow: {
    display: "flex",
    alignItems: "center",
    gap: tokens.spacingHorizontalS,
  },
  progressBar: {
    width: "120px",
  },
});

function statusColor(status: string): "warning" | "success" | "informative" {
  // State names from consts.json -- see web/src/shell/consts.ts.
  if (status === STATUS.codeReview) return "warning";
  if (status === STATUS.inProgress) return "success";
  return "informative";
}

export function PromptDetailPage() {
  const styles = useStyles();
  const { filename } = useParams<{ filename: string }>();

  const { data, isLoading, isError, refetch } = useGetPromptDetailQuery(filename ?? "", {
    skip: !filename,
  });
  // A picture asked for from the header (Replace cover, Add before): the zone
  // for it is drawn under the pictures until it is attached or cancelled (C2).
  const [asking, setAsking] = useState<"cover" | "before" | null>(null);
  const hasCover = !!data && !!imageLine(data.content, STAMPS.cover);

  return (
    <div className={styles.page}>
      <PageCard
        loading={isLoading}
        loadingLabel="Loading prompt..."
        empty={
          isError ? (
            <EmptyState
              icon={<DocumentTextRegular />}
              tone="error"
              title="Could not open this card"
              detail={
                <>
                  The agent did not answer, or there is no such file: <code>{filename}</code>
                </>
              }
            />
          ) : undefined
        }
        headerLeft={
          <>
            <BackButton />
            {data && (
              <div className={styles.titleBlock}>
                {/* The page's h1: the card's own is dropped below when it says the same. */}
                <Subtitle2 as="h1">{data.title || data.filename}</Subtitle2>
                {/* The file's address, not only its name: this is what goes into a chat. */}
                <FilePath path={data.path} />
                {/* The design it was worked against: its line, resolved by the agent. */}
                <DesignChip design={data.design} />
              </div>
            )}
          </>
        }
        headerRight={
          data ? (
            <>
              {data.total > 0 && (
                <div className={styles.progressRow}>
                  <ProgressBar
                    className={styles.progressBar}
                    aria-label={`${data.checked} of ${data.total} checklist items completed`}
                    value={data.checked / data.total}
                    thickness="large"
                    color={data.checked === data.total ? "success" : "brand"}
                  />
                  <Tooltip
                    content={`${data.checked} of ${data.total} checklist items completed`}
                    relationship="description"
                  >
                    <Caption1 style={{ cursor: "default" }}>{data.progress}</Caption1>
                  </Tooltip>
                </div>
              )}
              <Badge color={statusColor(data.status)} appearance="tint" size="small">
                {data.status}
              </Badge>
              {data.sprint !== "--" && (
                <Caption1 style={{ color: tokens.colorNeutralForeground3 }}>{data.sprint}</Caption1>
              )}
              {/* With a cover: Replace cover, Add before, Delete the cover (C2). */}
              <AttachActions
                filename={data.filename}
                content={data.content}
                onDone={() => void refetch()}
                onAsk={setAsking}
              />
            </>
          ) : undefined
        }
      >
        {/* No cover yet: the drop zone IS the cover's box, under the header, the
            same 16:10 the picture will fill -- nothing jumps when it lands (C2). */}
        {data && !hasCover && (
          <AttachZone
            filename={data.filename}
            content={data.content}
            kind="cover"
            onDone={() => void refetch()}
          />
        )}
        {/* The cover under the header -- or Before and After side by side. */}
        {data && (
          <CardPictures
            cover={data.cover}
            before={data.before}
            content={data.content}
            label={data.name || data.title || data.filename}
          />
        )}
        {/* Asked from the header: a zone for the before, or a replacement cover. */}
        {data && asking && (
          <AttachZone
            filename={data.filename}
            content={data.content}
            kind={asking}
            onDone={() => {
              setAsking(null);
              void refetch();
            }}
            onClose={() => setAsking(null)}
          />
        )}
        {data && (
          <MarkdownViewer
            content={data.content}
            titleAbove={data.title}
            style={{ marginTop: tokens.spacingVerticalS }}
          />
        )}
      </PageCard>
    </div>
  );
}
