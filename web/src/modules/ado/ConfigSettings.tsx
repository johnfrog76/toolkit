import { useEffect, useMemo, useState, useSyncExternalStore } from "react";
import { createPortal } from "react-dom";
import {
  Badge,
  Body1,
  Button,
  Caption1,
  Input,
  Option,
  Spinner,
  Subtitle2,
  Switch,
  makeStyles,
  tokens,
} from "@fluentui/react-components";
import { HairlineDivider } from "../../shared/HairlineDivider";
import { StatusMessage } from "../../shared/StatusMessage";
import { TruncatedDropdown } from "../../shared/TruncatedDropdown";
import { useGetEnvQuery } from "../../shell/api";
import { reportUnsaved, useSettingsFooter } from "../../shell/settings";
import { wordsFor } from "./configLabels";
import { useGetConfigQuery, useGetConfigSchemaQuery, useWriteConfigMutation } from "./api.ado";
import type { ConfigSchemaRow, ConfigSetting, CommandResponse } from "./api.ado";
import { buildConfigEdit, commandResultMessage, configEditNeedsRestart } from "./cliBridge";
import type { ConfigFieldEdit } from "./cliBridge";
import { SettingsRegular } from "@fluentui/react-icons";
import { EmptyState } from "../../shared/EmptyState";

/**
 * The config wizard's browser half -- and it writes nothing.
 *
 * Every save is `PUT /api/config`, which runs the CLI's `Config` verb through
 * the bridge. So the rules about what may be set, where it lands and what a
 * legal value is live in one place (`Scripts/Get-ConfigSchema.ps1`) and this
 * section only renders them: the tooltips, the allowed values in a select and the
 * boolean toggles all come from `GET /api/config/schema`.
 *
 * Three groups, because three files:
 *
 *   This machine   config.local.json -- gitignored, personal. The source badge
 *                  says whether a value came from the shipped file, the hub,
 *                  this machine or the environment.
 *   The active org the hub's hub.json. An org is the engineer's data and lives
 *                  with their hub, which is the correction to the ADO web
 *                  spec's 8.6 -- it predates hub.json and had the wizard
 *                  patching config.local.json by slug.
 *   Add / archive  the two org ACTIONS. Archiving sets `status: archive`, the
 *                  value the shell already renders as the retrospective view;
 *                  nothing here deletes an org, and the CLI would refuse to.
 *
 * Edits are batched: one Save sends every dirty field in one `PUT`, which is
 * one CLI call, which is one atomic write per file. A refusal comes back as a
 * `CommandResponse` and is rendered by `commandResultMessage`, so rejected,
 * timed out and failed read as what they are.
 *
 * It was once a card on /system and is a SECTION of the settings
 * drawer now, contributed through the registry's `settingsSections` because
 * the drawer is shell chrome and the shell does not import a module. Two
 * things changed with the move, both because a drawer closes and a card never
 * did:
 *
 *   - Save / Discard and the outcome of a save are portalled into the drawer's
 *     pinned foot (shell/settings.ts), so they stay in reach while the rows
 *     scroll -- the split the card got on its last day, kept.
 *   - The drafts live OUTSIDE the component (`draftStore` below). The drawer
 *     unmounts its content when it closes, and a scrim click must never throw
 *     away typing. The count is reported to the shell, which puts a dot on the
 *     avatar: edits a closed drawer is hiding still have to be findable.
 */

// ── Drafts that survive the drawer closing ───────────────────────────────────
// Page-lifetime only, on purpose: a reload is a clean slate, and an unsaved
// config edit is not worth a localStorage key that can go stale against the
// file it would have edited.
const SECTION_ID = "ado.config";
let draftStore: Record<string, string> = {};
const draftListeners = new Set<() => void>();

function setDraftStore(next: Record<string, string>) {
  draftStore = next;
  reportUnsaved(SECTION_ID, Object.keys(next).length);
  draftListeners.forEach((fn) => fn());
}

function useDrafts(): Record<string, string> {
  return useSyncExternalStore(
    (fn) => {
      draftListeners.add(fn);
      return () => draftListeners.delete(fn);
    },
    () => draftStore,
    () => draftStore,
  );
}

