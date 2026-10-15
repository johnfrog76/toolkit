/**
 * One 1:1 session, read: the agent-written agenda, prep and retro rendered, and
 * a dialog for the notes the person owns.
 *
 * Route: /communication/1on1/:filename. It moved off the /growth prefix with
 * the rest of the module; the old path redirects.
 */
import { useState } from "react";
import { useNavigate, useParams } from "react-router";
import {
  Subtitle2,
  Caption1,
  Badge,
  Button,
  Spinner,
  Dialog,
  DialogSurface,
  DialogBody,
  DialogTitle,
  DialogContent,
  DialogActions,
  DialogTrigger,
  Field,
  Textarea,
  makeStyles,
  tokens,
} from "@fluentui/react-components";
import { EditRegular, SendRegular, SparkleFilled } from "@fluentui/react-icons";
import { DialogDismiss } from "../../shared/DialogDismiss";
import { BackButton } from "../../shared/BackButton";
import { PageCard } from "../../shared/PageCard";
import { RefreshButton } from "../../shared/RefreshButton";
import { MarkdownViewer } from "../../shared/MarkdownViewer";
import { useGetEnvQuery } from "../../shell/api";
import { Timer } from "./Timer";
import { sessionPath } from "./paths";
import { extractSection, hasContent } from "./sendButton";
import { CloseMeetingButton } from "./CloseMeeting";
import { stageAfter, stageOf } from "./stages";
import { FOLDERS } from "../../shell/consts";
import {
  useGetManagerDetailQuery,
  useUpdateManagerSessionMutation,
  useRewriteTextMutation,
} from "./api.communication";
import { PeopleCommunityRegular } from "@fluentui/react-icons";
import { EmptyState } from "../../shared/EmptyState";
import { FilePath } from "../../shared/FilePath";

type RewriteField = "since" | "forward" | "retro";

function parseSessionStage(content: string) {
  const m = content.match(/^## Stage\s*\n(\w+)/m);
  return stageOf(m?.[1]?.toLowerCase());
}

function formatSessionDate(filename: string): string {
  const iso = filename.replace(/\.md$/, "");
  const [year, month, day] = iso.split("-").map(Number);
  return new Date(year, month - 1, day).toLocaleDateString("en-US", {
    weekday: "long",
    month: "long",
    day: "numeric",
  });
}

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
  dialogFields: {
    display: "flex",
    flexDirection: "column" as const,
    gap: tokens.spacingVerticalM,
    paddingTop: tokens.spacingVerticalS,
  },
  fieldLabelRow: {
    display: "flex",
    alignItems: "center",
    justifyContent: "space-between",
    width: "100%",
  },
});

