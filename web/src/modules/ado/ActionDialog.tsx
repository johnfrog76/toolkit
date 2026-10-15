import { useId, useState, useEffect, useRef } from "react";
import {
  Dialog,
  DialogSurface,
  DialogBody,
  DialogTitle,
  DialogContent,
  DialogActions,
  Body1,
  Button,
  Input,
  Textarea,
  Caption1,
  Checkbox,
  Option,
  Spinner,
  makeStyles,
  tokens,
} from "@fluentui/react-components";
import { DialogDismiss } from "../../shared/DialogDismiss";
import { ConfirmDialog } from "../../shared/ConfirmDialog";
import { StatusMessage } from "../../shared/StatusMessage";
import { TruncatedDropdown } from "../../shared/TruncatedDropdown";
import { PublicLine, useActiveSpaceIsPublic } from "../../shared/visibility";
import { useGetEnvQuery } from "../../shell/api";
import {
  useCreatePromptMutation,
  useCreatePRMutation,
  useResolveBugMutation,
  useCreateAdoItemMutation,
  useGetStatusQuery,
  useUploadAssetMutation,
} from "./api.ado";
import type { CommandResponse } from "./api.ado";
import { buildNewCardParams, commandResultMessage } from "./cliBridge";
import { ImageDropZone } from "../../shared/ImageDropZone";

export type ActionDialogTab = "create" | "resolve" | "pr" | "new-item";

const TAB_TITLES: Record<ActionDialogTab, string> = {
  create: "Card from an ADO Work Item",
  resolve: "Resolve Work Item",
  pr: "Create PR",
  "new-item": "New ADO Item",
};

const assignOptions = [
  { key: "force", label: "Force reassign to me" },
  { key: "me", label: "Assign to me (if unassigned)" },
  { key: "none", label: "Don't assign (read-only)" },
];

const reasonOptions = [
  { key: "Fixed", label: "Fixed" },
  { key: "AsDesigned", label: "As Designed" },
  { key: "CannotReproduce", label: "Cannot Reproduce" },
  { key: "Duplicate", label: "Duplicate" },
  { key: "WontFix", label: "Won't Fix" },
  { key: "Deferred", label: "Deferred" },
];

// On a GitHub space the same dialog wears the tracker's words (D-G4: same
// verbs, the space's own tool): kinds are labels, Sprint is the milestone,
// Tags are labels, the parent is the parent ISSUE (the CLI adds the new issue
// as its sub-issue -- Team Agile's Split opens this door with it named), and
// what has no GitHub shape (priority, points) is not offered -- the CLI
// refuses it by name anyway.
const ghItemTypeOptions = [
  { key: "Task", label: "Issue" },
  { key: "Bug", label: "Bug" },
  { key: "Feature", label: "Feature" },
];

const adoItemTypeOptions = [
  { key: "UserStory", label: "User Story" },
  { key: "Task", label: "Task" },
  { key: "Bug", label: "Bug" },
  { key: "Feature", label: "Feature" },
];

const priorityOptions = [
  { key: "", label: "— none —" },
  { key: "1", label: "1 — Critical" },
  { key: "2", label: "2 — High" },
  { key: "3", label: "3 — Medium" },
  { key: "4", label: "4 — Low" },
];

const useStyles = makeStyles({
  content: {
    display: "flex",
    flexDirection: "column",
    gap: tokens.spacingVerticalM,
    paddingTop: tokens.spacingVerticalS,
  },
  sourceRow: {
    display: "flex",
    gap: tokens.spacingHorizontalS,
    flexWrap: "wrap",
  },
  quiet: { color: tokens.colorNeutralForeground3 },
  fieldRow: {
    display: "grid",
    gridTemplateColumns: "1fr 1fr",
    gap: tokens.spacingHorizontalM,
    alignItems: "end",
  },
  fieldRow3: {
    display: "grid",
    gridTemplateColumns: "1fr 1fr 1fr",
    gap: tokens.spacingHorizontalM,
    alignItems: "end",
  },
  field: {
    display: "flex",
    flexDirection: "column",
    gap: tokens.spacingVerticalXS,
    minWidth: 0,
  },
  checkboxRow: {
    display: "flex",
    gap: tokens.spacingHorizontalL,
    flexWrap: "wrap",
    alignItems: "center",
  },
});

export interface ActionDialogProps {
  open: boolean;
  onClose: () => void;
  tab: ActionDialogTab;
  initialWorkItemId?: string;
  /** Work item type (e.g. "Bug", "User Story"). Drives the resolve tab's reason field. */
  initialWorkItemType?: string;
  /**
   * The new item's parent, named by the caller (Team Agile's Split): the
   * new-item door opens with it filled, and keeps it after a create so the
   * next piece of the split has it too.
   */
  initialParent?: number;
}