const useStyles = makeStyles({
  section: {
    display: "flex",
    flexDirection: "column",
    gap: tokens.spacingVerticalXS,
  },
  hint: {
    color: tokens.colorNeutralForeground3,
    lineHeight: tokens.lineHeightBase300,
  },
  path: {
    color: tokens.colorNeutralForeground4,
    overflowWrap: "anywhere",
  },
  footerActions: {
    display: "flex",
    justifyContent: "flex-end",
    alignItems: "center",
    gap: tokens.spacingHorizontalS,
  },
  group: {
    marginTop: tokens.spacingVerticalM,
  },
  groupLabel: {
    color: tokens.colorNeutralForeground3,
    textTransform: "uppercase" as const,
    letterSpacing: "0.04em",
  },
  // Two lines, not three columns. On the card a row was label | source |
  // control across ~600px; the drawer is 460, and three columns left a path
  // input about 170px wide with the path cut off. So: the name and where the
  // value came from on one line, the control under it at full width.
  row: {
    display: "grid",
    gridTemplateColumns: "minmax(0, 1fr) auto",
    alignItems: "center",
    columnGap: tokens.spacingHorizontalS,
    rowGap: tokens.spacingVerticalXXS,
    paddingTop: tokens.spacingVerticalM,
    paddingBottom: tokens.spacingVerticalS,
  },
  control: {
    gridColumn: "1 / -1",
    display: "flex",
    minWidth: 0,
    "& > *": { flexGrow: 1, minWidth: 0 },
  },
  labelText: {
    fontWeight: tokens.fontWeightSemibold,
    minWidth: 0,
  },
  rowHint: {
    gridColumn: "1 / -1",
    color: tokens.colorNeutralForeground2,
    marginBottom: tokens.spacingVerticalXS,
  },
  keyCaption: {
    gridColumn: "1 / -1",
    fontFamily: tokens.fontFamilyMonospace,
    // 12px: the audit's own floor. 10px is what it found everywhere else.
    fontSize: tokens.fontSizeBase200,
    color: tokens.colorNeutralForeground4,
    overflowWrap: "anywhere" as const,
  },
  actions: {
    display: "flex",
    gap: tokens.spacingHorizontalS,
    alignItems: "center",
    flexWrap: "wrap" as const,
    marginTop: tokens.spacingVerticalM,
  },
  note: {
    color: tokens.colorNeutralForeground3,
    marginTop: tokens.spacingVerticalS,
    display: "block",
  },
  feedback: {
    display: "flex",
    flexDirection: "column",
    gap: tokens.spacingVerticalXS,
  },
});

function sourceColor(source: string): "brand" | "informative" | "subtle" {
  if (source === "local" || source === "env") return "brand";
  if (source === "unset") return "subtle";
  return "informative";
}

/** The schema row for a resolved setting, matching `spaces.<slug>.x` by pattern. */
// The first `features.*` row is the door to Modules; the first `aliases.*` row
// to Shortcuts. Named here, once, and listed for the menu in ./index.tsx.
const RUNS: [prefix: string, anchor: string][] = [
  ["features.", "modules"],
  ["aliases.", "shortcuts"],
];

function runAnchor(keys: string[], key: string): string | undefined {
  for (const [prefix, anchor] of RUNS) {
    if (key.startsWith(prefix) && keys.find((k) => k.startsWith(prefix)) === key) return anchor;
  }
  return undefined;
}

function schemaFor(rows: ConfigSchemaRow[], key: string): ConfigSchemaRow | undefined {
  const exact = rows.find((r) => r.key === key);
  if (exact) return exact;
  const parts = key.split(".");
  if (parts[0] !== "spaces" || parts.length < 3) return undefined;
  const field = parts.slice(2).join(".");
  return rows.find((r) => r.key === `spaces.<slug>.${field}`);
}

interface FieldRowProps {
  setting: ConfigSetting;
  row: ConfigSchemaRow | undefined;
  draft: string | undefined;
  onChange: (value: string) => void;
  /** A named place this row is the start of. */
  anchor?: string;
  /**
   * What is in effect when nobody has set this. Most flags are simply off when
   * unset; one -- `features.ado` -- is DERIVED (on where the Space you are in is active
   * and its address names Azure DevOps), and
   * a switch reading "off" beside Azure DevOps plainly working would be a lie.
   */
  effective?: boolean;
}