export function ManagerDetailPage() {
  const styles = useStyles();
  const { filename } = useParams<{ filename: string }>();
  const navigate = useNavigate();

  const { data, isLoading, isFetching, isError, refetch } = useGetManagerDetailQuery(
    filename ?? "",
    {
      skip: !filename,
    },
  );
  const [update, { isLoading: saving }] = useUpdateManagerSessionMutation();
  const [rewrite] = useRewriteTextMutation();
  const { data: env } = useGetEnvQuery();
  const rewriteAvailable = env?.anthropicConfigured ?? false;

  const [dialogOpen, setDialogOpen] = useState(false);
  const [since, setSince] = useState("");
  const [forward, setForward] = useState("");
  const [retro, setRetro] = useState("");
  const [rewriting, setRewriting] = useState<RewriteField | null>(null);
  const [rewriteError, setRewriteError] = useState<Partial<Record<RewriteField, string>>>({});

  // The fields are seeded from each new read of the session, while rendering,
  // so the form never paints a frame of the previous read's text.
  const [seededFrom, setSeededFrom] = useState<typeof data>(undefined);
  if (data && data !== seededFrom) {
    setSeededFrom(data);
    setSince(data.since ?? "");
    setForward(data.forward ?? "");
    const raw = data.retro_input ?? "";
    setRetro(raw.includes("**Summary**") ? "" : raw);
  }

  const handleSave = async () => {
    try {
      await update({ filename: filename!, since, forward, retro }).unwrap();
      setDialogOpen(false);
    } catch {}
  };

  const fieldValue = { since, forward, retro };
  const fieldSetter = { since: setSince, forward: setForward, retro: setRetro };

  const handleRewrite = async (field: RewriteField) => {
    const text = fieldValue[field];
    if (!text.trim()) return;
    setRewriting(field);
    setRewriteError((e) => ({ ...e, [field]: undefined }));
    try {
      const result = await rewrite({ text }).unwrap();
      fieldSetter[field](result.text);
    } catch (err) {
      const detail = (err as { data?: { detail?: string } })?.data?.detail;
      setRewriteError((e) => ({ ...e, [field]: detail || "Rewrite failed" }));
    } finally {
      setRewriting(null);
    }
  };

  const rewriteButton = (field: RewriteField) => {
    if (!rewriteAvailable) return null;
    return (
      <Button
        icon={rewriting === field ? <Spinner size="tiny" /> : <SparkleFilled />}
        size="small"
        appearance="subtle"
        title="Magic rewrite — fix typos, tidy into bullets"
        disabled={rewriting !== null || !fieldValue[field].trim()}
        onClick={() => handleRewrite(field)}
      />
    );
  };

  // Every file this route serves is a session. The workflow-prompt records it
  // used to also render lived at the hub's manager/ root and are retired; the
  // session shape is documented in the toolkit now, not in the store.
  const sessionStage = data ? parseSessionStage(data.content) : null;
  // The date is a field on the record, not parsed from the filename, which for a
  // series carries the series in front (docs/modules/communication.md, "The file shape, and how a session's state is read").
  const sessionDate = data?.date ? formatSessionDate(data.date) : null;
  const isRetroStage = sessionStage?.key === "prep" || sessionStage?.key === "retro";
  const nextStage = sessionStage ? stageAfter(sessionStage.key) : null;
  const isClosed = data?.folder === FOLDERS.archive;

  return (
    <div className={styles.page}>
      <PageCard
        loading={isLoading}
        loadingLabel="Loading the meeting..."
        empty={
          isError ? (
            <EmptyState
              icon={<PeopleCommunityRegular />}
              tone="error"
              title="Could not open this meeting"
              detail={
                <>
                  The agent did not answer, or there is no such file: <code>{filename}</code>
                </>
              }
            />
          ) : undefined
        }
        headerRight={
          <>
            <Timer />
            {data && (
              <Button
                icon={<EditRegular />}
                size="small"
                appearance="subtle"
                title={isRetroStage ? "Add retro notes" : "Edit plan notes"}
                onClick={() => setDialogOpen(true)}
              />
            )}
            {/* The session page: the notes form, and the retro send. This read
                view is where the card's row lands, and once nothing
                on it led to the page the send button is on. */}
            {data && filename && (
              <Button
                icon={<SendRegular />}
                size="small"
                appearance="subtle"
                onClick={() => navigate(sessionPath(filename))}
              >
                Edit / send
              </Button>
            )}
            {/* Complete and still open: the one step left is to close it, and it
                is done here rather than in a terminal. */}
            {data && data.date && !isClosed && !nextStage && (
              <CloseMeetingButton filename={data.filename} date={data.date} series={data.series} />
            )}
            <RefreshButton onClick={refetch} isFetching={isFetching} />
          </>
        }
        headerLeft={
          <>
            <BackButton />
            {data && sessionStage && (
              <>
                <Badge color={sessionStage.color} appearance="outline" size="small">
                  {sessionStage.label}
                </Badge>
                <div className={styles.titleBlock}>
                  <Subtitle2 as="h1">
                    {data.series || "1:1"} — {sessionDate}
                  </Subtitle2>
                  <Caption1 style={{ color: tokens.colorNeutralForeground3 }}>
                    {/* Closing is MeetingAgenda -Close -- the verb that moves the file
                        to manager/archive/ AND writes the closed stamp -- and now
                        the Close button in the header runs it through the
                        bridge. This line used to name the CLI command instead. */}
                    {isClosed
                      ? "Closed"
                      : nextStage
                        ? `Next up: ${nextStage.label}`
                        : "Complete — close it to move it to the archive"}
                  </Caption1>
                  {/* The Carried-from check, said once and never rewritten
                      (docs/hub/manager.md, "Which session a record carries from"):
                      the agent's sentence, only for a verdict that is not ok. */}
                  {data.carried_from_verdict &&
                    data.carried_from_verdict !== "ok" &&
                    data.carried_from_note && (
                      <Caption1 style={{ color: tokens.colorNeutralForeground3 }}>
                        {data.carried_from_note}
                      </Caption1>
                    )}
                  <FilePath path={data.path} />
                </div>
              </>
            )}
          </>
        }
      >
        {data &&
          (() => {
            const agendaContent = extractSection(data.content, "Agenda");
            const prepContent = extractSection(data.content, "Prep");
            const retroContent = extractSection(data.content, "Retro");
            const showAgenda = hasContent(agendaContent);
            const showPrep = hasContent(prepContent);
            const showRetro = hasContent(retroContent) && retroContent.includes("**Summary**");

            const parts: string[] = [];
            if (showAgenda) parts.push(`## Agenda\n\n${agendaContent}`);
            if (showPrep) parts.push(`## Prep\n\n${prepContent}`);
            if (showRetro) parts.push(`## Retro\n\n${retroContent}`);
            const filtered = parts.join("\n\n---\n\n");

            return filtered ? (
              <MarkdownViewer content={filtered} style={{ marginTop: tokens.spacingVerticalS }} />
            ) : (
              <Caption1
                style={{
                  color: tokens.colorNeutralForeground3,
                  marginTop: tokens.spacingVerticalS,
                }}
              >
                No content yet — run the agent to generate the agenda.
              </Caption1>
            );
          })()}
      </PageCard>

      {data && (
        <Dialog open={dialogOpen} onOpenChange={(_e, d) => setDialogOpen(d.open)}>
          <DialogSurface>
            <DialogBody>
              <DialogTitle action={<DialogDismiss />}>
                Manager 1:1 — {sessionDate ?? ""}
              </DialogTitle>
              <DialogContent>
                <div className={styles.dialogFields}>
                  {!isRetroStage && (
                    <>
                      <Field
                        label={{
                          children: (
                            <span className={styles.fieldLabelRow}>
                              Since last session
                              {rewriteButton("since")}
                            </span>
                          ),
                        }}
                        validationState={rewriteError.since ? "error" : "none"}
                        validationMessage={rewriteError.since}
                      >
                        <Textarea
                          rows={5}
                          resize="vertical"
                          value={since}
                          onChange={(_, d) => setSince(d.value)}
                          placeholder="What's happened since your last session — work completed, progress made, context shifts."
                        />
                      </Field>
                      <Field
                        label={{
                          children: (
                            <span className={styles.fieldLabelRow}>
                              Unresolved / forward
                              {rewriteButton("forward")}
                            </span>
                          ),
                        }}
                        validationState={rewriteError.forward ? "error" : "none"}
                        validationMessage={rewriteError.forward}
                      >
                        <Textarea
                          rows={4}
                          resize="vertical"
                          value={forward}
                          onChange={(_, d) => setForward(d.value)}
                          placeholder="Anything unresolved or carrying tension. One thing you're thinking about beyond the current sprint."
                        />
                      </Field>
                    </>
                  )}
                  {isRetroStage && (
                    <Field
                      label={{
                        children: (
                          <span className={styles.fieldLabelRow}>
                            Post-meeting notes
                            {rewriteButton("retro")}
                          </span>
                        ),
                      }}
                      validationState={rewriteError.retro ? "error" : "none"}
                      validationMessage={rewriteError.retro}
                    >
                      <Textarea
                        rows={8}
                        resize="vertical"
                        value={retro}
                        onChange={(_, d) => setRetro(d.value)}
                        placeholder="What got covered. What didn't. Commitments on both sides. How you showed up."
                      />
                    </Field>
                  )}
                </div>
              </DialogContent>
              <DialogActions>
                <DialogTrigger disableButtonEnhancement>
                  <Button appearance="secondary">Cancel</Button>
                </DialogTrigger>
                <Button appearance="primary" onClick={handleSave} disabled={saving}>
                  {saving ? "Saving…" : "Save"}
                </Button>
              </DialogActions>
            </DialogBody>
          </DialogSurface>
        </Dialog>
      )}
    </div>
  );
}
