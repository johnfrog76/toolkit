/**
 * One 1:1 session, edited: the notes form, the agent-written sections, and the
 * retro send.
 *
 * Routes: /communication/sessions/new and /communication/sessions/:filename.
 *
 * The send is the one piece of this module that was designed and never built.
 * Its rule lives in sendButton.ts, pure and tested, because the only other way
 * to check it is to press a button that posts to a real webhook.
 */
import { useState } from "react";
import { useParams, useNavigate } from "react-router";
import {
  Subtitle2,
  Caption1,
  Body1,
  Badge,
  Button,
  Field,
  Input,
  Spinner,
  Textarea,
  makeStyles,
  tokens,
} from "@fluentui/react-components";
import { ArrowRightRegular, SendRegular } from "@fluentui/react-icons";
import { BackButton } from "../../shared/BackButton";
import { HairlineDivider } from "../../shared/HairlineDivider";
import { MarkdownBlock } from "../../shared/MarkdownBlock";
import { PageCard } from "../../shared/PageCard";
import { useGetEnvQuery } from "../../shell/api";
import { STAMPS } from "../../shell/consts";
import { extractSection, hasContent, sendButtonState } from "./sendButton";
import { sessionPath } from "./paths";
import { CloseMeetingButton } from "./CloseMeeting";
import { nextStageAction, stageOf } from "./stages";
import { FOLDERS } from "../../shell/consts";
import { buildMeetingAgendaParams, commandResultMessage } from "../ado/cliBridge";
import {
  useGetManagerDetailQuery,
  useCreateManagerSessionMutation,
  useUpdateManagerSessionMutation,
  useSendCommsMutation,
  useRunMeetingAgendaMutation,
} from "./api.communication";
import type { CommsSendResponse, EnvWithCommunication } from "./api.communication";
import { PeopleCommunityRegular } from "@fluentui/react-icons";
import { EmptyState } from "../../shared/EmptyState";
import { localToday, nextWeekday } from "../../utility/dates";

function nextThursday(): string {
  return nextWeekday(4);
}

function formatSessionDate(iso: string): string {
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
  form: {
    display: "flex",
    flexDirection: "column",
    gap: tokens.spacingVerticalM,
    marginTop: tokens.spacingVerticalS,
  },
  savedLabel: {
    color: tokens.colorPaletteGreenForeground1,
  },
  footerActions: {
    display: "flex",
    justifyContent: "flex-end",
    alignItems: "center",
    gap: tokens.spacingHorizontalS,
    paddingTop: tokens.spacingVerticalS,
  },
  savingBody: {
    display: "flex",
    justifyContent: "center",
    alignItems: "center",
    padding: tokens.spacingVerticalXL,
  },
  agenticSection: {
    display: "flex",
    flexDirection: "column" as const,
    gap: tokens.spacingVerticalXS,
  },
  agenticLabel: {
    color: tokens.colorNeutralForeground3,
    textTransform: "uppercase" as const,
    letterSpacing: "0.05em",
  },
  sendRow: {
    display: "flex",
    alignItems: "center",
    justifyContent: "space-between",
    gap: tokens.spacingHorizontalM,
  },
  sendBody: {
    display: "flex",
    flexDirection: "column" as const,
    gap: "2px",
    minWidth: 0,
  },
  stageRow: {
    display: "flex",
    alignItems: "center",
    justifyContent: "space-between",
    gap: tokens.spacingHorizontalM,
    flexWrap: "wrap" as const,
  },
});

