import {
  Body1,
  Button,
  Dialog,
  DialogActions,
  DialogBody,
  DialogContent,
  DialogSurface,
  DialogTitle,
  Field,
  Input,
  MessageBar,
  MessageBarBody,
  Radio,
  RadioGroup,
  makeStyles,
  tokens,
} from "@fluentui/react-components";
import { useState } from "react";
import { DialogDismiss } from "../../shared/DialogDismiss";
import { ORG } from "../../shell/consts";
import { buildStaffPresetParams } from "../ado/cliBridge";
import type { CommandResponse } from "../ado/api.ado";
import type { OrgPreset } from "./api.solitaireAgile";
import { NOT_RECOMMENDED, familyLabel } from "./orgChart";

// "Use this org" (docs/modules/solitaire-agile.md, "The web UI"): the steps that
// save a preset as a tree of the hub's org.json. Three questions, each already
// answered with its default -- who you are, the VP of engineering's model, the
// VP of product's model -- so any can be skipped, none comes before another,
// and Cancel leaves with nothing written. Save is the one write: Staff -Preset
// through the bridge (POST /api/cmd/Staff), which saves a draft.
//
// A Dialog, not a wizard: every question is in view at once, so there is no
// order to follow and no step to be held at, which is what "follow, skip or
// leave" asks for; a wizard's Next would impose the order the design leaves
// open. The questions, their choices and their defaults are consts.json
// org.steps, which Staff fills with too, so the page and the verb agree.

const useStyles = makeStyles({
  surface: { maxWidth: "480px" },
  content: { display: "flex", flexDirection: "column", rowGap: tokens.spacingVerticalM },
  lead: { color: tokens.colorNeutralForeground2 },
  refusal: { color: tokens.colorNeutralForeground1, whiteSpace: "pre-wrap" },
});

// A family's word and the "not recommended" note are the org's rules (orgChart.ts).
export { familyLabel, NOT_RECOMMENDED } from "./orgChart";

export function familyChoice(family: string): string {
  return ORG.steps.recommended.includes(family)
    ? familyLabel(family)
    : `${familyLabel(family)} (${NOT_RECOMMENDED})`;
}

/** What Save says it will do: a first org is the one in use; any other, a draft. */
export function saveNote(activeTitle: string | null): string {
  return activeTitle
    ? `It is saved as a draft: your active org stays ${activeTitle}.`
    : "It is your first org, so it is the one in use.";
}

/** The verb's own sentence for a refusal, else what the bridge said. */
export function refusalText(result: CommandResponse): string {
  return (result.error || result.output || "The org was not saved.").trim();
}

function ModelQuestion({
  label,
  value,
  onChange,
  name,
}: {
  label: string;
  value: string;
  onChange: (v: string) => void;
  name: string;
}) {
  return (
    <Field label={label}>
      <RadioGroup
        name={name}
        value={value}
        onChange={(_, d) => onChange(d.value)}
        layout="horizontal"
        data-testid={`org-step-${name}`}
      >
        {ORG.steps.families.map((f) => (
          <Radio key={f} value={f} label={familyChoice(f)} />
        ))}
      </RadioGroup>
    </Field>
  );
}

export function UseOrgDialog({
  preset,
  activeTitle,
  run,
  busy = false,
  onSaved,
  onClose,
}: {
  preset: OrgPreset;
  /** The active org's title, or null with no org saved yet. */
  activeTitle: string | null;
  /** Runs Staff through the bridge; resolves to its answer, rejects when the agent is away. */
  run: (params: string[]) => Promise<CommandResponse>;
  /** A Staff write is in flight on the page (an Active pick): Save waits for it.
   *  Staff takes no lock, so the page runs one write at a time. */
  busy?: boolean;
  onSaved: () => void;
  onClose: () => void;
}) {
  const styles = useStyles();
  const [owner, setOwner] = useState(ORG.steps.owner);
  const [vpEngineering, setVpEngineering] = useState(ORG.steps.vpEngineering);
  const [vpProduct, setVpProduct] = useState(ORG.steps.vpProduct);
  const [saving, setSaving] = useState(false);
  // While this save, or any other Staff write of the page's, is in flight,
  // nothing leaves or saves: Cancel, Escape and Close wait, so "Cancel leaves
  // with nothing written" stays true.
  const locked = saving || busy;
  const [refusal, setRefusal] = useState<string | null>(null);
  const [away, setAway] = useState(false);

  const save = async () => {
    if (locked) return;
    setSaving(true);
    setRefusal(null);
    setAway(false);
    try {
      const result = await run(
        buildStaffPresetParams({ size: preset.size, owner, vpEngineering, vpProduct }),
      );
      if (result.status === "success") onSaved();
      else setRefusal(refusalText(result));
    } catch {
      setAway(true);
    } finally {
      setSaving(false);
    }
  };

  return (
    <Dialog open onOpenChange={(_e, d) => !d.open && !locked && onClose()}>
      <DialogSurface className={styles.surface} data-testid="org-use-dialog">
        <DialogBody>
          <DialogTitle action={<DialogDismiss disabled={locked} />}>Use {preset.title}</DialogTitle>
          <DialogContent className={styles.content}>
            <Body1 className={styles.lead}>
              Every answer is filled in: change any of them, or save as it is.{" "}
              {saveNote(activeTitle)}
            </Body1>
            <Field label="Who you are">
              <Input
                value={owner}
                onChange={(_, d) => setOwner(d.value)}
                data-testid="org-step-owner"
              />
            </Field>
            <ModelQuestion
              label="The VP of engineering's model"
              name="vp-engineering"
              value={vpEngineering}
              onChange={setVpEngineering}
            />
            <ModelQuestion
              label="The VP of product's model"
              name="vp-product"
              value={vpProduct}
              onChange={setVpProduct}
            />
            {/* The refusal's status region stays mounted, its text swapped in. */}
            <div role="status" data-testid="org-use-refusal-region">
              {refusal ? (
                <Body1 className={styles.refusal} data-testid="org-use-refusal">
                  {refusal}
                </Body1>
              ) : null}
            </div>
            {away ? (
              <MessageBar intent="error" data-testid="org-use-away">
                <MessageBarBody>Could not reach the agent. Nothing was saved.</MessageBarBody>
              </MessageBar>
            ) : null}
          </DialogContent>
          <DialogActions>
            <Button onClick={onClose} disabled={locked}>
              Cancel
            </Button>
            <Button
              appearance="primary"
              onClick={save}
              disabled={locked}
              data-testid="org-use-save"
            >
              {saving ? "Saving..." : "Save"}
            </Button>
          </DialogActions>
        </DialogBody>
      </DialogSurface>
    </Dialog>
  );
}
