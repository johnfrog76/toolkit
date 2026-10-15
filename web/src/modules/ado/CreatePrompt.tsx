import { useState } from "react";
import {
  Subtitle2,
  Caption1,
  Button,
  Checkbox,
  Input,
  Textarea,
  Option,
  Spinner,
  makeStyles,
  tokens,
} from "@fluentui/react-components";
import { InfoTip } from "../../shared/InfoTip";
import { StatusMessage } from "../../shared/StatusMessage";
import { TruncatedDropdown } from "../../shared/TruncatedDropdown";
import { FilterBadge } from "../../shared/FilterBadge";
import { PageCard } from "../../shared/PageCard";
import { useGetEnvQuery } from "../../shell/api";
import {
  useCreatePromptMutation,
  useCreatePRMutation,
  useFetchPrCommentsMutation,
  useResolveBugMutation,
  useCreateAdoItemMutation,
} from "./api.ado";
import type { CommandResponse } from "./api.ado";
import { commandResultMessage } from "./cliBridge";

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
  // The one exception to PageGrid's "a lone card sits at half width": Actions
  // is the whole of its tab and its forms want the room, so it spans both
  // columns.
  card: { gridColumn: "1 / -1" },
  tabBar: {
    display: "flex",
    gap: tokens.spacingHorizontalS,
    flexWrap: "wrap",
  },
  form: {
    display: "flex",
    flexDirection: "column",
    gap: tokens.spacingVerticalM,
    marginTop: tokens.spacingVerticalS,
  },
  fieldRow: {
    display: "grid",
    gridTemplateColumns: "1fr 1fr 2.8rem",
    gap: tokens.spacingHorizontalM,
    alignItems: "end",
  },
  fieldRow2: {
    display: "grid",
    gridTemplateColumns: "1fr 2fr",
    gap: tokens.spacingHorizontalM,
    alignItems: "end",
  },
  fieldRow3: {
    display: "grid",
    gridTemplateColumns: "1fr 1fr 1fr",
    gap: tokens.spacingHorizontalM,
    alignItems: "end",
  },
  fieldRow4: {
    display: "grid",
    gridTemplateColumns: "1fr 1fr 1fr 2.8rem",
    gap: tokens.spacingHorizontalM,
    alignItems: "end",
  },
  field: {
    display: "flex",
    flexDirection: "column",
    gap: tokens.spacingVerticalXS,
    minWidth: 0,
  },
  button: {
    minWidth: "unset",
    width: "auto",
  },
  section: {
    marginTop: tokens.spacingVerticalS,
  },
  checkboxRow: {
    display: "flex",
    gap: tokens.spacingHorizontalL,
    flexWrap: "wrap",
    alignItems: "center",
  },
});

const LOADING_TEXT = "Running...";
const BUTTON_TEXT = "Go";
const SPINNER = <Spinner size="tiny" aria-label={LOADING_TEXT} />;

function ResultBox({
  result,
  successFallback,
  onDismiss,
}: {
  result: CommandResponse;
  successFallback: string;
  onDismiss: () => void;
}) {
  // Four statuses come back from the bridge, not two: success, error, rejected
  // and timeout. Only the first is green; the other three are named in the text
  // so "refused before it ran" is not shown as "failed while running".
  return (
    <StatusMessage status={result.status === "success" ? "success" : "error"} onDismiss={onDismiss}>
      {commandResultMessage(result, successFallback)}
    </StatusMessage>
  );
}

