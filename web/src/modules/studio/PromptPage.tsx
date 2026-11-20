import { useState } from "react";
import { useParams } from "react-router";
import { Badge, Caption1, Link, Subtitle2, makeStyles, tokens } from "@fluentui/react-components";
import { SparkleRegular } from "@fluentui/react-icons";
import { BackButton } from "../../shared/BackButton";
import { CardActions, ROW } from "../../shared/CardActions";
import { copyText } from "../../shared/copyText";
import { EmptyState } from "../../shared/EmptyState";
import { FilePath } from "../../shared/FilePath";
import { MarkdownViewer } from "../../shared/MarkdownViewer";
import { PanelFrame } from "../../shared/PanelFrame";
import { RefreshButton } from "../../shared/RefreshButton";
import { useGetPromptQuery } from "./api.studio";
import { promptReference } from "./PromptsCard";
import { groupLabel, senderLabel, workflowLabel } from "./prompts";

// The reading room for ONE agentic prompt -- the house's reading page,
// the frame a hub design is read in (DesignNotePage): PanelFrame, the back arrow
// and the name on the left, compact controls on the right, the file's address,
// and ONE MarkdownViewer. Read-only: a prompt is changed in its file.
//
// The card's row carries the record (title, purpose, owner, category); the
// detail is here: the category again beside whose it is, who sends it, the
// add-on, the ways of working, what it drives, when it changed, and whether a
// copy of yours runs instead of ToolKit's.
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
  copied: { color: tokens.colorPaletteGreenForeground1 },
});

export function PromptPage() {
  const styles = useStyles();
  // The address is the row's ref: a shipped prompt's name, yours/<name>, or space/<name>.
  const params = useParams();
  const ref = params["*"] ?? "";
  const { data, isLoading, isFetching, error, refetch } = useGetPromptQuery(ref);
  const readable = !!data && !error;
  const [copied, setCopied] = useState<"prompt" | "reference" | null>(null);
  const copy = async () => {
    if (!data) return;
    await copyText(data.body);
    setCopied("prompt");
  };

  const missing = error && "status" in error && error.status === 404;
  const detail =
    error && "data" in error && typeof (error.data as { detail?: unknown })?.detail === "string"
      ? (error.data as { detail: string }).detail
      : null;
  const empty = readable ? undefined : (
    <EmptyState
      icon={<SparkleRegular />}
      tone="error"
      title={missing ? `No prompt ${ref}` : "Could not open this prompt"}
      detail={
        missing
          ? detail || "It is not in agentic/, in your hub's, or in the Space's repository."
          : "The agent did not answer. Nothing was read."
      }
    />
  );

  return (
    <div className={styles.page}>
      <PanelFrame
        loading={isLoading}
        loadingLabel="Reading the prompt..."
        empty={empty}
        headerLeft={
          <>
            <BackButton />
            {readable && (
              <div className={styles.titleBlock}>
                <Subtitle2 as="h1">{data.title || data.name}</Subtitle2>
                <div className={styles.metaRow}>
                  <Badge
                    appearance="tint"
                    size="small"
                    color={data.group === "toolkit" ? "brand" : "informative"}
                  >
                    {groupLabel(data.group)}
                  </Badge>
                  <Badge appearance="tint" size="small" color="subtle">
                    {data.category}
                  </Badge>
                  <Badge appearance="outline" size="small" color="informative">
                    {senderLabel(data)}
                  </Badge>
                  {data.module !== "core" ? <Caption1>{data.module}</Caption1> : null}
                  {data.workflows.length > 0 ? (
                    <Caption1>
                      for working {data.workflows.map((w) => workflowLabel(w)).join(", ")}
                    </Caption1>
                  ) : null}
                  {data.drives ? <Caption1>drives {data.drives}</Caption1> : null}
                  {data.changed ? (
                    data.history ? (
                      <Link
                        appearance="subtle"
                        href={data.history}
                        target="_blank"
                        rel="noopener noreferrer"
                      >
                        <Caption1>changed {data.changed}</Caption1>
                      </Link>
                    ) : (
                      <Caption1>changed {data.changed}</Caption1>
                    )
                  ) : null}
                  {data.overrides ? (
                    <Caption1>runs instead of ToolKit&apos;s on this machine</Caption1>
                  ) : null}
                </div>
              </div>
            )}
          </>
        }
        headerRight={
          readable ? (
            <>
              {copied ? <Caption1 className={styles.copied}>Copied the {copied}</Caption1> : null}
              <CardActions
                primaryAction={ROW.copy.action({ detail: "prompt", onClick: () => void copy() })}
                menuLabel={`Actions for ${data.name}`}
                secondaryActions={[
                  ROW.copy.action({
                    detail: "reference",
                    onClick: () => {
                      void copyText(promptReference(data)).then(() => setCopied("reference"));
                    },
                  }),
                ]}
              />
              <RefreshButton onClick={refetch} isFetching={isFetching} />
            </>
          ) : undefined
        }
      >
        {readable && (
          <>
            <FilePath
              path={data.file_path}
              what={data.group === "space" ? "file link" : "file path"}
            />
            <MarkdownViewer
              content={data.body}
              titleAbove={data.title || data.name}
              style={{ marginTop: tokens.spacingVerticalS }}
            />
          </>
        )}
      </PanelFrame>
    </div>
  );
}
