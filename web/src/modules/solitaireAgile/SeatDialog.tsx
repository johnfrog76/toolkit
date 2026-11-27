import {
  Body1,
  Button,
  Dialog,
  DialogActions,
  DialogBody,
  DialogContent,
  DialogSurface,
  DialogTitle,
  Dropdown,
  Field,
  Input,
  MessageBar,
  MessageBarBody,
  Option,
  Radio,
  RadioGroup,
  makeStyles,
  tokens,
  useId,
} from "@fluentui/react-components";
import { useEffect, useRef, useState } from "react";
import { DialogDismiss } from "../../shared/DialogDismiss";
import { buildStaffSeatParams } from "../ado/cliBridge";
import type { StaffSeatFields } from "../ado/cliBridge";
import type { CommandResponse } from "../ado/api.ado";
import type { OrgPosition, OrgSeat } from "./api.solitaireAgile";
import { refusalText } from "./UseOrgDialog";
import {
  ASSIGN_WORD,
  CHANGE_WORD,
  isChangedSince,
  isOwnerPosition,
  isTeamLead,
  plateTitle,
  HELD_MODEL,
  hasOwnTitle,
  isHeldModel,
  seatChoices,
  seatModelDefault,
} from "./orgChart";

// The seat dialog (docs/modules/solitaire-agile.md, "The web UI"): Assign on a
// vacant seat's plate, Change on a staffed one's, on a saved org only. The
// fewest questions, each already answered: the model (the seat's own, or its
// position's default), the session's name, the role title, and for a team
// lead the Space it serves. The owner's seat asks for the name alone. Save is
// the one write: Staff -Seat through the bridge (POST /api/cmd/Staff), with
// the chart's etag as -IfMatch, so a file changed since the page read it is
// refused and the dialog offers a reload instead of writing over it. Only what
// changed is sent; a Save that changes nothing closes with nothing written.

const useStyles = makeStyles({
  surface: { maxWidth: "480px" },
  content: { display: "flex", flexDirection: "column", rowGap: tokens.spacingVerticalM },
  note: { color: tokens.colorNeutralForeground2 },
  titleRow: { display: "flex" },
  // The choices wrap as a row, each name kept whole on one line, never its version under its word.
  models: { flexWrap: "wrap" },
  choice: { whiteSpace: "nowrap" },
  // A link to look at, a real button underneath: no padding to push it off the fields' edge.
  titleLink: {
    minWidth: "auto",
    paddingLeft: 0,
    paddingRight: 0,
    // The neutral ink, underlined: the theme's link teal is under 4.5:1 at this size.
    color: tokens.colorNeutralForeground2,
    textDecorationLine: "underline",
    ":hover": { color: tokens.colorNeutralForeground1 },
  },

  refusal: { color: tokens.colorNeutralForeground1, whiteSpace: "pre-wrap" },
  conflict: {
    display: "flex",
    alignItems: "center",
    columnGap: tokens.spacingHorizontalM,
    flexWrap: "wrap",
  },
});

/** What the dialog says when Staff refused because org.json changed since it was read. */
export const CHANGED_SINCE_TEXT = "The org changed since you opened it. Reload to see it.";
/** The value the Space question holds for a seat that serves no Space. */
export const NO_SPACE = "";
export const NO_SPACE_LABEL = "None";

/** The note on a seat of a position with several: the role is the position's. */
export function sharedRoleNote(position: OrgPosition): string | null {
  const n = position.seats.length;
  return n > 1
    ? `${position.title} has ${n} seats: its role name and title change for all of them.`
    : null;
}

/** The control that opens the role title's field in place. */
export const OTHER_TITLE = "Use a different title";