export function PromptActions() {
  const styles = useStyles();
  const [activeTab, setActiveTab] = useState<"create" | "fetch" | "resolve" | "pr" | "new-item">(
    "new-item",
  );
  const { data: env } = useGetEnvQuery();

  // ── Create Prompt state ───────────────────────────────────────────────────
  const [createPrompt] = useCreatePromptMutation();
  const [workItemId, setWorkItemId] = useState("");
  const [assign, setAssign] = useState("force");
  const [creating, setCreating] = useState(false);
  const [createResult, setCreateResult] = useState<CommandResponse | null>(null);

  const createValid = /^\d+$/.test(workItemId);

  const handleCreate = async () => {
    if (!createValid) return;
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

  // ── Fetch PR Comments state ───────────────────────────────────────────────
  const [fetchComments] = useFetchPrCommentsMutation();
  const [prId, setPrId] = useState("");
  const [fetching, setFetching] = useState(false);
  const [fetchResult, setFetchResult] = useState<CommandResponse | null>(null);

  const fetchValid = /^\d+$/.test(prId);

  const handleFetch = async () => {
    if (!fetchValid) return;
    setFetching(true);
    setFetchResult(null);

    try {
      const data = await fetchComments({
        pullRequestId: Number(prId),
      }).unwrap();
      setFetchResult(data);
    } catch {
      setFetchResult({
        command: "GetPRComments",
        status: "error",
        exit_code: -1,
        output: null,
        error: "Network error",
        duration: 0,
      });
    } finally {
      setFetching(false);
    }
  };

  // ── Create PR state ───────────────────────────────────────────────────────
  const [createPR] = useCreatePRMutation();
  const [prWorkItemId, setPrWorkItemId] = useState("");
  const [prTargetBranch, setPrTargetBranch] = useState("");
  const [prDraft, setPrDraft] = useState(true);
  const [prAutoComplete, setPrAutoComplete] = useState(false);
  const [prSkipWorkItem, setPrSkipWorkItem] = useState(false);
  const [creatingPR, setCreatingPR] = useState(false);
  const [createPRResult, setCreatePRResult] = useState<CommandResponse | null>(null);

  const prValid = /^\d+$/.test(prWorkItemId);

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

  // ── Resolve Bug state ─────────────────────────────────────────────────────
  const [resolveBug] = useResolveBugMutation();
  const [resolveBugId, setResolveBugId] = useState("");
  const [resolveComment, setResolveComment] = useState("");
  const [resolveReason, setResolveReason] = useState("Fixed");
  const [resolving, setResolving] = useState(false);
  const [resolveResult, setResolveResult] = useState<CommandResponse | null>(null);

  const resolveValid = /^\d+$/.test(resolveBugId) && resolveComment.trim().length > 0;

  const handleResolve = async () => {
    if (!resolveValid) return;
    setResolving(true);
    setResolveResult(null);

    try {
      const data = await resolveBug({
        workItemId: Number(resolveBugId),
        comment: resolveComment.trim(),
        reason: resolveReason,
      }).unwrap();
      setResolveResult(data);
      if (data.status === "success") {
        setResolveBugId("");
        setResolveComment("");
      }
    } catch {
      setResolveResult({
        command: "CloseItem",
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

  // ── New ADO Item state ───────────────────────────────────────────────────
  const [createAdoItem] = useCreateAdoItemMutation();
  const [niType, setNiType] = useState("UserStory");
  const [niTitle, setNiTitle] = useState("");
  const [niProject, setNiProject] = useState("");
  const [niSprint, setNiSprint] = useState("");
  const [niParent, setNiParent] = useState("");
  const [niDescription, setNiDescription] = useState("");
  const [niAC, setNiAC] = useState("");
  const [niReproSteps, setNiReproSteps] = useState("");
  const [niPriority, setNiPriority] = useState("");
  const [niPoints, setNiPoints] = useState("");
  const [niTags, setNiTags] = useState("");
  const [submittingNi, setSubmittingNi] = useState(false);
  const [niResult, setNiResult] = useState<CommandResponse | null>(null);

  const niValid = niTitle.trim().length > 0;
  const projectList = env?.config?.projects ?? [];

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
        setNiParent("");
        setNiDescription("");
        setNiAC("");
        setNiReproSteps("");
        setNiPriority("");
        setNiPoints("");
        setNiTags("");
      }
    } catch {
      setNiResult({
        command: "NewItem",
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

  const tabs = (
    <div className={styles.tabBar}>
      <FilterBadge
        label="Create from Work Item"
        appearance="pink"
        active={activeTab === "create"}
        onClick={() => setActiveTab("create")}
      />
      <FilterBadge
        label="Fetch PR Comments"
        appearance="pink"
        active={activeTab === "fetch"}
        onClick={() => setActiveTab("fetch")}
      />
      <FilterBadge
        label="Resolve Work Item"
        appearance="pink"
        active={activeTab === "resolve"}
        onClick={() => setActiveTab("resolve")}
      />
      <FilterBadge
        label="Create PR"
        appearance="pink"
        active={activeTab === "pr"}
        onClick={() => setActiveTab("pr")}
      />
      <FilterBadge
        label="New ADO Item"
        appearance="pink"
        active={activeTab === "new-item"}
        onClick={() => setActiveTab("new-item")}
      />
    </div>
  );

  // ── Render ────────────────────────────────────────────────────────────────
  return (
    <PageCard className={styles.card} headerLeft={<Subtitle2>Actions</Subtitle2>}>
      {tabs}

      {/* ── Create from Work Item ─────────────────────────────────────────── */}
      {activeTab === "create" && (
        <div className={styles.section}>
          <div style={{ display: "flex", alignItems: "center", gap: "8px" }}>
            <Caption1>
              <strong>Create from Work Item</strong>
            </Caption1>
            <InfoTip content="Make a card from an ADO work item, with options for who it is assigned to." />
          </div>
          <div className={styles.form}>
            <div className={styles.fieldRow}>
              <div className={styles.field}>
                <Caption1>Work Item ID</Caption1>
                <Input
                  type="text"
                  inputMode="numeric"
                  pattern="[0-9]*"
                  placeholder="e.g. 223061"
                  value={workItemId}
                  onChange={(_e, data) => setWorkItemId(data.value.replace(/\D/g, ""))}
                  onKeyDown={(e) => {
                    if (e.key === "Enter" && createValid && !creating) handleCreate();
                  }}
                  disabled={creating}
                />
              </div>

              <div className={styles.field}>
                <Caption1>Assignment</Caption1>
                <TruncatedDropdown
                  maxToggleLength={15}
                  value={assignOptions.find((o) => o.key === assign)?.label}
                  selectedOptions={[assign]}
                  onOptionSelect={(_e, data) => {
                    if (data.optionValue) setAssign(data.optionValue);
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

              <Button
                appearance="primary"
                disabled={!createValid || creating}
                onClick={handleCreate}
                className={styles.button}
              >
                {creating ? SPINNER : BUTTON_TEXT}
              </Button>
            </div>

            {createResult && (
              <ResultBox
                result={createResult}
                successFallback="✓ Prompt created"
                onDismiss={() => setCreateResult(null)}
              />
            )}
          </div>
        </div>
      )}

      {/* ── Fetch PR Comments ─────────────────────────────────────────────── */}
      {activeTab === "fetch" && (
        <div className={styles.section}>
          <div style={{ display: "flex", alignItems: "center", gap: "8px" }}>
            <Caption1>
              <strong>Fetch PR Comments</strong>
            </Caption1>
            <InfoTip content="Fetches PR threads from ADO, filters noise, appends to matching prompt file." />
          </div>
          <div className={styles.form}>
            <div className={styles.fieldRow}>
              <div className={styles.field} style={{ gridColumn: "1 / 3" }}>
                <Caption1>PR ID</Caption1>
                <Input
                  type="text"
                  inputMode="numeric"
                  pattern="[0-9]*"
                  placeholder="e.g. 140123"
                  value={prId}
                  onChange={(_e, data) => setPrId(data.value.replace(/\D/g, ""))}
                  onKeyDown={(e) => {
                    if (e.key === "Enter" && fetchValid && !fetching) handleFetch();
                  }}
                  disabled={fetching}
                />
              </div>

              <Button
                appearance="primary"
                disabled={!fetchValid || fetching}
                onClick={handleFetch}
                className={styles.button}
              >
                {fetching ? SPINNER : BUTTON_TEXT}
              </Button>
            </div>

            {fetchResult && (
              <ResultBox
                result={fetchResult}
                successFallback="✓ Comments fetched"
                onDismiss={() => setFetchResult(null)}
              />
            )}
          </div>
        </div>
      )}

      {/* ── Create PR ────────────────────────────────────────────────────── */}
      {activeTab === "pr" && (
        <div className={styles.section}>
          <div style={{ display: "flex", alignItems: "center", gap: "8px" }}>
            <Caption1>
              <strong>Create PR</strong>
            </Caption1>
            <InfoTip content="Creates an ADO pull request linked to a work item." />
          </div>
          <div className={styles.form}>
            <div className={styles.fieldRow}>
              <div className={styles.field}>
                <Caption1>Work Item ID</Caption1>
                <Input
                  type="text"
                  inputMode="numeric"
                  pattern="[0-9]*"
                  placeholder="e.g. 223061"
                  value={prWorkItemId}
                  onChange={(_e, data) => setPrWorkItemId(data.value.replace(/\D/g, ""))}
                  onKeyDown={(e) => {
                    if (e.key === "Enter" && prValid && !creatingPR) handleCreatePR();
                  }}
                  disabled={creatingPR}
                />
              </div>

              <div className={styles.field}>
                <Caption1>Target Branch</Caption1>
                <Input
                  type="text"
                  placeholder="main"
                  value={prTargetBranch}
                  onChange={(_e, data) => setPrTargetBranch(data.value)}
                  disabled={creatingPR}
                />
              </div>

              <Button
                appearance="primary"
                disabled={!prValid || creatingPR}
                onClick={handleCreatePR}
                className={styles.button}
              >
                {creatingPR ? SPINNER : BUTTON_TEXT}
              </Button>
            </div>

            <div className={styles.checkboxRow}>
              <Checkbox
                label={<Caption1>Draft</Caption1>}
                checked={prDraft}
                onChange={(_e, data) => setPrDraft(!!data.checked)}
                disabled={creatingPR}
              />
              <Checkbox
                label={<Caption1>Auto Complete</Caption1>}
                checked={prAutoComplete}
                onChange={(_e, data) => setPrAutoComplete(!!data.checked)}
                disabled={creatingPR}
              />
              <Checkbox
                label={<Caption1>Skip Work Item</Caption1>}
                checked={prSkipWorkItem}
                onChange={(_e, data) => setPrSkipWorkItem(!!data.checked)}
                disabled={creatingPR}
              />
            </div>

            {createPRResult && (
              <ResultBox
                result={createPRResult}
                successFallback="✓ PR created"
                onDismiss={() => setCreatePRResult(null)}
              />
            )}
          </div>
        </div>
      )}

      {/* ── Resolve Work Item ─────────────────────────────────────────────── */}
      {activeTab === "resolve" && (
        <div className={styles.section}>
          <div style={{ display: "flex", alignItems: "center", gap: "8px" }}>
            <Caption1>
              <strong>Resolve Work Item</strong>
            </Caption1>
            <InfoTip content="Resolve an ADO work item with a comment and resolution reason." />
          </div>
          <div className={styles.form}>
            <div className={styles.fieldRow}>
              <div className={styles.field}>
                <Caption1>Work Item ID</Caption1>
                <Input
                  type="text"
                  inputMode="numeric"
                  pattern="[0-9]*"
                  placeholder="e.g. 232208"
                  value={resolveBugId}
                  onChange={(_e, data) => setResolveBugId(data.value.replace(/\D/g, ""))}
                  disabled={resolving}
                />
              </div>

              <div className={styles.field}>
                <Caption1>Reason</Caption1>
                <TruncatedDropdown
                  maxToggleLength={15}
                  value={reasonOptions.find((o) => o.key === resolveReason)?.label}
                  selectedOptions={[resolveReason]}
                  onOptionSelect={(_e, data) => {
                    if (data.optionValue) setResolveReason(data.optionValue);
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
            </div>

            <div className={styles.fieldRow}>
              <div className={styles.field} style={{ gridColumn: "1 / 3" }}>
                <Caption1>Comment</Caption1>
                <Textarea
                  placeholder="e.g. Fixed in PR 141234"
                  value={resolveComment}
                  onChange={(_e, data) => setResolveComment(data.value)}
                  disabled={resolving}
                  resize="vertical"
                  rows={3}
                />
              </div>

              <Button
                appearance="primary"
                disabled={!resolveValid || resolving}
                onClick={handleResolve}
                className={styles.button}
                style={{ alignSelf: "end" }}
              >
                {resolving ? SPINNER : BUTTON_TEXT}
              </Button>
            </div>

            {resolveResult && (
              <ResultBox
                result={resolveResult}
                successFallback="✓ Work item resolved"
                onDismiss={() => setResolveResult(null)}
              />
            )}
          </div>
        </div>
      )}
      {/* ── New ADO Item ──────────────────────────────────────────────────── */}
      {activeTab === "new-item" && (
        <div className={styles.section}>
          <div style={{ display: "flex", alignItems: "center", gap: "8px" }}>
            <Caption1>
              <strong>New ADO Item</strong>
            </Caption1>
            <InfoTip content="Create a new ADO work item (User Story, Task, Bug, or Feature) without leaving the browser." />
          </div>
          <div className={styles.form}>
            {/* Type | Title */}
            <div className={styles.fieldRow2}>
              <div className={styles.field}>
                <Caption1>Type</Caption1>
                <TruncatedDropdown
                  maxToggleLength={12}
                  value={adoItemTypeOptions.find((o) => o.key === niType)?.label}
                  selectedOptions={[niType]}
                  onOptionSelect={(_e, d) => {
                    if (d.optionValue) setNiType(d.optionValue);
                  }}
                  disabled={submittingNi}
                >
                  {adoItemTypeOptions.map((o) => (
                    <Option key={o.key} value={o.key}>
                      {o.label}
                    </Option>
                  ))}
                </TruncatedDropdown>
              </div>
              <div className={styles.field}>
                <Caption1>
                  Title <span style={{ color: tokens.colorPaletteRedForeground1 }}>*</span>
                </Caption1>
                <Input
                  placeholder="e.g. Add dark mode toggle"
                  value={niTitle}
                  onChange={(_e, d) => setNiTitle(d.value)}
                  disabled={submittingNi}
                />
              </div>
            </div>

            {/* Project | Sprint | Parent */}
            <div className={styles.fieldRow3}>
              <div className={styles.field}>
                <Caption1>Project</Caption1>
                {projectList.length > 1 ? (
                  <TruncatedDropdown
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
                    placeholder={projectList[0]?.name ?? "project name"}
                    value={niProject}
                    onChange={(_e, d) => setNiProject(d.value)}
                    disabled={submittingNi || projectList.length === 1}
                  />
                )}
              </div>
              <div className={styles.field}>
                <Caption1>Sprint</Caption1>
                <Input
                  placeholder="e.g. Sprint 72"
                  value={niSprint}
                  onChange={(_e, d) => setNiSprint(d.value)}
                  disabled={submittingNi}
                />
              </div>
              <div className={styles.field}>
                <Caption1>Parent ID</Caption1>
                <Input
                  type="text"
                  inputMode="numeric"
                  pattern="[0-9]*"
                  placeholder="e.g. 195551"
                  value={niParent}
                  onChange={(_e, d) => setNiParent(d.value.replace(/\D/g, ""))}
                  disabled={submittingNi}
                />
              </div>
            </div>

            {/* Acceptance Criteria — User Story only */}
            {niType === "UserStory" && (
              <div className={styles.field}>
                <Caption1>Acceptance Criteria</Caption1>
                <Textarea
                  placeholder="- [ ] ..."
                  value={niAC}
                  onChange={(_e, d) => setNiAC(d.value)}
                  disabled={submittingNi}
                  resize="vertical"
                  rows={3}
                />
              </div>
            )}

            {/* Repro Steps — Bug only */}
            {niType === "Bug" && (
              <div className={styles.field}>
                <Caption1>Repro Steps</Caption1>
                <Textarea
                  placeholder="1. Go to ... 2. Click ..."
                  value={niReproSteps}
                  onChange={(_e, d) => setNiReproSteps(d.value)}
                  disabled={submittingNi}
                  resize="vertical"
                  rows={3}
                />
              </div>
            )}

            {/* Description */}
            <div className={styles.field}>
              <Caption1>Description</Caption1>
              <Textarea
                placeholder="Optional context or scope"
                value={niDescription}
                onChange={(_e, d) => setNiDescription(d.value)}
                disabled={submittingNi}
                resize="vertical"
                rows={2}
              />
            </div>

            {/* Priority | Points | Tags | Go */}
            <div className={styles.fieldRow4}>
              <div className={styles.field}>
                <Caption1>Priority</Caption1>
                <TruncatedDropdown
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
              <div className={styles.field}>
                <Caption1>Points</Caption1>
                <Input
                  type="text"
                  inputMode="numeric"
                  pattern="[0-9]*"
                  placeholder="e.g. 3"
                  value={niPoints}
                  onChange={(_e, d) => setNiPoints(d.value.replace(/\D/g, ""))}
                  disabled={submittingNi}
                />
              </div>
              <div className={styles.field}>
                <Caption1>Tags</Caption1>
                <Input
                  placeholder="e.g. ux; a11y"
                  value={niTags}
                  onChange={(_e, d) => setNiTags(d.value)}
                  disabled={submittingNi}
                />
              </div>
              <Button
                appearance="primary"
                disabled={!niValid || submittingNi}
                onClick={handleNewItem}
                className={styles.button}
              >
                {submittingNi ? SPINNER : BUTTON_TEXT}
              </Button>
            </div>

            {niResult && (
              <ResultBox
                result={niResult}
                successFallback="✓ Work item created"
                onDismiss={() => setNiResult(null)}
              />
            )}
          </div>
        </div>
      )}
    </PageCard>
  );
}