export function ManagerSessionPage() {
  const styles = useStyles();
  const { filename } = useParams<{ filename: string }>();
  const navigate = useNavigate();
  const isNew = !filename || filename === "new";

  const { data, isLoading, isError } = useGetManagerDetailQuery(filename ?? "", {
    skip: isNew,
  });

  const [create, { isLoading: creating }] = useCreateManagerSessionMutation();
  const [update, { isLoading: updating }] = useUpdateManagerSessionMutation();
  const [sendComms, { isLoading: sending }] = useSendCommsMutation();
  const [runMeetingAgenda, { isLoading: advancing }] = useRunMeetingAgendaMutation();
  const { data: env } = useGetEnvQuery();

  const [sessionDate, setSessionDate] = useState(nextThursday);
  const [since, setSince] = useState("");
  const [forward, setForward] = useState("");
  const [retro, setRetro] = useState("");
  const [saved, setSaved] = useState(false);
  const [error, setError] = useState<string | null>(null);
  // The send's outcome, and -- separately -- whether the file recorded it. Two
  // requests, two answers: a send that landed and a write-back that did not is
  // "sent; could not record it", never "error", which is what invites pressing
  // it again.
  const [sendOutcome, setSendOutcome] = useState<
    (CommsSendResponse & { recorded?: "ok" | "failed" }) | null
  >(null);

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
    setError(null);
    try {
      if (isNew) {
        const result = await create({ date: sessionDate, since, forward, retro }).unwrap();
        navigate(sessionPath(result.filename), { replace: true });
      } else {
        await update({ filename: filename!, since, forward, retro }).unwrap();
        setSaved(true);
        setTimeout(() => setSaved(false), 2000);
      }
    } catch {
      setError("Failed to save. Check that the date is valid and try again.");
    }
  };

  // -- The retro send ------------------------------------------------------
  //
  // What goes out is the Agenda section and nothing else. The Retro holds a
  // self-assessment, which is private reflection rather than a manager-facing
  // note, and a send that took "the session" would post it.
  //
  // Afterwards the file records that it happened -- not a tracker, not this
  // component's state. That is the same premise the whole store rests on: if it
  // is not in the file, it did not happen.
  const send = sendButtonState((env as EnvWithCommunication | undefined)?.communication, data);

  const handleSend = async () => {
    if (!data || !filename) return;
    setSendOutcome(null);
    const agenda = extractSection(data.content, "Agenda");

    // 1. The send. The engine never throws, so a throw here means the request
    //    itself did not land -- the agent is down, or the module was switched
    //    off between the page loading and the click. Nothing was posted.
    let outcome: CommsSendResponse;
    try {
      outcome = await sendComms({
        caller: "ManagerSessionPage",
        recipient: send.recipient,
        subject: data.title,
        sections: [{ heading: "Agenda", body: agenda }],
        tone: "personal",
      }).unwrap();
    } catch {
      setSendOutcome({ status: "error", detail: "Could not reach the agent. Nothing was sent." });
      return;
    }
    if (outcome.status !== "ok") {
      setSendOutcome(outcome);
      return;
    }

    // 2. The record. A separate request with a separate answer: the message is
    //    with the manager whatever happens here, so a failure is reported as
    //    exactly that -- sent, and not written down -- and the button, which
    //    reads ## Sent, stays enabled only because the file does not say.
    const today = localToday();
    try {
      await update({
        filename,
        since,
        forward,
        retro,
        append_sent: `${STAMPS.sent} manager: ${today}`,
      }).unwrap();
      setSendOutcome({ ...outcome, recorded: "ok" });
    } catch {
      setSendOutcome({ ...outcome, recorded: "failed" });
    }
  };

  // -- The stage -----------------------------------------------------------
  //
  // MeetingAgenda -Plan / -Prep / -Retro, through the bridge, from here. The
  // verb stamps ## Stage; this page only asks. Only the stage AHEAD is offered
  // (stages.ts says which), and the notes are saved FIRST: the stamp re-reads
  // the file, and a stamp over unsaved notes would put the form's text a step
  // behind the file it is editing.
  const [stageMessage, setStageMessage] = useState<string | null>(null);
  const stageAction = isNew ? null : nextStageAction(data?.session_stage, data?.folder);

  const handleAdvance = async () => {
    if (!data || !filename || !stageAction || !data.date) return;
    setStageMessage(null);
    try {
      await update({ filename, since, forward, retro }).unwrap();
    } catch {
      setStageMessage("Could not save the notes first. Nothing was stamped.");
      return;
    }
    try {
      const result = await runMeetingAgenda({
        params: buildMeetingAgendaParams({
          date: data.date,
          series: data.series,
          action: stageAction,
        }),
      }).unwrap();
      if (result.status !== "success") setStageMessage(commandResultMessage(result, "Stamped."));
    } catch {
      setStageMessage("Could not reach the agent. Nothing was stamped.");
    }
  };

  const isBusy = creating || updating;
  const sessionStage = isNew ? "draft" : (data?.session_stage ?? "draft");
  const isRetroStage = sessionStage === "prep" || sessionStage === "retro";
  const isClosed = !isNew && data?.folder === FOLDERS.archive;
  const stage = stageOf(sessionStage);
  const stageLabel = stage.label;
  const badgeColor = stage.color;
  // The date comes from the record, not from its filename: a series' file carries
  // its name in front of the date.
  const dateIso = isNew ? sessionDate : (data?.date ?? "");
  const title = `${data?.series || "1:1"} — ${dateIso ? formatSessionDate(dateIso) : ""}`;

  const agendaContent = data ? extractSection(data.content, "Agenda") : "";
  const prepContent = data ? extractSection(data.content, "Prep") : "";
  const retroContent = data ? extractSection(data.content, "Retro") : "";
  const showAgenda = hasContent(agendaContent);
  const showPrep = hasContent(prepContent);
  const showRetro = isRetroStage && retroContent.includes("**Summary**");

  return (
    <div className={styles.page}>
      <PageCard
        loading={isLoading}
        loadingLabel="Loading session..."
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
        headerLeft={
          <>
            <BackButton />
            <Badge color={badgeColor} appearance="outline" size="small">
              {stageLabel}
            </Badge>
            <Subtitle2 as="h1">{title}</Subtitle2>
          </>
        }
      >
        {isBusy ? (
          <div className={styles.savingBody}>
            <Spinner size="medium" label="Saving…" />
          </div>
        ) : (
          <div className={styles.form}>
            {/* User input fields — conditional on stage */}
            {isNew && (
              <Field label="Session date">
                <Input
                  type="date"
                  value={sessionDate}
                  onChange={(_, d) => setSessionDate(d.value)}
                />
              </Field>
            )}

            {!isRetroStage && (
              <>
                <Field label="Since last session">
                  <Textarea
                    rows={5}
                    resize="vertical"
                    value={since}
                    onChange={(_, d) => setSince(d.value)}
                    placeholder="What's happened since your last session — work completed, progress made, context shifts."
                  />
                </Field>
                <Field label="Unresolved / forward">
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
              <Field label="Post-meeting notes">
                <Textarea
                  rows={8}
                  resize="vertical"
                  value={retro}
                  onChange={(_, d) => setRetro(d.value)}
                  placeholder="What got covered. What didn't. Commitments on both sides. How you showed up."
                />
              </Field>
            )}

            {/* Agentic content — rendered as markdown, shown only when content exists */}
            {showRetro && (
              <div className={styles.agenticSection}>
                <Caption1 className={styles.agenticLabel}>Retro</Caption1>
                <MarkdownBlock>{retroContent}</MarkdownBlock>
              </div>
            )}

            {showAgenda && (
              <div className={styles.agenticSection}>
                <Caption1 className={styles.agenticLabel}>Agenda</Caption1>
                <MarkdownBlock>{agendaContent}</MarkdownBlock>
              </div>
            )}

            {showPrep && (
              <div className={styles.agenticSection}>
                <Caption1 className={styles.agenticLabel}>Prep</Caption1>
                <MarkdownBlock>{prepContent}</MarkdownBlock>
              </div>
            )}

            {error && (
              <Caption1 style={{ color: tokens.colorPaletteRedForeground1 }}>{error}</Caption1>
            )}

            {!isNew && data && (
              <>
                <HairlineDivider />
                <div className={styles.stageRow}>
                  <div className={styles.sendBody}>
                    <Body1>
                      {isClosed
                        ? "Closed"
                        : stageAction
                          ? `Next up: ${stageAction}`
                          : "Complete — close it to move it to the archive"}
                    </Body1>
                    <Caption1 style={{ color: tokens.colorNeutralForeground3 }}>
                      {isClosed
                        ? "A closed session is the record. It is read here, not changed."
                        : stageAction
                          ? "Saves your notes, then stamps the stage in the file -- the same thing the terminal's MeetingAgenda does."
                          : "Moves the file to the archive and stamps the date it closed."}
                    </Caption1>
                    {stageMessage && (
                      <Caption1
                        role="alert"
                        style={{
                          color: tokens.colorPaletteRedForeground1,
                          whiteSpace: "pre-wrap",
                        }}
                      >
                        {stageMessage}
                      </Caption1>
                    )}
                  </div>
                  {stageAction && data.date && (
                    <Button
                      appearance="secondary"
                      size="small"
                      icon={<ArrowRightRegular />}
                      disabled={advancing || updating}
                      onClick={handleAdvance}
                    >
                      {advancing ? "Stamping\u2026" : stageAction}
                    </Button>
                  )}
                  {!isClosed && !stageAction && data.date && (
                    <CloseMeetingButton
                      filename={data.filename}
                      date={data.date}
                      series={data.series}
                    />
                  )}
                </div>
              </>
            )}

            {send.shown && (
              <>
                <HairlineDivider />
                <div className={styles.sendRow}>
                  <div className={styles.sendBody}>
                    <Body1>Send the agenda to your manager</Body1>
                    {/* A disabled button that says WHY. The alternative is a
                        live button that fails on click and only then mentions
                        an environment variable. */}
                    {!send.enabled && (
                      <Caption1 style={{ color: tokens.colorNeutralForeground3 }}>
                        {send.reason}
                      </Caption1>
                    )}
                    {sendOutcome && (
                      <Caption1
                        role="status"
                        style={{
                          color:
                            sendOutcome.status === "ok" && sendOutcome.recorded !== "failed"
                              ? tokens.colorPaletteGreenForeground1
                              : sendOutcome.status === "ok"
                                ? tokens.colorPaletteDarkOrangeForeground1
                                : tokens.colorPaletteRedForeground1,
                        }}
                      >
                        {sendOutcome.recorded === "failed"
                          ? `sent; could not record it. ${sendOutcome.detail} The message reached ${send.recipient}, but "${STAMPS.sent} manager: ${localToday()}" could not be written under ## Sent -- add it by hand before sending again.`
                          : `${sendOutcome.status}: ${sendOutcome.detail}`}
                      </Caption1>
                    )}
                  </div>
                  <Button
                    appearance="secondary"
                    size="small"
                    icon={<SendRegular />}
                    disabled={!send.enabled || sending}
                    onClick={handleSend}
                  >
                    {sending ? "Sending\u2026" : "Send"}
                  </Button>
                </div>
              </>
            )}

            <HairlineDivider />
            <div className={styles.footerActions}>
              {saved && <Caption1 className={styles.savedLabel}>Saved</Caption1>}
              <Button appearance="secondary" size="small" onClick={() => navigate(-1)}>
                Cancel
              </Button>
              <Button
                appearance="primary"
                size="small"
                onClick={handleSave}
                disabled={isClosed}
                title={
                  isClosed ? "A closed session is the record and is not edited here" : undefined
                }
              >
                Save
              </Button>
            </div>
          </div>
        )}
      </PageCard>
    </div>
  );
}