/** What Save sends: the seat, and each answer that differs from what the file says now. */
export function seatChanges(
  position: OrgPosition,
  seat: OrgSeat,
  answers: { model: string; person: string; session: string; space: string; roleTitle: string },
  familyNames: Record<string, string> = {},
): Omit<StaffSeatFields, "tree" | "ifMatch"> | null {
  const out: Omit<StaffSeatFields, "tree" | "ifMatch"> = { position: position.id, seat: seat.id };
  let changed = false;
  const set = (key: "model" | "person" | "session" | "space" | "roleTitle", value: string) => {
    out[key] = value;
    changed = true;
  };
  if (isOwnerPosition(position)) {
    if (answers.person.trim() !== (seat.person ?? "")) set("person", answers.person.trim());
    return changed ? out : null;
  }
  // A held model kept sends no -Model; its family's current model, picked over it, is a change.
  if (
    answers.model &&
    answers.model !== HELD_MODEL &&
    (answers.model !== seat.modelFamily || isHeldModel(seat, familyNames))
  )
    set("model", answers.model);
  if (answers.session.trim() !== (seat.session ?? "")) set("session", answers.session.trim());
  if (isTeamLead(position) && answers.space !== (seat.space ?? NO_SPACE))
    set("space", answers.space);
  const title = answers.roleTitle.trim();
  if (title && title !== position.title) set("roleTitle", title);
  return changed ? out : null;
}