function FieldRow({ setting, row, draft, onChange, anchor, effective }: FieldRowProps) {
  const styles = useStyles();
  const value = draft ?? setting.value;
  const type = row?.type ?? "string";
  const words = wordsFor(setting.key, row?.help ?? "");
  // The control is NAMED by the label and DESCRIBED by the sentence under it:
  // 22 of the drawer's 31 inputs used to have no accessible name at all.
  const id = `cfg-${setting.key.replace(/[^A-Za-z0-9]+/g, "-")}`;
  // Every row can be arrived at by its key; the first row of a run is also the
  // door to the run ("modules", "shortcuts").
  const anchors = [setting.key, anchor].filter(Boolean).join(" ");
  const naming = { "aria-labelledby": `${id}-label`, "aria-describedby": `${id}-hint` };

  let control;
  if (type === "bool") {
    // Unset AND derived: show what is in effect, and say whose answer it is.
    const following = value === "" && effective !== undefined;
    const on = following ? effective : value === "true";
    // An inverted row draws "Hide ...": the switch is on when the key is off.
    const shown = words.inverted ? !on : on;
    control = (
      <Switch
        checked={shown}
        onChange={(_e, d) => onChange(d.checked !== Boolean(words.inverted) ? "true" : "false")}
        label={following ? `${shown ? "on" : "off"} -- following this Space` : shown ? "on" : "off"}
        {...naming}
      />
    );
  } else if (type === "enum" && row && row.allowed.length > 0) {
    control = (
      <TruncatedDropdown
        size="small"
        value={value}
        selectedOptions={[value]}
        onOptionSelect={(_e, d) => onChange(String(d.optionValue))}
        {...naming}
      >
        {row.allowed.map((allowed) => (
          <Option key={allowed} value={allowed} text={allowed}>
            {allowed}
          </Option>
        ))}
      </TruncatedDropdown>
    );
  } else {
    control = (
      <Input
        size="small"
        value={value}
        placeholder={
          type === "array" ? "comma separated" : type === "projects" ? "Name/repo; Other/repo2" : ""
        }
        onChange={(_e, d) => onChange(d.value)}
        {...naming}
      />
    );
  }

  return (
    <div className={styles.row} data-settings-anchor={anchors}>
      <Body1 id={`${id}-label`} className={styles.labelText}>
        {words.label}
      </Body1>
      <Badge appearance="outline" color={sourceColor(setting.source)} size="small">
        {setting.source}
      </Badge>
      {/* What it does for you, in sight -- it used to be behind an (i) per row. */}
      <Caption1 id={`${id}-hint`} className={styles.rowHint}>
        {words.hint}
      </Caption1>
      <div className={styles.control}>{control}</div>
      {/* The key, for the terminal: it is what `Config -Set` takes. Shown only
          when the label is NOT already the key. */}
      {words.named ? <Caption1 className={styles.keyCaption}>{setting.key}</Caption1> : null}
    </div>
  );
}