export function ActionDialog({
  open,
  onClose,
  tab: initialTab,
  initialWorkItemId = "",
  initialWorkItemType = "",
  initialParent = 0,
}: ActionDialogProps) {
  // The caller picks the door; the person may walk to another (the owner:
  // one create dialog for the local card, the pickup AND the
  // new issue). Internal state, reseeded each open.
  // Reseeded while rendering, against what the last render was opened with,
  // so an open never paints the previous door for a frame first.
  const [tab, setTab] = useState<ActionDialogTab>(initialTab);
  const [seededFor, setSeededFor] = useState({ open, initialTab });
  if (seededFor.open !== open || seededFor.initialTab !== initialTab) {
    setSeededFor({ open, initialTab });
    if (open) setTab(initialTab);
  }
  const styles = useStyles();
  // Each field's visible caption names it: ids are per instance, so two open
  // dialogs never share one.
  const uid = useId();
  const { data: env } = useGetEnvQuery();
  const { data: statusData } = useGetStatusQuery();
  const isGithub = env?.tracker === "github";
  // On stage: the Space's repository is public, so a write here -- a new
  // issue, a close and its comment, a pull request -- is read by strangers.
  const onStage = useActiveSpaceIsPublic(isGithub);
  const itemTypeOptions = isGithub ? ghItemTypeOptions : adoItemTypeOptions;
  const projectList = env?.config?.projects ?? [];

  // ── Create from Work Item ─────────────────────────────────────────────────
  const [createPrompt] = useCreatePromptMutation();
  const [workItemId, setWorkItemId] = useState(initialWorkItemId);
  const [assign, setAssign] = useState("force");
  const [creating, setCreating] = useState(false);
  const [createResult, setCreateResult] = useState<CommandResponse | null>(null);
  // Two sources for one card (docs/hub/cards.md, "Who writes a card"): made from nothing --
  // a title and a type, no work item, no ADO call -- or made from a work item.
  // Where there is no ADO to ask (a `local` org, or ADO unreachable) the only one
  // that can work is "new", so it is the default there; an initial work item id
  // means the caller already chose.
  // Azure DevOps is something you plug in. Where it is not in use there is ONE
  // way to make a card, so there is no choice to show: no tab row at all, rather
  // than a second tab that can do nothing for the person reading it. An agent too
  // old to say reads as "in use", which is what this dialog always was.
  const adoShown = env?.ado?.enabled ?? true;
  // With the tabs hidden the default IS the only source, so "reachable" has to
  // mean "and shown": features.ado=false in an active org must not land a person
  // on a work-item form they have no tab to leave.
  const adoReachable = adoShown && env?.spaceStatus === "active" && env?.tier === 1;
  const [source, setSource] = useState<"new" | "workItem">(
    initialWorkItemId || adoReachable ? "workItem" : "new",
  );
  useEffect(() => {
    if (!initialWorkItemId && env) setSource(adoReachable ? "workItem" : "new"); // eslint-disable-line react-hooks/set-state-in-effect
  }, [adoReachable, env, initialWorkItemId]);
  const cardTypes = env?.cardTypes?.length ? env.cardTypes : ["Task"];
  const [cardTitle, setCardTitle] = useState("");
  const [cardType, setCardType] = useState("");
  const chosenType = cardType || (cardTypes.includes("Task") ? "Task" : cardTypes[0]);
  const createValid = source === "new" ? cardTitle.trim().length > 0 : /^\d+$/.test(workItemId);
  // A picture at birth (docs/hub/cards.md, "A card's pictures"): the
  // dialog takes one through the zone, uploads it to a temp file first, and
  // NewPrompt attaches it with -Cover -- or -Before when it shows what is wrong,
  // the snap that IS the report for GUI work.
  const [uploadAsset] = useUploadAssetMutation();
  const [picture, setPicture] = useState<File | null>(null);
  const [pictureIsBefore, setPictureIsBefore] = useState(false);
  // The dialog's own button: a dropped picture names it and focuses it.
  const submitRef = useRef<HTMLButtonElement>(null);

  // ── Resolve Work Item ─────────────────────────────────────────────────────
  const [resolveBug] = useResolveBugMutation();
  const [resolveBugId, setResolveBugId] = useState(initialWorkItemId);
  const [resolveComment, setResolveComment] = useState("");
  const [resolveReason, setResolveReason] = useState("Fixed");
  const [resolving, setResolving] = useState(false);
  const [resolveResult, setResolveResult] = useState<CommandResponse | null>(null);
  const resolveValid = /^\d+$/.test(resolveBugId) && resolveComment.trim().length > 0;
  // Closing is the one act here a person may regret -- it takes the item off
  // every list. The tab says what happens and what does not, its
  // button is named for the act, and the act still asks first: "Are you sure?
  // Close issue #<n>." [Cancel] [Submit], the owner's sketch, in shared/ConfirmDialog.
  const resolveNoun = isGithub ? "issue" : "work item";
  const resolveRef = /^\d+$/.test(resolveBugId) ? ` #${resolveBugId}` : "";
  const resolveVerb = isGithub ? "Close" : "Resolve";
  const resolveTitle = `${resolveVerb} ${resolveNoun}${resolveRef}`;
  const [confirmResolve, setConfirmResolve] = useState(false);
  const resolveAction = `${resolveVerb} ${resolveNoun}`;
  // Reason only applies to Bugs (-> Resolved). Story/Task/Feature close as Completed.
  const isBug = initialWorkItemType === "" || initialWorkItemType === "Bug";

  // ── Create PR ─────────────────────────────────────────────────────────────
  const [createPR] = useCreatePRMutation();
  const [prWorkItemId, setPrWorkItemId] = useState("");
  const [prTargetBranch, setPrTargetBranch] = useState("");
  const [prDraft, setPrDraft] = useState(true);
  const [prAutoComplete, setPrAutoComplete] = useState(false);
  const [prSkipWorkItem, setPrSkipWorkItem] = useState(false);
  const [creatingPR, setCreatingPR] = useState(false);
  const [createPRResult, setCreatePRResult] = useState<CommandResponse | null>(null);
  const prValid = /^\d+$/.test(prWorkItemId);

  // ── New ADO Item ──────────────────────────────────────────────────────────
  const [createAdoItem] = useCreateAdoItemMutation();
  const [niType, setNiType] = useState("UserStory");
  // A gh space has no "User Story": the default folds to the plain issue. Folded
  // while rendering; once it is "Task" the condition is false, so it settles.
  if (isGithub && niType === "UserStory") setNiType("Task");
  const [niTitle, setNiTitle] = useState("");
  const [niProject, setNiProject] = useState("");
  const [niSprint, setNiSprint] = useState("");
  const seededParent = initialParent > 0 ? String(initialParent) : "";
  const [niParent, setNiParent] = useState(seededParent);
  const [niDescription, setNiDescription] = useState("");
  const [niAC, setNiAC] = useState("");
  const [niReproSteps, setNiReproSteps] = useState("");
  const [niPriority, setNiPriority] = useState("");
  const [niPoints, setNiPoints] = useState("");
  const [niTags, setNiTags] = useState("");
  const [submittingNi, setSubmittingNi] = useState(false);
  const [niResult, setNiResult] = useState<CommandResponse | null>(null);
  const niValid = niTitle.trim().length > 0;

  // Reset state when the dialog opens (handles both fresh opens and re-opens with a new ID).
  // Deliberately setState-in-effect: the dialog stays mounted while closed, so this is the
  // reset-on-open pattern, not a synchronization bug. A `key`-based remount would ditch
  // Fluent Dialog's exit animation instead.
  useEffect(() => {
    if (!open) return;
    setWorkItemId(initialWorkItemId); // eslint-disable-line react-hooks/set-state-in-effect
    setResolveBugId(initialWorkItemId);
    setAssign("force");
    setResolveComment("");
    setResolveReason("Fixed");
    setPrWorkItemId("");
    setPrTargetBranch("");
    setPrDraft(true);
    setPrAutoComplete(false);
    setPrSkipWorkItem(false);
    setNiTitle("");
    setNiSprint("");
    setNiParent(seededParent);
    setNiDescription("");
    setNiAC("");
    setNiReproSteps("");
    setNiPriority("");
    setNiPoints("");
    setNiTags("");
    setCreateResult(null);
    setResolveResult(null);
    setCreatePRResult(null);
    setNiResult(null);
  }, [open, initialWorkItemId, seededParent]);

  // ── Submit handlers ───────────────────────────────────────────────────────

  const handleCreate = async () => {
    if (!createValid) return;

    // A NEW card: through the bridge like everything else, so the id comes from
    // the CLI's one id engine and the file from its one writer.
    if (source === "new") {
      setCreating(true);
      setCreateResult(null);
      try {
        // The picture first, to a temp file: the verb copies it in and writes the
        // line; the upload route writes nothing into the hub.
        let path = "";
        if (picture) {
          try {
            path = (await uploadAsset({ file: picture }).unwrap()).path;
          } catch (e) {
            const detail = (e as { data?: { detail?: string } } | undefined)?.data?.detail;
            setCreateResult({
              command: "NewPrompt",
              status: "error",
              exit_code: -1,
              output: null,
              error: detail ?? "Could not upload the picture. Nothing was created.",
              duration: 0,
            });
            return;
          }
        }
        const data = await createPrompt({
          params: buildNewCardParams({
            title: cardTitle,
            type: chosenType,
            cover: path && !pictureIsBefore ? path : undefined,
            before: path && pictureIsBefore ? path : undefined,
          }),
        }).unwrap();
        setCreateResult(data);
        if (data.status === "success") {
          setCardTitle("");
          setPicture(null);
          setPictureIsBefore(false);
        }
      } catch {
        setCreateResult({
          command: "NewPrompt",
          status: "error",
          exit_code: -1,
          output: null,
          error: "Could not reach the agent. Nothing was created.",
          duration: 0,
        });
      } finally {
        setCreating(false);
      }
      return;
    }

    // Duplicate guard: if an active prompt already references this work item, no-op
    const isDuplicate =
      statusData?.prompts.some((p) =>
        p.ado_url?.match(new RegExp(`[/=]${workItemId}([^\\d]|$)`)),
      ) ?? false;

    if (isDuplicate) {
      setCreateResult({
        command: "NewPrompt",
        status: "success",
        exit_code: 0,
        output: `⚡ A prompt for work item #${workItemId} already exists — no changes made.`,
        error: null,
        duration: 0,
      });
      return;
    }

    setCreating(true);
    setCreateResult(null);
    const params = [workItemId];
    if (assign === "none") params.push("-ReadOnly");
    else if (assign === "force") params.push("-Force");
    try {
      const data = await createPrompt({ params }).unwrap();
      setCreateResult(data);
      if (data.status === "success") setWorkItemId("");
    } catch {
      setCreateResult({
        command: "NewPrompt",
        status: "error",
        exit_code: -1,
        output: null,
        error: "Network error",
        duration: 0,
      });
    } finally {
      setCreating(false);
    }
  };

  const handleResolve = async () => {
    if (!resolveValid) return;
    setResolving(true);
    setResolveResult(null);
    try {
      const data = await resolveBug({
        workItemId: Number(resolveBugId),
        comment: resolveComment.trim(),
        // Only a Bug has a reason to state here. For every other type the
        // dialog shows "Completed" and sends no -Reason, so the CLI applies
        // its own per-type default rather than being told "Fixed".
        reason: isBug ? resolveReason : undefined,
      }).unwrap();
      setResolveResult(data);
      if (data.status === "success") {
        setResolveBugId("");
        setResolveComment("");
      }
    } catch {
      setResolveResult({
        command: "CloseWorkItem",
        status: "error",
        exit_code: -1,
        output: null,
        error: "Network error",
        duration: 0,
      });
    } finally {
      setResolving(false);
    }
  };

  const handleCreatePR = async () => {
    if (!prValid) return;
    setCreatingPR(true);
    setCreatePRResult(null);
    try {
      const data = await createPR({
        workItemId: Number(prWorkItemId),
        targetBranch: prTargetBranch.trim() || undefined,
        draft: prDraft,
        autoComplete: prAutoComplete,
        skipWorkItem: prSkipWorkItem,
      }).unwrap();
      setCreatePRResult(data);
      if (data.status === "success") setPrWorkItemId("");
    } catch {
      setCreatePRResult({
        command: "NewPR",
        status: "error",
        exit_code: -1,
        output: null,
        error: "Network error",
        duration: 0,
      });
    } finally {
      setCreatingPR(false);
    }
  };

  const handleNewItem = async () => {
    if (!niValid) return;
    setSubmittingNi(true);
    setNiResult(null);
    try {
      const body: Parameters<typeof createAdoItem>[0] = {
        type: niType as "UserStory" | "Task" | "Bug" | "Feature",
        title: niTitle.trim(),
      };
      if (niDescription.trim()) body.description = niDescription.trim();
      if (niProject.trim()) body.project = niProject.trim();
      if (niSprint.trim()) body.sprint = niSprint.trim();
      if (niParent.trim()) body.parent = Number(niParent);
      if (niPriority) body.priority = Number(niPriority);
      if (niPoints.trim()) body.points = Number(niPoints);
      if (niAC.trim()) body.acceptanceCriteria = niAC.trim();
      if (niReproSteps.trim()) body.reproSteps = niReproSteps.trim();
      if (niTags.trim()) body.tags = niTags.trim();
      const data = await createAdoItem(body).unwrap();
      setNiResult(data);
      if (data.status === "success") {
        setNiTitle("");
        setNiSprint("");
        setNiParent(seededParent);
        setNiDescription("");
        setNiAC("");
        setNiReproSteps("");
        setNiPriority("");
        setNiPoints("");
        setNiTags("");
      }
    } catch {
      setNiResult({
        command: "NewAdoItem",
        status: "error",
        exit_code: -1,
        output: null,
        error: "Network error",
        duration: 0,
      });
    } finally {
      setSubmittingNi(false);
    }
  };

  // ── Derived submit state ──────────────────────────────────────────────────
  const isSubmitting = creating || resolving || creatingPR || submittingNi;
  const isValid =
    tab === "create"
      ? createValid
      : tab === "resolve"
        ? resolveValid
        : tab === "pr"
          ? prValid
          : niValid;

  const handleSubmit = () => {
    if (tab === "create") handleCreate();
    else if (tab === "resolve") setConfirmResolve(true);
    else if (tab === "pr") handleCreatePR();
    else handleNewItem();
  };

  const currentResult =
    tab === "create"
      ? createResult
      : tab === "resolve"
        ? resolveResult
        : tab === "pr"
          ? createPRResult
          : niResult;

  const clearResult = () => {
    if (tab === "create") setCreateResult(null);
    else if (tab === "resolve") setResolveResult(null);
    else if (tab === "pr") setCreatePRResult(null);
    else setNiResult(null);
  };

  // The confirm is a SIBLING of the form's Dialog, never a child: a Fluent
  // Dialog with two children reads the first as its trigger and draws it
  // always -- the form stood on every page and would not dismiss.
  return (
    <>
      <Dialog
        open={open}
        onOpenChange={(_e, d) => {
          if (!d.open) onClose();
        }}
      >
        <DialogSurface style={{ maxWidth: "520px", width: "100%" }}>
          <DialogBody>
            <DialogTitle action={<DialogDismiss />}>
              {tab === "resolve"
                ? resolveTitle
                : tab === "create" && source === "new"
                  ? "New ToolKit Card"
                  : tab === "create" && isGithub
                    ? "Card from a GitHub Issue"
                    : tab === "new-item" && isGithub
                      ? "New GitHub Issue"
                      : TAB_TITLES[tab]}
            </DialogTitle>
            <DialogContent>
              <div className={styles.content}>
                {/* ── Create from Work Item ───────────────────────────────── */}
                {(tab === "create" || tab === "new-item") && adoShown && (
                  <div
                    role="radiogroup"
                    aria-label="Where it comes from"
                    className={styles.sourceRow}
                  >
                    {/* THE SINGLE DIALOG (the owner: "it can be a single
                      dialog for ADO, Non ADO and Custom Cards -- just lot of
                      states ... it is the way to go"): the source row is the
                      tracker's doors. Local spaces show no row (one way, no
                      choice); both tracker kinds show three. */}
                    {(isGithub
                      ? ([
                          ["new", "New ToolKit Card"],
                          ["workItem", "From an issue"],
                          ["issue", "New GitHub Issue"],
                        ] as const)
                      : ([
                          ["new", "New ToolKit Card"],
                          ["workItem", "From a work item"],
                          ["issue", "New ADO Item"],
                        ] as const)
                    ).map(([key, label]) => {
                      const active =
                        key === "issue" ? tab === "new-item" : tab === "create" && source === key;
                      return (
                        <Button
                          key={key}
                          role="radio"
                          aria-checked={active}
                          appearance={active ? "primary" : "secondary"}
                          size="small"
                          disabled={creating || submittingNi}
                          onClick={() => {
                            setCreateResult(null);
                            if (key === "issue") {
                              setTab("new-item");
                              return;
                            }
                            setTab("create");
                            setSource(key as "new" | "workItem");
                          }}
                        >
                          {label}
                        </Button>
                      );
                    })}
                  </div>
                )}

                {tab === "create" && source === "new" && (
                  <>
                    <div className={styles.field}>
                      <Caption1 id="new-card-title-label">What is it called?</Caption1>
                      <Input
                        aria-labelledby="new-card-title-label"
                        placeholder="e.g. Wallet ticket from a QR code"
                        value={cardTitle}
                        onChange={(_e, d) => setCardTitle(d.value)}
                        disabled={creating}
                        autoFocus
                      />
                    </div>
                    <div className={styles.field}>
                      <Caption1 id="new-card-type-label">What kind of thing is it?</Caption1>
                      <TruncatedDropdown
                        aria-labelledby="new-card-type-label"
                        value={chosenType}
                        selectedOptions={[chosenType]}
                        onOptionSelect={(_e, d) => {
                          if (d.optionValue) setCardType(d.optionValue);
                        }}
                        disabled={creating}
                      >
                        {cardTypes.map((t) => (
                          <Option key={t} value={t}>
                            {t}
                          </Option>
                        ))}
                      </TruncatedDropdown>
                    </div>
                    {/* A picture, optional (C2): a visible zone -- drop, paste,
                      or choose a file -- and whether the snap is the before. */}
                    <div className={styles.field}>
                      <Caption1 id="new-card-picture-label">A picture, if you have one</Caption1>
                      <ImageDropZone
                        label="A picture for the card"
                        file={picture}
                        onFile={setPicture}
                        disabled={creating}
                        compact
                        next={submitRef}
                      />
                      {picture ? (
                        <Checkbox
                          label="It shows what is wrong (a before, not the cover)"
                          checked={pictureIsBefore}
                          onChange={(_e, d) => setPictureIsBefore(!!d.checked)}
                          disabled={creating}
                        />
                      ) : null}
                    </div>
                    {/* Say what it IS, not what it is not (the owner,
                      the string pass's rule in action) -- and no tracker
                      named, because this door exists on every space kind. */}
                    <Caption1 className={styles.quiet}>
                      A custom card, created by ToolKit: it gets a short id of its own, and is in
                      play as soon as it is made.
                    </Caption1>
                  </>
                )}

                {tab === "create" && source === "workItem" && (
                  <>
                    <div className={styles.fieldRow}>
                      <div className={styles.field}>
                        <Caption1 id={`${uid}-f1`}>
                          {isGithub ? "Issue number" : "Work Item ID"}
                        </Caption1>
                        <Input
                          aria-labelledby={`${uid}-f1`}
                          type="text"
                          inputMode="numeric"
                          pattern="[0-9]*"
                          placeholder={isGithub ? "e.g. 55" : "e.g. 223061"}
                          value={workItemId}
                          onChange={(_e, d) => setWorkItemId(d.value.replace(/\D/g, ""))}
                          disabled={creating}
                        />
                      </div>
                      <div className={styles.field}>
                        <Caption1 id={`${uid}-f2`}>Assignment</Caption1>
                        <TruncatedDropdown
                          aria-labelledby={`${uid}-f2`}
                          maxToggleLength={15}
                          value={assignOptions.find((o) => o.key === assign)?.label}
                          selectedOptions={[assign]}
                          onOptionSelect={(_e, d) => {
                            if (d.optionValue) setAssign(d.optionValue);
                          }}
                          disabled={creating}
                        >
                          {assignOptions.map((o) => (
                            <Option key={o.key} value={o.key}>
                              {o.label}
                            </Option>
                          ))}
                        </TruncatedDropdown>
                      </div>
                    </div>
                  </>
                )}

                {/* ── Resolve Work Item ───────────────────────────────────── */}
                {tab === "resolve" && (
                  <>
                    <Body1>
                      {isGithub
                        ? `Closes${resolveRef || " the issue"} on GitHub and posts your comment on it. It leaves the Issues tab; the thread and its history stay, and it can be reopened on GitHub.`
                        : `Resolves${resolveRef || " the work item"} in Azure DevOps and posts your comment on it. It leaves your work list; its history stays, and it can be reopened on the board.`}
                    </Body1>
                    <div className={styles.fieldRow}>
                      <div className={styles.field}>
                        <Caption1 id={`${uid}-f3`}>{isGithub ? "Issue" : "Work Item ID"}</Caption1>
                        <Input
                          aria-labelledby={`${uid}-f3`}
                          type="text"
                          inputMode="numeric"
                          pattern="[0-9]*"
                          placeholder={isGithub ? "e.g. 74" : "e.g. 232208"}
                          value={resolveBugId}
                          onChange={(_e, d) => setResolveBugId(d.value.replace(/\D/g, ""))}
                          disabled={resolving}
                        />
                      </div>
                      {isBug ? (
                        <div className={styles.field}>
                          <Caption1 id={`${uid}-f4`}>Reason</Caption1>
                          <TruncatedDropdown
                            aria-labelledby={`${uid}-f4`}
                            maxToggleLength={15}
                            value={reasonOptions.find((o) => o.key === resolveReason)?.label}
                            selectedOptions={[resolveReason]}
                            onOptionSelect={(_e, d) => {
                              if (d.optionValue) setResolveReason(d.optionValue);
                            }}
                            disabled={resolving}
                          >
                            {reasonOptions.map((o) => (
                              <Option key={o.key} value={o.key}>
                                {o.label}
                              </Option>
                            ))}
                          </TruncatedDropdown>
                        </div>
                      ) : (
                        <div className={styles.field}>
                          <Caption1 id={`${uid}-f5`}>Resolution</Caption1>
                          <Input
                            aria-labelledby={`${uid}-f5`}
                            type="text"
                            value="Completed"
                            disabled
                            readOnly
                          />
                        </div>
                      )}
                    </div>
                    {!isBug && (
                      <Caption1 style={{ color: tokens.colorNeutralForeground3 }}>
                        {initialWorkItemType || "This item"} will be closed as Completed. The reason
                        field applies to Bugs only.
                      </Caption1>
                    )}
                    <div className={styles.field}>
                      <Caption1 id={`${uid}-f6`}>Comment</Caption1>
                      <Textarea
                        aria-labelledby={`${uid}-f6`}
                        placeholder="e.g. Fixed in PR 141234"
                        value={resolveComment}
                        onChange={(_e, d) => setResolveComment(d.value)}
                        disabled={resolving}
                        resize="vertical"
                        rows={3}
                      />
                    </div>
                  </>
                )}

                {/* ── Create PR ───────────────────────────────────────────── */}
                {tab === "pr" && (
                  <>
                    <div className={styles.fieldRow}>
                      <div className={styles.field}>
                        <Caption1 id={`${uid}-f7`}>Work Item ID</Caption1>
                        <Input
                          aria-labelledby={`${uid}-f7`}
                          type="text"
                          inputMode="numeric"
                          pattern="[0-9]*"
                          placeholder={isGithub ? "e.g. 55" : "e.g. 223061"}
                          value={prWorkItemId}
                          onChange={(_e, d) => setPrWorkItemId(d.value.replace(/\D/g, ""))}
                          disabled={creatingPR}
                        />
                      </div>
                      <div className={styles.field}>
                        <Caption1 id={`${uid}-f8`}>Target Branch</Caption1>
                        <Input
                          aria-labelledby={`${uid}-f8`}
                          type="text"
                          placeholder="main"
                          value={prTargetBranch}
                          onChange={(_e, d) => setPrTargetBranch(d.value)}
                          disabled={creatingPR}
                        />
                      </div>
                    </div>
                    <div className={styles.checkboxRow}>
                      <Checkbox
                        label={<Caption1>Draft</Caption1>}
                        checked={prDraft}
                        onChange={(_e, d) => setPrDraft(!!d.checked)}
                        disabled={creatingPR}
                      />
                      <Checkbox
                        label={<Caption1>Auto Complete</Caption1>}
                        checked={prAutoComplete}
                        onChange={(_e, d) => setPrAutoComplete(!!d.checked)}
                        disabled={creatingPR}
                      />
                      <Checkbox
                        label={<Caption1>Skip Work Item</Caption1>}
                        checked={prSkipWorkItem}
                        onChange={(_e, d) => setPrSkipWorkItem(!!d.checked)}
                        disabled={creatingPR}
                      />
                    </div>
                  </>
                )}

                {/* ── New ADO Item ─────────────────────────────────────────── */}
                {tab === "new-item" && (
                  <>
                    <div className={styles.fieldRow}>
                      <div className={styles.field}>
                        <Caption1 id={`${uid}-f9`}>Type</Caption1>
                        <TruncatedDropdown
                          aria-labelledby={`${uid}-f9`}
                          maxToggleLength={12}
                          value={itemTypeOptions.find((o) => o.key === niType)?.label}
                          selectedOptions={[niType]}
                          onOptionSelect={(_e, d) => {
                            if (d.optionValue) setNiType(d.optionValue);
                          }}
                          disabled={submittingNi}
                        >
                          {itemTypeOptions.map((o) => (
                            <Option key={o.key} value={o.key}>
                              {o.label}
                            </Option>
                          ))}
                        </TruncatedDropdown>
                      </div>
                      <div className={styles.field}>
                        <Caption1 id={`${uid}-f10`}>
                          Title <span style={{ color: tokens.colorPaletteRedForeground1 }}>*</span>
                        </Caption1>
                        <Input
                          aria-labelledby={`${uid}-f10`}
                          placeholder="e.g. Add dark mode toggle"
                          value={niTitle}
                          onChange={(_e, d) => setNiTitle(d.value)}
                          disabled={submittingNi}
                        />
                      </div>
                    </div>
                    <div className={styles.fieldRow3}>
                      {/* A repo-grained gh space has no project to pick -- the
                        address already says which repo. Absent, not empty. */}
                      {!(isGithub && projectList.length === 0) && (
                        <div className={styles.field}>
                          <Caption1 id={`${uid}-f11`}>Project</Caption1>
                          {projectList.length > 1 ? (
                            <TruncatedDropdown
                              aria-labelledby={`${uid}-f11`}
                              maxToggleLength={14}
                              value={niProject || "— auto —"}
                              selectedOptions={[niProject]}
                              onOptionSelect={(_e, d) => setNiProject(d.optionValue ?? "")}
                              disabled={submittingNi}
                            >
                              <Option key="" value="">
                                — auto —
                              </Option>
                              {projectList.map((p) => (
                                <Option key={p.name} value={p.name}>
                                  {p.name}
                                </Option>
                              ))}
                            </TruncatedDropdown>
                          ) : (
                            <Input
                              aria-labelledby={`${uid}-f11`}
                              placeholder={projectList[0]?.name ?? "project name"}
                              value={niProject}
                              onChange={(_e, d) => setNiProject(d.value)}
                              disabled={submittingNi || projectList.length === 1}
                            />
                          )}
                        </div>
                      )}
                      <div className={styles.field}>
                        <Caption1 id={`${uid}-f12`}>{isGithub ? "Milestone" : "Sprint"}</Caption1>
                        <Input
                          aria-labelledby={`${uid}-f12`}
                          placeholder={isGithub ? "e.g. Milestone P" : "e.g. Sprint 72"}
                          value={niSprint}
                          onChange={(_e, d) => setNiSprint(d.value)}
                          disabled={submittingNi}
                        />
                      </div>
                      <div className={styles.field}>
                        <Caption1 id={`${uid}-f13`}>
                          {isGithub ? "Parent issue" : "Parent ID"}
                        </Caption1>
                        <Input
                          aria-labelledby={`${uid}-f13`}
                          type="text"
                          inputMode="numeric"
                          pattern="[0-9]*"
                          placeholder={isGithub ? "e.g. 140" : "e.g. 195551"}
                          value={niParent}
                          onChange={(_e, d) => setNiParent(d.value.replace(/\D/g, ""))}
                          disabled={submittingNi}
                        />
                      </div>
                    </div>
                    {niType === "UserStory" && (
                      <div className={styles.field}>
                        <Caption1 id={`${uid}-f14`}>Acceptance Criteria</Caption1>
                        <Textarea
                          aria-labelledby={`${uid}-f14`}
                          placeholder="- [ ] ..."
                          value={niAC}
                          onChange={(_e, d) => setNiAC(d.value)}
                          disabled={submittingNi}
                          resize="vertical"
                          rows={3}
                        />
                      </div>
                    )}
                    {niType === "Bug" && (
                      <div className={styles.field}>
                        <Caption1 id={`${uid}-f15`}>Repro Steps</Caption1>
                        <Textarea
                          aria-labelledby={`${uid}-f15`}
                          placeholder="1. Go to ... 2. Click ..."
                          value={niReproSteps}
                          onChange={(_e, d) => setNiReproSteps(d.value)}
                          disabled={submittingNi}
                          resize="vertical"
                          rows={3}
                        />
                      </div>
                    )}
                    <div className={styles.field}>
                      <Caption1 id={`${uid}-f16`}>Description</Caption1>
                      <Textarea
                        aria-labelledby={`${uid}-f16`}
                        placeholder="Optional context or scope"
                        value={niDescription}
                        onChange={(_e, d) => setNiDescription(d.value)}
                        disabled={submittingNi}
                        resize="vertical"
                        rows={2}
                      />
                    </div>
                    <div className={styles.fieldRow3}>
                      {!isGithub && (
                        <div className={styles.field}>
                          <Caption1 id={`${uid}-f17`}>Priority</Caption1>
                          <TruncatedDropdown
                            aria-labelledby={`${uid}-f17`}
                            maxToggleLength={12}
                            value={priorityOptions.find((o) => o.key === niPriority)?.label}
                            selectedOptions={[niPriority]}
                            onOptionSelect={(_e, d) => setNiPriority(d.optionValue ?? "")}
                            disabled={submittingNi}
                          >
                            {priorityOptions.map((o) => (
                              <Option key={o.key} value={o.key}>
                                {o.label}
                              </Option>
                            ))}
                          </TruncatedDropdown>
                        </div>
                      )}
                      {!isGithub && (
                        <div className={styles.field}>
                          <Caption1 id={`${uid}-f18`}>Points</Caption1>
                          <Input
                            aria-labelledby={`${uid}-f18`}
                            type="text"
                            inputMode="numeric"
                            pattern="[0-9]*"
                            placeholder="e.g. 3"
                            value={niPoints}
                            onChange={(_e, d) => setNiPoints(d.value.replace(/\D/g, ""))}
                            disabled={submittingNi}
                          />
                        </div>
                      )}
                      <div className={styles.field}>
                        <Caption1 id={`${uid}-f19`}>{isGithub ? "Labels" : "Tags"}</Caption1>
                        <Input
                          aria-labelledby={`${uid}-f19`}
                          placeholder={isGithub ? "e.g. bug; sev2" : "e.g. ux; a11y"}
                          value={niTags}
                          onChange={(_e, d) => setNiTags(d.value)}
                          disabled={submittingNi}
                        />
                      </div>
                    </div>
                  </>
                )}

                {/* The one line a write to a public repository carries:
                  on the tabs that write to the tracker, said and never asked. */}
                <PublicLine
                  show={onStage && (tab === "new-item" || tab === "resolve" || tab === "pr")}
                />

                {/* Four statuses come back from the bridge, not two: success, error,
                  rejected and timeout. Only the first is green; the other three are
                  named in the text, with whatever the command printed before it
                  stopped -- that is usually where the CLI's own [!] line is. */}
                {currentResult && (
                  <StatusMessage
                    status={currentResult.status === "success" ? "success" : "error"}
                    onDismiss={clearResult}
                  >
                    {commandResultMessage(currentResult, "✓ Done")}
                  </StatusMessage>
                )}
              </div>
            </DialogContent>
            <DialogActions>
              <Button appearance="secondary" onClick={onClose} disabled={isSubmitting}>
                Cancel
              </Button>
              <Button
                ref={submitRef}
                appearance="primary"
                disabled={!isValid || isSubmitting}
                onClick={handleSubmit}
              >
                {isSubmitting ? (
                  <Spinner size="tiny" aria-label="Submitting..." />
                ) : tab === "resolve" ? (
                  resolveAction
                ) : (
                  "Submit"
                )}
              </Button>
            </DialogActions>
          </DialogBody>
        </DialogSurface>
      </Dialog>
      <ConfirmDialog
        open={confirmResolve}
        what={`${resolveAction}${resolveRef}.`}
        onCancel={() => setConfirmResolve(false)}
        onConfirm={() => {
          setConfirmResolve(false);
          handleResolve();
        }}
      />
    </>
  );
}