export function SeatDialog({
  position,
  seat,
  treeId,
  etag,
  families,
  familyNames = {},
  spaces,
  run,
  busy = false,
  onSaved,
  onReload,
  onClose,
}: {
  position: OrgPosition;
  seat: OrgSeat;
  /** The saved tree the seat is in: active or a draft. */
  treeId: string;
  /** The etag the chart was read with: Staff -Seat's -IfMatch. */
  etag?: string;
  /** Every family the model map's current block names, as the agent serves it. */
  families: string[];
  /** Each family by its current model's name, as the agent serves it (familyNames). */
  familyNames?: Record<string, string>;
  /** The Spaces a team lead's seat may serve, as /env lists them. */
  spaces: Array<{ slug: string; name?: string }>;
  /** Runs Staff through the bridge; resolves to its answer, rejects when the agent is away. */
  run: (params: string[]) => Promise<CommandResponse>;
  /** A Staff write is in flight on the page: Save waits for it, one write at a time. */
  busy?: boolean;
  onSaved: () => void;
  /** Read the org again, after a conflict. */
  onReload: () => void;
  onClose: () => void;
}) {
  const styles = useStyles();
  const owner = isOwnerPosition(position);
  const lead = isTeamLead(position);
  const start = seatModelDefault(position, seat, familyNames);
  const [model, setModel] = useState(start);
  const [person, setPerson] = useState(seat.person ?? "");
  const [session, setSession] = useState(seat.session ?? "");
  const [space, setSpace] = useState(seat.space ?? NO_SPACE);
  const [roleTitle, setRoleTitle] = useState(position.title);
  // The role title waits behind a link, open from the start where the position's
  // title already differs from its role's; opened, its field takes the focus.
  const [titleOpen, setTitleOpen] = useState(hasOwnTitle(position));
  const titleField = useRef<HTMLInputElement>(null);
  const titleId = useId("org-seat-title");
  const [focusTitle, setFocusTitle] = useState(false);
  useEffect(() => {
    if (focusTitle && titleOpen) {
      titleField.current?.focus();
      setFocusTitle(false);
    }
  }, [focusTitle, titleOpen]);
  const toggleTitle = () => {
    if (titleOpen) setRoleTitle(position.title);
    else setFocusTitle(true);
    setTitleOpen(!titleOpen);
  };
  const [saving, setSaving] = useState(false);
  // While this save, or any other Staff write of the page's, is in flight,
  // nothing leaves or saves: Cancel, Escape and Close wait.
  const locked = saving || busy;
  const [refusal, setRefusal] = useState<string | null>(null);
  const [conflict, setConflict] = useState(false);
  const [away, setAway] = useState(false);

  const title = plateTitle(position, seat);
  const verb = seat.state === "vacant" ? ASSIGN_WORD : CHANGE_WORD;
  const choices = seatChoices(position, seat, families, familyNames);
  const note = sharedRoleNote(position);
  const spaceName = (slug: string) =>
    slug === NO_SPACE ? NO_SPACE_LABEL : (spaces.find((s) => s.slug === slug)?.name ?? slug);
  // A seat may serve a Space /env does not offer (a dismissed demo): it stays a choice.
  const spaceSlugs = [
    ...spaces.map((s) => s.slug),
    ...(seat.space && !spaces.some((s) => s.slug === seat.space) ? [seat.space] : []),
  ];

  const save = async () => {
    if (locked) return;
    const changes = seatChanges(
      position,
      seat,
      { model, person, session, space, roleTitle: titleOpen ? roleTitle : position.title },
      familyNames,
    );
    if (!changes) {
      onClose();
      return;
    }
    setSaving(true);
    setRefusal(null);
    setConflict(false);
    setAway(false);
    try {
      const result = await run(buildStaffSeatParams({ ...changes, tree: treeId, ifMatch: etag }));
      if (result.status === "success") onSaved();
      else if (isChangedSince(result.error) || isChangedSince(result.output)) setConflict(true);
      else setRefusal(refusalText(result));
    } catch {
      setAway(true);
    } finally {
      setSaving(false);
    }
  };

  return (
    <Dialog open onOpenChange={(_e, d) => !d.open && !locked && onClose()}>
      <DialogSurface className={styles.surface} data-testid="org-seat-dialog">
        <DialogBody>
          <DialogTitle action={<DialogDismiss disabled={locked} />}>
            {verb} {title}
          </DialogTitle>
          <DialogContent className={styles.content}>
            {owner ? (
              <Field label="Name">
                <Input
                  value={person}
                  onChange={(_, d) => setPerson(d.value)}
                  data-testid="org-seat-person"
                />
              </Field>
            ) : (
              <>
                <Field label="Model">
                  <RadioGroup
                    name="org-seat-model"
                    value={model}
                    onChange={(_, d) => setModel(d.value)}
                    layout="horizontal"
                    className={styles.models}
                    data-testid="org-seat-model"
                  >
                    {choices.map((c) => (
                      <Radio
                        key={c.value}
                        value={c.value}
                        label={{ children: c.label, className: styles.choice }}
                      />
                    ))}
                  </RadioGroup>
                </Field>
                <Field label="Session name">
                  <Input
                    value={session}
                    onChange={(_, d) => setSession(d.value)}
                    data-testid="org-seat-session"
                  />
                </Field>
                {lead ? (
                  <Field label="Space">
                    <Dropdown
                      value={spaceName(space)}
                      selectedOptions={[space]}
                      onOptionSelect={(_, d) => setSpace(d.optionValue ?? NO_SPACE)}
                      data-testid="org-seat-space"
                    >
                      <Option value={NO_SPACE}>{NO_SPACE_LABEL}</Option>
                      {spaceSlugs.map((slug) => (
                        <Option key={slug} value={slug}>
                          {spaceName(slug)}
                        </Option>
                      ))}
                    </Dropdown>
                  </Field>
                ) : null}
                <div className={styles.titleRow}>
                  <Button
                    appearance="transparent"
                    size="small"
                    className={styles.titleLink}
                    aria-expanded={titleOpen}
                    aria-controls={titleId}
                    onClick={toggleTitle}
                    data-testid="org-seat-title-toggle"
                  >
                    {OTHER_TITLE}
                  </Button>
                </div>
                {titleOpen ? (
                  <>
                    <Field label="Role title">
                      <Input
                        id={titleId}
                        ref={titleField}
                        value={roleTitle}
                        onChange={(_, d) => setRoleTitle(d.value)}
                        data-testid="org-seat-role-title"
                      />
                    </Field>
                    {note ? (
                      <Body1 className={styles.note} data-testid="org-seat-shared">
                        {note}
                      </Body1>
                    ) : null}
                  </>
                ) : null}
              </>
            )}
            {/* The status region stays mounted, its text swapped in. */}
            <div role="status" data-testid="org-seat-refusal-region">
              {conflict ? (
                <div className={styles.conflict} data-testid="org-seat-conflict">
                  <Body1 className={styles.refusal}>{CHANGED_SINCE_TEXT}</Body1>
                  <Button size="small" onClick={onReload} data-testid="org-seat-reload">
                    Reload
                  </Button>
                </div>
              ) : refusal ? (
                <Body1 className={styles.refusal} data-testid="org-seat-refusal">
                  {refusal}
                </Body1>
              ) : null}
            </div>
            {away ? (
              <MessageBar intent="error" data-testid="org-seat-away">
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
              disabled={locked || conflict}
              data-testid="org-seat-save"
            >
              {saving ? "Saving..." : "Save"}
            </Button>
          </DialogActions>
        </DialogBody>
      </DialogSurface>
    </Dialog>
  );
}