export function ConfigSettings() {
  const styles = useStyles();
  const { data: env } = useGetEnvQuery();
  const { data: config, isLoading, isError } = useGetConfigQuery();
  const { data: schemaData } = useGetConfigSchemaQuery();
  const [writeConfig, { isLoading: isSaving }] = useWriteConfigMutation();

  const drafts = useDrafts();
  const footer = useSettingsFooter();
  const [result, setResult] = useState<CommandResponse | null>(null);
  const [restartNote, setRestartNote] = useState(false);
  const [newSlug, setNewSlug] = useState("");
  const [archiveSlug, setArchiveSlug] = useState("");

  const schema = schemaData?.schema ?? [];
  const settings = useMemo(() => config?.settings ?? [], [config]);

  const machineRows = settings.filter((s) => s.scope === "machine");
  const orgRows = settings.filter((s) => s.scope === "org");
  const orgs = env?.config?.spaces ?? [];
  const dirtyKeys = Object.keys(drafts);

  const setDraft = (key: string, value: string) => setDraftStore({ ...draftStore, [key]: value });

  async function save(edits: ConfigFieldEdit[], extra?: { local?: boolean; hub?: boolean }) {
    const payload = buildConfigEdit(edits);
    setRestartNote(configEditNeedsRestart(payload));
    const reply = await writeConfig({ ...payload, ...extra }).unwrap();
    setResult(reply.result);
    if (reply.result.status === "success") setDraftStore({});
    return reply;
  }

  function saveDirty() {
    const edits: ConfigFieldEdit[] = dirtyKeys.map((key) => ({
      key,
      type: schemaFor(schema, key)?.type ?? "string",
      value: drafts[key],
    }));
    void save(edits);
  }

  function addOrg() {
    const slug = newSlug.trim().toLowerCase();
    if (!slug) return;
    // One field is enough: the CLI fills in the two an org must carry -- slug
    // and promptsFolder -- and starts it `local`, so nothing contacts ADO until
    // someone gives it a URL and says so.
    void save([{ key: `spaces.${slug}.name`, type: "string", value: slug }]).then(() =>
      setNewSlug(""),
    );
  }

  function archiveOrg() {
    if (!archiveSlug) return;
    void save([{ key: `spaces.${archiveSlug}.status`, type: "enum", value: "archive" }]);
  }

  const hasReadError = isError || Boolean(config?.error);

  // The result of a save belongs to the visit it happened in. Clearing it on
  // unmount means a reopened drawer does not greet you with yesterday's "Saved."
  useEffect(() => () => setResult(null), []);

  const footerContent =
    hasReadError || (dirtyKeys.length === 0 && !result && !restartNote) ? null : (
      <>
        {result ? (
          <StatusMessage
            status={result.status === "success" ? "success" : "error"}
            onDismiss={() => setResult(null)}
          >
            {commandResultMessage(result, "Saved.")}
          </StatusMessage>
        ) : null}
        {restartNote ? (
          <Caption1 className={styles.note}>
            Agent port and Allowed page addresses are read once, when the agent starts -- restart it
            for these to take effect.
          </Caption1>
        ) : null}
        {dirtyKeys.length > 0 ? (
          <div className={styles.footerActions}>
            <Button appearance="subtle" onClick={() => setDraftStore({})}>
              Discard
            </Button>
            <Button appearance="primary" onClick={saveDirty} disabled={isSaving}>
              {isSaving ? <Spinner size="tiny" /> : `Save ${dirtyKeys.length}`}
            </Button>
          </div>
        ) : null}
      </>
    );

  return (
    <section className={styles.section} aria-labelledby="settings-config-heading">
      <Subtitle2 id="settings-config-heading">Configuration</Subtitle2>
      <Body1 className={styles.hint}>
        What this machine and the Space you are working in are set to. Changes wait for Save, and
        need no restart: the agent re-reads config on every request.
      </Body1>
      {config?.files?.local ? (
        <Caption1 className={styles.path}>{config.files.local}</Caption1>
      ) : null}

      {footer && footerContent ? createPortal(footerContent, footer) : null}

      {isLoading ? (
        <Spinner size="tiny" label="Reading the settings files..." labelPosition="after" />
      ) : hasReadError ? (
        <EmptyState
          icon={<SettingsRegular />}
          tone="error"
          title="Could not read the settings files"
          detail={config?.error ?? "The agent did not answer. Nothing was read."}
        />
      ) : (
        <>
          <div className={styles.group}>
            <Caption1 className={styles.groupLabel}>This machine</Caption1>
            {machineRows.map((setting) => (
              <FieldRow
                key={setting.key}
                setting={setting}
                row={schemaFor(schema, setting.key)}
                draft={drafts[setting.key]}
                onChange={(value) => setDraft(setting.key, value)}
                effective={setting.key === "features.ado" ? env?.ado?.enabled : undefined}
                anchor={runAnchor(
                  machineRows.map((r) => r.key),
                  setting.key,
                )}
              />
            ))}
          </div>

          {orgRows.length > 0 ? (
            <>
              <HairlineDivider />
              <div className={styles.group} data-settings-anchor="organisation">
                <Caption1 className={styles.groupLabel}>
                  Active Space{config?.activeSpace ? ` -- ${config.activeSpace}` : ""} (written to
                  the hub)
                </Caption1>
                {orgRows.map((setting) => (
                  <FieldRow
                    key={setting.key}
                    setting={setting}
                    row={schemaFor(schema, setting.key)}
                    draft={drafts[setting.key]}
                    onChange={(value) => setDraft(setting.key, value)}
                  />
                ))}
              </div>
            </>
          ) : null}

          <HairlineDivider />
          <div className={styles.actions}>
            <Input
              size="small"
              value={newSlug}
              placeholder="short name for a new Space"
              aria-label="Short name for a new Space"
              onChange={(_e, d) => setNewSlug(d.value)}
            />
            <Button size="small" onClick={addOrg} disabled={isSaving || !newSlug.trim()}>
              Add Space
            </Button>
            <TruncatedDropdown
              size="small"
              value={archiveSlug}
              placeholder="Space to archive"
              aria-label="Space to archive"
              selectedOptions={archiveSlug ? [archiveSlug] : []}
              onOptionSelect={(_e, d) => setArchiveSlug(String(d.optionValue))}
            >
              {orgs.map((o) => (
                <Option key={o.slug} value={o.slug} text={o.slug}>
                  {o.name}
                </Option>
              ))}
            </TruncatedDropdown>
            <Button size="small" onClick={archiveOrg} disabled={isSaving || !archiveSlug}>
              Archive Space
            </Button>
          </div>
        </>
      )}
    </section>
  );
}
